//
//  VoiceCallActivity.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//
//  The Live Activity of a voice call and its buttons. Compiled into the app
//  and the widget extension; the buttons' intents run in the app, which has
//  the call (`VoiceCallIntentRouter`).
//

#if os(iOS)
  import ActivityKit
  import AppIntents
  import Foundation

  struct VoiceCallAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
      var isMuted: Bool
      var isDeafened: Bool
      /// Others in the call.
      var participants: Int
      var isConnected: Bool
    }

    /// "#channel" or the DM's name.
    var channelName: String
    /// The server, empty for a DM.
    var serverName: String
    var startedAt: Date
    var link: AicordLink
  }

  /// What the Live Activity's buttons do; the app fills it in at launch. The
  /// widget extension never sets it, its copies of the intents do nothing.
  @MainActor
  enum VoiceCallIntentRouter {
    static var toggleMute: (() -> Void)?
    static var leave: (() -> Void)?
  }

  struct ToggleVoiceMuteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mute or Unmute"
    static let description = IntentDescription("Turns your microphone off or on in the voice call.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
      VoiceCallIntentRouter.toggleMute?()
      return .result()
    }
  }

  struct LeaveVoiceCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Leave Voice Call"
    static let description = IntentDescription("Disconnects from the voice call.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
      VoiceCallIntentRouter.leave?()
      return .result()
    }
  }
#endif
