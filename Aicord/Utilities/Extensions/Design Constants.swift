//
//  Design Constants.swift
//  Aicord
//
// Created by Lakhan Lothiyi on 06/09/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

enum UserInterfaceIdiom: Hashable, Sendable {
  case phone
  case pad
  case mac
  case tv
  case watch
  case vision
  case unspecified

  @MainActor
  static var current: UserInterfaceIdiom {
    #if os(macOS)
      return .mac
    #elseif os(iOS)
      switch UIDevice.current.userInterfaceIdiom {
      case .phone: return .phone
      case .pad: return .pad
      case .mac: return .mac
      case .tv: return .tv
      case .vision: return .vision
      default: return .unspecified
      }
    #else
      return .unspecified
    #endif
  }
}

extension EnvironmentValues {
  @Entry var userInterfaceIdiom: UserInterfaceIdiom = MainActor.assumeIsolated { .current }
}

extension Shape where Self == RoundedRectangle {
  /// Standard 10 point continuous rounding
  public static var rounded: Self {
    .rect(cornerSize: .init(10), style: .continuous)
  }
}
extension RoundedRectangle {
  public init() {
    self = .init(cornerSize: .init(10), style: .continuous)
  }
}
