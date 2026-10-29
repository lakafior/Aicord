import DiscordModels
import Foundation

/// A manager of Gateway interactions.
public protocol GatewayManager: AnyObject, Sendable {
  /// The client to send requests to Discord with.
  nonisolated var client: any DiscordClient { get }
  /// This gateway manager's identifier.
  nonisolated var id: UInt { get }
  /// The identification payload that is sent to Discord.
  nonisolated var identifyPayload: Gateway.Identify { get }
  /// An stream of Gateway events.
  nonisolated var events: DiscordAsyncSequence<Gateway.Event> { get }
  /// An stream of Gateway event parse failures.
  nonisolated var eventFailures: DiscordAsyncSequence<(any Error, Data)> {
    get
  }
  /// Connects to Discord.
  func connect() async
  /// https://discord.com/developers/docs/topics/gateway-events#request-guild-members
  func requestGuildMembersChunk(payload: Gateway.RequestGuildMembers) async
  /// https://discord.com/developers/docs/topics/gateway-events#update-presence
  func updatePresence(payload: Gateway.Identify.Presence) async
  /// https://discord.com/developers/docs/topics/gateway-events#update-voice-state
  func updateVoiceState(payload: VoiceStateUpdate) async
  /// An stream of Gateway events.
  @available(*, deprecated, renamed: "events")
  func makeEventsStream() async -> AsyncStream<Gateway.Event>
  /// Makes an stream of Gateway event parse failures.
  @available(*, deprecated, renamed: "eventFailures")
  func makeEventsParseFailureStream() async -> AsyncStream<(any Error, Data)>
  /// Disconnects from Discord.
  func disconnect() async
}
