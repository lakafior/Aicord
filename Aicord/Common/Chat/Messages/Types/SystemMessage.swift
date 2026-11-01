//
//  SystemMessage.swift
//  Aicord
//

import AicordKit
import SwiftUI

extension MessageCell {
  /// Discord's one-line notices: pins, threads, boosts, calls, group changes,
  /// Stage events and the rest. Types without their own wording get a neutral line.
  struct SystemMessage: View, Equatable {
    let message: DiscordChannel.Message
    let channelStore: ChannelStore

    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState

    nonisolated static func == (lhs: SystemMessage, rhs: SystemMessage) -> Bool {
      lhs.message.id == rhs.message.id
        && lhs.message.content == rhs.message.content
        && lhs.message.call == rhs.message.call
        && lhs.message.embeds == rhs.message.embeds
    }

    var body: some View {
      switch message.type {
      case .threadStarterMessage:
        threadStarter
      case .pollResult:
        VStack(alignment: .leading, spacing: 4) {
          line
          HStack(spacing: 8) {
            AvatarBalancing()
            MessageBody(message: message, channelStore: channelStore)
          }
        }
      default:
        line
      }
    }

    // MARK: - Line

    private var line: some View {
      let notice = notice
      return HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: notice.symbol)
          .foregroundStyle(notice.tint)
          .frame(width: avatarSize)
          .accessibilityHidden(true)
        Text(
          "\(notice.text)  \(Text(SystemTimestamp.text(for: message.timestamp.date)).font(.caption2).foregroundStyle(.secondary))"
        )
          #if os(iOS)
            .font(.callout)
          #elseif os(macOS)
            .font(.body)
          #endif
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let action = notice.action {
          Button(action.title, action: action.perform)
            .buttonStyle(.borderless)
            .font(.caption)
        }
      }
      .accessibilityElement(children: .combine)
    }

    private struct Notice {
      var symbol: String
      var tint: Color = .secondary
      var text: Text
      var action: Action?
    }

    private struct Action {
      var title: LocalizedStringKey
      var perform: () -> Void
    }

    // MARK: - Names

    private func name(of user: DiscordUser?) -> String {
      guard let user else { return String(localized: "Someone") }
      return channelStore.guildStore?.member(user.id)?.nick ?? message.member?.nick
        ?? user.global_name ?? user.username
    }

    private func name(of user: MentionUser) -> String {
      channelStore.guildStore?.member(user.id)?.nick ?? user.member?.nick ?? user.global_name
        ?? user.username
    }

    private var author: Text { Text(name(of: message.author)).bold().foregroundStyle(.primary) }

    private var target: Text {
      Text(message.mentions.first.map(name(of:)) ?? String(localized: "someone"))
        .bold().foregroundStyle(.primary)
    }

    private var content: Text { Text(message.content).bold().foregroundStyle(.primary) }

    private var guildName: Text {
      Text(channelStore.guildStore?.guild?.name ?? String(localized: "This server"))
        .bold().foregroundStyle(.primary)
    }

    // MARK: - Wording

    private var notice: Notice {
      switch message.type {
      case .recipientAdd:
        return Notice(
          symbol: "arrow.right", tint: .green, text: Text("\(author) added \(target) to the group."))
      case .recipientRemove:
        if message.mentions.first?.id == message.author?.id {
          return Notice(
            symbol: "arrow.left", tint: .red, text: Text("\(author) left the group."))
        }
        return Notice(
          symbol: "arrow.left", tint: .red,
          text: Text("\(author) removed \(target) from the group."))
      case .call:
        return callNotice
      case .channelNameChange:
        return Notice(
          symbol: "pencil", text: Text("\(author) changed the channel name: \(content)"))
      case .channelIconChange:
        return Notice(symbol: "pencil", text: Text("\(author) changed the channel icon."))
      case .channelPinnedMessage:
        return Notice(
          symbol: "pin.fill",
          text: Text("\(author) pinned a message to this channel."),
          action: message.message_reference?.message_id.map { id in
            Action(title: "Show Message") {
              Task { await channelStore.jump(to: id) }
            }
          })
      case .userPremiumGuildSubscription:
        let times = Int(message.content) ?? 1
        return Notice(
          symbol: "rocket.fill", tint: .pink,
          text: times > 1
            ? Text("\(author) just boosted the server \(times) times!")
            : Text("\(author) just boosted the server!"))
      case .userPremiumGuildSubscriptionTier1, .userPremiumGuildSubscriptionTier2,
        .userPremiumGuildSubscriptionTier3:
        let level =
          message.type == .userPremiumGuildSubscriptionTier1
          ? 1 : message.type == .userPremiumGuildSubscriptionTier2 ? 2 : 3
        let times = Int(message.content) ?? 1
        let boosted =
          times > 1
          ? Text("\(author) just boosted the server \(times) times!")
          : Text("\(author) just boosted the server!")
        return Notice(
          symbol: "rocket.fill", tint: .pink,
          text: Text("\(boosted) \(Text("\(guildName) has achieved Level \(level)!"))"))
      case .channelFollowAdd:
        return Notice(
          symbol: "megaphone.fill",
          text: Text(
            "\(author) has added \(content) to this channel. Its most important updates will show up here."
          ))
      case .threadCreated:
        let threadID = message.message_reference?.channel_id
        return Notice(
          symbol: "number",
          text: Text("\(author) started a thread: \(content)"),
          action: threadID.map { id in
            Action(title: "Open Thread") { openThread(id) }
          })
      case .guildInviteReminder:
        return Notice(
          symbol: "person.badge.plus",
          text: Text("Invite your friends to \(guildName) to get the conversation going."))
      case .autoModerationAction:
        return Notice(
          symbol: "shield.lefthalf.filled", tint: .orange,
          text: Text("AutoMod blocked a message from \(author)."))
      case .roleSubscriptionPurchase:
        return Notice(
          symbol: "star.fill", tint: .yellow, text: Text("\(author) joined a role subscription."))
      case .stageStart:
        return Notice(
          symbol: "person.wave.2.fill", tint: .green, text: Text("\(author) started \(content)"))
      case .stageEnd:
        return Notice(
          symbol: "person.wave.2.fill", tint: .red, text: Text("\(author) ended \(content)"))
      case .stageSpeaker:
        return Notice(symbol: "mic.fill", text: Text("\(author) is now a speaker."))
      case .stageRaiseHand:
        return Notice(symbol: "hand.raised.fill", text: Text("\(author) requested to speak."))
      case .stageTopic:
        return Notice(
          symbol: "person.wave.2.fill",
          text: Text("\(author) changed the Stage topic: \(content)"))
      case .pollResult:
        return Notice(symbol: "chart.bar.fill", text: Text("\(author)'s poll has closed."))
      case .guildIncidentAlertModeEnabled:
        return Notice(
          symbol: "exclamationmark.shield.fill", tint: .orange,
          text: Text("\(author) paused some server activity for security."))
      case .guildIncidentAlertModeDisabled:
        return Notice(
          symbol: "checkmark.shield.fill", tint: .green,
          text: Text("\(author) resumed server activity."))
      case .guildIncidentReportRaid:
        return Notice(
          symbol: "exclamationmark.shield.fill", tint: .orange,
          text: Text("\(author) reported a raid in \(guildName)."))
      case .guildIncidentReportFalseAlarm:
        return Notice(
          symbol: "checkmark.shield.fill", text: Text("\(author) reported a false alarm."))
      case .emojiAdded:
        return Notice(symbol: "face.smiling", text: Text("\(author) added a new emoji."))
      default:
        // anything else: a quiet line with whatever text Discord sent
        let detail = message.content.isEmpty ? "" : ": " + message.content
        return Notice(
          symbol: "info.circle",
          text: Text("\(Text("\(author) · system message"))\(Text(verbatim: detail))"))
      }
    }

    private var callNotice: Notice {
      let me = gw.user.currentUser?.id
      let call = message.call
      let missed =
        call.map { call in !call.participants.contains { $0 == me } } ?? false
        && message.author?.id != me
      guard let ended = call?.ended_timestamp?.date else {
        return Notice(
          symbol: "phone.fill", tint: .green, text: Text("\(author) started a call."))
      }
      let duration = Duration.seconds(max(0, ended.timeIntervalSince(message.timestamp.date)))
      let lasted = duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
      if missed {
        return Notice(
          symbol: "phone.arrow.down.left.fill", tint: .red,
          text: Text("You missed a call from \(author) that lasted \(lasted)."))
      }
      return Notice(
        symbol: "phone.fill", text: Text("\(author) started a call that lasted \(lasted)."))
    }

    // MARK: - Thread starter

    /// A thread's first line: the message it was started from, in the parent channel.
    @ViewBuilder
    private var threadStarter: some View {
      if let original = message.referenced_message?.value {
        DefaultMessage(message: original, channelStore: channelStore, inline: false)
      } else {
        HStack(spacing: 8) {
          Image(systemName: "text.bubble")
            .foregroundStyle(.secondary)
            .frame(width: avatarSize)
          Text("The message this thread started from was deleted.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }

    private func openThread(_ id: ChannelSnowflake) {
      let guildStore = channelStore.guildStore
      Task {
        if guildStore?.threads[id] == nil,
          let thread = try? await gw.client.getChannel(id: id).decode()
        {
          guildStore?.threads[id] = thread
        }
        appState.selectedChannel = id
      }
    }
  }

  /// "Today at 12:30", "Yesterday at 12:30" or a date, like the other message types.
  enum SystemTimestamp {
    private static let timeFormatter: DateFormatter = {
      let f = DateFormatter()
      f.timeStyle = .short
      f.dateStyle = .none
      return f
    }()

    private static let fullDateFormatter: DateFormatter = {
      let f = DateFormatter()
      f.dateStyle = .medium
      f.timeStyle = .none
      return f
    }()

    static func text(for date: Date) -> String {
      if Calendar.current.isDateInToday(date) {
        return timeFormatter.string(from: date)
      } else if Calendar.current.isDateInYesterday(date) {
        return String(localized: "Yesterday at \(timeFormatter.string(from: date))")
      } else {
        return fullDateFormatter.string(from: date)
      }
    }
  }
}
