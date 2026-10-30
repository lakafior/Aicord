//
//  IntelligenceSection.swift
//  Aicord
//
//  Where Intelligence runs, what it may read, and translation.
//

import AicordKit
import SwiftUI

#if !os(visionOS)
  import Translation
#endif

extension SettingsView {
  @ViewBuilder
  var intelligenceSection: some View {
    IntelligenceSettings()
  }
}

struct IntelligenceSettings: View {
  typealias Key = IntelligencePreferences.Key

  @AppStorage(Key.provider) private var provider = IntelligenceProvider.onDevice
  @AppStorage(Key.apiBase) private var apiBase = ""
  @AppStorage(Key.apiModel) private var apiModel = ""
  @AppStorage(Key.apiContext) private var apiContext = 32_000
  @AppStorage(Key.allowsDMs) private var allowsDMs = false
  @AppStorage(Key.summaryLanguage) private var summaryLanguage = ""
  @AppStorage(Key.scamWarnings) private var scamWarnings = true
  @AppStorage(Key.importantMuted) private var importantMuted = false
  @AppStorage(Key.importantTopics) private var importantTopics = ""
  @AppStorage(Key.voiceOverImages) private var voiceOverImages = true
  @AppStorage(Key.voiceOverImagesAPI) private var voiceOverImagesAPI = false

  @State private var keyDraft = ""
  @State private var hasKey = IntelligenceKeychain.hasAPIKey
  @State private var models: [String] = []
  @State private var loadingModels = false
  @State private var testState: TestState = .idle

  enum TestState: Equatable {
    case idle, testing
    case success(String)
    case failure(String)
  }

  var body: some View {
    Section {
      Picker("Provider", selection: $provider) {
        Text("On This Device").tag(IntelligenceProvider.onDevice)
        Text("OpenAI-Compatible API").tag(IntelligenceProvider.api)
      }
      if provider == .onDevice {
        onDeviceStatus
      }
    } header: {
      Text("Language Model")
    } footer: {
      Text(
        "Summaries and catch-up run on Apple Intelligence on this device unless you choose an API. With an API, the messages a feature reads are sent to that server. Intelligence only reads: it never sends anything to Discord."
      )
    }

    if provider == .api {
      apiSections
    }

    Section {
      Toggle("Use in Direct Messages", isOn: $allowsDMs)
      Picker("Summary Language", selection: $summaryLanguage) {
        Text("App Language").tag("")
        ForEach(summaryLanguages, id: \.self) { code in
          Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
        }
      }
    } header: {
      Text("Privacy and Output")
    } footer: {
      Text(
        "Off: summaries and catch-up skip direct messages and group chats. Messages hidden by your word filter, from blocked people, under spoilers or blocked by your sensitive media settings are never given to the model."
      )
    }

    Section {
      Toggle("Important Messages from Muted Channels", isOn: $importantMuted)
        .disabled(IntelligenceModel.onDeviceUnavailability != nil)
      if importantMuted {
        TextField("Your Topics", text: $importantTopics, prompt: Text("e.g. shipping, Kraków, jackets"))
          .autocorrectionDisabled()
      }
    } header: {
      Text("Notifications")
    } footer: {
      Text(
        "Muted channels stay quiet, except for messages Apple Intelligence on this device thinks are for you: questions to you, your name, or your topics (comma separated). Only on-device, never through an API, at most 20 checks an hour. Uses the notification settings for everything else."
      )
    }

    Section {
      Toggle("Warn About Scams", isOn: $scamWarnings)
    } header: {
      Text("Safety")
    } footer: {
      Text(
        "In direct messages from people who aren't your friends, a warning shows when messages look like a known scam: free Nitro or Steam gifts through links, links imitating Discord, “I reported you by accident”, or requests for passwords and codes. Checked on this device without a language model."
      )
    }

    Section {
      Toggle("Describe Images for VoiceOver", isOn: $voiceOverImages)
      if provider == .api {
        Toggle("Describe with the API Model", isOn: $voiceOverImagesAPI)
          .disabled(!voiceOverImages)
      }
    } header: {
      Text("Accessibility")
    } footer: {
      Text(
        provider == .api
          ? "While VoiceOver is on, images without alt text are read with the text Vision finds in them on this device. With the API model, each image you reach is also sent to that server for a short description; images in direct messages only when Use in Direct Messages is on."
          : "While VoiceOver is on, images without alt text are read with the text Vision finds in them, on this device. Spoilers and hidden sensitive media are never read."
      )
    }

    TranslationSettingsSections()
  }

  // MARK: On device

  @ViewBuilder
  private var onDeviceStatus: some View {
    if let reason = IntelligenceModel.onDeviceUnavailability {
      Label {
        Text(reason.localizedDescription)
      } icon: {
        Image(systemName: "exclamationmark.triangle")
          .foregroundStyle(.orange)
      }
      .font(.callout)
    } else {
      Label("Apple Intelligence is ready", systemImage: "checkmark.circle")
        .foregroundStyle(.green)
    }
  }

  // MARK: API

  @ViewBuilder
  private var apiSections: some View {
    Section {
      TextField("Address", text: $apiBase, prompt: Text(verbatim: "https://api.example.com/v1"))
        .textContentType(.URL)
        .autocorrectionDisabled()
        #if os(iOS)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
        #endif
      if hasKey {
        LabeledContent("API Key") {
          Text("Saved in Keychain")
            .foregroundStyle(.secondary)
        }
        Button("Remove Key", role: .destructive) {
          IntelligenceKeychain.removeAPIKey()
          hasKey = IntelligenceKeychain.hasAPIKey
          testState = .idle
        }
      } else {
        SecureField("API Key", text: $keyDraft)
          .textContentType(.password)
          .autocorrectionDisabled()
          .onSubmit(saveKey)
        Button("Save Key", action: saveKey)
          .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    } header: {
      Text("Server")
    } footer: {
      if apiBase.isEmpty {
        Text(
          "Any server with the OpenAI chat completions API: OpenAI, Mistral, OpenRouter, or Ollama and LM Studio on your network (those need no key). Ollama is at localhost:11434 and LM Studio at localhost:1234 on the same computer; from an iPhone, use the computer's name, like my-mac.local:11434."
        )
      } else if let url = OpenAICompatibleClient.normalizedBaseURL(apiBase),
        OpenAICompatibleClient.isLocalHost(url.host() ?? "")
      {
        Text("Requests go to \(url.absoluteString) on your network, over plain HTTP. The first time, iOS asks to allow Aicord on the local network.")
      } else if let url = OpenAICompatibleClient.normalizedBaseURL(apiBase) {
        Text("Requests go to \(url.absoluteString). The key stays in this device's keychain.")
      } else {
        Text("That doesn't look like an address.")
          .foregroundStyle(.red)
      }
    }

    Section {
      TextField("Model", text: $apiModel, prompt: Text(verbatim: "mistral-small-latest"))
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
      if !models.isEmpty {
        Picker("Available Models", selection: $apiModel) {
          if !models.contains(apiModel) {
            Text(apiModel.isEmpty ? "Choose" : apiModel).tag(apiModel)
          }
          ForEach(models, id: \.self) { Text($0).tag($0) }
        }
      }
      Button {
        Task { await loadModels() }
      } label: {
        HStack {
          Text("Load Models from Server")
          if loadingModels {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(OpenAICompatibleClient.normalizedBaseURL(apiBase) == nil || loadingModels)
      Picker("Context Size", selection: $apiContext) {
        Text("8K tokens").tag(8_000)
        Text("32K tokens").tag(32_000)
        Text("128K tokens").tag(128_000)
      }
    } header: {
      Text("Model")
    } footer: {
      Text(
        "Context size is how much the model reads at once. Longer conversations are summarised in parts, so a smaller size works but takes more requests."
      )
    }

    Section {
      Button {
        Task { await testConnection() }
      } label: {
        HStack {
          Text("Test Connection")
          if testState == .testing {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(IntelligenceModel.apiClient(model: apiModel) == nil || testState == .testing)
      switch testState {
      case .success(let reply):
        Label("Connected. The model replied “\(reply)”.", systemImage: "checkmark.circle")
          .foregroundStyle(.green)
      case .failure(let message):
        Label(message, systemImage: "xmark.octagon")
          .foregroundStyle(.red)
      default:
        EmptyView()
      }
    } footer: {
      Text("Sends one short test prompt, with no messages from Discord.")
    }
  }

  private func saveKey() {
    let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    if IntelligenceKeychain.setAPIKey(key) {
      keyDraft = ""
    }
    hasKey = IntelligenceKeychain.hasAPIKey
    testState = .idle
  }

  private func loadModels() async {
    guard let base = OpenAICompatibleClient.normalizedBaseURL(apiBase) else { return }
    loadingModels = true
    defer { loadingModels = false }
    let client = OpenAICompatibleClient(
      baseURL: base, apiKey: IntelligenceKeychain.apiKey(), model: apiModel)
    do {
      models = try await client.models()
      if apiModel.isEmpty, let first = models.first { apiModel = first }
      testState = .idle
    } catch {
      testState = .failure(error.localizedDescription)
    }
  }

  private func testConnection() async {
    guard let client = IntelligenceModel.apiClient(model: apiModel) else { return }
    testState = .testing
    do {
      let reply = try await client.complete(
        instructions: "Reply with one word.", prompt: "Say OK.", maxTokens: 10)
      testState = .success(String(reply.prefix(40)))
    } catch {
      testState = .failure(error.localizedDescription)
    }
  }

  private var summaryLanguages: [String] {
    var codes: [String] = []
    for identifier in Locale.preferredLanguages + ["en"] {
      if let code = Locale.Language(identifier: identifier).languageCode?.identifier,
        !codes.contains(code)
      {
        codes.append(code)
      }
    }
    if !summaryLanguage.isEmpty, !codes.contains(summaryLanguage) { codes.append(summaryLanguage) }
    return codes
  }
}

// MARK: - Translation

struct TranslationSettingsSections: View {
  typealias Key = IntelligencePreferences.Key

  @AppStorage(Key.translationTarget) private var target = ""
  @AppStorage(Key.autoTranslateLanguages) private var autoLanguages = ""
  @State private var supported: [Locale.Language] = []

  var body: some View {
    #if os(visionOS)
      EmptyView()
    #else
      Section {
        Picker("Translate To", selection: $target) {
          Text("App Language").tag("")
          ForEach(supported, id: \.minimalIdentifier) { language in
            Text(MessageTranslator.name(of: language)).tag(language.minimalIdentifier)
          }
        }
        NavigationLink {
          AutoTranslateLanguagesView(supported: supported)
        } label: {
          LabeledContent("Translate Automatically") {
            Text(autoSummary)
          }
        }
      } header: {
        Text("Translation")
      } footer: {
        Text(
          "“Translate” in a message's menu, and automatic translation of the languages you pick, use Apple's Translation on this device. Each language downloads once. Automatic translation only uses languages already downloaded."
        )
      }
      .task {
        supported = await MessageTranslator.supportedLanguages()
          .sorted { MessageTranslator.name(of: $0) < MessageTranslator.name(of: $1) }
      }
    #endif
  }

  private var autoSummary: String {
    let codes = autoLanguages.split(separator: ",").map(String.init)
    if codes.isEmpty { return String(localized: "Off") }
    return codes.map { MessageTranslator.name(of: Locale.Language(identifier: $0)) }
      .joined(separator: ", ")
  }
}

#if !os(visionOS)
  struct AutoTranslateLanguagesView: View {
    @AppStorage(IntelligencePreferences.Key.autoTranslateLanguages) private var autoLanguages = ""
    let supported: [Locale.Language]

    var body: some View {
      Form {
        Section {
          ForEach(supported, id: \.minimalIdentifier) { language in
            Toggle(MessageTranslator.name(of: language), isOn: binding(for: language))
          }
        } footer: {
          Text(
            "Messages detected in these languages show a translation under them, when the language is downloaded on this device."
          )
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Translate Automatically")
    }

    private func binding(for language: Locale.Language) -> Binding<Bool> {
      let code = language.minimalIdentifier
      return Binding {
        autoLanguages.split(separator: ",").contains { $0 == code }
      } set: { on in
        var codes = autoLanguages.split(separator: ",").map(String.init).filter { $0 != code }
        if on { codes.append(code) }
        autoLanguages = codes.joined(separator: ",")
      }
    }
  }
#endif
