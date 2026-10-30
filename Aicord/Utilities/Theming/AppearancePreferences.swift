//
//  AppearancePreferences.swift
//  Aicord
//
//  Local appearance settings (text size, font, motion) applied to each window,
//  together with the theme and its colour scheme.
//

import SwiftUI

/// Local appearance settings that apply to the whole window.
enum AppearancePreferences {
  enum Key {
    static let textSize = "Paicord.Appearance.TextSize"
    static let fontDesign = "Paicord.Appearance.FontDesign"
    static let reduceMotion = "Paicord.Appearance.ReduceMotion"
    static let chatMessagesAnimated = "Paicord.Appearance.ChatMessagesAnimated"
  }

  /// Stored as an index into `DynamicTypeSize.allCases`, -1 follows the system.
  static let systemTextSize = -1
  static let textSizes = DynamicTypeSize.allCases

  enum FontDesign: String, CaseIterable, Identifiable {
    case `default`, rounded, serif, monospaced

    var id: String { rawValue }

    var title: LocalizedStringKey {
      switch self {
      case .default: "System"
      case .rounded: "Rounded"
      case .serif: "Serif"
      case .monospaced: "Monospaced"
      }
    }

    var design: Font.Design {
      switch self {
      case .default: .default
      case .rounded: .rounded
      case .serif: .serif
      case .monospaced: .monospaced
      }
    }
  }
}

extension EnvironmentValues {
  /// The system's Reduce Motion or Aicord's own, whichever is on.
  @Entry var reducesMotion: Bool = false
}

extension View {
  /// Applies the theme, colour scheme, text size, font and motion settings.
  func appAppearance() -> some View {
    modifier(AppAppearanceModifier())
  }
}

private struct AppAppearanceModifier: ViewModifier {
  @AppStorage(AppearancePreferences.Key.textSize)
  private var textSize = AppearancePreferences.systemTextSize
  @AppStorage(AppearancePreferences.Key.fontDesign)
  private var fontDesign = AppearancePreferences.FontDesign.default
  @AppStorage(AppearancePreferences.Key.reduceMotion)
  private var reduceMotion = false
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  func body(content: Content) -> some View {
    let theming = Theming.shared
    let theme = theming.currentTheme
    let reducesMotion = reduceMotion || systemReduceMotion
    content
      .environment(\.theme, theme)
      .environment(\.reducesMotion, reducesMotion)
      .preferredColorScheme(theme.common.colorScheme)
      .fontDesign(fontDesign.design)
      .modifier(TextSizeModifier(index: textSize))
      #if os(macOS)
        // macOS keeps the system accent unless one is picked
        .tint(theming.accentOverride)
      #endif
      .transaction { transaction in
        if reducesMotion {
          transaction.animation = nil
          transaction.disablesAnimations = true
        }
      }
  }
}

private struct TextSizeModifier: ViewModifier {
  let index: Int

  func body(content: Content) -> some View {
    if AppearancePreferences.textSizes.indices.contains(index) {
      content.dynamicTypeSize(AppearancePreferences.textSizes[index])
    } else {
      content
    }
  }
}
