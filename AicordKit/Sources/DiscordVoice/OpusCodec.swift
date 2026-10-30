//
//  OpusCodec.swift
//  AicordKit
//

import COpusShim
import Foundation

/// Discord voice audio: 48 kHz Opus in 20 ms frames.
public enum VoiceAudioFormat {
  public static let sampleRate = 48_000
  /// Samples per channel in one 20 ms frame.
  public static let frameSamples = 960
  public static let frameDuration: Duration = .milliseconds(20)
  /// Microphone audio is sent mono, like Serein; received audio is decoded
  /// to mono too and the app pans nothing.
  public static let channels = 1
  /// The longest frame libopus may hand back (120 ms).
  static let maxFrameSamples = 5760
  /// Discord's 3-byte Opus silence frame.
  public static let silenceFrame = Data([0xF8, 0xFF, 0xFE])
}

public enum OpusError: Error, Equatable {
  case code(Int32)
}

/// A mono VoIP Opus encoder.
public final class OpusEncoder: @unchecked Sendable {
  private let handle: OpaquePointer
  private var output = [UInt8](repeating: 0, count: 1275)

  public init(bitrate: Int32 = 64_000) throws(OpusError) {
    var error: Int32 = 0
    guard
      let handle = opus_encoder_create(
        Int32(VoiceAudioFormat.sampleRate),
        Int32(VoiceAudioFormat.channels),
        OPUS_APPLICATION_VOIP,
        &error
      ), error == OPUS_OK
    else { throw .code(error) }
    self.handle = handle
    _ = paicord_opus_set_bitrate(handle, bitrate)
    _ = paicord_opus_set_signal_voice(handle)
    // In-band FEC lets receivers rebuild a lost frame from the next one.
    _ = paicord_opus_set_inband_fec(handle, 1)
    _ = paicord_opus_set_packet_loss_perc(handle, 10)
  }

  deinit { opus_encoder_destroy(handle) }

  /// Encodes one 20 ms frame of mono samples in [-1, 1].
  public func encode(_ samples: UnsafeBufferPointer<Float>) throws(OpusError)
    -> Data
  {
    precondition(samples.count == VoiceAudioFormat.frameSamples)
    let count = output.withUnsafeMutableBufferPointer { out in
      opus_encode_float(
        handle,
        samples.baseAddress!,
        Int32(VoiceAudioFormat.frameSamples),
        out.baseAddress!,
        Int32(out.count)
      )
    }
    guard count > 0 else { throw .code(count) }
    return Data(output[..<Int(count)])
  }

  public func reset() { _ = paicord_opus_encoder_reset(handle) }
}

/// A mono Opus decoder with packet-loss concealment.
public final class OpusDecoder: @unchecked Sendable {
  private let handle: OpaquePointer
  private var lastFrameSamples = VoiceAudioFormat.frameSamples

  public init() throws(OpusError) {
    var error: Int32 = 0
    guard
      let handle = opus_decoder_create(
        Int32(VoiceAudioFormat.sampleRate),
        Int32(VoiceAudioFormat.channels),
        &error
      ), error == OPUS_OK
    else { throw .code(error) }
    self.handle = handle
  }

  deinit { opus_decoder_destroy(handle) }

  /// Decodes a packet into mono PCM. Returns the decoded samples.
  public func decode(_ packet: Data) throws(OpusError) -> [Float] {
    var pcm = [Float](repeating: 0, count: VoiceAudioFormat.maxFrameSamples)
    let samples = packet.withUnsafeBytes { raw in
      pcm.withUnsafeMutableBufferPointer { out in
        opus_decode_float(
          handle,
          raw.bindMemory(to: UInt8.self).baseAddress,
          Int32(raw.count),
          out.baseAddress!,
          Int32(VoiceAudioFormat.maxFrameSamples),
          0
        )
      }
    }
    guard samples >= 0 else { throw .code(samples) }
    lastFrameSamples = Int(samples)
    return Array(pcm[..<Int(samples)])
  }

  /// Packet-loss concealment for one missing packet of the previous duration.
  public func conceal() -> [Float] {
    let count = min(max(lastFrameSamples, 120), VoiceAudioFormat.maxFrameSamples)
    var pcm = [Float](repeating: 0, count: count)
    let samples = pcm.withUnsafeMutableBufferPointer { out in
      opus_decode_float(handle, nil, 0, out.baseAddress!, Int32(count), 0)
    }
    return samples > 0 ? Array(pcm[..<Int(samples)]) : pcm
  }

  public func reset() { _ = paicord_opus_decoder_reset(handle) }
}
