//
//  ChannelIndex.swift
//  Aicord
//
//  "Index Channel": the last N messages of a channel kept on this device with
//  a sentence vector each, so they can be searched by meaning and Ask About
//  This Channel can reach further back than the recent messages. Built and
//  searched on the device; the index never leaves it.
//

import AicordKit
import SwiftUI

struct ChannelIndex: Codable, Sendable {
  struct Entry: Codable, Sendable {
    var id: String
    var date: Date
    /// "Name: text", already through the reader's filters.
    var text: String
    /// Float32 sentence vector, when the on-device model was there.
    var vector: Data?

    var floats: [Float]? {
      vector.map { data in
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
      }
    }
  }

  var channelId: String
  var created: Date
  var updated: Date
  /// Oldest first.
  var entries: [Entry]

  var hasVectors: Bool { entries.contains { $0.vector != nil } }

  /// The entries that match `query` best, best first.
  func matches(for query: String, limit: Int) async -> [Entry] {
    guard !entries.isEmpty else { return [] }
    let queryVector = await SentenceEmbedder.shared.vector(for: query)
    let scores = SemanticRanker.scores(
      query: query, documents: entries.map(\.text), queryVector: queryVector,
      documentVectors: entries.map(\.floats))
    return entries.indices
      .filter { scores[$0] > 0.15 }
      .sorted { scores[$0] > scores[$1] }
      .prefix(limit)
      .map { entries[$0] }
  }
}

/// Indexes as files in Application Support, one per channel.
enum ChannelIndexFiles {
  static var directory: URL {
    URL.applicationSupportDirectory.appending(path: "ChannelIndexes", directoryHint: .isDirectory)
  }

  static func url(for channelId: ChannelSnowflake) -> URL {
    directory.appending(path: "\(channelId.rawValue).json")
  }

  static func exists(_ channelId: ChannelSnowflake) -> Bool {
    FileManager.default.fileExists(atPath: url(for: channelId).path(percentEncoded: false))
  }

  static func load(_ channelId: ChannelSnowflake) -> ChannelIndex? {
    guard let data = try? Data(contentsOf: url(for: channelId)) else { return nil }
    return try? JSONDecoder().decode(ChannelIndex.self, from: data)
  }

  static func save(_ index: ChannelIndex) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(index)
    try data.write(to: url(for: ChannelSnowflake(index.channelId)), options: .atomic)
  }

  static func delete(_ channelId: ChannelSnowflake) {
    try? FileManager.default.removeItem(at: url(for: channelId))
  }

  static func size(_ channelId: ChannelSnowflake) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: url(for: channelId).path(percentEncoded: false))[.size] as? Int)
      ?? 0
  }
}

// MARK: - Sheet

struct ChannelIndexSheet: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  let channelId: ChannelSnowflake
  let guildId: GuildSnowflake?
  let channelName: String

  enum Phase: Equatable {
    case idle
    case fetching(Int, of: Int)
    case embedding(Int, of: Int)
    case failed(String)
  }

  @State private var index: ChannelIndex?
  @State private var size = 0
  @State private var phase: Phase = .idle
  @State private var task: Task<Void, Never>?
  @State private var limit = 1_000
  @State private var query = ""
  @State private var results: [ChannelIndex.Entry] = []
  @State private var searching = false
  @State private var searched = false
  @State private var confirmingDelete = false
  @State private var vectorsAvailable: Bool?

  var body: some View {
    NavigationStack {
      Form {
        if let index {
          searchSection
          statusSection(index)
        } else {
          buildSection
        }
        progressSection
      }
      .formStyle(.grouped)
      .navigationTitle("Channel Index")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            task?.cancel()
            dismiss()
          }
        }
      }
      .task {
        reload()
        vectorsAvailable = await SentenceEmbedder.shared.isAvailable
      }
      .confirmationDialog(
        "Delete the index of \(channelName)?", isPresented: $confirmingDelete,
        titleVisibility: .visible
      ) {
        Button("Delete Index", role: .destructive) {
          ChannelIndexFiles.delete(channelId)
          results = []
          reload()
        }
      } message: {
        Text("It only removes the copy on this device. Messages on Discord stay.")
      }
    }
    #if os(macOS)
      .frame(minWidth: 440, idealWidth: 500, minHeight: 480, idealHeight: 560)
    #endif
  }

  // MARK: Sections

  private var buildSection: some View {
    Section {
      Picker("Messages", selection: $limit) {
        ForEach([500, 1_000, 2_000, 5_000], id: \.self) { count in
          Text("Last \(count)").tag(count)
        }
      }
      .disabled(isWorking)
      Button("Build Index") { start(update: false) }
        .disabled(isWorking)
    } header: {
      Text("Index \(channelName)")
    } footer: {
      Text(
        "Aicord reads the channel's last messages, 100 at a time, and keeps them on this device with a vector for their meaning, so you can search them by what they say and Ask About This Channel can reach further back. Nothing is sent anywhere. Messages hidden by your filters are left out."
      )
    }
  }

  private var searchSection: some View {
    Section {
      TextField("Search by meaning", text: $query, prompt: Text("who sold a jacket"))
        .autocorrectionDisabled()
        .onSubmit(search)
      Button("Search", action: search)
        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
      ForEach(results, id: \.id) { entry in
        Button {
          open(entry)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(entry.date, format: .dateTime.day().month().year().hour().minute())
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(entry.text)
              .lineLimit(4)
          }
        }
        .tint(.primary)
      }
    } header: {
      Text("Search")
    } footer: {
      if searching {
        Text("Searching…")
      } else if !results.isEmpty {
        Text("Best matches first. Tap one to open it in the chat.")
      } else if searched {
        Text("No indexed messages match.")
      }
    }
  }

  private func statusSection(_ index: ChannelIndex) -> some View {
    Section {
      LabeledContent("Messages", value: index.entries.count.formatted())
      if let first = index.entries.first?.date, let last = index.entries.last?.date {
        LabeledContent("From") {
          Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
        }
      }
      LabeledContent("Size on Device", value: size.formatted(.byteCount(style: .file)))
      LabeledContent("Updated") {
        Text(index.updated, format: .relative(presentation: .named))
      }
      Button("Add New Messages") { start(update: true) }
        .disabled(isWorking)
      Button("Delete Index", role: .destructive) { confirmingDelete = true }
        .disabled(isWorking)
    } header: {
      Text("Index")
    } footer: {
      if !index.hasVectors {
        Text("Built without the on-device meaning model, so search matches words only. Delete and build again once it's downloaded.")
      } else {
        Text("Kept on this device only. New messages are added when you tap Add New Messages.")
      }
    }
  }

  @ViewBuilder
  private var progressSection: some View {
    switch phase {
    case .idle:
      if vectorsAvailable == false, index == nil {
        Section {
          Label(
            "The on-device meaning model isn't available, so the index will match words only.",
            systemImage: "info.circle")
        }
      }
    case .fetching(let done, let total):
      Section {
        ProgressView(value: Double(done), total: Double(max(total, 1))) {
          Text("Reading messages… \(done) of \(total)")
        }
        Button("Cancel", role: .cancel) { task?.cancel() }
      }
    case .embedding(let done, let total):
      Section {
        ProgressView(value: Double(done), total: Double(max(total, 1))) {
          Text("Indexing… \(done) of \(total)")
        }
        Button("Cancel", role: .cancel) { task?.cancel() }
      }
    case .failed(let reason):
      Section {
        Label(reason, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      }
    }
  }

  private var isWorking: Bool {
    switch phase {
    case .fetching, .embedding: true
    default: false
    }
  }

  // MARK: Actions

  private func reload() {
    index = ChannelIndexFiles.load(channelId)
    size = ChannelIndexFiles.size(channelId)
  }

  private func search() {
    guard let index, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    searching = true
    let query = query
    Task {
      results = await index.matches(for: query, limit: 15)
      searching = false
      searched = true
    }
  }

  private func open(_ entry: ChannelIndex.Entry) {
    appState.open(guild: guildId, channel: channelId, message: MessageSnowflake(entry.id))
    dismiss()
  }

  private func start(update: Bool) {
    task?.cancel()
    task = Task {
      do {
        try await build(update: update)
        phase = .idle
        reload()
      } catch is CancellationError {
        phase = .idle
      } catch {
        phase = .failed(error.localizedDescription)
      }
    }
  }

  /// Reads up to `limit` messages (or those after the newest indexed one),
  /// newest first in pages of 100, then gives each a vector.
  private func build(update: Bool) async throws {
    let existing = update ? index : nil
    let newest = existing?.entries.last.map { MessageSnowflake($0.id) }
    let target = update ? 5_000 : limit
    var collected: [DiscordChannel.Message] = []
    var before: MessageSnowflake?
    phase = .fetching(0, of: update ? 0 : target)
    pages: while collected.count < target {
      try Task.checkCancellation()
      let res = try await gw.client.listMessages(
        channelId: channelId, before: before, limit: min(100, target - collected.count))
      try res.guardSuccess()
      let page = try res.decode()  // newest first
      for message in page {
        if let newest, message.id <= newest { break pages }
        collected.append(message)
      }
      phase = .fetching(collected.count, of: update ? collected.count : target)
      guard page.count == 100, let oldest = page.last else { break }
      before = oldest.id
      // a gentle pace keeps clear of Discord's rate limits
      try await Task.sleep(for: .milliseconds(350))
    }

    let transcript = IntelligenceSource.transcript(
      of: collected.reversed(), guildId: guildId, gw: gw, maxCharacters: 400)
    var entries: [ChannelIndex.Entry] = []
    for (offset, message) in transcript.messages.enumerated() {
      try Task.checkCancellation()
      phase = .embedding(offset, of: transcript.messages.count)
      // "[n] Name: text" without the number
      let line = transcript.lines[offset]
      let text = line.firstIndex(of: " ").map { String(line[line.index(after: $0)...]) } ?? line
      let vector = await SentenceEmbedder.shared.vector(for: text).map { floats in
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
      }
      entries.append(
        .init(id: message.id.rawValue, date: message.timestamp.date, text: text, vector: vector))
    }

    var result =
      existing
      ?? ChannelIndex(channelId: channelId.rawValue, created: .now, updated: .now, entries: [])
    let known = Set(result.entries.map(\.id))
    result.entries += entries.filter { !known.contains($0.id) }
    result.entries.sort { MessageSnowflake($0.id) < MessageSnowflake($1.id) }
    result.updated = .now
    try ChannelIndexFiles.save(result)
  }
}
