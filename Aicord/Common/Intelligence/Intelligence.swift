//
//  Intelligence.swift
//  Aicord
//
//  Read-only language model features: where they run (Apple's on-device
//  model or an OpenAI-compatible API), their settings and the API key.
//  Nothing here ever sends anything to Discord.
//

import AicordKit
import Foundation
import FoundationModels
import Security
import SwiftUI

enum IntelligenceProvider: String, CaseIterable, Identifiable {
  case onDevice
  case api

  var id: String { rawValue }
}

enum IntelligencePreferences {
  enum Key {
    static let provider = "Intelligence.Provider"
    static let apiBase = "Intelligence.APIBase"
    static let apiModel = "Intelligence.APIModel"
    static let apiContext = "Intelligence.APIContextTokens"
    static let allowsDMs = "Intelligence.AllowsDMs"
    static let summaryLanguage = "Intelligence.SummaryLanguage"
    static let translationTarget = "Intelligence.TranslationTarget"
    static let autoTranslateLanguages = "Intelligence.AutoTranslateLanguages"
    static let importantMuted = "Intelligence.ImportantMuted"
    static let importantTopics = "Intelligence.ImportantTopics"
    static let scamWarnings = "Intelligence.ScamWarnings"
    static let imageDescriptions = "Intelligence.ImageDescriptions"
  }

  static var defaults: UserDefaults { .standard }

  static var provider: IntelligenceProvider {
    defaults.string(forKey: Key.provider).flatMap(IntelligenceProvider.init) ?? .onDevice
  }

  static var allowsDMs: Bool { defaults.bool(forKey: Key.allowsDMs) }

  /// Context window of the API model, in tokens. 32k fits most hosted models;
  /// small local models can be set lower.
  static var apiContextTokens: Int {
    let value = defaults.integer(forKey: Key.apiContext)
    return value > 0 ? value : 32_000
  }

  /// "" follows the app's language.
  static var summaryLanguageCode: String {
    defaults.string(forKey: Key.summaryLanguage) ?? ""
  }

  /// The language summaries are written in, by its English name for the prompt.
  static var summaryLanguageName: String {
    let code =
      summaryLanguageCode.isEmpty
      ? (Locale.preferredLanguages.first.map { Locale.Language(identifier: $0) }?.languageCode?
        .identifier ?? "en")
      : summaryLanguageCode
    return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
  }
}

// MARK: - API key

/// The API key lives in the keychain of this device, never in preferences.
enum IntelligenceKeychain {
  private static let service = "net.smigi.aicord.intelligence"
  private static let account = "api-key"

  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func apiKey() -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static var hasAPIKey: Bool { apiKey()?.isEmpty == false }

  @discardableResult
  static func setAPIKey(_ key: String) -> Bool {
    let data = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    let update = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if update == errSecSuccess { return true }
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
  }

  @discardableResult
  static func removeAPIKey() -> Bool {
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}

// MARK: - Model

/// Why a feature can't run, worded for the person using it.
enum IntelligenceUnavailable: LocalizedError, Equatable {
  case deviceNotEligible
  case appleIntelligenceOff
  case modelNotReady
  case onDeviceUnavailable
  case apiNotConfigured
  case directMessagesOff

  var errorDescription: String? {
    switch self {
    case .deviceNotEligible:
      "This device can't run Apple Intelligence. Choose an OpenAI-compatible API in Settings → Intelligence."
    case .appleIntelligenceOff:
      "Turn on Apple Intelligence in the system Settings, or choose an API in Settings → Intelligence."
    case .modelNotReady:
      "Apple Intelligence is still downloading its model. Try again in a while."
    case .onDeviceUnavailable:
      "Apple Intelligence isn't available here."
    case .apiNotConfigured:
      "Add the API address and model in Settings → Intelligence."
    case .directMessagesOff:
      "Intelligence is off for direct messages. You can turn it on in Settings → Intelligence."
    }
  }
}

/// A language model a feature can use, with what it can hold and where the
/// text goes.
struct IntelligenceModel: Sendable {
  enum Backend: Sendable {
    case onDevice
    case api(OpenAICompatibleClient)
  }

  let backend: Backend
  /// Tokens of prompt one call may carry.
  let tokenBudget: Int

  var isOnDevice: Bool {
    if case .onDevice = backend { return true }
    return false
  }

  /// Where messages go, for the note under each feature.
  var destination: String {
    switch backend {
    case .onDevice: String(localized: "Runs on this device. Nothing leaves it.")
    case .api(let client):
      String(localized: "Messages are sent to \(client.baseURL.host() ?? client.baseURL.absoluteString).")
    }
  }

  /// The model chosen in Settings, or why there is none. `isDirectMessage`
  /// checks the switch for DMs.
  static func current(isDirectMessage: Bool = false) -> Result<IntelligenceModel, IntelligenceUnavailable> {
    if isDirectMessage, !IntelligencePreferences.allowsDMs { return .failure(.directMessagesOff) }
    switch IntelligencePreferences.provider {
    case .onDevice:
      if let reason = onDeviceUnavailability { return .failure(reason) }
      // half the window for the messages; the rest is instructions and reply,
      // and the token estimate is rough for languages other than English
      let context = SystemLanguageModel.default.contextSize
      return .success(.init(backend: .onDevice, tokenBudget: max(1_000, context / 2)))
    case .api:
      guard let client = apiClient() else { return .failure(.apiNotConfigured) }
      let context = IntelligencePreferences.apiContextTokens
      return .success(.init(backend: .api(client), tokenBudget: max(1_000, context * 2 / 3)))
    }
  }

  static var onDeviceUnavailability: IntelligenceUnavailable? {
    switch SystemLanguageModel.default.availability {
    case .available: nil
    case .unavailable(.deviceNotEligible): .deviceNotEligible
    case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceOff
    case .unavailable(.modelNotReady): .modelNotReady
    case .unavailable: .onDeviceUnavailable
    }
  }

  static func apiClient(model: String? = nil) -> OpenAICompatibleClient? {
    let defaults = IntelligencePreferences.defaults
    guard
      let base = OpenAICompatibleClient.normalizedBaseURL(
        defaults.string(forKey: IntelligencePreferences.Key.apiBase) ?? "")
    else { return nil }
    let model =
      model ?? defaults.string(forKey: IntelligencePreferences.Key.apiModel)?
      .trimmingCharacters(in: .whitespaces) ?? ""
    guard !model.isEmpty else { return nil }
    return OpenAICompatibleClient(
      baseURL: base, apiKey: IntelligenceKeychain.apiKey(), model: model)
  }

  /// One answer: a fresh session per call, so nothing carries over between
  /// pieces of a conversation.
  func respond(instructions: String, prompt: String) async throws -> String {
    switch backend {
    case .api(let client):
      return try await client.complete(instructions: instructions, prompt: prompt)
    case .onDevice:
      do {
        return try await Self.onDeviceRespond(instructions: instructions, prompt: prompt)
      } catch where Self.isContextOverflow(error) {
        // the estimate ran short: keep the newest part and try once more
        let kept = String(prompt.suffix(prompt.count * 3 / 5))
        return try await Self.onDeviceRespond(instructions: instructions, prompt: kept)
      } catch {
        throw Self.friendly(error)
      }
    }
  }

  private static func onDeviceRespond(instructions: String, prompt: String) async throws -> String {
    let session = LanguageModelSession(instructions: instructions)
    let response = try await session.respond(
      to: prompt, options: GenerationOptions(temperature: 0.3))
    return response.content
  }

  private static func isContextOverflow(_ error: any Error) -> Bool {
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
      let error = error as? LanguageModelError, case .contextSizeExceeded = error
    {
      return true
    }
    if let error = error as? LanguageModelSession.GenerationError,
      case .exceededContextWindowSize = error
    {
      return true
    }
    return false
  }

  /// Apple's errors say what went wrong for a developer; these say it for a reader.
  private static func friendly(_ error: any Error) -> any Error {
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
      let error = error as? LanguageModelError
    {
      switch error {
      case .guardrailViolation, .refusal:
        return IntelligenceError(
          "Apple Intelligence declined to work with these messages. An API model in Settings → Intelligence may handle them."
        )
      case .unsupportedLanguageOrLocale:
        return IntelligenceError(
          "Apple Intelligence doesn't support the language of these messages yet.")
      case .rateLimited:
        return IntelligenceError("Apple Intelligence is busy. Try again in a moment.")
      default: break
      }
    }
    if let error = error as? LanguageModelSession.GenerationError {
      switch error {
      case .guardrailViolation, .refusal:
        return IntelligenceError(
          "Apple Intelligence declined to work with these messages. An API model in Settings → Intelligence may handle them."
        )
      case .unsupportedLanguageOrLocale:
        return IntelligenceError(
          "Apple Intelligence doesn't support the language of these messages yet.")
      case .rateLimited:
        return IntelligenceError("Apple Intelligence is busy. Try again in a moment.")
      default: break
      }
    }
    return error
  }

  func summarizer() -> Summarizer {
    let model = self
    return Summarizer(
      tokenBudget: tokenBudget,
      language: IntelligencePreferences.summaryLanguageName
    ) { instructions, prompt in
      try await model.respond(instructions: instructions, prompt: prompt)
    }
  }
}

struct IntelligenceError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// The line under a feature saying where its text goes.
struct IntelligenceDestinationNote: View {
  let model: IntelligenceModel

  var body: some View {
    Label(model.destination, systemImage: model.isOnDevice ? "lock.shield" : "network")
      .font(.caption)
      .foregroundStyle(.secondary)
  }
}
