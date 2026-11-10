//
//  ExternalUpload.swift
//  AicordKit
//
//  Files too large for Discord go to a service the user chose in Settings
//  (catbox, litterbox or their own S3-compatible bucket such as R2), and
//  the link goes into the message. Nothing is uploaded anywhere else, and
//  the app asks before every file.
//

import CryptoKit
import Foundation

public enum ExternalUpload {
  public enum LitterboxExpiry: String, Sendable, CaseIterable, Codable {
    case hour = "1h"
    case halfDay = "12h"
    case day = "24h"
    case threeDays = "72h"
  }

  /// An S3-compatible bucket. Objects must be readable at `publicBaseURL`.
  public struct S3Bucket: Sendable, Equatable, Codable {
    /// e.g. `https://<account>.r2.cloudflarestorage.com` or `https://s3.eu-central-1.amazonaws.com`.
    public var endpoint: String
    public var bucket: String
    /// `auto` for R2.
    public var region: String
    /// Where uploaded objects can be read, e.g. `https://files.example.com`.
    public var publicBaseURL: String
    /// Put in front of every object name, e.g. `aicord/`.
    public var prefix: String

    public init(endpoint: String, bucket: String, region: String, publicBaseURL: String, prefix: String = "") {
      self.endpoint = endpoint
      self.bucket = bucket
      self.region = region
      self.publicBaseURL = publicBaseURL
      self.prefix = prefix
    }

    public var isComplete: Bool {
      URL(string: endpoint)?.host != nil && !bucket.isEmpty && !region.isEmpty
        && URL(string: publicBaseURL)?.host != nil
    }
  }

  public struct S3Credentials: Sendable, Equatable {
    public var accessKeyID: String
    public var secretAccessKey: String
    public init(accessKeyID: String, secretAccessKey: String) {
      self.accessKeyID = accessKeyID
      self.secretAccessKey = secretAccessKey
    }
  }

  public enum Service: Sendable, Equatable {
    case catbox(userHash: String?)
    case litterbox(LitterboxExpiry)
    case s3(S3Bucket, S3Credentials)

    /// Shown in the confirmation, so the user sees where the file goes.
    public var host: String {
      switch self {
      case .catbox: "catbox.moe"
      case .litterbox: "litterbox.catbox.moe"
      case .s3(let bucket, _): URL(string: bucket.publicBaseURL)?.host ?? bucket.endpoint
      }
    }

    /// The largest file the service takes, nil when it sets none we know of.
    public var sizeLimit: Int64? {
      switch self {
      case .catbox: 200 * 1024 * 1024
      case .litterbox: 1024 * 1024 * 1024
      case .s3: 5 * 1024 * 1024 * 1024
      }
    }
  }

  public enum UploadError: LocalizedError, Equatable {
    case tooLarge(limit: Int64)
    case rejected(status: Int, message: String)
    case notALink(String)

    public var errorDescription: String? {
      switch self {
      case .tooLarge(let limit):
        "The service takes files up to \(ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))."
      case .rejected(let status, let message):
        message.isEmpty ? "The service answered \(status)." : "The service answered \(status): \(message)"
      case .notALink(let text):
        "The service didn't send back a link: \(text.prefix(200))"
      }
    }
  }

  // MARK: - Uploading

  /// Uploads the file and returns the link to put in the message.
  public static func upload(
    file: URL,
    filename: String,
    contentType: String,
    to service: Service,
    session: URLSession = .shared
  ) async throws -> URL {
    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    if let limit = service.sizeLimit, size > limit { throw UploadError.tooLarge(limit: limit) }

    switch service {
    case .catbox(let userHash):
      var fields = [("reqtype", "fileupload")]
      if let userHash, !userHash.isEmpty { fields.append(("userhash", userHash)) }
      return try await postForm(
        to: URL(string: "https://catbox.moe/user/api.php")!, fields: fields,
        file: file, filename: filename, contentType: contentType,
        expectedHost: "catbox.moe", session: session)
    case .litterbox(let expiry):
      return try await postForm(
        to: URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!,
        fields: [("reqtype", "fileupload"), ("time", expiry.rawValue)],
        file: file, filename: filename, contentType: contentType,
        expectedHost: "catbox.moe", session: session)
    case .s3(let bucket, let credentials):
      let key = objectKey(prefix: bucket.prefix, filename: filename)
      var request = try S3Signer.putRequest(
        bucket: bucket, key: key, contentType: contentType, credentials: credentials, date: .now)
      request.timeoutInterval = 600
      let (data, response) = try await session.upload(for: request, fromFile: file)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else {
        throw UploadError.rejected(status: status, message: s3Message(data))
      }
      return publicURL(bucket: bucket, key: key)
    }
  }

  private static func postForm(
    to url: URL, fields: [(String, String)], file: URL, filename: String,
    contentType: String, expectedHost: String, session: URLSession
  ) async throws -> URL {
    let boundary = "aicord-" + UUID().uuidString
    let body = FileManager.default.temporaryDirectory
      .appendingPathComponent("upload-\(UUID().uuidString).multipart")
    // removed also when writing it fails halfway
    defer { try? FileManager.default.removeItem(at: body) }
    try Multipart.write(
      fields: fields, fileField: "fileToUpload", file: file, filename: filename,
      contentType: contentType, boundary: boundary, to: body)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 600
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.upload(for: request, fromFile: body)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let text = String(decoding: data, as: UTF8.self)
    guard (200..<300).contains(status) else {
      throw UploadError.rejected(status: status, message: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return try link(fromResponse: text, expectedHost: expectedHost)
  }

  /// The link in a catbox or litterbox answer, which is the link alone as text.
  public static func link(fromResponse text: String, expectedHost: String) throws -> URL {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme == "https",
      let host = url.host?.lowercased(),
      host == expectedHost || host.hasSuffix("." + expectedHost),
      url.path.count > 1
    else { throw UploadError.notALink(trimmed) }
    return url
  }

  /// A name that won't collide with earlier uploads: a random folder and the file name.
  public static func objectKey(prefix: String, filename: String) -> String {
    let folder = String(UUID().uuidString.lowercased().prefix(8))
    var prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    if !prefix.isEmpty { prefix += "/" }
    return prefix + folder + "/" + filename
  }

  public static func publicURL(bucket: S3Bucket, key: String) -> URL {
    var base = bucket.publicBaseURL
    while base.hasSuffix("/") { base.removeLast() }
    return URL(string: base + "/" + S3Signer.encodePath(key))!
  }

  private static func s3Message(_ data: Data) -> String {
    let text = String(decoding: data, as: UTF8.self)
    if let start = text.range(of: "<Message>"), let end = text.range(of: "</Message>"),
      start.upperBound <= end.lowerBound
    {
      return String(text[start.upperBound..<end.lowerBound])
    }
    return String(text.prefix(200))
  }
}

// MARK: - Multipart

public enum Multipart {
  /// The text before the file's bytes.
  public static func head(
    fields: [(String, String)], fileField: String, filename: String, contentType: String,
    boundary: String
  ) -> Data {
    var text = ""
    for (name, value) in fields {
      text += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(escape(name))\"\r\n\r\n\(value)\r\n"
    }
    text += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(escape(fileField))\"; filename=\"\(escape(filename))\"\r\n"
    text += "Content-Type: \(contentType)\r\n\r\n"
    return Data(text.utf8)
  }

  public static func tail(boundary: String) -> Data {
    Data("\r\n--\(boundary)--\r\n".utf8)
  }

  /// Writes the whole body to `destination` without loading the file into memory.
  public static func write(
    fields: [(String, String)], fileField: String, file: URL, filename: String,
    contentType: String, boundary: String, to destination: URL
  ) throws {
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }
    try output.write(
      contentsOf: head(
        fields: fields, fileField: fileField, filename: filename, contentType: contentType,
        boundary: boundary))
    let input = try FileHandle(forReadingFrom: file)
    defer { try? input.close() }
    while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
      try output.write(contentsOf: chunk)
    }
    try output.write(contentsOf: tail(boundary: boundary))
  }

  private static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "")
      .replacingOccurrences(of: "\n", with: "")
  }
}

// MARK: - S3 signing

/// AWS Signature Version 4 for single requests to S3-compatible storage.
public enum S3Signer {
  public static func putRequest(
    bucket: ExternalUpload.S3Bucket, key: String, contentType: String,
    credentials: ExternalUpload.S3Credentials, date: Date
  ) throws -> URLRequest {
    var base = bucket.endpoint
    while base.hasSuffix("/") { base.removeLast() }
    guard let url = URL(string: base + "/" + encodePath(bucket.bucket) + "/" + encodePath(key)),
      url.host != nil
    else { throw ExternalUpload.UploadError.notALink(bucket.endpoint) }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    let headers = sign(
      method: "PUT", url: url,
      headers: ["content-type": contentType],
      payloadHash: "UNSIGNED-PAYLOAD",
      region: bucket.region, service: "s3", credentials: credentials, date: date)
    for (name, value) in headers where name != "host" {
      request.setValue(value, forHTTPHeaderField: name)
    }
    return request
  }

  /// The headers to send, `authorization` among them. `headers` are signed too.
  public static func sign(
    method: String, url: URL, headers: [String: String], payloadHash: String,
    region: String, service: String, credentials: ExternalUpload.S3Credentials, date: Date
  ) -> [String: String] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    let amzDate = formatter.string(from: date)
    let day = String(amzDate.prefix(8))

    var all: [String: String] = [:]
    for (name, value) in headers { all[name.lowercased()] = value.trimmingCharacters(in: .whitespaces) }
    var host = url.host ?? ""
    if let port = url.port { host += ":\(port)" }
    all["host"] = host
    all["x-amz-date"] = amzDate
    all["x-amz-content-sha256"] = payloadHash

    let names = all.keys.sorted()
    let canonicalHeaders = names.map { "\($0):\(all[$0]!)\n" }.joined()
    let signedHeaders = names.joined(separator: ";")
    let path = url.path.isEmpty ? "/" : encodePath(url.path)
    let query = canonicalQuery(url)
    let canonicalRequest = [method, path, query, canonicalHeaders, signedHeaders, payloadHash]
      .joined(separator: "\n")

    let scope = "\(day)/\(region)/\(service)/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256", amzDate, scope, hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
    ].joined(separator: "\n")

    var key = SymmetricKey(data: Data("AWS4\(credentials.secretAccessKey)".utf8))
    for part in [day, region, service, "aws4_request"] {
      key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key)))
    }
    let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))

    all["authorization"] =
      "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    return all
  }

  /// Percent-encodes each path segment as S3 expects (RFC 3986 unreserved kept).
  public static func encodePath(_ path: String) -> String {
    path.split(separator: "/", omittingEmptySubsequences: false)
      .map { encode(String($0)) }
      .joined(separator: "/")
  }

  static func encode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    // alphanumerics includes non-ASCII letters, which must be encoded
    return value.unicodeScalars.map { scalar in
      scalar.isASCII && allowed.contains(scalar)
        ? String(scalar)
        : String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
    }.joined()
  }

  private static func canonicalQuery(_ url: URL) -> String {
    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
      return ""
    }
    let pairs: [(name: String, value: String)] = items.map { item in
      (encode(item.name), encode(item.value ?? ""))
    }
    let sorted = pairs.sorted { a, b in a.name == b.name ? a.value < b.value : a.name < b.name }
    return sorted.map { pair in pair.name + "=" + pair.value }.joined(separator: "&")
  }

  private static func hex(_ digest: some Sequence<UInt8>) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
