//
//  MessageCell.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 07/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

struct MessageCell: View {

  /// Controls the size of the avatar in the message cell.
  #if os(iOS)
    static let avatarSize: CGFloat = 40
  #elseif os(macOS)
    static let avatarSize: CGFloat = 35
  #endif

  var message: DiscordChannel.Message
  var priorMessage: DiscordChannel.Message?
  var channelStore: ChannelStore
  var isScrolling: Bool = false
  @State var cellHighlighted = false

  init(
    for message: DiscordChannel.Message,
    prior: DiscordChannel.Message? = nil,
    channel: ChannelStore,
    scrolling: Bool = false
  ) {
    self.message = message
    self.priorMessage = prior
    self.channelStore = channel
    self.isScrolling = scrolling
  }

  var userMentioned: Bool {
    let gw = GatewayStore.shared
    guard let currentUserID = gw.user.currentUser?.id else { return false }

    if !message.mention_everyone,
      message.mentions.isEmpty,
      message.mention_roles.isEmpty
    {
      return false
    }

    if message.mention_everyone { return true }

    if message.mentions.contains(where: { $0.id == currentUserID }) {
      return true
    }

    let userRoles = channelStore.guildStore?.member(currentUserID)?.roles ?? []
    for roleID in message.mention_roles {
      if userRoles.contains(roleID) { return true }
    }
    return false
  }

  var body: some View {
    let inline =
      priorMessage?.author?.id == message.author?.id
      && message.timestamp.date.timeIntervalSince(
        priorMessage?.timestamp.date ?? .distantPast
      ) < 300 && message.referenced_message == nil
      && message.type == .default
      && priorMessage?.type != .guildMemberJoin

    let compact = GatewayStore.shared.settings.displaysCompactMessages
    let isDeleted = channelStore.deletedMessageIDs.contains(message.id)
    let previousVersions = channelStore.previousVersions[message.id] ?? []

    VStack(alignment: .leading, spacing: 2) {
      // Content
      switch message.type {
      case .default, .reply:
        DefaultMessage(
          message: message,
          channelStore: channelStore,
          inline: inline,
          compact: compact
        )
        .equatable()
      case .chatInputCommand:
        ChatInputCommandMessage(message: message, channelStore: channelStore)
          .equatable()
      case .guildMemberJoin:
        GuildMemberJoinMessage(message: message, channelStore: channelStore)
          .equatable()
      default:
        HStack {
          AvatarBalancing()
          Text("\(Image(systemName: "xmark.circle.fill")) Unsupported message type \(String(describing: message.type))")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }

      if !previousVersions.isEmpty {
        EditHistory(versions: previousVersions)
      }
      if isDeleted {
        DeletedNote {
          withAnimation { channelStore.hideDeletedMessage(message.id) }
        }
      }
    }
    .background(Color.almostClear)
    .padding(.horizontal, 10)
    .padding(.vertical, 2)
    .background(Color.accentColor.opacity(channelStore.highlightedMessageID == message.id ? 0.18 : 0))
    .background(Color(hexadecimal6: 0xcc8735).opacity(userMentioned && !isDeleted ? 0.05 : 0))
    .background(alignment: .leading) {
      Color(hexadecimal6: 0xce9c5c).opacity(userMentioned && !isDeleted ? 1 : 0)
        .frame(maxWidth: 2)
    }
    .background(Color.red.opacity(isDeleted ? 0.08 : 0))
    .background(alignment: .leading) {
      Color.red.opacity(isDeleted ? 0.8 : 0)
        .frame(maxWidth: 2)
    }
    #if os(macOS)
      .onHover { self.cellHighlighted = $0 }
      .background(
        !isScrolling && cellHighlighted
          ? Color(NSColor.secondaryLabelColor).opacity(0.1) : .clear
      )
    #endif
    .modifier(DeletedAwareContextMenu(message: message, isDeleted: isDeleted) {
      withAnimation { channelStore.hideDeletedMessage(message.id) }
    })
    .padding(.top, inline ? 0 : compact ? 6 : 15)  // adds space between message groups
  }

  /// What an edited message said before, kept by the Chat setting.
  struct EditHistory: View {
    let versions: [String]

    var body: some View {
      HStack(alignment: .top, spacing: 0) {
        AvatarBalancing()
          .padding(.trailing, 8)
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(versions.enumerated()), id: \.offset) { _, version in
            Text(verbatim: version)
              .strikethrough()
          }
          Text(versions.count == 1 ? "Before the edit" : "Earlier versions, oldest first")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// Marks a message Discord deleted that the Chat setting kept.
  struct DeletedNote: View {
    var hide: () -> Void

    var body: some View {
      HStack(spacing: 0) {
        AvatarBalancing()
          .padding(.trailing, 8)
        HStack(spacing: 6) {
          Image(systemName: "trash")
          Text("Deleted")
          Button("Hide", action: hide)
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  /// A deleted message only offers what still makes sense locally.
  struct DeletedAwareContextMenu: ViewModifier {
    let message: DiscordChannel.Message
    let isDeleted: Bool
    var hide: () -> Void

    func body(content: Content) -> some View {
      if isDeleted {
        content.contextMenu {
          Button {
            #if os(iOS)
              UIPasteboard.general.string = message.content
            #else
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(message.content, forType: .string)
            #endif
          } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
          }
          Button(action: hide) {
            Label("Hide Deleted Message", systemImage: "eye.slash")
          }
        }
      } else {
        content.entityContextMenu(for: message)
      }
    }
  }
}

#Preview {
  let llsc12 = DiscordUser(
    id: .init("381538809180848128"),
    username: "llsc12",
    discriminator: "0",
    global_name: nil,
    avatar: "df71b3f223666fd8331c9940c6f7cbd9",
    banner: nil,
    bot: false,
    system: false,
    mfa_enabled: true,
    accent_color: nil,
    locale: .englishUS,
    verified: true,
    email: nil,
    flags: .init(rawValue: 4_194_352),
    premium_type: nil,
    public_flags: .init(rawValue: 4_194_304),
    avatar_decoration_data: nil
  )
  MessageCell(
    for: .init(
      id: try! .makeFake(),
      channel_id: try! .makeFake(),
      author: llsc12,
      content: "gm",
      timestamp: .init(date: .now),
      edited_timestamp: nil,
      tts: false,
      mention_everyone: false,
      mentions: [],
      mention_roles: [],
      mention_channels: nil,
      attachments: [],
      embeds: [],
      reactions: nil,
      nonce: nil,
      pinned: false,
      webhook_id: nil,
      type: DiscordChannel.Message.Kind.default,
      activity: nil,
      application: nil,
      application_id: nil,
      message_reference: nil,
      flags: [],
      referenced_message: nil,
      interaction: nil,
      thread: nil,
      components: nil,
      sticker_items: nil,
      stickers: nil,
      position: nil,
      role_subscription_data: nil,
      resolved: nil,
      poll: nil,
      call: nil,
      guild_id: nil,
      member: nil
    ),
    prior: nil,
    channel: .init(id: try! .makeFake())
  )
}
