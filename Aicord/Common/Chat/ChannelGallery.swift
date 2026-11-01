//
//  ChannelGallery.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//

import AicordKit
import SwiftUI

/// Every image, video, link and file of a channel or DM in one place. Starts
/// from the messages already loaded, then pages through Discord's search with
/// a `has:` filter as you scroll; nothing is fetched in the background.
struct ChannelGallerySheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss
  @Environment(\.openURL) var openURL

  let channelId: ChannelSnowflake
  let guildId: GuildSnowflake?
  let title: String

  enum Tab: Hashable, CaseIterable {
    case media, links, files

    var title: LocalizedStringKey {
      switch self {
      case .media: "Media"
      case .links: "Links"
      case .files: "Files"
      }
    }

    /// Discord's search filters for the tab.
    var has: [String] {
      switch self {
      case .media: ["image", "video"]
      case .links: ["link"]
      case .files: ["file"]
      }
    }
  }

  /// Where the search left off for one tab.
  struct Page {
    var offset = 0
    var total: Int?
    var loading = false
    var failed = false
    var indexing = false
    var hasMore: Bool { total.map { offset < $0 } ?? true }
  }

  @State private var tab: Tab = .media
  @State private var messages: [MessageSnowflake: DiscordChannel.Message] = [:]
  @State private var pages: [Tab: Page] = [:]

  @State private var viewerMedia: [DiscordMedia] = []
  @State private var viewerIndex: Int?
  @State private var showingViewer = false

  var body: some View {
    NavigationStack {
      content
        .navigationTitle(title)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .top) {
          Picker("Show", selection: $tab) {
            ForEach(Tab.allCases, id: \.self) { tab in
              Text(tab.title).tag(tab)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .padding(.horizontal)
          .padding(.vertical, 8)
          .background(.bar)
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    .task {
      guard messages.isEmpty else { return }
      for message in gw.loadedMessages(in: channelId) { messages[message.id] = message }
    }
    .task(id: tab) {
      if pages[tab] == nil { await loadMore(tab) }
    }
    #if os(iOS)
      .fullScreenCover(isPresented: $showingViewer) {
        AttachmentViewer(
          attachments: $viewerMedia, selectedIndex: $viewerIndex, isPresented: $showingViewer)
      }
    #else
      .overlay {
        if showingViewer {
          ZStack {
            Color.black.opacity(0.75)
              .onTapGesture { showingViewer = false }
            AttachmentViewer(
              attachments: $viewerMedia, selectedIndex: $viewerIndex, isPresented: $showingViewer)
          }
          .transition(.opacity)
        }
      }
      .animation(.default.speed(1.5), value: showingViewer)
    #endif
  }

  // MARK: - Content

  @ViewBuilder
  private var content: some View {
    let items = items(for: tab)
    let page = pages[tab] ?? Page()
    if items.isEmpty {
      VStack {
        if page.loading || pages[tab] == nil {
          ProgressView()
        } else {
          ContentUnavailableView(
            emptyTitle, systemImage: emptySymbol, description: footerText(page).map { Text($0) })
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      switch tab {
      case .media: mediaGrid(items, page: page)
      case .links, .files: list(items, page: page)
      }
    }
  }

  private func mediaGrid(_ items: [Item], page: Page) -> some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 2)], spacing: 2) {
        ForEach(items) { item in
          if case .media(let media, let isVideo) = item.kind {
            Button {
              openViewer(on: item, in: items)
            } label: {
              MediaThumbnail(media: media, isVideo: isVideo, isHidden: Self.isHidden(media))
            }
            .buttonStyle(.plain)
            .contextMenu { goToMessage(item) }
            .accessibilityLabel(isVideo ? Text("Video") : Text("Image"))
            .accessibilityHint(Text("From \(item.author), \(item.date.formatted(date: .abbreviated, time: .shortened))"))
            .onAppear { loadMoreIfLast(item, in: items) }
          }
        }
      }
      footer(page)
        .padding()
    }
  }

  private func list(_ items: [Item], page: Page) -> some View {
    List {
      ForEach(items) { item in
        row(item)
          .onAppear { loadMoreIfLast(item, in: items) }
      }
      footer(page)
        .listRowBackground(Color.clear)
    }
  }

  @ViewBuilder
  private func row(_ item: Item) -> some View {
    HStack(spacing: 10) {
      Button {
        switch item.kind {
        case .link(let url, _): openURL(url)
        case .file(let file): URL(string: file.url).map { openURL($0) }
        case .media: break
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: item.symbol)
            .font(.title3)
            .foregroundStyle(.tint)
            .frame(width: 32)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.title)
              .lineLimit(2)
            Text(verbatim: item.subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Text("\(item.author) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      Button {
        jump(to: item)
      } label: {
        Image(systemName: "arrow.right.circle")
      }
      .buttonStyle(.borderless)
      .help(Text("Go to Message"))
      .accessibilityLabel(Text("Go to Message"))
    }
    .contextMenu { goToMessage(item) }
  }

  @ViewBuilder
  private func footer(_ page: Page) -> some View {
    HStack {
      Spacer()
      if page.loading {
        ProgressView()
      } else if page.failed {
        Button("Try Again") { Task { await loadMore(tab) } }
      } else if let text = footerText(page) {
        Text(text)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      } else if page.hasMore {
        Button("Load More") { Task { await loadMore(tab) } }
      }
      Spacer()
    }
  }

  private func footerText(_ page: Page) -> LocalizedStringKey? {
    if page.indexing { return "Discord is still indexing this channel. Try again in a moment." }
    if page.failed { return "Couldn't search this channel." }
    return nil
  }

  private func goToMessage(_ item: Item) -> some View {
    Button("Go to Message", systemImage: "arrow.right.circle") { jump(to: item) }
  }

  private var emptyTitle: LocalizedStringKey {
    switch tab {
    case .media: "No Media"
    case .links: "No Links"
    case .files: "No Files"
    }
  }

  private var emptySymbol: String {
    switch tab {
    case .media: "photo.on.rectangle"
    case .links: "link"
    case .files: "doc"
    }
  }

  // MARK: - Actions

  private func openViewer(on item: Item, in items: [Item]) {
    var media: [DiscordMedia] = []
    var index = 0
    for other in items {
      guard case .media(let attachment, _) = other.kind else { continue }
      if other.id == item.id { index = media.count }
      media.append(attachment)
    }
    viewerMedia = media
    viewerIndex = index
    showingViewer = true
  }

  private func jump(to item: Item) {
    dismiss()
    appState.open(guild: guildId, channel: channelId, message: item.messageID)
  }

  private func loadMoreIfLast(_ item: Item, in items: [Item]) {
    guard item.id == items.last?.id else { return }
    let page = pages[tab] ?? Page()
    guard page.hasMore, !page.loading, !page.failed, !page.indexing else { return }
    Task { await loadMore(tab) }
  }

  /// One page of Discord's search for the tab: 25 messages that have the kind.
  private func loadMore(_ tab: Tab) async {
    var page = pages[tab] ?? Page()
    guard !page.loading, page.hasMore else { return }
    page.loading = true
    page.failed = false
    page.indexing = false
    pages[tab] = page
    do {
      let query = MessageSearchQuery(
        channelIDs: guildId == nil ? [] : [channelId], has: tab.has, offset: page.offset)
      let res: DiscordClientResponse<MessageSearchResults>
      if let guildId {
        res = try await gw.client.searchGuildMessages(guildID: guildId, query: query)
      } else {
        res = try await gw.client.searchChannelMessages(channelID: channelId, query: query)
      }
      if res.httpResponse.status == .accepted {
        page.indexing = true
      } else {
        try res.guardSuccess()
        let results = try res.decode()
        let found = results.messages.compactMap(\.first)
        for message in found { messages[message.id] = message }
        page.total = results.total_results
        page.offset += found.count
        if found.isEmpty { page.total = page.offset }
      }
    } catch {
      print("[Gallery] Search failed:", error)
      page.failed = true
    }
    page.loading = false
    pages[tab] = page
  }

  // MARK: - Items

  struct Item: Identifiable {
    enum Kind {
      case media(DiscordMedia, isVideo: Bool)
      case link(URL, title: String?)
      case file(DiscordChannel.Message.Attachment)
    }

    let id: String
    let messageID: MessageSnowflake
    let author: String
    let date: Date
    let kind: Kind

    var symbol: String {
      switch kind {
      case .media(_, let isVideo): isVideo ? "film" : "photo"
      case .link: "link"
      case .file(let file):
        file.mediaKind == .audio ? "waveform" : "doc"
      }
    }

    var title: String {
      switch kind {
      case .media: ""
      case .link(let url, let title): title ?? url.host() ?? url.absoluteString
      case .file(let file): file.filename
      }
    }

    var subtitle: String {
      switch kind {
      case .media: ""
      case .link(let url, _): url.absoluteString
      case .file(let file): Int64(file.size).formatted(.byteCount(style: .file))
      }
    }
  }

  /// Spoilers and media Discord flagged as explicit stay blurred, as in the chat.
  static func isHidden(_ media: DiscordMedia) -> Bool {
    guard let attachment = media as? DiscordChannel.Message.Attachment else { return false }
    return attachment.filename.hasPrefix("SPOILER_")
      || attachment.flags?.contains(.isSpoiler) == true
      || attachment.flags?.contains(.containsExplicitMedia) == true
  }

  private static let linkDetector = try? NSDataDetector(
    types: NSTextCheckingResult.CheckingType.link.rawValue)

  /// The tab's items, newest message first.
  private func items(for tab: Tab) -> [Item] {
    let sorted = messages.values.sorted {
      $0.id.rawValue.compare($1.id.rawValue, options: .numeric) == .orderedDescending
    }
    var items: [Item] = []
    for message in sorted {
      let author =
        message.member?.nick ?? message.author?.global_name ?? message.author?.username ?? ""
      let date = message.timestamp.date
      func add(_ suffix: String, _ kind: Item.Kind) {
        items.append(
          Item(
            id: "\(message.id.rawValue)-\(suffix)", messageID: message.id, author: author,
            date: date, kind: kind))
      }
      switch tab {
      case .media:
        for attachment in message.attachments {
          switch attachment.mediaKind {
          case .image: add(attachment.id.rawValue, .media(attachment, isVideo: false))
          case .video: add(attachment.id.rawValue, .media(attachment, isVideo: true))
          default: break
          }
        }
        for (index, embed) in message.embeds.enumerated() {
          switch embed.type {
          case .image:
            if let image = embed.image ?? embed.thumbnail {
              add("embed-\(index)", .media(image, isVideo: false))
            }
          case .gifv, .video:
            if let video = embed.video, embed.type == .gifv {
              add("embed-\(index)", .media(video, isVideo: true))
            } else if let thumbnail = embed.thumbnail {
              add("embed-\(index)", .media(thumbnail, isVideo: false))
            }
          default: break
          }
        }
      case .links:
        let text = message.content
        let matches =
          Self.linkDetector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var seen: Set<String> = []
        for match in matches {
          guard let url = match.url, url.scheme?.hasPrefix("http") == true,
            seen.insert(url.absoluteString).inserted
          else { continue }
          let title = message.embeds.first { $0.url == url.absoluteString }?.title
          add("link-\(seen.count)", .link(url, title: title))
        }
      case .files:
        for attachment in message.attachments
        where attachment.mediaKind == .audio || attachment.mediaKind == .other {
          add(attachment.id.rawValue, .file(attachment))
        }
      }
    }
    return items
  }
}

/// A square thumbnail; videos show their first frame and a play badge.
private struct MediaThumbnail: View {
  let media: DiscordMedia
  let isVideo: Bool
  var isHidden = false

  var body: some View {
    Color.gray.opacity(0.15)
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        MessageCell.AttachmentsView.AttachmentItemPreview.ImageView(
          attachment: media, needsPoster: isVideo
        )
        .scaledToFill()
        // a tall image overflows the cell; only the cell itself takes taps
        .allowsHitTesting(false)
        .blur(radius: isHidden ? 24 : 0)
      }
      .clipped()
      .overlay {
        if isHidden {
          Image(systemName: "eye.slash.fill")
            .font(.title3)
            .foregroundStyle(.white)
            .shadow(radius: 4)
            .accessibilityLabel(Text("Spoiler"))
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if isVideo {
          Image(systemName: "play.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.5), in: .circle)
            .padding(4)
        }
      }
      .contentShape(.rect)
  }
}

// MARK: - Entry Points

/// Opens the gallery of a DM with this person, from their profile.
struct DMGalleryProfileButton: View {
  @Environment(\.gateway) var gw
  let user: PartialUser
  @State private var showing = false

  var body: some View {
    if let channel = gw.user.privateChannels.values.first(where: {
      $0.type == .dm && $0.recipients?.first?.id == user.id
    }) {
      Button("Media, Links and Files", systemImage: "photo.on.rectangle") { showing = true }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .padding(.top, 6)
        .sheet(isPresented: $showing) {
          ChannelGallerySheet(
            channelId: channel.id, guildId: nil,
            title: user.global_name ?? user.username ?? String(localized: "Direct Message")
          )
          .galleryFrame()
        }
    }
  }
}

extension View {
  /// The gallery's size as a sheet on Mac.
  func galleryFrame() -> some View {
    #if os(macOS)
      self.frame(width: 720, height: 620)
    #else
      self
    #endif
  }
}
