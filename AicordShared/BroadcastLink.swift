//
//  BroadcastLink.swift
//  Aicord
//
//  The wire between the iOS Broadcast extension and the app. ReplayKit
//  hands the screen to the extension, a separate process with little
//  memory; the call, its encryption and its connections live in the app.
//  So the extension only encodes, and sends each frame to the app over a
//  Unix socket in the shared App Group container.
//
//  Messages: one type byte, a 4-byte big-endian length, the payload.
//

import Foundation

enum BroadcastLink {
  enum Message: Equatable {
    /// Extension → app: one encoded H.264 frame (Annex B) and its RTP
    /// timestamp.
    case frame(isKeyframe: Bool, timestamp: UInt32, data: Data)
    /// App → extension: a viewer needs a key frame.
    case keyframe
    /// App → extension: the call or the stream is over.
    case stop
  }

  /// A frame larger than this is not something the encoder made.
  static let maxPayload = 8 * 1024 * 1024

  /// The socket in the App Group container. `nil` without an App Group, or
  /// when the path does not fit a socket address (104 bytes).
  static var socketPath: String? {
    guard
      let group = Bundle.main.object(forInfoDictionaryKey: "AicordAppGroup") as? String,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group)
    else { return nil }
    let path = container.appendingPathComponent("broadcast.sock").path
    return path.utf8.count < 104 ? path : nil
  }

  static func encode(_ message: Message) -> Data {
    var type: UInt8
    var payload = Data()
    switch message {
    case .frame(let isKeyframe, let timestamp, let data):
      type = 1
      payload.append(isKeyframe ? 1 : 0)
      payload.append(contentsOf: bytes(timestamp))
      payload.append(data)
    case .keyframe:
      type = 2
    case .stop:
      type = 3
    }
    var out = Data([type])
    out.append(contentsOf: bytes(UInt32(payload.count)))
    out.append(payload)
    return out
  }

  private static func bytes(_ value: UInt32) -> [UInt8] {
    [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
  }

  /// Puts messages back together from the bytes of the stream.
  struct Parser {
    private var buffer = Data()
    /// The stream broke the format; nothing more can be read from it.
    private(set) var isBroken = false

    mutating func append(_ data: Data) -> [Message] {
      guard !isBroken else { return [] }
      buffer.append(data)
      var messages: [Message] = []
      while buffer.count >= 5 {
        let head = [UInt8](buffer.prefix(5))
        let length =
          Int(head[1]) << 24 | Int(head[2]) << 16 | Int(head[3]) << 8 | Int(head[4])
        guard length <= BroadcastLink.maxPayload else {
          isBroken = true
          return messages
        }
        guard buffer.count >= 5 + length else { break }
        let payload = [UInt8](buffer.dropFirst(5).prefix(length))
        buffer = Data(buffer.dropFirst(5 + length))
        switch head[0] {
        case 1 where payload.count > 5:
          let timestamp =
            UInt32(payload[1]) << 24 | UInt32(payload[2]) << 16
            | UInt32(payload[3]) << 8 | UInt32(payload[4])
          messages.append(
            .frame(isKeyframe: payload[0] != 0, timestamp: timestamp, data: Data(payload[5...])))
        case 2:
          messages.append(.keyframe)
        case 3:
          messages.append(.stop)
        default:
          // A type this build doesn't know: skipped.
          continue
        }
      }
      return messages
    }
  }

  // MARK: Sockets

  private static func address(_ path: String) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      let bytes = Array(path.utf8.prefix(raw.count - 1))
      raw.copyBytes(from: bytes)
    }
    return address
  }

  private static func withAddress<R>(
    _ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R
  ) -> R {
    var address = address(path)
    return withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
  }

  private static func makeSocket() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    // A closed peer is an error from write, not a signal that ends us.
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    return fd
  }

  /// The app's side: a listening socket, replacing a stale one.
  static func listen(at path: String) -> Int32? {
    guard let fd = makeSocket() else { return nil }
    unlink(path)
    guard withAddress(path, { bind(fd, $0, $1) }) == 0, Darwin.listen(fd, 1) == 0 else {
      close(fd)
      return nil
    }
    return fd
  }

  /// The extension's side. `nil` when the app isn't listening.
  static func connect(to path: String) -> Int32? {
    guard let fd = makeSocket() else { return nil }
    guard withAddress(path, { Darwin.connect(fd, $0, $1) }) == 0 else {
      close(fd)
      return nil
    }
    // A stuck app must not hold the encoder up for ever.
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    return fd
  }

  /// Writes all of `data`; `false` when the other side is gone or stuck.
  static func write(_ data: Data, to fd: Int32) -> Bool {
    data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let written = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
        if written > 0 {
          offset += written
        } else if written < 0, errno == EINTR {
          continue
        } else {
          return false
        }
      }
      return true
    }
  }

  /// Reads what is there, blocking until something is. `nil` at the end of
  /// the stream or on an error.
  static func read(from fd: Int32) -> Data? {
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = Darwin.read(fd, &buffer, buffer.count)
      if count > 0 { return Data(buffer[..<count]) }
      if count < 0, errno == EINTR { continue }
      return nil
    }
  }
}
