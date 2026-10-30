//
//  MessageTranslation.swift
//  Aicord
//
//  "Translate" in the message menu and automatic translation, with Apple's
//  Translation on this device. No language model and no network once a
//  language is downloaded.
//

import AicordKit
import NaturalLanguage
import SwiftUI

#if !os(visionOS)
  @preconcurrency import Translation

  @MainActor
  @Observable
  final class MessageTranslator {
    static let shared = MessageTranslator()

    enum State: Equatable {
      case working
      /// The language pair isn't downloaded; the view asks the system to get it.
      case needsDownload(source: Locale.Language, target: Locale.Language)
      case translated(text: String, source: Locale.Language)
      case failed(String)
    }

    var states: [MessageSnowflake: State] = [:]
    /// Automatic translations the reader closed, so they don't come back.
    @ObservationIgnored private var dismissed: Set<MessageSnowflake> = []
    @ObservationIgnored private var checked: Set<MessageSnowflake> = []
    @ObservationIgnored private var sessions: [String: TranslationSession] = [:]

    static var target: Locale.Language {
      let saved =
        UserDefaults.standard.string(forKey: IntelligencePreferences.Key.translationTarget) ?? ""
      if !saved.isEmpty { return Locale.Language(identifier: saved) }
      return Locale.preferredLanguages.first.map(Locale.Language.init(identifier:))
        ?? Locale.current.language
    }

    nonisolated static func supportedLanguages() async -> [Locale.Language] {
      await LanguageAvailability().supportedLanguages
    }

    nonisolated static func status(from source: Locale.Language, to target: Locale.Language) async
      -> LanguageAvailability.Status
    {
      await LanguageAvailability().status(from: source, to: target)
    }

    static func name(of language: Locale.Language) -> String {
      Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
        ?? language.minimalIdentifier
    }

    /// The language a message is written in, when the recogniser is fairly sure.
    static func detect(_ text: String) -> Locale.Language? {
      let recognizer = NLLanguageRecognizer()
      recognizer.processString(text)
      guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
        confidence > 0.5, language != .undetermined
      else { return nil }
      return Locale.Language(identifier: language.rawValue)
    }

    static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
      a.languageCode == b.languageCode
        && (a.script == nil || b.script == nil || a.script == b.script)
    }

    /// The message text worth translating: mentions as names, emoji codes kept, lines kept.
    static func text(of message: DiscordChannel.PartialMessage) -> String {
      var names: [String: String] = [:]
      for user in message.mentions ?? [] {
        names[user.id.rawValue] = user.global_name ?? user.username
      }
      return (message.content ?? "")
        .components(separatedBy: .newlines)
        .map { IntelligenceText.clean($0, userNames: names) }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isShowing(_ id: MessageSnowflake) -> Bool { states[id] != nil }

    /// From the message menu.
    func translate(_ message: DiscordChannel.PartialMessage) {
      let text = Self.text(of: message)
      let target = Self.target
      guard !text.isEmpty else { return }
      guard let source = Self.detect(text) else {
        states[message.id] = .failed(String(localized: "Couldn't tell which language this is."))
        return
      }
      if Self.sameLanguage(source, target) {
        states[message.id] = .failed(
          String(localized: "This message is already in \(Self.name(of: target))."))
        return
      }
      states[message.id] = .working
      Task {
        switch await Self.status(from: source, to: target) {
        case .installed:
          await run(message.id, text: text, source: source, target: target)
        case .supported:
          states[message.id] = .needsDownload(source: source, target: target)
        case .unsupported:
          states[message.id] = .failed(
            String(localized: "Translation from \(Self.name(of: source)) isn't available."))
        @unknown default:
          states[message.id] = .failed(String(localized: "Translation isn't available."))
        }
      }
    }

    /// "Show Original": the translation goes away, and an automatic one stays away.
    func hide(_ id: MessageSnowflake) {
      states[id] = nil
      dismissed.insert(id)
    }

    /// Translates a message on its own when its language is one picked in
    /// Settings and already downloaded, so nothing is asked of the reader.
    func translateAutomatically(_ message: DiscordChannel.PartialMessage) async {
      let codes = UserDefaults.standard.string(
        forKey: IntelligencePreferences.Key.autoTranslateLanguages) ?? ""
      guard !codes.isEmpty, !dismissed.contains(message.id), states[message.id] == nil,
        checked.insert(message.id).inserted
      else { return }
      let text = Self.text(of: message)
      guard text.count >= 4, let source = Self.detect(text) else { return }
      let target = Self.target
      let wanted = codes.split(separator: ",").map { Locale.Language(identifier: String($0)) }
      guard wanted.contains(where: { Self.sameLanguage($0, source) }),
        !Self.sameLanguage(source, target),
        await Self.status(from: source, to: target) == .installed
      else { return }
      await run(message.id, text: text, source: source, target: target, quietly: true)
    }

    private func run(
      _ id: MessageSnowflake, text: String, source: Locale.Language, target: Locale.Language,
      quietly: Bool = false
    ) async {
      let key = source.minimalIdentifier + ">" + target.minimalIdentifier
      let session =
        sessions[key] ?? TranslationSession(installedSource: source, target: target)
      sessions[key] = session
      do {
        let response = try await session.translate(text)
        states[id] = .translated(text: response.targetText, source: source)
      } catch {
        sessions[key] = nil
        if !quietly { states[id] = .failed(error.localizedDescription) }
      }
    }

    /// After the system's download sheet, from `translationTask`.
    func finish(
      _ id: MessageSnowflake, text: String, source: Locale.Language, session: TranslationSession
    ) async {
      do {
        let response = try await session.translate(text)
        states[id] = .translated(text: response.targetText, source: source)
      } catch {
        states[id] = .failed(error.localizedDescription)
      }
    }
  }

  /// The translation under a message's text, with "Show Original".
  struct MessageTranslationView: View {
    let message: DiscordChannel.PartialMessage
    private var translator: MessageTranslator { .shared }

    @AppStorage(IntelligencePreferences.Key.autoTranslateLanguages) private var autoLanguages = ""

    var body: some View {
      Group {
        if let state = translator.states[message.id] {
          box(for: state)
        }
      }
      .task(id: autoLanguages) {
        guard !autoLanguages.isEmpty else { return }
        await translator.translateAutomatically(message)
      }
    }

    @ViewBuilder
    private func box(for state: MessageTranslator.State) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        switch state {
        case .working:
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Translating…")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        case .needsDownload(let source, let target):
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Getting \(MessageTranslator.name(of: source)) ready…")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .translationTask(.init(source: source, target: target)) { session in
            await translator.finish(
              message.id, text: MessageTranslator.text(of: message), source: source,
              session: session)
          }
        case .translated(let text, let source):
          Text(text)
            .textSelection(.enabled)
          footer("Translated from \(MessageTranslator.name(of: source))")
        case .failed(let reason):
          footer(LocalizedStringKey(reason))
        }
      }
      .padding(.leading, 10)
      .overlay(alignment: .leading) {
        Capsule()
          .fill(.tint.opacity(0.6))
          .frame(width: 3)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(_ text: LocalizedStringKey) -> some View {
      HStack(spacing: 8) {
        Label(text, systemImage: "translate")
          .labelStyle(.titleAndIcon)
        Button("Show Original") {
          translator.hide(message.id)
        }
        .buttonStyle(.borderless)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
#endif
