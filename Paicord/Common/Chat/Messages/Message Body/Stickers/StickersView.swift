//
//  StickersView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 11/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension MessageCell {
  struct StickersView: View {
    var stickers: [StickerItem]
    var body: some View {
      VStack {
        ForEach(stickers) { sticker in
          StickerView(sticker: sticker)
        }
      }
    }
  }

  /// Follows Discord's sticker animation setting and Reduce Motion.
  private struct StickerView: View {
    var sticker: StickerItem
    @Environment(\.gateway) var gw
    @Environment(\.reducesMotion) var reducesMotion
    @State private var isInteracting = false

    private var animates: Bool {
      guard !reducesMotion else { return false }
      switch gw.settings.stickerAnimation {
      case .always: return true
      case .onInteraction: return isInteracting
      case .never: return false
      }
    }

    var body: some View {
      let url = URL(
        string: CDNEndpoint.sticker(
          stickerId: sticker.id,
          format: sticker.format_type
        ).url + "?size=320"
      )
      Group {
        if case .lottie = sticker.format_type, let url {
          NativeLottieStickerView(url: url, name: sticker.name, animates: animates)
        } else {
          NukeImage(animation: .enabled(animates)) { _ in url }
            .resizable()
            .scaledToFit()
        }
      }
      .frame(maxWidth: 160, maxHeight: 160)
      .onHover { isInteracting = $0 }
      #if os(iOS)
        .onTapGesture {
          if gw.settings.stickerAnimation == .onInteraction { isInteracting.toggle() }
        }
      #endif
    }
  }
}

// MARK: - Lightweight Native Lottie Sticker Renderer (Serein / rasterlottie style)

private actor LottieStickerCache {
  static let shared = LottieStickerCache()
  private var cache: [URL: LottieDocument] = [:]

  func load(url: URL) async -> LottieDocument? {
    if let cached = cache[url] {
      return cached
    }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      guard
        let http = response as? HTTPURLResponse,
        (200..<300).contains(http.statusCode),
        data.count <= 2 * 1024 * 1024
      else { return nil }
      let doc = try JSONDecoder().decode(LottieDocument.self, from: data)
      guard doc.w > 0, doc.h > 0, doc.w <= 1024, doc.h <= 1024 else {
        return nil
      }
      cache[url] = doc
      return doc
    } catch {
      return nil
    }
  }
}

private struct NativeLottieStickerView: View {
  let url: URL
  let name: String
  var animates: Bool = true
  @State private var document: LottieDocument?
  @State private var failed = false

  var body: some View {
    Group {
      if let document {
        if !animates {
          LottieCanvasView(document: document, frame: document.ip)
        } else {
          TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let frame = document.frame(at: timeline.date.timeIntervalSinceReferenceDate)
            LottieCanvasView(document: document, frame: frame)
          }
        }
      } else if failed {
        RoundedRectangle(cornerRadius: 12)
          .fill(.quaternary)
          .overlay {
            VStack(spacing: 4) {
              Image(systemName: "sparkles")
                .font(.title2)
              Text(name)
                .font(.caption2)
                .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(8)
          }
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .task(id: url) {
      if let doc = await LottieStickerCache.shared.load(url: url) {
        self.document = doc
      } else {
        self.failed = true
      }
    }
  }
}

private struct LottieCanvasView: View {
  let document: LottieDocument
  let frame: Double

  var body: some View {
    Canvas { context, size in
      let scaleX = size.width / CGFloat(document.w)
      let scaleY = size.height / CGFloat(document.h)
      let scale = min(scaleX, scaleY)
      var rootContext = context
      rootContext.scaleBy(x: scale, y: scale)
      document.render(
        layers: document.layers,
        frame: frame,
        in: &rootContext,
        parentOpacity: 1.0
      )
    }
  }
}

// MARK: - Minimal Lottie JSON Models & Evaluator

private struct LottieDocument: Decodable, Sendable {
  let w: Double
  let h: Double
  let ip: Double
  let op: Double
  let fr: Double
  let layers: [Layer]
  let assets: [Asset]?

  enum CodingKeys: String, CodingKey {
    case w, h, ip, op, fr, layers, assets
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    w = (try? c.decode(Double.self, forKey: .w)) ?? 320
    h = (try? c.decode(Double.self, forKey: .h)) ?? 320
    ip = (try? c.decode(Double.self, forKey: .ip)) ?? 0
    op = (try? c.decode(Double.self, forKey: .op)) ?? 60
    fr = max((try? c.decode(Double.self, forKey: .fr)) ?? 30, 1)
    layers = (try? c.decode([Layer].self, forKey: .layers)) ?? []
    assets = try? c.decode([Asset].self, forKey: .assets)
  }

  func frame(at time: TimeInterval) -> Double {
    let totalFrames = max(op - ip, 1)
    let duration = totalFrames / fr
    let progress = (time.truncatingRemainder(dividingBy: duration)) / duration
    return ip + (progress >= 0 ? progress : progress + 1.0) * totalFrames
  }

  func render(
    layers: [Layer],
    frame: Double,
    in context: inout GraphicsContext,
    parentOpacity: Double
  ) {
    var layerMap: [Int: Layer] = [:]
    for layer in layers {
      if let ind = layer.ind {
        layerMap[ind] = layer
      }
    }

    for layer in layers.reversed() {
      guard layer.hd != true else { continue }
      let ip = layer.ip ?? self.ip
      let op = layer.op ?? self.op
      guard frame >= ip && frame <= op else { continue }

      let st = layer.st ?? 0
      let sr = (layer.sr ?? 1) != 0 ? (layer.sr ?? 1) : 1
      let localFrame = (frame - st) / sr

      var layerCtx = context
      let transform = combinedTransform(
        for: layer,
        at: frame,
        layerMap: layerMap
      )
      layerCtx.concatenate(transform)

      let layerOpacity =
        parentOpacity * ((layer.ks?.o?.value(at: frame).first ?? 100.0) / 100.0)
      guard layerOpacity > 0.001 else { continue }

      if layer.ty == 0, let refId = layer.refId,
        let asset = assets?.first(where: { $0.id == refId }),
        let sublayers = asset.layers
      {
        render(
          layers: sublayers,
          frame: localFrame,
          in: &layerCtx,
          parentOpacity: layerOpacity
        )
      } else if layer.ty == 4, let shapes = layer.shapes {
        renderShapeItems(
          shapes,
          frame: frame,
          in: &layerCtx,
          opacity: layerOpacity
        )
      }
    }
  }

  private func combinedTransform(
    for layer: Layer,
    at frame: Double,
    layerMap: [Int: Layer],
    depth: Int = 0
  ) -> CGAffineTransform {
    let own = layer.ks?.affineTransform(at: frame) ?? .identity
    guard depth < 16, let parentIdx = layer.parent,
      let parent = layerMap[parentIdx]
    else {
      return own
    }
    let st = parent.st ?? 0
    let sr = (parent.sr ?? 1) != 0 ? (parent.sr ?? 1) : 1
    let parentFrame = (frame - st) / sr
    return own.concatenating(
      combinedTransform(
        for: parent,
        at: parentFrame,
        layerMap: layerMap,
        depth: depth + 1
      )
    )
  }

  private func renderShapeItems(
    _ items: [ShapeItem],
    frame: Double,
    in context: inout GraphicsContext,
    opacity: Double
  ) {
    var groupTransform: Transform?
    for item in items where item.ty == "tr" {
      groupTransform = item.tr
    }

    var ctx = context
    var groupOpacity = opacity
    if let tr = groupTransform {
      ctx.concatenate(tr.affineTransform(at: frame))
      let trOpacity = (tr.o?.value(at: frame).first ?? 100.0) / 100.0
      groupOpacity *= trOpacity
    }
    guard groupOpacity > 0.001 else { return }

    var currentPath = Path()
    for item in items {
      guard item.hd != true else { continue }
      switch item.ty {
      case "gr":
        if let subItems = item.it {
          renderShapeItems(subItems, frame: frame, in: &ctx, opacity: groupOpacity)
        }
      case "sh":
        if let bezier = item.ks?.shapeValue(at: frame) {
          currentPath.addPath(bezier.toPath())
        }
      case "rc":
        let pos = item.p?.value(at: frame) ?? [0, 0]
        let sz = item.s?.value(at: frame) ?? [0, 0]
        let r = item.r?.value(at: frame).first ?? 0
        if pos.count >= 2 && sz.count >= 2 {
          let rect = CGRect(
            x: pos[0] - sz[0] / 2,
            y: pos[1] - sz[1] / 2,
            width: sz[0],
            height: sz[1]
          )
          currentPath.addRoundedRect(
            in: rect,
            cornerSize: CGSize(width: r, height: r)
          )
        }
      case "el":
        let pos = item.p?.value(at: frame) ?? [0, 0]
        let sz = item.s?.value(at: frame) ?? [0, 0]
        if pos.count >= 2 && sz.count >= 2 {
          let rect = CGRect(
            x: pos[0] - sz[0] / 2,
            y: pos[1] - sz[1] / 2,
            width: sz[0],
            height: sz[1]
          )
          currentPath.addEllipse(in: rect)
        }
      case "fl":
        let c = item.c?.value(at: frame) ?? [1, 1, 1]
        let fillOpacity =
          groupOpacity * ((item.o?.value(at: frame).first ?? 100.0) / 100.0)
        if c.count >= 3 && !currentPath.isEmpty {
          let color = Color(
            red: c[0],
            green: c[1],
            blue: c[2],
            opacity: fillOpacity
          )
          ctx.fill(currentPath, with: .color(color))
        }
      case "st":
        let c = item.c?.value(at: frame) ?? [1, 1, 1]
        let strokeOpacity =
          groupOpacity * ((item.o?.value(at: frame).first ?? 100.0) / 100.0)
        let width = item.w?.value(at: frame).first ?? 1.0
        if c.count >= 3 && width > 0 && !currentPath.isEmpty {
          let color = Color(
            red: c[0],
            green: c[1],
            blue: c[2],
            opacity: strokeOpacity
          )
          ctx.stroke(
            currentPath,
            with: .color(color),
            style: StrokeStyle(
              lineWidth: width,
              lineCap: .round,
              lineJoin: .round
            )
          )
        }
      default:
        break
      }
    }
  }
}

private struct Asset: Decodable, Sendable {
  let id: String
  let layers: [Layer]?
}

private struct Layer: Decodable, Sendable {
  let ty: Int?
  let ind: Int?
  let parent: Int?
  let refId: String?
  let ip: Double?
  let op: Double?
  let st: Double?
  let sr: Double?
  let hd: Bool?
  let ks: Transform?
  let shapes: [ShapeItem]?
}

private struct Transform: Decodable, Sendable {
  let a: AnimatedVector?
  let p: AnimatedVector?
  let s: AnimatedVector?
  let r: AnimatedVector?
  let o: AnimatedVector?

  func affineTransform(at frame: Double) -> CGAffineTransform {
    let anchor = a?.value(at: frame) ?? [0, 0]
    let pos = p?.value(at: frame) ?? [0, 0]
    let scale = s?.value(at: frame) ?? [100, 100]
    let rot = (r?.value(at: frame).first ?? 0) * .pi / 180.0

    let ax = anchor.count >= 1 ? anchor[0] : 0
    let ay = anchor.count >= 2 ? anchor[1] : 0
    let px = pos.count >= 1 ? pos[0] : 0
    let py = pos.count >= 2 ? pos[1] : 0
    let sx = (scale.count >= 1 ? scale[0] : 100) / 100.0
    let sy = (scale.count >= 2 ? scale[1] : sx * 100) / 100.0

    var t = CGAffineTransform.identity
    t = t.translatedBy(x: px, y: py)
    t = t.rotated(by: rot)
    t = t.scaledBy(x: sx, y: sy)
    t = t.translatedBy(x: -ax, y: -ay)
    return t
  }
}

private struct ShapeItem: Decodable, Sendable {
  let ty: String
  let hd: Bool?
  let it: [ShapeItem]?
  let ks: AnimatedShape?
  let p: AnimatedVector?
  let s: AnimatedVector?
  let r: AnimatedVector?
  let c: AnimatedVector?
  let o: AnimatedVector?
  let w: AnimatedVector?
  let tr: Transform?

  enum CodingKeys: String, CodingKey {
    case ty, hd, it, ks, p, s, r, c, o, w, a
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ty = (try? container.decode(String.self, forKey: .ty)) ?? ""
    hd = try? container.decode(Bool.self, forKey: .hd)
    it = try? container.decode([ShapeItem].self, forKey: .it)
    ks = try? container.decode(AnimatedShape.self, forKey: .ks)
    p = try? container.decode(AnimatedVector.self, forKey: .p)
    s = try? container.decode(AnimatedVector.self, forKey: .s)
    r = try? container.decode(AnimatedVector.self, forKey: .r)
    c = try? container.decode(AnimatedVector.self, forKey: .c)
    o = try? container.decode(AnimatedVector.self, forKey: .o)
    w = try? container.decode(AnimatedVector.self, forKey: .w)
    if ty == "tr" {
      tr = try? Transform(from: decoder)
    } else {
      tr = nil
    }
  }
}

private struct AnimatedVector: Decodable, Sendable {
  struct Keyframe: Decodable, Sendable {
    let t: Double?
    let s: [Double]?
    let e: [Double]?

    enum CodingKeys: String, CodingKey { case t, s, e }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      t = try? c.decode(Double.self, forKey: .t)
      if let arr = try? c.decode([Double].self, forKey: .s) {
        s = arr
      } else if let val = try? c.decode(Double.self, forKey: .s) {
        s = [val]
      } else {
        s = nil
      }
      if let arr = try? c.decode([Double].self, forKey: .e) {
        e = arr
      } else if let val = try? c.decode(Double.self, forKey: .e) {
        e = [val]
      } else {
        e = nil
      }
    }
  }

  let staticValue: [Double]
  let keyframes: [Keyframe]

  enum CodingKeys: String, CodingKey { case a, k }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let val = try? c.decode(Double.self, forKey: .k) {
      staticValue = [val]
      keyframes = []
    } else if let arr = try? c.decode([Double].self, forKey: .k) {
      staticValue = arr
      keyframes = []
    } else if let kfs = try? c.decode([Keyframe].self, forKey: .k) {
      staticValue = []
      keyframes = kfs
    } else {
      staticValue = []
      keyframes = []
    }
  }

  func value(at frame: Double) -> [Double] {
    guard !keyframes.isEmpty else { return staticValue }
    guard let first = keyframes.first else { return staticValue }
    if frame <= (first.t ?? 0) {
      return first.s ?? staticValue
    }
    for i in 0..<(keyframes.count - 1) {
      let current = keyframes[i]
      let next = keyframes[i + 1]
      let t0 = current.t ?? 0
      let t1 = next.t ?? t0
      if frame >= t0 && frame <= t1 {
        let start = current.s ?? []
        let end = current.e ?? next.s ?? start
        guard t1 > t0, start.count == end.count else { return start }
        let ratio = (frame - t0) / (t1 - t0)
        return zip(start, end).map { $0 + ($1 - $0) * ratio }
      }
    }
    return keyframes.last?.s ?? keyframes.dropLast().last?.e ?? staticValue
  }
}

private struct BezierShapeData: Decodable, Sendable {
  let c: Bool?
  let v: [[Double]]?
  let i: [[Double]]?
  let o: [[Double]]?

  func toPath() -> Path {
    var path = Path()
    guard let vertices = v, !vertices.isEmpty else { return path }
    let inTangents = i ?? []
    let outTangents = o ?? []

    let p0 = point(at: 0, in: vertices)
    path.move(to: p0)

    for idx in 1..<vertices.count {
      let prevPt = point(at: idx - 1, in: vertices)
      let currPt = point(at: idx, in: vertices)
      let outTan = point(at: idx - 1, in: outTangents)
      let inTan = point(at: idx, in: inTangents)
      path.addCurve(
        to: currPt,
        control1: CGPoint(x: prevPt.x + outTan.x, y: prevPt.y + outTan.y),
        control2: CGPoint(x: currPt.x + inTan.x, y: currPt.y + inTan.y)
      )
    }

    if c == true, vertices.count > 1 {
      let lastIdx = vertices.count - 1
      let prevPt = point(at: lastIdx, in: vertices)
      let currPt = p0
      let outTan = point(at: lastIdx, in: outTangents)
      let inTan = point(at: 0, in: inTangents)
      path.addCurve(
        to: currPt,
        control1: CGPoint(x: prevPt.x + outTan.x, y: prevPt.y + outTan.y),
        control2: CGPoint(x: currPt.x + inTan.x, y: currPt.y + inTan.y)
      )
      path.closeSubpath()
    }
    return path
  }

  private func point(at index: Int, in list: [[Double]]) -> CGPoint {
    guard index < list.count, list[index].count >= 2 else { return .zero }
    return CGPoint(x: list[index][0], y: list[index][1])
  }
}

private struct AnimatedShape: Decodable, Sendable {
  struct ShapeKeyframe: Decodable, Sendable {
    let t: Double?
    let s: [BezierShapeData]?
    let e: [BezierShapeData]?
  }

  let staticShape: BezierShapeData?
  let keyframes: [ShapeKeyframe]

  enum CodingKeys: String, CodingKey { case k }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let single = try? c.decode(BezierShapeData.self, forKey: .k) {
      staticShape = single
      keyframes = []
    } else if let kfs = try? c.decode([ShapeKeyframe].self, forKey: .k) {
      staticShape = nil
      keyframes = kfs
    } else {
      staticShape = nil
      keyframes = []
    }
  }

  func shapeValue(at frame: Double) -> BezierShapeData? {
    if let staticShape { return staticShape }
    guard !keyframes.isEmpty else { return nil }
    for i in 0..<(keyframes.count - 1) {
      let current = keyframes[i]
      let next = keyframes[i + 1]
      let t0 = current.t ?? 0
      let t1 = next.t ?? t0
      if frame >= t0 && frame <= t1 {
        return current.s?.first
      }
    }
    return keyframes.last?.s?.first ?? keyframes.first?.s?.first
  }
}
