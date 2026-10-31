//
//  ReplyThread.swift
//  AicordKit
//
//  "Show Thread": the conversation a reply belongs to, as Discord's reply
//  links draw it. The app fetches the messages; this decides which belong
//  and which a model gets when they don't all fit.
//

import Foundation

public enum ReplyThread {
  /// A message and the one it replies to.
  public struct Node: Sendable, Equatable {
    public var id: String
    public var parentID: String?

    public init(id: String, parentID: String?) {
      self.id = id
      self.parentID = parentID
    }
  }

  /// Loaded messages that reply to a message of `thread`, directly or through
  /// each other. `loaded` is oldest first, so a reply comes after what it answers.
  public static func laterReplies(to thread: Set<String>, in loaded: [Node]) -> [String] {
    var members = thread
    var found: [String] = []
    for node in loaded where !members.contains(node.id) {
      guard let parent = node.parentID, members.contains(parent) else { continue }
      members.insert(node.id)
      found.append(node.id)
    }
    return found
  }

  /// Which messages of `thread` (oldest first) fit in `budget`: the target,
  /// then what it replies to from the nearest up, then the rest closest to
  /// the target first. Indices into `thread`, in thread order.
  public static func fit(thread: [Node], target: String, costs: [Int], budget: Int) -> [Int] {
    guard let targetIndex = thread.firstIndex(where: { $0.id == target }),
      costs.count == thread.count
    else { return [] }
    let index = Dictionary(thread.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })

    var order = [targetIndex]
    var parent = thread[targetIndex].parentID
    while let id = parent, let found = index[id], !order.contains(found) {
      order.append(found)
      parent = thread[found].parentID
    }
    let rest = thread.indices.filter { !order.contains($0) }
      .sorted { (abs($0 - targetIndex), $0) < (abs($1 - targetIndex), $1) }
    order += rest

    var used = 0
    var kept: [Int] = []
    for position in order {
      guard used + costs[position] <= budget || kept.isEmpty else { continue }
      used += costs[position]
      kept.append(position)
    }
    return kept.sorted()
  }
}
