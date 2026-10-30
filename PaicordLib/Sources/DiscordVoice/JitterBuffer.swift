//
//  JitterBuffer.swift
//  PaicordLib
//
//  Behaviour ported from Serein's `crates/discord-voice/src/jitter.rs`
//  (MIT/Apache-2.0): https://github.com/ViceVerse-cz/Serein
//

import Foundation

/// A per-speaker reorder buffer for encoded Opus packets.
///
/// - Holds at most eight packets.
/// - Starts playout after two 20 ms ticks (40 ms), or at once when full.
/// - Asks for packet-loss concealment for at most three consecutive missing
///   packets, then skips to the nearest buffered successor.
/// - A jump of eight or more packets restarts the stream.
package struct JitterBuffer: Sendable {
  package static let slots = 8
  static let startupTicks: UInt8 = 2
  static let maxConcealedPackets: UInt8 = 3
  static let maxOpusFrameSize = 1275

  package enum Output: Equatable, Sendable {
    /// Nothing to play yet (start-up, or the stream ended).
    case none
    /// Decode this packet.
    case packet(Data)
    /// The expected packet is missing: run the decoder's PLC.
    case conceal
  }

  package private(set) var packets: [(sequence: UInt16, opus: Data)] = []
  private var next: UInt16?
  private var wait: UInt8 = 0
  package private(set) var missing: UInt8 = 0

  package init() {}

  package mutating func clear() {
    self = JitterBuffer()
  }

  package mutating func push(sequence: UInt16, opus: Data) {
    guard opus.count <= Self.maxOpusFrameSize else { return }
    if next == nil {
      next = sequence
      wait = Self.startupTicks
    }
    let distance = sequence &- next!
    // Older than the playout point: late or duplicate, drop.
    if distance >= 32768 { return }
    if distance >= Self.slots {
      packets.removeAll()
      next = sequence
      wait = Self.startupTicks
      missing = 0
    }
    if packets.count < Self.slots,
      !packets.contains(where: { $0.sequence == sequence })
    {
      packets.append((sequence, opus))
    }
  }

  /// Called once per 20 ms playback tick.
  package mutating func pop() -> Output {
    if wait > 0 {
      // Short packets can fill the window before 40 ms. Starting early avoids
      // repeatedly resetting a full window on the next arrival.
      if packets.count < Self.slots {
        wait -= 1
        return .none
      }
      wait = 0
    }
    guard let expected = next else { return .none }
    next = expected &+ 1
    if let index = packets.firstIndex(where: { $0.sequence == expected }) {
      missing = 0
      return .packet(packets.remove(at: index).opus)
    }
    missing += 1
    if missing > Self.maxConcealedPackets {
      // Stop concealing the gap, but keep speech that arrived after it.
      if let index = packets.indices.min(by: {
        packets[$0].sequence &- expected < packets[$1].sequence &- expected
      }) {
        let packet = packets.remove(at: index)
        next = packet.sequence &+ 1
        missing = 0
        return .packet(packet.opus)
      }
      clear()
      return .none
    }
    return .conceal
  }
}
