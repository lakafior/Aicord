//
//  ActivityNotice.swift
//  Aicord
//

import AicordKit
import SwiftUI

/// Says that an app (Wordle and the like) is running as an Activity here, or
/// invites to one, and that Aicord can't open it: Open in Discord instead.
struct ActivityNotice: View {
  var applicationID: ApplicationSnowflake
  var channel: ChannelStore
  var participants = 0
  /// The application, when the message already carries it.
  var knownApp: PartialApplication?
  var dismiss: (() -> Void)?

  @Environment(\.gateway) var gw
  @Environment(\.openURL) var openURL
  @Environment(\.theme) var theme
  @State private var app: PartialApplication?

  private static var cache: [ApplicationSnowflake: PartialApplication] = [:]

  private var shown: PartialApplication? { knownApp ?? app }

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if let icon = shown?.icon,
          let url = DiscordImageURL.applicationIcon(id: applicationID, icon: icon, size: 64)
        {
          NukeImage(url: url).resizable().scaledToFill()
        } else {
          Image(systemName: "gamecontroller.fill")
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 36, height: 36)
      .clipShape(.rect(cornerRadius: 8))
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(shown?.name ?? String(localized: "An app"))
            .font(.subheadline.weight(.semibold))
          if participants > 0 {
            Text("· ^[\(participants) person](inflect: true) playing")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Text("This app opens an Activity, which Aicord can't run yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button("Open in Discord") { openInDiscord() }
        .buttonStyle(.bordered)
        .controlSize(.small)

      if let dismiss {
        Button(action: dismiss) {
          Image(systemName: "xmark")
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("Dismiss"))
      }
    }
    .padding(10)
    .frame(maxWidth: 480, alignment: .leading)
    .background(theme.common.tertiaryBackground, in: .rect(cornerRadius: 12))
    .accessibilityElement(children: .contain)
    .task(id: applicationID) { await loadApp() }
  }

  /// The channel's web link; with Discord installed it opens the app.
  private func openInDiscord() {
    let guild = channel.guildStore?.guildId.rawValue ?? "@me"
    if let url = URL(string: "https://discord.com/channels/\(guild)/\(channel.channelId.rawValue)") {
      openURL(url)
    }
  }

  private func loadApp() async {
    guard knownApp == nil else { return }
    if let cached = Self.cache[applicationID] {
      app = cached
      return
    }
    // public details, no authorization needed
    if let loaded = try? await gw.client.getApplicationRPC(applicationID: applicationID).decode() {
      Self.cache[applicationID] = loaded
      app = loaded
    }
  }
}
