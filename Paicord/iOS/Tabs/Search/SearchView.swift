//
//  SearchView.swift
//  Aicord
//
//  One search field for servers, channels, people and messages. Picking a server,
//  channel or person turns it into a filter token, so each step narrows the next
//  without forcing you to start from the server.
//

import PaicordLib
import SwiftUI

struct SearchView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  /// Called after a channel is selected, so the tab bar can show the chat.
  var onOpen: () -> Void

  @State var text = ""
  @State var tokens: [SearchToken] = []
  @State var has: Set<HasFilter> = []
  @State var messages = MessageResults()
  @State var searchTask: Task<Void, Never>? = nil

  var serverID: GuildSnowflake? {
    for token in tokens {
      switch token {
      case .server(let id): return id
      case .channel(let guild, _): if let guild { return guild }
      default: continue
      }
    }
    return nil
  }
  var channelID: ChannelSnowflake? {
    tokens.lazy.compactMap { if case .channel(_, let id) = $0 { id } else { nil } }.first
  }
  var userID: UserSnowflake? {
    tokens.lazy.compactMap { if case .user(let id) = $0 { id } else { nil } }.first
  }

  var query: String { text.trimmingCharacters(in: .whitespaces) }

  var body: some View {
    NavigationStack {
      List {
        if query.isEmpty && tokens.isEmpty {
          tips
        } else {
          serverResults
          channelResults
          peopleResults
          messageResults
        }
      }
      .navigationTitle("Search")
      .searchable(text: $text, tokens: $tokens, placement: Self.fieldPlacement, prompt: prompt) {
        token in
        Label(token.title(gw), systemImage: token.symbol)
      }
      .onSubmit(of: .search) { runMessageSearch(debounce: false) }
      .onChange(of: text) { _, _ in runMessageSearch(debounce: true); requestMembers() }
      .onChange(of: tokens) { _, _ in runMessageSearch(debounce: false) }
      .onChange(of: has) { _, _ in runMessageSearch(debounce: false) }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            ForEach(HasFilter.allCases) { filter in
              Toggle(isOn: Binding(
                get: { has.contains(filter) },
                set: { on in if on { has.insert(filter) } else { has.remove(filter) } }
              )) {
                Label(filter.title, systemImage: filter.symbol)
              }
            }
          } label: {
            Label("Filters", systemImage: has.isEmpty
              ? "line.3.horizontal.decrease.circle"
              : "line.3.horizontal.decrease.circle.fill")
          }
        }
      }
    }
  }

  #if os(iOS)
    static let fieldPlacement = SearchFieldPlacement.navigationBarDrawer(displayMode: .always)
  #else
    static let fieldPlacement = SearchFieldPlacement.automatic
  #endif

  var prompt: LocalizedStringKey {
    if channelID != nil { return "Search this channel" }
    if serverID != nil { return "Search this server" }
    return "Servers, channels, people, messages"
  }

  // MARK: - Tips

  var tips: some View {
    Section {
      Label("Type part of a server name, like “kao”.", systemImage: "square.stack.3d.up")
      Label("Tap a server, channel or person to search inside it.", systemImage: "line.3.horizontal.decrease")
      Label("Messages need a server, channel or person to search in.", systemImage: "text.bubble")
    } header: {
      Text("How Search Works")
    }
    .foregroundStyle(.secondary)
  }

  // MARK: - Servers

  @ViewBuilder
  var serverResults: some View {
    if serverID == nil, !query.isEmpty {
      let matches = gw.user.guilds.values
        .filter { $0.name.localizedCaseInsensitiveContains(query) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .prefix(6)
      if !matches.isEmpty {
        Section("Servers") {
          ForEach(Array(matches), id: \.id) { guild in
            ResultRow(
              title: guild.name,
              subtitle: nil,
              open: { open(guild: guild.id, channel: nil) }
            ) {
              ServerIcon(guild: guild)
            } narrow: {
              narrow(to: .server(guild.id))
            }
          }
        }
      }
    }
  }

  // MARK: - Channels

  static let searchableChannelTypes: Set<DiscordChannel.Kind> = [
    .guildText, .guildAnnouncement, .guildForum, .guildMedia, .guildVoice, .guildStageVoice,
  ]

  func channels(in guild: Guild) -> [DiscordChannel] {
    (gw.user.guilds[guild.id]?.channels ?? [])
      .filter { $0.type.map(Self.searchableChannelTypes.contains) ?? false }
  }

  @ViewBuilder
  var channelResults: some View {
    if channelID == nil, !query.isEmpty || serverID != nil {
      let guilds = serverID.flatMap { gw.user.guilds[$0] }.map { [$0] } ?? Array(gw.user.guilds.values)
      let matches = guilds.flatMap { guild in
        channels(in: guild)
          .filter { query.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(query) }
          .map { (guild, $0) }
      }
      .sorted { ($0.1.position ?? 0) < ($1.1.position ?? 0) }
      .prefix(serverID == nil ? 8 : 12)
      if !matches.isEmpty {
        Section("Channels") {
          ForEach(Array(matches), id: \.1.id) { guild, channel in
            ResultRow(
              title: channel.name ?? "",
              subtitle: serverID == nil ? guild.name : nil,
              open: { open(guild: guild.id, channel: channel.id) }
            ) {
              Image(systemName: ChannelButton.symbol(for: channel.type))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
            } narrow: {
              narrow(to: .channel(guild.id, channel.id))
            }
          }
        }
      }
    }
  }

  // MARK: - People

  struct Person: Identifiable {
    var id: UserSnowflake
    var name: String
    var username: String
    var user: PartialUser
  }

  var people: [Person] {
    var found: [UserSnowflake: Person] = [:]
    func add(_ user: PartialUser?, nick: String? = nil) {
      guard let user, let username = user.username, found[user.id] == nil else { return }
      let name = nick ?? user.global_name ?? username
      guard [name, username, user.global_name ?? ""].contains(where: {
        $0.localizedCaseInsensitiveContains(query)
      }) else { return }
      found[user.id] = Person(id: user.id, name: name, username: username, user: user)
    }
    if let serverID {
      for member in gw.getGuildStore(for: serverID).loadedMembers {
        add(member.user?.toPartialUser(), nick: member.nick)
      }
    } else {
      for relationship in gw.user.relationships.values where relationship.type == .friend {
        add(relationship.user, nick: relationship.nickname)
      }
      for channel in gw.user.privateChannels.values {
        for recipient in channel.recipients ?? [] { add(recipient.toPartialUser()) }
      }
      for user in gw.user.users.values { add(user) }
    }
    return found.values.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  @ViewBuilder
  var peopleResults: some View {
    if userID == nil, !query.isEmpty {
      let matches = people.prefix(8)
      if !matches.isEmpty {
        Section("People") {
          ForEach(Array(matches)) { person in
            ResultRow(
              title: person.name,
              subtitle: "@\(person.username)",
              open: { openDM(with: person.id) }
            ) {
              Profile.AvatarWithPresence(member: nil, user: person.user)
                .profileAnimated(false)
                .frame(width: 32, height: 32)
            } narrow: {
              narrow(to: .user(person.id))
            }
          }
        }
      }
    }
  }

  /// Asks the gateway for members matching the text, since only some are loaded.
  func requestMembers() {
    guard let serverID, query.count >= 2 else { return }
    let payload = Gateway.RequestGuildMembers(guild_id: serverID, query: query, limit: 10)
    Task { await gw.gateway?.requestGuildMembersChunk(payload: payload) }
  }

  // MARK: - Messages

  struct MessageResults {
    var items: [DiscordChannel.Message] = []
    var total = 0
    var loading = false
    var indexing = false
    var failed = false
  }

  /// Where messages can be searched with the current tokens, if anywhere.
  enum MessageScope {
    case guild(GuildSnowflake)
    case channel(ChannelSnowflake)
  }

  var messageScope: MessageScope? {
    if let serverID { return .guild(serverID) }
    if let userID,
      let dm = gw.user.privateChannels.values.first(where: {
        $0.type == .dm && $0.recipients?.first?.id == userID
      })
    {
      return .channel(dm.id)
    }
    return nil
  }

  var hasMessageCriteria: Bool {
    !query.isEmpty || userID != nil || channelID != nil || !has.isEmpty
  }

  @ViewBuilder
  var messageResults: some View {
    if hasMessageCriteria {
      Section {
        if messageScope == nil {
          Label(
            userID != nil
              ? "You have no direct messages with this person. Add a server to search there."
              : "Pick a server, channel or person above to search messages.",
            systemImage: "text.magnifyingglass"
          )
          .foregroundStyle(.secondary)
        } else if messages.indexing {
          Label("Discord is still indexing this server. Try again in a moment.", systemImage: "hourglass")
            .foregroundStyle(.secondary)
        } else if messages.failed {
          Label("Search didn't work. Try again.", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if messages.loading && messages.items.isEmpty {
          HStack { Spacer(); ProgressView(); Spacer() }
        } else if messages.items.isEmpty {
          Text("No messages found.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(messages.items, id: \.id) { message in
            Button {
              open(guild: message.guild_id ?? serverID, channel: message.channel_id)
            } label: {
              MessageResultRow(message: message, channelName: channelName(for: message))
            }
            .tint(.primary)
          }
          if messages.items.count < messages.total {
            Button("Show More") { loadMoreMessages() }
              .disabled(messages.loading)
          }
        }
      } header: {
        if messageScope != nil, messages.total > 0 {
          Text("Messages — \(messages.total)")
        } else {
          Text("Messages")
        }
      }
    }
  }

  func channelName(for message: DiscordChannel.Message) -> String? {
    guard let guild = message.guild_id ?? serverID,
      let channel = gw.user.guilds[guild]?.channels?.first(where: { $0.id == message.channel_id })
    else { return nil }
    return channel.name
  }

  func makeQuery(offset: Int) -> MessageSearchQuery {
    MessageSearchQuery(
      content: query.isEmpty ? nil : query,
      channelIDs: channelID.map { [$0] } ?? [],
      authorIDs: userID.map { [$0] } ?? [],
      has: has.map(\.rawValue).sorted(),
      offset: offset
    )
  }

  func runMessageSearch(debounce: Bool) {
    searchTask?.cancel()
    guard hasMessageCriteria, let scope = messageScope else {
      messages = MessageResults()
      return
    }
    searchTask = Task {
      if debounce {
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
      }
      messages = MessageResults(loading: true)
      messages = await fetchMessages(scope: scope, offset: 0, into: MessageResults())
    }
  }

  func loadMoreMessages() {
    guard let scope = messageScope else { return }
    let current = messages
    searchTask = Task {
      messages.loading = true
      messages = await fetchMessages(scope: scope, offset: current.items.count, into: current)
    }
  }

  func fetchMessages(scope: MessageScope, offset: Int, into current: MessageResults) async
    -> MessageResults
  {
    var result = current
    result.loading = false
    do {
      let query = makeQuery(offset: offset)
      let res: DiscordClientResponse<MessageSearchResults>
      switch scope {
      case .guild(let id): res = try await gw.client.searchGuildMessages(guildID: id, query: query)
      case .channel(let id): res = try await gw.client.searchChannelMessages(channelID: id, query: query)
      }
      guard !Task.isCancelled else { return current }
      if res.httpResponse.status == .accepted {
        result.indexing = true
        return result
      }
      try res.guardSuccess()
      let page = try res.decode()
      result.total = page.total_results
      // each inner array holds the match first; extra entries are context
      result.items += page.messages.compactMap(\.first)
    } catch {
      result.failed = !Task.isCancelled
    }
    return result
  }

  // MARK: - Actions

  func narrow(to token: SearchToken) {
    // a channel implies its server, so drop a separate server token
    if case .channel = token { tokens.removeAll { if case .server = $0 { true } else { false } } }
    tokens.removeAll { $0.kind == token.kind }
    tokens.append(token)
    text = ""
  }

  func open(guild: GuildSnowflake?, channel: ChannelSnowflake?) {
    appState.selectedGuild = guild
    if let channel { appState.selectedChannel = channel }
    onOpen()
  }

  func openDM(with user: UserSnowflake) {
    if let dm = gw.user.privateChannels.values.first(where: {
      $0.type == .dm && $0.recipients?.first?.id == user
    }) {
      open(guild: nil, channel: dm.id)
      return
    }
    Task {
      do {
        let res = try await gw.client.createDm(payload: .init(recipient: user))
        try res.guardSuccess()
        let channel = try res.decode()
        gw.user.privateChannels[channel.id] = channel
        open(guild: nil, channel: channel.id)
      } catch {
        appState.error = error
      }
    }
  }
}

// MARK: - Tokens and filters

enum SearchToken: Identifiable, Hashable {
  case server(GuildSnowflake)
  case channel(GuildSnowflake?, ChannelSnowflake)
  case user(UserSnowflake)

  var id: String {
    switch self {
    case .server(let id): "server-\(id.rawValue)"
    case .channel(_, let id): "channel-\(id.rawValue)"
    case .user(let id): "user-\(id.rawValue)"
    }
  }

  enum Kind { case server, channel, user }
  var kind: Kind {
    switch self {
    case .server: .server
    case .channel: .channel
    case .user: .user
    }
  }

  var symbol: String {
    switch self {
    case .server: "square.stack.3d.up"
    case .channel: "number"
    case .user: "person"
    }
  }

  @MainActor
  func title(_ gw: GatewayStore) -> String {
    switch self {
    case .server(let id):
      return gw.user.guilds[id]?.name ?? String(localized: "Server")
    case .channel(let guild, let id):
      let channel = guild.flatMap { gw.user.guilds[$0]?.channels?.first { $0.id == id } }
      return channel?.name ?? String(localized: "Channel")
    case .user(let id):
      let user = gw.user.users[id]
      return user?.global_name ?? user?.username ?? String(localized: "Person")
    }
  }
}

enum HasFilter: String, CaseIterable, Identifiable, Hashable {
  case link, image, video, file, embed, sound, sticker, poll
  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .link: "Link"
    case .image: "Image"
    case .video: "Video"
    case .file: "File"
    case .embed: "Embed"
    case .sound: "Audio"
    case .sticker: "Sticker"
    case .poll: "Poll"
    }
  }

  var symbol: String {
    switch self {
    case .link: "link"
    case .image: "photo"
    case .video: "film"
    case .file: "doc"
    case .embed: "rectangle.text.magnifyingglass"
    case .sound: "waveform"
    case .sticker: "face.smiling"
    case .poll: "chart.bar"
    }
  }
}

// MARK: - Rows

/// Tapping the row narrows the search to it; the arrow opens it.
struct ResultRow<Icon: View>: View {
  var title: String
  var subtitle: String?
  var open: () -> Void
  @ViewBuilder var icon: () -> Icon
  var narrow: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button(action: narrow) {
        HStack(spacing: 12) {
          icon()
          VStack(alignment: .leading, spacing: 1) {
            Text(title).lineLimit(1)
            if let subtitle {
              Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 0)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityHint(Text("Searches inside this"))

      Button(action: open) {
        Image(systemName: "arrow.up.forward.circle.fill")
          .font(.title3)
          .symbolRenderingMode(.hierarchical)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text("Open"))
    }
  }
}

struct ServerIcon: View {
  var guild: Guild

  var body: some View {
    Group {
      if let icon = guild.icon {
        NukeImage(url: DiscordImageURL.guildIcon(id: guild.id, icon: icon, animated: false))
          .resizable()
          .scaledToFill()
      } else {
        Text(guild.name.prefix(2))
          .font(.caption.bold())
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.secondary.opacity(0.2))
      }
    }
    .frame(width: 32, height: 32)
    .clipShape(.rect(cornerRadius: 9, style: .continuous))
  }
}

struct MessageResultRow: View {
  @Environment(\.gateway) var gw
  var message: DiscordChannel.Message
  var channelName: String?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if let author = message.author {
        Profile.Avatar(member: nil, user: author.toPartialUser())
          .frame(width: 32, height: 32)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(message.author?.global_name ?? message.author?.username ?? "")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          if let channelName {
            Text("#\(channelName)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 4)
          Text(message.timestamp.date, format: .dateTime.day().month(.abbreviated).year())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if WordFilter.hides(message.content, origin: gw.origin(of: message)) {
          HiddenContentNote(text: "Hidden by your word filter")
        } else if !message.content.isEmpty {
          Text(message.content)
            .font(.subheadline)
            .lineLimit(4)
        } else if !message.attachments.isEmpty {
          Label("\(message.attachments.count) attachment(s)", systemImage: "paperclip")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .contentShape(.rect)
  }
}
