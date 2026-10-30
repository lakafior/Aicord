//
//  LanguageSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

extension SettingsView {
  @ViewBuilder
  var languageSection: some View {
    LanguageSettings()
  }
}

/// Discord's language, saved to the account (it decides the language of
/// Discord's emails, system messages and other clients), and the language
/// Aicord itself is shown in, which the system sets per app.
struct LanguageSettings: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.openURL) var openURL

  /// Discord's locales, by the code its settings store.
  static let discordLocales = [
    "bg", "cs", "da", "de", "el", "en-GB", "en-US", "es-ES", "es-419", "fi", "fr", "hi", "hr",
    "hu", "id", "it", "ja", "ko", "lt", "nl", "no", "pl", "pt-BR", "ro", "ru", "sv-SE", "th",
    "tr", "uk", "vi", "zh-CN", "zh-TW",
  ]

  private var discordLocale: String {
    gw.settings.userSettings.localization.locale.value
  }

  var body: some View {
    Section {
      Picker("Discord Language", selection: discordLocaleBinding) {
        if !Self.discordLocales.contains(discordLocale) {
          Text(Self.name(of: discordLocale.isEmpty ? "en-US" : discordLocale))
            .tag(discordLocale)
        }
        ForEach(Self.sortedLocales, id: \.self) { code in
          Text(Self.name(of: code)).tag(code)
        }
      }
    } header: {
      Text("Discord")
    } footer: {
      Text(
        "Saved to your Discord account. It's the language of Discord's emails and system messages, and the one other Discord apps start in."
      )
    }

    Section {
      LabeledContent("App Language") {
        Text(Self.name(of: Bundle.main.preferredLocalizations.first ?? "en"))
      }
      Button("Change in System Settings…", systemImage: "gear") {
        openSystemLanguageSettings()
      }
    } header: {
      Text("Aicord")
    } footer: {
      #if os(macOS)
        Text(
          "Choose Aicord's language in System Settings → General → Language & Region → Applications. Aicord restarts in the new language. Discord's own text, like channel names and messages, stays as it is."
        )
      #else
        Text(
          "Choose Aicord's language in its page in the Settings app, under Language. Discord's own text, like channel names and messages, stays as it is."
        )
      #endif
    }
  }

  private var discordLocaleBinding: Binding<String> {
    Binding {
      discordLocale.isEmpty ? "en-US" : discordLocale
    } set: { code in
      Task {
        do {
          try await gw.settings.patchUserSettings { settings in
            settings.localization.locale = .init(code)
          }
        } catch {
          appState.error = error
        }
      }
    }
  }

  /// In the reader's language first, so the list sorts as they'd expect.
  static var sortedLocales: [String] {
    discordLocales.sorted {
      name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending
    }
  }

  /// "Polski (Polish)" style: the language's own name, then the reader's.
  static func name(of code: String) -> String {
    let native = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    let reader = Locale.current.localizedString(forIdentifier: code) ?? code
    let nativeName = native.prefix(1).uppercased() + native.dropFirst()
    return nativeName == reader ? nativeName : "\(nativeName) (\(reader))"
  }

  private func openSystemLanguageSettings() {
    #if os(iOS)
      if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    #elseif os(macOS)
      if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
        NSWorkspace.shared.open(url)
      }
    #endif
  }
}
