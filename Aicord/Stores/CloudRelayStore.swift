//
//  CloudRelayStore.swift
//  Aicord
//
//  Notifications Through the Mac (Settings → Notifications): while Aicord on
//  iOS is closed, the Mac, which keeps the gateway open, saves a
//  RelayNotification record in the user's private iCloud database, and a
//  CKQuerySubscription on iOS makes Apple push it as a visible alert. No
//  server of our own and no push key. While iOS is in front it keeps an
//  "active until" marker fresh, and the Mac sends nothing.
//
//  Builds without the iCloud entitlement (the unsigned IPA for AltStore and
//  SideStore, CI) never touch CloudKit: creating the container there would
//  crash, so the entitlement is checked first and the option stays off.
//

import AicordKit
import CloudKit
import Foundation
import OSLog
import Security
import UserNotifications

#if os(iOS)
  import UIKit
#endif

@MainActor
@Observable
final class CloudRelayStore {
  static let shared = CloudRelayStore()

  enum Availability: Equatable {
    case off
    case checking
    case available
    /// This build has no iCloud entitlement (sideloaded, unsigned).
    case notEntitled
    /// No iCloud account, or iCloud Drive/CloudKit turned off for Aicord.
    case noAccount
    case unreachable(String)
  }

  private(set) var availability: Availability = .off

  var isEnabled: Bool { NotificationPrefs.bool(NotificationPrefs.macRelayKey) }

  /// The Mac sends: the option is on and iCloud answered.
  var isSending: Bool {
    #if os(macOS)
      isEnabled && availability == .available
    #else
      false
    #endif
  }

  @ObservationIgnored private var container: CKContainer?
  @ObservationIgnored private let logger = Logger(
    subsystem: "net.smigi.aicord", category: "CloudRelay")
  @ObservationIgnored private var accountObserver: NSObjectProtocol?
  @ObservationIgnored private var checkTask: Task<Void, Never>?

  private var database: CKDatabase? { container?.privateCloudDatabase }

  private init() {}

  /// At launch, when the option changes and when the iCloud account changes.
  func update() {
    checkTask?.cancel()
    guard isEnabled else {
      stop()
      return
    }
    guard Self.isEntitled else {
      availability = .notEntitled
      return
    }
    if container == nil {
      container = CKContainer(identifier: CloudRelay.containerID)
      accountObserver = NotificationCenter.default.addObserver(
        forName: .CKAccountChanged, object: nil, queue: .main
      ) { _ in
        Task { @MainActor in CloudRelayStore.shared.update() }
      }
    }
    availability = .checking
    checkTask = Task { await start() }
  }

  private func start() async {
    guard let container, let database else { return }
    do {
      let status = try await container.accountStatus()
      guard !Task.isCancelled else { return }
      guard status == .available else {
        logger.info("iCloud account status \(status.rawValue, privacy: .public)")
        availability = .noAccount
        return
      }
      #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        try await ensureSubscription(in: database)
        availability = .available
        if UIApplication.shared.applicationState == .active { appBecameActive() }
      #elseif os(macOS)
        // one round trip to know the container answers
        _ = try await fetchMarker(from: database)
        availability = .available
        startCleanup()
      #endif
    } catch {
      guard !Task.isCancelled else { return }
      logger.error("CloudKit unavailable: \(error, privacy: .public)")
      if (error as? CKError)?.code == .notAuthenticated {
        availability = .noAccount
      } else {
        availability = .unreachable(error.localizedDescription)
      }
    }
  }

  private func stop() {
    availability = .off
    #if os(iOS)
      heartbeat?.cancel()
      heartbeat = nil
      // no pushes once the option is off (the container exists only when entitled)
      if let database {
        Task {
          _ = try? await database.deleteSubscription(withID: CloudRelay.subscriptionID)
        }
      }
    #elseif os(macOS)
      coalescer.reset()
      flushTask?.cancel()
      flushTask = nil
      cleanupTask?.cancel()
      cleanupTask = nil
    #endif
  }

  private func handle(_ error: Error) {
    guard let error = error as? CKError else {
      logger.error("CloudKit: \(error, privacy: .public)")
      return
    }
    logger.error("CloudKit: \(error, privacy: .public)")
    switch error.code {
    case .notAuthenticated:
      availability = .noAccount
    case .requestRateLimited, .zoneBusy, .serviceUnavailable:
      pausedUntil = .now.addingTimeInterval(error.retryAfterSeconds ?? 60)
    default:
      break
    }
  }

  @ObservationIgnored private var pausedUntil: Date = .distantPast

  /// A save that didn't throw can still fail record by record (a schema not
  /// deployed to Production, say): show it instead of a false "Ready".
  private func reportFailures(_ results: [CKRecord.ID: Result<CKRecord, Error>]) {
    for case .failure(let error) in results.values {
      handle(error)
      // only what won't pass by itself; network trouble and limits do
      let lasting: [CKError.Code] = [
        .unknownItem, .invalidArguments, .permissionFailure, .serverRejectedRequest,
        .badContainer, .missingEntitlement, .quotaExceeded, .incompatibleVersion,
      ]
      if let code = (error as? CKError)?.code, lasting.contains(code) {
        availability = .unreachable(error.localizedDescription)
      }
      return
    }
  }

  // MARK: - iOS: subscription, marker, delivered notifications

  #if os(iOS)
    @ObservationIgnored private var heartbeat: Task<Void, Never>?

    /// Once per container: fetched by its ID first, so it's never made twice.
    private func ensureSubscription(in database: CKDatabase) async throws {
      do {
        _ = try await database.subscription(for: CloudRelay.subscriptionID)
        return
      } catch let error as CKError where error.code == .unknownItem {
        // not made yet
      }
      do {
        _ = try await database.save(Self.makeSubscription())
      } catch let error as CKError where error.code != .notAuthenticated && error.code != .networkUnavailable && error.code != .networkFailure {
        // In the Development environment the record type exists only after a
        // first record: make one and take it away, then try again. In
        // Production the schema must be deployed (see the notes).
        logger.info("Subscription refused (\(error.code.rawValue)), creating the record type")
        let seed = RelayNotification(
          title: "", body: "", channelId: "0", guildId: nil, messageId: "schema",
          createdAt: .distantPast)
        _ = try await database.modifyRecords(
          saving: [seed.record()], deleting: [], savePolicy: .allKeys)
        _ = try? await database.modifyRecords(saving: [], deleting: [seed.record().recordID])
        _ = try await database.save(Self.makeSubscription())
      }
    }

    private static func makeSubscription() -> CKQuerySubscription {
      typealias F = CloudRelay.Field
      let subscription = CKQuerySubscription(
        recordType: CloudRelay.notificationType, predicate: NSPredicate(value: true),
        subscriptionID: CloudRelay.subscriptionID, options: [.firesOnRecordCreation])
      let info = CKSubscription.NotificationInfo()
      info.titleLocalizationKey = CloudRelay.titleKey
      info.titleLocalizationArgs = [F.title]
      info.subtitleLocalizationKey = CloudRelay.subtitleKey
      info.subtitleLocalizationArgs = [F.subtitle]
      info.alertLocalizationKey = CloudRelay.bodyKey
      info.alertLocalizationArgs = [F.body]
      info.soundName = "default"
      info.shouldBadge = true
      info.category = NotificationStore.messageCategory
      info.desiredKeys = RelayTarget.desiredKeys
      // no collapseIDKey: it's one literal apns-collapse-id for every push,
      // so each would replace the one before, whatever the channel
      subscription.notificationInfo = info
      return subscription
    }

    func appBecameActive() {
      guard availability == .available, heartbeat == nil else { return }
      heartbeat = Task { [weak self] in
        while !Task.isCancelled {
          await self?.writeMarker(.active())
          try? await Task.sleep(for: .seconds(ActivityMarker.refreshInterval))
        }
      }
    }

    /// The Mac takes over once NotificationStore's background time is over.
    func appEnteredBackground() {
      heartbeat?.cancel()
      heartbeat = nil
      guard availability == .available else { return }
      Task { await writeMarker(.leaving()) }
    }

    private func writeMarker(_ marker: ActivityMarker) async {
      guard let database else { return }
      do {
        let (saved, _) = try await database.modifyRecords(
          saving: [marker.record()], deleting: [], savePolicy: .allKeys)
        reportFailures(saved)
      } catch {
        handle(error)
      }
    }
  #endif

  /// Relay pushes still in Notification Center whose message has been read
  /// (here or on another device): at launch, once read states are known.
  static func removeReadDelivered(isRead: @escaping @MainActor (RelayTarget) -> Bool) {
    let center = UNUserNotificationCenter.current()
    Task { @MainActor in
      // READY's read states land in their own store a moment later
      try? await Task.sleep(for: .seconds(2))
      let ids = await center.deliveredNotifications().compactMap { notification -> String? in
        guard let target = RelayTarget(userInfo: notification.request.content.userInfo),
          isRead(target)
        else { return nil }
        return notification.request.identifier
      }
      if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
  }

  // MARK: - macOS: sending

  #if os(macOS)
    @ObservationIgnored private var coalescer = RelayCoalescer()
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var marker: (ActivityMarker?, fetched: Date)?

    /// A message the Mac notifies about (NotificationStore's rules already
    /// decided, with its preview setting applied to the content).
    func relay(_ content: NotificationStore.Content, messageId: String) {
      guard isSending, let channelId = content.userInfo["channel"] else { return }
      let notification = RelayNotification(
        title: content.title, subtitle: content.subtitle, body: content.body,
        channelId: channelId, guildId: content.userInfo["guild"], messageId: messageId)
      if let now = coalescer.offer(notification) {
        Task { await send([now]) }
      }
      scheduleFlush()
    }

    private func scheduleFlush() {
      guard flushTask == nil, let deadline = coalescer.nextDeadline else { return }
      flushTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(max(0.1, deadline.timeIntervalSinceNow)))
        guard let self, !Task.isCancelled else { return }
        self.flushTask = nil
        let due = self.coalescer.flush()
        if !due.isEmpty { await self.send(due) }
        self.scheduleFlush()
      }
    }

    private func send(_ notifications: [RelayNotification]) async {
      guard isSending, let database, pausedUntil < .now else { return }
      if await iOSIsActive(database) {
        // iOS notifies by itself; what waited in bursts is stale too
        coalescer.reset()
        return
      }
      let records = notifications.map { Self.summarized($0).trimmed.record() }
      do {
        let (saved, _) = try await database.modifyRecords(
          saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
        reportFailures(saved)
      } catch {
        handle(error)
      }
    }

    /// A burst's notification says how many messages it stands for.
    static func summarized(_ notification: RelayNotification) -> RelayNotification {
      guard notification.count > 1 else { return notification }
      var out = notification
      let count = String(localized: "\(notification.count) new messages")
      out.body =
        NotificationPrefs.preview == .full ? "\(count)\n\(notification.body)" : count
      return out
    }

    /// The marker, fetched at most every 15 seconds.
    private func iOSIsActive(_ database: CKDatabase) async -> Bool {
      if let marker, marker.fetched > .now.addingTimeInterval(-15) {
        return marker.0?.isActive() ?? false
      }
      do {
        let fetched = try await fetchMarker(from: database)
        marker = (fetched, .now)
        return fetched?.isActive() ?? false
      } catch {
        handle(error)
        // unknown: send rather than lose the notification
        return false
      }
    }

    private func fetchMarker(from database: CKDatabase) async throws -> ActivityMarker? {
      let id = CKRecord.ID(recordName: CloudRelay.markerRecordName)
      do {
        return ActivityMarker(record: try await database.record(for: id))
      } catch let error as CKError where error.code == .unknownItem {
        return nil
      }
    }

    /// Records older than an hour go, every quarter of an hour.
    private func startCleanup() {
      cleanupTask?.cancel()
      cleanupTask = Task { [weak self] in
        while !Task.isCancelled {
          await self?.deleteOldRecords()
          try? await Task.sleep(for: .seconds(15 * 60))
        }
      }
    }

    private func deleteOldRecords() async {
      guard let database else { return }
      let cutoff = Date.now.addingTimeInterval(-CloudRelay.maxAge)
      let query = CKQuery(
        recordType: CloudRelay.notificationType,
        predicate: NSPredicate(format: "%K < %@", CloudRelay.Field.createdAt, cutoff as NSDate))
      do {
        let (results, _) = try await database.records(
          matching: query, desiredKeys: [], resultsLimit: 200)
        let ids = results.map(\.0)
        guard !ids.isEmpty else { return }
        _ = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
        logger.info("Deleted \(ids.count) old relay records")
      } catch let error as CKError where error.code == .unknownItem {
        // no record type yet: nothing was ever sent
      } catch {
        handle(error)
      }
    }
  #endif

  // MARK: - Entitlement

  /// Whether this build may use the container. Without the entitlement
  /// `CKContainer(identifier:)` raises an exception Swift can't catch.
  static let isEntitled: Bool = {
    let entitlements = Entitlements.current()
    let services = entitlements["com.apple.developer.icloud-services"] as? [String] ?? []
    let containers =
      entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
    return services.contains("CloudKit") && containers.contains(CloudRelay.containerID)
  }()
}

/// The running app's own entitlements.
enum Entitlements {
  static func current() -> [String: Any] {
    #if os(macOS)
      guard let task = SecTaskCreateFromSelf(nil) else { return [:] }
      var result: [String: Any] = [:]
      for key in [
        "com.apple.developer.icloud-services", "com.apple.developer.icloud-container-identifiers",
      ] {
        if let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) {
          result[key] = value
        }
      }
      return result
    #else
      // no SecTask on iOS: read the entitlements blob from the executable's
      // code signature
      guard let url = Bundle.main.executableURL,
        let data = try? Data(contentsOf: url, options: .alwaysMapped)
      else { return [:] }
      return fromMachO(data) ?? [:]
    #endif
  }

  /// The entitlements plist in a Mach-O's code signature (thin 64-bit, or
  /// the arm64 slice of a universal binary).
  static func fromMachO(_ data: Data) -> [String: Any]? {
    func u32(_ offset: Int, bigEndian: Bool) -> UInt32? {
      guard offset >= 0, offset + 4 <= data.count else { return nil }
      let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
      return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
    }

    var base = 0
    if u32(0, bigEndian: true) == 0xCAFE_BABE {
      // universal: find the arm64 slice
      guard let count = u32(4, bigEndian: true) else { return nil }
      var found: Int?
      for index in 0..<Int(count) {
        let entry = 8 + index * 20
        if u32(entry, bigEndian: true) == 0x0100_000C, let offset = u32(entry + 8, bigEndian: true) {
          found = Int(offset)
        }
      }
      guard let found else { return nil }
      base = found
    }
    guard u32(base, bigEndian: false) == 0xFEED_FACF,
      let commands = u32(base + 16, bigEndian: false)
    else { return nil }

    var cursor = base + 32
    var signature: (offset: Int, size: Int)?
    for _ in 0..<Int(commands) {
      guard let command = u32(cursor, bigEndian: false),
        let size = u32(cursor + 4, bigEndian: false), size > 0
      else { return nil }
      if command == 0x1D,  // LC_CODE_SIGNATURE
        let offset = u32(cursor + 8, bigEndian: false),
        let length = u32(cursor + 12, bigEndian: false)
      {
        signature = (base + Int(offset), Int(length))
        break
      }
      cursor += Int(size)
    }
    guard let signature, u32(signature.offset, bigEndian: true) == 0xFADE_0CC0,
      let count = u32(signature.offset + 8, bigEndian: true)
    else { return nil }

    for index in 0..<Int(count) {
      let entry = signature.offset + 12 + index * 8
      guard u32(entry, bigEndian: true) == 5,  // CSSLOT_ENTITLEMENTS
        let offset = u32(entry + 4, bigEndian: true)
      else { continue }
      let blob = signature.offset + Int(offset)
      guard u32(blob, bigEndian: true) == 0xFADE_7171,
        let length = u32(blob + 4, bigEndian: true), length > 8,
        blob + Int(length) <= data.count
      else { return nil }
      let plist = data.subdata(in: (blob + 8)..<(blob + Int(length)))
      return try? PropertyListSerialization.propertyList(from: plist, format: nil)
        as? [String: Any]
    }
    return nil
  }
}
