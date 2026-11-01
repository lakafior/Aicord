//
//  ForwardSheet.swift
//  Aicord
//
//  Forwards a message to up to five DMs, group chats or server channels, with an
//  optional comment. Discord keeps an immutable copy of the message
//  (`message_snapshots`), so the forward reads the same even if the original
//  is edited or deleted later.
//

import AicordKit
import SwiftUI

/// The message a forward is being picked for.
struct ForwardTarget: Identifiable, Hashable {
  let message: DiscordChannel.Message
  /// Where the message lives, sent along so Discord can find it.
  let guildID: GuildSnowflake?

  var id: MessageSnowflake { message.id }

  /// Discord forwards only plain messages: no polls, calls or components.
  static func canForward(_ message: DiscordChannel.Message) -> Bool {
    guard message.type == .default || message.type == .reply else { return false }
    guard message.poll == nil, message.call == nil else { return false }
    // only the v2 flag is checked; Discord refuses other component messages itself
    if message.flags?.contains(.isComponentsV2) == true { return false }
    return true
  }
}

extension View {
  func forwardSheet() -> some View {
    self.modifier(ForwardSheetModifier())
  }
}

private struct ForwardSheetModifier: ViewModifier {
  @Environment(\.appState) var appState

  func body(content: Content) -> some View {
    @Bindable var appState = appState
    content
      .sheet(item: $appState.forwardTarget) { target in
        ForwardSheet(target: target)
          #if os(macOS)
            .frame(width: 420, height: 560)
          #endif
      }
  }
}

struct ForwardSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  let target: ForwardTarget

  /// Discord's own limit for one forward.
  static let maxDestinations = 5

  @State var searchText = ""
  @State var comment = ""
  @State var selected: [Destination] = []
  @State var sending = false
  @State var failures: [String] = []

  /// A place a message can be forwarded to.
  struct Destination: Identifiable, Hashable {
    var id: ChannelSnowflake
    var guildID: GuildSnowflake?
    var title: String
    var subtitle: String?
    var symbol: String
  }

  @ViewBuilder var sendButton: some View {
    if sending {
      ProgressView()
    } else {
      Button(selected.count > 1 ? "Send (\(selected.count))" : "Send") {
        Task { await send() }
      }
      .disabled(selected.isEmpty)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForwardPreview(message: target.message)
        }

        if !selected.isEmpty {
          Section {
            TextField("Add a comment (optional)", text: $comment, axis: .vertical)
              .lineLimit(1...4)
          }
          Section {
            ForEach(selected) { row($0) }
          } header: {
            Text("Sending To — \(selected.count) of \(Self.maxDestinations)")
          }
        }

        if !failures.isEmpty {
          Section {
            ForEach(failures, id: \.self) { failure in
              Label(failure, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            }
          }
        }

        let direct = directMessages.filter { !selected.contains($0) }
        if !direct.isEmpty {
          Section("Direct Messages") {
            ForEach(direct) { row($0) }
          }
        }
        let channels = serverChannels.filter { !selected.contains($0) }
        if !channels.isEmpty {
          Section("Server Channels") {
            ForEach(channels) { row($0) }
          }
        }
        if direct.isEmpty && channels.isEmpty && selected.isEmpty {
          ContentUnavailableView.search(text: searchText)
            .listRowBackground(Color.clear)
        }
      }
      .navigationTitle("Forward")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
          text: $searchText,
          placement: .navigationBarDrawer(displayMode: .always),
          prompt: "Search people and channels"
        )
      #else
        .searchable(text: $searchText, prompt: "Search people and channels")
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        #if os(macOS)
          ToolbarItem(placement: .confirmationAction) {
            sendButton
          }
        #endif
      }
      #if os(iOS)
        // the navigation bar drops its buttons while the search field is
        // active, so Send sits above the keyboard instead
        .safeAreaInset(edge: .bottom) {
          if !selected.isEmpty {
            sendButton
              .buttonStyle(.glassProminent)
              .controlSize(.large)
              .frame(maxWidth: .infinity)
              .padding(.horizontal)
              .padding(.bottom, 8)
          }
        }
      #endif
    }
  }

  @ViewBuilder
  func row(_ destination: Destination) -> some View {
    let isSelected = selected.contains(destination)
    Button {
      if isSelected {
        selected.removeAll { $0 == destination }
      } else if selected.count < Self.maxDestinations {
        selected.append(destination)
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: destination.symbol)
          .foregroundStyle(.secondary)
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
          Text(destination.title)
            .lineLimit(1)
          if let subtitle = destination.subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
          .imageScale(.large)
      }
      .contentShape(.rect)
    }
    .tint(.primary)
    .disabled(!isSelected && selected.count >= Self.maxDestinations)
  }

  // MARK: Destinations

  var query: String { searchText.trimmingCharacters(in: .whitespaces) }

  func matches(_ strings: String?...) -> Bool {
    guard !query.isEmpty else { return true }
    return strings.contains { $0?.localizedCaseInsensitiveContains(query) == true }
  }

  /// DMs and group chats, newest first; requests and spam stay out.
  var directMessages: [Destination] {
    gw.user.privateChannels.values
      .filter { !$0.isSpam && !$0.isPendingMessageRequest }
      .sorted {
        ($0.last_message_id?.rawValue ?? $0.id.rawValue)
          .compare($1.last_message_id?.rawValue ?? $1.id.rawValue, options: .numeric)
          == .orderedDescending
      }
      .map { channel in
        Destination(
          id: channel.id,
          guildID: nil,
          title: MessagesView.title(of: channel),
          subtitle: channel.type == .groupDm ? String(localized: "Group") : nil,
          symbol: channel.type == .groupDm ? "person.2.fill" : "person.fill"
        )
      }
      .filter { matches($0.title) }
      .prefix(query.isEmpty ? 8 : 30)
      .map { $0 }
  }

  static let textChannelTypes: Set<DiscordChannel.Kind> = [
    .guildText, .guildAnnouncement, .guildVoice, .guildStageVoice,
  ]

  /// Text channels you can post in. Without a search only the server you are
  /// looking at is listed; a search covers every server.
  var serverChannels: [Destination] {
    let guilds: [Guild]
    if query.isEmpty {
      guilds = appState.selectedGuild.flatMap { gw.user.guilds[$0] }.map { [$0] } ?? []
    } else {
      guilds = Array(gw.user.guilds.values)
    }
    return guilds.flatMap { guild in
      (guild.channels ?? [])
        .filter { $0.type.map(Self.textChannelTypes.contains) ?? false }
        .filter { matches($0.name, guild.name) }
        .filter { canSend(in: $0, guild: guild.id) }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        .map { channel in
          Destination(
            id: channel.id,
            guildID: guild.id,
            title: channel.name ?? "",
            subtitle: guild.name,
            symbol: ChannelButton.symbol(for: channel.type)
          )
        }
    }
    .prefix(query.isEmpty ? 30 : 40)
    .map { $0 }
  }

  /// Checked only for servers already loaded, where your roles are known;
  /// elsewhere Discord answers for itself when the forward is sent.
  func canSend(in channel: DiscordChannel, guild: GuildSnowflake) -> Bool {
    guard let store = gw.existingGuildStore(for: guild) else { return true }
    return store.hasPermission(channel: channel, .viewChannel)
      && store.hasPermission(channel: channel, .sendMessages)
  }

  // MARK: Sending

  func send() async {
    sending = true
    failures = []
    defer { sending = false }
    let reference = DiscordChannel.Message.MessageReference(
      type: .forward,
      message_id: target.message.id,
      channel_id: target.message.channel_id,
      guild_id: target.guildID,
      fail_if_not_exists: false
    )
    let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    var failed: [Destination] = []
    for destination in selected {
      do {
        // the forward first, then the comment as its own message, like Discord
        try await gw.client.createMessage(
          channelId: destination.id,
          payload: .init(message_reference: reference)
        ).guardSuccess()
        if !note.isEmpty {
          try await gw.client.createMessage(
            channelId: destination.id,
            payload: .init(content: note)
          ).guardSuccess()
        }
      } catch {
        failed.append(destination)
        failures.append(
          String(localized: "Couldn't forward to \(destination.title): \(error.localizedDescription)")
        )
      }
    }
    if failed.isEmpty {
      dismiss()
    } else {
      // keep the ones that failed selected so Send can retry them
      selected = failed
    }
  }
}

/// A short look at what is being forwarded.
private struct ForwardPreview: View {
  let message: DiscordChannel.Message

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if let author = message.author {
        Profile.Avatar(member: nil, user: author.toPartialUser())
          .frame(width: 28, height: 28)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(message.author?.global_name ?? message.author?.username ?? "")
          .font(.subheadline.weight(.semibold))
        Text(summary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
  }

  var summary: String {
    if !message.content.isEmpty { return message.content }
    if !message.attachments.isEmpty {
      return String(AttributedString(localized: "^[\(message.attachments.count) attachment](inflect: true)").characters)
    }
    if !message.embeds.isEmpty { return String(localized: "Embed") }
    return String(localized: "Message")
  }
}
