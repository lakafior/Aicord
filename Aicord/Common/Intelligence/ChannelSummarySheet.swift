//
//  ChannelSummarySheet.swift
//  Aicord
//
//  "Summarize" from the channel header: the unread or latest messages as a
//  few points, each linking to the messages it came from.
//

import AicordKit
import SwiftUI

enum SummaryRange: Hashable, Identifiable {
  case unread
  case last(Int)

  var id: String {
    switch self {
    case .unread: "unread"
    case .last(let count): "last\(count)"
    }
  }

  var title: LocalizedStringKey {
    switch self {
    case .unread: "Unread Messages"
    case .last(let count): "Last \(count) Messages"
    }
  }

  var sheetTitle: LocalizedStringKey {
    self == .unread ? "Catch Up" : "Summary"
  }
}

/// The Intelligence menu in the channel's toolbar.
struct ChannelIntelligenceMenu: View {
  @Environment(\.gateway) var gw
  let channelId: ChannelSnowflake
  @Binding var summary: SummaryRange?

  var body: some View {
    Menu {
      Section("Summarize") {
        Button {
          summary = .unread
        } label: {
          Label("Catch Up on Unread", systemImage: "envelope.badge")
        }
        .disabled(!hasUnread)
        ForEach([100, 500, 1_000], id: \.self) { count in
          Button {
            summary = .last(count)
          } label: {
            Label("Last \(count) Messages", systemImage: "text.line.first.and.arrowtriangle.forward")
          }
        }
      }
    } label: {
      Label("Intelligence", systemImage: "sparkles")
    }
    .menuIndicator(.hidden)
  }

  private var hasUnread: Bool {
    let last =
      gw.user.privateChannels[channelId]?.last_message_id
      ?? gw.user.guilds.values.lazy.compactMap { $0.channels?.first { $0.id == channelId } }.first?
      .last_message_id
    return gw.readStates.isUnread(channelId: channelId, lastMessageId: last)
  }
}

struct ChannelSummarySheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  let channelId: ChannelSnowflake
  let guildId: GuildSnowflake?
  let channelName: String
  let range: SummaryRange

  enum Phase {
    case fetching
    case summarizing(Double)
    case done([SummaryPoint])
    case empty(String)
    case failed(String)
  }

  @State private var phase: Phase = .fetching
  @State private var transcript = IntelligenceTranscript()
  @State private var model: IntelligenceModel?
  @State private var run = 0

  var body: some View {
    NavigationStack {
      List {
        Section {
          content
        } header: {
          Text(range.title)
        } footer: {
          VStack(alignment: .leading, spacing: 4) {
            if !transcript.isEmpty {
              Text("Read \(transcript.lines.count) messages from \(channelName).")
            }
            if transcript.hiddenCount > 0 {
              Text("\(transcript.hiddenCount) hidden messages were left out.")
            }
            if let model { IntelligenceDestinationNote(model: model) }
          }
        }
      }
      .navigationTitle(range.sheetTitle)
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(isWorking ? "Cancel" : "Done") { dismiss() }
        }
        if case .done = phase {
          ToolbarItem(placement: .primaryAction) {
            Button {
              run += 1
            } label: {
              Label("Summarize Again", systemImage: "arrow.clockwise")
            }
          }
        }
      }
      .task(id: run) { await summarize() }
    }
    #if os(macOS)
      .frame(minWidth: 460, minHeight: 420)
    #endif
  }

  private var isWorking: Bool {
    switch phase {
    case .fetching, .summarizing: true
    default: false
    }
  }

  @ViewBuilder
  private var content: some View {
    switch phase {
    case .fetching:
      HStack {
        ProgressView()
        Text("Loading messages…")
          .foregroundStyle(.secondary)
      }
    case .summarizing(let progress):
      VStack(alignment: .leading, spacing: 6) {
        ProgressView(value: progress)
        Text(
          transcript.lines.count > 0
            ? "Summarizing \(transcript.lines.count) messages…" : "Summarizing…"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    case .done(let points):
      if points.isEmpty {
        Text("The model found nothing to summarize.")
          .foregroundStyle(.secondary)
      }
      ForEach(points, id: \.self) { point in
        SummaryPointRow(point: point, transcript: transcript) { message in
          open(message)
        }
      }
    case .empty(let text):
      ContentUnavailableView(text, systemImage: "text.bubble")
    case .failed(let text):
      Label(text, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.secondary)
    }
  }

  private func open(_ message: DiscordChannel.Message) {
    appState.open(guild: guildId, channel: channelId, message: message.id)
    dismiss()
  }

  private func summarize() async {
    phase = .fetching
    let isDM = IntelligenceSource.isDirectMessage(channelId, gw: gw)
    let model: IntelligenceModel
    switch IntelligenceModel.current(isDirectMessage: isDM) {
    case .success(let current): model = current
    case .failure(let reason):
      phase = .failed(reason.localizedDescription)
      return
    }
    self.model = model
    do {
      let messages: [DiscordChannel.Message]
      switch range {
      case .unread:
        let acked = gw.readStates.readStates[AnySnowflake(channelId)]?.last_message_id
        messages = try await IntelligenceSource.fetchMessages(
          channelId: channelId, limit: 1_000, after: acked, gw: gw)
      case .last(let count):
        messages = try await IntelligenceSource.fetchMessages(
          channelId: channelId, limit: count, gw: gw)
      }
      transcript = IntelligenceSource.transcript(of: messages, guildId: guildId, gw: gw)
      guard !transcript.isEmpty else {
        phase = .empty(
          String(localized: range == .unread ? "No unread messages" : "No messages to summarize"))
        return
      }
      phase = .summarizing(0)
      let points = try await model.summarizer().summarize(
        lines: transcript.lines,
        context: "Conversation in \(channelName):",
        maxPoints: 8
      ) { value in
        Task { @MainActor in
          if case .summarizing = phase { phase = .summarizing(value) }
        }
      }
      phase = .done(points)
    } catch is CancellationError {
      // the sheet closed
    } catch {
      if Task.isCancelled { return }
      phase = .failed(error.localizedDescription)
    }
  }
}

/// A summary point and links to the messages it cites.
struct SummaryPointRow: View {
  let point: SummaryPoint
  let transcript: IntelligenceTranscript
  let open: (DiscordChannel.Message) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(point.text)
        .textSelection(.enabled)
      let sources = point.refs.prefix(4).compactMap(transcript.message(for:))
      if !sources.isEmpty {
        SourceChipsLayout(spacing: 6) {
          ForEach(sources, id: \.id) { message in
            Button {
              open(message)
            } label: {
              Text(Self.label(for: message))
                .font(.caption)
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Opens the message")
          }
        }
      }
    }
    .padding(.vertical, 2)
  }

  static func label(for message: DiscordChannel.Message) -> String {
    let name = message.member?.nick ?? message.author?.global_name ?? message.author?.username ?? ""
    let date = message.timestamp.date
    let time =
      Calendar.current.isDateInToday(date)
      ? date.formatted(date: .omitted, time: .shortened)
      : date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    return "\(name) · \(time)"
  }
}

/// Source links side by side, wrapping onto more lines when they don't fit.
struct SourceChipsLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = rows(for: subviews, width: proposal.width ?? .infinity)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: min(width, proposal.width ?? width), height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in rows(for: subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
        subviews[index].place(
          at: CGPoint(x: x, y: y), proposal: .init(width: min(size.width, bounds.width), height: nil))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.init(width: width, height: nil))
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > width, !current.indices.isEmpty {
        rows.append(current)
        current = Row()
      }
      current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}
