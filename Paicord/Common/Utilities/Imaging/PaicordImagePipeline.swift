//
//  PaicordImagePipeline.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 04/08/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import Foundation
import ImageIO
import os

#if os(macOS)
  import AppKit
  typealias PlatformImage = NSImage
#else
  import UIKit
  typealias PlatformImage = UIImage
#endif

final class ImageContainer: @unchecked Sendable {
  let image: PlatformImage
  let data: Data?
  let utType: CFString?
  let animatedSource: AnimatedImageFrameSource?

  init(
    image: PlatformImage,
    data: Data? = nil,
    utType: CFString? = nil,
    animatedSource: AnimatedImageFrameSource? = nil
  ) {
    self.image = image
    self.data = data
    self.utType = utType
    self.animatedSource = animatedSource
  }
}

actor ImagePipeline {
  static let shared = ImagePipeline()

  nonisolated private let memoryCache = OSAllocatedUnfairLock<NSCache<NSURL, ImageContainer>>(
    uncheckedState: {
      let cache = NSCache<NSURL, ImageContainer>()
      cache.countLimit = 500
      cache.totalCostLimit = 128 * 1024 * 1024
      return cache
    }()
  )

  private let session: URLSession
  private var ongoingTasks: [URL: Task<ImageContainer, Error>] = [:]

  init() {
    let config = URLSessionConfiguration.default
    let cacheDir = URL.cachesDirectory.appending(path: "com.llsc12.paicord.imagecache")
    let urlCache = URLCache(
      memoryCapacity: 64 * 1024 * 1024,
      diskCapacity: 250 * 1024 * 1024,
      directory: cacheDir
    )
    config.urlCache = urlCache
    config.requestCachePolicy = .returnCacheDataElseLoad
    self.session = URLSession(configuration: config)
  }

  nonisolated func cachedContainer(for url: URL) -> ImageContainer? {
    memoryCache.withLockUnchecked { $0.object(forKey: url as NSURL) }
  }

  func container(for url: URL) async throws -> ImageContainer {
    if let cached = cachedContainer(for: url) {
      return cached
    }

    if let existingTask = ongoingTasks[url] {
      return try await existingTask.value
    }

    let task = Task<ImageContainer, Error> {
      defer {
        ongoingTasks.removeValue(forKey: url)
      }

      let (data, response) = try await session.data(from: url)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw URLError(.badServerResponse)
      }

      let container = try await Task.detached(priority: .userInitiated) {
        try Self.decodeContainer(from: data)
      }.value

      memoryCache.withLockUnchecked {
        $0.setObject(container, forKey: url as NSURL, cost: data.count)
      }
      return container
    }

    ongoingTasks[url] = task
    return try await task.value
  }

  func image(for url: URL) async throws -> PlatformImage {
    try await container(for: url).image
  }

  nonisolated private static func decodeContainer(from data: Data) throws -> ImageContainer {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      throw URLError(.cannotDecodeContentData)
    }

    let utType = CGImageSourceGetType(source)
    let count = CGImageSourceGetCount(source)

    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw URLError(.cannotDecodeContentData)
    }

    #if os(macOS)
      let platformImage = NSImage(
        cgImage: cgImage,
        size: NSSize(width: cgImage.width, height: cgImage.height)
      )
    #else
      let platformImage = UIImage(cgImage: cgImage)
    #endif

    var animatedSource: AnimatedImageFrameSource? = nil
    if count > 1, let frames = AnimatedImageFrameSource(data: data, utType: utType),
      frames.isAnimated
    {
      animatedSource = frames
    }

    return ImageContainer(
      image: platformImage,
      data: animatedSource != nil ? data : nil,
      utType: utType,
      animatedSource: animatedSource
    )
  }
}

enum PaicordImagePipeline {
  static func configure() {
    _ = ImagePipeline.shared
  }
}
