//
//  MessagesView.swift
//  Aicord
//
//  The iPhone Messages tab: direct messages, group chats and friends,
//  kept apart from the server list on the Home tab.
//

import AicordKit
import SwiftUI

struct MessagesView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  enum Page: Hashable { case messages, mentions }
  @State var page: Page = .messages
  @State var searchText = ""
  @State var composing = false
  @State var showingFriends = false

  var body: some View {
    NavigationStack {
      List {
        Picker("Show", selection: $page) {
          Text("Messages").tag(Page.messages)
          Text("Mentions").tag(Page.mentions)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        switch page {
        case .messages:
          if searchText.isEmpty { folders }
          conversations
        case .mentions: MentionsList(searchText: searchText, open: open(guild:channel:))
        }
      }
      .navigationTitle("Messages")
      .searchable(text: $searchText, prompt: page == .messages ? "Find a conversation" : "Filter mentions")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showingFriends = true
          } label: {
            Label("Friends", systemImage: "person.2")
          }
          .badge(pendingRequests)
        }
        ToolbarItem(placement: .primaryAction) {
          Button {
            composing = true
          } label: {
            Label("New Message", systemImage: "square.and.pencil")
          }
        }
      }
      .navigationDestination(for: MessageFolder.self) { folder in
        MessageFolderView(folder: folder, open: open(channel:))
      }
      .sheet(isPresented: $composing) {
        NewMessageSheet(open: open(user:))
      }
      .sheet(isPresented: $showingFriends) {
        FriendsSheet(open: open(user:))
      }
    }
  }

  // MARK: Conversations

  /// Your conversations; requests and spam have their own folders.
  var channels: [DiscordChannel] {
    let all = gw.user.privateChannels.values
      .filter { !$0.isPendingMessageRequest && !$0.isSpam }
      .sorted {
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

  /// Rows for the Requests and Spam folders above the conversations.
  var folders: some View {
    Section {
      ForEach(MessageFolder.allCases) { folder in
        let count =
          folder == .requests ? gw.user.messageRequests().count : gw.user.spamChannels.count
        NavigationLink(value: folder) {
          Label {
            HStack {
              Text(folder.title)
              Spacer()
              if count > 0 {
                Text("\(count)")
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
              }
            }
          } icon: {
            Image(systemName: folder.symbol)
          }
        }
      }
    }
  }

  static func title(of channel: DiscordChannel) -> String {
    channel.name
      ?? channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
      ?? String(localized: "Unknown Conversation")
  }

  var pendingRequests: Int { gw.user.incomingFriendRequestCount }

  // MARK: Opening

  func open(guild: GuildSnowflake?, channel: ChannelSnowflake) {
    appState.selectedGuild = guild
    appState.selectedChannel = channel
    withAnimation { appState.chatOpen = true }
  }

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

extension CurrentUserStore {
  /// Incoming friend requests worth a badge: not from people you ignored, not
  /// ones Discord marked as likely spam.
  var incomingFriendRequestCount: Int {
    relationships.values.filter {
      $0.type == .incomingRequest && !$0.user_ignored && $0.is_spam_request != true
    }.count
  }
}

struct FriendsList: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  var page: FriendsPage
  var searchText: String
  var open: (UserSnowflake) -> Void

  /// The request waiting for confirmation; the sheet shows the dialog.
  @Binding var pendingRemoval: DiscordRelationship?

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

  /// Requests newest first, like Discord.
  func byDate(_ list: [DiscordRelationship]) -> [DiscordRelationship] {
    list.sorted { ($0.since?.date ?? .distantPast) > ($1.since?.date ?? .distantPast) }
  }

  func name(of relationship: DiscordRelationship) -> String {
    relationship.displayName
  }

  var body: some View {
    let all = gw.user.relationships.values.filter(matches)
    switch page {
    case .friends: friends(all.filter { $0.type == .friend })
    case .incoming: incoming(all.filter { $0.type == .incomingRequest })
    case .sent: sent(all.filter { $0.type == .outgoingRequest })
    }
  }

  @ViewBuilder
  func friends(_ friends: [DiscordRelationship]) -> some View {
    let online = sorted(friends.filter { isOnline($0.id) })
    let offline = sorted(friends.filter { !isOnline($0.id) })
    if friends.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "No Friends Yet" : "No Results",
        systemImage: "person.2"
      )
      .listRowBackground(Color.clear)
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

  @ViewBuilder
  func incoming(_ requests: [DiscordRelationship]) -> some View {
    let likelySpam = byDate(requests.filter { $0.is_spam_request == true || $0.user_ignored })
    let regular = byDate(requests.filter { $0.is_spam_request != true && !$0.user_ignored })
    if requests.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "No Friend Requests" : "No Results",
        systemImage: "person.badge.plus",
        description: searchText.isEmpty ? Text("Requests people send you show up here.") : nil
      )
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    }
    if !regular.isEmpty {
      Section("Received — \(regular.count)") {
        ForEach(regular, id: \.id) { incomingRow($0) }
      }
    }
    if !likelySpam.isEmpty {
      Section {
        ForEach(likelySpam, id: \.id) { incomingRow($0) }
      } header: {
        Text("Ignored or Likely Spam — \(likelySpam.count)")
      } footer: {
        Text("These don't count towards the badge.")
      }
    }
  }

  @ViewBuilder
  func sent(_ requests: [DiscordRelationship]) -> some View {
    if requests.isEmpty {
      ContentUnavailableView(
        searchText.isEmpty ? "No Sent Requests" : "No Results",
        systemImage: "paperplane",
        description: searchText.isEmpty
          ? Text("Friend requests you send stay here until they're accepted.") : nil
      )
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
    } else {
      Section("Sent — \(requests.count)") {
        ForEach(byDate(requests), id: \.id) { relationship in
          FriendRow(relationship: relationship, subtitle: sentLine(for: relationship)) {
            RequestButton(title: "Cancel Request", symbol: "xmark", role: .destructive) {
              pendingRemoval = relationship
            }
          }
          .swipeActions {
            Button("Cancel", systemImage: "xmark", role: .destructive) {
              pendingRemoval = relationship
            }
          }
        }
      }
    }
  }

  func incomingRow(_ relationship: DiscordRelationship) -> some View {
    FriendRow(relationship: relationship, subtitle: receivedLine(for: relationship)) {
      RequestButton(title: "Ignore", symbol: "xmark", role: .destructive) {
        pendingRemoval = relationship
      }
      RequestButton(title: "Accept", symbol: "checkmark", role: nil) {
        Task { await accept(relationship) }
      }
    }
    .swipeActions(edge: .leading) {
      Button("Accept", systemImage: "checkmark") {
        Task { await accept(relationship) }
      }
      .tint(.green)
    }
    .swipeActions(edge: .trailing) {
      Button("Ignore", systemImage: "xmark", role: .destructive) {
        pendingRemoval = relationship
      }
    }
  }

  func receivedLine(for relationship: DiscordRelationship) -> String {
    guard let since = relationship.since?.date else {
      return String(localized: "Incoming friend request")
    }
    return String(localized: "Sent you a request \(since.formatted(.relative(presentation: .named)))")
  }

  func sentLine(for relationship: DiscordRelationship) -> String {
    guard let since = relationship.since?.date else {
      return String(localized: "Outgoing friend request")
    }
    return String(localized: "Sent \(since.formatted(.relative(presentation: .named)))")
  }

  /// Creating the relationship without a type accepts the pending request.
  func accept(_ relationship: DiscordRelationship) async {
    do {
      try await gw.client.createRelationship(
        userID: relationship.id,
        payload: .init(type: nil)
      ).guardSuccess()
    } catch {
      appState.error = error
    }
  }

  /// Declines an incoming request or cancels a sent one; Relationship Remove follows.
  static func remove(_ relationship: DiscordRelationship, gw: GatewayStore, appState: AicordAppState) async {
    do {
      try await gw.client.removeRelationship(userID: relationship.id).guardSuccess()
      gw.user.relationships.removeValue(forKey: relationship.id)
    } catch {
      appState.error = error
    }
  }

  /// Confirms before a request goes, like Discord.
  struct RemovalDialog: ViewModifier {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @Binding var pending: DiscordRelationship?

    func body(content: Content) -> some View {
      content.confirmationDialog(
        pending?.type == .outgoingRequest
          ? "Cancel your friend request to \(pending?.displayName ?? "")?"
          : "Ignore the friend request from \(pending?.displayName ?? "")?",
        isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
        titleVisibility: .visible,
        presenting: pending
      ) { relationship in
        Button(
          relationship.type == .outgoingRequest ? "Cancel Request" : "Ignore Request",
          role: .destructive
        ) {
          Task { await FriendsList.remove(relationship, gw: gw, appState: appState) }
        }
      } message: { relationship in
        Text(
          relationship.type == .outgoingRequest
            ? "They won't be told. You can send another request later."
            : "They won't be told. They can send another request later."
        )
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

enum FriendsPage: Hashable, CaseIterable {
  case friends, incoming, sent
}

/// The round accept, ignore and cancel buttons on a request row.
private struct RequestButton: View {
  var title: LocalizedStringKey
  var symbol: String
  var role: ButtonRole?
  var action: () -> Void

  var body: some View {
    Button(role: role, action: action) {
      Image(systemName: symbol)
        .font(.body.weight(.semibold))
        .frame(width: 34, height: 34)
        .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.green))
        .background(.secondary.opacity(0.15), in: .circle)
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(Text(title))
  }
}

struct FriendRow<Accessory: View>: View {
  var relationship: DiscordRelationship
  var subtitle: String?
  @ViewBuilder var accessory: () -> Accessory

  init(
    relationship: DiscordRelationship,
    subtitle: String?,
    @ViewBuilder accessory: @escaping () -> Accessory
  ) {
    self.relationship = relationship
    self.subtitle = subtitle
    self.accessory = accessory
  }

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
      accessory()
    }
    .contentShape(.rect)
  }
}

extension FriendRow where Accessory == EmptyView {
  init(relationship: DiscordRelationship, subtitle: String?) {
    self.init(relationship: relationship, subtitle: subtitle) { EmptyView() }
  }
}

/// Friends in a sheet, opened from the toolbar.
struct FriendsSheet: View {
  var incoming: Int { gw.user.incomingFriendRequestCount }

  @Environment(\.dismiss) var dismiss
  var open: (UserSnowflake) -> Void
  @State var searchText = ""
  @State var page: FriendsPage = .friends
  @State var pendingRemoval: DiscordRelationship? = nil
  @State var addingFriend = false
  @Environment(\.gateway) var gw

  var body: some View {
    NavigationStack {
      List {
        Picker("Show", selection: $page) {
          Text("Friends").tag(FriendsPage.friends)
          Text(incoming > 0 ? "Incoming (\(incoming))" : "Incoming").tag(FriendsPage.incoming)
          Text("Sent").tag(FriendsPage.sent)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        Section {
          Button("Add Friend", systemImage: "person.badge.plus") { addingFriend = true }
        }

        FriendsList(
          page: page,
          searchText: searchText,
          open: { user in
            dismiss()
            open(user)
          },
          pendingRemoval: $pendingRemoval
        )
      }
      .modifier(FriendsList.RemovalDialog(pending: $pendingRemoval))
      .sheetErrorAlert()
      .navigationTitle("Friends")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .searchable(text: $searchText, prompt: "Find a friend")
      .onAppear {
        // open on the requests when there are some to answer
        if incoming > 0 { page = .incoming }
      }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $addingFriend) {
        AddFriendSheet()
      }
    }
  }
}

// MARK: - Mentions

struct MentionsList: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  var searchText: String
  var open: (GuildSnowflake?, ChannelSnowflake) -> Void

  @AppStorage("Aicord.Mentions.OnlyReplies") var onlyReplies = false
  @AppStorage("Aicord.Mentions.IncludeEveryone") var includeEveryone = true

  @State var mentions: [DiscordChannel.Message] = []
  @State var loading = false
  @State var reachedEnd = false
  @State var failed = false

  var me: UserSnowflake? { gw.user.currentUser?.id }

  var visible: [DiscordChannel.Message] {
    mentions.filter { message in
      if onlyReplies, message.referenced_message?.value.author?.id != me { return false }
      guard !searchText.isEmpty else { return true }
      return message.content.localizedCaseInsensitiveContains(searchText)
        || (message.author?.username ?? "").localizedCaseInsensitiveContains(searchText)
        || (message.author?.global_name ?? "").localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    Section {
      Toggle("Only Replies to Me", isOn: $onlyReplies)
      Toggle("Include @everyone and @here", isOn: $includeEveryone)
    }
    .onChange(of: includeEveryone) { _, _ in Task { await reload() } }

    Section {
      if visible.isEmpty && !loading {
        ContentUnavailableView(
          failed ? "Couldn't Load Mentions" : "No Mentions",
          systemImage: failed ? "exclamationmark.triangle" : "at",
          description: failed ? nil : Text("When someone mentions or replies to you, it shows up here.")
        )
      }
      ForEach(visible, id: \.id) { message in
        Button {
          open(guildID(for: message), message.channel_id)
        } label: {
          MentionRow(message: message)
        }
        .tint(.primary)
      }
      if loading {
        HStack { Spacer(); ProgressView(); Spacer() }
      } else if !reachedEnd && !mentions.isEmpty {
        Button("Show Older") { Task { await loadMore() } }
      }
    } header: {
      HStack {
        Text("Recent")
        Spacer()
        if hasUnread {
          Button("Mark All as Read") { Task { await markAllRead() } }
            .font(.caption.weight(.semibold))
            .textCase(nil)
        }
      }
    }
    .task { if mentions.isEmpty { await reload() } }
    .refreshable { await reload() }
  }

  func guildID(for message: DiscordChannel.Message) -> GuildSnowflake? {
    message.guild_id
      ?? gw.user.guilds.values.first { $0.channels?.contains { $0.id == message.channel_id } == true }?.id
  }

  var hasUnread: Bool {
    Set(mentions.map(\.channel_id)).contains { gw.readStates.mentionCount(channelId: $0) > 0 }
  }

  func reload() async {
    mentions = []
    reachedEnd = false
    await loadMore()
  }

  func loadMore() async {
    guard !loading else { return }
    loading = true
    failed = false
    defer { loading = false }
    do {
      let res = try await gw.client.getRecentMentions(
        before: mentions.last?.id,
        includeEveryone: includeEveryone
      )
      try res.guardSuccess()
      let page = try res.decode()
      mentions += page
      reachedEnd = page.count < 25
    } catch {
      failed = true
    }
  }

  /// Acks the newest mention in each channel that still has unread mentions.
  func markAllRead() async {
    var newest: [ChannelSnowflake: MessageSnowflake] = [:]
    for message in mentions where newest[message.channel_id] == nil {
      newest[message.channel_id] = message.id
    }
    for (channel, message) in newest where gw.readStates.mentionCount(channelId: channel) > 0 {
      do {
        try await gw.client.acknowledgeMessage(
          channelId: channel, messageId: message, payload: Payloads.AcknowledgeMessage()
        ).guardSuccess()
        gw.readStates.applyAck(channelId: channel, messageId: message)
      } catch {
        appState.error = error
        return
      }
    }
  }
}

struct MentionRow: View {
  @Environment(\.gateway) var gw
  var message: DiscordChannel.Message

  /// The server, from the message or by finding which server owns the channel.
  var guild: Guild? {
    if let id = message.guild_id, let guild = gw.user.guilds[id] { return guild }
    return gw.user.guilds.values.first { $0.channels?.contains { $0.id == message.channel_id } == true }
  }

  var place: String {
    if let guild {
      let channel = guild.channels?.first { $0.id == message.channel_id }?.name
      return [guild.name, channel.map { "#\($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
    if let dm = gw.user.privateChannels[message.channel_id] {
      return MessagesView.title(of: dm)
    }
    return ""
  }

  var isUnread: Bool {
    gw.readStates.isUnread(channelId: message.channel_id, lastMessageId: message.id)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if let author = message.author {
        Profile.Avatar(member: nil, user: author.toPartialUser())
          .frame(width: 36, height: 36)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(message.author?.global_name ?? message.author?.username ?? "")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(message.timestamp.date, format: .relative(presentation: .numeric))
            .font(.caption)
            .foregroundStyle(.secondary)
          if isUnread {
            Circle().fill(.tint).frame(width: 8, height: 8)
          }
        }
        if !place.isEmpty {
          Text(place)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if WordFilter.hides(message.content, origin: gw.origin(of: message)) {
          HiddenContentNote(text: "Hidden by your word filter")
        } else {
          Text(message.content.isEmpty ? String(localized: "Attachment") : message.content)
            .font(.subheadline)
            .lineLimit(3)
        }
      }
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
