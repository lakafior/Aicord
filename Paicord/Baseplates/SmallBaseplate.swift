//
//  SmallBaseplate.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

@available(macOS, unavailable)
struct SmallBaseplate: View {
  @Bindable var appState: PaicordAppState
  @Environment(\.gateway) var gw
  @Environment(\.theme) var theme

  @State var currentGuildStore: GuildStore? = nil
  @State var currentChannelStore: ChannelStore? = nil

  @State private var currentTab: CurrentTab = .home
  var disableSlideover: Bool {
    self.currentTab != .home
  }

  var body: some View {
    SlideoverDoubleView(swap: $appState.chatOpen) {
      NavigationStack {
        TabView(selection: $currentTab) {
          HomeView(guild: currentGuildStore)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.common.primaryBackground)
            .toolbarBackground(theme.common.tertiaryBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .tabItem { Label("Home", systemImage: "house") }
            .tag(CurrentTab.home)
          NotificationsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.common.primaryBackground)
            .toolbarBackground(theme.common.tertiaryBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .tabItem { Label("Notifications", systemImage: "bell") }
            .tag(CurrentTab.notifications)
            .tint(nil)
          ProfileView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.common.primaryBackground)
            .toolbarBackground(theme.common.tertiaryBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .tabItem { Label("Profile", systemImage: "person.circle") }
            .tag(CurrentTab.profile)
            .tint(nil)
        }
        .tint(theme.common.tertiaryButton)
      }
      .environment(\.guildStore, currentGuildStore)
      .environment(\.channelStore, currentChannelStore)
    } secondary: {
      NavigationStack {
        if let currentChannelStore {
          ChatView(vm: currentChannelStore)
            .id(currentChannelStore.channelId)  // force view update
            .environment(\.guildStore, currentGuildStore)
            .environment(\.channelStore, currentChannelStore)
            #if os(iOS)
              .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                  Button {
                    withAnimation {
                      appState.chatOpen.toggle()
                    }
                  } label: {
                    Image(systemName: "arrow.left")
                  }
                  .tint(theme.common.tertiaryButton)
                }
              }
            #endif
        } else {
          VStack {
            Text(":3")
              .font(.largeTitle)
              .foregroundStyle(.secondary)

            Text("Select a channel to start chatting")
              .foregroundStyle(.secondary)
              .font(.title2)
          }
        }
      }
    }
    .slideoverDisabled(disableSlideover)
    .task(id: appState.selectedGuild) {
      if let selected = appState.selectedGuild {
        self.currentGuildStore = gw.getGuildStore(for: selected)
      } else {
        self.currentGuildStore = nil
      }
    }
    .task(id: appState.selectedChannel) {
      if let selected = appState.selectedChannel {
        // there is a likelihood that currentGuildStore is wrong when this runs
        // but i dont think it will be a problem maybe.
        self.currentChannelStore = gw.getChannelStore(
          for: selected,
          from: self.currentGuildStore
        )
      } else {
        self.currentChannelStore = nil
      }
    }
  }

  enum CurrentTab {
    case home, notifications, profile
  }
}
