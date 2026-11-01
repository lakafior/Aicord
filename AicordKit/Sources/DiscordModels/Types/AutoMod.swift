//
//  AutoMod.swift
//  AicordKit
//
//  AutoMod rules of a server, for moderators with Manage Server.
//  https://docs.discord.food/resources/auto-moderation
//

/// One AutoMod rule.
public struct AutoModRule: Sendable, Codable, Equatable, Hashable, Identifiable {
  public var id: String
  public var guild_id: GuildSnowflake
  public var name: String
  public var creator_id: UserSnowflake?
  /// 1 message send, 2 member update.
  public var event_type: Int
  public var trigger_type: TriggerKind
  public var trigger_metadata: TriggerMetadata
  public var actions: [Action]
  public var enabled: Bool
  public var exempt_roles: [RoleSnowflake]
  public var exempt_channels: [ChannelSnowflake]

  public enum TriggerKind: Int, Sendable, Codable, CaseIterable {
    case keyword = 1
    case spam = 3
    case keywordPreset = 4
    case mentionSpam = 5
    case memberProfile = 6
  }

  public struct TriggerMetadata: Sendable, Codable, Equatable, Hashable {
    public var keyword_filter: [String]?
    public var regex_patterns: [String]?
    /// 1 profanity, 2 sexual content, 3 slurs.
    public var presets: [Int]?
    public var allow_list: [String]?
    public var mention_total_limit: Int?
    public var mention_raid_protection_enabled: Bool?

    public init(
      keyword_filter: [String]? = nil, regex_patterns: [String]? = nil, presets: [Int]? = nil,
      allow_list: [String]? = nil, mention_total_limit: Int? = nil,
      mention_raid_protection_enabled: Bool? = nil
    ) {
      self.keyword_filter = keyword_filter
      self.regex_patterns = regex_patterns
      self.presets = presets
      self.allow_list = allow_list
      self.mention_total_limit = mention_total_limit
      self.mention_raid_protection_enabled = mention_raid_protection_enabled
    }
  }

  public struct Action: Sendable, Codable, Equatable, Hashable {
    public enum Kind: Int, Sendable, Codable {
      case blockMessage = 1
      case sendAlert = 2
      case timeout = 3
      case blockMemberInteraction = 4
    }

    public struct Metadata: Sendable, Codable, Equatable, Hashable {
      public var channel_id: ChannelSnowflake?
      public var duration_seconds: Int?
      public var custom_message: String?

      public init(
        channel_id: ChannelSnowflake? = nil, duration_seconds: Int? = nil,
        custom_message: String? = nil
      ) {
        self.channel_id = channel_id
        self.duration_seconds = duration_seconds
        self.custom_message = custom_message
      }
    }

    public var type: Kind
    public var metadata: Metadata?

    public init(type: Kind, metadata: Metadata? = nil) {
      self.type = type
      self.metadata = metadata
    }
  }
}

extension Payloads {
  /// Creates or changes an AutoMod rule. On a change, the trigger type stays.
  public struct AutoModRule: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var event_type: Int
    public var trigger_type: DiscordModels.AutoModRule.TriggerKind?
    public var trigger_metadata: DiscordModels.AutoModRule.TriggerMetadata?
    public var actions: [DiscordModels.AutoModRule.Action]
    public var enabled: Bool
    public var exempt_roles: [RoleSnowflake]
    public var exempt_channels: [ChannelSnowflake]

    public init(
      name: String, event_type: Int = 1, trigger_type: DiscordModels.AutoModRule.TriggerKind?,
      trigger_metadata: DiscordModels.AutoModRule.TriggerMetadata?,
      actions: [DiscordModels.AutoModRule.Action], enabled: Bool,
      exempt_roles: [RoleSnowflake], exempt_channels: [ChannelSnowflake]
    ) {
      self.name = name
      self.event_type = event_type
      self.trigger_type = trigger_type
      self.trigger_metadata = trigger_metadata
      self.actions = actions
      self.enabled = enabled
      self.exempt_roles = exempt_roles
      self.exempt_channels = exempt_channels
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateElementCountDoesNotExceed(exempt_roles, max: 20, name: "exempt_roles")
      validateElementCountDoesNotExceed(exempt_channels, max: 50, name: "exempt_channels")
    }
  }
}

extension Payloads {
  /// Takes a role's icon away: both fields as JSON null, which `GuildRole` leaves out.
  public struct ClearRoleIcon: Sendable, Encodable, ValidatablePayload {
    public init() {}

    enum CodingKeys: String, CodingKey {
      case icon, unicode_emoji
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeNil(forKey: .icon)
      try container.encodeNil(forKey: .unicode_emoji)
    }

    public func validate() -> [ValidationFailure] {}
  }
}
