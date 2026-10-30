//
//  SearchIntent.swift
//  AicordKit
//
//  A sentence ("who recommended a shipping agent last week") turned into
//  search filters by a model, as JSON.
//

import Foundation

public struct SearchIntent: Decodable, Sendable, Equatable {
  /// Keywords for Discord's search, not the whole sentence.
  public var keywords: String?
  public var author: String?
  public var server: String?
  public var channel: String?
  public var daysBack: Int?
  /// YYYY-MM-DD
  public var after: String?
  public var before: String?
  /// link, image, video, file, embed, sound, sticker or poll
  public var has: [String]?

  public init(
    keywords: String? = nil, author: String? = nil, server: String? = nil, channel: String? = nil,
    daysBack: Int? = nil, after: String? = nil, before: String? = nil, has: [String]? = nil
  ) {
    self.keywords = keywords
    self.author = author
    self.server = server
    self.channel = channel
    self.daysBack = daysBack
    self.after = after
    self.before = before
    self.has = has
  }

  enum CodingKeys: String, CodingKey {
    case keywords, author, server, channel, daysBack, after, before, has
  }

  /// Lenient: `has` may be one string, numbers may be strings, empty strings are nil.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func text(_ key: CodingKeys) -> String? {
      let value = (try? c.decodeIfPresent(String.self, forKey: key))??
        .trimmingCharacters(in: .whitespaces)
      guard let value, !value.isEmpty, value.lowercased() != "null" else { return nil }
      return value
    }
    keywords = text(.keywords)
    author = text(.author)?.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    server = text(.server)
    channel = text(.channel)?.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    after = text(.after)
    before = text(.before)
    daysBack =
      (try? c.decodeIfPresent(Int.self, forKey: .daysBack)) ?? text(.daysBack).flatMap { Int($0) }
    if let list = try? c.decodeIfPresent([String].self, forKey: .has) {
      has = list.map { $0.lowercased() }
    } else if let one = text(.has) {
      has = [one.lowercased()]
    }
    if has?.isEmpty == true { has = nil }
    if let days = daysBack, days <= 0 { daysBack = nil }
  }

  /// The first JSON object in a reply, also inside a ```json fence.
  public static func parse(_ output: String) -> SearchIntent? {
    guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
      start < end
    else { return nil }
    return try? JSONDecoder().decode(SearchIntent.self, from: Data(output[start...end].utf8))
  }

  public static func instructions(today: Date) -> String {
    let day = ISO8601DateFormatter.string(
      from: today, timeZone: .current, formatOptions: [.withFullDate])
    return """
      You turn a request to find Discord messages into search filters. Today \
      is \(day). Reply only with one JSON object with these optional fields: \
      "keywords" (2-4 words the messages would contain, not the whole \
      request), "author" (a person's name), "server", "channel", "daysBack" \
      (a number), "after" and "before" (YYYY-MM-DD), "has" (a list of: link, \
      image, video, file, embed, sound, sticker, poll). Leave out what the \
      request doesn't say.
      """
  }
}
