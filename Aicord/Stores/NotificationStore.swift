//
//  NotificationStore.swift
//  Aicord
//
//  Created by Lakafior on 30/10/2026.
//

import Foundation
import AicordKit
import SwiftUI
@preconcurrency import UserNotifications

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// Local notifications for messages arriving on the gateway. There's no push:
/// on iOS they come while Aicord is open or for a short while after leaving it.
@MainActor
@Observable
class NotificationStore: DiscordDataStore {
  typealias Prefs = NotificationPrefs

  var gateway: GatewayStore?
  var eventTask: Task<Void, Never>?

  /// The system permission, refreshed when Settings shows it.
  var authorization: UNAuthorizationStatus = .notDetermined

  @ObservationIgnored private var badgeTask: Task<Void, Never>?

  func setupEventHandling() {
    eventTask?.cancel()
    guard let gateway = gateway?.gateway else { return }
    let events = gateway.events
    eventTask = Task {
      for await event in events {
        switch event.data {
        case .ready:
          observeBadge()
        case .messageCreate(let message):
          handleMessageCreate(message)
        case .relationshipAdd(let relationship):
          handleRelationshipAdd(relationship)
        default:
          break
        }
      }
    }
  }

  // MARK: - Permission

  func refreshAuthorization() async {
    authorization = await UNUserNotificationCenter.current().notificationSettings()
      .authorizationStatus
  }

  func requestAuthorization() async {
    _ = try? await UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .sound, .badge]
    )
    await refreshAuthorization()
    updateBadge()
  }

  static func openSystemSettings() {
    #if os(iOS)
      if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
        UIApplication.shared.open(url)
      }
    #elseif os(macOS)
      let id = Bundle.main.bundleIdentifier ?? ""
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)"
      ) {
        NSWorkspace.shared.open(url)
      }
    #endif
  }

  func sendTest() {
    post(
      Content(
        title: String(localized: "Aicord"),
        body: String(localized: "Notifications are working."),
        thread: "test"
      ),
      id: UUID().uuidString
    )
  }

  // MARK: - Messages

  private func handleMessageCreate(_ message: Gateway.MessageCreate) {
    guard let gw = gateway, let me = gw.user.currentUser?.id else { return }
    guard let author = message.author, author.id != me else { return }
    guard Prefs.bool(Prefs.enabledKey) else { return }
    guard message.type == .default || message.type == .reply else { return }
    // @silent messages never notify, like in Discord
    if message.flags?.contains(.suppressNotifications) == true { return }
    if gw.user.relationships[author.id]?.type == .blocked { return }
    if isViewing(message.channel_id) { return }

    let isDM = message.guild_id == nil && gw.user.privateChannels[message.channel_id] != nil
    let notifies: Bool
    if isDM {
      notifies = notifiesDM(from: author.id, channelId: message.channel_id)
    } else if let guildId = message.guild_id {
      notifies = notifiesServer(message, guildId: guildId, me: me)
    } else {
      notifies = false
    }
    guard notifies else { return }

    let text = plainText(of: message)
    let origin = gw.origin(authorId: author.id, inServer: !isDM)
    if WordFilter.hides(text, origin: origin) { return }

    post(content(for: message, author: author, text: text, isDM: isDM), id: message.id.rawValue)
  }

  /// Someone's looking at the channel already: the app is in front and it's open.
  private func isViewing(_ channelId: ChannelSnowflake) -> Bool {
    guard Self.isAppActive else { return false }
    return AicordAppState.instances.values.contains { state in
      #if os(iOS)
        guard state.chatOpen else { return false }
      #endif
      return state.selectedChannel == channelId
    }
  }

  static var isAppActive: Bool {
    #if os(iOS)
      UIApplication.shared.applicationState == .active
    #elseif os(macOS)
      NSApp.isActive
    #else
      false
    #endif
  }

  func notifiesDM(from author: UserSnowflake, channelId: ChannelSnowflake) -> Bool {
    guard let gw = gateway else { return false }
    // muted in Discord (on any client)
    if gw.userGuildSettings.isMuted(guildId: nil, channelId: channelId) { return false }
    let listed = Prefs.ids(Prefs.dmUsersKey).contains(author.rawValue)
    switch Prefs.dmMode {
    case .everyone: return true
    case .friends: return gw.user.relationships[author]?.type == .friend
    case .whitelist: return listed
    case .blacklist: return !listed
    }
  }

  /// Follows the server's notification settings from Discord, then Aicord's own
  /// list. Muted servers and channels only let direct mentions through.
  func notifiesServer(_ message: Gateway.MessageCreate, guildId: GuildSnowflake, me: UserSnowflake)
    -> Bool
  {
    guard let gw = gateway else { return false }
    let settings = gw.userGuildSettings
    let stored = settings.userGuildSettings[guildId]
    let channel = channel(message.channel_id, in: guildId)
    let parentId = channel?.parent_id.map { ChannelSnowflake($0) }

    if Prefs.serverMode == .whitelist {
      let listed = Prefs.ids(Prefs.serverPlacesKey)
      let places = [guildId.rawValue, message.channel_id.rawValue, parentId?.rawValue]
      guard places.contains(where: { $0.map(listed.contains) ?? false }) else { return false }
    }

    let personal = message.mentions.contains { $0.id == me }
    var roles = false
    if !message.mention_roles.isEmpty, stored?.suppress_roles != true, Prefs.bool(Prefs.rolesKey) {
      let mine = gw.existingGuildStore(for: guildId)?.member(me)?.roles ?? []
      roles = mine.contains { message.mention_roles.contains($0) }
    }
    let everyone =
      message.mention_everyone && stored?.suppress_everyone != true && Prefs.bool(Prefs.everyoneKey)
    let keyword = Self.matchesKeyword(message.content)

    // the most specific level wins: channel, its category, the server, its default
    var level = settings.channelLevel(guildId: guildId, channelId: message.channel_id)
    if level == .inherit, let parentId {
      level = settings.channelLevel(guildId: guildId, channelId: parentId)
    }
    if level == .inherit { level = settings.guildLevel(guildId) }
    if level == .inherit {
      level = gw.user.guilds[guildId]?.default_message_notifications == .allMessages
        ? .allMessages : .onlyMentions
    }

    let muted =
      settings.isMuted(guildId: guildId)
      || settings.isMuted(guildId: guildId, channelId: message.channel_id)
      || parentId.map { settings.isMuted(guildId: guildId, channelId: $0) } ?? false
    if muted { return level != .nothing && (personal || roles) }

    switch level {
    case .nothing: return false
    case .allMessages: return true
    case .onlyMentions, .inherit: return personal || roles || everyone || keyword
    }
  }

  static func matchesKeyword(_ text: String) -> Bool {
    let words = Prefs.string(Prefs.keywordsKey)
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !words.isEmpty else { return false }
    return words.contains { word in
      text.range(
        of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
        options: [.regularExpression, .caseInsensitive]
      ) != nil
    }
  }

  func channel(_ id: ChannelSnowflake, in guildId: GuildSnowflake) -> DiscordChannel? {
    gateway?.existingGuildStore(for: guildId)?.channels[id]
      ?? gateway?.user.guilds[guildId]?.channels?.first { $0.id == id }
  }

  // MARK: - Content

  struct Content {
    var title: String
    var subtitle = ""
    var body: String
    var thread: String
    var userInfo: [String: String] = [:]
    var category = ""
  }

  private func content(
    for message: Gateway.MessageCreate, author: DiscordUser, text: String, isDM: Bool
  ) -> Content {
    let name = message.member?.nick ?? author.global_name ?? author.username
    var place = ""
    if isDM {
      let channel = gateway?.user.privateChannels[message.channel_id]
      if let channel, channel.type == .groupDm {
        place =
          channel.name
          ?? channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
          ?? ""
      }
    } else if let guildId = message.guild_id {
      let channelName = channel(message.channel_id, in: guildId)?.name.map { "#\($0)" }
      let guildName = gateway?.user.guilds[guildId]?.name
      place = [channelName, guildName].compactMap(\.self).joined(separator: " · ")
    }

    var content = Content(title: name, body: text, thread: message.channel_id.rawValue)
    switch Prefs.preview {
    case .full:
      content.subtitle = place
    case .author:
      content.subtitle = place
      content.body = String(localized: "New message")
    case .hidden:
      content.title = String(localized: "Aicord")
      content.body = String(localized: "New message")
    }
    content.userInfo["channel"] = message.channel_id.rawValue
    if let guildId = message.guild_id { content.userInfo["guild"] = guildId.rawValue }
    content.userInfo["message"] = message.id.rawValue
    content.category = Self.messageCategory
    return content
  }

  /// The message as it would read in a notification: mentions, channels and
  /// emoji spelled out, and a note for messages with only files or stickers.
  func plainText(of message: Gateway.MessageCreate) -> String {
    var text = message.content
    for user in message.mentions {
      let name = user.global_name ?? user.username
      text = text.replacingOccurrences(of: "<@\(user.id.rawValue)>", with: "@\(name)")
      text = text.replacingOccurrences(of: "<@!\(user.id.rawValue)>", with: "@\(name)")
    }
    if let guildId = message.guild_id {
      for role in message.mention_roles {
        let name = gateway?.user.guilds[guildId]?.roles.first { $0.id == role }?.name ?? "role"
        text = text.replacingOccurrences(of: "<@&\(role.rawValue)>", with: "@\(name)")
      }
      text = text.replacing(/<#(\d+)>/) { match in
        let id = ChannelSnowflake(String(match.output.1))
        return "#" + (channel(id, in: guildId)?.name ?? "channel")
      }
    }
    text = text.replacing(/<a?(:\w+:)\d+>/) { String($0.output.1) }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty {
      if !message.attachments.isEmpty {
        text = String(localized: "Sent an attachment")
      } else if message.sticker_items?.isEmpty == false {
        text = String(localized: "Sent a sticker")
      } else if !message.embeds.isEmpty {
        text = String(localized: "Sent an embed")
      }
    }
    return text
  }

  private func handleRelationshipAdd(_ relationship: DiscordRelationship) {
    guard relationship.type == .incomingRequest,
      Prefs.bool(Prefs.enabledKey), Prefs.bool(Prefs.friendRequestsKey)
    else { return }
    let user = relationship.user
    let name = user.global_name ?? user.username ?? ""
    post(
      Content(
        title: String(localized: "Friend Request"),
        body: String(localized: "\(name) sent you a friend request."),
        thread: "friend-requests"
      ),
      id: "friend-\(relationship.id.rawValue)"
    )
  }

  // MARK: - Delivery

  /// Quiet hours or Do Not Disturb: the notification goes to the list without
  /// a banner or sound.
  var isQuiet: Bool {
    if Prefs.bool(Prefs.dndKey),
      gateway?.settings.userSettings.status.status.value == "dnd"
    {
      return true
    }
    guard Prefs.bool(Prefs.quietHoursKey) else { return false }
    let parts = Calendar.current.dateComponents([.hour, .minute], from: .now)
    let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    let start = Prefs.int(Prefs.quietStartKey)
    let end = Prefs.int(Prefs.quietEndKey)
    return start <= end ? (now >= start && now < end) : (now >= start || now < end)
  }

  private func post(_ content: Content, id: String) {
    let notification = UNMutableNotificationContent()
    notification.title = content.title
    notification.subtitle = content.subtitle
    notification.body = content.body
    notification.threadIdentifier = content.thread
    notification.categoryIdentifier = content.category
    notification.userInfo = content.userInfo
    if isQuiet {
      notification.interruptionLevel = .passive
    } else if Prefs.bool(Prefs.soundKey) {
      notification.sound = .default
    }
    let request = UNNotificationRequest(identifier: id, content: notification, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  /// Takes a channel's notifications out of the list once it's been read.
  func clearDelivered(channelId: ChannelSnowflake) {
    let center = UNUserNotificationCenter.current()
    Task {
      let ids = await center.deliveredNotifications()
        .filter { $0.request.content.threadIdentifier == channelId.rawValue }
        .map(\.request.identifier)
      if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
  }

  // MARK: - Badge

  /// The number on the app icon: unread DMs, plus mentions on servers that
  /// aren't muted when asked for.
  var badgeCount: Int {
    guard let gw = gateway else { return 0 }
    let mode = Prefs.badgeMode
    guard mode != .off else { return 0 }
    let dms = gw.user.privateChannels.values.reduce(0) { total, channel in
      gw.userGuildSettings.isMuted(guildId: nil, channelId: channel.id)
        ? total : total + gw.readStates.mentionCount(channelId: channel.id)
    }
    guard mode == .all else { return dms }
    return gw.user.guilds.values.reduce(dms) { total, guild in
      gw.userGuildSettings.isMuted(guildId: guild.id)
        ? total : total + GuildButton.mentionCount(guild, readStates: gw.readStates)
    }
  }

  /// Keeps the icon's number in step with the read states while connected.
  func observeBadge() {
    withObservationTracking {
      _ = badgeCount
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.updateBadge()
        self?.observeBadge()
      }
    }
    updateBadge()
  }

  func updateBadge() {
    let count = badgeCount
    badgeTask?.cancel()
    badgeTask = Task {
      // several read states change together; set the number once
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
  }

  // MARK: - Responses

  static let messageCategory = "message"
  static let markReadAction = "mark-read"
  static let replyAction = "reply"

  static func registerCategories() {
    let markRead = UNNotificationAction(
      identifier: markReadAction, title: String(localized: "Mark as Read"))
    let reply = UNTextInputNotificationAction(
      identifier: replyAction, title: String(localized: "Reply"),
      textInputButtonTitle: String(localized: "Send"),
      textInputPlaceholder: String(localized: "Message"))
    let category = UNNotificationCategory(
      identifier: messageCategory, actions: [reply, markRead], intentIdentifiers: [])
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  func handle(action: String, userInfo: [String: String], text: String?) async {
    guard let gw = gateway, let rawChannel = userInfo["channel"] else { return }
    let channelId = ChannelSnowflake(rawChannel)
    let guildId = userInfo["guild"].map(GuildSnowflake.init)
    switch action {
    case Self.markReadAction:
      await markRead(channelId: channelId, messageId: userInfo["message"])
    case Self.replyAction:
      guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      let res = try? await gw.client.createMessage(
        channelId: channelId, payload: .init(content: text)
      )
      if let message = try? res?.decode() {
        await markRead(channelId: channelId, messageId: message.id.rawValue)
      }
    case UNNotificationDefaultActionIdentifier:
      open(guildId: guildId, channelId: channelId)
    default:
      break
    }
  }

  private func markRead(channelId: ChannelSnowflake, messageId: String?) async {
    guard let gw = gateway, let messageId else { return }
    let id = MessageSnowflake(messageId)
    let res = try? await gw.client.acknowledgeMessage(
      channelId: channelId, messageId: id, payload: Payloads.AcknowledgeMessage()
    )
    if (try? res?.guardSuccess()) != nil {
      gw.readStates.applyAck(channelId: channelId, messageId: id)
    }
  }

  private func open(guildId: GuildSnowflake?, channelId: ChannelSnowflake) {
    guard let appState = AicordAppState.instances.values.first else { return }
    appState.selectedGuild = guildId
    appState.selectedChannel = channelId
    appState.chatOpen = true
    appState.openedFromNotification += 1
    #if os(macOS)
      NSApp.activate()
    #endif
  }

  // MARK: - Background (iOS)

  #if os(iOS)
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Keeps the connection for the short time iOS allows after leaving the app,
    /// so messages arriving meanwhile still notify.
    func enterBackground() {
      updateBadge()
      guard backgroundTask == .invalid else { return }
      backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Notifications") {
        [weak self] in
        MainActor.assumeIsolated { self?.endBackground() }
      }
    }

    func endBackground() {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  #endif
}

/// Hands the system's notification callbacks to the gateway's store.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
  static let shared = NotificationCenterDelegate()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let passive = notification.request.content.interruptionLevel == .passive
    if passive { return [.list] }
    let showsInApp = await MainActor.run { NotificationPrefs.bool(NotificationPrefs.inAppKey) }
    return showsInApp ? [.banner, .list, .sound] : [.list]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let action = response.actionIdentifier
    let userInfo = response.notification.request.content.userInfo
      .reduce(into: [String: String]()) { result, pair in
        if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
      }
    let text = (response as? UNTextInputNotificationResponse)?.userText
    await Task { @MainActor in
      await GatewayStore.shared.notifications.handle(action: action, userInfo: userInfo, text: text)
    }.value
  }
}

/// Aicord's own notification choices, kept on this device.
enum NotificationPrefs {
  static let enabledKey = "Paicord.Notifications.Enabled"
  static let previewKey = "Paicord.Notifications.Preview"
  static let soundKey = "Paicord.Notifications.Sound"
  static let badgeKey = "Paicord.Notifications.Badge"
  static let inAppKey = "Paicord.Notifications.InApp"
  static let dmModeKey = "Paicord.Notifications.DMMode"
  static let dmUsersKey = "Paicord.Notifications.DMUsers"
  static let serverModeKey = "Paicord.Notifications.ServerMode"
  static let serverPlacesKey = "Paicord.Notifications.ServerPlaces"
  static let everyoneKey = "Paicord.Notifications.Everyone"
  static let rolesKey = "Paicord.Notifications.Roles"
  static let keywordsKey = "Paicord.Notifications.Keywords"
  static let friendRequestsKey = "Paicord.Notifications.FriendRequests"
  static let dndKey = "Paicord.Notifications.QuietOnDND"
  static let quietHoursKey = "Paicord.Notifications.QuietHours"
  static let quietStartKey = "Paicord.Notifications.QuietStart"
  static let quietEndKey = "Paicord.Notifications.QuietEnd"

  enum Preview: String { case full, author, hidden }
  enum Badge: String { case off, directMessages, all }
  enum DMMode: String { case everyone, friends, whitelist, blacklist }
  enum ServerMode: String { case all, whitelist, blacklist }

  /// Defaults for keys that were never set.
  nonisolated(unsafe) static let defaults: [String: Any] = [
    enabledKey: true, soundKey: true, inAppKey: true, everyoneKey: true, rolesKey: true,
    friendRequestsKey: true, dndKey: true, quietStartKey: 22 * 60, quietEndKey: 7 * 60,
  ]

  static func bool(_ key: String) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? defaults[key] as? Bool ?? false
  }

  static func int(_ key: String) -> Int {
    UserDefaults.standard.object(forKey: key) as? Int ?? defaults[key] as? Int ?? 0
  }

  static func string(_ key: String) -> String {
    UserDefaults.standard.string(forKey: key) ?? ""
  }

  /// Lists are IDs separated by commas, like the word filter's languages.
  static func ids(_ key: String) -> Set<String> {
    Set(string(key).split(separator: ",").map(String.init))
  }

  static var preview: Preview { Preview(rawValue: string(previewKey)) ?? .full }
  static var badgeMode: Badge { Badge(rawValue: string(badgeKey)) ?? .directMessages }
  static var dmMode: DMMode { DMMode(rawValue: string(dmModeKey)) ?? .everyone }
  static var serverMode: ServerMode { ServerMode(rawValue: string(serverModeKey)) ?? .all }
}
