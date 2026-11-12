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
    @Environment(\.openWindow) var openWindow
    @State private var showingSearch = false
    /// What's typed in the toolbar's search field; Return opens Search with it.
    @State private var searchQuery = ""
    @FocusState private var searchFieldFocused: Bool

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
          .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 400)
      } detail: {
        detail
      }
      .navigationTitle(windowTitle)
      .navigationSubtitle(windowSubtitle)
      .keepsWindowTitle(windowTitle)
      // the toolbar's search field, like Mail's; Return opens Search with the text
      .searchable(text: $searchQuery, placement: .toolbar, prompt: Text("Search"))
      .searchFocused($searchFieldFocused)
      .onSubmit(of: .search) { showingSearch = true }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showingInspector.toggle()
          } label: {
            Label("Member List", systemImage: "sidebar.right")
          }
          .help("Show or hide the member list (⌥⌘I)")
          .disabled(currentChannelStore == nil)
        }
      }
      .sheet(isPresented: $showingSearch, onDismiss: { searchQuery = "" }) {
        SearchView(
          onOpen: { showingSearch = false }, onClose: { showingSearch = false },
          initialText: searchQuery
        )
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
          // the server comes from the selection, not `currentGuildStore`: the
          // two tasks run in either order, and a channel store made with the
          // previous server (or none) has no member list
          let guild = appState.selectedGuild.map { gw.getGuildStore(for: $0) }
          currentChannelStore = gw.getChannelStore(for: selected, from: guild)
        } else {
          currentChannelStore = nil
        }
      }
    }

    @ViewBuilder
    private var detail: some View {
      if let currentChannelStore {
        ChannelContentView(vm: currentChannelStore)
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

    /// The channel, like a mailbox in Mail; the server's name without one.
    private var windowTitle: String {
      guard let channel = currentChannelStore?.channel else {
        return currentGuildStore?.guild?.name ?? "Aicord"
      }
      if let name = channel.name, !name.isEmpty {
        // channels from READY carry no guild_id; the open server tells
        return currentGuildStore == nil ? name : "#" + name
      }
      return channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
        ?? "Aicord"
    }

    /// The channel's topic on one line, or the server when there's none.
    private var windowSubtitle: String {
      if let topic = currentChannelStore?.channel?.topic?
        .split(whereSeparator: \.isNewline).first.map(String.init), !topic.isEmpty
      {
        return topic
      }
      if let guild = currentGuildStore?.guild { return guild.name }
      return currentChannelStore == nil ? "" : String(localized: "Direct Messages")
    }

    private var actions: MacWindowActions {
      MacWindowActions(
        toggleMembers: { showingInspector.toggle() },
        search: { searchFieldFocused = true },
        currentChannel: currentChannelStore.map {
          ChannelWindowValue(guildId: currentGuildStore?.guildId, channelId: $0.channelId)
        },
        markCurrentRead: currentChannelStore?.channel.map { channel in
          { [gw] in Task { try? await gw.readStates.markRead([channel]) } }
        },
        serverSettings: appState.selectedGuild.map { guildId in
          { openWindow(id: ServerSettingsWindow.id, value: guildId) }
        },
        goToChannel: currentGuildStore.map { guild in
          { [appState] step, unreadOnly in
            if let next = Self.channel(after: appState.selectedChannel, in: guild, step: step, unreadOnly: unreadOnly) {
              appState.selectedChannel = next
            }
          }
        }
      )
    }

    /// The server's chat channels in the sidebar's order: channels outside a
    /// category first, then each category's, as `GuildView` lists them.
    static func chatChannels(in guild: GuildStore) -> [DiscordChannel] {
      let all = guild.channels.values.filter {
        ($0.type == .guildText || $0.type == .guildAnnouncement)
          && guild.hasPermission(channel: $0, .viewChannel)
      }
      let byPosition: (DiscordChannel, DiscordChannel) -> Bool = {
        ($0.position ?? 0) < ($1.position ?? 0)
      }
      let categories = guild.channels.values.filter { $0.type == .guildCategory }.sorted(by: byPosition)
      var ordered = all.filter { $0.parent_id == nil }.sorted(by: byPosition)
      for category in categories {
        let id = AnySnowflake(category.id)
        ordered += all.filter { $0.parent_id == id }.sorted(by: byPosition)
      }
      return ordered
    }

    /// The channel `step` places away from `current`, wrapping round; with
    /// `unreadOnly` the next unread one.
    static func channel(
      after current: ChannelSnowflake?, in guild: GuildStore, step: Int, unreadOnly: Bool
    ) -> ChannelSnowflake? {
      let channels = chatChannels(in: guild)
      guard !channels.isEmpty else { return nil }
      let start = channels.firstIndex { $0.id == current } ?? (step > 0 ? -1 : 0)
      for offset in 1...channels.count {
        let index = ((start + offset * step) % channels.count + channels.count) % channels.count
        let channel = channels[index]
        if !unreadOnly
          || guild.gateway?.readStates.isUnread(
            channelId: channel.id, lastMessageId: channel.last_message_id) == true
        {
          return channel.id
        }
      }
      return nil
    }
  }

  // MARK: - Commands

  /// What the menu bar can do in the focused main window.
  struct MacWindowActions {
    var toggleMembers: () -> Void
    var search: () -> Void
    var currentChannel: ChannelWindowValue?
    var markCurrentRead: (() -> Void)?
    var serverSettings: (() -> Void)?
    /// Moves to another channel of the open server: a step of ±1, unread only or not.
    var goToChannel: ((Int, Bool) -> Void)?
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
        // the standard inspector shortcut
        Button("Show Member List") { actions?.toggleMembers() }
          .keyboardShortcut("i", modifiers: [.command, .option])
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

        // ⌘1…⌘9: the first servers of the server bar
        ForEach(Array(serverShortcuts.enumerated()), id: \.element.id) { index, guild in
          Button(guild.name) { appState?.selectedGuild = guild.id }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command])
        }

        Divider()

        // with ⌘: ⌥↑ and ⌥↓ alone move by paragraph in the message field
        Button("Previous Channel") { actions?.goToChannel?(-1, false) }
          .keyboardShortcut(.upArrow, modifiers: [.command, .option])
          .disabled(actions?.goToChannel == nil)
        Button("Next Channel") { actions?.goToChannel?(1, false) }
          .keyboardShortcut(.downArrow, modifiers: [.command, .option])
          .disabled(actions?.goToChannel == nil)
        Button("Next Unread Channel") { actions?.goToChannel?(1, true) }
          .keyboardShortcut(.downArrow, modifiers: [.command, .option, .shift])
          .disabled(actions?.goToChannel == nil)

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

        Divider()

        Button("Server Settings…") { actions?.serverSettings?() }
          .disabled(actions?.serverSettings == nil)
      }
    }

    /// The servers ⌘1…⌘9 open, in the server bar's order: pinned ones, then
    /// ones in no folder (newest joined first), then the folders'.
    private var serverShortcuts: [Guild] {
      let gw = GatewayStore.shared
      let pinned = PinnedPlacesStore.shared.guilds
      let inFolders = gw.settings.userSettings.guildFolders.folders.flatMap { folder in
        folder.guildIds.map { GuildSnowflake($0.description) }
      }
      let me = gw.user.currentUser?.id
      let joined: (Guild) -> Date = { guild in
        guild.members?.first { $0.user?.id == me }?.joined_at.date ?? .now
      }
      let unlisted = gw.user.guilds.values
        .filter { !pinned.contains($0.id) && !inFolders.contains($0.id) }
        .sorted { joined($0) > joined($1) }
        .map(\.id)
      var seen = Set<GuildSnowflake>()
      return (pinned + unlisted + inFolders)
        .filter { seen.insert($0).inserted }
        .compactMap { gw.user.guilds[$0] }
        .prefix(9)
        .map { $0 }
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

    /// The channel's name, as the main window titles it.
    private var windowTitle: String {
      guard let channel = channelStore?.channel else { return String(localized: "Channel") }
      if let name = channel.name, !name.isEmpty {
        return guildStore == nil ? name : "#" + name
      }
      return channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
        ?? String(localized: "Channel")
    }

    var body: some View {
      Group {
        if gw.state != .connected {
          ProgressView()
        } else if let channelStore {
          ChannelContentView(vm: channelStore)
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
      .navigationTitle(windowTitle)
      .navigationSubtitle(guildStore?.guild?.name ?? "")
      // as in the main window: a sheet or a popover would rename the window
      .keepsWindowTitle(windowTitle)
      .attachmentViewer()
      .reactionPicker()
      .forwardSheet()
      .moderationSheet()
      .reminderSheet()
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
  extension View {
    /// Keeps the window's title as `title` while a sheet or a popover is open.
    /// On the Mac a `navigationTitle` inside presented content replaces the
    /// title of the window it is presented from ("Pinned Messages" instead of
    /// the channel), and SwiftUI has no way to keep it inside the sheet.
    func keepsWindowTitle(_ title: String) -> some View {
      background(WindowTitleKeeper(title: title))
    }
  }

  private struct WindowTitleKeeper: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> KeeperView { KeeperView() }

    func updateNSView(_ view: KeeperView, context: Context) {
      view.title = title
      view.apply()
    }

    final class KeeperView: NSView {
      var title = ""
      private var observation: NSKeyValueObservation?

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = window?.observe(\.title) { [weak self] _, _ in
          // SwiftUI sets the title on the main thread
          MainActor.assumeIsolated { self?.apply() }
        }
        apply()
      }

      func apply() {
        guard let window, !title.isEmpty, window.title != title else { return }
        window.title = title
      }
    }
  }

  /// A server's settings in a window of their own, as Mac apps keep longer
  /// forms: it can stay open beside the chat, and its title is the server's
  /// instead of replacing the main window's.
  struct ServerSettingsWindow: View {
    static let id = "server-settings"

    @Environment(\.gateway) var gw
    let guildId: GuildSnowflake
    /// Its own state, so sheets opened here show here. Leaving or deleting the
    /// server clears this selection, and that is passed on to the main window.
    @State private var appState = AicordAppState(remembersSelection: false)

    var body: some View {
      Group {
        if gw.state != .connected {
          ProgressView()
        } else {
          ServerSettingsSheet(guildId: guildId, inWindow: true)
        }
      }
      .navigationSubtitle(Text("Server Settings"))
      .moderationSheet()
      .environment(\.appState, appState)
      .task { appState.selectedGuild = guildId }
      .onChange(of: appState.selectedGuild) { _, selected in
        if selected == nil, AicordAppState.main?.selectedGuild == guildId {
          AicordAppState.main?.selectedGuild = nil
        }
      }
    }
  }

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

