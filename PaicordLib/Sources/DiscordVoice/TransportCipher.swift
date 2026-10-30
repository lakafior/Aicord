//
//  TransportCipher.swift
//  PaicordLib
//
//  Transport encryption for Discord voice RTP packets: the two `*_rtpsize`
//  AEAD modes, implemented on CryptoKit only.
//
//  Packet layout (https://docs.discord.food/topics/voice-connections#transport-encryption-modes):
//
//    | RTP header + CSRCs | ext header (4 B)? | ciphertext | tag (16 B) | nonce (4 B) |
//    |<-------- associated data ------------>|
//
//  The 4 nonce bytes are a big-endian counter; the full nonce is that
//  counter followed by zeros (12 bytes for AES-GCM, 24 for XChaCha20).
//

import CryptoKit
import DiscordModels
import Foundation

public struct TransportCipher: Sendable {
  public enum Mode: Sendable, Equatable {
    case aes256GCM
    case xchacha20Poly1305

    /// In order of preference. AES-GCM first (hardware accelerated), XChaCha
    /// as the mode Discord requires every server to offer.
    public static let preferred: [Mode] = [.aes256GCM, .xchacha20Poly1305]

    public init?(_ mode: VoiceGateway.EncryptionMode) {
      switch mode {
      case .aead_aes256_gcm_rtpsize: self = .aes256GCM
      case .aead_xchacha20_poly1305_rtpsize: self = .xchacha20Poly1305
      default: return nil
      }
    }

    public var encryptionMode: VoiceGateway.EncryptionMode {
      switch self {
      case .aes256GCM: return .aead_aes256_gcm_rtpsize
      case .xchacha20Poly1305: return .aead_xchacha20_poly1305_rtpsize
      }
    }

    /// The best mode both sides support.
    public static func negotiate(
      offered: [VoiceGateway.EncryptionMode]
    ) -> Mode? {
      preferred.first { offered.contains($0.encryptionMode) }
    }
  }

  public enum Error: Swift.Error, Equatable {
    case invalidKey
    case truncatedPacket
    case authenticationFailed
    /// The 32-bit nonce counter is used up; the session must be renegotiated.
    case nonceExhausted
  }

  static let tagSize = 16
  static let nonceSuffixSize = 4

  public let mode: Mode
  private let key: SymmetricKey

  public init(mode: Mode, secretKey: [UInt8]) throws(Error) {
    guard secretKey.count == 32 else { throw .invalidKey }
    self.mode = mode
    self.key = SymmetricKey(data: secretKey)
  }

  /// Encrypts an RTP packet. `packet.payload` holds the cleartext Opus frame
  /// (already DAVE-encrypted, if DAVE is active); no header extension is sent.
  public func seal(_ packet: RTPPacket, nonce counter: UInt32) throws(Error)
    -> Data
  {
    let aad = packet.header
    let suffix = Self.counterBytes(counter)
    let (ciphertext, tag): (Data, Data)
    do {
      switch mode {
      case .aes256GCM:
        let box = try AES.GCM.seal(
          packet.payload,
          using: key,
          nonce: AES.GCM.Nonce(data: suffix + Data(count: 8)),
          authenticating: aad
        )
        (ciphertext, tag) = (box.ciphertext, box.tag)
      case .xchacha20Poly1305:
        let (subkey, nonce) = Self.xchachaParameters(
          key: key,
          nonce24: suffix + Data(count: 20)
        )
        let box = try ChaChaPoly.seal(
          packet.payload,
          using: subkey,
          nonce: nonce,
          authenticating: aad
        )
        (ciphertext, tag) = (box.ciphertext, box.tag)
      }
    } catch {
      throw .authenticationFailed
    }
    return aad + ciphertext + tag + suffix
  }

  /// Decrypts a received datagram. The returned packet's payload is the
  /// decrypted Opus frame with the header extension body (if any) removed.
  public func open(_ datagram: Data) throws(Error) -> RTPPacket {
    guard var packet = RTPPacket(rawValue: datagram) else {
      throw .truncatedPacket
    }
    let bytes = [UInt8](datagram)
    var aadEnd = packet.headerSize
    var extensionWords = 0
    if packet.extension {
      // Only the 4-byte extension header is in the clear.
      guard bytes.count >= aadEnd + 4 else { throw .truncatedPacket }
      extensionWords = Int(bytes[aadEnd + 2]) << 8 | Int(bytes[aadEnd + 3])
      aadEnd += 4
    }
    let trailer = Self.tagSize + Self.nonceSuffixSize
    guard bytes.count >= aadEnd + trailer else { throw .truncatedPacket }

    let aad = Data(bytes[..<aadEnd])
    let ciphertextEnd = bytes.count - trailer
    let ciphertext = Data(bytes[aadEnd..<ciphertextEnd])
    let tag = Data(bytes[ciphertextEnd..<(ciphertextEnd + Self.tagSize)])
    let suffix = Data(bytes[(bytes.count - Self.nonceSuffixSize)...])

    var plaintext: Data
    do {
      switch mode {
      case .aes256GCM:
        let box = try AES.GCM.SealedBox(
          nonce: AES.GCM.Nonce(data: suffix + Data(count: 8)),
          ciphertext: ciphertext,
          tag: tag
        )
        plaintext = try AES.GCM.open(box, using: key, authenticating: aad)
      case .xchacha20Poly1305:
        let (subkey, nonce) = Self.xchachaParameters(
          key: key,
          nonce24: suffix + Data(count: 20)
        )
        let box = try ChaChaPoly.SealedBox(
          nonce: nonce,
          ciphertext: ciphertext,
          tag: tag
        )
        plaintext = try ChaChaPoly.open(box, using: subkey, authenticating: aad)
      }
    } catch {
      throw .authenticationFailed
    }

    let extensionBytes = extensionWords * 4
    guard plaintext.count >= extensionBytes else { throw .truncatedPacket }
    plaintext.removeFirst(extensionBytes)
    if packet.padding, let count = plaintext.last {
      guard Int(count) <= plaintext.count else { throw .truncatedPacket }
      plaintext.removeLast(Int(count))
    }
    packet.payload = plaintext
    return packet
  }

  static func counterBytes(_ counter: UInt32) -> Data {
    Data([
      UInt8(counter >> 24), UInt8((counter >> 16) & 0xFF),
      UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF),
    ])
  }

  /// XChaCha20-Poly1305 = ChaCha20-Poly1305 keyed with HChaCha20(key, nonce[0..<16])
  /// and nonce `0x00000000 || nonce[16..<24]`.
  /// https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.3
  static func xchachaParameters(key: SymmetricKey, nonce24: Data) -> (
    SymmetricKey, ChaChaPoly.Nonce
  ) {
    let keyBytes = key.withUnsafeBytes { [UInt8]($0) }
    let subkey = HChaCha20.derive(key: keyBytes, nonce: [UInt8](nonce24.prefix(16)))
    // 12 bytes is always a valid ChaChaPoly nonce.
    let nonce = try! ChaChaPoly.Nonce(data: Data(count: 4) + nonce24.suffix(8))
    return (SymmetricKey(data: subkey), nonce)
  }
}

/// The HChaCha20 key derivation function.
/// https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.2
package enum HChaCha20 {
  package static func derive(key: [UInt8], nonce: [UInt8]) -> [UInt8] {
    precondition(key.count == 32 && nonce.count == 16)
    func word(_ b: [UInt8], _ i: Int) -> UInt32 {
      UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16
        | UInt32(b[i + 3]) << 24
    }
    var s: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]
    for i in 0..<8 { s.append(word(key, i * 4)) }
    for i in 0..<4 { s.append(word(nonce, i * 4)) }

    func quarterRound(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
      s[a] &+= s[b]; s[d] ^= s[a]; s[d] = s[d] << 16 | s[d] >> 16
      s[c] &+= s[d]; s[b] ^= s[c]; s[b] = s[b] << 12 | s[b] >> 20
      s[a] &+= s[b]; s[d] ^= s[a]; s[d] = s[d] << 8 | s[d] >> 24
      s[c] &+= s[d]; s[b] ^= s[c]; s[b] = s[b] << 7 | s[b] >> 25
    }
    for _ in 0..<10 {
      quarterRound(0, 4, 8, 12)
      quarterRound(1, 5, 9, 13)
      quarterRound(2, 6, 10, 14)
      quarterRound(3, 7, 11, 15)
      quarterRound(0, 5, 10, 15)
      quarterRound(1, 6, 11, 12)
      quarterRound(2, 7, 8, 13)
      quarterRound(3, 4, 9, 14)
    }
    var out: [UInt8] = []
    out.reserveCapacity(32)
    for w in [s[0], s[1], s[2], s[3], s[12], s[13], s[14], s[15]] {
      out += [UInt8(w & 0xFF), UInt8((w >> 8) & 0xFF), UInt8((w >> 16) & 0xFF), UInt8(w >> 24)]
    }
    return out
  }
}
