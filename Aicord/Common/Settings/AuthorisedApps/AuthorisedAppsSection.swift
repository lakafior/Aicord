//
//  AuthorisedAppsSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var authorisedAppsSection: some View {
    AuthorisedAppsSettings()
  }
}

/// Bots and sites the account has signed in to with Discord, with what each
/// may do, and a way to take that access back.
struct AuthorisedAppsSettings: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @State private var state: LoadState = .loading
  @State private var revoking: OAuth2Authorization?

  var body: some View {
    Section {
      switch state {
      case .loading:
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      case .failed:
        VStack(alignment: .leading, spacing: 8) {
          Text("Couldn't load your authorised apps.")
            .foregroundStyle(.secondary)
          Button("Try Again") {
            Task { await load() }
          }
        }
      case .loaded(let authorizations) where authorizations.isEmpty:
        Text("No authorised apps")
          .foregroundStyle(.secondary)
      case .loaded(let authorizations):
        ForEach(authorizations) { authorization in
          AuthorisedAppRow(authorization: authorization)
            .contextMenu {
              Button("Deauthorise", systemImage: "xmark.circle", role: .destructive) {
                revoking = authorization
              }
            }
            .swipeActions {
              // Not `.destructive`: that role removes the row before the
              // confirmation is answered.
              Button("Deauthorise") {
                revoking = authorization
              }
              .tint(.red)
            }
            .confirmationDialog(
              "Deauthorise \(authorization.application.name ?? String(localized: "App"))?",
              isPresented: Binding(
                get: { revoking?.id == authorization.id },
                set: { if !$0 { revoking = nil } }
              ),
              titleVisibility: .visible
            ) {
              Button("Deauthorise", role: .destructive) { revoke(authorization) }
            } message: {
              Text("The app loses access to your account. To use it again, you have to authorise it again.")
            }
        }
      }
    } footer: {
      Text("Apps and sites you signed in to with Discord. Deauthorising one takes back its access to your account.")
    }
    .task { await load() }
  }

  private enum LoadState {
    case loading
    case loaded([OAuth2Authorization])
    case failed
  }

  // MARK: - Requests

  private func load() async {
    state = .loading
    do {
      let authorizations = try await gw.client.listOAuth2Tokens().decode()
      state = .loaded(
        authorizations.sorted {
          ($0.application.name ?? "").localizedCaseInsensitiveCompare($1.application.name ?? "")
            == .orderedAscending
        }
      )
    } catch {
      // Leaving the screen cancels the request; that is not a failure.
      guard !Task.isCancelled else { return }
      state = .failed
    }
  }

  private func revoke(_ authorization: OAuth2Authorization) {
    Task {
      do {
        try await gw.client.revokeOAuth2Token(id: authorization.id).guardSuccess()
        if case .loaded(let authorizations) = state {
          state = .loaded(authorizations.filter { $0.id != authorization.id })
        }
      } catch {
        appState.error = error
      }
    }
  }
}

private struct AuthorisedAppRow: View {
  let authorization: OAuth2Authorization

  private var application: PartialApplication { authorization.application }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      icon
        .frame(width: 40, height: 40)
        .clipShape(.rect(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(application.name ?? String(localized: "Unknown App"))
            .font(.headline)
          if application.bot != nil {
            Text("Bot")
              .font(.caption2.bold())
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.tint.opacity(0.2), in: .capsule)
          }
        }
        if let description = application.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        VStack(alignment: .leading, spacing: 2) {
          ForEach(authorization.scopes.map(\.rawValue), id: \.self) { scope in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Image(systemName: "checkmark")
                .imageScale(.small)
              Text(Self.describe(scope: scope))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .padding(.top, 2)
      }
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private var icon: some View {
    if let hash = application.icon {
      NukeImage(url: DiscordImageURL.applicationIcon(id: application.id, icon: hash, size: 80))
        .resizable()
        .scaledToFill()
    } else {
      Text((application.name ?? "?").prefix(1))
        .font(.headline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.secondary.opacity(0.2))
    }
  }

  /// What a scope lets the app do, in plain words. Unknown scopes show their name.
  static func describe(scope: String) -> String {
    switch scope {
    case "identify": String(localized: "Knows your username, avatar and banner")
    case "email": String(localized: "Knows your email address")
    case "connections": String(localized: "Sees your connected accounts")
    case "guilds": String(localized: "Sees which servers you're in")
    case "guilds.join": String(localized: "Can add you to servers")
    case "guilds.members.read": String(localized: "Reads your member info in servers")
    case "guilds.channels.read": String(localized: "Sees the channels in your servers")
    case "gdm.join": String(localized: "Can add you to group DMs it manages")
    case "bot": String(localized: "Added a bot to a server")
    case "webhook.incoming": String(localized: "Posts to a channel through a webhook")
    case "applications.commands": String(localized: "Offers commands you can use")
    case "applications.commands.update": String(localized: "Updates its own commands")
    case "applications.commands.permissions.update":
      String(localized: "Updates its command permissions in your servers")
    case "applications.entitlements": String(localized: "Manages entitlements for your apps")
    case "applications.builds.read": String(localized: "Reads builds of your apps")
    case "applications.builds.upload": String(localized: "Uploads builds of your apps")
    case "applications.store.update": String(localized: "Manages store data of your apps")
    case "activities.read": String(localized: "Sees your activity")
    case "activities.write": String(localized: "Updates your activity")
    case "activities.invites.write": String(localized: "Sends activity invites")
    case "presences.read": String(localized: "Sees your status")
    case "presences.write": String(localized: "Updates your status")
    case "relationships.read": String(localized: "Sees your friends list")
    case "relationships.write": String(localized: "Manages your friends list")
    case "dm_channels.read": String(localized: "Sees your DMs and group DMs")
    case "dm_channels.messages.read": String(localized: "Reads messages in your DMs")
    case "dm_channels.messages.write": String(localized: "Sends messages in your DMs")
    case "messages.read": String(localized: "Reads messages in Discord on your computer")
    case "role_connections.write": String(localized: "Updates linked roles metadata")
    case "openid": String(localized: "Signs you in with your Discord account")
    case "voice": String(localized: "Joins voice for you and sees who's there")
    case "gateway.connect": String(localized: "Connects to Discord as you")
    case "lobbies.write": String(localized: "Manages game lobbies")
    case "account.global_name.update": String(localized: "Changes your display name")
    case "application_identities.write": String(localized: "Manages your identities in its apps")
    case "payment_sources.country_code": String(localized: "Knows your country")
    case "rpc": String(localized: "Controls Discord on your computer")
    case "rpc.activities.write": String(localized: "Updates your activity in Discord on your computer")
    case "rpc.notifications.read": String(localized: "Sees your notifications in Discord on your computer")
    case "rpc.voice.read": String(localized: "Sees your voice settings")
    case "rpc.voice.write": String(localized: "Changes your voice settings")
    case "rpc.video.read": String(localized: "Sees your video status")
    case "rpc.video.write": String(localized: "Changes your video settings")
    case "rpc.screenshare.read": String(localized: "Sees your screen share status")
    case "rpc.screenshare.write": String(localized: "Changes your screen share settings")
    case "sdk.social_layer", "sdk.social_layer_presence":
      String(localized: "Shows your Discord friends and status in its game")
    default: scope
    }
  }
}
