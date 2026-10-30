//
//  DiscordEmojiNameIndex.swift
//  Aicord
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

  private struct IndexStorage: Sendable {
    let byCharacter: [String: [String]]
    let byName: [String: String]
    let byBareCharacter: [String: String]
    let categorizedEmojis: [EmojiCategory: [DiscordUnicodeEmoji]]
    let baseEmojis: [DiscordUnicodeEmoji]
  }

  /// Lazily initialized, immutable, and thread-safe (`Sendable`) storage.
  private static let storage: IndexStorage = {
    guard
      let url = Bundle.main.url(forResource: "DiscordEmojiNames", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let entries = try? JSONDecoder().decode([Entry].self, from: data)
    else {
      return IndexStorage(
        byCharacter: [:],
        byName: [:],
        byBareCharacter: [:],
        categorizedEmojis: [:],
        baseEmojis: []
      )
    }

    var byCharacter: [String: [String]] = [:]
    byCharacter.reserveCapacity(entries.count)
    var nameLookup: [String: String] = [:]
    var bareLookup: [String: String] = [:]
    var categoriesDict: [EmojiCategory: [DiscordUnicodeEmoji]] = [:]
    var allBase: [DiscordUnicodeEmoji] = []
    var seenBaseCharacters = Set<String>()
    var currentCategory: EmojiCategory = .people

    for entry in entries {
      if byCharacter[entry.s] == nil {
        byCharacter[entry.s] = entry.n
      }
      for name in entry.n where nameLookup[name] == nil {
        nameLookup[name] = entry.s
      }
      let bareChar = bare(entry.s)
      if bareLookup[bareChar] == nil {
        bareLookup[bareChar] = entry.s
      }

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

      // Exclude skin-tone variants and deduplicate base emojis
      if entry.n.contains(where: { $0.contains("_tone") }) {
        continue
      }
      guard seenBaseCharacters.insert(entry.s).inserted else {
        continue
      }

      let emoji = DiscordUnicodeEmoji(entry.s, names: entry.n)
      categoriesDict[currentCategory, default: []].append(emoji)
      allBase.append(emoji)
    }

    return IndexStorage(
      byCharacter: byCharacter,
      byName: nameLookup,
      byBareCharacter: bareLookup,
      categorizedEmojis: categoriesDict,
      baseEmojis: allBase
    )
  }()

  static var categories: [EmojiCategory: [DiscordUnicodeEmoji]] {
    storage.categorizedEmojis
  }

  static func search(_ query: String) -> [DiscordUnicodeEmoji] {
    let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !lower.isEmpty else { return [] }
    return storage.baseEmojis.filter { emoji in
      emoji.names.contains { $0.lowercased().contains(lower) }
    }
  }

  static func names(for character: String) -> [String]? {
    if let exact = storage.byCharacter[character] {
      return exact
    }
    if let matched = storage.byBareCharacter[bare(character)] {
      return storage.byCharacter[matched]
    }
    return nil
  }

  static func character(forName name: String) -> String? {
    storage.byName[name]
  }

  /// Maps a character onto Discord's spelling of it, or nil if Discord has no
  /// such emoji.
  static func discordCharacter(matching character: String) -> String? {
    if storage.byCharacter[character] != nil { return character }
    return storage.byBareCharacter[bare(character)]
  }

  private static func bare(_ character: String) -> String {
    character.replacingOccurrences(of: "\u{FE0F}", with: "")
  }
}
