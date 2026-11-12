//
//  VideoPanel.swift
//  Aicord
//
//  Other people's video above the chat of the voice channel we are in:
//  who has a camera or a Go Live on, and the one being watched. Video is
//  only received for what is on screen here.
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
  private struct VideoLayerView: NSViewRepresentable {
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
  private struct VideoLayerView: UIViewRepresentable {
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
  @State private var selected: VoiceConnectionStore.VideoSource?
  @State private var feed: VideoFeed?

  typealias Source = VoiceConnectionStore.VideoSource

  var voice: VoiceConnectionStore { gw.voice }
  var guild: GuildStore? { vm.guildStore }
  var isHere: Bool { voice.call?.channelID == vm.channelId }

  var states: [VoiceState] {
    let me = gw.user.currentUser?.id
    return (guild?.voiceStates.values.filter {
      $0.channel_id == vm.channelId && $0.user_id != me
    } ?? [])
    .sorted { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }
  }

  /// Go Lives first: they are what people gather around.
  var sources: [Source] {
    states.filter { $0.self_stream == true }.map { Source(userID: $0.user_id, kind: .stream) }
      + states.filter(\.self_video).map { Source(userID: $0.user_id, kind: .camera) }
  }

  var body: some View {
    if isHere, !sources.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        if let selected, let feed {
          picture(selected, feed)
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
        // The camera went off or the stream ended.
        if let selected, !sources.contains(selected) { select(nil) }
      }
      .onDisappear { select(nil) }
    }
  }

  func picture(_ source: Source, _ feed: VideoFeed) -> some View {
    ZStack {
      Color.black
      VideoLayerView(feed: feed)
      if !feed.hasPicture {
        status(source)
      }
    }
    .aspectRatio(feed.aspectRatio, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: 420)
    .clipShape(.rect(cornerRadius: 10))
    .overlay(alignment: .topTrailing) {
      Button {
        select(nil)
      } label: {
        Image(systemName: "xmark")
          .padding(6)
      }
      .buttonStyle(.plain)
      .glassEffect(.regular, in: .circle)
      .padding(6)
      .help(Text("Stop Watching"))
      .accessibilityLabel(Text("Stop Watching"))
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label(source))
  }

  @ViewBuilder
  func status(_ source: Source) -> some View {
    if source.kind == .stream, case .ended(let reason) = voice.streamPhase {
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
    let isOn = selected == source
    return Button {
      select(isOn ? nil : source)
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

  func select(_ source: Source?) {
    if let selected, selected != source { voice.stopWatching(selected) }
    selected = source
    feed = source.map { voice.watch($0) }
  }

  func label(_ source: Source) -> Text {
    switch source.kind {
    case .stream: Text("\(name(source.userID))’s stream")
    case .camera: Text("\(name(source.userID))’s camera")
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
    let member = state.member ?? guild?.member(state.user_id)
    return member?.nick ?? member?.user?.global_name ?? member?.user?.username
      ?? state.user_id.rawValue
  }

  func name(_ userID: UserSnowflake) -> String {
    guild?.voiceStates[userID].map(name) ?? userID.rawValue
  }
}
