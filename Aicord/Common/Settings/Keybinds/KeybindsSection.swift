//
//  KeybindsSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

extension SettingsView {
  @ViewBuilder
  var keybindsSection: some View {
    Section("App") {
      KeybindRow("Settings", keys: "⌘ ,")
      KeybindRow("Quick Switcher", keys: "⌘ K")
      KeybindRow("Reload", keys: "⇧ ⌘ R")
    }
    Section("Chat") {
      KeybindRow("Send Message", keys: "↩")
      #if os(macOS)
        KeybindRow("New Line", keys: "⇧ ↩")
        KeybindRow("Jump to Latest Messages", keys: "esc")
      #endif
    }
    Section("Media Viewer") {
      KeybindRow("Previous / Next", keys: "← →")
      KeybindRow("Close", keys: "esc")
    }
  }
}

/// A shortcut name with its keys shown in key-cap style.
struct KeybindRow: View {
  var title: LocalizedStringKey
  var keys: String

  init(_ title: LocalizedStringKey, keys: String) {
    self.title = title
    self.keys = keys
  }

  var body: some View {
    LabeledContent(title) {
      HStack(spacing: 4) {
        ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
          Text(verbatim: key)
            .font(.callout.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: .rect(cornerRadius: 5))
        }
      }
      .accessibilityElement(children: .combine)
    }
  }
}
