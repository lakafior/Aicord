//
//  MacBaseplate.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

#if os(macOS)
  /// The Mac's own window layout: the system sidebar with servers and
  /// channels, the chat as the detail, members in an inspector, the server and
  /// channel as the window's title and subtitle, and a toolbar for search and
  /// the member list. Settings → Advanced can switch back to the shared iPad
  /// layout (`LargeBaseplate`).
  struct MacBaseplate: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @AppStorage("Paicord.ShowingMembersSidebar") var showingInspector = true

    @State private var currentGuildStore: GuildStore? = nil
    @State private var currentChannelStore: ChannelStore? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingSearch = false

    var body: some View {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        SidebarView(currentGuildStore: $currentGuildStore)
          .environment(\.guildStore, currentGuildStore)
          .environment(\.channelStore, currentChannelStore)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
              VoiceCallBar()
              ProfileBar()
            }
          }
          .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 420)
      } detail: {
        detail
      }
      .navigationTitle(windowTitle)
      .navigationSubtitle(windowSubtitle)
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button {
            showingSearch = true
          } label: {
            Label("Search", systemImage: "magnifyingglass")
          }
          .help("Search servers, channels, people and messages (⌘F)")

          Button {
            showingInspector.toggle()
          } label: {
            Label("Member List", systemImage: "sidebar.right")
          }
          .help("Show or hide the member list (⌥⌘M)")
          .disabled(currentChannelStore == nil)
        }
      }
      .sheet(isPresented: $showingSearch) {
        SearchView(onOpen: { showingSearch = false }, onClose: { showingSearch = false })
          .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 640)
      }
      .focusedSceneValue(\.macWindowActions, actions)
      .frame(minWidth: 900, minHeight: 540)
      .task(id: appState.selectedGuild) {
        if let selected = appState.selectedGuild {
          currentGuildStore = gw.getGuildStore(for: selected)
        } else {
          currentGuildStore = nil
        }
      }
      .task(id: appState.selectedChannel) {
        if let selected = appState.selectedChannel {
          currentChannelStore = gw.getChannelStore(for: selected, from: currentGuildStore)
        } else {
          currentChannelStore = nil
        }
      }
    }

    @ViewBuilder
    private var detail: some View {
      if let currentChannelStore {
        ChatView(vm: currentChannelStore)
          // a fixed minimum keeps the chat and member list columns from resizing
          // each other in a loop (AppKit throws once it runs out of layout passes)
          .frame(minWidth: 0, maxWidth: .infinity)
          .inspector(isPresented: $showingInspector) {
            MemberSidebarView(guildStore: currentGuildStore, channelStore: currentChannelStore)
              .frame(minWidth: 0, maxWidth: .infinity)
              .inspectorColumnWidth(min: 250, ideal: 260, max: 360)
          }
          .id(currentChannelStore.channelId)
          .environment(\.guildStore, currentGuildStore)
          .environment(\.channelStore, currentChannelStore)
      } else {
        ContentUnavailableView(
          "No Channel Selected",
          systemImage: "bubble.left.and.bubble.right",
          description: Text("Pick a channel or a conversation in the sidebar.")
        )
      }
    }

    private var windowTitle: String {
      guard let channel = currentChannelStore?.channel else { return "Aicord" }
      if let name = channel.name, !name.isEmpty {
        return channel.guild_id == nil ? name : "#" + name
      }
      return channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
        ?? "Aicord"
    }

    private var windowSubtitle: String {
      if let guild = currentGuildStore?.guild { return guild.name }
      return currentChannelStore == nil ? "" : String(localized: "Direct Messages")
    }

    private var actions: MacWindowActions {
      MacWindowActions(
        toggleMembers: { showingInspector.toggle() },
        search: { showingSearch = true },
        currentChannel: currentChannelStore.map {
          ChannelWindowValue(guildId: currentGuildStore?.guildId, channelId: $0.channelId)
        },
        markCurrentRead: currentChannelStore?.channel.map { channel in
          { [gw] in Task { try? await gw.readStates.markRead([channel]) } }
        }
      )
    }
  }

  // MARK: - Commands

  /// What the menu bar can do in the focused main window.
  struct MacWindowActions {
    var toggleMembers: () -> Void
    var search: () -> Void
    var currentChannel: ChannelWindowValue?
    var markCurrentRead: (() -> Void)?
  }

  extension FocusedValues {
    @Entry var macWindowActions: MacWindowActions?
  }

  /// View and Go menus for the Mac layout.
  struct MacCommands: Commands {
    @FocusedValue(\.macWindowActions) var actions
    @FocusedValue(\.appState) var appState
    @Environment(\.openWindow) var openWindow

    var body: some Commands {
      SidebarCommands()

      CommandGroup(after: .sidebar) {
        Button("Show Member List") { actions?.toggleMembers() }
          .keyboardShortcut("m", modifiers: [.command, .option])
          .disabled(actions?.currentChannel == nil)
      }

      CommandGroup(after: .textEditing) {
        Button("Search…") { actions?.search() }
          .keyboardShortcut("f", modifiers: [.command])
          .disabled(actions == nil)
      }

      CommandMenu("Go") {
        Button("Direct Messages") {
          appState?.selectedGuild = nil
        }
        .keyboardShortcut("0", modifiers: [.command])
        .disabled(appState == nil)

        Divider()

        Button("Open Channel in New Window") {
          if let channel = actions?.currentChannel {
            openWindow(value: channel)
          }
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(actions?.currentChannel == nil)

        Button("Mark Channel as Read") { actions?.markCurrentRead?() }
          .keyboardShortcut(.escape, modifiers: [.shift])
          .disabled(actions?.markCurrentRead == nil)
      }
    }
  }

  // MARK: - Channel window

  /// A channel open in a window of its own.
  struct ChannelWindowValue: Codable, Hashable {
    var guildId: GuildSnowflake?
    var channelId: ChannelSnowflake
  }

  /// One channel and its member list, without the sidebar. It has its own app
  /// state that doesn't remember selections, so the main window's last channel
  /// stays as it was.
  struct ChannelWindow: View {
    @Environment(\.gateway) var gw
    let value: ChannelWindowValue
    @State private var appState = AicordAppState(remembersSelection: false)
    @State private var guildStore: GuildStore?
    @State private var channelStore: ChannelStore?
    @State private var showingMembers = false

    var body: some View {
      Group {
        if gw.state != .connected {
          ProgressView()
        } else if let channelStore {
          ChatView(vm: channelStore)
            .frame(minWidth: 0, maxWidth: .infinity)
            .inspector(isPresented: $showingMembers) {
              MemberSidebarView(guildStore: guildStore, channelStore: channelStore)
                .frame(minWidth: 0, maxWidth: .infinity)
                .inspectorColumnWidth(min: 250, ideal: 260, max: 360)
            }
            .environment(\.guildStore, guildStore)
            .environment(\.channelStore, channelStore)
            .toolbar {
              ToolbarItem(placement: .primaryAction) {
                Button {
                  showingMembers.toggle()
                } label: {
                  Label("Member List", systemImage: "sidebar.right")
                }
              }
            }
        } else {
          ContentUnavailableView("Channel Not Available", systemImage: "number")
        }
      }
      .navigationSubtitle(guildStore?.guild?.name ?? "")
      .attachmentViewer()
      .reactionPicker()
      .forwardSheet()
      .messageIntelligenceSheet()
      .environment(\.appState, appState)
      .focusedSceneValue(\.appState, appState)
      .frame(minWidth: 480, minHeight: 400)
      .task(id: gw.state == .connected) {
        guard gw.state == .connected else { return }
        appState.selectedGuild = value.guildId
        appState.selectedChannel = value.channelId
        guildStore = value.guildId.map { gw.getGuildStore(for: $0) }
        channelStore = gw.getChannelStore(for: value.channelId, from: guildStore)
      }
    }
  }
#endif

#if os(macOS)
  /// "Open in New Window" for a channel's context menu.
  struct OpenInNewWindowButton: View {
    @Environment(\.openWindow) var openWindow
    let value: ChannelWindowValue

    var body: some View {
      Button("Open in New Window", systemImage: "macwindow.badge.plus") {
        openWindow(value: value)
      }
    }
  }
#endif

