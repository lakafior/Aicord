//
//  CatchUpSheet.swift
//  Aicord
//
//  "Catch Up": every unread channel at once, server → channel → a few points.
//  Opened from the top of the server list.
//

import AicordKit
import SwiftUI

/// The button above the servers that opens Catch Up.
struct CatchUpButton: View {
  @Environment(\.theme) var theme
  @Environment(\.colorScheme) var colorScheme
  @State private var showing = false

  var body: some View {
    Button {
      showing = true
    } label: {
      Rectangle()
        .fill(.clear)
        .aspectRatio(1, contentMode: .fit)
        .overlay {
          Image(systemName: "sparkles")
            .font(.title2)
            .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .background(theme.common.primaryButtonBackground.opacity(0.5))
        .clipShape(.rect(cornerRadius: 32, style: .continuous))
    }
    .buttonStyle(.borderless)
    .help("Catch Up")
    .accessibilityLabel("Catch Up")
    .accessibilityHint("Summarizes your unread channels")
    .sheet(isPresented: $showing) {
      CatchUpSheet()
    }
  }
}

struct CatchUpSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  /// At most this many channels, the most recently active first.
  static let channelLimit = 12

  struct Item: Identifiable {
    let id: ChannelSnowflake
    let guildId: GuildSnowflake?
    let place: String
    let channelName: String
    var state: State = .waiting
    var transcript = IntelligenceTranscript()

    enum State {
      case waiting, working
      case done([SummaryPoint])
      case failed(String)
    }
  }

  @State private var items: [Item] = []
  @State private var model: IntelligenceModel?
  @State private var failure: String?
  @State private var finished = false
  @State private var skipped = 0

  var body: some View {
    NavigationStack {
      List {
        if let failure {
          Label(failure, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.secondary)
        } else if finished && items.isEmpty {
          ContentUnavailableView(
            "You're All Caught Up", systemImage: "checkmark.circle",
            description: Text("No unread channels to summarize."))
        } else {
          if !finished {
            Section {
              progress
            }
          }
          ForEach(places, id: \.self) { place in
            Section(place) {
              ForEach(items.filter { $0.place == place }) { item in
                row(item)
              }
            }
          }
        }
        if let model {
          Section {
          } footer: {
            VStack(alignment: .leading, spacing: 4) {
              Text(
                "Up to \(Self.channelLimit) unread channels you've opened before, newest first, 100 messages each. Muted servers and channels are skipped\(IntelligencePreferences.allowsDMs ? "" : ", and so are direct messages")."
              )
              if skipped > 0 {
                Text("\(skipped) more unread channels weren't included.")
              }
              IntelligenceDestinationNote(model: model)
            }
          }
        }
      }
      .navigationTitle("Catch Up")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(finished ? "Done" : "Cancel") { dismiss() }
        }
      }
      .task { await catchUp() }
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 480)
    #endif
  }

  private var places: [String] {
    var seen: [String] = []
    for item in items where !seen.contains(item.place) { seen.append(item.place) }
    return seen
  }

  private var progress: some View {
    let done = items.filter {
      if case .done = $0.state { return true }
      if case .failed = $0.state { return true }
      return false
    }.count
    return VStack(alignment: .leading, spacing: 6) {
      ProgressView(value: Double(done), total: Double(max(items.count, 1)))
      Text(items.isEmpty ? "Finding unread channels…" : "Summarized \(done) of \(items.count) channels")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func row(_ item: Item) -> some View {
    Button {
      appState.selectedGuild = item.guildId
      appState.selectedChannel = item.id
      appState.chatOpen = true
      dismiss()
    } label: {
      Label(item.channelName, systemImage: item.guildId == nil ? "bubble.left" : "number")
        .font(.headline)
    }
    .tint(.primary)
    switch item.state {
    case .waiting:
      EmptyView()
    case .working:
      HStack {
        ProgressView().controlSize(.small)
        Text("Summarizing…").foregroundStyle(.secondary)
      }
    case .done(let points):
      if points.isEmpty {
        Text("Nothing worth summarizing.")
          .foregroundStyle(.secondary)
      }
      ForEach(points, id: \.self) { point in
        SummaryPointRow(point: point, transcript: item.transcript) { message in
          appState.open(guild: item.guildId, channel: item.id, message: message.id)
          dismiss()
        }
      }
    case .failed(let reason):
      Text(reason).foregroundStyle(.secondary)
    }
  }

  // MARK: Work

  struct Candidate {
    let channel: DiscordChannel
    let guild: Guild?
  }

  /// Unread channels you've opened before (so a newly joined server's backlog
  /// doesn't count), not muted, newest activity first.
  private func candidates() -> [Candidate] {
    let readStates = gw.readStates
    let guildSettings = gw.userGuildSettings
    var found: [Candidate] = []
    for guild in gw.user.guilds.values where !guildSettings.isMuted(guildId: guild.id) {
      for channel in guild.channels ?? []
      where channel.type == .guildText || channel.type == .guildAnnouncement {
        guard readStates.readStates[AnySnowflake(channel.id)] != nil,
          readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id),
          !guildSettings.isMuted(guildId: guild.id, channelId: channel.id),
          !(channel.parent_id.map { guildSettings.isMuted(guildId: guild.id, channelId: ChannelSnowflake($0.rawValue)) }
            ?? false)
        else { continue }
        found.append(Candidate(channel: channel, guild: guild))
      }
    }
    if IntelligencePreferences.allowsDMs {
      for channel in gw.user.privateChannels.values
      where !channel.isPendingMessageRequest && !channel.isSpam
        && readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id)
        && !guildSettings.isMuted(guildId: nil, channelId: channel.id)
      {
        found.append(Candidate(channel: channel, guild: nil))
      }
    }
    return found.sorted {
      ($0.channel.last_message_id ?? .init("0")) > ($1.channel.last_message_id ?? .init("0"))
    }
  }

  private func catchUp() async {
    // DMs are checked per channel below; the switch only decides whether they're listed
    switch IntelligenceModel.current() {
    case .success(let current): model = current
    case .failure(let reason):
      failure = reason.localizedDescription
      return
    }
    guard let model else { return }

    let all = candidates()
    skipped = max(0, all.count - Self.channelLimit)
    items = all.prefix(Self.channelLimit).map { candidate in
      let channel = candidate.channel
      let name =
        candidate.guild == nil
        ? MessagesView.title(of: channel) : "#" + (channel.name ?? "channel")
      return Item(
        id: channel.id,
        guildId: candidate.guild?.id,
        place: candidate.guild?.name ?? String(localized: "Direct Messages"),
        channelName: name
      )
    }

    for index in items.indices {
      if Task.isCancelled { return }
      items[index].state = .working
      let item = items[index]
      do {
        let acked = gw.readStates.readStates[AnySnowflake(item.id)]?.last_message_id
        let messages = try await IntelligenceSource.fetchMessages(
          channelId: item.id, limit: 100, after: acked, gw: gw)
        let transcript = IntelligenceSource.transcript(
          of: messages, guildId: item.guildId, gw: gw)
        items[index].transcript = transcript
        guard !transcript.isEmpty else {
          items[index].state = .done([])
          continue
        }
        let where_ = item.guildId == nil ? item.channelName : "\(item.channelName) on \(item.place)"
        let points = try await model.summarizer().summarize(
          lines: transcript.lines,
          context: "New messages in \(where_):",
          maxPoints: 3
        )
        items[index].state = .done(points)
      } catch is CancellationError {
        return
      } catch {
        if Task.isCancelled { return }
        items[index].state = .failed(error.localizedDescription)
      }
    }
    finished = true
  }
}
