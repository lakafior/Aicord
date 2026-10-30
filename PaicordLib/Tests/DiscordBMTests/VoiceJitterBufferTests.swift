import Foundation
import XCTest

import DiscordVoice

/// Ported from the tests in Serein's `jitter.rs`.
class VoiceJitterBufferTests: XCTestCase {
  func testBurstLossPreservesBufferedRecoveryAndResetsOnFarJump() {
    for first: UInt16 in [0, .max - 2] {
      var jitter = JitterBuffer()
      jitter.push(sequence: first, opus: Data([0]))
      for offset: UInt16 in [7, 5, 6] {
        jitter.push(sequence: first &+ offset, opus: Data([UInt8(offset)]))
      }
      XCTAssertEqual(jitter.pop(), .none)
      XCTAssertEqual(jitter.pop(), .none)
      XCTAssertEqual(jitter.pop(), .packet(Data([0])))
      for _ in 0..<3 { XCTAssertEqual(jitter.pop(), .conceal) }
      for offset: UInt8 in [5, 6, 7] {
        XCTAssertEqual(jitter.pop(), .packet(Data([offset])))
      }
      for _ in 0..<2 { XCTAssertEqual(jitter.pop(), .conceal) }
      jitter.push(sequence: first &+ 100, opus: Data([100]))
      XCTAssertEqual(jitter.missing, 0)
      XCTAssertEqual(jitter.pop(), .none)
      XCTAssertEqual(jitter.pop(), .none)
      XCTAssertEqual(jitter.pop(), .packet(Data([100])))
    }
  }

  func testBoundedReorderingLossDuplicatesAndWrap() {
    var jitter = JitterBuffer()
    jitter.push(sequence: .max, opus: Data([1]))
    jitter.push(sequence: 1, opus: Data([3]))
    jitter.push(sequence: 0, opus: Data([2]))
    jitter.push(sequence: 0, opus: Data([9]))
    XCTAssertEqual(jitter.pop(), .none)
    XCTAssertEqual(jitter.pop(), .none)
    XCTAssertEqual(jitter.pop(), .packet(Data([1])))
    XCTAssertEqual(jitter.pop(), .packet(Data([2])))
    XCTAssertEqual(jitter.pop(), .packet(Data([3])))
    for _ in 0..<3 { XCTAssertEqual(jitter.pop(), .conceal) }
    XCTAssertEqual(jitter.pop(), .none)
    XCTAssertEqual(jitter.pop(), .none)
    for sequence: UInt16 in 0..<1000 {
      jitter.push(sequence: sequence, opus: Data(repeating: 1, count: 1275))
      XCTAssertLessThanOrEqual(jitter.packets.count, JitterBuffer.slots)
    }
    jitter.push(sequence: 1000, opus: Data(count: 1276))
    XCTAssertLessThanOrEqual(jitter.packets.count, JitterBuffer.slots)
  }

  func testFullWindowStartsEarly() {
    var jitter = JitterBuffer()
    for sequence: UInt16 in 10..<18 {
      jitter.push(sequence: sequence, opus: Data([UInt8(sequence)]))
    }
    XCTAssertEqual(jitter.pop(), .packet(Data([10])))
  }
}
