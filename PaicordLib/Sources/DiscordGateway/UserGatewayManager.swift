//
//  UserGatewayManager.swift
//  PaicordLib
//
// Created by Lakhan Lothiyi on 26/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import DiscordHTTP
import DiscordModels
import Foundation
import Logging
import Synchronization

public actor UserGatewayManager: GatewayManager {

  private struct Message: Sendable {
    let payload: Gateway.Event
    let connectionId: UInt?
    var tryCount: Int

    init(
      payload: Gateway.Event,
      connectionId: UInt? = nil,
      tryCount: Int = 0
    ) {
      self.payload = payload
      self.connectionId = connectionId
      self.tryCount = tryCount
    }
  }

  var webSocketTask: URLSessionWebSocketTask?
  let session: URLSession
  /// A client to send requests to Discord.
  public nonisolated let client: any DiscordClient
  /// Max frame size we accept to receive through the web-socket connection.
  let maxFrameSize: Int
  /// Generator of `UserGatewayManager` ids.
  static let idGenerator = Atomic<UInt>(0)
  /// This gateway manager's identifier.
  public nonisolated let id = idGenerator.wrappingAdd(1, ordering: .relaxed).newValue
  let logger: Logger

  //MARK: Event streams
  nonisolated let eventsStreamContinuations = ContinuationBox<Gateway.Event>()
  nonisolated let eventsParseFailureContinuations = ContinuationBox<
    (any Error, Data)
  >()

  /// An async sequence of Gateway events.
  public nonisolated var events: DiscordAsyncSequence<Gateway.Event> {
    DiscordAsyncSequence<Gateway.Event>(
      base: AsyncStream<Gateway.Event> { continuation in
        self.eventsStreamContinuations.append(continuation)
      }
    )
  }
  /// An async sequence of Gateway event parse failures.
  public nonisolated var eventFailures: DiscordAsyncSequence<(any Error, Data)> {
    DiscordAsyncSequence<(any Error, Data)>(
      base: AsyncStream<(any Error, Data)> { continuation in
        self.eventsParseFailureContinuations.append(continuation)
      }
    )
  }

  //MARK: Connection data
  public nonisolated let identifyPayload: Gateway.Identify

  //MARK: Connection state
  public nonisolated let state = Atomic<GatewayState>(.noConnection)
  public nonisolated let stateCallback: (@Sendable (GatewayState) -> Void)?

  //MARK: Send queue

  /// 120 per 60 seconds (1 every 500ms),
  /// per https://discord.com/developers/docs/topics/gateway#rate-limiting
  let sendQueue = SerialQueue(waitTime: .milliseconds(500))

  //MARK: Current connection properties

  /// An ID to keep track of connection changes.
  nonisolated let connectionId = Atomic<UInt>(0)

  //MARK: Resume-related current-connection properties

  /// The sequence number for the payloads sent to us.
  var sequenceNumber: Int? = nil
  /// The ID of the current Discord-related session.
  var sessionId: String? = nil
  /// Gateway URL for resuming the connection, so we don't need to make an api call.
  var resumeGatewayURL: String? = nil

  //MARK: Backoff

  let connectionBackoff = Backoff(
    base: 2,
    maxExponentiation: 7,
    coefficient: 1,
    minBackoff: 15
  )

  //MARK: Ping-pong tracking properties
  var unsuccessfulPingsCount = 0
  var lastPongDate = Date()

  public init(
    session: URLSession = .shared,
    clientConfiguration: ClientConfiguration = .init(),
    maxFrameSize: Int = 1 << 28,
    token: Secret,
    appId: ApplicationSnowflake? = nil,
    largeThreshold: Int? = nil,
    presence: Gateway.Identify.Presence? = nil,
    capabilities: [Gateway.Capability] = [
      .lazyUserNotes,
      .authTokenRefresh,
      .userSettingsProto,
      .debounceMessageReactions,
      .nonChannelReadStates,
    ],
    captchaCallback: CaptchaChallengeHandler? = nil,
    mfaCallback: MFAVerificationHandler? = nil,
    stateCallback: (@Sendable (GatewayState) -> Void)? = nil
  ) async {
    self.session = session
    self.stateCallback = stateCallback
    self.client = await DefaultDiscordClient(
      session: session,
      header: .userToken(token),
      appId: appId,
      configuration: clientConfiguration,
      captchaCallback: captchaCallback,
      mfaCallback: mfaCallback
    )
    self.maxFrameSize = maxFrameSize
    self.identifyPayload = .init(
      token: token,
      properties: .init(ws: true),
      large_threshold: largeThreshold,
      presence: presence,
      capabilities: capabilities
    )

    var logger = DiscordGlobalConfiguration.makeLogger("GatewayManager")
    logger[metadataKey: "gateway-id"] = .string("\(self.id)")
    self.logger = logger
  }

  /// Connects to Discord.
  /// `state` must be set to an appropriate value before triggering this function.
  public func connect() async {
    logger.debug("Connect method triggered")
    if let connectIn = connectionBackoff.canPerformIn() {
      logger.warning(
        "Cannot try to connect immediately due to backoff",
        metadata: [
          "wait-time": .stringConvertible(connectIn)
        ]
      )
      try? await Task.sleep(for: connectIn)
    }
    let state = self.state.load(ordering: .relaxed)
    guard [.noConnection, .configured, .stopped].contains(state) else {
      logger.error(
        "Gateway state doesn't allow a new connection",
        metadata: [
          "state": .stringConvertible(state)
        ]
      )
      return
    }
    self.state.store(.connecting, ordering: .relaxed)
    self.stateCallback?(.connecting)

    await self.sendQueue.reset()
    let gatewayURL = await getGatewayURL()
    let queries: [(String, String)] = [
      ("v", "\(DiscordGlobalConfiguration.apiVersion)"),
      ("encoding", "json"),
      ("compress", "zstd-stream"),
    ]
    let decompressor: ZstdStreamingDecompressor
    do {
      decompressor = try ZstdStreamingDecompressor()
    } catch {
      self.logger.critical(
        "Will not connect because can't create a decompressor.",
        metadata: ["error": .string(String(reflecting: error))]
      )
      return
    }

    guard let wsURL = URL(string: gatewayURL + queries.makeForURLQuery()) else {
      self.logger.critical("Invalid Gateway URL: \(gatewayURL)")
      return
    }

    var request = URLRequest(url: wsURL)
    request.setValue(SuperProperties.useragent(ws: false)!, forHTTPHeaderField: "User-Agent")
    request.setValue("https://discord.com", forHTTPHeaderField: "Origin")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.setValue(SuperProperties.GenerateLocaleHeader(), forHTTPHeaderField: "Accept-Language")

    logger.trace("Will try to connect to Discord through web-socket")
    let connectionId = self.connectionId.wrappingAdd(1, ordering: .relaxed).newValue

    let wsTask = self.session.webSocketTask(with: request)
    wsTask.maximumMessageSize = self.maxFrameSize
    self.webSocketTask = wsTask
    wsTask.resume()

    self.logger.debug("Connected to Discord through web-socket. Will configure")
    self.state.store(.configured, ordering: .relaxed)
    self.stateCallback?(.configured)

    Task {
      do {
        while self.connectionId.load(ordering: .relaxed) == connectionId {
          let message = try await wsTask.receive()
          self.processMessage(
            message,
            decompressor: decompressor,
            forConnectionWithId: connectionId
          )
        }
      } catch {
        let closeCode = wsTask.closeCode
        let closeReasonData = wsTask.closeReason
        let closeReasonStr = closeReasonData.flatMap { String(data: $0, encoding: .utf8) }
        if closeCode != .invalid {
          logger.debug(
            "web-socket connection closed",
            metadata: [
              "closeCode": .string("\(closeCode.rawValue)"),
              "closeReason": .string(closeReasonStr ?? "nil"),
              "connectionId": .stringConvertible(
                self.connectionId.load(ordering: .relaxed)
              ),
            ]
          )
          await self.onClose(
            closeReason: .closeFrame(code: UInt16(clamping: closeCode.rawValue), reason: closeReasonStr),
            forConnectionWithId: connectionId
          )
        } else {
          logger.debug(
            "web-socket error while connecting to Discord. Will try again",
            metadata: [
              "error": .string(String(reflecting: error)),
              "connectionId": .stringConvertible(
                self.connectionId.load(ordering: .relaxed)
              ),
            ]
          )
          self.state.store(.noConnection, ordering: .relaxed)
          self.stateCallback?(.noConnection)
          await self.onClose(
            closeReason: .error(error),
            forConnectionWithId: connectionId
          )
        }
      }
    }
  }

  // MARK: - Gateway actions

  /// https://discord.com/developers/docs/topics/gateway-events#update-presence
  public func updatePresence(payload: Gateway.Identify.Presence) {
    self.send(
      message: .init(
        payload: .init(
          opcode: .presenceUpdate,
          data: .requestPresenceUpdate(payload)
        )
      )
    )
  }

  /// https://discord.com/developers/docs/topics/gateway-events#update-voice-state
  public func updateVoiceState(payload: VoiceStateUpdate) {
    self.send(
      message: .init(
        payload: .init(
          opcode: .voiceStateUpdate,
          data: .requestVoiceStateUpdate(payload)
        )
      )
    )
  }

  /// https://docs.discord.food/topics/gateway-events#ping-voice-server
  public func pingVoiceServer() {
    self.send(
      message: .init(
        payload: .init(
          opcode: .voiceServerPing,
          data: nil
        )
      )
    )
  }

  /// https://discord.com/developers/docs/topics/gateway-events#request-guild-members
  /// https://docs.discord.food/topics/gateway-events#request-guild-members
  public func requestGuildMembersChunk(payload: Gateway.RequestGuildMembers) {
    self.send(
      message: .init(
        payload: .init(
          opcode: .requestGuildMembers,
          data: .requestGuildMembers(payload)
        )
      )
    )
  }

  /// https://docs.discord.food/topics/gateway-events#update-guild-subscriptions
  public func updateGuildSubscriptions(
    payload: Gateway.UpdateGuildSubscriptions
  ) {
    self.send(
      message: .init(
        payload: .init(
          opcode: .guildSubscriptionsBulk,
          data: .updateGuildSubscriptions(payload)
        )
      )
    )
  }

  /// https://docs.discord.food/topics/gateway-events#request-last-messages
  public func requestLastMessages(payload: Gateway.RequestLastMessages) {
    self.send(
      message: .init(
        payload: .init(
          opcode: .requestLastMessages,
          data: .requestLastMessages(payload)
        )
      )
    )
  }

  // MARK: End of Gateway actions -

  /// Makes an stream of Gateway events.
  @available(*, deprecated, renamed: "events")
  public func makeEventsStream() -> AsyncStream<Gateway.Event> {
    self.events.base
  }

  /// Makes an stream of Gateway event parse failures.
  @available(*, deprecated, renamed: "eventFailures")
  public func makeEventsParseFailureStream() -> AsyncStream<
    (any Error, Data)
  > {
    self.eventFailures.base
  }

  /// Disconnects from Discord.
  /// Doesn't end the event streams.
  public func disconnect() async {
    logger.debug(
      "Will disconnect",
      metadata: [
        "connectionId": .stringConvertible(
          self.connectionId.load(ordering: .relaxed)
        )
      ]
    )
    if self.state.load(ordering: .relaxed) == .stopped {
      logger.debug(
        "Already disconnected",
        metadata: [
          "connectionId": .stringConvertible(
            self.connectionId.load(ordering: .relaxed)
          )
        ]
      )
      return
    }
    _ = self.connectionId.wrappingAdd(1, ordering: .relaxed)
    self.state.store(.noConnection, ordering: .relaxed)
    self.stateCallback?(.noConnection)
    connectionBackoff.resetTryCount()
    await self.sendQueue.reset()
    self.closeWebSocket()
  }
}

extension UserGatewayManager {
  private func processEvent(_ event: Gateway.Event) async {
    if let sequenceNumber = event.sequenceNumber {
      self.sequenceNumber = sequenceNumber
    }

    switch event.opcode {
    case .heartbeat:
      self.sendPing(
        forConnectionWithId: self.connectionId.load(ordering: .relaxed)
      )
    case .heartbeatAccepted:
      self.lastPongDate = Date()
    case .reconnect:
      logger.debug(
        "Received reconnect request. Will reconnect after connection closure"
      )
    default:
      break
    }

    switch event.data {
    case .invalidSession(let canResume):
      logger.warning(
        "Got invalid session. Will try to reconnect or resume",
        metadata: [
          "canResume": .stringConvertible(canResume)
        ]
      )
      if !canResume {
        self.sequenceNumber = nil
        self.resumeGatewayURL = nil
        self.sessionId = nil
      }
      self.state.store(.noConnection, ordering: .relaxed)
      self.stateCallback?(.noConnection)
      await self.connect()
    case .hello(let hello):
      logger.debug("Received 'hello'")
      self.setupPingTask(
        forConnectionWithId: self.connectionId.load(ordering: .relaxed),
        every: .milliseconds(Int64(hello.heartbeat_interval))
      )
      self.sendUpdateTimeSpentSessionID(
        forConnectionWithId: self.connectionId.load(ordering: .relaxed)
      )
      self.setupUpdateTimeSpentSessionID(
        forConnectionWithId: self.connectionId.load(ordering: .relaxed),
        every: .seconds(1800)
      )
      logger.trace("Will resume or identify")
      await self.sendResumeOrIdentify()
    case .ready(let payload):
      logger.notice(
        "Received ready notice. The connection is fully established",
        metadata: [
          "connectionId": .stringConvertible(
            self.connectionId.load(ordering: .relaxed)
          )
        ]
      )
      await self.onSuccessfulConnection()
      self.sessionId = payload.session_id
      self.resumeGatewayURL = payload.resume_gateway_url
    case .resumed:
      logger.debug(
        "Received resume notice. The connection is fully established",
        metadata: [
          "connectionId": .stringConvertible(
            self.connectionId.load(ordering: .relaxed)
          )
        ]
      )
      await self.onSuccessfulConnection()
    default:
      break
    }
  }

  private func getGatewayURL() async -> String {
    logger.debug("Will try to get Discord gateway url")
    if self.sequenceNumber != nil,
      let gatewayURL = self.resumeGatewayURL
    {
      logger.trace("Got Discord gateway url from 'resumeGatewayURL'")
      return gatewayURL
    } else {
      return DiscordGlobalConfiguration.gatewayURL
    }
  }

  private func sendResumeOrIdentify() async {
    if let sessionId = self.sessionId,
      let lastSequenceNumber = self.sequenceNumber
    {
      self.sendResume(sessionId: sessionId, sequenceNumber: lastSequenceNumber)
    } else {
      logger.debug(
        "Can't resume last Discord connection. Will identify",
        metadata: [
          "sessionId": .stringConvertible(self.sessionId ?? "nil"),
          "lastSequenceNumber": .stringConvertible(self.sequenceNumber ?? -1),
        ]
      )
      await self.sendIdentify()
    }
  }

  private func sendResume(sessionId: String, sequenceNumber: Int) {
    let resume = Gateway.Event(
      opcode: .resume,
      data: .resume(
        .init(
          token: identifyPayload.token,
          session_id: sessionId,
          sequence: sequenceNumber
        )
      )
    )
    self.send(message: .init(payload: resume))

    self.sequenceNumber = nil

    logger.debug("Sent resume request to Discord")
  }

  private func sendIdentify() async {
    connectionBackoff.willTry()
    let identify = Gateway.Event(
      opcode: .identify,
      data: .identify(identifyPayload)
    )
    self.send(message: .init(payload: identify))
  }

  private func processMessage(
    _ message: URLSessionWebSocketTask.Message,
    decompressor: ZstdStreamingDecompressor,
    forConnectionWithId connectionId: UInt
  ) {
    guard self.connectionId.load(ordering: .relaxed) == connectionId else {
      return
    }

    let data: Data
    switch message {
    case .string(let string):
      self.logger.debug(
        "Got text from websocket",
        metadata: [
          "text": .string(string)
        ]
      )
      data = Data(string.utf8)
    case .data(let rawData):
      do {
        data = try decompressor.decompress(data: rawData)
        self.logger.debug(
          "Got binary from websocket",
          metadata: [
            "text": .string(String(buffer: data))
          ]
        )
      } catch {
        self.logger.error(
          "Failed to decompress zstd frame",
          metadata: ["error": .string("\(error)")]
        )
        return
      }
    @unknown default:
      return
    }

    do {
      let event = try DiscordGlobalConfiguration.decoder.decode(
        Gateway.Event.self,
        from: data
      )
      self.logger.debug(
        "Decoded event",
        metadata: [
          "event": .string("\(event)"),
          "opcode": .string(event.opcode.description),
        ]
      )
      Task { await self.processEvent(event) }
      self.eventsStreamContinuations.yieldToAll(event)
    } catch {
      self.logger.debug(
        "Failed to decode event",
        metadata: [
          "error": .string("\(error)")
        ]
      )
      self.eventsParseFailureContinuations.yieldToAll((error, data))
    }
  }

  private enum CloseReason {
    case closeFrame(code: UInt16?, reason: String?)
    case error(any Error)
  }

  private func onClose(
    closeReason: CloseReason,
    forConnectionWithId connectionId: UInt
  ) async {
    self.logger.debug("Received connection close notification for a web-socket")
    guard self.connectionId.load(ordering: .relaxed) == connectionId else {
      return
    }
    let (code, codeDesc) = self.getCloseCodeAndDescription(of: closeReason)
    let isDebugLevelCode = [nil, 1000, 1001, 1011].contains(code)
    self.logger.log(
      level: isDebugLevelCode ? .debug : .warning,
      "Received connection close notification. Will try to reconnect",
      metadata: [
        "code": .string(codeDesc),
        "closedConnectionId": .stringConvertible(
          self.connectionId.load(ordering: .relaxed)
        ),
      ]
    )
    if self.canTryReconnect(code: code) {
      self.state.store(.noConnection, ordering: .relaxed)
      self.stateCallback?(.noConnection)
      self.logger.trace(
        "Will try reconnect since Discord does allow it.",
        metadata: [
          "code": .string(codeDesc),
          "closedConnectionId": .stringConvertible(
            self.connectionId.load(ordering: .relaxed)
          ),
        ]
      )
      await self.connect()
    } else {
      self.state.store(.stopped, ordering: .relaxed)
      self.stateCallback?(.stopped)
      _ = self.connectionId.wrappingAdd(1, ordering: .relaxed)
      self.logger.critical(
        "Will not reconnect because Discord does not allow it. Something is wrong. Your close code is '\(codeDesc)'."
      )
    }
  }

  private nonisolated func getCloseCodeAndDescription(
    of closeReason: CloseReason
  ) -> (UInt16?, String) {
    switch closeReason {
    case .error(let error):
      return (nil, String(reflecting: error))
    case .closeFrame(let code, let reason):
      guard let code else {
        return (nil, "nil")
      }
      if let discordCode = GatewayCloseCode(rawValue: code) {
        return (code, "\(discordCode)")
      }
      return (code, reason ?? "\(code)")
    }
  }

  private nonisolated func canTryReconnect(code: UInt16?) -> Bool {
    guard let code, let discordCode = GatewayCloseCode(rawValue: code) else {
      return true
    }
    return discordCode.canTryReconnect
  }

  private func setupPingTask(
    forConnectionWithId connectionId: UInt,
    every duration: Duration
  ) {
    Task {
      try? await Task.sleep(for: duration)
      guard self.connectionId.load(ordering: .relaxed) == connectionId else {
        self.logger.trace(
          "Canceled a ping task",
          metadata: [
            "connectionId": .stringConvertible(connectionId)
          ]
        )
        return
      }
      self.logger.debug(
        "Will send automatic ping",
        metadata: [
          "connectionId": .stringConvertible(connectionId)
        ]
      )
      self.sendPing(forConnectionWithId: connectionId)
      self.setupPingTask(forConnectionWithId: connectionId, every: duration)
    }
  }

  private func setupUpdateTimeSpentSessionID(
    forConnectionWithId connectionId: UInt,
    every duration: Duration
  ) {
    Task {
      try? await Task.sleep(for: duration)
      guard self.connectionId.load(ordering: .relaxed) == connectionId else {
        self.logger.trace(
          "Canceled a session time spent update task",
          metadata: [
            "connectionId": .stringConvertible(connectionId)
          ]
        )
        return
      }
      self.logger.debug(
        "Will send automatic session time spent update",
        metadata: [
          "connectionId": .stringConvertible(connectionId)
        ]
      )
      self.sendPing(forConnectionWithId: connectionId)
      self.sendUpdateTimeSpentSessionID(forConnectionWithId: connectionId)
      self.setupUpdateTimeSpentSessionID(
        forConnectionWithId: connectionId,
        every: duration
      )
    }
  }

  private func sendPing(forConnectionWithId connectionId: UInt) {
    logger.trace(
      "Will ping",
      metadata: [
        "connectionId": .stringConvertible(connectionId)
      ]
    )
    self.send(
      message: .init(
        payload: .init(
          opcode: .qosHeartbeat,
          data: .qosHeartbeat(.init(seq: self.sequenceNumber, qos: .init()))
        )
      )
    )
    Task {
      try? await Task.sleep(for: .seconds(10))
      guard self.connectionId.load(ordering: .relaxed) == connectionId else {
        return
      }
      if self.lastPongDate.addingTimeInterval(15) > Date() {
        logger.trace("Successful ping")
        self.unsuccessfulPingsCount = 0
      } else {
        logger.trace("Unsuccessful ping")
        self.unsuccessfulPingsCount += 1
      }
      if unsuccessfulPingsCount > 2 {
        logger.debug(
          "Too many unsuccessful pings. Will try to reconnect",
          metadata: [
            "connectionId": .stringConvertible(
              self.connectionId.load(ordering: .relaxed)
            )
          ]
        )
        self.state.store(.noConnection, ordering: .relaxed)
        self.stateCallback?(.noConnection)
        await self.connect()
      }
    }
  }

  private func sendUpdateTimeSpentSessionID(
    forConnectionWithId connectionId: UInt
  ) {
    logger.trace(
      "Will send session time spent update",
      metadata: [
        "connectionId": .stringConvertible(connectionId)
      ]
    )
    self.send(
      message: .init(
        payload: .init(
          opcode: .updateTimeSpentSessionId,
          data: .updateTimeSpentSessionId(Gateway.UpdateTimeSpentSessionID())
        )
      )
    )
  }

  private nonisolated func send(message: Message) {
    self.sendQueue.perform { [weak self] in
      guard let self = self else { return }
      let state = self.state.load(ordering: .relaxed)
      switch state {
      case .connected:
        break
      case .stopped:
        logger.warning(
          "Will not send message because bot is stopped",
          metadata: [
            "message": .string("\(message)")
          ]
        )
        return
      case .noConnection, .connecting, .configured:
        switch message.payload.opcode.isSentForConnectionEstablishment {
        case true:
          break
        case false:
          self.send(message: message)
          return
        }
      }
      if let connectionId = message.connectionId,
        self.connectionId.load(ordering: .relaxed) != connectionId
      {
        return
      }
      Task {
        let data: Data
        do {
          data = try DiscordGlobalConfiguration.encoder.encode(message.payload)
        } catch {
          self.logger.error(
            "Could not encode payload, \(error)",
            metadata: [
              "payload": .string("\(message.payload)"),
              "connectionId": .stringConvertible(
                self.connectionId.load(ordering: .relaxed)
              ),
            ]
          )
          return
        }

        if let wsTask = await self.webSocketTask {
          do {
            self.logger.debug(
              "Will send a payload with opcode",
              metadata: [
                "opcode": .string(message.payload.opcode.description)
              ]
            )
            let stringPayload = String(decoding: data, as: UTF8.self)
            try await wsTask.send(.string(stringPayload))
          } catch {
            self.logger.error(
              "Could not send payload through web-socket",
              metadata: [
                "error": .string(String(reflecting: error)),
                "payload": .string("\(message.payload)"),
                "state": .stringConvertible(
                  self.state.load(ordering: .relaxed)
                ),
                "connectionId": .stringConvertible(
                  self.connectionId.load(ordering: .relaxed)
                ),
              ]
            )
          }
        } else {
          self.logger.log(
            level: (message.payload.opcode == .heartbeat) ? .debug : .warning,
            "Trying to send through ws when a connection is not established",
            metadata: [
              "payload": .string("\(message.payload)"),
              "state": .stringConvertible(self.state.load(ordering: .relaxed)),
              "connectionId": .stringConvertible(
                self.connectionId.load(ordering: .relaxed)
              ),
            ]
          )
        }
      }
    }
  }

  private func onSuccessfulConnection() async {
    self.state.store(.connected, ordering: .relaxed)
    self.stateCallback?(.connected)
    connectionBackoff.resetTryCount()
    self.unsuccessfulPingsCount = 0
    await self.sendQueue.reset()
  }

  private func closeWebSocket() {
    logger.debug("Will possibly close a web-socket")
    self.webSocketTask?.cancel(with: .goingAway, reason: nil)
    self.webSocketTask = nil
  }

  public func getSessionID() -> String? {
    return self.sessionId
  }
}

extension UserGatewayManager {
  func addEventsContinuation(
    _ continuation: AsyncStream<Gateway.Event>.Continuation
  ) {
    self.eventsStreamContinuations.append(continuation)
  }

  func addEventsParseFailureContinuation(
    _ continuation: AsyncStream<(any Error, Data)>.Continuation
  ) {
    self.eventsParseFailureContinuations.append(continuation)
  }
}

//MARK: - GatewayState
/// Represents the current state of the gateway connection lifecycle.
public enum GatewayState: Int, Sendable, AtomicRepresentable, CustomStringConvertible {
  /// The gateway manager has been intentionally stopped and will not reconnect.
  case stopped
  /// No active connection exists; the gateway is disconnected and idle.
  case noConnection
  /// The gateway is in the process of establishing a connection.
  case connecting
  /// The gateway connection is established at the protocol level, but not yet fully ready (awaiting identification/resume).
  case configured
  /// The gateway has successfully connected, identified/resumed, and is fully ready to send/receive events.
  case connected

  public var description: String {
    switch self {
    case .stopped: return "stopped"
    case .noConnection: return "noConnection"
    case .connecting: return "connecting"
    case .configured: return "configured"
    case .connected: return "connected"
    }
  }
}

// MARK: - +Gateway.Opcode
extension Gateway.Opcode {
  var isSentForConnectionEstablishment: Bool {
    switch self {
    case .identify, .resume: true
    default: false
    }
  }
}
