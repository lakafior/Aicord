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
  /// The server Home showed last, so opening a DM from Messages doesn't empty Home.
  @State private var lastHomeGuild: GuildSnowflake? = nil
  var disableSlideover: Bool {
    self.currentTab == .settings || currentChannelStore == nil
  }

  var body: some View {
    SlideoverDoubleView(swap: $appState.chatOpen) {
      TabView(selection: $currentTab) {
        Tab("Home", systemImage: "house", value: CurrentTab.home) {
          NavigationStack {
            HomeView(guild: currentGuildStore)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(theme.common.primaryBackground)
          }
        }
        Tab("Messages", systemImage: "bubble.left.and.bubble.right", value: CurrentTab.messages) {
          MessagesView()
            .tint(nil)
        }
        .badge(messagesBadge)
        Tab("Search", systemImage: "magnifyingglass", value: CurrentTab.search) {
          SearchView {
            withAnimation { appState.chatOpen = true }
          }
          .tint(nil)
        }
        Tab("Settings", systemImage: "gearshape", value: CurrentTab.settings) {
          SettingsView(initialTab: nil, showsDoneButton: false)
            .tint(nil)
        }
      }
      .tint(theme.common.tertiaryButton)
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
          // never shown: the slideover stays shut until a channel is picked
          Color.clear
        }
      }
    }
    .slideoverDisabled(disableSlideover)
    .onChange(of: currentTab) { _, _ in showServerOnHome() }
    .onAppear { showServerOnHome() }
    .task(id: appState.selectedGuild) {
      if let selected = appState.selectedGuild { lastHomeGuild = selected }
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

  /// Unread direct messages, like Discord's own badge. Server mentions are counted
  /// per channel and can pile up into thousands, so they stay in the Mentions list.
  var messagesBadge: Int {
    gw.user.privateChannels.values.reduce(0) { total, channel in
      total + gw.readStates.mentionCount(channelId: channel.id)
    }
  }

  /// Home lists servers only; with no server chosen it falls back to the last one.
  func showServerOnHome() {
    guard currentTab == .home, appState.selectedGuild == nil else { return }
    let fallback = gw.user.guilds.values.min {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }?.id
    if let guild = lastHomeGuild ?? fallback {
      appState.selectedGuild = guild
    }
  }

  enum CurrentTab {
    case home, messages, search, settings
  }
}
