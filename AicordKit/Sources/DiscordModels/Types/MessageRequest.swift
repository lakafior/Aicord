//
//  MessageRequest.swift
//  Aicord
//
//  DMs from people you don't share a friendship with arrive as message
//  requests (`is_message_request`), and the ones Discord's filter flags as
//  spam (`is_spam`).
//

/// https://docs.discord.food/resources/channel#consent-status
#if Non64BitSystemsCompatibility
  @UnstableEnum<Int64>
#else
  @UnstableEnum<Int>
#endif
public enum MessageRequestConsentStatus: Sendable, Codable {
  case unspecified  // 0
  case pending  // 1
  case accepted  // 2
  case rejected  // 3
  #if Non64BitSystemsCompatibility
    case __undocumented(Int64)
  #else
    case __undocumented(Int)
  #endif
}

/// The message that started a request, for previews in the request list.
/// https://docs.discord.food/resources/channel#supplemental-message-request-object
public struct SupplementalMessageRequest: Sendable, Decodable {
  public var channel_id: ChannelSnowflake
  public var message_preview: DiscordChannel.Message?

  public init(channel_id: ChannelSnowflake, message_preview: DiscordChannel.Message? = nil) {
    self.channel_id = channel_id
    self.message_preview = message_preview
  }
}

extension DiscordChannel {
  /// A DM still waiting to be accepted, outside the spam folder.
  public var isPendingMessageRequest: Bool {
    is_message_request == true && !isSpam
  }

  /// Discord's spam filter caught it: `is_spam` or the `IS_SPAM` channel flag.
  public var isSpam: Bool {
    is_spam == true || flags?.contains(.spam) == true
  }
}
