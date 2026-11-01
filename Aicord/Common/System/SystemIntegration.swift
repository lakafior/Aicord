//
//  SystemIntegration.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//
//  Spotlight, the widgets' data and links coming in from the system
//  (widgets, Spotlight results, Handoff, App Intents). Everything is written
//  from what the running app already has; nothing here talks to Discord.
//

import AicordKit
import CoreSpotlight
import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import os

/// A channel or DM the system knows about, for Spotlight and App Intents.
struct DirectoryEntry: Codable, Hashable, Sendable {
  var link: AicordLink
  /// "#channel", the other person's name or the group's name.
  var name: String
  /// The server, empty for a DM.
  var server: String
  var isDirectMessage: Bool { link.guildID == nil }
}

@MainActor
final class SystemIntegration {
  static let shared = SystemIntegration()

  static let spotlightEnabledKey = "Aicord.Spotlight.Enabled"
  static let channelActivityType = "net.smigi.aicord.channel"

  private enum Domain {
    static let channels = "channels"
    static let saved = "saved"
  }

  private let index = CSSearchableIndex(name: "Aicord")
  private let logger = Logger(subsystem: "net.smigi.aicord", category: "System")
  private var gateway: GatewayStore { GatewayStore.shared }
  private var spotlightTask: Task<Void, Never>?
  private var widgetTask: Task<Void, Never>?
  private var lastWidgetSnapshot: WidgetSnapshot? = WidgetSnapshot.load()
  /// The account the index and the widget data belong to.
  private var observedAccount: UserSnowflake?

  static var spotlightEnabled: Bool {
    UserDefaults.standard.object(forKey: spotlightEnabledKey) as? Bool ?? true
  }

  private init() {}

  /// Called once at launch.
  func start() {
    observedAccount = gateway.accounts.currentAccountID
    observeAccount()
    observeSaved()
    #if os(iOS)
      VoiceLiveActivityController.shared.start()
    #endif
  }

  /// The gateway is ready: guilds, DMs and read states are in.
  func gatewayReady() {
    scheduleChannelIndex()
    observeWidgetSnapshot()
  }

  // MARK: - Account

  private func observeAccount() {
    withObservationTracking {
      _ = gateway.accounts.currentAccountID
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        let account = self.gateway.accounts.currentAccountID
        if account != self.observedAccount {
          self.observedAccount = account
          self.clearAccountData()
        }
        self.observeAccount()
      }
    }
  }

  /// Logging out or switching accounts: nothing of the old account stays in
  /// Spotlight, the widgets or the app's channel list for Shortcuts.
  func clearAccountData() {
    spotlightTask?.cancel()
    widgetTask?.cancel()
    index.deleteAllSearchableItems { _ in }
    writeDirectory([])
    if let url = AicordAppGroup.widgetSnapshotURL {
      try? FileManager.default.removeItem(at: url)
    }
    lastWidgetSnapshot = nil
    WidgetCenter.shared.reloadAllTimelines()
    #if os(iOS)
      VoiceLiveActivityController.shared.endAll()
    #endif
  }

  // MARK: - Directory

  /// DMs (newest first), then each server's text channels.
  func liveDirectory() -> [DirectoryEntry] {
    let gw = gateway
    var entries: [DirectoryEntry] = []
    let dms = gw.user.privateChannels.values.sorted {
      ($0.last_message_id ?? .init("0")) > ($1.last_message_id ?? .init("0"))
    }
    for channel in dms {
      let name = Self.directMessageName(channel)
      guard !name.isEmpty else { continue }
      entries.append(
        DirectoryEntry(
          link: AicordLink(guildID: nil, channelID: channel.id.rawValue), name: name, server: ""))
    }
    let guilds = gw.user.guilds.values.sorted { $0.name < $1.name }
    for guild in guilds {
      let store = gw.existingGuildStore(for: guild.id)
      for channel in (guild.channels ?? []).sorted(by: { ($0.position ?? 0) < ($1.position ?? 0) })
      where Self.isIndexable(channel)
        && store?.hasPermission(channel: channel, .viewChannel) != false
      {
        entries.append(
          DirectoryEntry(
            link: AicordLink(guildID: guild.id.rawValue, channelID: channel.id.rawValue),
            name: "#\(channel.name ?? "")", server: guild.name))
      }
    }
    return entries
  }

  /// The live list while connected, otherwise the one saved last time, so
  /// Shortcuts can still pick a channel before the app has connected.
  func directory() -> [DirectoryEntry] {
    let live = liveDirectory()
    return live.isEmpty ? Self.loadDirectory() : live
  }

  private static func isIndexable(_ channel: DiscordChannel) -> Bool {
    switch channel.type {
    case .guildText, .guildAnnouncement, .guildForum, .guildMedia, .guildVoice: true
    default: false
    }
  }

  static func directMessageName(_ channel: DiscordChannel) -> String {
    if channel.type == .groupDm {
      return channel.name
        ?? channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ") ?? ""
    }
    guard let other = channel.recipients?.first else { return "" }
    return other.global_name ?? other.username
  }

  private static var directoryURL: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: "ChannelDirectory.json")
  }

  private static func loadDirectory() -> [DirectoryEntry] {
    guard let url = directoryURL, let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([DirectoryEntry].self, from: data)) ?? []
  }

  private func writeDirectory(_ entries: [DirectoryEntry]) {
    guard let url = Self.directoryURL else { return }
    if entries.isEmpty {
      try? FileManager.default.removeItem(at: url)
    } else {
      try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
  }

  // MARK: - Spotlight

  /// Guild lists arrive in pieces after READY; index once they've settled.
  private func scheduleChannelIndex() {
    spotlightTask?.cancel()
    spotlightTask = Task {
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      let entries = liveDirectory()
      writeDirectory(entries)
      guard Self.spotlightEnabled else { return }
      await indexChannels(entries)
      await indexSaved()
    }
  }

  private func indexChannels(_ entries: [DirectoryEntry]) async {
    let items = entries.map { entry in
      let attributes = CSSearchableItemAttributeSet(contentType: .content)
      attributes.title = entry.name
      attributes.displayName = entry.name
      attributes.contentDescription =
        entry.isDirectMessage
        ? String(localized: "Direct Message") : entry.server
      attributes.keywords = [entry.server, "Aicord", "Discord"].filter { !$0.isEmpty }
      attributes.contentURL = entry.link.url
      let item = CSSearchableItem(
        uniqueIdentifier: "channel:\(entry.link.identifier)",
        domainIdentifier: Domain.channels, attributeSet: attributes)
      item.expirationDate = .distantFuture
      return item
    }
    do {
      try await index.deleteSearchableItems(withDomainIdentifiers: [Domain.channels])
      guard !Task.isCancelled else { return }
      try await index.indexSearchableItems(items)
      logger.info("Spotlight: \(items.count) channels indexed")
    } catch {
      logger.error("Spotlight: indexing channels failed: \(error.localizedDescription)")
    }
  }

  /// Saved messages are the only message text that goes into Spotlight.
  private func indexSaved() async {
    let items = SavedItemsStore.shared.saved.map { saved in
      let message = saved.message
      let link = AicordLink(
        guildID: message.guildID, channelID: message.channelID, messageID: message.id)
      let attributes = CSSearchableItemAttributeSet(contentType: .text)
      attributes.title = message.authorName
      attributes.displayName = message.authorName
      attributes.contentDescription = [message.place, message.text].filter { !$0.isEmpty }
        .joined(separator: "\n")
      attributes.textContent = message.text
      attributes.contentCreationDate = message.date
      attributes.keywords = [message.place, String(localized: "Saved")]
      attributes.contentURL = link.url
      let item = CSSearchableItem(
        uniqueIdentifier: "saved:\(link.identifier)",
        domainIdentifier: Domain.saved, attributeSet: attributes)
      item.expirationDate = .distantFuture
      return item
    }
    do {
      try await index.deleteSearchableItems(withDomainIdentifiers: [Domain.saved])
      guard !items.isEmpty, !Task.isCancelled else { return }
      try await index.indexSearchableItems(items)
      logger.info("Spotlight: \(items.count) saved messages indexed")
    } catch {
      logger.error("Spotlight: indexing saved messages failed: \(error.localizedDescription)")
    }
  }

  private func observeSaved() {
    withObservationTracking {
      _ = SavedItemsStore.shared.saved
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        if Self.spotlightEnabled, self.gateway.accounts.currentAccountID != nil {
          await self.indexSaved()
        }
        self.observeSaved()
      }
    }
  }

  /// Settings switch: off removes everything Aicord put in Spotlight.
  func setSpotlightEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: Self.spotlightEnabledKey)
    spotlightTask?.cancel()
    if enabled {
      guard gateway.accounts.currentAccountID != nil else { return }
      spotlightTask = Task {
        await indexChannels(liveDirectory())
        await indexSaved()
      }
    } else {
      index.deleteAllSearchableItems { _ in }
    }
  }

  // MARK: - Widgets

  /// Rewrites the widgets' data whenever read states change, at most once a
  /// second, and asks WidgetKit to reload only when something visible changed.
  private func observeWidgetSnapshot() {
    withObservationTracking {
      _ = makeWidgetSnapshot()
    } onChange: { [weak self] in
      Task { @MainActor in
        self?.scheduleWidgetWrite()
        self?.observeWidgetSnapshot()
      }
    }
    scheduleWidgetWrite()
  }

  private func scheduleWidgetWrite() {
    widgetTask?.cancel()
    widgetTask = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, gateway.accounts.currentAccountID != nil else { return }
      let snapshot = makeWidgetSnapshot()
      guard !snapshot.hasSameContent(as: lastWidgetSnapshot) else { return }
      write(snapshot)
    }
  }

  /// Leaving the app: the widgets' "as of" time becomes now, even when the
  /// counts haven't changed.
  func flushWidgetSnapshot() {
    guard gateway.accounts.currentAccountID != nil, lastWidgetSnapshot != nil else { return }
    widgetTask?.cancel()
    write(makeWidgetSnapshot())
  }

  private func write(_ snapshot: WidgetSnapshot) {
    guard let url = AicordAppGroup.widgetSnapshotURL else { return }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(snapshot) else { return }
    try? data.write(to: url, options: .atomic)
    lastWidgetSnapshot = snapshot
    WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.widgetKind)
  }

  /// The same counting as the app icon's badge and the server list.
  func makeWidgetSnapshot() -> WidgetSnapshot {
    let gw = gateway
    let readStates = gw.readStates
    let settings = gw.userGuildSettings
    var mentions = 0
    var unreadDMs = 0
    var places: [WidgetSnapshot.Place] = []

    for channel in gw.user.privateChannels.values
    where !settings.isMuted(guildId: nil, channelId: channel.id) {
      let count = readStates.mentionCount(channelId: channel.id)
      if readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id) {
        unreadDMs += 1
      }
      guard count > 0 else { continue }
      mentions += count
      places.append(
        .init(
          link: AicordLink(guildID: nil, channelID: channel.id.rawValue),
          name: Self.directMessageName(channel), server: "", mentions: count))
    }

    var unreadServers = 0
    for guild in gw.user.guilds.values where !settings.isMuted(guildId: guild.id) {
      var guildUnread = false
      for channel in guild.channels ?? []
      where channel.type == .guildText || channel.type == .guildAnnouncement {
        if !guildUnread,
          readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id),
          !settings.isMuted(guildId: guild.id, channelId: channel.id)
        {
          guildUnread = true
        }
        let count = readStates.mentionCount(channelId: channel.id)
        guard count > 0 else { continue }
        mentions += count
        places.append(
          .init(
            link: AicordLink(guildID: guild.id.rawValue, channelID: channel.id.rawValue),
            name: "#\(channel.name ?? "")", server: guild.name, mentions: count))
      }
      if guildUnread { unreadServers += 1 }
    }

    places.sort { $0.mentions != $1.mentions ? $0.mentions > $1.mentions : $0.name < $1.name }
    return WidgetSnapshot(
      mentions: mentions, unreadDirectMessages: unreadDMs, unreadServers: unreadServers,
      places: Array(places.prefix(6)), updatedAt: .now)
  }

  // MARK: - Opening

  /// Opens a channel (and a message in it) from outside the app.
  func open(_ link: AicordLink) {
    guard gateway.accounts.currentAccountID != nil else { return }
    AicordAppState.openExternally(
      guild: link.guildID.map(GuildSnowflake.init),
      channel: ChannelSnowflake(link.channelID),
      message: link.messageID.map(MessageSnowflake.init))
  }

  /// A Spotlight result or a Handoff activity; `false` when it isn't ours.
  @discardableResult
  func `continue`(_ activity: NSUserActivity) -> Bool {
    switch activity.activityType {
    case CSSearchableItemActionType:
      guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
        return false
      }
      let raw = id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
      guard let link = AicordLink(identifier: raw) else { return false }
      open(link)
      return true
    case Self.channelActivityType:
      guard let raw = activity.userInfo?["link"] as? String,
        let link = AicordLink(identifier: raw)
      else { return false }
      open(link)
      return true
    default:
      return false
    }
  }
}

extension AicordAppState {
  /// The window a notification, widget, Spotlight result or shortcut opens
  /// channels in.
  static var externalTarget: AicordAppState? {
    main ?? instances.values.first(where: { $0 !== sharedEphemeral })
  }

  static func openExternally(
    guild: GuildSnowflake?, channel: ChannelSnowflake, message: MessageSnowflake? = nil
  ) {
    guard let appState = externalTarget else { return }
    if let message {
      appState.open(guild: guild, channel: channel, message: message)
    } else {
      appState.selectedGuild = guild
      appState.selectedChannel = channel
      appState.chatOpen = true
    }
    appState.openedFromNotification += 1
    #if os(macOS)
      NSApp.activate()
    #endif
  }
}

/// Handoff: the open channel, so another device signed in to the same Apple
/// Account can pick it up.
struct ChannelHandoff: ViewModifier {
  let appState: AicordAppState
  @Environment(\.gateway) private var gw

  func body(content: Content) -> some View {
    content.userActivity(
      SystemIntegration.channelActivityType,
      isActive: appState.selectedChannel != nil && gw.accounts.currentAccountID != nil
    ) { activity in
      guard let channel = appState.selectedChannel else { return }
      let link = AicordLink(
        guildID: appState.selectedGuild?.rawValue, channelID: channel.rawValue)
      let place = gw.placeName(channelId: channel, guildId: appState.selectedGuild)
      activity.title = place.isEmpty ? String(localized: "Aicord") : place
      activity.userInfo = ["link": link.identifier]
      activity.requiredUserInfoKeys = ["link"]
      activity.isEligibleForHandoff = true
      activity.isEligibleForSearch = false
      activity.targetContentIdentifier = link.identifier
    }
  }
}
