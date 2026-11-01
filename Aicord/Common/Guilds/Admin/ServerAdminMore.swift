//
//  ServerAdminMore.swift
//  Aicord
//
//  The rest of server management: channel permission overrides, the order of
//  categories and roles, every role permission and role icons, AutoMod,
//  emoji and stickers, and deleting a server you own.
//

import AicordKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Permission catalog

/// Every permission, grouped and named like Discord's own lists.
@MainActor
enum PermissionCatalog {
  typealias Group = (title: LocalizedStringKey, items: [(Permission, LocalizedStringKey)])

  static let groups: [Group] = [
    (
      "General Server Permissions",
      [
        (.viewChannel, "View Channels"),
        (.manageChannels, "Manage Channels"),
        (.manageRoles, "Manage Roles"),
        (.createGuildExpressions, "Create Expressions"),
        (.manageGuildExpressions, "Manage Expressions"),
        (.viewAuditLog, "View Audit Log"),
        (.viewGuildInsights, "View Server Insights"),
        (.manageWebhooks, "Manage Webhooks"),
        (.manageGuild, "Manage Server"),
      ]
    ),
    (
      "Membership Permissions",
      [
        (.createInstantInvite, "Create Invite"),
        (.changeNickname, "Change Nickname"),
        (.manageNicknames, "Manage Nicknames"),
        (.kickMembers, "Kick, Approve and Reject Members"),
        (.banMembers, "Ban Members"),
        (.moderateMembers, "Timeout Members"),
      ]
    ),
    (
      "Text Channel Permissions",
      [
        (.sendMessages, "Send Messages and Create Posts"),
        (.sendMessagesInThreads, "Send Messages in Threads and Posts"),
        (.createPublicThreads, "Create Public Threads"),
        (.createPrivateThreads, "Create Private Threads"),
        (.embedLinks, "Embed Links"),
        (.attachFiles, "Attach Files"),
        (.addReactions, "Add Reactions"),
        (.useExternalEmojis, "Use External Emoji"),
        (.useExternalStickers, "Use External Stickers"),
        (.mentionEveryone, "Mention @everyone, @here and All Roles"),
        (.manageMessages, "Manage Messages"),
        (.pinMessages, "Pin Messages"),
        (.manageThreads, "Manage Threads and Posts"),
        (.readMessageHistory, "Read Message History"),
        (.sendTtsMessages, "Send Text-to-Speech Messages"),
        (.sendVoiceMessages, "Send Voice Messages"),
        (.sendPolls, "Create Polls"),
      ]
    ),
    (
      "Voice Channel Permissions",
      [
        (.connect, "Connect"),
        (.speak, "Speak"),
        (.stream, "Video"),
        (.useEmbeddedActivities, "Use Activities"),
        (.useSoundboard, "Use Soundboard"),
        (.useExternalSounds, "Use External Sounds"),
        (.useVAD, "Use Voice Activity"),
        (.prioritySpeaker, "Priority Speaker"),
        (.muteMembers, "Mute Members"),
        (.deafenMembers, "Deafen Members"),
        (.moveMembers, "Move Members"),
        (.setVoiceChannelStatus, "Set Voice Channel Status"),
      ]
    ),
    (
      "Apps Permissions",
      [
        (.useApplicationCommands, "Use Application Commands"),
        (.useExternalApps, "Use External Apps"),
      ]
    ),
    ("Stage Channel Permissions", [(.requestToSpeak, "Request to Speak")]),
    (
      "Events Permissions",
      [
        (.createEvents, "Create Events"),
        (.manageEvents, "Manage Events"),
      ]
    ),
    ("Advanced Permissions", [(.administrator, "Administrator")]),
  ]

  /// Permissions that only mean something server-wide, so channels can't override them.
  static let serverOnly: Set<Permission> = [
    .administrator, .manageGuild, .viewAuditLog, .viewGuildInsights, .kickMembers, .banMembers,
    .changeNickname, .manageNicknames, .moderateMembers, .manageGuildExpressions,
    .createGuildExpressions, .viewCreatorMonetizationAnalytics,
  ]

  static func count(in set: StringBitField<Permission>) -> Int {
    groups.flatMap(\.items).filter { set.contains($0.0) }.count
  }

  /// The groups for a channel override, without server-only permissions.
  static var channelGroups: [Group] {
    groups.compactMap { group in
      let items = group.items.filter { !serverOnly.contains($0.0) }
      return items.isEmpty ? nil : (group.title, items)
    }
  }
}

// MARK: - Channel permission overrides

/// The role and member overrides of one channel or category.
struct ChannelPermissionsView: View {
  let guildId: GuildSnowflake
  let channelId: ChannelSnowflake
  @Environment(\.gateway) var gw
  @State private var editing: OverwriteTarget?
  @State private var error: String?

  struct OverwriteTarget: Identifiable, Hashable {
    var id: AnySnowflake
    var kind: DiscordChannel.Overwrite.Kind
    var name: String
  }

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }
  private var channel: DiscordChannel? { guild?.channels[channelId] }
  private var overwrites: [DiscordChannel.Overwrite] { channel?.permission_overwrites ?? [] }

  private func name(of overwrite: DiscordChannel.Overwrite) -> String {
    switch overwrite.type {
    case .role:
      return guild?.role(RoleSnowflake(overwrite.id.rawValue))?.name ?? String(localized: "Deleted Role")
    default:
      let member = guild?.member(UserSnowflake(overwrite.id.rawValue))
      return member?.nick ?? member?.user?.global_name ?? member?.user?.username
        ?? overwrite.id.rawValue
    }
  }

  /// Roles and loaded members that don't have an override yet.
  private var candidates: [OverwriteTarget] {
    let taken = Set(overwrites.map(\.id.rawValue))
    let roles = (guild?.allRoles ?? []).sorted { $0.position > $1.position }
      .filter { !taken.contains($0.id.rawValue) }
      .map { OverwriteTarget(id: AnySnowflake($0.id.rawValue), kind: .role, name: $0.name) }
    let members = (guild?.loadedMembers ?? []).compactMap { member -> OverwriteTarget? in
      guard let user = member.user, !taken.contains(user.id.rawValue) else { return nil }
      return OverwriteTarget(
        id: AnySnowflake(user.id.rawValue), kind: .member,
        name: member.nick ?? user.global_name ?? user.username)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return roles + members
  }

  var body: some View {
    List {
      Section {
        ForEach(overwrites, id: \.id) { overwrite in
          Button {
            editing = OverwriteTarget(id: overwrite.id, kind: overwrite.type, name: name(of: overwrite))
          } label: {
            HStack {
              Label(
                name(of: overwrite),
                systemImage: overwrite.type == .role ? "tag" : "person")
              Spacer()
              let allowed = PermissionCatalog.count(in: overwrite.allow)
              let denied = PermissionCatalog.count(in: overwrite.deny)
              if allowed > 0 {
                Text(verbatim: "+\(allowed)")
                  .foregroundStyle(.green)
                  .accessibilityLabel(Text("Allowed: \(allowed)"))
              }
              if denied > 0 {
                Text(verbatim: "−\(denied)")
                  .foregroundStyle(.red)
                  .accessibilityLabel(Text("Denied: \(denied)"))
              }
            }
            .font(.body.monospacedDigit())
          }
          .foregroundStyle(.primary)
        }
      } footer: {
        Text(
          "Overrides change what a role or a person can do in this channel only. Member overrides win over role overrides."
        )
      }
    }
    .navigationTitle("Permissions")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          ForEach(candidates) { candidate in
            Button(candidate.name, systemImage: candidate.kind == .role ? "tag" : "person") {
              editing = candidate
            }
          }
        } label: {
          Label("Add Role or Member", systemImage: "plus")
        }
        .disabled(candidates.isEmpty)
      }
    }
    .sheet(item: $editing) { target in
      OverwriteEditorView(
        channelId: channelId, target: target,
        existing: overwrites.first { $0.id == target.id })
    }
    .saveErrorAlert($error)
  }
}

/// Allow, neutral or deny for each channel permission of one role or person.
struct OverwriteEditorView: View {
  let channelId: ChannelSnowflake
  let target: ChannelPermissionsView.OverwriteTarget
  let existing: DiscordChannel.Overwrite?
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  enum State3: Int, Hashable { case deny, neutral, allow }

  @State private var allow: StringBitField<Permission> = []
  @State private var deny: StringBitField<Permission> = []
  @State private var loaded = false
  @State private var isSaving = false
  @State private var confirmsRemove = false
  @State private var error: String?

  private func binding(_ permission: Permission) -> Binding<State3> {
    Binding {
      allow.contains(permission) ? .allow : deny.contains(permission) ? .deny : .neutral
    } set: { value in
      allow.remove(permission)
      deny.remove(permission)
      if value == .allow { allow.insert(permission) }
      if value == .deny { deny.insert(permission) }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        ForEach(PermissionCatalog.channelGroups.indices, id: \.self) { index in
          let group = PermissionCatalog.channelGroups[index]
          Section(group.title) {
            ForEach(group.items.indices, id: \.self) { item in
              let (permission, title) = group.items[item]
              LabeledContent(title) {
                Picker(title, selection: binding(permission)) {
                  Image(systemName: "xmark").tag(State3.deny)
                    .accessibilityLabel("Deny")
                  Image(systemName: "slash.circle").tag(State3.neutral)
                    .accessibilityLabel("Inherit")
                  Image(systemName: "checkmark").tag(State3.allow)
                    .accessibilityLabel("Allow")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 132)
              }
            }
          }
        }
        if existing != nil {
          Section {
            Button("Remove Override", role: .destructive) { confirmsRemove = true }
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(Text(verbatim: target.name))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Save", action: save)
          }
        }
      }
      .confirmationDialog(
        "Remove the override for \(target.name)?", isPresented: $confirmsRemove,
        titleVisibility: .visible
      ) {
        Button("Remove Override", role: .destructive, action: remove)
        Button("Cancel", role: .cancel) {}
      }
      .saveErrorAlert($error)
      .onAppear {
        guard !loaded else { return }
        loaded = true
        allow = existing?.allow ?? []
        deny = existing?.deny ?? []
      }
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 560)
    #endif
  }

  private func save() {
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.setChannelPermissionOverwrite(
          channelId: channelId, overwriteId: target.id,
          payload: .init(type: target.kind, allow: allow, deny: deny)
        ).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func remove() {
    Task {
      do {
        try await gw.client.deleteChannelPermissionOverwrite(
          channelId: channelId, overwriteId: target.id
        ).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Category order

/// Drag categories into a new order.
struct CategoryOrderView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss
  @State private var categories: [DiscordChannel] = []
  @State private var isSaving = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      List {
        ForEach(categories, id: \.id) { category in
          Label(category.name ?? "", systemImage: "folder")
        }
        .onMove { categories.move(fromOffsets: $0, toOffset: $1) }
      }
      #if os(iOS)
        .environment(\.editMode, .constant(.active))
      #endif
      .navigationTitle("Category Order")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Save", action: save)
          }
        }
      }
      .saveErrorAlert($error)
      .onAppear {
        categories = (gw.existingGuildStore(for: guildId)?.channels.values
          .filter { $0.type == .guildCategory } ?? [])
          .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
      }
    }
    #if os(macOS)
      .frame(minWidth: 360, minHeight: 420)
    #endif
  }

  private func save() {
    let payload = categories.enumerated().map { index, category in
      Payloads.ModifyGuildChannelPositions(id: category.id, position: index)
    }
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.updateGuildChannelPositions(guildId: guildId, payload: payload)
          .guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Role order

enum RoleOrder {
  /// New positions after a move, highest first; nil when it would move a role
  /// you can't manage. @everyone stays at the bottom.
  static func positions(
    after reordered: [Role], original: [Role], editable: (Role) -> Bool
  ) -> [Payloads.ModifyGuildRolePositions]? {
    // roles you can't manage must keep their place
    for (index, role) in original.enumerated() where !editable(role) {
      guard reordered.indices.contains(index), reordered[index].id == role.id else { return nil }
    }
    let count = reordered.count
    return reordered.enumerated().compactMap { index, role in
      let position = count - index
      return role.position == position ? nil : .init(id: role.id, position: position)
    }
  }
}

// MARK: - AutoMod

/// The server's AutoMod rules, for people with Manage Server.
struct AutoModView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw
  @State private var rules: [AutoModRule] = []
  @State private var isLoading = true
  @State private var editing: AutoModEditorTarget?
  @State private var error: String?

  struct AutoModEditorTarget: Identifiable {
    var id: String { rule?.id ?? "new-\(kind.rawValue)" }
    var rule: AutoModRule?
    var kind: AutoModRule.TriggerKind
  }

  static func title(_ kind: AutoModRule.TriggerKind) -> String {
    switch kind {
    case .keyword: String(localized: "Custom Keywords")
    case .spam: String(localized: "Suspected Spam")
    case .keywordPreset: String(localized: "Commonly Flagged Words")
    case .mentionSpam: String(localized: "Mention Spam")
    case .memberProfile: String(localized: "Member Profile Names")
    }
  }

  /// How many rules of a kind a server may have.
  static func limit(_ kind: AutoModRule.TriggerKind) -> Int {
    switch kind {
    case .keyword: 6
    default: 1
    }
  }

  private let creatable: [AutoModRule.TriggerKind] = [.keyword, .keywordPreset, .mentionSpam, .spam]

  var body: some View {
    List {
      Section {
        ForEach(rules) { rule in
          Button {
            editing = .init(rule: rule, kind: rule.trigger_type)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: rule.name)
                Text(verbatim: Self.title(rule.trigger_type))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(rule.enabled ? "On" : "Off")
                .foregroundStyle(rule.enabled ? .green : .secondary)
            }
          }
          .foregroundStyle(.primary)
        }
      } footer: {
        if !isLoading && rules.isEmpty {
          Text("No rules yet. AutoMod blocks or flags messages before anyone sees them.")
        }
      }
    }
    .overlay {
      if isLoading { ProgressView() }
    }
    .navigationTitle("AutoMod")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          ForEach(creatable, id: \.self) { kind in
            Button(Self.title(kind) as String) { editing = .init(rule: nil, kind: kind) }
              .disabled(rules.filter { $0.trigger_type == kind }.count >= Self.limit(kind))
          }
        } label: {
          Label("New Rule", systemImage: "plus")
        }
      }
    }
    .sheet(item: $editing, onDismiss: { Task { await load() } }) { target in
      AutoModRuleEditor(guildId: guildId, rule: target.rule, kind: target.kind)
    }
    .saveErrorAlert($error)
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    defer { isLoading = false }
    do {
      rules = try await gw.client.listAutoModRules(guildId: guildId).decode()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

/// One AutoMod rule: what it catches, what it does and who it skips.
struct AutoModRuleEditor: View {
  let guildId: GuildSnowflake
  let rule: AutoModRule?
  let kind: AutoModRule.TriggerKind
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  @State private var name = ""
  @State private var enabled = true
  @State private var keywords = ""
  @State private var regexes = ""
  @State private var allowList = ""
  @State private var presets: Set<Int> = []
  @State private var mentionLimit = 10
  @State private var raidProtection = false
  @State private var blocks = true
  @State private var customMessage = ""
  @State private var alertChannel: ChannelSnowflake?
  @State private var timeoutSeconds = 0
  @State private var exemptRoles: Set<RoleSnowflake> = []
  @State private var exemptChannels: Set<ChannelSnowflake> = []
  @State private var loaded = false
  @State private var isSaving = false
  @State private var confirmsDelete = false
  @State private var error: String?

  static let timeouts = [0, 60, 300, 600, 3600, 86_400, 604_800]

  private var guild: GuildStore? { gw.existingGuildStore(for: guildId) }
  private var textChannels: [DiscordChannel] {
    (guild?.channels.values.filter { $0.type == .guildText } ?? [])
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }
  private var canTimeout: Bool { kind == .keyword || kind == .mentionSpam }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Rule Name", text: $name)
          Toggle("Enabled", isOn: $enabled)
        }
        trigger
        Section {
          Toggle("Block the Message", isOn: $blocks)
          if blocks {
            TextField("Message Shown to the Member", text: $customMessage, axis: .vertical)
          }
          Picker("Send an Alert To", selection: $alertChannel) {
            Text("No Alert").tag(ChannelSnowflake?.none)
            ForEach(textChannels, id: \.id) { channel in
              Text(verbatim: "#" + (channel.name ?? "")).tag(Optional(channel.id))
            }
          }
          if canTimeout {
            Picker("Timeout the Member", selection: $timeoutSeconds) {
              ForEach(Self.timeouts, id: \.self) { seconds in
                if seconds == 0 {
                  Text("Off").tag(seconds)
                } else {
                  Text(Duration.seconds(seconds).formatted(.units(allowed: [.weeks, .days, .hours, .minutes], width: .wide)))
                    .tag(seconds)
                }
              }
            }
          }
        } header: {
          Text("Response")
        }
        Section {
          ForEach((guild?.allRoles ?? []).filter { $0.id.rawValue != guildId.rawValue }, id: \.id) { role in
            Toggle(role.name, isOn: membership($exemptRoles, role.id))
          }
        } header: {
          Text("Roles AutoMod Skips")
        }
        Section {
          ForEach(textChannels, id: \.id) { channel in
            Toggle("#" + (channel.name ?? ""), isOn: membership($exemptChannels, channel.id))
          }
        } header: {
          Text("Channels AutoMod Skips")
        }
        if rule != nil {
          Section {
            Button("Delete Rule", role: .destructive) { confirmsDelete = true }
          }
        }
      }
      .formStyle(.grouped)
      #if os(macOS)
        .toggleStyle(.switch)
      #endif
      .navigationTitle(Text(verbatim: AutoModView.title(kind)))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Save", action: save)
              .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (!blocks && alertChannel == nil && timeoutSeconds == 0))
          }
        }
      }
      .confirmationDialog(
        "Delete the rule \(name)?", isPresented: $confirmsDelete, titleVisibility: .visible
      ) {
        Button("Delete Rule", role: .destructive, action: delete)
        Button("Cancel", role: .cancel) {}
      }
      .saveErrorAlert($error)
      .onAppear(perform: load)
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 600)
    #endif
  }

  @ViewBuilder
  private var trigger: some View {
    switch kind {
    case .keyword:
      Section {
        Group {
          TextField("Words, One per Line or Separated by Commas", text: $keywords, axis: .vertical)
            .lineLimit(3...8)
          TextField("Regular Expressions, One per Line", text: $regexes, axis: .vertical)
            .lineLimit(1...5)
            .font(.body.monospaced())
          TextField("Allowed Words", text: $allowList, axis: .vertical)
        }
        .autocorrectionDisabled()
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
      } header: {
        Text("Trigger")
      } footer: {
        Text("Use * for partial matches: cat* matches catapult, *cat matches bobcat.")
      }
    case .keywordPreset:
      Section {
        Toggle("Insults and Slurs", isOn: membership($presets, 3))
        Toggle("Sexual Content", isOn: membership($presets, 2))
        Toggle("Severe Profanity", isOn: membership($presets, 1))
        TextField("Allowed Words", text: $allowList, axis: .vertical)
      } header: {
        Text("Trigger")
      }
    case .mentionSpam:
      Section {
        Stepper("At Most \(mentionLimit) Mentions per Message", value: $mentionLimit, in: 1...50)
        Toggle("Raid Protection", isOn: $raidProtection)
      } header: {
        Text("Trigger")
      }
    case .spam, .memberProfile:
      Section {
      } footer: {
        Text("Discord decides what counts as spam.")
      }
    }
  }

  private func membership<T: Hashable>(_ set: Binding<Set<T>>, _ value: T) -> Binding<Bool> {
    Binding {
      set.wrappedValue.contains(value)
    } set: { isOn in
      if isOn { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
    }
  }

  private static func list(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == "\n" || $0 == "," })
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private func load() {
    guard !loaded else { return }
    loaded = true
    guard let rule else {
      name = AutoModView.title(kind)
      return
    }
    name = rule.name
    enabled = rule.enabled
    keywords = (rule.trigger_metadata.keyword_filter ?? []).joined(separator: "\n")
    regexes = (rule.trigger_metadata.regex_patterns ?? []).joined(separator: "\n")
    allowList = (rule.trigger_metadata.allow_list ?? []).joined(separator: ", ")
    presets = Set(rule.trigger_metadata.presets ?? [])
    mentionLimit = rule.trigger_metadata.mention_total_limit ?? 10
    raidProtection = rule.trigger_metadata.mention_raid_protection_enabled ?? false
    let block = rule.actions.first { $0.type == .blockMessage }
    blocks = block != nil
    customMessage = block?.metadata?.custom_message ?? ""
    alertChannel = rule.actions.first { $0.type == .sendAlert }?.metadata?.channel_id
    timeoutSeconds = rule.actions.first { $0.type == .timeout }?.metadata?.duration_seconds ?? 0
    exemptRoles = Set(rule.exempt_roles)
    exemptChannels = Set(rule.exempt_channels)
  }

  private func save() {
    var metadata = AutoModRule.TriggerMetadata()
    switch kind {
    case .keyword:
      metadata.keyword_filter = Self.list(keywords)
      metadata.regex_patterns = regexes.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
      metadata.allow_list = Self.list(allowList)
    case .keywordPreset:
      metadata.presets = presets.sorted()
      metadata.allow_list = Self.list(allowList)
    case .mentionSpam:
      metadata.mention_total_limit = mentionLimit
      metadata.mention_raid_protection_enabled = raidProtection
    default:
      break
    }
    var actions: [AutoModRule.Action] = []
    if blocks {
      actions.append(
        .init(
          type: .blockMessage,
          metadata: customMessage.isEmpty ? nil : .init(custom_message: customMessage)))
    }
    if let alertChannel {
      actions.append(.init(type: .sendAlert, metadata: .init(channel_id: alertChannel)))
    }
    if canTimeout, timeoutSeconds > 0 {
      actions.append(.init(type: .timeout, metadata: .init(duration_seconds: timeoutSeconds)))
    }
    let payload = Payloads.AutoModRule(
      name: name, trigger_type: rule == nil ? kind : nil,
      trigger_metadata: kind == .spam ? nil : metadata, actions: actions, enabled: enabled,
      exempt_roles: Array(exemptRoles), exempt_channels: Array(exemptChannels))
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        if let rule {
          _ = try await gw.client.updateAutoModRule(guildId: guildId, ruleId: rule.id, payload: payload)
            .decode()
        } else {
          _ = try await gw.client.createAutoModRule(guildId: guildId, payload: payload).decode()
        }
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func delete() {
    guard let rule else { return }
    Task {
      do {
        try await gw.client.deleteAutoModRule(guildId: guildId, ruleId: rule.id).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Emoji and stickers

/// The server's emoji and stickers: upload, rename and delete.
struct ExpressionsAdminView: View {
  let guildId: GuildSnowflake
  @Environment(\.gateway) var gw
  @State private var emojis: [Emoji] = []
  @State private var stickers: [Sticker] = []
  @State private var importKind: Importing = .emoji
  @State private var showsImporter = false
  @State private var pendingFile: URL?
  @State private var pendingKind: Importing = .emoji
  @State private var newName = ""
  @State private var newTag = ""
  @State private var deletingEmoji: Emoji?
  @State private var deletingSticker: Sticker?
  @State private var isWorking = false
  @State private var error: String?

  enum Importing: Identifiable {
    case emoji, sticker
    var id: Self { self }
  }

  /// Discord's upload limits.
  static let emojiMaxBytes = 256 * 1024
  static let stickerMaxBytes = 512 * 1024

  var body: some View {
    List {
      Section {
        ForEach(emojis, id: \.id) { emoji in
          HStack(spacing: 10) {
            if let id = emoji.id {
              NukeImage(url: URL(string: "https://cdn.discordapp.com/emojis/\(id.rawValue).webp?size=64"))
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            }
            Text(verbatim: ":\(emoji.name ?? ""):")
            Spacer()
          }
          .contextMenu {
            Button("Delete Emoji", systemImage: "trash", role: .destructive) { deletingEmoji = emoji }
          }
          .swipeActions {
            Button("Delete", role: .destructive) { deletingEmoji = emoji }
          }
        }
      } header: {
        Text("Emoji")
      } footer: {
        Text("PNG, JPEG, GIF or WebP, up to 256 KB. Names use letters, numbers and underscores.")
      }
      Section {
        ForEach(stickers, id: \.id) { sticker in
          HStack(spacing: 10) {
            NukeImage(url: URL(string: "https://media.discordapp.net/stickers/\(sticker.id.rawValue).png?size=64"))
              .resizable()
              .scaledToFit()
              .frame(width: 36, height: 36)
              .accessibilityHidden(true)
            VStack(alignment: .leading) {
              Text(verbatim: sticker.name)
              Text(verbatim: sticker.tags)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          .contextMenu {
            Button("Delete Sticker", systemImage: "trash", role: .destructive) { deletingSticker = sticker }
          }
          .swipeActions {
            Button("Delete", role: .destructive) { deletingSticker = sticker }
          }
        }
      } header: {
        Text("Stickers")
      } footer: {
        Text("PNG, APNG or GIF, 320 × 320, up to 512 KB. The tag is an emoji name, like smile.")
      }
    }
    .overlay {
      if isWorking { ProgressView() }
    }
    .navigationTitle("Emoji and Stickers")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button("Upload Emoji", systemImage: "face.smiling") { startImport(.emoji) }
          Button("Upload Sticker", systemImage: "seal") { startImport(.sticker) }
        } label: {
          Label("Upload", systemImage: "plus")
        }
      }
    }
    .fileImporter(
      isPresented: $showsImporter,
      allowedContentTypes: importKind == .emoji ? [.png, .jpeg, .gif, .webP] : [.png, .gif]
    ) { result in
      guard case .success(let url) = result else { return }
      pendingKind = importKind
      newName = url.deletingPathExtension().lastPathComponent
        .replacingOccurrences(of: " ", with: "_")
        .filter { $0.isLetter || $0.isNumber || $0 == "_" }
      newTag = ""
      pendingFile = url
    }
    .alert(
      pendingKind == .emoji ? "Name the Emoji" : "Name the Sticker",
      isPresented: Binding(get: { pendingFile != nil }, set: { if !$0 { pendingFile = nil } })
    ) {
      TextField("Name", text: $newName)
        .autocorrectionDisabled()
      if pendingKind == .sticker {
        TextField("Emoji Tag", text: $newTag)
          .autocorrectionDisabled()
      }
      Button("Upload") { upload() }
      Button("Cancel", role: .cancel) { pendingFile = nil }
    }
    .confirmationDialog(
      "Delete :\(deletingEmoji?.name ?? ""):?",
      isPresented: Binding(get: { deletingEmoji != nil }, set: { if !$0 { deletingEmoji = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete Emoji", role: .destructive) {
        if let emoji = deletingEmoji { delete(emoji) }
      }
      Button("Cancel", role: .cancel) {}
    }
    .confirmationDialog(
      "Delete the sticker \(deletingSticker?.name ?? "")?",
      isPresented: Binding(get: { deletingSticker != nil }, set: { if !$0 { deletingSticker = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete Sticker", role: .destructive) {
        if let sticker = deletingSticker { delete(sticker) }
      }
      Button("Cancel", role: .cancel) {}
    }
    .saveErrorAlert($error)
    .task { await load() }
    .refreshable { await load() }
  }

  /// The file picker asked for while the menu is still closing doesn't appear
  /// on iOS, so wait for the menu first.
  private func startImport(_ kind: Importing) {
    importKind = kind
    Task {
      try? await Task.sleep(for: .milliseconds(400))
      showsImporter = true
    }
  }

  private func load() async {
    do {
      emojis = try await gw.client.listGuildEmojis(guildId: guildId).decode()
        .sorted { ($0.name ?? "") < ($1.name ?? "") }
      stickers = try await gw.client.listGuildStickers(guildId: guildId).decode()
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func readFile(_ url: URL, limit: Int) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let data = try Data(contentsOf: url)
    guard data.count <= limit else {
      throw UploadError.tooLarge(limit)
    }
    return data
  }

  enum UploadError: LocalizedError {
    case tooLarge(Int)
    var errorDescription: String? {
      switch self {
      case .tooLarge(let limit):
        String(localized: "The file is larger than \(limit.formatted(.byteCount(style: .file))).")
      }
    }
  }

  private func upload() {
    guard let url = pendingFile else { return }
    pendingFile = nil
    let kind = pendingKind
    let name = newName.trimmingCharacters(in: .whitespaces)
    let tag = newTag.trimmingCharacters(in: .whitespaces)
    isWorking = true
    Task {
      defer { isWorking = false }
      do {
        if kind == .emoji {
          let data = try readFile(url, limit: Self.emojiMaxBytes)
          let file = RawFile(data: data, filename: url.lastPathComponent)
          _ = try await gw.client.createGuildEmoji(
            guildId: guildId,
            payload: .init(name: name, image: .init(file: file), roles: [])
          ).decode()
        } else {
          let data = try readFile(url, limit: Self.stickerMaxBytes)
          let file = RawFile(data: data, filename: url.lastPathComponent)
          _ = try await gw.client.createGuildSticker(
            guildId: guildId,
            payload: .init(name: name, description: "", tags: tag.isEmpty ? name : tag, file: file)
          ).decode()
        }
        await load()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func delete(_ emoji: Emoji) {
    guard let id = emoji.id else { return }
    Task {
      do {
        try await gw.client.deleteGuildEmoji(guildId: guildId, emojiId: id).guardSuccess()
        await load()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  private func delete(_ sticker: Sticker) {
    Task {
      do {
        try await gw.client.deleteGuildSticker(guildId: guildId, stickerId: sticker.id).guardSuccess()
        await load()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Role icon

/// A role's icon: an emoji or an uploaded image, for servers with the Role Icons perk.
struct RoleIconSection: View {
  let guildId: GuildSnowflake
  let role: Role
  @Binding var error: String?
  @Environment(\.gateway) var gw
  @State private var emoji = ""
  @State private var importing = false
  @State private var isSaving = false

  private var iconURL: URL? {
    role.icon.flatMap { URL(string: "https://cdn.discordapp.com/role-icons/\(role.id.rawValue)/\($0).png?size=64") }
  }

  var body: some View {
    Section {
      HStack {
        if let iconURL {
          NukeImage(url: iconURL)
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .accessibilityLabel("Current Icon")
        } else if let unicode = role.unicode_emoji {
          Text(verbatim: unicode).font(.title2)
        } else {
          Text("No Icon").foregroundStyle(.secondary)
        }
        Spacer()
        if isSaving { ProgressView() }
      }
      HStack {
        TextField("Emoji", text: $emoji)
          .frame(maxWidth: 80)
        Button("Use Emoji") {
          let value = String(emoji.trimmingCharacters(in: .whitespaces).prefix(1))
          guard !value.isEmpty else { return }
          save(.init(icon: nil, unicode_emoji: value))
        }
        .disabled(emoji.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      Button("Upload Image…") { importing = true }
      if role.icon != nil || role.unicode_emoji != nil {
        Button("Remove Icon", role: .destructive) { clear() }
      }
    } header: {
      Text("Role Icon")
    } footer: {
      Text("Shown next to names in chat. An image should be at least 64 × 64 and under 256 KB.")
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { result in
      guard case .success(let url) = result else { return }
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      guard let data = try? Data(contentsOf: url) else { return }
      guard data.count <= ExpressionsAdminView.emojiMaxBytes else {
        error = ExpressionsAdminView.UploadError.tooLarge(ExpressionsAdminView.emojiMaxBytes)
          .localizedDescription
        return
      }
      save(.init(icon: .init(file: RawFile(data: data, filename: url.lastPathComponent)), unicode_emoji: nil))
    }
  }

  private func save(_ payload: Payloads.GuildRole) {
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.updateGuildRole(guildId: guildId, roleId: role.id, payload: payload)
          .guardSuccess()
        emoji = ""
      } catch {
        self.error = error.localizedDescription
      }
    }
  }

  /// Both fields as JSON null, which the usual payload leaves out.
  private func clear() {
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.clearGuildRoleIcon(guildId: guildId, roleId: role.id).guardSuccess()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Delete server

/// Deleting a server you own: type its name to confirm. When your account has
/// two-factor authentication, Discord asks for a code first (the shared MFA sheet).
struct DeleteServerSection: View {
  let guildId: GuildSnowflake
  var onDeleted: () -> Void
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @State private var confirming = false
  @State private var typedName = ""
  @State private var isDeleting = false
  @State private var error: String?

  private var guildName: String { gw.user.guilds[guildId]?.name ?? "" }

  var body: some View {
    Section {
      Button(role: .destructive) {
        typedName = ""
        confirming = true
      } label: {
        HStack {
          Text("Delete Server")
          if isDeleting {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(isDeleting)
    } footer: {
      Text("Only the owner can delete a server. Its channels, messages and roles are gone for everyone.")
    }
    .alert("Delete \(guildName)?", isPresented: $confirming) {
      TextField("Server Name", text: $typedName)
        .autocorrectionDisabled()
      Button("Delete Server", role: .destructive, action: delete)
        .disabled(typedName != guildName)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Type the server's name to confirm. This can't be undone.")
    }
    .saveErrorAlert($error)
  }

  private func delete() {
    guard typedName == guildName else { return }
    isDeleting = true
    Task {
      defer { isDeleting = false }
      do {
        try await gw.client.deleteGuild(id: guildId).guardSuccess()
        if appState.selectedGuild == guildId { appState.selectedGuild = nil }
        onDeleted()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}
