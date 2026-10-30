//
//  VoiceAudioEngine.swift
//  Paicord
//
//  Microphone capture and speaker playback for a voice connection, on
//  AVAudioEngine. The system's voice processing does echo cancellation,
//  noise suppression and (optionally) automatic gain; that replaces
//  Serein's Sonora/RNNoise chain.
//
//  Audio leaves as 20 ms mono 48 kHz frames (`VoiceAudioFormat`) and comes
//  back already mixed by `VoiceGatewayManager`.
//

import AVFoundation
import Foundation
import PaicordLib
import os

#if os(macOS)
  import CoreAudio
#endif

final class VoiceAudioEngine: @unchecked Sendable {
  /// Everything the capture callback reads, behind one lock.
  struct Gate: Sendable {
    var transmitting = false
    /// Push-to-talk sends whatever the key is held for, without detection.
    var pushToTalk = false
    var inputVolume: Float = 1
    var automaticSensitivity = true
    var sensitivity: Float = -50
  }

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: Double(VoiceAudioFormat.sampleRate),
    channels: AVAudioChannelCount(VoiceAudioFormat.channels),
    interleaved: false
  )!
  private let logger = Logger(subsystem: "Paicord", category: "VoiceAudio")
  /// Starting, stopping and reconfiguring run here, in order: activating the
  /// audio session blocks, so it must stay off the main thread.
  private let queue = DispatchQueue(label: "Aicord.VoiceAudio", qos: .userInitiated)
  private let gate = OSAllocatedUnfairLock(initialState: Gate())
  /// Buffers handed to the player and not played yet.
  private let scheduled = OSAllocatedUnfairLock(initialState: 0)

  private let frames = OSAllocatedUnfairLock<AsyncStream<[Float]>.Continuation?>(
    initialState: nil
  )
  private var sendTask: Task<Void, Never>?
  private var playbackTask: Task<Void, Never>?
  private var configurationObserver: (any NSObjectProtocol)?
  private(set) var isRunning = false
  private var hasInput = false

  /// Microphone level in dBFS after gain, about every 100 ms.
  var onInputLevel: (@Sendable (Float, _ isVoice: Bool) -> Void)?

  // MARK: Lifecycle

  /// Starts capture and playback. Captured frames that pass the gate go to
  /// `send`; `playback` is played as it arrives.
  func start(
    capture: Bool,
    playback: AsyncStream<[Float]>?,
    send: (@Sendable ([Float]) async -> Void)?
  ) {
    queue.async { [self] in
      startOnQueue(capture: capture, playback: playback, send: send)
    }
  }

  func stop() {
    queue.async { [self] in stopOnQueue() }
  }

  private func startOnQueue(
    capture: Bool,
    playback: AsyncStream<[Float]>?,
    send: (@Sendable ([Float]) async -> Void)?
  ) {
    stopOnQueue()
    loadPreferences()
    #if os(iOS)
      configureSession()
    #endif

    let input = engine.inputNode
    #if os(macOS)
      select(device: VoicePreferences.inputDeviceID, on: input.audioUnit)
      select(device: VoicePreferences.outputDeviceID, on: engine.outputNode.audioUnit)
    #endif
    if VoicePreferences.voiceProcessing {
      do {
        try input.setVoiceProcessingEnabled(true)
        input.isVoiceProcessingAGCEnabled = VoicePreferences.automaticGain
        input.isVoiceProcessingBypassed = false
      } catch {
        logger.error("Voice processing unavailable: \(error.localizedDescription)")
      }
    }

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = VoicePreferences.outputVolume

    if let send {
      let (stream, continuation) = AsyncStream.makeStream(
        of: [Float].self,
        bufferingPolicy: .bufferingNewest(8)
      )
      frames.withLock { $0 = continuation }
      sendTask = Task.detached(priority: .userInitiated) {
        for await frame in stream { await send(frame) }
      }
    }

    hasInput = capture && input.inputFormat(forBus: 0).channelCount > 0
    if hasInput {
      installTap(on: input)
    }

    do {
      engine.prepare()
      try engine.start()
      player.play()
      isRunning = true
      logger.info("Audio engine started (input: \(self.hasInput))")
    } catch {
      logger.error("Audio engine failed to start: \(error.localizedDescription)")
      return
    }

    if let playback {
      playbackTask = Task.detached(priority: .userInitiated) { [weak self] in
        for await frame in playback { self?.play(frame) }
      }
    }

    configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange,
      object: engine,
      queue: nil
    ) { [weak self] _ in
      // A device came or went: restart the graph keeping the same streams.
      guard let self else { return }
      queue.async { self.restartAfterConfigurationChange() }
    }
  }

  private func stopOnQueue() {
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
    }
    configurationObserver = nil
    frames.withLock {
      $0?.finish()
      $0 = nil
    }
    sendTask?.cancel()
    playbackTask?.cancel()
    sendTask = nil
    playbackTask = nil
    guard isRunning || engine.attachedNodes.contains(player) else { return }
    engine.inputNode.removeTap(onBus: 0)
    player.stop()
    engine.stop()
    if engine.attachedNodes.contains(player) { engine.detach(player) }
    engine.reset()
    scheduled.withLock { $0 = 0 }
    isRunning = false
    #if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
    logger.info("Audio engine stopped")
  }

  private func restartAfterConfigurationChange() {
    guard isRunning else { return }
    logger.info("Audio configuration changed; restarting the engine")
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    if hasInput { installTap(on: engine.inputNode) }
    do {
      try engine.start()
      player.play()
    } catch {
      logger.error("Audio engine restart failed: \(error.localizedDescription)")
    }
  }

  // MARK: Controls

  /// Whether captured audio may leave (unmuted and, for push-to-talk, held).
  func setTransmitting(_ transmitting: Bool) {
    gate.withLock { $0.transmitting = transmitting }
  }

  func setDeafened(_ deafened: Bool) {
    queue.async { [self] in
      engine.mainMixerNode.outputVolume = deafened ? 0 : VoicePreferences.outputVolume
    }
  }

  /// Picks up changes made in Settings while running.
  func loadPreferences() {
    gate.withLock {
      $0.inputVolume = VoicePreferences.inputVolume
      $0.automaticSensitivity = VoicePreferences.automaticSensitivity
      $0.sensitivity = VoicePreferences.sensitivity
      $0.pushToTalk = VoicePreferences.inputMode == .pushToTalk
    }
    queue.async { [self] in
      if isRunning {
        engine.mainMixerNode.outputVolume = VoicePreferences.outputVolume
      }
    }
  }

  // MARK: Capture

  private func installTap(on input: AVAudioInputNode) {
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0,
      let converter = AVAudioConverter(from: inputFormat, to: format)
    else {
      logger.error("No usable microphone format")
      return
    }
    let frameSamples = VoiceAudioFormat.frameSamples
    var pending: [Float] = []
    var activity = VoiceActivity()
    var levelFrames = 0

    input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
      [weak self] buffer, _ in
      guard let self else { return }
      let capacity = AVAudioFrameCount(
        Double(buffer.frameLength) * self.format.sampleRate / inputFormat.sampleRate + 32
      )
      guard let converted = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: capacity)
      else { return }
      var supplied = false
      var error: NSError?
      converter.convert(to: converted, error: &error) { _, status in
        if supplied {
          status.pointee = .noDataNow
          return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, let samples = converted.floatChannelData?[0] else { return }
      pending.append(
        contentsOf: UnsafeBufferPointer(start: samples, count: Int(converted.frameLength))
      )

      let gate = self.gate.withLock { $0 }
      while pending.count >= frameSamples {
        var frame = Array(pending[..<frameSamples])
        pending.removeFirst(frameSamples)
        var energy: Float = 0
        for i in frame.indices {
          let sample = min(max(frame[i] * gate.inputVolume, -1), 1)
          frame[i] = sample
          energy += sample * sample
        }
        let level = 10 * log10(max(energy / Float(frameSamples), 1e-10))
        let isVoice = activity.update(
          level: level,
          automatic: gate.automaticSensitivity,
          threshold: gate.sensitivity
        )
        levelFrames += 1
        if levelFrames >= 5 {
          levelFrames = 0
          self.onInputLevel?(level, isVoice)
        }
        if gate.transmitting, isVoice || gate.pushToTalk {
          let ready = frame
          self.frames.withLock { _ = $0?.yield(ready) }
        }
      }
    }
  }

  // MARK: Playback

  private func play(_ samples: [Float]) {
    // Keep at most ~120 ms queued; drop rather than drift behind.
    guard scheduled.withLock({ $0 }) < 6,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
      ),
      let channel = buffer.floatChannelData?[0]
    else { return }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer {
      channel.update(from: $0.baseAddress!, count: samples.count)
    }
    scheduled.withLock { $0 += 1 }
    player.scheduleBuffer(buffer) { [weak self] in
      self?.scheduled.withLock { $0 = max(0, $0 - 1) }
    }
  }

  // MARK: Platform

  #if os(iOS)
    private func configureSession() {
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(
          .playAndRecord,
          mode: .voiceChat,
          options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        if let uid = VoicePreferences.inputDeviceID,
          let port = session.availableInputs?.first(where: { $0.uid == uid })
        {
          try session.setPreferredInput(port)
        }
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
      } catch {
        logger.error("Audio session setup failed: \(error.localizedDescription)")
      }
    }
  #endif

  #if os(macOS)
    private func select(device uid: String?, on unit: AudioUnit?) {
      guard let uid, let unit, var id = AudioDevices.deviceID(forUID: uid) else { return }
      let status = AudioUnitSetProperty(
        unit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &id,
        UInt32(MemoryLayout<AudioDeviceID>.size)
      )
      if status != noErr {
        logger.error("Could not select audio device (\(status))")
      }
    }
  #endif
}

/// Voice activity detection on frame levels: a threshold with 3 dB of
/// hysteresis and a 300 ms hold so word endings are not cut.
struct VoiceActivity {
  private var holdFrames = 0
  private var noiseFloor: Float = -60
  private(set) var isActive = false

  mutating func update(level: Float, automatic: Bool, threshold manual: Float) -> Bool {
    let threshold: Float
    if automatic {
      // Track the quietest recent level and open 15 dB above it.
      noiseFloor =
        level < noiseFloor ? level : min(noiseFloor + 0.05, -20)
      threshold = max(noiseFloor + 15, -60)
    } else {
      threshold = manual
    }
    let opening = isActive ? threshold - 3 : threshold
    if level >= opening {
      isActive = true
      holdFrames = 15
    } else if holdFrames > 0 {
      holdFrames -= 1
    } else {
      isActive = false
    }
    return isActive
  }
}
