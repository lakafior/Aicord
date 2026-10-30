//
//  SearchView.swift
//  Aicord
//
//  One search field for servers, channels, people and messages. Picking a server,
//  channel or person turns it into a filter token, so each step narrows the next
//  without forcing you to start from the server.
//

import AicordKit
import SwiftUI

struct SearchView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  /// Called after a channel is selected, so the tab bar can show the chat.
  var onOpen: () -> Void
  /// Shows a Done button, for Search in a sheet on Mac and iPad.
  var onClose: (() -> Void)? = nil

  @State var text = ""
  @State var tokens: [SearchToken] = []
  @State var has: Set<HasFilter> = []
  @State var messages = MessageResults()
  @State var searchTask: Task<Void, Never>? = nil
  @State var filters = MessageFilters()
  @State var showingFilters = false
  @State var interpreting = false
  @State var sentenceTask: Task<Void, Never>? = nil
  /// The sentence results are ranked against, while the keywords it gave stay.
  @State var rankingSentence: String? = nil
  @State var rankedText: String? = nil
  @State var relevanceOrder: [MessageSnowflake]? = nil
  @State var sortByRelevance = true

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
          if looksLikeSentence {
            Section {
              Button {
                searchWithSentence()
              } label: {
                HStack {
                  Label("Search with a Sentence", systemImage: "sparkles")
                  if interpreting {
                    Spacer()
                    ProgressView()
                  }
                }
              }
              .disabled(interpreting)
            } footer: {
              Text("Turns what you wrote into a server, channel, person, dates and keywords. Only the sentence goes to the language model.")
            }
          }
          serverResults
          channelResults
          peopleResults
          activeFilters
          messageResults
        }
      }
      .navigationTitle("Search")
      .searchable(text: $text, tokens: $tokens, placement: Self.fieldPlacement, prompt: prompt) {
        token in
        Label(token.title(gw), systemImage: token.symbol)
      }
      .task(id: RankingKey(sentence: ranking ? rankingSentence : nil, ids: messages.items.map(\.id))) {
        await rankResults()
      }
      .onSubmit(of: .search) { runMessageSearch(debounce: false) }
      .onChange(of: text) { _, _ in runMessageSearch(debounce: true); requestMembers() }
      .onChange(of: tokens) { _, _ in runMessageSearch(debounce: false) }
      .onChange(of: has) { _, _ in runMessageSearch(debounce: false) }
      .onChange(of: filters.dateRange) { _, _ in runMessageSearch(debounce: false) }
      .onChange(of: filters.pattern) { old, new in
        // the pattern filters loaded results; only starting or clearing it refetches
        if old.isEmpty != new.isEmpty { runMessageSearch(debounce: true) }
      }
      .sheet(isPresented: $showingFilters) {
        MessageFiltersSheet(filters: $filters)
      }
      .toolbar {
        if let onClose {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done", action: onClose)
          }
        }
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button {
              searchWithSentence()
            } label: {
              Label("Search with a Sentence", systemImage: "sparkles")
            }
            .disabled(!looksLikeSentence || interpreting)
            Divider()
            Button {
            showingFilters = true
          } label: {
            Label("Dates and Regex…", systemImage: "calendar.badge.clock")
          }
          Divider()
          ForEach(HasFilter.allCases) { filter in
              Toggle(isOn: Binding(
                get: { has.contains(filter) },
                set: { on in if on { has.insert(filter) } else { has.remove(filter) } }
              )) {
                Label(filter.title, systemImage: filter.symbol)
              }
            }
          } label: {
            if interpreting {
              ProgressView()
            } else {
            Label("Filters", systemImage: has.isEmpty && !filters.isActive
              ? "line.3.horizontal.decrease.circle"
              : "line.3.horizontal.decrease.circle.fill")
            }
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
      Label(
        "Or write what you're looking for, like “who recommended a shipping agent last week”, and choose Search with a Sentence in Filters.",
        systemImage: "sparkles")
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
    /// No message had all the keywords, so these are the scope's recent
    /// messages, ranked by the sentence instead.
    var broadened = false
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
    !query.isEmpty || userID != nil || channelID != nil || !has.isEmpty || filters.isActive
  }

  /// Dates and regex in use, each with a way to clear it.
  @ViewBuilder
  var activeFilters: some View {
    if !filters.isActive, hasMessageCriteria, messageScope != nil {
      // the toolbar menu is out of reach while typing
      Section {
        Button {
          showingFilters = true
        } label: {
          Label("Dates and Regex…", systemImage: "calendar.badge.clock")
        }
      }
    }
    if filters.isActive {
      Section {
        Button {
          showingFilters = true
        } label: {
          Label("Edit Dates and Regex…", systemImage: "slider.horizontal.3")
        }
        if let range = filters.dateRangeDescription {
          HStack {
            Label(range, systemImage: "calendar")
            Spacer()
            Button("Clear", role: .destructive) {
              filters.from = nil
              filters.to = nil
            }
            .buttonStyle(.borderless)
          }
        }
        if !filters.pattern.isEmpty {
          HStack {
            Label {
              Text(verbatim: "/\(filters.pattern)/" + (filters.ignoresCase ? "i" : ""))
                .monospaced()
                .lineLimit(1)
            } icon: {
              Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            Spacer()
            Button("Clear", role: .destructive) { filters.pattern = "" }
              .buttonStyle(.borderless)
          }
          if filters.regex == nil {
            Label("This isn't a valid regular expression.", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
          }
        }
      } header: {
        Text("Filters")
      } footer: {
        if !filters.pattern.isEmpty {
          Text("Regex runs in Aicord on the results Discord sends, so “Show More” may be needed to find older matches.")
        }
      }
    }
  }

  /// Results after the app-side regex, most relevant first when ranked.
  var visibleMessages: [DiscordChannel.Message] {
    var items = messages.items
    if !filters.pattern.isEmpty {
      guard let regex = filters.regex else { return [] }
      items = items.filter { $0.content.contains(regex) }
    }
    if ranking, sortByRelevance, let relevanceOrder {
      let position = Dictionary(
        relevanceOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
      items.sort { (position[$0.id] ?? .max) < (position[$1.id] ?? .max) }
    }
    return items
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
        } else if visibleMessages.isEmpty && !(messages.items.count < messages.total) {
          Text("No messages found.")
            .foregroundStyle(.secondary)
        } else {
          if visibleMessages.isEmpty {
            Text("No matches in the \(messages.items.count) messages loaded so far.")
              .foregroundStyle(.secondary)
          }
          if ranking {
            rankingControls
          }
          ForEach(visibleMessages, id: \.id) { message in
            Button {
              open(guild: message.guild_id ?? serverID, channel: message.channel_id, message: message.id)
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
        if messageScope != nil, messages.total > 0, !filters.pattern.isEmpty {
          Text("Messages — \(visibleMessages.count) of \(messages.items.count) loaded")
        } else if messageScope != nil, messages.total > 0 {
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

  func makeQuery(offset: Int, broad: Bool = false) -> MessageSearchQuery {
    MessageSearchQuery(
      content: query.isEmpty || broad ? nil : query,
      channelIDs: channelID.map { [$0] } ?? [],
      authorIDs: userID.map { [$0] } ?? [],
      has: has.map(\.rawValue).sorted(),
      offset: offset,
      minID: filters.minID,
      maxID: filters.maxID
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
      var first = await fetchMessages(scope: scope, offset: 0, into: MessageResults())
      // a sentence's keywords can be too many for Discord's all-words search:
      // rank the recent messages in the same place by the sentence instead
      if ranking, !query.isEmpty, !first.failed, !first.indexing, first.total == 0,
        !Task.isCancelled
      {
        first = await fetchMessages(
          scope: scope, offset: 0, into: MessageResults(broadened: true), broad: true)
      }
      messages = first
    }
  }

  func loadMoreMessages() {
    guard let scope = messageScope else { return }
    let current = messages
    searchTask = Task {
      messages.loading = true
      messages = await fetchMessages(
        scope: scope, offset: current.items.count, into: current, broad: current.broadened)
    }
  }

  func fetchMessages(
    scope: MessageScope, offset: Int, into current: MessageResults, broad: Bool = false
  ) async -> MessageResults {
    var result = current
    result.loading = false
    do {
      let query = makeQuery(offset: offset, broad: broad)
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
      if !Task.isCancelled { print("[Search] Message search failed:", error) }
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

  /// Opens the channel scrolled to the message, which is briefly highlighted.
  func open(guild: GuildSnowflake?, channel: ChannelSnowflake, message: MessageSnowflake) {
    appState.open(guild: guild, channel: channel, message: message)
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

/// Message filters Discord's search doesn't take as text: a date range (sent as
/// `min_id`/`max_id`) and a regular expression applied in the app.
struct MessageFilters: Equatable {
  var from: Date?
  var to: Date?
  var pattern = ""
  var ignoresCase = true

  var isActive: Bool { from != nil || to != nil || !pattern.isEmpty }

  struct DateRange: Equatable { var from: Date?; var to: Date? }
  var dateRange: DateRange { DateRange(from: from, to: to) }

  /// From the start of the first day.
  var minID: MessageSnowflake? {
    from.flatMap { MessageSearchQuery.boundary(for: Calendar.current.startOfDay(for: $0)) }
  }

  /// Up to the end of the last day.
  var maxID: MessageSnowflake? {
    to.flatMap {
      Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0))
    }
    .flatMap(MessageSearchQuery.boundary(for:))
  }

  var regex: Regex<AnyRegexOutput>? {
    guard let regex = try? Regex(pattern) else { return nil }
    return ignoresCase ? regex.ignoresCase() : regex
  }

  var dateRangeDescription: String? {
    let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
    switch (from, to) {
    case let (from?, to?): return "\(from.formatted(style)) – \(to.formatted(style))"
    case let (from?, nil): return String(localized: "From \(from.formatted(style))")
    case let (nil, to?): return String(localized: "Until \(to.formatted(style))")
    default: return nil
    }
  }
}

struct MessageFiltersSheet: View {
  @Environment(\.dismiss) var dismiss
  @Binding var filters: MessageFilters

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("From", isOn: Binding(
            get: { filters.from != nil },
            set: { filters.from = $0 ? (filters.to ?? .now).addingTimeInterval(-7 * 86_400) : nil }
          ))
          if let from = filters.from {
            DatePicker(
              "From", selection: Binding(get: { from }, set: { filters.from = $0 }),
              in: ...(filters.to ?? .now), displayedComponents: .date
            )
          }
          Toggle("To", isOn: Binding(
            get: { filters.to != nil },
            set: { filters.to = $0 ? .now : nil }
          ))
          if let to = filters.to {
            DatePicker(
              "To", selection: Binding(get: { to }, set: { filters.to = $0 }),
              in: (filters.from ?? .distantPast)...Date.now, displayedComponents: .date
            )
          }
        } header: {
          Text("Dates")
        } footer: {
          Text("Both days are included.")
        }

        Section {
          TextField("Regular expression", text: $filters.pattern)
            .monospaced()
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never)
            #endif
          Toggle("Ignore Case", isOn: $filters.ignoresCase)
          if !filters.pattern.isEmpty && filters.regex == nil {
            Label("This isn't a valid regular expression.", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
          }
        } header: {
          Text("Regex")
        } footer: {
          Text("Matched against message text in Aicord, after Discord's search. For example, ^v\\d+ finds messages starting with a version number.")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Dates and Regex")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Reset", role: .destructive) { filters = MessageFilters() }
            .disabled(!filters.isActive)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    #if os(macOS)
      .frame(width: 400, height: 460)
    #endif
  }
}

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
        } else if let forwarded = message.message_snapshots?.first?.message {
          Label {
            Text(forwarded.content.isEmpty ? String(localized: "Forwarded message") : forwarded.content)
              .lineLimit(4)
          } icon: {
            Image(systemName: "arrowshape.turn.up.right")
          }
          .font(.subheadline)
          .foregroundStyle(.secondary)
        } else if !message.attachments.isEmpty {
          Label("^[\(message.attachments.count) attachment](inflect: true)", systemImage: "paperclip")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
    .contentShape(.rect)
  }
}

// MARK: - Ranking

extension SearchView {
  /// Ranking applies while the keywords the sentence gave are unchanged.
  var ranking: Bool { rankingSentence != nil && rankedText == text }

  struct RankingKey: Equatable {
    var sentence: String?
    var ids: [MessageSnowflake]
  }

  @ViewBuilder
  var rankingControls: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker("Order", selection: $sortByRelevance) {
        Text("Most Relevant").tag(true)
        Text("Newest").tag(false)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      Text(
        messages.broadened
          ? "No message had all of “\(query)”, so these are the latest messages here, ranked by how well they match your sentence on this device."
          : "Ranked on this device by how well each message matches your sentence."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }

  /// Orders the loaded results by meaning (on-device sentence vectors when
  /// the model is there) and shared words.
  func rankResults() async {
    guard ranking, let sentence = rankingSentence, !messages.items.isEmpty else {
      relevanceOrder = nil
      return
    }
    let items = messages.items
    let documents = items.map(SemanticRanker.document(for:))
    let order = await SemanticRanker.rank(query: sentence, documents: documents)
    guard !Task.isCancelled else { return }
    relevanceOrder = order.map { items[$0].id }
  }
}
