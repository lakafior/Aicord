import Foundation
import XCTest

@testable import DiscordModels

class InviteLinksTests: XCTestCase {

  func testCodeFromLinkSpellings() {
    func code(_ string: String) -> String? { InviteLink.code(from: URL(string: string)!) }
    XCTAssertEqual(code("https://discord.gg/abc123"), "abc123")
    XCTAssertEqual(code("https://discord.gg/invite/abc123"), "abc123")
    XCTAssertEqual(code("http://discord.gg/abc123?event=1"), "abc123")
    XCTAssertEqual(code("https://discord.com/invite/my-server"), "my-server")
    XCTAssertEqual(code("https://canary.discord.com/invite/abc123"), "abc123")
    XCTAssertEqual(code("https://discordapp.com/invite/abc123/"), "abc123")
    XCTAssertEqual(code("aicord://invite/abc123"), "abc123")

    XCTAssertNil(code("https://discord.com/channels/1/2/3"))
    XCTAssertNil(code("https://example.com/invite/abc123"))
    XCTAssertNil(code("https://discord.gg/"))
    XCTAssertNil(code("aicord://mention/abc123"))
    XCTAssertNil(code("https://discord.gg/a%20b"))
  }

  func testCodesInMessageText() {
    let text = """
      join us discord.gg/abc123, or <https://discord.com/invite/xyz-9>!
      [here](https://discord.gg/abc123) and https://example.com/invite/nope
      """
    XCTAssertEqual(InviteLink.codes(in: text), ["abc123", "xyz-9"])
    XCTAssertEqual(InviteLink.codes(in: "no links here"), [])
  }

  func testLinksForCode() {
    XCTAssertEqual(InviteLink.url(for: "abc").absoluteString, "https://discord.gg/abc")
    XCTAssertEqual(InviteLink.appURL(for: "abc").absoluteString, "aicord://invite/abc")
    XCTAssertEqual(InviteLink.code(from: InviteLink.appURL(for: "abc")), "abc")
  }

  func testExpiryAndUseLimitPayloads() throws {
    func json(_ payload: Payloads.CreateChannelInvite) throws -> [String: Any] {
      let data = try JSONEncoder().encode(payload)
      return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    let never = try json(.init(max_age: InviteExpiry.never.maxAge, max_uses: InviteUseLimit.unlimited.maxUses))
    XCTAssertEqual(never["max_age"] as? Int, 0)
    XCTAssertEqual(never["max_uses"] as? Int, 0)

    let week = try json(.init(max_age: InviteExpiry.sevenDays.maxAge, max_uses: InviteUseLimit.ten.maxUses))
    XCTAssertEqual(week["max_age"] as? Int, 604_800)
    XCTAssertEqual(week["max_uses"] as? Int, 10)

    for expiry in InviteExpiry.allCases {
      for limit in InviteUseLimit.allCases {
        XCTAssertTrue(
          Payloads.CreateChannelInvite(max_age: expiry.maxAge, max_uses: limit.maxUses)
            .validate().isEmpty
        )
      }
    }
  }

  func testFriendRequestFailureFromErrorCodes() {
    XCTAssertEqual(FriendRequestFailure(status: 400, code: 80004, message: nil), .unknownUser)
    XCTAssertEqual(FriendRequestFailure(status: 400, code: 80007, message: nil), .alreadyFriends)
    XCTAssertEqual(FriendRequestFailure(status: 400, code: 80000, message: nil), .requestsDisabled)
    XCTAssertEqual(FriendRequestFailure(status: 400, code: 30002, message: nil), .friendLimit)
    XCTAssertEqual(FriendRequestFailure(status: 429, code: nil, message: nil), .rateLimited)
    XCTAssertEqual(FriendRequestFailure(status: 400, code: 12345, message: "Nope"), .other("Nope"))
  }
}
