//
//  InvitePreview.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// Invites looked up once per launch, shared by every card showing the same code.
@MainActor
@Observable
final class InviteCache {
  static let shared = InviteCache()

  enum Entry {
    case loading
    case loaded(Invite)
    case invalid
    case failed(String)
  }

  private(set) var entries: [String: Entry] = [:]

  func entry(for code: String) -> Entry { entries[code] ?? .loading }

  func load(_ code: String, gw: GatewayStore, force: Bool = false) async {
    if !force, let entry = entries[code] {
      if case .failed = entry {} else { return }
    }
    entries[code] = .loading
    do {
      let response = try await gw.client.resolveInvite(
        code: code, withCounts: true, withExpiration: true)
      if let error = response.asError() {
        if case .jsonError(let json) = error, json.code == .unknownInvite {
          entries[code] = .invalid
        } else if Int(response.httpResponse.status.code) == 404 {
          entries[code] = .invalid
        } else {
          throw error
        }
        return
      }
      entries[code] = .loaded(try response.decode())
    } catch {
      entries[code] = .failed(error.localizedDescription)
    }
  }
}

/// What an invite leads to and whether you're already there.
struct InvitePreview: View {
  enum Style { case card, sheet }

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss
  @Environment(\.theme) var theme
  let code: String
  var style: Style = .card

  @State private var joining = false
  @State private var error: String?

  private var cache: InviteCache { .shared }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(heading)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)

      switch cache.entry(for: code) {
      case .loading:
        HStack(spacing: 12) {
          RoundedRectangle(cornerRadius: 14)
            .fill(.secondary.opacity(0.2))
            .frame(width: iconSize, height: iconSize)
          ProgressView()
        }
      case .invalid:
        HStack(spacing: 12) {
          Image(systemName: "link.badge.plus")
            .font(.title2)
            .frame(width: iconSize, height: iconSize)
            .background(.secondary.opacity(0.2), in: .rect(cornerRadius: 14))
          VStack(alignment: .leading) {
            Text("Invalid Invite").font(.headline)
            Text("This invite may have expired, or you might not have permission to join.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      case .failed(let message):
        VStack(alignment: .leading, spacing: 6) {
          Text(message).font(.caption).foregroundStyle(.secondary)
          Button("Try Again") { Task { await cache.load(code, gw: gw, force: true) } }
        }
      case .loaded(let invite):
        loaded(invite)
      }
    }
    .padding(style == .card ? 12 : 0)
    .frame(maxWidth: style == .card ? 425 : .infinity, alignment: .leading)
    .background {
      if style == .card {
        theme.common.tertiaryBackground.clipShape(.rounded)
      }
    }
    .task(id: code) { await cache.load(code, gw: gw) }
    .alert(
      "Couldn't Join",
      isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(error ?? "")
    }
  }

  private var iconSize: CGFloat { style == .card ? 50 : 72 }

  private var heading: LocalizedStringKey {
    if case .loaded(let invite) = cache.entry(for: code) {
      switch invite.type {
      case .groupDm: return "You've been invited to join a group DM"
      case .friend: return "You've been sent a friend invite"
      default: break
      }
    }
    return "You've been invited to join a server"
  }

  @ViewBuilder
  private func loaded(_ invite: Invite) -> some View {
    let layout =
      style == .card
      ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 12))
    layout {
      icon(invite)
      VStack(alignment: style == .card ? .leading : .center, spacing: 2) {
        Text(title(of: invite))
          .font(style == .card ? .headline : .title2.bold())
          .lineLimit(2)
          .multilineTextAlignment(style == .card ? .leading : .center)
        counts(invite)
      }
      if style == .card {
        Spacer(minLength: 0)
        actionButton(invite)
      }
    }
    .frame(maxWidth: .infinity, alignment: style == .card ? .leading : .center)

    if style == .sheet {
      actionButton(invite)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
  }

  @ViewBuilder
  private func icon(_ invite: Invite) -> some View {
    if let guild = invite.guild, let hash = guild.icon,
      let url = DiscordImageURL.guildIcon(id: guild.id, icon: hash, animated: true)
    {
      NukeImage(url: url)
        .resizable()
        .scaledToFill()
        .frame(width: iconSize, height: iconSize)
        .clipShape(.rect(cornerRadius: 14))
    } else {
      Text(initials(title(of: invite)))
        .font(style == .card ? .headline : .title)
        .frame(width: iconSize, height: iconSize)
        .background(.secondary.opacity(0.2), in: .rect(cornerRadius: 14))
    }
  }

  @ViewBuilder
  private func counts(_ invite: Invite) -> some View {
    HStack(spacing: 10) {
      if let online = invite.approximate_presence_count {
        Label {
          Text("\(online) Online")
        } icon: {
          Circle().fill(.green).frame(width: 8, height: 8)
        }
      }
      if let members = invite.approximate_member_count {
        Label {
          Text("^[\(members) Member](inflect: true)")
        } icon: {
          Circle().fill(.secondary).frame(width: 8, height: 8)
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .labelStyle(.titleAndIcon)
  }

  @ViewBuilder
  private func actionButton(_ invite: Invite) -> some View {
    if isMember(of: invite) {
      Button("Open") { open(invite) }
        .buttonStyle(.bordered)
    } else {
      Button {
        Task { await join(invite) }
      } label: {
        if joining {
          ProgressView().controlSize(.small)
        } else {
          Text(invite.type == .friend ? "Accept" : "Join")
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(.green)
      .disabled(joining)
    }
  }

  private func title(of invite: Invite) -> String {
    if let name = invite.guild?.name { return name }
    if let name = invite.channel?.name, !name.isEmpty { return name }
    if let inviter = invite.inviter {
      return inviter.global_name ?? inviter.username
    }
    return String(localized: "Unknown")
  }

  private func initials(_ name: String) -> String {
    String(name.split(separator: " ").prefix(3).compactMap(\.first))
  }

  private func isMember(of invite: Invite) -> Bool {
    if let guild = invite.guild { return gw.user.guilds[guild.id] != nil }
    if invite.type == .friend, let inviter = invite.inviter {
      return gw.user.relationships[inviter.id]?.type == .friend
    }
    if invite.type == .groupDm, let channel = invite.channel {
      return gw.user.privateChannels[channel.id] != nil
    }
    return false
  }

  private func open(_ invite: Invite) {
    if let guild = invite.guild {
      appState.selectedGuild = guild.id
      if let channel = invite.channel?.id { appState.selectedChannel = channel }
    } else if invite.type == .groupDm, let channel = invite.channel {
      appState.selectedGuild = nil
      appState.selectedChannel = channel.id
    } else {
      return
    }
    appState.chatOpen = true
    appState.invitePreviewCode = nil
    if style == .sheet { dismiss() }
  }

  /// Captcha, when Discord asks for one, goes through the client's own retry.
  private func join(_ invite: Invite) async {
    joining = true
    defer { joining = false }
    do {
      let response = try await gw.client.acceptInvite(code: invite.code, payload: .init())
      if let failure = response.asError() { throw failure }
      // the server arrives over the gateway shortly after
      for _ in 0..<50 where !isMember(of: invite) {
        try await Task.sleep(for: .milliseconds(200))
      }
      if isMember(of: invite) { open(invite) }
    } catch {
      self.error = Self.text(for: error)
    }
  }

  static func text(for error: any Error) -> String {
    if let response = error as? DiscordHTTPErrorResponse, case .jsonError(let json) = response {
      switch json.code {
      case .maxNumberOfGuildsReached:
        return String(localized: "You've reached the limit of servers you can be in.")
      case .userIsBannedFromGuild:
        return String(localized: "You're banned from this server.")
      case .unknownInvite:
        return String(localized: "This invite is invalid or has expired.")
      default:
        return json.message
      }
    }
    return error.localizedDescription
  }
}

/// The invite from a tapped link or one handed over from Safari.
struct InvitePreviewSheet: View {
  @Environment(\.dismiss) var dismiss
  let code: String

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        InvitePreview(code: code, style: .sheet)
        SafariExtensionHint()
      }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle("Invite")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
          }
          ToolbarItem(placement: .primaryAction) {
            ShareLink(item: InviteLink.url(for: code))
          }
        }
    }
    .presentationDetents([.medium, .large])
    #if os(macOS)
      .frame(minWidth: 360, idealWidth: 400, minHeight: 320)
    #endif
  }
}

/// `invitePreviewCode` as an identifiable sheet item.
struct InviteCode: Identifiable, Hashable {
  let code: String
  var id: String { code }
}
