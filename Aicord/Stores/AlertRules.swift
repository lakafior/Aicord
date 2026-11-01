//
//  AlertRules.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//

import AicordKit
import Foundation

/// Aicord's own alerts on top of Discord's notifications: keywords and regular
/// expressions in chosen places, and people to watch. They only look at
/// messages the gateway already delivers; nothing is fetched for them.
@MainActor
@Observable
final class AlertRules {
  static let shared = AlertRules()

  struct KeywordRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var pattern = ""
    var isRegex = false
    /// Servers and channels, separated by commas like the notification lists;
    /// empty means everywhere, DMs included.
    var places = ""
    var enabled = true

    var placeIDs: Set<String> { Set(places.split(separator: ",").map(String.init)) }

    /// A plain keyword matches whole words, ignoring case.
    var expression: NSRegularExpression? {
      let trimmed = pattern.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return nil }
      let source =
        isRegex ? trimmed : "\\b\(NSRegularExpression.escapedPattern(for: trimmed))\\b"
      return try? NSRegularExpression(pattern: source, options: [.caseInsensitive])
    }
  }

  static let rulesKey = "Paicord.Alerts.KeywordRules"
  static let watchedUsersKey = "Paicord.Alerts.WatchedUsers"
  static let ghostPingsKey = "Paicord.Alerts.GhostPings"

  var rules: [KeywordRule] {
    didSet {
      UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: Self.rulesKey)
      compiled = [:]
    }
  }

  @ObservationIgnored private var compiled: [UUID: NSRegularExpression] = [:]

  private init() {
    rules =
      UserDefaults.standard.data(forKey: Self.rulesKey)
      .flatMap { try? JSONDecoder().decode([KeywordRule].self, from: $0) } ?? []
  }

  static var watchesGhostPings: Bool {
    UserDefaults.standard.object(forKey: ghostPingsKey) as? Bool ?? true
  }

  static var watchedUsers: Set<String> {
    NotificationPrefs.ids(watchedUsersKey)
  }

  /// The first enabled rule that matches the text in this place.
  func matchingRule(
    _ text: String, channelId: ChannelSnowflake, parentId: ChannelSnowflake?,
    guildId: GuildSnowflake?
  ) -> KeywordRule? {
    guard !text.isEmpty else { return nil }
    let places = [guildId?.rawValue, channelId.rawValue, parentId?.rawValue].compactMap(\.self)
    let range = NSRange(text.startIndex..., in: text)
    return rules.first { rule in
      guard rule.enabled else { return false }
      let listed = rule.placeIDs
      guard listed.isEmpty || places.contains(where: listed.contains) else { return false }
      let expression = compiled[rule.id] ?? rule.expression
      compiled[rule.id] = expression
      return expression?.firstMatch(in: text, range: range) != nil
    }
  }
}
