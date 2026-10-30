//
//  Environment.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 06/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

// Some new environment values for storing things like the gateway, app state, and optional values like the current guild or channel stores.

import AicordKit
import SwiftUI

extension EnvironmentValues {
  @Entry var appState: AicordAppState = .environmentDefault  // only really used by login page.
  @Entry var gateway: GatewayStore = .environmentDefault

  @Entry var guildStore: GuildStore?
  @Entry var channelStore: ChannelStore?

  @Entry var challenges: Challenges?
}

// Environment defaults are read nonisolated; SwiftUI only reads them on the main actor.
extension AicordAppState {
  fileprivate nonisolated static var environmentDefault: AicordAppState {
    MainActor.assumeIsolated { .sharedEphemeral }
  }
}

extension GatewayStore {
  fileprivate nonisolated static var environmentDefault: GatewayStore {
    MainActor.assumeIsolated { .shared }
  }
}

extension FocusedValues {
  @Entry var appState: AicordAppState?
}
