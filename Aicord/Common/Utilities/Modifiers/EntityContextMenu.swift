//
//  EntityContextMenu.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 06/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension View {
  func entityContextMenu<Entity>(
    for entity: Entity,
    case: EntityContextMenuUseCase? = nil
  ) -> some View {
    self
      .modifier(EntityContextMenu<Entity>(entity: entity))
  }
}

enum EntityContextMenuUseCase {
  case channelFromDMsScroller
  case channelFromGuildScroller
}

struct EntityContextMenu<Entity>: ViewModifier {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.guildStore) var guild
  @Environment(\.channelStore) var channel

  var settings: DiscordProtos_DiscordUsers_V1_PreloadedUserSettings {
    gw.settings.userSettings
  }

  var entity: Entity

  func body(content: Content) -> some View {
    content
      .contextMenu {
        switch entity {
        case let user as PartialUser:
          userContextMenu(user: user)
        case let message as DiscordChannel.Message:
          messageContextMenu(message: message)
        default: EmptyView()
        }
      }
  }

  @ViewBuilder
  func messageContextMenu(message: DiscordChannel.Message) -> some View {
    if hasPermission(.addReactions) {
      let target = ReactionPickerTarget(message: message, guildID: guild?.guildId)
      ControlGroup {
        ForEach(quickReactions, id: \.self) { character in
          Button {
            target.react(with: .init(name: character), gw: gw, appState: appState)
          } label: {
            Text(verbatim: character)
          }
        }
        Button {
          appState.reactionPickerTarget = target
        } label: {
          Label("Add Reaction", systemImage: "face.smiling")
        }
      }
      .controlGroupStyle(.palette)
    }

    Section {
      if hasPermission(.sendMessages) {
        Button {
          guard let channel else { return }
          let vm = ChatView.InputBar.vm(for: channel)
          vm.messageAction = .reply(message: message, mention: true)
        } label: {
          Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
      }
      if messageIsFromSelf(message) {
        Button {
          guard let channel else { return }
          let vm = ChatView.InputBar.vm(for: channel)
          vm.messageAction = .edit(message: message)
        } label: {
          Label("Edit Message", systemImage: "pencil")
        }
      }
      if let authorID = message.author?.id {
        Button {
          guard let channel else { return }
          let vm = ChatView.InputBar.vm(for: channel)
          vm.content += "<@\(authorID.rawValue)> "
        } label: {
          Label("Mention", systemImage: "at")
        }
      }
      if ForwardTarget.canForward(message) {
        Button {
          appState.forwardTarget = ForwardTarget(message: message, guildID: guild?.guildId)
        } label: {
          Label("Forward", systemImage: "arrowshape.turn.up.right")
        }
      }
      if message.replyParentID != nil {
        Button {
          appState.replyThreadTarget = ReplyThreadTarget(message: message, guildID: guild?.guildId)
        } label: {
          Label("Show Thread", systemImage: "bubble.left.and.bubble.right")
        }
      }
    }

    Section {
      if !message.content.isEmpty {
        Button {
          copyText(message.content)
        } label: {
          Label("Copy Text", systemImage: "doc.on.doc")
        }
        #if !os(visionOS)
          translateButton(message)
        #endif
      }
      Button {
        let guildID = appState.selectedGuild?.rawValue ?? "@me"
        let channelID = message.channel_id.rawValue
        let messageID = message.id.rawValue
        copyText(
          "https://discord.com/channels/\(guildID)/\(channelID)/\(messageID)"
        )
      } label: {
        Label("Copy Message Link", systemImage: "link")
      }
      if isDeveloperModeEnabled() {
        Button {
          copyText(message.id.rawValue)
        } label: {
          Label("Copy Message ID", systemImage: "circle.grid.2x1.right.filled")
        }
        if let authorID = message.author?.id.rawValue {
          Button {
            copyText(authorID)
          } label: {
            Label("Copy Author ID", systemImage: "circle.grid.2x1.right.filled")
          }
        }
      }
    }

    intelligenceSection(message)

    Section {
      Button {
        Task {
          do {
            try await gw.readStates.markUnread(
              channelId: message.channel_id,
              from: message.id
            )
          } catch {
            appState.error = error
          }
        }
      } label: {
        Label("Mark Unread", systemImage: "envelope.badge")
      }
    }

    if messageIsFromSelf(message) || hasPermission(.manageMessages) {
      Section {
        #if os(iOS)
          Menu {
            Section {
              deleteMessageButton(message)
            } header: {
              Text("Are you sure?")
            }
          } label: {
            Label("Delete Message", systemImage: "trash")
          }
        #elseif os(macOS)
          deleteMessageButton(message)
        #endif
      }
    }
  }

  /// Read-only language model help for this message; in DMs only when allowed.
  @ViewBuilder
  func intelligenceSection(_ message: DiscordChannel.Message) -> some View {
    let isDM = guild == nil
    if !isDM || IntelligencePreferences.allowsDMs {
      let open = { (kind: MessageIntelligenceTarget.Kind) in
        appState.messageIntelligenceTarget = MessageIntelligenceTarget(
          kind: kind, message: message, guildID: guild?.guildId)
      }
      Menu {
        Button {
          open(.context)
        } label: {
          Label("Explain Context", systemImage: "point.3.connected.trianglepath.dotted")
        }
        if !message.content.isEmpty {
          Button {
            open(.explain)
          } label: {
            Label("Explain Slang and Terms", systemImage: "character.book.closed")
          }
        }
        if message.attachments.contains(where: { $0.content_type?.hasPrefix("image") == true }) {
          Button {
            open(.images)
          } label: {
            Label("Describe Images", systemImage: "photo.badge.magnifyingglass")
          }
        }
        if message.thread != nil || message.message_reference?.message_id != nil {
          Button {
            open(.replies)
          } label: {
            Label(
              message.thread != nil ? "Summarize Thread" : "Summarize Replies",
              systemImage: "text.line.first.and.arrowtriangle.forward")
          }
        }
      } label: {
        Label("Intelligence", systemImage: "sparkles")
      }
    }
  }

  #if !os(visionOS)
    /// On-device translation, shown under the message; again to take it away.
    @ViewBuilder
    func translateButton(_ message: DiscordChannel.Message) -> some View {
      let translator = MessageTranslator.shared
      if translator.isShowing(message.id) {
        Button {
          translator.hide(message.id)
        } label: {
          Label("Show Original", systemImage: "translate")
        }
      } else {
        Button {
          translator.translate(message.toPartialMessage())
        } label: {
          Label("Translate", systemImage: "translate")
        }
      }
    }
  #endif

  func deleteMessageButton(_ message: DiscordChannel.Message) -> some View {
    Button(role: .destructive) {
      Task {
        var res: DiscordHTTPResponse?
        do {
          res = try await gw.client.deleteMessage(
            channelId: message.channel_id,
            messageId: message.id
          )
          try res?.guardSuccess()
        } catch {
          if let error = res?.asError() {
            appState.error = error
          } else {
            appState.error = error
          }
        }
      }
    } label: {
      Label("Delete Message", systemImage: "trash")
    }
  }

  /// Unicode emoji for the quick reaction row: favourites, then the most used,
  /// topped up with defaults. Custom emoji are left to the picker, since a menu
  /// can't load their images.
  var quickReactions: [String] {
    let frecency = gw.settings.frecencySettings
    var names: [String] = []
    if frecency.hasFavoriteEmojis {
      names += frecency.favoriteEmojis.emojis
    }
    if frecency.hasEmojiReactionFrecency {
      names += frecency.emojiReactionFrecency.emojis
        .sorted { $0.value.score > $1.value.score }
        .map(\.key)
    }
    if frecency.hasEmojiFrecency {
      names += frecency.emojiFrecency.emojis
        .sorted { $0.value.score > $1.value.score }
        .map(\.key)
    }
    var characters: [String] = []
    for name in names {
      guard let character = DiscordEmojiNameIndex.character(forName: name),
        !characters.contains(character)
      else { continue }
      characters.append(character)
    }
    for fallback in ["👍", "❤️", "😂", "😮", "😢"] where !characters.contains(fallback) {
      characters.append(fallback)
    }
    return Array(characters.prefix(5))
  }

  @ViewBuilder
  func userContextMenu(user: PartialUser) -> some View {
    if isDeveloperModeEnabled() {
      Button {
        copyText(user.id.rawValue)
      } label: {
        Label("Copy User ID", systemImage: "circle.grid.2x1.right.filled")
      }
    }
  }

  // Helpers

  func messageIsFromSelf(_ msg: DiscordChannel.Message) -> Bool {
    guard let currentUserID = gw.user.currentUser?.id else {
      return false
    }
    return msg.author?.id == currentUserID
  }

  func isDeveloperModeEnabled() -> Bool {
    settings.appearance.developerMode
  }

  func hasPermission(
    _ permission: Permission
  ) -> Bool {
    guard let guild else { return true }
    return guild.hasPermission(channel: channel, permission)
  }

  func copyText(_ string: String) {
    #if os(iOS)
      UIPasteboard.general.string = string
    #elseif os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(string, forType: .string)
    #endif
  }
}
