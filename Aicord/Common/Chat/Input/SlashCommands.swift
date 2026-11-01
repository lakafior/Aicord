//
//  SlashCommands.swift
//  Aicord
//

import AicordKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Index

/// A command as the picker lists it: subcommands and groups flattened into
/// "/name group sub", with the options that leaf takes.
struct SlashCommandEntry: Identifiable, Hashable {
  var command: ApplicationCommandIndex.Command
  var application: ApplicationCommandIndex.Application?
  /// Subcommand group and subcommand names under the command, if any.
  var path: [String]
  var options: [ApplicationCommandIndex.Option]
  var description: String

  var id: String { ([command.id.rawValue] + path).joined(separator: " ") }
  var title: String { ([command.displayName] + path).joined(separator: " ") }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Commands the user can run, per server or DM, plus their own installed apps.
/// Loaded the first time `/` is typed there and kept for the session.
@MainActor
@Observable
final class SlashCommandIndex {
  static let shared = SlashCommandIndex()

  @ObservationIgnored private var cache: [String: [SlashCommandEntry]] = [:]
  /// User (type 2) and message (type 3) commands, for the message menu's Apps.
  private(set) var contextCommands: [String: [SlashCommandEntry]] = [:]

  static func key(for channel: ChannelStore) -> String {
    channel.guildStore.map { "g\($0.guildId.rawValue)" } ?? "c\(channel.channelId.rawValue)"
  }

  func entries(for channel: ChannelStore, client: any DiscordClient) async -> [SlashCommandEntry] {
    let key = Self.key(for: channel)
    if let cached = cache[key] { return cached }
    async let place = Self.load {
      if let guild = channel.guildStore {
        try await client.getGuildApplicationCommandIndex(guildId: guild.guildId).decode()
      } else {
        try await client.getChannelApplicationCommandIndex(channelId: channel.channelId).decode()
      }
    }
    async let user = Self.load { try await client.getUserApplicationCommandIndex().decode() }
    var entries: [SlashCommandEntry] = []
    var contextEntries: [SlashCommandEntry] = []
    var seen = Set<String>()
    for index in [await place, await user].compactMap({ $0 }) {
      let apps = Dictionary(index.applications.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
      for command in index.application_commands {
        if command.type == 2 || command.type == 3 {
          if seen.insert(command.id.rawValue).inserted {
            contextEntries.append(
              SlashCommandEntry(
                command: command, application: apps[command.application_id], path: [], options: [],
                description: command.displayDescription))
          }
          continue
        }
        guard command.isChatInput else { continue }
        for entry in Self.flatten(command, application: apps[command.application_id])
        where seen.insert(entry.id).inserted {
          entries.append(entry)
        }
      }
    }
    entries.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    contextEntries.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    cache[key] = entries
    contextCommands[key] = contextEntries
    return entries
  }

  private static func load(
    _ request: () async throws -> ApplicationCommandIndex
  ) async -> ApplicationCommandIndex? {
    do {
      return try await request()
    } catch {
      print("[SlashCommands] Command index failed:", error)
      return nil
    }
  }

  private static func flatten(
    _ command: ApplicationCommandIndex.Command,
    application: ApplicationCommandIndex.Application?
  ) -> [SlashCommandEntry] {
    let options = command.options ?? []
    let subcommands = options.filter { $0.type == .subCommand || $0.type == .subCommandGroup }
    guard !subcommands.isEmpty else {
      return [
        SlashCommandEntry(
          command: command, application: application, path: [], options: options,
          description: command.displayDescription)
      ]
    }
    var entries: [SlashCommandEntry] = []
    for option in subcommands {
      if option.type == .subCommand {
        entries.append(
          SlashCommandEntry(
            command: command, application: application, path: [option.displayName],
            options: option.options ?? [], description: option.displayDescription))
      } else {
        for sub in option.options ?? [] where sub.type == .subCommand {
          entries.append(
            SlashCommandEntry(
              command: command, application: application,
              path: [option.displayName, sub.displayName],
              options: sub.options ?? [], description: sub.displayDescription))
        }
      }
    }
    return entries
  }
}

// MARK: - Interaction results

/// Waits for the gateway's answer to an interaction this client sent, by nonce.
@MainActor
final class InteractionWatcher {
  static let shared = InteractionWatcher()

  enum Outcome { case success, failure }

  /// Where each interaction sent from here ran, by nonce, so a modal it opens
  /// can be answered in the same place.
  struct Origin {
    var applicationID: ApplicationSnowflake
    var guildID: GuildSnowflake?
    var channelID: ChannelSnowflake
  }

  private var listening = false
  private var origins: [String: Origin] = [:]
  private var outcomes: [String: CheckedContinuation<Outcome?, Never>] = [:]
  private var autocompletes: [String: CheckedContinuation<[ApplicationCommandIndex.Choice], Never>] = [:]

  /// Remembers where an interaction ran before it is sent.
  func sent(nonce: String, origin: Origin, gateway: UserGatewayManager) {
    listen(gateway)
    origins[nonce] = origin
    if origins.count > 50, let oldest = origins.keys.min() { origins.removeValue(forKey: oldest) }
  }

  private func listen(_ gateway: UserGatewayManager) {
    guard !listening else { return }
    listening = true
    let events = gateway.events
    Task { @MainActor in
      for await event in events {
        switch event.data {
        case .interactionSuccess(let status):
          resolve(status.nonce, .success)
        case .interactionFailure(let status):
          resolve(status.nonce, .failure)
        case .interactionModalCreate(let modal):
          let origin = modal.nonce.flatMap { origins[$0] }
          BotInteractions.shared.present(modal, origin: origin)
        case .applicationCommandAutocompleteResponse(let response):
          if let nonce = response.nonce, let waiter = autocompletes.removeValue(forKey: nonce) {
            waiter.resume(returning: response.choices)
          }
        default:
          break
        }
      }
      listening = false
    }
  }

  private func resolve(_ nonce: String?, _ outcome: Outcome) {
    guard let nonce, let waiter = outcomes.removeValue(forKey: nonce) else { return }
    waiter.resume(returning: outcome)
  }

  /// The outcome, or nil when nothing came within the timeout.
  func outcome(of nonce: String, gateway: UserGatewayManager, timeout: Duration = .seconds(10)) async
    -> Outcome?
  {
    listen(gateway)
    return await withCheckedContinuation { continuation in
      outcomes[nonce] = continuation
      Task { @MainActor in
        try? await Task.sleep(for: timeout)
        if let waiter = outcomes.removeValue(forKey: nonce) { waiter.resume(returning: nil) }
      }
    }
  }

  func choices(for nonce: String, gateway: UserGatewayManager) async -> [ApplicationCommandIndex.Choice] {
    listen(gateway)
    return await withCheckedContinuation { continuation in
      autocompletes[nonce] = continuation
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(5))
        if let waiter = autocompletes.removeValue(forKey: nonce) { waiter.resume(returning: []) }
      }
    }
  }
}

// MARK: - Draft

/// An option's value while the command is being filled in.
enum SlashOptionValue: Hashable {
  case text(String)
  case choice(ApplicationCommandIndex.Value, label: String)
  case bool(Bool)
  case user(UserSnowflake, label: String)
  case channel(ChannelSnowflake, label: String)
  case role(RoleSnowflake, label: String)
  case attachment(Data, filename: String)

  var label: String {
    switch self {
    case .text(let text): text
    case .attachment(_, let filename): filename
    case .choice(_, let label), .user(_, let label), .channel(_, let label), .role(_, let label): label
    case .bool(let value): value ? String(localized: "True") : String(localized: "False")
    }
  }
}

/// A command picked from the list, with the values entered so far.
@MainActor
@Observable
final class SlashCommandDraft {
  let entry: SlashCommandEntry
  var values: [String: SlashOptionValue] = [:]
  var isSending = false
  var error: String?
  /// Files for attachment options, uploaded right before sending: index and upload by option name.
  private var uploads: [String: (index: Int, file: Payloads.CreateInteraction.UploadedAttachment)] = [:]

  init(entry: SlashCommandEntry) { self.entry = entry }

  var missingRequired: Bool {
    entry.options.contains { $0.required == true && !isFilled($0) }
  }

  func isFilled(_ option: ApplicationCommandIndex.Option) -> Bool {
    switch values[option.name] {
    case nil: false
    case .text(let text): !text.trimmingCharacters(in: .whitespaces).isEmpty
    default: true
    }
  }

  /// The value the interaction sends, or nil when it doesn't parse.
  func payloadValue(_ option: ApplicationCommandIndex.Option) -> ApplicationCommandIndex.Value? {
    guard let value = values[option.name] else { return nil }
    switch value {
    case .choice(let raw, _): return raw
    case .bool(let flag): return .bool(flag)
    case .user(let id, _): return .string(id.rawValue)
    case .channel(let id, _): return .string(id.rawValue)
    case .role(let id, _): return .string(id.rawValue)
    case .attachment: return uploads[option.name].map { .int($0.index) }
    case .text(let text):
      let trimmed = text.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return nil }
      switch option.type {
      case .integer: return Int(trimmed).map { .int($0) }
      case .number: return Double(trimmed.replacingOccurrences(of: ",", with: ".")).map { .double($0) }
      default: return .string(trimmed)
      }
    }
  }

  /// The leaf options wrapped in their subcommand and group, as Discord expects.
  func dataOptions(focused: String? = nil) -> [Payloads.CreateInteraction.DataOption] {
    var leaf: [Payloads.CreateInteraction.DataOption] = entry.options.compactMap { option in
      let isFocused = option.name == focused
      let value: ApplicationCommandIndex.Value? =
        isFocused ? .string(values[option.name]?.label ?? "") : payloadValue(option)
      guard let value else { return nil }
      return .init(type: option.type.rawValue, name: option.name, value: value, focused: isFocused ? true : nil)
    }
    let names = entry.path
    let command = entry.command.options ?? []
    if names.count == 2, let group = command.first(where: { $0.displayName == names[0] }),
      let sub = group.options?.first(where: { $0.displayName == names[1] })
    {
      leaf = [
        .init(
          type: group.type.rawValue, name: group.name,
          options: [.init(type: sub.type.rawValue, name: sub.name, options: leaf)])
      ]
    } else if names.count == 1, let sub = command.first(where: { $0.displayName == names[0] }) {
      leaf = [.init(type: sub.type.rawValue, name: sub.name, options: leaf)]
    }
    return leaf
  }

  func interaction(
    type: Int, channel: ChannelStore, sessionId: String, focused: String? = nil
  ) throws -> Payloads.CreateInteraction {
    Payloads.CreateInteraction(
      type: type,
      application_id: entry.command.application_id,
      guild_id: channel.guildStore?.guildId,
      channel_id: channel.channelId,
      session_id: sessionId,
      data: .init(
        command: entry.command, options: dataOptions(focused: focused),
        attachments: uploads.values.sorted { $0.index < $1.index }.map(\.file)),
      nonce: try MessageSnowflake.makeFake(date: .now).rawValue
    )
  }

  /// Uploads the files picked for attachment options to Discord's storage.
  func uploadAttachments(channel: ChannelSnowflake, client: any DiscordClient) async throws {
    uploads = [:]
    let files: [(name: String, data: Data, filename: String)] = entry.options.compactMap { option in
      guard case .attachment(let data, let filename) = values[option.name] else { return nil }
      return (option.name, data, filename)
    }
    for (index, file) in files.enumerated() {
      let uploaded = try await InteractionUpload.upload(
        file.data, filename: file.filename, channel: channel, client: client)
      uploads[file.name] = (
        index,
        .init(id: String(index), filename: file.filename, uploaded_filename: uploaded)
      )
    }
  }
}

/// Puts a file in Discord's storage the way message attachments go:
/// ask for an upload URL, then PUT the bytes there.
enum InteractionUpload {
  static func upload(
    _ data: Data, filename: String, channel: ChannelSnowflake, client: any DiscordClient
  ) async throws -> String {
    let slots = try await client.createAttachments(
      channelID: channel,
      payload: .init(files: [.init(filename: filename, file_size: data.count)])
    ).decode()
    guard let slot = slots.attachments.first, let url = URL(string: slot.upload_url) else {
      throw URLError(.badServerResponse)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    let (_, response) = try await URLSession.shared.upload(for: request, from: data)
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
      throw URLError(.cannotWriteToFile)
    }
    return slot.upload_filename
  }
}

// MARK: - Views

/// Commands matching what follows the `/`, shown above the message field.
struct SlashCommandSuggestions: View {
  var channel: ChannelStore
  var query: String
  var pick: (SlashCommandEntry) -> Void
  @Environment(\.gateway) var gw
  @Environment(\.theme) var theme

  @State private var entries: [SlashCommandEntry] = []
  @State private var isLoading = true

  private var matches: [SlashCommandEntry] {
    let needle = query.lowercased()
    guard !needle.isEmpty else { return entries }
    return entries.filter {
      $0.title.lowercased().hasPrefix(needle) || $0.title.lowercased().contains(" " + needle)
        || ($0.application?.name.lowercased().hasPrefix(needle) ?? false)
    }
  }

  var body: some View {
    let matches = matches
    VStack(alignment: .leading, spacing: 0) {
      if isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
          .padding(8)
      } else if matches.isEmpty {
        Text(entries.isEmpty ? "No commands here." : "No matching commands.")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(10)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(matches.prefix(50)) { entry in
              Button {
                pick(entry)
              } label: {
                row(entry)
              }
              .buttonStyle(.plain)
            }
          }
        }
        // a scroll view has no height of its own next to the chat's
        .frame(height: min(CGFloat(min(matches.count, 50)) * 46, 230))
      }
    }
    .background(.background.secondary, in: .rect(cornerRadius: 14))
    .padding(.horizontal, 8)
    .task(id: channel.channelId) {
      entries = await SlashCommandIndex.shared.entries(for: channel, client: gw.client)
      isLoading = false
    }
  }

  private func row(_ entry: SlashCommandEntry) -> some View {
    HStack(spacing: 10) {
      Group {
        if let app = entry.application, let icon = app.icon,
          let url = DiscordImageURL.applicationIcon(id: app.id, icon: icon, size: 64)
        {
          NukeImage(url: url).resizable().scaledToFill()
        } else {
          Image(systemName: "command").foregroundStyle(.secondary)
        }
      }
      .frame(width: 24, height: 24)
      .clipShape(.circle)
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: "/" + entry.title)
          .font(.callout.weight(.semibold))
        Text(entry.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if let name = entry.application?.name {
        Text(name)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .contentShape(.rect)
  }
}

/// A picked command: its options to fill in, then Send runs it like Discord's
/// own apps do (an interaction from the user, never on its own).
struct SlashCommandComposer: View {
  var draft: SlashCommandDraft
  var channel: ChannelStore
  var close: () -> Void
  @Environment(\.gateway) var gw
  @Environment(\.theme) var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Text(verbatim: "/" + draft.entry.title)
          .font(.callout.weight(.semibold))
        if let app = draft.entry.application?.name {
          Text(app).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button(action: close) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Cancel Command"))
      }
      if draft.entry.options.isEmpty {
        Text(draft.entry.description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ForEach(draft.entry.options, id: \.name) { option in
        SlashOptionField(option: option, draft: draft, channel: channel)
      }
      if let error = draft.error {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        if draft.isSending {
          ProgressView().controlSize(.small)
        }
        Button("Send") { send() }
          .buttonStyle(.borderedProminent)
          .disabled(draft.missingRequired || draft.isSending)
      }
    }
    .padding(10)
    .background(.background.secondary.opacity(0.8), in: .rect(cornerRadius: 18))
  }

  private func send() {
    guard let gateway = gw.gateway else { return }
    draft.isSending = true
    draft.error = nil
    Task {
      defer { draft.isSending = false }
      do {
        guard let sessionId = await gateway.getSessionID() else {
          throw URLError(.notConnectedToInternet)
        }
        try await draft.uploadAttachments(channel: channel.channelId, client: gw.client)
        let payload = try draft.interaction(type: 2, channel: channel, sessionId: sessionId)
        InteractionWatcher.shared.sent(
          nonce: payload.nonce,
          origin: .init(
            applicationID: payload.application_id, guildID: payload.guild_id,
            channelID: payload.channel_id),
          gateway: gateway)
        try await gw.client.createInteraction(payload: payload).guardSuccess()
        let outcome = await InteractionWatcher.shared.outcome(of: payload.nonce, gateway: gateway)
        if outcome == .failure {
          draft.error = String(localized: "The application did not respond.")
        } else {
          close()
        }
      } catch {
        print("[Interactions] Command failed:", error)
        draft.error = error.localizedDescription
      }
    }
  }
}

/// One option's input, by its type.
struct SlashOptionField: View {
  var option: ApplicationCommandIndex.Option
  var draft: SlashCommandDraft
  var channel: ChannelStore
  @Environment(\.gateway) var gw

  @State private var suggestions: [ApplicationCommandIndex.Choice] = []
  @State private var pickingFile = false
  @State private var autocompleteTask: Task<Void, Never>?

  private var label: String {
    option.displayName + (option.required == true ? "" : " " + String(localized: "(optional)"))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(label)
          .font(.caption.weight(.semibold))
        Text(option.displayDescription)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      input
      if !suggestions.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(suggestions, id: \.self) { choice in
              Button(choice.displayName) {
                draft.values[option.name] = .choice(choice.value, label: choice.displayName)
                suggestions = []
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var input: some View {
    if let choices = option.choices, !choices.isEmpty {
      menu(
        choices.map { ($0.displayName, SlashOptionValue.choice($0.value, label: $0.displayName)) })
    } else {
      switch option.type {
      case .boolean:
        menu([(String(localized: "True"), .bool(true)), (String(localized: "False"), .bool(false))])
      case .user, .mentionable:
        menu(userChoices + (option.type == .mentionable ? roleChoices : []))
      case .channel:
        menu(channelChoices)
      case .role:
        menu(roleChoices)
      case .attachment:
        attachmentPicker
      case .unknown, .subCommand, .subCommandGroup:
        Text("Aicord can't fill in this kind of option yet.")
          .font(.caption)
          .foregroundStyle(.secondary)
      case .string, .integer, .number:
        TextField(
          option.displayName,
          text: Binding(
            get: { draft.values[option.name]?.label ?? "" },
            set: { text in
              draft.values[option.name] = .text(text)
              if option.autocomplete == true { requestAutocomplete() }
            }
          )
        )
        .textFieldStyle(.roundedBorder)
        #if os(iOS)
          .keyboardType(option.type == .string ? .default : .numbersAndPunctuation)
        #endif
      }
    }
  }

  private var attachmentPicker: some View {
    HStack {
      Button {
        pickingFile = true
      } label: {
        Label(
          draft.values[option.name]?.label ?? String(localized: "Choose File…"),
          systemImage: "paperclip")
      }
      .buttonStyle(.bordered)
      if draft.values[option.name] != nil {
        Button {
          draft.values[option.name] = nil
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Remove File"))
      }
    }
    .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item]) { result in
      guard case .success(let url) = result else { return }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        let data = try Data(contentsOf: url)
        draft.values[option.name] = .attachment(data, filename: url.lastPathComponent)
      } catch {
        draft.error = error.localizedDescription
      }
    }
  }

  private func menu(_ items: [(String, SlashOptionValue)]) -> some View {
    Menu {
      if option.required != true, draft.values[option.name] != nil {
        Button("Clear", role: .destructive) { draft.values[option.name] = nil }
      }
      ForEach(Array(items.prefix(100).enumerated()), id: \.offset) { _, item in
        Button(item.0) { draft.values[option.name] = item.1 }
      }
    } label: {
      HStack {
        Text(draft.values[option.name]?.label ?? String(localized: "Choose…"))
          .foregroundStyle(draft.values[option.name] == nil ? .secondary : .primary)
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(.background, in: .rect(cornerRadius: 8))
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
  }

  private var userChoices: [(String, SlashOptionValue)] {
    if let guild = channel.guildStore {
      return guild.loadedMembers.compactMap { member in
        guard let user = member.user else { return nil }
        let name = member.nick ?? user.global_name ?? user.username
        return (name, .user(user.id, label: name))
      }
      .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
    var people = channel.channel?.recipients ?? []
    if let me = gw.user.currentUser { people.append(me) }
    return people.map { user in
      let name = user.global_name ?? user.username
      return (name, .user(user.id, label: name))
    }
  }

  private var roleChoices: [(String, SlashOptionValue)] {
    (channel.guildStore?.allRoles ?? []).map { role in
      // @everyone already carries its @
      let name = role.name.hasPrefix("@") ? role.name : "@" + role.name
      return (name, .role(role.id, label: name))
    }
  }

  private var channelChoices: [(String, SlashOptionValue)] {
    guard let guild = channel.guildStore else { return [] }
    let allowed = option.channel_types.map(Set.init)
    return guild.channels.values
      .filter { $0.type != .guildCategory }
      .filter { channel in
        guard let allowed, let raw = channel.type?.rawValue else { return true }
        return allowed.contains(Int(raw))
      }
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
      .map { ("#" + ($0.name ?? ""), .channel($0.id, label: "#" + ($0.name ?? ""))) }
  }

  /// Asks the bot for choices matching what's typed, after a short pause.
  private func requestAutocomplete() {
    autocompleteTask?.cancel()
    autocompleteTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled, let gateway = gw.gateway,
        let sessionId = await gateway.getSessionID(),
        let payload = try? draft.interaction(
          type: 4, channel: channel, sessionId: sessionId, focused: option.name)
      else { return }
      guard (try? await gw.client.createInteraction(payload: payload).guardSuccess()) != nil else { return }
      let choices = await InteractionWatcher.shared.choices(for: payload.nonce, gateway: gateway)
      if !Task.isCancelled { suggestions = choices }
    }
  }
}
