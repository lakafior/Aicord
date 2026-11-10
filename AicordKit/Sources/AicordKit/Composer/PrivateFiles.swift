//
//  PrivateFiles.swift
//  AicordKit
//
//  Private file names (a random name with the original extension) and
//  removing EXIF and GPS from photos before they are uploaded.
//

import Foundation

#if canImport(ImageIO)
  import ImageIO
  import UniformTypeIdentifiers
#endif

public enum PrivateFilename {
  /// Extensions made of two parts that should stay together.
  static let doubleExtensions: Set<String> = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst"]
  static let spoilerPrefix = "SPOILER_"
  static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

  /// A random name that keeps `original`'s extension and the `SPOILER_` prefix
  /// Discord uses to hide a file, e.g. `IMG_2041.HEIC` → `k3v9x0q2m7ab.HEIC`.
  public static func random(
    for original: String,
    length: Int = 12,
    using generator: inout some RandomNumberGenerator
  ) -> String {
    let isSpoiler = original.hasPrefix(spoilerPrefix)
    let name = String((0..<max(length, 1)).map { _ in alphabet.randomElement(using: &generator)! })
    let ext = fileExtension(of: original)
    return (isSpoiler ? spoilerPrefix : "") + name + (ext.isEmpty ? "" : "." + ext)
  }

  public static func random(for original: String, length: Int = 12) -> String {
    var generator = SystemRandomNumberGenerator()
    return random(for: original, length: length, using: &generator)
  }

  /// The extension as written, "" when there is none. Hidden files like
  /// `.env` have no extension.
  public static func fileExtension(of filename: String) -> String {
    let base = filename.hasPrefix(spoilerPrefix) ? String(filename.dropFirst(spoilerPrefix.count)) : filename
    let parts = base.split(separator: ".", omittingEmptySubsequences: false)
    // "name" and ".env" have none
    guard parts.count > 1, !(parts.count == 2 && parts[0].isEmpty) else { return "" }
    if parts.count > 2 {
      let lastTwo = parts.suffix(2).joined(separator: ".")
      if doubleExtensions.contains(lastTwo.lowercased()) { return lastTwo }
    }
    let ext = String(parts.last!)
    // "file." or a long tail after a dot in a sentence-like name isn't an extension
    guard !ext.isEmpty, ext.count <= 10, !ext.contains(" ") else { return "" }
    return ext
  }
}

#if canImport(ImageIO)
  public enum ImageMetadata {
    /// Photo formats whose metadata is rewritten; anything else is sent as it is.
    public static let strippableTypes: [UTType] = [.jpeg, .heic, .heif, .png, .tiff]

    public static func canStrip(_ type: UTType) -> Bool {
      strippableTypes.contains { type.conforms(to: $0) }
    }

    /// The image without EXIF, GPS, TIFF camera details, IPTC and XMP. The
    /// orientation stays, so the photo isn't turned. JPEG and HEIC are copied
    /// without re-encoding when ImageIO can; nil when the data isn't an image
    /// of a type above.
    public static func stripped(_ data: Data) -> Data? {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let typeID = CGImageSourceGetType(source),
        let type = UTType(typeID as String), canStrip(type)
      else { return nil }
      let count = CGImageSourceGetCount(source)
      guard count > 0 else { return nil }

      let output = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(output, typeID, count, nil)
      else { return nil }

      // keep only the orientation
      let metadata = CGImageMetadataCreateMutable()
      if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation != 1
      {
        CGImageMetadataSetValueMatchingImageProperty(
          metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation,
          orientation as CFNumber)
      }
      let options: [CFString: Any] = [
        kCGImageDestinationMetadata: metadata,
        kCGImageDestinationMergeMetadata: false,
        kCGImageMetadataShouldExcludeGPS: true,
        kCGImageMetadataShouldExcludeXMP: true,
      ]
      var error: Unmanaged<CFError>?
      if CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error),
        isClean(output as Data)
      {
        return output as Data
      }
      return reencoded(source, typeID: typeID, count: count)
    }

    /// Draws the pixels again into a new file with nothing but orientation.
    private static func reencoded(_ source: CGImageSource, typeID: CFString, count: Int) -> Data? {
      let output = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(output, typeID, count, nil)
      else { return nil }
      for index in 0..<count {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.92]
        if let original = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let orientation = original[kCGImagePropertyOrientation]
        {
          properties[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
      }
      guard CGImageDestinationFinalize(destination) else { return nil }
      return output as Data
    }

    /// Whether `data` has no GPS, EXIF dates or camera details left.
    public static func isClean(_ data: Data) -> Bool {
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
      else { return false }
      if properties[kCGImagePropertyGPSDictionary] != nil { return false }
      if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
        exif[kCGImagePropertyExifDateTimeOriginal] != nil
          || exif[kCGImagePropertyExifLensModel] != nil
          || exif[kCGImagePropertyExifBodySerialNumber] != nil
      {
        return false
      }
      if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
        tiff[kCGImagePropertyTIFFModel] != nil || tiff[kCGImagePropertyTIFFMake] != nil
          || tiff[kCGImagePropertyTIFFDateTime] != nil || tiff[kCGImagePropertyTIFFSoftware] != nil
      {
        return false
      }
      return true
    }
  }
#endif
