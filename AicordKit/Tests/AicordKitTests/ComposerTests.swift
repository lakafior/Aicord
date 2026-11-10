import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AicordKit

class ComposerTests: XCTestCase {

  // MARK: Link cleaning

  func testRemovesUTMAndClickIDs() {
    let url = URL(string: "https://example.com/a/b?id=7&utm_source=x&utm_medium=y&fbclid=abc#top")!
    XCTAssertEqual(LinkCleaner.clean(url)?.absoluteString, "https://example.com/a/b?id=7#top")
  }

  func testDropsQuestionMarkWhenNothingIsLeft() {
    let url = URL(string: "https://example.com/page?gclid=1&utm_campaign=2")!
    XCTAssertEqual(LinkCleaner.clean(url)?.absoluteString, "https://example.com/page")
  }

  func testYouTubeAndSpotifyShareIDs() {
    XCTAssertEqual(
      LinkCleaner.clean(URL(string: "https://youtu.be/dQw4w9WgXcQ?si=AbCdEf&t=42")!)?.absoluteString,
      "https://youtu.be/dQw4w9WgXcQ?t=42")
    XCTAssertEqual(
      LinkCleaner.clean(URL(string: "https://www.youtube.com/watch?v=abc&si=x&pp=y")!)?.absoluteString,
      "https://www.youtube.com/watch?v=abc")
    XCTAssertEqual(
      LinkCleaner.clean(URL(string: "https://open.spotify.com/track/123?si=4f2a")!)?.absoluteString,
      "https://open.spotify.com/track/123")
  }

  func testHostRulesStayOnTheirHosts() {
    // `si` and `t` mean something else elsewhere
    XCTAssertNil(LinkCleaner.clean(URL(string: "https://example.com/?si=1&t=2")!))
    XCTAssertEqual(
      LinkCleaner.clean(URL(string: "https://x.com/user/status/1?s=20&t=abc")!)?.absoluteString,
      "https://x.com/user/status/1")
  }

  func testDisabledRulesAreKept() {
    let url = URL(string: "https://youtu.be/abc?si=1&utm_source=2")!
    XCTAssertEqual(
      LinkCleaner.clean(url, enabledRules: ["utm"])?.absoluteString, "https://youtu.be/abc?si=1")
    XCTAssertNil(LinkCleaner.clean(url, enabledRules: []))
  }

  func testUnchangedAndNonWebLinksReturnNil() {
    XCTAssertNil(LinkCleaner.clean(URL(string: "https://example.com/?q=swift")!))
    XCTAssertNil(LinkCleaner.clean(URL(string: "mailto:a@b.c?utm_source=1")!))
  }

  func testCleansLinksInsideText() {
    let text = "look https://youtu.be/abc?si=zz and https://example.com/?utm_source=a&q=1 ok"
    XCTAssertEqual(
      LinkCleaner.clean(text: text),
      "look https://youtu.be/abc and https://example.com/?q=1 ok")
    XCTAssertEqual(LinkCleaner.clean(text: "no links? fine"), "no links? fine")
  }

  // MARK: Splitting

  func testShortTextIsOnePart() {
    XCTAssertEqual(MessageSplitter.split("  hello  ", limit: 2000), ["hello"])
    XCTAssertEqual(MessageSplitter.split("   ", limit: 2000), [])
  }

  func testSplitsBetweenParagraphs() {
    let a = String(repeating: "a", count: 60)
    let b = String(repeating: "b", count: 60)
    let parts = MessageSplitter.split("\(a)\n\n\(b)", limit: 100)
    XCTAssertEqual(parts, [a, b])
  }

  func testPrefersSentencesOverWords() {
    let first = "This is the first sentence of a long text."
    let second = "And this second one goes on for a while more words"
    let parts = MessageSplitter.split("\(first) \(second)", limit: 60)
    XCTAssertEqual(parts.first, first)
    XCTAssertTrue(parts.allSatisfy { MessageSplitter.length($0) <= 60 })
    XCTAssertEqual(parts.joined(separator: " "), "\(first) \(second)")
  }

  func testEveryPartFitsAndNothingIsLost() {
    let words = (1...800).map { "word\($0)" }
    let text = words.joined(separator: " ")
    let parts = MessageSplitter.split(text, limit: 2000)
    XCTAssertGreaterThan(parts.count, 1)
    XCTAssertTrue(parts.allSatisfy { MessageSplitter.length($0) <= 2000 })
    XCTAssertEqual(parts.joined(separator: " "), text)
  }

  func testCodeBlockThatFitsMovesWhole() {
    let intro = String(repeating: "intro ", count: 10).trimmingCharacters(in: .whitespaces)
    let code = "```swift\n" + (1...8).map { "let x\($0) = \($0)" }.joined(separator: "\n") + "\n```"
    let parts = MessageSplitter.split(intro + "\n" + code, limit: 150)
    XCTAssertEqual(parts, [intro, code])
  }

  func testLongCodeBlockIsClosedAndReopened() {
    let lines = (1...40).map { "print(\"line \($0)\")" }
    let text = "```python\n" + lines.joined(separator: "\n") + "\n```"
    let parts = MessageSplitter.split(text, limit: 200)
    XCTAssertGreaterThan(parts.count, 1)
    for part in parts {
      XCTAssertLessThanOrEqual(MessageSplitter.length(part), 200)
      XCTAssertTrue(part.hasPrefix("```python\n"), part)
      XCTAssertTrue(part.hasSuffix("```"), part)
    }
    // every line is in exactly one part, whole
    let sentLines = parts.flatMap { $0.split(separator: "\n").map(String.init) }
      .filter { !$0.hasPrefix("```") }
    XCTAssertEqual(sentLines, lines)
  }

  func testOneHugeWordIsCutHard() {
    let text = String(repeating: "x", count: 250)
    let parts = MessageSplitter.split(text, limit: 100)
    XCTAssertEqual(parts.map(\.count), [100, 100, 50])
  }

  func testEmojiCountAsScalars() {
    let family = "👨‍👩‍👧‍👦"  // 7 scalars
    let text = Array(repeating: family, count: 40).joined(separator: " ")
    let parts = MessageSplitter.split(text, limit: 50)
    XCTAssertTrue(parts.allSatisfy { MessageSplitter.length($0) <= 50 })
    XCTAssertEqual(parts.joined(separator: " "), text)
  }

  // MARK: Private names

  struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state
    }
  }

  func testRandomNameKeepsExtension() {
    var generator = SeededGenerator(state: 1)
    let name = PrivateFilename.random(for: "IMG_2041.HEIC", using: &generator)
    XCTAssertTrue(name.hasSuffix(".HEIC"))
    XCTAssertEqual(name.count, 12 + 5)
    XCTAssertFalse(name.contains("IMG"))
    XCTAssertTrue(name.dropLast(5).allSatisfy { $0.isLowercase || $0.isNumber })
  }

  func testRandomNamesDiffer() {
    let names = Set((0..<50).map { _ in PrivateFilename.random(for: "a.png") })
    XCTAssertEqual(names.count, 50)
  }

  func testSpoilerPrefixAndOddExtensions() {
    var generator = SeededGenerator(state: 7)
    XCTAssertTrue(PrivateFilename.random(for: "SPOILER_cat.jpg", using: &generator).hasPrefix("SPOILER_"))
    XCTAssertTrue(PrivateFilename.random(for: "SPOILER_cat.jpg", using: &generator).hasSuffix(".jpg"))
    XCTAssertEqual(PrivateFilename.fileExtension(of: "backup.tar.gz"), "tar.gz")
    XCTAssertEqual(PrivateFilename.fileExtension(of: "README"), "")
    XCTAssertEqual(PrivateFilename.fileExtension(of: ".env"), "")
    XCTAssertEqual(PrivateFilename.fileExtension(of: "notes.v2.txt"), "txt")
    XCTAssertEqual(PrivateFilename.fileExtension(of: "weird.name with spaces"), "")
    XCTAssertEqual(PrivateFilename.random(for: "README", using: &generator).count, 12)
  }

  // MARK: Photo metadata

  private func jpegWithLocation(orientation: Int) throws -> Data {
    let context = CGContext(
      data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
    let image = context.makeImage()!
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    let properties: [CFString: Any] = [
      kCGImagePropertyOrientation: orientation,
      kCGImagePropertyGPSDictionary: [
        kCGImagePropertyGPSLatitude: 52.2297, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 21.0122, kCGImagePropertyGPSLongitudeRef: "E",
      ],
      kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2026:11:10 12:00:00",
        kCGImagePropertyExifLensModel: "Test Lens",
      ],
      kCGImagePropertyTIFFDictionary: [
        kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone",
      ],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  func testStripsLocationAndCameraButKeepsOrientation() throws {
    let original = try jpegWithLocation(orientation: 6)
    XCTAssertFalse(ImageMetadata.isClean(original))
    let stripped = try XCTUnwrap(ImageMetadata.stripped(original))
    XCTAssertTrue(ImageMetadata.isClean(stripped))
    let source = CGImageSourceCreateWithData(stripped as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, 6)
    XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 8)
  }

  func testNonImagesAreLeftAlone() {
    XCTAssertNil(ImageMetadata.stripped(Data("not an image".utf8)))
  }

  // MARK: Links without Nitro

  func testEmojiAndStickerLinks() {
    XCTAssertEqual(
      NitroFreeLinks.emoji(id: "123", name: "pog", animated: false),
      "https://cdn.discordapp.com/emojis/123.webp?size=48&name=pog&quality=lossless")
    XCTAssertEqual(
      NitroFreeLinks.emoji(id: "9", name: "dance", animated: true),
      "https://cdn.discordapp.com/emojis/9.gif?size=48&name=dance")
    XCTAssertEqual(
      NitroFreeLinks.sticker(id: "55", format: .apng),
      "https://media.discordapp.net/stickers/55.png?size=160")
    XCTAssertNil(NitroFreeLinks.sticker(id: "55", format: .lottie))
  }

  // MARK: External upload

  func testCatboxAnswerMustBeItsLink() throws {
    XCTAssertEqual(
      try ExternalUpload.link(fromResponse: "https://files.catbox.moe/ab12cd.mp4\n", expectedHost: "catbox.moe")
        .absoluteString,
      "https://files.catbox.moe/ab12cd.mp4")
    XCTAssertThrowsError(try ExternalUpload.link(fromResponse: "File too large", expectedHost: "catbox.moe"))
    XCTAssertThrowsError(
      try ExternalUpload.link(fromResponse: "https://evil.example/x", expectedHost: "catbox.moe"))
  }

  func testMultipartLayout() {
    let head = String(
      decoding: Multipart.head(
        fields: [("reqtype", "fileupload")], fileField: "fileToUpload", filename: "a b.png",
        contentType: "image/png", boundary: "B"), as: UTF8.self)
    XCTAssertEqual(
      head,
      "--B\r\nContent-Disposition: form-data; name=\"reqtype\"\r\n\r\nfileupload\r\n"
        + "--B\r\nContent-Disposition: form-data; name=\"fileToUpload\"; filename=\"a b.png\"\r\n"
        + "Content-Type: image/png\r\n\r\n")
    XCTAssertEqual(String(decoding: Multipart.tail(boundary: "B"), as: UTF8.self), "\r\n--B--\r\n")
  }

  func testMultipartFileOnDisk() throws {
    let directory = FileManager.default.temporaryDirectory
    let file = directory.appendingPathComponent("aicord-test-\(UUID().uuidString).bin")
    let body = directory.appendingPathComponent("aicord-test-\(UUID().uuidString).multipart")
    defer {
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: body)
    }
    try Data([1, 2, 3]).write(to: file)
    try Multipart.write(
      fields: [], fileField: "f", file: file, filename: "x.bin",
      contentType: "application/octet-stream", boundary: "Q", to: body)
    let data = try Data(contentsOf: body)
    XCTAssertTrue(data.starts(with: Data("--Q\r\n".utf8)))
    XCTAssertNotNil(data.range(of: Data([1, 2, 3])))
    XCTAssertTrue(String(decoding: data.suffix(9), as: UTF8.self).hasSuffix("--Q--\r\n"))
  }

  /// The GET Object example from AWS's Signature Version 4 documentation.
  func testS3SignatureMatchesAWSExample() {
    let headers = S3Signer.sign(
      method: "GET",
      url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!,
      headers: ["Range": "bytes=0-9"],
      payloadHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      region: "us-east-1", service: "s3",
      credentials: .init(
        accessKeyID: "AKIAIOSFODNN7EXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"),
      date: Date(timeIntervalSince1970: 1_369_353_600))
    XCTAssertEqual(
      headers["authorization"],
      "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, "
        + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, "
        + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
  }

  func testS3PutRequestAndPublicLink() throws {
    let bucket = ExternalUpload.S3Bucket(
      endpoint: "https://acc.r2.cloudflarestorage.com/", bucket: "files", region: "auto",
      publicBaseURL: "https://files.example.com/", prefix: "/aicord/")
    let request = try S3Signer.putRequest(
      bucket: bucket, key: "aicord/ab/zdjęcie 1.png", contentType: "image/png",
      credentials: .init(accessKeyID: "K", secretAccessKey: "S"), date: .now)
    XCTAssertEqual(
      request.url?.absoluteString,
      "https://acc.r2.cloudflarestorage.com/files/aicord/ab/zdj%C4%99cie%201.png")
    XCTAssertEqual(request.httpMethod, "PUT")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-amz-content-sha256"), "UNSIGNED-PAYLOAD")
    XCTAssertTrue(request.value(forHTTPHeaderField: "authorization")?.contains("/auto/s3/aws4_request") == true)
    XCTAssertEqual(
      ExternalUpload.publicURL(bucket: bucket, key: "aicord/ab/zdjęcie 1.png").absoluteString,
      "https://files.example.com/aicord/ab/zdj%C4%99cie%201.png")
    XCTAssertTrue(ExternalUpload.objectKey(prefix: "/aicord/", filename: "a.png").hasPrefix("aicord/"))
    XCTAssertTrue(ExternalUpload.objectKey(prefix: "", filename: "a.png").hasSuffix("/a.png"))
  }
}
