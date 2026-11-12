//
//  VideoDepacketizer.swift
//  AicordKit
//
//  Puts the RTP packets of one video source back together into frames:
//  H.264 (RFC 6184: single NAL units, STAP-A and FU-A) and H.265
//  (RFC 7798: single NAL units, aggregation and fragmentation units).
//
//  The output is an Annex B byte stream with 4-byte start codes, which is
//  the layout libdave encrypted on the sender's side: a DAVE frame has to be
//  rebuilt byte for byte before it can be decrypted. NAL unit headers stay
//  in the clear, so key frames can be told apart before decryption.
//
//  A packet that is late is waited for, and listed in `missingSequences`
//  so the owner can ask for it again (NACK); one that never comes costs the
//  frames up to the next key frame.
//

import DiscordModels
import Foundation

public enum VideoCodec: Sendable, Equatable {
  case h264
  case h265
}

package struct VideoDepacketizer {
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
  static let reorderWindow = 128
  /// A missing packet is asked for again after this long, this many times.
  static let nackInterval: Duration = .milliseconds(80)
  static let maxNacks = 3
  static let maxNackedAtOnce = 64
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
  /// Missing packets already asked for: how often, and when last.
  private var nacked: [UInt16: (count: Int, last: ContinuousClock.Instant)] = [:]

  package let codec: VideoCodec

  package init(codec: VideoCodec = .h264) {
    self.codec = codec
  }

  /// Packets missing between the frame being waited for and the newest one
  /// received, that are due to be asked for (again). The sender's
  /// retransmission arrives as an ordinary packet with the same sequence.
  package mutating func missingSequences(now: ContinuousClock.Instant = .now) -> [UInt16] {
    guard let next, let newest else { return [] }
    var due: [UInt16] = []
    var sequence = next
    while Self.distance(newest, from: sequence) > 0, due.count < Self.maxNackedAtOnce {
      defer { sequence &+= 1 }
      guard pending[sequence] == nil else { continue }
      let state = nacked[sequence]
      if let state {
        guard state.count < Self.maxNacks, now - state.last >= Self.nackInterval
        else { continue }
      }
      nacked[sequence] = ((state?.count ?? 0) + 1, now)
      due.append(sequence)
    }
    return due
  }

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
    nacked = nacked.filter { Self.distance($0.key, from: sequence) >= 0 }
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
    let codec = self.codec

    /// Starts a NAL unit; `header` is its first byte.
    func note(_ header: UInt8) {
      switch codec {
      case .h264:
        let type = header & 0x1F
        // IDR slice or SPS.
        if type == 5 || type == 7 { isKeyframe = true }
      case .h265:
        let type = (header >> 1) & 0x3F
        // IRAP pictures and VPS, SPS, PPS.
        if (16...23).contains(type) || (32...34).contains(type) { isKeyframe = true }
      }
    }

    /// 2-byte length, NAL unit, repeated (STAP-A and H.265 aggregation).
    func aggregated(_ payload: [UInt8], from start: Int) {
      var offset = start
      while offset + 2 <= payload.count {
        let length = Int(payload[offset]) << 8 | Int(payload[offset + 1])
        offset += 2
        guard length > 0, offset + length <= payload.count else { break }
        note(payload[offset])
        data += Self.startCode
        data.append(contentsOf: payload[offset..<(offset + length)])
        offset += length
      }
    }

    for packet in packets {
      let payload = [UInt8](packet.payload)
      guard let first = payload.first else { continue }
      switch codec {
      case .h264:
        switch first & 0x1F {
        case 1...23:
          note(first)
          data += Self.startCode
          data.append(contentsOf: payload)
          fragmentOpen = false
        case 24:
          aggregated(payload, from: 1)
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
      case .h265:
        guard payload.count > 2 else { continue }
        switch (first >> 1) & 0x3F {
        case 48:
          aggregated(payload, from: 2)
          fragmentOpen = false
        case 49:
          // FU: 2-byte payload header, FU header (start, end, type), fragment.
          guard payload.count > 3 else { continue }
          let header = payload[2]
          if header & 0x80 != 0 {
            let nal = (first & 0x81) | ((header & 0x3F) << 1)
            note(nal)
            data += Self.startCode
            data.append(contentsOf: [nal, payload[1]])
            fragmentOpen = true
          }
          guard fragmentOpen else { return dropped() }
          data.append(contentsOf: payload[3...])
          if header & 0x40 != 0 { fragmentOpen = false }
        case 50...63:
          // PACI and reserved types.
          continue
        default:
          note(first)
          data += Self.startCode
          data.append(contentsOf: payload)
          fragmentOpen = false
        }
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
