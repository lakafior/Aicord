//
//  ConnectionsSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var connectionsSection: some View {
    ConnectionsSettings()
  }
}

/// Accounts on other services linked to Discord, with how each shows on the
/// profile and in the status, and a way to remove one. Adding a connection
/// needs the service's own sign-in, so that happens on discord.com.
struct ConnectionsSettings: View {
  typealias Connection = DiscordUser.Connection

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.openURL) var openURL

  @State private var state: LoadState = .loading
  @State private var removing: Connection?

  private static let addURL = URL(string: "https://discord.com/settings/connections")!

  var body: some View {
    switch state {
    case .loading:
      Section {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      }
      .task { await load() }
    case .failed:
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text("Couldn't load your connections.")
            .foregroundStyle(.secondary)
          // Back to loading, whose `.task` fetches again.
          Button("Try Again") { state = .loading }
        }
      }
    case .loaded(let connections):
      if connections.isEmpty {
        Section {
          Text("No connections")
            .foregroundStyle(.secondary)
        }
      }

      ForEach(connections, id: \.key) { connection in
        connectionSection(connection)
      }

      Section {
        Button("Add Connection on discord.com", systemImage: "plus.circle") {
          openURL(Self.addURL)
        }
      } footer: {
        Text("Linking a new account needs that service's sign-in, so it opens Discord's website. Come back here afterwards.")
      }
    }
  }

  @ViewBuilder
  private func connectionSection(_ connection: Connection) -> some View {
    Section {
      ConnectionRow(connection: connection)

      if connection.revoked == true {
        Label("This connection has expired. Remove it and add it again on discord.com.", systemImage: "exclamationmark.triangle")
          .font(.subheadline)
          .foregroundStyle(.orange)
      }

      Toggle(
        "Display on Profile",
        isOn: binding(for: connection, get: { $0.visibility == .everyone }) {
          Payloads.ModifyConnection(visibility: $0 ? .everyone : Connection.VisibilityKind.none)
        }
      )

      if connection.metadata?.isEmpty == false {
        Toggle(
          "Display Details on Profile",
          isOn: binding(for: connection, get: { $0.metadata_visibility == .everyone }) {
            Payloads.ModifyConnection(metadata_visibility: $0 ? .everyone : Connection.VisibilityKind.none)
          }
        )
        // Details only show where the connection itself does.
        .disabled(connection.visibility != .everyone)
      }

      if ConnectionRow.showsActivity(connection.type) || connection.show_activity {
        Toggle(
          "Display as Status",
          isOn: binding(for: connection, get: \.show_activity) {
            Payloads.ModifyConnection(show_activity: $0)
          }
        )
      }

      Button("Remove", role: .destructive) {
        removing = connection
      }
      .confirmationDialog(
        "Remove \(ConnectionRow.serviceName(connection.type))?",
        isPresented: Binding(
          get: { removing?.key == connection.key },
          set: { if !$0 { removing = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Remove", role: .destructive) { remove(connection) }
      } message: {
        Text("\(connection.name ?? ConnectionRow.serviceName(connection.type)) is unlinked from your account. Servers you joined through it may remove you.")
      }
    }
  }

  private enum LoadState {
    case loading
    case loaded([Connection])
    case failed
  }

  // MARK: - Requests

  private func load() async {
    do {
      let connections = try await gw.client.listOwnConnections().decode()
      // Contact sync isn't an account to show or manage here.
      state = .loaded(connections.filter { $0.type != .contacts })
    } catch {
      // Leaving the screen cancels the request; that is not a failure.
      guard !Task.isCancelled else { return }
      state = .failed
    }
  }

  /// A toggle that shows the change at once and keeps what the server answers,
  /// or puts the old value back if the request fails.
  private func binding(
    for connection: Connection,
    get: @escaping (Connection) -> Bool,
    payload: @escaping (Bool) -> Payloads.ModifyConnection
  ) -> Binding<Bool> {
    Binding(
      get: { current(connection).map(get) ?? get(connection) },
      set: { newValue in
        guard let old = current(connection) else { return }
        var optimistic = old
        apply(payload(newValue), to: &optimistic)
        replace(optimistic)
        Task {
          do {
            let updated = try await gw.client
              .modifyOwnConnection(type: old.type, id: old.id, payload: payload(newValue))
              .decode()
            replace(updated)
          } catch {
            replace(old)
            appState.error = error
          }
        }
      }
    )
  }

  private func apply(_ payload: Payloads.ModifyConnection, to connection: inout Connection) {
    if let visibility = payload.visibility { connection.visibility = visibility }
    if let metadataVisibility = payload.metadata_visibility {
      connection.metadata_visibility = metadataVisibility
    }
    if let showActivity = payload.show_activity { connection.show_activity = showActivity }
    if let friendSync = payload.friend_sync { connection.friend_sync = friendSync }
  }

  private func current(_ connection: Connection) -> Connection? {
    guard case .loaded(let all) = state else { return nil }
    return all.first { $0.key == connection.key }
  }

  private func replace(_ connection: Connection) {
    guard case .loaded(var all) = state,
      let index = all.firstIndex(where: { $0.key == connection.key })
    else { return }
    all[index] = connection
    state = .loaded(all)
  }

  private func remove(_ connection: Connection) {
    Task {
      do {
        try await gw.client.deleteOwnConnection(type: connection.type, id: connection.id)
          .guardSuccess()
        if case .loaded(let all) = state {
          state = .loaded(all.filter { $0.key != connection.key })
        }
      } catch {
        appState.error = error
      }
    }
  }
}

extension DiscordUser.Connection {
  /// Ids are only unique within one service.
  fileprivate var key: String { "\(type.rawValue)/\(id)" }
}

private struct ConnectionRow: View {
  let connection: DiscordUser.Connection

  var body: some View {
    HStack(spacing: 12) {
      Text(Self.monogram(connection.type))
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(Self.color(connection.type), in: .rect(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(connection.name ?? Self.serviceName(connection.type))
            .font(.headline)
          if connection.verified {
            Image(systemName: "checkmark.seal.fill")
              .foregroundStyle(.blue)
              .accessibilityLabel("Verified")
          }
        }
        Text(Self.serviceName(connection.type))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  /// Services whose activity Discord can show as the status.
  static func showsActivity(_ service: DiscordUser.Connection.Service) -> Bool {
    switch service {
    case .spotify, .xbox, .playstation, .crunchyroll, .amazonMusic,
      .leagueOfLegends, .riotGames:
      true
    default:
      false
    }
  }

  static func serviceName(_ service: DiscordUser.Connection.Service) -> String {
    switch service {
    case .amazonMusic: "Amazon Music"
    case .battleNet: "Battle.net"
    case .bungie: "Bungie.net"
    case .bluesky: "Bluesky"
    case .contacts: "Contact Sync"
    case .crunchyroll: "Crunchyroll"
    case .domain: "Domain"
    case .ebay: "eBay"
    case .epicGames: "Epic Games"
    case .facebook: "Facebook"
    case .github: "GitHub"
    case .instagram: "Instagram"
    case .leagueOfLegends: "League of Legends"
    case .mastodon: "Mastodon"
    case .paypal: "PayPal"
    case .playstation, .playstationStaging: "PlayStation Network"
    case .reddit: "Reddit"
    case .riotGames: "Riot Games"
    case .roblox: "Roblox"
    case .samsung: "Samsung Galaxy"
    case .soundcloud: "SoundCloud"
    case .spotify: "Spotify"
    case .skype: "Skype"
    case .steam: "Steam"
    case .tikTok: "TikTok"
    case .twitch: "Twitch"
    case .twitter: "X"
    case .xbox: "Xbox"
    case .youtube: "YouTube"
    case .__undocumented(let raw): raw.capitalized
    }
  }

  static func monogram(_ service: DiscordUser.Connection.Service) -> String {
    switch service {
    case .amazonMusic: "AM"
    case .battleNet: "B"
    case .epicGames: "EG"
    case .github: "GH"
    case .leagueOfLegends: "LoL"
    case .playstation, .playstationStaging: "PS"
    case .paypal: "PP"
    case .riotGames: "R"
    case .soundcloud: "SC"
    case .tikTok: "TT"
    case .twitter: "X"
    case .youtube: "YT"
    default: String(serviceName(service).prefix(1)).uppercased()
    }
  }

  static func color(_ service: DiscordUser.Connection.Service) -> Color {
    let hex: UInt32 =
      switch service {
      case .amazonMusic: 0x25D1DA
      case .battleNet: 0x148EFF
      case .bungie: 0x0071BC
      case .bluesky: 0x1185FE
      case .crunchyroll: 0xF47521
      case .ebay: 0x0064D2
      case .epicGames: 0x313131
      case .facebook: 0x0866FF
      case .github: 0x24292F
      case .instagram: 0xE4405F
      case .leagueOfLegends: 0xC28F2C
      case .mastodon: 0x6364FF
      case .paypal: 0x003087
      case .playstation, .playstationStaging: 0x0070D1
      case .reddit: 0xFF4500
      case .riotGames: 0xD32936
      case .roblox: 0x393B3D
      case .samsung: 0x1428A0
      case .soundcloud: 0xFF5500
      case .spotify: 0x1DB954
      case .skype: 0x00AFF0
      case .steam: 0x1B2838
      case .tikTok: 0x000000
      case .twitch: 0x9146FF
      case .twitter: 0x000000
      case .xbox: 0x107C10
      case .youtube: 0xFF0000
      default: 0x5865F2
      }
    return Color(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
