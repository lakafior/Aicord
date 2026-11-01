//
//  MemberVerification.swift
//  AicordKit
//

import Foundation

/// A server's rules screen (and questions) that new members answer before they
/// can talk. https://docs.discord.food/resources/guild#member-verification-object
public struct MemberVerification: Sendable, Decodable {
  /// Sent back with the answers so Discord knows which version they're for.
  public var version: String?
  public var description: String?
  public var form_fields: [FormField]

  /// https://docs.discord.food/resources/guild#member-verification-form-field-structure
  public struct FormField: Sendable, Codable, Hashable {
    /// `TERMS`, `TEXT_INPUT`, `PARAGRAPH`, `MULTIPLE_CHOICE` or a newer type.
    public var field_type: String
    public var label: String
    public var choices: [String]?
    public var values: [String]?
    public var response: Response?
    public var required: Bool
    public var description: String?
    public var placeholder: String?
  }

  /// A form field's answer: agreement, text or the index of a choice.
  public enum Response: Sendable, Codable, Hashable {
    case bool(Bool)
    case int(Int)
    case string(String)

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let bool = try? container.decode(Bool.self) {
        self = .bool(bool)
      } else if let int = try? container.decode(Int.self) {
        self = .int(int)
      } else {
        self = .string(try container.decode(String.self))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .bool(let value): try container.encode(value)
      case .int(let value): try container.encode(value)
      case .string(let value): try container.encode(value)
      }
    }
  }
}

/// A join request after answering member verification.
/// https://docs.discord.food/resources/guild#guild-join-request-object
public struct GuildJoinRequestResult: Sendable, Decodable {
  /// `STARTED`, `SUBMITTED`, `REJECTED` or `APPROVED`.
  public var application_status: String?
  public var rejection_reason: String?
}

/// The current user's interest in scheduled events.
/// https://docs.discord.food/resources/guild-scheduled-event#guild-scheduled-event-user-object
public struct ScheduledEventRSVP: Sendable, Decodable {
  public var guild_scheduled_event_id: GuildScheduledEventSnowflake
  public var user_id: UserSnowflake?
}

extension Payloads {
  /// https://docs.discord.food/resources/guild#modify-guild-onboarding-responses
  public struct UpdateOnboardingResponses: Sendable, Encodable, ValidatablePayload {
    public var onboarding_responses: [OnboardingPromptOptionSnowflake]
    /// Prompt ID → Unix time in milliseconds when it was shown.
    public var onboarding_prompts_seen: [String: Int64]
    /// Option ID → Unix time in milliseconds when it was shown.
    public var onboarding_responses_seen: [String: Int64]

    public init(
      onboarding_responses: [OnboardingPromptOptionSnowflake],
      onboarding_prompts_seen: [String: Int64],
      onboarding_responses_seen: [String: Int64]
    ) {
      self.onboarding_responses = onboarding_responses
      self.onboarding_prompts_seen = onboarding_prompts_seen
      self.onboarding_responses_seen = onboarding_responses_seen
    }

    public func validate() -> [ValidationFailure] {
      validateElementCountDoesNotExceed(onboarding_responses, max: 750, name: "onboarding_responses")
    }
  }

  /// https://docs.discord.food/resources/guild#create-guild-join-request
  public struct SubmitMemberVerification: Sendable, Encodable, ValidatablePayload {
    public var form_fields: [MemberVerification.FormField]
    public var version: String?

    public init(form_fields: [MemberVerification.FormField], version: String?) {
      self.form_fields = form_fields
      self.version = version
    }

    public func validate() -> [ValidationFailure] {}
  }
}
