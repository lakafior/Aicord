//
//  HomeView.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

/// Discord iOS Home View, the left side is a list of servers, with the right being the selected server's channels etc.
/// The left side should be 1/5th of the width of both scroll views
struct HomeView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.theme) var theme

  var guild: GuildStore?

  var body: some View {
    HStack(spacing: 0) {
      GuildScrollBar()
        .scrollIndicators(.hidden)
        .frame(width: 65)

      Group {
        if let guild {
          GuildView(guild: guild)
        } else {
          DMsView()
        }
      }
      .background(theme.common.secondaryBackground)
      .roundedCorners(radius: 25, corners: .topLeft)
    }
    .padding(.top, 4)
  }
}
