//
//  ThreadSearch.swift
//  AicordKit
//

import Foundation

/// Filters for a forum or media channel's posts. Leaving `archived` out searches
/// active and archived posts together.
/// https://docs.discord.food/resources/channel#search-threads
public struct ThreadSearchQuery: Sendable {
  public enum SortBy: String, Sendable {
    case lastMessageTime = "last_message_time"
    case archiveTime = "archive_time"
    case relevance
    case creationTime = "creation_time"
  }

  public var name: String?
  public var tags: [ForumTagSnowflake]
  public var archived: Bool?
  public var sortBy: SortBy
  public var ascending: Bool
  /// 1–25.
  public var limit: Int
  public var offset: Int

  public init(
    name: String? = nil,
    tags: [ForumTagSnowflake] = [],
    archived: Bool? = nil,
    sortBy: SortBy = .lastMessageTime,
    ascending: Bool = false,
    limit: Int = 25,
    offset: Int = 0
  ) {
    self.name = name
    self.tags = tags
    self.archived = archived
    self.sortBy = sortBy
    self.ascending = ascending
    self.limit = limit
    self.offset = offset
  }

  public var queries: [(String, String?)] {
    var items: [(String, String?)] = []
    if let name, !name.isEmpty { items.append(("name", name)) }
    items += tags.map { ("tag", $0.rawValue) }
    if !tags.isEmpty { items.append(("tag_setting", "match_some")) }
    if let archived { items.append(("archived", archived ? "true" : "false")) }
    items.append(("sort_by", sortBy.rawValue))
    items.append(("sort_order", ascending ? "asc" : "desc"))
    items.append(("limit", String(limit)))
    if offset > 0 { items.append(("offset", String(offset))) }
    return items
  }
}

/// https://docs.discord.food/resources/channel#search-threads
public struct ThreadSearchResults: Sendable, Decodable {
  public var threads: [DiscordChannel]
  /// The current user's membership, for the posts they joined.
  public var members: [ThreadMember]?
  public var has_more: Bool?
  public var total_results: Int?
  /// The opening message of each post, for previews.
  public var first_messages: [DiscordChannel.Message]?
}
