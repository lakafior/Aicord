//
//  ServerInvitesView.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// Server Settings → Invites: the server's active invite links, who made
/// them, how often they were used and when they run out, with Revoke.
/// Discord only lists them for people with Manage Server.
struct ServerInvitesView: View {
  @Environment(\.gateway) var gw
  let guildId: GuildSnowflake

  @State private var invites: [InviteWithMetadata]?
  @State private var loadError: String?
  @State private var revoking: InviteWithMetadata?
  @State private var error: String?

  var body: some View {
    Form {
      if let invites {
        if invites.isEmpty {
          ContentUnavailableView(
            "No Invites",
            systemImage: "link",
            description: Text("Nobody has made an invite link to this server, or they have all expired.")
          )
        } else {
          Section {
            ForEach(invites, id: \.code) { invite in
              row(invite)
            }
          } footer: {
            Text("Revoking a link stops it working for everyone. People who already joined stay.")
          }
        }
      } else if let loadError {
        ContentUnavailableView(
          "Can't Show Invites",
          systemImage: "exclamationmark.triangle",
          description: Text(loadError)
        )
      } else {
        HStack {
          Text("Loading invites…")
            .foregroundStyle(.secondary)
          Spacer()
          ProgressView()
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Invites")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .refreshable { await load() }
    .task { await load() }
    .confirmationDialog(
      "Revoke Invite?",
      isPresented: .init(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
      titleVisibility: .visible,
      presenting: revoking
    ) { invite in
      Button("Revoke \(invite.code)", role: .destructive) {
        Task { await revoke(invite) }
      }
    } message: { invite in
      Text("discord.gg/\(invite.code) will stop working.")
    }
    .saveErrorAlert($error)
  }

  private func row(_ invite: InviteWithMetadata) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: invite.code)
          .font(.body.monospaced())
          .textSelection(.enabled)
        Text(ServerInvites.details(of: invite))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Revoke", role: .destructive) { revoking = invite }
        #if os(iOS)
          .buttonStyle(.borderless)
        #endif
    }
    .contextMenu {
      Button("Copy Link", systemImage: "doc.on.doc") {
        copyToPasteboard(InviteLink.url(for: invite.code).absoluteString)
      }
      Button("Revoke", systemImage: "trash", role: .destructive) { revoking = invite }
    }
    #if os(iOS)
      .swipeActions {
        Button("Revoke", role: .destructive) { revoking = invite }
      }
    #endif
  }

  private func load() async {
    do {
      let response = try await gw.client.listGuildInvites(guildId: guildId)
      if let failure = response.asError() { throw failure }
      let list: [InviteWithMetadata] = try response.decode()
      invites = list.sorted { $0.created_at.date > $1.created_at.date }
      loadError = nil
    } catch is CancellationError {
      return
    } catch {
      invites = nil
      loadError = ServerInvites.text(for: error)
    }
  }

  private func revoke(_ invite: InviteWithMetadata) async {
    do {
      let response = try await gw.client.revokeInvite(code: invite.code)
      if let failure = response.asError() { throw failure }
      withAnimation { invites?.removeAll { $0.code == invite.code } }
    } catch {
      self.error = ServerInvites.text(for: error)
    }
  }
}

enum ServerInvites {
  /// "#general · by @name · 3 of 10 uses · expires in 6 days"
  static func details(of invite: InviteWithMetadata) -> String {
    var parts: [String] = []
    if let name = invite.channel?.name { parts.append("#" + name) }
    if let inviter = invite.inviter { parts.append(String(localized: "by @\(inviter.username)")) }
    if invite.max_uses > 0 {
      parts.append(String(localized: "\(invite.uses) of \(invite.max_uses) uses"))
    } else {
      parts.append(String(AttributedString(localized: "^[\(invite.uses) use](inflect: true)").characters))
    }
    if let expires = invite.expires_at {
      parts.append(
        String(localized: "expires \(expires.date.formatted(.relative(presentation: .numeric)))"))
    } else {
      parts.append(String(localized: "never expires"))
    }
    return parts.joined(separator: " · ")
  }

  static func text(for error: any Error) -> String {
    if let response = error as? DiscordHTTPErrorResponse, case .jsonError(let json) = response {
      switch json.code {
      case .missingPermissions, .missingAccess:
        return String(localized: "Only people with Manage Server can see and revoke this server's invites.")
      case .unknownInvite:
        return String(localized: "That invite no longer exists.")
      default:
        return json.message
      }
    }
    return error.localizedDescription
  }
}

// MARK: - Leave Server

extension View {
  /// Asks before leaving `guild`, then leaves it and goes back to Home.
  /// `onLeave` runs after Discord agreed, e.g. to close a sheet.
  func leaveServerConfirmation(
    isPresented: Binding<Bool>, guild: Guild?, onLeave: @escaping @MainActor () -> Void = {}
  ) -> some View {
    modifier(LeaveServerConfirmation(isPresented: isPresented, guild: guild, onLeave: onLeave))
  }
}

enum LeaveServer {
  /// The owner can't leave a server without handing it over first, so the
  /// option isn't offered to them.
  @MainActor
  static func canLeave(_ guild: Guild, gw: GatewayStore) -> Bool {
    guard let me = gw.user.currentUser?.id else { return false }
    return guild.owner_id != me
  }
}

private struct LeaveServerConfirmation: ViewModifier {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Binding var isPresented: Bool
  let guild: Guild?
  let onLeave: @MainActor () -> Void
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      // an alert rather than a popover: leaving can't be undone without a new invite
      .alert(
        "Leave \(guild?.name ?? "")?",
        isPresented: $isPresented
      ) {
        Button("Leave Server", role: .destructive) {
          guard let guild else { return }
          saveInBackground($error) {
            let response = try await gw.client.leaveGuild(id: guild.id)
            if let failure = response.asError() { throw failure }
            if appState.selectedGuild == guild.id {
              appState.selectedGuild = nil
            }
            onLeave()
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You won't be able to rejoin unless you are re-invited.")
      }
      .saveErrorAlert($error)
  }
}
