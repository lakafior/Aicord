//
//  MessageList.swift
//  Aicord
//
//  The chat's messages on iOS, in a collection view. The rows are still the
//  SwiftUI message cells.
//

#if os(iOS)
  import AicordKit
  import SwiftUI
  import UIKit

  /// Lets `ChatView` move the list: to the newest messages or to one message.
  @MainActor
  final class MessageListController {
    fileprivate weak var coordinator: MessageList.Coordinator?

    func scrollToBottom(animated: Bool) {
      coordinator?.scrollToBottom(animated: animated)
    }

    func scroll(to id: MessageSnowflake) {
      coordinator?.scroll(to: id)
    }
  }

  /// The list is upside down: the collection view is flipped, and each cell is
  /// flipped back. The newest message is the first item and sits at the bottom,
  /// so the list opens there and stays there as messages arrive, and older
  /// history is added at the far end, where it can't move what's on screen
  /// however wrong the height estimates for unseen rows are.
  struct MessageList: UIViewRepresentable {
    let vm: ChannelStore
    let rows: [MessageRow]
    let pending: OrderedDictionary<MessageSnowflake, Payloads.CreateMessage>
    let showsEdge: Bool
    let controller: MessageListController
    /// Within three screens of the oldest loaded message.
    var onNearTop: (Bool) -> Void
    /// More than a screen away from the newest message.
    var onAwayFromLatest: (Bool) -> Void
    var onUserScroll: () -> Void

    enum Item: Hashable {
      case pending(MessageSnowflake)
      case message(MessageSnowflake)
      case edge
    }

    enum Content {
      case message(DiscordChannel.Message, prior: DiscordChannel.Message?)
      case pending(
        Payloads.CreateMessage, priorSent: DiscordChannel.Message?,
        priorQueued: Payloads.CreateMessage?)
      case edge
    }

    static let flip = CGAffineTransform(scaleX: 1, y: -1)

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICollectionView {
      let item = NSCollectionLayoutItem(
        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(64)))
      let group = NSCollectionLayoutGroup.vertical(
        layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(64)),
        subitems: [item])
      let layout = UICollectionViewCompositionalLayout(section: .init(group: group))

      let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
      view.transform = Self.flip
      view.backgroundColor = .clear
      // rows show through under the navigation bar and the message field
      view.clipsToBounds = false
      view.contentInsetAdjustmentBehavior = .never
      view.keyboardDismissMode = .interactive
      view.alwaysBounceVertical = true
      // a tap on the status bar would go to the newest message, not the oldest
      view.scrollsToTop = false
      view.allowsSelection = false
      view.delegate = context.coordinator

      context.coordinator.attach(to: view, environment: context.environment)
      controller.coordinator = context.coordinator
      context.coordinator.apply()
      return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
      let coordinator = context.coordinator
      coordinator.parent = self
      controller.coordinator = coordinator
      coordinator.environment.update(context.environment, channel: vm)
      coordinator.apply()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDelegate {
      var parent: MessageList
      private(set) var environment = RowEnvironment()
      private weak var view: UICollectionView?
      private var dataSource: UICollectionViewDiffableDataSource<Int, Item>?
      private var items: [Item] = []
      private var content: [Item: Content] = [:]
      /// Every cell made so far, to hand new data to the ones in use.
      private let cells = NSHashTable<RowCell>.weakObjects()
      private var pendingScroll: MessageSnowflake?
      private var nearTop: Bool?
      private var awayFromLatest: Bool?

      init(parent: MessageList) {
        self.parent = parent
      }

      func attach(to view: UICollectionView, environment values: EnvironmentValues) {
        self.view = view
        environment.update(values, channel: parent.vm)
        let registration = UICollectionView.CellRegistration<RowCell, Item> {
          [weak self] cell, _, item in
          self?.configure(cell, item)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: view) {
          view, indexPath, item in
          view.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
        }
      }

      private func configure(_ cell: RowCell, _ item: Item) {
        guard let content = content[item] else { return }
        cells.add(cell)
        let model = RowModel(item: item, content: content)
        cell.model = model
        cell.contentConfiguration = UIHostingConfiguration {
          RowView(model: model, vm: parent.vm, environment: environment)
            // a reused cell starts the next message with fresh view state
            .id(item)
        }
        .margins(.all, 0)
        cell.contentView.transform = MessageList.flip
        cell.backgroundConfiguration = .clear()
      }

      /// Brings the list in line with the messages `parent` holds now.
      func apply() {
        guard let view, let dataSource else { return }

        // newest first: the list is upside down
        var newItems: [Item] = []
        var newContent: [Item: Content] = [:]
        newItems.reserveCapacity(parent.rows.count + parent.pending.count + 1)
        let pending = parent.pending
        let lastSent = parent.rows.last?.message
        for index in pending.keys.indices.reversed() {
          let key = pending.keys[index]
          guard let message = pending[key] else { continue }
          let item = Item.pending(key)
          newItems.append(item)
          newContent[item] = .pending(
            message,
            priorSent: index == 0 ? lastSent : nil,
            priorQueued: index > 0 ? pending[pending.keys[index - 1]] : nil)
        }
        for row in parent.rows.reversed() {
          let item = Item.message(row.id)
          newItems.append(item)
          newContent[item] = .message(row.message, prior: row.prior)
        }
        if parent.showsEdge {
          newItems.append(.edge)
          newContent[.edge] = .edge
        }
        content = newContent

        if newItems != items {
          let anchor = scrollAnchor(in: view, keeping: newItems)
          items = newItems
          var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
          snapshot.appendSections([0])
          snapshot.appendItems(newItems)
          UIView.performWithoutAnimation {
            dataSource.apply(snapshot, animatingDifferences: false)
            if let anchor {
              view.layoutIfNeeded()
              restore(anchor, in: view)
            }
          }
        }

        // cells in use, on screen or prepared ahead, get the current message
        for cell in cells.allObjects {
          guard let model = cell.model, let content = newContent[model.item] else { continue }
          model.content = content
        }

        if let id = pendingScroll, newContent[.message(id)] != nil {
          pendingScroll = nil
          scroll(to: id)
        }
        reportPosition(of: view)
      }

      // MARK: Keeping what's on screen in place

      private struct Anchor {
        let item: Item
        /// The row's top edge below the top of the visible area.
        let distance: CGFloat
      }

      /// A row on screen that stays in the list, to put back where it was after
      /// rows are added or removed on the newer side of it. Nothing at the
      /// newest message: the list stays there by itself.
      private func scrollAnchor(in view: UICollectionView, keeping newItems: [Item]) -> Anchor? {
        guard view.contentOffset.y > 1 else { return nil }
        let staying = Set(newItems)
        for indexPath in view.indexPathsForVisibleItems.sorted() {
          guard let item = dataSource?.itemIdentifier(for: indexPath), staying.contains(item),
            let frame = view.layoutAttributesForItem(at: indexPath)?.frame
          else { continue }
          return Anchor(item: item, distance: frame.minY - view.contentOffset.y)
        }
        return nil
      }

      private func restore(_ anchor: Anchor, in view: UICollectionView) {
        guard let indexPath = dataSource?.indexPath(for: anchor.item),
          let frame = view.layoutAttributesForItem(at: indexPath)?.frame
        else { return }
        let furthest = max(0, view.contentSize.height - view.bounds.height)
        let offset = min(max(0, frame.minY - anchor.distance), furthest)
        if abs(offset - view.contentOffset.y) > 0.5 {
          view.contentOffset.y = offset
        }
      }

      // MARK: Scrolling

      func scrollToBottom(animated: Bool) {
        guard let view else { return }
        view.setContentOffset(.zero, animated: animated)
      }

      func scroll(to id: MessageSnowflake) {
        guard let view, let indexPath = dataSource?.indexPath(for: .message(id)) else {
          // not in the list yet: once its page is in
          pendingScroll = id
          return
        }
        // the content's top is the bottom of the screen. Twice: the first pass
        // lands by estimated heights, the second by the measured ones.
        view.scrollToItem(at: indexPath, at: .top, animated: false)
        view.layoutIfNeeded()
        view.scrollToItem(at: indexPath, at: .top, animated: false)
      }

      func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        parent.onUserScroll()
      }

      func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportPosition(of: scrollView)
      }

      private func reportPosition(of view: UIScrollView) {
        let height = view.bounds.height
        guard height > 0 else { return }
        let fromNewest = view.contentOffset.y
        let fromOldest = view.contentSize.height - fromNewest - height
        let isNearTop = view.contentSize.height > height && fromOldest < height * 3
        let isAway = fromNewest > height

        // after the current update: these set view state, and a layout pass
        // during a SwiftUI update can get here
        if isNearTop != nearTop {
          nearTop = isNearTop
          DispatchQueue.main.async { [weak self] in self?.parent.onNearTop(isNearTop) }
        }
        if isAway != awayFromLatest {
          awayFromLatest = isAway
          DispatchQueue.main.async { [weak self] in self?.parent.onAwayFromLatest(isAway) }
        }
      }
    }
  }

  // MARK: - Rows

  private final class RowCell: UICollectionViewCell {
    var model: RowModel?
  }

  /// What a cell shows. The cell's view reads it, so a message that changes
  /// updates its row without the cell being made again.
  @MainActor @Observable
  private final class RowModel {
    let item: MessageList.Item
    var content: MessageList.Content

    init(item: MessageList.Item, content: MessageList.Content) {
      self.item = item
      self.content = content
    }
  }

  /// The chat's SwiftUI environment, for the rows. A cell's view is its own
  /// SwiftUI hierarchy and inherits nothing from the chat around the list.
  @MainActor @Observable
  final class RowEnvironment {
    private(set) var values = EnvironmentValues()
    @ObservationIgnored private var signature: Signature?
    /// Set when a preference is saved: the accent colour and the font design
    /// reach the rows through the environment but can't be read back from it.
    @ObservationIgnored private var preferencesChanged = false
    @ObservationIgnored private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    init() {
      observer = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.preferencesChanged = true }
      }
    }

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private struct Signature: Equatable {
      var channel: ObjectIdentifier
      var theme: String
      var colorScheme: ColorScheme
      var contrast: ColorSchemeContrast
      var typeSize: DynamicTypeSize
      var sizeClass: UserInterfaceSizeClass?
      var layoutDirection: LayoutDirection
      var locale: Locale
      var reducesMotion: Bool
      var scenePhase: ScenePhase
    }

    /// Rows only re-render when something they can show differently changed;
    /// the environment itself can't be compared.
    func update(_ new: EnvironmentValues, channel: ChannelStore) {
      let signature = Signature(
        channel: ObjectIdentifier(channel),
        theme: new.theme.id,
        colorScheme: new.colorScheme,
        contrast: new.colorSchemeContrast,
        typeSize: new.dynamicTypeSize,
        sizeClass: new.horizontalSizeClass,
        layoutDirection: new.layoutDirection,
        locale: new.locale,
        reducesMotion: new.reducesMotion,
        scenePhase: new.scenePhase)
      guard signature != self.signature || preferencesChanged else { return }
      self.signature = signature
      preferencesChanged = false
      values = new
    }
  }

  private struct RowView: View {
    let model: RowModel
    let vm: ChannelStore
    let environment: RowEnvironment

    var body: some View {
      Group {
        switch model.content {
        case .message(let message, let prior):
          MessageCell(for: message, prior: prior, channel: vm)
        case .pending(let message, let priorSent, let priorQueued):
          if let priorQueued {
            ChatView.SendMessageCell(for: message, prior: priorQueued)
          } else {
            ChatView.SendMessageCell(for: message, prior: priorSent)
          }
        case .edge:
          ChatHistoryEdge(vm: vm)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      // a row passing under the navigation bar or the message field is laid
      // out like any other
      .ignoresSafeArea()
      .environment(\.self, environment.values)
    }
  }
#endif
