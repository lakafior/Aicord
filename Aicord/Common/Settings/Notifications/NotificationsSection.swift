//
//  NotificationsSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI
import UserNotifications

extension SettingsView {
  @ViewBuilder
  var notificationsSection: some View {
    NotificationSettings()
  }
}

/// When Aicord notifies, and how. Everything is on this device except the
/// servers and channels set to Nothing, which are saved to the Discord account.
struct NotificationSettings: View {
  typealias Prefs = NotificationPrefs

  @Environment(\.gateway) var gw
  @Environment(\.scenePhase) var scenePhase

  @AppStorage(Prefs.enabledKey) private var enabled = true
  @AppStorage(Prefs.inAppKey) private var inApp = true
  @AppStorage(Prefs.previewKey) private var preview = Prefs.Preview.full.rawValue
  @AppStorage(Prefs.soundKey) private var sound = true
  @AppStorage(Prefs.badgeKey) private var badge = Prefs.Badge.directMessages.rawValue
  @AppStorage(Prefs.dmModeKey) private var dmMode = Prefs.DMMode.everyone.rawValue
  @AppStorage(Prefs.dmUsersKey) private var dmUsers = ""
  @AppStorage(Prefs.serverModeKey) private var serverMode = Prefs.ServerMode.all.rawValue
  @AppStorage(Prefs.serverPlacesKey) private var serverPlaces = ""
  @AppStorage(Prefs.everyoneKey) private var everyone = true
  @AppStorage(Prefs.rolesKey) private var roles = true
  @AppStorage(Prefs.keywordsKey) private var keywords = ""
  @AppStorage(Prefs.dndKey) private var quietOnDND = true
  @AppStorage(Prefs.quietHoursKey) private var quietHours = false
  @AppStorage(Prefs.quietStartKey) private var quietStart = 22 * 60
  @AppStorage(Prefs.quietEndKey) private var quietEnd = 7 * 60
  @AppStorage(Prefs.friendRequestsKey) private var friendRequests = true

  var body: some View {
    accessSection

    Section {
      toggle("Notifications", isOn: $enabled)
        .onChange(of: enabled) { gw.notifications.updateBadge() }
      if enabled {
        toggle("Show While Using Aicord", isOn: $inApp)
        Picker("Preview", selection: $preview) {
          Text("Name and Message").tag(Prefs.Preview.full.rawValue)
          Text("Name Only").tag(Prefs.Preview.author.rawValue)
          Text("Hidden").tag(Prefs.Preview.hidden.rawValue)
        }
        toggle("Sound", isOn: $sound)
      }
      Picker("Badge on App Icon", selection: $badge) {
        Text("Off").tag(Prefs.Badge.off.rawValue)
        Text("Unread DMs").tag(Prefs.Badge.directMessages.rawValue)
        Text("Unread DMs and Mentions").tag(Prefs.Badge.all.rawValue)
      }
      .onChange(of: badge) { gw.notifications.updateBadge() }
    } header: {
      Text("Alerts")
    } footer: {
      Text(alertsFooter)
    }

    if enabled {
      directMessagesSection
      serversSection
      quietSection
      AlertSettingsSection()

      Section {
        toggle("Friend Requests", isOn: $friendRequests)
      } header: {
        Text("Other")
      }
    }
  }

  // MARK: - Access

  @ViewBuilder
  private var accessSection: some View {
    let status = gw.notifications.authorization
    Section {
      LabeledContent("Notifications for Aicord") {
        Text(statusLabel(status))
          .foregroundStyle(status == .denied ? .red : .secondary)
      }
      switch status {
      case .notDetermined:
        Button("Allow Notifications") {
          Task { await gw.notifications.requestAuthorization() }
        }
      case .denied:
        Button("Open Settings") { NotificationStore.openSystemSettings() }
      default:
        Button("Send Test Notification") { gw.notifications.sendTest() }
        Button("Open Settings") { NotificationStore.openSystemSettings() }
      }
    } header: {
      Text("Access")
    } footer: {
      if status == .denied {
        Text("Turned off in the system settings. Turn on Allow Notifications there for Aicord.")
      } else {
        Text("Banners, sounds, badges and Focus are also set in the system settings.")
      }
    }
    .task(id: scenePhase) { await gw.notifications.refreshAuthorization() }
  }

  private func statusLabel(_ status: UNAuthorizationStatus) -> LocalizedStringKey {
    switch status {
    case .authorized: "Allowed"
    case .provisional: "Delivered Quietly"
    case .denied: "Not Allowed"
    case .notDetermined: "Not Asked Yet"
    default: "Allowed"
    }
  }

  private var alertsFooter: LocalizedStringKey {
    #if os(iOS)
      "Aicord notifies while it's open and for about half a minute after you leave it; after that iOS pauses it until you come back. Nothing is sent through a server. No notification comes for the channel you're looking at."
    #else
      "Aicord notifies while it's running, also in the background. No notification comes for the channel you're looking at."
    #endif
  }

  // MARK: - Direct Messages

  @ViewBuilder
  private var directMessagesSection: some View {
    Section {
      Picker("Notify For", selection: $dmMode) {
        Text("Everyone").tag(Prefs.DMMode.everyone.rawValue)
        Text("Friends").tag(Prefs.DMMode.friends.rawValue)
        Text("Only Selected People").tag(Prefs.DMMode.whitelist.rawValue)
        Text("Everyone Except").tag(Prefs.DMMode.blacklist.rawValue)
      }
      if dmMode == Prefs.DMMode.whitelist.rawValue || dmMode == Prefs.DMMode.blacklist.rawValue {
        NavigationLink {
          NotificationPeopleList(selection: $dmUsers)
        } label: {
          LabeledContent("People", value: countLabel(dmUsers))
        }
      }
    } header: {
      Text("Direct Messages")
    } footer: {
      Text(
        "Direct and group messages. Conversations muted in Discord stay silent in every mode. Only on this device."
      )
    }
  }

  // MARK: - Servers

  @ViewBuilder
  private var serversSection: some View {
    Section {
      Picker("Notify For", selection: $serverMode) {
        Text("All Servers").tag(Prefs.ServerMode.all.rawValue)
        Text("Only Selected").tag(Prefs.ServerMode.whitelist.rawValue)
        Text("All Except").tag(Prefs.ServerMode.blacklist.rawValue)
      }
      if serverMode == Prefs.ServerMode.whitelist.rawValue {
        NavigationLink {
          NotificationPlaceList(mode: .selected(selection: $serverPlaces))
        } label: {
          LabeledContent("Servers and Channels", value: countLabel(serverPlaces))
        }
      } else if serverMode == Prefs.ServerMode.blacklist.rawValue {
        NavigationLink {
          NotificationPlaceList(mode: .silenced)
        } label: {
          LabeledContent("Silenced in Discord", value: "\(silencedCount)")
        }
      }
      toggle("@everyone and @here", isOn: $everyone)
      toggle("Role Mentions", isOn: $roles)
      TextField(
        "Keywords", text: $keywords, prompt: Text("Keywords, separated by commas"), axis: .vertical
      )
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif
    } header: {
      Text("Servers")
    } footer: {
      Text(serversFooter)
    }
  }

  private var serversFooter: LocalizedStringKey {
    switch Prefs.ServerMode(rawValue: serverMode) ?? .all {
    case .all, .blacklist:
      "Mentions of you, your roles, @everyone and @here, and every message where a server or channel is set to All Messages in Discord. Servers and channels set to Nothing stay silent; muted ones only notify when you're mentioned. Silencing a server or channel sets it to Nothing on your Discord account, so the official apps stay quiet too. Keywords notify like a mention."
    case .whitelist:
      "Only the servers and channels you pick notify, still following their notification settings from Discord. The list is only on this device. Keywords notify like a mention."
    }
  }

  private var silencedCount: Int {
    let settings = gw.userGuildSettings
    return settings.userGuildSettings.values.reduce(0) { total, guild in
      guard let guildId = guild.guild_id else { return total }
      let channels = guild.channel_overrides.filter {
        settings.channelLevel(guildId: guildId, channelId: $0.channel_id) == .nothing
      }
      return total + channels.count + (settings.guildLevel(guildId) == .nothing ? 1 : 0)
    }
  }

  // MARK: - Quiet

  @ViewBuilder
  private var quietSection: some View {
    Section {
      toggle("During Do Not Disturb", isOn: $quietOnDND)
      toggle("Quiet Hours", isOn: $quietHours)
      if quietHours {
        DatePicker("From", selection: time($quietStart), displayedComponents: .hourAndMinute)
        DatePicker("To", selection: time($quietEnd), displayedComponents: .hourAndMinute)
      }
    } header: {
      Text("Quiet")
    } footer: {
      Text(
        "Notifications still arrive, without a banner or sound, and wait in Notification Centre. Do Not Disturb is your Discord status."
      )
    }
  }

  // MARK: - Helpers

  private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
      #if os(macOS)
        .toggleStyle(.switch)
      #endif
  }

  private func countLabel(_ list: String) -> String {
    let count = list.split(separator: ",").count
    return count == 0 ? String(localized: "None") : "\(count)"
  }

  /// Minutes after midnight as a time of day for the date picker.
  private func time(_ minutes: Binding<Int>) -> Binding<Date> {
    Binding {
      Calendar.current.date(
        bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0,
        of: .now
      ) ?? .now
    } set: { date in
      let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
      minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
  }
}

// MARK: - People

/// Friends and people you have a DM with, ticked into a list of IDs.
struct NotificationPeopleList: View {
  @Environment(\.gateway) var gw
  @Binding var selection: String
  @State private var search = ""

  private struct Person: Identifiable {
    var id: String
    var name: String
    var username: String
  }

  var body: some View {
    let selected = Set(selection.split(separator: ",").map(String.init))
    Form {
      ForEach(people) { person in
        Button {
          var newSelection = selected
          if selected.contains(person.id) {
            newSelection.remove(person.id)
          } else {
            newSelection.insert(person.id)
          }
          selection = newSelection.sorted().joined(separator: ",")
        } label: {
          HStack {
            VStack(alignment: .leading) {
              Text(verbatim: person.name)
                .foregroundStyle(.primary)
              Text(verbatim: person.username)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if selected.contains(person.id) {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
            }
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }
    }
    .formStyle(.grouped)
    .searchable(text: $search)
    .navigationTitle("People")
  }

  private var people: [Person] {
    var byId: [String: Person] = [:]
    for relationship in gw.user.relationships.values where relationship.type == .friend {
      let user = relationship.user
      byId[user.id.rawValue] = Person(
        id: user.id.rawValue,
        name: relationship.nickname ?? user.global_name ?? user.username ?? "",
        username: user.username ?? ""
      )
    }
    for channel in gw.user.privateChannels.values where channel.type == .dm {
      guard let user = channel.recipients?.first, byId[user.id.rawValue] == nil else { continue }
      byId[user.id.rawValue] = Person(
        id: user.id.rawValue, name: user.global_name ?? user.username, username: user.username
      )
    }
    return byId.values
      .filter {
        search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
          || $0.username.localizedCaseInsensitiveContains(search)
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

// MARK: - Servers and Channels

/// Servers with their text channels. `selected` ticks them into Aicord's own
/// list; `silenced` sets them to Nothing on the Discord account.
struct NotificationPlaceList: View {
  typealias Level = UserGuildSettingsStore.Level

  enum Mode {
    case selected(selection: Binding<String>)
    case silenced
  }

  @Environment(\.gateway) var gw
  let mode: Mode
  @State private var search = ""
  @State private var saving: Set<String> = []
  @State private var error: String?

  /// What a server or channel was set to before it was silenced, to go back to.
  @AppStorage("Paicord.Notifications.LevelsBeforeSilencing") private var previousLevels = ""

  var body: some View {
    Form {
      ForEach(guilds, id: \.id) { guild in
        let channels = textChannels(of: guild)
        DisclosureGroup {
          ForEach(channels, id: \.id) { channel in
            row(Text(verbatim: "#" + (channel.name ?? "")), guild: guild.id, channel: channel.id)
          }
        } label: {
          row(Text(verbatim: guild.name).bold(), guild: guild.id, channel: nil)
        }
      }
    }
    .formStyle(.grouped)
    .searchable(text: $search)
    .navigationTitle(isSilenced ? "Silenced in Discord" : "Servers and Channels")
    .alert(
      "Couldn't Save", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(error ?? "")
    }
  }

  private var isSilenced: Bool {
    if case .silenced = mode { return true }
    return false
  }

  private func row(_ title: Text, guild: GuildSnowflake, channel: ChannelSnowflake?) -> some View {
    let id = channel?.rawValue ?? guild.rawValue
    return Button {
      toggle(guild: guild, channel: channel)
    } label: {
      HStack {
        title.foregroundStyle(.primary)
        Spacer()
        if saving.contains(id) {
          ProgressView().controlSize(.small)
        } else if isOn(guild: guild, channel: channel) {
          Image(systemName: isSilenced ? "bell.slash.fill" : "checkmark")
            .foregroundStyle(isSilenced ? .red : .accentColor)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(saving.contains(id))
  }

  private func isOn(guild: GuildSnowflake, channel: ChannelSnowflake?) -> Bool {
    switch mode {
    case .selected(let selection):
      return selection.wrappedValue.split(separator: ",").contains {
        $0 == (channel?.rawValue ?? guild.rawValue)
      }
    case .silenced:
      let settings = gw.userGuildSettings
      if let channel { return settings.channelLevel(guildId: guild, channelId: channel) == .nothing }
      return settings.guildLevel(guild) == .nothing
    }
  }

  private func toggle(guild: GuildSnowflake, channel: ChannelSnowflake?) {
    let id = channel?.rawValue ?? guild.rawValue
    switch mode {
    case .selected(let selection):
      var set = Set(selection.wrappedValue.split(separator: ",").map(String.init))
      if set.contains(id) { set.remove(id) } else { set.insert(id) }
      selection.wrappedValue = set.sorted().joined(separator: ",")
    case .silenced:
      let settings = gw.userGuildSettings
      let current =
        channel.map { settings.channelLevel(guildId: guild, channelId: $0) }
        ?? settings.guildLevel(guild)
      var previous = decodedLevels
      let target: Level
      if current == .nothing {
        target = previous[id].flatMap(Level.init) ?? .inherit
        previous[id] = nil
      } else {
        target = .nothing
        previous[id] = current.rawValue
      }
      saving.insert(id)
      Task {
        defer { saving.remove(id) }
        do {
          try await settings.setLevel(target, guildId: guild, channelId: channel)
          previousLevels = previous.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        } catch {
          self.error = error.localizedDescription
        }
      }
    }
  }

  private var decodedLevels: [String: Int] {
    previousLevels.split(separator: ",").reduce(into: [:]) { result, pair in
      let parts = pair.split(separator: "=")
      if parts.count == 2, let level = Int(parts[1]) { result[String(parts[0])] = level }
    }
  }

  private var guilds: [Guild] {
    gw.user.guilds.values
      .filter { guild in
        search.isEmpty || guild.name.localizedCaseInsensitiveContains(search)
          || textChannels(of: guild).contains { $0.name?.localizedCaseInsensitiveContains(search) == true }
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private func textChannels(of guild: Guild) -> [DiscordChannel] {
    (guild.channels ?? [])
      .filter { $0.type == .guildText || $0.type == .guildAnnouncement }
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }
}
