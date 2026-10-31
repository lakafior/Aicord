//
//  ServerSettingsSheet.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// Your own settings for one server: notifications, and the per-server
/// exceptions from Content & Social and Data & Privacy.
struct ServerSettingsSheet: View {
  typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  typealias Level = UserGuildSettingsStore.Level
  typealias MuteDuration = UserGuildSettingsStore.MuteDuration

  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss
  let guildId: GuildSnowflake
  @State private var error: String?
  @State private var showsLeave = false

  private var guild: Guild? { gw.user.guilds[guildId] }
  private var notifications: UserGuildSettingsStore { gw.userGuildSettings }
  private var privacy: Settings.PrivacySettings { gw.settings.userSettings.privacy }
  private var rawId: UInt64 { UInt64(guildId.rawValue) ?? 0 }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink {
            InvitePeopleView(guildId: guildId)
          } label: {
            Label("Invite People", systemImage: "person.badge.plus")
          }
          .disabled(InvitePeople.channels(in: guildId, gw: gw).isEmpty)
          if gw.existingGuildStore(for: guildId)?.hasPermission(channel: nil as DiscordChannel?, .manageGuild) != false {
            NavigationLink {
              ServerInvitesView(guildId: guildId)
            } label: {
              Label("Invites", systemImage: "link")
            }
          }
        }

        if let guild {
          notificationsSection(guild)
        }
        directMessagesSection
        activitySection

        Section {
          NavigationLink("Server Profile") {
            Form { ServerProfileEditor(guildID: guildId) }
              .formStyle(.grouped)
              .navigationTitle("Server Profile")
          }
        } footer: {
          Text("Your nickname and pronouns on this server, also in Settings → Profiles.")
        }

        if let guild, LeaveServer.canLeave(guild, gw: gw) {
          Section {
            Button("Leave Server", role: .destructive) { showsLeave = true }
          }
        }
      }
      .formStyle(.grouped)
      .leaveServerConfirmation(isPresented: $showsLeave, guild: guild) { dismiss() }
      .navigationTitle(guild?.name ?? String(localized: "Server Settings"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, idealWidth: 480, minHeight: 520, idealHeight: 600)
    #endif
    .saveErrorAlert($error)
  }

  // MARK: - Notifications

  @ViewBuilder
  private func notificationsSection(_ guild: Guild) -> some View {
    Section {
      Picker("Notify", selection: levelBinding(guild)) {
        Text("All Messages").tag(Level.allMessages)
        Text("Only @mentions").tag(Level.onlyMentions)
        Text("Nothing").tag(Level.nothing)
      }
      toggle(
        "Suppress @everyone and @here",
        isOn: notifications.suppressesEveryone(guildId: guildId)
      ) { value in
        saveInBackground($error) {
          try await notifications.setSuppress(everyone: value, guildId: guildId)
        }
      }
      toggle(
        "Suppress All Role @mentions",
        isOn: notifications.suppressesRoles(guildId: guildId)
      ) { value in
        saveInBackground($error) {
          try await notifications.setSuppress(roles: value, guildId: guildId)
        }
      }

      if notifications.isMuted(guildId: guildId) {
        LabeledContent("Muted") {
          if let end = notifications.muteEnd(guildId: guildId) {
            Text(end, format: .dateTime.weekday().hour().minute())
          } else {
            Text("Until you turn it back on")
          }
        }
        Button("Unmute Server") {
          saveInBackground($error) {
            try await notifications.setMuted(false, guildId: guildId)
          }
        }
      } else {
        Menu("Mute Server") {
          ForEach(MuteDuration.allCases) { duration in
            Button(String(localized: duration.title)) {
              saveInBackground($error) {
                try await notifications.setMuted(true, for: duration, guildId: guildId)
              }
            }
          }
        }
      }
    } header: {
      Text("Notifications")
    } footer: {
      Text("Saved to your Discord account. Channels can override this from their own menu.")
    }
  }

  private func levelBinding(_ guild: Guild) -> Binding<Level> {
    Binding {
      let level = notifications.guildLevel(guildId)
      guard level == .inherit else { return level }
      return guild.default_message_notifications == .onlyMentions ? .onlyMentions : .allMessages
    } set: { level in
      saveInBackground($error) { try await notifications.setLevel(level, guildId: guildId) }
    }
  }

  // MARK: - Privacy

  private var directMessagesSection: some View {
    Section {
      privacyToggle("Allow DMs from Server Members", list: \.restrictedGuildIds)
      privacyToggle("Message Requests", list: \.messageRequestRestrictedGuildIds)
    } header: {
      Text("Direct Messages")
    } footer: {
      Text("Exceptions to your defaults in Content & Social, for this server only.")
    }
  }

  private var activitySection: some View {
    Section {
      privacyToggle("Share Your Activity", list: \.activityRestrictedGuildIds)
      privacyToggle("Allow Friends to Join Your Activity", list: \.activityJoiningRestrictedGuildIds)
    } header: {
      Text("Activity Privacy")
    } footer: {
      Text("Exceptions to your defaults in Data & Privacy, for this server only.")
    }
  }

  /// On when the server is not in the given "restricted" list.
  private func privacyToggle(
    _ title: LocalizedStringKey,
    list: WritableKeyPath<Settings.PrivacySettings, [UInt64]>
  ) -> some View {
    toggle(title, isOn: !privacy[keyPath: list].contains(rawId)) { allowed in
      let id = rawId
      saveInBackground($error) {
        // the whole privacy group is sent, so go through patchUserSettings
        try await gw.settings.patchUserSettings { settings in
          var ids = settings.privacy[keyPath: list]
          ids.removeAll { $0 == id }
          if !allowed { ids.append(id) }
          settings.privacy[keyPath: list] = ids
        }
      }
    }
  }

  private func toggle(
    _ title: LocalizedStringKey, isOn: Bool, set: @escaping @MainActor @Sendable (Bool) -> Void
  ) -> some View {
    Toggle(title, isOn: Binding(get: { isOn }, set: set))
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
  }
}
