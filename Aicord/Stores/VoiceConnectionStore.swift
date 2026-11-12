//
//  VoiceConnectionStore.swift
//  Aicord
//
//  The one voice call this device is in: joining through the main gateway,
//  the voice connection, audio, mute, deafen and push-to-talk, and the
//  video of others: cameras over the call's connection, a Go Live over a
//  second one.
//
//  Ported from the `voice` branch of llsc12/Paicord. Join behaviour follows
//  Serein: a lost main gateway session or a voice session that cannot be
//  resumed ends the call; joining again is an explicit action.
//

import AVFoundation
import Foundation
import AicordKit
import os

@MainActor
@Observable
final class VoiceConnectionStore: DiscordDataStore {
  enum Phase: Equatable {
    case idle
    /// Voice state sent, waiting for the voice server.
    case joining
    case connecting
    /// Connected; waiting for the end-to-end encrypted group.
    case encrypting
    case connected
    case reconnecting
    case failed(String)

    var isActive: Bool {
      switch self {
      case .idle, .failed: false
      default: true
      }
    }
  }

  struct Call: Equatable {
    var channelID: ChannelSnowflake
    /// `nil` for DM and group calls.
    var guildID: GuildSnowflake?
    /// A Stage: you join in the audience and speak only once let on stage.
    var isStage = false
    var startedAt = Date()
  }

  /// Video somebody in the call is sending.
  struct VideoSource: Hashable, Identifiable {
    enum Kind: Hashable {
      case camera
      /// A Go Live: a screen or a window.
      case stream
    }
    var userID: UserSnowflake
    var kind: Kind
    var id: Self { self }
  }

  enum StreamPhase: Equatable {
    case connecting
    case watching
    /// Discord's reason (`stream_ended`, `stream_full`, …) or ours.
    case ended(String)
  }

  /// How long Discord gets to hand out a voice server.
  static let joinTimeout: Duration = .seconds(30)

  var gateway: GatewayStore?
  @ObservationIgnored var eventTask: Task<Void, Never>?

  private(set) var call: Call?
  private(set) var phase: Phase = .idle
  private(set) var isMuted = UserDefaults.standard.bool(forKey: VoicePreferences.mutedKey)
  private(set) var isDeafened = UserDefaults.standard.bool(forKey: VoicePreferences.deafenedKey)
  /// Push-to-talk key or button currently held.
  private(set) var isPushToTalkHeld = false
  private(set) var speaking: Set<UserSnowflake> = []
  /// Everyone else the voice server says is in the call.
  private(set) var participants: Set<UserSnowflake> = []
  /// 0 when the call is not end-to-end encrypted.
  private(set) var daveProtocolVersion: UInt16 = 0
  private(set) var microphoneDenied = false
  /// Last microphone level in dBFS (for Settings and the call bar).
  private(set) var inputLevel: Float = -100
  /// Our own voice state in the call, as Discord last sent it.
  private(set) var ownState: VoiceState?
  /// Discord turned down the last Stage action (raise hand, go on stage).
  private(set) var stageError: String?

  /// The Go Lives being watched, by owner.
  private(set) var streamPhases: [UserSnowflake: StreamPhase] = [:]
  /// Who is in each DM or group call, as far as Discord told us; server
  /// voice states are in their `GuildStore`.
  private(set) var callVoiceStates: [ChannelSnowflake: [UserSnowflake: VoiceState]] = [:]

  /// One watched Go Live: what Discord sent for it and its connection.
  private struct StreamWatch {
    var info: Gateway.GoLiveStream?
    var server: Gateway.StreamServerUpdate?
    var manager: VoiceGatewayManager?
    var tasks: [Task<Void, Never>] = []
  }

  @ObservationIgnored private var feeds: [VideoSource: VideoFeed] = [:]
  @ObservationIgnored private var watchedCameras: Set<UserSnowflake> = []
  @ObservationIgnored private var videoTask: Task<Void, Never>?
  @ObservationIgnored private var streams: [UserSnowflake: StreamWatch] = [:]

  @ObservationIgnored private var manager: VoiceGatewayManager?
  @ObservationIgnored private var managerTask: Task<Void, Never>?
  @ObservationIgnored private var joinTimeoutTask: Task<Void, Never>?
  @ObservationIgnored private var pushToTalkReleaseTask: Task<Void, Never>?
  @ObservationIgnored private let audio = VoiceAudioEngine()
  @ObservationIgnored private var pendingSessionID: String?
  @ObservationIgnored private var pendingServer: Gateway.VoiceServerUpdate?
  @ObservationIgnored private var ringsWhenConnected = false
  @ObservationIgnored private var managerState: VoiceGatewayManager.State = .idle
  @ObservationIgnored private let logger = Logger(subsystem: "net.smigi.aicord", category: "Voice")

  init() {
    VoicePreferences.register()
    audio.onInputLevel = { [weak self] level, _ in
      Task { @MainActor in self?.inputLevel = level }
    }
  }

  // MARK: Gateway events

  func setupEventHandling() {
    guard let gateway = gateway?.gateway else { return }
    eventTask = Task { @MainActor [weak self] in
      for await event in gateway.events {
        guard let self else { return }
        switch event.data {
        case .ready:
          // A new main gateway session invalidates the voice session.
          if self.call != nil {
            self.logger.info("Main gateway reconnected; ending the call")
            self.endLocally(.failed(String(localized: "Connection to Discord was lost.")))
          }
        case .voiceStateUpdate(let state):
          if state.guild_id == nil { self.trackCallState(state) }
          self.handleVoiceState(state)
        case .voiceServerUpdate(let server):
          self.handleVoiceServer(server)
        case .streamCreate(let stream):
          guard let owner = self.watchedOwner(of: stream.stream_key) else { break }
          self.streams[owner]?.info = stream
          self.connectStreamIfReady(owner)
        case .streamServerUpdate(let server):
          guard let owner = self.watchedOwner(of: server.stream_key) else { break }
          self.streams[owner]?.server = server
          // A new server for a stream already being watched.
          self.disconnectStream(owner)
          self.streamPhases[owner] = .connecting
          self.connectStreamIfReady(owner)
        case .streamDelete(let deleted):
          guard let owner = self.watchedOwner(of: deleted.stream_key) else { break }
          self.logger.info("Stream ended: \(deleted.reason ?? "?", privacy: .public)")
          self.endStream(owner, .ended(deleted.reason ?? "stream_ended"))
        case .callCreate(let created):
          self.setCallStates(created.voice_states, in: created.channel_id)
        case .callUpdate(let updated):
          if let states = updated.voice_states {
            self.setCallStates(states, in: updated.channel_id)
          }
        case .callDelete(let deleted):
          self.callVoiceStates[deleted.channel_id] = nil
        default:
          break
        }
      }
    }
  }

  func cancelEventHandling() {
    eventTask?.cancel()
    eventTask = nil
    if call != nil { endLocally(.idle) }
  }

  // MARK: Joining and leaving

  /// Joins a server voice channel, or starts or joins a DM call.
  /// `ring` rings the other DM members once the call is up.
  func join(channelID: ChannelSnowflake, guildID: GuildSnowflake?, ring: Bool = false) {
    if call?.channelID == channelID, phase.isActive { return }
    if call != nil { leave() }
    guard gateway?.gateway != nil else { return }
    logger.info("Joining voice channel \(channelID.rawValue, privacy: .public)")
    if VoicePreferences.listenOnly {
      // Muted for this call only; the saved mute setting is untouched.
      logger.info("Listen-only: the microphone stays closed")
      microphoneDenied = true
      isMuted = true
    }
    let isStage = guildID.flatMap { gateway?.existingGuildStore(for: $0) }?
      .channels[channelID]?.type == .guildStageVoice
    call = Call(channelID: channelID, guildID: guildID, isStage: isStage)
    ownState = nil
    phase = .joining
    ringsWhenConnected = ring && guildID == nil
    pendingSessionID = nil
    pendingServer = nil
    sendVoiceState()

    joinTimeoutTask?.cancel()
    joinTimeoutTask = Task { [weak self] in
      try? await Task.sleep(for: Self.joinTimeout)
      guard let self, !Task.isCancelled, self.phase == .joining else { return }
      self.logger.warning("No voice server within the join timeout")
      self.leave(reason: .failed(String(localized: "Discord didn't assign a voice server.")))
    }

    if VoicePreferences.listenOnly { return }
    Task {
      if AVAudioApplication.shared.recordPermission == .undetermined {
        _ = await AVAudioApplication.requestRecordPermission()
      }
      microphoneDenied = AVAudioApplication.shared.recordPermission == .denied
    }
  }

  /// Leaves the call and tells Discord.
  func leave(reason: Phase = .idle) {
    guard call != nil else { return }
    logger.info("Leaving voice channel")
    endLocally(reason)
    sendVoiceState()
  }

  /// Ends the local connection without telling Discord (it already knows,
  /// or another device took the call over).
  private func endLocally(_ reason: Phase) {
    joinTimeoutTask?.cancel()
    managerTask?.cancel()
    managerTask = nil
    videoTask?.cancel()
    videoTask = nil
    for owner in Array(streams.keys) { endStream(owner, nil) }
    streams = [:]
    streamPhases = [:]
    watchedCameras = []
    feeds = [:]
    let manager = self.manager
    self.manager = nil
    Task { await manager?.disconnect() }
    audio.stop()
    call = nil
    ownState = nil
    stageError = nil
    phase = reason
    speaking = []
    participants = []
    managerState = .idle
    daveProtocolVersion = 0
    pendingSessionID = nil
    pendingServer = nil
    isPushToTalkHeld = false
  }

  private func handleVoiceState(_ state: VoiceState) {
    guard state.user_id == gateway?.user.currentUser?.id, let call else { return }
    let wasSuppressed = isSuppressed
    ownState = state.channel_id == nil ? nil : state
    if wasSuppressed != isSuppressed { applyAudioGates() }
    guard let channelID = state.channel_id else {
      // Disconnected by a moderator, or left from another device.
      if phase != .joining || pendingSessionID != nil {
        logger.info("Our voice state was cleared; ending the call")
        endLocally(.idle)
      }
      return
    }
    if phase == .joining {
      guard channelID == call.channelID else { return }
      pendingSessionID = state.session_id
      connectIfReady()
      return
    }
    if let pendingSessionID, state.session_id != pendingSessionID {
      // The call continues on another device.
      logger.info("Voice session moved to another client")
      endLocally(.idle)
    } else if channelID != call.channelID {
      // Moved by a moderator: Discord sends a new voice server next.
      logger.info("Moved to another voice channel")
      self.call?.channelID = channelID
      self.call?.isStage = call.guildID.flatMap { gateway?.existingGuildStore(for: $0) }?
        .channels[channelID]?.type == .guildStageVoice
      restartForNewServer()
    }
  }

  private func handleVoiceServer(_ server: Gateway.VoiceServerUpdate) {
    guard let call else { return }
    if let guildID = server.guild_id {
      guard guildID == call.guildID else { return }
    } else if let channelID = server.channel_id, channelID != call.channelID {
      return
    }
    guard let endpoint = server.endpoint, !endpoint.isEmpty else {
      // The server is being reallocated; another update follows.
      logger.info("Voice server is being reallocated")
      return
    }
    pendingServer = server
    if phase == .joining {
      connectIfReady()
    } else {
      restartForNewServer()
    }
  }

  private func restartForNewServer() {
    managerTask?.cancel()
    videoTask?.cancel()
    let old = manager
    manager = nil
    Task { await old?.disconnect() }
    audio.stop()
    phase = .joining
    connectIfReady()
  }

  private func connectIfReady() {
    guard let call, let sessionID = pendingSessionID,
      let server = pendingServer, let endpoint = server.endpoint,
      let userID = gateway?.user.currentUser?.id, manager == nil
    else { return }
    joinTimeoutTask?.cancel()
    phase = .connecting

    var allowed: Set<UserSnowflake>?
    if call.guildID == nil,
      let channel = gateway?.user.privateChannels[call.channelID],
      channel.type == .dm
    {
      allowed = Set((channel.recipients ?? []).map(\.id))
    }
    let manager = VoiceGatewayManager(
      connectionData: .init(
        token: server.token,
        guildID: call.guildID,
        channelID: call.channelID,
        userID: userID,
        sessionID: sessionID,
        endpoint: endpoint,
        allowedUserIDs: allowed
      )
    )
    self.manager = manager
    managerTask = Task { [weak self] in
      for await event in manager.events {
        self?.handle(event, from: manager)
      }
    }
    videoTask = Task { [weak self] in
      for await frame in manager.video {
        self?.feeds[.init(userID: frame.userID, kind: .camera)]?.enqueue(frame)
      }
    }
    let cameras = watchedCameras
    Task {
      await manager.setVideoWanted(cameras)
      await manager.connect()
    }

    audio.start(
      capture: !microphoneDenied,
      playback: manager.playback,
      send: { [weak manager] frame in await manager?.sendAudio(frame) }
    )
    applyAudioGates()
    Task { await manager.setReceiving(!isDeafened) }
  }

  private func handle(_ event: VoiceGatewayManager.Event, from source: VoiceGatewayManager) {
    guard source === manager else { return }
    switch event {
    case .stateChanged(let state):
      managerState = state
      switch state {
      case .disconnected(let reason):
        switch reason {
        case .requested:
          break
        case .removed:
          endLocally(.idle)
        case .sessionInvalid(let why), .failed(let why):
          logger.error("Voice connection ended: \(why, privacy: .public)")
          leave(reason: .failed(String(localized: "Voice connection lost.")))
        }
      default:
        updatePhase()
      }
    case .speaking(let user, let isSpeaking):
      if isSpeaking { speaking.insert(user) } else { speaking.remove(user) }
    case .participantJoined(let user):
      participants.insert(user)
      updatePhase()
    case .participantLeft(let user):
      participants.remove(user)
      speaking.remove(user)
      updatePhase()
    case .encryption(let version, _):
      daveProtocolVersion = version
    case .video(let user, let isOn):
      // A camera that comes back starts with a fresh picture.
      if !isOn { feeds[.init(userID: user, kind: .camera)]?.reset() }
    }
  }

  // MARK: Video

  /// Starts receiving a camera or a Go Live and returns where its picture
  /// arrives.
  func watch(_ source: VideoSource) -> VideoFeed {
    let feed = feeds[source] ?? VideoFeed()
    feeds[source] = feed
    let owner = source.userID
    switch source.kind {
    case .camera:
      feed.onNeedsKeyframe = { [weak self] in
        Task { await self?.manager?.refreshVideo(for: owner) }
      }
      if watchedCameras.insert(owner).inserted { sendWantedCameras() }
    case .stream:
      feed.onNeedsKeyframe = { [weak self] in
        Task { await self?.streams[owner]?.manager?.refreshVideo(for: owner) }
      }
      if streams[owner] != nil,
        streamPhases[owner] == .connecting || streamPhases[owner] == .watching
      {
        break
      }
      guard let key = streamKey(of: owner), let gateway = gateway?.gateway else { break }
      endStream(owner, nil)
      streams[owner] = StreamWatch()
      streamPhases[owner] = .connecting
      logger.info("Asking to watch a stream")
      Task { await gateway.watchStream(key: key) }
    }
    return feed
  }

  func stopWatching(_ source: VideoSource) {
    feeds[source] = nil
    switch source.kind {
    case .camera:
      if watchedCameras.remove(source.userID) != nil { sendWantedCameras() }
    case .stream:
      endStream(source.userID, nil)
      streams[source.userID] = nil
    }
  }

  private func streamKey(of owner: UserSnowflake) -> Gateway.StreamKey? {
    call.map { .init(guildID: $0.guildID, channelID: $0.channelID, ownerID: owner) }
  }

  /// The owner of the stream with this key, if we are watching it.
  private func watchedOwner(of key: String) -> UserSnowflake? {
    guard let owner = Gateway.StreamKey(key)?.ownerID, streams[owner] != nil,
      streamKey(of: owner)?.rawValue == key
    else { return nil }
    return owner
  }

  private func sendWantedCameras() {
    let cameras = watchedCameras
    Task { [manager] in await manager?.setVideoWanted(cameras) }
  }

  /// A Go Live has a voice connection of its own, next to the call's, with
  /// the call's session and the IDs and token Discord sent for the stream.
  private func connectStreamIfReady(_ owner: UserSnowflake) {
    guard let watch = streams[owner], watch.manager == nil,
      streamPhases[owner] == .connecting,
      let serverID = watch.info?.rtc_server_id,
      let channelID = watch.info?.rtc_channel_id,
      let server = watch.server, let endpoint = server.endpoint, !endpoint.isEmpty,
      let sessionID = pendingSessionID,
      let userID = gateway?.user.currentUser?.id
    else { return }
    var connection = VoiceGatewayManager.ConnectionData(
      token: server.token,
      guildID: serverID,
      channelID: channelID,
      userID: userID,
      sessionID: sessionID,
      endpoint: endpoint
    )
    connection.isStream = true
    // The stream's encrypted group is numbered one below its server ID.
    connection.daveGroupID = UInt64(serverID.rawValue).map { $0 &- 1 }
    let manager = VoiceGatewayManager(connectionData: connection)
    streams[owner]?.manager = manager
    streams[owner]?.tasks = [
      Task { [weak self] in
        for await event in manager.events {
          guard let self, manager === self.streams[owner]?.manager else { return }
          if case .stateChanged(.disconnected(let reason)) = event, reason != .requested {
            self.logger.error("Stream connection ended: \(reason.description, privacy: .public)")
            self.endStream(owner, .ended("connection_lost"))
          }
        }
      },
      Task { [weak self] in
        for await frame in manager.video {
          guard let self, manager === self.streams[owner]?.manager else { return }
          // Whoever sends on a stream connection is its owner.
          self.feeds[.init(userID: owner, kind: .stream)]?.enqueue(frame)
          if self.streamPhases[owner] == .connecting { self.streamPhases[owner] = .watching }
        }
      },
    ]
    // The stream's sound, next to the call's.
    audio.addPlayback(owner.rawValue, manager.playback)
    let receiving = !isDeafened
    Task {
      await manager.setReceiving(receiving)
      await manager.connect()
    }
  }

  private func disconnectStream(_ owner: UserSnowflake) {
    streams[owner]?.tasks.forEach { $0.cancel() }
    streams[owner]?.tasks = []
    let manager = streams[owner]?.manager
    streams[owner]?.manager = nil
    audio.removePlayback(owner.rawValue)
    Task { await manager?.disconnect() }
  }

  /// `phase` stays on screen as the reason; `nil` when we stopped watching.
  private func endStream(_ owner: UserSnowflake, _ phase: StreamPhase?) {
    disconnectStream(owner)
    feeds[.init(userID: owner, kind: .stream)]?.reset()
    streams[owner]?.info = nil
    streams[owner]?.server = nil
    streamPhases[owner] = phase
  }

  // MARK: DM calls

  /// Everyone in the call of this DM or group DM.
  func callStates(in channelID: ChannelSnowflake) -> [VoiceState] {
    Array((callVoiceStates[channelID] ?? [:]).values)
  }

  private func setCallStates(_ states: [VoiceState]?, in channelID: ChannelSnowflake) {
    callVoiceStates[channelID] = Dictionary(
      (states ?? []).map { ($0.user_id, $0) }, uniquingKeysWith: { _, new in new })
  }

  /// A voice state outside any server: somebody joined, left or changed
  /// their state in a DM call.
  private func trackCallState(_ state: VoiceState) {
    for channelID in Array(callVoiceStates.keys) where channelID != state.channel_id {
      callVoiceStates[channelID]?[state.user_id] = nil
    }
    if let channelID = state.channel_id {
      callVoiceStates[channelID, default: [:]][state.user_id] = state
    }
  }

  /// Alone in the channel the encrypted group cannot form yet, but to the
  /// user the call is up; a DM call rings at that point.
  private func updatePhase() {
    switch managerState {
    case .idle, .connecting, .discovering:
      phase = .connecting
    case .negotiatingEncryption:
      phase = participants.isEmpty ? .connected : .encrypting
    case .connected:
      phase = .connected
    case .resuming:
      phase = .reconnecting
    case .disconnected:
      return
    }
    if phase == .connected, ringsWhenConnected, let call {
      ringsWhenConnected = false
      logger.info("Ringing the DM recipients")
      Task { [gateway] in
        _ = try? await gateway?.client.ringChannelRecipients(
          channelID: call.channelID,
          payload: .init()
        )
      }
    }
  }

  // MARK: Stage

  /// On a Stage in the audience: Discord drops anything we would send.
  /// Until our voice state arrives we count as audience, as we join there.
  var isSuppressed: Bool {
    guard call?.isStage == true else { return false }
    return ownState?.suppress ?? true
  }

  /// In the audience with a raised hand.
  var isHandRaised: Bool {
    isSuppressed && ownState?.request_to_speak_timestamp != nil
  }

  /// A moderator let us on stage; Discord marks it with a request timestamp
  /// on an unsuppressed state until we take it up.
  var isInvitedToSpeak: Bool {
    call?.isStage == true && ownState?.suppress == false
      && ownState?.request_to_speak_timestamp != nil
  }

  /// Raises or lowers our hand.
  func setHandRaised(_ raised: Bool) {
    updateStageState(
      raised
        ? .init(request_to_speak_timestamp: .init(date: .now))
        : .init(clearsRequestToSpeak: true))
  }

  /// Steps on stage: takes up an invitation, or as a moderator just goes up.
  func becomeSpeaker() {
    updateStageState(.init(suppress: false, clearsRequestToSpeak: true))
  }

  /// Goes back to the audience (also declines an invitation).
  func moveToAudience() {
    updateStageState(.init(suppress: true))
  }

  private func updateStageState(_ change: Payloads.ModifyCurrentUserVoiceState) {
    guard let call, call.isStage, let guildID = call.guildID else { return }
    var payload = change
    payload.channel_id = call.channelID
    stageError = nil
    Task { [gateway, logger] in
      do {
        let response = try await gateway?.client.updateSelfVoiceState(
          guildId: guildID, payload: payload)
        try response?.guardSuccess()
      } catch {
        logger.error("Stage voice state change failed: \(error, privacy: .public)")
        self.stageError = String(localized: "Discord didn't allow that on this Stage.")
      }
    }
  }

  // MARK: Mute, deafen, push-to-talk

  func toggleMute() { setMuted(!isMuted) }

  func setMuted(_ muted: Bool) {
    isMuted = muted
    // Undeafening by unmuting, like Discord.
    if !muted, isDeafened { isDeafened = false }
    persistAndApply()
  }

  func toggleDeafen() { setDeafened(!isDeafened) }

  func setDeafened(_ deafened: Bool) {
    isDeafened = deafened
    persistAndApply()
  }

  /// Push-to-talk key or button pressed or released.
  func setPushToTalk(_ held: Bool) {
    pushToTalkReleaseTask?.cancel()
    if held {
      isPushToTalkHeld = true
      applyAudioGates()
    } else {
      // A short release delay keeps word endings.
      pushToTalkReleaseTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(VoicePreferences.pushToTalkRelease))
        guard !Task.isCancelled else { return }
        self?.isPushToTalkHeld = false
        self?.applyAudioGates()
      }
    }
  }

  /// Settings changed while in a call.
  func preferencesChanged() {
    audio.loadPreferences()
    applyAudioGates()
  }

  var usesPushToTalk: Bool { VoicePreferences.inputMode == .pushToTalk }

  private func persistAndApply() {
    UserDefaults.standard.set(isMuted, forKey: VoicePreferences.mutedKey)
    UserDefaults.standard.set(isDeafened, forKey: VoicePreferences.deafenedKey)
    applyAudioGates()
    if call != nil { sendVoiceState() }
    let receiving = !isDeafened
    let streamManagers = streams.values.compactMap(\.manager)
    Task { [manager] in
      await manager?.setReceiving(receiving)
      for stream in streamManagers { await stream.setReceiving(receiving) }
    }
  }

  private func applyAudioGates() {
    let open = !isMuted && !isDeafened && !microphoneDenied && !isSuppressed
      && (!usesPushToTalk || isPushToTalkHeld)
    audio.setTransmitting(open)
    audio.setDeafened(isDeafened)
  }

  /// Opcode 4 on the main gateway: where we are and our mute state.
  private func sendVoiceState() {
    let payload = VoiceStateUpdate(
      guild_id: call?.guildID,
      channel_id: call?.channelID,
      self_mute: isMuted || isDeafened,
      self_deaf: isDeafened,
      self_video: false
    )
    Task { [gateway] in await gateway?.gateway?.updateVoiceState(payload: payload) }
  }
}
