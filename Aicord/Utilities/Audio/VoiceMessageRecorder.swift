//
//  VoiceMessageRecorder.swift
//  Aicord
//

import AVFoundation
import AicordKit
import Foundation

/// Records a voice message the way Discord's apps send one: 48 kHz mono Opus
/// in an Ogg file, with its length and a waveform of up to 256 bars.
@MainActor
@Observable
final class VoiceMessageRecorder {
  enum State: Equatable {
    case idle
    case recording(started: Date)
    case sending
  }

  struct Recording {
    var data: Data
    var duration: Double
    /// Base64 of one byte (0–255) per bar.
    var waveform: String
  }

  private(set) var state: State = .idle
  /// The last few levels (0–1), for the live meter.
  private(set) var levels: [Float] = []

  @ObservationIgnored private var engine: AVAudioEngine?
  @ObservationIgnored private let worker = Worker()

  var isRecording: Bool {
    if case .recording = state { true } else { false }
  }

  /// Asks for the microphone, then starts. Returns false when it can't record.
  func start() async -> Bool {
    guard state == .idle else { return false }
    guard await AVAudioApplication.requestRecordPermission() else { return false }
    #if os(iOS)
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
      } catch {
        print("[VoiceMessage] Audio session failed:", error)
        return false
      }
    #endif
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, worker.prepare(from: inputFormat) else { return false }
    Self.installTap(on: input, format: inputFormat, worker: worker) { [weak self] level in
      guard let self else { return }
      self.levels.append(level)
      if self.levels.count > 40 { self.levels.removeFirst(self.levels.count - 40) }
    }
    do {
      try engine.start()
    } catch {
      print("[VoiceMessage] Engine failed:", error)
      input.removeTap(onBus: 0)
      return false
    }
    self.engine = engine
    levels = []
    state = .recording(started: .now)
    return true
  }

  /// The tap runs on the audio thread, so its block must not be main-actor
  /// isolated (Swift 6 checks that at run time and traps).
  private nonisolated static func installTap(
    on input: AVAudioInputNode,
    format: AVAudioFormat,
    worker: Worker,
    level: @escaping @MainActor @Sendable (Float) -> Void
  ) {
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
      guard let loudness = worker.append(buffer) else { return }
      Task { @MainActor in level(loudness) }
    }
  }

  /// Stops and returns the file, or nil when it was too short or failed.
  func stop() -> Recording? {
    guard isRecording else { return nil }
    finishEngine()
    state = .idle
    return worker.finish()
  }

  func cancel() {
    guard isRecording else { return }
    finishEngine()
    _ = worker.finish()
    state = .idle
  }

  private func finishEngine() {
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    #if os(iOS)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

  /// Sends a recording to a channel as a voice message: upload to Discord's
  /// storage, then a message with only that attachment and the voice flag.
  func send(_ recording: Recording, to channel: ChannelSnowflake, client: any DiscordClient) async throws {
    state = .sending
    defer { state = .idle }
    let filename = "voice-message.ogg"
    let slots = try await client.createAttachments(
      channelID: channel,
      payload: .init(files: [.init(filename: filename, file_size: recording.data.count)])
    ).decode()
    guard let slot = slots.attachments.first, let url = URL(string: slot.upload_url) else {
      throw URLError(.badServerResponse)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("audio/ogg", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.upload(for: request, from: recording.data)
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
      throw URLError(.cannotWriteToFile)
    }
    let attachment = Payloads.Attachment(
      index: 0,
      filename: filename,
      uploaded_filename: slot.upload_filename,
      content_type: "audio/ogg",
      duration_secs: recording.duration,
      waveform: recording.waveform
    )
    let nonce = try MessageSnowflake.makeFake(date: .now).rawValue
    try await client.createMessage(
      channelId: channel,
      payload: Payloads.CreateMessage(
        nonce: .string(nonce),
        attachments: [attachment],
        flags: [.isVoiceMessage]
      )
    ).guardSuccess()
  }

  // MARK: - Encoding

  /// Converts, encodes and keeps the pages off the main actor; the audio tap
  /// calls it on the engine's thread.
  private final class Worker: @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    private var encoder: OpusEncoder?
    private var pending: [Float] = []
    private var writer = OggOpusWriter()
    private var peaks: [Float] = []
    private var frames = 0

    func prepare(from inputFormat: AVAudioFormat) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      converter = AVAudioConverter(from: inputFormat, to: outputFormat)
      encoder = try? OpusEncoder(bitrate: 64_000)
      pending = []
      writer = OggOpusWriter()
      peaks = []
      frames = 0
      return converter != nil && encoder != nil
    }

    /// Encodes what's whole of a buffer; returns its loudness for the meter.
    func append(_ buffer: AVAudioPCMBuffer) -> Float? {
      lock.lock()
      defer { lock.unlock() }
      guard let converter, let encoder else { return nil }
      let ratio = outputFormat.sampleRate / buffer.format.sampleRate
      let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
      guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
        return nil
      }
      var fed = false
      var error: NSError?
      converter.convert(to: converted, error: &error) { _, status in
        if fed {
          status.pointee = .noDataNow
          return nil
        }
        fed = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, let channel = converted.floatChannelData?[0] else { return nil }
      pending.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))

      var loudest: Float = 0
      let frameSamples = VoiceAudioFormat.frameSamples
      while pending.count >= frameSamples {
        let frame = Array(pending.prefix(frameSamples))
        pending.removeFirst(frameSamples)
        let peak = frame.reduce(Float(0)) { max($0, abs($1)) }
        peaks.append(peak)
        loudest = max(loudest, peak)
        if let packet = try? frame.withUnsafeBufferPointer({ try encoder.encode($0) }) {
          frames += 1
          writer.append(packet, granule: Int64(frames * frameSamples))
        }
      }
      return min(1, loudest * 1.5)
    }

    func finish() -> Recording? {
      lock.lock()
      defer { lock.unlock() }
      let duration = Double(frames * VoiceAudioFormat.frameSamples) / 48_000
      // Discord's apps don't send voice messages under about a second
      guard duration >= 1, let data = writer.finish() else { return nil }
      return Recording(data: data, duration: duration, waveform: Self.waveform(peaks))
    }

    /// Up to 256 bars of the loudest frame in each slice, scaled to 0–255.
    private static func waveform(_ peaks: [Float]) -> String {
      let bars = min(256, max(1, peaks.count))
      let loudest = max(peaks.max() ?? 1, 0.01)
      var bytes = [UInt8]()
      for bar in 0..<bars {
        let start = bar * peaks.count / bars
        let end = max(start + 1, (bar + 1) * peaks.count / bars)
        let peak = peaks[start..<min(end, peaks.count)].max() ?? 0
        bytes.append(UInt8(min(255, max(0, (peak / loudest) * 255))))
      }
      return Data(bytes).base64EncodedString()
    }
  }
}

/// Ogg encapsulation of Opus packets (RFC 7845): the OpusHead and OpusTags
/// pages, then audio pages of up to 50 packets (one second).
struct OggOpusWriter {
  private var output = Data()
  private var packets: [Data] = []
  private var lastGranule: Int64 = 0
  private var sequence: UInt32 = 0
  private let serial = UInt32.random(in: 1...UInt32.max)
  /// Samples the decoder drops at the start (libopus' usual look-ahead).
  private let preSkip: UInt16 = 312

  init() {
    var head = Data("OpusHead".utf8)
    head.append(1)  // version
    head.append(1)  // channels
    head.appendLittleEndian(preSkip)
    head.appendLittleEndian(UInt32(48_000))
    head.appendLittleEndian(UInt16(0))  // output gain
    head.append(0)  // mapping family
    writePage([head], granule: 0, flags: 0x02)

    var tags = Data("OpusTags".utf8)
    let vendor = Data("Aicord".utf8)
    tags.appendLittleEndian(UInt32(vendor.count))
    tags.append(vendor)
    tags.appendLittleEndian(UInt32(0))  // no comments
    writePage([tags], granule: 0, flags: 0)
  }

  mutating func append(_ packet: Data, granule: Int64) {
    packets.append(packet)
    lastGranule = granule
    if packets.count >= 50 {
      writePage(packets, granule: granule, flags: 0)
      packets = []
    }
  }

  /// The whole file, or nil when nothing was recorded.
  mutating func finish() -> Data? {
    guard lastGranule > 0 else { return nil }
    writePage(packets, granule: lastGranule, flags: 0x04)
    packets = []
    return output
  }

  private mutating func writePage(_ pagePackets: [Data], granule: Int64, flags: UInt8) {
    var lacing = [UInt8]()
    for packet in pagePackets {
      var size = packet.count
      while size >= 255 {
        lacing.append(255)
        size -= 255
      }
      lacing.append(UInt8(size))
    }
    var page = Data("OggS".utf8)
    page.append(0)  // version
    page.append(flags)
    page.appendLittleEndian(UInt64(bitPattern: granule))
    page.appendLittleEndian(serial)
    page.appendLittleEndian(sequence)
    page.appendLittleEndian(UInt32(0))  // checksum, filled below
    page.append(UInt8(lacing.count))
    page.append(contentsOf: lacing)
    for packet in pagePackets { page.append(packet) }
    let crc = Self.crc(page)
    page.replaceSubrange(22..<26, with: withUnsafeBytes(of: crc.littleEndian) { Data($0) })
    output.append(page)
    sequence += 1
  }

  private static let table: [UInt32] = (0..<256).map { index in
    var value = UInt32(index) << 24
    for _ in 0..<8 {
      value = value & 0x8000_0000 != 0 ? (value << 1) ^ 0x04C1_1DB7 : value << 1
    }
    return value
  }

  private static func crc(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0
    for byte in data {
      crc = (crc << 8) ^ table[Int(((crc >> 24) ^ UInt32(byte)) & 0xFF)]
    }
    return crc
  }
}

extension Data {
  fileprivate mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }
}
