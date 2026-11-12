//
//  VideoCapture.swift
//  Aicord
//
//  Where our own video comes from: the camera, and on the Mac a screen or
//  a window picked in the system's sharing picker. Both hand over pixel
//  buffers stamped with the host clock, ready for the encoder.
//

import AVFoundation
import CoreMedia
import SwiftUI
import os

#if os(macOS)
  import ScreenCaptureKit
#endif

/// Pictures as they are captured. Called on a capture queue.
typealias VideoCaptureOutput = @Sendable (CVPixelBuffer, CMTime) -> Void

/// CoreVideo buffers are safe to hand to another thread once captured.
private struct CapturedFrame: @unchecked Sendable {
  let pixels: CVPixelBuffer
}

private func hostTime() -> CMTime {
  CMClockGetTime(CMClockGetHostTimeClock())
}

/// The camera at 720p and 30 frames a second.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "Aicord.Camera", qos: .userInitiated)
  private let output = OSAllocatedUnfairLock<VideoCaptureOutput?>(initialState: nil)
  private var isConfigured = false

  /// Starts the camera; `false` when there is none to use.
  func start(_ handler: @escaping VideoCaptureOutput) async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async { [self] in
        guard configure() else {
          continuation.resume(returning: false)
          return
        }
        output.withLock { $0 = handler }
        if !session.isRunning { session.startRunning() }
        continuation.resume(returning: true)
      }
    }
  }

  func stop() {
    output.withLock { $0 = nil }
    queue.async { [self] in
      if session.isRunning { session.stopRunning() }
    }
  }

  private func configure() -> Bool {
    if isConfigured { return true }
    #if os(iOS)
      let device =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        ?? AVCaptureDevice.default(for: .video)
    #else
      let device = AVCaptureDevice.default(for: .video)
    #endif
    guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
      return false
    }
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
    guard session.canAddInput(input) else { return false }
    session.addInput(input)
    let video = AVCaptureVideoDataOutput()
    video.alwaysDiscardsLateVideoFrames = true
    video.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    video.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(video) else { return false }
    session.addOutput(video)
    #if os(iOS)
      // The phone is held upright; the sensor is not.
      if let connection = video.connection(with: .video) {
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
      }
    #endif
    isConfigured = true
    return true
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixels = sampleBuffer.imageBuffer,
      let handler = self.output.withLock({ $0 })
    else { return }
    handler(pixels, hostTime())
  }
}

/// What the camera sees, for the small picture of ourselves.
struct CameraPreview {
  let session: AVCaptureSession
}

#if os(macOS)
  extension CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
      let view = NSView()
      let layer = AVCaptureVideoPreviewLayer(session: session)
      layer.videoGravity = .resizeAspectFill
      view.layer = layer
      view.wantsLayer = true
      return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
  }

  /// A display, a window or an app, chosen in the system's picker, captured
  /// at up to 1080p and 30 frames a second. A picture that doesn't change
  /// is sent again every second, so somebody joining gets one.
  @MainActor
  final class ScreenCapture: NSObject, SCContentSharingPickerObserver {
    private var stream: SCStream?
    private let sink = Sink()
    private var onPicked: ((Bool) -> Void)?
    /// The capture ended by itself (the window closed, sharing was stopped
    /// from the menu bar).
    var onEnded: (() -> Void)?

    /// Shows the picker; `picked` says whether something was chosen and is
    /// now being captured.
    func pick(output: @escaping VideoCaptureOutput, picked: @escaping (Bool) -> Void) {
      sink.output.withLock { $0 = output }
      onPicked = picked
      let picker = SCContentSharingPicker.shared
      picker.add(self)
      picker.isActive = true
      picker.present()
    }

    func stop() {
      let stream = self.stream
      self.stream = nil
      sink.stop()
      SCContentSharingPicker.shared.remove(self)
      SCContentSharingPicker.shared.isActive = false
      Task { try? await stream?.stopCapture() }
    }

    nonisolated func contentSharingPicker(
      _ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
      for stream: SCStream?
    ) {
      // The picker hands the filter over for good.
      nonisolated(unsafe) let filter = filter
      Task { @MainActor in await self.start(filter) }
    }

    nonisolated func contentSharingPicker(
      _ picker: SCContentSharingPicker, didCancelFor stream: SCStream?
    ) {
      Task { @MainActor in self.answer(false) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
      Task { @MainActor in self.answer(false) }
    }

    private func answer(_ picked: Bool) {
      let onPicked = self.onPicked
      self.onPicked = nil
      onPicked?(picked)
    }

    private func start(_ filter: SCContentFilter) async {
      if let stream {
        // Picked something else while sharing.
        try? await stream.updateContentFilter(filter)
        return
      }
      let configuration = SCStreamConfiguration()
      let scale = CGFloat(filter.pointPixelScale)
      var width = filter.contentRect.width * scale
      var height = filter.contentRect.height * scale
      let fit = min(1, 1920 / max(width, 1), 1080 / max(height, 1))
      width *= fit
      height *= fit
      // Encoders want even sizes.
      configuration.width = max(2, Int(width) / 2 * 2)
      configuration.height = max(2, Int(height) / 2 * 2)
      configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
      configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
      configuration.showsCursor = true
      let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
      do {
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
      } catch {
        answer(false)
        return
      }
      self.stream = stream
      sink.onStopped = { [weak self] in
        Task { @MainActor in
          guard let self, self.stream != nil else { return }
          self.stream = nil
          self.onEnded?()
        }
      }
      sink.start()
      answer(true)
    }

    /// Takes the frames off the capture queue.
    private final class Sink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
      let queue = DispatchQueue(label: "Aicord.ScreenCapture", qos: .userInitiated)
      let output = OSAllocatedUnfairLock<VideoCaptureOutput?>(initialState: nil)
      var onStopped: (@Sendable () -> Void)?
      private var last: CapturedFrame?
      private var lastSent = ContinuousClock.now
      private var timer: (any DispatchSourceTimer)?

      func start() {
        queue.async { [self] in
          let timer = DispatchSource.makeTimerSource(queue: queue)
          timer.schedule(deadline: .now() + 1, repeating: 1)
          timer.setEventHandler { [weak self] in
            guard let self, let last, ContinuousClock.now - lastSent >= .milliseconds(900)
            else { return }
            deliver(last)
          }
          timer.resume()
          self.timer = timer
        }
      }

      func stop() {
        output.withLock { $0 = nil }
        queue.async { [self] in
          timer?.cancel()
          timer = nil
          last = nil
        }
      }

      private func deliver(_ frame: CapturedFrame) {
        lastSent = .now
        output.withLock { $0 }?(frame.pixels, hostTime())
      }

      func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
      ) {
        guard type == .screen, let pixels = sampleBuffer.imageBuffer else { return }
        // Idle and blank notifications come without a new picture.
        let attachments =
          CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
          as? [[SCStreamFrameInfo: Any]]
        if let raw = attachments?.first?[.status] as? Int,
          let status = SCFrameStatus(rawValue: raw), status != .complete
        {
          return
        }
        let frame = CapturedFrame(pixels: pixels)
        last = frame
        deliver(frame)
      }

      func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStopped?()
      }
    }
  }
#else
  extension CameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> PreviewView {
      let view = PreviewView()
      view.preview.session = session
      view.preview.videoGravity = .resizeAspectFill
      return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
      override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
      var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
  }
#endif
