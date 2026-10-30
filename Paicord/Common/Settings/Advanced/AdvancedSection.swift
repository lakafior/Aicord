//
//  AdvancedSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var advancedSection: some View {
    AdvancedSettings()
  }
}

/// Developer mode, the image cache and the app's logs.
struct AdvancedSettings: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @State private var cacheSize: Int?

  var body: some View {
    Section {
      Toggle(
        "Developer Mode",
        isOn: Binding(
          get: { gw.settings.userSettings.appearance.developerMode },
          set: { newValue in
            Task {
              do {
                try await gw.settings.patchUserSettings {
                  $0.appearance.developerMode = newValue
                }
              } catch {
                appState.error = error
              }
            }
          }
        )
      )
      #if os(macOS)
        .toggleStyle(.switch)
      #endif
    } footer: {
      Text(
        "Saved to your Discord account. Adds Copy ID to the menus of messages, users and servers, for bots and bug reports."
      )
    }

    Section {
      LabeledContent("Image Cache") {
        if let cacheSize {
          Text(cacheSize.formatted(.byteCount(style: .file)))
        } else {
          ProgressView()
            .controlSize(.small)
        }
      }
      Button("Clear Cache", role: .destructive) {
        ImagePipeline.shared.clearCache()
        cacheSize = nil
        Task {
          // URLCache removes the files in the background
          try? await Task.sleep(for: .seconds(1))
          cacheSize = ImagePipeline.shared.diskUsage()
        }
      }
      .disabled(cacheSize == 0)
    } header: {
      Text("Storage")
    } footer: {
      Text("Avatars, emoji and images from messages, kept so they load faster. They download again when needed.")
    }
    .task {
      cacheSize = ImagePipeline.shared.diskUsage()
    }

    Section {
      NavigationLink {
        ShellView()
      } label: {
        Label("View Logs", systemImage: "apple.terminal")
      }
      ShareLink(
        item: StdOutInterceptor.shared.getLogs().map(\.str).joined(separator: "\n"),
        preview: SharePreview("Aicord Logs")
      ) {
        Label("Share Logs", systemImage: "square.and.arrow.up")
      }
    } header: {
      Text("Diagnostics")
    } footer: {
      Text("What Aicord recorded since it started. Attach it to a bug report; it can contain names of servers and channels.")
    }
  }
}
