import DiscordModels
import Foundation

public enum HTTPMethod: String, Sendable, Hashable {
  case GET
  case PUT
  case ACL
  case HEAD
  case POST
  case COPY
  case LOCK
  case MOVE
  case BIND
  case LINK
  case PATCH
  case TRACE
  case MKCOL
  case MERGE
  case PURGE
  case NOTIFY
  case SEARCH
  case UNLOCK
  case REBIND
  case UNBIND
  case REPORT
  case DELETE
  case UNLINK
  case OPTIONS
  case PROPFIND
  case CHECKOUT
  case PROPPATCH
  case SUBSCRIBE
  case MKCALENDAR
  case MKACTIVITY
  case UNSUBSCRIBE
}

public struct HTTPHeaders: Sendable, ExpressibleByDictionaryLiteral, Sequence, CustomStringConvertible, Equatable {
  public typealias Element = (name: String, value: String)
  public typealias Iterator = IndexingIterator<[Element]>

  @usableFromInline
  internal var storage: [Element]

  @inlinable
  public init(_ headers: [(String, String)] = []) {
    self.storage = headers.map { (name: $0.0, value: $0.1) }
  }

  @inlinable
  public init(dictionaryLiteral elements: (String, String)...) {
    self.storage = elements.map { (name: $0.0, value: $0.1) }
  }

  @inlinable
  public mutating func add(name: String, value: String) {
    self.storage.append((name: name, value: value))
  }

  @inlinable
  public mutating func replaceOrAdd(name: String, value: String) {
    let lower = name.lowercased()
    self.storage.removeAll { $0.name.lowercased() == lower }
    self.storage.append((name: name, value: value))
  }

  @inlinable
  public mutating func remove(name: String) {
    let lower = name.lowercased()
    self.storage.removeAll { $0.name.lowercased() == lower }
  }

  @inlinable
  public func first(name: String) -> String? {
    let lower = name.lowercased()
    return self.storage.first { $0.name.lowercased() == lower }?.value
  }

  @inlinable
  public subscript(name: String) -> [String] {
    let lower = name.lowercased()
    return self.storage.compactMap { $0.name.lowercased() == lower ? $0.value : nil }
  }

  @inlinable
  public subscript(canonicalForm name: String) -> [Substring] {
    let lower = name.lowercased()
    return self.storage.compactMap { $0.name.lowercased() == lower ? Substring($0.value) : nil }
  }

  @inlinable
  public var isEmpty: Bool {
    self.storage.isEmpty
  }

  @inlinable
  public func makeIterator() -> IndexingIterator<[Element]> {
    self.storage.makeIterator()
  }

  public var description: String {
    self.storage.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
  }

  public static func == (lhs: HTTPHeaders, rhs: HTTPHeaders) -> Bool {
    guard lhs.storage.count == rhs.storage.count else { return false }
    return zip(lhs.storage, rhs.storage).allSatisfy {
      $0.name.lowercased() == $1.name.lowercased() && $0.value == $1.value
    }
  }
}

public struct HTTPResponseStatus: Sendable, Hashable, CustomStringConvertible {
  public let code: UInt
  public let reasonPhrase: String

  public init(statusCode: Int, reasonPhrase: String = "") {
    self.code = UInt(clamping: statusCode)
    self.reasonPhrase =
      reasonPhrase.isEmpty
      ? HTTPURLResponse.localizedString(forStatusCode: statusCode)
      : reasonPhrase
  }

  public static let ok = HTTPResponseStatus(statusCode: 200, reasonPhrase: "OK")
  public static let created = HTTPResponseStatus(statusCode: 201, reasonPhrase: "Created")
  public static let accepted = HTTPResponseStatus(statusCode: 202, reasonPhrase: "Accepted")
  public static let noContent = HTTPResponseStatus(statusCode: 204, reasonPhrase: "No Content")
  public static let badRequest = HTTPResponseStatus(statusCode: 400, reasonPhrase: "Bad Request")
  public static let unauthorized = HTTPResponseStatus(statusCode: 401, reasonPhrase: "Unauthorized")
  public static let forbidden = HTTPResponseStatus(statusCode: 403, reasonPhrase: "Forbidden")
  public static let notFound = HTTPResponseStatus(statusCode: 404, reasonPhrase: "Not Found")
  public static let tooManyRequests = HTTPResponseStatus(statusCode: 429, reasonPhrase: "Too Many Requests")
  public static let internalServerError = HTTPResponseStatus(statusCode: 500, reasonPhrase: "Internal Server Error")
  public static let badGateway = HTTPResponseStatus(statusCode: 502, reasonPhrase: "Bad Gateway")
  public static let serviceUnavailable = HTTPResponseStatus(statusCode: 503, reasonPhrase: "Service Unavailable")
  public static let gatewayTimeout = HTTPResponseStatus(statusCode: 504, reasonPhrase: "Gateway Timeout")

  public var description: String {
    "\(code) \(reasonPhrase)"
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(code)
  }

  public static func == (lhs: HTTPResponseStatus, rhs: HTTPResponseStatus) -> Bool {
    lhs.code == rhs.code
  }
}

public struct HTTPVersion: Sendable, Hashable, CustomStringConvertible {
  public let major: Int
  public let minor: Int

  public init(major: Int, minor: Int) {
    self.major = major
    self.minor = minor
  }

  public static let http1_1 = HTTPVersion(major: 1, minor: 1)
  public static let http2 = HTTPVersion(major: 2, minor: 0)
  public static let http3 = HTTPVersion(major: 3, minor: 0)

  public var description: String {
    "HTTP/\(major).\(minor)"
  }
}

extension String {
  @inlinable
  public init(buffer: Data) {
    self = String(decoding: buffer, as: UTF8.self)
  }
}

public struct DiscordHTTPRequest: Sendable {
  /// The endpoint to send the request to.
  public let endpoint: AnyEndpoint
  /// The query parameters of the request.
  public let queries: [(String, String?)]
  /// The extra headers of the request.
  public let headers: HTTPHeaders

  public init(
    to endpoint: UserAPIEndpoint,
    queries: [(String, String?)] = [],
    headers: HTTPHeaders = [:]
  ) {
    self.endpoint = .userApi(endpoint)
    self.queries = queries
    self.headers = headers
  }

  public init(
    to endpoint: APIEndpoint,
    queries: [(String, String?)] = [],
    headers: HTTPHeaders = [:]
  ) {
    self.endpoint = .api(endpoint)
    self.queries = queries
    self.headers = headers
  }

  public init(
    to endpoint: CDNEndpoint,
    queries: [(String, String?)] = [],
    headers: HTTPHeaders = [:]
  ) {
    self.endpoint = .cdn(endpoint)
    self.queries = queries
    self.headers = headers
  }

  public init(to endpoint: LooseEndpoint) {
    self.endpoint = .loose(endpoint)
    self.queries = []
    self.headers = [:]
  }
}

/// Represents a raw Discord HTTP response.
public struct DiscordHTTPResponse: Sendable, CustomStringConvertible {
  /// Remote host of the request.
  public let host: String
  /// Response HTTP status.
  public let status: HTTPResponseStatus
  /// Response HTTP version.
  public let version: HTTPVersion
  /// Response HTTP headers.
  public let headers: HTTPHeaders
  /// Response body.
  public let body: Data?

  public init(
    host: String,
    status: HTTPResponseStatus,
    version: HTTPVersion = .http2,
    headers: HTTPHeaders = [:],
    body: Data? = nil
  ) {
    self.host = host
    self.status = status
    self.version = version
    self.headers = headers
    self.body = body
  }

  public var description: String {
    "DiscordHTTPResponse("
      + "host: \(host), "
      + "status: \(status), "
      + "version: \(version), "
      + "headers: \(headers), "
      + "body: \(body.map({ String(buffer: $0) }) ?? "nil")"
      + ")"
  }

  /// Throws an error if the response does not indicate success.
  @inlinable
  public func guardSuccess() throws {
    guard (200..<300).contains(self.status.code) else {
      throw DiscordHTTPError.badStatusCode(self)
    }
  }

  /// Makes sure the response is a success response, or tries to find a `JSONError`
  /// so you have a chance to process the error and try to recover.
  ///
  /// Returns `.none` if the response is a success response.
  /// Returns `.jsonError` if it's a recognizable error.
  /// Otherwise returns `.badStatusCode`.
  @inlinable
  public func asError() -> DiscordHTTPErrorResponse? {
    if (200..<300).contains(self.status.code) {
      return .none
    } else {
      if let error = try? self._decode(as: JSONError.self) {
        return .jsonError(error)
      } else {
        return .badStatusCode(self)
      }
    }
  }

  /// Decodes the response into `JSONError` or throws.
  @inlinable
  public func decodeJSONError() throws -> JSONError {
    if (200..<300).contains(self.status.code) {
      throw DiscordHTTPError.cantDecodeJSONErrorFromSuccessfulResponse(self)
    } else {
      return try self._decode(as: JSONError.self)
    }
  }

  /// Decodes the response into an arbitrary type.
  @inlinable
  public func decode<D: Decodable>(as _: D.Type = D.self) throws -> D {
    try self.guardSuccess()
    return try self._decode()
  }

  /// Doesn't check for success of the response
  @usableFromInline
  func _decode<D: Decodable>(as _: D.Type = D.self) throws -> D {
    if let data = body, !data.isEmpty {
      do {
        return try DiscordGlobalConfiguration.decoder.decode(D.self, from: data)
      } catch {
        throw DiscordHTTPError.decodingError(
          typeName: Swift._typeName(D.self),
          response: self,
          error: error
        )
      }
    } else {
      throw DiscordHTTPError.emptyBody(self)
    }
  }
}

/// Represents a Discord HTTP response for endpoints that return some data in the body.
public struct DiscordClientResponse<C>: Sendable, CustomStringConvertible
where C: Codable {
  /// The raw http response.
  public let httpResponse: DiscordHTTPResponse

  public init(httpResponse: DiscordHTTPResponse) {
    self.httpResponse = httpResponse
  }

  public var description: String {
    "DiscordClientResponse<\(Swift._typeName(C.self, qualified: true))>(httpResponse: \(self.httpResponse))"
  }

  /// Throws an error if the response does not indicate success.
  @inlinable
  public func guardSuccess() throws {
    try self.httpResponse.guardSuccess()
  }

  @inlinable
  public func asError() -> DiscordHTTPErrorResponse? {
    self.httpResponse.asError()
  }

  /// Decodes the response into `JSONError` or throws.
  @inlinable
  public func decodeJSONError() throws -> JSONError {
    try self.httpResponse.decodeJSONError()
  }

  /// Decodes the response.
  @inlinable
  public func decode() throws -> C {
    try httpResponse.decode(as: C.self)
  }
}

/// Represents a Discord HTTP response for CDN endpoints.
public struct DiscordCDNResponse: Sendable, CustomStringConvertible {
  /// The raw http response.
  public let httpResponse: DiscordHTTPResponse
  /// The fallback name for the file that will be decoded.
  public let fallbackFileName: String

  public init(httpResponse: DiscordHTTPResponse, fallbackFileName: String) {
    self.httpResponse = httpResponse
    self.fallbackFileName = fallbackFileName
  }

  public var description: String {
    "DiscordCDNResponse(httpResponse: \(self.httpResponse), fallbackFileName: \"\(self.fallbackFileName)\")"
  }

  @inlinable
  public func guardSuccess() throws {
    try self.httpResponse.guardSuccess()
  }

  @inlinable
  public func getFile(overrideName: String? = nil) throws -> RawFile {
    try self.guardSuccess()
    guard let body = self.httpResponse.body else {
      throw DiscordHTTPError.emptyBody(httpResponse)
    }
    guard
      let contentType = self.httpResponse.headers.first(name: "Content-Type")
    else {
      throw DiscordHTTPError.noContentTypeHeader(httpResponse)
    }
    let name = overrideName ?? fallbackFileName
    return RawFile(data: body, nameNoExtension: name, contentType: contentType)
  }
}

/// Represents a possible Discord HTTP error.
/// Is conformed to `Error` so users can conveniently throw it.
public enum DiscordHTTPErrorResponse: Error, CustomStringConvertible {
  /// The error is in a recognizable format and you can attempt to recover from it.
  case jsonError(JSONError)
  /// The error was not in a recognizable format, but the status code still indicates a failure.
  case badStatusCode(DiscordHTTPResponse)

  public var description: String {
    switch self {
    case .jsonError(let jsonError):
      return "DiscordHTTPErrorResponse.jsonError(\(jsonError))"
    case .badStatusCode(let response):
      return "DiscordHTTPErrorResponse.badStatusCode(\(response))"
    }
  }
}

public enum DiscordHTTPError: Error, CustomStringConvertible {
  /// Your rate-limits have been exhausted for '\(url)'. Try to send less messages or send at a slower pace.
  case rateLimited(url: String)
  /// Discord responded with a non-200 status code.
  case badStatusCode(DiscordHTTPResponse)
  /// Discord responded with a 200 status code but you requested DiscordBM to decode a `JSONError`.
  case cantDecodeJSONErrorFromSuccessfulResponse(DiscordHTTPResponse)
  /// The response body was unexpectedly empty.
  case emptyBody(DiscordHTTPResponse)
  /// Discord didn't send a Content-Type header. See if they mentions any errors in the response.
  case noContentTypeHeader(DiscordHTTPResponse)
  /// The endpoint requires an authentication header but you have not passed authentication info in the 'DefaultDiscordClient' initializer.
  case authenticationHeaderRequired(request: DiscordHTTPRequest)
  /// Could not decode to type '\(typeName)'. Make sure your Codable types match the response that Discord sends.
  case decodingError(
    typeName: String, response: DiscordHTTPResponse, error: any Error)
  /// Discord only accepts one of these query parameters at a time.
  case queryParametersMutuallyExclusive(queries: [(String, String)])
  /// The query parameter '\(name)' with a value of '\(value ?? "nil")' is out of the Discord-acceptable bounds of \(lowerBound)...\(upperBound).
  case queryParameterOutOfBounds(
    name: String, value: String?, lowerBound: Int, upperBound: Int)

  public var description: String {
    switch self {
    case .rateLimited(let url):
      return "DiscordHTTPError.rateLimited(url: \(url))"
    case .badStatusCode(let response):
      return "DiscordHTTPError.badStatusCode(\(response))"
    case .cantDecodeJSONErrorFromSuccessfulResponse(let response):
      return
        "DiscordHTTPError.cantDecodeJSONErrorFromSuccessfulResponse(\(response))"
    case .emptyBody(let response):
      return "DiscordHTTPError.emptyBody(\(response))"
    case .noContentTypeHeader(let response):
      return "DiscordHTTPError.noContentTypeHeader(\(response))"
    case .authenticationHeaderRequired(let request):
      return
        "DiscordHTTPError.authenticationHeaderRequired(request: \(request))"
    case .decodingError(let typeName, let response, let error):
      return
        "DiscordHTTPError.decodingError(typeName: \(typeName), response: \(response), error: \(error))"
    case .queryParametersMutuallyExclusive(let queries):
      return
        "DiscordHTTPError.queryParametersMutuallyExclusive(queries: \(queries))"
    case .queryParameterOutOfBounds(let name, let value, let lowerBound, let upperBound):
      return
        "DiscordHTTPError.queryParameterOutOfBounds(name: \(name), value: \(value ?? "nil"), lowerBound: \(lowerBound), upperBound: \(upperBound))"
    }
  }
}
