//
//  ReplyThreadSheet.swift
//  Aicord
//
//  "Show Thread" from a reply's menu: the reply chain up to where it started,
//  with the loaded replies to any of it, oldest first. No model involved;
//  Explain Context and Summarize Replies read the same thread.
//

import AicordKit
import SwiftUI

struct ReplyThreadTarget: Identifiable, Hashable {
  let message: DiscordChannel.Message
  let guildID: GuildSnowflake?

  var id: MessageSnowflake { message.id }
}

extension DiscordChannel.Message {
  /// The message this one replies to; forwards don't count.
  var replyParentID: MessageSnowflake? {
    message_reference?.type == .forward ? nil : message_reference?.message_id
  }
}

@MainActor
enum ReplyThreadCollector {
  /// The thread `message` belongs to, oldest first: the messages it replies
  /// up through (from the loaded history, else fetched one by one), and the
  /// loaded messages that reply to any of them. Blocked people are left out.
  static func collect(
    around message: DiscordChannel.Message, gw: GatewayStore, maxDepth: Int = 50
  ) async -> [DiscordChannel.Message] {
    let loaded = gw.loadedMessages(in: message.channel_id)
    let byID = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

    var thread = [byID[message.id] ?? message]
    var current = thread[0]
    for _ in 0..<maxDepth {
      guard let parentID = current.replyParentID else { break }
      if let parent = byID[parentID] {
        current = parent
      } else if let parent = current.referenced_message?.value, parent.id == parentID {
        current = parent
      } else {
        let channel = current.message_reference?.channel_id ?? current.channel_id
        guard let res = try? await gw.client.getMessage(channelId: channel, messageId: parentID),
          (try? res.guardSuccess()) != nil, let parent = try? res.decode()
        else { break }
        current = parent
      }
      guard !thread.contains(where: { $0.id == current.id }) else { break }
      thread.append(current)
    }

    let nodes = loaded.map { ReplyThread.Node(id: $0.id.rawValue, parentID: $0.replyParentID?.rawValue) }
    let later = ReplyThread.laterReplies(to: Set(thread.map(\.id.rawValue)), in: nodes)
    thread += later.compactMap { byID[MessageSnowflake($0)] }

    return thread
      .filter { $0.id == message.id || !isBlocked($0, gw: gw) }
      .sorted { $0.id < $1.id }
  }

  /// The part of `thread` a model gets: `message`, what it replies to from
  /// the nearest up, then the rest closest to it, within `tokenBudget`.
  static func fit(
    _ thread: [DiscordChannel.Message], around message: DiscordChannel.Message,
    maxCharacters: Int, tokenBudget: Int
  ) -> [DiscordChannel.Message] {
    let nodes = thread.map { ReplyThread.Node(id: $0.id.rawValue, parentID: $0.replyParentID?.rawValue) }
    // a line is its author, the text cut to maxCharacters and a number
    let costs = thread.map { IntelligenceText.estimatedTokens(String($0.content.prefix(maxCharacters))) + 8 }
    return ReplyThread.fit(thread: nodes, target: message.id.rawValue, costs: costs, budget: tokenBudget)
      .map { thread[$0] }
  }

  private static func isBlocked(_ message: DiscordChannel.Message, gw: GatewayStore) -> Bool {
    guard let author = message.author?.id, let relationship = gw.user.relationships[author] else {
      return false
    }
    return relationship.type == .blocked || relationship.user_ignored
  }
}

struct ReplyThreadSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  let target: ReplyThreadTarget
  @State private var thread: [DiscordChannel.Message]?

  var body: some View {
    NavigationStack {
      List {
        if let thread {
          Section {
            ForEach(Array(thread.enumerated()), id: \.element.id) { index, message in
              Button {
                appState.open(
                  guild: message.guild_id ?? target.guildID, channel: message.channel_id,
                  message: message.id)
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  if let parent = parentLabel(of: message, after: index, in: thread) {
                    Label(parent, systemImage: "arrow.turn.up.right")
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                  }
                  MessagePreviewRow(message: message)
                }
              }
              .tint(.primary)
              .listRowBackground(
                message.id == target.message.id ? Color.accentColor.opacity(0.15) : nil)
            }
          } footer: {
            Text("\(thread.count) messages, oldest first. Tap one to jump to it in the channel.")
          }
        } else {
          ProgressView()
            .frame(maxWidth: .infinity)
        }
      }
      .navigationTitle("Thread")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task {
        thread = await ReplyThreadCollector.collect(around: target.message, gw: gw)
      }
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 460)
    #endif
  }

  /// Who a message answers, when that isn't the row right above it.
  private func parentLabel(
    of message: DiscordChannel.Message, after index: Int, in thread: [DiscordChannel.Message]
  ) -> String? {
    guard let parentID = message.replyParentID,
      index == 0 || thread[index - 1].id != parentID
    else { return nil }
    guard let parent = thread.first(where: { $0.id == parentID }) else {
      return String(localized: "Replying to a message not shown")
    }
    let quote = String(IntelligenceText.clean(parent.content).prefix(60))
    return String(localized: "Replying to \(SummaryPointRow.label(for: parent)): \(quote)")
  }
}
