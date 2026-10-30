import Foundation

/// Server invite links in their many spellings: `discord.gg/abc`,
/// `discord.com/invite/abc`, `discordapp.com/invite/abc`, and the app's own
/// `aicord://invite/abc` that the Safari extension sends.
public enum InviteLink {
  /// The scheme the app registers for links handed over from Safari.
  public static let appScheme = "aicord"

  /// Invite codes are letters, digits and dashes (vanity URLs use dashes).
  private static let codeCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
  )

  private static let discordHosts: Set<String> = [
    "discord.com", "www.discord.com", "ptb.discord.com", "canary.discord.com",
    "discordapp.com", "www.discordapp.com",
  ]

  /// The invite code a link points at, or `nil` when it isn't an invite.
  public static func code(from url: URL) -> String? {
    let path = url.pathComponents.filter { $0 != "/" }
    let host = url.host()?.lowercased() ?? ""
    let candidate: String?
    if url.scheme == appScheme {
      candidate = host == "invite" ? path.first : nil
    } else if url.scheme == "https" || url.scheme == "http" {
      if host == "discord.gg" || host == "www.discord.gg" {
        // discord.gg/invite/abc works too
        candidate = path.first == "invite" ? (path.count > 1 ? path[1] : nil) : path.first
      } else if discordHosts.contains(host), path.first == "invite" {
        candidate = (path.count > 1 ? path[1] : nil)
      } else {
        candidate = nil
      }
    } else {
      candidate = nil
    }
    guard let candidate, isValidCode(candidate) else { return nil }
    return candidate
  }

  /// Invite codes in a message, in order and without repeats.
  public static func codes(in text: String) -> [String] {
    var codes: [String] = []
    for word in text.split(whereSeparator: { $0.isWhitespace || $0 == "<" || $0 == ">" }) {
      var string = String(word)
      // markdown links: [text](https://discord.gg/abc)
      if let open = string.range(of: "(http", options: .backwards) {
        string = String(string[string.index(after: open.lowerBound)...])
      }
      string = string.trimmingCharacters(in: CharacterSet(charactersIn: ")]*_~|.,!?;:'\""))
      if !string.contains("://") { string = "https://" + string }
      guard let url = URL(string: string), let code = code(from: url) else { continue }
      if !codes.contains(code) { codes.append(code) }
    }
    return codes
  }

  /// The link people share.
  public static func url(for code: String) -> URL {
    URL(string: "https://discord.gg/\(code)")!
  }

  /// The link that opens the invite in the app.
  public static func appURL(for code: String) -> URL {
    URL(string: "\(appScheme)://invite/\(code)")!
  }

  static func isValidCode(_ code: String) -> Bool {
    (2...64).contains(code.count) && code.unicodeScalars.allSatisfy(codeCharacters.contains)
  }
}

/// How long a new invite works, as in Discord's Invite People dialog.
public enum InviteExpiry: Int, CaseIterable, Sendable, Identifiable {
  case thirtyMinutes = 1800
  case oneHour = 3600
  case sixHours = 21600
  case twelveHours = 43200
  case oneDay = 86400
  case sevenDays = 604_800
  case never = 0

  public var id: Int { rawValue }

  /// `max_age` for `createChannelInvite`; 0 means it never expires.
  public var maxAge: Payloads.Count {
    self == .never ? .unlimited : .count(rawValue)
  }
}

/// How many times a new invite can be used.
public enum InviteUseLimit: Int, CaseIterable, Sendable, Identifiable {
  case unlimited = 0
  case one = 1
  case five = 5
  case ten = 10
  case twentyFive = 25
  case fifty = 50
  case hundred = 100

  public var id: Int { rawValue }

  public var maxUses: Payloads.Count {
    self == .unlimited ? .unlimited : .count(rawValue)
  }
}

/// Why Discord turned down a friend request, from its error code.
public enum FriendRequestFailure: Equatable, Sendable {
  case unknownUser
  case alreadyFriends
  case requestsDisabled
  case blocked
  case yourself
  case bot
  case friendLimit
  case needsVerification
  case rateLimited
  case other(String?)

  /// - Parameters:
  ///   - status: the HTTP status code.
  ///   - code: Discord's JSON error code, if the body had one.
  ///   - message: Discord's own wording, kept for codes not listed here.
  public init(status: Int, code: Int?, message: String?) {
    switch code {
    case 80004: self = .unknownUser
    case 80007: self = .alreadyFriends
    case 80000: self = .requestsDisabled
    case 80001: self = .blocked
    case 80002: self = .bot
    case 80003: self = .yourself
    case 30002: self = .friendLimit
    case 40002: self = .needsVerification
    default:
      self = status == 429 ? .rateLimited : .other(message)
    }
  }
}
