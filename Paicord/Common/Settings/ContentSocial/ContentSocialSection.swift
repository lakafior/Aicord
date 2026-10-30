//
//  ContentSocialSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var contentSocialSection: some View {
    ContentSocialSettings()
  }
}

/// Content filters and who can reach you, stored in the account's settings proto.
struct ContentSocialSettings: View {
  typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  typealias Redaction = Settings.ExplicitContentRedaction

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  private var settings: Settings { gw.settings.userSettings }
  private var textAndImages: Settings.TextAndImagesSettings { settings.textAndImages }
  private var privacy: Settings.PrivacySettings { settings.privacy }

  var body: some View {
    Section {
      redactionPicker(
        "Direct Messages from Friends",
        value: textAndImages.explicitContentSettings.explicitContentFriendDm,
        unset: .show
      ) { $0.textAndImages.explicitContentSettings.explicitContentFriendDm = $1 }
      redactionPicker(
        "Direct Messages from Others",
        value: textAndImages.explicitContentSettings.explicitContentNonFriendDm,
        unset: .block
      ) { $0.textAndImages.explicitContentSettings.explicitContentNonFriendDm = $1 }
      redactionPicker(
        "Servers",
        value: textAndImages.explicitContentSettings.explicitContentGuilds,
        unset: .show
      ) { $0.textAndImages.explicitContentSettings.explicitContentGuilds = $1 }
    } header: {
      Text("Sensitive Media")
    } footer: {
      Text("Images and videos Discord flags as explicit. Aicord and the official apps both follow this.")
    }

    Section {
      redactionPicker(
        "Direct Messages from Friends",
        value: textAndImages.goreContentSettings.goreContentFriendDm,
        unset: .show
      ) { $0.textAndImages.goreContentSettings.goreContentFriendDm = $1 }
      redactionPicker(
        "Direct Messages from Others",
        value: textAndImages.goreContentSettings.goreContentNonFriendDm,
        unset: .block
      ) { $0.textAndImages.goreContentSettings.goreContentNonFriendDm = $1 }
      redactionPicker(
        "Servers",
        value: textAndImages.goreContentSettings.goreContentGuilds,
        unset: .show
      ) { $0.textAndImages.goreContentSettings.goreContentGuilds = $1 }
    } header: {
      Text("Violent and Graphic Content")
    }

    Section {
      settingToggle("Profanity", isOn: textAndImages.keywordFilterSettings.profanity.value) {
        $0.textAndImages.keywordFilterSettings.profanity = .init($1)
      }
      settingToggle("Sexual Content", isOn: textAndImages.keywordFilterSettings.sexualContent.value) {
        $0.textAndImages.keywordFilterSettings.sexualContent = .init($1)
      }
      settingToggle("Slurs and Hateful Language", isOn: textAndImages.keywordFilterSettings.slurs.value) {
        $0.textAndImages.keywordFilterSettings.slurs = .init($1)
      }
    } header: {
      Text("Keyword Filters")
    } footer: {
      Text("Saved to your Discord account and applied by the official apps.")
    }

    WordFilterSettings()

    Section {
      Picker("Filter Spam", selection: dmSpamFilter) {
        Text("All Direct Messages").tag(Settings.DmSpamFilterV2.friendsAndNonFriends)
        Text("From Non-Friends").tag(Settings.DmSpamFilterV2.nonFriends)
        Text("Off").tag(Settings.DmSpamFilterV2.disabled)
      }
      settingToggle("Allow DMs from Server Members", isOn: !guildsRestricted) {
        $0.privacy.defaultGuildsRestricted = !$1
        $0.privacy.defaultGuildsRestrictedV2 = .init(!$1)
      }
      settingToggle(
        "Message Requests",
        isOn: !privacy.defaultMessageRequestRestricted.value
      ) {
        $0.privacy.defaultMessageRequestRestricted = .init(!$1)
      }
    } header: {
      Text("Direct Messages")
    } footer: {
      Text(
        "Spam goes to a separate folder. Message requests hold DMs from server members you may not know. Both server options apply to servers you join from now on."
      )
    }

    Section {
      friendSourceToggle("Everyone", flag: FriendSource.noRelation)
      friendSourceToggle("Friends of Friends", flag: FriendSource.mutualFriends)
      friendSourceToggle("Server Members", flag: FriendSource.mutualGuilds)
    } header: {
      Text("Who Can Send You Friend Requests")
    }
  }

  // MARK: - Values

  /// Discord bits; "everyone" only works together with the other two.
  enum FriendSource {
    static let mutualFriends: UInt32 = 1 << 1
    static let mutualGuilds: UInt32 = 1 << 2
    static let noRelation: UInt32 = 1 << 3
    static let all = mutualFriends | mutualGuilds | noRelation
  }

  private var friendSourceFlags: UInt32 {
    privacy.hasFriendSourceFlags ? privacy.friendSourceFlags.value : FriendSource.all
  }

  /// Discord has a plain and a wrapped (v2) field for this; both are written,
  /// the v2 one wins when reading.
  private var guildsRestricted: Bool {
    privacy.hasDefaultGuildsRestrictedV2
      ? privacy.defaultGuildsRestrictedV2.value : privacy.defaultGuildsRestricted
  }

  private var dmSpamFilter: Binding<Settings.DmSpamFilterV2> {
    Binding(
      get: {
        switch textAndImages.dmSpamFilterV2 {
        case .defaultUnset, .UNRECOGNIZED: .nonFriends
        case let value: value
        }
      },
      set: { value in patch { $0.textAndImages.dmSpamFilterV2 = value } }
    )
  }

  // MARK: - Rows

  private func redactionPicker(
    _ title: LocalizedStringKey,
    value: Redaction,
    unset: Redaction,
    write: @escaping (inout Settings, Redaction) -> Void
  ) -> some View {
    Picker(
      title,
      selection: Binding(
        get: {
          switch value {
          case .unsetExplicitContentRedaction, .UNRECOGNIZED: unset
          default: value
          }
        },
        set: { newValue in patch { write(&$0, newValue) } }
      )
    ) {
      Text("Show").tag(Redaction.show)
      Text("Blur").tag(Redaction.blur)
      Text("Block").tag(Redaction.block)
    }
  }

  private func settingToggle(
    _ title: LocalizedStringKey,
    isOn: Bool,
    write: @escaping (inout Settings, Bool) -> Void
  ) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { isOn },
        set: { newValue in patch { write(&$0, newValue) } }
      )
    )
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
  }

  private func friendSourceToggle(_ title: LocalizedStringKey, flag: UInt32) -> some View {
    let flags = friendSourceFlags
    return settingToggle(title, isOn: flags & flag == flag) { settings, isOn in
      var newFlags = flags
      if isOn {
        newFlags = flag == FriendSource.noRelation ? FriendSource.all : newFlags | flag
      } else {
        newFlags &= ~flag
        if flag != FriendSource.noRelation { newFlags &= ~FriendSource.noRelation }
      }
      settings.privacy.friendSourceFlags = .init(newFlags)
    }
  }

  private func patch(_ change: @escaping (inout Settings) -> Void) {
    Task {
      do {
        try await gw.settings.patchUserSettings(change)
      } catch {
        appState.error = error
      }
    }
  }
}

/// Aicord's own word filter: the bundled community lists plus your own words.
struct WordFilterSettings: View {
  @AppStorage(WordFilter.Key.enabled) private var enabled = false
  @AppStorage(WordFilter.Key.languages) private var languages = WordFilter.defaultLanguages
  @AppStorage(WordFilter.Key.customWords) private var customWords = ""
  @AppStorage(WordFilter.Key.scope) private var scope = WordFilter.Scope.nonFriendDMs

  var body: some View {
    Section {
      Toggle("Community Word List", isOn: $enabled)
      #if os(macOS)
        .toggleStyle(.switch)
      #endif
      if enabled {
        Picker("Applies To", selection: $scope) {
          Text("DMs from Non-Friends").tag(WordFilter.Scope.nonFriendDMs)
          Text("All Messages").tag(WordFilter.Scope.everywhere)
        }
        NavigationLink {
          WordListLanguages(languages: $languages)
        } label: {
          LabeledContent("Languages", value: languageSummary)
        }
        TextField("Your Own Words", text: $customWords, prompt: Text("Separated by commas"), axis: .vertical)
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
      }
    } header: {
      Text("Word Filter in Aicord")
    } footer: {
      Text(
        "Hides matching messages behind a tap, only in Aicord. Uses the [List of Dirty, Naughty, Obscene, and Otherwise Bad Words](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words) by Shutterstock and contributors (CC BY 4.0), matched as whole words, plus your own words."
      )
    }
  }

  private var languageSummary: String {
    let codes = languages.split(separator: ",").map(String.init)
    if codes.isEmpty { return String(localized: "None") }
    return codes.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
      .formatted(.list(type: .and))
  }
}

/// Which bundled lists the word filter uses.
struct WordListLanguages: View {
  @Binding var languages: String

  var body: some View {
    let selected = Set(languages.split(separator: ",").map(String.init))
    Form {
      ForEach(sortedLanguages, id: \.code) { language in
        Button {
          var newSelection = selected
          if selected.contains(language.code) {
            newSelection.remove(language.code)
          } else {
            newSelection.insert(language.code)
          }
          languages = newSelection.sorted().joined(separator: ",")
        } label: {
          HStack {
            Text(verbatim: language.name)
              .foregroundStyle(.primary)
            Spacer()
            if selected.contains(language.code) {
              Image(systemName: "checkmark")
                .foregroundStyle(.tint)
            }
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Languages")
  }

  private var sortedLanguages: [(code: String, name: String)] {
    WordFilter.availableLanguages
      .map { ($0, Locale.current.localizedString(forLanguageCode: $0) ?? $0) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
