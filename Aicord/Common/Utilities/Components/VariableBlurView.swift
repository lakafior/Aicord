//
//  VariableBlurView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

/// A native SwiftUI progressive blur view using system materials and a smooth gradient mask.
public struct VariableBlurView: View {
  public var blurRadius: CGFloat
  public var startPoint: UnitPoint
  public var endPoint: UnitPoint

  public init(
    blurRadius: CGFloat = 20,
    startPoint: UnitPoint = .top,
    endPoint: UnitPoint = .bottom
  ) {
    self.blurRadius = blurRadius
    self.startPoint = startPoint
    self.endPoint = endPoint
  }

  public var body: some View {
    Rectangle()
      .fill(.ultraThinMaterial)
      .mask(
        LinearGradient(
          stops: [
            .init(color: .black, location: 0.0),
            .init(color: .black.opacity(0.75), location: 0.35),
            .init(color: .black.opacity(0.3), location: 0.7),
            .init(color: .clear, location: 1.0),
          ],
          startPoint: startPoint,
          endPoint: endPoint
        )
      )
      .allowsHitTesting(false)
  }
}

#Preview {
  ZStack(alignment: .top) {
    ScrollView {
      Text("gm\ngm\ngm\ngm\ngm\ngm\ngm\ngm\n")
    }

    VariableBlurView(blurRadius: 10)
      .frame(width: 200, height: 200)
      .border(Color.red)
  }
}
