//
//  QuickSwitcherProviderStore.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 12/02/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import Foundation
import AicordKit

@MainActor
@Observable
class QuickSwitcherProviderStore: DiscordDataStore {
  var gateway: GatewayStore?

  var eventTask: Task<Void, Never>?

  func setupEventHandling() {
  }

  enum SearchResult: Hashable, Sendable {
    case user(PartialUser)
    case groupDM(DiscordChannel)
    case guildChannel(DiscordChannel, DiscordChannel?, Guild)
    case guild(Guild)
  }

  func search(_ query: String) -> AsyncStream<[SearchResult]> {
    let guildsSnapshot = Array((gateway?.user.guilds ?? [:]).values)
    let privateChannelsSnapshot = Array((gateway?.user.privateChannels ?? [:]).values)
    let relationshipsSnapshot = Array((gateway?.user.relationships ?? [:]).values)

    return AsyncStream { continuation in
      let task = Task.detached(priority: .userInitiated) {
        let normalizedQuery = query.lowercased()
        if normalizedQuery.isEmpty {
          continuation.yield([])
          continuation.finish()
          return
        }

        defer { continuation.finish() }

        var yieldedIds = Set<String>()
        var currentResults: [(result: SearchResult, name: String)] = []

        func addIfNew(_ result: SearchResult, name: String, id: String) {
          if !yieldedIds.contains(id) {
            yieldedIds.insert(id)

            let index =
              currentResults.firstIndex { existing in
                let existingName = existing.name.lowercased()
                let newName = name.lowercased()

                let newStarts = newName.hasPrefix(normalizedQuery)
                let existingStarts = existingName.hasPrefix(normalizedQuery)

                if newStarts != existingStarts {
                  return newStarts
                }

                return newName < existingName
              } ?? currentResults.count

            currentResults.insert((result, name), at: index)

            let resultsToYield = currentResults.prefix(25).map(\.result)
            continuation.yield(resultsToYield)
          }
        }

        for guild in guildsSnapshot {
          if Task.isCancelled { return }
          if guild.name.lowercased().contains(normalizedQuery) {
            addIfNew(
              .guild(guild),
              name: guild.name,
              id: guild.id.rawValue
            )
          }
        }

        for channel in privateChannelsSnapshot {
          if Task.isCancelled { return }
          if let name = channel.name,
            name.lowercased().contains(normalizedQuery)
              || channel.recipients?.contains(where: { recipient in
                let displayName = recipient.global_name ?? recipient.username
                return displayName.lowercased().contains(normalizedQuery)
                  || recipient.username.lowercased().contains(normalizedQuery)
              }) == true
          {
            if channel.type == .groupDm {
              addIfNew(
                .groupDM(channel),
                name: name,
                id: channel.id.rawValue
              )
            }
          } else if channel.type == .dm,
            let recipient = channel.recipients?.first
          {
            let displayName = recipient.global_name ?? recipient.username
            if displayName.lowercased().contains(normalizedQuery)
              || recipient.username.lowercased().contains(normalizedQuery)
            {
              addIfNew(
                .user(recipient.toPartialUser()),
                name: displayName,
                id: recipient.id.rawValue
              )
            }
          }
        }

        for guild in guildsSnapshot {
          if Task.isCancelled { return }
          for channel in guild.channels ?? [] {
            if Task.isCancelled { return }
            if let name = channel.name,
              name.lowercased().contains(normalizedQuery)
            {
              let category = guild.channels?.first {
                $0.id.rawValue == channel.parent_id?.rawValue
              }
              addIfNew(
                .guildChannel(channel, category, guild),
                name: name,
                id: channel.id.rawValue
              )
            }
          }
        }

        for relationship in relationshipsSnapshot {
          if Task.isCancelled { return }
          let user = relationship.user
          let displayName = user.global_name ?? user.username ?? "Unknown User"
          if displayName.lowercased().contains(normalizedQuery)
            || user.username?.lowercased().contains(normalizedQuery) == true
          {
            addIfNew(.user(user), name: displayName, id: user.id.rawValue)
          }
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
