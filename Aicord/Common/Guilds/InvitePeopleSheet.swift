//
//  InvitePeopleSheet.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// Invite People from the server menu: a sheet of its own.
struct InvitePeopleSheet: View {
  @Environment(\.dismiss) var dismiss
  let guildId: GuildSnowflake
  var preferredChannel: ChannelSnowflake?

  var body: some View {
    NavigationStack {
      InvitePeopleView(guildId: guildId, preferredChannel: preferredChannel)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
    #if os(macOS)
      .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 480)
    #endif
  }
}

/// A link to the server, like Discord's Invite People: the channel it lands
/// in, how long it works and how many times. Discord hands back the same link
/// for the same settings, so changing them back doesn't pile up invites.
struct InvitePeopleView: View {
  @Environment(\.gateway) var gw
  let guildId: GuildSnowflake
  var preferredChannel: ChannelSnowflake?

  @State private var channelId: ChannelSnowflake?
  @State private var expiry: InviteExpiry = .sevenDays
  @State private var useLimit: InviteUseLimit = .unlimited
  @State private var invite: Invite?
  @State private var creating = false
  @State private var error: String?
  @State private var copied = false

  private var guild: Guild? { gw.user.guilds[guildId] }

  var body: some View {
    let channels = InvitePeople.channels(in: guildId, gw: gw)
    Form {
      if channels.isEmpty {
        Section {
          ContentUnavailableView(
            "Can't Invite",
            systemImage: "person.crop.circle.badge.xmark",
            description: Text("You don't have permission to create invites on this server.")
          )
        }
      } else {
        linkSection
        Section {
          Picker("Channel", selection: $channelId) {
            ForEach(channels, id: \.id) { channel in
              Text(verbatim: "# \(channel.name ?? "")").tag(Optional(channel.id))
            }
          }
          Picker("Expire After", selection: $expiry) {
            ForEach(InviteExpiry.allCases) { Text($0.title).tag($0) }
          }
          Picker("Max Number of Uses", selection: $useLimit) {
            ForEach(InviteUseLimit.allCases) { Text($0.title).tag($0) }
          }
        } header: {
          Text("Settings")
        } footer: {
          Text("Changing a setting makes a new link. Older links keep working until they expire.")
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Invite People")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      // permissions need the server's members and roles
      _ = gw.getGuildStore(for: guildId)
      if channelId == nil {
        channelId = InvitePeople.defaultChannel(
          in: guildId, preferred: preferredChannel, gw: gw)
      }
    }
    .task(id: InviteSettings(channel: channelId, expiry: expiry, useLimit: useLimit)) {
      await create()
    }
  }

  @ViewBuilder
  private var linkSection: some View {
    Section {
      if let invite {
        let url = InviteLink.url(for: invite.code)
        Text(url.absoluteString)
          .font(.body.monospaced())
          .textSelection(.enabled)
          .lineLimit(1)
          .truncationMode(.middle)
        Button(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc") {
          copyToPasteboard(url.absoluteString)
          copied = true
        }
        ShareLink(item: url) {
          Label("Share Link", systemImage: "square.and.arrow.up")
        }
      } else if let error {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
        Button("Try Again") { Task { await create() } }
      } else {
        HStack {
          Text("Creating a link…")
            .foregroundStyle(.secondary)
          Spacer()
          ProgressView()
        }
      }
    } header: {
      Text("Invite Link")
    } footer: {
      if let invite, !creating {
        Text(InvitePeople.summary(of: invite, expiry: expiry, useLimit: useLimit))
      }
    }
  }

  private func create() async {
    guard let channelId else { return }
    creating = true
    copied = false
    error = nil
    defer { creating = false }
    do {
      let response = try await gw.client.createChannelInvite(
        channelId: channelId,
        payload: .init(max_age: expiry.maxAge, max_uses: useLimit.maxUses, unique: false)
      )
      if let failure = response.asError() {
        throw failure
      }
      invite = try response.decode()
    } catch is CancellationError {
      return
    } catch {
      invite = nil
      self.error = InvitePeople.text(for: error)
    }
  }

  private struct InviteSettings: Equatable {
    var channel: ChannelSnowflake?
    var expiry: InviteExpiry
    var useLimit: InviteUseLimit
  }
}

enum InvitePeople {
  private static let invitableTypes: [DiscordChannel.Kind] = [
    .guildText, .guildAnnouncement, .guildVoice, .guildStageVoice, .guildForum, .guildMedia,
  ]

  /// Channels you can see and create invites for, in sidebar order.
  @MainActor
  static func channels(in guildId: GuildSnowflake, gw: GatewayStore) -> [DiscordChannel] {
    guard let guild = gw.user.guilds[guildId] else { return [] }
    let store = gw.existingGuildStore(for: guildId)
    return (guild.channels ?? [])
      .filter { channel in
        guard let type = channel.type, invitableTypes.contains(type) else { return false }
        guard let store else { return true }
        return store.hasPermission(channel: channel, .viewChannel)
          && store.hasPermission(channel: channel, .createInstantInvite)
      }
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }

  /// The channel you're in, if you can invite to it, else the first that works.
  @MainActor
  static func defaultChannel(
    in guildId: GuildSnowflake, preferred: ChannelSnowflake?, gw: GatewayStore
  ) -> ChannelSnowflake? {
    let channels = channels(in: guildId, gw: gw)
    if let preferred, channels.contains(where: { $0.id == preferred }) { return preferred }
    return channels.first(where: { $0.type == .guildText })?.id ?? channels.first?.id
  }

  static func summary(of invite: Invite, expiry: InviteExpiry, useLimit: InviteUseLimit) -> String {
    let expires =
      invite.expires_at.map {
        String(localized: "Expires \($0.date.formatted(.relative(presentation: .numeric))).")
      } ?? String(localized: "Never expires.")
    switch useLimit {
    case .unlimited: return expires
    // a plain String would keep the ^[…](inflect:) markup as it is
    default:
      return expires + " "
        + String(AttributedString(localized: "^[\(useLimit.rawValue) use](inflect: true) at most.").characters)
    }
  }

  static func text(for error: any Error) -> String {
    if let response = error as? DiscordHTTPErrorResponse, case .jsonError(let json) = response {
      switch json.code {
      case .missingPermissions:
        return String(localized: "You don't have permission to invite people to that channel.")
      case .maxNumberOfInvitesReached:
        return String(localized: "This server has reached its limit of invites.")
      default:
        return json.message
      }
    }
    return error.localizedDescription
  }
}

extension InviteExpiry {
  var title: LocalizedStringResource {
    switch self {
    case .thirtyMinutes: "30 minutes"
    case .oneHour: "1 hour"
    case .sixHours: "6 hours"
    case .twelveHours: "12 hours"
    case .oneDay: "1 day"
    case .sevenDays: "7 days"
    case .never: "Never"
    }
  }
}

extension InviteUseLimit {
  var title: LocalizedStringResource {
    switch self {
    case .unlimited: "No limit"
    default: "^[\(rawValue) use](inflect: true)"
    }
  }
}
