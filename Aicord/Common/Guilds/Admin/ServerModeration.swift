//
//  ServerModeration.swift
//  Aicord
//
//  Timeout, kick, ban and roles for one member, from their profile or a
//  message's menu. Every action asks first and can carry a reason, which
//  Discord keeps in the audit log. Only shown with the matching permission
//  and when your highest role is above theirs, the same rules Discord checks.
//

import AicordKit
import SwiftUI

/// A moderation action picked for one member.
struct ModerationTarget: Identifiable, Hashable {
  enum Action: String {
    case timeout, removeTimeout, kick, ban, roles
  }

  let guildId: GuildSnowflake
  let user: PartialUser
  let action: Action

  var id: String { "\(guildId.rawValue)-\(user.id.rawValue)-\(action.rawValue)" }
}

@MainActor
enum Moderation {
  /// How high someone sits in the server: the position of their highest role,
  /// with the owner above everyone.
  static func rank(of userId: UserSnowflake, in guild: GuildStore) -> Int {
    if guild.guild?.owner_id == userId { return .max }
    let roles = guild.member(userId)?.roles ?? []
    return roles.compactMap { guild.role($0)?.position }.max() ?? 0
  }

  static func isOwner(_ guild: GuildStore) -> Bool {
    guard let me = guild.gateway?.user.currentUser?.id else { return false }
    return guild.guild?.owner_id == me
  }

  /// Your rank, for what roles you can hand out or edit.
  static func myRank(in guild: GuildStore) -> Int {
    guard let me = guild.gateway?.user.currentUser?.id else { return 0 }
    return rank(of: me, in: guild)
  }

  /// Whether you can use a member permission on someone: never on yourself or
  /// the owner, and only on people below you.
  static func canAct(on userId: UserSnowflake, in guild: GuildStore, _ permission: Permission) -> Bool {
    guard let me = guild.gateway?.user.currentUser?.id, me != userId else { return false }
    guard guild.guild?.owner_id != userId else { return false }
    guard guild.hasPermission(channel: nil as DiscordChannel?, permission) else { return false }
    return isOwner(guild) || rank(of: me, in: guild) > rank(of: userId, in: guild)
  }

  static func isTimedOut(_ member: Guild.PartialMember?) -> Bool {
    guard let until = member?.communication_disabled_until?.date else { return false }
    return until > .now
  }

  /// What you can do to someone here, in menu order.
  static func actions(for user: PartialUser, in guild: GuildStore) -> [ModerationTarget.Action] {
    var actions: [ModerationTarget.Action] = []
    if guild.hasPermission(channel: nil as DiscordChannel?, .manageRoles), guild.member(user.id) != nil {
      actions.append(.roles)
    }
    if canAct(on: user.id, in: guild, .moderateMembers) {
      actions.append(isTimedOut(guild.member(user.id)) ? .removeTimeout : .timeout)
    }
    if canAct(on: user.id, in: guild, .kickMembers) { actions.append(.kick) }
    if canAct(on: user.id, in: guild, .banMembers) { actions.append(.ban) }
    return actions
  }
}

/// Menu items for the moderation actions you have on someone.
/// Picking one opens the app-wide sheet, or calls `pick` where a sheet is
/// already showing (the profile on iPhone) and has to present its own.
struct ModerationMenuItems: View {
  var guild: GuildStore
  var user: PartialUser
  var pick: ((ModerationTarget) -> Void)? = nil
  @Environment(\.appState) var appState

  var body: some View {
    ForEach(Moderation.actions(for: user, in: guild), id: \.self) { action in
      Button(role: action == .kick || action == .ban ? .destructive : nil) {
        let target = ModerationTarget(guildId: guild.guildId, user: user, action: action)
        if let pick { pick(target) } else { appState.moderationTarget = target }
      } label: {
        switch action {
        case .roles: Label("Roles…", systemImage: "tag")
        case .timeout: Label("Timeout…", systemImage: "clock.badge.xmark")
        case .removeTimeout: Label("Remove Timeout…", systemImage: "clock.arrow.circlepath")
        case .kick: Label("Kick…", systemImage: "figure.walk.departure")
        case .ban: Label("Ban…", systemImage: "hand.raised")
        }
      }
    }
  }
}

extension View {
  func moderationSheet() -> some View {
    self.modifier(ModerationSheetModifier())
  }
}

private struct ModerationSheetModifier: ViewModifier {
  @Environment(\.appState) var appState

  func body(content: Content) -> some View {
    @Bindable var appState = appState
    content
      .sheet(item: $appState.moderationTarget) { target in
        ModerationTargetSheet(target: target)
      }
  }
}

/// The sheet for one picked action: the role list, or the action's details.
struct ModerationTargetSheet: View {
  let target: ModerationTarget

  var body: some View {
    Group {
      if target.action == .roles {
        NavigationStack {
          MemberRolesView(guildId: target.guildId, user: target.user)
        }
      } else {
        ModerationSheet(target: target)
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, idealWidth: 460, minHeight: 440, idealHeight: 520)
    #endif
  }
}

/// Asks for the details of one action (how long, what to delete, why), then
/// confirms before sending it.
struct ModerationSheet: View {
  let target: ModerationTarget
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  /// Discord's own timeout lengths.
  static let timeoutLengths: [Duration] = [
    .seconds(60), .seconds(5 * 60), .seconds(10 * 60), .seconds(3600), .seconds(86_400), .seconds(7 * 86_400),
  ]
  /// How far back a ban deletes messages, at most 7 days.
  static let deleteHistoryLengths: [Duration] = [
    .zero, .seconds(3600), .seconds(6 * 3600), .seconds(12 * 3600), .seconds(86_400), .seconds(3 * 86_400),
    .seconds(7 * 86_400),
  ]

  @State private var reason = ""
  @State private var timeoutLength: Duration = .seconds(3600)
  @State private var deleteHistory: Duration = .zero
  @State private var confirming = false
  @State private var isWorking = false
  @State private var error: String?

  private var name: String {
    let member = gw.existingGuildStore(for: target.guildId)?.member(target.user.id)
    return member?.nick ?? target.user.global_name ?? target.user.username ?? String(localized: "Unknown User")
  }

  private var title: LocalizedStringKey {
    switch target.action {
    case .timeout: "Timeout"
    case .removeTimeout: "Remove Timeout"
    case .kick: "Kick"
    case .ban: "Ban"
    case .roles: "Roles"
    }
  }

  private var confirmTitle: String {
    switch target.action {
    case .timeout: String(localized: "Time out \(name)?")
    case .removeTimeout: String(localized: "Remove \(name)'s timeout?")
    case .kick: String(localized: "Kick \(name)?")
    case .ban: String(localized: "Ban \(name)?")
    case .roles: ""
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 12) {
            Profile.Avatar(member: gw.existingGuildStore(for: target.guildId)?.member(target.user.id), user: target.user)
              .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
              Text(name).font(.headline)
              if let username = target.user.username {
                Text(verbatim: "@\(username)")
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } footer: {
          footer
        }

        switch target.action {
        case .timeout:
          Section {
            Picker("Duration", selection: $timeoutLength) {
              ForEach(Self.timeoutLengths, id: \.self) { length in
                Text(length.formatted(.units(allowed: [.weeks, .days, .hours, .minutes, .seconds], width: .wide)))
                  .tag(length)
              }
            }
          }
        case .ban:
          Section {
            Picker("Delete Messages From", selection: $deleteHistory) {
              ForEach(Self.deleteHistoryLengths, id: \.self) { length in
                if length == .zero {
                  Text("Don't Delete Any").tag(length)
                } else {
                  Text("The Last \(length.formatted(.units(allowed: [.days, .hours], width: .wide)))")
                    .tag(length)
                }
              }
            }
          } footer: {
            Text("Messages they sent in that time are deleted from the whole server.")
          }
        default:
          EmptyView()
        }

        Section {
          TextField("Reason (optional)", text: $reason, axis: .vertical)
            .lineLimit(1...4)
        } footer: {
          Text("Shown in the server's audit log.")
        }
      }
      .formStyle(.grouped)
      .navigationTitle(title)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        OnboardingActionButton(title: title, isWorking: isWorking) { confirming = true }
          .tint(target.action == .removeTimeout ? Color.accentColor : .red)
      }
      .confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
        Button(title, role: target.action == .removeTimeout ? nil : .destructive) { perform() }
        Button("Cancel", role: .cancel) {}
      }
      .saveErrorAlert($error)
    }
  }

  @ViewBuilder
  private var footer: some View {
    switch target.action {
    case .timeout:
      Text("They can still read the server, but can't send messages, react, talk or join voice until the timeout ends.")
    case .removeTimeout:
      Text("They can talk again right away.")
    case .kick:
      Text("They're removed from the server and can come back with an invite.")
    case .ban:
      Text("They're removed from the server and can't come back, even with an invite, until they're unbanned.")
    case .roles:
      EmptyView()
    }
  }

  private func perform() {
    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    let reason = trimmed.isEmpty ? nil : trimmed
    let guildId = target.guildId
    let userId = target.user.id
    let client = gw.client
    let timeoutLength = timeoutLength
    let deleteSeconds = Int(deleteHistory.components.seconds)
    isWorking = true
    Task {
      defer { isWorking = false }
      do {
        switch target.action {
        case .timeout:
          let until = Date.now.addingTimeInterval(TimeInterval(timeoutLength.components.seconds))
          try await client.updateGuildMember(
            guildId: guildId, userId: userId, reason: reason,
            payload: .init(communication_disabled_until: .init(date: until))
          ).guardSuccess()
        case .removeTimeout:
          try await client.removeGuildMemberTimeout(guildId: guildId, userId: userId, reason: reason)
            .guardSuccess()
        case .kick:
          try await client.deleteGuildMember(guildId: guildId, userId: userId, reason: reason).guardSuccess()
        case .ban:
          try await client.banUserFromGuild(
            guildId: guildId, userId: userId, reason: reason,
            payload: .init(delete_message_seconds: deleteSeconds == 0 ? nil : deleteSeconds)
          ).guardSuccess()
        case .roles:
          break
        }
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// Roles you can hand out or take back from one member, below your own.
struct MemberRolesView: View {
  let guildId: GuildSnowflake
  let user: PartialUser
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  @State private var assigned: Set<RoleSnowflake> = []
  @State private var busy: Set<RoleSnowflake> = []
  @State private var error: String?

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }

  private var roles: [Role] {
    guard let guild else { return [] }
    return guild.allRoles
      .filter { $0.id.rawValue != guildId.rawValue && !$0.managed }
      .sorted { $0.position > $1.position }
  }

  private func canAssign(_ role: Role) -> Bool {
    guard let guild else { return false }
    return Moderation.isOwner(guild) || role.position < Moderation.myRank(in: guild)
  }

  var body: some View {
    Form {
      Section {
        ForEach(roles, id: \.id) { role in
          Toggle(isOn: binding(role)) {
            HStack(spacing: 10) {
              RoleColorDot(color: role.color)
              Text(role.name)
            }
          }
          .disabled(!canAssign(role) || busy.contains(role.id))
        }
      } footer: {
        Text("You can only give and take roles below your highest one.")
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
    .navigationTitle(Text("Roles"))
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
    .saveErrorAlert($error)
    .onAppear {
      assigned = Set(guild?.member(user.id)?.roles ?? [])
    }
  }

  private func binding(_ role: Role) -> Binding<Bool> {
    Binding {
      assigned.contains(role.id)
    } set: { isOn in
      if isOn { assigned.insert(role.id) } else { assigned.remove(role.id) }
      busy.insert(role.id)
      let client = gw.client
      Task {
        defer { busy.remove(role.id) }
        do {
          let response =
            isOn
            ? try await client.addGuildMemberRole(guildId: guildId, userId: user.id, roleId: role.id)
            : try await client.deleteGuildMemberRole(guildId: guildId, userId: user.id, roleId: role.id)
          try response.guardSuccess()
        } catch {
          if isOn { assigned.remove(role.id) } else { assigned.insert(role.id) }
          self.error = error.localizedDescription
        }
      }
    }
  }
}

/// A role's colour as a small dot; grey for roles without one.
struct RoleColorDot: View {
  var color: DiscordColor

  var body: some View {
    Circle()
      .fill(color.asColor() ?? .secondary)
      .frame(width: 12, height: 12)
      .accessibilityHidden(true)
  }
}
