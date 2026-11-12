//
//  VideoPanel.swift
//  Aicord
//
//  Other people's video above the chat of the voice channel or DM call we
//  are in: who has a camera or a Go Live on, and the ones being watched,
//  side by side or one of them full screen. Video is only received for
//  what is on screen here.
//

import AVFoundation
import AicordKit
import SwiftUI

/// Where the picture of one camera or Go Live arrives. The layer decodes
/// the compressed frames itself.
@MainActor
@Observable
final class VideoFeed {
  @ObservationIgnored let layer = AVSampleBufferDisplayLayer()
  @ObservationIgnored private var builder = VideoSampleBuilder()
  @ObservationIgnored private var waitsForKeyframe = false
  /// The decoder lost the picture and needs a key frame to go on.
  @ObservationIgnored var onNeedsKeyframe: (() -> Void)?

  private(set) var hasPicture = false
  private(set) var aspectRatio: CGFloat = 16 / 9

  init() {
    layer.videoGravity = .resizeAspect
  }

  func enqueue(_ frame: VideoFrame) {
    let renderer = layer.sampleBufferRenderer
    if renderer.status == .failed {
      // After the app was in the background, for one.
      renderer.flush()
      waitsForKeyframe = true
      onNeedsKeyframe?()
    }
    if waitsForKeyframe {
      guard frame.isKeyframe else { return }
      waitsForKeyframe = false
    }
    guard let sample = builder.makeSampleBuffer(frame) else { return }
    renderer.enqueue(sample)
    if !hasPicture { hasPicture = true }
    if let size = builder.dimensions, size.width > 0, size.height > 0 {
      let ratio = CGFloat(size.width) / CGFloat(size.height)
      if ratio != aspectRatio { aspectRatio = ratio }
    }
  }

  /// The video stopped; the last picture goes away.
  func reset() {
    layer.sampleBufferRenderer.flush(removingDisplayedImage: true)
    builder = VideoSampleBuilder()
    waitsForKeyframe = false
    hasPicture = false
  }
}

#if os(macOS)
  struct VideoLayerView: NSViewRepresentable {
    let feed: VideoFeed

    func makeNSView(context: Context) -> Host { Host() }

    func updateNSView(_ view: Host, context: Context) { view.show(feed.layer) }

    final class Host: NSView {
      private var shown: CALayer?

      override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
      }

      required init?(coder: NSCoder) { fatalError() }

      func show(_ video: CALayer) {
        guard shown !== video else { return }
        shown?.removeFromSuperlayer()
        shown = video
        layer?.addSublayer(video)
        needsLayout = true
      }

      override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shown?.frame = bounds
        CATransaction.commit()
      }
    }
  }
#else
  struct VideoLayerView: UIViewRepresentable {
    let feed: VideoFeed

    func makeUIView(context: Context) -> Host { Host() }

    func updateUIView(_ view: Host, context: Context) { view.show(feed.layer) }

    final class Host: UIView {
      private var shown: CALayer?

      func show(_ video: CALayer) {
        guard shown !== video else { return }
        shown?.removeFromSuperlayer()
        shown = video
        layer.addSublayer(video)
        setNeedsLayout()
      }

      override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shown?.frame = bounds
        CATransaction.commit()
      }
    }
  }
#endif

struct VideoPanel: View {
  var vm: ChannelStore
  @Environment(\.gateway) var gw
  /// What is being watched, in the order it was picked.
  @State private var watched: [Source] = []
  @State private var feeds: [Source: VideoFeed] = [:]
  /// The one shown full screen (in a window of its own on the Mac).
  @State private var expanded: Source?

  typealias Source = VoiceConnectionStore.VideoSource

  var voice: VoiceConnectionStore { gw.voice }
  var guild: GuildStore? { vm.guildStore }
  var isHere: Bool { voice.call?.channelID == vm.channelId }

  /// Everyone else in the call: from the server's voice states, or from
  /// the DM call's.
  var states: [VoiceState] {
    let me = gw.user.currentUser?.id
    let all =
      guild.map { Array($0.voiceStates.values) } ?? voice.callStates(in: vm.channelId)
    return all.filter { $0.channel_id == vm.channelId && $0.user_id != me }
      .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
  }

  /// Go Lives first: they are what people gather around.
  var sources: [Source] {
    states.filter { $0.self_stream == true }.map { Source(userID: $0.user_id, kind: .stream) }
      + states.filter(\.self_video).map { Source(userID: $0.user_id, kind: .camera) }
  }

  var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 6), count: min(watched.count, 2))
  }

  var body: some View {
    if isHere, !sources.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        if watched.count == 1, let source = watched.first, let feed = feeds[source] {
          picture(source, feed)
            .frame(maxHeight: 420)
        } else if !watched.isEmpty {
          LazyVGrid(columns: columns, spacing: 6) {
            ForEach(watched) { source in
              if let feed = feeds[source] {
                picture(source, feed)
                  .frame(maxHeight: 220)
              }
            }
          }
        }
        ScrollView(.horizontal) {
          HStack(spacing: 6) {
            ForEach(sources) { source in
              chip(source)
            }
          }
        }
        .scrollIndicators(.hidden)
      }
      .padding(10)
      .glassEffect(.regular, in: .rect(cornerRadius: 16))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .onChange(of: sources) { _, sources in
        // A camera went off or a stream ended.
        for source in watched where !sources.contains(source) { stop(source) }
      }
      .onDisappear {
        for source in watched { stop(source) }
      }
      #if os(iOS)
        .fullScreenCover(item: $expanded) { source in
          if let feed = feeds[source] {
            FullScreenVideo(feed: feed, title: label(source)) { expanded = nil }
          }
        }
      #endif
    }
  }

  func picture(_ source: Source, _ feed: VideoFeed) -> some View {
    ZStack {
      Color.black
      if expanded == source {
        // The picture is in its own window or full screen right now.
        Image(systemName: "arrow.up.left.and.arrow.down.right")
          .font(.title2)
          .foregroundStyle(.white.opacity(0.6))
      } else {
        VideoLayerView(feed: feed)
        if !feed.hasPicture {
          status(source)
        }
      }
    }
    .aspectRatio(feed.aspectRatio, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(.rect(cornerRadius: 10))
    .contentShape(.rect)
    .onTapGesture(count: 2) { expand(source) }
    .overlay(alignment: .topTrailing) {
      HStack(spacing: 4) {
        Button {
          expand(source)
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .padding(6)
        }
        .glassEffect(.regular, in: .circle)
        .help(Text("Full Screen"))
        .accessibilityLabel(Text("Full Screen"))
        Button {
          stop(source)
        } label: {
          Image(systemName: "xmark")
            .padding(6)
        }
        .glassEffect(.regular, in: .circle)
        .help(Text("Stop Watching"))
        .accessibilityLabel(Text("Stop Watching"))
      }
      .buttonStyle(.plain)
      .padding(6)
    }
    .overlay(alignment: .bottomLeading) {
      if watched.count > 1 {
        Text(name(source.userID))
          .font(.caption)
          .lineLimit(1)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.black.opacity(0.5), in: .capsule)
          .foregroundStyle(.white)
          .padding(6)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label(source))
  }

  @ViewBuilder
  func status(_ source: Source) -> some View {
    if source.kind == .stream, case .ended(let reason) = voice.streamPhases[source.userID] {
      Label(endedText(reason), systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .foregroundStyle(.white)
        .padding()
    } else {
      VStack(spacing: 8) {
        ProgressView()
          .tint(.white)
        Text("Waiting for video…")
          .font(.caption)
          .foregroundStyle(.white.opacity(0.8))
      }
    }
  }

  func chip(_ source: Source) -> some View {
    let isOn = watched.contains(source)
    return Button {
      if isOn { stop(source) } else { start(source) }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: source.kind == .stream ? "display" : "video.fill")
          .imageScale(.small)
        Text(name(source.userID))
          .lineLimit(1)
        if source.kind == .stream {
          Text("Live")
            .font(.caption2.bold())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.red, in: .capsule)
            .foregroundStyle(.white)
        }
      }
      .font(.callout)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(isOn ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: .capsule)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label(source))
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }

  func start(_ source: Source) {
    guard !watched.contains(source) else { return }
    feeds[source] = voice.watch(source)
    watched.append(source)
  }

  func stop(_ source: Source) {
    if expanded == source { collapse() }
    watched.removeAll { $0 == source }
    feeds[source] = nil
    voice.stopWatching(source)
  }

  func expand(_ source: Source) {
    guard let feed = feeds[source] else { return }
    expanded = source
    #if os(macOS)
      VideoWindow.shared.show(feed: feed, title: String(localized: label(source))) {
        expanded = nil
      }
    #else
      _ = feed
    #endif
  }

  func collapse() {
    #if os(macOS)
      VideoWindow.shared.close()
    #endif
    expanded = nil
  }

  func label(_ source: Source) -> LocalizedStringResource {
    switch source.kind {
    case .stream: "\(name(source.userID))’s stream"
    case .camera: "\(name(source.userID))’s camera"
    }
  }

  func endedText(_ reason: String) -> LocalizedStringKey {
    switch reason {
    case "stream_full": "This stream is full."
    case "unauthorized": "You can't watch this stream."
    case "connection_lost": "The connection to the stream was lost."
    default: "The stream ended."
    }
  }

  func name(_ state: VoiceState) -> String {
    name(state.user_id)
  }

  func name(_ userID: UserSnowflake) -> String {
    if let guild {
      let member = guild.voiceStates[userID]?.member ?? guild.member(userID)
      return member?.nick ?? member?.user?.global_name ?? member?.user?.username
        ?? userID.rawValue
    }
    let user = vm.channel?.recipients?.first { $0.id == userID }
    return user?.global_name ?? user?.username ?? userID.rawValue
  }
}

#if os(iOS)
  /// One picture over the whole screen; a tap brings up the way back.
  private struct FullScreenVideo: View {
    let feed: VideoFeed
    let title: LocalizedStringResource
    let close: () -> Void

    var body: some View {
      ZStack(alignment: .topTrailing) {
        Color.black.ignoresSafeArea()
        VideoLayerView(feed: feed)
          .ignoresSafeArea()
          .accessibilityLabel(Text(title))
        Button(action: close) {
          Image(systemName: "xmark")
            .padding(10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .padding()
        .accessibilityLabel(Text("Close"))
      }
      .statusBarHidden()
    }
  }
#else
  /// One picture in a window of its own, opened full screen; closing it (or
  /// leaving full screen and closing) puts the picture back in the chat.
  @MainActor
  final class VideoWindow: NSObject, NSWindowDelegate {
    static let shared = VideoWindow()

    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func show(feed: VideoFeed, title: String, onClose: @escaping () -> Void) {
      close()
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 960, height: 540),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
      )
      window.title = title
      window.isReleasedWhenClosed = false
      window.backgroundColor = .black
      window.collectionBehavior = [.fullScreenPrimary]
      window.contentView = NSHostingView(rootView: VideoLayerView(feed: feed))
      window.delegate = self
      window.center()
      self.window = window
      self.onClose = onClose
      window.makeKeyAndOrderFront(nil)
      window.toggleFullScreen(nil)
    }

    func close() {
      window?.close()
    }

    func windowWillClose(_ notification: Notification) {
      let onClose = self.onClose
      self.onClose = nil
      window = nil
      onClose?()
    }
  }
#endif
