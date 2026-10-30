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
      channelStore: ChannelStore
    ) {
      self.message = message
      self.channelStore = channelStore
    }

    let channelStore: ChannelStore

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
          AttachmentsView(message: message, attachments: shown)
        }
        if let blurred = attachments[.blur] {
          SensitiveMediaCover {
            AttachmentsView(message: message, attachments: blurred)
          }
        }

        // Embeds
        let embeds = Dictionary(
          grouping: message.embeds ?? [],
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
        let reactions = channelStore.reactions[message.id, default: [:]]
        if !reactions.isEmpty {
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
              channelStore: channelStore
            )
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

    /// Determines if the message content should be hidden based on things like if the embed is a gif.
    var messageContentHidden: Bool {
      if message.embeds?.count == 1,  // only one embed
        let embed = message.embeds?.first,  // get that first embed
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
