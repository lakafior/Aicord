//
//  MessagesView.swift
//  Aicord
//
//  The iPhone Messages tab: direct messages, group chats and friends,
//  kept apart from the server list on the Home tab.
//

import PaicordLib
import SwiftUI

struct MessagesView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  enum Page: Hashable { case messages, friends }
  @State var page: Page = .messages
  @State var searchText = ""
  @State var composing = false

  var body: some View {
    NavigationStack {
      List {
        Picker("Show", selection: $page) {
          Text("Messages").tag(Page.messages)
          Text("Friends").tag(Page.friends)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        switch page {
        case .messages: conversations
        case .friends: FriendsList(searchText: searchText, open: open(user:))
        }
      }
      .navigationTitle("Messages")
      .searchable(text: $searchText, prompt: page == .messages ? "Find a conversation" : "Find a friend")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            composing = true
          } label: {
            Label("New Message", systemImage: "square.and.pencil")
          }
        }
      }
      .sheet(isPresented: $composing) {
        NewMessageSheet(open: open(user:))
      }
    }
  }

  // MARK: Conversations

  var channels: [DiscordChannel] {
    let all = gw.user.privateChannels.values.sorted {
      ($0.last_message_id?.rawValue ?? $0.id.rawValue)
        .compare($1.last_message_id?.rawValue ?? $1.id.rawValue, options: .numeric)
        == .orderedDescending
    }
    guard !searchText.isEmpty else { return all }
    return all.filter { Self.title(of: $0).localizedCaseInsensitiveContains(searchText) }
  }

  @ViewBuilder
  var conversations: some View {
    if channels.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "No Messages Yet" : "No Results",
        systemImage: "bubble.left.and.bubble.right"
      )
      .listRowBackground(Color.clear)
    } else {
      Section {
        ForEach(channels) { channel in
          Button {
            open(channel: channel.id)
          } label: {
            ConversationRow(channel: channel)
          }
          .tint(.primary)
        }
      }
    }
  }

  static func title(of channel: DiscordChannel) -> String {
    channel.name
      ?? channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
      ?? String(localized: "Unknown Conversation")
  }

  // MARK: Opening

  func open(channel: ChannelSnowflake) {
    // direct messages live under the "no server" selection
    appState.selectedGuild = nil
    appState.selectedChannel = channel
    withAnimation { appState.chatOpen = true }
  }

  /// Opens the existing DM with someone, or creates one.
  func open(user: UserSnowflake) {
    if let existing = gw.user.privateChannels.values.first(where: {
      $0.type == .dm && $0.recipients?.first?.id == user
    }) {
      open(channel: existing.id)
      return
    }
    Task {
      do {
        let res = try await gw.client.createDm(payload: .init(recipient: user))
        try res.guardSuccess()
        let channel = try res.decode()
        gw.user.privateChannels[channel.id] = channel
        open(channel: channel.id)
      } catch {
        appState.error = error
      }
    }
  }
}

/// One conversation in the list: avatar, name, unread dot and mention count.
struct ConversationRow: View {
  @Environment(\.gateway) var gw
  var channel: DiscordChannel

  var isUnread: Bool {
    gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id)
  }

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if channel.type == .dm, let user = channel.recipients?.first {
          Profile.AvatarWithPresence(member: nil, user: user)
            .profileAnimated(false)
            .profileShowsAvatarDecoration()
        } else if let icon = channel.icon {
          NukeImage(url: DiscordImageURL.channelIcon(id: channel.id, icon: icon))
            .resizable()
            .scaledToFill()
            .clipShape(.circle)
        } else {
          Circle()
            .fill(.secondary.opacity(0.25))
            .overlay {
              Image(systemName: "person.2.fill")
                .foregroundStyle(.secondary)
            }
        }
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(MessagesView.title(of: channel))
          .fontWeight(isUnread ? .semibold : .regular)
          .lineLimit(1)
        if channel.type == .groupDm, let count = channel.recipients?.count {
          Text("\(count + 1) members")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 4)

      let mentions = gw.readStates.mentionCount(channelId: channel.id)
      if mentions > 0 {
        MentionCountBadge(count: mentions)
      } else if isUnread {
        Circle()
          .fill(.tint)
          .frame(width: 9, height: 9)
          .accessibilityLabel(Text("Unread"))
      }
    }
    .contentShape(.rect)
  }
}

// MARK: - Friends

struct FriendsList: View {
  @Environment(\.gateway) var gw
  var searchText: String
  var open: (UserSnowflake) -> Void

  func matches(_ relationship: DiscordRelationship) -> Bool {
    guard !searchText.isEmpty else { return true }
    let user = relationship.user
    return [relationship.nickname, user.global_name, user.username]
      .compactMap { $0 }
      .contains { $0.localizedCaseInsensitiveContains(searchText) }
  }

  func isOnline(_ id: UserSnowflake) -> Bool {
    guard let status = gw.user.presence(id)?.status else { return false }
    return status != .offline && status != .invisible
  }

  func sorted(_ list: [DiscordRelationship]) -> [DiscordRelationship] {
    list.sorted {
      name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending
    }
  }

  func name(of relationship: DiscordRelationship) -> String {
    relationship.displayName
  }

  var body: some View {
    let all = gw.user.relationships.values.filter(matches)
    let friends = all.filter { $0.type == .friend }
    let online = sorted(friends.filter { isOnline($0.id) })
    let offline = sorted(friends.filter { !isOnline($0.id) })
    let pending = sorted(all.filter { $0.type == .incomingRequest || $0.type == .outgoingRequest })

    if friends.isEmpty && pending.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "No Friends Yet" : "No Results",
        systemImage: "person.2"
      )
      .listRowBackground(Color.clear)
    }
    if !pending.isEmpty {
      Section("Pending — \(pending.count)") {
        ForEach(pending, id: \.id) { relationship in
          FriendRow(
            relationship: relationship,
            subtitle: relationship.type == .incomingRequest
              ? String(localized: "Incoming friend request")
              : String(localized: "Outgoing friend request")
          )
        }
      }
    }
    if !online.isEmpty {
      Section("Online — \(online.count)") {
        ForEach(online, id: \.id) { relationship in
          Button { open(relationship.id) } label: {
            FriendRow(relationship: relationship, subtitle: activityLine(for: relationship.id))
          }
          .tint(.primary)
        }
      }
    }
    if !offline.isEmpty {
      Section("Offline — \(offline.count)") {
        ForEach(offline, id: \.id) { relationship in
          Button { open(relationship.id) } label: {
            FriendRow(relationship: relationship, subtitle: nil)
          }
          .tint(.primary)
        }
      }
    }
  }

  /// "Playing …" or the custom status, like Discord's "Active Now".
  func activityLine(for id: UserSnowflake) -> String? {
    guard let activities = gw.user.presence(id)?.activities else { return nil }
    if let game = activities.first(where: { $0.type != .custom }), let name = game.name {
      switch game.type {
      case .listening: return String(localized: "Listening to \(name)")
      case .watching: return String(localized: "Watching \(name)")
      case .streaming: return String(localized: "Streaming \(name)")
      case .competing: return String(localized: "Competing in \(name)")
      default: return String(localized: "Playing \(name)")
      }
    }
    return activities.first(where: { $0.type == .custom })?.state
  }
}

struct FriendRow: View {
  var relationship: DiscordRelationship
  var subtitle: String?

  var body: some View {
    HStack(spacing: 12) {
      Profile.AvatarWithPresence(member: nil, user: relationship.user)
        .profileAnimated(false)
        .profileShowsAvatarDecoration()
        .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(relationship.displayName)
          .lineLimit(1)
        Text(subtitle ?? "@\(relationship.user.username ?? "")")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .contentShape(.rect)
  }
}

// MARK: - New message

struct NewMessageSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss
  var open: (UserSnowflake) -> Void
  @State var searchText = ""

  var friends: [DiscordRelationship] {
    gw.user.relationships.values
      .filter { $0.type == .friend }
      .filter {
        searchText.isEmpty
          || $0.displayName.localizedCaseInsensitiveContains(searchText)
          || ($0.user.username ?? "").localizedCaseInsensitiveContains(searchText)
      }
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
  }

  var body: some View {
    NavigationStack {
      List(friends, id: \.id) { relationship in
        Button {
          dismiss()
          open(relationship.id)
        } label: {
          FriendRow(relationship: relationship, subtitle: nil)
        }
        .tint(.primary)
      }
      .overlay {
        if friends.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }
      }
      .navigationTitle("New Message")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "To:")
      #else
        .searchable(text: $searchText, prompt: "To:")
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
    }
  }
}
extension DiscordRelationship {
  /// Friend nickname, then display name, then username.
  var displayName: String {
    nickname ?? user.global_name ?? user.username ?? String(localized: "Unknown User")
  }
}
