//
//  Cookies.swift
//  PaicordLib
//
//  Created by Lakhan Lothiyi on 10/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import XCTest

@testable import DiscordHTTP

final class Cookies: XCTestCase {
  func testCookies() async throws {
    let c = CookieStore()
    let headers: HTTPHeaders = [
      "set-cookie":
        "__cf_bm=oDArIUJUGLW6bdrvAzN4IF3DRVtw5fMloZdJUaP4CQs-1757525679-1.0.1.1; path=/; expires=Wed, 10-Sep-2099 18:04:39 GMT; domain=.discord.com; HttpOnly; Secure; SameSite=None"
    ]
    await c.checkIncomingHeaders(headers)

    var outgoing = HTTPHeaders()
    await c.applyCookies(to: &outgoing)
    XCTAssertEqual(
      outgoing.first(name: "Cookie"),
      "__cf_bm=oDArIUJUGLW6bdrvAzN4IF3DRVtw5fMloZdJUaP4CQs-1757525679-1.0.1.1"
    )
  }

  func testExpiredCookiesAreNotSent() async throws {
    let c = CookieStore()
    let headers: HTTPHeaders = [
      "set-cookie": "__cf_bm=stale; path=/; expires=Wed, 10-Sep-2003 18:04:39 GMT; domain=.discord.com"
    ]
    await c.checkIncomingHeaders(headers)

    var outgoing = HTTPHeaders()
    await c.applyCookies(to: &outgoing)
    XCTAssertNil(outgoing.first(name: "Cookie"))
  }
}
