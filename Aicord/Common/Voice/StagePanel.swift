//
//  StagePanel.swift
//  Aicord
//
//  A Stage channel above its chat: the topic, who is on stage and who is
//  listening, and listening, raising a hand or going on stage. Moderators
//  start and end the Stage and invite people up.
//

import AicordKit
import SwiftUI

struct StagePanel: View {
  var vm: ChannelStore
  @Environment(\.gateway) var gw
  @State private var showsAudience = false
  @State private var editsTopic = false
  @State private var topicDraft = ""
  @State private var actionError: String?

  var voice: VoiceConnectionStore { gw.voice }
  var guild: GuildStore? { vm.guildStore }
  var stage: StageInstance? { guild?.stageInstances[vm.channelId] }
  var isHere: Bool { voice.call?.channelID == vm.channelId }

  var states: [VoiceState] {
    (guild?.voiceStates.values.filter { $0.channel_id == vm.channelId } ?? [])
      .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
  }

  /// On stage: not suppressed and not holding an invitation.
  var speakers: [VoiceState] { states.filter(\.isStageSpeaker) }

  /// Everyone else, raised hands first in the order they went up.
  var audience: [VoiceState] {
    states.filter { !$0.isStageSpeaker }
      .sorted {
        switch ($0.request_to_speak_timestamp, $1.request_to_speak_timestamp) {
        case (let lhs?, let rhs?): lhs.date < rhs.date
        case (.some, nil): true
        default: false
        }
      }
  }

  /// Discord's Stage moderator: manage the channel, mute and move members.
  var isModerator: Bool {
    guard let guild, let channel = vm.channel else { return false }
    return [.manageChannels, .muteMembers, .moveMembers]
      .allSatisfy { guild.hasPermission(channel: channel, $0) }
  }

  var canRequestToSpeak: Bool {
    guild?.hasPermission(channel: vm.channel, .requestToSpeak) != false
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if !speakers.isEmpty {
        speakerStrip
      }
      if showsAudience, !audience.isEmpty {
        audienceList
      }
      controls
      if let error = actionError ?? (isHere ? voice.stageError : nil) {
        Text(error)
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(12)
    .glassEffect(.regular, in: .rect(cornerRadius: 16))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .task(id: vm.channelId) { await loadStage() }
    .alert(stage == nil ? "Start Stage" : "Edit Topic", isPresented: $editsTopic) {
      TextField("Topic", text: $topicDraft)
      Button(stage == nil ? "Start" : "Save") { saveTopic() }
        .disabled(topicDraft.trimmingCharacters(in: .whitespaces).isEmpty)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("What the Stage is about, shown to everyone in the server.")
    }
  }

  // MARK: Parts

  var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "person.wave.2.fill")
        .foregroundStyle(stage == nil ? Color.secondary : Color.green)
      VStack(alignment: .leading, spacing: 2) {
        if let stage {
          Text(stage.topic)
            .font(.headline)
            .lineLimit(2)
          Text("Live Stage")
            .font(.caption)
            .foregroundStyle(.green)
        } else {
          Text("No Stage is live")
            .font(.headline)
          Text(
            isModerator
              ? "Start one to let people listen in." : "A moderator starts the Stage."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      if !audience.isEmpty {
        Button {
          withAnimation(.snappy) { showsAudience.toggle() }
        } label: {
          Label {
            Text(verbatim: "\(audience.count)")
          } icon: {
            Image(systemName: "person.2.fill")
          }
          .font(.caption.monospacedDigit())
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help(Text("Listening"))
        .accessibilityLabel(Text("\(audience.count) listening"))
        .accessibilityHint(showsAudience ? Text("Hides the audience") : Text("Shows the audience"))
      }
    }
  }

  var speakerStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 12) {
        ForEach(speakers, id: \.user_id) { state in
          person(state, size: 44)
            .contextMenu { moderatorActions(state) }
        }
      }
      .padding(.vertical, 2)
    }
  }

  var audienceList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Listening")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
        ForEach(audience, id: \.user_id) { state in
          person(state, size: 32)
            .contextMenu { moderatorActions(state) }
        }
      }
    }
  }

  func person(_ state: VoiceState, size: CGFloat) -> some View {
    let speaking = isHere && voice.speaking.contains(state.user_id)
    let member = member(state)
    return VStack(spacing: 4) {
      Profile.AvatarWithPresence(member: member, user: member?.user)
        .profileShowsAvatarDecoration(false)
        .frame(width: size, height: size)
        .overlay {
          Circle()
            .stroke(.green, lineWidth: 2)
            .padding(-2)
            .opacity(speaking ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
          if state.request_to_speak_timestamp != nil, state.suppress {
            badge("hand.raised.fill", .yellow)
          } else if state.isStageSpeaker, state.mute || state.self_mute || state.deaf {
            badge("mic.slash.fill", .red)
          }
        }
      Text(name(state))
        .font(.caption2)
        .foregroundStyle(speaking ? .primary : .secondary)
        .lineLimit(1)
        .frame(maxWidth: max(size + 20, 64))
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue(accessibilityState(state))
  }

  func badge(_ symbol: String, _ color: Color) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(color)
      .padding(3)
      .background(.background, in: .circle)
  }

  @ViewBuilder
  var controls: some View {
    HStack(spacing: 8) {
      if !isHere {
        if stage != nil || isModerator {
          Button {
            guard let guildID = guild?.guildId else { return }
            voice.join(channelID: vm.channelId, guildID: guildID)
          } label: {
            Label("Listen", systemImage: "headphones")
          }
          .buttonStyle(.glassProminent)
          .disabled(guild?.hasPermission(channel: vm.channel, .connect) == false)
        }
      } else if voice.isInvitedToSpeak {
        Button {
          voice.becomeSpeaker()
        } label: {
          Label("Join as Speaker", systemImage: "mic.fill")
        }
        .buttonStyle(.glassProminent)
        Button("Stay in Audience") { voice.moveToAudience() }
          .buttonStyle(.glass)
      } else if voice.isSuppressed {
        if isModerator {
          Button {
            voice.becomeSpeaker()
          } label: {
            Label("Speak", systemImage: "mic.fill")
          }
          .buttonStyle(.glassProminent)
        } else if canRequestToSpeak {
          if voice.isHandRaised {
            Button {
              voice.setHandRaised(false)
            } label: {
              Label("Lower Hand", systemImage: "hand.raised.slash.fill")
            }
            .buttonStyle(.glass)
          } else {
            Button {
              voice.setHandRaised(true)
            } label: {
              Label("Request to Speak", systemImage: "hand.raised.fill")
            }
            .buttonStyle(.glassProminent)
          }
        }
      } else if voice.call?.isStage == true {
        Button {
          voice.moveToAudience()
        } label: {
          Label("Move to Audience", systemImage: "person.2.fill")
        }
        .buttonStyle(.glass)
      }
      if isHere {
        Button(role: .destructive) {
          voice.leave()
        } label: {
          Label("Leave Stage", systemImage: "phone.down.fill")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .tint(.red)
        .help(Text("Leave Stage"))
      }
      Spacer(minLength: 0)
      if isModerator {
        moderatorMenu
      }
    }
    .controlSize(.regular)
  }

  var moderatorMenu: some View {
    Menu {
      if stage == nil {
        Button("Start Stage…", systemImage: "play.fill") {
          topicDraft = vm.channel?.topic ?? ""
          editsTopic = true
        }
      } else {
        Button("Edit Topic…", systemImage: "pencil") {
          topicDraft = stage?.topic ?? ""
          editsTopic = true
        }
        Button("End Stage", systemImage: "stop.fill", role: .destructive) { endStage() }
      }
    } label: {
      Image(systemName: "ellipsis")
        .padding(.vertical, 4)
    }
    .menuIndicator(.hidden)
    .fixedSize()
    .accessibilityLabel(Text("Stage Settings"))
  }

  @ViewBuilder
  func moderatorActions(_ state: VoiceState) -> some View {
    if isModerator, state.user_id != gw.user.currentUser?.id {
      if state.suppress {
        Button("Invite to Speak", systemImage: "mic.fill") {
          setSuppressed(false, for: state)
        }
      } else {
        Button("Move to Audience", systemImage: "person.2.fill") {
          setSuppressed(true, for: state)
        }
      }
    }
  }

  // MARK: Actions

  /// The gateway sends live Stages with the server; a Stage started before
  /// the server's store existed is asked for once.
  func loadStage() async {
    let missing = states.filter { $0.member == nil && guild?.member($0.user_id) == nil }
      .map(\.user_id)
    if !missing.isEmpty { await guild?.requestMembers(for: Set(missing)) }
    guard stage == nil,
      let response = try? await gw.client.getStageInstance(channelId: vm.channelId),
      let fetched = try? response.decode()
    else { return }
    guild?.stageInstances[fetched.channel_id] = fetched
  }

  func saveTopic() {
    let topic = topicDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !topic.isEmpty else { return }
    let channelID = vm.channelId
    let isNew = stage == nil
    perform {
      if isNew {
        let created = try await gw.client.createStageInstance(
          payload: .init(channel_id: channelID, topic: String(topic.prefix(120)))
        ).decode()
        guild?.stageInstances[channelID] = created
      } else {
        let updated = try await gw.client.updateStageInstance(
          channelId: channelID, payload: .init(topic: String(topic.prefix(120)))
        ).decode()
        guild?.stageInstances[channelID] = updated
      }
    }
  }

  func endStage() {
    let channelID = vm.channelId
    perform {
      try await gw.client.deleteStageInstance(channelId: channelID).guardSuccess()
      guild?.stageInstances.removeValue(forKey: channelID)
    }
  }

  func setSuppressed(_ suppressed: Bool, for state: VoiceState) {
    guard let guildID = guild?.guildId else { return }
    let channelID = vm.channelId
    perform {
      try await gw.client.updateVoiceState(
        guildId: guildID, userId: state.user_id,
        payload: .init(channel_id: channelID, suppress: suppressed)
      ).guardSuccess()
    }
  }

  func perform(_ action: @escaping @MainActor () async throws -> Void) {
    actionError = nil
    Task {
      do {
        try await action()
      } catch {
        actionError = String(localized: "Discord didn't allow that on this Stage.")
      }
    }
  }

  // MARK: Names

  func member(_ state: VoiceState) -> Guild.PartialMember? {
    state.member ?? guild?.member(state.user_id)
  }

  func name(_ state: VoiceState) -> String {
    let member = member(state)
    return member?.nick ?? member?.user?.global_name ?? member?.user?.username
      ?? state.user_id.rawValue
  }

  func accessibilityState(_ state: VoiceState) -> Text {
    if state.isStageSpeaker { return Text("Speaker") }
    if !state.suppress { return Text("Invited to speak") }
    if state.request_to_speak_timestamp != nil { return Text("Hand raised") }
    return Text("Listening")
  }
}

extension VoiceState {
  /// On a Stage: speaking, not in the audience and not holding an invitation.
  var isStageSpeaker: Bool { !suppress && request_to_speak_timestamp == nil }
}
