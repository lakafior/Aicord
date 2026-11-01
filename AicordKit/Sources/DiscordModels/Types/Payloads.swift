import Foundation

/// REST API payloads.
///
/// These types only need to be `Encodable`,
/// unless we actually need them to be `Decodable` as well.
public enum Payloads {

  /// Used to authenticate and retrieve credentials.
  /// https://docs.discord.food/authentication#login-account
  public struct Authentication: Sendable, Encodable, ValidatablePayload {
    public var login: String
    public var password: Secret
    public var undelete: Bool = false

    public var login_source: LoginSource? = nil
    public var gift_code_sku_id: String? = nil

    public init(login: String, password: Secret, undelete: Bool = false) {
      self.login = login
      self.password = password
      self.undelete = undelete
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(
        password.value,
        min: 8,
        max: 72,
        name: "password"
      )
    }

    /// Where a login is initiated from outside of the normal login flow.
    public enum LoginSource: String, Sendable, Encodable {
      case
        gift,
        guild_template,
        guild_invite,
        dm_invite,
        friend_invite,
        role_subscription,
        role_subscription_setting
    }
  }

  /// Used to send an SMS to the user's phone for MFA.
  /// https://docs.discord.food/authentication#send-mfa-sms
  public struct AuthenticationMFASendSMS: Sendable, Encodable,
    ValidatablePayload
  {
    public var ticket: Secret

    public init(ticket: Secret) {
      self.ticket = ticket
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// Used to complete MFA verify process when you've received a ticket rather than a token from the login endpoint.
  /// https://docs.discord.food/authentication#verify-mfa-login
  public struct AuthenticationMFA: Sendable, Encodable, ValidatablePayload {
    var code: String
    var ticket: Secret

    var login_source: Authentication.LoginSource? = nil
    var gift_code_sku_id: String? = nil

    public init(code: String, ticket: Secret) {
      self.code = code
      self.ticket = ticket
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(code, min: 6, max: 8, name: "code")
    }
  }

  /// https://docs.discord.food/authentication#logout-auth-sessions
  public struct LogoutSessions: Sendable, Encodable, ValidatablePayload {
    public var session_id_hashes: [String]

    public init(session_id_hashes: [String]) {
      self.session_id_hashes = session_id_hashes
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/authentication#forgot-password
  public struct ForgotPassword: Sendable, Encodable, ValidatablePayload {
    public var login: String

    public init(login: String) {
      self.login = login
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/authentication#mfa-verification
  public struct MFASubmitData: Sendable, Codable, ValidatablePayload {
    public var ticket: Secret
    public var mfa_type: MFAKind
    public var data: String

    public init(ticket: Secret, mfa_type: MFAKind, data: String) {
      self.ticket = ticket
      self.mfa_type = mfa_type
      self.data = data
    }

    public enum MFAKind: String, Sendable, Codable {
      case totp  // totp
      case sms  // sms
      case backup  // backup
      case webauthn  // webauthn
      case password  // password
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// An attachment object, but for sending.
  /// https://discord.com/developers/docs/resources/channel#attachment-object
  /// https://docs.discord.food/resources/message#attachment-structure
  public struct Attachment: Sendable, Encodable, Hashable, ValidatablePayload {
    /// When sending, `id` is the index of this attachment in the `files` you provide.
    public var id: String
    public var filename: String?
    public var uploaded_filename: String?
    public var title: String?
    public var description: String?
    public var content_type: String?
    public var size: Int?
    public var url: String?
    public var proxy_url: String?
    public var height: Int?
    public var width: Int?
    public var ephemeral: Bool?
    public var duration_secs: Double?
    public var waveform: String?

    /// `index` is the index of this attachment in the `files` you provide.
    public init(
      index: Int,
      filename: String? = nil,
      uploaded_filename: String? = nil,
      title: String? = nil,
      description: String? = nil,
      content_type: String? = nil,
      size: Int? = nil,
      url: String? = nil,
      proxy_url: String? = nil,
      height: Int? = nil,
      width: Int? = nil,
      ephemeral: Bool? = nil,
      duration_secs: Double? = nil,
      waveform: String? = nil
    ) {
      self.id = "\(index)"
      self.filename = filename
      self.uploaded_filename = uploaded_filename
      self.title = title
      self.description = description
      self.content_type = content_type
      self.size = size
      self.url = url
      self.proxy_url = proxy_url
      self.height = height
      self.width = width
      self.ephemeral = ephemeral
      self.duration_secs = duration_secs
      self.waveform = waveform
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountDoesNotExceed(
        description,
        max: 1_024,
        name: "description"
      )
    }
  }

  /// A allowed-mentions object, but for sending.
  /// https://discord.com/developers/docs/resources/channel#allowed-mentions-object
  public struct AllowedMentions: Sendable, Hashable, Codable, ValidatablePayload {
    public var parse: [DiscordChannel.AllowedMentions.Kind]?
    public var roles: [RoleSnowflake]?
    public var users: [UserSnowflake]?
    public var replied_user: Bool?

    /// What to be mentioned.
    /// - Parameters:
    ///   - parse: What general type of mentions to be allowed.
    ///     If empty, nothing will be allowed by this field (empty != `nil`).
    ///     Doesn't stop other fields from allowing mentions.
    ///   - roles: What roles to be allowed to be mentioned.
    ///   - users: What users to be allowed to be mentioned.
    ///   - replied_user: Allow to mention the replied user.
    public init(
      parse: [DiscordChannel.AllowedMentions.Kind]? = nil,
      roles: [RoleSnowflake]? = nil,
      users: [UserSnowflake]? = nil,
      replied_user: Bool? = nil
    ) {
      self.parse = parse
      self.roles = roles
      self.users = users
      self.replied_user = replied_user
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountDoesNotExceed(roles, max: 100, name: "roles")
      validateElementCountDoesNotExceed(users, max: 100, name: "users")
    }
  }

  public struct ImageData: Sendable, Codable {
    public var file: RawFile

    public init(file: RawFile) {
      self.file = file
    }

    public init(from decoder: any Decoder) throws {
      let string = try String(from: decoder)
      guard let file = ImageData.decodeFromString(string) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "\(string.debugDescription) can't be base64 decoded into a file"
          )
        )
      }
      self.file = file
    }

    public func encode(to encoder: any Encoder) throws {
      guard let string = self.encodeToString() else {
        throw EncodingError.invalidValue(
          file,
          .init(
            codingPath: encoder.codingPath,
            debugDescription: "Can't base64 encode the file"
          )
        )
      }
      var container = encoder.singleValueContainer()
      try container.encode(string)
    }

    static func decodeFromString(_ string: String) -> RawFile? {
      var filename: String?
      guard string.hasPrefix("data:") else {
        return nil
      }
      guard let semicolon = string.firstIndex(of: ";") else {
        return nil
      }
      let type = string[string.startIndex..<semicolon].dropFirst(5)
      let typeComps = type.split(separator: "/", maxSplits: 1)
      if typeComps.count == 2,
        let ext = fileExtensionMediaTypeMapping.first(
          where: { $1.0 == typeComps[0] && $1.1 == typeComps[1] }
        )?.key
      {
        filename = "unknown.\(ext)"
      }
      guard string[semicolon...].hasPrefix(";base64,") else {
        return nil
      }
      let encodedString = string[semicolon...].dropFirst(8)
      guard let data = Data(base64Encoded: String(encodedString)) else {
        return nil
      }
      return .init(data: data, filename: filename ?? "unknown")
    }

    func encodeToString() -> String? {
      guard let type = file.type else { return nil }
      let encoded = file.data.base64EncodedString()
      return "data:\(type);base64,\(encoded)"
    }
  }

  /// https://discord.com/developers/docs/resources/channel#create-message-jsonform-params
  /// https://docs.discord.food/resources/message#create-message
  public struct CreateMessage: Sendable, Hashable, MultipartEncodable,
    ValidatablePayload
  {
    public var content: String?
    public var nonce: StringOrInt?
    public var tts: Bool?
    public var embeds: [Embed]?
    public var allowed_mentions: AllowedMentions?
    public var message_reference: DiscordChannel.Message.MessageReference?
    public var sticker_ids: [String]?
    public var files: [RawFile]?
    public var attachments: [Attachment]?
    public var flags: IntBitField<DiscordChannel.Message.Flag>?
    public var enforce_nonce: Bool?
    public var poll: CreatePollRequest?

    enum CodingKeys: String, CodingKey {
      case content
      case nonce
      case tts
      case embeds
      case allowed_mentions
      case message_reference
      case sticker_ids
      case attachments
      case flags
      case enforce_nonce
      case poll
    }

    public init(
      content: String? = nil,
      nonce: StringOrInt? = nil,
      tts: Bool? = nil,
      embeds: [Embed]? = nil,
      allowed_mentions: AllowedMentions? = nil,
      message_reference: DiscordChannel.Message.MessageReference? = nil,
      sticker_ids: [String]? = nil,
      files: [RawFile]? = nil,
      attachments: [Attachment]? = nil,
      flags: IntBitField<DiscordChannel.Message.Flag>? = nil,
      enforce_nonce: Bool? = nil,
      poll: CreatePollRequest? = nil
    ) {
      self.content = content
      self.nonce = nonce
      self.tts = tts
      self.embeds = embeds
      self.allowed_mentions = allowed_mentions
      self.message_reference = message_reference
      self.sticker_ids = sticker_ids
      self.files = files
      self.attachments = attachments
      self.flags = flags
      self.enforce_nonce = enforce_nonce
      self.poll = poll
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountDoesNotExceed(embeds, max: 10, name: "embeds")
      validateElementCountDoesNotExceed(
        sticker_ids,
        max: 3,
        name: "sticker_ids"
      )
      validateCharacterCountDoesNotExceed(content, max: 2_000, name: "content")
      validateCharacterCountDoesNotExceed(
        nonce?.asString,
        max: 25,
        name: "nonce"
      )
      allowed_mentions?.validate()
      if message_reference?.type == .forward,
        message_reference?.message_id == nil || message_reference?.channel_id == nil
      {
        ValidationFailure.hasPrecondition(
          name: "message_reference",
          reason: "Forwarded messages require message_id and channel_id"
        )
      }
      validateAtLeastOneIsNotEmpty(
        content?.isEmpty ?? true,
        embeds?.isEmpty ?? true,
        sticker_ids?.isEmpty ?? true,
        files?.isEmpty ?? true,
        poll?.answers.isEmpty ?? true,
        message_reference?.type != .forward,
        attachments?.isEmpty ?? true,
        names: "content",
        "embeds",
        "sticker_ids",
        "files",
        "poll",
        "message_reference",
        "attachments"
      )
      validateCombinedCharacterCountDoesNotExceed(
        embeds?.reduce(into: 0, { $0 += $1.contentLength }),
        max: 6_000,
        names: "embeds"
      )
      validateOnlyContains(
        flags,
        name: "flags",
        reason: "Unsupported message flags",
        allowed: [.suppressEmbeds, .suppressNotifications, .isVoiceMessage]
      )
      if flags?.contains(.isVoiceMessage) == true {
        validateElementCountInRange(attachments, min: 1, max: 1, name: "attachments")
        validateElementCountDoesNotExceed(files, max: 1, name: "files")
        if let attachment = attachments?.first {
          if attachment.content_type?.lowercased().hasPrefix("audio/") != true {
            ValidationFailure.hasPrecondition(
              name: "attachments.content_type",
              reason: "Voice message attachments require an audio content type"
            )
          }
          if attachment.duration_secs?.isFinite != true || (attachment.duration_secs ?? 0) <= 0 {
            ValidationFailure.hasPrecondition(
              name: "attachments.duration_secs",
              reason: "Voice message attachments require a positive finite duration"
            )
          }
          if attachment.waveform?.isEmpty != false {
            ValidationFailure.cantBeEmpty(name: "attachments.waveform")
          }
        }
        if content?.isEmpty == false || embeds?.isEmpty == false || sticker_ids?.isEmpty == false
          || poll != nil || tts == true
        {
          ValidationFailure.containsProhibitedValues(
            name: "flags",
            reason: "Voice messages cannot contain additional message content",
            valuesRepresentation: "isVoiceMessage"
          )
        }
      }
      attachments?.validate()
      embeds?.validate()
      poll?.validate()
    }
  }

  /// https://discord.com/developers/docs/resources/channel#edit-message-jsonform-params
  public struct EditMessage: Sendable, MultipartEncodable, ValidatablePayload {
    public var content: String?
    public var embeds: [Embed]?
    public var flags: IntBitField<DiscordChannel.Message.Flag>?
    public var allowed_mentions: AllowedMentions?
    public var files: [RawFile]?
    public var attachments: [Attachment]?

    enum CodingKeys: String, CodingKey {
      case content
      case embeds
      case flags
      case allowed_mentions
      case attachments
    }

    public init(
      content: String? = nil,
      embeds: [Embed]? = nil,
      flags: IntBitField<DiscordChannel.Message.Flag>? = nil,
      allowed_mentions: AllowedMentions? = nil,
      files: [RawFile]? = nil,
      attachments: [Attachment]? = nil
    ) {
      self.content = content
      self.embeds = embeds
      self.flags = flags
      self.allowed_mentions = allowed_mentions
      self.files = files
      self.attachments = attachments
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountDoesNotExceed(embeds, max: 10, name: "embeds")
      validateCharacterCountDoesNotExceed(content, max: 2_000, name: "content")
      validateCombinedCharacterCountDoesNotExceed(
        embeds?.reduce(into: 0, { $0 += $1.contentLength }),
        max: 6_000,
        names: "embeds"
      )
      validateOnlyContains(
        flags,
        name: "flags",
        reason: "Can only contain 'suppressEmbeds'",
        allowed: [.suppressEmbeds]
      )
      allowed_mentions?.validate()
      attachments?.validate()
      embeds?.validate()
    }
  }

  public struct CreateThreadFromMessage: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var auto_archive_duration: DiscordChannel.AutoArchiveDuration?
    public var rate_limit_per_user: Int?

    public init(
      name: String,
      auto_archive_duration: DiscordChannel.AutoArchiveDuration? = nil,
      rate_limit_per_user: Int? = nil
    ) {
      self.name = name
      self.auto_archive_duration = auto_archive_duration
      self.rate_limit_per_user = rate_limit_per_user
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateNumberInRangeOrNil(
        rate_limit_per_user,
        min: 0,
        max: 21_600,
        name: "rate_limit_per_user"
      )
    }
  }

  public struct CreateThreadWithoutMessage: Sendable, Encodable,
    ValidatablePayload
  {
    public var name: String
    public var auto_archive_duration: DiscordChannel.AutoArchiveDuration?
    public var type: ThreadKind
    public var invitable: Bool?
    public var rate_limit_per_user: Int?

    public init(
      name: String,
      auto_archive_duration: DiscordChannel.AutoArchiveDuration? = nil,
      type: ThreadKind,
      invitable: Bool? = nil,
      rate_limit_per_user: Int? = nil
    ) {
      self.name = name
      self.auto_archive_duration = auto_archive_duration
      self.type = type
      self.invitable = invitable
      self.rate_limit_per_user = rate_limit_per_user
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateNumberInRangeOrNil(
        rate_limit_per_user,
        min: 0,
        max: 21_600,
        name: "rate_limit_per_user"
      )
    }
  }

  public struct CreateThreadInForumChannel: Sendable, MultipartEncodable,
    ValidatablePayload
  {

    /// https://discord.com/developers/docs/resources/channel#start-thread-in-forum-channel-forum-thread-message-params-object
    public struct ForumMessage: Sendable, MultipartEncodable, ValidatablePayload {
      public var content: String?
      public var embeds: [Embed]?
      public var allowed_mentions: AllowedMentions?
      public var sticker_ids: [String]?
      public var files: [RawFile]?
      public var attachments: [Attachment]?
      public var flags: IntBitField<DiscordChannel.Message.Flag>?
      public var poll: CreatePollRequest?

      enum CodingKeys: String, CodingKey {
        case content
        case embeds
        case allowed_mentions
        case sticker_ids
        case attachments
        case flags
        case poll
      }

      public init(
        content: String? = nil,
        embeds: [Embed]? = nil,
        allowed_mentions: AllowedMentions? = nil,
        sticker_ids: [String]? = nil,
        files: [RawFile]? = nil,
        attachments: [Attachment]? = nil,
        flags: IntBitField<DiscordChannel.Message.Flag>? = nil,
        poll: CreatePollRequest? = nil
      ) {
        self.content = content
        self.embeds = embeds
        self.allowed_mentions = allowed_mentions
        self.sticker_ids = sticker_ids
        self.files = files
        self.attachments = attachments
        self.flags = flags
        self.poll = poll
      }

      public func validate() -> [ValidationFailure] {
        validateElementCountDoesNotExceed(embeds, max: 10, name: "embeds")
        validateElementCountDoesNotExceed(
          sticker_ids,
          max: 3,
          name: "sticker_ids"
        )
        validateCharacterCountDoesNotExceed(
          content,
          max: 2_000,
          name: "content"
        )
        allowed_mentions?.validate()
        validateAtLeastOneIsNotEmpty(
          content?.isEmpty,
          embeds?.isEmpty,
          sticker_ids?.isEmpty,
          files?.isEmpty,
          poll?.answers.isEmpty,
          names: "content",
          "embeds",
          "sticker_ids",
          "files",
          "poll"
        )
        validateCombinedCharacterCountDoesNotExceed(
          embeds?.reduce(into: 0, { $0 += $1.contentLength }),
          max: 6_000,
          names: "embeds"
        )
        validateOnlyContains(
          flags,
          name: "flags",
          reason:
            "Can only contain 'suppressEmbeds' or 'suppressNotifications'",
          allowed: [.suppressEmbeds, .suppressNotifications]
        )
        attachments?.validate()
        embeds?.validate()
        poll?.validate()
      }
    }

    public var name: String
    public var auto_archive_duration: DiscordChannel.AutoArchiveDuration?
    public var rate_limit_per_user: Int?
    public var message: ForumMessage
    public var applied_tags: [ForumTagSnowflake]?
    public var files: [RawFile]? {
      message.files
    }

    enum CodingKeys: String, CodingKey {
      case name
      case auto_archive_duration
      case rate_limit_per_user
      case message
      case applied_tags
    }

    public init(
      name: String,
      auto_archive_duration: DiscordChannel.AutoArchiveDuration? = nil,
      rate_limit_per_user: Int? = nil,
      message: ForumMessage,
      applied_tags: [ForumTagSnowflake]? = nil
    ) {
      self.name = name
      self.auto_archive_duration = auto_archive_duration
      self.rate_limit_per_user = rate_limit_per_user
      self.message = message
      self.applied_tags = applied_tags
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateNumberInRangeOrNil(
        rate_limit_per_user,
        min: 0,
        max: 21_600,
        name: "rate_limit_per_user"
      )
      self.message.validate()
    }
  }

  /// https://discord.com/developers/docs/resources/channel#modify-channel-json-params-group-dm
  public struct ModifyGroupDMChannel: Sendable, Encodable, ValidatablePayload {
    public var name: String?
    public var icon: ImageData?

    public init(name: String? = nil, icon: ImageData? = nil) {
      self.name = name
      self.icon = icon
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRangeOrNil(name, min: 1, max: 100, name: "name")
    }
  }

  /// https://discord.com/developers/docs/resources/channel#overwrite-object
  public struct PartialChannelOverwrite: Sendable, Encodable {
    public var id: AnySnowflake
    public var type: DiscordChannel.Overwrite.Kind
    public var allow: StringBitField<Permission>?
    public var deny: StringBitField<Permission>?

    public init(
      id: AnySnowflake,
      type: DiscordChannel.Overwrite.Kind,
      allow: StringBitField<Permission>? = nil,
      deny: StringBitField<Permission>? = nil
    ) {
      self.id = id
      self.type = type
      self.allow = allow
      self.deny = deny
    }
  }

  /// https://discord.com/developers/docs/resources/channel#forum-tag-object-forum-tag-structure
  public struct PartialForumTag: Sendable, Encodable, ValidatablePayload {
    public var id: ForumTagSnowflake?
    public var name: String
    public var moderated: Bool?
    public var emoji_id: EmojiSnowflake?
    public var emoji_name: String?

    public init(
      id: ForumTagSnowflake? = nil,
      name: String,
      moderated: Bool? = nil,
      emoji_id: EmojiSnowflake? = nil
    ) {
      self.id = id
      self.name = name
      self.moderated = moderated
      self.emoji_id = emoji_id
    }

    public init(
      id: ForumTagSnowflake? = nil,
      name: String,
      moderated: Bool? = nil,
      emoji_name: String? = nil
    ) {
      self.id = id
      self.name = name
      self.moderated = moderated
      self.emoji_name = emoji_name
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 0, max: 20, name: "name")
    }
  }

  /// https://discord.com/developers/docs/resources/channel#modify-channel-json-params-guild-channel
  public struct ModifyGuildChannel: Sendable, Encodable, ValidatablePayload {
    public var name: String?
    public var type: DiscordChannel.Kind?
    public var position: Int?
    public var topic: String?
    public var nsfw: Bool?
    public var rate_limit_per_user: Int?
    public var bitrate: Int?
    public var user_limit: Int?
    public var permission_overwrites: [PartialChannelOverwrite]?
    public var parent_id: AnySnowflake?
    public var rtc_region: String?
    public var video_quality_mode: DiscordChannel.VideoQualityMode?
    public var default_auto_archive_duration: DiscordChannel.AutoArchiveDuration?
    public var flags: IntBitField<DiscordChannel.Flag>?
    public var available_tags: [PartialForumTag]?
    public var default_reaction_emoji: DiscordChannel.DefaultReaction?
    public var default_thread_rate_limit_per_user: Int?
    public var default_sort_order: DiscordChannel.SortOrder?
    public var default_forum_layout: DiscordChannel.ForumLayout?

    public init(
      name: String? = nil,
      type: DiscordChannel.Kind? = nil,
      position: Int? = nil,
      topic: String? = nil,
      nsfw: Bool? = nil,
      rate_limit_per_user: Int? = nil,
      bitrate: Int? = nil,
      user_limit: Int? = nil,
      permission_overwrites: [PartialChannelOverwrite]? = nil,
      parent_id: AnySnowflake? = nil,
      rtc_region: String? = nil,
      video_quality_mode: DiscordChannel.VideoQualityMode? = nil,
      default_auto_archive_duration: DiscordChannel.AutoArchiveDuration? = nil,
      flags: IntBitField<DiscordChannel.Flag>? = nil,
      available_tags: [PartialForumTag]? = nil,
      default_reaction_emoji: DiscordChannel.DefaultReaction? = nil,
      default_thread_rate_limit_per_user: Int? = nil,
      default_sort_order: DiscordChannel.SortOrder? = nil,
      default_forum_layout: DiscordChannel.ForumLayout? = nil
    ) {
      self.name = name
      self.type = type
      self.position = position
      self.topic = topic
      self.nsfw = nsfw
      self.rate_limit_per_user = rate_limit_per_user
      self.bitrate = bitrate
      self.user_limit = user_limit
      self.permission_overwrites = permission_overwrites
      self.parent_id = parent_id
      self.rtc_region = rtc_region
      self.video_quality_mode = video_quality_mode
      self.default_auto_archive_duration = default_auto_archive_duration
      self.flags = flags
      self.available_tags = available_tags
      self.default_reaction_emoji = default_reaction_emoji
      self.default_thread_rate_limit_per_user =
        default_thread_rate_limit_per_user
      self.default_sort_order = default_sort_order
      self.default_forum_layout = default_forum_layout
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRangeOrNil(name, min: 1, max: 100, name: "name")
      validateCharacterCountDoesNotExceed(topic, max: 4_096, name: "topic")
      validateNumberInRangeOrNil(
        rate_limit_per_user,
        min: 0,
        max: 21_600,
        name: "rate_limit_per_user"
      )
      validateNumberInRangeOrNil(
        bitrate,
        min: 8_000,
        max: 384_000,
        name: "bitrate"
      )
      validateNumberInRangeOrNil(
        user_limit,
        min: 0,
        max: 10_000,
        name: "user_limit"
      )
      validateOnlyContains(
        flags,
        name: "flags",
        reason: "Can only contain 'requireTag'",
        allowed: [.requireTag]
      )
      validateElementCountDoesNotExceed(
        available_tags,
        max: 20,
        name: "available_tags"
      )
      available_tags?.validate()
    }
  }

  /// https://discord.com/developers/docs/resources/channel#modify-channel-json-params-thread
  public struct ModifyThreadChannel: Sendable, Encodable, ValidatablePayload {
    public var name: String?
    public var archived: Bool?
    public var auto_archive_duration: DiscordChannel.AutoArchiveDuration?
    public var locked: Bool?
    public var invitable: Bool?
    public var rate_limit_per_user: Int?
    public var flags: IntBitField<DiscordChannel.Flag>?
    public var applied_tags: [PartialForumTag]?

    public init(
      name: String? = nil,
      archived: Bool? = nil,
      auto_archive_duration: DiscordChannel.AutoArchiveDuration? = nil,
      locked: Bool? = nil,
      invitable: Bool? = nil,
      rate_limit_per_user: Int? = nil,
      flags: IntBitField<DiscordChannel.Flag>? = nil,
      applied_tags: [PartialForumTag]? = nil
    ) {
      self.name = name
      self.archived = archived
      self.auto_archive_duration = auto_archive_duration
      self.locked = locked
      self.invitable = invitable
      self.rate_limit_per_user = rate_limit_per_user
      self.flags = flags
      self.applied_tags = applied_tags
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRangeOrNil(name, min: 1, max: 100, name: "name")
      validateNumberInRangeOrNil(
        rate_limit_per_user,
        min: 0,
        max: 21_600,
        name: "rate_limit_per_user"
      )
      validateOnlyContains(
        flags,
        name: "flags",
        reason: "Can only contain 'pinned'",
        allowed: [.pinned]
      )
      validateElementCountDoesNotExceed(
        applied_tags,
        max: 5,
        name: "applied_tags"
      )
      applied_tags?.validate()
    }
  }

  /// https://discord.com/developers/docs/resources/guild#create-guild-channel-json-params
  public struct CreateGuildChannel: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var type: DiscordChannel.Kind?
    public var position: Int?
    public var topic: String?
    public var nsfw: Bool?
    public var rate_limit_per_user: Int?
    public var bitrate: Int?
    public var user_limit: Int?
    public var permission_overwrites: [PartialChannelOverwrite]?
    public var parent_id: AnySnowflake?
    public var rtc_region: String?
    public var video_quality_mode: DiscordChannel.VideoQualityMode?
    public var default_auto_archive_duration: DiscordChannel.AutoArchiveDuration?
    public var available_tags: [PartialForumTag]?
    public var default_reaction_emoji: DiscordChannel.DefaultReaction?
    public var default_sort_order: DiscordChannel.SortOrder?
    public var default_forum_layout: DiscordChannel.ForumLayout?
    public var default_thread_rate_limit_per_user: Int?

    public init(
      name: String,
      type: DiscordChannel.Kind? = nil,
      position: Int? = nil,
      topic: String? = nil,
      nsfw: Bool? = nil,
      rate_limit_per_user: Int? = nil,
      bitrate: Int? = nil,
      user_limit: Int? = nil,
      permission_overwrites: [PartialChannelOverwrite]? = nil,
      parent_id: AnySnowflake? = nil,
      rtc_region: String? = nil,
      video_quality_mode: DiscordChannel.VideoQualityMode? = nil,
      default_auto_archive_duration: DiscordChannel.AutoArchiveDuration? = nil,
      available_tags: [PartialForumTag]? = nil,
      default_reaction_emoji: DiscordChannel.DefaultReaction? = nil,
      default_sort_order: DiscordChannel.SortOrder? = nil,
      default_forum_layout: DiscordChannel.ForumLayout? = nil,
      default_thread_rate_limit_per_user: Int? = nil
    ) {
      self.name = name
      self.type = type
      self.position = position
      self.topic = topic
      self.nsfw = nsfw
      self.rate_limit_per_user = rate_limit_per_user
      self.bitrate = bitrate
      self.user_limit = user_limit
      self.permission_overwrites = permission_overwrites
      self.parent_id = parent_id
      self.rtc_region = rtc_region
      self.video_quality_mode = video_quality_mode
      self.default_auto_archive_duration = default_auto_archive_duration
      self.available_tags = available_tags
      self.default_reaction_emoji = default_reaction_emoji
      self.default_sort_order = default_sort_order
      self.default_forum_layout = default_forum_layout
      self.default_thread_rate_limit_per_user =
        default_thread_rate_limit_per_user
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateCharacterCountDoesNotExceed(topic, max: 4_096, name: "topic")
      validateNumberInRangeOrNil(
        rate_limit_per_user,
        min: 0,
        max: 21_600,
        name: "rate_limit_per_user"
      )
      validateNumberInRangeOrNil(
        bitrate,
        min: 8_000,
        max: 384_000,
        name: "bitrate"
      )
      validateNumberInRangeOrNil(
        user_limit,
        min: 0,
        max: 10_000,
        name: "user_limit"
      )
      validateElementCountDoesNotExceed(
        available_tags,
        max: 20,
        name: "available_tags"
      )
      available_tags?.validate()
    }
  }

  public struct CreateGuild: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var icon: ImageData?
    public var verification_level: Guild.VerificationLevel?
    public var default_message_notifications: Guild.DefaultMessageNotificationLevel?
    public var explicit_content_filter: Guild.ExplicitContentFilterLevel?
    public var afk_channel_id: ChannelSnowflake?
    public var afk_timeout: Guild.AFKTimeout?
    public var system_channel_id: ChannelSnowflake?
    public var system_channel_flags: IntBitField<Guild.SystemChannelFlag>?

    public init(
      name: String,
      icon: ImageData? = nil,
      verification_level: Guild.VerificationLevel? = nil,
      default_message_notifications: Guild.DefaultMessageNotificationLevel? =
        nil,
      explicit_content_filter: Guild.ExplicitContentFilterLevel? = nil,
      afk_channel_id: ChannelSnowflake? = nil,
      afk_timeout: Guild.AFKTimeout? = nil,
      system_channel_id: ChannelSnowflake? = nil,
      system_channel_flags: IntBitField<Guild.SystemChannelFlag>? = nil
    ) {
      self.name = name
      self.icon = icon
      self.verification_level = verification_level
      self.default_message_notifications = default_message_notifications
      self.explicit_content_filter = explicit_content_filter
      self.afk_channel_id = afk_channel_id
      self.afk_timeout = afk_timeout
      self.system_channel_id = system_channel_id
      self.system_channel_flags = system_channel_flags
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 2, max: 100, name: "name")
    }
  }

  public struct ModifyGuild: Sendable, Encodable, ValidatablePayload {
    public var name: String?
    public var verification_level: Guild.VerificationLevel?
    public var default_message_notifications: Guild.DefaultMessageNotificationLevel?
    public var explicit_content_filter: Guild.ExplicitContentFilterLevel?
    public var afk_channel_id: ChannelSnowflake?
    public var afk_timeout: Guild.AFKTimeout?
    public var icon: ImageData?
    public var owner_id: UserSnowflake?
    public var splash: ImageData?
    public var discovery_splash: ImageData?
    public var banner: ImageData?
    public var system_channel_id: ChannelSnowflake?
    public var system_channel_flags: IntBitField<Guild.SystemChannelFlag>?
    public var rules_channel_id: ChannelSnowflake?
    public var public_updates_channel_id: ChannelSnowflake?
    public var preferred_locale: DiscordLocale?
    public var features: [Guild.Feature]?
    public var description: String?
    public var premium_progress_bar_enabled: Bool?

    public init(
      name: String? = nil,
      verification_level: Guild.VerificationLevel? = nil,
      default_message_notifications: Guild.DefaultMessageNotificationLevel? =
        nil,
      explicit_content_filter: Guild.ExplicitContentFilterLevel? = nil,
      afk_channel_id: ChannelSnowflake? = nil,
      afk_timeout: Guild.AFKTimeout? = nil,
      icon: ImageData? = nil,
      owner_id: UserSnowflake? = nil,
      splash: ImageData? = nil,
      discovery_splash: ImageData? = nil,
      banner: ImageData? = nil,
      system_channel_id: ChannelSnowflake? = nil,
      system_channel_flags: IntBitField<Guild.SystemChannelFlag>? = nil,
      rules_channel_id: ChannelSnowflake? = nil,
      public_updates_channel_id: ChannelSnowflake? = nil,
      preferred_locale: DiscordLocale? = nil,
      features: [Guild.Feature]? = nil,
      description: String? = nil,
      premium_progress_bar_enabled: Bool? = nil
    ) {
      self.name = name
      self.verification_level = verification_level
      self.default_message_notifications = default_message_notifications
      self.explicit_content_filter = explicit_content_filter
      self.afk_channel_id = afk_channel_id
      self.afk_timeout = afk_timeout
      self.icon = icon
      self.owner_id = owner_id
      self.splash = splash
      self.discovery_splash = discovery_splash
      self.banner = banner
      self.system_channel_id = system_channel_id
      self.system_channel_flags = system_channel_flags
      self.rules_channel_id = rules_channel_id
      self.public_updates_channel_id = public_updates_channel_id
      self.preferred_locale = preferred_locale
      self.features = features
      self.description = description
      self.premium_progress_bar_enabled = premium_progress_bar_enabled
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 2, max: 100, name: "name")
    }
  }

  /// https://docs.discord.food/resources/auto-moderation#automod-trigger-metadata
  public struct AutoModTriggerMetadata: Sendable, Codable, ValidatablePayload {
    public var keyword_filter: [String]
    public var regex_patterns: [String]
    public var presets: [Int]
    public var allow_list: [String]
    public var mention_total_limit: Int
    public var mention_raid_protection_enabled: Bool

    public init(
      keyword_filter: [String],
      regex_patterns: [String],
      presets: [Int],
      allow_list: [String],
      mention_total_limit: Int,
      mention_raid_protection_enabled: Bool
    ) {
      self.keyword_filter = keyword_filter
      self.regex_patterns = regex_patterns
      self.presets = presets
      self.allow_list = allow_list
      self.mention_total_limit = mention_total_limit
      self.mention_raid_protection_enabled = mention_raid_protection_enabled
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountDoesNotExceed(
        keyword_filter,
        max: 1000,
        name: "keyword_filter"
      )
      validateElementCountDoesNotExceed(
        regex_patterns,
        max: 10,
        name: "regex_patterns"
      )
      validateElementCountDoesNotExceed(
        allow_list,
        max: 1000,
        name: "allow_list"
      )
      validateHasPrecondition(
        condition: mention_total_limit <= 50,
        allowedIf: !mention_raid_protection_enabled,
        name: "mention_total_limit",
        reason:
          "'mention_total_limit' must be less than or equal to 50 when 'mention_raid_protection_enabled' is false"
      )
    }
  }

  /// https://docs.discord.food/resources/auto-moderation#execute-automod-alert-action
  public struct ExecuteAutoModAlertAction: Sendable, Codable, ValidatablePayload {
    public var channel_id: ChannelSnowflake
    public var message_id: MessageSnowflake
    public var alert_action_type: AlertActionKind

    public enum AlertActionKind: Int, Sendable, Codable {
      case setCompleted = 1
      case unsetCompleted = 2
      case deleteUserMessage = 3
      case submitFeedback = 4
    }

    public func validate() -> [ValidationFailure] {
    }
  }

  /// https://discord.com/developers/docs/resources/channel#bulk-delete-messages-json-params
  public struct BulkDeleteMessages: Sendable, Codable, ValidatablePayload {
    public var messages: [MessageSnowflake]

    public init(messages: [MessageSnowflake]) {
      self.messages = messages
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountInRange(messages, min: 2, max: 100, name: "messages")
    }
  }

  /// https://docs.discord.food/topics/read-state#acknowledge-message
  public struct AcknowledgeMessage: Sendable, Codable, ValidatablePayload {
    public var token: String?
    public var manual: Bool?
    public var mention_count: Int?
    public var flags: IntBitField<Gateway.ReadState.Flags>?
    public var last_viewed: Int?

    public init(
      token: String? = nil,
      manual: Bool? = nil,
      mention_count: Int? = nil,
      flags: IntBitField<Gateway.ReadState.Flags>? = nil,
      last_viewed: Int? = nil
    ) {
      self.token = token
      self.manual = manual
      self.mention_count = mention_count
      self.flags = flags
      self.last_viewed = last_viewed
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/channel#edit-channel-permissions-json-params
  public struct EditChannelPermissions: Sendable, Codable, ValidatablePayload {
    public var type: DiscordChannel.Overwrite.Kind
    public var allow: StringBitField<Permission>?
    public var deny: StringBitField<Permission>?

    public init(
      type: DiscordChannel.Overwrite.Kind,
      allow: StringBitField<Permission>? = nil,
      deny: StringBitField<Permission>? = nil
    ) {
      self.type = type
      self.allow = allow
      self.deny = deny
    }

    public func validate() -> [ValidationFailure] {}
  }

  public enum Count: Sendable, Encodable, ExpressibleByIntegerLiteral {
    case unlimited
    case count(Int)

    public init(integerLiteral value: Int) {
      if value == 0 {
        self = .unlimited
      } else {
        self = .count(value)
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .unlimited:
        try container.encode(0)
      case .count(let count):
        try container.encode(count)
      }
    }
  }

  /// https://discord.com/developers/docs/resources/channel#create-channel-invite-json-params
  public struct CreateChannelInvite: Sendable, Encodable, ValidatablePayload {
    public var max_age: Count?
    public var max_uses: Count?
    public var temporary: Bool?
    public var unique: Bool?
    public var target_type: Invite.TargetKind?
    public var target_user_id: UserSnowflake?
    public var target_application_id: ApplicationSnowflake?

    public init(
      max_age: Count? = nil,
      max_uses: Count? = nil,
      temporary: Bool? = nil,
      unique: Bool? = nil,
      target_type: Invite.TargetKind? = nil,
      target_user_id: UserSnowflake? = nil,
      target_application_id: ApplicationSnowflake? = nil
    ) {
      self.max_age = max_age
      self.max_uses = max_uses
      self.temporary = temporary
      self.unique = unique
      self.target_type = target_type
      self.target_user_id = target_user_id
      self.target_application_id = target_application_id
    }

    public func validate() -> [ValidationFailure] {
      switch max_age {
      case .unlimited, .none:
        Optional<ValidationFailure>.none
      case .count(let count):
        validateNumberInRangeOrNil(count, min: 0, max: 604_800, name: "max_age")
      }
      switch max_uses {
      case .unlimited, .none:
        Optional<ValidationFailure>.none
      case .count(let count):
        validateNumberInRangeOrNil(count, min: 0, max: 100, name: "max_uses")
      }
      if target_type == .stream {
        validateHasPrecondition(
          condition: target_user_id != nil,
          allowedIf: target_type == .stream,
          name: "target_user_id",
          reason:
            "'target_user_id' & 'target_type == .stream' require each other"
        )
      }
      if target_type == .embeddedApplication {
        validateHasPrecondition(
          condition: target_application_id != nil,
          allowedIf: target_type == .embeddedApplication,
          name: "target_user_id",
          reason:
            "'target_application_id' & 'target_type == .embeddedApplication' require each other"
        )
      }
    }
  }

  /// https://discord.com/developers/docs/resources/channel#follow-announcement-channel-json-params
  public struct FollowAnnouncementChannel: Sendable, Encodable,
    ValidatablePayload
  {
    public var webhook_channel_id: ChannelSnowflake

    public init(webhook_channel_id: ChannelSnowflake) {
      self.webhook_channel_id = webhook_channel_id
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/channel#group-dm-add-recipient-json-params
  public struct AddGroupDMUser: Sendable, Encodable, ValidatablePayload {
    public var access_token: String
    public var nick: String

    public init(access_token: String, nick: String) {
      self.access_token = access_token
      self.nick = nick
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/emoji#create-guild-emoji-json-params
  public struct CreateGuildEmoji: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var image: ImageData
    public var roles: [RoleSnowflake]

    public init(name: String, image: ImageData, roles: [RoleSnowflake]) {
      self.name = name
      self.image = image
      self.roles = roles
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/emoji#create-guild-emoji-json-params
  public struct ModifyGuildEmoji: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var roles: [RoleSnowflake]

    public init(name: String, roles: [RoleSnowflake]) {
      self.name = name
      self.roles = roles
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-channel-positions-json-params
  public struct ModifyGuildChannelPositions: Sendable, Encodable,
    ValidatablePayload
  {
    public var id: ChannelSnowflake
    public var position: Int?
    public var lock_permissions: Bool?
    public var parent_id: ChannelSnowflake?

    public init(
      id: ChannelSnowflake,
      position: Int? = nil,
      lock_permissions: Bool? = nil,
      parent_id: ChannelSnowflake? = nil
    ) {
      self.id = id
      self.position = position
      self.lock_permissions = lock_permissions
      self.parent_id = parent_id
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#add-guild-member-json-params
  public struct AddGuildMember: Sendable, Encodable, ValidatablePayload {
    public var access_token: String
    public var nick: String?
    public var roles: [RoleSnowflake]?
    public var mute: Bool?
    public var deaf: Bool?

    public init(
      access_token: String,
      nick: String? = nil,
      roles: [RoleSnowflake]? = nil,
      mute: Bool? = nil,
      deaf: Bool? = nil
    ) {
      self.access_token = access_token
      self.nick = nick
      self.roles = roles
      self.mute = mute
      self.deaf = deaf
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-member-json-params
  public struct ModifyGuildMember: Sendable, Encodable, ValidatablePayload {
    public var nick: String?
    public var roles: [RoleSnowflake]?
    public var mute: Bool?
    public var deaf: Bool?
    public var channel_id: ChannelSnowflake?
    public var communication_disabled_until: DiscordTimestamp?
    public var flags: IntBitField<Guild.Member.Flag>?

    public init(
      nick: String? = nil,
      roles: [RoleSnowflake]? = nil,
      mute: Bool? = nil,
      deaf: Bool? = nil,
      channel_id: ChannelSnowflake? = nil,
      communication_disabled_until: DiscordTimestamp? = nil,
      flags: IntBitField<Guild.Member.Flag>? = nil
    ) {
      self.nick = nick
      self.roles = roles
      self.mute = mute
      self.deaf = deaf
      self.channel_id = channel_id
      self.communication_disabled_until = communication_disabled_until
      self.flags = flags
    }

    public func validate() -> [ValidationFailure] {
      let now = Date().timeIntervalSince1970
      validateNumberInRangeOrNil(
        communication_disabled_until?.date.timeIntervalSince1970,
        min: now,
        max: now + (28 * 24 * 60 * 60),
        name: "communication_disabled_until.date.timeIntervalSince1970"
      )
    }
  }

  /// https://discord.com/developers/docs/resources/guild#modify-current-member-json-params
  /// https://docs.discord.food/resources/guild#modify-current-guild-member
  /// A field left `nil` is not sent; `.some(nil)` sends `null` and clears it.
  public struct ModifyCurrentMember: Sendable, Encodable, ValidatablePayload {
    public var nick: String??
    public var pronouns: String??
    /// Nitro only.
    public var bio: String??
    /// Nitro only.
    public var avatar: ImageData??

    public init(
      nick: String?? = nil,
      pronouns: String?? = nil,
      bio: String?? = nil,
      avatar: ImageData?? = nil
    ) {
      self.nick = nick
      self.pronouns = pronouns
      self.bio = bio
      self.avatar = avatar
    }

    enum CodingKeys: String, CodingKey {
      case nick, pronouns, bio, avatar
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeNullable(nick, forKey: .nick)
      try container.encodeNullable(pronouns, forKey: .pronouns)
      try container.encodeNullable(bio, forKey: .bio)
      try container.encodeNullable(avatar, forKey: .avatar)
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountDoesNotExceed(nick ?? nil, max: 32, name: "nick")
      validateCharacterCountDoesNotExceed(pronouns ?? nil, max: 40, name: "pronouns")
      validateCharacterCountDoesNotExceed(bio ?? nil, max: 190, name: "bio")
    }
  }

  /// https://discord.com/developers/docs/resources/guild#create-guild-ban-json-params
  public struct CreateGuildBan: Sendable, Encodable, ValidatablePayload {
    public var delete_message_seconds: Int?

    public init(delete_message_seconds: Int? = nil) {
      self.delete_message_seconds = delete_message_seconds
    }

    public func validate() -> [ValidationFailure] {
      validateNumberInRangeOrNil(
        delete_message_seconds,
        min: 0,
        max: 604_800,
        name: "delete_message_seconds"
      )
    }
  }

  /// https://discord.com/developers/docs/resources/guild#bulk-guild-ban-json-params
  public struct CreateBulkGuildBan: Sendable, Encodable, ValidatablePayload {
    public var user_ids: [UserSnowflake]
    public var delete_message_seconds: Int?

    public init(user_ids: [UserSnowflake], delete_message_seconds: Int? = nil) {
      self.user_ids = user_ids
      self.delete_message_seconds = delete_message_seconds
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountInRange(user_ids, min: 1, max: 200, name: "user_ids")
      validateNumberInRangeOrNil(
        delete_message_seconds,
        min: 0,
        max: 604_800,
        name: "delete_message_seconds"
      )
    }
  }

  /// https://discord.com/developers/docs/resources/guild#create-guild-role-json-params
  /// https://discord.com/developers/docs/resources/guild#modify-guild-role-json-params
  public struct GuildRole: Sendable, Codable, ValidatablePayload {
    public var name: String?
    public var permissions: StringBitField<Permission>?
    public var color: DiscordColor?
    public var hoist: Bool?
    public var icon: ImageData?
    public var unicode_emoji: String?
    public var mentionable: Bool?

    /// `icon` and `unicode_emoji` require `roleIcons` guild feature,
    /// which most guild don't have.
    /// No fields are required. If you send an empty payload, you'll get a basic role
    /// with a name like "new role".
    public init(
      name: String? = nil,
      permissions: StringBitField<Permission>? = nil,
      color: DiscordColor? = nil,
      hoist: Bool? = nil,
      icon: ImageData? = nil,
      unicode_emoji: String? = nil,
      mentionable: Bool? = nil
    ) {
      self.name = name
      self.permissions = permissions
      self.color = color
      self.hoist = hoist
      self.icon = icon
      self.unicode_emoji = unicode_emoji
      self.mentionable = mentionable
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountDoesNotExceed(name, max: 1_000, name: "name")
    }
  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-role-positions-json-params
  public struct ModifyGuildRolePositions: Sendable, Encodable,
    ValidatablePayload
  {
    public var id: RoleSnowflake
    public var position: Int?

    public init(id: RoleSnowflake, position: Int? = nil) {
      self.id = id
      self.position = position
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-mfa-level-json-params
  public struct ModifyGuildMFALevel: Sendable, Encodable, ValidatablePayload {
    public var level: Guild.MFALevel

    public init(level: Guild.MFALevel) {
      self.level = level
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#begin-guild-prune-json-params
  public struct BeginGuildPrune: Sendable, Encodable, ValidatablePayload {
    public var days: Int
    public var compute_prune_count: Bool
    public var include_roles: [RoleSnowflake]

    public init(
      days: Int,
      compute_prune_count: Bool,
      include_roles: [RoleSnowflake]
    ) {
      self.days = days
      self.compute_prune_count = compute_prune_count
      self.include_roles = include_roles
    }

    public func validate() -> [ValidationFailure] {
      validateNumberInRangeOrNil(days, min: 1, max: 30, name: "days")
    }
  }

  /// https://discord.com/developers/docs/resources/guild#get-guild-widget-image-widget-style-options
  /// Cases show sizes from small to big.
  /// See Discord docs for examples.
  public enum WidgetStyle: String, Sendable {
    case shield = "small"
    case banner1 = "banner1"
    case banner2 = "banner2"
    case banner3 = "banner3"
    case banner4 = "banner4"

    public static let `default`: WidgetStyle = .shield
  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-widget
  public struct ModifyWidgetSettings: Sendable, Encodable, ValidatablePayload {
    public var enabled: Bool?
    public var channel_id: ChannelSnowflake?

    public init(enabled: Bool? = nil, channel_id: ChannelSnowflake? = nil) {
      self.enabled = enabled
      self.channel_id = channel_id
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-welcome-screen-json-params
  public struct ModifyGuildWelcomeScreen: Sendable, Encodable,
    ValidatablePayload
  {
    public var enabled: Bool?
    public var welcome_channels: [Guild.WelcomeScreen.Channel]?
    public var description: String?

    public init(
      enabled: Bool? = nil,
      welcome_channels: [Guild.WelcomeScreen.Channel]? = nil,
      description: String? = nil
    ) {
      self.enabled = enabled
      self.welcome_channels = welcome_channels
      self.description = description
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#modify-current-user-voice-state-json-params
  public struct ModifyCurrentUserVoiceState: Sendable, Encodable,
    ValidatablePayload
  {
    public var channel_id: ChannelSnowflake?
    public var suppress: Bool?
    public var request_to_speak_timestamp: DiscordTimestamp?

    public init(
      channel_id: ChannelSnowflake? = nil,
      suppress: Bool? = nil,
      request_to_speak_timestamp: DiscordTimestamp? = nil
    ) {
      self.channel_id = channel_id
      self.suppress = suppress
      self.request_to_speak_timestamp = request_to_speak_timestamp
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild#modify-user-voice-state-json-params
  public struct ModifyUserVoiceState: Sendable, Encodable, ValidatablePayload {
    public var channel_id: ChannelSnowflake?
    public var suppress: Bool?

    public init(channel_id: ChannelSnowflake? = nil, suppress: Bool? = nil) {
      self.channel_id = channel_id
      self.suppress = suppress
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild-scheduled-event#create-guild-scheduled-event-json-params
  public struct CreateGuildScheduledEvent: Sendable, Encodable,
    ValidatablePayload
  {
    public var channel_id: ChannelSnowflake?
    public var entity_metadata: GuildScheduledEvent.EntityMetadata?
    public var name: String
    public var privacy_level: GuildScheduledEvent.PrivacyLevel
    public var scheduled_start_time: DiscordTimestamp
    public var scheduled_end_time: DiscordTimestamp?
    public var description: String?
    public var entity_type: GuildScheduledEvent.EntityKind
    public var image: ImageData?
    public var recurrence_rule: GuildScheduledEvent.RecurrenceRule?

    public init(
      channel_id: ChannelSnowflake? = nil,
      entity_metadata: GuildScheduledEvent.EntityMetadata? = nil,
      name: String,
      privacy_level: GuildScheduledEvent.PrivacyLevel,
      scheduled_start_time: DiscordTimestamp,
      scheduled_end_time: DiscordTimestamp? = nil,
      description: String? = nil,
      entity_type: GuildScheduledEvent.EntityKind,
      image: ImageData? = nil,
      recurrence_rule: GuildScheduledEvent.RecurrenceRule? = nil
    ) {
      self.channel_id = channel_id
      self.entity_metadata = entity_metadata
      self.name = name
      self.privacy_level = privacy_level
      self.scheduled_start_time = scheduled_start_time
      self.scheduled_end_time = scheduled_end_time
      self.description = description
      self.entity_type = entity_type
      self.image = image
      self.recurrence_rule = recurrence_rule
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild-scheduled-event#modify-guild-scheduled-event-json-params
  public struct ModifyGuildScheduledEvent: Sendable, Encodable,
    ValidatablePayload
  {
    public var channel_id: ChannelSnowflake?
    public var entity_metadata: GuildScheduledEvent.EntityMetadata?
    public var name: String?
    public var privacy_level: GuildScheduledEvent.PrivacyLevel?
    public var scheduled_start_time: DiscordTimestamp?
    public var scheduled_end_time: DiscordTimestamp?
    public var description: String?
    public var entity_type: GuildScheduledEvent.EntityKind?
    public var status: GuildScheduledEvent.Status?
    public var image: ImageData?
    public var recurrence_rule: GuildScheduledEvent.RecurrenceRule?

    public init(
      channel_id: ChannelSnowflake? = nil,
      entity_metadata: GuildScheduledEvent.EntityMetadata? = nil,
      name: String? = nil,
      privacy_level: GuildScheduledEvent.PrivacyLevel? = nil,
      scheduled_start_time: DiscordTimestamp? = nil,
      scheduled_end_time: DiscordTimestamp? = nil,
      description: String? = nil,
      entity_type: GuildScheduledEvent.EntityKind? = nil,
      status: GuildScheduledEvent.Status? = nil,
      image: ImageData? = nil,
      recurrence_rule: GuildScheduledEvent.RecurrenceRule? = nil
    ) {
      self.channel_id = channel_id
      self.entity_metadata = entity_metadata
      self.name = name
      self.privacy_level = privacy_level
      self.scheduled_start_time = scheduled_start_time
      self.scheduled_end_time = scheduled_end_time
      self.description = description
      self.entity_type = entity_type
      self.status = status
      self.image = image
      self.recurrence_rule = recurrence_rule
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/guild-template#create-guild-from-guild-template-json-params
  public struct CreateGuildFromGuildTemplate: Sendable, Encodable,
    ValidatablePayload
  {
    public var name: String
    public var icon: ImageData?

    public init(name: String, icon: ImageData? = nil) {
      self.name = name
      self.icon = icon
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 2, max: 100, name: "name")
    }
  }

  /// https://discord.com/developers/docs/resources/guild-template#create-guild-template-json-params
  public struct CreateGuildTemplate: Sendable, Encodable, ValidatablePayload {
    public var name: String
    public var description: String?

    public init(name: String, description: String? = nil) {
      self.name = name
      self.description = description
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateCharacterCountDoesNotExceed(
        description,
        max: 120,
        name: "description"
      )
    }
  }

  /// https://discord.com/developers/docs/resources/guild-template#modify-guild-template-json-params
  public struct ModifyGuildTemplate: Sendable, Encodable, ValidatablePayload {
    public var name: String?
    public var description: String?

    public init(name: String? = nil, description: String? = nil) {
      self.name = name
      self.description = description
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 1, max: 100, name: "name")
      validateCharacterCountDoesNotExceed(
        description,
        max: 120,
        name: "description"
      )
    }
  }

  /// https://discord.com/developers/docs/resources/stage-instance#create-stage-instance-json-params
  public struct CreateStageInstance: Sendable, Encodable, ValidatablePayload {
    public var channel_id: ChannelSnowflake
    public var topic: String
    public var privacy_level: StageInstance.PrivacyLevel?
    public var send_start_notification: Bool?
    public var guild_scheduled_event_id: GuildScheduledEventSnowflake?

    public init(
      channel_id: ChannelSnowflake,
      topic: String,
      privacy_level: StageInstance.PrivacyLevel? = nil,
      send_start_notification: Bool? = nil,
      guild_scheduled_event_id: GuildScheduledEventSnowflake? = nil
    ) {
      self.channel_id = channel_id
      self.topic = topic
      self.privacy_level = privacy_level
      self.send_start_notification = send_start_notification
      self.guild_scheduled_event_id = guild_scheduled_event_id
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(topic, min: 1, max: 120, name: "topic")
    }
  }

  /// https://discord.com/developers/docs/resources/stage-instance#modify-stage-instance-json-params
  public struct ModifyStageInstance: Sendable, Encodable, ValidatablePayload {
    public var topic: String?
    public var privacy_level: StageInstance.PrivacyLevel?

    public init(
      topic: String? = nil,
      privacy_level: StageInstance.PrivacyLevel? = nil
    ) {
      self.topic = topic
      self.privacy_level = privacy_level
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRangeOrNil(topic, min: 1, max: 120, name: "topic")
    }
  }

  /// https://discord.com/developers/docs/resources/sticker#create-guild-sticker-form-params
  public struct CreateGuildSticker: Sendable, Encodable, MultipartEncodable,
    ValidatablePayload
  {
    public var name: String
    public var description: String
    public var tags: String
    public var file: RawFile

    public static var rawEncodable: Bool { true }
    public var rawFields: [(String, String)] {
      [
        ("name", name),
        ("description", description),
        ("tags", tags),
      ]
    }
    public var files: [RawFile]? {
      [self.file]
    }

    public init(name: String, description: String, tags: String, file: RawFile) {
      self.name = name
      self.description = description
      self.tags = tags
      self.file = file
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 2, max: 30, name: "name")
      validateCharacterCountInRangeOrNil(
        description,
        min: 2,
        max: 100,
        name: "description"
      )
      validateCharacterCountDoesNotExceed(tags, max: 200, name: "tags")
    }
  }

  /// https://discord.com/developers/docs/resources/sticker#modify-guild-sticker-json-params
  public struct ModifyGuildSticker: Sendable, Encodable, ValidatablePayload {
    public var name: String?
    public var description: String?
    public var tags: String?

    public init(
      name: String? = nil,
      description: String? = nil,
      tags: String? = nil
    ) {
      self.name = name
      self.description = description
      self.tags = tags
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(name, min: 2, max: 30, name: "name")
      validateCharacterCountInRangeOrNil(
        description,
        min: 2,
        max: 100,
        name: "description"
      )
      validateCharacterCountDoesNotExceed(tags, max: 200, name: "tags")
    }
  }

  /// https://discord.com/developers/docs/resources/user#modify-current-user-json-params
  /// https://docs.discord.food/resources/user#modify-current-user
  /// A field left `nil` is not sent; `.some(nil)` sends `null` and clears it.
  public struct ModifyCurrentUser: Sendable, Encodable, ValidatablePayload {
    public var global_name: String??
    public var avatar: ImageData??
    public var pronouns: String??
    public var bio: String??
    public var accent_color: DiscordColor??
    /// Nitro only.
    public var banner: ImageData??

    public init(
      global_name: String?? = nil,
      avatar: ImageData?? = nil,
      pronouns: String?? = nil,
      bio: String?? = nil,
      accent_color: DiscordColor?? = nil,
      banner: ImageData?? = nil
    ) {
      self.global_name = global_name
      self.avatar = avatar
      self.pronouns = pronouns
      self.bio = bio
      self.accent_color = accent_color
      self.banner = banner
    }

    enum CodingKeys: String, CodingKey {
      case global_name, avatar, pronouns, bio, accent_color, banner
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encodeNullable(global_name, forKey: .global_name)
      try container.encodeNullable(avatar, forKey: .avatar)
      try container.encodeNullable(pronouns, forKey: .pronouns)
      try container.encodeNullable(bio, forKey: .bio)
      try container.encodeNullable(accent_color, forKey: .accent_color)
      try container.encodeNullable(banner, forKey: .banner)
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountDoesNotExceed(global_name ?? nil, max: 32, name: "global_name")
      validateCharacterCountDoesNotExceed(pronouns ?? nil, max: 40, name: "pronouns")
      validateCharacterCountDoesNotExceed(bio ?? nil, max: 190, name: "bio")
    }
  }

  /// https://discord.com/developers/docs/resources/user#create-dm-json-params
  /// https://discord.com/developers/docs/resources/user#create-group-dm-json-params
  /// https://docs.discord.food/resources/channel#json-params
  public struct CreateDM: Sendable, Encodable, ValidatablePayload {
    //    public var recipient_id: UserSnowflake? // deprecated
    public var recipients: [UserSnowflake]?

    @inlinable
    public init(recipient: UserSnowflake) {
      self.recipients = [recipient]
    }

    @inlinable
    public init(recipients: [UserSnowflake]) {
      self.recipients = recipients
    }

    public func validate() -> [ValidationFailure] {
      if let recipients {
        validateElementCountInRange(
          recipients,
          min: 1,
          max: 10,
          name: "recipients"
        )
      }
    }
  }

  //  public struct CreateGroupDM: Sendable, Encodable, ValidatablePayload {
  //    public var recipients: [UserSnowflake]
  //
  //    public init(recipients: [UserSnowflake]) {
  //      self.recipients = recipients
  //    }
  //
  //    public func validate() -> [ValidationFailure] {}
  //  }

  /// https://discord.com/developers/docs/resources/guild#modify-guild-onboarding-json-params
  public struct UpdateGuildOnboarding: Sendable, Encodable, ValidatablePayload {
    public var prompts: [Guild.Onboarding.Prompt]?
    public var default_channel_ids: [ChannelSnowflake]?
    public var enabled: Bool?
    public var mode: Guild.Onboarding.Mode?

    public init(
      prompts: [Guild.Onboarding.Prompt]? = nil,
      default_channel_ids: [ChannelSnowflake]? = nil,
      enabled: Bool? = nil,
      mode: Guild.Onboarding.Mode? = nil
    ) {
      self.prompts = prompts
      self.default_channel_ids = default_channel_ids
      self.enabled = enabled
      self.mode = mode
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://discord.com/developers/docs/resources/poll#poll-create-request-object
  public struct CreatePollRequest: Sendable, Codable, Hashable,
    ValidatablePayload
  {
    public var question: Poll.Media
    public var answers: [Poll.Answer]
    /// "Number of hours the poll should be open for, up to 32 days"
    public var duration: Int
    public var allow_multiselect: Bool
    public var layout_type: Poll.LayoutKind?

    public init(
      question: Poll.Media,
      answers: [Poll.Answer],
      duration: Int,
      allow_multiselect: Bool,
      layout_type: Poll.LayoutKind? = nil
    ) {
      self.question = question
      self.answers = answers
      self.duration = duration
      self.allow_multiselect = allow_multiselect
      self.layout_type = layout_type
    }

    public func validate() -> [ValidationFailure] {
      question.validate()
      answers.map(\.poll_media).validate()
      validateElementCountDoesNotExceed(answers, max: 10, name: "answers")
      validateNumberInRangeOrNil(duration, min: 1, max: 768, name: "duration")/// 32 days max
    }
  }

  /// https://docs.discord.food/resources/relationships#send-friend-request
  public struct SendFriendRequest: Sendable, Encodable, ValidatablePayload {
    public var username: String
    public var discriminator: String?  // nil for migrated users

    public init(username: String, discriminator: String? = nil) {
      self.username = username
      self.discriminator = discriminator
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRange(username, min: 2, max: 32, name: "username")
      if let discriminator {
        validateCharacterCountInRange(
          discriminator,
          min: 4,
          max: 4,
          name: "discriminator"
        )
      }
    }
  }

  /// https://docs.discord.food/resources/relationships#create-relationship
  public struct CreateRelationship: Sendable, Encodable, ValidatablePayload {
    public var type: DiscordRelationship.Kind?
    public var from_friend_suggestion: Bool?
    public var confirm_stranger_request: Bool?

    public init(
      type: DiscordRelationship.Kind?,
      from_friend_suggestion: Bool? = nil,
      confirm_stranger_request: Bool? = nil
    ) {
      self.type = type
      self.from_friend_suggestion = from_friend_suggestion
      self.confirm_stranger_request = confirm_stranger_request
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// Only the fields that are set are changed. Not every service supports all of them.
  /// https://docs.discord.food/resources/connected-accounts#modify-user-connection
  public struct ModifyConnection: Sendable, Encodable, ValidatablePayload {
    public var show_activity: Bool?
    public var friend_sync: Bool?
    public var visibility: DiscordUser.Connection.VisibilityKind?
    public var metadata_visibility: DiscordUser.Connection.VisibilityKind?

    public init(
      show_activity: Bool? = nil,
      friend_sync: Bool? = nil,
      visibility: DiscordUser.Connection.VisibilityKind? = nil,
      metadata_visibility: DiscordUser.Connection.VisibilityKind? = nil
    ) {
      self.show_activity = show_activity
      self.friend_sync = friend_sync
      self.visibility = visibility
      self.metadata_visibility = metadata_visibility
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// Only the fields that are set are sent. Channel overrides are keyed by
  /// channel ID and merge with the ones already saved.
  /// https://docs.discord.food/resources/user-settings#modify-user-guild-settings
  public struct ModifyUserGuildSettings: Sendable, Encodable, ValidatablePayload {
    public var message_notifications: Int?
    public var muted: Bool?
    public var suppress_everyone: Bool?
    public var suppress_roles: Bool?
    public var channel_overrides: [String: ChannelOverride]?

    public var mute_config: MuteConfig?

    public struct ChannelOverride: Sendable, Encodable {
      public var message_notifications: Int?
      public var muted: Bool?
      public var mute_config: MuteConfig?

      public init(
        message_notifications: Int? = nil, muted: Bool? = nil, mute_config: MuteConfig? = nil
      ) {
        self.message_notifications = message_notifications
        self.muted = muted
        self.mute_config = mute_config
      }
    }

    /// How long a mute lasts. `selected_time_window` is in seconds, -1 with no
    /// `end_time` meaning until it is turned off.
    public struct MuteConfig: Sendable, Encodable {
      public var selected_time_window: Int
      public var end_time: Date?

      public init(selected_time_window: Int, end_time: Date?) {
        self.selected_time_window = selected_time_window
        self.end_time = end_time
      }

      public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selected_time_window, forKey: .selected_time_window)
        // Discord wants the key present, as null, for a mute without an end
        if let end_time {
          try container.encode(ISO8601DateFormatter().string(from: end_time), forKey: .end_time)
        } else {
          try container.encodeNil(forKey: .end_time)
        }
      }

      enum CodingKeys: String, CodingKey {
        case selected_time_window, end_time
      }
    }

    public init(
      message_notifications: Int? = nil,
      muted: Bool? = nil,
      mute_config: MuteConfig? = nil,
      suppress_everyone: Bool? = nil,
      suppress_roles: Bool? = nil,
      channel_overrides: [String: ChannelOverride]? = nil
    ) {
      self.message_notifications = message_notifications
      self.muted = muted
      self.mute_config = mute_config
      self.suppress_everyone = suppress_everyone
      self.suppress_roles = suppress_roles
      self.channel_overrides = channel_overrides
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// Only `accepted` is open to regular accounts.
  /// https://docs.discord.food/resources/channel#update-message-request
  public struct UpdateMessageRequest: Sendable, Encodable, ValidatablePayload {
    public var consent_status: MessageRequestConsentStatus

    public init(consent_status: MessageRequestConsentStatus = .accepted) {
      self.consent_status = consent_status
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/message#create-poll-vote
  public struct CreatePollVote: Sendable, Encodable, ValidatablePayload {
    /// Answer IDs as strings, the way Discord's client sends them. Empty removes the vote.
    public var answer_ids: [String]

    public init(answer_ids: [String]) {
      self.answer_ids = answer_ids
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountDoesNotExceed(answer_ids, max: 10, name: "answer_ids")
    }
  }

  /// https://docs.discord.food/resources/channel#batch-reject-message-requests
  public struct BatchRejectMessageRequests: Sendable, Encodable, ValidatablePayload {
    public var channel_ids: [ChannelSnowflake]

    public init(channel_ids: [ChannelSnowflake]) {
      self.channel_ids = channel_ids
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountInRange(channel_ids, min: 1, max: 50, name: "channel_ids")
    }
  }

  /// https://docs.discord.food/topics/read-state#bulk-acknowledge
  public struct BulkAckReadStates: Sendable, Encodable, ValidatablePayload {
    public var read_states: [ReadState]

    public struct ReadState: Sendable, Encodable {
      public var channel_id: ChannelSnowflake
      public var message_id: MessageSnowflake
      public var read_state_type: Int?

      public init(
        channel_id: ChannelSnowflake, message_id: MessageSnowflake, read_state_type: Int? = nil
      ) {
        self.channel_id = channel_id
        self.message_id = message_id
        self.read_state_type = read_state_type
      }
    }

    public init(read_states: [ReadState]) {
      self.read_states = read_states
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/relationships#modify-relationship
  public struct ModifyRelationship: Sendable, Encodable, ValidatablePayload {
    public var nickname: String?

    public init(nickname: String?) {
      self.nickname = nickname
    }

    public func validate() -> [ValidationFailure] {
      validateCharacterCountInRangeOrNil(
        nickname,
        min: 1,
        max: 32,
        name: "nickname"
      )
    }
  }

  /// https://docs.discord.food/resources/relationships#bulk-remove-relationships
  public struct BulkRemoveRelationships: Sendable, Encodable, ValidatablePayload {
    public var filters: Set<Filter>?
    public init(filters: Set<Filter>? = nil) {
      self.filters = filters
    }
    public func validate() -> [ValidationFailure] {}

    public enum Filter: Int, Sendable, Codable {
      case spam = 1
      case ignored = 2
    }
  }

  /// https://docs.discord.food/resources/relationships#bulk-add-relationships
  public struct BulkAddRelationships: Sendable, Encodable, ValidatablePayload {
    public var user_ids: [UserSnowflake]
    public var token: String  // contact sync is the only way to bulk add. contact sync token required.
    public init(user_ids: [UserSnowflake], token: String) {
      self.user_ids = user_ids
      self.token = token
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/soundboard#send-soundboard-sound
  public struct SendSoundboardSound: Sendable, Encodable, ValidatablePayload {
    public var sound_id: SoundSnowflake
    public var source_guild_id: GuildSnowflake?

    public init(
      sound_id: SoundSnowflake,
      source_guild_id: GuildSnowflake? = nil
    ) {
      self.sound_id = sound_id
      self.source_guild_id = source_guild_id
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/invite#accept-invite
  public struct AcceptInvite: Sendable, Encodable, ValidatablePayload {
    public var session_id: String?

    public init(session_id: String? = nil) {
      self.session_id = session_id
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/invite#create-user-invite
  public struct CreateUserInvite: Sendable, Encodable, ValidatablePayload {
    public var code: String?

    public init(code: String? = nil) {
      self.code = code
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/message#create-attachments
  public struct CreateApplicationExternalAssets: Sendable, Encodable, ValidatablePayload {
    public var urls: [String]

    public init(urls: [String]) {
      self.urls = urls
    }

    public func validate() -> [ValidationFailure] {}
  }

  public struct CreateAttachments: Sendable, Encodable, ValidatablePayload {
    public var files: [UploadAttachment]

    public init(files: [UploadAttachment]) {
      self.files = files
    }

    public func validate() -> [ValidationFailure] {}

    public struct UploadAttachment: Sendable, Encodable {
      public var id: AttachmentSnowflake?
      public var filename: String
      public var file_size: Int

      public init(
        id: AttachmentSnowflake? = nil,
        filename: String,
        file_size: Int
      ) {
        self.id = id
        self.filename = filename
        self.file_size = file_size
      }
    }
  }

  /// https://docs.discord.food/remote-authentication/mobile#create-remote-auth-session
  public struct CreateRemoteAuthSession: Sendable, Encodable, ValidatablePayload {
    public var fingerprint: String

    public init(fingerprint: String) {
      self.fingerprint = fingerprint
    }
    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/remote-authentication/mobile#finish-remote-auth
  public struct RemoteAuthSession: Sendable, Encodable, ValidatablePayload {
    public var handshake_token: String
    /// Unsupported as of writing.
    public var temporary_token: Bool?

    public init(handshake_token: String, temporary_token: Bool? = nil) {
      self.handshake_token = handshake_token
      self.temporary_token = temporary_token
    }

    public func validate() -> [ValidationFailure] {}
  }

  public struct ExchangeRemoteAuthTicket: Sendable, Encodable,
    ValidatablePayload
  {
    public var ticket: String

    public init(ticket: String) {
      self.ticket = ticket
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/user-settings-proto#json-params
  public struct ModifyUserSettingsProto: Sendable, Codable, ValidatablePayload {
    /// Only the fields being changed; the server merges them into the stored settings.
    public var settings: DiscordModels.UserSettingsProto
    public var required_data_version: UInt32?  // get this from within the last fetched proto

    public init(
      settings: DiscordModels.UserSettingsProto,
      required_data_version: UInt32? = nil
    ) {
      self.settings = settings
      self.required_data_version = required_data_version
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/channel#modify-call
  public struct ModifyCall: Sendable, Encodable, ValidatablePayload {
    public var region: String?

    public init(region: String? = nil) {
      self.region = region
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/channel#ring-channel-recipients
  public struct RingChannelRecipients: Sendable, Encodable, ValidatablePayload {
    public var recipients: [UserSnowflake]?

    public init(recipients: [UserSnowflake]? = nil) {
      self.recipients = recipients
    }

    public func validate() -> [ValidationFailure] {}
  }
}

extension KeyedEncodingContainer {
  /// Skips an absent field and writes `null` for a present-but-empty one.
  mutating func encodeNullable<T: Encodable>(_ value: T??, forKey key: Key) throws {
    switch value {
    case .none: break
    case .some(.none): try encodeNil(forKey: key)
    case .some(.some(let value)): try encode(value, forKey: key)
    }
  }
}
