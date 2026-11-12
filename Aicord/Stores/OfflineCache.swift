//
//  OfflineCache.swift
//  Aicord
//
//  The last messages of recently opened channels, kept on disk to read offline.
//

import AicordKit
import Foundation
import Network

/// A message as saved for offline reading: the snapshot plus its attachments.
struct OfflineMessage: Codable, Hashable, Identifiable {
  struct Attachment: Codable, Hashable {
    var filename: String
    var url: String
  }

  var message: MessageSnapshot
  var attachments: [Attachment]
  var id: String { message.id }
}

/// One channel's saved messages, oldest first.
struct OfflineChannel: Codable, Hashable, Identifiable {
  var id: String
  var guildID: String?
  var place: String
  var savedAt: Date
  var messages: [OfflineMessage]
}

/// Saves the newest messages of channels you open, in Application Support (left
/// out of backups). Only what you opened yourself: nothing is fetched for it.
@MainActor @Observable
final class OfflineCache {
  static let shared = OfflineCache()

  static let enabledKey = "Aicord.Offline.Enabled"
  /// Messages kept per channel.
  static let messagesPerChannel = 100
  /// Channels kept; the least recently saved fall off.
  static let channelLimit = 40

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  /// Saved channels, newest first (summaries without the messages).
  private(set) var channels: [OfflineChannel] = []

  private let directory: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    var url = base.appendingPathComponent("Offline", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
    return url
  }()

  private init() {
    reloadIndex()
  }

  private func file(for channelID: String) -> URL {
    directory.appendingPathComponent("\(channelID).json")
  }

  private func reloadIndex() {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    channels =
      files
      .filter { $0.pathExtension == "json" }
      .compactMap { url in
        guard let data = try? Data(contentsOf: url),
          var channel = try? JSONDecoder().decode(OfflineChannel.self, from: data)
        else { return nil }
        channel.messages = []
        return channel
      }
      .sorted { $0.savedAt > $1.savedAt }
  }

  func load(_ channelID: String) -> OfflineChannel? {
    guard let data = try? Data(contentsOf: file(for: channelID)) else { return nil }
    return try? JSONDecoder().decode(OfflineChannel.self, from: data)
  }

  /// Saves what's loaded of the channel right now.
  func save(_ store: ChannelStore, gateway gw: GatewayStore) {
    guard Self.isEnabled, !store.messages.isEmpty else { return }
    let guildId = store.guildStore?.guildId
    let newest = store.messages.values.suffix(Self.messagesPerChannel)
    let messages = newest.map { message in
      var snapshot = gw.snapshot(of: message, guildId: guildId)
      snapshot.text = gw.notifications.plainText(of: message, guildId: guildId)
      return OfflineMessage(
        message: snapshot,
        attachments: message.attachments.map { .init(filename: $0.filename, url: $0.url) })
    }
    let channel = OfflineChannel(
      id: store.channelId.rawValue,
      guildID: guildId?.rawValue,
      place: gw.placeName(channelId: store.channelId, guildId: guildId),
      savedAt: .now,
      messages: Array(messages)
    )
    var summary = channel
    summary.messages = []
    channels.removeAll { $0.id == channel.id }
    channels.insert(summary, at: 0)
    var evicted: [URL] = []
    while channels.count > Self.channelLimit, let oldest = channels.popLast() {
      evicted.append(file(for: oldest.id))
    }
    // encoding and writing off the main thread: it ran a few seconds after a
    // channel opened and after each new message, and stalled scrolling. One
    // queue, so saves of the same channel land in order.
    let url = file(for: channel.id)
    Self.diskQueue.async { [evicted] in
      if let data = try? JSONEncoder().encode(channel) {
        #if os(iOS)
          try? data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
          try? data.write(to: url, options: .atomic)
        #endif
      }
      for file in evicted {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  private static let diskQueue = DispatchQueue(label: "Aicord.OfflineCache.disk", qos: .utility)

  func remove(_ channelID: String) {
    try? FileManager.default.removeItem(at: file(for: channelID))
    channels.removeAll { $0.id == channelID }
  }

  func removeAll() {
    for channel in channels {
      try? FileManager.default.removeItem(at: file(for: channel.id))
    }
    channels = []
  }

  var sizeOnDisk: Int {
    channels.reduce(0) { total, channel in
      total
        + ((try? file(for: channel.id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }
}

/// Whether the device has a usable network path, for the "Offline" state.
@MainActor @Observable
final class NetworkMonitor {
  static let shared = NetworkMonitor()

  private(set) var isOnline = true
  private let monitor = NWPathMonitor()

  private init() {
    monitor.pathUpdateHandler = { path in
      let online = path.status == .satisfied
      Task { @MainActor in NetworkMonitor.shared.isOnline = online }
    }
    monitor.start(queue: DispatchQueue(label: "Aicord.NetworkMonitor"))
  }
}
