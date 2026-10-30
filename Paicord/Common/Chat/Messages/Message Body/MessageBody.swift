//
//  MessageBody.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 11/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

extension MessageCell {
  struct MessageBody: View {
    let message: DiscordChannel.PartialMessage  // to allow both message types

    init(
      message: DiscordChannel.Message,
      channelStore: ChannelStore
    ) {
      self.message = message.toPartialMessage()
      self.channelStore = channelStore
    }

    init(
      message: DiscordChannel.PartialMessage,
      channelStore: ChannelStore,
      isSnapshot: Bool = false
    ) {
      self.message = message
      self.channelStore = channelStore
      self.isSnapshot = isSnapshot
    }

    let channelStore: ChannelStore
    /// A forwarded copy: it shares the original's ID, so the original's
    /// reactions must not show on it.
    var isSnapshot = false

    @AppStorage(WordFilter.Key.enabled) private var wordFilterEnabled = false
    @AppStorage(WordFilter.Key.languages) private var wordFilterLanguages =
      WordFilter.defaultLanguages
    @AppStorage(WordFilter.Key.customWords) private var wordFilterCustomWords = ""
    @AppStorage(WordFilter.Key.scope) private var wordFilterScope = WordFilter.Scope
      .nonFriendDMs
    @State private var revealsFilteredMessage = false

    var body: some View {
      if hiddenByWordFilter {
        HiddenContentNote(text: "Hidden by your word filter") {
          revealsFilteredMessage = true
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        content
      }
    }

    /// The community word list from Settings → Content & Social.
    private var hiddenByWordFilter: Bool {
      guard wordFilterEnabled, !revealsFilteredMessage,
        let origin = channelStore.origin(of: message),
        wordFilterScope == .everywhere || origin == .otherDM
      else { return false }
      return WordFilter.shared.matches(
        message.content ?? "",
        languages: wordFilterLanguages,
        customWords: wordFilterCustomWords
      )
    }

    private var mediaFilter: MediaFilter {
      MediaFilter(
        origin: channelStore.origin(of: message),
        settings: channelStore.gateway?.settings.userSettings ?? .init()
      )
    }

    @ViewBuilder
    private var content: some View {
      let mediaFilter = mediaFilter
      VStack(alignment: .leading, spacing: 4) {
        // Content
        Group {
          if !messageContentHidden {
            let content = message.content ?? ""
            if message.flags?.contains(.isComponentsV2) == true {
              ComponentsV2View( /*components: message.components*/)
                .equatable(by: message.components)
            } else if !content.isEmpty {
              MarkdownText(
                content: content,
                channelStore: channelStore,
                allowsJumboEmoji: true
              )
            }
          }
        }

        // Attachments, flagged ones blurred or left out per Content & Social
        let attachments = Dictionary(
          grouping: message.attachments ?? [],
          by: mediaFilter.redaction(for:)
        )
        if let shown = attachments[.show] {
          // Spoiler-marked ones covered unless the Chat setting reveals them
          let isCovered = { (attachment: DiscordChannel.Message.Attachment) in
            !revealsSpoilers
              && (attachment.flags?.contains(.isSpoiler) == true
                || attachment.filename.hasPrefix("SPOILER_"))
          }
          let spoilers = shown.filter(isCovered)
          let plain = shown.filter { !isCovered($0) }
          if !plain.isEmpty {
            AttachmentsView(message: message, attachments: plain)
          }
          if !spoilers.isEmpty {
            SensitiveMediaCover(title: "Spoiler", systemImage: "eye.trianglebadge.exclamationmark") {
              AttachmentsView(message: message, attachments: spoilers)
            }
          }
        }
        if let blurred = attachments[.blur] {
          SensitiveMediaCover {
            AttachmentsView(message: message, attachments: blurred)
          }
        }

        // Embeds, left out or without link media per the Chat settings
        let embeds = Dictionary(
          grouping: visibleEmbeds,
          by: mediaFilter.redaction(for:)
        )
        if let shown = embeds[.show] {
          EmbedsView(embeds: shown, message: message)
        }
        if let blurred = embeds[.blur] {
          SensitiveMediaCover {
            EmbedsView(embeds: blurred, message: message)
          }
        }

        let blocked = (attachments[.block]?.count ?? 0) + (embeds[.block]?.count ?? 0)
        if blocked > 0 {
          HiddenContentNote(text: "^[\(blocked) item](inflect: true) blocked by your content settings")
        }

        // Stickers
        if let stickers = message.sticker_items, !stickers.isEmpty {
          StickersView(stickers: stickers)
        }

        // Reactions
        let reactions = isSnapshot ? [:] : channelStore.reactions[message.id, default: [:]]
        if !reactions.isEmpty, settings?.rendersReactions ?? true {
          ReactionsView(reactions: reactions)
        }

        if let msgSnapshot = message.partialMessageForSnapshot() {
          VStack(alignment: .leading, spacing: 4) {
            Group {
              Text("\(Image(systemName: "arrowshape.turn.up.right.fill")) \(Text("Forwarded").italic())")
            }
            .font(.caption.italic())
            .foregroundStyle(.tertiary)

            MessageBody(
              message: msgSnapshot,
              channelStore: channelStore,
              isSnapshot: true
            )

            if let reference = message.message_reference {
              ForwardSource(reference: reference, timestamp: msgSnapshot.timestamp)
            }
          }
          .padding(.leading, 12)
          .overlay(
            Rectangle()
              .frame(width: 3)
              .foregroundStyle(.quaternary)
              .clipShape(.capsule),
            alignment: .leading
          )
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settings: SettingsStore? { channelStore.gateway?.settings }

    private var revealsSpoilers: Bool {
      settings?.revealsSpoilers(in: channelStore) ?? false
    }

    /// Embeds after Discord's "show embeds" and "show media posted as links".
    private var visibleEmbeds: [Embed] {
      guard settings?.rendersEmbeds ?? true else { return [] }
      guard settings?.inlinesEmbedMedia ?? true else {
        return (message.embeds ?? []).filter { embed in
          embed.type.map { !Self.linkMediaKinds.contains($0) } ?? true
        }
      }
      return message.embeds ?? []
    }

    private static let linkMediaKinds: [Embed.Kind] = [.image, .gifv, .video]

    /// Determines if the message content should be hidden based on things like if the embed is a gif.
    var messageContentHidden: Bool {
      if visibleEmbeds.count == 1,  // only one embed shown
        let embed = visibleEmbeds.first,  // get that first embed
        [Embed.Kind.image, .gifv, .video].contains(embed.type),  // is of type image, gifv or video
        let url = embed.url,
        message.content?.trimmingCharacters(in: .whitespacesAndNewlines) == url  // ensure content is just the url
      {
        return true  // then hide the content
      }
      return false
    }
  }
}

#Preview {
  @Previewable @State var yea = false
  Text("gm")
    .popover(isPresented: $yea) {
      MarkdownText.EmojiDetailsView.init(
        emoji: .init(id: .init("724374128777494608"), name: "AyameLove"))
    }
    .onAppear {
      yea = true
    }
}

/// Where a forwarded message came from: the channel (or DM) and when it was
/// written. Tapping it opens the original, when you can still see it.
private struct ForwardSource: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  let reference: DiscordChannel.Message.MessageReference
  let timestamp: DiscordTimestamp?

  var place: String? {
    guard let channelID = reference.channel_id else { return nil }
    if let guildID = reference.guild_id {
      guard let guild = gw.user.guilds[guildID] else {
        return String(localized: "Another server")
      }
      let channel = guild.channels?.first { $0.id == channelID }?.name
      return [channel.map { "#\($0)" }, guild.name].compactMap { $0 }.joined(separator: " · ")
    }
    if let dm = gw.user.privateChannels[channelID] {
      return MessagesView.title(of: dm)
    }
    return String(localized: "Direct Message")
  }

  /// Only places you are in can be opened.
  var canOpen: Bool {
    guard let channelID = reference.channel_id, reference.message_id != nil else { return false }
    if let guildID = reference.guild_id {
      return gw.user.guilds[guildID]?.channels?.contains { $0.id == channelID } == true
    }
    return gw.user.privateChannels[channelID] != nil
  }

  var body: some View {
    let label = HStack(spacing: 4) {
      if let place { Text(place).lineLimit(1) }
      if let date = timestamp?.date {
        Text("·")
        Text(date, format: .dateTime.day().month().year().hour().minute())
      }
      if canOpen {
        Image(systemName: "chevron.right")
          .imageScale(.small)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)

    if canOpen, let channelID = reference.channel_id, let messageID = reference.message_id {
      Button {
        appState.open(guild: reference.guild_id, channel: channelID, message: messageID)
      } label: {
        label
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text("Open the original message"))
    } else {
      label
    }
  }
}
