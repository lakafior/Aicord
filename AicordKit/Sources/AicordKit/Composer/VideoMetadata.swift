//
//  VideoMetadata.swift
//  AicordKit
//
//  Taking the location out of videos before they are uploaded, the video
//  counterpart of `ImageMetadata`. The picture and sound are copied as they
//  are (passthrough), only the metadata changes.
//

import Foundation

#if canImport(AVFoundation) && !os(watchOS)
  import AVFoundation
  import UniformTypeIdentifiers

  public enum VideoMetadata {
    public enum Failure: Error {
      case cannotExport
      case locationRemains
    }

    /// QuickTime and MPEG-4 videos; anything else is sent as it is.
    public static func canStrip(_ type: UTType) -> Bool { fileType(for: type) != nil }

    static func fileType(for type: UTType) -> AVFileType? {
      if type.conforms(to: .quickTimeMovie) { return .mov }
      if type.conforms(to: .mpeg4Movie) { return .mp4 }
      return nil
    }

    /// Writes a copy of `source` to `destination` without location, nor the
    /// owner, device and software details `forSharing()` treats as private.
    /// Throws when the copy can't be made, or still has a location, so a
    /// video isn't sent with it by mistake.
    public static func strip(_ source: URL, to destination: URL) async throws {
      guard let type = UTType(filenameExtension: source.pathExtension),
        let fileType = fileType(for: type)
      else { throw Failure.cannotExport }
      let asset = AVURLAsset(url: source)
      guard
        let session = AVAssetExportSession(
          asset: asset, presetName: AVAssetExportPresetPassthrough)
      else { throw Failure.cannotExport }
      // both: the filter for what the export copies over, and the movie's own
      // metadata set explicitly without the location items
      session.metadataItemFilter = .forSharing()
      let metadata = (try? await asset.load(.metadata)) ?? []
      session.metadata = metadata.filter { !isLocation($0) }
      try await session.export(to: destination, as: fileType)
      if await hasLocation(destination) {
        try? FileManager.default.removeItem(at: destination)
        throw Failure.locationRemains
      }
    }

    /// Whether the movie, or one of its tracks, carries a location.
    public static func hasLocation(_ url: URL) async -> Bool {
      let asset = AVURLAsset(url: url)
      var items = (try? await asset.load(.metadata)) ?? []
      for track in (try? await asset.load(.tracks)) ?? [] {
        items += (try? await track.load(.metadata)) ?? []
      }
      return items.contains(where: isLocation)
    }

    static let locationIdentifiers: Set<AVMetadataIdentifier> = [
      .quickTimeMetadataLocationISO6709,
      .quickTimeUserDataLocationISO6709,
      .commonIdentifierLocation,
      .quickTimeMetadataLocationName,
      .quickTimeMetadataLocationBody,
      .quickTimeMetadataLocationNote,
      .quickTimeMetadataLocationRole,
      .quickTimeMetadataLocationDate,
    ]

    static func isLocation(_ item: AVMetadataItem) -> Bool {
      if let identifier = item.identifier, locationIdentifiers.contains(identifier) { return true }
      return item.commonKey == .commonKeyLocation
    }
  }
#endif
