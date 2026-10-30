//
//  DaveSession.swift
//  PaicordLib
//
//  DAVE (Discord Audio & Video End-to-End Encryption) on top of libdave's C
//  API, which DaveKit builds and re-exports. DaveKit's own
//  `DaveSessionManager` is not used: it records the transition ID where the
//  protocol version belongs and has no failure budgets, so the protocol
//  handling lives here.
//
//  Protocol: https://daveprotocol.com and
//  https://docs.discord.food/topics/voice-connections#dave
//  Safeguards follow Serein's discord-voice crate.
//

@_implementationOnly import DaveKit
import DiscordCore
import DiscordModels
import Foundation
import Logging

/// What the voice gateway must send after DAVE handled an event.
package enum DaveOutbound: Sendable, Equatable {
  /// Opcode 26 (binary).
  case keyPackage(Data)
  /// Opcode 23.
  case transitionReady(transitionID: UInt16)
  /// Opcode 28 (binary).
  case commitWelcome(Data)
  /// Opcode 31.
  case invalidCommitWelcome(transitionID: UInt16)
}

package enum DaveError: Error, Equatable, CustomStringConvertible {
  case unsupportedProtocolVersion(UInt16)
  /// The server tried to turn end-to-end encryption off mid-call.
  case downgrade
  case recoveryBudgetExhausted
  case transitionBudgetExhausted
  case rosterTooLarge

  package var description: String {
    switch self {
    case .unsupportedProtocolVersion(let v): "unsupported DAVE protocol version \(v)"
    case .downgrade: "the voice server tried to disable end-to-end encryption"
    case .recoveryBudgetExhausted: "too many invalid DAVE groups"
    case .transitionBudgetExhausted: "too many DAVE transitions"
    case .rosterTooLarge: "too many participants"
    }
  }
}

/// Not thread-safe: owned and driven by `VoiceGatewayManager`'s actor.
package final class DaveSession: @unchecked Sendable {
  static let initTransitionID: UInt16 = 0
  static let newGroupEpoch: UInt32 = 1
  /// Serein's budgets.
  static let maxInvalidGroupRecoveries = 3
  static let maxTransitions = 1024
  static let maxParticipants = 64

  package static var maxSupportedProtocolVersion: UInt16 {
    daveMaxSupportedProtocolVersion()
  }

  private let selfUserID: String
  private let groupID: UInt64
  /// For one-to-one DMs: the only users that may ever join the group.
  private let allowedUserIDs: Set<String>?
  private let logger: Logger

  private let session: OpaquePointer
  private let encryptor: OpaquePointer
  private var decryptors: [String: OpaquePointer] = [:]

  /// The protocol version from Session Description (0 = no DAVE).
  package private(set) var protocolVersion: UInt16 = 0
  private var pendingTransitions: [UInt16: UInt16] = [:]
  private var hasGroup = false
  private var recoveries = 0
  private var transitions = 0

  package init(
    selfUserID: UserSnowflake,
    channelID: ChannelSnowflake,
    allowedUserIDs: Set<UserSnowflake>?,
    logger: Logger
  ) {
    Self.installLogSink
    self.selfUserID = selfUserID.rawValue
    self.groupID = UInt64(channelID.rawValue) ?? 0
    self.allowedUserIDs = allowedUserIDs.map { Set($0.map(\.rawValue)) }
    self.logger = logger
    self.session = daveSessionCreate(
      nil,
      nil,
      { source, reason, _ in
        // libdave's failure reasons carry no key material.
        let source = source.map { String(cString: $0) } ?? "?"
        let reason = reason.map { String(cString: $0) } ?? "?"
        DaveSession.libdaveLogger.warning("MLS failure in \(source): \(reason)")
      },
      nil
    )
    self.encryptor = daveEncryptorCreate()
    daveEncryptorSetPassthroughMode(encryptor, true)
  }

  deinit {
    for decryptor in decryptors.values { daveDecryptorDestroy(decryptor) }
    daveEncryptorDestroy(encryptor)
    daveSessionDestroy(session)
  }

  // MARK: Logging

  static let libdaveLogger = DiscordGlobalConfiguration.makeLogger("libdave")

  /// libdave's verbose and info output is dropped: only warnings and errors
  /// are forwarded, and those never contain keys.
  private static let installLogSink: Void = {
    daveSetLogSinkCallback { severity, _, _, message in
      guard let message else { return }
      switch severity {
      case .LOGGING_SEVERITY_ERROR:
        DaveSession.libdaveLogger.error("\(String(cString: message))")
      case .LOGGING_SEVERITY_WARNING:
        DaveSession.libdaveLogger.warning("\(String(cString: message))")
      default:
        break
      }
    }
  }()

  // MARK: State

  /// Whether outgoing media may be sent: either DAVE is off for this call,
  /// or the encryptor holds our key ratchet for the current epoch.
  package var isMediaReady: Bool {
    if protocolVersion == 0 { return true }
    return !daveEncryptorIsPassthroughMode(encryptor)
      && daveEncryptorHasKeyRatchet(encryptor)
  }

  package var participants: Set<String> { Set(decryptors.keys) }

  /// Whether a transition is prepared but not executed yet.
  var isTransitionPending: Bool { !pendingTransitions.isEmpty }

  // MARK: Roster

  /// Opcode 11. Users the voice server authenticated into the channel.
  package func addParticipants(_ userIDs: [UserSnowflake]) throws(DaveError) {
    for id in userIDs.map(\.rawValue) where id != selfUserID {
      guard decryptors[id] == nil else { continue }
      if let allowedUserIDs, !allowedUserIDs.contains(id) {
        logger.warning("Ignoring a participant outside this DM")
        continue
      }
      guard decryptors.count + 1 < Self.maxParticipants else {
        throw .rosterTooLarge
      }
      let decryptor = daveDecryptorCreate()!
      decryptors[id] = decryptor
      setupDecryptor(decryptor, userID: id, protocolVersion: protocolVersion)
    }
  }

  /// Opcode 13.
  func removeParticipant(_ userID: UserSnowflake) {
    if let decryptor = decryptors.removeValue(forKey: userID.rawValue) {
      daveDecryptorDestroy(decryptor)
    }
  }

  // MARK: Gateway events

  /// Session Description (opcode 4).
  package func selectProtocol(version: UInt16) throws(DaveError) -> [DaveOutbound] {
    if version > 0 {
      guard version <= Self.maxSupportedProtocolVersion else {
        throw .unsupportedProtocolVersion(version)
      }
      protocolVersion = version
      return try prepareEpoch(epoch: Self.newGroupEpoch, protocolVersion: version)
    }
    protocolVersion = 0
    _ = try prepareTransition(id: Self.initTransitionID, protocolVersion: 0)
    try executeTransition(id: Self.initTransitionID)
    return []
  }

  /// Opcode 21.
  package func prepareTransition(id: UInt16, protocolVersion version: UInt16)
    throws(DaveError) -> [DaveOutbound]
  {
    if version == 0, protocolVersion > 0 { throw .downgrade }
    transitions += 1
    guard transitions <= Self.maxTransitions else {
      throw .transitionBudgetExhausted
    }
    for (userID, decryptor) in decryptors {
      setupDecryptor(decryptor, userID: userID, protocolVersion: version)
    }
    if id == Self.initTransitionID {
      setupEncryptor(protocolVersion: version)
      return []
    }
    pendingTransitions[id] = version
    return [.transitionReady(transitionID: id)]
  }

  /// Opcode 22.
  func executeTransition(id: UInt16) throws(DaveError) {
    guard let version = pendingTransitions.removeValue(forKey: id) else {
      if id != Self.initTransitionID {
        logger.debug("Execute for an unknown DAVE transition", metadata: ["id": "\(id)"])
      }
      return
    }
    if version == 0 {
      if protocolVersion > 0 { throw .downgrade }
      daveSessionReset(session)
      hasGroup = false
    }
    setupEncryptor(protocolVersion: version)
  }

  /// Opcode 24, and the start of every new group.
  func prepareEpoch(epoch: UInt32, protocolVersion version: UInt16)
    throws(DaveError) -> [DaveOutbound]
  {
    guard epoch == Self.newGroupEpoch else { return [] }
    if version == 0, protocolVersion > 0 { throw .downgrade }
    guard version <= Self.maxSupportedProtocolVersion else {
      throw .unsupportedProtocolVersion(version)
    }
    protocolVersion = version
    daveSessionInit(session, version, groupID, selfUserID)
    hasGroup = true
    // A new group starts without our ratchet; stop sending until the
    // transition that follows the commit/welcome completes.
    daveEncryptorSetPassthroughMode(encryptor, false)
    return [.keyPackage(keyPackage())]
  }

  /// Opcode 25 (binary).
  func setExternalSender(_ data: Data) {
    guard !data.isEmpty else { return }
    data.withUnsafeBytes { raw in
      daveSessionSetExternalSender(
        session,
        raw.bindMemory(to: UInt8.self).baseAddress,
        raw.count
      )
    }
  }

  /// Opcode 27 (binary). libdave itself checks the group ID, that proposals
  /// come from the external sender, are Add or Remove only, and only add
  /// recognised users; recognised means announced through opcode 11.
  package func processProposals(_ data: Data) -> [DaveOutbound] {
    // Proposals before a local group exists are ignored, as the initial
    // group procedure requires.
    guard hasGroup, protocolVersion > 0, !data.isEmpty else { return [] }
    var output: UnsafeMutablePointer<UInt8>?
    var length = 0
    withRecognizedUserIDs { ids, count in
      data.withUnsafeBytes { raw in
        daveSessionProcessProposals(
          session,
          raw.bindMemory(to: UInt8.self).baseAddress,
          raw.count,
          ids,
          count,
          &output,
          &length
        )
      }
    }
    guard let output else { return [] }
    defer { daveFree(output) }
    guard length > 0 else { return [] }
    return [.commitWelcome(Data(bytes: output, count: length))]
  }

  /// Opcode 29 (binary).
  func processCommit(transitionID: UInt16, commit: Data) throws(DaveError)
    -> [DaveOutbound]
  {
    guard hasGroup, !commit.isEmpty else {
      return try recoverInvalidGroup(transitionID: transitionID)
    }
    let result = commit.withUnsafeBytes { raw in
      daveSessionProcessCommit(
        session,
        raw.bindMemory(to: UInt8.self).baseAddress,
        raw.count
      )
    }
    guard let result else {
      return try recoverInvalidGroup(transitionID: transitionID)
    }
    defer { daveCommitResultDestroy(result) }
    if daveCommitResultIsFailed(result) {
      return try recoverInvalidGroup(transitionID: transitionID)
    }
    if daveCommitResultIsIgnored(result) { return [] }
    return try prepareTransition(
      id: transitionID,
      protocolVersion: daveSessionGetProtocolVersion(session)
    )
  }

  /// Opcode 30 (binary).
  func processWelcome(transitionID: UInt16, welcome: Data) throws(DaveError)
    -> [DaveOutbound]
  {
    guard hasGroup, !welcome.isEmpty else {
      return try recoverInvalidGroup(transitionID: transitionID)
    }
    let result = withRecognizedUserIDs { ids, count in
      welcome.withUnsafeBytes { raw in
        daveSessionProcessWelcome(
          session,
          raw.bindMemory(to: UInt8.self).baseAddress,
          raw.count,
          ids,
          count
        )
      }
    }
    guard let result else {
      return try recoverInvalidGroup(transitionID: transitionID)
    }
    daveWelcomeResultDestroy(result)
    return try prepareTransition(
      id: transitionID,
      protocolVersion: daveSessionGetProtocolVersion(session)
    )
  }

  // MARK: Media

  package enum MediaError: Error {
    case notReady
    case failed(Int)
  }

  package func encrypt(ssrc: UInt32, opus frame: Data) throws(MediaError) -> Data {
    if protocolVersion == 0 { return frame }
    guard isMediaReady else { throw .notReady }
    let capacity = daveEncryptorGetMaxCiphertextByteSize(
      encryptor,
      .audio,
      frame.count
    )
    var output = Data(count: max(capacity, frame.count + 64))
    var written = 0
    let result = output.withUnsafeMutableBytes { out in
      frame.withUnsafeBytes { input in
        daveEncryptorEncrypt(
          encryptor,
          .audio,
          ssrc,
          input.bindMemory(to: UInt8.self).baseAddress,
          input.count,
          out.bindMemory(to: UInt8.self).baseAddress,
          out.count,
          &written
        )
      }
    }
    guard result == DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS, written <= output.count
    else { throw .failed(Int(result.rawValue)) }
    output.removeSubrange(written...)
    return output
  }

  func decrypt(userID: UserSnowflake, frame: Data) throws(MediaError) -> Data {
    guard let decryptor = decryptors[userID.rawValue] else {
      // Media from someone the voice server never announced.
      throw .notReady
    }
    let capacity = daveDecryptorGetMaxPlaintextByteSize(
      decryptor,
      .audio,
      frame.count
    )
    var output = Data(count: max(capacity, frame.count))
    var written = 0
    let result = output.withUnsafeMutableBytes { out in
      frame.withUnsafeBytes { input in
        daveDecryptorDecrypt(
          decryptor,
          .audio,
          input.bindMemory(to: UInt8.self).baseAddress,
          input.count,
          out.bindMemory(to: UInt8.self).baseAddress,
          out.count,
          &written
        )
      }
    }
    guard result == DAVE_DECRYPTOR_RESULT_CODE_SUCCESS, written <= output.count
    else { throw .failed(Int(result.rawValue)) }
    output.removeSubrange(written...)
    return output
  }

  func assign(ssrc: UInt32) {
    daveEncryptorAssignSsrcToCodec(encryptor, ssrc, .opus)
  }

  // MARK: Private

  private func recoverInvalidGroup(transitionID: UInt16) throws(DaveError)
    -> [DaveOutbound]
  {
    recoveries += 1
    logger.warning(
      "Invalid DAVE commit or welcome; recreating the group",
      metadata: ["attempt": "\(recoveries)"]
    )
    guard recoveries <= Self.maxInvalidGroupRecoveries else {
      throw .recoveryBudgetExhausted
    }
    var output: [DaveOutbound] = [
      .invalidCommitWelcome(transitionID: transitionID)
    ]
    output += try prepareEpoch(
      epoch: Self.newGroupEpoch,
      protocolVersion: max(protocolVersion, 1)
    )
    return output
  }

  private func keyPackage() -> Data {
    var bytes: UnsafeMutablePointer<UInt8>?
    var length = 0
    daveSessionGetMarshalledKeyPackage(session, &bytes, &length)
    guard let bytes else { return Data() }
    defer { daveFree(bytes) }
    return Data(bytes: bytes, count: length)
  }

  private func setupEncryptor(protocolVersion version: UInt16) {
    if version == 0 {
      daveEncryptorSetPassthroughMode(encryptor, true)
      return
    }
    daveEncryptorSetPassthroughMode(encryptor, false)
    if let ratchet = daveSessionGetKeyRatchet(session, selfUserID) {
      daveEncryptorSetKeyRatchet(encryptor, ratchet)
      daveKeyRatchetDestroy(ratchet)
    }
  }

  private func setupDecryptor(
    _ decryptor: OpaquePointer,
    userID: String,
    protocolVersion version: UInt16
  ) {
    if version == 0 {
      daveDecryptorTransitionToPassthroughMode(decryptor, true)
      return
    }
    daveDecryptorTransitionToPassthroughMode(decryptor, false)
    if let ratchet = daveSessionGetKeyRatchet(session, userID) {
      daveDecryptorTransitionToKeyRatchet(decryptor, ratchet)
      daveKeyRatchetDestroy(ratchet)
    }
  }

  /// Calls `body` with a C array of every recognised user ID, ourselves
  /// included.
  private func withRecognizedUserIDs<R>(
    _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>?, Int) -> R
  ) -> R {
    let ids = Array(decryptors.keys) + [selfUserID]
    var pointers: [UnsafePointer<CChar>?] = ids.map { UnsafePointer(strdup($0)) }
    defer { pointers.forEach { free(UnsafeMutablePointer(mutating: $0)) } }
    return pointers.withUnsafeMutableBufferPointer {
      body($0.baseAddress, $0.count)
    }
  }
}
