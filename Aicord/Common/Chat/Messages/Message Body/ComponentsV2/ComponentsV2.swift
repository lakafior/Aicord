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
  /// action rows. Link buttons open their URL; other buttons and selects send
  /// an interaction to the bot (`BotInteractions`).
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
        ComponentActionRow(components: children, message: message, channelStore: channelStore)
      case .button(let button):
        ComponentButton(button: button, message: message, channelStore: channelStore)
      case .select(let select):
        ComponentSelect(select: select, message: message, channelStore: channelStore)
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
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore

    var body: some View {
      // buttons wrap like Discord's; a select takes the whole row
      FlowLayout(spacing: 8) {
        ForEach(Array(components.enumerated()), id: \.offset) { _, component in
          switch component {
          case .button(let button):
            ComponentButton(button: button, message: message, channelStore: channelStore)
          case .select(let select):
            ComponentSelect(select: select, message: message, channelStore: channelStore)
          default: EmptyView()
          }
        }
      }
    }
  }

  struct ComponentButton: View {
    @Environment(\.openURL) var openURL
    @Environment(\.gateway) var gw
    var button: Interaction.ActionRow.Button
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore

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

    private var isSending: Bool {
      button.custom_id.map { BotInteractions.shared.isSending(message.id, $0) } ?? false
    }

    var body: some View {
      let isSending = isSending
      // premium buttons open a store page Aicord doesn't have
      let isDisabled =
        button.disabled == true || button.style == .premium
        || (linkURL == nil && button.custom_id == nil)
      Button {
        if let linkURL {
          openURL(linkURL)
        } else if let customID = button.custom_id {
          BotInteractions.shared.send(
            componentType: 2, customID: customID, message: message, channel: channelStore, gw: gw)
        }
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
        .opacity(isSending ? 0 : 1)
        .overlay {
          if isSending {
            ProgressView()
              .controlSize(.small)
              .tint(.white)
          }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(background, in: .rect(cornerRadius: 6))
        .opacity(isDisabled ? 0.5 : 1)
      }
      .buttonStyle(.plain)
      .disabled(isDisabled || isSending)
      .help(linkURL == nil ? Text(verbatim: button.label ?? "") : Text(verbatim: button.url ?? ""))
      .accessibilityValue(isSending ? Text("Sending") : Text(verbatim: ""))
    }
  }

  /// A select menu: its placeholder, default or picked values; tapping opens
  /// the list and a pick goes to the bot.
  struct ComponentSelect: View {
    @Environment(\.theme) var theme
    @Environment(\.gateway) var gw
    var select: Interaction.MessageComponent.Select
    var message: DiscordChannel.PartialMessage
    var channelStore: ChannelStore
    @State private var picking = false

    var body: some View {
      let interactions = BotInteractions.shared
      let isSending = interactions.isSending(message.id, select.custom_id)
      let choices = SelectChoice.choices(for: select, channel: channelStore, gw: gw)
      let defaults = choices.filter(\.isDefault)
      let selected = interactions.pickedLabels(message, select.custom_id) ?? defaults.map(\.label)
      Button {
        picking = true
      } label: {
        HStack {
          Text(
            selected.isEmpty
              ? (select.placeholder ?? String(localized: "Make a selection"))
              : selected.joined(separator: ", ")
          )
          .lineLimit(1)
          .foregroundStyle(selected.isEmpty ? .secondary : .primary)
          Spacer(minLength: 8)
          if isSending {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: "chevron.down")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 400)
        .background(theme.common.tertiaryBackground, in: .rect(cornerRadius: 6))
        // inside a container the card has the same background
        .overlay(.quaternary, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .disabled(select.disabled || isSending)
      .opacity(select.disabled ? 0.5 : 1)
      .sheet(isPresented: $picking) {
        SelectPickerSheet(
          select: select, choices: choices, initial: Set(defaults.map(\.value))
        ) { picked in
          BotInteractions.shared.send(
            componentType: select.type, customID: select.custom_id, values: picked.map(\.value),
            labels: picked.map(\.label), message: message, channel: channelStore, gw: gw)
        }
      }
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
