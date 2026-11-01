import Foundation

/// A page of a guild's audit log, newest first.
/// https://docs.discord.food/resources/audit-log#audit-log-object
public struct GuildAuditLog: Sendable, Decodable {
  public var audit_log_entries: [Entry]
  public var users: [PartialUser]?

  /// https://docs.discord.food/resources/audit-log#audit-log-entry-object
  public struct Entry: Sendable, Decodable, Identifiable {
    public var id: AnySnowflake
    public var target_id: String?
    public var user_id: UserSnowflake?
    public var action_type: Int
    public var reason: String?
    public var changes: [Change]?
    public var options: Options?
  }

  /// One field an entry changed; values are left loosely typed.
  public struct Change: Sendable, Decodable {
    public var key: String
    public var new_value: Value?
    public var old_value: Value?
  }

  public struct Options: Sendable, Decodable {
    public var channel_id: String?
    public var count: String?
    public var delete_member_days: String?
    public var members_removed: String?
    public var role_name: String?
  }

  /// A change's value: text, a number, a flag, or anything else (lists and objects).
  public enum Value: Sendable, Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case other

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let bool = try? container.decode(Bool.self) {
        self = .bool(bool)
      } else if let number = try? container.decode(Double.self) {
        self = .number(number)
      } else if let string = try? container.decode(String.self) {
        self = .string(string)
      } else {
        self = .other
      }
    }
  }
}

extension Payloads {
  /// Ends a member's timeout: sends `communication_disabled_until: null`.
  public struct RemoveGuildMemberTimeout: Sendable, Encodable, ValidatablePayload {
    public init() {}

    enum CodingKeys: String, CodingKey {
      case communication_disabled_until
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeNil(forKey: .communication_disabled_until)
    }

    public func validate() -> [ValidationFailure] {}
  }
}
