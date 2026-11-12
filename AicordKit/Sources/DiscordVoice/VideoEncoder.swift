//
//  VideoEncoder.swift
//  AicordKit
//
//  Our own video on its way out: pixel buffers into H.264 frames with the
//  system encoder, and frames into RTP payloads (RFC 6184).
//

import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// One encoded frame of our own video: an Annex B byte stream with 4-byte
/// start codes, parameter sets first on key frames.
public struct EncodedVideoFrame: Sendable {
  public var data: Data
  public var isKeyframe: Bool
  /// RTP timestamp, 90 kHz.
  public var timestamp: UInt32
}

/// A real-time H.264 encoder. Frames come out in the order they went in.
/// The session is made again when the picture size changes.
public final class VideoEncoder: @unchecked Sendable {
  public struct Settings: Sendable, Equatable {
    public var bitrate: Int
    public var framerate: Int

    public init(bitrate: Int, framerate: Int) {
      self.bitrate = bitrate
      self.framerate = framerate
    }

    public static let camera = Settings(bitrate: 1_500_000, framerate: 30)
    public static let screen = Settings(bitrate: 3_500_000, framerate: 30)
  }

  /// Key frames come this often even when nobody asks for one.
  static let keyframeInterval = 4

  private let lock = NSLock()
  private var session: VTCompressionSession?
  private var size: (width: Int32, height: Int32) = (0, 0)
  private var wantsKeyframe = true
  private let settings: Settings
  private let output: @Sendable (EncodedVideoFrame) -> Void

  public init(settings: Settings, output: @escaping @Sendable (EncodedVideoFrame) -> Void) {
    self.settings = settings
    self.output = output
  }

  deinit {
    if let session { VTCompressionSessionInvalidate(session) }
  }

  /// The next frame will be a key frame (a viewer joined or lost packets).
  public func requestKeyframe() {
    lock.withLock { wantsKeyframe = true }
  }

  /// Encodes one picture taken at `time`.
  public func encode(_ pixels: CVPixelBuffer, at time: CMTime) {
    let width = Int32(CVPixelBufferGetWidth(pixels))
    let height = Int32(CVPixelBufferGetHeight(pixels))
    let (session, keyframe): (VTCompressionSession?, Bool) = lock.withLock {
      if self.session == nil || size.width != width || size.height != height {
        if let old = self.session { VTCompressionSessionInvalidate(old) }
        self.session = makeSession(width: width, height: height)
        size = (width, height)
        wantsKeyframe = true
      }
      defer { wantsKeyframe = false }
      return (self.session, wantsKeyframe)
    }
    guard let session else { return }
    let properties =
      keyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
    let output = self.output
    VTCompressionSessionEncodeFrame(
      session,
      imageBuffer: pixels,
      presentationTimeStamp: time,
      duration: .invalid,
      frameProperties: properties,
      infoFlagsOut: nil
    ) { status, _, sample in
      guard status == noErr, let sample, let frame = Self.frame(from: sample) else { return }
      output(frame)
    }
  }

  private func makeSession(width: Int32, height: Int32) -> VTCompressionSession? {
    var session: VTCompressionSession?
    guard
      VTCompressionSessionCreate(
        allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_H264,
        encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
        outputCallback: nil, refcon: nil, compressionSessionOut: &session) == noErr,
      let session
    else { return nil }
    func set(_ key: CFString, _ value: CFTypeRef) {
      VTSessionSetProperty(session, key: key, value: value)
    }
    set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
    // No B-frames: every frame is sent as soon as it is captured.
    set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
    set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel)
    set(kVTCompressionPropertyKey_AverageBitRate, settings.bitrate as CFNumber)
    set(kVTCompressionPropertyKey_ExpectedFrameRate, settings.framerate as CFNumber)
    set(
      kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
      Self.keyframeInterval as CFNumber)
    VTCompressionSessionPrepareToEncodeFrames(session)
    return session
  }

  /// AVCC out of the encoder into Annex B, parameter sets ahead of key frames.
  static func frame(from sample: CMSampleBuffer) -> EncodedVideoFrame? {
    guard let block = sample.dataBuffer else { return nil }
    let attachments =
      CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
      as? [[CFString: Any]]
    let isKeyframe = !((attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
    var data = Data()
    if isKeyframe, let format = sample.formatDescription {
      var count = 0
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
        parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
      for index in 0..<count {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
          format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
          parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        if let pointer {
          data += VideoDepacketizer.startCode
          data.append(pointer, count: size)
        }
      }
    }
    var length = 0
    var pointer: UnsafeMutablePointer<CChar>?
    guard
      CMBlockBufferGetDataPointer(
        block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
        dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer
    else { return nil }
    let bytes = UnsafeRawBufferPointer(start: pointer, count: length)
    var offset = 0
    while offset + 4 <= length {
      let size =
        Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
        | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
      offset += 4
      guard size > 0, offset + size <= length else { break }
      data += VideoDepacketizer.startCode
      data.append(contentsOf: bytes[offset..<(offset + size)])
      offset += size
    }
    guard !data.isEmpty else { return nil }
    let seconds = sample.presentationTimeStamp.seconds
    let ticks = seconds.isFinite ? UInt64(max(seconds, 0) * 90_000) : 0
    return EncodedVideoFrame(
      data: data, isKeyframe: isKeyframe, timestamp: UInt32(truncatingIfNeeded: ticks))
  }
}

/// Splits an H.264 frame into RTP payloads: a NAL unit that fits goes out
/// whole, a larger one as FU-A fragments.
package enum VideoPacketizer {
  /// Leaves room for the RTP header, the extension, the encryption tag and
  /// the nonce inside a 1200-byte datagram.
  package static let maxPayloadSize = 1100

  package static func payloads(annexB: Data, maxSize: Int = maxPayloadSize) -> [Data] {
    var payloads: [Data] = []
    for unit in VideoSampleBuilder.nalUnits(in: annexB) {
      guard let header = unit.first else { continue }
      if unit.count <= maxSize {
        payloads.append(unit)
        continue
      }
      let body = unit.dropFirst()
      var offset = body.startIndex
      while offset < body.endIndex {
        let end = min(offset + maxSize - 2, body.endIndex)
        var flags = header & 0x1F
        if offset == body.startIndex { flags |= 0x80 }
        if end == body.endIndex { flags |= 0x40 }
        payloads.append(Data([(header & 0xE0) | 28, flags]) + body[offset..<end])
        offset = end
      }
    }
    return payloads
  }
}
