//
//  ComponentsV2.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 12/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension MessageCell {
  /// A message's component tree: containers, sections, text, media, files and
  /// action rows. Link buttons open their URL; the client has no way to send
  /// interactions, so other buttons and selects are shown but do nothing.
  struct ComponentsV2View: View {
    var components: [Interaction.MessageComponent]
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
          ComponentView(component: component, message: message, channelStore: channelStore)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  struct ComponentView: View {
    var component: Interaction.MessageComponent
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore

    var body: some View {
      switch component {
      case .container(let container):
        ComponentContainerView(container: container, message: message, channelStore: channelStore)
      case .section(let section):
        HStack(alignment: .top, spacing: 12) {
          ComponentsV2View(components: section.components, message: message, channelStore: channelStore)
          if let accessory = section.accessory {
            ComponentView(component: accessory, message: message, channelStore: channelStore)
              .fixedSize()
          }
        }
      case .textDisplay(let text):
        MarkdownText(content: text.content, channelStore: channelStore)
      case .thumbnail(let thumbnail):
        ComponentMediaTile(
          media: thumbnail.media, description: thumbnail.description,
          isSpoiler: thumbnail.spoiler == true, gallery: [thumbnail.media], message: message
        )
        .frame(width: 85, height: 85)
      case .mediaGallery(let gallery):
        ComponentGalleryView(gallery: gallery, message: message)
      case .file(let file):
        ComponentFileView(file: file, message: message)
      case .separator(let separator):
        let large = separator.spacing == 2
        if separator.divider ?? true {
          Divider().padding(.vertical, large ? 8 : 2)
        } else {
          Spacer().frame(height: large ? 24 : 8)
        }
      case .actionRow(let children):
        ComponentActionRow(components: children)
      case .button(let button):
        ComponentButton(button: button)
      case .select(let select):
        ComponentSelect(select: select)
      case .unknown:
        // types Discord adds later
        EmptyView()
      }
    }
  }

  /// Discord's card: a rounded box with an optional accent bar on the leading edge.
  struct ComponentContainerView: View {
    @Environment(\.theme) var theme
    var container: Interaction.MessageComponent.Container
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore

    var body: some View {
      let content = ComponentsV2View(
        components: container.components, message: message, channelStore: channelStore
      )
      .padding(12)
      HStack(spacing: 0) {
        if let accent = container.accent_color {
          Color(hexadecimal6: accent)
            .frame(width: 4)
        }
        if container.spoiler == true {
          SensitiveMediaCover(title: "Spoiler", systemImage: "eye.trianglebadge.exclamationmark") {
            content
          }
        } else {
          content
        }
      }
      .frame(maxWidth: 500, alignment: .leading)
      .background(theme.common.tertiaryBackground)
      .clipShape(.rounded)
    }
  }

  struct ComponentGalleryView: View {
    var gallery: Interaction.MessageComponent.MediaGallery
    var message: DiscordChannel.PartialMessage

    var body: some View {
      let media = gallery.items.map(\.media)
      if gallery.items.count == 1, let item = gallery.items.first {
        AttachmentsView.AttachmentSizedView(attachment: item.media) {
          ComponentMediaTile(
            media: item.media, description: item.description, isSpoiler: item.spoiler == true,
            gallery: media, message: message)
        }
      } else {
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: 4), count: gallery.items.count == 2 ? 2 : 3),
          spacing: 4
        ) {
          ForEach(Array(gallery.items.enumerated()), id: \.offset) { index, item in
            Color.clear
              .aspectRatio(1, contentMode: .fit)
              .overlay {
                ComponentMediaTile(
                  media: item.media, description: item.description,
                  isSpoiler: item.spoiler == true, gallery: media, startIndex: index,
                  message: message, fills: true)
              }
              .clipShape(.rect(cornerRadius: 4))
          }
        }
        .frame(maxWidth: 500)
      }
    }
  }

  /// An image or video from a component; tapping opens the viewer on its gallery.
  struct ComponentMediaTile: View {
    @Environment(\.appState) var appState
    var media: Interaction.MessageComponent.UnfurledMedia
    var description: String?
    var isSpoiler: Bool
    var gallery: [Interaction.MessageComponent.UnfurledMedia]
    var startIndex = 0
    var message: DiscordChannel.PartialMessage
    var fills = false

    var body: some View {
      let tile = Button {
        appState.attachmentViewerAttachments = gallery
        appState.attachmentViewerIndex = startIndex
        appState.attachmentViewerContextMessage = message
        appState.showingAttachmentViewer = true
      } label: {
        AttachmentsView.AttachmentItemPreview(attachment: media)
          .displayMode(asPoster: true)
          .aspectRatio(contentMode: fills ? .fill : .fit)
          .clipShape(.rounded)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(Text(description ?? String(localized: "Image")))
      if isSpoiler {
        SensitiveMediaCover(title: "Spoiler", systemImage: "eye.trianglebadge.exclamationmark") {
          tile
        }
      } else {
        tile
      }
    }
  }

  /// A file component: the message attachment it points at, or a plain row.
  struct ComponentFileView: View {
    @Environment(\.openURL) var openURL
    var file: Interaction.MessageComponent.File
    var message: DiscordChannel.PartialMessage

    private var attachment: DiscordChannel.Message.Attachment? {
      let attachments = message.attachments ?? []
      if let id = file.file.attachment_id, let match = attachments.first(where: { $0.id == id }) {
        return match
      }
      let name = file.file.url.replacingOccurrences(of: "attachment://", with: "")
      return attachments.first { $0.filename == name || $0.url == file.file.url }
    }

    var body: some View {
      if let attachment {
        AttachmentsView.FileAttachmentView(attachment: attachment)
      } else {
        Button {
          if let url = URL(string: file.file.proxy_url ?? file.file.url) { openURL(url) }
        } label: {
          Label {
            VStack(alignment: .leading) {
              Text(file.name ?? file.file.url)
                .font(.headline)
              if let size = file.size {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                  .font(.caption)
                  .foregroundStyle(.tertiary)
              }
            }
          } icon: {
            Image(systemName: "doc")
          }
        }
        .buttonStyle(.plain)
      }
    }
  }

  struct ComponentActionRow: View {
    var components: [Interaction.MessageComponent]

    var body: some View {
      // buttons wrap like Discord's; a select takes the whole row
      FlowLayout(spacing: 8) {
        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
          switch component {
          case .button(let button): ComponentButton(button: button)
          case .select(let select): ComponentSelect(select: select)
          default: EmptyView()
          }
        }
      }
    }
  }

  struct ComponentButton: View {
    @Environment(\.openURL) var openURL
    var button: Interaction.ActionRow.Button

    private var linkURL: URL? {
      guard button.style == .link, let url = button.url else { return nil }
      return URL(string: url)
    }

    private var background: Color {
      switch button.style {
      case .primary: Color(hexadecimal6: 0x5865F2)
      case .success: Color(hexadecimal6: 0x248046)
      case .danger: Color(hexadecimal6: 0xDA373C)
      case .premium: Color(hexadecimal6: 0xA855F7)
      default: Color(hexadecimal6: 0x4E5058)
      }
    }

    var body: some View {
      let isDisabled = button.disabled == true || linkURL == nil
      Button {
        if let linkURL { openURL(linkURL) }
      } label: {
        HStack(spacing: 6) {
          if let emoji = button.emoji {
            ComponentEmoji(emoji: emoji)
          }
          if let label = button.label {
            Text(label)
              .lineLimit(1)
          }
          if linkURL != nil {
            Image(systemName: "arrow.up.right.square")
              .font(.caption)
          }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(background, in: .rect(cornerRadius: 6))
        .opacity(button.disabled == true ? 0.5 : 1)
      }
      .buttonStyle(.plain)
      .disabled(isDisabled)
      .help(
        linkURL == nil
          ? Text("Aicord can't use bot buttons yet") : Text(verbatim: button.url ?? ""))
    }
  }

  /// A select menu, shown as its placeholder or default choice; it can't be used.
  struct ComponentSelect: View {
    @Environment(\.theme) var theme
    var select: Interaction.MessageComponent.Select

    var body: some View {
      let selected = select.options.filter { $0.default == true }.map(\.label)
      HStack {
        Text(
          selected.isEmpty
            ? (select.placeholder ?? String(localized: "Make a selection"))
            : selected.joined(separator: ", ")
        )
        .lineLimit(1)
        .foregroundStyle(selected.isEmpty ? .secondary : .primary)
        Spacer(minLength: 8)
        Image(systemName: "chevron.down")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .frame(maxWidth: 400)
      .background(theme.common.tertiaryBackground, in: .rect(cornerRadius: 6))
      .opacity(select.disabled ? 0.5 : 1)
      .accessibilityElement(children: .combine)
      .accessibilityHint(Text("Aicord can't use bot menus yet"))
    }
  }

  struct ComponentEmoji: View {
    var emoji: Emoji

    var body: some View {
      if let id = emoji.id,
        let url = DiscordImageURL.customEmoji(id: id, animated: emoji.animated ?? false)
      {
        NukeImage(url: url)
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
      } else if let name = emoji.name {
        Text(name)
      }
    }
  }
}

extension Interaction.MessageComponent.UnfurledMedia: DiscordMedia {
  var proxyurl: String { proxy_url ?? url }
  var cdnURL: String { url }
  var placeholder: String? { nil }
}
