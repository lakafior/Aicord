//
//  ServerOnboarding.swift
//  Aicord
//

import AicordKit
import SwiftUI

/// What a server offers besides its channels: onboarding and scheduled events.
@MainActor
@Observable
final class GuildPlaces {
  var onboarding: Guild.Onboarding?
  var events: [GuildScheduledEvent] = []

  var upcoming: [GuildScheduledEvent] {
    events.filter { $0.status == .scheduled || $0.status == .active }
  }

  /// Channels & Roles works from the server's questions even with the
  /// onboarding flow for new members turned off, like Discord's own apps.
  var hasOnboarding: Bool {
    !(onboarding?.prompts.isEmpty ?? true)
  }

  func load(_ guildId: GuildSnowflake, client: any DiscordClient) async {
    async let onboardingResponse = try? client.getGuildOnboarding(guildId: guildId).decode()
    async let eventsResponse = try? client.listGuildScheduledEvents(guildId: guildId, withUserCount: true)
      .decode()
    let (loadedOnboarding, loadedEvents) = await (onboardingResponse, eventsResponse)
    onboarding = loadedOnboarding
    events = loadedEvents ?? []
  }
}

/// Rows above a server's channels: its rules screen while you haven't agreed
/// yet, its upcoming events and Channels & Roles when it has onboarding.
/// A server you just joined opens its rules or onboarding by itself, once.
struct GuildPlacesSection: View {
  var guild: GuildStore
  var places: GuildPlaces
  @Environment(\.gateway) var gw

  @State private var showsOnboarding = false
  @State private var showsVerification = false
  @State private var showsEvents = false

  private var me: Guild.PartialMember? {
    gw.user.currentUser.flatMap { guild.member($0.id) }
  }

  private var isPending: Bool { me?.pending == true }

  var body: some View {
    let upcoming = places.upcoming
    if isPending || places.hasOnboarding || !upcoming.isEmpty {
      Section {
        if isPending {
          Button {
            showsVerification = true
          } label: {
            Label("Agree to the Server Rules", systemImage: "checkmark.shield")
              .foregroundStyle(Color.accentColor)
          }
        }
        if !upcoming.isEmpty {
          Button {
            showsEvents = true
          } label: {
            Label {
              Text("^[\(upcoming.count) Event](inflect: true)")
            } icon: {
              Image(
                systemName: upcoming.contains { $0.status == .active }
                  ? "dot.radiowaves.left.and.right" : "calendar")
            }
          }
        }
        if places.hasOnboarding {
          Button {
            showsOnboarding = true
          } label: {
            Label("Channels & Roles", systemImage: "checklist")
          }
        }
      }
      .buttonStyle(.plain)
      .selectionDisabled()
      .sheet(isPresented: $showsOnboarding) {
        OnboardingSheet(guildId: guild.guildId)
      }
      .sheet(isPresented: $showsVerification) {
        MemberVerificationSheet(guildId: guild.guildId)
      }
      .sheet(isPresented: $showsEvents) {
        ScheduledEventsSheet(guildId: guild.guildId)
      }
      .onAppear { openOnceAfterJoining() }
    }
  }

  /// Discord shows the rules, then onboarding, right after joining; do the same
  /// for a server joined in the last day, only the first time it's opened here.
  private func openOnceAfterJoining() {
    guard let joined = me?.joined_at?.date, Date.now.timeIntervalSince(joined) < 86_400 else { return }
    let key = "Onboarding.Shown.\(guild.guildId.rawValue)"
    guard !UserDefaults.standard.bool(forKey: key) else { return }
    if isPending {
      UserDefaults.standard.set(true, forKey: key)
      showsVerification = true
    } else if let onboarding = places.onboarding, onboarding.enabled,
      (onboarding.responses ?? []).isEmpty,
      onboarding.prompts.contains(where: \.in_onboarding)
    {
      UserDefaults.standard.set(true, forKey: key)
      showsOnboarding = true
    }
  }
}

// MARK: - Onboarding

/// A server's onboarding questions: each option gives roles or opens channels.
/// Opened after joining and later from Channels & Roles.
struct OnboardingSheet: View {
  var guildId: GuildSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  @State private var onboarding: Guild.Onboarding?
  @State private var selected: Set<OnboardingPromptOptionSnowflake> = []
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var error: String?

  private var prompts: [Guild.Onboarding.Prompt] { onboarding?.prompts ?? [] }

  /// Required questions without an answer keep Save disabled.
  private var missingRequired: Bool {
    prompts.contains { prompt in
      prompt.required && !prompt.options.contains { selected.contains($0.id) }
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if let onboarding, onboarding.prompts.isEmpty {
          Text("This server has no channels or roles to pick.")
            .foregroundStyle(.secondary)
        }
        ForEach(prompts, id: \.id) { prompt in
          Section {
            ForEach(prompt.options, id: \.id) { option in
              optionRow(option, in: prompt)
            }
          } header: {
            HStack {
              Text(prompt.title)
              if prompt.required {
                Text("Required").foregroundStyle(.red)
              }
            }
          } footer: {
            Text(prompt.single_select ? "Pick one." : "Pick any that apply.")
          }
        }
      }
      .overlay {
        if isLoading { ProgressView() }
      }
      .navigationTitle("Channels & Roles")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Save") { save() }
              .disabled(onboarding == nil || missingRequired)
          }
        }
      }
      .saveErrorAlert($error)
      .task { await load() }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 520)
    #endif
  }

  private func optionRow(_ option: Guild.Onboarding.Prompt.Option, in prompt: Guild.Onboarding.Prompt)
    -> some View
  {
    let isOn = selected.contains(option.id)
    return Button {
      if isOn {
        selected.remove(option.id)
      } else {
        if prompt.single_select {
          for other in prompt.options { selected.remove(other.id) }
        }
        selected.insert(option.id)
      }
    } label: {
      HStack(spacing: 10) {
        if let emoji = option.emoji, emoji.id != nil || emoji.name != nil {
          MessageCell.ComponentEmoji(emoji: emoji)
            .frame(width: 24)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(option.title)
          if let description = option.description, !description.isEmpty {
            Text(description)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isOn ? Color.accentColor : .secondary)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }

  private func load() async {
    defer { isLoading = false }
    do {
      let loaded = try await gw.client.getGuildOnboarding(guildId: guildId).decode()
      onboarding = loaded
      selected = Set(loaded.responses ?? [])
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func save() {
    guard let onboarding else { return }
    let now = Int64(Date.now.timeIntervalSince1970 * 1000)
    var promptsSeen = onboarding.onboarding_prompts_seen ?? [:]
    var optionsSeen = onboarding.onboarding_responses_seen ?? [:]
    for prompt in onboarding.prompts {
      promptsSeen[prompt.id.rawValue] = promptsSeen[prompt.id.rawValue] ?? now
      for option in prompt.options {
        optionsSeen[option.id.rawValue] = optionsSeen[option.id.rawValue] ?? now
      }
    }
    let payload = Payloads.UpdateOnboardingResponses(
      onboarding_responses: Array(selected),
      onboarding_prompts_seen: promptsSeen,
      onboarding_responses_seen: optionsSeen
    )
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        try await gw.client.updateOnboardingResponses(guildId: guildId, payload: payload).guardSuccess()
        dismiss()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Member verification

/// A server's rules (and any questions) to agree to before you can talk there.
struct MemberVerificationSheet: View {
  var guildId: GuildSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  @State private var verification: MemberVerification?
  @State private var fields: [MemberVerification.FormField] = []
  @State private var isLoading = true
  @State private var isSending = false
  @State private var submitted = false
  @State private var error: String?

  private var isComplete: Bool {
    fields.allSatisfy { field in
      guard field.required else { return true }
      switch field.response {
      case .bool(let agreed): return agreed
      case .string(let text): return !text.trimmingCharacters(in: .whitespaces).isEmpty
      case .int: return true
      case nil: return false
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        if let description = verification?.description, !description.isEmpty {
          Section { Text(description) }
        }
        ForEach(fields.indices, id: \.self) { index in
          fieldSection(index)
        }
        if submitted {
          Section {
            Label("Sent. The server's moderators will review your answers.", systemImage: "clock")
          }
        }
      }
      .formStyle(.grouped)
      .overlay {
        if isLoading { ProgressView() }
      }
      .navigationTitle("Server Rules")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(submitted ? "Done" : "Cancel") { dismiss() }
        }
        if !submitted {
          ToolbarItem(placement: .confirmationAction) {
            if isSending {
              ProgressView()
            } else {
              Button("Submit") { submit() }
                .disabled(verification == nil || !isComplete)
            }
          }
        }
      }
      .saveErrorAlert($error)
      .task { await load() }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 520)
    #endif
  }

  @ViewBuilder
  private func fieldSection(_ index: Int) -> some View {
    let field = fields[index]
    switch field.field_type {
    case "TERMS":
      Section {
        ForEach(Array((field.values ?? []).enumerated()), id: \.offset) { number, rule in
          HStack(alignment: .top, spacing: 8) {
            Text("\(number + 1).").foregroundStyle(.secondary).monospacedDigit()
            Text(rule)
          }
        }
        Toggle(
          "I have read and agree to the rules",
          isOn: Binding(
            get: { fields[index].response == .bool(true) },
            set: { fields[index].response = .bool($0) }
          ))
      } header: {
        Text(field.label)
      }
    case "MULTIPLE_CHOICE":
      Section {
        Picker(
          field.label,
          selection: Binding(
            get: { if case .int(let choice) = fields[index].response { choice } else { -1 } },
            set: { fields[index].response = .int($0) }
          )
        ) {
          Text("Choose…").tag(-1)
          ForEach(Array((field.choices ?? []).enumerated()), id: \.offset) { choice, text in
            Text(text).tag(choice)
          }
        }
      } header: {
        Text(field.label)
      }
    case "TEXT_INPUT", "PARAGRAPH":
      Section {
        TextField(
          field.placeholder ?? "",
          text: Binding(
            get: { if case .string(let text) = fields[index].response { text } else { "" } },
            set: { fields[index].response = .string($0) }
          ),
          axis: field.field_type == "PARAGRAPH" ? .vertical : .horizontal
        )
      } header: {
        Text(field.label)
      } footer: {
        if let description = field.description { Text(description) }
      }
    default:
      Section {
        Text("Aicord can't answer this kind of question yet. Open the server in Discord to finish.")
          .foregroundStyle(.secondary)
      } header: {
        Text(field.label)
      }
    }
  }

  private func load() async {
    defer { isLoading = false }
    do {
      let loaded = try await gw.client.getMemberVerification(guildId: guildId).decode()
      verification = loaded
      fields = loaded.form_fields
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func submit() {
    let payload = Payloads.SubmitMemberVerification(form_fields: fields, version: verification?.version)
    isSending = true
    Task {
      defer { isSending = false }
      do {
        let result = try await gw.client.submitMemberVerification(guildId: guildId, payload: payload)
          .decode()
        if result.application_status == "SUBMITTED" {
          submitted = true
        } else {
          dismiss()
        }
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

// MARK: - Scheduled events

/// A server's upcoming and live events, with Interested and where they happen.
struct ScheduledEventsSheet: View {
  var guildId: GuildSnowflake
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  @State private var events: [GuildScheduledEvent] = []
  @State private var interested: Set<GuildScheduledEventSnowflake> = []
  @State private var isLoading = true
  @State private var error: String?

  var body: some View {
    NavigationStack {
      List {
        ForEach(events, id: \.id) { event in
          ScheduledEventRow(
            event: event,
            channelName: event.channel_id.flatMap { gw.existingGuildStore(for: guildId)?.channels[$0]?.name },
            isInterested: interested.contains(event.id),
            toggleInterest: { toggle(event) },
            openChannel: { channel in
              dismiss()
              appState.selectedChannel = channel
              appState.chatOpen = true
            }
          )
        }
      }
      .overlay {
        if isLoading {
          ProgressView()
        } else if events.isEmpty {
          ContentUnavailableView("No Upcoming Events", systemImage: "calendar")
        }
      }
      .navigationTitle("Events")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .refreshable { await load() }
      .saveErrorAlert($error)
      .task { await load() }
    }
    #if os(macOS)
      .frame(minWidth: 440, minHeight: 520)
    #endif
  }

  private func load() async {
    defer { isLoading = false }
    async let eventsResponse = try? gw.client.listGuildScheduledEvents(guildId: guildId, withUserCount: true)
      .decode()
    async let rsvpResponse = try? gw.client.listOwnScheduledEventRSVPs(guildIds: [guildId]).decode()
    events = (await eventsResponse ?? [])
      .filter { $0.status == .scheduled || $0.status == .active }
      .sorted { $0.scheduled_start_time.date < $1.scheduled_start_time.date }
    interested = Set((await rsvpResponse ?? []).map(\.guild_scheduled_event_id))
  }

  private func toggle(_ event: GuildScheduledEvent) {
    let wasInterested = interested.contains(event.id)
    // show it at once; put it back if Discord says no
    if wasInterested { interested.remove(event.id) } else { interested.insert(event.id) }
    adjustCount(event.id, by: wasInterested ? -1 : 1)
    Task {
      do {
        let response =
          wasInterested
          ? try await gw.client.removeScheduledEventInterest(guildId: guildId, eventId: event.id)
          : try await gw.client.addScheduledEventInterest(guildId: guildId, eventId: event.id)
        try response.guardSuccess()
      } catch {
        if wasInterested { interested.insert(event.id) } else { interested.remove(event.id) }
        adjustCount(event.id, by: wasInterested ? 1 : -1)
        self.error = error.localizedDescription
      }
    }
  }

  private func adjustCount(_ id: GuildScheduledEventSnowflake, by delta: Int) {
    guard let index = events.firstIndex(where: { $0.id == id }) else { return }
    events[index].user_count = max(0, (events[index].user_count ?? 0) + delta)
  }
}

struct ScheduledEventRow: View {
  var event: GuildScheduledEvent
  var channelName: String?
  var isInterested: Bool
  var toggleInterest: () -> Void
  var openChannel: (ChannelSnowflake) -> Void
  @Environment(\.openURL) var openURL

  private var imageURL: URL? {
    event.image.flatMap {
      URL(string: "https://cdn.discordapp.com/guild-events/\(event.id.rawValue)/\($0).png?size=512")
    }
  }

  private var locationURL: URL? {
    guard let location = event.entity_metadata?.location,
      let url = URL(string: location), url.scheme?.hasPrefix("http") == true
    else { return nil }
    return url
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let imageURL {
        Color.clear
          .aspectRatio(2.5, contentMode: .fit)
          .overlay(NukeImage(url: imageURL).resizable().scaledToFill())
          .clipShape(.rect(cornerRadius: 10))
          .accessibilityHidden(true)
      }
      HStack(spacing: 6) {
        if event.status == .active {
          Text("Live Now")
            .font(.caption.weight(.bold))
            .foregroundStyle(.green)
        } else {
          Text(event.scheduled_start_time.date, format: .dateTime.weekday().day().month().hour().minute())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        if let end = event.scheduled_end_time?.date {
          Text(verbatim: "–")
          Text(end, format: .dateTime.hour().minute())
            .font(.caption)
        }
      }
      .font(.caption)
      Text(event.name)
        .font(.headline)
      if let description = event.description, !description.isEmpty {
        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(4)
      }
      HStack(spacing: 12) {
        location
        Spacer(minLength: 0)
        Label("\(event.user_count ?? 0)", systemImage: "person.2")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityLabel(Text("^[\(event.user_count ?? 0) person](inflect: true) interested"))
        Button(action: toggleInterest) {
          Label("Interested", systemImage: isInterested ? "checkmark" : "bell")
        }
        .buttonStyle(.bordered)
        .tint(isInterested ? Color.accentColor : .secondary)
        .accessibilityAddTraits(isInterested ? .isSelected : [])
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var location: some View {
    if let channel = event.channel_id {
      Button {
        openChannel(channel)
      } label: {
        Label(channelName ?? String(localized: "Voice Channel"), systemImage: event.entity_type == .stageInstance ? "person.wave.2" : "speaker.wave.2")
          .font(.caption)
          .lineLimit(1)
      }
      .buttonStyle(.borderless)
    } else if let place = event.entity_metadata?.location {
      if let locationURL {
        Button {
          openURL(locationURL)
        } label: {
          Label(place, systemImage: "link").font(.caption).lineLimit(1)
        }
        .buttonStyle(.borderless)
      } else {
        Label(place, systemImage: "mappin.and.ellipse")
          .font(.caption)
          .lineLimit(1)
          .foregroundStyle(.secondary)
      }
    }
  }
}
