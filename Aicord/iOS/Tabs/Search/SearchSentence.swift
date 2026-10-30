//
//  SearchSentence.swift
//  Aicord
//
//  "Search with a Sentence": a request in plain words turned into the Search
//  tab's filters. Only the sentence goes to the model; names are matched to
//  servers, channels and people on the device.
//

import AicordKit
import SwiftUI

extension SearchView {
  /// At least three words reads as a sentence rather than keywords.
  var looksLikeSentence: Bool {
    query.split(separator: " ").count >= 3
  }

  func searchWithSentence() {
    let sentence = query
    guard !sentence.isEmpty else { return }
    let model: IntelligenceModel
    switch IntelligenceModel.current() {
    case .success(let current): model = current
    case .failure(let reason):
      appState.error = reason
      return
    }
    sentenceTask?.cancel()
    sentenceTask = Task {
      interpreting = true
      defer { interpreting = false }
      do {
        let reply = try await model.respond(
          instructions: SearchIntent.instructions(today: .now), prompt: sentence)
        guard let intent = SearchIntent.parse(reply) else {
          throw IntelligenceError("The model didn't return filters. Try rewording the request.")
        }
        apply(intent, sentence: sentence)
      } catch is CancellationError {
      } catch {
        appState.error = error
      }
    }
  }

  /// The longest server name the sentence mentions as a whole word.
  static func guildNamed(in sentence: String, gw: GatewayStore) -> String? {
    let words = Set(
      sentence.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    return gw.user.guilds.values.map(\.name)
      .filter { name in
        let parts = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return name.count >= 3 && !parts.isEmpty && parts.allSatisfy { words.contains(String($0)) }
      }
      .max { $0.count < $1.count }
  }

  /// A text channel you can read, the exact name first.
  func readableChannel(named name: String, in guild: GuildSnowflake) -> DiscordChannel? {
    let store = gw.existingGuildStore(for: guild)
    let channels = (gw.user.guilds[guild]?.channels ?? []).filter {
      [.guildText, .guildAnnouncement, .guildForum].contains($0.type)
        && store?.hasPermission(channel: $0, .viewChannel) != false
        && store?.hasPermission(channel: $0, .readMessageHistory) != false
    }
    return channels.first { ($0.name ?? "").caseInsensitiveCompare(name) == .orderedSame }
      ?? channels.first { ($0.name ?? "").localizedCaseInsensitiveContains(name) }
  }

  /// Sets tokens, has-filters and dates from what the model understood.
  func apply(_ intent: SearchIntent, sentence: String) {
    var newTokens = tokens
    var guild = serverID
    var intent = intent
    if intent.server == nil, guild == nil, let named = Self.guildNamed(in: sentence, gw: gw) {
      // small models often leave the server out even when the sentence names it
      intent.server = named
    }
    if let name = intent.server,
      let match = gw.user.guilds.values.first(where: {
        $0.name.caseInsensitiveCompare(name) == .orderedSame
      })
        ?? gw.user.guilds.values.first(where: { $0.name.localizedCaseInsensitiveContains(name) })
    {
      guild = match.id
      newTokens.removeAll { $0.kind == .server || $0.kind == .channel }
      newTokens.append(.server(match.id))
    }
    if let name = intent.channel, let guild, let channel = readableChannel(named: name, in: guild) {
      newTokens.removeAll { $0.kind == .server || $0.kind == .channel }
      newTokens.append(.channel(guild, channel.id))
    }
    if let name = intent.author {
      let previous = text
      text = name
      if let person = people.first { 
        newTokens.removeAll { $0.kind == .user }
        newTokens.append(.user(person.id))
      }
      text = previous
    }
    has = Set((intent.has ?? []).compactMap(HasFilter.init(rawValue:)))
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    day.locale = Locale(identifier: "en_US_POSIX")
    if let days = intent.daysBack {
      filters.from = Calendar.current.date(byAdding: .day, value: -days, to: .now)
      filters.to = nil
    }
    if let after = intent.after.flatMap(day.date(from:)) { filters.from = after }
    if let before = intent.before.flatMap(day.date(from:)) { filters.to = before }
    tokens = newTokens
    // names that became tokens aren't words to look for
    var keywords = intent.keywords ?? ""
    for name in [intent.server, intent.channel, intent.author].compactMap({ $0 }) {
      keywords = keywords.replacingOccurrences(of: name, with: "", options: .caseInsensitive)
    }
    text = keywords.split(separator: " ").joined(separator: " ")
    rankingSentence = sentence
    rankedText = text
    sortByRelevance = true
    runMessageSearch(debounce: false)
  }
}
