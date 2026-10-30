//
//  DevicesSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var devicesSection: some View {
    DevicesSettings()
  }
}

/// Where the account is logged in, with a way to log out of other devices.
/// This client's own session is shown apart and can't be logged out here.
struct DevicesSettings: View {
  typealias AuthSession = UserAuthenticationSessions.Session

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @State private var state: LoadState = .loading
  @State private var loggingOut: AuthSession?
  @State private var confirmsLogOutAll = false

  private var currentHash: String? { gw.user.authSessionIdHash }

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
          Text("Couldn't load your devices.")
            .foregroundStyle(.secondary)
          // Back to loading, whose `.task` fetches again.
          Button("Try Again") { state = .loading }
        }
      }
    case .loaded(let sessions):
      let current = sessions.first { $0.id_hash == currentHash }
      let others = sessions.filter { $0.id_hash != currentHash }

      if let current {
        Section("This Device") {
          DeviceRow(session: current)
        }
      }

      Section {
        if others.isEmpty {
          Text("No other devices")
            .foregroundStyle(.secondary)
        }
        ForEach(others) { session in
          DeviceRow(session: session)
            .contextMenu {
              Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                loggingOut = session
              }
            }
            .swipeActions {
              // Not `.destructive`: that role removes the row before the
              // confirmation is answered.
              Button("Log Out") {
                loggingOut = session
              }
              .tint(.red)
            }
            .confirmationDialog(
              "Log out of \(DeviceRow.title(for: session))?",
              isPresented: Binding(
                get: { loggingOut?.id == session.id },
                set: { if !$0 { loggingOut = nil } }
              ),
              titleVisibility: .visible
            ) {
              Button("Log Out", role: .destructive) { logOut([session]) }
            } message: {
              Text("This device will have to log in again to use your account.")
            }
        }
      } header: {
        Text(current == nil ? "Devices" : "Other Devices")
      } footer: {
        Text("Devices logged in to your account. Locations are approximate. If you don't recognise a device, log it out and change your password.")
      }

      if !others.isEmpty {
        Section {
          Button("Log Out All Known Devices", role: .destructive) {
            confirmsLogOutAll = true
          }
          .confirmationDialog(
            "Log out all known devices?",
            isPresented: $confirmsLogOutAll,
            titleVisibility: .visible
          ) {
            Button("Log Out All", role: .destructive) { logOut(others) }
          } message: {
            Text("Every device except this one will have to log in again.")
          }
        }
      }
    }
  }

  private enum LoadState {
    case loading
    case loaded([AuthSession])
    case failed
  }

  // MARK: - Requests

  private func load() async {
    do {
      let sessions = try await gw.client.getAuthSessions().decode().user_sessions
      state = .loaded(
        sessions.sorted { $0.approx_last_used_time.date > $1.approx_last_used_time.date }
      )
    } catch {
      // Leaving the screen cancels the request; that is not a failure.
      guard !Task.isCancelled else { return }
      state = .failed
    }
  }

  private func logOut(_ sessions: [AuthSession]) {
    // Never this client's own session: that would log Aicord out mid-request.
    let hashes = sessions.map(\.id_hash).filter { $0 != currentHash }
    guard !hashes.isEmpty else { return }
    Task {
      do {
        try await gw.client.logoutAuthSessions(hashes).guardSuccess()
        if case .loaded(let all) = state {
          state = .loaded(all.filter { !hashes.contains($0.id_hash) })
        }
      } catch {
        appState.error = error
      }
    }
  }
}

private struct DeviceRow: View {
  let session: DevicesSettings.AuthSession

  private var info: UserAuthenticationSessions.Session.ClientInfo { session.client_info }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: Self.symbol(for: session))
        .font(.title2)
        .foregroundStyle(.secondary)
        .frame(width: 40, height: 40)
        .background(.secondary.opacity(0.15), in: .rect(cornerRadius: 10))

      VStack(alignment: .leading, spacing: 2) {
        Text(Self.title(for: session))
          .font(.headline)
        let details = [info.platform, info.location]
          .compactMap { $0 }
          .filter { !$0.isEmpty }
        if !details.isEmpty {
          Text(details.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Text("Last used \(session.approx_last_used_time.date, format: .relative(presentation: .named))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  static func title(for session: DevicesSettings.AuthSession) -> String {
    if let os = session.client_info.os, !os.isEmpty { return os }
    return String(localized: "Unknown Device")
  }

  static func symbol(for session: DevicesSettings.AuthSession) -> String {
    let os = (session.client_info.os ?? "").lowercased()
    let platform = (session.client_info.platform ?? "").lowercased()
    if os.contains("ipad") { return "ipad" }
    if os.contains("ios") || os.contains("android") { return "iphone" }
    if !platform.isEmpty && !platform.contains("discord") { return "globe" }
    if os.contains("mac") || os.contains("windows") || os.contains("linux") { return "laptopcomputer" }
    return "questionmark.circle"
  }
}
