//
//  BotInteractions.swift
//  Aicord
//

import AicordKit
import SwiftUI

/// Clicks on bots' buttons and picks in their menus, sent as interactions the
/// way Discord's own apps send them, plus the modals bots answer with. Every
/// interaction starts from the user's tap; nothing here runs on its own.
@MainActor
@Observable
final class BotInteractions {
  static let shared = BotInteractions()

  /// "message/custom_id" of components waiting for the bot.
  private(set) var sending: Set<String> = []
  /// Messages whose last interaction failed, with Discord's text for it.
  private(set) var failures: [MessageSnowflake: String] = [:]
  /// What the user picked in a select, by "message/custom_id", until the message changes.
  private(set) var picks: [String: (labels: [String], components: Int)] = [:]
  /// The modal a bot opened, shown as a sheet over the chat.
  var modal: PresentedModal?

  struct PresentedModal: Identifiable {
    var modal: Gateway.InteractionModalCreate
    var origin: InteractionWatcher.Origin
    var id: AnySnowflake { modal.id }
  }

  static func key(_ message: MessageSnowflake, _ customID: String) -> String {
    message.rawValue + "/" + customID
  }

  func isSending(_ message: MessageSnowflake, _ customID: String) -> Bool {
    sending.contains(Self.key(message, customID))
  }

  func pickedLabels(
    _ message: DiscordChannel.PartialMessage, _ customID: String
  ) -> [String]? {
    guard let pick = picks[Self.key(message.id, customID)],
      pick.components == message.components.hashValue
    else { return nil }
    return pick.labels
  }

  func dismissFailure(_ message: MessageSnowflake) {
    failures.removeValue(forKey: message)
  }

  func present(_ modal: Gateway.InteractionModalCreate, origin: InteractionWatcher.Origin?) {
    guard
      let origin = origin
        ?? modal.application.flatMap({ app in
          modal.channel_id.map { .init(applicationID: app.id, guildID: nil, channelID: $0) }
        })
    else { return }
    self.modal = PresentedModal(modal: modal, origin: origin)
  }

  /// A button click (no values) or a select pick, on a bot's message.
  func send(
    componentType: Int,
    customID: String,
    values: [String]? = nil,
    labels: [String] = [],
    message: DiscordChannel.PartialMessage,
    channel: ChannelStore,
    gw: GatewayStore
  ) {
    guard let gateway = gw.gateway,
      let applicationID = message.application_id ?? message.author.map({ ApplicationSnowflake($0.id) })
    else { return }
    let key = Self.key(message.id, customID)
    guard !sending.contains(key) else { return }
    sending.insert(key)
    failures.removeValue(forKey: message.id)
    if values != nil {
      picks[key] = (labels, message.components.hashValue)
    }
    Task {
      defer { sending.remove(key) }
      do {
        guard let sessionID = await gateway.getSessionID() else {
          throw URLError(.notConnectedToInternet)
        }
        let nonce = try MessageSnowflake.makeFake(date: .now).rawValue
        let payload = Payloads.ComponentInteraction(
          application_id: applicationID,
          guild_id: channel.guildStore?.guildId,
          channel_id: message.channel_id,
          message_id: message.id,
          message_flags: Int(message.flags?.rawValue ?? 0),
          session_id: sessionID,
          data: .init(component_type: componentType, custom_id: customID, values: values),
          nonce: nonce
        )
        InteractionWatcher.shared.sent(
          nonce: nonce,
          origin: .init(
            applicationID: applicationID, guildID: payload.guild_id, channelID: payload.channel_id),
          gateway: gateway)
        try await gw.client.createInteraction(payload: payload).guardSuccess()
        let outcome = await InteractionWatcher.shared.outcome(of: nonce, gateway: gateway)
        if outcome == .failure {
          failures[message.id] = String(localized: "This interaction failed")
          picks.removeValue(forKey: key)
        }
      } catch {
        print("[Interactions] Component failed:", error)
        failures[message.id] = error.localizedDescription
        picks.removeValue(forKey: key)
      }
    }
  }

  /// Sends a modal's answers; throws so the sheet can stay open with the error.
  func submit(
    _ presented: PresentedModal,
    answers: [String: Payloads.ModalSubmitInteraction.Answer],
    gw: GatewayStore
  ) async throws {
    guard let gateway = gw.gateway, let sessionID = await gateway.getSessionID() else {
      throw URLError(.notConnectedToInternet)
    }
    let nonce = try MessageSnowflake.makeFake(date: .now).rawValue
    let payload = Payloads.ModalSubmitInteraction(
      modal: presented.modal,
      answers: answers,
      application_id: presented.origin.applicationID,
      guild_id: presented.origin.guildID,
      channel_id: presented.origin.channelID,
      session_id: sessionID,
      nonce: nonce
    )
    InteractionWatcher.shared.sent(nonce: nonce, origin: presented.origin, gateway: gateway)
    try await gw.client.createInteraction(payload: payload).guardSuccess()
    if await InteractionWatcher.shared.outcome(of: nonce, gateway: gateway) == .failure {
      throw ModalError.didNotRespond
    }
  }

  /// Runs a user or message context menu command on a target.
  func runContextCommand(
    _ entry: SlashCommandEntry, target: AnySnowflake, channel: ChannelStore, gw: GatewayStore,
    onError: @escaping @MainActor (any Error) -> Void
  ) {
    guard let gateway = gw.gateway else { return }
    Task {
      do {
        guard let sessionID = await gateway.getSessionID() else {
          throw URLError(.notConnectedToInternet)
        }
        let payload = Payloads.CreateInteraction(
          type: 2,
          application_id: entry.command.application_id,
          guild_id: channel.guildStore?.guildId,
          channel_id: channel.channelId,
          session_id: sessionID,
          data: .init(command: entry.command, options: [], target_id: target),
          nonce: try MessageSnowflake.makeFake(date: .now).rawValue,
          analytics_location: nil
        )
        InteractionWatcher.shared.sent(
          nonce: payload.nonce,
          origin: .init(
            applicationID: payload.application_id, guildID: payload.guild_id,
            channelID: payload.channel_id),
          gateway: gateway)
        try await gw.client.createInteraction(payload: payload).guardSuccess()
        if await InteractionWatcher.shared.outcome(of: payload.nonce, gateway: gateway) == .failure {
          onError(ModalError.didNotRespond)
        }
      } catch {
        onError(error)
      }
    }
  }

  enum ModalError: LocalizedError {
    case didNotRespond
    var errorDescription: String? { String(localized: "The application did not respond.") }
  }
}

// MARK: - Choices for selects

/// The entries a select offers, by its kind: the bot's options, or the
/// server's people, roles and channels Aicord has loaded.
struct SelectChoice: Identifiable, Hashable {
  var value: String
  var label: String
  var description: String?
  var emoji: Emoji?
  var isDefault: Bool
  var id: String { value }

  @MainActor
  static func choices(
    for select: Interaction.MessageComponent.Select, channel: ChannelStore, gw: GatewayStore
  ) -> [SelectChoice] {
    let defaults = Set((select.default_values ?? []).map(\.id.rawValue))
    switch select.type {
    case 3:
      return select.options.map {
        SelectChoice(
          value: $0.value, label: $0.label, description: $0.description, emoji: $0.emoji,
          isDefault: $0.default == true)
      }
    case 5:
      return users(channel: channel, gw: gw, defaults: defaults)
    case 6:
      return roles(channel: channel, defaults: defaults)
    case 7:
      return users(channel: channel, gw: gw, defaults: defaults)
        + roles(channel: channel, defaults: defaults)
    case 8:
      guard let guild = channel.guildStore else { return [] }
      let allowed = select.channel_types.map(Set.init)
      return guild.channels.values
        .filter { $0.type != .guildCategory }
        .filter { channel in
          guard let allowed, let raw = channel.type?.rawValue else { return true }
          return allowed.contains(Int(raw))
        }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        .map {
          SelectChoice(
            value: $0.id.rawValue, label: "#" + ($0.name ?? ""),
            isDefault: defaults.contains($0.id.rawValue))
        }
    default:
      return []
    }
  }

  @MainActor
  private static func users(channel: ChannelStore, gw: GatewayStore, defaults: Set<String>)
    -> [SelectChoice]
  {
    var people: [(String, UserSnowflake)] = []
    if let guild = channel.guildStore {
      people = guild.loadedMembers.compactMap { member in
        guard let user = member.user else { return nil }
        return (member.nick ?? user.global_name ?? user.username, user.id)
      }
    } else {
      people = (channel.channel?.recipients ?? []).map { ($0.global_name ?? $0.username, $0.id) }
    }
    if let me = gw.user.currentUser, !people.contains(where: { $0.1 == me.id }) {
      people.append((me.global_name ?? me.username, me.id))
    }
    return
      people
      .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
      .map {
        SelectChoice(value: $0.1.rawValue, label: $0.0, isDefault: defaults.contains($0.1.rawValue))
      }
  }

  @MainActor
  private static func roles(channel: ChannelStore, defaults: Set<String>) -> [SelectChoice] {
    (channel.guildStore?.allRoles ?? []).map {
      SelectChoice(
        value: $0.id.rawValue, label: $0.name.hasPrefix("@") ? $0.name : "@" + $0.name,
        isDefault: defaults.contains($0.id.rawValue))
    }
  }
}

/// A select's list: one tap picks when it takes a single value, otherwise
/// checkmarks and Done once the minimum is reached.
struct SelectPickerSheet: View {
  var select: Interaction.MessageComponent.Select
  var choices: [SelectChoice]
  var initial: Set<String>
  var onPick: ([SelectChoice]) -> Void
  @Environment(\.dismiss) var dismiss
  @State private var picked: Set<String> = []
  @State private var query = ""

  private var minValues: Int { select.min_values ?? 1 }
  private var maxValues: Int { min(select.max_values ?? 1, max(choices.count, 1)) }

  private var shown: [SelectChoice] {
    query.isEmpty
      ? choices : choices.filter { $0.label.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    NavigationStack {
      List(shown) { choice in
        Button {
          toggle(choice)
        } label: {
          HStack(spacing: 10) {
            if let emoji = choice.emoji {
              MessageCell.ComponentEmoji(emoji: emoji)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(choice.label)
              if let description = choice.description {
                Text(description).font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            if picked.contains(choice.value) {
              Image(systemName: "checkmark").foregroundStyle(.tint)
            }
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }
      .overlay {
        if choices.isEmpty {
          ContentUnavailableView("Nothing to pick", systemImage: "list.bullet")
        }
      }
      .searchable(text: $query)
      .navigationTitle(select.placeholder ?? String(localized: "Make a selection"))
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        if maxValues > 1 {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { finish() }
              .disabled(picked.count < minValues)
          }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 360, minHeight: 420)
    #endif
    .onAppear { picked = initial }
  }

  private func toggle(_ choice: SelectChoice) {
    if maxValues == 1 {
      picked = [choice.value]
      finish()
    } else if picked.contains(choice.value) {
      picked.remove(choice.value)
    } else if picked.count < maxValues {
      picked.insert(choice.value)
    }
  }

  private func finish() {
    onPick(choices.filter { picked.contains($0.value) })
    dismiss()
  }
}

// MARK: - Modal

/// A bot's modal as a native form: text fields, selects and lines of text,
/// sent back only when the user taps Submit.
struct InteractionModalSheet: View {
  var presented: BotInteractions.PresentedModal
  @Environment(\.gateway) var gw
  @Environment(\.channelStore) var channelStore
  @Environment(\.dismiss) var dismiss
  @State private var texts: [String: String] = [:]
  @State private var selections: [String: Set<String>] = [:]
  @State private var isSending = false
  @State private var error: String?

  private var modal: Gateway.InteractionModalCreate { presented.modal }

  private var missingRequired: Bool {
    modal.components.contains { field in
      switch field.input {
      case .text(let input):
        let text = texts[input.custom_id, default: ""]
        // the gateway leaves out `required: false` but sends `true`
        return input.required == true && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || text.count < (input.min_length ?? 0) && !text.isEmpty
      case .select(let select):
        return selections[select.custom_id, default: []].count < (select.min_values ?? 1)
      default:
        return false
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        if let app = modal.application, let name = app.name {
          Section {
            Text(name).font(.caption).foregroundStyle(.secondary)
          }
        }
        ForEach(modal.components) { field in
          Section {
            row(field)
          } header: {
            if let title = title(field) {
              Text(title)
            }
          } footer: {
            if let description = field.description {
              Text(description)
            }
          }
        }
        if let error {
          Section {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle(modal.title)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSending {
            ProgressView()
          } else {
            Button("Submit") { submit() }
              .disabled(missingRequired)
          }
        }
      }
      .interactiveDismissDisabled(isSending)
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 360)
    #endif
    .onAppear(perform: fillDefaults)
  }

  private func title(_ field: Gateway.ModalField) -> String? {
    if let label = field.label { return label }
    if case .text(let input) = field.input { return input.label }
    return nil
  }

  @ViewBuilder
  private func row(_ field: Gateway.ModalField) -> some View {
    switch field.input {
    case .text(let input):
      let binding = Binding(
        get: { texts[input.custom_id, default: ""] },
        set: { texts[input.custom_id] = String($0.prefix(input.max_length ?? 4000)) })
      VStack(alignment: .trailing, spacing: 4) {
        if input.style == .paragraph {
          TextField(input.placeholder ?? "", text: binding, axis: .vertical)
            .lineLimit(4...10)
        } else {
          TextField(input.placeholder ?? "", text: binding)
        }
        if let max = input.max_length {
          Text(verbatim: "\(texts[input.custom_id, default: ""].count)/\(max)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }
    case .select(let select):
      ModalSelectField(
        select: select,
        selection: Binding(
          get: { selections[select.custom_id, default: []] },
          set: { selections[select.custom_id] = $0 }))
    case .display(let text):
      if let channelStore {
        MarkdownText(content: text, channelStore: channelStore)
      } else {
        Text(text)
      }
    case .unsupported:
      Text("Aicord can't fill in this kind of field yet.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func fillDefaults() {
    for field in modal.components {
      switch field.input {
      case .text(let input):
        if let value = input.value { texts[input.custom_id] = value }
      case .select(let select):
        let defaults = select.options.filter { $0.default == true }.map(\.value)
        if !defaults.isEmpty { selections[select.custom_id] = Set(defaults) }
      default:
        break
      }
    }
  }

  private func submit() {
    var answers: [String: Payloads.ModalSubmitInteraction.Answer] = [:]
    for (id, text) in texts { answers[id] = .text(text) }
    for (id, values) in selections { answers[id] = .values(Array(values)) }
    isSending = true
    error = nil
    Task {
      defer { isSending = false }
      do {
        try await BotInteractions.shared.submit(presented, answers: answers, gw: gw)
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// A string select inside a modal, as a menu (one value) or toggles.
private struct ModalSelectField: View {
  var select: Interaction.MessageComponent.Select
  @Binding var selection: Set<String>

  var body: some View {
    if (select.max_values ?? 1) > 1 {
      ForEach(select.options, id: \.value) { option in
        Toggle(
          option.label,
          isOn: Binding(
            get: { selection.contains(option.value) },
            set: { on in
              if on, selection.count < (select.max_values ?? 1) {
                selection.insert(option.value)
              } else if !on {
                selection.remove(option.value)
              }
            }))
      }
    } else {
      Picker(
        select.placeholder ?? String(localized: "Make a selection"),
        selection: Binding(
          get: { selection.first ?? "" },
          set: { selection = $0.isEmpty ? [] : [$0] })
      ) {
        Text("None").tag("")
        ForEach(select.options, id: \.value) { option in
          Text(option.label).tag(option.value)
        }
      }
    }
  }
}

// MARK: - Message footers

extension MessageCell {
  /// "<bot> is thinking…" on a deferred reply, "Only you can see this" with
  /// Dismiss on an ephemeral one, and an interaction's failure, like Discord.
  struct InteractionFooter: View {
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore

    var body: some View {
      let flags = message.flags
      let failure = BotInteractions.shared.failures[message.id]
      if flags?.contains(.loading) == true {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text("\(message.author?.global_name ?? message.author?.username ?? String(localized: "The application")) is thinking…")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      if let failure {
        Label(failure, systemImage: "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.red)
      }
      if flags?.contains(.ephemeral) == true {
        HStack(spacing: 4) {
          Image(systemName: "eye")
          Text("Only you can see this")
          Text(verbatim: "•")
          Button("Dismiss message") {
            channelStore.messages.removeValue(forKey: message.id)
          }
          .buttonStyle(.plain)
          .foregroundStyle(.tint)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }
}
