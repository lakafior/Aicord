//
//  VoiceUDPConnection.swift
//  PaicordLib
//
//  The voice media socket on Network.framework.
//

import Foundation
import Network

/// One UDP flow to the voice server announced in Ready.
package final class VoiceUDPConnection: @unchecked Sendable {
  enum Error: Swift.Error, Equatable {
    case addressNotAllowed(String)
    case discoveryTimedOut
    case discoveryMalformed
    case connectionFailed(String)
  }

  /// Datagrams larger than this are dropped (Serein's receive budget).
  static let maxDatagramSize = 4096
  static let keepaliveInterval: Duration = .seconds(5)

  private let connection: NWConnection
  private let queue = DispatchQueue(label: "paicord.voice.udp", qos: .userInteractive)
  private let lock = NSLock()
  private var discoveryContinuation: CheckedContinuation<(String, UInt16), any Swift.Error>?
  private var datagramContinuation: AsyncStream<Data>.Continuation?

  /// Every datagram that is not an IP discovery reply.
  let datagrams: AsyncStream<Data>

  init(host: String, port: UInt16) throws(Error) {
    guard Self.isPublicAddress(host), port != 0 else {
      throw .addressNotAllowed(host)
    }
    let parameters = NWParameters.udp
    parameters.serviceClass = .interactiveVoice
    self.connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: NWEndpoint.Port(rawValue: port)!,
      using: parameters
    )
    var continuation: AsyncStream<Data>.Continuation!
    self.datagrams = AsyncStream(bufferingPolicy: .bufferingNewest(64)) {
      continuation = $0
    }
    self.datagramContinuation = continuation
  }

  /// Opens the flow and waits until it is ready.
  func start() async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Swift.Error>) in
      let resumed = LockedFlag()
      connection.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          if resumed.set() { continuation.resume() }
        case .failed(let error):
          if resumed.set() {
            continuation.resume(throwing: Error.connectionFailed("\(error)"))
          }
          self?.finish()
        case .cancelled:
          if resumed.set() {
            continuation.resume(throwing: Error.connectionFailed("cancelled"))
          }
          self?.finish()
        default:
          break
        }
      }
      connection.start(queue: queue)
    }
    receiveLoop()
  }

  func cancel() {
    connection.cancel()
    finish()
  }

  private func finish() {
    lock.lock()
    let datagram = datagramContinuation
    datagramContinuation = nil
    let discovery = discoveryContinuation
    discoveryContinuation = nil
    lock.unlock()
    datagram?.finish()
    discovery?.resume(throwing: Error.connectionFailed("closed"))
  }

  private func receiveLoop() {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self else { return }
      if let data, !data.isEmpty, data.count <= Self.maxDatagramSize {
        self.handle(data)
      }
      if error == nil { self.receiveLoop() }
    }
  }

  private func handle(_ data: Data) {
    // IP discovery response: type 0x0002, length 70.
    if data.count == 74, data[data.startIndex] == 0, data[data.startIndex + 1] == 2 {
      lock.lock()
      let continuation = discoveryContinuation
      discoveryContinuation = nil
      lock.unlock()
      guard let continuation else { return }
      let bytes = [UInt8](data)
      let addressBytes = bytes[8..<72].prefix { $0 != 0 }
      let port = UInt16(bytes[72]) << 8 | UInt16(bytes[73])
      if let address = String(bytes: addressBytes, encoding: .utf8),
        !address.isEmpty, port != 0
      {
        continuation.resume(returning: (address, port))
      } else {
        continuation.resume(throwing: Error.discoveryMalformed)
      }
      return
    }
    lock.lock()
    let continuation = datagramContinuation
    lock.unlock()
    continuation?.yield(data)
  }

  func send(_ data: Data) {
    connection.send(content: data, completion: .idempotent)
  }

  /// https://docs.discord.food/topics/voice-connections#ip-discovery
  /// Asks the voice server which public address and port it sees, which
  /// also opens the NAT mapping. Times out after `timeout`.
  func discoverExternalAddress(ssrc: UInt32, timeout: Duration) async throws
    -> (address: String, port: UInt16)
  {
    var request = Data([0x00, 0x01, 0x00, 70])
    request.append(contentsOf: [
      UInt8(ssrc >> 24), UInt8((ssrc >> 16) & 0xFF), UInt8((ssrc >> 8) & 0xFF),
      UInt8(ssrc & 0xFF),
    ])
    request.append(Data(count: 66))
    let discoveryRequest = request

    let timeoutTask = Task { [weak self] in
      try await Task.sleep(for: timeout)
      self?.takeDiscoveryContinuation()?.resume(throwing: Error.discoveryTimedOut)
    }
    defer { timeoutTask.cancel() }

    let (address, port) = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<(String, UInt16), any Swift.Error>) in
      setDiscoveryContinuation(continuation)
      // Resend a couple of times in case the first datagram is lost.
      send(discoveryRequest)
      queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.send(discoveryRequest) }
      queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.send(discoveryRequest) }
    }
    return (address, port)
  }

  private func setDiscoveryContinuation(
    _ continuation: CheckedContinuation<(String, UInt16), any Swift.Error>
  ) {
    lock.withLock { discoveryContinuation = continuation }
  }

  private func takeDiscoveryContinuation()
    -> CheckedContinuation<(String, UInt16), any Swift.Error>?
  {
    lock.withLock {
      defer { discoveryContinuation = nil }
      return discoveryContinuation
    }
  }

  /// Keeps the NAT mapping open while no audio is flowing.
  func keepalive() async {
    var counter: UInt32 = 0
    while !Task.isCancelled {
      var packet = Data([0x13, 0x37, 0xCA, 0xFE])
      packet.append(contentsOf: withUnsafeBytes(of: counter.littleEndian) { Array($0) })
      send(packet)
      counter &+= 1
      try? await Task.sleep(for: Self.keepaliveInterval)
    }
  }

  /// Only public unicast IPv4/IPv6 literals are accepted. The voice server
  /// never needs to send us to a private, loopback or link-local address, so
  /// a Ready that does is treated as hostile.
  package static func isPublicAddress(_ host: String) -> Bool {
    if let v4 = IPv4Address(host) {
      let b = [UInt8](v4.rawValue)
      switch (b[0], b[1]) {
      case (0, _), (10, _), (127, _), (169, 254), (255, _): return false
      case (100, 64...127): return false  // CGNAT
      case (172, 16...31), (192, 168): return false
      case (192, 0) where b[2] == 0 || b[2] == 2: return false
      case (198, 18...19): return false
      case (198, 51) where b[2] == 100: return false
      case (203, 0) where b[2] == 113: return false
      case (224...239, _), (240...254, _): return false
      default: return true
      }
    }
    if let v6 = IPv6Address(host) {
      if v6.isLoopback || v6.isLinkLocal || v6.isMulticast || v6.isAny {
        return false
      }
      let b = [UInt8](v6.rawValue)
      if b[0] & 0xFE == 0xFC { return false }  // unique local
      if v6.asIPv4 != nil { return isPublicAddress("\(v6.asIPv4!)") }
      if b[0] == 0x20, b[1] == 0x01, b[2] == 0x0D, b[3] == 0xB8 { return false }
      return true
    }
    // Host names are not accepted: Ready always carries an IP literal.
    return false
  }
}

/// A one-shot flag safe to touch from Network.framework callbacks.
final class LockedFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  /// Returns true the first time only.
  func set() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if value { return false }
    value = true
    return true
  }
}
