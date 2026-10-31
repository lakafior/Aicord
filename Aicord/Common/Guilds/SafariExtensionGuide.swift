//
//  SafariExtensionGuide.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import SwiftUI

#if os(macOS)
  import SafariServices
#endif

/// How to turn on the "Aicord Invites" Safari extension, which opens
/// discord.gg and discord.com/invite links in Aicord. Turning it on takes a
/// few screens in Settings (iOS) or Safari (macOS), and the switch sometimes
/// flips back before it sticks, so the steps are spelled out.
struct SafariExtensionGuide: View {
  #if os(macOS)
    @State private var enabled: Bool?
    @State private var error: String?
  #endif

  var body: some View {
    Form {
      Section {
        Label {
          Text("Invite links you open in Safari go straight to Aicord's invite preview instead of the Discord website.")
        } icon: {
          Image(systemName: "safari")
        }
      }

      #if os(macOS)
        Section {
          LabeledContent("Status") {
            switch enabled {
            case .some(true): Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false): Text("Off")
            case nil: ProgressView().controlSize(.small)
            }
          }
          Button("Open Safari Extension Settings…") { openSafariSettings() }
          if let error {
            Text(error).foregroundStyle(.red)
          }
        }
      #endif

      Section {
        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
          Label {
            Text(step)
          } icon: {
            Text(verbatim: "\(index + 1)")
              .font(.callout.bold().monospacedDigit())
              .foregroundStyle(.white)
              .frame(width: 24, height: 24)
              .background(.tint, in: .circle)
          }
        }
      } header: {
        Text("Turn It On")
      }

      Section {
        Text(
          "If the switch turns itself off again, leave it for a moment, close Safari and try once more. It can take a couple of goes before it stays on."
        )
        Text(
          "Safari asks again when you first open an invite link. Choose Always Allow on Every Website, or allow discord.com and discord.gg."
        )
        Text("Safari then asks whether to open Aicord. Tap Open.")
      } header: {
        Text("If It Doesn't Work")
      }

      Section {
        Text(
          "The extension can only see discord.gg and discord.com/invite pages, and all it does there is hand the invite code to Aicord. It doesn't read anything else you browse."
        )
      } header: {
        Text("Privacy")
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Safari Extension")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear { SafariExtensionGuide.markSeen() }
    #if os(macOS)
      .task { await refreshState() }
    #endif
  }

  static var steps: [LocalizedStringKey] {
    #if os(macOS)
      [
        "Open Safari and choose Safari → Settings → Extensions, or use the button above.",
        "Tick Aicord Invites.",
        "Under Permissions, choose Always Allow on discord.com and discord.gg.",
        "A development build may need Develop → Allow Unsigned Extensions first.",
      ]
    #else
      [
        "Open the Settings app and go to Apps → Safari → Extensions.",
        "Tap Aicord Invites and turn on Allow Extension.",
        "Under Permissions, set discord.com and discord.gg to Allow.",
        "Open an invite link in Safari and tap Open when asked.",
      ]
    #endif
  }

  #if os(macOS)
    static let extensionIdentifier = (Bundle.main.bundleIdentifier ?? "net.smigi.aicord") + ".SafariExtension"

    private func refreshState() async {
      do {
        let state = try await SFSafariExtensionManager.stateOfSafariExtension(
          withIdentifier: Self.extensionIdentifier)
        enabled = state.isEnabled
        if state.isEnabled { SafariExtensionGuide.markWorking() }
      } catch {
        enabled = false
      }
    }

    private func openSafariSettings() {
      SFSafariApplication.showPreferencesForExtension(withIdentifier: Self.extensionIdentifier) { failure in
        Task { @MainActor in
          error = failure?.localizedDescription
        }
      }
    }
  #endif

  // MARK: - First invite link

  private static let seenKey = "SafariExtensionGuide.seen"
  private static let workingKey = "SafariExtensionGuide.working"

  /// A link came in from the extension, so it is set up already.
  static func markWorking() {
    UserDefaults.standard.set(true, forKey: workingKey)
  }

  static func markSeen() {
    UserDefaults.standard.set(true, forKey: seenKey)
  }

  /// Offer the guide once, with the first invite opened inside the app,
  /// unless the extension already handed one over.
  static var shouldSuggest: Bool {
    let defaults = UserDefaults.standard
    return !defaults.bool(forKey: workingKey) && !defaults.bool(forKey: seenKey)
  }
}

/// The one-time hint under an invite preview.
struct SafariExtensionHint: View {
  @State private var visible = SafariExtensionGuide.shouldSuggest

  var body: some View {
    if visible {
      VStack(alignment: .leading, spacing: 8) {
        Label("Open invite links from Safari in Aicord", systemImage: "safari")
          .font(.subheadline.weight(.semibold))
        Text("Turn on the Aicord Invites extension and links like this one open here instead of on the website.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        HStack {
          NavigationLink("Show Me How") { SafariExtensionGuide() }
          Spacer()
          Button("Not Now") {
            SafariExtensionGuide.markSeen()
            withAnimation { visible = false }
          }
          .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .font(.footnote)
      }
      .padding(12)
      .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
  }
}
