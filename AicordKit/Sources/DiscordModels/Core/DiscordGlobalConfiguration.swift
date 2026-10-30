import Foundation
import Logging
import Synchronization

private final class ConfigurationStorage: Sendable {
  struct State: Sendable {
    var decoder: any DiscordDecoder = JSONDecoder()
    var encoder: any DiscordEncoder = JSONEncoder()
    var makeLogger: @Sendable (String) -> Logger = { Logger(label: $0) }
  }

  let state = Mutex(State())

  static let shared = ConfigurationStorage()
}

/// A container for **on-boot & one-time-only** configuration options.
public enum DiscordGlobalConfiguration {
  /// Currently only 10 is supported.
  /// official client is on v9, not v10.
  public static let apiVersion = 9

  /// https://docs.discord.food/topics/gateway-events#qos-payload-structure
  public static let qosVersion = 29

  public static let gatewayURL = "wss://gateway.discord.gg"
  public static let apiBaseURL = "https://discord.com/api"
  public static let remoteAuthURL = "wss://remote-auth-gateway.discord.gg"

  /// The global decoder to decode JSONs with.
  public static var decoder: any DiscordDecoder {
    get { ConfigurationStorage.shared.state.withLock { $0.decoder } }
    set { ConfigurationStorage.shared.state.withLock { $0.decoder = newValue } }
  }
  /// The global encoder to encode JSONs with.
  public static var encoder: any DiscordEncoder {
    get { ConfigurationStorage.shared.state.withLock { $0.encoder } }
    set { ConfigurationStorage.shared.state.withLock { $0.encoder = newValue } }
  }
  /// Function to make loggers with. You can override it with your own logger.
  /// The `String` argument represents the label of the logger.
  public static var makeLogger: @Sendable (String) -> Logger {
    get { ConfigurationStorage.shared.state.withLock { $0.makeLogger } }
    set { ConfigurationStorage.shared.state.withLock { $0.makeLogger = newValue } }
  }
}

//MARK: - DiscordDecoder
public protocol DiscordDecoder: Sendable {
  func decode<D: Decodable>(_ type: D.Type, from: Data) throws -> D
}

extension JSONDecoder: DiscordDecoder {}

//MARK: - DiscordEncoder
public protocol DiscordEncoder: Sendable {
  func encode<E: Encodable>(_ value: E) throws -> Data
}

extension JSONEncoder: DiscordEncoder {}
