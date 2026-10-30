//
//  NukeImage.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 04/08/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import SwiftUI

enum ImageAnimation {
  case never
  case always
  case enabled(Bool)

  var wantsAnimation: Bool {
    switch self {
    case .never: false
    case .always: true
    case .enabled(let enabled): enabled
    }
  }
}

struct NukeImage<Placeholder: View>: View {
  let urlForVariant: (_ animated: Bool) -> URL?
  var animation: ImageAnimation = .always
  var placeholder: (() -> Placeholder)?

  private var isResizable = false

  @State private var loadedContainer: ImageContainer?
  @State private var loadedURL: URL?

  private var wantsAnimation: Bool { animation.wantsAnimation }
  private var primaryURL: URL? { urlForVariant(wantsAnimation) }
  private var fallbackStillURL: URL? {
    guard wantsAnimation, let still = urlForVariant(false), still != primaryURL else {
      return nil
    }
    return still
  }

  private var effectiveContainer: ImageContainer? {
    guard let primaryURL else { return nil }
    if loadedURL == primaryURL, let loadedContainer {
      return loadedContainer
    }
    return ImagePipeline.shared.cachedContainer(for: primaryURL)
  }

  private var fallbackStillContainer: ImageContainer? {
    guard let fallbackStillURL else { return nil }
    return ImagePipeline.shared.cachedContainer(for: fallbackStillURL)
  }

  var body: some View {
    Group {
      if let container = effectiveContainer {
        content(for: container)
      } else if let stillContainer = fallbackStillContainer {
        resized(Image(platformImage: stillContainer.image))
      } else if let placeholder {
        placeholder()
      } else {
        Color.clear
      }
    }
    .task(id: primaryURL) {
      guard let url = primaryURL else {
        loadedContainer = nil
        loadedURL = nil
        return
      }
      if let cached = ImagePipeline.shared.cachedContainer(for: url) {
        loadedContainer = cached
        loadedURL = url
        return
      }
      if let container = try? await ImagePipeline.shared.container(for: url),
        !Task.isCancelled
      {
        loadedContainer = container
        loadedURL = url
      }
    }
  }

  @ViewBuilder
  private func content(for container: ImageContainer) -> some View {
    if wantsAnimation, let source = container.animatedSource, source.isAnimated {
      AnimatedImageRenderer(
        source: source,
        isAnimating: true,
        isResizable: isResizable
      )
    } else {
      resized(Image(platformImage: container.image))
    }
  }

  @ViewBuilder
  private func resized(_ image: Image) -> some View {
    if isResizable {
      image.resizable()
    } else {
      image
    }
  }

  func resizable() -> Self {
    var copy = self
    copy.isResizable = true
    return copy
  }
}

// extra initialisers

extension NukeImage where Placeholder == EmptyView {
  init(
    animation: ImageAnimation = .always,
    url urlForVariant: @escaping (_ animated: Bool) -> URL?
  ) {
    self.urlForVariant = urlForVariant
    self.animation = animation
    self.placeholder = nil
  }
}

extension NukeImage {
  init(
    animation: ImageAnimation = .always,
    url urlForVariant: @escaping (_ animated: Bool) -> URL?,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.urlForVariant = urlForVariant
    self.animation = animation
    self.placeholder = placeholder
  }
}

extension NukeImage where Placeholder == EmptyView {
  init(url: URL?, isAnimating: Bool = true) {
    self.urlForVariant = { _ in url }
    self.animation = isAnimating ? .always : .never
    self.placeholder = nil
  }
}

extension NukeImage {
  init(
    url: URL?,
    isAnimating: Bool = true,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.urlForVariant = { _ in url }
    self.animation = isAnimating ? .always : .never
    self.placeholder = placeholder
  }
}

extension Image {
  init(platformImage: PlatformImage) {
    #if os(macOS)
      self.init(nsImage: platformImage)
    #else
      self.init(uiImage: platformImage)
    #endif
  }
}
