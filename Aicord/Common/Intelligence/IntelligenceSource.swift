//
//  IntelligenceSource.swift
//  Aicord
//
//  The messages a summary reads: fetched from Discord, filtered the way the
//  chat filters them, and written out as numbered lines.
//

import AicordKit
import Foundation

/// Numbered message lines and the messages they stand for.
struct IntelligenceTranscript {
  var lines: [String] = []
  /// `messages[n - 1]` is the message cited as `[n]`.
  var messages: [DiscordChannel.Message] = []
  /// Messages left out because the word filter, a block or a content setting hides them.
  var hiddenCount = 0

  var isEmpty: Bool { lines.isEmpty }

  func message(for ref: Int) -> DiscordChannel.Message? {
    messages.indices.contains(ref - 1) ? messages[ref - 1] : nil
  }
}

@MainActor
enum IntelligenceSource {
  /// Up to `limit` of the newest messages, oldest first, newer than `after`
  /// when given. Pages of 100, as Discord allows.
  static func fetchMessages(
    channelId: ChannelSnowflake,
    limit: Int,
    after: MessageSnowflake? = nil,
    gw: GatewayStore
  ) async throws -> [DiscordChannel.Message] {
    let client = gw.client
    var collected: [DiscordChannel.Message] = []
    var before: MessageSnowflake?
    while collected.count < limit {
      try Task.checkCancellation()
      let page = min(100, limit - collected.count)
      let res = try await client.listMessages(channelId: channelId, before: before, limit: page)
      try res.guardSuccess()
      var fetched = try res.decode()  // newest first
      if let after { fetched = fetched.filter { $0.id > after } }
      collected += fetched
      guard fetched.count == page, let oldest = fetched.last else { break }
      before = oldest.id
    }
    return collected.reversed()
  }

  /// Lines for the model. Leaves out what the chat would hide: blocked or
  /// ignored people, the word filter's matches, spoilers and media blocked or
  /// blurred by Content & Social.
  static func transcript(
    of messages: [DiscordChannel.Message],
    guildId: GuildSnowflake?,
    gw: GatewayStore,
    maxCharacters: Int = 600,
    into existing: IntelligenceTranscript = IntelligenceTranscript(),
    describesPlace: Bool = false
  ) -> IntelligenceTranscript {
    var transcript = existing
    let known = Set(existing.messages.map(\.id))
    let inServer = guildId != nil
    let guildChannels = guildId.flatMap { gw.user.guilds[$0]?.channels } ?? []
    let channelNames = Dictionary(
      guildChannels.map { ($0.id.rawValue, $0.name ?? "channel") },
      uniquingKeysWith: { first, _ in first })
    let roleNames = Dictionary(
      (guildId.flatMap { gw.user.guilds[$0]?.roles } ?? []).map { ($0.id.rawValue, $0.name) },
      uniquingKeysWith: { first, _ in first })

    for message in messages where !known.contains(message.id) {
      guard let author = message.author else { continue }
      if let relationship = gw.user.relationships[author.id],
        relationship.type == .blocked || relationship.user_ignored
      {
        transcript.hiddenCount += 1
        continue
      }
      let origin = gw.origin(authorId: author.id, inServer: inServer)
      let snapshotText = message.message_snapshots?.first.map { "(forwarded) " + $0.message.content }
      let raw = [message.content, snapshotText ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
      if WordFilter.hides(raw, origin: origin) {
        transcript.hiddenCount += 1
        continue
      }

      var userNames: [String: String] = [:]
      for user in message.mentions {
        userNames[user.id.rawValue] = user.global_name ?? user.username
      }
      var text = IntelligenceText.clean(
        raw, userNames: userNames, channelNames: channelNames, roleNames: roleNames)

      // media: say what was shared, unless Content & Social hides it
      let filter = MediaFilter(origin: origin, settings: gw.settings.userSettings)
      let attachments = message.attachments.filter { filter.redaction(for: $0) == .show }
      if !attachments.isEmpty {
        let names = attachments.prefix(3).map { attachment in
          let kind =
            attachment.content_type?.hasPrefix("image") == true
            ? "image" : attachment.content_type?.hasPrefix("video") == true ? "video" : "file"
          let label = attachment.description ?? attachment.title ?? attachment.filename
          return "[\(kind): \(label)]"
        }
        text += (text.isEmpty ? "" : " ") + names.joined(separator: " ")
      }
      // bots often write in embeds
      for embed in message.embeds.prefix(2) where filter.redaction(for: embed) == .show {
        let parts = [embed.title, embed.description].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { continue }
        text +=
          (text.isEmpty ? "" : " ") + "[embed: "
          + IntelligenceText.clean(parts.joined(separator: " – ")) + "]"
      }
      if let poll = message.poll {
        text += (text.isEmpty ? "" : " ") + "[poll: \(poll.question.text ?? "")]"
      }
      guard !text.isEmpty else { continue }

      if let reply = message.referenced_message?.value, let replyAuthor = reply.author {
        text = "(replying to \(replyAuthor.global_name ?? replyAuthor.username)) " + text
      }
      var name = message.member?.nick ?? author.global_name ?? author.username
      if describesPlace {
        // search results come from anywhere and any time
        let date = message.timestamp.date.formatted(.iso8601.year().month().day())
        let channel = channelNames[message.channel_id.rawValue].map { " #\($0)" } ?? ""
        name += " (\(date)\(channel))"
      }
      transcript.messages.append(message)
      transcript.lines.append(
        IntelligenceText.line(
          ref: transcript.messages.count, author: name, text: text,
          maxCharacters: maxCharacters))
    }
    return transcript
  }

  /// The server a channel belongs to, from the loaded server list.
  static func guildId(of channelId: ChannelSnowflake, gw: GatewayStore) -> GuildSnowflake? {
    gw.user.guilds.values.first { $0.channels?.contains { $0.id == channelId } == true }?.id
  }

  static func isDirectMessage(_ channelId: ChannelSnowflake, gw: GatewayStore) -> Bool {
    gw.user.privateChannels[channelId] != nil
  }
}
