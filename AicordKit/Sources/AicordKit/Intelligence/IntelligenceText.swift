//
//  IntelligenceText.swift
//  AicordKit
//
//  Turning messages into compact numbered lines for a language model, and
//  splitting them into pieces that fit its context window.
//

import Foundation

public enum IntelligenceText {
  /// A rough token count. Models count about four characters per token in
  /// English and fewer in other languages, so three keeps on the safe side.
  public static func estimatedTokens(_ text: String) -> Int {
    (text.count + 2) / 3
  }

  /// Message text as a model should read it: mentions as names, custom emoji
  /// as `:name:`, timestamps and markup left out, on one line.
  public static func clean(
    _ content: String,
    userNames: [String: String] = [:],
    channelNames: [String: String] = [:],
    roleNames: [String: String] = [:]
  ) -> String {
    var text = content
    text = replace(#"<@!?(\d+)>"#, in: text) { "@" + (userNames[$0] ?? "someone") }
    text = replace(#"<#(\d+)>"#, in: text) { "#" + (channelNames[$0] ?? "channel") }
    text = replace(#"<@&(\d+)>"#, in: text) { "@" + (roleNames[$0] ?? "role") }
    text = replace(#"<a?:(\w+):\d+>"#, in: text) { ":\($0):" }
    text = replace(#"<t:(\d+)(?::\w)?>"#, in: text) { raw in
      guard let seconds = TimeInterval(raw) else { return raw }
      return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }
    // spoilers stay hidden from the model too
    text = replace(#"\|\|(.+?)\|\|"#, in: text) { _ in "[spoiler]" }
    text = text.replacingOccurrences(of: "```", with: " ")
    return
      text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .joined(separator: " / ")
  }

  /// One numbered line per message: `[3] Name: text`. The number is what the
  /// model cites, so links back to the message survive a summary.
  public static func line(ref: Int, author: String, text: String, maxCharacters: Int = 600)
    -> String
  {
    var body = text
    if body.count > maxCharacters {
      body = String(body.prefix(maxCharacters)) + "…"
    }
    return "[\(ref)] \(author): \(body)"
  }

  /// Lines grouped in order into pieces of at most `tokenBudget` tokens. A line
  /// too long on its own is cut to fit.
  public static func chunks(_ lines: [String], tokenBudget: Int) -> [[String]] {
    let budget = max(tokenBudget, 16)
    var result: [[String]] = []
    var current: [String] = []
    var used = 0
    for var line in lines {
      var cost = estimatedTokens(line) + 1
      if cost > budget {
        line = String(line.prefix(budget * 3 - 6)) + "…"
        cost = estimatedTokens(line) + 1
      }
      if used + cost > budget, !current.isEmpty {
        result.append(current)
        current = []
        used = 0
      }
      current.append(line)
      used += cost
    }
    if !current.isEmpty { result.append(current) }
    return result
  }

  private static func replace(
    _ pattern: String, in text: String, with transform: (String) -> String
  ) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    else { return text }
    let ns = text as NSString
    var result = ""
    var last = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
      let group = match.numberOfRanges > 1 ? ns.substring(with: match.range(at: 1)) : ""
      result += transform(group)
      last = match.range.location + match.range.length
    }
    result += ns.substring(from: last)
    return result
  }
}

/// One point of a summary, with the message numbers it was drawn from.
public struct SummaryPoint: Sendable, Equatable, Hashable {
  public var text: String
  public var refs: [Int]

  public init(text: String, refs: [Int]) {
    self.text = text
    self.refs = refs
  }

  /// Back as a line the model can merge in a later pass, citations kept.
  public var line: String {
    refs.isEmpty ? "- \(text)" : "- \(text) [\(refs.map(String.init).joined(separator: ", "))]"
  }
}

public enum SummaryParser {
  /// Points from a model's reply: one per bullet or numbered line, with the
  /// `[3]` or `[3, 7]` citations taken out of the text. Citations outside
  /// `validRefs` are dropped, since a model sometimes makes them up.
  public static func points(from output: String, validRefs: ClosedRange<Int>? = nil)
    -> [SummaryPoint]
  {
    var points: [SummaryPoint] = []
    for rawLine in output.components(separatedBy: .newlines) {
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }
      let bulleted = stripBullet(&line)
      // a heading or a preamble ("Here is the summary:") isn't a point
      if !bulleted, line.hasSuffix(":") || line.hasPrefix("#") { continue }
      line = line.replacingOccurrences(of: "**", with: "")

      var refs: [Int] = []
      let pattern = #"\[\s*(\d+(?:\s*[,;–-]\s*\d+)*)\s*\]"#
      if let regex = try? NSRegularExpression(pattern: pattern) {
        let ns = line as NSString
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
          let inner = ns.substring(with: match.range(at: 1))
          refs += numbers(in: inner)
        }
        line = regex.stringByReplacingMatches(
          in: line, range: NSRange(location: 0, length: ns.length), withTemplate: "")
      }
      if let validRefs { refs = refs.filter(validRefs.contains) }
      var seen = Set<Int>()
      refs = refs.filter { seen.insert($0).inserted }

      line = line.replacingOccurrences(of: "  ", with: " ")
        .replacingOccurrences(of: " .", with: ".")
        .replacingOccurrences(of: " ,", with: ",")
        .trimmingCharacters(in: .whitespaces)
      guard line.count > 1 else { continue }
      points.append(SummaryPoint(text: line, refs: refs))
    }
    return points
  }

  /// Removes `- `, `* `, `• ` or `1. ` from the front; says whether there was one.
  private static func stripBullet(_ line: inout String) -> Bool {
    for bullet in ["- ", "* ", "• ", "– "] where line.hasPrefix(bullet) {
      line.removeFirst(bullet.count)
      return true
    }
    if let dot = line.firstIndex(where: { $0 == "." || $0 == ")" }),
      line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
      line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " "
    {
      line = String(line[line.index(dot, offsetBy: 2)...])
      return true
    }
    return false
  }

  /// `3, 7` or a range `3-5`, which is spelled out up to ten numbers.
  private static func numbers(in text: String) -> [Int] {
    var result: [Int] = []
    for part in text.split(whereSeparator: { $0 == "," || $0 == ";" }) {
      let bounds = part.split(whereSeparator: { $0 == "-" || $0 == "–" })
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
      if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 10 {
        result += Array(bounds[0]...bounds[1])
      } else {
        result += bounds
      }
    }
    return result
  }
}
