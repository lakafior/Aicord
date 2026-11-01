//
//  ServerAdmin.swift
//  Aicord
//
//  Server management for moderators: channels and categories, roles, bans
//  and the audit log. Each part shows only with the permission Discord asks
//  for, and everything that removes something asks first.
//

import AicordKit
import SwiftUI

/// The management links in a server's settings, for the parts you may manage.
struct ServerAdminSection: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }

  private func can(_ permission: Permission) -> Bool {
    guild?.hasPermission(channel: nil as DiscordChannel?, permission) == true
  }

  var body: some View {
    if can(.manageChannels) || can(.manageRoles) || can(.banMembers) || can(.viewAuditLog) {
      Section {
        if can(.manageChannels) {
          NavigationLink {
            ChannelsAdminView(guildId: guildId)
          } label: {
            Label("Channels", systemImage: "number")
          }
        }
        if can(.manageRoles) {
          NavigationLink {
            RolesAdminView(guildId: guildId)
          } label: {
            Label("Roles", systemImage: "tag")
          }
        }
        if can(.banMembers) {
          NavigationLink {
            BansView(guildId: guildId)
          } label: {
            Label("Bans", systemImage: "hand.raised")
          }
        }
        if can(.viewAuditLog) {
          NavigationLink {
            AuditLogView(guildId: guildId)
          } label: {
            Label("Audit Log", systemImage: "list.bullet.rectangle")
          }
        }
      } header: {
        Text("Server Management")
      } footer: {
        Text("Members are moderated from their profile or a message's menu.")
      }
    }
  }
}

// MARK: - Channels

/// The server's channels by category; tap one to edit it, drag to reorder
/// within its category.
struct ChannelsAdminView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw

  @State private var newKind: NewChannelSheet.Kind?
  @State private var error: String?

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }

  private var allChannels: [DiscordChannel] {
    (guild?.channels.values.map { $0 } ?? []).sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }

  private var categories: [DiscordChannel] {
    allChannels.filter { $0.type == .guildCategory }
  }

  /// A category's channels in Discord's order: text-like ones first, then voice.
  private func children(of parent: ChannelSnowflake?) -> [DiscordChannel] {
    allChannels
      .filter { $0.type != .guildCategory && $0.parent_id.map { ChannelSnowflake($0) } == parent }
      .sorted { lhs, rhs in
        let lhsVoice = lhs.type == .guildVoice || lhs.type == .guildStageVoice
        let rhsVoice = rhs.type == .guildVoice || rhs.type == .guildStageVoice
        if lhsVoice != rhsVoice { return !lhsVoice }
        return (lhs.position ?? 0) < (rhs.position ?? 0)
      }
  }

  var body: some View {
    List {
      let loose = children(of: nil)
      if !loose.isEmpty {
        Section {
          rows(loose)
        }
      }
      ForEach(categories, id: \.id) { category in
        Section {
          rows(children(of: category.id))
        } header: {
          NavigationLink {
            ChannelEditorView(guildId: guildId, channelId: category.id)
          } label: {
            HStack {
              Text(category.name ?? "")
              Spacer()
              Image(systemName: "pencil")
                .accessibilityLabel(Text("Edit Category"))
            }
          }
          .buttonStyle(.plain)
        }
      }
      Section {
      } footer: {
        Text("Drag a channel to move it within its category.")
      }
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #else
      .listStyle(.inset)
    #endif
    .navigationTitle("Channels")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("New Channel", systemImage: "number") { newKind = .channel }
          Button("New Category", systemImage: "folder") { newKind = .category }
        } label: {
          Label("Add", systemImage: "plus")
        }
      }
    }
    .sheet(item: $newKind) { kind in
      NewChannelSheet(guildId: guildId, kind: kind)
    }
    .saveErrorAlert($error)
  }

  @ViewBuilder
  private func rows(_ channels: [DiscordChannel]) -> some View {
    ForEach(channels, id: \.id) { channel in
      NavigationLink {
        ChannelEditorView(guildId: guildId, channelId: channel.id)
      } label: {
        Label(channel.name ?? "", systemImage: ChannelButton.symbol(for: channel.type))
      }
    }
    .onMove { source, destination in
      var reordered = channels
      reordered.move(fromOffsets: source, toOffset: destination)
      move(reordered)
    }
  }

  /// Sends the new order of one category's channels; the gateway brings it back.
  private func move(_ reordered: [DiscordChannel]) {
    let payload = reordered.enumerated().map { index, channel in
      Payloads.ModifyGuildChannelPositions(id: channel.id, position: index)
    }
    saveInBackground($error) {
      try await gw.client.updateGuildChannelPositions(guildId: guildId, payload: payload).guardSuccess()
    }
  }
}

/// Name, topic, slowmode, age restriction and category of one channel, or the
/// name of a category; deleting asks first.
struct ChannelEditorView: View {
  let guildId: GuildSnowflake
  let channelId: ChannelSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  /// Discord's slowmode steps, in seconds.
  static let slowmodeSteps = [0, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 21_600]

  @State private var name = ""
  @State private var topic = ""
  @State private var slowmode = 0
  @State private var nsfw = false
  @State private var parent: ChannelSnowflake?
  @State private var loaded = false
  @State private var isSaving = false
  @State private var confirmsDelete = false
  @State private var error: String?

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }
  private var channel: DiscordChannel? { guild?.channels[channelId] }
  private var isCategory: Bool { channel?.type == .guildCategory }
  private var isVoice: Bool { channel?.type == .guildVoice || channel?.type == .guildStageVoice }
  private var hasTopic: Bool {
    [.guildText, .guildAnnouncement, .guildForum, .guildMedia].contains(channel?.type)
  }

  private var categories: [DiscordChannel] {
    (guild?.channels.values.filter { $0.type == .guildCategory } ?? [])
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }

  private var hasChanges: Bool {
    guard let channel else { return false }
    return name != (channel.name ?? "") || topic != (channel.topic ?? "")
      || slowmode != (channel.rate_limit_per_user ?? 0) || nsfw != (channel.nsfw ?? false)
      || parent != channel.parent_id.map { ChannelSnowflake($0) }
  }

  var body: some View {
    Form {
      Section {
        TextField(isCategory ? "Category Name" : "Channel Name", text: $name)
          .channelNameField()
        if hasTopic {
          TextField("Topic", text: $topic, axis: .vertical)
            .lineLimit(1...5)
        }
      }
      if !isCategory {
        if !isVoice {
          Section {
            Picker("Slowmode", selection: $slowmode) {
              ForEach(Self.slowmodeSteps, id: \.self) { seconds in
                if seconds == 0 {
                  Text("Off").tag(seconds)
                } else {
                  Text(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
                    .tag(seconds)
                }
              }
            }
            Toggle("Age-Restricted", isOn: $nsfw)
          } footer: {
            Text("With slowmode, members wait between messages. People who can manage the channel or messages aren't slowed down.")
          }
        }
        Section {
          Picker("Category", selection: $parent) {
            Text("No Category").tag(ChannelSnowflake?.none)
            ForEach(categories, id: \.id) { category in
              Text(category.name ?? "").tag(Optional(category.id))
            }
          }
        }
      }
      Section {
        Button(isCategory ? "Delete Category" : "Delete Channel", role: .destructive) {
          confirmsDelete = true
        }
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
    .navigationTitle(channel?.name ?? "")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save") { save() }
            .disabled(!hasChanges || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
    .confirmationDialog(
      isCategory ? "Delete the category \(channel?.name ?? "")?" : "Delete #\(channel?.name ?? "")?",
      isPresented: $confirmsDelete,
      titleVisibility: .visible
    ) {
      Button(isCategory ? "Delete Category" : "Delete Channel", role: .destructive) { delete() }
      Button("Cancel", role: .cancel) {}
    } message: {
      if isCategory {
        Text("Its channels stay, without a category.")
      } else {
        Text("Its messages are deleted with it. This can't be undone.")
      }
    }
    .saveErrorAlert($error)
    .onAppear(perform: load)
  }

  private func load() {
    guard !loaded, let channel else { return }
    loaded = true
    name = channel.name ?? ""
    topic = channel.topic ?? ""
    slowmode = channel.rate_limit_per_user ?? 0
    nsfw = channel.nsfw ?? false
    parent = channel.parent_id.map { ChannelSnowflake($0) }
  }

  private func save() {
    guard let channel else { return }
    let payload = Payloads.ModifyGuildChannel(
      name: name != channel.name ? name : nil,
      topic: hasTopic && topic != (channel.topic ?? "") ? topic : nil,
      nsfw: !isCategory && nsfw != (channel.nsfw ?? false) ? nsfw : nil,
      rate_limit_per_user: !isCategory && slowmode != (channel.rate_limit_per_user ?? 0) ? slowmode : nil,
      parent_id: !isCategory && parent != channel.parent_id.map { ChannelSnowflake($0) }
        ? parent.map { AnySnowflake($0) } : nil
    )
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.updateGuildChannel(id: channelId, payload: payload).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func delete() {
    Task {
      do {
        try await gw.client.deleteChannel(id: channelId).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// Makes a channel (text, voice, forum or announcement) or a category.
struct NewChannelSheet: View {
  enum Kind: String, Identifiable {
    case channel, category
    var id: String { rawValue }
  }

  let guildId: GuildSnowflake
  let kind: Kind
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  @State private var name = ""
  @State private var type: DiscordChannel.Kind = .guildText
  @State private var parent: ChannelSnowflake?
  @State private var isCreating = false
  @State private var error: String?

  private var categories: [DiscordChannel] {
    (gw.existingGuildStore(for: guildId)?.channels.values.filter { $0.type == .guildCategory } ?? [])
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }

  var body: some View {
    NavigationStack {
      Form {
        if kind == .channel {
          Section {
            Picker("Type", selection: $type) {
              Label("Text", systemImage: "number").tag(DiscordChannel.Kind.guildText)
              Label("Voice", systemImage: "speaker.wave.2.fill").tag(DiscordChannel.Kind.guildVoice)
              Label("Forum", systemImage: "bubble.left.and.text.bubble.right").tag(DiscordChannel.Kind.guildForum)
              Label("Announcement", systemImage: "megaphone.fill").tag(DiscordChannel.Kind.guildAnnouncement)
            }
            #if os(iOS)
              .pickerStyle(.inline)
              .labelsHidden()
            #endif
          } footer: {
            Text("Announcement channels need a Community server.")
          }
        }
        Section {
          TextField(kind == .category ? "Category Name" : "Channel Name", text: $name)
            .channelNameField()
          if kind == .channel {
            Picker("Category", selection: $parent) {
              Text("No Category").tag(ChannelSnowflake?.none)
              ForEach(categories, id: \.id) { category in
                Text(category.name ?? "").tag(Optional(category.id))
              }
            }
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(kind == .category ? "New Category" : "New Channel")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isCreating {
            ProgressView()
          } else {
            Button("Create") { create() }
              .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
      .saveErrorAlert($error)
    }
    #if os(macOS)
      .frame(minWidth: 400, minHeight: 360)
    #endif
  }

  private func create() {
    let payload = Payloads.CreateGuildChannel(
      name: name.trimmingCharacters(in: .whitespaces),
      type: kind == .category ? .guildCategory : type,
      parent_id: kind == .channel ? parent.map { AnySnowflake($0) } : nil
    )
    isCreating = true
    Task {
      defer { isCreating = false }
      do {
        try await gw.client.createGuildChannel(guildId: guildId, payload: payload).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Roles

/// The server's roles, highest first; tap one to edit it.
struct RolesAdminView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw

  @State private var created: RoleSnowflake?
  @State private var isCreating = false
  @State private var error: String?

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }

  private var roles: [Role] {
    (guild?.allRoles ?? []).sorted { $0.position > $1.position }
  }

  var body: some View {
    List {
      Section {
        ForEach(roles, id: \.id) { role in
          NavigationLink {
            RoleEditorView(guildId: guildId, roleId: role.id)
          } label: {
            HStack(spacing: 10) {
              RoleColorDot(color: role.color)
              Text(role.name)
              Spacer()
              if role.managed {
                Image(systemName: "lock.fill")
                  .foregroundStyle(.tertiary)
                  .accessibilityLabel(Text("Managed by an integration"))
              }
            }
          }
        }
      } footer: {
        Text("You can edit roles below your highest one. Roles made by bots and integrations are managed by them.")
      }
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #else
      .listStyle(.inset)
    #endif
    .navigationTitle("Roles")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if isCreating {
          ProgressView()
        } else {
          Button("New Role", systemImage: "plus") { create() }
        }
      }
    }
    .navigationDestination(item: $created) { roleId in
      RoleEditorView(guildId: guildId, roleId: roleId)
    }
    .saveErrorAlert($error)
  }

  private func create() {
    isCreating = true
    Task {
      defer { isCreating = false }
      do {
        let role = try await gw.client.createGuildRole(
          guildId: guildId, payload: .init(name: String(localized: "new role"))
        ).decode()
        created = role.id
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// A role's name, colour, display options and the basic permissions.
struct RoleEditorView: View {
  let guildId: GuildSnowflake
  let roleId: RoleSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  /// Discord's colour swatches.
  static let swatches: [Int] = [
    0x1ABC9C, 0x2ECC71, 0x3498DB, 0x9B59B6, 0xE91E63, 0xF1C40F, 0xE67E22, 0xE74C3C, 0x95A5A6, 0x607D8B,
  ]

  /// The permissions most servers set, grouped like Discord's own list.
  static let permissionGroups: [(LocalizedStringKey, [(Permission, LocalizedStringKey)])] = [
    (
      "General",
      [
        (.viewChannel, "View Channels"),
        (.manageChannels, "Manage Channels"),
        (.manageRoles, "Manage Roles"),
        (.manageGuildExpressions, "Manage Expressions"),
        (.viewAuditLog, "View Audit Log"),
        (.manageGuild, "Manage Server"),
      ]
    ),
    (
      "Membership",
      [
        (.createInstantInvite, "Create Invite"),
        (.changeNickname, "Change Nickname"),
        (.manageNicknames, "Manage Nicknames"),
        (.kickMembers, "Kick Members"),
        (.banMembers, "Ban Members"),
        (.moderateMembers, "Timeout Members"),
      ]
    ),
    (
      "Text",
      [
        (.sendMessages, "Send Messages"),
        (.embedLinks, "Embed Links"),
        (.attachFiles, "Attach Files"),
        (.addReactions, "Add Reactions"),
        (.mentionEveryone, "Mention @everyone, @here and All Roles"),
        (.manageMessages, "Manage Messages"),
        (.pinMessages, "Pin Messages"),
        (.readMessageHistory, "Read Message History"),
      ]
    ),
    (
      "Voice",
      [
        (.connect, "Connect"),
        (.speak, "Speak"),
        (.muteMembers, "Mute Members"),
        (.moveMembers, "Move Members"),
      ]
    ),
    (
      "Advanced",
      [
        (.administrator, "Administrator")
      ]
    ),
  ]

  @State private var name = ""
  @State private var color: Color = .gray
  @State private var colorValue = 0
  @State private var hoist = false
  @State private var mentionable = false
  @State private var permissions: StringBitField<Permission> = []
  @State private var loaded = false
  @State private var isSaving = false
  @State private var confirmsDelete = false
  @State private var error: String?

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }
  private var role: Role? { guild?.role(roleId) }
  private var isEveryone: Bool { roleId.rawValue == guildId.rawValue }

  /// Roles at or above yours, and integration roles, can only be looked at.
  private var isEditable: Bool {
    guard let guild, let role, !role.managed else { return false }
    return Moderation.isOwner(guild) || role.position < Moderation.myRank(in: guild)
  }

  private var hasChanges: Bool {
    guard let role else { return false }
    return name != role.name || colorValue != role.color.value || hoist != role.hoist
      || mentionable != role.mentionable || permissions != role.permissions
  }

  var body: some View {
    Form {
      if !isEveryone {
        Section {
          TextField("Role Name", text: $name)
        }
        Section {
          ScrollView(.horizontal) {
            HStack(spacing: 10) {
              swatch(0)
              ForEach(Self.swatches, id: \.self) { swatch($0) }
              ColorPicker("Custom Color", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { _, newValue in
                  colorValue = Self.rgb(newValue)
                }
            }
            .padding(.vertical, 4)
          }
          .scrollIndicators(.hidden)
        } header: {
          Text("Color")
        }
        Section {
          Toggle("Show Separately in the Member List", isOn: $hoist)
          Toggle("Anyone Can @mention This Role", isOn: $mentionable)
        }
      }
      ForEach(Self.permissionGroups.indices, id: \.self) { index in
        let group = Self.permissionGroups[index]
        Section {
          ForEach(group.1.indices, id: \.self) { item in
            let (permission, title) = group.1[item]
            Toggle(title, isOn: binding(permission))
          }
        } header: {
          Text(group.0)
        } footer: {
          if group.1.contains(where: { $0.0 == .administrator }) {
            Text("Administrator gives every permission and skips channel overrides. Give it with care.")
          }
        }
      }
      if !isEveryone {
        Section {
          Button("Delete Role", role: .destructive) { confirmsDelete = true }
        }
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
    .disabled(!isEditable)
    .navigationTitle(role?.name ?? "")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save") { save() }
            .disabled(!isEditable || !hasChanges || (!isEveryone && name.trimmingCharacters(in: .whitespaces).isEmpty))
        }
      }
    }
    .confirmationDialog(
      "Delete the role \(role?.name ?? "")?", isPresented: $confirmsDelete, titleVisibility: .visible
    ) {
      Button("Delete Role", role: .destructive) { delete() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Members who have it lose it. This can't be undone.")
    }
    .saveErrorAlert($error)
    .onAppear(perform: load)
  }

  private func swatch(_ value: Int) -> some View {
    Button {
      colorValue = value
      color = value == 0 ? .gray : Color(rgb: value)
    } label: {
      Circle()
        .fill(value == 0 ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(Color(rgb: value)))
        .frame(width: 30, height: 30)
        .overlay {
          if colorValue == value {
            Image(systemName: "checkmark")
              .font(.caption.weight(.bold))
              .foregroundStyle(.white)
          }
        }
        .overlay {
          Circle().strokeBorder(.primary.opacity(colorValue == value ? 0.6 : 0), lineWidth: 2)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(value == 0 ? Text("Default") : Text(verbatim: String(format: "#%06X", value)))
    .accessibilityAddTraits(colorValue == value ? .isSelected : [])
  }

  private func binding(_ permission: Permission) -> Binding<Bool> {
    Binding {
      permissions.contains(permission)
    } set: { isOn in
      if isOn { permissions.insert(permission) } else { permissions.remove(permission) }
    }
  }

  private func load() {
    guard !loaded, let role else { return }
    loaded = true
    name = role.name
    colorValue = role.color.value
    color = role.color.value == 0 ? .gray : Color(rgb: role.color.value)
    hoist = role.hoist
    mentionable = role.mentionable
    permissions = role.permissions
  }

  private func save() {
    guard let role else { return }
    let payload = Payloads.GuildRole(
      name: !isEveryone && name != role.name ? name : nil,
      permissions: permissions != role.permissions ? permissions : nil,
      color: colorValue != role.color.value ? DiscordColor(value: colorValue) : nil,
      hoist: hoist != role.hoist ? hoist : nil,
      mentionable: mentionable != role.mentionable ? mentionable : nil
    )
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.updateGuildRole(guildId: guildId, roleId: roleId, payload: payload).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func delete() {
    Task {
      do {
        try await gw.client.deleteGuildRole(guildId: guildId, roleId: roleId).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  /// A colour as Discord's 0xRRGGBB integer.
  static func rgb(_ color: Color) -> Int {
    let resolved = color.resolve(in: EnvironmentValues())
    let red = Int((max(0, min(1, resolved.red)) * 255).rounded())
    let green = Int((max(0, min(1, resolved.green)) * 255).rounded())
    let blue = Int((max(0, min(1, resolved.blue)) * 255).rounded())
    return (red << 16) | (green << 8) | blue
  }
}

extension View {
  /// Discord lowercases text channel names itself; don't capitalise or correct them.
  fileprivate func channelNameField() -> some View {
    self
      .autocorrectionDisabled()
      #if os(iOS)
        .textInputAutocapitalization(.never)
      #endif
  }
}

extension Color {
  /// A colour from a 0xRRGGBB integer.
  init(rgb: Int) {
    self.init(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }
}

// MARK: - Bans

/// Banned people, with their reason; unbanning asks first.
struct BansView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw

  @State private var bans: [Guild.Ban] = []
  @State private var isLoading = true
  @State private var unbanning: Guild.Ban?
  @State private var error: String?

  var body: some View {
    List {
      ForEach(bans, id: \.user.id) { ban in
        HStack(spacing: 12) {
          Profile.Avatar(member: nil, user: ban.user.toPartialUser())
            .frame(width: 32, height: 32)
          VStack(alignment: .leading, spacing: 2) {
            Text(ban.user.global_name ?? ban.user.username)
            Text(ban.reason ?? String(localized: "No reason given"))
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
          Spacer()
          Button("Unban") { unbanning = ban }
            .buttonStyle(.bordered)
        }
      }
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #endif
    .overlay {
      if isLoading {
        ProgressView()
      } else if bans.isEmpty {
        ContentUnavailableView("No Bans", systemImage: "hand.raised")
      }
    }
    .navigationTitle("Bans")
    .refreshable { await load() }
    .task { await load() }
    .confirmationDialog(
      "Unban \(unbanning?.user.username ?? "")?",
      isPresented: Binding(get: { unbanning != nil }, set: { if !$0 { unbanning = nil } }),
      titleVisibility: .visible,
      presenting: unbanning
    ) { ban in
      Button("Unban") { unban(ban) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("They can join again with an invite.")
    }
    .saveErrorAlert($error)
  }

  private func load() async {
    defer { isLoading = false }
    do {
      bans = try await gw.client.listGuildBans(guildId: guildId, limit: 1000).decode()
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func unban(_ ban: Guild.Ban) {
    Task {
      do {
        try await gw.client.unbanUserFromGuild(guildId: guildId, userId: ban.user.id).guardSuccess()
        bans.removeAll { $0.user.id == ban.user.id }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Audit log

/// Who did what on the server, newest first, 50 at a time.
struct AuditLogView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw

  @State private var entries: [GuildAuditLog.Entry] = []
  @State private var users: [UserSnowflake: PartialUser] = [:]
  @State private var isLoading = true
  @State private var reachedEnd = false
  @State private var error: String?

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }

  var body: some View {
    List {
      ForEach(entries) { entry in
        AuditLogRow(
          entry: entry,
          actor: entry.user_id.flatMap { users[$0] },
          target: target(of: entry)
        )
      }
      if !entries.isEmpty && !reachedEnd {
        Button("Load More") { Task { await load(more: true) } }
          .disabled(isLoading)
      }
    }
    #if os(iOS)
      .listStyle(.insetGrouped)
    #endif
    .overlay {
      if isLoading && entries.isEmpty {
        ProgressView()
      } else if !isLoading && entries.isEmpty {
        ContentUnavailableView("Nothing Logged Yet", systemImage: "list.bullet.rectangle")
      }
    }
    .navigationTitle("Audit Log")
    .refreshable { await load(more: false) }
    .task { await load(more: false) }
    .saveErrorAlert($error)
  }

  /// What the entry acted on, by name where Aicord knows it.
  private func target(of entry: GuildAuditLog.Entry) -> String? {
    guard let id = entry.target_id else { return nil }
    if let user = users[UserSnowflake(id)] {
      return user.global_name ?? user.username
    }
    if let channel = guild?.channels[ChannelSnowflake(id)] {
      return channel.type == .guildCategory ? channel.name : "#\(channel.name ?? "")"
    }
    if let role = guild?.role(RoleSnowflake(id)) {
      return "@\(role.name)"
    }
    // a deleted channel or role still has its name in the changes
    let nameChange = entry.changes?.first { $0.key == "name" }
    if case .string(let name) = nameChange?.old_value ?? nameChange?.new_value {
      return name
    }
    return nil
  }

  private func load(more: Bool) async {
    isLoading = true
    defer { isLoading = false }
    do {
      let page = try await gw.client.listGuildAuditLogEntries(
        guildID: guildId, before: more ? entries.last?.id : nil
      ).decode()
      for user in page.users ?? [] { users[user.id] = user }
      entries = more ? entries + page.audit_log_entries : page.audit_log_entries
      reachedEnd = page.audit_log_entries.count < 50
    } catch {
      self.error = error.localizedDescription
    }
  }
}

private struct AuditLogRow: View {
  let entry: GuildAuditLog.Entry
  let actor: PartialUser?
  let target: String?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: Self.symbol(entry.action_type))
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(.fill.tertiary, in: .rect(cornerRadius: 8))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(Self.describe(entry.action_type))
          .font(.body.weight(.medium))
        if let target {
          Text(target)
            .font(.subheadline)
        }
        if let reason = entry.reason, !reason.isEmpty {
          Text("Reason: \(reason)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        HStack(spacing: 4) {
          Text(actor?.global_name ?? actor?.username ?? String(localized: "Someone"))
          Text(verbatim: "·")
          if let date = entry.id.parse()?.date {
            Text(date, format: .relative(presentation: .named))
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  /// Discord's audit log action types, by their numbers.
  static func describe(_ action: Int) -> LocalizedStringKey {
    switch action {
    case 1: "Server Updated"
    case 10: "Channel Created"
    case 11: "Channel Updated"
    case 12: "Channel Deleted"
    case 13, 14, 15: "Channel Permissions Changed"
    case 20: "Member Kicked"
    case 21: "Members Pruned"
    case 22: "Member Banned"
    case 23: "Member Unbanned"
    case 24: "Member Updated"
    case 25: "Member Roles Changed"
    case 26: "Member Moved in Voice"
    case 27: "Member Disconnected from Voice"
    case 28: "Bot Added"
    case 30: "Role Created"
    case 31: "Role Updated"
    case 32: "Role Deleted"
    case 40: "Invite Created"
    case 41: "Invite Updated"
    case 42: "Invite Deleted"
    case 50, 51, 52: "Webhook Changed"
    case 60, 61, 62: "Emoji Changed"
    case 72: "Messages Deleted"
    case 73: "Messages Bulk Deleted"
    case 74: "Message Pinned"
    case 75: "Message Unpinned"
    case 80, 81, 82: "Integration Changed"
    case 83, 84, 85: "Stage Changed"
    case 90, 91, 92: "Sticker Changed"
    case 100, 101, 102: "Event Changed"
    case 110, 111, 112: "Thread Changed"
    case 121: "Command Permissions Changed"
    case 140, 141, 142, 143, 144, 145: "AutoMod"
    case 150, 151: "Onboarding Changed"
    case 163, 164, 165, 166, 167: "Onboarding Changed"
    default: "Other Change"
    }
  }

  static func symbol(_ action: Int) -> String {
    switch action {
    case 1: "gearshape"
    case 10...15: "number"
    case 20, 21: "figure.walk.departure"
    case 22, 23: "hand.raised"
    case 24, 25, 26, 27, 28: "person"
    case 30...32: "tag"
    case 40...42: "link"
    case 72...75: "text.bubble"
    case 140...145: "shield.lefthalf.filled"
    default: "list.bullet"
    }
  }
}
