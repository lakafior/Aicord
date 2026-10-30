//
//  MessageSearch.swift
//  PaicordLib
//

import Foundation

/// Filters for message search. Array filters are sent as repeated query parameters.
/// https://docs.discord.food/resources/message#search-messages
public struct MessageSearchQuery: Sendable {
  public var content: String?
  public var channelIDs: [ChannelSnowflake]
  public var authorIDs: [UserSnowflake]
  /// e.g. "link", "embed", "file", "image", "video", "sound", "sticker", "poll"
  public var has: [String]
  public var offset: Int
  public var includeNSFW: Bool

  public init(
    content: String? = nil,
    channelIDs: [ChannelSnowflake] = [],
    authorIDs: [UserSnowflake] = [],
    has: [String] = [],
    offset: Int = 0,
    includeNSFW: Bool = true
  ) {
    self.content = content
    self.channelIDs = channelIDs
    self.authorIDs = authorIDs
    self.has = has
    self.offset = offset
    self.includeNSFW = includeNSFW
  }

  public var queries: [(String, String?)] {
    var items: [(String, String?)] = []
    if let content, !content.isEmpty { items.append(("content", content)) }
    items += channelIDs.map { ("channel_id", $0.rawValue) }
    items += authorIDs.map { ("author_id", $0.rawValue) }
    items += has.map { ("has", $0) }
    if offset > 0 { items.append(("offset", String(offset))) }
    if includeNSFW { items.append(("include_nsfw", "true")) }
    return items
  }
}

/// https://docs.discord.food/resources/message#search-messages
public struct MessageSearchResults: Sendable, Codable {
  public var total_results: Int
  /// Each inner array holds one match; older API versions added context messages around it.
  public var messages: [[DiscordChannel.Message]]
  public var doing_deep_historical_index: Bool?
}
