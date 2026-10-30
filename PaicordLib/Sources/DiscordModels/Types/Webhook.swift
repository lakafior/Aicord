import Foundation

/// https://discord.com/developers/docs/resources/webhook#webhook-object-webhook-structure
public struct Webhook: Sendable, Codable {
  /// https://discord.com/developers/docs/resources/webhook#webhook-object-webhook-types
  #if Non64BitSystemsCompatibility
    @UnstableEnum<Int64>
  #else
    @UnstableEnum<Int>
  #endif
  public enum Kind: Sendable, Codable {
    case incoming  // 1
    case channelFollower  // 2
    case application  // 3
    #if Non64BitSystemsCompatibility
      case __undocumented(Int64)
    #else
      case __undocumented(Int)
    #endif
  }

  public var id: WebhookSnowflake
  public var type: Kind
  public var guild_id: GuildSnowflake?
  public var channel_id: ChannelSnowflake?
  public var user: DiscordUser?
  public var name: String?
  public var avatar: String?
  public var token: String?
  public var application_id: ApplicationSnowflake?
  public var source_guild: PartialGuild?
  public var source_channel: DiscordChannel?
  public var url: String?
}
