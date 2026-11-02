//
//  ChatView.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct ChatView: View {
  @State var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme
  @Environment(\.scenePhase) var scenePhase

  /// Moves the list: to a message, to the bottom, or by an offset when older
  /// history comes in above. Never read in `body`.
  @State private var scrollPosition = ScrollPosition(idType: MessageSnowflake.self)
  /// Whether the newest messages are scrolled out of view, from the scroll
  /// geometry. Only read in callbacks and by `JumpToLatestButton`.
  @State private var awayFromLatest = false
  @State private var summaryRange: SummaryRange?
  @State private var askingChannel = false
  @State private var indexingChannel = false
  @State private var showsPins = false
  @State private var showsThreads = false
  @State private var showsGallery = false
  @State private var showsExport = false
  @AppStorage(IntelligencePreferences.Key.allowsDMs) private var intelligenceInDMs = false
  @State private var isScrolling: Bool = false
  /// Whether the user has scrolled this chat. Older history only loads after
  /// that: before the first layout settles on the bottom, the list briefly
  /// starts at its top, which used to fetch page after page on open.
  /// Only read in callbacks, never in `body`.
  @State private var userHasScrolled = false
  /// Whether the list is within three screens of its top. Only read in callbacks.
  @State private var nearTop = false

  var drain: MessageDrainStore { gw.messageDrain }

  @AppStorage(AppearancePreferences.Key.chatMessagesAnimated)
  var animatesMessagesSetting: Bool = false
  @Environment(\.reducesMotion) var reducesMotion
  var chatAnimatesMessages: Bool { animatesMessagesSetting && !reducesMotion }

  init(vm: ChannelStore) { self._vm = .init(initialValue: vm) }

  private var botModal: Binding<BotInteractions.PresentedModal?> {
    Binding(
      get: {
        BotInteractions.shared.modal.flatMap { $0.origin.channelID == vm.channelId ? $0 : nil }
      },
      set: { if $0 == nil { BotInteractions.shared.modal = nil } }
    )
  }

  #if os(macOS)
    @FocusState private var isChatFocused: Bool
  #endif

  var body: some View {
    let orderedMessages = vm.messages.values
    let pendingMessages = drain.pendingMessages[vm.channelId, default: [:]]

    let shouldAnimate =
      orderedMessages.last?.author?.id != gw.user.currentUser?.id
    VStack(spacing: 20) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if !vm.messages.isEmpty {
            HistoryEdge(vm: vm)
          }

          ForEach(orderedMessages) { msg in
            let prior = vm.getMessage(before: msg)
            if messageAllowed(msg) {
              #if os(macOS)
                MessageCell(
                  for: msg,
                  prior: prior,
                  channel: vm,
                  scrolling: isScrolling
                )
              #else
                // only the Mac's hover highlight needs the scroll phase; passing it
                // here re-rendered every visible row whenever a scroll began or ended
                MessageCell(for: msg, prior: prior, channel: vm)
              #endif
            }
          }

          ForEach(pendingMessages.values) { message in
            // if there is only one message, there is no prior. use the latest message from channelstore
            if pendingMessages.count > 1,
              let messageIndex = pendingMessages.values.firstIndex(where: {
                $0.nonce == message.nonce
              }),
              messageIndex > 0
            {
              let priorMessage = pendingMessages.values[messageIndex - 1]
              SendMessageCell(for: message, prior: priorMessage)
            } else if let latestMessage = orderedMessages.last {
              // if there is a prior message from the channel store, use that
              SendMessageCell(for: message, prior: latestMessage)
            } else {
              // no prior message
              SendMessageCell(
                for: message,
                prior: Optional<DiscordChannel.Message>.none
              )
            }
          }
          // message drain view, represents messages being sent etc
        }
        // no scrollTargetLayout: with it the scroll position tracked the row at
        // its anchor, and each row scrolling past re-rendered the whole chat.
        // scrollTo(id:) finds the rows without it.
      }
      // macos 26/27 bug workaround
      .safeAreaPadding(.top, 1)
      .safeAreaInset(edge: .top, spacing: 0) {
        ScamWarningBanner(vm: vm)
      }
      .overlay(alignment: .top) { OfflinePill() }
      #if os(macOS)
        // esc to scroll to bottom of chat, its a little jank
        .focusable()
        .focusEffectDisabled()
        // no tap gesture here: on macOS a click recogniser on the whole list
        // swallowed mouse-downs before Textual's text view saw them, so links
        // in messages (invite links among them) did nothing when clicked
        .focused($isChatFocused)
        .onKeyPress(.escape, phases: .down) { _ in
          vm.requestScrollToBottom(immediate: true)
          InputBar.inputVMs[vm.channelId]?.uploadItems = []
          return .handled
        }
      #endif
      .onScrollPhaseChange { _, newPhase in
        if newPhase.isScrolling { userHasScrolled = true }
        #if os(macOS)
          isScrolling = newPhase.isScrolling
          // scrolling the chat is what makes Esc jump back to the bottom
          if newPhase == .interacting { isChatFocused = true }
        #endif
      }
      // older history loads once the user scrolls within three screens of the top
      .onScrollGeometryChange(for: Bool.self) { geometry in
        let fromTop = geometry.contentOffset.y + geometry.contentInsets.top
        return geometry.contentSize.height > geometry.containerSize.height
          && fromTop < geometry.containerSize.height * 3
      } action: { _, isNearTop in
        nearTop = isNearTop
        loadOlderIfNeeded()
      }
      // a page that came in short of filling those three screens asks for the next
      // once its load has finished
      .onChange(of: vm.loadingMessagesTask == nil) { _, idle in
        if idle { loadOlderIfNeeded() }
      }
      // SwiftUI leaves the offset alone when rows are inserted above it, so a
      // page of older history pushed what was on screen a page down. Move by
      // what the page added instead, so the same message stays put. The lazy
      // stack reports the new height on a later scroll update, often with the
      // offset moving too, so the page is recognised by its size (at least 10
      // points a message) rather than by timing. Smaller changes are the stack
      // refining its estimates, which it already keeps in place itself.
      .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
        ScrollMetrics(
          offset: geometry.contentOffset.y, contentHeight: geometry.contentSize.height)
      } action: { old, new in
        let inserted = vm.unsettledHistoryInsertion
        let grown = new.contentHeight - old.contentHeight
        guard inserted > 0, grown > CGFloat(inserted) * 10 else { return }
        vm.unsettledHistoryInsertion = 0
        scrollPosition.scrollTo(y: new.offset + grown)
      }
      .onScrollGeometryChange(for: Bool.self) { geometry in
        let fromBottom =
          geometry.contentSize.height + geometry.contentInsets.bottom
          - geometry.contentOffset.y - geometry.containerSize.height
        return fromBottom > geometry.containerSize.height
      } action: { _, away in
        awayFromLatest = away
      }
      .scrollPosition($scrollPosition, anchor: .bottom)  // causes issues with input bar height changes:
      // currently, the input bar changing size can cause the scrollview position to jump unexpectedly.
      // not sure how to fix.
      .bottomAnchored()
      .scrollClipDisabled()
      .frame(maxHeight: .infinity)
      .overlay(alignment: .bottomTrailing) {
        // its own view, so the scroll position changing as rows pass by only
        // updates the button, not the whole chat
        JumpToLatestButton(vm: vm, awayFromLatest: $awayFromLatest) {
          acknowledgeLatestIfVisible()
        }
      }

      ForEach(vm.activities.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { app in
        ActivityNotice(
          applicationID: app,
          channel: vm,
          participants: vm.activities[app]?.count ?? 0
        ) {
          vm.activities.removeValue(forKey: app)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, -12)
      }

      ChatComposer(vm: vm)
    }
    // only a new newest message animates: animating on any change (a reaction, an
    // edit, an embed arriving) moved rows around while scrolling, and compared
    // every loaded message on each update
    .animation(
      shouldAnimate && chatAnimatesMessages ? .default : nil,
      value: vm.messages.keys.last
    )
    .animation(chatAnimatesMessages ? .default : nil, value: pendingMessages)
    .scrollDismissesKeyboard(.interactively)
    .background(theme.common.secondaryBackground)
    .ignoresSafeArea(.keyboard, edges: .all)

    .toolbar {
      // a plain title rather than a glass pill: the leading pill on iOS is too narrow for
      // most channel names, and the centre slot truncates gracefully when space runs out
      #if os(iOS)
        ToolbarItem(placement: .principal) {
          titleMenu
        }
        .sharedBackgroundVisibility(.hidden)
      #else
        // the window's title and subtitle name the channel (MacBaseplate), so
        // the toolbar carries the channel's actions as buttons, like Mail's
        ToolbarItemGroup(placement: .primaryAction) {
          if !isPrivateChannel || intelligenceInDMs {
            intelligenceMenu
          }
          Button {
            showsPins = true
          } label: {
            Label("Pinned Messages", systemImage: "pin")
          }
          .help("Pinned messages")
          if vm.channel?.type == .guildText || vm.channel?.type == .guildAnnouncement {
            Button {
              showsThreads = true
            } label: {
              Label("Threads", systemImage: "number.square")
            }
            .help("Threads")
          }
        }
      #endif
      ToolbarItem(placement: .primaryAction) {
        channelMenu
      }
      // no calls before a request is accepted
      if vm.channel?.type == .dm || vm.channel?.type == .groupDm,
        gw.user.privateChannels[vm.channelId].map({ !$0.isPendingMessageRequest && !$0.isSpam })
          ?? true
      {
        ToolbarItem(placement: .primaryAction) {
          DMCallButton(channelID: vm.channelId)
        }
      }
    }
    .sheet(item: $summaryRange) { range in
      ChannelSummarySheet(
        channelId: vm.channelId,
        guildId: vm.guildStore?.guildId,
        channelName: channelTitle,
        range: range
      )
    }
    .sheet(isPresented: $askingChannel) {
      AskChannelSheet(
        channelId: vm.channelId, guildId: vm.guildStore?.guildId, channelName: channelTitle)
    }
    .sheet(isPresented: $showsPins) {
      PinnedMessagesSheet(vm: vm)
    }
    .sheet(isPresented: $showsThreads) {
      ThreadBrowserSheet(vm: vm)
    }
    .sheet(isPresented: $showsExport) {
      ChannelExportSheet(
        channelId: vm.channelId, guildId: vm.guildStore?.guildId,
        title: exportTitle)
    }
    .sheet(isPresented: $showsGallery) {
      ChannelGallerySheet(
        channelId: vm.channelId, guildId: vm.guildStore?.guildId, title: channelTitle
      )
      .galleryFrame()
    }
    .sheet(isPresented: $indexingChannel) {
      ChannelIndexSheet(
        channelId: vm.channelId, guildId: vm.guildStore?.guildId, channelName: channelTitle)
    }
    // a bot's modal, in the chat where its interaction ran
    .sheet(item: botModal) { presented in
      InteractionModalSheet(presented: presented)
        .environment(\.channelStore, vm)
    }
    // user and message commands for the message menu's Apps
    .task(id: vm.channelId) {
      _ = await SlashCommandIndex.shared.entries(for: vm, client: gw.client)
    }
    .onChange(of: vm.scrollRequest) { _, request in
      guard let request else { return }
      switch request.kind {
      case .bottom(let immediate, let pending):
        guard isNearBottom || immediate else {
          return
        }
        let resolvedId = pending ?? orderedMessages.last?.id
        withAnimation(immediate ? .default : nil) {
          if let resolvedId {
            scrollPosition.scrollTo(id: resolvedId, anchor: .bottom)
          }
        }
        acknowledgeLatestIfVisible()
      case .message(let messageId):
        scrollPosition.scrollTo(id: messageId, anchor: .bottom)
      }
    }
    // opening a channel whose messages are already loaded doesn't produce a scroll request
    .onAppear { acknowledgeLatestIfVisible() }
    // a channel marked unread goes back to normal once the user leaves it
    .onDisappear { gw.readStates.manuallyUnread.remove(vm.channelId) }
    // keep the newest messages on disk to read offline, once loading settles
    .task(id: vm.messages.keys.last) {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      OfflineCache.shared.save(vm, gateway: gw)
    }
    .onChange(of: vm.channelId) { old, _ in
      gw.readStates.manuallyUnread.remove(old)
      userHasScrolled = false
    }
    // on iPhone the chat only slides away, so closing it counts as leaving
    .onChange(of: appState.chatOpen) { _, open in
      if open {
        acknowledgeLatestIfVisible()
      } else {
        gw.readStates.manuallyUnread.remove(vm.channelId)
      }
    }
    // a jump from Search or a forward's source, for this channel
    .task(id: appState.pendingJump) {
      guard let jump = appState.pendingJump, jump.channelID == vm.channelId else { return }
      appState.pendingJump = nil
      await vm.jump(to: jump.messageID)
    }
    .onChange(of: scenePhase) { acknowledgeLatestIfVisible() }
  }

  /// The channel's name; tapping it opens the Intelligence actions, the same
  /// ones as the channel's long-press menu. In DMs only when allowed in
  /// Settings → Intelligence.
  @ViewBuilder
  private var titleMenu: some View {
    if !isPrivateChannel || intelligenceInDMs {
      Menu {
        ChannelIntelligenceActions(
          channelId: vm.channelId, summary: $summaryRange, asking: $askingChannel,
          indexing: $indexingChannel)
      } label: {
        HStack(spacing: 4) {
          ChannelHeader(vm: vm)
          Image(systemName: "chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .contentShape(.rect)
      }
      .menuIndicator(.hidden)
      .buttonStyle(.plain)
      .accessibilityHint("Shows Intelligence actions for this channel")
    } else {
      ChannelHeader(vm: vm)
    }
  }

  #if os(macOS)
    /// The Intelligence actions as a toolbar menu with a symbol.
    private var intelligenceMenu: some View {
      Menu {
        ChannelIntelligenceActions(
          channelId: vm.channelId, summary: $summaryRange, asking: $askingChannel,
          indexing: $indexingChannel)
      } label: {
        Label("Intelligence", systemImage: "sparkles")
      }
      .help("Summarise or ask about this channel")
    }
  #endif

  /// Pins, the gallery, and the threads of a text or announcement channel.
  private var channelMenu: some View {
    let hasThreads = vm.channel?.type == .guildText || vm.channel?.type == .guildAnnouncement
    return Menu {
      Button {
        showsPins = true
      } label: {
        Label("Pinned Messages", systemImage: "pin")
      }
      Button {
        showsGallery = true
      } label: {
        Label("Media, Links and Files", systemImage: "photo.on.rectangle")
      }
      if hasThreads {
        Button {
          showsThreads = true
        } label: {
          Label("Threads", systemImage: "number.square")
        }
      }
      Divider()
      Button {
        showsExport = true
      } label: {
        Label("Export Channel…", systemImage: "square.and.arrow.up")
      }
    } label: {
      Label("Channel", systemImage: "ellipsis.circle")
    }
  }

  /// "#channel · Server" for a server channel, the DM's name otherwise.
  private var exportTitle: String {
    let place = gw.placeName(channelId: vm.channelId, guildId: vm.guildStore?.guildId)
    return place.isEmpty ? channelTitle : place
  }

  private var isPrivateChannel: Bool {
    vm.channel?.type == .dm || vm.channel?.type == .groupDm
  }

  /// How summaries name the channel.
  private var channelTitle: String {
    if let name = vm.channel?.name, !name.isEmpty {
      return isPrivateChannel ? name : "#" + name
    }
    let people = vm.channel?.recipients?.map { $0.global_name ?? $0.username } ?? []
    return people.isEmpty ? String(localized: "this conversation") : people.joined(separator: ", ")
  }

  /// Whether the chat is scrolled to (or within a screen of) the newest messages.
  private var isNearBottom: Bool { !awayFromLatest }

  /// Asks for the page before the oldest loaded message, when the user has
  /// scrolled up near it.
  private func loadOlderIfNeeded() {
    guard nearTop, userHasScrolled, !vm.messages.isEmpty else { return }
    vm.tryFetchMoreMessageHistory()
  }

  func messageAllowed(_ msg: DiscordChannel.Message) -> Bool {
    // Currently only filters out messages from blocked users
    guard let authorId = msg.author?.id else { return true }

    // check relationship
    if let relationship = gw.user.relationships[authorId] {
      if relationship.type == .blocked || relationship.user_ignored {
        return false
      }
    }

    return true
  }

  //  private func scheduleScrollToBottom(
  //    proxy: ScrollViewProxy,
  //    lastID: DiscordChannel.Message.ID? = nil,
  //  ) {
  //    pendingScrollWorkItem?.cancel()
  //    guard let lastID else { return }
  //
  //    let workItem = DispatchWorkItem { [proxy] in
  //      //      withAnimation(accessibilityReduceMotion ? .none : .default) {
  //      proxy.scrollTo(lastID, anchor: .top)
  //      //      }
  //    }
  //    pendingScrollWorkItem = workItem
  //    DispatchQueue.main.asyncAfter(deadline: .now(), execute: workItem)
  //  }

  @State var ackTask: Task<Void, Never>? = nil
  /// Marks the channel as read up to its newest message, if the user can actually see it:
  /// the app is active, the newest messages are loaded, and the chat is scrolled to the bottom.
  private func acknowledgeLatestIfVisible() {
    guard scenePhase == .active, vm.hasLatestMessages, isNearBottom,
      !gw.readStates.manuallyUnread.contains(vm.channelId),
      let messageId = vm.messages.values.last?.id,
      gw.readStates.isUnread(channelId: vm.channelId, lastMessageId: messageId)
    else { return }
    let channelId = vm.channelId
    ackTask?.cancel()
    ackTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      do {
        try await gw.client.acknowledgeMessage(
          channelId: channelId,
          messageId: messageId,
          payload: Payloads.AcknowledgeMessage()
        ).guardSuccess()
        gw.readStates.applyAck(channelId: channelId, messageId: messageId)
      } catch {
        print("[ChatView] Failed to acknowledge message \(messageId.rawValue):", error)
      }
    }
  }
}

extension View {
  fileprivate func bottomAnchored() -> some View {
    self
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .defaultScrollAnchor(.bottom, for: .alignment)
      .defaultScrollAnchor(.bottom, for: .sizeChanges)
  }
}

/// What the history insertion compensation compares between scroll updates.
private struct ScrollMetrics: Equatable {
  var offset: CGFloat
  var contentHeight: CGFloat
}

/// The top of the loaded messages: a spinner while older history is left to load,
/// otherwise the start of the channel. Its own view, so the permission check,
/// which reads the server's members, doesn't re-render the whole chat each time
/// a member loads.
private struct HistoryEdge: View {
  let vm: ChannelStore

  var body: some View {
    if !vm.hasPermission(.readMessageHistory) {
      ChatHeaders.NoHistoryPermissionHeader()
    } else if vm.hasMoreHistory {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .accessibilityLabel("Loading older messages")
    } else {
      ChatHeaders.WelcomeStartOfChannelHeader()
    }
  }
}

/// The input bar, or what stands in for it. Its own view for the same reason as
/// `HistoryEdge`, and because DM channels update with every message sent anywhere.
private struct ChatComposer: View {
  let vm: ChannelStore
  @Environment(\.gateway) var gw

  var body: some View {
    if let channel = gw.user.privateChannels[vm.channelId],
      channel.isPendingMessageRequest || channel.isSpam
    {
      // replying would accept the request, so ask first
      MessageRequestBar(channel: channel)
    } else if vm.hasPermission(.sendMessages) {
      ChatView.InputBar(vm: vm)
        .id(vm.channelId)
    } else {
      Spacer().frame(height: 10)
    }
  }
}

/// The arrow back to the newest messages, shown once they're scrolled out of view.
private struct JumpToLatestButton: View {
  let vm: ChannelStore
  @Binding var awayFromLatest: Bool
  /// Runs when the newest messages come into or leave view, e.g. to mark them as read.
  var onPositionChange: () -> Void

  var body: some View {
    // a ZStack stays in the tree while the button is hidden, so onChange still runs
    ZStack { content }
      .onChange(of: awayFromLatest) {
        // lets new messages trim the oldest ones only while the newest are on screen
        vm.isViewingLatest = vm.hasLatestMessages && !awayFromLatest
        onPositionChange()
      }
  }

  @ViewBuilder
  private var content: some View {
    if !vm.hasLatestMessages || awayFromLatest {
      Button(action: {
        if vm.hasLatestMessages {
          vm.requestScrollToBottom(immediate: true)
        } else {
          vm.returnToLatest()
        }
      }) {
        Image(systemName: "arrow.down")
          .tint(.primary)
          .imageScale(.large)
          .padding(10)
          .glassEffect(.regular.interactive(), in: .circle)
      }
      .buttonStyle(.plain)
      .padding()
      .transition(.blurReplace.animation(.default))
    }
  }
}

