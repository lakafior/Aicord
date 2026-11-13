//
//  VideoFrame.swift
//  AicordKit
//
//  Received video: one decrypted H.264 or H.265 frame, and the step that
//  turns it into a sample buffer a display layer can decode.
//

import CoreMedia
import DiscordModels
import Foundation

/// One received video frame, decrypted, as an Annex B byte stream.
public struct VideoFrame: Sendable {
  public var userID: UserSnowflake
  public var codec: VideoCodec
  /// RTP timestamp, 90 kHz.
  public var timestamp: UInt32
  public var isKeyframe: Bool
  public var data: Data
}

/// Turns the frames of one video source into compressed sample buffers for
/// `AVSampleBufferDisplayLayer`, which decodes them itself. Keeps the
/// parameter sets of the last key frame.
public struct VideoSampleBuilder {
  private var vps: Data?
  private var sps: Data?
  private var pps: Data?
  private var codec = VideoCodec.h264
  private var format: CMVideoFormatDescription?

  public init() {}

  /// The picture size, once a key frame has been seen.
  public var dimensions: CMVideoDimensions? {
    format.map { CMVideoFormatDescriptionGetDimensions($0) }
  }

  /// `nil` until parameter sets have arrived, and for frames without
  /// picture data.
  public mutating func makeSampleBuffer(_ frame: VideoFrame) -> CMSampleBuffer? {
    makeSampleBuffer(annexB: frame.data, codec: frame.codec, timestamp: frame.timestamp)
  }

  public mutating func makeSampleBuffer(
    annexB: Data, codec: VideoCodec = .h264, timestamp: UInt32
  ) -> CMSampleBuffer? {
    if codec != self.codec {
      // The call moved to another codec.
      self.codec = codec
      (vps, sps, pps, format) = (nil, nil, nil, nil)
    }
    // AVCC: every NAL unit behind its 4-byte big-endian length.
    var avcc = Data()
    var isSync = false
    for unit in Self.nalUnits(in: annexB) {
      guard let header = unit.first else { continue }
      /// Parameter sets are kept for the format; a changed one resets it.
      func keep(_ set: inout Data?) {
        if set != unit {
          set = unit
          format = nil
        }
      }
      let isPicture: Bool
      switch codec {
      case .h264:
        switch header & 0x1F {
        case 7: keep(&sps)
        case 8: keep(&pps)
        default: break
        }
        isPicture = (1...5).contains(header & 0x1F)
        if header & 0x1F == 5 { isSync = true }
      case .h265:
        let type = (header >> 1) & 0x3F
        switch type {
        case 32: keep(&vps)
        case 33: keep(&sps)
        case 34: keep(&pps)
        default: break
        }
        isPicture = type < 32
        if (16...21).contains(type) { isSync = true }
      }
      // Access unit delimiters, SEI and the rest are not needed to decode.
      guard isPicture else { continue }
      let length = UInt32(unit.count)
      avcc.append(contentsOf: [
        UInt8(length >> 24), UInt8((length >> 16) & 0xFF),
        UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
      ])
      avcc.append(unit)
    }
    if format == nil, let sps, let pps {
      switch codec {
      case .h264: format = Self.makeFormat(codec, [sps, pps])
      case .h265: format = vps.flatMap { Self.makeFormat(codec, [$0, sps, pps]) }
      }
    }
    guard let format, !avcc.isEmpty else { return nil }

    var block: CMBlockBuffer?
    guard
      CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: avcc.count,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: avcc.count,
        flags: kCMBlockBufferAssureMemoryNowFlag,
        blockBufferOut: &block
      ) == kCMBlockBufferNoErr, let block
    else { return nil }
    let copied = avcc.withUnsafeBytes { bytes in
      CMBlockBufferReplaceDataBytes(
        with: bytes.baseAddress!,
        blockBuffer: block,
        offsetIntoDestination: 0,
        dataLength: bytes.count
      )
    }
    guard copied == kCMBlockBufferNoErr else { return nil }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMTime(value: CMTimeValue(timestamp), timescale: 90_000),
      decodeTimeStamp: .invalid
    )
    var size = avcc.count
    var sample: CMSampleBuffer?
    guard
      CMSampleBufferCreateReady(
        allocator: kCFAllocatorDefault,
        dataBuffer: block,
        formatDescription: format,
        sampleCount: 1,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 1,
        sampleSizeArray: &size,
        sampleBufferOut: &sample
      ) == noErr, let sample
    else { return nil }

    // Live video: show each frame as soon as it is decoded.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(
      sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0
    {
      let dictionary = unsafeBitCast(
        CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        dictionary,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
      if !isSync {
        CFDictionarySetValue(
          dictionary,
          Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
          Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
      }
    }
    return sample
  }

  /// Splits an Annex B stream at its 3- or 4-byte start codes.
  package static func nalUnits(in annexB: Data) -> [Data] {
    let bytes = [UInt8](annexB)
    var units: [Data] = []
    var start: Int?
    var i = 0
    while i + 2 < bytes.count {
      if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
        if let start {
          // A 4-byte start code leaves its first zero behind the unit.
          var end = i
          if end > start, bytes[end - 1] == 0 { end -= 1 }
          if end > start { units.append(Data(bytes[start..<end])) }
        }
        start = i + 3
        i += 3
      } else {
        i += 1
      }
    }
    if let start, start < bytes.count {
      units.append(Data(bytes[start...]))
    }
    return units
  }

  private static func makeFormat(_ codec: VideoCodec, _ sets: [Data]) -> CMVideoFormatDescription? {
    // The pointers have to stay valid for the call: copy into one buffer.
    let joined = sets.reduce(into: Data()) { $0 += $1 }
    var format: CMVideoFormatDescription?
    let status = joined.withUnsafeBytes { bytes -> OSStatus in
      let base = bytes.bindMemory(to: UInt8.self).baseAddress!
      var offset = 0
      let pointers = sets.map { set -> UnsafePointer<UInt8> in
        defer { offset += set.count }
        return base + offset
      }
      let sizes = sets.map(\.count)
      switch codec {
      case .h264:
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: kCFAllocatorDefault,
          parameterSetCount: sets.count,
          parameterSetPointers: pointers,
          parameterSetSizes: sizes,
          nalUnitHeaderLength: 4,
          formatDescriptionOut: &format
        )
      case .h265:
        return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
          allocator: kCFAllocatorDefault,
          parameterSetCount: sets.count,
          parameterSetPointers: pointers,
          parameterSetSizes: sizes,
          nalUnitHeaderLength: 4,
          extensions: nil,
          formatDescriptionOut: &format
        )
      }
    }
    return status == noErr ? format : nil
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
