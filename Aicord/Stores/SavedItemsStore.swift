//
//  SavedItemsStore.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//

import AicordKit
import Foundation
@preconcurrency import UserNotifications

/// A message as it looked when it was saved, reminded about or ghost-pinged:
/// enough to list it and jump to it without loading the channel.
struct MessageSnapshot: Codable, Hashable, Identifiable {
  var id: String
  var channelID: String
  var guildID: String?
  var authorID: String?
  var authorName: String
  var avatarURL: String?
  var place: String
  var text: String
  var date: Date

  var messageID: MessageSnowflake { MessageSnowflake(id) }
  var channel: ChannelSnowflake { ChannelSnowflake(channelID) }
  var guild: GuildSnowflake? { guildID.map(GuildSnowflake.init) }
}

extension GatewayStore {
  /// "#channel · Server", or the group's name in a group DM; empty in a DM.
  func placeName(channelId: ChannelSnowflake, guildId: GuildSnowflake?) -> String {
    if let guildId {
      let channel =
        existingGuildStore(for: guildId)?.channels[channelId]
        ?? existingGuildStore(for: guildId)?.threads[channelId]
        ?? user.guilds[guildId]?.channels?.first { $0.id == channelId }
      let guildName = user.guilds[guildId]?.name
      return [channel?.name.map { "#\($0)" }, guildName].compactMap(\.self)
        .joined(separator: " · ")
    }
    guard let channel = user.privateChannels[channelId] else { return "" }
    if channel.type == .groupDm {
      return channel.name
        ?? channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ") ?? ""
    }
    let other = channel.recipients?.first
    return other.map { String(localized: "DM with \($0.global_name ?? $0.username)") } ?? ""
  }

  func snapshot(of message: DiscordChannel.Message, guildId: GuildSnowflake?) -> MessageSnapshot {
    let guildId = guildId ?? message.guild_id
    // messages loaded over HTTP carry no member; the server's nickname is in its store
    let nick =
      message.member?.nick
      ?? message.author.flatMap { author in
        guildId.flatMap { existingGuildStore(for: $0)?.member(author.id)?.nick }
      }
    return MessageSnapshot(
      id: message.id.rawValue,
      channelID: message.channel_id.rawValue,
      guildID: guildId?.rawValue,
      authorID: message.author?.id.rawValue,
      authorName: nick ?? message.author?.global_name ?? message.author?.username ?? "",
      avatarURL: message.author.flatMap {
        DiscordImageURL.userAvatar(user: $0.toPartialUser(), animated: false, size: 64)?
          .absoluteString
      },
      place: placeName(channelId: message.channel_id, guildId: guildId),
      text: String(notifications.plainText(of: message, guildId: guildId).prefix(600)),
      date: message.timestamp.date
    )
  }

  func snapshot(of message: Gateway.MessageCreate) -> MessageSnapshot {
    MessageSnapshot(
      id: message.id.rawValue,
      channelID: message.channel_id.rawValue,
      guildID: message.guild_id?.rawValue,
      authorID: message.author?.id.rawValue,
      authorName: message.member?.nick ?? message.author?.global_name ?? message.author?.username
        ?? "",
      avatarURL: message.author.flatMap {
        DiscordImageURL.userAvatar(user: $0.toPartialUser(), animated: false, size: 64)?
          .absoluteString
      },
      place: placeName(channelId: message.channel_id, guildId: message.guild_id),
      text: String(notifications.plainText(of: message).prefix(600)),
      date: message.timestamp.date
    )
  }
}

/// Saved messages, reminders and ghost pings. Discord has none of these for
/// user accounts, so they live in Aicord only, on this device.
@MainActor
@Observable
final class SavedItemsStore {
  static let shared = SavedItemsStore()

  struct Saved: Codable, Hashable, Identifiable {
    var message: MessageSnapshot
    var savedAt: Date
    var id: String { message.id }
  }

  struct Reminder: Codable, Hashable, Identifiable {
    var id: String
    var message: MessageSnapshot
    var fireDate: Date
  }

  struct GhostPing: Codable, Hashable, Identifiable {
    var message: MessageSnapshot
    var deletedAt: Date
    var id: String { message.id }
  }

  private static let savedKey = "Paicord.Saved.Messages"
  private static let remindersKey = "Paicord.Saved.Reminders"
  private static let ghostPingsKey = "Paicord.Saved.GhostPings"
  /// Ghost pings kept in the list; older ones fall off.
  static let ghostPingLimit = 100

  /// Newest first.
  private(set) var saved: [Saved]
  /// Soonest first.
  private(set) var reminders: [Reminder]
  /// Newest first.
  private(set) var ghostPings: [GhostPing]

  private init() {
    saved = Self.load(Self.savedKey) ?? []
    reminders = Self.load(Self.remindersKey) ?? []
    ghostPings = Self.load(Self.ghostPingsKey) ?? []
  }

  // MARK: - Saved

  func isSaved(_ id: MessageSnowflake) -> Bool {
    saved.contains { $0.id == id.rawValue }
  }

  func toggleSaved(_ message: MessageSnapshot) {
    if let index = saved.firstIndex(where: { $0.id == message.id }) {
      saved.remove(at: index)
    } else {
      saved.insert(Saved(message: message, savedAt: .now), at: 0)
    }
    Self.store(saved, Self.savedKey)
  }

  func removeSaved(_ ids: Set<String>) {
    saved.removeAll { ids.contains($0.id) }
    Self.store(saved, Self.savedKey)
  }

  // MARK: - Reminders

  enum ReminderTime: CaseIterable {
    case oneHour, threeHours, tomorrowMorning

    var title: LocalizedStringResource {
      switch self {
      case .oneHour: "In 1 Hour"
      case .threeHours: "In 3 Hours"
      case .tomorrowMorning: "Tomorrow Morning"
      }
    }

    var date: Date {
      switch self {
      case .oneHour: .now.addingTimeInterval(3_600)
      case .threeHours: .now.addingTimeInterval(3 * 3_600)
      case .tomorrowMorning:
        Calendar.current.date(
          bySettingHour: 9, minute: 0, second: 0,
          of: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now) ?? .now
      }
    }
  }

  /// Schedules a local notification; tapping it opens the channel on the message.
  func remind(_ message: MessageSnapshot, at date: Date) async {
    let center = UNUserNotificationCenter.current()
    if await center.notificationSettings().authorizationStatus == .notDetermined {
      _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    let reminder = Reminder(id: "reminder-\(UUID().uuidString)", message: message, fireDate: date)

    let content = UNMutableNotificationContent()
    content.title = String(localized: "Reminder")
    content.subtitle = [message.authorName, message.place].filter { !$0.isEmpty }
      .joined(separator: " · ")
    content.body = message.text.isEmpty ? String(localized: "A message you wanted to come back to") : message.text
    content.threadIdentifier = "reminders"
    content.sound = .default
    var info = ["channel": message.channelID, "message": message.id, "jump": "1"]
    info["guild"] = message.guildID
    content.userInfo = info
    let parts = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    let request = UNNotificationRequest(
      identifier: reminder.id, content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    try? await center.add(request)

    reminders.append(reminder)
    reminders.sort { $0.fireDate < $1.fireDate }
    Self.store(reminders, Self.remindersKey)
  }

  func removeReminders(_ ids: Set<String>) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: Array(ids))
    reminders.removeAll { ids.contains($0.id) }
    Self.store(reminders, Self.remindersKey)
  }

  // MARK: - Ghost Pings

  func addGhostPing(_ message: MessageSnapshot) {
    guard !ghostPings.contains(where: { $0.id == message.id }) else { return }
    ghostPings.insert(GhostPing(message: message, deletedAt: .now), at: 0)
    if ghostPings.count > Self.ghostPingLimit {
      ghostPings.removeLast(ghostPings.count - Self.ghostPingLimit)
    }
    Self.store(ghostPings, Self.ghostPingsKey)
  }

  func removeGhostPings(_ ids: Set<String>) {
    ghostPings.removeAll { ids.contains($0.id) }
    Self.store(ghostPings, Self.ghostPingsKey)
  }

  // MARK: - Storage

  private static func load<T: Decodable>(_ key: String) -> T? {
    UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  private static func store<T: Encodable>(_ value: T, _ key: String) {
    UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
  }
}
