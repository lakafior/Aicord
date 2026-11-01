//
//  ApplicationCommandIndex.swift
//  AicordKit
//

import Foundation

/// The commands a user can run somewhere: a guild's, a DM's or the user's own
/// installed apps. https://docs.discord.food/interactions/application-commands#application-command-index-structure
public struct ApplicationCommandIndex: Sendable, Decodable {
  public var applications: [Application]
  public var application_commands: [Command]
  public var version: String?

  public struct Application: Sendable, Decodable, Identifiable {
    public var id: ApplicationSnowflake
    public var name: String
    public var description: String?
    public var icon: String?
    public var bot_id: UserSnowflake?
  }

  /// https://docs.discord.food/interactions/application-commands#application-command-object
  public struct Command: Sendable, Codable, Identifiable, Hashable {
    public var id: AnySnowflake
    public var application_id: ApplicationSnowflake
    public var version: AnySnowflake
    /// 1 chat input, 2 user, 3 message, 4 primary entry point.
    public var type: Int?
    public var name: String
    public var name_localized: String?
    public var description: String
    public var description_localized: String?
    public var options: [Option]?
    public var guild_id: GuildSnowflake?

    public var isChatInput: Bool { (type ?? 1) == 1 }
    public var displayName: String { name_localized ?? name }
    public var displayDescription: String { description_localized ?? description }
  }

  /// https://docs.discord.food/interactions/application-commands#application-command-option-structure
  public struct Option: Sendable, Codable, Hashable {
    public var type: OptionKind
    public var name: String
    public var name_localized: String?
    public var description: String
    public var description_localized: String?
    public var required: Bool?
    public var choices: [Choice]?
    public var options: [Option]?
    public var channel_types: [Int]?
    public var min_value: Double?
    public var max_value: Double?
    public var min_length: Int?
    public var max_length: Int?
    public var autocomplete: Bool?

    public var displayName: String { name_localized ?? name }
    public var displayDescription: String { description_localized ?? description }
  }

  public enum OptionKind: Int, Sendable, Codable, Hashable {
    case subCommand = 1
    case subCommandGroup = 2
    case string = 3
    case integer = 4
    case boolean = 5
    case user = 6
    case channel = 7
    case role = 8
    case mentionable = 9
    case number = 10
    case attachment = 11
    case unknown = -1

    public init(from decoder: any Decoder) throws {
      let raw = try decoder.singleValueContainer().decode(Int.self)
      self = OptionKind(rawValue: raw) ?? .unknown
    }
  }

  /// https://docs.discord.food/interactions/application-commands#application-command-option-choice-structure
  public struct Choice: Sendable, Codable, Hashable {
    public var name: String
    public var name_localized: String?
    public var value: Value

    public var displayName: String { name_localized ?? name }

    public init(name: String, value: Value) {
      self.name = name
      self.value = value
    }
  }

  /// A choice's or an option's value: text or a number.
  public enum Value: Sendable, Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let int = try? container.decode(Int.self) {
        self = .int(int)
      } else if let double = try? container.decode(Double.self) {
        self = .double(double)
      } else if let bool = try? container.decode(Bool.self) {
        self = .bool(bool)
      } else {
        self = .string(try container.decode(String.self))
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .string(let value): try container.encode(value)
      case .int(let value): try container.encode(value)
      case .double(let value): try container.encode(value)
      case .bool(let value): try container.encode(value)
      }
    }
  }
}

extension Payloads {
  /// Runs an application command the way the official client does.
  /// https://docs.discord.food/interactions/receiving-and-responding#create-interaction
  public struct CreateInteraction: Sendable, Encodable, ValidatablePayload {
    /// 2 application command, 4 autocomplete.
    public var type: Int
    public var application_id: ApplicationSnowflake
    public var guild_id: GuildSnowflake?
    public var channel_id: ChannelSnowflake
    public var session_id: String
    public var data: CommandData
    public var nonce: String
    public var analytics_location: String?

    public init(
      type: Int,
      application_id: ApplicationSnowflake,
      guild_id: GuildSnowflake?,
      channel_id: ChannelSnowflake,
      session_id: String,
      data: CommandData,
      nonce: String,
      analytics_location: String? = "slash_ui"
    ) {
      self.type = type
      self.application_id = application_id
      self.guild_id = guild_id
      self.channel_id = channel_id
      self.session_id = session_id
      self.data = data
      self.nonce = nonce
      self.analytics_location = analytics_location
    }

    public func validate() -> [ValidationFailure] {}

    public struct CommandData: Sendable, Encodable {
      public var version: AnySnowflake
      public var id: AnySnowflake
      public var name: String
      public var type: Int
      public var options: [DataOption]
      public var application_command: ApplicationCommandIndex.Command
      public var attachments: [String]

      public init(command: ApplicationCommandIndex.Command, options: [DataOption]) {
        self.version = command.version
        self.id = command.id
        self.name = command.name
        self.type = command.type ?? 1
        self.options = options
        self.application_command = command
        self.attachments = []
      }
    }

    /// An option with its value, or a subcommand with its own options.
    public struct DataOption: Sendable, Encodable {
      public var type: Int
      public var name: String
      public var value: ApplicationCommandIndex.Value?
      public var options: [DataOption]?
      /// Set on the option being typed in an autocomplete request.
      public var focused: Bool?

      public init(
        type: Int,
        name: String,
        value: ApplicationCommandIndex.Value? = nil,
        options: [DataOption]? = nil,
        focused: Bool? = nil
      ) {
        self.type = type
        self.name = name
        self.value = value
        self.options = options
        self.focused = focused
      }
    }
  }
}

extension Gateway {
  /// INTERACTION_CREATE / INTERACTION_SUCCESS / INTERACTION_FAILURE sent to the
  /// user who ran a command, matched to the request by nonce.
  public struct InteractionStatus: Sendable, Decodable {
    public var id: AnySnowflake?
    public var nonce: String?
  }

  /// APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE.
  public struct ApplicationCommandAutocompleteResponse: Sendable, Decodable {
    public var nonce: String?
    public var choices: [ApplicationCommandIndex.Choice]
  }
}
