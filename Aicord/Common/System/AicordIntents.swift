//
//  AicordIntents.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//
//  Shortcuts and Siri: open a channel or DM, and a summary of what's new on a
//  server through Intelligence. Both run only when the user runs them and
//  bring the app forward, so they use the app's own connection.
//

import AicordKit
import AppIntents
import Foundation

// MARK: - Entities

struct ChannelEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Channel", numericFormat: "\(placeholder: .int) channels")
  static let defaultQuery = ChannelEntityQuery()

  /// `AicordLink.identifier`: server (or `@me`) and channel.
  var id: String
  var name: String
  var server: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(
      title: "\(name)",
      subtitle: server.isEmpty ? "Direct Message" : "\(server)")
  }

  init(_ entry: DirectoryEntry) {
    id = entry.link.identifier
    name = entry.name
    server = entry.server
  }
}

struct ChannelEntityQuery: EntityStringQuery {
  @MainActor
  func entities(for identifiers: [ChannelEntity.ID]) async throws -> [ChannelEntity] {
    let wanted = Set(identifiers)
    return SystemIntegration.shared.directory()
      .filter { wanted.contains($0.link.identifier) }
      .map(ChannelEntity.init)
  }

  @MainActor
  func entities(matching string: String) async throws -> [ChannelEntity] {
    let query = string.trimmingCharacters(in: .whitespaces).trimmingPrefix("#")
    return SystemIntegration.shared.directory()
      .filter {
        $0.name.trimmingPrefix("#").localizedStandardContains(query)
          || $0.server.localizedStandardContains(query)
      }
      .prefix(50)
      .map(ChannelEntity.init)
  }

  /// Recent DMs, then the first channels of each server.
  @MainActor
  func suggestedEntities() async throws -> [ChannelEntity] {
    SystemIntegration.shared.directory().prefix(60).map(ChannelEntity.init)
  }
}

struct ServerEntity: AppEntity {
  static let typeDisplayRepresentation = TypeDisplayRepresentation(
    name: "Server", numericFormat: "\(placeholder: .int) servers")
  static let defaultQuery = ServerEntityQuery()

  var id: String
  var name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

struct ServerEntityQuery: EntityStringQuery {
  @MainActor
  private func all() -> [ServerEntity] {
    var seen = Set<String>()
    return SystemIntegration.shared.directory().compactMap { entry in
      guard let id = entry.link.guildID, seen.insert(id).inserted else { return nil }
      return ServerEntity(id: id, name: entry.server)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  @MainActor
  func entities(for identifiers: [ServerEntity.ID]) async throws -> [ServerEntity] {
    let wanted = Set(identifiers)
    return all().filter { wanted.contains($0.id) }
  }

  @MainActor
  func entities(matching string: String) async throws -> [ServerEntity] {
    all().filter { $0.name.localizedStandardContains(string) }
  }

  @MainActor
  func suggestedEntities() async throws -> [ServerEntity] {
    all()
  }
}

// MARK: - Intents

struct OpenChannelIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Channel"
  static let description = IntentDescription("Opens a server channel or a direct message in Aicord.")
  static let supportedModes: IntentModes = .foreground

  @Parameter(title: "Channel")
  var channel: ChannelEntity

  static var parameterSummary: some ParameterSummary {
    Summary("Open \(\.$channel)")
  }

  init() {}

  init(channel: ChannelEntity) {
    self.channel = channel
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    guard let link = AicordLink(identifier: channel.id) else { return .result() }
    // a cold start: the window may not be up yet
    for _ in 0..<50 where AicordAppState.externalTarget == nil {
      try await Task.sleep(for: .milliseconds(100))
    }
    SystemIntegration.shared.open(link)
    return .result()
  }
}

struct WhatsNewInServerIntent: AppIntent {
  static let title: LocalizedStringResource = "What's New in Server"
  static let description = IntentDescription(
    "Summarises a server's unread channels with Intelligence, the same as Catch Up in the server's menu."
  )
  static let supportedModes: IntentModes = .foreground

  /// Fewer than Catch Up's 15: the answer is read out or shown in a dialog.
  static let channelLimit = 5
  /// How long a cold start may take to connect.
  static let connectTimeout: Duration = .seconds(20)

  @Parameter(title: "Server")
  var server: ServerEntity

  static var parameterSummary: some ParameterSummary {
    Summary("What's new in \(\.$server)")
  }

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let gw = GatewayStore.shared
    guard gw.accounts.currentAccountID != nil else {
      throw IntelligenceError(String(localized: "Log in to Aicord first."))
    }
    let deadline = ContinuousClock.now + Self.connectTimeout
    while gw.state != .connected || gw.user.guilds.isEmpty {
      guard ContinuousClock.now < deadline else {
        throw IntelligenceError(String(localized: "Aicord couldn't connect to Discord."))
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    let model: IntelligenceModel
    switch IntelligenceModel.current() {
    case .success(let current): model = current
    case .failure(let reason): throw IntelligenceError(reason.localizedDescription)
    }

    let guildId = GuildSnowflake(server.id)
    let place = gw.user.guilds[guildId]?.name ?? server.name
    let candidates = CatchUpSheet.candidates(guildId: guildId, gw: gw)
    var sections: [String] = []
    for channel in candidates.prefix(Self.channelLimit * 2) {
      guard sections.count < Self.channelLimit else { break }
      let acked = gw.readStates.readStates[AnySnowflake(channel.id)]?.last_message_id
      guard
        let messages = try? await IntelligenceSource.fetchMessages(
          channelId: channel.id, limit: 100, after: acked, gw: gw)
      else { continue }
      let transcript = IntelligenceSource.transcript(of: messages, guildId: guildId, gw: gw)
      guard !transcript.isEmpty else { continue }
      let name = channel.name ?? "channel"
      let points = try await model.summarizer().summarize(
        lines: transcript.lines, context: "New messages in #\(name) on \(place):", maxPoints: 3)
      guard !points.isEmpty else { continue }
      sections.append(
        "#\(name)\n" + points.map { "• \($0.text)" }.joined(separator: "\n"))
    }

    let text: String
    if sections.isEmpty {
      text = String(localized: "Nothing new on \(place).")
    } else {
      let more = max(0, candidates.count - sections.count)
      text = sections.joined(separator: "\n\n")
        + (more > 0 ? "\n\n" + String(localized: "\(more) more unread channels") : "")
    }
    return .result(value: text, dialog: "\(text)")
  }
}

// MARK: - Shortcuts

struct AicordShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenChannelIntent(),
      phrases: [
        "Open a channel in \(.applicationName)",
        "Open \(\.$channel) in \(.applicationName)",
      ],
      shortTitle: "Open Channel",
      systemImageName: "number"
    )
    AppShortcut(
      intent: WhatsNewInServerIntent(),
      phrases: [
        "What's new in \(.applicationName)",
        "What's new on \(\.$server) in \(.applicationName)",
      ],
      shortTitle: "What's New",
      systemImageName: "sparkles"
    )
  }

  static let shortcutTileColor: ShortcutTileColor = .lightBlue
}
