//
//  VoiceMessageButton.swift
//  Aicord
//

import AicordKit
import SwiftUI

/// The microphone next to the message field. On iPhone and iPad hold it to
/// record and let go to send (slide left to cancel); on the Mac click it, then
/// Send or Cancel in the bar that replaces the field.
struct VoiceMessageButton: View {
  var recorder: VoiceMessageRecorder
  var channel: ChannelSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.theme) var theme

  @State private var cancelsOnRelease = false
  @State private var isPressing = false
  @State private var error: String?

  var body: some View {
    Group {
      #if os(iOS)
        Image(systemName: recorder.isRecording ? "mic.fill" : "mic")
          .imageScale(.large)
          .padding(7.5)
          .foregroundStyle(recorder.isRecording ? .white : .primary)
          .background(
            recorder.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.background.secondary.opacity(0.8)),
            in: .circle
          )
          .scaleEffect(recorder.isRecording ? 1.25 : 1)
          .animation(.spring(duration: 0.25), value: recorder.isRecording)
          .gesture(holdToRecord)
          .accessibilityLabel(Text("Record Voice Message"))
          .accessibilityHint(Text("Double-tap to start recording, then double-tap again to send"))
          .accessibilityAction { toggleForAccessibility() }
      #else
        Button {
          Task { await start() }
        } label: {
          Image(systemName: "mic")
            .imageScale(.large)
            .padding(.trailing, 6)
        }
        .buttonStyle(.borderless)
        .help(Text("Record Voice Message"))
        .disabled(recorder.state != .idle)
      #endif
    }
    .saveErrorAlert($error)
  }

  #if os(iOS)
    private var holdToRecord: some Gesture {
      DragGesture(minimumDistance: 0)
        .onChanged { drag in
          if !isPressing {
            isPressing = true
            guard recorder.state == .idle else { return }
            Task {
              await start()
              // let go while the microphone prompt was up
              if !isPressing { recorder.cancel() }
            }
          }
          cancelsOnRelease = drag.translation.width < -80
        }
        .onEnded { _ in
          isPressing = false
          if cancelsOnRelease {
            recorder.cancel()
          } else {
            send()
          }
          cancelsOnRelease = false
        }
    }

    private func toggleForAccessibility() {
      if recorder.isRecording {
        send()
      } else {
        Task { await start() }
      }
    }
  #endif

  private func start() async {
    if await !recorder.start() {
      error = String(localized: "Aicord can't use the microphone. Allow it in System Settings → Privacy & Security → Microphone.")
    }
  }

  private func send() {
    guard let recording = recorder.stop() else { return }
    let client = gw.client
    Task {
      do {
        try await recorder.send(recording, to: channel, client: client)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// Shown instead of the message field while a voice message records or sends.
struct VoiceRecordingBar: View {
  var recorder: VoiceMessageRecorder
  var channel: ChannelSnowflake
  @Environment(\.gateway) var gw
  @State private var error: String?

  var body: some View {
    HStack(spacing: 10) {
      #if os(macOS)
        Button {
          recorder.cancel()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .help(Text("Cancel"))
      #endif
      Circle()
        .fill(.red)
        .frame(width: 8, height: 8)
      if case .recording(let started) = recorder.state {
        TimelineView(.periodic(from: started, by: 1)) { context in
          Text(Duration.seconds(context.date.timeIntervalSince(started)), format: .time(pattern: .minuteSecond))
            .monospacedDigit()
        }
      } else {
        Text("Sending…")
      }
      HStack(alignment: .center, spacing: 2) {
        ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
          Capsule()
            .fill(.secondary)
            .frame(width: 3, height: max(3, CGFloat(level) * 22))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 24)
      .accessibilityHidden(true)
      #if os(iOS)
        Text("\(Image(systemName: "chevron.left")) Slide to cancel")
          .font(.caption)
          .foregroundStyle(.secondary)
      #else
        Button("Send") { send() }
          .buttonStyle(.borderedProminent)
          .disabled(!recorder.isRecording)
      #endif
    }
    .padding(.horizontal, 12)
    .frame(maxHeight: .infinity)
    // covers the message field it sits over
    .background(.background.secondary)
    .background(.background)
    .clipShape(.rect(cornerRadius: 18))
    .saveErrorAlert($error)
  }

  private func send() {
    guard let recording = recorder.stop() else { return }
    let client = gw.client
    Task {
      do {
        try await recorder.send(recording, to: channel, client: client)
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
