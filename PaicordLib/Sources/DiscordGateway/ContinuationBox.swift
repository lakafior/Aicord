//
//  ContinuationBox.swift
//  PaicordLib
//
//  Created by Lakhan Lothiyi on 13/07/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import Foundation
import Synchronization

final class ContinuationBox<Value: Sendable>: Sendable {
  private let continuations = Mutex<[AsyncStream<Value>.Continuation]>([])

  func append(_ continuation: AsyncStream<Value>.Continuation) {
    continuations.withLock { $0.append(continuation) }
  }

  func yieldToAll(_ value: Value) {
    let current = continuations.withLock { $0 }
    for continuation in current {
      continuation.yield(value)
    }
  }
}
