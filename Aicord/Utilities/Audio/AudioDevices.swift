//
//  AudioDevices.swift
//  Aicord
//
//  Lists microphones and speakers. macOS reads Core Audio; iOS only lets
//  the app choose an input, outputs follow the system route.
//

import AVFoundation
import Foundation

#if os(macOS)
  import CoreAudio
#endif

struct AudioDevice: Identifiable, Hashable {
  /// Core Audio device UID on macOS, AVAudioSession port UID on iOS.
  var id: String
  var name: String
}

enum AudioDevices {
  static func inputs() -> [AudioDevice] {
    #if os(macOS)
      devices(scope: kAudioObjectPropertyScopeInput)
    #else
      (AVAudioSession.sharedInstance().availableInputs ?? []).map {
        AudioDevice(id: $0.uid, name: $0.portName)
      }
    #endif
  }

  static func outputs() -> [AudioDevice] {
    #if os(macOS)
      devices(scope: kAudioObjectPropertyScopeOutput)
    #else
      []
    #endif
  }

  #if os(macOS)
    /// The Core Audio ID for a saved device UID, if it is still connected.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
      allDeviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func devices(scope: AudioObjectPropertyScope) -> [AudioDevice] {
      allDeviceIDs().compactMap { id in
        guard hasStreams(id, scope: scope),
          let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
          let name = stringProperty(id, kAudioObjectPropertyName)
        else { return nil }
        return AudioDevice(id: uid, name: name)
      }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      var size: UInt32 = 0
      guard
        AudioObjectGetPropertyDataSize(
          AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr
      else { return [] }
      var ids = [AudioDeviceID](
        repeating: 0,
        count: Int(size) / MemoryLayout<AudioDeviceID>.size
      )
      guard
        AudioObjectGetPropertyData(
          AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr
      else { return [] }
      return ids
    }

    private static func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope)
      -> Bool
    {
      var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
      )
      var size: UInt32 = 0
      return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr
        && size > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector)
      -> String?
    {
      var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      var value: Unmanaged<CFString>?
      var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
      guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
        let value
      else { return nil }
      return value.takeRetainedValue() as String
    }
  #endif
}
