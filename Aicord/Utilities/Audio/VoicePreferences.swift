//
//  VoicePreferences.swift
//  Aicord
//
//  Device-local voice settings, shown in Settings → Voice & Video.
//  Nothing here is sent to Discord.
//

import Foundation

enum VoicePreferences {
  static let inputDeviceKey = "Paicord.Voice.InputDevice"
  static let outputDeviceKey = "Paicord.Voice.OutputDevice"
  static let inputVolumeKey = "Paicord.Voice.InputVolume"
  static let outputVolumeKey = "Paicord.Voice.OutputVolume"
  static let inputModeKey = "Paicord.Voice.InputMode"
  static let automaticSensitivityKey = "Paicord.Voice.AutomaticSensitivity"
  static let sensitivityKey = "Paicord.Voice.Sensitivity"
  static let voiceProcessingKey = "Paicord.Voice.VoiceProcessing"
  static let automaticGainKey = "Paicord.Voice.AutomaticGain"
  static let pushToTalkKeyKey = "Paicord.Voice.PushToTalkKey"
  static let pushToTalkReleaseKey = "Paicord.Voice.PushToTalkRelease"
  static let mutedKey = "Paicord.Voice.Muted"
  static let deafenedKey = "Paicord.Voice.Deafened"
  /// Debug: join without opening the microphone or asking for it
  /// (`-Paicord.Voice.ListenOnly YES` on the command line).
  static let listenOnlyKey = "Paicord.Voice.ListenOnly"

  enum InputMode: String, CaseIterable, Identifiable {
    case voiceActivity
    case pushToTalk
    var id: Self { self }
  }

  /// Keys that can hold push-to-talk while Aicord is focused.
  enum PushToTalkKey: String, CaseIterable, Identifiable {
    case backtick
    case rightOption
    case rightCommand
    case rightControl
    case f13
    var id: Self { self }

    var label: String {
      switch self {
      case .backtick: "` (Backtick)"
      case .rightOption: "Right Option"
      case .rightCommand: "Right Command"
      case .rightControl: "Right Control"
      case .f13: "F13"
      }
    }

    /// macOS virtual key codes.
    var keyCode: UInt16 {
      switch self {
      case .backtick: 50
      case .rightOption: 61
      case .rightCommand: 54
      case .rightControl: 62
      case .f13: 105
      }
    }

    var isModifier: Bool {
      switch self {
      case .rightOption, .rightCommand, .rightControl: true
      default: false
      }
    }
  }

  private static var defaults: UserDefaults { .standard }

  static func register() {
    defaults.register(defaults: [
      inputVolumeKey: 1.0,
      outputVolumeKey: 1.0,
      inputModeKey: InputMode.voiceActivity.rawValue,
      automaticSensitivityKey: true,
      sensitivityKey: -50.0,
      voiceProcessingKey: true,
      automaticGainKey: true,
      pushToTalkKeyKey: PushToTalkKey.backtick.rawValue,
      pushToTalkReleaseKey: 0.2,
    ])
  }

  /// `nil` follows the system default device.
  static var inputDeviceID: String? {
    defaults.string(forKey: inputDeviceKey).flatMap { $0.isEmpty ? nil : $0 }
  }
  static var outputDeviceID: String? {
    defaults.string(forKey: outputDeviceKey).flatMap { $0.isEmpty ? nil : $0 }
  }
  /// 0...2, applied in software.
  static var inputVolume: Float { Float(defaults.double(forKey: inputVolumeKey)) }
  static var outputVolume: Float { Float(defaults.double(forKey: outputVolumeKey)) }
  static var inputMode: InputMode {
    InputMode(rawValue: defaults.string(forKey: inputModeKey) ?? "") ?? .voiceActivity
  }
  static var automaticSensitivity: Bool { defaults.bool(forKey: automaticSensitivityKey) }
  /// dBFS threshold for voice activity when not automatic.
  static var sensitivity: Float { Float(defaults.double(forKey: sensitivityKey)) }
  /// Echo cancellation and noise suppression from the system.
  static var voiceProcessing: Bool { defaults.bool(forKey: voiceProcessingKey) }
  static var automaticGain: Bool { defaults.bool(forKey: automaticGainKey) }
  static var pushToTalkKey: PushToTalkKey {
    PushToTalkKey(rawValue: defaults.string(forKey: pushToTalkKeyKey) ?? "") ?? .backtick
  }
  static var pushToTalkRelease: Double { defaults.double(forKey: pushToTalkReleaseKey) }
  static var listenOnly: Bool { defaults.bool(forKey: listenOnlyKey) }
}
