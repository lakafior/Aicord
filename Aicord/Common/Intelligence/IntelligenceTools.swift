//
//  IntelligenceTools.swift
//  Aicord
//
//  Read-only lookups a model may make while answering: Discord's message
//  search, the messages around one, and a reply chain. The same lookups run
//  as Foundation Models tools on device and as functions over the API.
//

import AicordKit
import Foundation
import FoundationModels

/// What a search asks for, from either kind of model.
struct MessageSearchRequest: Decodable, Sendable {
  var text: String?
  var author: String?
  var channel: String?
  var daysBack: Int?
  var after: String?
  var before: String?
  var has: String?
  var pattern: String?
}

/// The lookups behind one question, with the messages they turned up. The
/// numbers the model cites index `transcript`, across all lookups.
@MainActor
final class MessageToolbox {
  let gw: GatewayStore
  let guildId: GuildSnowflake?
  /// The channel asked about; searches in a DM stay in it.
  let channelId: ChannelSnowflake
  let maxCalls: Int
  /// How many results and how much of each the model gets back.
  let resultLimit: Int
  let maxCharacters: Int

  private(set) var transcript = IntelligenceTranscript()
  /// What was searched for, shown under the answer.
  private(set) var searches: [String] = []
  private(set) var calls = 0
  var onChange: (() -> Void)?
  /// What the reader asked; search results that fit it best are kept when
  /// there are more than the model can take.
  var question: String?

  init(
    gw: GatewayStore, guildId: GuildSnowflake?, channelId: ChannelSnowflake, onDevice: Bool
  ) {
    self.gw = gw
    self.guildId = guildId
    self.channelId = channelId
    maxCalls = onDevice ? 3 : 6
    resultLimit = onDevice ? 6 : 15
    maxCharacters = onDevice ? 220 : 500
  }

  /// Messages given to the model up front, numbered like lookup results.
  func add(_ messages: [DiscordChannel.Message]) -> [String] {
    let before = transcript.lines.count
    transcript = IntelligenceSource.transcript(
      of: messages, guildId: guildId, gw: gw, maxCharacters: maxCharacters, into: transcript)
    return Array(transcript.lines[before...])
  }

  private func spendCall() -> String? {
    guard calls < maxCalls else { return ToolAgent.limitReached }
    calls += 1
    return nil
  }

  // MARK: search

  func search(_ request: MessageSearchRequest) async -> String {
    if let limit = spendCall() { return limit }
    var query = MessageSearchQuery()
    var described: [String] = []
    if let text = request.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
      query.content = text
      described.append(text)
    }
    if let author = request.author, !author.isEmpty {
      let ids = authorIDs(matching: author)
      guard !ids.isEmpty else {
        return "Nobody called \(author) was found here. Try without the author or another spelling."
      }
      query.authorIDs = ids
      described.append("from \(author)")
    }
    var scopeChannel: ChannelSnowflake?
    if guildId == nil {
      scopeChannel = channelId
    } else if let name = request.channel, !name.isEmpty {
      guard let channel = channel(named: name) else {
        return "There is no channel called \(name) here."
      }
      query.channelIDs = [channel.id]
      described.append("#" + (channel.name ?? name))
    }
    if let days = request.daysBack, days > 0 {
      query.minID = MessageSearchQuery.boundary(for: .now.addingTimeInterval(-Double(days) * 86_400))
      described.append(days == 1 ? "last day" : "last \(days) days")
    }
    if let after = request.after.flatMap(Self.day) {
      query.minID = MessageSearchQuery.boundary(for: after)
      described.append("after \(request.after ?? "")")
    }
    if let before = request.before.flatMap(Self.day) {
      query.maxID = MessageSearchQuery.boundary(for: before.addingTimeInterval(86_400))
      described.append("before \(request.before ?? "")")
    }
    if let has = request.has?.lowercased(),
      ["link", "image", "file", "video", "embed", "sound", "sticker", "poll"].contains(has)
    {
      query.has = [has]
      described.append("has \(has)")
    }
    var regex: NSRegularExpression?
    if let pattern = request.pattern, !pattern.isEmpty {
      regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
      described.append("/\(pattern)/")
    }
    searches.append(described.isEmpty ? String(localized: "everything") : described.joined(separator: " · "))
    onChange?()

    do {
      let res =
        if let scopeChannel {
          try await gw.client.searchChannelMessages(channelID: scopeChannel, query: query)
        } else if let guildId {
          try await gw.client.searchGuildMessages(guildID: guildId, query: query)
        } else {
          try await gw.client.searchChannelMessages(channelID: channelId, query: query)
        }
      if res.httpResponse.status == .accepted {
        return "Search isn't ready for this server yet (Discord is still indexing it). Answer from the messages you have."
      }
      if res.httpResponse.status == .tooManyRequests {
        return "Search is rate limited right now. Answer from the messages you have."
      }
      try res.guardSuccess()
      let page = try res.decode()
      var found = page.messages.compactMap(\.first)
      if let regex {
        found = found.filter {
          regex.firstMatch(in: $0.content, range: NSRange($0.content.startIndex..., in: $0.content))
            != nil
        }
      }
      guard !found.isEmpty else { return "No messages found." }
      let kept = await Self.best(
        found, for: [question, request.text].compactMap { $0 }.joined(separator: " "),
        limit: resultLimit)
      let before = transcript.lines.count
      transcript = IntelligenceSource.transcript(
        of: kept, guildId: guildId, gw: gw,
        maxCharacters: maxCharacters, into: transcript, describesPlace: true)
      let lines = transcript.lines[before...]
      onChange?()
      if lines.isEmpty { return "Found messages, but all of them are hidden by the reader's filters." }
      return "Found \(page.total_results) messages, the \(lines.count) closest to the question, oldest first:\n"
        + lines.joined(separator: "\n")
    } catch {
      return "The search failed: \(error.localizedDescription)"
    }
  }

  /// The `limit` messages that match `query` best, oldest first; the newest
  /// when there's nothing to rank by.
  static func best(
    _ messages: [DiscordChannel.Message], for query: String, limit: Int
  ) async -> [DiscordChannel.Message] {
    guard messages.count > limit else { return messages.reversed() }
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return Array(messages.prefix(limit)).reversed() }
    let order = await SemanticRanker.rank(
      query: query, documents: messages.map(SemanticRanker.document(for:)))
    return order.prefix(limit).map { messages[$0] }.sorted { $0.id < $1.id }
  }

  // MARK: messages around

  func messagesAround(ref: Int, count: Int) async -> String {
    if let limit = spendCall() { return limit }
    guard let message = transcript.message(for: ref) else { return "There is no message [\(ref)]." }
    do {
      let res = try await gw.client.listMessages(
        channelId: message.channel_id, around: message.id, limit: max(5, min(count, 25)))
      try res.guardSuccess()
      let messages = try res.decode().reversed()
      let before = transcript.lines.count
      transcript = IntelligenceSource.transcript(
        of: Array(messages), guildId: guildId, gw: gw, maxCharacters: maxCharacters,
        into: transcript)
      onChange?()
      let lines = transcript.lines[before...]
      return lines.isEmpty
        ? "No other readable messages around [\(ref)]."
        : "Messages around [\(ref)] not seen before, oldest first:\n" + lines.joined(separator: "\n")
    } catch {
      return "Couldn't load messages around [\(ref)]: \(error.localizedDescription)"
    }
  }

  // MARK: reply chain

  /// The messages a message replies to, up to its start.
  func replyChain(ref: Int) async -> String {
    if let limit = spendCall() { return limit }
    guard var message = transcript.message(for: ref) else { return "There is no message [\(ref)]." }
    var chain: [DiscordChannel.Message] = []
    for _ in 0..<8 {
      guard let parentID = message.message_reference?.message_id,
        message.message_reference?.type != .forward
      else { break }
      if let parent = message.referenced_message?.value, parent.id == parentID {
        message = parent
      } else {
        let channel = message.message_reference?.channel_id ?? message.channel_id
        guard let res = try? await gw.client.getMessage(channelId: channel, messageId: parentID),
          (try? res.guardSuccess()) != nil, let parent = try? res.decode()
        else { break }
        message = parent
      }
      chain.append(message)
    }
    guard !chain.isEmpty else { return "[\(ref)] doesn't reply to another message." }
    transcript = IntelligenceSource.transcript(
      of: chain.reversed(), guildId: guildId, gw: gw, maxCharacters: maxCharacters,
      into: transcript)
    onChange?()
    let ids = Set(chain.map(\.id))
    let lines = transcript.messages.indices.filter { ids.contains(transcript.messages[$0].id) }
      .map { transcript.lines[$0] }
    return "The replies leading to [\(ref)], oldest first:\n" + lines.joined(separator: "\n")
  }

  // MARK: helpers

  private static func day(_ text: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: text.trimmingCharacters(in: .whitespaces))
  }

  private func channel(named name: String) -> DiscordChannel? {
    let wanted = name.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
    let channels = guildId.flatMap { gw.user.guilds[$0]?.channels } ?? []
    return channels.first { ($0.name ?? "").lowercased() == wanted }
      ?? channels.first { ($0.name ?? "").lowercased().contains(wanted) }
  }

  /// People whose name, nickname or username matches, from what the app knows.
  private func authorIDs(matching name: String) -> [UserSnowflake] {
    let wanted = name.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
    guard !wanted.isEmpty else { return [] }
    var ids: [UserSnowflake] = []
    func consider(_ id: UserSnowflake, _ names: [String?]) {
      guard !ids.contains(id) else { return }
      if names.compactMap({ $0?.lowercased() }).contains(where: { $0 == wanted || $0.contains(wanted) })
      {
        ids.append(id)
      }
    }
    for message in transcript.messages {
      if let author = message.author {
        consider(author.id, [message.member?.nick, author.global_name, author.username])
      }
    }
    if let guildId, let store = gw.existingGuildStore(for: guildId) {
      for member in store.loadedMembers {
        if let user = member.user { consider(user.id, [member.nick, user.global_name, user.username]) }
      }
    }
    for user in gw.user.users.values { consider(user.id, [user.global_name, user.username]) }
    return Array(ids.prefix(5))
  }
}

// MARK: - Over the API

extension MessageToolbox {
  func apiTools() -> [ToolAgent.Tool] {
    [
      ToolAgent.Tool(
        name: "search_messages",
        description: Self.searchDescription,
        parameters: .objectSchema([
          ("text", "string", "Words the messages contain"),
          ("author", "string", "Name of who wrote them"),
          ("channel", "string", "Channel name, without #"),
          ("daysBack", "integer", "Only the last this many days"),
          ("after", "string", "Only after this day, YYYY-MM-DD"),
          ("before", "string", "Only before this day, YYYY-MM-DD"),
          ("has", "string", "link, image, file, video or embed"),
          ("pattern", "string", "A regular expression the text must match"),
        ])
      ) { [self] arguments in
        let request =
          (try? JSONDecoder().decode(MessageSearchRequest.self, from: Data(arguments.utf8)))
          ?? MessageSearchRequest()
        return await search(request)
      },
      ToolAgent.Tool(
        name: "messages_around",
        description: Self.aroundDescription,
        parameters: .objectSchema(
          [
            ("message", "integer", "The number of a message already seen, like 12 for [12]"),
            ("count", "integer", "How many messages, up to 25"),
          ], required: ["message"])
      ) { [self] arguments in
        let args = (try? JSONDecoder().decode(RefArguments.self, from: Data(arguments.utf8)))
        return await messagesAround(ref: args?.message ?? 0, count: args?.count ?? 15)
      },
      ToolAgent.Tool(
        name: "reply_chain",
        description: Self.chainDescription,
        parameters: .objectSchema(
          [("message", "integer", "The number of a message already seen")], required: ["message"])
      ) { [self] arguments in
        let args = (try? JSONDecoder().decode(RefArguments.self, from: Data(arguments.utf8)))
        return await replyChain(ref: args?.message ?? 0)
      },
    ]
  }

  struct RefArguments: Decodable {
    var message: Int?
    var count: Int?
  }

  nonisolated static let searchDescription =
    "Searches this server's messages (or this conversation's) with Discord's search. Use short keywords, not sentences. Results are numbered like the other messages."
  nonisolated static let aroundDescription =
    "Loads the messages just before and after a message you have seen, to read the conversation it belongs to."
  nonisolated static let chainDescription =
    "Follows the replies a message is part of, back to where they started."
}

// MARK: - On device

struct SearchMessagesTool: Tool {
  let toolbox: MessageToolbox
  let name = "searchMessages"
  let description = MessageToolbox.searchDescription

  @Generable
  struct Arguments {
    @Guide(description: "Keywords the messages contain")
    var text: String?
    @Guide(description: "Name of who wrote them")
    var author: String?
    @Guide(description: "Channel name, without #")
    var channel: String?
    @Guide(description: "Only the last this many days")
    var daysBack: Int?
    @Guide(description: "link, image, file, video or embed")
    var has: String?
  }

  func call(arguments: Arguments) async throws -> String {
    await toolbox.search(
      MessageSearchRequest(
        text: arguments.text, author: arguments.author, channel: arguments.channel,
        daysBack: arguments.daysBack, has: arguments.has))
  }
}

struct MessagesAroundTool: Tool {
  let toolbox: MessageToolbox
  let name = "messagesAround"
  let description = MessageToolbox.aroundDescription

  @Generable
  struct Arguments {
    @Guide(description: "The number of a message already seen, like 12 for [12]")
    var message: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await toolbox.messagesAround(ref: arguments.message, count: 10)
  }
}

struct ReplyChainTool: Tool {
  let toolbox: MessageToolbox
  let name = "replyChain"
  let description = MessageToolbox.chainDescription

  @Generable
  struct Arguments {
    @Guide(description: "The number of a message already seen")
    var message: Int
  }

  func call(arguments: Arguments) async throws -> String {
    await toolbox.replyChain(ref: arguments.message)
  }
}

extension IntelligenceModel {
  /// An answer that may look things up first. Its citations index the
  /// toolbox's transcript.
  func answer(instructions: String, prompt: String, toolbox: MessageToolbox) async throws
    -> String
  {
    switch backend {
    case .api(let client):
      let agent = ToolAgent(tools: await toolbox.apiTools(), maxCalls: await toolbox.maxCalls) {
        messages, tools in
        try await client.turn(messages, tools: tools)
      }
      return try await agent.answer(instructions: instructions, prompt: prompt)
    case .onDevice:
      let tools: [any Tool] = [
        SearchMessagesTool(toolbox: toolbox), MessagesAroundTool(toolbox: toolbox),
        ReplyChainTool(toolbox: toolbox),
      ]
      let session = LanguageModelSession(tools: tools, instructions: instructions)
      return try await session.respond(to: prompt).content
    }
  }
}
