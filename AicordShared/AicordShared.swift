//
//  AicordShared.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//
//  Compiled into the app and the widget extension. Plain types only: the
//  extension doesn't link AicordKit, never talks to Discord and holds no token.
//

import Foundation

/// The App Group the app and its widgets share. The id comes from Info.plist
/// (`AicordAppGroup`), so it can differ per platform: `group.…` on iOS and the
/// team-prefixed form on macOS.
enum AicordAppGroup {
  static let identifier: String? = Bundle.main.object(forInfoDictionaryKey: "AicordAppGroup")
    as? String

  static var containerURL: URL? {
    identifier.flatMap {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }
  }

  static var widgetSnapshotURL: URL? {
    containerURL?.appending(path: "WidgetSnapshot.json")
  }
}

/// Links into the app: `aicord://channel/<guild or @me>/<channel>[/<message>]`.
/// Widgets, Spotlight, Handoff and App Intents all end up here.
struct AicordLink: Hashable, Codable, Sendable {
  static let scheme = "aicord"
  /// `@me` in place of a server, as in discord.com/channels/@me/….
  static let directMessages = "@me"

  var guildID: String?
  var channelID: String
  var messageID: String?

  init(guildID: String?, channelID: String, messageID: String? = nil) {
    self.guildID = guildID
    self.channelID = channelID
    self.messageID = messageID
  }

  var url: URL {
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = "channel"
    let parts = [guildID ?? Self.directMessages, channelID] + (messageID.map { [$0] } ?? [])
    components.path = "/" + parts.joined(separator: "/")
    return components.url ?? URL(string: "\(Self.scheme)://")!
  }

  init?(url: URL) {
    guard url.scheme == Self.scheme, url.host() == "channel" else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 2, parts.dropFirst().allSatisfy({ UInt64($0) != nil }) else {
      return nil
    }
    guildID = parts[0] == Self.directMessages ? nil : parts[0]
    channelID = parts[1]
    messageID = parts.count > 2 ? parts[2] : nil
  }

  /// A stable string id, for Spotlight items and App Intents entities.
  var identifier: String {
    ([guildID ?? Self.directMessages, channelID] + (messageID.map { [$0] } ?? []))
      .joined(separator: ":")
  }

  init?(identifier: String) {
    let parts = identifier.split(separator: ":").map(String.init)
    guard parts.count >= 2 else { return nil }
    guildID = parts[0] == Self.directMessages ? nil : parts[0]
    channelID = parts[1]
    messageID = parts.count > 2 ? parts[2] : nil
  }
}

/// What the widgets show, written by the app while it runs. Counts and names
/// only, never message text.
struct WidgetSnapshot: Codable, Sendable {
  struct Place: Codable, Sendable, Hashable, Identifiable {
    var link: AicordLink
    /// "#channel" or the other person's name.
    var name: String
    /// The server, empty for a DM.
    var server: String
    var mentions: Int
    var id: String { link.identifier }
  }

  /// Unread mentions, DM messages included, outside muted servers and DMs.
  var mentions: Int
  /// DMs with unread messages.
  var unreadDirectMessages: Int
  /// Servers with unread channels, muted ones left out.
  var unreadServers: Int
  /// Where the mentions are, most first.
  var places: [Place]
  var updatedAt: Date

  static let empty = WidgetSnapshot(
    mentions: 0, unreadDirectMessages: 0, unreadServers: 0, places: [], updatedAt: .distantPast)

  static func load() -> WidgetSnapshot? {
    guard let url = AicordAppGroup.widgetSnapshotURL, let data = try? Data(contentsOf: url)
    else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(WidgetSnapshot.self, from: data)
  }

  /// Same content apart from the time it was written.
  func hasSameContent(as other: WidgetSnapshot?) -> Bool {
    guard let other else { return false }
    return mentions == other.mentions && unreadDirectMessages == other.unreadDirectMessages
      && unreadServers == other.unreadServers && places == other.places
  }

  static let widgetKind = "net.smigi.aicord.unread"
}
