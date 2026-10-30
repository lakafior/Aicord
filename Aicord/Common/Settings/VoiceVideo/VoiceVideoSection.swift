//
//  VoiceVideoSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var voiceVideoSection: some View {
    VoiceVideoSettings()
  }
}

/// Microphone, speaker and input mode. Stored on this device only.
struct VoiceVideoSettings: View {
  typealias Prefs = VoicePreferences

  @Environment(\.gateway) var gw

  @AppStorage(Prefs.inputDeviceKey) private var inputDevice = ""
  @AppStorage(Prefs.outputDeviceKey) private var outputDevice = ""
  @AppStorage(Prefs.inputVolumeKey) private var inputVolume = 1.0
  @AppStorage(Prefs.outputVolumeKey) private var outputVolume = 1.0
  @AppStorage(Prefs.inputModeKey) private var inputMode = Prefs.InputMode.voiceActivity
  @AppStorage(Prefs.automaticSensitivityKey) private var automaticSensitivity = true
  @AppStorage(Prefs.sensitivityKey) private var sensitivity = -50.0
  @AppStorage(Prefs.voiceProcessingKey) private var voiceProcessing = true
  @AppStorage(Prefs.automaticGainKey) private var automaticGain = true
  @AppStorage(Prefs.pushToTalkKeyKey) private var pushToTalkKey = Prefs.PushToTalkKey.backtick
  @AppStorage(Prefs.pushToTalkReleaseKey) private var pushToTalkRelease = 0.2

  @State private var inputs: [AudioDevice] = []
  @State private var outputs: [AudioDevice] = []

  var body: some View {
    Section {
      Picker("Input Device", selection: $inputDevice) {
        Text("System Default").tag("")
        ForEach(inputs) { Text($0.name).tag($0.id) }
      }
      #if os(macOS)
        Picker("Output Device", selection: $outputDevice) {
          Text("System Default").tag("")
          ForEach(outputs) { Text($0.name).tag($0.id) }
        }
      #endif
      LabeledContent("Input Volume") {
        Slider(value: $inputVolume, in: 0...2)
          .accessibilityValue(Text(verbatim: "\(Int(inputVolume * 100))%"))
      }
      LabeledContent("Output Volume") {
        Slider(value: $outputVolume, in: 0...2)
          .accessibilityValue(Text(verbatim: "\(Int(outputVolume * 100))%"))
      }
    } header: {
      Text("Devices")
    } footer: {
      #if os(macOS)
        Text(
          "A device change applies the next time you join a call. Volumes above 100% boost the signal and may clip."
        )
      #else
        Text(
          "Sound plays through the current route; pick headphones or a speaker from Control Center. Volumes above 100% boost the signal and may clip."
        )
      #endif
    }

    Section {
      Picker("Input Mode", selection: $inputMode) {
        Text("Voice Activity").tag(Prefs.InputMode.voiceActivity)
        Text("Push to Talk").tag(Prefs.InputMode.pushToTalk)
      }
      if inputMode == .voiceActivity {
        Toggle("Determine Input Sensitivity Automatically", isOn: $automaticSensitivity)
        if !automaticSensitivity {
          LabeledContent("Sensitivity") {
            Slider(value: $sensitivity, in: -80...0, step: 1)
              .accessibilityValue(Text(verbatim: "\(Int(sensitivity)) dB"))
          }
        }
        if gw.voice.call != nil {
          InputLevelMeter(level: gw.voice.inputLevel, threshold: automaticSensitivity ? nil : sensitivity)
        }
      } else {
        #if os(macOS)
          Picker("Push to Talk Key", selection: $pushToTalkKey) {
            ForEach(Prefs.PushToTalkKey.allCases) { Text($0.label).tag($0) }
          }
        #endif
        LabeledContent("Release Delay") {
          Slider(value: $pushToTalkRelease, in: 0...2, step: 0.05)
            .accessibilityValue(Text(verbatim: "\(Int(pushToTalkRelease * 1000)) ms"))
        }
      }
    } header: {
      Text("Input Mode")
    } footer: {
      if inputMode == .pushToTalk {
        #if os(macOS)
          Text(
            "Hold the key while Aicord is the active app, or hold the push-to-talk button in the call panel. Character keys do nothing while you are typing."
          )
        #else
          Text("Hold the push-to-talk button in the call panel to talk.")
        #endif
      } else {
        Text("Your microphone sends audio only while it hears speech.")
      }
    }

    Section {
      Toggle("Echo Cancellation and Noise Suppression", isOn: $voiceProcessing)
      Toggle("Automatic Gain Control", isOn: $automaticGain)
        .disabled(!voiceProcessing)
    } header: {
      Text("Voice Processing")
    } footer: {
      Text(
        "Uses the system's voice processing. Turn it off for a music setup or a studio microphone. Applies the next time you join a call."
      )
    }

    Section {
      LabeledContent("Video and Screen Sharing") {
        Text("Coming Soon").foregroundStyle(.secondary)
      }
    } header: {
      Text("Video")
    }
    .task { reloadDevices() }
    .onChange(of: settingsSignature) { gw.voice.preferencesChanged() }
  }

  /// Changes that apply to a running call right away.
  var settingsSignature: [Double] {
    [
      inputVolume, outputVolume, automaticSensitivity ? 1 : 0, sensitivity,
      inputMode == .pushToTalk ? 1 : 0, pushToTalkRelease,
    ]
  }

  func reloadDevices() {
    inputs = AudioDevices.inputs()
    outputs = AudioDevices.outputs()
  }
}

/// The microphone level against the voice activity threshold.
struct InputLevelMeter: View {
  var level: Float
  var threshold: Double?

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary)
        Capsule()
          .fill(.green)
          .frame(width: width * fraction(Double(level)))
        if let threshold {
          Rectangle()
            .fill(.primary)
            .frame(width: 2)
            .offset(x: width * fraction(threshold))
        }
      }
    }
    .frame(height: 8)
    .animation(.linear(duration: 0.1), value: level)
    .accessibilityLabel(Text("Microphone Level"))
    .accessibilityValue(Text(verbatim: "\(Int(level)) dB"))
  }

  func fraction(_ db: Double) -> CGFloat {
    CGFloat(min(max((db + 80) / 80, 0), 1))
  }
}
