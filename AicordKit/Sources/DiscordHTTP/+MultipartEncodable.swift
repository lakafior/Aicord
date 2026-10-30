import DiscordModels
import Foundation

extension MultipartEncodable {
  /// Encodes the multipart payload into `Data`.
  /// Returns `nil` if there are no multipart data to be encoded,
  /// in which case this should be sent as JSON.
  /// Throws encoding errors.
  @usableFromInline
  func encodeMultipart() throws -> Data? {
    guard let files = self.files, !files.isEmpty else { return nil }

    let boundary = MultipartConfiguration.boundary
    var body = Data()

    func appendString(_ string: String) {
      if let data = string.data(using: .utf8) {
        body.append(data)
      }
    }

    if Self.rawEncodable {
      for (fieldName, fieldValue) in self.rawFields {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fieldName)\"\r\n\r\n")
        appendString("\(fieldValue)\r\n")
      }
      for (index, file) in files.enumerated() {
        let fieldName = files.count == 1 && !self.rawFields.isEmpty ? "file" : "files[\(index)]"
        appendString("--\(boundary)\r\n")
        appendString(
          "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(file.filename)\"\r\n"
        )
        if let contentType = file.type {
          appendString("Content-Type: \(contentType)\r\n")
        }
        appendString("\r\n")
        body.append(file.data)
        appendString("\r\n")
      }
    } else {
      let jsonData = try DiscordGlobalConfiguration.encoder.encode(self)
      appendString("--\(boundary)\r\n")
      appendString("Content-Disposition: form-data; name=\"payload_json\"\r\n")
      appendString("Content-Type: application/json\r\n\r\n")
      body.append(jsonData)
      appendString("\r\n")

      for (index, file) in files.enumerated() {
        appendString("--\(boundary)\r\n")
        appendString(
          "Content-Disposition: form-data; name=\"files[\(index)]\"; filename=\"\(file.filename)\"\r\n"
        )
        if let contentType = file.type {
          appendString("Content-Type: \(contentType)\r\n")
        }
        appendString("\r\n")
        body.append(file.data)
        appendString("\r\n")
      }
    }

    appendString("--\(boundary)--\r\n")
    return body
  }
}

@usableFromInline
enum MultipartConfiguration {
  @usableFromInline
  static let boundary: String = {
    let random1 = (0..<5).map { _ in Int.random(in: 0..<10) }.map { "\($0)" }.joined()
    let random2 = (0..<5).map { _ in Int.random(in: 0..<10) }.map { "\($0)" }.joined()
    return random1 + "aicord" + random2
  }()
}
