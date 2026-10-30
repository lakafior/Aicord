//
//  VoiceChannelButton.swift
//  Aicord
//
//  A server voice channel in the channel list: joins on click and lists
//  who is connected, with speaking rings for the channel we are in.
//

import AicordKit
import SwiftUI

struct VoiceChannelButton: View {
  @Environment(\.gateway) var gw
  @Environment(\.guildStore) var guild
  @AppStorage(ChannelButton.showsHiddenChannelsKey) private var showsHiddenChannels = false
  @State private var showsHiddenInfo = false
  var channel: DiscordChannel

  var voice: VoiceConnectionStore { gw.voice }
  var isCurrent: Bool { voice.call?.channelID == channel.id }

  var canView: Bool {
    guild?.hasPermission(channel: channel, .viewChannel) != false
  }
  var canConnect: Bool {
    guild?.hasPermission(channel: channel, .connect) != false
  }

  var participants: [VoiceState] {
    (guild?.voiceStates.values.filter { $0.channel_id == channel.id } ?? [])
      .sorted { displayName($0) .localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
  }

  /// The channel and everyone in it, each its own list row.
  var body: some View {
    if canView {
      Button {
        guard let guildID = guild?.guildId else { return }
        voice.join(channelID: channel.id, guildID: guildID)
      } label: {
        HStack(spacing: 4) {
          Label {
            Text(channel.name ?? "unknown")
          } icon: {
            Image(systemName: "speaker.wave.2.fill")
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          if let limit = channel.user_limit, limit > 0 {
            Text(verbatim: "\(participants.count)/\(limit)")
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        .fontWeight(isCurrent ? .semibold : nil)
        .foregroundStyle(isCurrent ? .primary : .secondary)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .disabled(!canConnect)
      .selectionDisabled()
      .help(canConnect ? Text("Join Voice") : Text("You can't connect to this channel"))
      .accessibilityHint(canConnect ? Text("Join Voice") : Text("You can't connect to this channel"))
      .channelContextMenu(channel, in: guild?.guildId ?? .init("0"))

      ForEach(participants, id: \.user_id) { state in
        participantRow(state)
          .selectionDisabled()
      }
    } else if showsHiddenChannels {
      Button {
        showsHiddenInfo = true
      } label: {
        HStack(spacing: 4) {
          Label {
            Text(channel.name ?? "unknown")
          } icon: {
            Image(systemName: "speaker.wave.2.fill")
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          Image(systemName: "lock.fill")
            .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .selectionDisabled()
      .accessibilityHint(Text("You can't view this channel"))
      .popover(isPresented: $showsHiddenInfo) {
        HiddenChannelInfo(channel: channel, guild: guild)
          .presentationCompactAdaptation(.sheet)
          .presentationDetents([.medium, .large])
      }
    }
  }

  func participantRow(_ state: VoiceState) -> some View {
    let speaking = isCurrent && voice.speaking.contains(state.user_id)
    return HStack(spacing: 6) {
      Profile.AvatarWithPresence(member: member(state), user: member(state)?.user)
        .profileShowsAvatarDecoration(false)
        .frame(width: 22, height: 22)
        .overlay {
          Circle()
            .stroke(.green, lineWidth: 2)
            .opacity(speaking ? 1 : 0)
        }
      Text(displayName(state))
        .font(.callout)
        .foregroundStyle(speaking ? .primary : .secondary)
        .lineLimit(1)
      Spacer(minLength: 2)
      if state.mute || state.self_mute {
        Image(systemName: "mic.slash.fill").imageScale(.small).foregroundStyle(.secondary)
      }
      if state.deaf || state.self_deaf {
        Image(systemName: "speaker.slash.fill").imageScale(.small).foregroundStyle(.secondary)
      }
    }
    .padding(.leading, 28)
    .frame(minHeight: 26)
    .accessibilityElement(children: .combine)
  }

  func member(_ state: VoiceState) -> Guild.PartialMember? {
    state.member ?? guild?.member(state.user_id)
  }

  func displayName(_ state: VoiceState) -> String {
    let member = member(state)
    return member?.nick ?? member?.user?.global_name ?? member?.user?.username
      ?? state.user_id.rawValue
  }
}
