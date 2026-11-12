//
//  H264Depacketizer.swift
//  AicordKit
//
//  Puts the RTP packets of one video source back together into H.264 frames
//  (RFC 6184: single NAL units, STAP-A and FU-A).
//
//  The output is an Annex B byte stream with 4-byte start codes, which is
//  the layout libdave encrypted on the sender's side: a DAVE frame has to be
//  rebuilt byte for byte before it can be decrypted. NAL unit headers stay
//  in the clear, so key frames can be told apart before decryption.
//

import DiscordModels
import Foundation

package struct H264Depacketizer {
  package struct Frame: Equatable {
    /// RTP timestamp, 90 kHz.
    package var timestamp: UInt32
    /// Carries an IDR slice or parameter sets: decoding can start here.
    package var isKeyframe: Bool
    /// Annex B, still end-to-end encrypted if the call is.
    package var data: Data

    package init(timestamp: UInt32, isKeyframe: Bool, data: Data) {
      self.timestamp = timestamp
      self.isKeyframe = isKeyframe
      self.data = data
    }
  }

  /// How far behind the newest packet a missing one may be before it counts
  /// as lost.
  static let reorderWindow = 48
  static let maxPendingPackets = 2048
  /// A frame larger than this is not video we want to decode.
  static let maxFrameSize = 8 * 1024 * 1024
  static let startCode = Data([0, 0, 0, 1])

  /// Frames are dropped until the next key frame. The owner asks the sender
  /// for one while this is set.
  package private(set) var needsKeyframe = true

  private var pending: [UInt16: RTPPacket] = [:]
  /// The first packet of the frame being waited for; `nil` until a frame
  /// boundary has been seen.
  private var next: UInt16?
  private var newest: UInt16?

  package init() {}

  /// A frame could not be used (it failed to decrypt): start over from the
  /// next key frame.
  package mutating func requireKeyframe() {
    needsKeyframe = true
  }

  /// Takes one decrypted RTP packet and returns the frames it completed, in
  /// order.
  package mutating func push(_ packet: RTPPacket) -> [Frame] {
    let sequence = packet.sequence
    if let next, Self.distance(sequence, from: next) < 0 { return [] }
    pending[sequence] = packet
    if newest.map({ Self.distance(sequence, from: $0) > 0 }) ?? true {
      newest = sequence
    }
    guard next != nil else {
      // Joined mid-frame: the packet after a marker starts a frame.
      if packet.marker { skip(to: sequence &+ 1) }
      return []
    }

    var frames: [Frame] = []
    while let start = next {
      var packets: [RTPPacket] = []
      var sequence = start
      var complete = false
      while let packet = pending[sequence] {
        if let first = packets.first, first.timestamp != packet.timestamp {
          // The marker was not set; the timestamp change ends the frame.
          complete = true
          break
        }
        packets.append(packet)
        sequence &+= 1
        if packet.marker {
          complete = true
          break
        }
      }
      if complete {
        skip(to: sequence)
        if let frame = assemble(packets) { frames.append(frame) }
        continue
      }
      // `sequence` is missing. Wait for it while it may still arrive.
      let behind = newest.map { Self.distance($0, from: sequence) } ?? 0
      guard behind > Self.reorderWindow || pending.count > Self.maxPendingPackets
      else { break }
      needsKeyframe = true
      resynchronize(after: sequence)
    }
    return frames
  }

  // MARK: Private

  /// Signed distance between two sequence numbers, across the wrap.
  static func distance(_ a: UInt16, from b: UInt16) -> Int {
    Int(Int16(truncatingIfNeeded: a &- b))
  }

  private mutating func skip(to sequence: UInt16) {
    next = sequence
    pending = pending.filter { Self.distance($0.key, from: sequence) >= 0 }
  }

  /// After a loss: continue at the first frame boundary past the gap.
  private mutating func resynchronize(after missing: UInt16) {
    guard let newest else {
      pending.removeAll()
      next = nil
      return
    }
    var sequence = missing &+ 1
    while Self.distance(newest, from: sequence) >= 0 {
      if pending[sequence]?.marker == true {
        skip(to: sequence &+ 1)
        return
      }
      sequence &+= 1
    }
    pending.removeAll()
    next = nil
  }

  private mutating func assemble(_ packets: [RTPPacket]) -> Frame? {
    guard let timestamp = packets.first?.timestamp else { return nil }
    var data = Data()
    var isKeyframe = false
    var fragmentOpen = false

    func note(_ header: UInt8) {
      let type = header & 0x1F
      if type == 5 || type == 7 { isKeyframe = true }
    }

    for packet in packets {
      let payload = [UInt8](packet.payload)
      guard let first = payload.first else { continue }
      switch first & 0x1F {
      case 1...23:
        note(first)
        data += Self.startCode
        data.append(contentsOf: payload)
        fragmentOpen = false
      case 24:
        // STAP-A: 2-byte length, NAL unit, repeated.
        var offset = 1
        while offset + 2 <= payload.count {
          let length = Int(payload[offset]) << 8 | Int(payload[offset + 1])
          offset += 2
          guard length > 0, offset + length <= payload.count else { break }
          note(payload[offset])
          data += Self.startCode
          data.append(contentsOf: payload[offset..<(offset + length)])
          offset += length
        }
        fragmentOpen = false
      case 28:
        // FU-A: indicator, header (start, end, type), fragment.
        guard payload.count > 2 else { continue }
        let header = payload[1]
        if header & 0x80 != 0 {
          let nal = (first & 0xE0) | (header & 0x1F)
          note(nal)
          data += Self.startCode
          data.append(nal)
          fragmentOpen = true
        }
        // A fragment without its start cannot be placed.
        guard fragmentOpen else { return dropped() }
        data.append(contentsOf: payload[2...])
        if header & 0x40 != 0 { fragmentOpen = false }
      default:
        // STAP-B, MTAP and FU-B are not used by WebRTC senders.
        continue
      }
      guard data.count <= Self.maxFrameSize else { return dropped() }
    }

    guard !data.isEmpty else { return nil }
    if needsKeyframe {
      guard isKeyframe else { return nil }
      needsKeyframe = false
    }
    return Frame(timestamp: timestamp, isKeyframe: isKeyframe, data: data)
  }

  private mutating func dropped() -> Frame? {
    needsKeyframe = true
    return nil
  }
}
