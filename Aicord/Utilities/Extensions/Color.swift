//
//  Color.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 20/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

#if os(macOS)
  import AppKit
  typealias PlatformColor = NSColor
#else
  import UIKit
  typealias PlatformColor = UIColor
#endif

extension Color {
  init(hexadecimal6: Int, opacity: Double = 1.0) {
    let red = Double((hexadecimal6 >> 16) & 0xFF) / 255.0
    let green = Double((hexadecimal6 >> 8) & 0xFF) / 255.0
    let blue = Double(hexadecimal6 & 0xFF) / 255.0
    self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
  }

  static var almostClear: Color {
    Color.white.opacity(0.0001)
  }

  static var quaternaryLabel: Color {
    #if os(macOS)
      Color(nsColor: .quaternaryLabelColor)
    #else
      Color(uiColor: .quaternaryLabel)
    #endif
  }
}

extension ShapeStyle where Self == Color {
  static var almostClear: Color { .almostClear }
  static var quaternaryLabel: Color { .quaternaryLabel }
}

extension PlatformColor {
  var components: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    #if os(macOS)
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      self.usingColorSpace(.deviceRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
      return (r, g, b, a)
    #else
      var r: CGFloat = 0
      var g: CGFloat = 0
      var b: CGFloat = 0
      var a: CGFloat = 0
      self.getRed(&r, green: &g, blue: &b, alpha: &a)
      return (r, g, b, a)
    #endif
  }
}

extension Color {
  func relativeLuminance() -> CGFloat {
    let uiColor = PlatformColor(self)
    let (r, g, b, _) = uiColor.components

    func toLinear(_ c: CGFloat) -> CGFloat {
      return (c <= 0.04045)
        ? c / 12.92
        : pow((c + 0.055) / 1.055, 2.4)
    }

    let R = toLinear(r)
    let G = toLinear(g)
    let B = toLinear(b)

    return 0.2126 * R + 0.7152 * G + 0.0722 * B
  }

  /// Suggests whether `.light` or `.dark` scheme is more readable
  func suggestedColorScheme() -> ColorScheme {
    let L = relativeLuminance()
    return L > 0.5 ? .light : .dark
  }
}

extension PlatformImage {
  /// Extracts a vibrant/bright dominant color from the image, avoiding near-black and near-white pixels.
  func extractAccentColor() -> Color? {
    #if os(macOS)
      guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
    #else
      guard let cgImage = self.cgImage else { return nil }
    #endif

    let width = 32
    let height = 32
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

    guard
      let context = CGContext(
        data: &pixelData,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    struct Bucket {
      var count: Int = 0
      var rSum: Double = 0
      var gSum: Double = 0
      var bSum: Double = 0
    }

    let gridSize = 8
    var buckets = [Bucket](repeating: Bucket(), count: gridSize * gridSize * gridSize)

    for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
      let a = Double(pixelData[i + 3]) / 255.0
      guard a > 0.5 else { continue }

      let r = min(max((Double(pixelData[i]) / 255.0) / a, 0), 1)
      let g = min(max((Double(pixelData[i + 1]) / 255.0) / a, 0), 1)
      let b = min(max((Double(pixelData[i + 2]) / 255.0) / a, 0), 1)

      // Avoid near-black and near-white
      if r < 0.12 && g < 0.12 && b < 0.12 { continue }
      if r > 0.90 && g > 0.90 && b > 0.90 { continue }

      let rIdx = min(Int(r * Double(gridSize)), gridSize - 1)
      let gIdx = min(Int(g * Double(gridSize)), gridSize - 1)
      let bIdx = min(Int(b * Double(gridSize)), gridSize - 1)
      let idx = rIdx * gridSize * gridSize + gIdx * gridSize + bIdx

      buckets[idx].count += 1
      buckets[idx].rSum += r
      buckets[idx].gSum += g
      buckets[idx].bSum += b
    }

    let candidates = buckets.filter { $0.count > 0 }
    guard
      let best = candidates.max(by: { lhs, rhs in
        let lR = lhs.rSum / Double(lhs.count)
        let lG = lhs.gSum / Double(lhs.count)
        let lB = lhs.bSum / Double(lhs.count)
        let rR = rhs.rSum / Double(rhs.count)
        let rG = rhs.gSum / Double(rhs.count)
        let rB = rhs.bSum / Double(rhs.count)

        let lBrightness = 0.299 * lR + 0.587 * lG + 0.114 * lB
        let rBrightness = 0.299 * rR + 0.587 * rG + 0.114 * rB
        let lScore = lBrightness * log2(Double(lhs.count) + 1.0)
        let rScore = rBrightness * log2(Double(rhs.count) + 1.0)
        return lScore < rScore
      })
    else {
      return nil
    }

    let count = Double(best.count)
    return Color(
      red: best.rSum / count,
      green: best.gSum / count,
      blue: best.bSum / count
    )
  }
}
