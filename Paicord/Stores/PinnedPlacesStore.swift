//
//  PinnedPlacesStore.swift
//  Paicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import Foundation
import AicordKit

/// Servers and channels pinned to the top of their lists. Discord has no
/// pinning, so this lives in Aicord only, on this device.
@MainActor
@Observable
final class PinnedPlacesStore {
  static let shared = PinnedPlacesStore()

  private static let guildsKey = "Paicord.Pinned.Guilds"
  private static let channelsKey = "Paicord.Pinned.Channels"

  /// Pinned servers, in the order they were pinned.
  private(set) var guilds: [GuildSnowflake]
  /// Pinned channels of each server, in the order they were pinned.
  private(set) var channels: [GuildSnowflake: [ChannelSnowflake]]

  private init() {
    let defaults = UserDefaults.standard
    guilds = (defaults.stringArray(forKey: Self.guildsKey) ?? []).map(GuildSnowflake.init)
    let stored = defaults.dictionary(forKey: Self.channelsKey) as? [String: [String]] ?? [:]
    channels = stored.reduce(into: [:]) {
      $0[GuildSnowflake($1.key)] = $1.value.map(ChannelSnowflake.init)
    }
  }

  func isPinned(_ guild: GuildSnowflake) -> Bool {
    guilds.contains(guild)
  }

  func isPinned(_ channel: ChannelSnowflake, in guild: GuildSnowflake) -> Bool {
    channels[guild]?.contains(channel) ?? false
  }

  func togglePin(_ guild: GuildSnowflake) {
    if let index = guilds.firstIndex(of: guild) {
      guilds.remove(at: index)
    } else {
      guilds.append(guild)
    }
    UserDefaults.standard.set(guilds.map(\.rawValue), forKey: Self.guildsKey)
  }

  func togglePin(_ channel: ChannelSnowflake, in guild: GuildSnowflake) {
    var pinned = channels[guild] ?? []
    if let index = pinned.firstIndex(of: channel) {
      pinned.remove(at: index)
    } else {
      pinned.append(channel)
    }
    channels[guild] = pinned.isEmpty ? nil : pinned
    UserDefaults.standard.set(
      channels.reduce(into: [String: [String]]()) { $0[$1.key.rawValue] = $1.value.map(\.rawValue) },
      forKey: Self.channelsKey
    )
  }
}
