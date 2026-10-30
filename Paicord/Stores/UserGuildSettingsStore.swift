//
//  UserGuildSettingsStore.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 20/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import PaicordLib

// https://docs.discord.food/topics/read-state#how-unreads-work

@MainActor
@Observable
class UserGuildSettingsStore: DiscordDataStore {
  var gateway: GatewayStore?

  var eventTask: Task<Void, Never>?

  var userGuildSettings: [GuildSnowflake?: Guild.UserGuildSettings] = [:]

  func setupEventHandling() {
    guard let gateway = gateway?.gateway else { return }
    let events = gateway.events
    eventTask = Task {
      for await event in events {
        switch event.data {
        case .ready(let readyData):
          handleReady(readyData)
        case .userGuildSettingsUpdate(let settings):
          userGuildSettings[settings.guild_id] = settings
        default: break
        }
      }
    }
  }

  private func handleReady(_ readyData: Gateway.Ready) {
    userGuildSettings = readyData.user_guild_settings.reduce(into: [:]) {
      $0[$1.guild_id] = $1
    }
  }

  // MARK: - Notification levels

  /// Discord's notification level, as stored in `message_notifications`.
  enum Level: Int {
    case allMessages = 0
    case onlyMentions = 1
    case nothing = 2
    case inherit = 3
  }

  /// Whether a mute is on now, taking its end time into account.
  static func isActive(muted: Bool, config: Guild.UserGuildSettings.MuteConfig??) -> Bool {
    guard muted else { return false }
    guard let end = config??.end_time?.date else { return true }
    return end > .now
  }

  func isMuted(guildId: GuildSnowflake?) -> Bool {
    guard let settings = userGuildSettings[guildId] else { return false }
    return Self.isActive(muted: settings.muted, config: settings.mute_config)
  }

  func override(
    guildId: GuildSnowflake?, channelId: ChannelSnowflake
  ) -> Guild.UserGuildSettings.ChannelOverride? {
    userGuildSettings[guildId]?.channel_overrides.first { $0.channel_id == channelId }
  }

  func isMuted(guildId: GuildSnowflake?, channelId: ChannelSnowflake) -> Bool {
    guard let override = override(guildId: guildId, channelId: channelId) else { return false }
    return Self.isActive(muted: override.muted, config: override.mute_config)
  }

  /// The level set on the server itself; `inherit` means the server's default.
  func guildLevel(_ guildId: GuildSnowflake) -> Level {
    userGuildSettings[guildId].flatMap { Level(rawValue: $0.message_notifications) } ?? .inherit
  }

  /// The level set on one channel; `inherit` means it follows its category or server.
  func channelLevel(guildId: GuildSnowflake, channelId: ChannelSnowflake) -> Level {
    guard let override = override(guildId: guildId, channelId: channelId) else { return .inherit }
    return Level(rawValue: Int(override.message_notifications.rawValue)) ?? .inherit
  }

  /// Saves a server's level (or a channel's, with `channelId`) on the account.
  /// The gateway echoes the change back; we apply the answer right away too.
  func setLevel(
    _ level: Level, guildId: GuildSnowflake, channelId: ChannelSnowflake? = nil
  ) async throws {
    if let channelId {
      try await modify(
        guildId,
        .init(channel_overrides: [
          channelId.rawValue: .init(message_notifications: level.rawValue)
        ])
      )
    } else {
      try await modify(guildId, .init(message_notifications: level.rawValue))
    }
  }

  // MARK: - Mute

  /// The lengths Discord offers for a mute.
  enum MuteDuration: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 900
    case oneHour = 3600
    case eightHours = 28800
    case twentyFourHours = 86400
    case untilTurnedOff = -1

    var id: Int { rawValue }

    var title: LocalizedStringResource {
      switch self {
      case .fifteenMinutes: "For 15 Minutes"
      case .oneHour: "For 1 Hour"
      case .eightHours: "For 8 Hours"
      case .twentyFourHours: "For 24 Hours"
      case .untilTurnedOff: "Until I Turn It Back On"
      }
    }
  }

  /// When an active mute ends; `nil` if it lasts until turned off or isn't on.
  func muteEnd(guildId: GuildSnowflake?, channelId: ChannelSnowflake? = nil) -> Date? {
    let config: Guild.UserGuildSettings.MuteConfig??
    if let channelId {
      config = override(guildId: guildId, channelId: channelId)?.mute_config
    } else {
      config = userGuildSettings[guildId]?.mute_config
    }
    guard let end = config??.end_time?.date, end > .now else { return nil }
    return end
  }

  /// Mutes a server (or a channel, with `channelId`) for `duration`, or unmutes it.
  func setMuted(
    _ muted: Bool, for duration: MuteDuration = .untilTurnedOff,
    guildId: GuildSnowflake, channelId: ChannelSnowflake? = nil
  ) async throws {
    let config: Payloads.ModifyUserGuildSettings.MuteConfig? =
      muted
      ? .init(
        selected_time_window: duration.rawValue,
        end_time: duration == .untilTurnedOff
          ? nil : Date.now.addingTimeInterval(TimeInterval(duration.rawValue))
      )
      : nil
    if let channelId {
      try await modify(
        guildId,
        .init(channel_overrides: [
          channelId.rawValue: .init(muted: muted, mute_config: config)
        ])
      )
    } else {
      try await modify(guildId, .init(muted: muted, mute_config: config))
    }
  }

  // MARK: - Suppression

  func suppressesEveryone(guildId: GuildSnowflake) -> Bool {
    userGuildSettings[guildId]?.suppress_everyone ?? false
  }

  func suppressesRoles(guildId: GuildSnowflake) -> Bool {
    userGuildSettings[guildId]?.suppress_roles ?? false
  }

  /// Turns off (or back on) notifications for @everyone and @here, or for role mentions.
  func setSuppress(
    everyone: Bool? = nil, roles: Bool? = nil, guildId: GuildSnowflake
  ) async throws {
    try await modify(guildId, .init(suppress_everyone: everyone, suppress_roles: roles))
  }

  private func modify(
    _ guildId: GuildSnowflake, _ payload: Payloads.ModifyUserGuildSettings
  ) async throws {
    guard let gateway else { return }
    let res = try await gateway.client.modifyUserGuildSettings(
      guildId: guildId, payload: payload
    )
    try res.guardSuccess()
    if let settings = try? res.decode() {
      userGuildSettings[settings.guild_id] = settings
    }
  }
}
