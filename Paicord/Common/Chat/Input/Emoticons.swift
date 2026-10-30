//
//  Emoticons.swift
//  Paicord
//
//  Discord's "convert emoticons to emoji" for outgoing messages: `:)` becomes
//  🙂 when it stands alone, never inside code, links or other words.
//

import Foundation

enum Emoticons {
  /// Roughly the shortcuts Discord's own client converts.
  static let emoji: [String: String] = [
    ":)": "🙂", ":-)": "🙂", "=)": "🙂", "=-)": "🙂",
    ":(": "🙁", ":-(": "🙁", "=(": "🙁", "=-(": "🙁",
    ":D": "😃", ":-D": "😃", "=D": "😃", "=-D": "😃",
    ";)": "😉", ";-)": "😉",
    ":P": "😛", ":-P": "😛", ":p": "😛", ":-p": "😛", "=P": "😛", "=p": "😛",
    ":O": "😮", ":-O": "😮", ":o": "😮", ":-o": "😮",
    ":|": "😐", ":-|": "😐",
    ":/": "😕", ":-/": "😕", ":\\": "😕", ":-\\": "😕",
    ":'(": "😢", ":'-(": "😢",
    ":*": "😗", ":-*": "😗",
    "xD": "😆", "XD": "😆",
    "B-)": "😎", "8-)": "😎",
    ">:(": "😠", ">:-(": "😠",
    "O:)": "😇", "o:)": "😇", "O:-)": "😇", "o:-)": "😇",
    ":@": "😡",
    "D:": "😧",
    "<3": "❤️", "</3": "💔",
  ]

  private static let pattern: NSRegularExpression = {
    let alternatives = emoji.keys
      .sorted { $0.count > $1.count }
      .map(NSRegularExpression.escapedPattern(for:))
      .joined(separator: "|")
    return try! NSRegularExpression(pattern: "(?<=^|\\s)(?:\(alternatives))(?=$|\\s)")
  }()

  /// Converts emoticons outside code spans and code blocks.
  static func convert(_ content: String) -> String {
    guard !content.isEmpty else { return content }
    // Even pieces are outside ``` blocks, then outside `inline code`.
    return content.components(separatedBy: "```").enumerated().map { block in
      guard block.offset.isMultiple(of: 2) else { return block.element }
      return block.element.components(separatedBy: "`").enumerated().map { span in
        span.offset.isMultiple(of: 2) ? replace(in: span.element) : span.element
      }
      .joined(separator: "`")
    }
    .joined(separator: "```")
  }

  private static func replace(in text: String) -> String {
    let result = NSMutableString(string: text)
    let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
    for match in matches.reversed() {
      let token = result.substring(with: match.range)
      if let replacement = emoji[token] {
        result.replaceCharacters(in: match.range, with: replacement)
      }
    }
    return result as String
  }
}
