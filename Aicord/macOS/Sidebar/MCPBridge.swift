//
//  MCPBridge.swift
//  Aicord
//
//  The app's side of the MCP server: a loopback-only listener the
//  `aicord-mcp` helper connects to. It answers read-only questions (servers,
//  channels, threads, messages, search, mentions, unread, events, voice) with
//  what the app already knows, through the
//  same filters the language model features use. Off unless turned on in
//  Settings → Advanced; every request needs the key shown there, which goes
//  into the MCP client's configuration (other apps can't read Aicord's
//  sandbox container, so the key can't simply be left in a file).
//

#if os(macOS)
  import AicordKit
  import Foundation
  import Network
  import os

  enum MCPPreferences {
    static let enabledKey = "Aicord.MCP.Enabled"
    static let directMessagesKey = "Aicord.MCP.DirectMessages"

    static let tokenKey = "Aicord.MCP.Token"
    /// A fixed loopback port, so the client configuration stays valid.
    static let port: UInt16 = 47823

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var allowsDirectMessages: Bool { UserDefaults.standard.bool(forKey: directMessagesKey) }

    /// The key MCP clients send, made on first use.
    static var token: String {
      if let token = UserDefaults.standard.string(forKey: tokenKey), token.count >= 32 { return token }
      let token = newToken()
      UserDefaults.standard.set(token, forKey: tokenKey)
      return token
    }

    static func resetToken() {
      UserDefaults.standard.set(newToken(), forKey: tokenKey)
    }

    static func newToken() -> String {
      var bytes = [UInt8](repeating: 0, count: 24)
      _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
      return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The helper the build puts inside the app, in `Contents/Helpers`.
    static var helperPath: String {
      Bundle.main.bundleURL.appending(path: "Contents/Helpers/aicord-mcp").path
    }

    /// What goes into Claude's (or another client's) MCP server list.
    static var clientConfiguration: String {
      """
      {
        "mcpServers": {
          "aicord": {
            "command": "\(helperPath)",
            "env": { "AICORD_MCP_TOKEN": "\(token)", "AICORD_MCP_PORT": "\(port)" }
          }
        }
      }
      """
    }
  }

  @MainActor
  final class MCPBridge {
    static let shared = MCPBridge()

    /// Where the helper finds the port and token. In the sandbox this is
    /// inside the app's container.
    static var infoURL: URL {
      URL.applicationSupportDirectory.appending(path: "Aicord/mcp-bridge.json")
    }

    private let logger = Logger(subsystem: "net.smigi.aicord", category: "MCPBridge")
    private var listener: NWListener?
    private var recentCalls: [Date] = []
    private(set) var isRunning = false

    /// Starts or stops to match the setting.
    func update() {
      if MCPPreferences.enabled { start() } else { stop() }
    }

    private func start() {
      guard listener == nil else { return }
      do {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
          host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: MCPPreferences.port)!)
        parameters.acceptLocalOnly = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
          Task { @MainActor in self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
          Task { @MainActor in self?.listenerChanged(state) }
        }
        listener.start(queue: .main)
        self.listener = listener
      } catch {
        logger.error("Couldn't start the MCP bridge: \(error.localizedDescription)")
      }
    }

    func stop() {
      listener?.cancel()
      listener = nil
      isRunning = false
      try? FileManager.default.removeItem(at: Self.infoURL)
    }

    private func listenerChanged(_ state: NWListener.State) {
      switch state {
      case .ready:
        guard let port = listener?.port?.rawValue else { return }
        isRunning = true
        writeInfo(port: port)
        logger.info("MCP bridge listening on 127.0.0.1:\(port)")
      case .failed(let error):
        logger.error("MCP bridge failed: \(error.localizedDescription)")
        stop()
      default:
        break
      }
    }

    private func writeInfo(port: UInt16) {
      let info: [String: Any] = [
        "port": Int(port), "token": MCPPreferences.token,
        "pid": Int(ProcessInfo.processInfo.processIdentifier),
      ]
      do {
        let url = Self.infoURL
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: info)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
      } catch {
        logger.error("Couldn't write the MCP bridge info: \(error.localizedDescription)")
      }
    }

    // MARK: Connections

    /// One request per connection: a JSON line in, a JSON line out.
    private func accept(_ connection: NWConnection) {
      connection.start(queue: .main)
      receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
        [weak self] data, _, isComplete, error in
        Task { @MainActor in
          guard let self else { return }
          var buffer = buffer
          if let data { buffer.append(data) }
          if let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            let reply = await self.handle(Data(line))
            connection.send(
              content: reply + Data([0x0A]),
              completion: .contentProcessed { _ in connection.cancel() })
          } else if isComplete || error != nil || buffer.count > 256 * 1024 {
            connection.cancel()
          } else {
            self.receive(on: connection, buffer: buffer)
          }
        }
      }
    }

    private func handle(_ line: Data) async -> Data {
      func reply(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
      }
      guard let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
        let token = request["token"] as? String, Self.equalInConstantTime(token, MCPPreferences.token)
      else {
        return reply(["ok": false, "error": "Not authorised."])
      }
      // a few calls a second at most; Discord's limits apply behind this
      recentCalls = recentCalls.filter { $0.timeIntervalSinceNow > -60 }
      guard recentCalls.count < 30 else {
        return reply(["ok": false, "error": "Too many requests. Wait a minute and try again."])
      }
      recentCalls.append(.now)
      let tool = request["tool"] as? String ?? ""
      let arguments = request["arguments"] as? [String: Any] ?? [:]
      do {
        let text = try await MCPTools.run(tool, arguments: arguments)
        return reply(["ok": true, "text": text])
      } catch {
        return reply(["ok": false, "error": MCPTools.message(for: error)])
      }
    }

    private static func equalInConstantTime(_ a: String, _ b: String) -> Bool {
      let a = Array(a.utf8)
      let b = Array(b.utf8)
      guard a.count == b.count, !b.isEmpty else { return false }
      var difference: UInt8 = 0
      for i in a.indices { difference |= a[i] ^ b[i] }
      return difference == 0
    }
  }

  // MARK: - Tools

  /// The read-only lookups behind each MCP tool. Answers are plain text for
  /// the model, with IDs it can pass to the next call.
  @MainActor
  enum MCPTools {
    static func run(_ tool: String, arguments: [String: Any]) async throws -> String {
      let gw = GatewayStore.shared
      guard gw.state == .connected else {
        throw IntelligenceError("Aicord isn't connected to Discord right now.")
      }
      let args = Arguments(values: arguments)
      switch tool {
      case "list_servers":
        return listServers(gw)
      case "list_channels":
        return try listChannels(serverID: args.required("server_id"), gw: gw)
      case "list_direct_messages":
        return try listDirectMessages(gw)
      case "read_messages":
        return try await readMessages(args, gw: gw)
      case "search_messages":
        return try await search(args, gw: gw)
      case "find_members":
        return try await findMembers(
          serverID: args.required("server_id"), name: args.required("name"), gw: gw)
      case "list_threads":
        return try await listThreads(args, gw: gw)
      case "list_pinned":
        return try await listPinned(channelID: args.required("channel_id"), gw: gw)
      case "list_mentions":
        return try await listMentions(args, gw: gw)
      case "list_unread":
        return try listUnread(serverID: args.string("server_id"), gw: gw)
      case "list_events":
        return try await listEvents(serverID: args.required("server_id"), gw: gw)
      case "list_voice":
        return try listVoice(serverID: args.required("server_id"), gw: gw)
      default:
        throw IntelligenceError("Unknown tool \(tool).")
      }
    }

    /// What went wrong, in words: Discord's HTTP errors otherwise read as
    /// "DiscordHTTPError error 1".
    static func message(for error: Error) -> String {
      if case DiscordHTTPErrorResponse.jsonError(let json) = error {
        return "Discord refused: \(json.message)."
      }
      let status: UInt? =
        switch error {
        case DiscordHTTPError.badStatusCode(let response): response.status.code
        case DiscordHTTPErrorResponse.badStatusCode(let response): response.status.code
        case DiscordHTTPError.rateLimited: 429
        default: nil
        }
      switch status {
      case nil: return error.localizedDescription
      case 403: return "Discord says you can't see that (403)."
      case 404: return "Discord can't find that (404)."
      case 429: return "Discord's rate limit was reached. Wait a little and try again."
      case let code?: return "Discord answered with an error (\(code))."
      }
    }

    /// The tool's JSON arguments, read leniently: numbers may come as text
    /// and lists as one comma-separated string.
    struct Arguments {
      let values: [String: Any]

      func string(_ key: String) -> String? {
        guard let value = values[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }

      func required(_ key: String) throws -> String {
        guard let value = string(key) else { throw IntelligenceError("Missing \(key).") }
        return value
      }

      func int(_ key: String) -> Int? {
        (values[key] as? Int) ?? string(key).flatMap { Int($0) }
      }

      func bool(_ key: String) -> Bool? {
        if let value = values[key] as? Bool { return value }
        return string(key).map { ["true", "yes", "1"].contains($0.lowercased()) }
      }

      func strings(_ key: String) -> [String] {
        let items = (values[key] as? [Any])?.compactMap { $0 as? String } ?? string(key).map { [$0] } ?? []
        return items.flatMap { $0.split(separator: ",") }
          .map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
      }

      /// Case-insensitive, as people expect from a search box.
      func regex(_ key: String) throws -> NSRegularExpression? {
        guard let pattern = string(key) else { return nil }
        do {
          return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
          throw IntelligenceError("\(key) isn't a valid regular expression.")
        }
      }
    }

    // MARK: Servers and channels

    static func listServers(_ gw: GatewayStore) -> String {
      let servers = gw.user.guilds.values.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return servers.map { "\($0.name) (server_id: \($0.id.rawValue))" }.joined(separator: "\n")
    }

    /// Readable channels under their categories, with what kind each is,
    /// whether it's unread and the start of its topic.
    static func listChannels(serverID: String, gw: GatewayStore) throws -> String {
      let guildId = GuildSnowflake(serverID)
      guard let guild = gw.user.guilds[guildId] else {
        throw IntelligenceError("You're not in a server with that ID.")
      }
      let channels = readableChannels(in: guild, gw: gw)
      guard !channels.isEmpty else { return "No text channels you can read." }
      let categories = (guild.channels ?? []).filter { $0.type == .guildCategory }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
      let groups: [(String?, [DiscordChannel])] =
        [(nil, channels.filter { $0.parent_id == nil })]
        + categories.map { category in
          (category.name, channels.filter { $0.parent_id?.rawValue == category.id.rawValue })
        }
      var lines: [String] = []
      for (category, members) in groups where !members.isEmpty {
        if let category { lines.append(category) }
        for channel in members {
          lines.append((category == nil ? "" : "  ") + describe(channel, guildId: guildId, gw: gw))
        }
      }
      return lines.joined(separator: "\n")
    }

    private static func describe(_ channel: DiscordChannel, guildId: GuildSnowflake, gw: GatewayStore)
      -> String
    {
      var line = "#\(channel.name ?? "channel") (channel_id: \(channel.id.rawValue))"
      switch channel.type {
      case .guildAnnouncement: line += " [announcements]"
      case .guildForum: line += " [forum]"
      case .guildMedia: line += " [media]"
      case .guildVoice: line += " [voice]"
      case .guildStageVoice: line += " [stage]"
      default: break
      }
      var notes: [String] = []
      if gw.userGuildSettings.isMuted(guildId: guildId, channelId: channel.id) { notes.append("muted") }
      if gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id) {
        let mentions = gw.readStates.mentionCount(channelId: channel.id)
        notes.append(mentions > 0 ? "unread, \(count(mentions, "mention"))" : "unread")
      }
      if !notes.isEmpty { line += " · " + notes.joined(separator: ", ") }
      if let topic = channel.topic?.replacingOccurrences(of: "\n", with: " "), !topic.isEmpty {
        line += " · topic: " + (topic.count > 120 ? String(topic.prefix(120)) + "…" : topic)
      }
      return line
    }

    static func listDirectMessages(_ gw: GatewayStore) throws -> String {
      guard MCPPreferences.allowsDirectMessages else {
        throw IntelligenceError("Direct messages are off for MCP in Aicord's settings.")
      }
      func recency(_ channel: DiscordChannel) -> UInt64 {
        UInt64(channel.last_message_id?.rawValue ?? channel.id.rawValue) ?? 0
      }
      let channels: [DiscordChannel] = Array(
        gw.user.privateChannels.values
          .filter { !$0.isPendingMessageRequest && !$0.isSpam }
          .sorted { recency($0) > recency($1) }
          .prefix(50))
      var lines: [String] = []
      for channel in channels {
        let recipients = (channel.recipients ?? []).map { $0.global_name ?? $0.username }
        let name = channel.name ?? (recipients.isEmpty ? "Conversation" : recipients.joined(separator: ", "))
        var line = "\(name) (channel_id: \(channel.id.rawValue))"
        if gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id) {
          line += " · unread"
        }
        lines.append(line)
      }
      return lines.joined(separator: "\n")
    }

    // MARK: Reading

    /// A channel's messages: the latest, before or after a message or date,
    /// or around a message (also from a message link), optionally only those
    /// matching a regular expression.
    static func readMessages(_ args: Arguments, gw: GatewayStore) async throws -> String {
      var channelID = args.string("channel_id")
      var around = args.string("around").map { MessageSnowflake($0) }
      if let link = args.string("link") {
        guard let parsed = parseLink(link) else {
          throw IntelligenceError("That isn't a Discord message or channel link.")
        }
        channelID = parsed.channel.rawValue
        around = around ?? parsed.message
      }
      guard let channelID else { throw IntelligenceError("Give a channel_id or a link.") }
      let channelId = ChannelSnowflake(channelID)
      let guildId = try await allowedPlace(channelId, gw: gw)
      let regex = try args.regex("regex")
      let before = try args.string("before").map(boundary)
      let after = try args.string("after").map(boundary)

      let messages: [DiscordChannel.Message]
      let limit: Int
      if let around {
        limit = min(max(args.int("limit") ?? 21, 1), 100)
        let response = try await gw.client.listMessages(channelId: channelId, around: around, limit: limit)
        try response.guardSuccess()
        messages = try response.decode().reversed()
      } else {
        // with a regex, limit is how far back to look rather than how many to show
        limit = regex == nil
          ? min(max(args.int("limit") ?? 50, 1), 100)
          : min(max(args.int("limit") ?? 300, 1), 1_000)
        messages = try await history(channelId: channelId, before: before, after: after, limit: limit, gw: gw)
      }

      var text = lines(for: messages, guildId: guildId, gw: gw, highlight: around, regex: regex)
      if let regex, !messages.isEmpty {
        text = "Looked through \(messages.count) messages for /\(regex.pattern)/:\n" + text
      }
      if let first = messages.first, let last = messages.last, around != nil || messages.count == limit {
        text += "\n(older: before=\(first.id.rawValue) · newer: after=\(last.id.rawValue))"
      }
      if args.string("link") != nil, let name = placeName(channelId, guildId: guildId, gw: gw) {
        text = name + "\n" + text
      }
      return text
    }

    /// Up to `limit` messages, oldest first: the newest ones before `before`,
    /// or the first ones after `after` when only that is given. Pages of 100.
    private static func history(
      channelId: ChannelSnowflake, before: MessageSnowflake?, after: MessageSnowflake?, limit: Int,
      gw: GatewayStore
    ) async throws -> [DiscordChannel.Message] {
      var collected: [DiscordChannel.Message] = []
      if let after, before == nil {
        var cursor = after
        while collected.count < limit {
          let page = min(100, limit - collected.count)
          let response = try await gw.client.listMessages(channelId: channelId, after: cursor, limit: page)
          try response.guardSuccess()
          let fetched = try response.decode().sorted { $0.id < $1.id }
          collected += fetched
          guard fetched.count == page, let newest = fetched.last else { break }
          cursor = newest.id
        }
        return collected
      }
      var cursor = before
      while collected.count < limit {
        let page = min(100, limit - collected.count)
        let response = try await gw.client.listMessages(channelId: channelId, before: cursor, limit: page)
        try response.guardSuccess()
        var fetched = try response.decode()  // newest first
        let reachedAfter = after.map { after in fetched.contains { $0.id <= after } } ?? false
        if let after { fetched = fetched.filter { $0.id > after } }
        collected += fetched
        guard !reachedAfter, fetched.count == page, let oldest = fetched.last else { break }
        cursor = oldest.id
      }
      return collected.reversed()
    }

    /// `https://discord.com/channels/<server or @me>/<channel>[/<message>]`
    static func parseLink(_ link: String) -> (channel: ChannelSnowflake, message: MessageSnowflake?)? {
      guard let match = link.firstMatch(of: #/channels/(?:\d+|@me)/(\d+)(?:/(\d+))?/#) else { return nil }
      return (ChannelSnowflake(String(match.1)), match.2.map { MessageSnowflake(String($0)) })
    }

    /// A message ID, or a date (`2026-11-02`, or ISO 8601 with a time) in the
    /// Mac's time zone unless it gives one.
    static func boundary(_ value: String) throws -> MessageSnowflake {
      if value.count >= 15, value.allSatisfy(\.isNumber) { return MessageSnowflake(value) }
      let day = DateFormatter()
      day.locale = Locale(identifier: "en_US_POSIX")
      let date =
        (try? Date(value, strategy: .iso8601))
        ?? ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"].lazy
        .compactMap { format -> Date? in
          day.dateFormat = format
          return day.date(from: value)
        }.first
      guard let date, let boundary = MessageSearchQuery.boundary(for: date) else {
        throw IntelligenceError("\(value) isn't a message ID or a date like 2026-11-02.")
      }
      return boundary
    }

    static func listPinned(channelID: String, gw: GatewayStore) async throws -> String {
      let channelId = ChannelSnowflake(channelID)
      let guildId = try await allowedPlace(channelId, gw: gw)
      let response = try await gw.client.listPinnedMessages(channelId: channelId)
      try response.guardSuccess()
      let pins = try response.decode()
      guard !pins.isEmpty else { return "No pinned messages." }
      return "\(count(pins.count, "pinned message")), most recently pinned first:\n"
        + lines(for: pins, guildId: guildId, gw: gw)
    }

    // MARK: Search

    static let hasKinds: Set<String> = [
      "link", "embed", "file", "image", "video", "sound", "sticker", "poll", "snapshot",
    ]

    /// Discord's search with its filters; a regex narrows the results
    /// further, looking through up to five pages.
    static func search(_ args: Arguments, gw: GatewayStore) async throws -> String {
      var search = MessageSearchQuery(content: args.string("query"))
      var guildId: GuildSnowflake?
      var channelId: ChannelSnowflake?
      if let channelID = args.string("channel_id") {
        channelId = ChannelSnowflake(channelID)
        guildId = try await allowedPlace(channelId!, gw: gw)
        if guildId != nil { search.channelIDs = [channelId!] }
      } else if let serverID = args.string("server_id") {
        guildId = GuildSnowflake(serverID)
        guard gw.user.guilds[guildId!] != nil else {
          throw IntelligenceError("You're not in a server with that ID.")
        }
      } else {
        throw IntelligenceError("Give a server_id or a channel_id to search in.")
      }

      search.authorIDs = try await users(args.strings("author"), guildId: guildId, gw: gw)
      search.mentionIDs = try await users(args.strings("mentions"), guildId: guildId, gw: gw)
      search.has = try args.strings("has").map { kind in
        let bare = kind.lowercased().hasPrefix("-") ? String(kind.dropFirst()) : kind.lowercased()
        guard hasKinds.contains(bare) else {
          throw IntelligenceError("has can be \(hasKinds.sorted().joined(separator: ", ")), or one of them after -.")
        }
        return kind.lowercased()
      }
      search.authorTypes = try args.strings("author_type").map { kind in
        guard ["user", "bot", "webhook", "-user", "-bot", "-webhook"].contains(kind.lowercased()) else {
          throw IntelligenceError("author_type can be user, bot or webhook, or one of them after -.")
        }
        return kind.lowercased()
      }
      search.pinned = args.bool("pinned")
      search.minID = try args.string("after").map(boundary)
      search.maxID = try args.string("before").map(boundary)
      search.oldestFirst = args.string("sort")?.lowercased() == "oldest"
      let regex = try args.regex("regex")
      guard
        search.content != nil || !search.authorIDs.isEmpty || !search.mentionIDs.isEmpty
          || !search.has.isEmpty || !search.authorTypes.isEmpty || search.pinned != nil
          || search.minID != nil || search.maxID != nil
      else {
        throw IntelligenceError("Give a query or at least one filter.")
      }

      let page = max(args.int("page") ?? 1, 1)
      var found: [DiscordChannel.Message] = []
      var total = 0
      for index in 0..<(regex == nil ? 1 : 5) {
        search.offset = (page - 1 + index) * 25
        guard search.offset <= 9_975 else { break }
        let response: DiscordClientResponse<MessageSearchResults> =
          if let guildId {
            try await gw.client.searchGuildMessages(guildID: guildId, query: search)
          } else {
            try await gw.client.searchChannelMessages(channelID: channelId!, query: search)
          }
        if response.httpResponse.status == .accepted {
          return "Discord is still indexing this place. Try again in a moment."
        }
        try response.guardSuccess()
        let results = try response.decode()
        total = results.total_results
        let messages = results.messages.compactMap(\.first)
        found += messages
        if messages.count < 25 { break }
      }
      guard !found.isEmpty else { return "No messages found." }

      let order = search.oldestFirst ? "oldest first" : "newest first"
      let shown = search.oldestFirst ? found : found.reversed()
      let text = lines(for: shown, guildId: guildId, gw: gw, showsPlace: true, regex: regex)
      let pages = (total + 24) / 25
      if let regex {
        let lastPage = page - 1 + (found.count + 24) / 25
        return "\(total) results; looked through \(found.count) (pages \(page)–\(lastPage), \(order)) for /\(regex.pattern)/, shown oldest at the top:\n" + text
      }
      return "\(total) results, page \(page) of \(pages) (25 a page, \(order)), shown oldest at the top:\n" + text
    }

    // MARK: People

    /// User IDs for names or IDs, so searches can filter by person.
    private static func users(_ names: [String], guildId: GuildSnowflake?, gw: GatewayStore) async throws
      -> [UserSnowflake]
    {
      var ids: [UserSnowflake] = []
      for name in names {
        guard let id = await resolveUser(name, guildId: guildId, gw: gw) else {
          throw IntelligenceError("No one called \(name) found here. Try find_members, or give a user_id.")
        }
        ids.append(id)
      }
      return ids
    }

    private static func resolveUser(_ token: String, guildId: GuildSnowflake?, gw: GatewayStore) async
      -> UserSnowflake?
    {
      let name = token.hasPrefix("@") ? String(token.dropFirst()) : token
      if name.count >= 15, name.allSatisfy(\.isNumber) { return UserSnowflake(name) }
      if let guildId, let store = gw.existingGuildStore(for: guildId),
        let found = matches(name, in: store.loadedMembers).first
      {
        return found.id
      }
      if let found = gw.user.users.values.first(where: {
        [$0.username, $0.global_name].contains { $0?.caseInsensitiveCompare(name) == .orderedSame }
      }) {
        return found.id
      }
      guard let guildId else { return nil }
      return await requestMembers(name, guildId: guildId, gw: gw).first?.id
    }

    /// Members whose nickname, display name or username is `name`, then
    /// those starting with it, then those containing it.
    private static func matches(_ name: String, in members: [Guild.PartialMember]) -> [DiscordUser] {
      let wanted = name.lowercased()
      func names(_ member: Guild.PartialMember) -> [String] {
        [member.nick, member.user?.global_name, member.user?.username].compactMap { $0?.lowercased() }
      }
      let scored = members.compactMap { member -> (Int, DiscordUser)? in
        guard let user = member.user else { return nil }
        let names = names(member)
        if names.contains(wanted) { return (0, user) }
        if names.contains(where: { $0.hasPrefix(wanted) }) { return (1, user) }
        if names.contains(where: { $0.contains(wanted) }) { return (2, user) }
        return nil
      }
      return scored.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Asks the gateway for members matching `name` (only some are loaded)
    /// and waits briefly for them to arrive.
    private static func requestMembers(_ name: String, guildId: GuildSnowflake, gw: GatewayStore) async
      -> [DiscordUser]
    {
      let store = gw.getGuildStore(for: guildId)
      await gw.gateway?.requestGuildMembersChunk(
        payload: .init(guild_id: guildId, query: name, limit: 25))
      for _ in 0..<8 {
        try? await Task.sleep(for: .milliseconds(250))
        let found = matches(name, in: store.loadedMembers)
        if !found.isEmpty { return found }
      }
      return []
    }

    static func findMembers(serverID: String, name: String, gw: GatewayStore) async throws -> String {
      let guildId = GuildSnowflake(serverID)
      guard gw.user.guilds[guildId] != nil else {
        throw IntelligenceError("You're not in a server with that ID.")
      }
      let found = await requestMembers(name, guildId: guildId, gw: gw)
      guard !found.isEmpty else { return "No members found for \(name)." }
      let store = gw.existingGuildStore(for: guildId)
      return found.prefix(15).map { user in
        let shown = store?.member(user.id)?.nick ?? user.global_name ?? user.username
        return "\(shown) (@\(user.username), user_id: \(user.id.rawValue))\(user.bot == true ? " [bot]" : "")"
      }.joined(separator: "\n")
    }

    // MARK: Threads

    /// A channel's threads, or a forum's posts, most recently active first.
    static func listThreads(_ args: Arguments, gw: GatewayStore) async throws -> String {
      let channelId = ChannelSnowflake(try args.required("channel_id"))
      guard let guildId = try await allowedPlace(channelId, gw: gw) else {
        throw IntelligenceError("Direct messages have no threads.")
      }
      let page = max(args.int("page") ?? 1, 1)
      let query = ThreadSearchQuery(
        name: args.string("name"), archived: args.bool("archived"), offset: (page - 1) * 25)
      let response = try await gw.client.searchForumThreads(channelID: channelId, query: query)
      if response.httpResponse.status == .accepted {
        return "Discord is still indexing this channel's threads. Try again in a moment."
      }
      try response.guardSuccess()
      let results = try response.decode()
      guard !results.threads.isEmpty else { return "No threads found." }
      for thread in results.threads { knownThreads[thread.id] = thread }
      let openers = Dictionary(
        (results.first_messages ?? []).map { ($0.channel_id, $0) }, uniquingKeysWith: { first, _ in first })
      var rows = results.threads.map { thread in
        var line = "\(thread.name ?? "Thread") (channel_id: \(thread.id.rawValue))"
        if let messages = thread.message_count { line += " · \(count(messages, "message"))" }
        if let last = (thread.last_message_id ?? MessageSnowflake(thread.id.rawValue)).parse()?.date {
          line += " · last active \(stamp(last))"
        }
        if thread.thread_metadata?.archived == true { line += " · archived" }
        if let opener = openers[thread.id],
          let first = IntelligenceSource.transcript(of: [opener], guildId: guildId, gw: gw, maxCharacters: 200)
            .lines.first
        {
          line += "\n    " + (first.firstIndex(of: " ").map { String(first[first.index(after: $0)...]) } ?? first)
        }
        return line
      }
      if results.has_more == true { rows.append("(more: page=\(page + 1))") }
      return rows.joined(separator: "\n")
    }

    /// Threads looked up so far, which the loaded server lists don't have.
    private static var knownThreads: [ChannelSnowflake: DiscordChannel] = [:]

    private static func thread(_ channelId: ChannelSnowflake, gw: GatewayStore) async -> DiscordChannel? {
      if let thread = knownThreads[channelId] { return thread }
      for guildId in gw.user.guilds.keys {
        if let thread = gw.existingGuildStore(for: guildId)?.threads[channelId] {
          knownThreads[channelId] = thread
          return thread
        }
      }
      guard let response = try? await gw.client.getChannel(id: channelId),
        (try? response.guardSuccess()) != nil,
        let channel = try? response.decode()
      else { return nil }
      knownThreads[channelId] = channel
      return channel
    }

    // MARK: Mentions and unread

    static func listMentions(_ args: Arguments, gw: GatewayStore) async throws -> String {
      var guildId: GuildSnowflake?
      if let serverID = args.string("server_id") {
        guildId = GuildSnowflake(serverID)
        guard gw.user.guilds[guildId!] != nil else {
          throw IntelligenceError("You're not in a server with that ID.")
        }
      }
      let response = try await gw.client.getRecentMentions(
        before: args.string("before").map { MessageSnowflake($0) },
        limit: min(max(args.int("limit") ?? 25, 1), 100),
        includeEveryone: args.bool("include_everyone") ?? true,
        guildID: guildId)
      try response.guardSuccess()
      let mentions = try response.decode().filter {
        MCPPreferences.allowsDirectMessages || gw.user.privateChannels[$0.channel_id] == nil
      }
      guard let oldest = mentions.last else { return "No recent mentions." }
      // one at a time: each can come from a different server
      let rows = mentions.reversed().map { message in
        lines(
          for: [message], guildId: message.guild_id ?? IntelligenceSource.guildId(of: message.channel_id, gw: gw),
          gw: gw, showsPlace: true, showsServer: guildId == nil)
      }
      let shown = rows.filter { !$0.hasPrefix("(") && !$0.hasPrefix("No messages") }
      var text = "Recent mentions of you, shown oldest at the top:\n" + shown.joined(separator: "\n")
      if shown.count < rows.count { text += "\n(\(rows.count - shown.count) hidden by the reader's filters)" }
      return text + "\n(older: before=\(oldest.id.rawValue))"
    }

    /// Unread channels of one server, or which servers and DMs have unread
    /// messages; muted ones are left out, as in Catch Up.
    static func listUnread(serverID: String?, gw: GatewayStore) throws -> String {
      let readStates = gw.readStates
      if let serverID {
        let guildId = GuildSnowflake(serverID)
        guard let guild = gw.user.guilds[guildId] else {
          throw IntelligenceError("You're not in a server with that ID.")
        }
        let readable = Set(readableChannels(in: guild, gw: gw).map(\.id))
        let channels = CatchUpSheet.candidates(guildId: guildId, gw: gw).filter { readable.contains($0.id) }
        guard !channels.isEmpty else { return "Nothing unread in \(guild.name) (muted channels left out)." }
        return channels.map { channel in
          var line = "#\(channel.name ?? "channel") (channel_id: \(channel.id.rawValue))"
          let mentions = readStates.mentionCount(channelId: channel.id)
          if mentions > 0 { line += " · \(count(mentions, "mention"))" }
          if let date = channel.last_message_id?.parse()?.date { line += " · last message \(stamp(date))" }
          return line
        }.joined(separator: "\n")
      }

      var servers: [(name: String, line: String, mentions: Int)] = []
      for guild in gw.user.guilds.values where !gw.userGuildSettings.isMuted(guildId: guild.id) {
        let channels = CatchUpSheet.candidates(guildId: guild.id, gw: gw)
        guard !channels.isEmpty else { continue }
        let mentions = channels.reduce(0) { $0 + readStates.mentionCount(channelId: $1.id) }
        var line = "\(guild.name) (server_id: \(guild.id.rawValue)) · \(count(channels.count, "unread channel"))"
        if mentions > 0 { line += ", \(count(mentions, "mention"))" }
        servers.append((guild.name, line, mentions))
      }
      servers.sort { $0.mentions != $1.mentions ? $0.mentions > $1.mentions : $0.name < $1.name }
      var lines = servers.map(\.line)
      if MCPPreferences.allowsDirectMessages {
        let unread = gw.user.privateChannels.values.filter {
          !$0.isPendingMessageRequest && !$0.isSpam
            && readStates.isUnread(channelId: $0.id, lastMessageId: $0.last_message_id)
        }
        if !unread.isEmpty {
          lines.append("Direct messages:")
          lines += unread.map { channel in
            let names = (channel.recipients ?? []).map { $0.global_name ?? $0.username }
            return "  \(channel.name ?? names.joined(separator: ", ")) (channel_id: \(channel.id.rawValue))"
          }
        }
      }
      return lines.isEmpty ? "Nothing unread (muted servers and channels left out)." : lines.joined(separator: "\n")
    }

    // MARK: Events and voice

    static func listEvents(serverID: String, gw: GatewayStore) async throws -> String {
      let guildId = GuildSnowflake(serverID)
      guard let guild = gw.user.guilds[guildId] else {
        throw IntelligenceError("You're not in a server with that ID.")
      }
      let response = try await gw.client.listGuildScheduledEvents(guildId: guildId, withUserCount: true)
      try response.guardSuccess()
      let events = try response.decode()
        .filter { $0.status == .scheduled || $0.status == .active }
        .sorted { $0.scheduled_start_time.date < $1.scheduled_start_time.date }
      guard !events.isEmpty else { return "No upcoming events in \(guild.name)." }
      let channelNames = Dictionary(
        (guild.channels ?? []).map { ($0.id, $0.name ?? "channel") }, uniquingKeysWith: { first, _ in first })
      return events.map { event in
        var line = event.name
        line += event.status == .active ? " · happening now" : " · starts \(stamp(event.scheduled_start_time.date))"
        if let end = event.scheduled_end_time { line += ", ends \(stamp(end.date))" }
        if let channel = event.channel_id.flatMap({ channelNames[$0] }) {
          line += " · in #\(channel)"
        } else if let location = event.entity_metadata?.location {
          line += " · at \(location)"
        }
        if event.recurrence_rule != nil { line += " · repeats" }
        if let count = event.user_count { line += " · \(count) interested" }
        if let description = event.description?.replacingOccurrences(of: "\n", with: " "), !description.isEmpty {
          line += "\n    " + (description.count > 300 ? String(description.prefix(300)) + "…" : description)
        }
        return line
      }.joined(separator: "\n")
    }

    /// Who is in which voice channel, with who streams, has video on or is muted.
    static func listVoice(serverID: String, gw: GatewayStore) throws -> String {
      let guildId = GuildSnowflake(serverID)
      guard let guild = gw.user.guilds[guildId] else {
        throw IntelligenceError("You're not in a server with that ID.")
      }
      let store = gw.existingGuildStore(for: guildId)
      let states = store.map { Array($0.voiceStates.values) } ?? (guild.voice_states ?? [])
      let channels = (guild.channels ?? [])
        .filter {
          ($0.type == .guildVoice || $0.type == .guildStageVoice)
            && store?.hasPermission(channel: $0, .viewChannel) != false
        }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
      var lines: [String] = []
      for channel in channels {
        let inside = states.filter { $0.channel_id == channel.id }
        guard !inside.isEmpty else { continue }
        let people = inside.map { state in
          let member = state.member ?? store?.member(state.user_id)
          let user = gw.user.users[state.user_id]
          var name =
            member?.nick ?? member?.user?.global_name ?? member?.user?.username
            ?? user?.global_name ?? user?.username ?? "user \(state.user_id.rawValue)"
          var notes: [String] = []
          if state.self_stream == true { notes.append("streaming") }
          if state.self_video { notes.append("video") }
          if state.self_deaf || state.deaf {
            notes.append("deafened")
          } else if state.self_mute || state.mute {
            notes.append("muted")
          }
          if !notes.isEmpty { name += " (\(notes.joined(separator: ", ")))" }
          return name
        }
        lines.append("\(channel.name ?? "Voice") (channel_id: \(channel.id.rawValue)): \(people.joined(separator: ", "))")
      }
      guard !lines.isEmpty else { return "No one is in a voice channel in \(guild.name)." }
      if store == nil { lines.append("(as of when Aicord connected; open the server in Aicord for live updates)") }
      return lines.joined(separator: "\n")
    }

    // MARK: Access and formatting

    /// The server of a channel or thread you may read here, or `nil` for an
    /// allowed DM.
    private static func allowedPlace(_ channelId: ChannelSnowflake, gw: GatewayStore) async throws
      -> GuildSnowflake?
    {
      if gw.user.privateChannels[channelId] != nil {
        guard MCPPreferences.allowsDirectMessages else {
          throw IntelligenceError("Direct messages are off for MCP in Aicord's settings.")
        }
        return nil
      }
      if let guildId = IntelligenceSource.guildId(of: channelId, gw: gw), let guild = gw.user.guilds[guildId] {
        guard readableChannels(in: guild, gw: gw).contains(where: { $0.id == channelId }) else {
          throw IntelligenceError("No channel you can read has that ID.")
        }
        return guildId
      }
      // a thread or forum post: readable when its channel is
      if let thread = await thread(channelId, gw: gw),
        [.publicThread, .privateThread, .announcementThread].contains(thread.type),
        let guildId = thread.guild_id, let parent = thread.parent_id, let guild = gw.user.guilds[guildId],
        readableChannels(in: guild, gw: gw).contains(where: { $0.id.rawValue == parent.rawValue })
      {
        return guildId
      }
      throw IntelligenceError("No channel you can read has that ID.")
    }

    /// The server's store works out permissions, so it's made (as opening
    /// the server would) rather than letting every channel through.
    private static func readableChannels(in guild: Guild, gw: GatewayStore) -> [DiscordChannel] {
      let store = gw.getGuildStore(for: guild.id)
      return (guild.channels ?? [])
        .filter {
          [.guildText, .guildAnnouncement, .guildForum, .guildMedia, .guildVoice, .guildStageVoice]
            .contains($0.type)
            && store.hasPermission(channel: $0, .viewChannel)
            && store.hasPermission(channel: $0, .readMessageHistory)
        }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    /// "#channel in Server", for answers that start from a link.
    private static func placeName(_ channelId: ChannelSnowflake, guildId: GuildSnowflake?, gw: GatewayStore)
      -> String?
    {
      guard let guildId, let guild = gw.user.guilds[guildId] else { return nil }
      return channelName(channelId, guild: guild).map { "\($0) in \(guild.name)" }
    }

    private static func channelName(_ channelId: ChannelSnowflake, guild: Guild?) -> String? {
      if let channel = guild?.channels?.first(where: { $0.id == channelId }) {
        return "#\(channel.name ?? "channel")"
      }
      if let thread = knownThreads[channelId] {
        let parent = thread.parent_id.flatMap { parent in
          guild?.channels?.first { $0.id.rawValue == parent.rawValue }?.name
        }
        return "#\(parent ?? "channel") › \(thread.name ?? "thread")"
      }
      return nil
    }

    private static let stampFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd HH:mm xxx"
      return formatter
    }()

    /// "1 mention", "2 mentions".
    static func count(_ number: Int, _ noun: String) -> String {
      "\(number) \(noun)\(number == 1 ? "" : "s")"
    }

    /// The Mac's local time with its offset, e.g. "2026-11-02 11:25 +01:00".
    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    /// "date · [#channel ·] Name: text (message_id, author_id)", through the
    /// reader's filters; `highlight` marks the message a link points to.
    private static func lines(
      for messages: [DiscordChannel.Message], guildId: GuildSnowflake?, gw: GatewayStore,
      showsPlace: Bool = false, showsServer: Bool = false,
      highlight: MessageSnowflake? = nil, regex: NSRegularExpression? = nil
    ) -> String {
      let transcript = IntelligenceSource.transcript(
        of: messages, guildId: guildId, gw: gw, maxCharacters: 1_500)
      let guild = guildId.flatMap { gw.user.guilds[$0] }
      var result: [String] = []
      for (message, line) in zip(transcript.messages, transcript.lines) {
        let text = line.firstIndex(of: " ").map { String(line[line.index(after: $0)...]) } ?? line
        if let regex, regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil {
          continue
        }
        var parts = [stamp(message.timestamp.date)]
        if showsPlace {
          var place = channelName(message.channel_id, guild: guild) ?? (guildId == nil ? "DM" : "a thread")
          if showsServer, let guild { place += " in \(guild.name)" }
          parts.append(place)
        }
        parts.append(text)
        var ids = "message_id: \(message.id.rawValue)"
        if showsPlace { ids += ", channel_id: \(message.channel_id.rawValue)" }
        if let author = message.author { ids += ", author_id: \(author.id.rawValue)" }
        let marker = message.id == highlight ? "▶ " : ""
        result.append(marker + parts.joined(separator: " · ") + " (\(ids))")
      }
      if transcript.hiddenCount > 0 {
        result.append("(\(transcript.hiddenCount) messages hidden by the reader's filters)")
      }
      if result.isEmpty { return regex == nil ? "No messages." : "No messages match." }
      return result.joined(separator: "\n")
    }
  }
#endif
