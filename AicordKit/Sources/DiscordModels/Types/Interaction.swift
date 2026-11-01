import Foundation

/// Namespace for the interaction types a user client still needs to display
/// messages: the interaction kind, resolved data and message components.
public enum Interaction {

  /// https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-object-interaction-type
  #if Non64BitSystemsCompatibility
    @UnstableEnum<Int64>
  #else
    @UnstableEnum<Int>
  #endif
  public enum Kind: Sendable, Decodable {
    case ping  // 1
    case applicationCommand  // 2
    case messageComponent  // 3
    case applicationCommandAutocomplete  // 4
    case modalSubmit  // 5
    #if Non64BitSystemsCompatibility
      case __undocumented(Int64)
    #else
      case __undocumented(Int)
    #endif
  }

  /// https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-object-interaction-context-types
  #if Non64BitSystemsCompatibility
    @UnstableEnum<Int64>
  #else
    @UnstableEnum<Int>
  #endif
  public enum ContextKind: Sendable, Decodable {
    case guild  // 0
    case botDm  // 1
    case privateChannel  // 2
    #if Non64BitSystemsCompatibility
      case __undocumented(Int64)
    #else
      case __undocumented(Int)
    #endif
  }

  /// https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-object-resolved-data-structure
  public struct ResolvedData: Sendable, Decodable, Equatable, Hashable {

    /// https://discord.com/developers/docs/resources/channel#channel-object-channel-structure
    /// https://discord.com/developers/docs/interactions/receiving-and-responding#interaction-object-resolved-data-structure
    public struct PartialChannel: Sendable, Decodable, Equatable, Hashable {
      public var id: ChannelSnowflake
      public var type: DiscordChannel.Kind
      public var name: String?
      public var permissions: StringBitField<Permission>?
      public var parent_id: AnySnowflake?
      public var thread_metadata: ThreadMetadata?
    }

    public var users: [UserSnowflake: DiscordUser]?
    public var members: [UserSnowflake: Guild.PartialMember]?
    public var roles: [RoleSnowflake: Role]?
    public var channels: [ChannelSnowflake: PartialChannel]?
    public var messages: [MessageSnowflake: DiscordChannel.PartialMessage]?
    public var attachments: [AttachmentSnowflake: DiscordChannel.Message.Attachment]?
  }
}

/// https://discord.com/developers/docs/interactions/receiving-and-responding#message-interaction-object-message-interaction-structure
public struct MessageInteraction: Sendable, Decodable, Equatable, Hashable {
  public var id: InteractionSnowflake
  public var type: Interaction.Kind
  public var name: String
  public var user: DiscordUser
  public var member: Guild.PartialMember?
}

extension Interaction {
  /// Due to Discord reusing the components field, this enum exists to allow you to send either legacy components or the new components v2.
  /// This does not represent any actual Discord structure. It parses legacy action rows when every
  /// top-level component is one, and the lossy components v2 tree otherwise.
  public enum ComponentSwitch: Sendable, Decodable, Equatable, Hashable {
    var legacy: [ActionRow]? {
      if case .legacy(let actionRows) = self {
        return actionRows
      }
      return nil
    }

    /// The component tree to render, whichever kind was received.
    public var tree: [MessageComponent] {
      switch self {
      case .legacy(let actionRows): actionRows.map(MessageComponent.init)
      case .v2(let components): components
      }
    }

    case legacy([ActionRow])
    case v2([MessageComponent])

    public init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      let tree = try container.decode([MessageComponent.Lossy].self).map(\.value)
      if tree.allSatisfy({ if case .actionRow = $0 { true } else { false } }),
        let actionRows = try? container.decode([ActionRow].self)
      {
        self = .legacy(actionRows)
      } else {
        self = .v2(tree)
      }
    }
  }

  /// https://discord.com/developers/docs/interactions/message-components#action-rows
  /// `ActionRow` is an attempt to simplify/beautify Discord's messy components.
  /// Anything inside `ActionRow` must not be used on its own for decoding/encoding purposes.
  /// For example you always need to use `[ActionRow]` instead of `[ActionRow.Component]`.
  public struct ActionRow: Sendable, Decodable, ExpressibleByArrayLiteral,
    Equatable, Hashable, ValidatablePayload
  {

    /// https://discord.com/developers/docs/interactions/message-components#component-object-component-types
    /// https://docs.discord.food/resources/components#component-type
    #if Non64BitSystemsCompatibility
      @UnstableEnum<Int64>
    #else
      @UnstableEnum<Int>
    #endif
    public enum Kind: Sendable, Decodable {
      case actionRow  // 1
      case button  // 2
      case stringSelect  // 3
      case textInput  // 4
      case userSelect  // 5
      case roleSelect  // 6
      case mentionableSelect  // 7
      case channelSelect  // 8
      case label  // 18
      case fileUpload  // 19

      /* specifically components v2 below*/
      case section  // 9
      case textDisplay  // 10
      case thumbnail  // 11
      case mediaGallery  // 12
      case file  // 13
      case separator  // 14
      case contentInventoryEntry  // 16
      case container  // 17
      #if Non64BitSystemsCompatibility
        case __undocumented(Int64)
      #else
        case __undocumented(Int)
      #endif
    }

    /// https://discord.com/developers/docs/interactions/message-components#button-object-button-structure
    public struct Button: Sendable, Decodable, Equatable, Hashable,
      ValidatablePayload
    {

      /// https://discord.com/developers/docs/interactions/message-components#button-object-button-styles
      #if Non64BitSystemsCompatibility
        @UnstableEnum<Int64>
      #else
        @UnstableEnum<Int>
      #endif
      public enum Style: Sendable, Decodable {
        case primary  // 1
        case secondary  // 2
        case success  // 3
        case danger  // 4
        case link  // 5
        case premium  // 6
        #if Non64BitSystemsCompatibility
          case __undocumented(Int64)
        #else
          case __undocumented(Int)
        #endif
      }

      /// The same as ``Style``, but has no `link`.
      /// https://discord.com/developers/docs/interactions/message-components#button-object-button-styles
      public enum NonLinkStyle: Sendable {
        case primary
        case secondary
        case success
        case danger
        case premium

        /// This case serves as a way of discouraging exhaustive switch statements
        case __DO_NOT_USE_THIS_CASE

        public func toStyle() -> Style {
          switch self {
          case .primary: return .primary
          case .secondary: return .secondary
          case .success: return .success
          case .danger: return .danger
          case .premium: return .premium
          case .__DO_NOT_USE_THIS_CASE:
            fatalError(
              "If the case name wasn't already clear enough: '__DO_NOT_USE_THIS_CASE' MUST NOT be used"
            )
          }
        }

        public init?(style: Style) {
          switch style {
          case .primary: self = .primary
          case .secondary: self = .secondary
          case .success: self = .success
          case .danger: self = .danger
          case .link: return nil
          case .premium: self = .premium
          case .__undocumented: return nil
          }
        }
      }

      public var style: Style
      public var label: String?
      public var emoji: Emoji?
      public var custom_id: String?
      public var sku_id: SKUSnowflake?
      public var url: String?
      public var disabled: Bool?

      /// Makes a non-link button.
      public init(
        style: NonLinkStyle,
        label: String,
        custom_id: String,
        sku_id: SKUSnowflake? = nil,
        disabled: Bool? = nil
      ) {
        self.style = style.toStyle()
        self.label = label
        self.emoji = nil
        self.custom_id = custom_id
        self.sku_id = sku_id
        self.disabled = disabled
      }

      /// Makes a non-link button.
      public init(
        style: NonLinkStyle,
        emoji: Emoji,
        custom_id: String,
        sku_id: SKUSnowflake? = nil,
        disabled: Bool? = nil
      ) {
        self.style = style.toStyle()
        self.label = nil
        self.emoji = emoji
        self.custom_id = custom_id
        self.sku_id = sku_id
        self.disabled = disabled
      }

      /// Makes a non-link button.
      public init(
        style: NonLinkStyle,
        label: String,
        emoji: Emoji,
        custom_id: String,
        sku_id: SKUSnowflake? = nil,
        disabled: Bool? = nil
      ) {
        self.style = style.toStyle()
        self.label = label
        self.emoji = emoji
        self.custom_id = custom_id
        self.sku_id = sku_id
        self.disabled = disabled
      }

      /// Makes a link button.
      public init(
        label: String,
        url: String,
        sku_id: SKUSnowflake? = nil,
        disabled: Bool? = nil
      ) {
        self.style = .link
        self.label = label
        self.emoji = nil
        self.url = url
        self.sku_id = sku_id
        self.disabled = disabled
      }

      /// Makes a link button.
      public init(
        emoji: Emoji,
        url: String,
        sku_id: SKUSnowflake? = nil,
        disabled: Bool? = nil
      ) {
        self.style = .link
        self.label = nil
        self.emoji = emoji
        self.url = url
        self.sku_id = sku_id
        self.disabled = disabled
      }

      /// Makes a link button.
      public init(
        label: String,
        emoji: Emoji,
        url: String,
        sku_id: SKUSnowflake? = nil,
        disabled: Bool? = nil
      ) {
        self.style = .link
        self.label = label
        self.emoji = emoji
        self.url = url
        self.sku_id = sku_id
        self.disabled = disabled
      }

      public func validate() -> [ValidationFailure] {
        validateCharacterCountDoesNotExceed(label, max: 80, name: "label")
        validateCharacterCountDoesNotExceed(
          custom_id,
          max: 100,
          name: "custom_id"
        )
      }
    }

    /// https://discord.com/developers/docs/interactions/message-components#select-menu-object-select-menu-structure
    public struct StringSelectMenu: Sendable, Decodable, Equatable, Hashable,
      ValidatablePayload
    {

      /// https://discord.com/developers/docs/interactions/message-components#select-menu-object-select-option-structure
      public struct Option: Sendable, Decodable, Equatable, Hashable,
        ValidatablePayload
      {
        public var label: String
        public var value: String
        public var description: String?
        public var emoji: Emoji?
        public var `default`: Bool?

        public init(
          label: String,
          value: String,
          description: String? = nil,
          emoji: Emoji? = nil,
          `default`: Bool? = nil
        ) {
          self.label = label
          self.value = value
          self.description = description
          self.emoji = emoji
          self.`default` = `default`
        }

        public func validate() -> [ValidationFailure] {
          validateCharacterCountDoesNotExceed(label, max: 100, name: "label")
          validateCharacterCountDoesNotExceed(value, max: 100, name: "value")
          validateCharacterCountDoesNotExceed(
            description,
            max: 100,
            name: "description"
          )
        }
      }

      public var custom_id: String
      public var options: [Option]
      public var placeholder: String?
      public var min_values: Int?
      public var max_values: Int?
      public var disabled: Bool?

      public init(
        custom_id: String,
        options: [Option],
        placeholder: String? = nil,
        min_values: Int? = nil,
        max_values: Int? = nil,
        disabled: Bool? = nil
      ) {
        self.custom_id = custom_id
        self.options = options
        self.placeholder = placeholder
        self.min_values = min_values
        self.max_values = max_values
        self.disabled = disabled
      }

      public func validate() -> [ValidationFailure] {
        validateCharacterCountDoesNotExceed(
          custom_id,
          max: 100,
          name: "custom_id"
        )
        validateCharacterCountDoesNotExceed(
          placeholder,
          max: 150,
          name: "placeholder"
        )
        validateNumberInRangeOrNil(
          min_values,
          min: 0,
          max: 25,
          name: "min_values"
        )
        validateNumberInRangeOrNil(
          max_values,
          min: 1,
          max: 25,
          name: "max_values"
        )
        validateElementCountDoesNotExceed(options, max: 25, name: "options")
        options.validate()
      }
    }

    /// https://discord.com/developers/docs/interactions/message-components#select-menu-object-select-default-value-structure
    public struct DefaultValue: Sendable, Decodable, Equatable, Hashable {

      /// https://discord.com/developers/docs/interactions/message-components#select-menu-object-select-default-value-structure
      public enum Kind: String, Sendable, Decodable {
        case user
        case role
        case channel
      }

      public var id: AnySnowflake
      public var type: Kind

      public init(id: UserSnowflake) {
        self.id = AnySnowflake(id)
        self.type = .user
      }

      public init(id: RoleSnowflake) {
        self.id = AnySnowflake(id)
        self.type = .role
      }

      public init(id: ChannelSnowflake) {
        self.id = AnySnowflake(id)
        self.type = .channel
      }
    }

    /// https://discord.com/developers/docs/interactions/message-components#select-menu-object-select-menu-structure
    public struct ChannelSelectMenu: Sendable, Decodable, Equatable, Hashable,
      ValidatablePayload
    {
      public var custom_id: String
      public var channel_types: [DiscordChannel.Kind]?
      public var placeholder: String?
      public var default_values: [DefaultValue]?
      public var min_values: Int?
      public var max_values: Int?
      public var disabled: Bool?

      public init(
        custom_id: String,
        channel_types: [DiscordChannel.Kind]? = nil,
        placeholder: String? = nil,
        default_values: [DefaultValue]? = nil,
        min_values: Int? = nil,
        max_values: Int? = nil,
        disabled: Bool? = nil
      ) {
        self.custom_id = custom_id
        self.channel_types = channel_types
        self.placeholder = placeholder
        self.default_values = default_values
        self.min_values = min_values
        self.max_values = max_values
        self.disabled = disabled
      }

      public func validate() -> [ValidationFailure] {
        validateCharacterCountDoesNotExceed(
          custom_id,
          max: 100,
          name: "custom_id"
        )
        validateCharacterCountDoesNotExceed(
          placeholder,
          max: 150,
          name: "placeholder"
        )
        validateNumberInRangeOrNil(
          min_values,
          min: 0,
          max: 25,
          name: "min_values"
        )
        validateNumberInRangeOrNil(
          max_values,
          min: 1,
          max: 25,
          name: "max_values"
        )
      }
    }

    /// https://discord.com/developers/docs/interactions/message-components#select-menu-object-select-menu-structure
    public struct SelectMenu: Sendable, Decodable, Equatable, Hashable,
      ValidatablePayload
    {
      public var custom_id: String
      public var placeholder: String?
      public var default_values: [DefaultValue]?
      public var min_values: Int?
      public var max_values: Int?
      public var disabled: Bool?

      public init(
        custom_id: String,
        placeholder: String? = nil,
        default_values: [DefaultValue]? = nil,
        min_values: Int? = nil,
        max_values: Int? = nil,
        disabled: Bool? = nil
      ) {
        self.custom_id = custom_id
        self.placeholder = placeholder
        self.default_values = default_values
        self.min_values = min_values
        self.max_values = max_values
        self.disabled = disabled
      }

      public func validate() -> [ValidationFailure] {
        validateCharacterCountDoesNotExceed(
          custom_id,
          max: 100,
          name: "custom_id"
        )
        validateCharacterCountDoesNotExceed(
          placeholder,
          max: 150,
          name: "placeholder"
        )
        validateNumberInRangeOrNil(
          min_values,
          min: 0,
          max: 25,
          name: "min_values"
        )
        validateNumberInRangeOrNil(
          max_values,
          min: 1,
          max: 25,
          name: "max_values"
        )
        validateElementCountInRange(
          default_values,
          min: min_values ?? 0,
          max: max_values ?? .max,
          name: "default_values"
        )
      }
    }

    /// https://discord.com/developers/docs/interactions/message-components#text-inputs
    public struct TextInput: Sendable, Decodable, Equatable, Hashable,
      ValidatablePayload
    {

      /// https://discord.com/developers/docs/interactions/message-components#text-inputs-text-input-styles
      #if Non64BitSystemsCompatibility
        @UnstableEnum<Int64>
      #else
        @UnstableEnum<Int>
      #endif
      public enum Style: Sendable, Decodable {
        case short  // 1
        case paragraph  // 2
        #if Non64BitSystemsCompatibility
          case __undocumented(Int64)
        #else
          case __undocumented(Int)
        #endif
      }

      public var custom_id: String
      public var style: Style?
      public var label: String?
      public var min_length: Int?
      public var max_length: Int?
      public var required: Bool?
      public var value: String?
      public var placeholder: String?

      public init(
        custom_id: String,
        style: Style? = nil,
        label: String? = nil,
        min_length: Int? = nil,
        max_length: Int? = nil,
        required: Bool? = nil,
        value: String? = nil,
        placeholder: String? = nil
      ) {
        self.custom_id = custom_id
        self.style = style
        self.label = label
        self.min_length = min_length
        self.max_length = max_length
        self.required = required
        self.value = value
        self.placeholder = placeholder
      }

      public func validate() -> [ValidationFailure] {
        validateCharacterCountDoesNotExceed(
          custom_id,
          max: 100,
          name: "custom_id"
        )
        validateCharacterCountDoesNotExceed(label, max: 45, name: "label")
        validateNumberInRangeOrNil(
          min_length,
          min: 0,
          max: 4_000,
          name: "min_length"
        )
        validateNumberInRangeOrNil(
          max_length,
          min: 1,
          max: 4_000,
          name: "max_length"
        )
        validateCharacterCountDoesNotExceed(value, max: 4_000, name: "value")
        validateCharacterCountDoesNotExceed(
          placeholder,
          max: 100,
          name: "value"
        )
      }
    }

    public enum Component: Sendable, Decodable, Equatable, Hashable,
      ValidatablePayload
    {
      case button(Button)
      case stringSelect(StringSelectMenu)
      case textInput(TextInput)
      case userSelect(SelectMenu)
      case roleSelect(SelectMenu)
      case mentionableSelect(SelectMenu)
      case channelSelect(ChannelSelectMenu)
      case __undocumented

      public var customId: String? {
        switch self {
        case .button(let value):
          return value.custom_id
        case .stringSelect(let value):
          return value.custom_id
        case .textInput(let value):
          return value.custom_id
        case .userSelect(let value):
          return value.custom_id
        case .roleSelect(let value):
          return value.custom_id
        case .mentionableSelect(let value):
          return value.custom_id
        case .channelSelect(let value):
          return value.custom_id
        case .__undocumented:
          return nil
        }
      }

      enum CodingKeys: String, CodingKey {
        case type
      }

      public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .actionRow:
          throw CodingError.actionRowIsSupposedToOnlyAppearAtTopLevel
        case .button:
          self = try .button(.init(from: decoder))
        case .stringSelect:
          self = try .stringSelect(.init(from: decoder))
        case .userSelect:
          self = try .userSelect(.init(from: decoder))
        case .roleSelect:
          self = try .roleSelect(.init(from: decoder))
        case .mentionableSelect:
          self = try .mentionableSelect(.init(from: decoder))
        case .channelSelect:
          self = try .channelSelect(.init(from: decoder))
        case .textInput:
          self = try .textInput(.init(from: decoder))
        case .label:
          self = .__undocumented
        case .fileUpload:
          self = .__undocumented
        case .section:
          self = .__undocumented
        case .textDisplay:
          self = .__undocumented
        case .thumbnail:
          self = .__undocumented
        case .mediaGallery:
          self = .__undocumented
        case .file:
          self = .__undocumented
        case .separator:
          self = .__undocumented
        case .contentInventoryEntry:
          self = .__undocumented
        case .container:
          self = .__undocumented
        case .__undocumented:
          self = .__undocumented
        }
      }


      public func validate() -> [ValidationFailure] {
        switch self {
        case .button(let button):
          button.validate()
        case .stringSelect(let stringSelectMenu):
          stringSelectMenu.validate()
        case .textInput(let textInput):
          textInput.validate()
        case .userSelect(let selectMenu):
          selectMenu.validate()
        case .roleSelect(let selectMenu):
          selectMenu.validate()
        case .mentionableSelect(let selectMenu):
          selectMenu.validate()
        case .channelSelect(let channelSelectMenu):
          channelSelectMenu.validate()
        case .__undocumented:
          Optional<ValidationFailure>.none
        }
      }
    }

    public var components: [Component]

    public enum CodingError: Swift.Error, CustomStringConvertible {
      /// This component kind was not expected here. This is a library decoding issue.
      case unexpectedComponentKind(Kind)
      /// I thought action-row is supposed to only appear at top-level as a container for other components. This is a library decoding issue.
      case actionRowIsSupposedToOnlyAppearAtTopLevel

      public var description: String {
        switch self {
        case .unexpectedComponentKind(let kind):
          return
            "Interaction.ActionRow.CodingError.unexpectedComponentKind(\(kind))"
        case .actionRowIsSupposedToOnlyAppearAtTopLevel:
          return
            "Interaction.ActionRow.CodingError.actionRowIsSupposedToOnlyAppearAtTopLevel"
        }
      }
    }

    enum CodingKeys: String, CodingKey {
      case type
      case components
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let type = try container.decode(Kind.self, forKey: .type)
      guard type == .actionRow else {
        throw CodingError.unexpectedComponentKind(type)
      }
      self.components = try container.decode(
        [Component].self,
        forKey: .components
      )
    }


    public init(components: [Component]) {
      self.components = components
    }

    public init(arrayLiteral elements: Component...) {
      self.components = elements
    }

    /// Returns the component with the `customId`, or `nil`.
    @inlinable
    public func component(customId: String) -> Component? {
      self.components.first(where: { $0.customId == customId })
    }

    public func validate() -> [ValidationFailure] {
      components.validate()
    }
  }
}
