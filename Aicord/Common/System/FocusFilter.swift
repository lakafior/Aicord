//
//  FocusFilter.swift
//  Aicord
//
//  A Focus filter (Settings → Focus → a Focus → Add Filter → Aicord): while
//  the Focus is on, your Discord status changes and chosen servers only
//  notify you when you're mentioned. When it ends, the status you had comes
//  back. The status is changed by the open app with its own connection; if
//  Aicord isn't connected, it's done the next time it connects.
//

import AicordKit
import AppIntents
import Foundation

enum FocusStatus: String, AppEnum {
  case online, idle, doNotDisturb, invisible

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Status")
  static let caseDisplayRepresentations: [FocusStatus: DisplayRepresentation] = [
    .online: "Online",
    .idle: "Idle",
    .doNotDisturb: "Do Not Disturb",
    .invisible: "Invisible",
  ]

  var gatewayStatus: Gateway.Status {
    switch self {
    case .online: .online
    case .idle: .afk
    case .doNotDisturb: .doNotDisturb
    case .invisible: .invisible
    }
  }
}

struct AicordFocusFilter: SetFocusFilterIntent {
  static let title: LocalizedStringResource = "Set Discord Status and Mute Servers"
  static let description: IntentDescription? = IntentDescription(
    "While this Focus is on, Aicord changes your Discord status and the servers you choose only notify you when you're mentioned. Your status comes back when the Focus ends."
  )

  /// Left empty, the status stays as it is.
  @Parameter(title: "Status")
  var status: FocusStatus?

  @Parameter(title: "Mute Servers", default: [])
  var mutedServers: [ServerEntity]

  var displayRepresentation: DisplayRepresentation {
    var parts: [String] = []
    if let status {
      parts.append(String(localized: FocusStatus.caseDisplayRepresentations[status]?.title ?? ""))
    }
    if !mutedServers.isEmpty {
      parts.append(String(localized: "\(mutedServers.count) servers muted"))
    }
    return DisplayRepresentation(
      title: "Aicord",
      subtitle: parts.isEmpty ? "No changes" : "\(parts.joined(separator: " · "))")
  }

  @MainActor
  func perform() async throws -> some IntentResult {
    FocusSync.update(status: status, mutedServerIDs: Set(mutedServers.map(\.id)))
    return .result()
  }
}

/// What the active Focus asks for, kept so the app can act on it when it
/// connects, and the status to go back to.
@MainActor
enum FocusSync {
  private enum Key {
    static let status = "Aicord.Focus.Status"
    static let previousStatus = "Aicord.Focus.PreviousStatus"
    static let mutedServers = "Aicord.Focus.MutedServers"
    static let pending = "Aicord.Focus.Pending"
  }

  private static var defaults: UserDefaults { .standard }

  /// Servers the Focus mutes; they still notify about direct mentions.
  static var mutedServerIDs: Set<String> {
    Set(defaults.stringArray(forKey: Key.mutedServers) ?? [])
  }

  static func update(status: FocusStatus?, mutedServerIDs: Set<String>) {
    defaults.set(mutedServerIDs.sorted(), forKey: Key.mutedServers)
    defaults.set(status?.rawValue, forKey: Key.status)
    defaults.set(true, forKey: Key.pending)
    applyIfConnected(GatewayStore.shared)
  }

  /// Sets or restores the status once there's a connection to do it with.
  static func applyIfConnected(_ gateway: GatewayStore) {
    guard defaults.bool(forKey: Key.pending), gateway.state == .connected else { return }
    defaults.set(false, forKey: Key.pending)
    let presence = gateway.presence
    let wanted = defaults.string(forKey: Key.status).flatMap { FocusStatus(rawValue: $0) }
    let previous = defaults.string(forKey: Key.previousStatus).flatMap(FocusStatus.init(statusValue:))

    let target: Gateway.Status
    if let wanted {
      // remember what to go back to, once, while the Focus is on
      if previous == nil {
        defaults.set(FocusStatus.value(of: presence.currentClientStatus), forKey: Key.previousStatus)
      }
      target = wanted.gatewayStatus
    } else if let previous {
      defaults.removeObject(forKey: Key.previousStatus)
      target = previous.gatewayStatus
    } else {
      return
    }
    guard target != presence.currentClientStatus else { return }
    Task {
      do {
        try await presence.changeStatus(target)
      } catch {
        // try again on the next connection
        defaults.set(true, forKey: Key.pending)
      }
    }
  }
}

extension FocusStatus {
  /// From a status kept as Discord's own word ("dnd", "idle"…).
  init?(statusValue: String) {
    switch statusValue {
    case "online": self = .online
    case "idle": self = .idle
    case "dnd": self = .doNotDisturb
    case "invisible": self = .invisible
    default: return nil
    }
  }

  static func value(of status: Gateway.Status) -> String {
    switch status {
    case .online: "online"
    case .afk: "idle"
    case .doNotDisturb: "dnd"
    case .invisible, .offline: "invisible"
    case .__undocumented(let value): value
    }
  }
}
