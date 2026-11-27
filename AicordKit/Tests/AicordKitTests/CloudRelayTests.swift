import CloudKit
import XCTest

@testable import AicordKit

final class CloudRelayTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_800_000_000)

  private func note(_ message: String, channel: String = "c1", at date: Date? = nil)
    -> RelayNotification
  {
    RelayNotification(
      title: "Ala", subtitle: "#general · NAScin", body: "hi \(message)", channelId: channel,
      guildId: "g1", messageId: message, createdAt: date ?? start)
  }

  // MARK: - Records

  func testRecordRoundTrip() {
    let original = note("42")
    let record = original.record()
    XCTAssertEqual(record.recordType, "RelayNotification")
    XCTAssertEqual(record.recordID.recordName, "relay-g1-c1-42")
    XCTAssertEqual(record["title"] as? String, "Ala")
    XCTAssertEqual(record["channelId"] as? String, "c1")
    XCTAssertEqual(record["createdAt"] as? Date, start)
    XCTAssertEqual(RelayNotification(record: record), original)
  }

  func testDirectMessageHasNoGuild() {
    var dm = note("7")
    dm.guildId = nil
    let record = dm.record()
    XCTAssertEqual(record["guildId"] as? String, "")
    XCTAssertNil(RelayNotification(record: record)?.guildId)
    XCTAssertEqual(
      RelayTarget(recordName: record.recordID.recordName),
      RelayTarget(channelId: "c1", guildId: nil, messageId: "7"))
  }

  func testRecordNameCarriesTheTarget() {
    XCTAssertEqual(
      RelayTarget(recordName: note("42").recordName),
      RelayTarget(channelId: "c1", guildId: "g1", messageId: "42"))
    XCTAssertNil(RelayTarget(recordName: "ios-active"))
    XCTAssertNil(RelayTarget(recordName: "relay-42"))
  }

  func testLongTextIsTrimmed() {
    var long = note("1")
    long.body = String(repeating: "a", count: 5_000)
    let trimmed = long.trimmed
    XCTAssertEqual(trimmed.body.count, RelayNotification.maxBody)
    XCTAssertTrue(trimmed.body.hasSuffix("…"))
    XCTAssertEqual(note("2").trimmed, note("2"))
  }

  func testOtherRecordTypesAreRejected() {
    let other = CKRecord(recordType: "Something")
    other["channelId"] = "c1" as NSString
    other["messageId"] = "1" as NSString
    XCTAssertNil(RelayNotification(record: other))
  }

  func testPushFieldsBecomeActionInfo() {
    let target = RelayTarget(fields: ["channelId": "c1", "guildId": "", "messageId": "9"])
    XCTAssertEqual(target?.actionInfo, ["channel": "c1", "message": "9"])
    XCTAssertNil(RelayTarget(fields: ["guildId": "g1"]))
    XCTAssertNil(RelayTarget(userInfo: ["aps": ["alert": "x"]]))
  }

  // MARK: - Bursts

  func testFirstMessageGoesAtOnceAndTheRestWait() {
    var coalescer = RelayCoalescer(window: 10)
    XCTAssertEqual(coalescer.offer(note("1"), now: start)?.messageId, "1")
    XCTAssertNil(coalescer.offer(note("2"), now: start.addingTimeInterval(2)))
    XCTAssertNil(coalescer.offer(note("3"), now: start.addingTimeInterval(4)))
    XCTAssertTrue(coalescer.flush(now: start.addingTimeInterval(5)).isEmpty)
    XCTAssertEqual(coalescer.nextDeadline, start.addingTimeInterval(10))

    let batch = coalescer.flush(now: start.addingTimeInterval(10))
    XCTAssertEqual(batch.count, 1)
    XCTAssertEqual(batch.first?.messageId, "3")
    // the first was pushed on its own: the summary counts what waited
    XCTAssertEqual(batch.first?.count, 2)
  }

  func testQuietChannelClosesItsBurst() {
    var coalescer = RelayCoalescer(window: 10)
    _ = coalescer.offer(note("1"), now: start)
    XCTAssertTrue(coalescer.flush(now: start.addingTimeInterval(10)).isEmpty)
    XCTAssertTrue(coalescer.isEmpty)
    // a message after the window starts a new burst and goes at once
    XCTAssertEqual(coalescer.offer(note("2"), now: start.addingTimeInterval(11))?.count, 1)
  }

  func testLongBurstKeepsCounting() {
    var coalescer = RelayCoalescer(window: 10)
    _ = coalescer.offer(note("1"), now: start)
    _ = coalescer.offer(note("2"), now: start.addingTimeInterval(1))
    XCTAssertEqual(coalescer.flush(now: start.addingTimeInterval(10)).first?.count, 1)
    _ = coalescer.offer(note("3"), now: start.addingTimeInterval(12))
    _ = coalescer.offer(note("4"), now: start.addingTimeInterval(13))
    let next = coalescer.flush(now: start.addingTimeInterval(20))
    // the burst goes on: another window, counting only the new ones
    XCTAssertEqual(next.first?.count, 2)
    XCTAssertEqual(next.first?.messageId, "4")
  }

  func testChannelsAreSeparate() {
    var coalescer = RelayCoalescer(window: 10)
    XCTAssertNotNil(coalescer.offer(note("1", channel: "a"), now: start))
    XCTAssertNotNil(coalescer.offer(note("2", channel: "b"), now: start))
    XCTAssertNil(coalescer.offer(note("3", channel: "a"), now: start.addingTimeInterval(1)))
    let batch = coalescer.flush(now: start.addingTimeInterval(10))
    XCTAssertEqual(batch.map(\.channelId), ["a"])
  }

  func testHourlyCapHoldsInsteadOfSending() {
    var coalescer = RelayCoalescer(window: 10, maxPerHour: 2)
    XCTAssertNotNil(coalescer.offer(note("1", channel: "a"), now: start))
    XCTAssertNotNil(coalescer.offer(note("2", channel: "b"), now: start))
    XCTAssertNil(coalescer.offer(note("3", channel: "c"), now: start))
    // still capped: it waits for another window
    XCTAssertTrue(coalescer.flush(now: start.addingTimeInterval(10)).isEmpty)
    // an hour later there's room again
    let later = coalescer.flush(now: start.addingTimeInterval(3_601))
    XCTAssertEqual(later.map(\.messageId), ["3"])
    XCTAssertEqual(later.first?.count, 1)
  }

  func testResetForgetsWaitingMessages() {
    var coalescer = RelayCoalescer(window: 10)
    _ = coalescer.offer(note("1"), now: start)
    _ = coalescer.offer(note("2"), now: start.addingTimeInterval(1))
    coalescer.reset()
    XCTAssertTrue(coalescer.flush(now: start.addingTimeInterval(10)).isEmpty)
  }
}
