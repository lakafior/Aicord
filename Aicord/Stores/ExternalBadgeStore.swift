//
//  ExternalBadgeStore.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 22/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import AicordKit

/// External badge store (no third-party telemetry or sponsor badge endpoints).
@MainActor
@Observable
final class ExternalBadgeStore {
  init() {}

  func badges(for userID: UserSnowflake?) -> [DiscordUser.Profile.Badge] {
    []
  }
}
