import DiscordModels
import DiscordVoice
import Foundation
import Logging
import XCTest

class VoiceConnectionTests: XCTestCase {
  func testEndpointValidation() {
    for good in [
      "c-fra12-1a2b3c4d.discord.media:2096", "wss://voice-1.discord.media",
      "c-waw01.discord.media",
    ] {
      XCTAssertNotNil(VoiceGatewayManager.validatedURL(endpoint: good), good)
    }
    XCTAssertEqual(
      VoiceGatewayManager.validatedURL(endpoint: "c-fra12.discord.media:2096")?.absoluteString,
      "wss://c-fra12.discord.media:2096/?v=8"
    )
    for bad in [
      "", "discord.media", ".discord.media", "voice.discord.media.evil.test",
      "voice.discord.media/path", "token@voice.discord.media",
      "voice.discord.media?token=x", "evil.test", "voice.discord.com",
    ] {
      XCTAssertNil(VoiceGatewayManager.validatedURL(endpoint: bad), bad)
    }
  }

  func testOnlyPublicUDPAddresses() {
    for good in ["66.22.231.190", "35.214.1.1", "2606:4700::6810:84e5"] {
      XCTAssertTrue(VoiceUDPConnection.isPublicAddress(good), good)
    }
    for bad in [
      "127.0.0.1", "10.0.0.1", "192.168.1.10", "172.16.4.4", "169.254.1.1",
      "100.64.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "::1",
      "fe80::1", "fd00::1", "::ffff:192.168.0.1", "voice.discord.media",
      "198.51.100.3", "203.0.113.9",
    ] {
      XCTAssertFalse(VoiceUDPConnection.isPublicAddress(bad), bad)
    }
  }

  func testOpusRoundTripAndConcealment() throws {
    let encoder = try OpusEncoder()
    let decoder = try OpusDecoder()
    var tone = [Float](repeating: 0, count: VoiceAudioFormat.frameSamples)
    for i in tone.indices { tone[i] = 0.3 * sin(Float(i) * 2 * .pi * 440 / 48_000) }
    var last: [Float] = []
    for _ in 0..<5 {
      let packet = try tone.withUnsafeBufferPointer { try encoder.encode($0) }
      XCTAssertLessThanOrEqual(packet.count, 1275)
      last = try decoder.decode(packet)
      XCTAssertEqual(last.count, VoiceAudioFormat.frameSamples)
    }
    XCTAssertGreaterThan(last.map(abs).max() ?? 0, 0.05)
    XCTAssertEqual(decoder.conceal().count, VoiceAudioFormat.frameSamples)
    XCTAssertEqual(
      try decoder.decode(VoiceAudioFormat.silenceFrame).count,
      VoiceAudioFormat.frameSamples
    )
  }

  func testDaveGroupStartsClosed() throws {
    XCTAssertGreaterThanOrEqual(DaveSession.maxSupportedProtocolVersion, 1)
    let session = DaveSession(
      selfUserID: "100000000000000001",
      channelID: "200000000000000002",
      allowedUserIDs: ["100000000000000003"],
      logger: Logger(label: "test")
    )
    // DAVE call: a key package goes out and no media until a transition.
    let outbound = try session.selectProtocol(version: 1)
    guard case .keyPackage(let package) = outbound.first else {
      return XCTFail("expected a key package, got \(outbound)")
    }
    XCTAssertGreaterThan(package.count, 64)
    XCTAssertFalse(session.isMediaReady)
    XCTAssertThrowsError(try session.encrypt(ssrc: 1, opus: Data([1, 2, 3])))
    // Proposals before an external sender exist produce nothing.
    XCTAssertEqual(session.processProposals(Data([0, 1, 2])), [])
    // Turning DAVE off mid-call is refused.
    XCTAssertThrowsError(try session.prepareTransition(id: 5, protocolVersion: 0)) {
      XCTAssertEqual($0 as? DaveError, .downgrade)
    }
    // A one-to-one DM only admits its peer.
    try session.addParticipants(["100000000000000003", "100000000000000009"])
    XCTAssertEqual(session.participants, ["100000000000000003"])
  }

  func testNoDaveCallIsPassthrough() throws {
    let session = DaveSession(
      selfUserID: "1",
      channelID: "2",
      allowedUserIDs: nil,
      logger: Logger(label: "test")
    )
    XCTAssertEqual(try session.selectProtocol(version: 0), [])
    XCTAssertTrue(session.isMediaReady)
    XCTAssertEqual(try session.encrypt(ssrc: 1, opus: Data([1, 2, 3])), Data([1, 2, 3]))
  }
}
