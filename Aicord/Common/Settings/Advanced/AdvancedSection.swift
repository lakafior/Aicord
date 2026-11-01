//
//  AdvancedSection.swift
//  Aicord
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
  @AppStorage(SystemIntegration.spotlightEnabledKey) private var spotlightEnabled = true
  #if os(macOS)
    @AppStorage(MCPPreferences.enabledKey) private var mcpEnabled = false
    @AppStorage(MCPPreferences.directMessagesKey) private var mcpDirectMessages = false
  #endif

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

    #if os(macOS)
      Section {
        Toggle("Allow MCP Server", isOn: $mcpEnabled)
          .toggleStyle(.switch)
          .onChange(of: mcpEnabled) { MCPBridge.shared.update() }
        Toggle("Include Direct Messages", isOn: $mcpDirectMessages)
          .toggleStyle(.switch)
          .disabled(!mcpEnabled)
        if mcpEnabled {
          LabeledContent("Address") {
            Text(verbatim: "127.0.0.1:\(MCPPreferences.port)")
              .font(.body.monospaced())
              .textSelection(.enabled)
          }
          Button("Copy Configuration for Claude", systemImage: "doc.on.doc") {
            copyToPasteboard(MCPPreferences.clientConfiguration)
          }
          Button("Reset Key", role: .destructive) {
            MCPPreferences.resetToken()
          }
        }
      } header: {
        Text("MCP Server")
      } footer: {
        Text(
          "Lets an assistant like Claude read your servers, channels and messages through the aicord-mcp helper while Aicord is open. Read-only: it can't send, react or change anything. Only programs on this Mac that have the key from the copied configuration can connect; Reset Key cuts off the old one. Messages your filters hide are left out."
        )
      }
    #endif

    Section {
      NavigationLink {
        SafariExtensionGuide()
      } label: {
        Label("Safari Extension", systemImage: "safari")
      }
    } footer: {
      Text("Open discord.gg and discord.com/invite links from Safari in Aicord.")
    }

    Section {
      Toggle("Show in Spotlight", isOn: $spotlightEnabled)
        #if os(macOS)
          .toggleStyle(.switch)
        #endif
        .onChange(of: spotlightEnabled) {
          SystemIntegration.shared.setSpotlightEnabled(spotlightEnabled)
        }
    } header: {
      Text("Spotlight")
    } footer: {
      Text(
        "Find your DMs, channels and saved messages from Spotlight search. Only names go in, plus the text of messages you saved. Turning this off or logging out removes them."
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
