//
//  OpenAICompatibleClient.swift
//  AicordKit
//
//  The chat completions and model list endpoints shared by OpenAI, Mistral,
//  OpenRouter and local servers such as Ollama and LM Studio.
//

import Foundation

public struct OpenAICompatibleClient: Sendable {
  public var baseURL: URL
  public var apiKey: String?
  public var model: String
  public var session: URLSession

  public init(baseURL: URL, apiKey: String?, model: String, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.model = model
    self.session = session
  }

  /// The API root from what the user typed: `https` added when missing,
  /// trailing slashes and a pasted `/chat/completions` taken off, and `/v1`
  /// added when the path names no version.
  public static func normalizedBaseURL(_ text: String) -> URL? {
    var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !string.isEmpty else { return nil }
    if !string.contains("://") { string = "https://" + string }
    while string.hasSuffix("/") { string.removeLast() }
    for suffix in ["/chat/completions", "/models"] where string.hasSuffix(suffix) {
      string.removeLast(suffix.count)
    }
    guard var components = URLComponents(string: string), let host = components.host,
      !host.isEmpty, components.scheme == "https" || components.scheme == "http"
    else { return nil }
    let path = components.path
    let hasVersion = path.split(separator: "/").contains {
      $0.count >= 2 && $0.first == "v" && $0.dropFirst().allSatisfy(\.isNumber)
    }
    if !hasVersion { components.path = path + "/v1" }
    return components.url
  }

  // MARK: Requests

  public struct Message: Codable, Sendable, Equatable {
    public var role: String
    public var content: Content

    public init(role: String, content: Content) {
      self.role = role
      self.content = content
    }

    public static func system(_ text: String) -> Self { .init(role: "system", content: .text(text)) }
    public static func user(_ text: String) -> Self { .init(role: "user", content: .text(text)) }

    public enum Content: Codable, Sendable, Equatable {
      case text(String)
      case parts([Part])

      public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
      }

      public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
          self = .text(text)
        } else if let parts = try? container.decode([Part].self) {
          self = .parts(parts)
        } else {
          self = .text("")
        }
      }

      /// The text of the reply, whichever form it came in.
      public var text: String {
        switch self {
        case .text(let text): text
        case .parts(let parts): parts.compactMap(\.text).joined()
        }
      }
    }

    /// Text or an image (as a URL or a `data:` URL) in a multi-part message.
    public struct Part: Codable, Sendable, Equatable {
      public var type: String
      public var text: String?
      public var image_url: ImageURL?

      public struct ImageURL: Codable, Sendable, Equatable {
        public var url: String
      }

      public static func text(_ text: String) -> Self { .init(type: "text", text: text) }
      public static func image(url: String) -> Self {
        .init(type: "image_url", image_url: .init(url: url))
      }
    }
  }

  struct ChatRequest: Encodable {
    var model: String
    var messages: [Message]
    var temperature: Double
    var max_tokens: Int?
  }

  struct ChatResponse: Decodable {
    struct Choice: Decodable {
      var message: Message?
    }
    var choices: [Choice]?
  }

  struct ModelList: Decodable {
    struct Model: Decodable { var id: String }
    var data: [Model]?
    // Ollama's own /api/tags shape, in case a server answers with it
    var models: [Model]?
  }

  public enum ClientError: LocalizedError, Equatable {
    case http(status: Int, message: String?)
    case emptyReply
    case badResponse

    public var errorDescription: String? {
      switch self {
      case .http(let status, let message):
        let reason =
          switch status {
          case 401, 403: "The API key was refused."
          case 404: "Not found. Check the address and the model name."
          case 429: "Too many requests or no credit left."
          default: "The server answered with error \(status)."
          }
        return message.map { "\(reason) \($0)" } ?? reason
      case .emptyReply: return "The model sent an empty reply."
      case .badResponse: return "The server's reply wasn't an OpenAI-compatible response."
      }
    }
  }

  func request(path: String, body: Data? = nil) -> URLRequest {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.timeoutInterval = 120
    if let apiKey, !apiKey.isEmpty {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.httpMethod = "POST"
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  /// The model's reply to a conversation.
  public func complete(_ messages: [Message], maxTokens: Int? = nil, temperature: Double = 0.2)
    async throws -> String
  {
    let body = try JSONEncoder().encode(
      ChatRequest(model: model, messages: messages, temperature: temperature, max_tokens: maxTokens)
    )
    let data = try await send(request(path: "chat/completions", body: body))
    guard let response = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
      throw ClientError.badResponse
    }
    let text = response.choices?.first?.message?.content.text ?? ""
    let trimmed = Self.strippingReasoning(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ClientError.emptyReply }
    return trimmed
  }

  public func complete(instructions: String, prompt: String, maxTokens: Int? = nil) async throws
    -> String
  {
    try await complete([.system(instructions), .user(prompt)], maxTokens: maxTokens)
  }

  /// Model names the server offers, sorted.
  public func models() async throws -> [String] {
    let data = try await send(request(path: "models"))
    guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
      throw ClientError.badResponse
    }
    return Array(Set((list.data ?? list.models ?? []).map(\.id))).sorted()
  }

  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ClientError.badResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw ClientError.http(status: http.statusCode, message: Self.errorMessage(in: data))
    }
    return data
  }

  /// The message in an error body: `{"error": {"message": …}}`, `{"error": "…"}`
  /// or `{"message": …}` (Mistral), cut short.
  static func errorMessage(in data: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    let message =
      ((object["error"] as? [String: Any])?["message"] as? String)
      ?? (object["error"] as? String)
      ?? (object["message"] as? String)
      ?? (object["detail"] as? String)
    return message.map { String($0.prefix(200)) }
  }

  /// Reasoning models put their thinking in `<think>` tags before the answer.
  static func strippingReasoning(_ text: String) -> String {
    guard let end = text.range(of: "</think>") else { return text }
    return String(text[end.upperBound...])
  }
}
