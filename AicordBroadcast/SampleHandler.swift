//
//  SampleHandler.swift
//  AicordBroadcast
//
//  The iOS Broadcast extension: ReplayKit hands it the screen once the
//  user starts a broadcast from the call panel. It turns each picture
//  upright, encodes it as H.264 and passes it to the app (`BroadcastLink`),
//  which is in the call and sends it on as a Go Live. Nothing here talks to
//  Discord, and the extension holds no account data.
//

import CoreMedia
import CoreVideo
import Foundation
import ReplayKit
import VideoToolbox

final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
  /// The longer side of what is sent; an iPhone's screen is larger.
  static let maxDimension = 1920

  private let lock = NSLock()
  private var socket: Int32 = -1
  private var encoder: VideoEncoder?
  private var rotation: VTPixelRotationSession?
  private var rotationAngle: CFString?
  private var pool: CVPixelBufferPool?
  private var poolSize: (Int, Int) = (0, 0)
  /// The last picture, sent again while the screen doesn't change so that
  /// somebody who starts watching gets one.
  private var last: CVPixelBuffer?
  private var lastSent = ContinuousClock.now
  private var timer: (any DispatchSourceTimer)?
  private let queue = DispatchQueue(label: "Aicord.Broadcast", qos: .userInitiated)

  private static func text(_ english: String, _ polish: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("pl") == true ? polish : english
  }

  private func finish(_ message: String) {
    finishBroadcastWithError(
      NSError(
        domain: "net.smigi.aicord.Broadcast", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]))
  }

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    guard let path = BroadcastLink.socketPath,
      let socket = BroadcastLink.connect(to: path)
    else {
      finish(
        Self.text(
          "Join a voice channel or a call in Aicord first, then share your screen from the call panel.",
          "Najpierw dołącz w Aicord do kanału głosowego albo rozmowy, potem udostępnij ekran z panelu rozmowy."
        ))
      return
    }
    lock.withLock { self.socket = socket }
    encoder = VideoEncoder(settings: .screen, maxDimension: Self.maxDimension) {
      [weak self] frame in
      self?.send(.frame(isKeyframe: frame.isKeyframe, timestamp: frame.timestamp, data: frame.data))
    }

    // What the app says: a viewer needs a key frame, or the stream is over.
    Thread.detachNewThread { [weak self] in
      var parser = BroadcastLink.Parser()
      while let data = BroadcastLink.read(from: socket) {
        for message in parser.append(data) {
          switch message {
          case .keyframe: self?.encoder?.requestKeyframe()
          case .stop: self?.ended()
          case .frame: break
          }
        }
      }
      self?.ended()
    }

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { [weak self] in
      guard let self, let last, ContinuousClock.now - lastSent >= .milliseconds(900)
      else { return }
      encode(last)
    }
    timer.resume()
    self.timer = timer
  }

  override func processSampleBuffer(
    _ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType
  ) {
    guard sampleBufferType == .video, let pixels = sampleBuffer.imageBuffer else { return }
    let orientation =
      (CMGetAttachment(
        sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil)
        as? NSNumber)?.uint32Value ?? 1
    nonisolated(unsafe) let upright = self.upright(pixels, orientation: orientation)
    queue.async { [self] in
      last = upright
      encode(upright)
    }
  }

  override func broadcastFinished() {
    close()
  }

  // MARK: Private

  private func encode(_ pixels: CVPixelBuffer) {
    lastSent = .now
    encoder?.encode(pixels, at: CMClockGetTime(CMClockGetHostTimeClock()))
  }

  private func send(_ message: BroadcastLink.Message) {
    let socket = lock.withLock { self.socket }
    guard socket >= 0 else { return }
    if !BroadcastLink.write(BroadcastLink.encode(message), to: socket) { ended() }
  }

  /// The app closed the stream (or itself).
  private func ended() {
    guard lock.withLock({ socket >= 0 }) else { return }
    close()
    finish(Self.text("Screen sharing ended.", "Udostępnianie ekranu zakończone."))
  }

  private func close() {
    let socket = lock.withLock {
      defer { self.socket = -1 }
      return self.socket
    }
    if socket >= 0 { Darwin.close(socket) }
    queue.async { [self] in
      timer?.cancel()
      timer = nil
      last = nil
    }
  }

  /// ReplayKit always delivers the screen as it is built, upright for
  /// portrait, and says how it is held. Landscape pictures are turned so
  /// viewers don't see them on their side.
  private func upright(_ pixels: CVPixelBuffer, orientation: UInt32) -> CVPixelBuffer {
    let angle: CFString
    switch CGImagePropertyOrientation(rawValue: orientation) {
    case .right: angle = kVTRotation_CW90
    case .left: angle = kVTRotation_CCW90
    case .down: angle = kVTRotation_180
    default: return pixels
    }
    let turned = angle != kVTRotation_180
    let width = turned ? CVPixelBufferGetHeight(pixels) : CVPixelBufferGetWidth(pixels)
    let height = turned ? CVPixelBufferGetWidth(pixels) : CVPixelBufferGetHeight(pixels)
    if rotation == nil {
      VTPixelRotationSessionCreate(nil, &rotation)
    }
    guard let rotation else { return pixels }
    if rotationAngle != angle {
      VTSessionSetProperty(rotation, key: kVTPixelRotationPropertyKey_Rotation, value: angle)
      rotationAngle = angle
    }
    if pool == nil || poolSize != (width, height) {
      let attributes: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: CVPixelBufferGetPixelFormatType(pixels),
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      ]
      pool = nil
      CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
      poolSize = (width, height)
    }
    var output: CVPixelBuffer?
    guard let pool,
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess,
      let output,
      VTPixelRotationSessionRotateImage(rotation, pixels, output) == noErr
    else { return pixels }
    return output
  }
}
