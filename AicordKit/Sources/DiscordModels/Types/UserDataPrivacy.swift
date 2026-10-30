//
//  UserDataPrivacy.swift
//  AicordKit
//

import Foundation

/// Consent type to its state, e.g. `["personalization": .init(consented: true)]`.
/// https://docs.discord.food/resources/user-settings#consents-object
public typealias DiscordUserConsents = [String: DiscordUserConsent]

public struct DiscordUserConsent: Sendable, Codable, Hashable {
  public var consented: Bool

  public init(consented: Bool) {
    self.consented = consented
  }
}

extension DiscordUserConsent {
  public enum Kind: String, Sendable {
    case personalization
    case usageStatistics = "usage_statistics"
  }
}

/// A request for a copy of the user's data.
/// https://docs.discord.food/resources/user#harvest-object
public struct DiscordUserHarvest: Sendable, Codable {
  public var harvest_id: String
  public var user_id: UserSnowflake
  public var email: String?
  public var state: State
  public var status: Status?
  public var created_at: DiscordTimestamp
  public var completed_at: DiscordTimestamp?
  public var polled_at: DiscordTimestamp?

  @UnstableEnum<String>
  public enum State: Sendable, Codable {
    case incomplete  // "INCOMPLETE"
    case delivered  // "DELIVERED"
    case cancelled  // "CANCELLED"
    case __undocumented(String)
  }

  @UnstableEnum<Int>
  public enum Status: Sendable, Codable {
    case queued  // 0
    case running  // 1
    case failed  // 2
    case completed  // 3
    case cancelled  // 4
    case __undocumented(Int)
  }
}

extension Payloads {
  /// https://docs.discord.food/resources/user-settings#modify-user-consents
  public struct ModifyUserConsents: Sendable, Encodable, ValidatablePayload {
    public var grant: [String]
    public var revoke: [String]

    public init(grant: [DiscordUserConsent.Kind] = [], revoke: [DiscordUserConsent.Kind] = []) {
      self.grant = grant.map(\.rawValue)
      self.revoke = revoke.map(\.rawValue)
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// https://docs.discord.food/resources/user#create-user-harvest
  public struct CreateUserHarvest: Sendable, Encodable, ValidatablePayload {
    /// Empty asks for everything.
    public var backends: [String]

    public init(backends: [String] = []) {
      self.backends = backends
    }

    public func validate() -> [ValidationFailure] {}
  }
}
