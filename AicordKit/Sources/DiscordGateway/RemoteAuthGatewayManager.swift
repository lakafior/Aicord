//
//  RemoteAuthGatewayManager.swift
//  AicordKit
//
//  Created by Lakhan Lothiyi on 19/01/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import DiscordHTTP
import DiscordModels
import Foundation
import Logging
import Security
import Synchronization

public actor RemoteAuthGatewayManager {

  public enum RemoteAuthOpcode: String, Codable, Sendable {
    case hello
    case `init` = "init"
    case heartbeat
    case heartbeat_ack = "heartbeat_ack"
    case nonce_proof = "nonce_proof"
    case pending_remote_init = "pending_remote_init"
    case pending_ticket = "pending_ticket"
    case pending_login = "pending_login"
    case cancel
  }

  /// A flat payload structure used by the remote-auth gateway.
  public struct RemoteAuthPayload: Codable, CustomStringConvertible, Sendable {
    public let op: RemoteAuthOpcode

    // hello
    public var heartbeat_interval: Int?
    public var timeout_ms: Int?

    // init
    public var encoded_public_key: String?

    // nonce_proof (incoming)
    public var encrypted_nonce: String?

    // nonce_proof (outgoing)
    public var nonce: String?

    // pending_remote_init
    public var fingerprint: String?

    // pending_ticket
    public internal(set) var encrypted_user_payload: String?

    public var user_payload: UserPayload?

    public struct UserPayload: Codable, Sendable {
      public let id: String
      public let discriminator: String
      public let avatar: String?
      public let username: String
    }

    // pending_login
    public var ticket: String?

    public init(
      op: RemoteAuthOpcode,
      heartbeat_interval: Int? = nil,
      timeout_ms: Int? = nil,
      encoded_public_key: String? = nil,
      encrypted_nonce: String? = nil,
      nonce: String? = nil,
      fingerprint: String? = nil,
      encrypted_user_payload: String? = nil,
      user_payload: UserPayload? = nil,
      ticket: String? = nil
    ) {
      self.op = op
      self.heartbeat_interval = heartbeat_interval
      self.timeout_ms = timeout_ms
      self.encoded_public_key = encoded_public_key
      self.encrypted_nonce = encrypted_nonce
      self.nonce = nonce
      self.fingerprint = fingerprint
      self.encrypted_user_payload = encrypted_user_payload
      self.user_payload = user_payload
      self.ticket = ticket
    }

    public var description: String { "RemoteAuthPayload(op: \(op), ... )" }
  }

  private struct Message: Sendable {
    let payload: RemoteAuthPayload
    let connectionId: UInt?
    var tryCount: Int

    init(
      payload: RemoteAuthPayload,
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
  /// Max frame size we accept to receive through the web-socket connection.
  let maxFrameSize: Int
  /// Generator of `RemoteAuthGatewayManager` ids.
  static let idGenerator = Atomic<UInt>(0)
  /// This gateway manager's identifier.
  public nonisolated let id = idGenerator.wrappingAdd(1, ordering: .relaxed).newValue
  let logger: Logger

  //MARK: Event streams
  var eventsStreamContinuations: [AsyncStream<RemoteAuthPayload>.Continuation] =
    []
  var eventsParseFailureContinuations: [AsyncStream<(any Error, Data)>.Continuation] = []

  /// An async sequence of Gateway events.
  public var events: DiscordAsyncSequence<RemoteAuthPayload> {
    DiscordAsyncSequence<RemoteAuthPayload>(
      base: AsyncStream<RemoteAuthPayload> { continuation in
        self.eventsStreamContinuations.append(continuation)
      }
    )
  }
  /// An async sequence of Gateway event parse failures.
  public var eventFailures: DiscordAsyncSequence<(any Error, Data)> {
    DiscordAsyncSequence<(any Error, Data)>(
      base: AsyncStream<(any Error, Data)> { continuation in
        self.eventsParseFailureContinuations.append(continuation)
      }
    )
  }

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

  // MARK: - RSA keypair and fingerprint (Apple Security SecKey)
  /// The client's RSA private key used to decrypt nonces and payloads.
  private var privateKey: SecKey?
  /// The base64-encoded SPKI of the public key.
  private var encodedPublicKeySPKI: String?

  public init(
    session: URLSession = .shared,
    maxFrameSize: Int = 1 << 28,
    stateCallback: (@Sendable (GatewayState) -> Void)? = nil
  ) {
    self.session = session
    self.stateCallback = stateCallback
    self.maxFrameSize = maxFrameSize

    var logger = DiscordGlobalConfiguration.makeLogger(
      "RemoteAuthGatewayManager"
    )
    logger[metadataKey: "gateway-id"] = .string(
      "\(Self.idGenerator.wrappingAdd(1, ordering: .relaxed).newValue)"
    )
    self.logger = logger
  }

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
    let gatewayURL = DiscordGlobalConfiguration.remoteAuthURL
    let queries: [(String, String)] = [
      ("v", "2")
    ]

    guard let wsURL = URL(string: gatewayURL + queries.makeForURLQuery()) else {
      logger.critical("Invalid Remote Auth Gateway URL: \(gatewayURL)")
      return
    }

    var request = URLRequest(url: wsURL)
    request.setValue(SuperProperties.useragent(ws: false)!, forHTTPHeaderField: "User-Agent")
    request.setValue("https://discord.com", forHTTPHeaderField: "Origin")
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.setValue(SuperProperties.GenerateLocaleHeader(), forHTTPHeaderField: "Accept-Language")

    logger.trace(
      "Will try to connect to Remote Auth Gateway through web-socket"
    )
    let connectionId = self.connectionId.wrappingAdd(1, ordering: .relaxed).newValue

    let wsTask = self.session.webSocketTask(with: request)
    wsTask.maximumMessageSize = self.maxFrameSize
    self.webSocketTask = wsTask
    wsTask.resume()

    self.logger.debug("Connected to Remote Auth Gateway through web-socket.")
    await self.onSuccessfulConnection()

    Task {
      do {
        while self.connectionId.load(ordering: .relaxed) == connectionId {
          let message = try await wsTask.receive()
          await self.processMessage(
            message,
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
            "web-socket error while connecting to Remote Auth Gateway. Will try again",
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

  public func sendInit(encodedPublicKey: String) {
    let payload = RemoteAuthPayload(
      op: .`init`,
      encoded_public_key: encodedPublicKey
    )
    self.send(message: .init(payload: payload))
  }

  public func sendHeartbeat() {
    let payload = RemoteAuthPayload(op: .heartbeat)
    self.send(message: .init(payload: payload))
  }

  public func sendNonceProof(nonce: String) {
    let payload = RemoteAuthPayload(op: .nonce_proof, nonce: nonce)
    self.send(message: .init(payload: payload))
  }

  // MARK: End of Gateway actions -

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

extension RemoteAuthGatewayManager {
  private func processEvent(_ event: RemoteAuthPayload) async {
    switch event.op {
    case .heartbeat:
      self.sendHeartbeat()
    case .heartbeat_ack:
      self.lastPongDate = Date()
    case .hello:
      guard let interval = event.heartbeat_interval else { break }
      self.setupPingTask(
        forConnectionWithId: self.connectionId.load(ordering: .relaxed),
        every: .milliseconds(Int64(interval))
      )
      await self.generateRSAKeyPairIfNeeded()
      if let encodedKey = self.encodedPublicKeySPKI {
        self.sendInit(encodedPublicKey: encodedKey)
      }
    case .nonce_proof:
      guard let encNonce = event.encrypted_nonce,
        let decryptedNonce = self.rsaDecryptOAEPSHA256(encNonce)
      else {
        self.logger.error("Missing or invalid encrypted_nonce in nonce_proof")
        break
      }

      let nonceProof = decryptedNonce.base64EncodedString(
        options: [.endLineWithLineFeed]
      ).replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
      self.logger.debug(
        "Sending nonce_proof",
        metadata: [
          "nonce_proof": .string(nonceProof)
        ]
      )
      self.sendNonceProof(nonce: nonceProof)
    case .`init`: break
    default: break
    }
  }

  private func processMessage(
    _ message: URLSessionWebSocketTask.Message,
    forConnectionWithId connectionId: UInt
  ) async {
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
      self.logger.debug(
        "Got binary from websocket",
        metadata: [
          "text": .string(String(buffer: rawData))
        ]
      )
      data = rawData
    @unknown default:
      return
    }

    do {
      var event = try DiscordGlobalConfiguration.decoder.decode(
        RemoteAuthPayload.self,
        from: data
      )
      self.logger.debug(
        "Decoded remote-auth event",
        metadata: [
          "event": .string("\(event)"),
          "op": .string(event.op.rawValue),
        ]
      )

      if let enc = event.encrypted_user_payload,
        self.privateKey != nil
      {
        if let decrypted = self.rsaDecryptOAEPSHA256(enc) {
          if let decryptedString = String(data: decrypted, encoding: .utf8) {
            let parts = decryptedString.split(
              separator: ":",
              omittingEmptySubsequences: false
            ).map(String.init)
            if parts.count >= 4 {
              let payload = RemoteAuthPayload.UserPayload(
                id: parts[0],
                discriminator: parts[1],
                avatar: parts[2].isEmpty ? nil : parts[2],
                username: parts[3]
              )
              event.user_payload = payload
            } else {
              self.logger.error(
                "Failed to parse decrypted user payload: \(decryptedString)"
              )
            }
          } else {
            self.logger.error(
              "Failed to decode decrypted encrypted_user_payload as UTF-8"
            )
          }
        } else {
          self.logger.error("Failed to decrypt encrypted_user_payload")
        }
      }

      Task { await self.processEvent(event) }
      for continuation in self.eventsStreamContinuations {
        continuation.yield(event)
      }
    } catch {
      self.logger.debug(
        "Failed to decode remote-auth event",
        metadata: [
          "error": .string("\(error)")
        ]
      )
      for continuation in self.eventsParseFailureContinuations {
        continuation.yield((error, data))
      }
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
        "Will try reconnect since gateway allows it.",
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
        "Will not reconnect because gateway does not allow it. Your close code is '\(codeDesc)'."
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
      self.sendHeartbeat()
      self.setupPingTask(forConnectionWithId: connectionId, every: duration)
    }
  }

  private func sendPing(forConnectionWithId connectionId: UInt) {
    logger.trace(
      "Will ping",
      metadata: [
        "connectionId": .stringConvertible(connectionId)
      ]
    )
    self.sendHeartbeat()
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
        switch message.payload.op {
        case .`init`, .heartbeat, .heartbeat_ack:
          break
        default:
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
              "Will send payload",
              metadata: [
                "op": .string(message.payload.op.rawValue)
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
            level: (message.payload.op == .heartbeat) ? .debug : .warning,
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

  /// Use this to exchange a remote auth ticket for a Discord auth token.
  /// - Parameter ticket: The remote auth ticket received from the gateway.
  /// - Returns: A token.
  public func exchange(ticket: String, client: any DiscordClient) async throws -> Secret {
    let req = try await client.exchangeRemoteAuthTicket(
      payload: .init(ticket: ticket)
    )
    try req.guardSuccess()
    let data = try req.decode()
    let encrypted_token = data.encrypted_token

    guard self.privateKey != nil else {
      self.logger.error("No private key available to decrypt remote auth token")
      throw RemoteAuthError.noPrivateKey
    }

    guard Data(base64Encoded: encrypted_token) != nil else {
      self.logger.error("Remote auth token is not valid base64")
      throw RemoteAuthError.invalidBase64
    }

    guard let decryptedData = self.rsaDecryptOAEPSHA256(encrypted_token) else {
      self.logger.error("Failed to decrypt remote auth token")
      throw RemoteAuthError.decryptionFailed(underlying: nil)
    }

    guard var tokenString = String(data: decryptedData, encoding: .utf8) else {
      self.logger.error("Decrypted token is not valid UTF-8")
      throw RemoteAuthError.decryptionFailed(underlying: nil)
    }
    tokenString = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)
    if tokenString.isEmpty {
      self.logger.error("Decrypted remote auth token is empty")
      throw RemoteAuthError.emptyToken
    }
    return Secret(tokenString)
  }

  // MARK: - Helpers for RSA and fingerprints
  private func generateRSAKeyPairIfNeeded() async {
    if self.privateKey != nil { return }
    let attributes: [CFString: Any] = [
      kSecAttrKeyType: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits: 2048,
    ]
    var error: Unmanaged<CFError>?
    guard let privKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
      let pubKey = SecKeyCopyPublicKey(privKey),
      let pkcs1Data = SecKeyCopyExternalRepresentation(pubKey, &error) as Data?
    else {
      self.logger.error("SecKey RSA key generation failed: \(String(describing: error?.takeRetainedValue()))")
      return
    }
    self.privateKey = privKey

    // Standard 24-byte ASN.1 DER SubjectPublicKeyInfo header for a 2048-bit RSA PKCS#1 public key
    let spkiHeader: [UInt8] = [
      0x30, 0x82, 0x01, 0x22,
      0x30, 0x0D,
      0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
      0x05, 0x00,
      0x03, 0x82, 0x01, 0x0F, 0x00,
    ]
    var spki = Data(spkiHeader)
    spki.append(pkcs1Data)
    self.encodedPublicKeySPKI = spki.base64EncodedString()
  }

  private func rsaDecryptOAEPSHA256(_ ciphertextBase64: String) -> Data? {
    guard let priv = self.privateKey else { return nil }
    guard let cipher = Data(base64Encoded: ciphertextBase64) else {
      self.logger.error("SecKey RSA decrypt: invalid base64 ciphertext")
      return nil
    }

    var error: Unmanaged<CFError>?
    guard
      let plain = SecKeyCreateDecryptedData(
        priv,
        .rsaEncryptionOAEPSHA256,
        cipher as CFData,
        &error
      ) as Data?
    else {
      self.logger.trace(
        "RSA decrypt attempt failed: \(String(describing: error?.takeRetainedValue()))"
      )
      return nil
    }
    return plain
  }

  enum RemoteAuthError: Error, Sendable {
    case noPrivateKey
    case invalidBase64
    case decryptionFailed(underlying: (any Error)?)
    case emptyToken
  }
}

extension RemoteAuthGatewayManager {
  func addEventsContinuation(
    _ continuation: AsyncStream<RemoteAuthPayload>.Continuation
  ) {
    self.eventsStreamContinuations.append(continuation)
  }

  func addEventsParseFailureContinuation(
    _ continuation: AsyncStream<(any Error, Data)>.Continuation
  ) {
    self.eventsParseFailureContinuations.append(continuation)
  }
}
