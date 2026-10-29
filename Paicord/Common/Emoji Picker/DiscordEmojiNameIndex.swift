//
//  DiscordEmojiNameIndex.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 14/07/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import Foundation

enum EmojiCategory: String, CaseIterable, Hashable, Sendable {
  case people
  case nature
  case food
  case activity
  case travel
  case objects
  case symbols
  case flags

  var displayName: String {
    switch self {
    case .people: "People"
    case .nature: "Nature"
    case .food: "Food & Drink"
    case .activity: "Activities"
    case .travel: "Travel & Places"
    case .objects: "Objects"
    case .symbols: "Symbols"
    case .flags: "Flags"
    }
  }

  var symbolName: String {
    switch self {
    case .people: "face.smiling.inverse"
    case .nature: "leaf.fill"
    case .food: "fork.knife"
    case .activity: "soccerball"
    case .travel: "car.fill"
    case .objects: "lightbulb.fill"
    case .symbols: "heart.fill"
    case .flags: "flag.fill"
    }
  }
}

struct DiscordUnicodeEmoji: Identifiable, Hashable, Sendable {
  let character: String
  let names: [String]
  var name: String { names.first ?? character }
  var id: String { character }

  init(_ character: String, names: [String] = []) {
    self.character = character
    self.names = names
  }
}

enum DiscordEmojiNameIndex {
  private struct Entry: Decodable {
    let n: [String]
    let s: String
  }

  @MainActor private static var byCharacter: [String: [String]]?
  @MainActor private static var byName: [String: String]?
  /// Discord's spelling of each emoji, keyed by the character with every
  /// variation selector removed.
  @MainActor private static var byBareCharacter: [String: String]?
  @MainActor private static var categorizedEmojis: [EmojiCategory: [DiscordUnicodeEmoji]]?
  @MainActor private static var baseEmojis: [DiscordUnicodeEmoji]?

  @MainActor
  static var categories: [EmojiCategory: [DiscordUnicodeEmoji]] {
    loadIfNeeded()
    return categorizedEmojis ?? [:]
  }

  @MainActor
  static func search(_ query: String) -> [DiscordUnicodeEmoji] {
    loadIfNeeded()
    let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lower.isEmpty, let baseEmojis else { return [] }
    return baseEmojis.filter { emoji in
      emoji.names.contains { $0.lowercased().contains(lower) }
    }
  }

  @MainActor
  static func names(for character: String) -> [String]? {
    loadIfNeeded()
    if let exact = byCharacter?[character] {
      return exact
    }
    if let matched = byBareCharacter?[bare(character)] {
      return byCharacter?[matched]
    }
    return nil
  }

  @MainActor
  static func character(forName name: String) -> String? {
    loadIfNeeded()
    return byName?[name]
  }

  /// Maps a character onto Discord's spelling of it, or nil if Discord has no
  /// such emoji.
  @MainActor
  static func discordCharacter(matching character: String) -> String? {
    loadIfNeeded()
    if byCharacter?[character] != nil { return character }
    return byBareCharacter?[bare(character)]
  }

  private static func bare(_ character: String) -> String {
    character.replacingOccurrences(of: "\u{FE0F}", with: "")
  }

  @MainActor
  private static func loadIfNeeded() {
    guard byCharacter == nil else { return }
    guard
      let url = Bundle.main.url(forResource: "DiscordEmojiNames", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let entries = try? JSONDecoder().decode([Entry].self, from: data)
    else {
      byCharacter = [:]
      byName = [:]
      byBareCharacter = [:]
      categorizedEmojis = [:]
      baseEmojis = []
      return
    }
    byCharacter = Dictionary(entries.map { ($0.s, $0.n) }, uniquingKeysWith: { first, _ in first })
    var nameLookup: [String: String] = [:]
    for entry in entries {
      for name in entry.n where nameLookup[name] == nil {
        nameLookup[name] = entry.s
      }
    }
    byName = nameLookup
    var bareLookup: [String: String] = [:]
    for entry in entries where bareLookup[bare(entry.s)] == nil {
      bareLookup[bare(entry.s)] = entry.s
    }
    byBareCharacter = bareLookup

    var categoriesDict: [EmojiCategory: [DiscordUnicodeEmoji]] = [:]
    var allBase: [DiscordUnicodeEmoji] = []
    var currentCategory: EmojiCategory = .people

    for entry in entries {
      if let first = entry.n.first {
        switch first {
        case "dog": currentCategory = .nature
        case "green_apple": currentCategory = .food
        case "soccer": currentCategory = .activity
        case "red_car": currentCategory = .travel
        case "watch": currentCategory = .objects
        case "pink_heart": currentCategory = .symbols
        case "flag_white": currentCategory = .flags
        default: break
        }
      }

      // Exclude skin-tone variants from the default category grid and search list
      if entry.n.contains(where: { $0.contains("_tone") }) {
        continue
      }

      let emoji = DiscordUnicodeEmoji(entry.s, names: entry.n)
      categoriesDict[currentCategory, default: []].append(emoji)
      allBase.append(emoji)
    }

    categorizedEmojis = categoriesDict
    baseEmojis = allBase
  }
}
