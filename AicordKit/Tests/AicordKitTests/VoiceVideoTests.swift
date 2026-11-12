import CoreMedia
import CoreVideo
import DiscordModels
import Foundation
import VideoToolbox
import XCTest

import DiscordVoice

/// Received video: RTP packets back into H.264 frames, and frames into
/// sample buffers the system can decode.
class VoiceVideoTests: XCTestCase {
  static let startCode = Data([0, 0, 0, 1])

  /// RFC 6184 packetization as a WebRTC sender does it: small NAL units go
  /// out whole (or aggregated), large ones as FU-A fragments.
  func packetize(
    _ units: [Data],
    timestamp: UInt32,
    firstSequence: UInt16,
    mtu: Int = 100,
    aggregate: Bool = false,
    codec: VideoCodec = .h264
  ) -> [RTPPacket] {
    var payloads: [Data] = []
    var small: [Data] = []
    func flushSmall() {
      guard !small.isEmpty else { return }
      if small.count == 1 || !aggregate {
        payloads += small
      } else {
        var stap = codec == .h264 ? Data([24]) : Data([48 << 1, 1])
        for unit in small {
          stap.append(contentsOf: [UInt8(unit.count >> 8), UInt8(unit.count & 0xFF)])
          stap.append(unit)
        }
        payloads.append(stap)
      }
      small = []
    }
    for unit in units {
      if unit.count <= mtu {
        small.append(unit)
        continue
      }
      flushSmall()
      let header = unit[unit.startIndex]
      let headerSize = codec == .h264 ? 1 : 2
      let body = [UInt8](unit.dropFirst(headerSize))
      var offset = 0
      while offset < body.count {
        let end = min(offset + mtu - 3, body.count)
        var fu =
          codec == .h264
          ? Data([(header & 0xE0) | 28, header & 0x1F])
          : Data([(header & 0x81) | (49 << 1), unit[unit.startIndex + 1], (header >> 1) & 0x3F])
        let flags = fu.count - 1
        if offset == 0 { fu[flags] |= 0x80 }
        if end == body.count { fu[flags] |= 0x40 }
        fu.append(contentsOf: body[offset..<end])
        payloads.append(fu)
        offset = end
      }
    }
    flushSmall()
    return payloads.enumerated().map { index, payload in
      RTPPacket(
        payloadType: .dynamic(103),
        sequence: firstSequence &+ UInt16(index),
        timestamp: timestamp,
        ssrc: 7,
        payload: payload,
        marker: index == payloads.count - 1
      )
    }
  }

  func annexB(_ units: [Data]) -> Data {
    units.reduce(into: Data()) { $0 += Self.startCode + $1 }
  }

  func unit(type: UInt8, size: Int, fill: UInt8) -> Data {
    Data([0x60 | type]) + Data(repeating: fill, count: size - 1)
  }

  func testFramesAreRebuiltAcrossPacketKindsAndTheSequenceWrap() {
    let key = [
      unit(type: 7, size: 20, fill: 1), unit(type: 8, size: 6, fill: 2),
      unit(type: 5, size: 950, fill: 3),
    ]
    let delta = [unit(type: 1, size: 333, fill: 4)]
    for aggregate in [false, true] {
      var depacketizer = VideoDepacketizer()
      // A marker tells where the first whole frame starts.
      var frames = depacketizer.push(
        RTPPacket(
          payloadType: .dynamic(103), sequence: .max - 3, timestamp: 1, ssrc: 7,
          payload: unit(type: 1, size: 10, fill: 9), marker: true))
      XCTAssertTrue(frames.isEmpty)
      XCTAssertTrue(depacketizer.needsKeyframe)

      let first = packetize(key, timestamp: 3000, firstSequence: .max - 2, aggregate: aggregate)
      for packet in first { frames += depacketizer.push(packet) }
      let second = packetize(
        delta, timestamp: 6000, firstSequence: .max - 2 &+ UInt16(first.count))
      for packet in second { frames += depacketizer.push(packet) }

      XCTAssertEqual(
        frames,
        [
          .init(timestamp: 3000, isKeyframe: true, data: annexB(key)),
          .init(timestamp: 6000, isKeyframe: false, data: annexB(delta)),
        ])
      XCTAssertFalse(depacketizer.needsKeyframe)
    }
  }

  func testReorderedPacketsWaitAndLostOnesAskForAKeyframe() {
    let key = [unit(type: 7, size: 12, fill: 1), unit(type: 5, size: 500, fill: 2)]
    let delta = [unit(type: 1, size: 400, fill: 3)]
    var depacketizer = VideoDepacketizer()
    _ = depacketizer.push(
      RTPPacket(
        payloadType: .dynamic(103), sequence: 99, timestamp: 1, ssrc: 7,
        payload: unit(type: 1, size: 10, fill: 9), marker: true))

    // Out of order within the window: nothing is lost.
    var packets = packetize(key, timestamp: 3000, firstSequence: 100)
    packets.swapAt(1, 3)
    var frames: [VideoDepacketizer.Frame] = []
    for packet in packets { frames += depacketizer.push(packet) }
    XCTAssertEqual(frames.map(\.data), [annexB(key)])

    // A frame with a hole, then frames that depend on it.
    var sequence = 100 &+ UInt16(packets.count)
    frames = []
    var broken = packetize(delta, timestamp: 6000, firstSequence: sequence)
    sequence &+= UInt16(broken.count)
    broken.remove(at: 1)
    for packet in broken { frames += depacketizer.push(packet) }
    XCTAssertTrue(frames.isEmpty)
    XCTAssertFalse(depacketizer.needsKeyframe)
    for index in 0..<40 {
      let next = packetize(delta, timestamp: 9000 + UInt32(index) * 3000, firstSequence: sequence)
      sequence &+= UInt16(next.count)
      for packet in next { frames += depacketizer.push(packet) }
    }
    XCTAssertTrue(frames.isEmpty)
    XCTAssertTrue(depacketizer.needsKeyframe)

    // The next key frame starts the picture again.
    for packet in packetize(key, timestamp: 90_000, firstSequence: sequence) {
      frames += depacketizer.push(packet)
    }
    XCTAssertEqual(frames.map(\.isKeyframe), [true])
    XCTAssertFalse(depacketizer.needsKeyframe)
  }

  func testAMissingPacketIsAskedForAndItsRetransmissionCompletesTheFrame() {
    let key = [unit(type: 7, size: 12, fill: 1), unit(type: 5, size: 500, fill: 2)]
    var depacketizer = VideoDepacketizer()
    _ = depacketizer.push(
      RTPPacket(
        payloadType: .dynamic(103), sequence: 99, timestamp: 1, ssrc: 7,
        payload: unit(type: 1, size: 10, fill: 9), marker: true))
    let packets = packetize(key, timestamp: 3000, firstSequence: 100)
    XCTAssertGreaterThan(packets.count, 4)
    var frames: [VideoDepacketizer.Frame] = []
    for packet in packets where packet.sequence != 102 { frames += depacketizer.push(packet) }
    XCTAssertTrue(frames.isEmpty)

    let start = ContinuousClock.now
    XCTAssertEqual(depacketizer.missingSequences(now: start), [102])
    // Not again until some time has passed, and not for ever.
    XCTAssertEqual(depacketizer.missingSequences(now: start + .milliseconds(10)), [])
    XCTAssertEqual(depacketizer.missingSequences(now: start + .milliseconds(100)), [102])
    XCTAssertEqual(depacketizer.missingSequences(now: start + .milliseconds(200)), [102])
    XCTAssertEqual(depacketizer.missingSequences(now: start + .milliseconds(300)), [])

    frames += depacketizer.push(packets[2])
    XCTAssertEqual(frames.map(\.data), [annexB(key)])
    XCTAssertFalse(depacketizer.needsKeyframe)
    XCTAssertEqual(depacketizer.missingSequences(now: start + .seconds(1)), [])
  }

  /// What we send has to come back out of our own receiving side: the
  /// encoder's frames through the packetizer, the transport cipher with the
  /// header extension, the depacketizer and the decoder.
  func testOurOwnVideoIsReceivableAndRTCPRoundTrips() throws {
    let collected = EncodedFrames()
    let encoder = VideoEncoder(settings: .camera) { collected.append($0) }
    for index in 0..<3 {
      var pixels: CVPixelBuffer?
      CVPixelBufferCreate(
        nil, 320, 240, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels)
      encoder.encode(try XCTUnwrap(pixels), at: CMTime(value: CMTimeValue(index), timescale: 30))
    }
    var frames: [EncodedVideoFrame] = []
    for _ in 0..<100 where frames.count < 3 {
      Thread.sleep(forTimeInterval: 0.02)
      frames = collected.value
    }
    guard frames.count == 3 else { throw XCTSkip("No H.264 encoder here") }
    XCTAssertTrue(frames[0].isKeyframe)
    XCTAssertEqual(frames[1].timestamp, 3000)

    let cipher = try TransportCipher(mode: .aes256GCM, secretKey: [UInt8](repeating: 7, count: 32))
    var depacketizer = VideoDepacketizer()
    _ = depacketizer.push(
      RTPPacket(
        payloadType: .dynamic(103), sequence: 0, timestamp: 1, ssrc: 9,
        payload: Data([0x61, 0]), marker: true))
    var builder = VideoSampleBuilder()
    var sequence: UInt16 = 1
    var nonce: UInt32 = 0
    var received = 0
    for frame in frames {
      let payloads = VideoPacketizer.payloads(annexB: frame.data, maxSize: 300)
      XCTAssertTrue(payloads.allSatisfy { $0.count <= 300 })
      for (index, payload) in payloads.enumerated() {
        nonce += 1
        let datagram = try cipher.seal(
          RTPPacket(
            extension: true, payloadType: .dynamic(103), sequence: sequence,
            timestamp: frame.timestamp, ssrc: 9,
            payload: VoiceGatewayManager.videoExtension + payload,
            marker: index == payloads.count - 1),
          nonce: nonce)
        sequence &+= 1
        let packet = try cipher.open(datagram)
        XCTAssertEqual(packet.payload, payload)
        for rebuilt in depacketizer.push(packet) {
          XCTAssertEqual(rebuilt.data, frame.data)
          XCTAssertNotNil(
            builder.makeSampleBuffer(annexB: rebuilt.data, timestamp: rebuilt.timestamp))
          received += 1
        }
      }
    }
    XCTAssertEqual(received, 3)

    // A Picture Loss Indication as we send it, sealed and opened again.
    let pli = Data([0x81, 206, 0, 2, 0, 0, 0, 1, 0, 0, 0, 9])
    XCTAssertEqual(try cipher.openRTCP(cipher.sealRTCP(pli, nonce: 5)), pli)
  }

  final class EncodedFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [EncodedVideoFrame] = []
    var value: [EncodedVideoFrame] { lock.withLock { frames } }
    func append(_ frame: EncodedVideoFrame) { lock.withLock { frames.append(frame) } }
  }

  func testAnnexBSplitsAtShortAndLongStartCodes() {
    let stream = Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 0, 1, 0x65, 4, 5])
    XCTAssertEqual(
      VideoSampleBuilder.nalUnits(in: stream),
      [Data([0x67, 1, 2]), Data([0x68, 3]), Data([0x65, 4, 5])])
  }

  /// Frames from the system's own encoder, through packets and back, must
  /// come out as sample buffers the system's decoder accepts.
  func testEncodedVideoSurvivesTheRoundTripAndDecodes() throws {
    try roundTrip(.h264)
    try roundTrip(.h265)
  }

  func roundTrip(_ codec: VideoCodec) throws {
    let encoded = try Self.encodeFrames(count: 4, width: 320, height: 240, codec: codec)
    XCTAssertEqual(encoded.count, 4)

    var depacketizer = VideoDepacketizer(codec: codec)
    _ = depacketizer.push(
      RTPPacket(
        payloadType: .dynamic(103), sequence: 9, timestamp: 1, ssrc: 7,
        payload: Data([0x02, 1, 0]), marker: true))
    var builder = VideoSampleBuilder()
    var sequence: UInt16 = 10
    var samples: [CMSampleBuffer] = []
    for (index, units) in encoded.enumerated() {
      let packets = packetize(
        units, timestamp: UInt32(index) * 3000, firstSequence: sequence, mtu: 200,
        aggregate: true, codec: codec)
      sequence &+= UInt16(packets.count)
      for packet in packets {
        for frame in depacketizer.push(packet) {
          XCTAssertEqual(frame.data, annexB(units))
          let sample = try XCTUnwrap(
            builder.makeSampleBuffer(
              annexB: frame.data, codec: codec, timestamp: frame.timestamp))
          samples.append(sample)
        }
      }
    }
    XCTAssertEqual(samples.count, 4)
    XCTAssertEqual(builder.dimensions?.width, 320)
    XCTAssertEqual(builder.dimensions?.height, 240)

    let format = try XCTUnwrap(samples[0].formatDescription)
    var session: VTDecompressionSession?
    XCTAssertEqual(
      VTDecompressionSessionCreate(
        allocator: nil, formatDescription: format, decoderSpecification: nil,
        imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &session),
      noErr)
    let decoder = try XCTUnwrap(session)
    defer { VTDecompressionSessionInvalidate(decoder) }
    let decoded = Counter()
    for sample in samples {
      let status = VTDecompressionSessionDecodeFrame(
        decoder, sampleBuffer: sample, flags: [], infoFlagsOut: nil
      ) { status, _, image, _, _ in
        if status == noErr, image != nil { decoded.increment() }
      }
      XCTAssertEqual(status, noErr)
    }
    VTDecompressionSessionWaitForAsynchronousFrames(decoder)
    XCTAssertEqual(decoded.value, 4)
  }

  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
  }

  /// Encodes moving grey frames; returns each frame's NAL units, parameter
  /// sets first on key frames.
  static func encodeFrames(count: Int, width: Int32, height: Int32, codec: VideoCodec)
    throws -> [[Data]]
  {
    var session: VTCompressionSession?
    guard
      VTCompressionSessionCreate(
        allocator: nil, width: width, height: height,
        codecType: codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC,
        encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
        outputCallback: nil, refcon: nil, compressionSessionOut: &session) == noErr,
      let session
    else { throw XCTSkip("No \(codec) encoder here") }
    defer { VTCompressionSessionInvalidate(session) }
    VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
    VTSessionSetProperty(
      session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

    let output = Frames()
    for index in 0..<count {
      var pixels: CVPixelBuffer?
      CVPixelBufferCreate(
        nil, Int(width), Int(height), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels)
      guard let pixels else { throw XCTSkip("No pixel buffer") }
      CVPixelBufferLockBaseAddress(pixels, [])
      for plane in 0..<2 {
        if let base = CVPixelBufferGetBaseAddressOfPlane(pixels, plane) {
          memset(
            base, Int32(40 + index * 40),
            CVPixelBufferGetBytesPerRowOfPlane(pixels, plane)
              * CVPixelBufferGetHeightOfPlane(pixels, plane))
        }
      }
      CVPixelBufferUnlockBaseAddress(pixels, [])
      let status = VTCompressionSessionEncodeFrame(
        session, imageBuffer: pixels,
        presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: 30),
        duration: .invalid, frameProperties: nil, infoFlagsOut: nil
      ) { status, _, sample in
        guard status == noErr, let sample else { return }
        output.append(nalUnits(of: sample, codec: codec))
      }
      guard status == noErr else { throw XCTSkip("Encoding failed: \(status)") }
    }
    VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    return output.value
  }

  final class Frames: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [[Data]] = []
    var value: [[Data]] { lock.withLock { frames } }
    func append(_ frame: [Data]) { lock.withLock { frames.append(frame) } }
  }

  static func nalUnits(of sample: CMSampleBuffer, codec: VideoCodec) -> [Data] {
    var units: [Data] = []
    let attachments =
      CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
      as? [[CFString: Any]]
    let isKey = !((attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false)
    if isKey, let format = sample.formatDescription {
      for index in 0..<(codec == .h264 ? 2 : 3) {
        var pointer: UnsafePointer<UInt8>?
        var size = 0
        if codec == .h264 {
          CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        } else {
          CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
        }
        if let pointer { units.append(Data(bytes: pointer, count: size)) }
      }
    }
    guard let block = sample.dataBuffer else { return units }
    var length = 0
    var pointer: UnsafeMutablePointer<CChar>?
    CMBlockBufferGetDataPointer(
      block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
      dataPointerOut: &pointer)
    guard let pointer else { return units }
    let bytes = [UInt8](Data(bytes: pointer, count: length))
    var offset = 0
    while offset + 4 <= bytes.count {
      let size =
        Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
        | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
      offset += 4
      guard size > 0, offset + size <= bytes.count else { break }
      units.append(Data(bytes[offset..<(offset + size)]))
      offset += size
    }
    return units
  }
}
