/// Adapted from https://github.com/SwiftDiscordAudio/DiscordAudioKit/blob/main/Sources/DiscordRTP/RTP.swift

import Foundation

/// A Real-time Transport Protocol packet.
/// https://datatracker.ietf.org/doc/html/rfc3550#section-5.1
/// https://docs.discord.food/topics/voice-connections#rtp-packet-structure
///
/// Discord voice packets always use version 2 and the Opus payload type 120.
/// With the `*_rtpsize` encryption modes the header, the CSRC list and the
/// 4-byte extension header stay in the clear (they are the AEAD's associated
/// data); the extension body and the payload are encrypted.
public struct RTPPacket: Sendable, Equatable {
  /// 2 bits.
  public var version: UInt8
  /// The packet ends with padding octets, the last one holding their count.
  public var padding: Bool
  /// A header extension follows the CSRC list.
  public var `extension`: Bool
  public var marker: Bool
  /// 7 bits.
  public var payloadType: RTPType
  public var sequence: UInt16
  public var timestamp: UInt32
  public var ssrc: UInt32
  /// 0 to 15 contributing sources.
  public var csrcs: [UInt32]
  /// Everything after the CSRC list, including the extension header if any.
  public var payload: Data

  /// Size of the fixed header without CSRCs.
  public static let fixedHeaderSize = 12

  public init(
    extension: Bool = false,
    payloadType: RTPType,
    sequence: UInt16,
    timestamp: UInt32,
    ssrc: UInt32,
    payload: Data,
    marker: Bool = false
  ) {
    self.version = 2
    self.padding = false
    self.extension = `extension`
    self.marker = marker
    self.payloadType = payloadType
    self.sequence = sequence
    self.timestamp = timestamp
    self.ssrc = ssrc
    self.csrcs = []
    self.payload = payload
  }

  public init?(rawValue: Data) {
    let bytes = [UInt8](rawValue)
    guard bytes.count >= Self.fixedHeaderSize else { return nil }
    self.version = (bytes[0] & 0b1100_0000) >> 6
    self.padding = (bytes[0] & 0b0010_0000) != 0
    self.extension = (bytes[0] & 0b0001_0000) != 0
    let csrcCount = Int(bytes[0] & 0b0000_1111)
    guard version == 2,
      let type = RTPType(rawValue: bytes[1] & 0b0111_1111)
    else { return nil }
    self.marker = (bytes[1] & 0b1000_0000) != 0
    self.payloadType = type
    self.sequence = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
    self.timestamp = Self.readUInt32(bytes, at: 4)
    self.ssrc = Self.readUInt32(bytes, at: 8)
    let headerEnd = Self.fixedHeaderSize + csrcCount * 4
    guard bytes.count >= headerEnd else { return nil }
    self.csrcs = (0..<csrcCount).map {
      Self.readUInt32(bytes, at: Self.fixedHeaderSize + $0 * 4)
    }
    self.payload = Data(bytes[headerEnd...])
  }

  /// Header size including CSRCs, but not the extension header.
  public var headerSize: Int { Self.fixedHeaderSize + csrcs.count * 4 }

  /// The serialized header (fixed part and CSRCs).
  public var header: Data {
    var out = Data(capacity: headerSize)
    out.append(
      (version & 0b11) << 6 | (padding ? 0x20 : 0) | (self.extension ? 0x10 : 0)
        | UInt8(csrcs.count & 0x0F)
    )
    out.append((marker ? 0x80 : 0) | (payloadType.rawValue & 0x7F))
    out.append(contentsOf: [UInt8(sequence >> 8), UInt8(sequence & 0xFF)])
    Self.appendUInt32(&out, timestamp)
    Self.appendUInt32(&out, ssrc)
    for csrc in csrcs { Self.appendUInt32(&out, csrc) }
    return out
  }

  public var rawValue: Data { header + payload }

  static func readUInt32(_ bytes: [UInt8], at i: Int) -> UInt32 {
    UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16
      | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3])
  }

  static func appendUInt32(_ data: inout Data, _ value: UInt32) {
    data.append(contentsOf: [
      UInt8(value >> 24), UInt8((value >> 16) & 0xFF),
      UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
    ])
  }
}

extension RTPPacket {
  /// Whether a raw UDP datagram is RTCP rather than RTP (RFC 5761 §4):
  /// RTCP packet types 200–213 land in the second byte where RTP keeps the
  /// marker bit and the payload type.
  public static func isRTCP(_ datagram: Data) -> Bool {
    guard datagram.count >= 2 else { return false }
    let type = datagram[datagram.startIndex + 1]
    return (192...223).contains(type)
  }
}
