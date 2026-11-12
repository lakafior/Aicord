//
//  VideoFrame.swift
//  AicordKit
//
//  Received video: one decrypted H.264 frame, and the step that turns it
//  into a sample buffer a display layer can decode.
//

import CoreMedia
import DiscordModels
import Foundation

/// One received video frame, decrypted, as an H.264 Annex B byte stream.
public struct VideoFrame: Sendable {
  public var userID: UserSnowflake
  /// RTP timestamp, 90 kHz.
  public var timestamp: UInt32
  public var isKeyframe: Bool
  public var data: Data
}

/// Turns the frames of one video source into compressed sample buffers for
/// `AVSampleBufferDisplayLayer`, which decodes them itself. Keeps the
/// parameter sets of the last key frame.
public struct VideoSampleBuilder {
  private var sps: Data?
  private var pps: Data?
  private var format: CMVideoFormatDescription?

  public init() {}

  /// The picture size, once a key frame has been seen.
  public var dimensions: CMVideoDimensions? {
    format.map { CMVideoFormatDescriptionGetDimensions($0) }
  }

  /// `nil` until parameter sets have arrived, and for frames without
  /// picture data.
  public mutating func makeSampleBuffer(_ frame: VideoFrame) -> CMSampleBuffer? {
    makeSampleBuffer(annexB: frame.data, timestamp: frame.timestamp)
  }

  public mutating func makeSampleBuffer(annexB: Data, timestamp: UInt32)
    -> CMSampleBuffer?
  {
    // AVCC: every NAL unit behind its 4-byte big-endian length.
    var avcc = Data()
    var isSync = false
    for unit in Self.nalUnits(in: annexB) {
      guard let header = unit.first else { continue }
      switch header & 0x1F {
      case 7:
        if sps != unit {
          sps = unit
          format = nil
        }
      case 8:
        if pps != unit {
          pps = unit
          format = nil
        }
      case 1...5:
        if header & 0x1F == 5 { isSync = true }
        let length = UInt32(unit.count)
        avcc.append(contentsOf: [
          UInt8(length >> 24), UInt8((length >> 16) & 0xFF),
          UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
        ])
        avcc.append(unit)
      default:
        // Access unit delimiters, SEI and the rest are not needed to decode.
        continue
      }
    }
    if format == nil, let sps, let pps {
      format = Self.makeFormat(sps: sps, pps: pps)
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

  private static func makeFormat(sps: Data, pps: Data) -> CMVideoFormatDescription? {
    var format: CMVideoFormatDescription?
    let status = sps.withUnsafeBytes { spsBytes in
      pps.withUnsafeBytes { ppsBytes in
        let pointers = [
          spsBytes.bindMemory(to: UInt8.self).baseAddress!,
          ppsBytes.bindMemory(to: UInt8.self).baseAddress!,
        ]
        let sizes = [spsBytes.count, ppsBytes.count]
        return CMVideoFormatDescriptionCreateFromH264ParameterSets(
          allocator: kCFAllocatorDefault,
          parameterSetCount: 2,
          parameterSetPointers: pointers,
          parameterSetSizes: sizes,
          nalUnitHeaderLength: 4,
          formatDescriptionOut: &format
        )
      }
    }
    return status == noErr ? format : nil
  }
}
