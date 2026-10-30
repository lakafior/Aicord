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
  let guild: Guild
  @State private var showsSettings = false
  @State private var showsInvite = false
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button("Mark as Read", systemImage: "envelope.open") {
          saveInBackground($error) { try await gw.readStates.markRead(readableChannels) }
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

        Divider()

        PlaceNotificationMenus(guild: guild, channelId: nil, error: $error)

        Divider()

        Button("Server Settings…", systemImage: "gearshape") {
          showsSettings = true
        }

        if gw.settings.userSettings.appearance.developerMode {
          Button("Copy Server ID", systemImage: "number") {
            copyToPasteboard(guild.id.rawValue)
          }
        }
      }
      .sheet(isPresented: $showsSettings) {
        ServerSettingsSheet(guildId: guild.id)
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
      .saveErrorAlert($error)
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
