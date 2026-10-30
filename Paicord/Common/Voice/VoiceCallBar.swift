//
//  VoiceCallBar.swift
//  Paicord
//
//  The call panel above the profile bar (and the tab bar accessory on
//  iPhone): where the call is, its state, and mute, deafen, leave.
//

import AicordKit
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct VoiceCallBar: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  var voice: VoiceConnectionStore { gw.voice }

  var body: some View {
    if let call = voice.call {
      content(call)
        #if os(macOS)
          .background(PushToTalkMonitor(voice: voice))
        #endif
    } else if case .failed(let message) = voice.phase {
      HStack {
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
    }
  }

  @ViewBuilder
  func content(_ call: VoiceConnectionStore.Call) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            Image(systemName: statusSymbol)
            Text(statusText)
              .bold()
            if voice.phase == .connected, voice.daveProtocolVersion > 0 {
              Image(systemName: "lock.fill")
                .imageScale(.small)
                .help(Text("End-to-end encrypted"))
                .accessibilityLabel(Text("End-to-end encrypted"))
            }
          }
          .font(.subheadline)
          .foregroundStyle(statusColor)
          Button {
            open(call)
          } label: {
            Text(placeName(call))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          .buttonStyle(.plain)
        }
        Spacer(minLength: 4)
        Button {
          voice.leave()
        } label: {
          Image(systemName: "phone.down.fill")
            .padding(6)
        }
        .buttonStyle(.borderless)
        .tint(.red)
        .foregroundStyle(.red)
        .help(Text("Disconnect"))
        .accessibilityLabel(Text("Disconnect"))
      }

      HStack(spacing: 6) {
        Button {
          voice.toggleMute()
        } label: {
          Image(systemName: voice.isMuted || voice.isDeafened ? "mic.slash.fill" : "mic.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .foregroundStyle(voice.isMuted || voice.isDeafened ? .red : .primary)
        .keyboardShortcut("m", modifiers: [.command, .shift])
        .help(Text(voice.isMuted ? "Unmute" : "Mute"))
        .accessibilityLabel(Text(voice.isMuted ? "Unmute" : "Mute"))

        Button {
          voice.toggleDeafen()
        } label: {
          Image(systemName: voice.isDeafened ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .foregroundStyle(voice.isDeafened ? .red : .primary)
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .help(Text(voice.isDeafened ? "Undeafen" : "Deafen"))
        .accessibilityLabel(Text(voice.isDeafened ? "Undeafen" : "Deafen"))

        if voice.usesPushToTalk {
          PushToTalkButton(voice: voice)
        }
      }
      .buttonStyle(.borderless)
      .glassEffect(.regular, in: .capsule)

      if voice.microphoneDenied {
        Text("Microphone access is off. Allow it in System Settings to talk.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .glassEffect(.regular, in: .rect(cornerRadius: 14))
    .padding(.horizontal, 8)
    .padding(.top, 4)
  }

  var statusText: LocalizedStringKey {
    switch voice.phase {
    case .idle, .joining, .connecting: "Connecting…"
    case .encrypting: "Securing…"
    case .connected: "Voice Connected"
    case .reconnecting: "Reconnecting…"
    case .failed: "Disconnected"
    }
  }

  var statusSymbol: String {
    switch voice.phase {
    case .connected: "waveform"
    case .failed: "exclamationmark.triangle.fill"
    default: "antenna.radiowaves.left.and.right"
    }
  }

  var statusColor: Color {
    switch voice.phase {
    case .connected: .green
    case .failed: .red
    default: .orange
    }
  }

  func placeName(_ call: VoiceConnectionStore.Call) -> String {
    if let guildID = call.guildID,
      let guild = gw.existingGuildStore(for: guildID)
    {
      let channel = guild.channels[call.channelID]?.name ?? ""
      return "\(channel) / \(guild.guild?.name ?? "")"
    }
    let channel = gw.user.privateChannels[call.channelID]
    return channel?.name
      ?? channel?.recipients?.map { $0.global_name ?? $0.username }
        .joined(separator: ", ")
      ?? String(localized: "Call")
  }

  func open(_ call: VoiceConnectionStore.Call) {
    appState.selectedGuild = call.guildID
    appState.selectedChannel = call.channelID
  }
}

/// Hold to talk; for push-to-talk on touch screens and with the mouse.
struct PushToTalkButton: View {
  let voice: VoiceConnectionStore
  @GestureState private var isHeld = false

  var body: some View {
    Image(systemName: "dot.radiowaves.left.and.right")
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .foregroundStyle(voice.isPushToTalkHeld ? .green : .secondary)
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0)
          .updating($isHeld) { _, state, _ in state = true }
      )
      .onChange(of: isHeld) { _, held in voice.setPushToTalk(held) }
      .accessibilityLabel(Text("Push to Talk"))
      .accessibilityAddTraits(.isButton)
  }
}

#if os(macOS)
  /// Push-to-talk on a key, while Aicord is focused. A character key does
  /// nothing while a text field has focus, so typing is never transmitted.
  struct PushToTalkMonitor: NSViewRepresentable {
    let voice: VoiceConnectionStore

    func makeNSView(context: Context) -> NSView {
      context.coordinator.start()
      return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
      coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(voice: voice) }

    @MainActor
    final class Coordinator {
      let voice: VoiceConnectionStore
      var monitor: Any?
      var held = false

      init(voice: VoiceConnectionStore) { self.voice = voice }

      func start() {
        monitor = NSEvent.addLocalMonitorForEvents(
          matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
          guard let self, self.voice.usesPushToTalk else { return event }
          let key = VoicePreferences.pushToTalkKey
          guard event.keyCode == key.keyCode else { return event }
          if key.isModifier {
            let down = !event.modifierFlags
              .intersection(.deviceIndependentFlagsMask)
              .intersection([.option, .command, .control]).isEmpty
            self.set(down)
            return event
          }
          if NSApp.keyWindow?.firstResponder is NSTextView { return event }
          switch event.type {
          case .keyDown: self.set(true)
          case .keyUp: self.set(false)
          default: return event
          }
          return nil
        }
      }

      func set(_ down: Bool) {
        guard down != held else { return }
        held = down
        voice.setPushToTalk(down)
      }

      func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if held { voice.setPushToTalk(false) }
      }
    }
  }
#endif

/// The call as a tab bar accessory on iPhone.
struct VoiceCallAccessoryModifier: ViewModifier {
  let isInCall: Bool

  func body(content: Content) -> some View {
    #if os(iOS)
      if #available(iOS 26.1, *) {
        content.tabViewBottomAccessory(isEnabled: isInCall) {
          VoiceCallAccessory()
        }
      } else {
        content.safeAreaInset(edge: .bottom) {
          if isInCall { VoiceCallBar() }
        }
      }
    #else
      content
    #endif
  }
}

/// A one-line version of the call bar.
struct VoiceCallAccessory: View {
  @Environment(\.gateway) var gw

  var voice: VoiceConnectionStore { gw.voice }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: voice.phase == .connected ? "waveform" : "antenna.radiowaves.left.and.right")
        .foregroundStyle(voice.phase == .connected ? .green : .orange)
      Text(voice.phase == .connected ? "Voice Connected" : "Connecting…")
        .font(.subheadline.bold())
        .lineLimit(1)
      Spacer()
      if voice.usesPushToTalk {
        PushToTalkButton(voice: voice)
          .frame(width: 36)
      }
      Button {
        voice.toggleMute()
      } label: {
        Image(systemName: voice.isMuted || voice.isDeafened ? "mic.slash.fill" : "mic.fill")
      }
      .foregroundStyle(voice.isMuted || voice.isDeafened ? .red : .primary)
      .accessibilityLabel(Text(voice.isMuted ? "Unmute" : "Mute"))
      Button {
        voice.toggleDeafen()
      } label: {
        Image(systemName: voice.isDeafened ? "speaker.slash.fill" : "speaker.wave.2.fill")
      }
      .foregroundStyle(voice.isDeafened ? .red : .primary)
      .accessibilityLabel(Text(voice.isDeafened ? "Undeafen" : "Deafen"))
      Button {
        voice.leave()
      } label: {
        Image(systemName: "phone.down.fill")
      }
      .foregroundStyle(.red)
      .accessibilityLabel(Text("Disconnect"))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 16)
  }
}

/// Starts (and rings) or joins a DM or group call.
struct DMCallButton: View {
  @Environment(\.gateway) var gw
  let channelID: ChannelSnowflake

  var voice: VoiceConnectionStore { gw.voice }
  var isInThisCall: Bool { voice.call?.channelID == channelID }

  var body: some View {
    Button {
      if isInThisCall {
        voice.leave()
      } else {
        voice.join(channelID: channelID, guildID: nil, ring: true)
      }
    } label: {
      Image(systemName: isInThisCall ? "phone.down.fill" : "phone.fill")
    }
    .help(isInThisCall ? Text("Leave Call") : Text("Start Voice Call"))
    .accessibilityLabel(isInThisCall ? Text("Leave Call") : Text("Start Voice Call"))
  }
}
