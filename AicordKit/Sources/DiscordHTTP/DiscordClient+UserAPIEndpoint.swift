//
//  DiscordClient+UserAPIEndpoint.swift
//  AicordKit
//
// Created by Lakhan Lothiyi on 03/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import DiscordModels

extension DiscordClient {
  // MARK: - Authentication
  /// https://docs.discord.food/authentication

  /// Returns the user experiment assignments and optionally guild experiment rollouts for the user or fingerprint.
  /// https://docs.discord.food/topics/experiments#get-experiment-assignments
  @inlinable
  public func getExperiments()
    async throws -> DiscordClientResponse<FingerprintExperiments>
  {
    let endpoint = UserAPIEndpoint.getExperiments
    return try await self.send(request: .init(to: endpoint))
  }

  /// Retrieves an authentication token for the given credentials.
  /// https://docs.discord.food/authentication#login-account
  @inlinable
  public func userLogin(
    payload: Payloads.Authentication,
    fingerprint: String
  ) async throws -> DiscordClientResponse<UserAuthentication> {
    let endpoint = UserAPIEndpoint.userLogin
    return try await self.send(
      request: .init(
        to: endpoint,
        headers: [
          "X-Fingerprint": fingerprint
        ]
      ),
      payload: payload
    )
  }

  /// Sends a multi-factor authentication code to the user's phone number for verification.
  /// https://docs.discord.food/authentication#send-mfa-sms
  @inlinable
  public func verifySendSMS(
    ticket: Secret,
    fingerprint: String? = nil
  ) async throws -> DiscordClientResponse<UserAuthenticationMFASMS> {
    if case .userNone = self.authentication {
      // idk if this is like super bad or not
      assert(
        fingerprint?.isEmpty == false,
        "verifySendSMS needs a real fingerprint when called from the unauthenticated login client."
      )
    }
    let endpoint = UserAPIEndpoint.verifySendSMS
    var headers: HTTPHeaders = [:]
    if let fingerprint {
      headers.replaceOrAdd(name: "X-Fingerprint", value: fingerprint)
    }
    return try await self.send(
      request: .init(to: endpoint, headers: headers),
      payload: Payloads.AuthenticationMFASendSMS(
        ticket: ticket
      )
    )
  }

  /// Verifies a multi-factor login and retrieves an authentication token using the specified authenticator type.
  /// https://docs.discord.food/authentication#verify-mfa-login
  @inlinable
  public func verifyMFALogin(
    type: Payloads.MFASubmitData.MFAKind,
    payload: Payloads.AuthenticationMFA,
    fingerprint: String
  ) async throws -> DiscordClientResponse<UserAuthentication> {
    let endpoint = UserAPIEndpoint.verifyMFALogin(type: type)
    return try await self.send(
      request: .init(
        to: endpoint,
        headers: [
          "X-Fingerprint": fingerprint
        ]
      ),
      payload: payload
    )
  }

  /// Returns up to 50 of the user's active authentication sessions.
  /// https://docs.discord.food/authentication#get-auth-sessions
  @inlinable
  public func getAuthSessions() async throws -> DiscordClientResponse<
    UserAuthenticationSessions
  > {
    let endpoint = UserAPIEndpoint.getAuthSessions
    return try await self.send(request: .init(to: endpoint))
  }

  /// Invalidates a list of authentication sessions. Returns a 204 empty response on success.
  /// NOTE: Requires MFA, hence you may receive an error and need to decode that for MFA Request object.
  /// https://docs.discord.food/authentication#logout-auth-sessions
  @inlinable
  public func logoutAuthSessions(_ sessionIdHashes: [String]) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.logoutAuthSessions
    return try await self.send(
      request: .init(to: endpoint),
      payload: Payloads.LogoutSessions(session_id_hashes: sessionIdHashes)
    )
  }

  /// Initiates the password rea process for the given email or phone number. Returns a 204 empty response on success.
  /// https://docs.discord.food/authentication#forgot-password
  @inlinable
  public func forgotPassword(
    payload: Payloads.ForgotPassword,
    fingerprint: String
  ) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.forgotPassword
    return try await self.send(
      request: .init(
        to: endpoint,
        headers: [
          "X-Fingerprint": fingerprint
        ]
      ),
      payload: payload
    )
  }

  /// Verifies a user's identity using multi-factor authentication. On success, returns a cookie that can be used to bypass MFA for the next 5 minutes.
  /// https://docs.discord.food/authentication#verify-mfa
  @inlinable
  public func verifyMFA(
    payload: Payloads.MFASubmitData
  ) async throws -> DiscordClientResponse<MFAResponse> {
    let endpoint = UserAPIEndpoint.verifyMFA
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  // MARK: - Emoji
  /// https://docs.discord.food/resources/emoji

  /// Returns an object containing information on the guild or application that owns the given emoji.
  /// https://docs.discord.food/resources/emoji#get-emoji-source
  @inlinable
  public func getEmojiSource(emojiID: EmojiSnowflake) async throws
    -> DiscordClientResponse<EmojiSource>
  {
    let endpoint = UserAPIEndpoint.getEmojiSource(emojiId: emojiID)
    return try await self.send(request: .init(to: endpoint))
  }

  // MARK: - Applications
  /// https://docs.discord.food/resources/application

  /// Returns a list of application objects that the current user has.
  /// https://docs.discord.food/resources/application#get-applications
  @inlinable
  public func getApplications(withTeamApplications: Bool = false) async throws
    -> DiscordClientResponse<[PartialApplication]>
  {
    let endpoint = UserAPIEndpoint.getApplications(
      withTeamApplications: withTeamApplications
    )
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns a list of application objects that the current user has, additionally including the application's assets.
  /// https://docs.discord.food/resources/application#get-applications-with-assets
  @inlinable
  public func getApplicationsWithAssets(withTeamApplications: Bool = false)
    async throws -> DiscordClientResponse<
      [PartialApplication]
    >
  {
    let endpoint = UserAPIEndpoint.getApplicationsWithAssets(
      withTeamApplications: withTeamApplications
    )
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns the embedded activities available globally or in a particular guild.
  /// https://docs.discord.food/resources/application#get-embedded-activities
  @inlinable
  public func getEmbeddedActivities(guildID: GuildSnowflake) async throws
    -> DiscordClientResponse<EmbeddedActivities>
  {
    let endpoint = UserAPIEndpoint.getEmbeddedActivities(guildId: guildID)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns a list of partial application objects for the given IDs.
  /// https://docs.discord.food/resources/application#get-partial-applications
  @inlinable
  public func getPartialApplications(applicationIDs: [ApplicationSnowflake])
    async throws -> DiscordClientResponse<[PartialApplication]>
  {
    let endpoint = UserAPIEndpoint.getPartialApplications(ids: applicationIDs)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns a partial application object for the given ID with all public application fields.
  /// https://docs.discord.food/resources/application#get-partial-application
  @inlinable
  public func getPartialApplication(
    applicationID: ApplicationSnowflake,
    withGuild: Bool = false
  ) async throws -> DiscordClientResponse<PartialApplication> {
    let endpoint = UserAPIEndpoint.getPartialApplication(
      id: applicationID,
      withGuild: withGuild
    )
    return try await self.send(request: .init(to: endpoint))
  }

  /// Messages that mentioned the current user, newest first.
  /// https://docs.discord.food/resources/message#get-recent-mentions
  @inlinable
  public func getRecentMentions(
    before: MessageSnowflake? = nil,
    limit: Int = 25,
    includeRoles: Bool = true,
    includeEveryone: Bool = true,
    guildID: GuildSnowflake? = nil
  ) async throws -> DiscordClientResponse<[DiscordChannel.Message]> {
    let endpoint = UserAPIEndpoint.getRecentMentions
    return try await self.send(
      request: .init(
        to: endpoint,
        queries: [
          ("before", before?.rawValue),
          ("limit", String(limit)),
          ("roles", String(includeRoles)),
          ("everyone", String(includeEveryone)),
          ("guild_id", guildID?.rawValue),
        ]
      )
    )
  }

  /// Searches messages in a guild. A 202 response means the guild is still being indexed.
  /// https://docs.discord.food/resources/message#search-guild-messages
  @inlinable
  public func searchGuildMessages(
    guildID: GuildSnowflake,
    query: MessageSearchQuery
  ) async throws -> DiscordClientResponse<MessageSearchResults> {
    let endpoint = UserAPIEndpoint.searchGuildMessages(guildId: guildID)
    return try await self.send(request: .init(to: endpoint, queries: query.queries))
  }

  /// Searches messages in a DM, group DM or guild channel.
  /// https://docs.discord.food/resources/message#search-channel-messages
  @inlinable
  public func searchChannelMessages(
    channelID: ChannelSnowflake,
    query: MessageSearchQuery
  ) async throws -> DiscordClientResponse<MessageSearchResults> {
    let endpoint = UserAPIEndpoint.searchChannelMessages(channelId: channelID)
    return try await self.send(request: .init(to: endpoint, queries: query.queries))
  }

  /// Lists a forum or media channel's posts. Answers 202 while the index is being built.
  /// https://docs.discord.food/resources/channel#search-threads
  public func searchForumThreads(
    channelID: ChannelSnowflake,
    query: ThreadSearchQuery
  ) async throws -> DiscordClientResponse<ThreadSearchResults> {
    let endpoint = UserAPIEndpoint.searchForumThreads(channelId: channelID)
    return try await self.send(request: .init(to: endpoint, queries: query.queries))
  }

  /// Returns the public RPC details of an application (name, icon). Needs no authorization,
  /// so it doubles as a check that an application ID exists.
  /// https://docs.discord.food/resources/application#get-application-rpc
  @inlinable
  public func getApplicationRPC(
    applicationID: ApplicationSnowflake
  ) async throws -> DiscordClientResponse<PartialApplication> {
    let endpoint = UserAPIEndpoint.getApplicationRPC(id: applicationID)
    return try await self.send(request: .init(to: endpoint))
  }

  // /// Returns a list of detectable application objects representing games that can be detected by Discord for rich presence.
  // /// https://docs.discord.food/resources/application#get-detectable-applications
  //  @inlinable
  //  func getDetectableApplications() async throws -> DiscordClientResponse<[PartialApplication]> {
  //    let endpoint = UserAPIEndpoint.getDetectableApplications
  //    return try await self.send(request: .init(to: endpoint))
  //  }

  // MARK: - Auto Moderation

  /// Validates a potential rule request's schema for the guild. Requires the MANAGE_GUILD permission.
  /// https://docs.discord.food/resources/auto-moderation#validate-guild-automod-rule
  @inlinable
  public func validateAutoModRule(
    guildID: GuildSnowflake,
    payload: Payloads.AutoModTriggerMetadata
  ) async throws -> DiscordClientResponse<Payloads.AutoModTriggerMetadata> {
    let endpoint = UserAPIEndpoint.validateAutoModRule(guildId: guildID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Executes an alert action on an AutoMod alert. Requires the `MANAGE_GUILD` permission. Returns a 204 empty response on success. Fires a Message Update Gateway event.
  /// https://docs.discord.food/resources/auto-moderation#execute-automod-alert-action
  @inlinable
  public func executeAutoModAlertAction(
    guildID: GuildSnowflake,
    payload: Payloads.ExecuteAutoModAlertAction
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.executeAutoModAlertAction(guildId: guildID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  // MARK: - Channels

  /// Checks if the current user is eligible to ring a call in the DM channel.
  /// https://docs.discord.food/resources/channel#get-call-eligibility
  @inlinable
  public func getCallEligibility(channelID: ChannelSnowflake) async throws
    -> DiscordClientResponse<CallEligibility>
  {
    let endpoint = UserAPIEndpoint.getCallEligibility(channelId: channelID)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Modifies the active call in the private channel. Returns a 204 empty response on success. Fires a Call Update Gateway event.
  /// https://docs.discord.food/resources/channel#modify-call
  @inlinable
  public func modifyCall(channelID: ChannelSnowflake, payload: Payloads.ModifyCall)
    async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.modifyCall(channelId: channelID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Rings the recipients of a private channel to notify them of an active call. Returns a 204 empty response on success. Fires a Call Update Gateway event.
  /// https://docs.discord.food/resources/channel#ring-channel-recipients
  @inlinable
  public func ringChannelRecipients(channelID: ChannelSnowflake, payload: Payloads.RingChannelRecipients) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.ringChannelRecipients(channelId: channelID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Stops ringing the recipients of a private channel. Returns a 204 empty response on success. Fires a Call Update Gateway event.
  /// https://docs.discord.food/resources/channel#stop-ringing-channel-recipients
  @inlinable
  public func stopRingingChannelRecipients(channelID: ChannelSnowflake, payload: Payloads.RingChannelRecipients) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.stopRingingChannelRecipients(channelId: channelID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  // MARK: - Emoji

  /// Returns the most-used emojis for the given guild.
  /// https://docs.discord.food/resources/emoji#get-guild-top-emojis
  @inlinable
  public func getGuildTopEmojis(guildID: GuildSnowflake) async throws
    -> DiscordClientResponse<[Guild.TopEmoji]>
  {
    let endpoint = UserAPIEndpoint.getGuildTopEmojis(guildId: guildID)
    return try await self.send(request: .init(to: endpoint))
  }

  // MARK: - Invites

  /// Accepts an invite to a guild, group DM, or DM. Returns an invite object on success. May fire a Guild Create, Guild Member Add, Guild Join Request Create, Channel Create, and/or Relationship Add Gateway event.
  /// https://docs.discord.food/resources/invite#accept-invite
  @inlinable
  public func acceptInvite(code: String, payload: Payloads.AcceptInvite)
    async throws -> DiscordClientResponse<Invite>
  {
    let endpoint = UserAPIEndpoint.acceptInvite(code: code)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Returns a list of friend invite objects (with invite metadata) for the current user.
  /// https://docs.discord.food/resources/invite#get-user-invites
  @inlinable
  public func getUserInvites() async throws -> DiscordClientResponse<
    [InviteWithMetadata]
  > {
    let endpoint = UserAPIEndpoint.getUserInvites
    return try await self.send(request: .init(to: endpoint))
  }

  /// Creates a new friend invite. Returns a friend invite object (with invite metadata) on success.
  /// https://docs.discord.food/resources/invite#create-user-invite
  @inlinable
  public func createUserInvite(payload: Payloads.CreateUserInvite) async throws
    -> DiscordClientResponse<InviteWithMetadata>
  {
    let endpoint = UserAPIEndpoint.createUserInvite
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Revokes all of the current user's friend invites. Returns a list of revoked friend invite objects (with invite metadata) on success.
  /// https://docs.discord.food/resources/invite#revoke-user-invites
  @inlinable
  public func revokeUserInvites() async throws -> DiscordClientResponse<
    [InviteWithMetadata]
  > {
    let endpoint = UserAPIEndpoint.revokeUserInvites
    return try await self.send(request: .init(to: endpoint))
  }

  // MARK: - Relationships

  /// Returns a list of relationship objects for the current user.
  /// https://docs.discord.food/resources/relationships#get-relationships
  @inlinable
  public func getRelationships() async throws -> DiscordClientResponse<
    [DiscordRelationship]
  > {
    let endpoint = UserAPIEndpoint.getRelationships
    return try await self.send(request: .init(to: endpoint))
  }

  /// Sends a friend request to another user, which can be accepted by creating a new relationship of type FRIEND. Returns a 204 empty response on success. Fires a Relationship Add Gateway event.
  /// https://docs.discord.food/resources/relationships#send-friend-request
  @inlinable
  public func sendFriendRequest(payload: Payloads.SendFriendRequest)
    async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.sendFriendRequest
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Creates a relationship with another user. Returns a 204 empty response on success. Fires a Relationship Add Gateway event.
  /// https://docs.discord.food/resources/relationships#create-relationship
  @inlinable
  public func createRelationship(
    userID: UserSnowflake,
    payload: Payloads.CreateRelationship
  )
    async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.createRelationship(userId: userID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Ignores a user. Returns a 204 empty response on success. Fires a Relationship Add or Relationship Update Gateway event.
  /// https://docs.discord.food/resources/relationships#ignore-user
  @inlinable
  public func ignoreUser(userID: UserSnowflake) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.ignoreUser(userId: userID)
    return try await self.send(
      request: .init(to: endpoint)
    )
  }

  /// Unignores a user. Returns a 204 empty response on success. Fires a Relationship Update or Relationship Remove Gateway event.
  /// https://docs.discord.food/resources/relationships#unignore-user
  @inlinable
  public func unignoreUser(userID: UserSnowflake) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.unignoreUser(userId: userID)
    return try await self.send(
      request: .init(to: endpoint)
    )
  }

  /// Modifies a relationship to another user. Returns a 204 empty response on success. Fires a Relationship Update Gateway event.
  /// https://docs.discord.food/resources/relationships#modify-relationship
  @inlinable
  public func modifyRelationship(
    userID: UserSnowflake,
    payload: Payloads.ModifyRelationship
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.modifyRelationship(userId: userID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Removes a relationship with another user. Returns a 204 empty response on success. Fires a Relationship Remove Gateway event.
  /// https://docs.discord.food/resources/relationships#remove-relationship
  @inlinable
  public func removeRelationship(userID: UserSnowflake) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.removeRelationship(userId: userID)
    return try await self.send(
      request: .init(to: endpoint)
    )
  }

  /// Removes multiple relationships. Returns a 204 empty response on success. May fire multiple Relationship Remove Gateway events.
  /// https://docs.discord.food/resources/relationships#bulk-remove-relationships
  @inlinable
  public func bulkRemoveRelationships(
    relationshipType: DiscordRelationship.Kind = .incomingRequest,
    payload: Payloads.BulkRemoveRelationships
  ) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.bulkRemoveRelationships(
      type: relationshipType
    )
    return try await self.send(
      request: .init(to: endpoint)
    )
  }

  /// Adds multiple relationships from contact sync. May fire multiple Relationship Add Gateway events.
  /// https://docs.discord.food/resources/relationships#bulk-add-relationships
  @inlinable
  public func bulkAddRelationships(payload: Payloads.BulkAddRelationships)
    async throws -> DiscordClientResponse<BulkAddRelationshipsResult>
  {
    let endpoint = UserAPIEndpoint.bulkAddRelationships
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  /// Returns a list of friend suggestion objects for the current user.
  /// https://docs.discord.food/resources/relationships#get-friend-suggestions
  @inlinable
  public func getFriendSuggestions() async throws -> DiscordClientResponse<
    FriendSuggestions
  > {
    let endpoint = UserAPIEndpoint.getFriendSuggestions
    return try await self.send(request: .init(to: endpoint))
  }

  /// Removes a friend suggestion for the current user. Returns a 204 empty response on success. Fires a Friend Suggestion Delete Gateway event.
  /// https://docs.discord.food/resources/relationships#remove-friend-suggestion
  @inlinable
  public func removeFriendSuggestion(userID: UserSnowflake) async throws
    -> DiscordHTTPResponse
  {
    let endpoint = UserAPIEndpoint.removeFriendSuggestion(userId: userID)
    return try await self.send(
      request: .init(to: endpoint)
    )
  }

  /// Returns a list of soundboard sound objects that can be used by all users.
  /// https://docs.discord.food/resources/soundboard#get-default-soundboard-sounds
  @inlinable
  public func getDefaultSoundboardSounds() async throws
    -> DiscordClientResponse<
      Gateway.SoundboardSounds
    >
  {
    let endpoint = UserAPIEndpoint.getDefaultSoundboardSounds
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns an object containing a list of soundboard sound objects for the given guild. Includes the user field if the user has the `CREATE_EXPRESSIONS` or `MANAGE_EXPRESSIONS` permission.
  /// https://docs.discord.food/resources/soundboard#get-guild-soundboard-sounds
  @inlinable
  public func getGuildSoundboardSounds(guildID: GuildSnowflake) async throws
    -> DiscordClientResponse<
      Gateway.SoundboardSounds
    >
  {
    let endpoint = UserAPIEndpoint.getGuildSoundboardSounds(guildId: guildID)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns a soundboard sound object for the given guild and sound ID. Includes the user field if the user has the `CREATE_EXPRESSIONS` or `MANAGE_EXPRESSIONS` permission.
  /// https://docs.discord.food/resources/soundboard#get-guild-soundboard-sound
  @inlinable
  public func getGuildSoundboardSound(
    guildID: GuildSnowflake,
    soundID: SoundSnowflake
  ) async throws -> DiscordClientResponse<
    SoundboardSound
  > {
    let endpoint = UserAPIEndpoint.getGuildSoundboardSound(
      guildId: guildID,
      soundId: soundID
    )
    return try await self.send(request: .init(to: endpoint))
  }

  //  /// Creates a new soundboard sound for the guild. Requires the `CREATE_EXPRESSIONS` permission. Returns the new soundboard sound object on success. Fires a Guild Soundboard Sound Create Gateway event.
  //  /// https://docs.discord.food/resources/soundboard#create-guild-soundboard-sound
  //  @inlinable
  //  public func createGuildSoundboardSound(

  //  /// Modifies the given soundboard sound. For sounds created by the current user, requires either the `CREATE_EXPRESSIONS` or `MANAGE_EXPRESSIONS` permission. For other sounds, requires the `MANAGE_EXPRESSIONS` permission. Returns the updated soundboard sound object on success. Fires a Guild Soundboard Sound Update Gateway event.
  //  /// https://docs.discord.food/resources/soundboard#modify-guild-soundboard-sound
  //  @inlinable
  //  public func modifyGuildSoundboardSound(

  /// For sounds created by the current user, requires either the `CREATE_EXPRESSIONS` or `MANAGE_EXPRESSIONS` permission. For other sounds, requires the `MANAGE_EXPRESSIONS` permission. Returns a 204 empty response on success. Fires a Guild Soundboard Sound Delete Gateway event.
  /// https://docs.discord.food/resources/soundboard#delete-guild-soundboard-sound
  @inlinable
  public func deleteGuildSoundboardSound(
    guildID: GuildSnowflake,
    soundID: SoundSnowflake
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.deleteGuildSoundboardSound(
      guildId: guildID,
      soundId: soundID
    )
    return try await self.send(
      request: .init(to: endpoint)
    )
  }

  //  /// Returns a discoverable guild object for the guild that owns the given sound. This endpoint requires the guild to be discoverable, not be auto-removed, and have guild expression discoverability enabled.
  //  /// https://docs.discord.food/resources/soundboard#get-soundboard-sound-guild
  //  @inlinable
  //  public func getSoundboardSoundGuild(
  //    soundID: SoundSnowflake
  //  ) async throws -> DiscordClientResponse<

  /// Sends a soundboard sound to a voice channel. Returns a 204 empty response on success. Fires a Voice Channel Effect Send Gateway event.
  /// NOTE: Sending a soundboard sound requires the current user to be connected to the voice channel. The user cannot be server muted, deafened, or suppressed.
  /// https://docs.discord.food/resources/soundboard#send-soundboard-sound
  @inlinable
  public func sendSoundboardSound(
    channelID: ChannelSnowflake,
    payload: Payloads.SendSoundboardSound
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.sendSoundboardSound(channelId: channelID)
    return try await self.send(
      request: .init(to: endpoint),
      payload: payload
    )
  }

  // MARK: - Stickers

  /// Returns the list of sticker packs available to use.
  /// https://docs.discord.food/resources/sticker#get-sticker-packs
  @inlinable
  public func getStickerPacks() async throws -> DiscordClientResponse<
    Responses.ListStickerPacks
  > {
    let endpoint = UserAPIEndpoint.getStickerPacks
    return try await self.send(request: .init(to: endpoint))
  }

  /// Returns a sticker pack object for the given pack ID.
  /// https://docs.discord.food/resources/sticker#get-sticker-pack
  @inlinable
  public func getStickerPack(packID: StickerPackSnowflake) async throws
    -> DiscordClientResponse<StickerPack>
  {
    let endpoint = UserAPIEndpoint.getStickerPack(stickerPackId: packID)
    return try await self.send(request: .init(to: endpoint))
  }

  //  /// Returns a discoverable guild object for the guild that owns the given sticker. This endpoint requires the guild to be discoverable, not be auto-removed, and have guild expression discoverability enabled.
  //  /// https://docs.discord.food/resources/sticker#get-sticker-guild
  //  @inlinable
  //  public func getStickerGuild(
  //    stickerID: StickerSnowflake
  //  ) async throws -> DiscordClientResponse<

  // MARK: - Users

  /// Returns a user profile object for a given user ID.
  /// Warning: This endpoint requires one of the following:
  /// - The user is a bot
  /// - The user shares a mutual guild with the current user
  /// - The user is a friend of the current user
  /// - The user is a friend suggestion of the current user
  /// - The user has an outgoing friend request to the current user
  /// - A valid join_request_id is provided
  /// https://docs.discord.food/resources/user#get-user-profile
  @inlinable
  public func getUserProfile(
    userID: UserSnowflake,
    withMutualGuilds: Bool,
    withMutualFriends: Bool,
    withMutualFriendsCount: Bool,
    guildID: GuildSnowflake? = nil
      //    , joinRequestID: AnySnowflake? = nil
  ) async throws -> DiscordClientResponse<DiscordUser.Profile> {
    let endpoint = UserAPIEndpoint.getUserProfile(
      userId: userID,
      withMutualGuilds: withMutualGuilds,
      withMutualFriends: withMutualFriends,
      withMutualFriendsCount: withMutualFriendsCount,
      guildId: guildID
    )
    return try await self.send(request: .init(to: endpoint))
  }

  @inlinable
  public func getUserSettingsProto(
    type: Gateway.UserSettingsProto.Kind
  ) async throws -> DiscordClientResponse<UserSettingsProtoResponse> {
    let endpoint = UserAPIEndpoint.getUserSettingsProto(type: type)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Modifies the requester's user settings protobuf for the specified type. Fires a User Settings Proto Update and User Settings Update Gateway event.
  /// https://docs.discord.food/resources/user-settings-proto#modify-user-settings-proto
  /// - Parameters:
  ///   - type: The type of user settings proto being modified.
  ///   - payload: The new user settings proto data for the specified type.
  /// - Returns: The updated user settings proto for the specified type, and whether or not it was discarded.
  @inlinable
  public func modifyUserSettingsProto(
    type: Gateway.UserSettingsProto.Kind,
    payload: Payloads.ModifyUserSettingsProto
  ) async throws -> DiscordClientResponse<UserSettingsProtoResponse> {
    let endpoint = UserAPIEndpoint.modifyUserSettingsProto(type: type)
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Which data uses the user agreed to.
  /// https://docs.discord.food/resources/user-settings#get-user-consents
  @inlinable
  public func getUserConsents() async throws -> DiscordClientResponse<DiscordUserConsents> {
    let endpoint = UserAPIEndpoint.getUserConsents
    return try await self.send(request: .init(to: endpoint))
  }

  /// Grants or revokes consents; returns the new state.
  /// https://docs.discord.food/resources/user-settings#modify-user-consents
  @inlinable
  public func modifyUserConsents(
    payload: Payloads.ModifyUserConsents
  ) async throws -> DiscordClientResponse<DiscordUserConsents> {
    let endpoint = UserAPIEndpoint.modifyUserConsents
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// The latest data request, or a 204 with no body if there is none.
  /// https://docs.discord.food/resources/user#get-user-harvest
  @inlinable
  public func getUserHarvest() async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.getUserHarvest
    return try await self.send(request: .init(to: endpoint))
  }

  /// Asks Discord to email the user a copy of their data.
  /// https://docs.discord.food/resources/user#create-user-harvest
  @inlinable
  public func createUserHarvest(
    payload: Payloads.CreateUserHarvest = .init()
  ) async throws -> DiscordClientResponse<DiscordUserHarvest> {
    let endpoint = UserAPIEndpoint.createUserHarvest
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Applications the user has authorised, the latest authorisation of each.
  /// https://docs.discord.food/topics/oauth2#get-oauth2-authorizations
  @inlinable
  public func listOAuth2Tokens() async throws -> DiscordClientResponse<[OAuth2Authorization]> {
    let endpoint = UserAPIEndpoint.listOAuth2Tokens
    return try await self.send(request: .init(to: endpoint))
  }

  /// Revokes an authorisation, so the application loses access to the account.
  /// https://docs.discord.food/topics/oauth2#delete-oauth2-authorization
  @inlinable
  public func revokeOAuth2Token(id: OAuth2TokenSnowflake) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.revokeOAuth2Token(tokenId: id)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Changes how a connected account shows, e.g. on the profile or as activity.
  /// https://docs.discord.food/resources/connected-accounts#modify-user-connection
  @inlinable
  public func modifyOwnConnection(
    type: DiscordUser.Connection.Service,
    id: String,
    payload: Payloads.ModifyConnection
  ) async throws -> DiscordClientResponse<DiscordUser.Connection> {
    let endpoint = UserAPIEndpoint.modifyOwnConnection(type: type, id: id)
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Removes a connected account. Returns a 204 empty response on success.
  /// https://docs.discord.food/resources/connected-accounts#delete-user-connection
  @inlinable
  public func deleteOwnConnection(
    type: DiscordUser.Connection.Service,
    id: String
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.deleteOwnConnection(type: type, id: id)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Changes how a server (or, with `guildId: nil`, direct messages) notifies
  /// you. Only the fields that are set change; channel overrides merge by channel.
  /// https://docs.discord.food/resources/user-settings#modify-user-guild-settings
  @inlinable
  public func modifyUserGuildSettings(
    guildId: GuildSnowflake?,
    payload: Payloads.ModifyUserGuildSettings
  ) async throws -> DiscordClientResponse<Guild.UserGuildSettings> {
    let endpoint = UserAPIEndpoint.modifyUserGuildSettings(guildId: guildId)
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Marks many channels read at once, up to 100 per call.
  /// https://docs.discord.food/topics/read-state#bulk-acknowledge
  @inlinable
  public func bulkAckReadStates(
    payload: Payloads.BulkAckReadStates
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.bulkAckReadStates
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Sets the current user's answers in a poll; an empty list takes the vote back.
  /// Fires Message Poll Vote Add/Remove Gateway events.
  /// https://docs.discord.food/resources/message#create-poll-vote
  @inlinable
  public func createPollVote(
    channelId: ChannelSnowflake,
    messageId: MessageSnowflake,
    answerIds: [Int]
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.createPollVote(channelId: channelId, messageId: messageId)
    return try await self.send(
      request: .init(to: endpoint),
      payload: Payloads.CreatePollVote(answer_ids: answerIds.map(String.init))
    )
  }

  /// Accepts a message request; it moves out of Requests (or Spam) into your DMs.
  /// Fires a Channel Update Gateway event.
  /// https://docs.discord.food/resources/channel#update-message-request
  @inlinable
  public func acceptMessageRequest(
    channelId: ChannelSnowflake
  ) async throws -> DiscordClientResponse<DiscordChannel> {
    let endpoint = UserAPIEndpoint.updateMessageRequest(channelId: channelId)
    return try await self.send(
      request: .init(to: endpoint),
      payload: Payloads.UpdateMessageRequest(consent_status: .accepted)
    )
  }

  /// Rejects and deletes a pending message request. Fires Channel Update, Message Ack
  /// and Channel Delete Gateway events.
  /// https://docs.discord.food/resources/channel#reject-message-request
  @inlinable
  public func rejectMessageRequest(
    channelId: ChannelSnowflake
  ) async throws -> DiscordClientResponse<DiscordChannel> {
    let endpoint = UserAPIEndpoint.rejectMessageRequest(channelId: channelId)
    return try await self.send(request: .init(to: endpoint))
  }

  /// Rejects up to 50 message requests at once.
  /// https://docs.discord.food/resources/channel#batch-reject-message-requests
  @inlinable
  public func batchRejectMessageRequests(
    payload: Payloads.BatchRejectMessageRequests
  ) async throws -> DiscordClientResponse<[DiscordChannel]> {
    let endpoint = UserAPIEndpoint.batchRejectMessageRequests
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// The message that started each request, 1 to 25 channels per call.
  /// https://docs.discord.food/resources/channel#get-supplemental-message-request-data
  @inlinable
  public func getMessageRequestSupplementalData(
    channelIds: [ChannelSnowflake]
  ) async throws -> DiscordClientResponse<[SupplementalMessageRequest]> {
    let endpoint = UserAPIEndpoint.getMessageRequestSupplementalData
    return try await self.send(
      request: .init(
        to: endpoint,
        queries: channelIds.prefix(25).map { ("channel_ids", $0.rawValue) }
      )
    )
  }

  /// Proxies external image URLs through Discord's media proxy so they can be used as rich presence assets.
  /// Each result's `external_asset_path` is used as `mp:<path>` in the activity assets.
  /// https://docs.discord.food/resources/application#create-application-external-assets
  @inlinable
  public func createApplicationExternalAssets(
    applicationID: ApplicationSnowflake,
    payload: Payloads.CreateApplicationExternalAssets
  ) async throws -> DiscordClientResponse<[ApplicationExternalAsset]> {
    let endpoint = UserAPIEndpoint.createApplicationExternalAssets(
      applicationId: applicationID
    )
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Creates attachment URLs to upload the intended attachments directly to Discord's GCP storage bucket.
  /// https://docs.discord.food/resources/message#create-attachments
  @inlinable
  public func createAttachments(
    channelID: ChannelSnowflake,
    payload: Payloads.CreateAttachments
  ) async throws -> DiscordClientResponse<Gateway.CreateAttachments> {
    let endpoint = UserAPIEndpoint.createAttachments(channelId: channelID)
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Deletes an attachment from Discord's GCP storage bucket.
  /// https://docs.discord.food/resources/message#delete-attachment
  @inlinable
  public func deleteAttachment(
    uploadFilename: String,
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.deleteAttachment(
      uploadFilename: uploadFilename
    )
    return try await self.send(request: .init(to: endpoint))
  }

  /// Creates a new remote auth session. This sends the current user info to the desktop client.
  /// https://docs.discord.food/remote-authentication/mobile#create-remote-auth-session
  @inlinable
  public func createRemoteAuthSession(payload: Payloads.CreateRemoteAuthSession)
    async throws -> DiscordClientResponse<Gateway.CreateRemoteAuthSession>
  {
    let endpoint = UserAPIEndpoint.createRemoteAuthSession
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Finishes a remote auth session. This ends the remote auth session by sending an authentication token to the desktop client.
  /// https://docs.discord.food/remote-authentication/mobile#finish-remote-auth
  @inlinable
  public func finishRemoteAuthSession(
    payload: Payloads.RemoteAuthSession
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.finishRemoteAuthSession
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Cancels a remote auth session. This ends the remote auth session without sending an authentication token.
  /// https://docs.discord.food/remote-authentication/mobile#cancel-remote-auth
  @inlinable
  public func cancelRemoteAuthSession(
    payload: Payloads.RemoteAuthSession
  ) async throws -> DiscordHTTPResponse {
    let endpoint = UserAPIEndpoint.cancelRemoteAuthSession
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }

  /// Exchange a remote auth ticket for an encrypted authentication token.
  /// https://docs.discord.food/remote-authentication/mobile#cancel-remote-auth
  @inlinable
  public func exchangeRemoteAuthTicket(
    payload: Payloads.ExchangeRemoteAuthTicket
  ) async throws -> DiscordClientResponse<Gateway.ExchangeRemoteAuthTicket> {
    let endpoint = UserAPIEndpoint.exchangeRemoteAuthTicket
    return try await self.send(request: .init(to: endpoint), payload: payload)
  }
}
