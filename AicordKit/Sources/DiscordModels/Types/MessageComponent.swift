//
//  MessageComponent.swift
//  AicordKit
//

import Foundation

extension Interaction {
  /// One node of a message's component tree: a components v2 layout, or a v1 action row.
  /// Decoding is lossy: a component of an unknown type, or one that fails to decode,
  /// becomes `.unknown` instead of failing the whole message.
  /// https://docs.discord.food/resources/components
  public indirect enum MessageComponent: Sendable, Decodable, Equatable, Hashable {
    case actionRow([MessageComponent])
    case button(ActionRow.Button)
    case select(Select)
    case section(Section)
    case textDisplay(TextDisplay)
    case thumbnail(Thumbnail)
    case mediaGallery(MediaGallery)
    case file(File)
    case separator(Separator)
    case container(Container)
    case unknown(Int)

    /// A media reference: an arbitrary URL or an `attachment://` one, resolved on receive.
    public struct UnfurledMedia: Sendable, Decodable, Equatable, Hashable {
      public var url: String
      public var proxy_url: String?
      public var width: Int?
      public var height: Int?
      public var content_type: String?
      public var attachment_id: AttachmentSnowflake?

      enum CodingKeys: String, CodingKey {
        case url, proxy_url, width, height, content_type, attachment_id
      }

      public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        proxy_url = try? container.decode(String.self, forKey: .proxy_url)
        // media still loading comes with 0×0, which would make a 0 or infinite aspect ratio
        width = (try? container.decode(Int.self, forKey: .width)).flatMap { $0 > 0 ? $0 : nil }
        height = (try? container.decode(Int.self, forKey: .height)).flatMap { $0 > 0 ? $0 : nil }
        content_type = try? container.decode(String.self, forKey: .content_type)
        attachment_id = try? container.decode(AttachmentSnowflake.self, forKey: .attachment_id)
      }
    }

    /// A select menu of any kind, kept for display only.
    public struct Select: Sendable, Equatable, Hashable {
      public var placeholder: String?
      public var options: [ActionRow.StringSelectMenu.Option]
      public var disabled: Bool
    }

    public struct Section: Sendable, Decodable, Equatable, Hashable {
      /// Text displays, one to three.
      public var components: [MessageComponent]
      /// A thumbnail or a button beside the text.
      public var accessory: MessageComponent?
    }

    public struct TextDisplay: Sendable, Decodable, Equatable, Hashable {
      public var content: String
    }

    public struct Thumbnail: Sendable, Decodable, Equatable, Hashable {
      public var media: UnfurledMedia
      public var description: String?
      public var spoiler: Bool?
    }

    public struct MediaGallery: Sendable, Decodable, Equatable, Hashable {
      public struct Item: Sendable, Decodable, Equatable, Hashable {
        public var media: UnfurledMedia
        public var description: String?
        public var spoiler: Bool?
      }
      public var items: [Item]
    }

    public struct File: Sendable, Decodable, Equatable, Hashable {
      public var file: UnfurledMedia
      public var spoiler: Bool?
      public var name: String?
      public var size: Int?
    }

    public struct Separator: Sendable, Decodable, Equatable, Hashable {
      public var divider: Bool?
      /// 1 small, 2 large.
      public var spacing: Int?
    }

    public struct Container: Sendable, Decodable, Equatable, Hashable {
      public var components: [MessageComponent]
      /// RGB integer for the bar on the leading edge.
      public var accent_color: Int?
      public var spoiler: Bool?
    }

    enum CodingKeys: String, CodingKey {
      case type, components, placeholder, options, disabled
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let type = (try? container.decode(Int.self, forKey: .type)) ?? 0
      do {
        switch type {
        case 1:
          self = .actionRow(
            try container.decode([Lossy].self, forKey: .components).map(\.value))
        case 2: self = .button(try .init(from: decoder))
        case 3, 5, 6, 7, 8:
          self = .select(
            Select(
              placeholder: try? container.decode(String.self, forKey: .placeholder),
              options: (try? container.decode(
                [ActionRow.StringSelectMenu.Option].self, forKey: .options)) ?? [],
              disabled: (try? container.decode(Bool.self, forKey: .disabled)) ?? false
            ))
        case 9: self = .section(try .init(from: decoder))
        case 10: self = .textDisplay(try .init(from: decoder))
        case 11: self = .thumbnail(try .init(from: decoder))
        case 12: self = .mediaGallery(try .init(from: decoder))
        case 13: self = .file(try .init(from: decoder))
        case 14: self = .separator(try .init(from: decoder))
        case 17: self = .container(try .init(from: decoder))
        default: self = .unknown(type)
        }
      } catch {
        self = .unknown(type)
      }
    }

    /// Decodes one array element without letting it fail its siblings.
    struct Lossy: Decodable {
      var value: MessageComponent
      init(from decoder: any Decoder) throws {
        value = (try? MessageComponent(from: decoder)) ?? .unknown(0)
      }
    }
  }
}

extension Interaction.MessageComponent.Section {
  enum CodingKeys: String, CodingKey { case components, accessory }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    components = try container.decode([Interaction.MessageComponent.Lossy].self, forKey: .components)
      .map(\.value)
    accessory = try? container.decode(Interaction.MessageComponent.self, forKey: .accessory)
  }
}

extension Interaction.MessageComponent.Container {
  enum CodingKeys: String, CodingKey { case components, accent_color, spoiler }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    components = try container.decode([Interaction.MessageComponent.Lossy].self, forKey: .components)
      .map(\.value)
    accent_color = try? container.decode(Int.self, forKey: .accent_color)
    spoiler = try? container.decode(Bool.self, forKey: .spoiler)
  }
}

extension Interaction.MessageComponent {
  /// A v1 action row as a tree node, so both kinds render the same way.
  init(_ row: Interaction.ActionRow) {
    self = .actionRow(
      row.components.map { component in
        switch component {
        case .button(let button):
          return .button(button)
        case .stringSelect(let menu):
          return .select(
            Select(
              placeholder: menu.placeholder, options: menu.options,
              disabled: menu.disabled ?? false))
        case .userSelect(let menu), .roleSelect(let menu), .mentionableSelect(let menu):
          return .select(
            Select(placeholder: menu.placeholder, options: [], disabled: menu.disabled ?? false))
        case .channelSelect(let menu):
          return .select(
            Select(placeholder: menu.placeholder, options: [], disabled: menu.disabled ?? false))
        case .textInput, .__undocumented:
          return .unknown(0)
        }
      })
  }
}
