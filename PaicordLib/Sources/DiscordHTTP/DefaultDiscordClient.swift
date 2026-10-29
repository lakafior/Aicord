import DiscordModels
import Foundation
import Logging
import Synchronization

public struct DefaultDiscordClient: DiscordClient {
  public let session: URLSession
  public let authentication: AuthenticationHeader
  public let appId: ApplicationSnowflake?
  public let configuration: ClientConfiguration
  public let logger = DiscordGlobalConfiguration.makeLogger(
    "DefaultDiscordClient"
  )

  public var captchaCallback: CaptchaChallengeHandler? = nil
  public var mfaCallback: MFAVerificationHandler? = nil

  public var userAgent: String {
    if self.authentication.userMode {
      return SuperProperties.useragent(ws: false)!
    } else {
      return "DiscordBM (https://github.com/discordbm/discordbm, 1.0.0)"
    }
  }

  /// Use `getCache()` to get the appropriate cache.

  /// The cache used for requests that require an auth header.
  @usableFromInline
  let _authCache: ClientCache

  /// Stores cookies
  @usableFromInline
  let _cookieStore: CookieStore = .init()

  @usableFromInline
  static let requestIdGenerator = Atomic<UInt>(0)

  @usableFromInline
  static func nextRequestId() -> UInt {
    requestIdGenerator.wrappingAdd(1, ordering: .relaxed).newValue
  }

  /// The fact that this could be used by multiple different `DiscordClient`s with
  /// different `token`s should not matter because buckets are random anyway.
  @usableFromInline
  static let rateLimiter = HTTPRateLimiter(label: "DiscordClientRateLimiter")

  public init(
    session: URLSession = .shared,
    token: Secret,
    appId: ApplicationSnowflake? = nil,
    configuration: ClientConfiguration = .init(),
    captchaCallback: CaptchaChallengeHandler? = nil,
    mfaCallback: MFAVerificationHandler? = nil
  ) async {
    self.captchaCallback = captchaCallback
    self.mfaCallback = mfaCallback
    self.session = session
    self.authentication = .botToken(token)
    self.appId = appId ?? self.authentication.extractAppIdIfAvailable()
    self.configuration = configuration
    self._authCache = await ClientCacheStorage.shared.cache(
      for: self.authentication
    )
  }

  public init(
    session: URLSession = .shared,
    token: String,
    appId: ApplicationSnowflake? = nil,
    configuration: ClientConfiguration = .init()
  ) async {
    self.session = session
    self.authentication = .botToken(Secret(token))
    self.appId = appId ?? self.authentication.extractAppIdIfAvailable()
    self.configuration = configuration
    self._authCache = await ClientCacheStorage.shared.cache(
      for: self.authentication
    )
  }

  public init(
    session: URLSession = .shared,
    header: AuthenticationHeader,
    appId: ApplicationSnowflake? = nil,
    configuration: ClientConfiguration = .init(),
    captchaCallback: CaptchaChallengeHandler? = nil,
    mfaCallback: MFAVerificationHandler? = nil
  ) async {
    self.captchaCallback = captchaCallback
    self.mfaCallback = mfaCallback
    self.session = session
    self.authentication = header
    self.appId = appId ?? self.authentication.extractAppIdIfAvailable()
    self.configuration = configuration
    self._authCache = await ClientCacheStorage.shared.cache(
      for: self.authentication
    )
  }

  public init(
    session: URLSession = .shared,
    oAuthToken: Secret,
    appId: ApplicationSnowflake? = nil,
    configuration: ClientConfiguration = .init()
  ) async {
    self.session = session
    self.authentication = .oAuthToken(oAuthToken)
    self.appId = appId
    self.configuration = configuration
    self._authCache = await ClientCacheStorage.shared.cache(
      for: self.authentication
    )
  }

  public init(
    session: URLSession = .shared,
    oAuthToken: String,
    appId: ApplicationSnowflake? = nil,
    configuration: ClientConfiguration = .init()
  ) async {
    self.session = session
    self.authentication = .oAuthToken(Secret(oAuthToken))
    self.appId = appId
    self.configuration = configuration
    self._authCache = await ClientCacheStorage.shared.cache(
      for: self.authentication
    )
  }

  public init(
    session: URLSession = .shared,
    authentication: AuthenticationHeader,
    appId: ApplicationSnowflake? = nil,
    configuration: ClientConfiguration = .init()
  ) async {
    self.session = session
    self.authentication = authentication
    self.appId = appId ?? self.authentication.extractAppIdIfAvailable()
    self.configuration = configuration
    self._authCache = await ClientCacheStorage.shared.cache(
      for: self.authentication
    )
  }

  public init(
    session: URLSession = .shared,
    configuration: ClientConfiguration = .init(),
    captchaCallback: CaptchaChallengeHandler? = nil,
    mfaCallback: MFAVerificationHandler? = nil
  ) {
    self.captchaCallback = captchaCallback
    self.mfaCallback = mfaCallback
    self.session = session
    self.authentication = captchaCallback == nil ? .none : .userNone
    self.configuration = configuration
    self._authCache = .global
    self.appId = nil
  }

  @inlinable
  func checkRateLimitsAllowRequest(
    to endpoint: AnyEndpoint,
    requestId: UInt,
    retriesSoFar: Int
  ) async throws {
    switch await Self.rateLimiter.shouldRequest(to: endpoint) {
    case .true: return
    case .false:
      /// `HTTPRateLimiter` already logs this.
      throw DiscordHTTPError.rateLimited(url: "\(endpoint.urlDescription)")
    case .after(let after):
      /// If we make the request, we'll get 429-ed. So we can just assume the status is 429.
      if self.configuration.shouldRetry(
        status: .tooManyRequests,
        retriesSoFar: retriesSoFar,
        challengeSolved: false
      ) {
        logger.debug(
          "HTTP bucket is exhausted. Will wait before making the request",
          metadata: [
            "wait-time": .stringConvertible(after),
            "retriesWithoutThis": .stringConvertible(retriesSoFar),
            "endpoint": .stringConvertible(endpoint.urlDescription),
            "request-id": .stringConvertible(requestId),
          ]
        )
        let nanos = UInt64(after * 1_000_000_000)
        try await Task.sleep(for: .nanoseconds(nanos))
        await Self.rateLimiter.addGlobalRateLimitRecord()
      } else {
        logger.warning(
          "HTTP bucket is exhausted. Retry policy does not allow retry",
          metadata: [
            "solution":
              "Make requests slower or increase 'configuration.retryPolicy.backoff.basedOnHeaders.maxAllowed'",
            "wait-time": .stringConvertible(after),
            "retriesWithoutThis": .stringConvertible(retriesSoFar),
            "endpoint": .stringConvertible(endpoint.urlDescription),
            "request-id": .stringConvertible(requestId),
          ]
        )
        throw DiscordHTTPError.rateLimited(url: "\(endpoint.urlDescription)")
      }
    }
  }

  @inlinable
  func includeInRateLimits(
    endpoint: AnyEndpoint,
    headers: HTTPHeaders,
    status: HTTPResponseStatus
  ) async {
    await Self.rateLimiter.include(
      endpoint: endpoint,
      headers: headers,
      status: status
    )
  }

  @inlinable
  func isCacheable(identity: CacheableEndpointIdentity?) -> (
    CacheableEndpointIdentity, Duration
  )? {
    guard let identity,
      let ttl = self.configuration.cachingBehavior.getTTL(for: identity)
    else { return nil }
    return (identity, ttl)
  }

  @inlinable
  func getFromCache(
    identity: CacheableEndpointIdentity?,
    requiresAuthHeader: Bool,
    parameters: [String],
    queries: [(String, String?)]
  ) async -> DiscordHTTPResponse? {
    guard let (identity, _) = self.isCacheable(identity: identity) else {
      return nil
    }
    return await self.getCache(
      requiresAuthHeader: requiresAuthHeader
    ).get(
      item: .init(
        identity: identity,
        parameters: parameters,
        queries: queries
      )
    )
  }

  @inlinable
  func saveInCache(
    response: DiscordHTTPResponse,
    identity: CacheableEndpointIdentity?,
    requiresAuthHeader: Bool,
    parameters: [String],
    queries: [(String, String?)]
  ) async {
    guard (200..<300).contains(response.status.code),
      let (identity, ttl) = self.isCacheable(identity: identity)
    else {
      return
    }
    await self.getCache(requiresAuthHeader: requiresAuthHeader).save(
      response: response,
      item: .init(
        identity: identity,
        parameters: parameters,
        queries: queries
      ),
      ttl: ttl
    )
    logger.debug(
      "Saved response in cache",
      metadata: [
        "endpointIdentity": .stringConvertible(identity),
        "queries": .stringConvertible(queries),
      ]
    )
  }

  @inlinable
  func unlockRequestsInCache(
    identity: CacheableEndpointIdentity?,
    requiresAuthHeader: Bool,
    parameters: [String],
    queries: [(String, String?)]
  ) async {
    guard let identity = identity else { return }
    await self.getCache(requiresAuthHeader: requiresAuthHeader).unlockRequests(
      forItem: .init(
        identity: identity,
        parameters: parameters,
        queries: queries
      )
    )
  }

  @usableFromInline
  func execute(
    url: String,
    method: HTTPMethod,
    headers: HTTPHeaders,
    body: Data? = nil
  ) async throws -> DiscordHTTPResponse {
    guard let parsedURL = URL(string: url) else {
      throw URLError(.badURL)
    }
    var urlRequest = URLRequest(url: parsedURL)
    urlRequest.httpMethod = method.rawValue
    urlRequest.timeoutInterval = configuration.requestTimeoutInterval
    urlRequest.httpShouldHandleCookies = false
    for (name, value) in headers {
      urlRequest.addValue(value, forHTTPHeaderField: name)
    }
    urlRequest.httpBody = body

    let (data, urlResponse) = try await self.session.data(for: urlRequest)
    let httpResponse = urlResponse as? HTTPURLResponse
    let statusCode = httpResponse?.statusCode ?? 200
    var responseHeaders = HTTPHeaders()
    if let headerFields = httpResponse?.allHeaderFields {
      for (key, value) in headerFields {
        responseHeaders.add(name: String(describing: key), value: String(describing: value))
      }
    }

    return DiscordHTTPResponse(
      host: parsedURL.host ?? "discord.com",
      status: HTTPResponseStatus(statusCode: statusCode),
      version: .http2,
      headers: responseHeaders,
      body: data.isEmpty ? nil : data
    )
  }

  /// Waits for the next retry if needed, and increases the retry counter.
  @inlinable
  func waitForRetryAndIncreaseRetryCount(
    retriesSoFar: inout Int,
    headers: HTTPHeaders,
    requestId: UInt
  ) async throws {
    let retryWait = self.configuration.waitTimeBeforeRetry(
      retriesSoFar: retriesSoFar,
      headers: headers
    )
    logger.debug(
      "Will soon retry a request",
      metadata: [
        "request-id": .stringConvertible(requestId),
        "retriesWithoutThis": .stringConvertible(retriesSoFar),
        "waitSecondsBeforeRetry": .stringConvertible(retryWait ?? 0),
      ]
    )
    if let retryWait {
      try await Task.sleep(for: .nanoseconds(UInt64(retryWait * 1_000_000_000)))
    }
    retriesSoFar += 1
    logger.trace(
      "Will retry a request right now",
      metadata: [
        "request-id": .stringConvertible(requestId),
        "retriesWithoutThis": .stringConvertible(retriesSoFar),
      ]
    )
  }

  /// Returns an appropriate `ClientCache`.
  @usableFromInline
  func getCache(requiresAuthHeader: Bool) -> ClientCache {
    if requiresAuthHeader {
      return self._authCache
    } else {
      return .global
    }
  }

  /// Sends requests and retries if needed.
  @inlinable
  func sendWithRetries(
    request req: DiscordHTTPRequest,
    sendRequest: (CacheableEndpointIdentity?, Int, UInt, HTTPHeaders?)
      async throws -> (
        DiscordHTTPResponse, Bool
      )
  ) async throws -> DiscordHTTPResponse {
    let identity = CacheableEndpointIdentity(endpoint: req.endpoint)
    let requestId = Self.nextRequestId()

    var retriesSoFar = 0
    var cached = false
    var response: DiscordHTTPResponse
    var headers: HTTPHeaders

    do {
      (response, cached) = try await sendRequest(
        identity,
        retriesSoFar,
        requestId,
        nil
      )
      headers = response.headers

      await _cookieStore.checkIncomingHeaders(headers)

      var challengeSolved = false

      if let captchaData = extractCaptchaChallenge(from: response) {
        if let captchaHeaderData = await captchaCallback?(captchaData) {
          headers.replaceOrAdd(
            name: "X-Captcha-Key",
            value: captchaHeaderData.solutionToken
          )
          if let sessionID = captchaHeaderData.captchaSessionId {
            headers.replaceOrAdd(
              name: "X-Captcha-Session-Id",
              value: sessionID
            )
          }
          if let rqToken = captchaHeaderData.captchaRqtoken {
            headers.replaceOrAdd(
              name: "X-Captcha-Rqtoken",
              value: rqToken
            )
          }
          challengeSolved = true
        }
      }

      if let mfaHeader = extractMFAVerification(from: response) {
        if let mfaResponse = await mfaCallback?(mfaHeader) {
          headers.replaceOrAdd(
            name: "X-Discord-MFA-Authorization",
            value: mfaResponse.token
          )
          challengeSolved = true
        }
      }

      while configuration.shouldRetry(
        status: response.status,
        retriesSoFar: retriesSoFar,
        challengeSolved: challengeSolved
      ) {
        try await waitForRetryAndIncreaseRetryCount(
          retriesSoFar: &retriesSoFar,
          headers: headers,
          requestId: requestId
        )
        (response, cached) = try await sendRequest(
          identity,
          retriesSoFar,
          requestId,
          headers
        )
        headers = response.headers
      }
    } catch {
      if !cached {
        await self.unlockRequestsInCache(
          identity: identity,
          requiresAuthHeader: req.endpoint.requiresAuthorizationHeader,
          parameters: req.endpoint.parameters,
          queries: req.queries
        )
      }

      throw error
    }

    if !cached {
      await self.saveInCache(
        response: response,
        identity: identity,
        requiresAuthHeader: req.endpoint.requiresAuthorizationHeader,
        parameters: req.endpoint.parameters,
        queries: req.queries
      )
      await self.unlockRequestsInCache(
        identity: identity,
        requiresAuthHeader: req.endpoint.requiresAuthorizationHeader,
        parameters: req.endpoint.parameters,
        queries: req.queries
      )
    }

    return response
  }

  @inlinable
  public func send(request req: DiscordHTTPRequest) async throws
    -> DiscordHTTPResponse
  {
    try await self.sendWithRetries(request: req) {
      identity,
      retryCounter,
      requestId,
      overrideHeaders in

      if let cached = await self.getFromCache(
        identity: identity,
        requiresAuthHeader: req.endpoint.requiresAuthorizationHeader,
        parameters: req.endpoint.parameters,
        queries: req.queries
      ) {
        logger.debug(
          "Got cached response",
          metadata: [
            "endpoint": .string(req.endpoint.urlDescription),
            "queries": .stringConvertible(req.queries),
            "retry": .stringConvertible(retryCounter),
          ]
        )
        return (cached, true)
      }

      try await self.checkRateLimitsAllowRequest(
        to: req.endpoint,
        requestId: requestId,
        retriesSoFar: retryCounter
      )
      var headers = overrideHeaders ?? req.headers
      headers.add(name: "User-Agent", value: userAgent)
      if authentication.userMode {
        try self.addUserHeaders(&headers)
        await _cookieStore.applyCookies(to: &headers)
      }
      if req.endpoint.requiresAuthorizationHeader {
        try self.authentication.addHeader(
          headers: &headers,
          request: req
        )
      }

      let fullURL = req.endpoint.url + req.queries.makeForURLQuery()
      let method = req.endpoint.httpMethod

      logger.debug(
        "Will send a request to Discord",
        metadata: [
          "url": .stringConvertible(
            req.endpoint.urlDescription + req.queries.makeForURLQuery()
          ),
          "method": .string(method.rawValue),
          "retry": .stringConvertible(retryCounter),
          "request-id": .stringConvertible(requestId),
        ]
      )
      let response = try await self.execute(
        url: fullURL,
        method: method,
        headers: headers
      )
      logger.debug(
        "Received a response from Discord",
        metadata: [
          "response": .stringConvertible(response),
          "retry": .stringConvertible(retryCounter),
          "request-id": .stringConvertible(requestId),
        ]
      )

      await self.includeInRateLimits(
        endpoint: req.endpoint,
        headers: response.headers,
        status: response.status
      )

      return (response, false)
    }
  }

  @inlinable
  public func send<E: Sendable & Encodable & ValidatablePayload>(
    request req: DiscordHTTPRequest,
    payload: E
  ) async throws -> DiscordHTTPResponse {
    if configuration.performValidations {
      try payload.validate().throw(model: payload)
    }

    return try await self.sendWithRetries(request: req) {
      identity,
      retryCounter,
      requestId,
      overrideHeaders in

      let identity = CacheableEndpointIdentity(endpoint: req.endpoint)
      if let cached = await self.getFromCache(
        identity: identity,
        requiresAuthHeader: req.endpoint.requiresAuthorizationHeader,
        parameters: req.endpoint.parameters,
        queries: req.queries
      ) {
        logger.debug(
          "Got cached response",
          metadata: [
            "endpoint": .string(req.endpoint.urlDescription),
            "queries": .stringConvertible(req.queries),
            "retry": .stringConvertible(retryCounter),
          ]
        )
        return (cached, true)
      }

      try await self.checkRateLimitsAllowRequest(
        to: req.endpoint,
        requestId: requestId,
        retriesSoFar: retryCounter
      )

      let data = try DiscordGlobalConfiguration.encoder.encode(payload)
      var headers = overrideHeaders ?? req.headers
      headers.add(name: "User-Agent", value: userAgent)
      if authentication.userMode {
        try self.addUserHeaders(&headers)
        await _cookieStore.applyCookies(to: &headers)
      }
      headers.replaceOrAdd(
        name: "Content-Type",
        value: "application/json"
      )
      if req.endpoint.requiresAuthorizationHeader {
        try self.authentication.addHeader(
          headers: &headers,
          request: req
        )
      }

      let fullURL = req.endpoint.url + req.queries.makeForURLQuery()
      let method = req.endpoint.httpMethod

      logger.debug(
        "Will send a request to Discord",
        metadata: [
          "body": .string(String(data: data, encoding: .utf8) ?? "nil"),
          "url": .stringConvertible(
            req.endpoint.urlDescription + req.queries.makeForURLQuery()
          ),
          "method": .string(method.rawValue),
          "retry": .stringConvertible(retryCounter),
          "request-id": .stringConvertible(requestId),
        ]
      )
      let response = try await self.execute(
        url: fullURL,
        method: method,
        headers: headers,
        body: data
      )
      logger.debug(
        "Received a response from Discord",
        metadata: [
          "response": .stringConvertible(response),
          "retry": .stringConvertible(retryCounter),
          "request-id": .stringConvertible(requestId),
        ]
      )

      await self.includeInRateLimits(
        endpoint: req.endpoint,
        headers: response.headers,
        status: response.status
      )

      return (response, false)
    }
  }

  @inlinable
  public func sendMultipart<
    E: Sendable & MultipartEncodable & ValidatablePayload
  >(
    request req: DiscordHTTPRequest,
    payload: E
  ) async throws -> DiscordHTTPResponse {
    if configuration.performValidations {
      try payload.validate().throw(model: payload)
    }

    return try await self.sendWithRetries(request: req) {
      identity,
      retryCounter,
      requestId,
      overrideHeaders in

      let identity = CacheableEndpointIdentity(endpoint: req.endpoint)
      if let cached = await self.getFromCache(
        identity: identity,
        requiresAuthHeader: req.endpoint.requiresAuthorizationHeader,
        parameters: req.endpoint.parameters,
        queries: req.queries
      ) {
        logger.debug(
          "Got cached response",
          metadata: [
            "endpoint": .string(req.endpoint.urlDescription),
            "queries": .stringConvertible(req.queries),
            "retry": .stringConvertible(retryCounter),
          ]
        )
        return (cached, true)
      }

      try await self.checkRateLimitsAllowRequest(
        to: req.endpoint,
        requestId: requestId,
        retriesSoFar: retryCounter
      )

      let contentType: String
      let bodyData: Data
      if let multipart = try payload.encodeMultipart() {
        contentType =
          "multipart/form-data; boundary=\(MultipartConfiguration.boundary)"
        bodyData = multipart
      } else {
        contentType = "application/json"
        bodyData = try DiscordGlobalConfiguration.encoder.encode(payload)
      }
      var headers = overrideHeaders ?? req.headers
      headers.add(name: "User-Agent", value: userAgent)
      if authentication.userMode {
        try self.addUserHeaders(&headers)
        await _cookieStore.applyCookies(to: &headers)
      }
      headers.replaceOrAdd(name: "Content-Type", value: contentType)
      if req.endpoint.requiresAuthorizationHeader {
        try self.authentication.addHeader(
          headers: &headers,
          request: req
        )
      }

      let fullURL = req.endpoint.url + req.queries.makeForURLQuery()
      let method = req.endpoint.httpMethod

      logger.debug(
        "Will send a request to Discord",
        metadata: [
          "body": .string(String(buffer: bodyData)),
          "url": .stringConvertible(
            req.endpoint.urlDescription + req.queries.makeForURLQuery()
          ),
          "method": .string(method.rawValue),
          "retry": .stringConvertible(retryCounter),
          "request-id": .stringConvertible(requestId),
        ]
      )
      let response = try await self.execute(
        url: fullURL,
        method: method,
        headers: headers,
        body: bodyData
      )
      logger.debug(
        "Received a response from Discord",
        metadata: [
          "response": .stringConvertible(response),
          "retry": .stringConvertible(retryCounter),
          "request-id": .stringConvertible(requestId),
        ]
      )

      await self.includeInRateLimits(
        endpoint: req.endpoint,
        headers: response.headers,
        status: response.status
      )

      return (response, false)
    }
  }

  @usableFromInline
  func extractCaptchaChallenge(from response: DiscordHTTPResponse)
    -> CaptchaChallengeData?
  {
    guard response.status.code == 400,
      let data = response.body,
      let json = try? JSONSerialization.jsonObject(with: data, options: [])
        as? [String: Any],
      let captchaService = json["captcha_service"] as? String,
      let captchaKey = json["captcha_key"] as? [String]
    else { return nil }

    return CaptchaChallengeData(
      captchaKey: captchaKey,
      captchaService: captchaService,
      captchaSiteKey: json["captcha_sitekey"] as? String,
      captchaSessionId: json["captcha_session_id"] as? String,
      captchaRqdata: json["captcha_rqdata"] as? String,
      captchaRqtoken: json["captcha_rqtoken"] as? String,
      shouldServeInvisible: json["should_serve_invisible"] as? Bool
    )
  }

  @usableFromInline
  func extractMFAVerification(from response: DiscordHTTPResponse)
    -> MFAVerificationData?
  {
    guard response.status.code == 401,
      let data = response.body,
      let json = try? JSONSerialization.jsonObject(with: data, options: [])
        as? [String: Any],
      json["code"] as? Int == 60003,
      let mfa = json["mfa"] as? [String: Any],
      let mfaData = try? JSONSerialization.data(withJSONObject: mfa),
      let mfaRequest = try? DiscordGlobalConfiguration.decoder.decode(
        MFAVerificationData.self,
        from: mfaData
      )
    else { return nil }

    return mfaRequest
  }

  @inlinable
  func addUserHeaders(_ headers: inout HTTPHeaders) throws {
    let superProperties = SuperProperties.GenerateSuperPropertiesHeader()
    let locale = SuperProperties.GenerateLocaleHeader()
    let timezone = SuperProperties.GenerateTimezoneHeader()
    headers.add(name: "X-Super-Properties", value: superProperties)
    headers.add(name: "X-Discord-Locale", value: locale)
    headers.add(name: "X-Discord-Timezone", value: timezone)
    headers.add(name: "X-Debug-Options", value: "bugReporterEnabled")

    headers.add(name: "Accept", value: "*/*")
    headers.add(name: "Accept-Language", value: locale)
    headers.add(name: "Priority", value: "u=1, i")

    #if os(macOS)
      headers.add(name: "Sec-Fetch-Dest", value: "empty")
      headers.add(name: "Sec-Fetch-Mode", value: "cors")
      headers.add(name: "Sec-Fetch-Site", value: "same-origin")
      headers.add(name: "Sec-CH-UA-Mobile", value: "?0")
      headers.add(name: "Sec-CH-UA-Platform", value: "\"macOS\"")
      headers.add(
        name: "Sec-CH-UA",
        value:
          "\"Not)A;Brand\";v=\"8\", \"Chromium\";v=\"\(SuperProperties.chromeMajorVer())\""
      )
      headers.add(name: "Referer", value: "https://discord.com/channels/@me")
      headers.add(name: "Origin", value: "https://discord.com")
    #elseif os(iOS)
      // shared headers are sufficient on iOS
    #endif
  }
}
