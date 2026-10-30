//
//  LocalConsoleManager.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import Synchronization
import os

final class StdOutInterceptor: Sendable {
  static let shared = StdOutInterceptor()

  static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.smigi.aicord",
    category: "Console"
  )

  private let state = Mutex<InterceptorState>(InterceptorState())

  private struct InterceptorState {
    var logBuffer: [LogItem] = []
    var isActive: Bool = false
  }

  private init() {}

  func items(from str: String, source: LogItem.LogType) -> [LogItem] {
    [.init(str: str, type: source)]
  }

  func _addLog(_ item: String, source: LogItem.LogType) {
    let new = self.items(from: item, source: source)
    state.withLock { state in
      state.logBuffer.append(contentsOf: new)
    }
    switch source {
    case .out:
      Self.logger.info("\(item, privacy: .public)")
    case .err:
      Self.logger.error("\(item, privacy: .public)")
    case .flt:
      Self.logger.fault("\(item, privacy: .public)")
    }
    Task { @MainActor in
      NotificationCenter.default.post(name: .newLogAdded, object: new)
    }
  }

  /// No-op by default in production to avoid redirecting global stdout/stderr pipes.
  func startIntercepting() {
    state.withLock { $0.isActive = true }
  }

  func stopIntercepting() {
    state.withLock { $0.isActive = false }
  }

  struct LogItem: Identifiable, Equatable, Sendable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    let id: UUID = UUID()
    let str: String
    var type: LogType

    init(str: String, type: LogType) {
      let (metadata, cleanedLog) = LogItem.extractAndCleanMetadata(from: str)
      self.type = LogItem.determineLogType(from: metadata, defaultType: type)
      self.str = cleanedLog
    }

    enum LogType: Sendable {
      case out
      case err
      case flt
    }

    static func extractAndCleanMetadata(from log: String) -> (
      metadata: String?, cleanedLog: String
    ) {
      let osLogRegex = #"OSLOG-[A-F0-9-]+.+?\{.+?\}"#
      if let range = log.range(of: osLogRegex, options: .regularExpression) {
        let metadata = String(log[range])
        let cleanedLog = log.replacingOccurrences(of: metadata, with: "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        return (metadata: metadata, cleanedLog: cleanedLog)
      }
      return (metadata: nil, cleanedLog: log)
    }

    static func determineLogType(from metadata: String?, defaultType: LogType)
      -> LogType
    {
      guard let metadata = metadata else { return defaultType }
      if metadata.localizedCaseInsensitiveContains("fault") {
        return .flt
      }
      if metadata.localizedCaseInsensitiveContains("error") {
        return .err
      }
      return defaultType
    }
  }

  func getLogs() -> [LogItem] {
    state.withLock { state in
      state.logBuffer = state.logBuffer.compactMap {
        $0.str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : $0
      }
      return state.logBuffer
    }
  }
}

extension Notification.Name {
  static let newLogAdded = Notification.Name("newLogAdded")
}
