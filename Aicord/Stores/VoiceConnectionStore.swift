//
//  VoiceConnectionStore.swift
//  Aicord
//
//  The one voice call this device is in: joining through the main gateway,
//  the voice connection, audio, mute, deafen and push-to-talk.
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
    var startedAt = Date()
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
          self.handleVoiceState(state)
        case .voiceServerUpdate(let server):
          self.handleVoiceServer(server)
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
    call = Call(channelID: channelID, guildID: guildID)
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
    let manager = self.manager
    self.manager = nil
    Task { await manager?.disconnect() }
    audio.stop()
    call = nil
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
    Task { await manager.connect() }

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
    Task { [manager] in await manager?.setReceiving(receiving) }
  }

  private func applyAudioGates() {
    let open = !isMuted && !isDeafened && !microphoneDenied
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
