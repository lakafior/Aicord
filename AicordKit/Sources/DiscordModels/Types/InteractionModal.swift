//
//  InteractionModal.swift
//  AicordKit
//

import Foundation

extension Gateway {
  /// INTERACTION_MODAL_CREATE: a bot answered the user's interaction with a form.
  /// https://docs.discord.food/topics/gateway-events#interaction-modal-create
  public struct InteractionModalCreate: Sendable, Decodable, Identifiable {
    public var id: AnySnowflake
    public var nonce: String?
    public var channel_id: ChannelSnowflake?
    public var custom_id: String
    public var title: String
    public var components: [ModalField]
    public var application: Application?

    public struct Application: Sendable, Decodable {
      public var id: ApplicationSnowflake
      public var name: String?
      public var icon: String?
    }

    enum CodingKeys: String, CodingKey {
      case id, nonce, channel_id, custom_id, title, components, application
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(AnySnowflake.self, forKey: .id)
      nonce = try? container.decode(String.self, forKey: .nonce)
      channel_id = try? container.decode(ChannelSnowflake.self, forKey: .channel_id)
      custom_id = try container.decode(String.self, forKey: .custom_id)
      title = try container.decode(String.self, forKey: .title)
      application = try? container.decode(Application.self, forKey: .application)
      // old forms put each text input in an action row; new ones use labels
      components = try container.decode([ModalField.Lossy].self, forKey: .components)
        .flatMap(\.fields)
    }
  }

  /// One entry of a modal: a text input or select, wrapped in an action row (old
  /// forms) or a label (new ones), or a line of text.
  /// https://docs.discord.food/resources/components#label
  public struct ModalField: Sendable, Hashable, Identifiable {
    public enum Input: Sendable, Hashable {
      case text(Interaction.ActionRow.TextInput)
      case select(Interaction.MessageComponent.Select)
      /// A text display: shown, never sent.
      case display(String)
      /// A kind Aicord can't fill in, such as a file upload.
      case unsupported(Int)
    }

    public var input: Input
    /// Set when the input sits in a label, which then carries the field's title.
    public var label: String?
    public var description: String?
    /// The label's component type: 18 for a label, 1 for an action row, nil for none.
    public var wrapper: Int?

    public var id: String {
      switch input {
      case .text(let text): text.custom_id
      case .select(let select): select.custom_id
      case .display(let text): "display:" + text
      case .unsupported(let type): "unsupported:\(type):\(label ?? "")"
      }
    }

    public var customID: String? {
      switch input {
      case .text(let text): text.custom_id
      case .select(let select): select.custom_id
      default: nil
      }
    }

    struct Lossy: Decodable {
      var fields: [ModalField]

      enum CodingKeys: String, CodingKey { case type, components, component, label, description, content }

      init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
          fields = []
          return
        }
        let type = (try? container.decode(Int.self, forKey: .type)) ?? 0
        switch type {
        case 1:
          let children = (try? container.decode([Child].self, forKey: .components)) ?? []
          fields = children.map { ModalField(input: $0.input, wrapper: 1) }
        case 18:
          let child = (try? container.decode(Child.self, forKey: .component))?.input ?? .unsupported(0)
          fields = [
            ModalField(
              input: child,
              label: try? container.decode(String.self, forKey: .label),
              description: try? container.decode(String.self, forKey: .description),
              wrapper: 18)
          ]
        case 10:
          fields = [
            ModalField(input: .display((try? container.decode(String.self, forKey: .content)) ?? ""))
          ]
        case 4:
          fields = [ModalField(input: (try? Child(from: decoder))?.input ?? .unsupported(4))]
        default:
          fields = [ModalField(input: .unsupported(type))]
        }
      }
    }

    struct Child: Decodable {
      var input: Input

      enum CodingKeys: String, CodingKey { case type }

      init(from decoder: any Decoder) throws {
        let type = (try? decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .type)) ?? 0
        switch type {
        case 4:
          input = (try? .text(Interaction.ActionRow.TextInput(from: decoder))) ?? .unsupported(4)
        case 3, 5, 6, 7, 8:
          if case .select(let select) = try Interaction.MessageComponent(from: decoder) {
            input = .select(select)
          } else {
            input = .unsupported(type)
          }
        default:
          input = .unsupported(type)
        }
      }
    }

    public init(input: Input, label: String? = nil, description: String? = nil, wrapper: Int? = nil) {
      self.input = input
      self.label = label
      self.description = description
      self.wrapper = wrapper
    }
  }
}

extension Payloads {
  /// A click on a bot's button or a choice in its select menu.
  /// https://docs.discord.food/interactions/receiving-and-responding#create-interaction
  public struct ComponentInteraction: Sendable, Encodable, ValidatablePayload {
    public var type = 3
    public var application_id: ApplicationSnowflake
    public var guild_id: GuildSnowflake?
    public var channel_id: ChannelSnowflake
    public var message_id: MessageSnowflake
    public var message_flags: Int
    public var session_id: String
    public var data: ComponentData
    public var nonce: String

    public struct ComponentData: Sendable, Encodable {
      public var component_type: Int
      public var custom_id: String
      /// Picked values for a select; left out for a button.
      public var values: [String]?

      public init(component_type: Int, custom_id: String, values: [String]? = nil) {
        self.component_type = component_type
        self.custom_id = custom_id
        self.values = values
      }
    }

    public init(
      application_id: ApplicationSnowflake, guild_id: GuildSnowflake?, channel_id: ChannelSnowflake,
      message_id: MessageSnowflake, message_flags: Int, session_id: String, data: ComponentData,
      nonce: String
    ) {
      self.application_id = application_id
      self.guild_id = guild_id
      self.channel_id = channel_id
      self.message_id = message_id
      self.message_flags = message_flags
      self.session_id = session_id
      self.data = data
      self.nonce = nonce
    }

    public func validate() -> [ValidationFailure] {}
  }

  /// The user's answers to a bot's modal, sent back in the shape it came in.
  /// https://docs.discord.food/interactions/receiving-and-responding#modal-submit-data-structure
  public struct ModalSubmitInteraction: Sendable, Encodable, ValidatablePayload {
    public var type = 5
    public var application_id: ApplicationSnowflake
    public var guild_id: GuildSnowflake?
    public var channel_id: ChannelSnowflake
    public var session_id: String
    public var data: ModalData
    public var nonce: String

    public struct ModalData: Sendable, Encodable {
      public var id: AnySnowflake
      public var custom_id: String
      public var components: [Row]
    }

    /// An action row with one text input, or a label with one input.
    public struct Row: Sendable, Encodable {
      public var type: Int
      public var components: [Value]?
      public var component: Value?
    }

    public struct Value: Sendable, Encodable {
      public var type: Int
      public var custom_id: String
      public var value: String?
      public var values: [String]?
    }

    /// Answers by field: text for a text input, picked values for a select.
    public enum Answer: Sendable {
      case text(String)
      case values([String])
    }

    public init(
      modal: Gateway.InteractionModalCreate, answers: [String: Answer], application_id: ApplicationSnowflake,
      guild_id: GuildSnowflake?, channel_id: ChannelSnowflake, session_id: String, nonce: String
    ) {
      self.application_id = application_id
      self.guild_id = guild_id
      self.channel_id = channel_id
      self.session_id = session_id
      self.nonce = nonce
      let rows: [Row] = modal.components.compactMap { field in
        let value: Value
        switch field.input {
        case .text(let input):
          let text: String =
            if case .text(let text) = answers[input.custom_id] { text } else { "" }
          value = Value(type: 4, custom_id: input.custom_id, value: text)
        case .select(let select):
          let values: [String] =
            if case .values(let values) = answers[select.custom_id] { values } else { [] }
          value = Value(type: select.type, custom_id: select.custom_id, values: values)
        case .display, .unsupported:
          return nil
        }
        return field.wrapper == 18
          ? Row(type: 18, component: value) : Row(type: 1, components: [value])
      }
      self.data = ModalData(id: modal.id, custom_id: modal.custom_id, components: rows)
    }

    public func validate() -> [ValidationFailure] {}
  }
}
