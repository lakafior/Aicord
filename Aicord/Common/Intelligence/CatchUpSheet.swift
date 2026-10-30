//
//  CatchUpSheet.swift
//  Aicord
//
//  "Catch Up" in a server's menu: its unread channels at once, channel → a
//  few points each.
//

import AicordKit
import SwiftUI

struct CatchUpSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  let guildId: GuildSnowflake

  /// At most this many channels, the most recently active first.
  static let channelLimit = 15

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
  @State private var unreadable = 0
  @State private var total = 0

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
          ForEach(items) { item in
            Section {
              row(item)
            }
          }
        }
        if let model {
          Section {
          } footer: {
            VStack(alignment: .leading, spacing: 4) {
              Text(
                "Up to \(Self.channelLimit) unread channels, newest first, the last 100 unread messages of each. Muted channels are skipped."
              )
              .fixedSize(horizontal: false, vertical: true)
              if skipped > 0 {
                Text("\(skipped) more unread channels weren't included.")
              }
              if unreadable > 0 {
                Text("\(unreadable) channels couldn't be read and were left out.")
              }
              IntelligenceDestinationNote(model: model)
            }
          }
        }
      }
      .navigationTitle(gw.user.guilds[guildId]?.name ?? String(localized: "Catch Up"))
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

  private var progress: some View {
    let done = items.filter {
      if case .done = $0.state { return true }
      if case .failed = $0.state { return true }
      return false
    }.count
    return VStack(alignment: .leading, spacing: 6) {
      ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
      Text(total == 0 ? "Finding unread channels…" : "Summarized \(done) of \(total) channels")
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
      Label(item.channelName, systemImage: "number")
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

  /// The server's unread text channels you can view, except muted ones,
  /// newest activity first.
  private func candidates() -> [DiscordChannel] {
    guard let guild = gw.user.guilds[guildId] else { return [] }
    let readStates = gw.readStates
    let guildSettings = gw.userGuildSettings
    let store = gw.existingGuildStore(for: guildId)
    return (guild.channels ?? []).filter { channel in
      (channel.type == .guildText || channel.type == .guildAnnouncement)
        && store?.hasPermission(channel: channel, .viewChannel) != false
        && readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id)
        && !guildSettings.isMuted(guildId: guildId, channelId: channel.id)
        && !(channel.parent_id.map {
          guildSettings.isMuted(guildId: guildId, channelId: ChannelSnowflake($0.rawValue))
        } ?? false)
    }
    .sorted { ($0.last_message_id ?? .init("0")) > ($1.last_message_id ?? .init("0")) }
  }

  private func catchUp() async {
    switch IntelligenceModel.current() {
    case .success(let current): model = current
    case .failure(let reason):
      failure = reason.localizedDescription
      return
    }
    guard let model else { return }

    let all = candidates()
    total = min(all.count, Self.channelLimit)
    let place = gw.user.guilds[guildId]?.name ?? ""
    // channels the app can't check permissions for yet may refuse to load;
    // those are left out and the next ones tried, up to a limit of requests
    var tried = 0
    for channel in all {
      if Task.isCancelled { return }
      guard items.count < Self.channelLimit, tried < Self.channelLimit * 2 else { break }
      tried += 1
      let name = channel.name ?? "channel"
      let messages: [DiscordChannel.Message]
      do {
        let acked = gw.readStates.readStates[AnySnowflake(channel.id)]?.last_message_id
        messages = try await IntelligenceSource.fetchMessages(
          channelId: channel.id, limit: 100, after: acked, gw: gw)
      } catch is CancellationError {
        return
      } catch {
        if Task.isCancelled { return }
        unreadable += 1
        continue
      }
      let transcript = IntelligenceSource.transcript(of: messages, guildId: guildId, gw: gw)
      guard !transcript.isEmpty else { continue }
      items.append(
        Item(
          id: channel.id, guildId: guildId, place: place, channelName: name, state: .working,
          transcript: transcript))
      let index = items.count - 1
      do {
        let points = try await model.summarizer().summarize(
          lines: transcript.lines,
          context: "New messages in #\(name) on \(place):",
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
    skipped = max(0, all.count - tried)
    finished = true
  }
}
