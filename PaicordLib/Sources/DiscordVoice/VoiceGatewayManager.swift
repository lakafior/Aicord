//
//  VoiceGatewayManager.swift
//  PaicordLib
//
//  One voice connection: the voice WebSocket (v8), the UDP media flow,
//  transport encryption, DAVE, Opus and the receive mixer.
//
//  Ported from the `voice` branch of llsc12/Paicord (NIO, AsyncHTTPClient
//  and WSClient replaced by URLSessionWebSocketTask and Network.framework).
//  Connection behaviour and limits follow Serein's discord-voice crate.
//

import DiscordCore
import DiscordModels
import Foundation
import Logging

public actor VoiceGatewayManager {
  /// What the main gateway handed us for this connection.
  public struct ConnectionData: Sendable {
    public var token: Secret
    /// `nil` for DM and group calls.
    public var guildID: GuildSnowflake?
    public var channelID: ChannelSnowflake
    public var userID: UserSnowflake
    public var sessionID: String
    public var endpoint: String
    /// One-to-one DMs: the only users DAVE accepts into the group.
    public var allowedUserIDs: Set<UserSnowflake>?

    public init(
      token: Secret,
      guildID: GuildSnowflake?,
      channelID: ChannelSnowflake,
      userID: UserSnowflake,
      sessionID: String,
      endpoint: String,
      allowedUserIDs: Set<UserSnowflake>? = nil
    ) {
      self.token = token
      self.guildID = guildID
      self.channelID = channelID
      self.userID = userID
      self.sessionID = sessionID
      self.endpoint = endpoint
      self.allowedUserIDs = allowedUserIDs
    }

    /// Discord uses the channel ID as the server ID for DM calls.
    var serverID: String { guildID?.rawValue ?? channelID.rawValue }
  }

  public enum State: Sendable, Equatable, CustomStringConvertible {
    case idle
    /// Opening the WebSocket and waiting for Ready.
    case connecting
    /// UDP discovery and Select Protocol.
    case discovering
    /// Waiting for an end-to-end encrypted group (or, alone in the
    /// channel, for someone to join it).
    case negotiatingEncryption
    /// Media flows.
    case connected
    /// The WebSocket dropped and is being resumed; media keeps flowing.
    case resuming
    case disconnected(DisconnectReason)

    public var description: String {
      switch self {
      case .idle: "idle"
      case .connecting: "connecting"
      case .discovering: "discovering"
      case .negotiatingEncryption: "negotiatingEncryption"
      case .connected: "connected"
      case .resuming: "resuming"
      case .disconnected(let reason): "disconnected(\(reason))"
      }
    }
  }

  public enum DisconnectReason: Sendable, Equatable, CustomStringConvertible {
    /// `disconnect()` was called.
    case requested
    /// Removed from the channel, the channel was deleted, or the call ended.
    case removed
    /// The voice session is gone. Joining again starts a new one.
    case sessionInvalid(String)
    case failed(String)

    public var description: String {
      switch self {
      case .requested: "requested"
      case .removed: "removed"
      case .sessionInvalid(let why): "sessionInvalid(\(why))"
      case .failed(let why): "failed(\(why))"
      }
    }
  }

  public enum Event: Sendable {
    case stateChanged(State)
    case participantJoined(UserSnowflake)
    case participantLeft(UserSnowflake)
    case speaking(UserSnowflake, Bool)
    /// DAVE state: protocol version (0 = not end-to-end encrypted) and
    /// whether our media is currently encrypted and allowed out.
    case encryption(protocolVersion: UInt16, mediaReady: Bool)
  }

  // MARK: Limits

  /// From the start of a connection attempt until Ready.
  static let connectTimeout: Duration = .seconds(15)
  static let discoveryTimeout: Duration = .seconds(8)
  /// From Select Protocol until Session Description.
  static let sessionDescriptionTimeout: Duration = .seconds(15)
  /// First DAVE group with somebody else present.
  static let initialEncryptionTimeout: Duration = .seconds(90)
  /// Any later transition.
  static let transitionTimeout: Duration = .seconds(30)
  static let maxConsecutiveResumes = 2
  static let maxMessageSize = 64 * 1024
  /// After this much silence a speaker is reported as not speaking.
  static let speakingHold: Duration = .milliseconds(250)
  /// Silence frames sent after we stop talking, so receivers' decoders
  /// fade out instead of concealing.
  static let silenceTailFrames = 5

  // MARK: Public state

  public nonisolated let events: AsyncStream<Event>
  private let eventContinuation: AsyncStream<Event>.Continuation
  /// Mixed received audio: 20 ms mono frames at 48 kHz, only while somebody
  /// is audible.
  public nonisolated let playback: AsyncStream<[Float]>
  private let playbackContinuation: AsyncStream<[Float]>.Continuation

  public private(set) var state: State = .idle {
    didSet {
      guard state != oldValue else { return }
      logger.info("Voice state \(oldValue) → \(state)")
      eventContinuation.yield(.stateChanged(state))
    }
  }

  // MARK: Private state

  private let data: ConnectionData
  private let urlSession: URLSession
  private var logger: Logger

  /// Bumped on every WebSocket; stale callbacks compare against it.
  private var socketGeneration = 0
  private var webSocket: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var heartbeatTask: Task<Void, Never>?
  private var watchdogTask: Task<Void, Never>?

  private var seqAck = -1
  private var heartbeatNonce: UInt64 = 0
  private var unacknowledgedHeartbeats = 0
  private var consecutiveResumes = 0
  private var hasSession = false

  private var udp: VoiceUDPConnection?
  private var udpReceiveTask: Task<Void, Never>?
  private var keepaliveTask: Task<Void, Never>?
  private var tickTask: Task<Void, Never>?

  private var ssrc: UInt32 = 0
  private var offeredModes: [VoiceGateway.EncryptionMode] = []
  private var cipher: TransportCipher?
  private var dave: DaveSession

  private var deadline: (ContinuousClock.Instant, String)?

  // Sending
  private let encoder: OpusEncoder?
  private var rtpSequence = UInt16.random(in: .min ... .max)
  private var rtpTimestamp = UInt32.random(in: .min ... .max)
  private var nonceCounter: UInt32 = 0
  private var isSpeaking = false
  private var lastSentFrame: ContinuousClock.Instant?
  private var silenceFramesRemaining = 0

  // Receiving
  private struct Speaker {
    var jitter = JitterBuffer()
    var decoder: OpusDecoder?
    var pending: [Float] = []
    var lastAudible: ContinuousClock.Instant?
    var isSpeaking = false
  }
  private var ssrcToUser: [UInt32: UserSnowflake] = [:]
  private var speakers: [UInt32: Speaker] = [:]
  private var userVolumes: [UserSnowflake: Float] = [:]
  private var isReceiving = true

  public init(
    connectionData: ConnectionData,
    urlSession: URLSession = .shared
  ) {
    self.data = connectionData
    self.urlSession = urlSession
    var logger = DiscordGlobalConfiguration.makeLogger("VoiceGateway")
    logger[metadataKey: "channel"] = .string(connectionData.channelID.rawValue)
    self.logger = logger
    self.dave = DaveSession(
      selfUserID: connectionData.userID,
      channelID: connectionData.channelID,
      allowedUserIDs: connectionData.allowedUserIDs,
      logger: logger
    )
    self.encoder = try? OpusEncoder()
    (events, eventContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(256)
    )
    (playback, playbackContinuation) = AsyncStream.makeStream(
      bufferingPolicy: .bufferingNewest(10)
    )
  }

  // MARK: - Public API

  public func connect() {
    guard state == .idle else { return }
    guard let url = Self.validatedURL(endpoint: data.endpoint) else {
      finish(.failed("voice endpoint is not a Discord media host"))
      return
    }
    logger.info("Connecting to voice server", metadata: ["host": "\(url.host ?? "")"])
    state = .connecting
    deadline = (.now + Self.connectTimeout, "voice connection timed out")
    startWatchdog()
    openSocket(url: url, resume: false)
  }

  public func disconnect() {
    finish(.requested)
  }

  /// Sends one 20 ms frame of mono 48 kHz microphone audio. Dropped unless
  /// media is ready (transport keys and, for DAVE calls, our group key).
  public func sendAudio(_ samples: [Float]) {
    guard state == .connected || state == .resuming,
      samples.count == VoiceAudioFormat.frameSamples,
      let encoder
    else { return }
    let frame: Data
    do {
      frame = try samples.withUnsafeBufferPointer { try encoder.encode($0) }
    } catch {
      return
    }
    if !isSpeaking {
      isSpeaking = true
      sendSpeaking(true)
      eventContinuation.yield(.speaking(data.userID, true))
    }
    silenceFramesRemaining = Self.silenceTailFrames
    lastSentFrame = .now
    sendOpus(frame)
  }

  /// Per-user playback volume, 0...2.
  public func setVolume(_ volume: Float, for userID: UserSnowflake) {
    userVolumes[userID] = min(max(volume, 0), 2)
  }

  /// When deafened, received audio is not decoded at all.
  public func setReceiving(_ receiving: Bool) {
    isReceiving = receiving
    if !receiving {
      for key in speakers.keys { speakers[key]?.jitter.clear() }
    }
  }

  // MARK: - WebSocket

  /// Only `*.discord.media` hosts, no credentials, paths or queries.
  package static func validatedURL(endpoint: String) -> URL? {
    var raw = endpoint
    for scheme in ["wss://", "https://"] where raw.hasPrefix(scheme) {
      raw.removeFirst(scheme.count)
    }
    guard !raw.isEmpty,
      !raw.contains(where: { "/?#@\\ ".contains($0) }),
      let url = URL(string: "wss://\(raw)/?v=8"),
      let host = url.host?.lowercased(),
      host.hasSuffix(".discord.media"),
      host.count > ".discord.media".count,
      url.user == nil, url.password == nil
    else { return nil }
    return url
  }

  private func openSocket(url: URL, resume: Bool) {
    socketGeneration += 1
    let generation = socketGeneration
    webSocket?.cancel(with: .goingAway, reason: nil)

    var request = URLRequest(url: url)
    request.setValue(SuperProperties.useragent(ws: false), forHTTPHeaderField: "User-Agent")
    request.setValue("https://discord.com", forHTTPHeaderField: "Origin")
    let task = urlSession.webSocketTask(with: request)
    task.maximumMessageSize = Self.maxMessageSize
    webSocket = task
    unacknowledgedHeartbeats = 0
    heartbeatTask?.cancel()
    task.resume()

    if resume {
      send(
        .init(
          opcode: .resume,
          data: .resume(
            .init(
              server_id: GuildSnowflake(data.serverID),
              channel_id: data.channelID,
              session_id: data.sessionID,
              token: data.token,
              seq_ack: seqAck
            )
          )
        )
      )
    } else {
      send(
        .init(
          opcode: .identify,
          data: .identify(
            .init(
              server_id: GuildSnowflake(data.serverID),
              channel_id: data.channelID,
              user_id: data.userID,
              session_id: data.sessionID,
              token: data.token,
              video: false,
              max_dave_protocol_version: Int(DaveSession.maxSupportedProtocolVersion)
            )
          )
        )
      )
    }

    receiveTask?.cancel()
    receiveTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          let message = try await task.receive()
          await self?.handle(message, generation: generation)
        } catch {
          await self?.socketClosed(
            generation: generation,
            code: task.closeCode,
            error: error
          )
          return
        }
      }
    }
  }

  private func send(_ event: VoiceGateway.Event) {
    guard let webSocket else { return }
    do {
      let json = try DiscordGlobalConfiguration.encoder.encode(event)
      logger.debug("→ op \(event.opcode)")
      webSocket.send(.string(String(decoding: json, as: UTF8.self))) { _ in }
    } catch {
      logger.error("Could not encode voice payload", metadata: ["op": "\(event.opcode)"])
    }
  }

  private func sendBinary(_ opcode: VoiceGateway.Opcode, _ payload: Data) {
    logger.debug("→ op \(opcode) (binary, \(payload.count) B)")
    webSocket?.send(.data(Data([opcode.rawValue]) + payload)) { _ in }
  }

  private struct Envelope: Decodable {
    var op: UInt8
    var seq: Int?
  }

  private func handle(
    _ message: URLSessionWebSocketTask.Message,
    generation: Int
  ) {
    guard generation == socketGeneration, isActive else { return }
    switch message {
    case .data(let frame):
      handleBinary(frame)
    case .string(let text):
      let json = Data(text.utf8)
      guard
        let envelope = try? DiscordGlobalConfiguration.decoder.decode(
          Envelope.self,
          from: json
        )
      else { return }
      if let seq = envelope.seq { seqAck = seq }
      switch envelope.op {
      case VoiceGateway.Opcode.heartbeatAck.rawValue:
        heartbeatAcknowledged()
        return
      case VoiceGateway.Opcode.resumed.rawValue:
        resumed()
        return
      default:
        break
      }
      do {
        let event = try DiscordGlobalConfiguration.decoder.decode(
          VoiceGateway.Event.self,
          from: json
        )
        logger.debug("← op \(event.opcode)")
        handle(event)
      } catch {
        logger.debug("Ignoring undecodable voice payload", metadata: ["op": "\(envelope.op)"])
      }
    @unknown default:
      break
    }
  }

  private func handle(_ event: VoiceGateway.Event) {
    do {
      switch event.data {
      case .hello(let hello):
        startHeartbeat(intervalMilliseconds: hello.heartbeat_interval)
      case .ready(let ready):
        try handleReady(ready)
      case .sessionDescription(let description):
        try handleSessionDescription(description)
      case .speaking(let speaking):
        if let userID = speaking.user_id {
          let ssrc = UInt32(truncatingIfNeeded: speaking.ssrc)
          if ssrcToUser[ssrc] != userID {
            ssrcToUser[ssrc] = userID
            speakers[ssrc] = nil
          }
        }
      case .clientsConnect(let connect):
        try dave.addParticipants(connect.user_ids)
        for id in connect.user_ids where id != data.userID {
          eventContinuation.yield(.participantJoined(id))
        }
        updateEncryptionState(participantsChanged: true)
      case .clientDisconnect(let disconnect):
        dave.removeParticipant(disconnect.user_id)
        for (ssrc, user) in ssrcToUser where user == disconnect.user_id {
          ssrcToUser[ssrc] = nil
          speakers[ssrc] = nil
        }
        eventContinuation.yield(.participantLeft(disconnect.user_id))
        updateEncryptionState(participantsChanged: true)
      case .davePrepareTransition(let payload):
        try sendDave(
          dave.prepareTransition(
            id: payload.transition_id,
            protocolVersion: payload.protocol_version
          )
        )
        if payload.transition_id != DaveSession.initTransitionID {
          deadline = (.now + Self.transitionTimeout, "DAVE transition timed out")
        }
        updateEncryptionState()
      case .daveExecuteTransition(let payload):
        try dave.executeTransition(id: payload.transition_id)
        logger.info(
          "DAVE transition executed",
          metadata: [
            "transition": "\(payload.transition_id)",
            "protocol": "\(dave.protocolVersion)",
          ]
        )
        updateEncryptionState()
      case .davePrepareEpoch(let payload):
        try sendDave(
          dave.prepareEpoch(
            epoch: payload.epoch,
            protocolVersion: payload.protocol_version
          )
        )
        updateEncryptionState()
      default:
        break
      }
    } catch let error as DaveError {
      logger.error("DAVE failed: \(error)")
      finish(.sessionInvalid(error.description))
    } catch {
      logger.error("Voice protocol error: \(error)")
      finish(.failed("\(error)"))
    }
  }

  /// Server binary frames: sequence (u16 BE), opcode (u8), payload.
  private func handleBinary(_ frame: Data) {
    let bytes = [UInt8](frame)
    guard bytes.count >= 3 else { return }
    seqAck = Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
    let payload = Data(bytes[3...])
    func transition() -> (UInt16, Data)? {
      guard payload.count >= 2 else { return nil }
      let id = UInt16(payload[payload.startIndex]) << 8
        | UInt16(payload[payload.startIndex + 1])
      return (id, payload.dropFirst(2))
    }
    do {
      switch VoiceGateway.Opcode(rawValue: bytes[2]) {
      case .mlsExternalSender:
        logger.debug("← op mlsExternalSender")
        dave.setExternalSender(payload)
      case .mlsProposals:
        logger.debug("← op mlsProposals")
        try sendDave(dave.processProposals(payload))
      case .mlsAnnounceCommitTransition:
        guard let (id, commit) = transition() else { return }
        logger.debug("← op mlsAnnounceCommitTransition", metadata: ["transition": "\(id)"])
        try sendDave(dave.processCommit(transitionID: id, commit: Data(commit)))
        updateEncryptionState()
      case .mlsWelcome:
        guard let (id, welcome) = transition() else { return }
        logger.debug("← op mlsWelcome", metadata: ["transition": "\(id)"])
        try sendDave(dave.processWelcome(transitionID: id, welcome: Data(welcome)))
        updateEncryptionState()
      default:
        logger.debug("Ignoring binary voice opcode \(bytes[2])")
      }
    } catch let error as DaveError {
      logger.error("DAVE failed: \(error)")
      finish(.sessionInvalid(error.description))
    } catch {
      finish(.failed("\(error)"))
    }
  }

  private func sendDave(_ outbound: [DaveOutbound]) throws {
    for message in outbound {
      switch message {
      case .keyPackage(let package):
        sendBinary(.mlsKeyPackage, package)
      case .commitWelcome(let commitWelcome):
        sendBinary(.mlsCommitWelcome, commitWelcome)
      case .transitionReady(let id):
        send(.init(opcode: .daveTransitionReady, data: .daveTransitionReady(.init(transition_id: id))))
      case .invalidCommitWelcome(let id):
        send(
          .init(
            opcode: .mlsInvalidCommitWelcome,
            data: .mlsInvalidCommitWelcome(.init(transition_id: id))
          )
        )
      }
    }
  }

  // MARK: Heartbeat and resume

  private func startHeartbeat(intervalMilliseconds: Double) {
    let interval = Duration.milliseconds(max(1000, min(intervalMilliseconds, 60_000)))
    let generation = socketGeneration
    heartbeatTask?.cancel()
    heartbeatTask = Task { [weak self] in
      while !Task.isCancelled {
        guard await self?.heartbeat(generation: generation) == true else { return }
        try? await Task.sleep(for: interval)
      }
    }
  }

  /// Returns false when the heartbeat loop should stop.
  private func heartbeat(generation: Int) -> Bool {
    guard generation == socketGeneration, isActive else { return false }
    // One interval may pass without an ack; the second means the socket is
    // a zombie and gets resumed.
    if unacknowledgedHeartbeats >= 2 {
      logger.warning("Voice heartbeats unacknowledged; resuming")
      reconnect(code: nil)
      return false
    }
    unacknowledgedHeartbeats += 1
    heartbeatNonce = UInt64(Date().timeIntervalSince1970 * 1000)
    send(.init(opcode: .heartbeat, data: .heartbeat(.init(t: UInt(heartbeatNonce), seq_ack: seqAck))))
    return true
  }

  private func heartbeatAcknowledged() {
    unacknowledgedHeartbeats = 0
    // A healthy resumed socket renews the resume budget.
    if state != .resuming { consecutiveResumes = 0 }
  }

  private func resumed() {
    logger.info("Voice session resumed")
    state = dave.isMediaReady ? .connected : .negotiatingEncryption
  }

  private func socketClosed(
    generation: Int,
    code: URLSessionWebSocketTask.CloseCode,
    error: any Error
  ) {
    guard generation == socketGeneration, isActive else { return }
    let discordCode = VoiceGateway.CloseCode(rawValue: UInt16(clamping: code.rawValue))
    logger.warning(
      "Voice socket closed",
      metadata: ["code": "\(code.rawValue)", "error": "\(error.localizedDescription)"]
    )
    reconnect(code: discordCode)
  }

  private func reconnect(code: VoiceGateway.CloseCode?) {
    switch code?.recovery {
    case .stop:
      finish(code == .disconnected || code == .callTerminated ? .removed : .failed("closed with \(code!)"))
      return
    case .rejoin:
      finish(.sessionInvalid("closed with \(code!)"))
      return
    case .resume, nil:
      break
    }
    // Before Ready there is no session to resume.
    guard hasSession, cipher != nil else {
      finish(.failed("voice connection lost before it was established"))
      return
    }
    consecutiveResumes += 1
    guard consecutiveResumes <= Self.maxConsecutiveResumes,
      let url = Self.validatedURL(endpoint: data.endpoint)
    else {
      finish(.sessionInvalid("voice resume failed"))
      return
    }
    state = .resuming
    deadline = (.now + Self.connectTimeout, "voice resume timed out")
    openSocket(url: url, resume: true)
  }

  // MARK: Ready, UDP and session description

  private func handleReady(_ ready: VoiceGateway.Ready) throws {
    hasSession = true
    ssrc = ready.ssrc
    offeredModes = ready.modes
    dave.assign(ssrc: ssrc)
    state = .discovering
    deadline = (.now + Self.discoveryTimeout, "UDP discovery timed out")
    guard let port = UInt16(exactly: ready.port) else {
      throw VoiceUDPConnection.Error.addressNotAllowed("port \(ready.port)")
    }
    let udp = try VoiceUDPConnection(host: ready.ip, port: port)
    self.udp = udp
    let ssrc = ready.ssrc
    let generation = socketGeneration
    Task { [weak self] in
      do {
        try await udp.start()
        let (address, port) = try await udp.discoverExternalAddress(
          ssrc: ssrc,
          timeout: Self.discoveryTimeout
        )
        await self?.discovered(address: address, port: port, generation: generation)
      } catch {
        await self?.finish(.failed("UDP: \(error)"))
      }
    }
  }

  private func discovered(address: String, port: UInt16, generation: Int) {
    guard isActive, let udp else { return }
    guard let mode = TransportCipher.Mode.negotiate(offered: offeredModes) else {
      finish(.failed("no supported voice encryption mode"))
      return
    }
    logger.info("UDP discovery done", metadata: ["mode": "\(mode.encryptionMode.rawValue)"])
    send(
      .init(
        opcode: .selectProtocol,
        data: .selectProtocol(
          .init(
            protocol: "udp",
            data: .init(address: address, port: Int(port), mode: mode.encryptionMode),
            codecs: [.opusCodec]
          )
        )
      )
    )
    deadline = (.now + Self.sessionDescriptionTimeout, "no session description")

    keepaliveTask?.cancel()
    keepaliveTask = Task { await udp.keepalive() }
    udpReceiveTask?.cancel()
    udpReceiveTask = Task { [weak self] in
      for await datagram in udp.datagrams {
        await self?.receive(datagram)
      }
      await self?.udpEnded()
    }
  }

  private func udpEnded() {
    guard isActive else { return }
    finish(.failed("UDP connection closed"))
  }

  private func handleSessionDescription(
    _ description: VoiceGateway.SessionDescription
  ) throws {
    guard let mode = description.mode.flatMap(TransportCipher.Mode.init) else {
      throw TransportCipher.Error.invalidKey
    }
    cipher = try TransportCipher(mode: mode, secretKey: description.secret_key)
    nonceCounter = 0
    let version = description.dave_protocol_version ?? 0
    logger.info(
      "Session description received",
      metadata: ["mode": "\(mode.encryptionMode.rawValue)", "dave": "\(version)"]
    )
    try sendDave(dave.selectProtocol(version: version))
    deadline = nil
    updateEncryptionState(participantsChanged: true)
    startTicking()
    // Silence lets the server learn our SSRC mapping before anyone talks.
    for _ in 0..<3 { sendOpus(VoiceAudioFormat.silenceFrame) }
  }

  /// Moves between `negotiatingEncryption` and `connected`, and arms the
  /// DAVE deadline only while somebody else is in the channel.
  private func updateEncryptionState(participantsChanged: Bool = false) {
    guard cipher != nil, isActive, state != .resuming else { return }
    let ready = dave.isMediaReady && !dave.isTransitionPending
    eventContinuation.yield(
      .encryption(protocolVersion: dave.protocolVersion, mediaReady: dave.isMediaReady)
    )
    if ready {
      if state != .connected {
        logger.info(
          "Voice media ready",
          metadata: ["dave": "\(dave.protocolVersion)", "participants": "\(dave.participants.count)"]
        )
      }
      state = .connected
      deadline = nil
      return
    }
    if dave.isMediaReady {
      // A transition is pending but the previous epoch still works.
      state = .connected
      return
    }
    state = .negotiatingEncryption
    if dave.participants.isEmpty {
      // Alone in the channel: no group can form yet, so no deadline.
      deadline = nil
    } else if participantsChanged || deadline == nil {
      deadline = (.now + Self.initialEncryptionTimeout, "DAVE negotiation timed out")
    }
  }

  // MARK: Media

  private func sendOpus(_ frame: Data) {
    guard let cipher, let udp else { return }
    let payload: Data
    do {
      payload = try dave.encrypt(ssrc: ssrc, opus: frame)
    } catch {
      // No media before the DAVE transition completes.
      return
    }
    guard nonceCounter < .max else {
      finish(.sessionInvalid("transport nonce exhausted"))
      return
    }
    nonceCounter += 1
    let packet = RTPPacket(
      payloadType: .dynamic(UInt8(VoiceGateway.Codec.opusCodec.payload_type)),
      sequence: rtpSequence,
      timestamp: rtpTimestamp,
      ssrc: ssrc,
      payload: payload
    )
    rtpSequence &+= 1
    rtpTimestamp &+= UInt32(VoiceAudioFormat.frameSamples)
    guard let datagram = try? cipher.seal(packet, nonce: nonceCounter) else { return }
    udp.send(datagram)
  }

  private func sendSpeaking(_ speaking: Bool) {
    send(
      .init(
        opcode: .speaking,
        data: .speaking(.init(speaking: speaking ? [.voice] : [], ssrc: UInt(ssrc), delay: 0))
      )
    )
  }

  private func receive(_ datagram: Data) {
    guard isReceiving, let cipher, !RTPPacket.isRTCP(datagram) else { return }
    guard let packet = try? cipher.open(datagram),
      packet.payloadType.rawValue == UInt8(VoiceGateway.Codec.opusCodec.payload_type),
      packet.ssrc != ssrc,
      let userID = ssrcToUser[packet.ssrc]
    else { return }
    guard let opus = try? dave.decrypt(userID: userID, frame: packet.payload),
      !opus.isEmpty
    else { return }
    var speaker = speakers[packet.ssrc] ?? Speaker(decoder: try? OpusDecoder())
    speaker.jitter.push(sequence: packet.sequence, opus: opus)
    if opus != VoiceAudioFormat.silenceFrame {
      speaker.lastAudible = .now
    }
    speakers[packet.ssrc] = speaker
  }

  private func startTicking() {
    guard tickTask == nil else { return }
    tickTask = Task { [weak self] in
      let clock = ContinuousClock()
      var next = clock.now
      while !Task.isCancelled {
        next += VoiceAudioFormat.frameDuration
        await self?.tick()
        // Skip ahead after a stall instead of bursting.
        if next < clock.now { next = clock.now }
        try? await clock.sleep(until: next)
      }
    }
  }

  /// Runs every 20 ms: playout, mixing, speaking state and the silence tail.
  private func tick() {
    let now = ContinuousClock.now
    var mix = [Float](repeating: 0, count: VoiceAudioFormat.frameSamples)
    var audible = false
    for (ssrc, var speaker) in speakers {
      if isReceiving, let decoder = speaker.decoder {
        // Short packets: decode until one 20 ms frame is filled (at most 8).
        var decodes = 0
        while speaker.pending.count < VoiceAudioFormat.frameSamples, decodes < 8 {
          decodes += 1
          switch speaker.jitter.pop() {
          case .packet(let opus):
            if let pcm = try? decoder.decode(opus) { speaker.pending += pcm }
          case .conceal:
            speaker.pending += decoder.conceal()
          case .none:
            decodes = 8
          }
        }
        if !speaker.pending.isEmpty {
          let count = min(speaker.pending.count, VoiceAudioFormat.frameSamples)
          let gain = ssrcToUser[ssrc].flatMap { userVolumes[$0] } ?? 1
          for i in 0..<count { mix[i] += speaker.pending[i] * gain }
          speaker.pending.removeFirst(count)
          // Bound per-speaker leftovers to 120 ms.
          if speaker.pending.count > VoiceAudioFormat.maxFrameSamples {
            speaker.pending.removeFirst(speaker.pending.count - VoiceAudioFormat.maxFrameSamples)
          }
          audible = true
        }
      }
      let speaking = speaker.lastAudible.map { now - $0 < Self.speakingHold } ?? false
      if speaking != speaker.isSpeaking, let userID = ssrcToUser[ssrc] {
        speaker.isSpeaking = speaking
        eventContinuation.yield(.speaking(userID, speaking))
      }
      speakers[ssrc] = speaker
    }
    if audible {
      for i in mix.indices { mix[i] = min(max(mix[i], -1), 1) }
      playbackContinuation.yield(mix)
    }

    // Our own silence tail once the microphone stops delivering frames.
    if isSpeaking, let last = lastSentFrame, now - last > .milliseconds(60) {
      if silenceFramesRemaining > 0 {
        silenceFramesRemaining -= 1
        sendOpus(VoiceAudioFormat.silenceFrame)
      } else {
        isSpeaking = false
        sendSpeaking(false)
        eventContinuation.yield(.speaking(data.userID, false))
      }
    }
  }

  // MARK: Lifecycle

  private var isActive: Bool {
    if case .disconnected = state { return false }
    return state != .idle
  }

  private func startWatchdog() {
    watchdogTask?.cancel()
    watchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        await self?.checkDeadline()
      }
    }
  }

  private func checkDeadline() {
    guard isActive, let (instant, reason) = deadline, ContinuousClock.now >= instant
    else { return }
    logger.warning("Voice deadline passed: \(reason)")
    finish(.failed(reason))
  }

  private func finish(_ reason: DisconnectReason) {
    guard isActive || state == .idle else { return }
    if reason != .requested {
      logger.warning("Voice connection ending: \(reason)")
    }
    socketGeneration += 1
    webSocket?.cancel(with: .normalClosure, reason: nil)
    webSocket = nil
    for task in [receiveTask, heartbeatTask, watchdogTask, udpReceiveTask, keepaliveTask, tickTask] {
      task?.cancel()
    }
    receiveTask = nil
    heartbeatTask = nil
    watchdogTask = nil
    udpReceiveTask = nil
    keepaliveTask = nil
    tickTask = nil
    udp?.cancel()
    udp = nil
    cipher = nil
    speakers.removeAll()
    deadline = nil
    state = .disconnected(reason)
    eventContinuation.finish()
    playbackContinuation.finish()
  }
}
