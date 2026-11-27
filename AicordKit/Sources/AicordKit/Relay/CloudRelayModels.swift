//
//  CloudRelayModels.swift
//  AicordKit
//
//  The Mac as a notification relay for a closed Aicord on iOS: the Mac writes
//  a RelayNotification record into the user's private iCloud database, and a
//  CKQuerySubscription on iOS makes Apple push it as a visible alert.
//  These are the pure parts (records, bursts, the activity marker), kept here
//  so they can be tested without the app.
//

import CloudKit
import Foundation

public enum CloudRelay {
  /// The container both platforms use. It must belong to the team that signs
  /// the app on iOS and on macOS.
  public static let containerID = "iCloud.net.smigi.aicord"
  public static let notificationType = "RelayNotification"
  public static let markerType = "ActivityMarker"
  /// One marker for every iOS device of the account.
  public static let markerRecordName = "ios-active"
  /// Raise the number when the notification's look changes: the old
  /// subscription is then replaced.
  public static let subscriptionID = "relay-notifications-v1"
  /// Records older than this are deleted by the Mac.
  public static let maxAge: TimeInterval = 3_600

  /// Localization keys the push alert is formatted with: each is "%@" in the
  /// string catalog, filled with the record's field.
  public static let titleKey = "RELAY_TITLE"
  public static let subtitleKey = "RELAY_SUBTITLE"
  public static let bodyKey = "RELAY_BODY"

  /// The record fields.
  public enum Field {
    public static let title = "title"
    public static let subtitle = "subtitle"
    public static let body = "body"
    public static let channelId = "channelId"
    public static let guildId = "guildId"
    public static let messageId = "messageId"
    public static let createdAt = "createdAt"
    public static let count = "count"
    public static let activeUntil = "activeUntil"
  }
}

/// One notification the Mac hands to iOS.
public struct RelayNotification: Equatable, Sendable {
  public var title: String
  public var subtitle: String
  public var body: String
  public var channelId: String
  public var guildId: String?
  public var messageId: String
  public var createdAt: Date
  /// How many messages this one stands for (a burst sends one record).
  public var count: Int

  public init(
    title: String, subtitle: String = "", body: String, channelId: String, guildId: String?,
    messageId: String, createdAt: Date = .now, count: Int = 1
  ) {
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.channelId = channelId
    self.guildId = guildId
    self.messageId = messageId
    self.createdAt = createdAt
    self.count = count
  }

  /// One record per message, so saving it twice can't make two pushes. It
  /// also carries where the message is: CloudKit drops `desiredKeys` from a
  /// push that would be too big, but keeps the record ID.
  public var recordName: String { "relay-\(guildId ?? "0")-\(channelId)-\(messageId)" }

  /// What fits in a push (APNs allows 4 KB for everything).
  public static let maxTitle = 100
  public static let maxSubtitle = 120
  public static let maxBody = 400

  /// Trimmed to what a push can carry.
  public var trimmed: RelayNotification {
    func cut(_ text: String, _ limit: Int) -> String {
      text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
    var out = self
    out.title = cut(title, Self.maxTitle)
    out.subtitle = cut(subtitle, Self.maxSubtitle)
    out.body = cut(body, Self.maxBody)
    return out
  }

  public func record(zoneID: CKRecordZone.ID = .default) -> CKRecord {
    let record = CKRecord(
      recordType: CloudRelay.notificationType,
      recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
    typealias F = CloudRelay.Field
    // the alert can only show plain fields: encryptedValues never reach APNs
    record[F.title] = title as NSString
    record[F.subtitle] = subtitle as NSString
    record[F.body] = body as NSString
    record[F.channelId] = channelId as NSString
    record[F.guildId] = (guildId ?? "") as NSString
    record[F.messageId] = messageId as NSString
    record[F.createdAt] = createdAt as NSDate
    record[F.count] = NSNumber(value: count)
    return record
  }

  public init?(record: CKRecord) {
    guard record.recordType == CloudRelay.notificationType else { return nil }
    typealias F = CloudRelay.Field
    guard let channelId = record[F.channelId] as? String, !channelId.isEmpty,
      let messageId = record[F.messageId] as? String, !messageId.isEmpty
    else { return nil }
    let guildId = record[F.guildId] as? String
    self.init(
      title: record[F.title] as? String ?? "",
      subtitle: record[F.subtitle] as? String ?? "",
      body: record[F.body] as? String ?? "",
      channelId: channelId,
      guildId: guildId?.isEmpty == false ? guildId : nil,
      messageId: messageId,
      createdAt: record[F.createdAt] as? Date ?? .distantPast,
      count: (record[F.count] as? NSNumber)?.intValue ?? 1)
  }
}

/// Where a pushed notification points: the fields the subscription asks
/// CloudKit to put in the payload (`desiredKeys`).
public struct RelayTarget: Equatable, Sendable {
  public var channelId: String
  public var guildId: String?
  public var messageId: String?

  public init(channelId: String, guildId: String?, messageId: String?) {
    self.channelId = channelId
    self.guildId = guildId
    self.messageId = messageId
  }

  public static let desiredKeys = [
    CloudRelay.Field.channelId, CloudRelay.Field.guildId, CloudRelay.Field.messageId,
  ]

  /// From a delivered notification's userInfo. Nil when it isn't a relay push.
  public init?(userInfo: [AnyHashable: Any]) {
    guard userInfo["ck"] != nil,
      let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        as? CKQueryNotification,
      notification.subscriptionID?.hasPrefix("relay-notifications") == true
    else { return nil }
    if let target = RelayTarget(fields: notification.recordFields ?? [:]) {
      self = target
    } else if let name = notification.recordID?.recordName,
      let target = RelayTarget(recordName: name)
    {
      self = target
    } else {
      return nil
    }
  }

  /// From `relay-<guild or 0>-<channel>-<message>`.
  public init?(recordName: String) {
    let parts = recordName.split(separator: "-").map(String.init)
    guard parts.count == 4, parts[0] == "relay", !parts[2].isEmpty, !parts[3].isEmpty else {
      return nil
    }
    self.init(
      channelId: parts[2], guildId: parts[1] == "0" ? nil : parts[1], messageId: parts[3])
  }

  public init?(fields: [String: Any]) {
    typealias F = CloudRelay.Field
    guard let channelId = fields[F.channelId] as? String, !channelId.isEmpty else { return nil }
    let guildId = fields[F.guildId] as? String
    let messageId = fields[F.messageId] as? String
    self.init(
      channelId: channelId, guildId: guildId?.isEmpty == false ? guildId : nil,
      messageId: messageId?.isEmpty == false ? messageId : nil)
  }

  /// The keys the app's notification actions read (as in local notifications).
  public var actionInfo: [String: String] {
    var info = ["channel": channelId]
    info["guild"] = guildId
    info["message"] = messageId
    return info
  }
}

/// "Aicord on iOS is in front until…": while it's valid the Mac sends nothing,
/// because iOS notifies by itself.
public struct ActivityMarker: Equatable, Sendable {
  public var activeUntil: Date

  /// iOS writes the marker this often while it's active...
  public static let refreshInterval: TimeInterval = 60
  /// ...valid for this long, so one late write doesn't open a gap.
  public static let lifetime: TimeInterval = 150
  /// After leaving the app iOS keeps the connection about half a minute
  /// (NotificationStore's background task), and notifies by itself meanwhile.
  public static let backgroundGrace: TimeInterval = 30

  public init(activeUntil: Date) {
    self.activeUntil = activeUntil
  }

  public static func active(now: Date = .now) -> ActivityMarker {
    ActivityMarker(activeUntil: now.addingTimeInterval(lifetime))
  }

  public static func leaving(now: Date = .now) -> ActivityMarker {
    ActivityMarker(activeUntil: now.addingTimeInterval(backgroundGrace))
  }

  public func isActive(at now: Date = .now) -> Bool { activeUntil > now }

  public func record(zoneID: CKRecordZone.ID = .default) -> CKRecord {
    let record = CKRecord(
      recordType: CloudRelay.markerType,
      recordID: CKRecord.ID(recordName: CloudRelay.markerRecordName, zoneID: zoneID))
    record[CloudRelay.Field.activeUntil] = activeUntil as NSDate
    return record
  }

  public init?(record: CKRecord) {
    guard record.recordType == CloudRelay.markerType,
      let date = record[CloudRelay.Field.activeUntil] as? Date
    else { return nil }
    self.init(activeUntil: date)
  }
}

/// Bursts in one channel become one push: the first message goes at once,
/// the ones after it within `window` wait and go as one ("3 new messages",
/// counting what waited). An hourly cap keeps a busy account under
/// CloudKit's and APNs' limits.
public struct RelayCoalescer: Sendable {
  public var window: TimeInterval
  public var maxPerHour: Int

  private struct Burst {
    var deadline: Date
    /// Messages waiting since the last push for the channel.
    var held: Int
    var latest: RelayNotification?
  }

  private var bursts: [String: Burst] = [:]
  private var sent: [Date] = []

  public init(window: TimeInterval = 10, maxPerHour: Int = 60) {
    self.window = window
    self.maxPerHour = maxPerHour
  }

  /// The notification to send now, or nil when it waits for its burst.
  public mutating func offer(_ notification: RelayNotification, now: Date = .now)
    -> RelayNotification?
  {
    if var burst = bursts[notification.channelId], burst.deadline > now || burst.latest != nil {
      burst.held += 1
      burst.latest = notification
      bursts[notification.channelId] = burst
      return nil
    }
    bursts[notification.channelId] = Burst(
      deadline: now.addingTimeInterval(window), held: 0, latest: nil)
    guard takeSlot(now: now) else {
      // over the cap: it waits like the rest of a burst
      bursts[notification.channelId]?.held = 1
      bursts[notification.channelId]?.latest = notification
      return nil
    }
    return notification
  }

  /// Bursts whose window ended: one notification each for what waited, with
  /// `count` set to how many messages waited. A burst that keeps going gets
  /// another window.
  public mutating func flush(now: Date = .now) -> [RelayNotification] {
    var out: [RelayNotification] = []
    for (channel, burst) in bursts where burst.deadline <= now {
      guard var latest = burst.latest else {
        bursts.removeValue(forKey: channel)
        continue
      }
      guard takeSlot(now: now) else {
        bursts[channel]?.deadline = now.addingTimeInterval(window)
        continue
      }
      latest.count = burst.held
      out.append(latest)
      bursts[channel] = Burst(deadline: now.addingTimeInterval(window), held: 0, latest: nil)
    }
    return out.sorted { $0.createdAt < $1.createdAt }
  }

  /// When `flush` has something to do next.
  public var nextDeadline: Date? { bursts.values.map(\.deadline).min() }

  public var isEmpty: Bool { bursts.isEmpty }

  /// Forgets what waited (the relay was turned off, or iOS became active).
  public mutating func reset() { bursts.removeAll() }

  private mutating func takeSlot(now: Date) -> Bool {
    sent.removeAll { $0 <= now.addingTimeInterval(-3_600) }
    guard sent.count < maxPerHour else { return false }
    sent.append(now)
    return true
  }
}
