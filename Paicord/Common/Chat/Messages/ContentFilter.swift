//
//  ContentFilter.swift
//  Paicord
//
//  Filters from Settings → Content & Social applied to messages: Discord's
//  sensitive media settings and the optional community word list.
//

import Foundation
import PaicordLib
import SwiftUI

/// Where a message came from; Discord's content settings differ per origin.
enum MessageOrigin {
  case friendDM
  case otherDM
  case server
}

extension ChannelStore {
  /// `nil` for your own messages, which are never filtered.
  func origin(of message: DiscordChannel.PartialMessage) -> MessageOrigin? {
    let authorId = message.author?.id
    if let authorId, authorId == gateway?.user.currentUser?.id { return nil }
    if channel?.guild_id != nil || guildStore != nil { return .server }
    if let authorId, gateway?.user.relationships[authorId]?.type == .friend {
      return .friendDM
    }
    return .otherDM
  }
}

// MARK: - Sensitive media

enum MediaRedaction: Int, Comparable {
  case show, blur, block

  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Decides how flagged attachments and embeds of one message are shown.
struct MediaFilter {
  typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  typealias Redaction = Settings.ExplicitContentRedaction

  let origin: MessageOrigin?
  let settings: Settings

  func redaction(for attachment: DiscordChannel.Message.Attachment) -> MediaRedaction {
    let flags = attachment.flags
    return redaction(
      explicit: flags?.contains(.containsExplicitMedia) == true,
      gore: flags?.contains(.containsGoreContent) == true
    )
  }

  func redaction(for embed: Embed) -> MediaRedaction {
    let flags = embed.flags
    return redaction(
      explicit: flags?.contains(.containsExplicitMedia) == true,
      gore: flags?.contains(.containsGoreContent) == true
    )
  }

  private func redaction(explicit: Bool, gore: Bool) -> MediaRedaction {
    guard let origin, explicit || gore else { return .show }
    let textAndImages = settings.textAndImages
    var result = MediaRedaction.show
    if explicit {
      let explicitSettings = textAndImages.explicitContentSettings
      result = max(
        result,
        Self.resolve(
          origin == .server
            ? explicitSettings.explicitContentGuilds
            : origin == .friendDM
              ? explicitSettings.explicitContentFriendDm
              : explicitSettings.explicitContentNonFriendDm,
          origin: origin
        )
      )
    }
    if gore {
      let goreSettings = textAndImages.goreContentSettings
      result = max(
        result,
        Self.resolve(
          origin == .server
            ? goreSettings.goreContentGuilds
            : origin == .friendDM
              ? goreSettings.goreContentFriendDm
              : goreSettings.goreContentNonFriendDm,
          origin: origin
        )
      )
    }
    return result
  }

  /// Unset means block for DMs from non-friends and show elsewhere (docs.discord.food).
  static func resolve(_ value: Redaction, origin: MessageOrigin) -> MediaRedaction {
    switch value {
    case .show: .show
    case .blur: .blur
    case .block: .block
    case .unsetExplicitContentRedaction, .UNRECOGNIZED:
      origin == .otherDM ? .block : .show
    }
  }
}

/// Blurs media until tapped.
struct SensitiveMediaCover<Content: View>: View {
  @ViewBuilder var content: Content
  @State private var revealed = false

  var body: some View {
    if revealed {
      content
    } else {
      content
        .blur(radius: 40, opaque: true)
        .clipShape(.rect(cornerRadius: 8))
        .allowsHitTesting(false)
        .overlay {
          VStack(spacing: 6) {
            Image(systemName: "eye.slash")
              .font(.title2)
            Text("Sensitive Content")
              .font(.subheadline.weight(.semibold))
            Button("Show") {
              revealed = true
            }
            .buttonStyle(.bordered)
          }
          .foregroundStyle(.white)
          .shadow(radius: 4)
        }
        .accessibilityElement(children: .combine)
    }
  }
}

/// One line saying something was hidden, with an optional "Show".
struct HiddenContentNote: View {
  let text: LocalizedStringKey
  var show: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "eye.slash")
      Text(text)
      if let show {
        Button("Show", action: show)
          .buttonStyle(.borderless)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

// MARK: - Community word list

/// Optional filter of Aicord's own on top of Discord's keyword filters: the
/// bundled LDNOOBW lists (CC BY 4.0) plus words the user adds.
@MainActor
final class WordFilter {
  static let shared = WordFilter()

  enum Scope: String, CaseIterable {
    case nonFriendDMs
    case everywhere
  }

  enum Key {
    static let enabled = "contentFilter.communityList"
    static let languages = "contentFilter.languages"
    static let customWords = "contentFilter.customWords"
    static let scope = "contentFilter.scope"
  }

  /// Languages without spaces between words, matched as substrings.
  private static let unspacedLanguages: Set<String> = ["ja", "zh", "th"]

  /// Language codes with a bundled list.
  static let availableLanguages: [String] = {
    guard
      let urls = Bundle.main.urls(
        forResourcesWithExtension: "txt", subdirectory: "WordLists")
    else { return [] }
    return urls.map { $0.deletingPathExtension().lastPathComponent }
      .filter { $0 != "LICENSE" }
      .sorted()
  }()

  /// The app language and English, when no choice was saved yet.
  static var defaultLanguages: String {
    let current = Locale.current.language.languageCode?.identifier ?? "en"
    return Set([current, "en"]).intersection(availableLanguages).sorted()
      .joined(separator: ",")
  }

  private var signature = ""
  private var words: Set<String> = []
  private var phrases: [String] = []
  private var substrings: [String] = []
  private var results: [String: Bool] = [:]

  func matches(_ text: String, languages: String, customWords: String) -> Bool {
    guard !text.isEmpty else { return false }
    load(languages: languages, customWords: customWords)
    if let cached = results[text] { return cached }
    if results.count > 4_000 { results.removeAll() }

    let normalized = Self.normalize(text)
    let tokens = Self.tokens(normalized)
    var found = tokens.contains { words.contains($0) }
    if !found, !phrases.isEmpty {
      let joined = " " + tokens.joined(separator: " ") + " "
      found = phrases.contains { joined.contains(" \($0) ") }
    }
    if !found {
      found = substrings.contains { normalized.contains($0) }
    }
    results[text] = found
    return found
  }

  private func load(languages: String, customWords: String) {
    let newSignature = languages + "|" + customWords
    guard newSignature != signature else { return }
    signature = newSignature
    words = []
    phrases = []
    substrings = []
    results = [:]

    var entries: [(String, unspaced: Bool)] = []
    for code in languages.split(separator: ",").map(String.init) {
      guard
        let url = Bundle.main.url(
          forResource: code, withExtension: "txt", subdirectory: "WordLists"),
        let list = try? String(contentsOf: url, encoding: .utf8)
      else { continue }
      let unspaced = Self.unspacedLanguages.contains(code)
      entries += list.split(whereSeparator: \.isNewline).map { (String($0), unspaced) }
    }
    entries += customWords.split(whereSeparator: { $0 == "," || $0.isNewline })
      .map { (String($0), false) }

    for (entry, unspaced) in entries {
      let normalized = Self.normalize(entry)
      if unspaced {
        let trimmed = normalized.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { substrings.append(trimmed) }
        continue
      }
      let parts = Self.tokens(normalized)
      if parts.count == 1 {
        words.insert(parts[0])
      } else if parts.count > 1 {
        phrases.append(parts.joined(separator: " "))
      }
    }
  }

  private static func normalize(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: nil
    )
  }

  private static func tokens(_ text: String) -> [String] {
    text.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }
}
