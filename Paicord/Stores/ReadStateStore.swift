//
//  ReadStateStore.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 20/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import PaicordLib

@MainActor
@Observable
class ReadStateStore: DiscordDataStore {
  var gateway: GatewayStore?

  var eventTask: Task<Void, Never>?

  func setGateway(_ gateway: GatewayStore?) {
    self.gateway = gateway
    setupEventHandling()
  }

  var readStates: [AnySnowflake: Gateway.ReadState] = [:]

  func setupEventHandling() {
    eventTask?.cancel()
    guard let gateway = gateway?.gateway else { return }
    let events = gateway.events
    eventTask = Task {
      for await event in events {
        switch event.data {
        case .ready(let readyData):
          handleReady(readyData)
        case .messageAcknowledge(let ackData):
          handleMessageAcknowledge(ackData)
        case .messageCreate(let messageData):
          handleMessageCreate(messageData)
        default:
          break
        }
      }
    }
  }

  private func handleReady(_ readyData: Gateway.Ready) {
    readStates = (readyData.read_state ?? []).reduce(into: [:]) {
      $0[$1.id] = $1
    }
  }

  private func handleMessageAcknowledge(_ ackData: Gateway.MessageAcknowledge) {
    applyAck(
      channelId: ackData.channel_id,
      messageId: ackData.message_id,
      mentionCount: ackData.mention_count ?? 0
    )
  }

  /// Marks a channel as read up to a given message. Called after we send an ack
  /// ourselves, and when a `MESSAGE_ACK` event arrives from another client.
  func applyAck(channelId: ChannelSnowflake, messageId: MessageSnowflake, mentionCount: Int = 0) {
    let key = AnySnowflake(channelId)
    if mentionCount == 0 { gateway?.notifications.clearDelivered(channelId: channelId) }
    if readStates[key] != nil {
      readStates[key]?.last_message_id = messageId
      readStates[key]?.mention_count = mentionCount
    } else {
      readStates[key] = Gateway.ReadState(
        id: key,
        last_message_id: messageId,
        mention_count: mentionCount
      )
    }
  }

  /// Marks channels read up to their latest message, 100 per request.
  func markRead(_ channels: [DiscordChannel]) async throws {
    guard let gateway else { return }
    let pending: [(ChannelSnowflake, MessageSnowflake)] = channels.compactMap { channel in
      guard let last = channel.last_message_id,
        isUnread(channelId: channel.id, lastMessageId: last)
          || mentionCount(channelId: channel.id) > 0
      else { return nil }
      return (channel.id, last)
    }
    for start in stride(from: 0, to: pending.count, by: 100) {
      let batch = pending[start..<min(start + 100, pending.count)]
      let res = try await gateway.client.bulkAckReadStates(
        payload: .init(read_states: batch.map { .init(channel_id: $0.0, message_id: $0.1) })
      )
      try res.guardSuccess()
      for (channel, message) in batch { applyAck(channelId: channel, messageId: message) }
    }
  }

  func isUnread(channelId: ChannelSnowflake, lastMessageId: MessageSnowflake?) -> Bool {
    guard let lastMessageId else { return false }
    guard let acked = readStates[AnySnowflake(channelId)]?.last_message_id else { return true }
    return lastMessageId > acked
  }

  func mentionCount(channelId: ChannelSnowflake) -> Int {
    readStates[AnySnowflake(channelId)]?.mention_count ?? 0
  }

  func incrementMentionCount(channelId: ChannelSnowflake) {
    let key = AnySnowflake(channelId)
    let newCount = (readStates[key]?.mention_count ?? 0) + 1
    if readStates[key] != nil {
      readStates[key]?.mention_count = newCount
    } else {
      readStates[key] = Gateway.ReadState(id: key, mention_count: newCount)
    }
  }

  private func handleMessageCreate(_ messageData: Gateway.MessageCreate) {
    guard let currentUserId = gateway?.user.currentUser?.id else { return }
    guard messageData.author?.id != currentUserId else { return }
    // every DM message counts, like Discord's own read states
    guard let guildId = messageData.guild_id else {
      if gateway?.user.privateChannels[messageData.channel_id] != nil {
        incrementMentionCount(channelId: messageData.channel_id)
      }
      return
    }
    let guildStore = gateway?.existingGuildStore(for: guildId)
    guard isMentioned(in: messageData, currentUserId: currentUserId, guildStore: guildStore)
    else { return }
    incrementMentionCount(channelId: messageData.channel_id)
  }

  private func isMentioned(
    in messageData: Gateway.MessageCreate,
    currentUserId: UserSnowflake,
    guildStore: GuildStore?
  ) -> Bool {
    if messageData.mention_everyone { return true }
    if messageData.mentions.contains(where: { $0.id == currentUserId }) { return true }
    if !messageData.mention_roles.isEmpty, let guildStore {
      let myRoles = guildStore.member(currentUserId)?.roles ?? []
      if myRoles.contains(where: { messageData.mention_roles.contains($0) }) { return true }
    }
    return false
  }
}
