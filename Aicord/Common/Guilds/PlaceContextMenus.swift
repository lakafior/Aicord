//
//  PlaceContextMenus.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension View {
  /// The menu a server shows on long press or right click.
  func guildContextMenu(_ guild: Guild) -> some View {
    modifier(GuildContextMenu(guild: guild))
  }

  /// The menu a server channel shows on long press or right click.
  func channelContextMenu(_ channel: DiscordChannel, in guildId: GuildSnowflake) -> some View {
    modifier(ChannelContextMenu(channel: channel, guildId: guildId))
  }
}

// MARK: - Server

struct GuildContextMenu: ViewModifier {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  #if os(macOS)
    @Environment(\.openWindow) var openWindow
  #endif
  let guild: Guild
  @State private var showsSettings = false
  @State private var showsInvite = false
  @State private var showsCatchUp = false
  @State private var showsEvents = false
  @State private var showsOnboarding = false
  @State private var showsLeave = false
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button("Mark as Read", systemImage: "envelope.open") {
          saveInBackground($error) { try await gw.readStates.markRead(readableChannels) }
        }
        .disabled(!GuildButton.hasUnreadChannels(guild, readStates: gw.readStates))

        // read-only summaries of the unread channels
        Button("Catch Up", systemImage: "sparkles") {
          showsCatchUp = true
        }
        .disabled(!GuildButton.hasUnreadChannels(guild, readStates: gw.readStates))

        let pinned = PinnedPlacesStore.shared.isPinned(guild.id)
        Button(
          pinned ? "Unpin from Top" : "Pin to Top",
          systemImage: pinned ? "pin.slash" : "pin"
        ) {
          withAnimation { PinnedPlacesStore.shared.togglePin(guild.id) }
        }

        Button("Invite People", systemImage: "person.badge.plus") {
          showsInvite = true
        }
        .disabled(InvitePeople.channels(in: guild.id, gw: gw).isEmpty)

        Button("Events", systemImage: "calendar") {
          showsEvents = true
        }
        Button("Channels & Roles", systemImage: "checklist") {
          showsOnboarding = true
        }

        Divider()

        PlaceNotificationMenus(guild: guild, channelId: nil, error: $error)

        Divider()

        Button("Server Settings…", systemImage: "gearshape") {
          #if os(macOS)
            openWindow(id: ServerSettingsWindow.id, value: guild.id)
          #else
            showsSettings = true
          #endif
        }

        if gw.settings.userSettings.appearance.developerMode {
          Button("Copy Server ID", systemImage: "number") {
            copyToPasteboard(guild.id.rawValue)
          }
        }

        if LeaveServer.canLeave(guild, gw: gw) {
          Divider()
          Button("Leave Server", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
            showsLeave = true
          }
        }
      }
      .leaveServerConfirmation(isPresented: $showsLeave, guild: guild)
      .sheet(isPresented: $showsSettings) {
        ServerSettingsSheet(guildId: guild.id)
      }
      .sheet(isPresented: $showsEvents) {
        ScheduledEventsSheet(guildId: guild.id)
      }
      .sheet(isPresented: $showsOnboarding) {
        OnboardingSheet(guildId: guild.id)
      }
      .sheet(isPresented: $showsCatchUp) {
        CatchUpSheet(guildId: guild.id)
      }
      .sheet(isPresented: $showsInvite) {
        InvitePeopleSheet(
          guildId: guild.id,
          preferredChannel: appState.selectedGuild == guild.id ? appState.selectedChannel : nil
        )
      }
      .saveErrorAlert($error)
  }

  /// Text channels the server shows you; channels you can't view stay as they are.
  private var readableChannels: [DiscordChannel] {
    let store = gw.existingGuildStore(for: guild.id)
    return (guild.channels ?? []).filter { channel in
      (channel.type == .guildText || channel.type == .guildAnnouncement)
        && store?.hasPermission(channel: channel, .viewChannel) != false
    }
  }
}

// MARK: - Channel

struct ChannelContextMenu: ViewModifier {
  @Environment(\.gateway) var gw
  let channel: DiscordChannel
  let guildId: GuildSnowflake
  @State private var error: String?
  @State private var summary: SummaryRange?
  @State private var asking = false
  @State private var indexing = false
  @State private var showsGallery = false

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button("Mark as Read", systemImage: "envelope.open") {
          saveInBackground($error) { try await gw.readStates.markRead([channel]) }
        }
        .disabled(
          !gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id)
            && gw.readStates.mentionCount(channelId: channel.id) == 0
        )

        Button("Catch Up", systemImage: "sparkles") {
          summary = .unread
        }
        .disabled(!gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id))

        // read-only summaries and questions, as in the chat's title menu
        Menu("Intelligence", systemImage: "sparkles") {
          ChannelIntelligenceActions(
            channelId: channel.id, includesCatchUp: false, summary: $summary, asking: $asking,
            indexing: $indexing)
        }

        Button("Media, Links and Files", systemImage: "photo.on.rectangle") {
          showsGallery = true
        }

        #if os(macOS)
          OpenInNewWindowButton(value: .init(guildId: guildId, channelId: channel.id))
        #endif

        let pinned = PinnedPlacesStore.shared.isPinned(channel.id, in: guildId)
        Button(
          pinned ? "Unpin from Top" : "Pin to Top",
          systemImage: pinned ? "pin.slash" : "pin"
        ) {
          withAnimation { PinnedPlacesStore.shared.togglePin(channel.id, in: guildId) }
        }

        Divider()

        if let guild = gw.user.guilds[guildId] {
          PlaceNotificationMenus(guild: guild, channelId: channel.id, error: $error)
        }

        if gw.settings.userSettings.appearance.developerMode {
          Divider()
          Button("Copy Channel ID", systemImage: "number") {
            copyToPasteboard(channel.id.rawValue)
          }
        }
      }
      .sheet(item: $summary) { range in
        ChannelSummarySheet(
          channelId: channel.id, guildId: guildId, channelName: channelName, range: range)
      }
      .sheet(isPresented: $asking) {
        AskChannelSheet(channelId: channel.id, guildId: guildId, channelName: channelName)
      }
      .sheet(isPresented: $indexing) {
        ChannelIndexSheet(channelId: channel.id, guildId: guildId, channelName: channelName)
      }
      .sheet(isPresented: $showsGallery) {
        ChannelGallerySheet(channelId: channel.id, guildId: guildId, title: channelName)
          .galleryFrame()
      }
      .saveErrorAlert($error)
  }

  private var channelName: String { "#" + (channel.name ?? "channel") }
}

// MARK: - Direct Messages

extension View {
  /// The menu a direct message or group shows on long press or right click.
  func dmContextMenu(_ channel: DiscordChannel) -> some View {
    modifier(DMContextMenu(channel: channel))
  }

  /// The confirmations the conversation actions ask for, and their errors.
  func dmActionDialogs(
    _ confirming: Binding<DMAction?>, error: Binding<String?>
  ) -> some View {
    modifier(DMActionDialogs(confirming: confirming, error: error))
  }
}

struct DMContextMenu: ViewModifier {
  let channel: DiscordChannel
  @State private var confirming: DMAction?
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .contextMenu {
        DMActionButtons(channel: channel, confirming: $confirming, error: $error)
      }
      .dmActionDialogs($confirming, error: $error)
  }
}

/// The conversation actions behind a button, for the profile panel.
struct DMActionsMenu<MenuLabel: View>: View {
  var channel: DiscordChannel?
  var user: UserSnowflake?
  var userName: String?
  @ViewBuilder var label: () -> MenuLabel
  @State private var confirming: DMAction?
  @State private var error: String?

  var body: some View {
    Menu {
      DMActionButtons(
        channel: channel, user: user, userName: userName, confirming: $confirming, error: $error)
    } label: {
      label()
    }
    .dmActionDialogs($confirming, error: $error)
  }
}

/// What Discord lets you do with a conversation and the person in it. Closing a
/// DM only hides it: the history stays, and a new message brings it back.
struct DMActionButtons: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  var channel: DiscordChannel?
  /// The other person; taken from the channel when it's a one-to-one DM.
  var user: UserSnowflake?
  var userName: String?
  @Binding var confirming: DMAction?
  @Binding var error: String?

  init(
    channel: DiscordChannel?, user: UserSnowflake? = nil, userName: String? = nil,
    confirming: Binding<DMAction?>, error: Binding<String?>
  ) {
    self.channel = channel
    let recipient = channel?.type == .dm ? channel?.recipients?.first : nil
    self.user = user ?? recipient?.id
    self.userName = userName ?? recipient.map { $0.global_name ?? $0.username }
    self._confirming = confirming
    self._error = error
  }

  var body: some View {
    if let channel {
      Button("Mark as Read", systemImage: "envelope.open") {
        saveInBackground($error) { try await gw.readStates.markRead([channel]) }
      }
      .disabled(
        !gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id)
          && gw.readStates.mentionCount(channelId: channel.id) == 0
      )
    }

    if let user, user != gw.user.currentUser?.id {
      let relationship = gw.user.relationships[user]
      let name = userName ?? ""
      Divider()
      if relationship?.type == .friend {
        Button("Remove Friend", systemImage: "person.badge.minus", role: .destructive) {
          confirming = .removeFriend(user, name: name)
        }
      }
      let ignored = relationship?.user_ignored == true
      Button(ignored ? "Unignore" : "Ignore", systemImage: ignored ? "eye" : "eye.slash") {
        saveInBackground($error) {
          try await DMActions.setIgnored(!ignored, user: user, gw: gw)
        }
      }
      if relationship?.type == .blocked {
        Button("Unblock", systemImage: "hand.raised.slash") {
          saveInBackground($error) {
            try await gw.client.removeRelationship(userID: user).guardSuccess()
          }
        }
      } else {
        Button("Block", systemImage: "hand.raised", role: .destructive) {
          confirming = .block(user, name: name)
        }
      }
    }

    if gw.settings.userSettings.appearance.developerMode {
      Divider()
      if let user {
        Button("Copy User ID", systemImage: "number") { copyToPasteboard(user.rawValue) }
      }
      if let channel {
        Button("Copy Channel ID", systemImage: "number") { copyToPasteboard(channel.id.rawValue) }
      }
    }

    if let channel {
      Divider()
      if channel.type == .groupDm {
        Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
          confirming = .leaveGroup(channel)
        }
      } else {
        Button("Close DM", systemImage: "xmark.circle", role: .destructive) {
          saveInBackground($error) {
            try await DMActions.close(channel, gw: gw, appState: appState)
          }
        }
      }
    }
  }
}

/// The conversation actions that ask first.
enum DMAction: Identifiable {
  case block(UserSnowflake, name: String)
  case removeFriend(UserSnowflake, name: String)
  case leaveGroup(DiscordChannel)

  var id: String {
    switch self {
    case .block(let user, _): "block-\(user.rawValue)"
    case .removeFriend(let user, _): "remove-\(user.rawValue)"
    case .leaveGroup(let channel): "leave-\(channel.id.rawValue)"
    }
  }
}

struct DMActionDialogs: ViewModifier {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Binding var confirming: DMAction?
  @Binding var error: String?

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        title,
        isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
        titleVisibility: .visible,
        presenting: confirming
      ) { action in
        switch action {
        case .block(let user, _):
          Button("Block", role: .destructive) {
            saveInBackground($error) {
              try await gw.client.createRelationship(userID: user, payload: .init(type: .blocked))
                .guardSuccess()
            }
          }
        case .removeFriend(let user, _):
          Button("Remove Friend", role: .destructive) {
            saveInBackground($error) {
              try await gw.client.removeRelationship(userID: user).guardSuccess()
            }
          }
        case .leaveGroup(let channel):
          Button("Leave Group", role: .destructive) {
            saveInBackground($error) {
              try await DMActions.close(channel, gw: gw, appState: appState)
            }
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: { action in
        switch action {
        case .block:
          Text("They won't be able to message you, and their messages will be hidden. They aren't told.")
        case .removeFriend:
          Text("Your conversation stays; you can add them again later.")
        case .leaveGroup:
          Text("You won't get its messages unless someone adds you back.")
        }
      }
      .saveErrorAlert($error)
  }

  private var title: String {
    switch confirming {
    case .block(_, let name): String(localized: "Block \(name)?")
    case .removeFriend(_, let name): String(localized: "Remove \(name) from Friends?")
    case .leaveGroup: String(localized: "Leave this group?")
    case nil: ""
    }
  }
}

@MainActor
enum DMActions {
  /// Closes a DM (or leaves a group) and leaves the chat if it was open.
  static func close(_ channel: DiscordChannel, gw: GatewayStore, appState: AicordAppState)
    async throws
  {
    try await gw.client.deleteChannel(id: channel.id).guardSuccess()
    gw.user.privateChannels.removeValue(forKey: channel.id)
    if appState.selectedChannel == channel.id {
      appState.selectedChannel = nil
      appState.chatOpen = false
    }
  }

  /// Ignoring keeps someone's messages and requests quiet without telling them.
  static func setIgnored(_ ignored: Bool, user: UserSnowflake, gw: GatewayStore) async throws {
    let res =
      ignored
      ? try await gw.client.ignoreUser(userID: user)
      : try await gw.client.unignoreUser(userID: user)
    try res.guardSuccess()
    // the gateway confirms with Relationship Add/Update; reflect it right away
    gw.user.relationships[user]?.user_ignored = ignored
  }
}

// MARK: - Mute and Notify

/// Mute and Notify submenus for a server, or one of its channels with `channelId`.
/// Both are saved on the Discord account, like the official client.
struct PlaceNotificationMenus: View {
  typealias Level = UserGuildSettingsStore.Level
  typealias MuteDuration = UserGuildSettingsStore.MuteDuration

  @Environment(\.gateway) var gw
  let guild: Guild
  let channelId: ChannelSnowflake?
  @Binding var error: String?

  private var settings: UserGuildSettingsStore { gw.userGuildSettings }

  var body: some View {
    let muted =
      channelId.map { settings.isMuted(guildId: guild.id, channelId: $0) }
      ?? settings.isMuted(guildId: guild.id)

    if muted {
      Button(
        channelId == nil ? "Unmute Server" : "Unmute Channel",
        systemImage: "speaker.wave.2"
      ) {
        saveInBackground($error) {
          try await settings.setMuted(false, guildId: guild.id, channelId: channelId)
        }
      }
      if let end = settings.muteEnd(guildId: guild.id, channelId: channelId) {
        Text("Muted until \(end.formatted(date: .omitted, time: .shortened))")
      }
    } else {
      Menu(
        channelId == nil ? "Mute Server" : "Mute Channel",
        systemImage: "speaker.slash"
      ) {
        ForEach(MuteDuration.allCases) { duration in
          Button(String(localized: duration.title)) {
            saveInBackground($error) {
              try await settings.setMuted(
                true, for: duration, guildId: guild.id, channelId: channelId
              )
            }
          }
        }
      }
    }

    Menu("Notify", systemImage: "bell") {
      Picker("Notify", selection: levelBinding) {
        if channelId != nil {
          Text("Use Server Default").tag(Level.inherit)
        }
        Text("All Messages").tag(Level.allMessages)
        Text("Only @mentions").tag(Level.onlyMentions)
        Text("Nothing").tag(Level.nothing)
      }
      .pickerStyle(.inline)

      if channelId == nil {
        Divider()
        Toggle(
          "Suppress @everyone and @here",
          isOn: suppressBinding(settings.suppressesEveryone) { .init(everyone: $0) }
        )
        Toggle(
          "Suppress All Role @mentions",
          isOn: suppressBinding(settings.suppressesRoles) { .init(roles: $0) }
        )
      }
    }
  }

  /// A server set to `inherit` follows its own default, which the picker shows instead.
  private var levelBinding: Binding<Level> {
    Binding {
      if let channelId {
        return settings.channelLevel(guildId: guild.id, channelId: channelId)
      }
      let level = settings.guildLevel(guild.id)
      guard level == .inherit else { return level }
      return guild.default_message_notifications == .onlyMentions ? .onlyMentions : .allMessages
    } set: { level in
      saveInBackground($error) { try await settings.setLevel(level, guildId: guild.id, channelId: channelId) }
    }
  }

  private struct Suppression {
    var everyone: Bool?
    var roles: Bool?
  }

  private func suppressBinding(
    _ current: @escaping (GuildSnowflake) -> Bool,
    _ change: @escaping (Bool) -> Suppression
  ) -> Binding<Bool> {
    Binding {
      current(guild.id)
    } set: { value in
      let suppression = change(value)
      saveInBackground($error) {
        try await settings.setSuppress(
          everyone: suppression.everyone, roles: suppression.roles, guildId: guild.id
        )
      }
    }
  }
}

// MARK: - Helpers

/// Runs a save in the background and puts its error, if any, into `error`.
@MainActor
func saveInBackground(_ error: Binding<String?>, _ work: @escaping @MainActor () async throws -> Void) {
  Task { @MainActor in
    do {
      try await work()
    } catch let failure {
      error.wrappedValue = failure.localizedDescription
    }
  }
}

extension View {
  /// The "Couldn't Save" alert the settings pages use.
  func saveErrorAlert(_ error: Binding<String?>) -> some View {
    alert(
      "Couldn't Save",
      isPresented: .init(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(error.wrappedValue ?? "")
    }
  }
}

func copyToPasteboard(_ string: String) {
  #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
  #elseif os(iOS)
    UIPasteboard.general.string = string
  #endif
}
