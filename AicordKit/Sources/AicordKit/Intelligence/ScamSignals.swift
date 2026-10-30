//
//  ScamSignals.swift
//  AicordKit
//
//  Common Discord scams in direct messages from strangers, recognised on the
//  device without a model: fake Nitro gifts, "I reported you by accident",
//  Steam gifts, and links dressed up as Discord or Steam.
//

import Foundation

public enum ScamSignals {
  public enum Kind: String, Sendable, CaseIterable {
    case fakeNitro
    case accidentalReport
    case fakeGift
    case lookalikeLink
    case credentialRequest
  }

  /// What looks like a scam in a message, most telling first.
  public static func check(_ text: String) -> [Kind] {
    let lower = text.lowercased()
    var found: [Kind] = []
    let hosts = linkHosts(in: text)
    if hosts.contains(where: isLookalike) { found.append(.lookalikeLink) }
    if lower.contains("nitro"),
      ["free", "gift", "claim", "giveaway", "darmow", "za darmo"].contains(where: lower.contains),
      !hosts.isEmpty
    {
      found.append(.fakeNitro)
    }
    let reportWords = ["reported", "report", "zgłosi", "zglosi", "zgłoszen"]
    let accidentWords = ["accident", "by mistake", "przypadk", "niechcący", "niechcacy"]
    if reportWords.contains(where: lower.contains), accidentWords.contains(where: lower.contains) {
      found.append(.accidentalReport)
    }
    if lower.contains("steam"),
      ["gift", "$50", "50$", "free", "prezent"].contains(where: lower.contains), !hosts.isEmpty
    {
      found.append(.fakeGift)
    }
    let credentialWords = [
      "your password", "login code", "2fa code", "qr code to verify", "scan this qr", "token",
      "kod logowania", "twoje hasło", "zeskanuj",
    ]
    if credentialWords.contains(where: lower.contains) { found.append(.credentialRequest) }
    return found
  }

  /// Hosts of the links in a message.
  public static func linkHosts(in text: String) -> [String] {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return [] }
    return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
      .compactMap { $0.url?.host()?.lowercased() }
  }

  static let realHosts = [
    "discord.com", "discord.gg", "discordapp.com", "discord.media", "discordapp.net",
    "discord.new", "steamcommunity.com", "steampowered.com",
  ]

  /// A host that imitates Discord or Steam without being theirs:
  /// `dlscord.gift`, `discord-nitro.com`, `steamcommunlty.com`.
  public static func isLookalike(_ host: String) -> Bool {
    let host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    if realHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return false }
    let name = host.split(separator: ".").dropLast().joined(separator: ".")
    let flat = name.replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "1", with: "i").replacingOccurrences(of: "l", with: "i")
      .replacingOccurrences(of: "0", with: "o")
    for brand in ["discord", "steamcommunity", "steampowered", "nitro"] {
      let target = brand.replacingOccurrences(of: "l", with: "i")
      if flat.contains(target) { return true }
      // one letter changed, dropped or added
      if flat.split(separator: ".").contains(where: { editDistance(String($0), target) == 1 }) {
        return true
      }
    }
    return false
  }

  /// Edits between two words, a swap of neighbours counting as one.
  static func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    guard !a.isEmpty else { return b.count }
    guard !b.isEmpty else { return a.count }
    var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in 0...a.count { d[i][0] = i }
    for j in 0...b.count { d[0][j] = j }
    for i in 1...a.count {
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
        if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
          d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
        }
      }
    }
    return d[a.count][b.count]
  }
}
