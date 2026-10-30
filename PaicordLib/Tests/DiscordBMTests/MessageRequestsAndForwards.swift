import DiscordHTTP
import Foundation
import XCTest

@testable import DiscordModels

class MessageRequestsAndForwardsTests: XCTestCase {

  func testSpamAndRequestStateFromFieldsAndFlags() throws {
    func channel(_ json: String) throws -> DiscordChannel {
      try JSONDecoder().decode(DiscordChannel.self, from: Data(json.utf8))
    }
    let request = try channel(#"{"id":"1","type":1,"is_message_request":true,"is_spam":false}"#)
    XCTAssertTrue(request.isPendingMessageRequest)
    XCTAssertFalse(request.isSpam)

    let spam = try channel(#"{"id":"1","type":1,"is_message_request":true,"is_spam":true}"#)
    XCTAssertTrue(spam.isSpam)
    XCTAssertFalse(spam.isPendingMessageRequest)

    // IS_SPAM is 1 << 5
    let flagged = try channel(#"{"id":"1","type":1,"flags":32}"#)
    XCTAssertTrue(flagged.isSpam)

    let plain = try channel(#"{"id":"1","type":1}"#)
    XCTAssertFalse(plain.isSpam)
    XCTAssertFalse(plain.isPendingMessageRequest)
  }

  func testUpdateMessageRequestEncodesAcceptedConsent() throws {
    let data = try JSONEncoder().encode(Payloads.UpdateMessageRequest())
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(json["consent_status"] as? Int, 2)
  }

  func testBatchRejectLimits() {
    XCTAssertFalse(Payloads.BatchRejectMessageRequests(channel_ids: []).validate().isEmpty)
    let fifty = (1...50).map { ChannelSnowflake(String($0)) }
    XCTAssertTrue(Payloads.BatchRejectMessageRequests(channel_ids: fifty).validate().isEmpty)
    XCTAssertFalse(
      Payloads.BatchRejectMessageRequests(channel_ids: fifty + ["51"]).validate().isEmpty
    )
  }

  func testMessageRequestEndpoints() {
    let accept = UserAPIEndpoint.updateMessageRequest(channelId: "10")
    XCTAssertTrue(accept.url.hasSuffix("/channels/10/recipients/@me"))
    XCTAssertEqual(accept.httpMethod, .PUT)

    let reject = UserAPIEndpoint.rejectMessageRequest(channelId: "10")
    XCTAssertTrue(reject.url.hasSuffix("/channels/10/recipients/@me"))
    XCTAssertEqual(reject.httpMethod, .DELETE)

    let batch = UserAPIEndpoint.batchRejectMessageRequests
    XCTAssertTrue(batch.url.hasSuffix("/channels/recipients/@me/batch-reject"))
    XCTAssertEqual(batch.httpMethod, .PUT)

    let preview = UserAPIEndpoint.getMessageRequestSupplementalData
    XCTAssertTrue(preview.url.hasSuffix("/users/@me/message-requests/supplemental-data"))
    XCTAssertEqual(preview.httpMethod, .GET)
  }

  func testForwardPayloadEncodesReference() throws {
    let payload = Payloads.CreateMessage(
      message_reference: .init(type: .forward, message_id: "5", channel_id: "6", guild_id: "7")
    )
    XCTAssertTrue(payload.validate().isEmpty)
    let data = try JSONEncoder().encode(payload)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let reference = try XCTUnwrap(json["message_reference"] as? [String: Any])
    XCTAssertEqual(reference["type"] as? Int, 1)
    XCTAssertEqual(reference["message_id"] as? String, "5")
    XCTAssertEqual(reference["channel_id"] as? String, "6")
    XCTAssertEqual(reference["guild_id"] as? String, "7")
    XCTAssertNil(json["content"])
  }

  func testForwardedMessageDecodesSnapshot() throws {
    let json = #"""
      {"id":"100","channel_id":"200","type":0,"content":"","timestamp":"2026-10-30T12:00:00.000000+00:00",
      "edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],
      "attachments":[],"embeds":[],"pinned":false,"flags":16384,
      "author":{"id":"1","username":"me","discriminator":"0","avatar":null},
      "message_reference":{"type":1,"channel_id":"300","message_id":"400","guild_id":"500"},
      "message_snapshots":[{"message":{"type":0,"content":"guh","mentions":[],"attachments":[],
      "embeds":[],"timestamp":"2026-10-29T10:00:00.000000+00:00","edited_timestamp":null,"flags":0,
      "components":[]}}]}
      """#
    let message = try JSONDecoder().decode(DiscordChannel.Message.self, from: Data(json.utf8))
    XCTAssertEqual(message.message_reference?.type, .forward)
    XCTAssertEqual(message.message_reference?.guild_id, "500")
    XCTAssertEqual(message.message_snapshots?.count, 1)
    XCTAssertEqual(message.message_snapshots?.first?.message.content, "guh")
    XCTAssertTrue(message.flags?.contains(.hasSnapshot) == true)
  }

  func testSupplementalMessageRequestDecodes() throws {
    let json = #"[{"channel_id":"9","message_preview":null}]"#
    let decoded = try JSONDecoder().decode(
      [SupplementalMessageRequest].self, from: Data(json.utf8))
    XCTAssertEqual(decoded.first?.channel_id, "9")
    XCTAssertNil(decoded.first?.message_preview)
  }
}
