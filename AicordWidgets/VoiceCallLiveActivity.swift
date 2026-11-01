//
//  VoiceCallLiveActivity.swift
//  AicordWidgets
//
//  Created by Lakafior on 01/11/2026.
//
//  The voice call on the Lock Screen and in the Dynamic Island.
//

#if os(iOS)
  import ActivityKit
  import AppIntents
  import SwiftUI
  import WidgetKit

  struct VoiceCallLiveActivity: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: VoiceCallAttributes.self) { context in
        VoiceCallLockScreenView(context: context)
          .padding()
          .activityBackgroundTint(nil)
          .widgetURL(context.attributes.link.url)
      } dynamicIsland: { context in
        DynamicIsland {
          DynamicIslandExpandedRegion(.leading) {
            Label {
              Text(verbatim: context.attributes.channelName)
                .lineLimit(1)
            } icon: {
              Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.green)
            }
            .font(.headline)
          }
          DynamicIslandExpandedRegion(.trailing) {
            Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
              .monospacedDigit()
              .multilineTextAlignment(.trailing)
              .frame(maxWidth: 70)
          }
          DynamicIslandExpandedRegion(.bottom) {
            HStack {
              VoiceCallSubtitle(context: context)
              Spacer()
              VoiceCallButtons(state: context.state)
            }
          }
        } compactLeading: {
          Image(systemName: context.state.isMuted ? "mic.slash.fill" : "speaker.wave.2.fill")
            .foregroundStyle(context.state.isMuted ? .red : .green)
        } compactTrailing: {
          Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .frame(maxWidth: 44)
        } minimal: {
          Image(systemName: context.state.isMuted ? "mic.slash.fill" : "speaker.wave.2.fill")
            .foregroundStyle(context.state.isMuted ? .red : .green)
        }
        .widgetURL(context.attributes.link.url)
      }
    }
  }

  struct VoiceCallLockScreenView: View {
    let context: ActivityViewContext<VoiceCallAttributes>

    var body: some View {
      HStack(spacing: 12) {
        Image(systemName: "speaker.wave.2.fill")
          .font(.title2)
          .foregroundStyle(.green)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: context.attributes.channelName)
            .font(.headline)
            .lineLimit(1)
          VoiceCallSubtitle(context: context)
          Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        Spacer()
        VoiceCallButtons(state: context.state)
      }
    }
  }

  struct VoiceCallSubtitle: View {
    let context: ActivityViewContext<VoiceCallAttributes>

    var body: some View {
      Group {
        if !context.state.isConnected {
          Text("Connecting…")
        } else if context.state.participants == 0 {
          Text("Only you")
        } else {
          Text("\(context.state.participants) others")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
  }

  struct VoiceCallButtons: View {
    let state: VoiceCallAttributes.ContentState

    var body: some View {
      HStack(spacing: 8) {
        Button(intent: ToggleVoiceMuteIntent()) {
          Image(systemName: state.isMuted ? "mic.slash.fill" : "mic.fill")
            .frame(width: 22, height: 22)
        }
        .tint(state.isMuted ? .red : .gray)
        .accessibilityLabel(state.isMuted ? Text("Unmute") : Text("Mute"))
        Button(intent: LeaveVoiceCallIntent()) {
          Image(systemName: "phone.down.fill")
            .frame(width: 22, height: 22)
        }
        .tint(.red)
        .accessibilityLabel(Text("Disconnect"))
      }
      .buttonStyle(.borderedProminent)
      .buttonBorderShape(.circle)
    }
  }
#endif
