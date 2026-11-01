//
//  ForumChannelView.swift
//  Aicord
//

import AicordKit
import SwiftUI

extension DiscordChannel.Kind {
  /// Channels whose content is a message list `ChatView` can show.
  var opensAsChat: Bool {
    switch self {
    case .guildText, .dm, .groupDm, .guildAnnouncement, .guildVoice,
      .announcementThread, .publicThread, .privateThread:
      true
    default:
      false
    }
  }

  var isThread: Bool {
    self == .announcementThread || self == .publicThread || self == .privateThread
  }

  /// Forum and media channels: a list of posts, each one a thread.
  var isThreadOnly: Bool {
    self == .guildForum || self == .guildMedia
  }
}

/// What a selected channel shows: its chat, its posts, or a way out to Discord.
struct ChannelContentView: View {
  var vm: ChannelStore
  @Environment(\.appState) var appState

  var body: some View {
    let type = vm.channel?.type
    if type?.isThreadOnly == true {
      ForumChannelView(vm: vm)
    } else if let type, !type.opensAsChat {
      UnsupportedChannelView(vm: vm)
    } else {
      ChatView(vm: vm)
        .toolbar {
          if let parent = forumParent {
            ToolbarItem(placement: .navigation) {
              Button {
                appState.selectedChannel = parent.id
              } label: {
                Label(parent.name ?? String(localized: "Forum"), systemImage: "chevron.backward")
              }
              .help(
                parent.type?.isThreadOnly == true
                  ? Text("Back to the post list") : Text("Back to the channel"))
            }
          }
        }
    }
  }

  /// The channel a thread or forum post belongs to, for the way back to it.
  private var forumParent: DiscordChannel? {
    guard vm.channel?.type?.isThread == true, let parentID = vm.channel?.parent_id,
      let parent = vm.guildStore?.channels[ChannelSnowflake(parentID.rawValue)]
    else { return nil }
    return parent
  }
}

/// A channel type Aicord has no view for (stage, directory, store, new ones).
struct UnsupportedChannelView: View {
  var vm: ChannelStore
  @Environment(\.openURL) var openURL

  var body: some View {
    ContentUnavailableView {
      Label(
        vm.channel?.name ?? String(localized: "Channel"),
        systemImage: ChannelButton.symbol(for: vm.channel?.type))
    } description: {
      Text("Aicord can't show this kind of channel yet.")
    } actions: {
      Button("Open in Browser") {
        let guild = vm.guildStore?.guildId.rawValue ?? "@me"
        if let url = URL(string: "https://discord.com/channels/\(guild)/\(vm.channelId.rawValue)") {
          openURL(url)
        }
      }
      .buttonStyle(.borderedProminent)
    }
  }
}

/// A forum or media channel: its posts, most recently active first, with tags
/// to filter by. Opening a post shows it in the chat.
struct ForumChannelView: View {
  var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.theme) var theme

  @State private var posts: [DiscordChannel] = []
  @State private var firstMessages: [ChannelSnowflake: DiscordChannel.Message] = [:]
  @State private var hasMore = false
  @State private var isLoading = false
  @State private var failed = false
  @State private var indexing = false
  @State private var sort: ThreadSearchQuery.SortBy = .lastMessageTime
  @State private var selectedTags: Set<ForumTagSnowflake> = []

  private var channel: DiscordChannel? { vm.channel }
  private var tags: [DiscordChannel.ForumTag] { channel?.available_tags ?? [] }

  var body: some View {
    List {
      if let topic = channel?.topic, !topic.isEmpty {
        Section {
          // guidelines can run for pages; the first lines say what the forum is for
          Text(topic.replacingOccurrences(of: "\n", with: " "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
      }
      if !tags.isEmpty {
        Section {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(tags, id: \.id) { tag in
                let isOn = selectedTags.contains(tag.id)
                Button {
                  if isOn { selectedTags.remove(tag.id) } else { selectedTags.insert(tag.id) }
                } label: {
                  ForumTagChip(tag: tag, isSelected: isOn)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
              }
            }
          }
        }
      }
      Section {
        ForEach(posts, id: \.id) { post in
          Button {
            open(post)
          } label: {
            ForumPostRow(
              post: post, firstMessage: firstMessages[post.id], tags: tags,
              guildStore: vm.guildStore)
          }
          .buttonStyle(.plain)
          .onAppear {
            if post.id == posts.last?.id, hasMore { Task { await load(reset: false) } }
          }
        }
        if isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
      } footer: {
        if indexing {
          Text("Discord is still indexing this channel. Try again in a moment.")
        } else if failed {
          Text("The posts couldn't be loaded.")
        } else if !isLoading && posts.isEmpty {
          Text("No posts yet.")
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(theme.common.secondaryBackground)
    .refreshable { await load(reset: true) }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Label(
          channel?.name ?? String(localized: "Forum"),
          systemImage: ChannelButton.symbol(for: channel?.type)
        )
        .labelStyle(.titleAndIcon)
        .font(.headline)
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Picker("Sort by", selection: $sort) {
            Text("Recent Activity").tag(ThreadSearchQuery.SortBy.lastMessageTime)
            Text("Date Posted").tag(ThreadSearchQuery.SortBy.creationTime)
          }
        } label: {
          Label("Sort", systemImage: "arrow.up.arrow.down")
        }
      }
    }
    .task(id: QueryKey(sort: sort, tags: selectedTags)) { await load(reset: true) }
  }

  private struct QueryKey: Equatable {
    var sort: ThreadSearchQuery.SortBy
    var tags: Set<ForumTagSnowflake>
  }

  private func open(_ post: DiscordChannel) {
    vm.guildStore?.threads[post.id] = post
    appState.selectedChannel = post.id
  }

  private func load(reset: Bool) async {
    guard !isLoading || reset else { return }
    isLoading = true
    defer { isLoading = false }
    let query = ThreadSearchQuery(
      tags: Array(selectedTags), sortBy: sort, offset: reset ? 0 : posts.count)
    // Discord answers 202 while it builds the index; it's usually ready in seconds
    for attempt in 0..<3 {
      do {
        let response = try await gw.client.searchForumThreads(channelID: vm.channelId, query: query)
        guard !Task.isCancelled else { return }
        if response.httpResponse.status == .accepted {
          indexing = true
          try await Task.sleep(for: .seconds(2 * (attempt + 1)))
          continue
        }
        try response.guardSuccess()
        let page = try response.decode()
        indexing = false
        failed = false
        if reset {
          posts = []
          firstMessages = [:]
        }
        let known = Set(posts.map(\.id))
        posts += page.threads.filter { !known.contains($0.id) }
        for message in page.first_messages ?? [] {
          firstMessages[message.channel_id] = message
        }
        hasMore = page.has_more ?? false
        return
      } catch {
        if !Task.isCancelled {
          print("[Forum] Post search failed:", error)
          failed = true
        }
        return
      }
    }
  }
}

struct ForumTagChip: View {
  var tag: DiscordChannel.ForumTag
  var isSelected = false
  @Environment(\.theme) var theme

  var body: some View {
    HStack(spacing: 4) {
      if let id = tag.emoji_id,
        let url = DiscordImageURL.customEmoji(id: id, animated: false)
      {
        NukeImage(url: url)
          .resizable()
          .scaledToFit()
          .frame(width: 14, height: 14)
      } else if let name = tag.emoji_name {
        Text(name)
      }
      Text(tag.name)
        .lineLimit(1)
    }
    .font(.caption.weight(.medium))
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(
      isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.3))
        : AnyShapeStyle(theme.common.tertiaryBackground),
      in: .capsule
    )
    .overlay {
      if isSelected { Capsule().strokeBorder(Color.accentColor) }
    }
  }
}

/// A post: title, tags, author, a preview of the opening message, replies and
/// when it was last active.
struct ForumPostRow: View {
  var post: DiscordChannel
  var firstMessage: DiscordChannel.Message?
  var tags: [DiscordChannel.ForumTag]
  var guildStore: GuildStore?

  private var appliedTags: [DiscordChannel.ForumTag] {
    let applied = post.applied_tags ?? []
    return tags.filter { applied.contains($0.id) }
  }

  private var authorName: String? {
    guard let author = firstMessage?.author else { return nil }
    return guildStore?.member(author.id)?.nick ?? author.global_name ?? author.username
  }

  /// The latest message or, without one, when the post was made.
  private var lastActivity: Date? {
    post.last_message_id?.parse()?.date ?? post.id.parse()?.date
  }

  private var preview: DiscordChannel.Message.Attachment? {
    firstMessage?.attachments.first { $0.content_type?.hasPrefix("image/") == true }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        if !appliedTags.isEmpty {
          HStack(spacing: 4) {
            ForEach(appliedTags, id: \.id) { ForumTagChip(tag: $0) }
          }
        }
        HStack(spacing: 4) {
          if post.thread_metadata?.locked == true {
            Image(systemName: "lock.fill")
              .font(.caption)
              .accessibilityLabel(Text("Locked"))
          } else if post.thread_metadata?.archived == true {
            Image(systemName: "archivebox")
              .font(.caption)
              .accessibilityLabel(Text("Archived"))
          }
          Text(post.name ?? "")
            .font(.headline)
            .lineLimit(2)
        }
        if let content = firstMessage?.content, !content.isEmpty {
          Text(
            (authorName.map { "\($0): " } ?? "") + content.replacingOccurrences(of: "\n", with: " ")
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        } else if let authorName {
          Text(authorName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 12) {
          Label("\(post.message_count ?? 0)", systemImage: "bubble.left.and.bubble.right")
            .accessibilityLabel(Text("\(post.message_count ?? 0) replies"))
          if let lastActivity {
            Text(lastActivity, format: .relative(presentation: .named))
          }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let preview, let url = URL(string: preview.proxy_url) {
        NukeImage(url: url)
          .resizable()
          .scaledToFill()
          .frame(width: 64, height: 64)
          .clipShape(.rect(cornerRadius: 8))
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 4)
    .contentShape(.rect)
  }
}
