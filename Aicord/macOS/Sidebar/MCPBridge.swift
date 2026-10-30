//
//  MCPBridge.swift
//  Aicord
//
//  The app's side of the MCP server: a loopback-only listener the
//  `aicord-mcp` helper connects to. It answers read-only questions (servers,
//  channels, messages, search) with what the app already shows, through the
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

    /// What goes into Claude's (or another client's) MCP server list.
    static var clientConfiguration: String {
      """
      {
        "mcpServers": {
          "aicord": {
            "command": "/usr/local/bin/aicord-mcp",
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
        return reply(["ok": false, "error": error.localizedDescription])
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
      switch tool {
      case "list_servers":
        return listServers(gw)
      case "list_channels":
        return try listChannels(serverID: string(arguments, "server_id"), gw: gw)
      case "list_direct_messages":
        return try listDirectMessages(gw)
      case "read_messages":
        return try await readMessages(
          channelID: string(arguments, "channel_id"),
          limit: min(max(arguments["limit"] as? Int ?? 50, 1), 100), gw: gw)
      case "search_messages":
        return try await search(
          serverID: arguments["server_id"] as? String, channelID: arguments["channel_id"] as? String,
          query: string(arguments, "query"), gw: gw)
      default:
        throw IntelligenceError("Unknown tool \(tool).")
      }
    }

    private static func string(_ arguments: [String: Any], _ key: String) throws -> String {
      guard let value = arguments[key] as? String, !value.isEmpty else {
        throw IntelligenceError("Missing \(key).")
      }
      return value
    }

    static func listServers(_ gw: GatewayStore) -> String {
      let servers = gw.user.guilds.values.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      return servers.map { "\($0.name) (server_id: \($0.id.rawValue))" }.joined(separator: "\n")
    }

    static func listChannels(serverID: String, gw: GatewayStore) throws -> String {
      let guildId = GuildSnowflake(serverID)
      guard let guild = gw.user.guilds[guildId] else {
        throw IntelligenceError("You're not in a server with that ID.")
      }
      let channels = readableChannels(in: guild, gw: gw)
      guard !channels.isEmpty else { return "No text channels you can read." }
      return channels.map { "#\($0.name ?? "channel") (channel_id: \($0.id.rawValue))" }
        .joined(separator: "\n")
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
        lines.append("\(name) (channel_id: \(channel.id.rawValue))")
      }
      return lines.joined(separator: "\n")
    }

    static func readMessages(channelID: String, limit: Int, gw: GatewayStore) async throws -> String {
      let channelId = ChannelSnowflake(channelID)
      let guildId = try allowedPlace(channelId, gw: gw)
      let messages = try await IntelligenceSource.fetchMessages(
        channelId: channelId, limit: limit, gw: gw)
      return lines(for: messages, guildId: guildId, gw: gw)
    }

    static func search(
      serverID: String?, channelID: String?, query: String, gw: GatewayStore
    ) async throws -> String {
      var search = MessageSearchQuery(content: query)
      let response: DiscordClientResponse<MessageSearchResults>
      var guildId: GuildSnowflake?
      if let channelID, !channelID.isEmpty {
        let channelId = ChannelSnowflake(channelID)
        guildId = try allowedPlace(channelId, gw: gw)
        if let guildId {
          search.channelIDs = [channelId]
          response = try await gw.client.searchGuildMessages(guildID: guildId, query: search)
        } else {
          response = try await gw.client.searchChannelMessages(channelID: channelId, query: search)
        }
      } else if let serverID, !serverID.isEmpty {
        guildId = GuildSnowflake(serverID)
        guard gw.user.guilds[guildId!] != nil else {
          throw IntelligenceError("You're not in a server with that ID.")
        }
        response = try await gw.client.searchGuildMessages(guildID: guildId!, query: search)
      } else {
        throw IntelligenceError("Give a server_id or a channel_id to search in.")
      }
      if response.httpResponse.status == .accepted {
        return "Discord is still indexing this place. Try again in a moment."
      }
      try response.guardSuccess()
      let page = try response.decode()
      let found = page.messages.compactMap(\.first)
      guard !found.isEmpty else { return "No messages found." }
      return "\(page.total_results) results, the newest \(found.count):\n"
        + lines(for: found.reversed(), guildId: guildId, gw: gw, describesPlace: true)
    }

    /// The server of a channel you may read here, or `nil` for an allowed DM.
    private static func allowedPlace(_ channelId: ChannelSnowflake, gw: GatewayStore) throws
      -> GuildSnowflake?
    {
      if gw.user.privateChannels[channelId] != nil {
        guard MCPPreferences.allowsDirectMessages else {
          throw IntelligenceError("Direct messages are off for MCP in Aicord's settings.")
        }
        return nil
      }
      guard let guildId = IntelligenceSource.guildId(of: channelId, gw: gw),
        let guild = gw.user.guilds[guildId],
        readableChannels(in: guild, gw: gw).contains(where: { $0.id == channelId })
      else {
        throw IntelligenceError("No channel you can read has that ID.")
      }
      return guildId
    }

    private static func readableChannels(in guild: Guild, gw: GatewayStore) -> [DiscordChannel] {
      let store = gw.existingGuildStore(for: guild.id)
      return (guild.channels ?? [])
        .filter {
          [.guildText, .guildAnnouncement, .guildForum].contains($0.type)
            && store?.hasPermission(channel: $0, .viewChannel) != false
            && store?.hasPermission(channel: $0, .readMessageHistory) != false
        }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    }

    /// "date time · Name: text (message_id)", through the reader's filters.
    private static func lines(
      for messages: [DiscordChannel.Message], guildId: GuildSnowflake?, gw: GatewayStore,
      describesPlace: Bool = false
    ) -> String {
      let transcript = IntelligenceSource.transcript(
        of: messages, guildId: guildId, gw: gw, maxCharacters: 1_500,
        describesPlace: describesPlace)
      var result = zip(transcript.messages, transcript.lines).map { message, line in
        let text = line.firstIndex(of: " ").map { String(line[line.index(after: $0)...]) } ?? line
        let date = message.timestamp.date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
        return "\(date) · \(text) (message_id: \(message.id.rawValue))"
      }
      if transcript.hiddenCount > 0 {
        result.append("(\(transcript.hiddenCount) messages hidden by the reader's filters)")
      }
      return result.isEmpty ? "No messages." : result.joined(separator: "\n")
    }
  }
#endif
