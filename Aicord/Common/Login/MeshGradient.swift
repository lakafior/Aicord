//
//  MeshGradient.swift
//  Aicord
//
// Created by Lakhan Lothiyi on 05/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI
import simd

extension LoginView {
  struct MeshGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    private static let lightColors: [Color] = [
      Color(red: 0.345, green: 0.396, blue: 0.949),  // Blurple (#5865F2)
      Color(red: 0.557, green: 0.631, blue: 0.882),  // Soft Indigo (#8EA1E1)
      Color(red: 0.655, green: 0.686, blue: 1.000),  // Periwinkle (#A7AFFF)
      Color(red: 0.765, green: 0.749, blue: 0.992),  // Lavender (#C3BFFD)
      Color(red: 0.278, green: 0.251, blue: 0.631),  // Deep Purple (#4740A1)
      Color(red: 0.557, green: 0.631, blue: 0.882),
      Color(red: 0.345, green: 0.396, blue: 0.949),
      Color(red: 0.655, green: 0.686, blue: 1.000),
      Color(red: 0.278, green: 0.251, blue: 0.631),
    ]

    private static let darkColors: [Color] = [
      Color(red: 0.345, green: 0.396, blue: 0.949),  // Blurple (#5865F2)
      Color(red: 0.227, green: 0.243, blue: 0.675),  // Royal Blue (#3A3EAC)
      Color(red: 0.157, green: 0.173, blue: 0.329),  // Deep Indigo (#282C54)
      Color(red: 0.118, green: 0.098, blue: 0.231),  // Midnight Purple (#1E193B)
      Color(red: 0.227, green: 0.243, blue: 0.675),
      Color(red: 0.137, green: 0.153, blue: 0.165),  // Slate (#23272A)
      Color(red: 0.157, green: 0.173, blue: 0.329),
      Color(red: 0.345, green: 0.396, blue: 0.949),
      Color(red: 0.118, green: 0.098, blue: 0.231),
    ]

    var body: some View {
      TimelineView(.animation) { timeline in
        let t = Float(timeline.date.timeIntervalSinceReferenceDate)
        SwiftUI.MeshGradient(
          width: 3,
          height: 3,
          points: Self.animatedPoints(at: t),
          colors: colorScheme == .light ? Self.lightColors : Self.darkColors,
          smoothsColors: true
        )
      }
      .ignoresSafeArea()
    }

    private static func animatedPoints(at t: Float) -> [SIMD2<Float>] {
      let dx1 = 0.12 * sin(t * 0.45)
      let dy1 = 0.12 * cos(t * 0.38)
      let dx2 = 0.10 * cos(t * 0.52)
      let dy2 = 0.10 * sin(t * 0.41)

      return [
        SIMD2<Float>(0.0, 0.0),
        SIMD2<Float>(0.5 + dx1 * 0.5, 0.0),
        SIMD2<Float>(1.0, 0.0),

        SIMD2<Float>(0.0, 0.5 + dy1 * 0.5),
        SIMD2<Float>(0.5 + dx1, 0.5 + dy2),
        SIMD2<Float>(1.0, 0.5 - dy1 * 0.5),

        SIMD2<Float>(0.0, 1.0),
        SIMD2<Float>(0.5 - dx2 * 0.5, 1.0),
        SIMD2<Float>(1.0, 1.0),
      ]
    }
  }
}
