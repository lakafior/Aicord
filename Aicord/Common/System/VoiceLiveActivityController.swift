//
//  VoiceLiveActivityController.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//
//  Shows the voice call on the Lock Screen and in the Dynamic Island: starts
//  when a call starts, follows mute and the people in it, ends with the call.
//

#if os(iOS)
  import ActivityKit
  import AicordKit
  import Foundation
  import os

  @MainActor
  final class VoiceLiveActivityController {
    static let shared = VoiceLiveActivityController()

    private var activity: Activity<VoiceCallAttributes>?
    private var activityCall: VoiceConnectionStore.Call?
    private var lastState: VoiceCallAttributes.ContentState?
    private let logger = Logger(subsystem: "net.smigi.aicord", category: "LiveActivity")

    private init() {}

    func start() {
      VoiceCallIntentRouter.toggleMute = { GatewayStore.shared.voice.toggleMute() }
      VoiceCallIntentRouter.leave = { GatewayStore.shared.voice.leave() }
      // activities left over from a run that ended without cleaning up
      endAll()
      observe()
    }

    private func observe() {
      withObservationTracking {
        update()
      } onChange: { [weak self] in
        Task { @MainActor in self?.observe() }
      }
    }

    /// Reads the call (which registers the observation) and brings the
    /// activity in line with it.
    private func update() {
      let voice = GatewayStore.shared.voice
      let call = voice.call
      let state = VoiceCallAttributes.ContentState(
        isMuted: voice.isMuted,
        isDeafened: voice.isDeafened,
        participants: voice.participants.count,
        isConnected: voice.phase == .connected || voice.phase == .encrypting
      )
      guard let call, voice.phase.isActive else {
        if activity != nil { end() }
        return
      }
      if activityCall != call {
        end()
        begin(call, state: state)
      } else if state != lastState {
        lastState = state
        guard let id = activity?.id else { return }
        Task.detached { await Self.update(id: id, state: state) }
      }
    }

    private func begin(_ call: VoiceConnectionStore.Call, state: VoiceCallAttributes.ContentState) {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
      let gw = GatewayStore.shared
      let name: String
      let server: String
      if let guildID = call.guildID {
        let channel = gw.user.guilds[guildID]?.channels?.first { $0.id == call.channelID }
        name = "#\(channel?.name ?? "")"
        server = gw.user.guilds[guildID]?.name ?? ""
      } else {
        name = gw.user.privateChannels[call.channelID].map(SystemIntegration.directMessageName)
          ?? ""
        server = ""
      }
      let attributes = VoiceCallAttributes(
        channelName: name, serverName: server, startedAt: call.startedAt,
        link: AicordLink(guildID: call.guildID?.rawValue, channelID: call.channelID.rawValue))
      do {
        activity = try Activity.request(
          attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        activityCall = call
        lastState = state
      } catch {
        logger.error("Couldn't start the voice Live Activity: \(error.localizedDescription)")
      }
    }

    private func end() {
      let id = activity?.id
      activity = nil
      activityCall = nil
      lastState = nil
      if let id { Task.detached { await Self.end(id: id) } }
    }

    // `Activity` isn't Sendable; these find it again by id off the main actor.
    private nonisolated static func update(
      id: String, state: VoiceCallAttributes.ContentState
    ) async {
      for activity in Activity<VoiceCallAttributes>.activities where activity.id == id {
        await activity.update(ActivityContent(state: state, staleDate: nil))
      }
    }

    private nonisolated static func end(id: String?) async {
      for activity in Activity<VoiceCallAttributes>.activities where id == nil || activity.id == id {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }

    /// Ends every voice activity, this run's or an earlier one's.
    func endAll() {
      end()
      Task.detached { await Self.end(id: nil) }
    }
  }
#endif
