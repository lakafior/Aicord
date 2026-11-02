//
//  Sidebar.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 15/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

struct SidebarView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @Binding var currentGuildStore: GuildStore?

  var body: some View {
    HStack(spacing: 0) {
      guildScroller
        #if os(macOS)
          // a narrow column of small icons, like a Mac source list's
          .frame(width: GuildButton.railWidth)
        #else
          .frame(width: 65)
        #endif
      if let guild = currentGuildStore {
        GuildView(guild: guild)
      } else {
        DMsView()
      }
    }
  }

  @ViewBuilder
  var guildScroller: some View {
    GuildScrollBar()
      .scrollIndicators(.never)
  }
}
