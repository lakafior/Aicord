import DiscordModels
import Foundation
import XCTest

import DiscordVoice

/// Vectors were produced independently of this code with OpenSSL (through
/// Python's `cryptography`): AES-GCM and ChaCha20-Poly1305 from OpenSSL, the
/// HChaCha20 subkey from OpenSSL's raw ChaCha20 block minus the input state.
/// The HChaCha20 vector itself is draft-irtf-cfrg-xchacha-03 §2.2.1.
class VoiceTransportCipherTests: XCTestCase {
  let key = hex(
    "8c3f6b1e0d9a2b47c5e1f0a39d8e7b6a5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f"
  )
  let opus = Data([0xF8, 0xFF, 0xFE]) + Data("hello opus".utf8)

  let vectors: [(TransportCipher.Mode, extension: Bool, packet: String)] = [
    (
      .aes256GCM, false,
      "807812340000abcd00c0ffee74b9f6b781817b17ddf89af901424ec884665becb3328038e7a61858af00000007"
    ),
    (
      .aes256GCM, true,
      "907812340000abcd00c0ffeebede00019cb908df1c12e91098fb86e3520c23b99c2bbfa2e7daea89888b843bc3af2ccf4900000007"
    ),
    (
      .xchacha20Poly1305, false,
      "807812340000abcd00c0ffee215bff316b84d3fb31384df72cfcce5f14fd1885cc63fd38b63e22020d00000007"
    ),
    (
      .xchacha20Poly1305, true,
      "907812340000abcd00c0ffeebede0001c95b0159f61741fc743b51ed7f72fd7281600dcc4c386e12ee9629153aa96d541800000007"
    ),
  ]

  func testHChaCha20DraftVector() {
    let subkey = HChaCha20.derive(
      key: Array(0..<32),
      nonce: [UInt8](hex("000000090000004a0000000031415927"))
    )
    XCTAssertEqual(
      Data(subkey),
      hex("82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc")
    )
  }

  func testOpenVectors() throws {
    for (mode, hasExtension, packet) in vectors {
      let cipher = try TransportCipher(mode: mode, secretKey: [UInt8](key))
      let opened = try cipher.open(hex(packet))
      XCTAssertEqual(opened.payload, opus, "\(mode) ext=\(hasExtension)")
      XCTAssertEqual(opened.sequence, 0x1234)
      XCTAssertEqual(opened.timestamp, 0xABCD)
      XCTAssertEqual(opened.ssrc, 0x00C0_FFEE)
      XCTAssertEqual(opened.payloadType, .dynamic(120))
      XCTAssertEqual(opened.extension, hasExtension)
    }
  }

  func testSealMatchesVectors() throws {
    for (mode, hasExtension, packet) in vectors where !hasExtension {
      let cipher = try TransportCipher(mode: mode, secretKey: [UInt8](key))
      let rtp = RTPPacket(
        payloadType: .dynamic(120),
        sequence: 0x1234,
        timestamp: 0xABCD,
        ssrc: 0x00C0_FFEE,
        payload: opus
      )
      XCTAssertEqual(try cipher.seal(rtp, nonce: 7), hex(packet), "\(mode)")
    }
  }

  func testTamperingAndTruncationAreRejected() throws {
    for (mode, _, packet) in vectors {
      let cipher = try TransportCipher(mode: mode, secretKey: [UInt8](key))
      let original = hex(packet)
      // Header (associated data), ciphertext, tag and nonce each matter.
      for index in [1, 13, original.count - 6, original.count - 1] {
        var tampered = original
        tampered[index] ^= 0x01
        XCTAssertThrowsError(try cipher.open(tampered), "\(mode) byte \(index)")
      }
      XCTAssertThrowsError(try cipher.open(original.prefix(30)))
      XCTAssertThrowsError(try cipher.open(Data(count: 8)))
    }
    XCTAssertThrowsError(
      try TransportCipher(mode: .aes256GCM, secretKey: [1, 2, 3])
    )
  }

  func testNegotiationPrefersAES() {
    XCTAssertEqual(
      TransportCipher.Mode.negotiate(offered: [
        .aead_xchacha20_poly1305_rtpsize, .aead_aes256_gcm_rtpsize,
      ]),
      .aes256GCM
    )
    XCTAssertEqual(
      TransportCipher.Mode.negotiate(offered: [
        .xsalsa20_poly1305, .aead_xchacha20_poly1305_rtpsize,
      ]),
      .xchacha20Poly1305
    )
    XCTAssertNil(
      TransportCipher.Mode.negotiate(offered: [.xsalsa20_poly1305_lite])
    )
  }

  func testRTPRoundTrip() throws {
    var packet = RTPPacket(
      payloadType: .dynamic(120),
      sequence: 65535,
      timestamp: .max,
      ssrc: 42,
      payload: Data([1, 2, 3]),
      marker: true
    )
    packet.csrcs = [7, 8]
    let parsed = try XCTUnwrap(RTPPacket(rawValue: packet.rawValue))
    XCTAssertEqual(parsed, packet)
    XCTAssertEqual(parsed.headerSize, 20)
    XCTAssertNil(RTPPacket(rawValue: Data([0x80, 0x78, 0])))
    XCTAssertTrue(RTPPacket.isRTCP(Data([0x81, 0xC9, 0, 7])))
    XCTAssertFalse(RTPPacket.isRTCP(packet.rawValue))
  }
}

private func hex(_ string: String) -> Data {
  var data = Data()
  var index = string.startIndex
  while index < string.endIndex {
    let next = string.index(index, offsetBy: 2)
    data.append(UInt8(string[index..<next], radix: 16)!)
    index = next
  }
  return data
}
