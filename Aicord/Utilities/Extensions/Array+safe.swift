//
//  Array+safe.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 05/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation

public struct OrderedDictionary<Key: Hashable, Value>: ExpressibleByDictionaryLiteral, Sequence {
  public struct ElementTuple {
    public let key: Key
    public var value: Value

    public init(key: Key, value: Value) {
      self.key = key
      self.value = value
    }
  }

  public private(set) var keys: [Key] = []
  private var valuesByKey: [Key: Value] = [:]

  public init() {}

  public init(minimumCapacity: Int) {
    self.keys.reserveCapacity(minimumCapacity)
    self.valuesByKey.reserveCapacity(minimumCapacity)
  }

  public init(dictionaryLiteral elements: (Key, Value)...) {
    self.init(uniqueKeysWithValues: elements)
  }

  public init<S: Sequence>(uniqueKeysWithValues keysAndValues: S)
  where S.Element == (Key, Value) {
    for (k, v) in keysAndValues {
      if valuesByKey[k] == nil {
        keys.append(k)
      }
      valuesByKey[k] = v
    }
  }

  public var count: Int { keys.count }
  public var isEmpty: Bool { keys.isEmpty }

  public var values: [Value] {
    get {
      keys.compactMap { valuesByKey[$0] }
    }
    set {
      precondition(newValue.count == keys.count, "OrderedDictionary.values count mismatch")
      for (key, val) in zip(keys, newValue) {
        valuesByKey[key] = val
      }
    }
  }

  public struct Elements: RandomAccessCollection {
    public typealias Element = (key: Key, value: Value)
    public typealias Index = Int

    fileprivate let base: OrderedDictionary<Key, Value>

    public var startIndex: Int { 0 }
    public var endIndex: Int { base.keys.count }

    public subscript(position: Int) -> (key: Key, value: Value) {
      let key = base.keys[position]
      return (key: key, value: base.valuesByKey[key]!)
    }

    public subscript(safe index: Int) -> (key: Key, value: Value)? {
      (startIndex..<endIndex).contains(index) ? self[index] : nil
    }
  }

  public var elements: Elements {
    Elements(base: self)
  }

  public subscript(key: Key) -> Value? {
    get { valuesByKey[key] }
    set {
      if let newValue {
        if valuesByKey[key] == nil {
          keys.append(key)
        }
        valuesByKey[key] = newValue
      } else {
        _ = removeValue(forKey: key)
      }
    }
  }

  public subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
    get { valuesByKey[key] ?? defaultValue() }
    set { self[key] = newValue }
  }

  public func index(forKey key: Key) -> Int? {
    guard valuesByKey[key] != nil else { return nil }
    return keys.firstIndex(of: key)
  }

  @discardableResult
  public mutating func updateValue(_ value: Value, forKey key: Key) -> Value? {
    let old = valuesByKey.updateValue(value, forKey: key)
    if old == nil {
      keys.append(key)
    }
    return old
  }

  @discardableResult
  public mutating func updateValue(
    _ value: Value,
    forKey key: Key,
    insertingAt index: Int
  ) -> (oldValue: Value?, index: Int) {
    if let existingIdx = keys.firstIndex(of: key) {
      let old = valuesByKey.updateValue(value, forKey: key)
      return (old, existingIdx)
    } else {
      let clampedIndex = Swift.max(0, Swift.min(index, keys.count))
      keys.insert(key, at: clampedIndex)
      valuesByKey[key] = value
      return (nil, clampedIndex)
    }
  }

  @discardableResult
  public mutating func removeValue(forKey key: Key) -> Value? {
    guard let old = valuesByKey.removeValue(forKey: key) else { return nil }
    if let idx = keys.firstIndex(of: key) {
      keys.remove(at: idx)
    }
    return old
  }

  @discardableResult
  public mutating func removeFirst() -> (key: Key, value: Value) {
    let key = keys.removeFirst()
    let val = valuesByKey.removeValue(forKey: key)!
    return (key: key, value: val)
  }

  @discardableResult
  public mutating func removeLast() -> (key: Key, value: Value) {
    let key = keys.removeLast()
    let val = valuesByKey.removeValue(forKey: key)!
    return (key: key, value: val)
  }

  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    keys.removeAll(keepingCapacity: keepCapacity)
    valuesByKey.removeAll(keepingCapacity: keepCapacity)
  }

  public func filter(
    _ isIncluded: ((key: Key, value: Value)) throws -> Bool
  ) rethrows -> OrderedDictionary<Key, Value> {
    var result = OrderedDictionary<Key, Value>()
    for key in keys {
      if let value = valuesByKey[key], try isIncluded((key: key, value: value)) {
        result[key] = value
      }
    }
    return result
  }

  public func makeIterator() -> IndexingIterator<[(key: Key, value: Value)]> {
    let pairs = keys.compactMap { k -> (key: Key, value: Value)? in
      guard let v = valuesByKey[k] else { return nil }
      return (key: k, value: v)
    }
    return pairs.makeIterator()
  }

  /// Updates the value for the given key and moves that key–value pair to the front.
  /// If the key doesn’t exist, it’s inserted at the front.
  public mutating func updateValueAndMoveToFront(
    _ value: @autoclosure () -> Value,
    forKey key: Key
  ) {
    let newVal = value()
    if let idx = keys.firstIndex(of: key) {
      keys.remove(at: idx)
    }
    keys.insert(key, at: 0)
    valuesByKey[key] = newVal
  }
}

extension OrderedDictionary: Sendable where Key: Sendable, Value: Sendable {}

extension OrderedDictionary: Equatable where Value: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.keys == rhs.keys && lhs.valuesByKey == rhs.valuesByKey
  }
}

extension OrderedDictionary: Hashable where Value: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(keys)
    for k in keys {
      hasher.combine(valuesByKey[k])
    }
  }
}

extension Sequence {
  public func uniqued<Subject: Hashable>(
    on projection: (Element) throws -> Subject
  ) rethrows -> [Element] {
    var seen = Set<Subject>()
    var result: [Element] = []
    for element in self {
      let key = try projection(element)
      if seen.insert(key).inserted {
        result.append(element)
      }
    }
    return result
  }
}

extension Array {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
