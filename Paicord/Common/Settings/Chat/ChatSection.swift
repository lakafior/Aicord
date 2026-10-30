//
//  ChatSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var chatSection: some View {
    ChatSettings()
  }
}

/// How messages show and what happens to what you type. The display and
/// emoticon options live in the account's text and images group.
struct ChatSettings: View {
  typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  typealias SpoilerReveal = SettingsStore.SpoilerReveal

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @AppStorage(EmojiPicker.showsNitroEmojiKey) private var showsNitroEmoji = false

  var body: some View {
    Section {
      settingToggle("Show Reactions", isOn: gw.settings.rendersReactions) {
        $0.textAndImages.renderReactions = .init($1)
      }
      settingToggle("Show Link Previews", isOn: gw.settings.rendersEmbeds) {
        $0.textAndImages.renderEmbeds = .init($1)
      }
      settingToggle("Show Uploaded Images and Videos", isOn: gw.settings.inlinesAttachmentMedia) {
        $0.textAndImages.inlineAttachmentMedia = .init($1)
      }
      settingToggle("Show Media from Links", isOn: gw.settings.inlinesEmbedMedia) {
        $0.textAndImages.inlineEmbedMedia = .init($1)
      }
    } header: {
      Text("Messages")
    } footer: {
      Text(
        "Saved to your Discord account. With uploads off, images and videos show as files that open when tapped. With media from links off, links to images, GIFs and videos stay plain links."
      )
    }

    Section {
      Picker("Show Spoilers", selection: spoilerReveal) {
        Text("On Tap").tag(SpoilerReveal.onClick)
        Text("On Servers I Moderate").tag(SpoilerReveal.ifModerator)
        Text("Always").tag(SpoilerReveal.always)
      }
    } header: {
      Text("Spoilers")
    } footer: {
      Text(
        "Hidden text and images marked as spoilers. Servers you moderate are the ones where you can manage messages."
      )
    }

    Section {
      settingToggle("Convert Emoticons to Emoji", isOn: gw.settings.convertsEmoticons) {
        $0.textAndImages.convertEmoticons = .init($1)
      }
    } header: {
      Text("Writing")
    } footer: {
      Text("When you send, :) becomes 🙂 and <3 becomes ❤️. Code and links stay as typed.")
    }

    if gw.user.premiumKind == .none {
      Section {
        Toggle("Show Emoji That Need Nitro", isOn: $showsNitroEmoji)
          #if os(macOS)
            .toggleStyle(.switch)
          #endif
      } header: {
        Text("Emoji")
      } footer: {
        Text(
          "Without Nitro you can use standard emoji and the still emoji of the server you're in. Turn this on to also see other servers' and animated emoji, locked, in the emoji picker. Only on this device."
        )
      }
    }
  }

  private var spoilerReveal: Binding<SpoilerReveal> {
    Binding(
      get: { gw.settings.spoilerReveal },
      set: { value in patch { $0.textAndImages.renderSpoilers = .init(value.rawValue) } }
    )
  }

  // MARK: - Rows

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
