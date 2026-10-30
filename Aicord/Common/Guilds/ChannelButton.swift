//
//  ChannelButton.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 24/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// A row in a channel list (`GuildView`, `DMsView`). The list owns selection: text
/// channels and direct messages are tagged with their id, everything else opts out.
struct ChannelButton: View {
  /// Chat setting: list channels you can't view, locked, like Vencord's ShowHiddenChannels.
  static let showsHiddenChannelsKey = "Paicord.Chat.ShowsHiddenChannels"

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.guildStore) var guild
  @State private var isHovered = false
  @State private var showsHiddenInfo = false
  @AppStorage(ChannelButton.showsHiddenChannelsKey) private var showsHiddenChannels = false
  var channel: DiscordChannel

  /// A server channel you lack View Channel for.
  var isHidden: Bool {
    guild?.hasPermission(channel: channel, .viewChannel) == false
  }

  var isUnread: Bool {
    !isHidden
      && gw.readStates.isUnread(channelId: channel.id, lastMessageId: channel.last_message_id)
  }

  var mentionCount: Int {
    isHidden ? 0 : gw.readStates.mentionCount(channelId: channel.id)
  }

  var isSelected: Bool { appState.selectedChannel == channel.id }

  /// The selection a channel list binds to: picking a row opens its chat, and on
  /// iPhone slides the chat over the list, also when the row was already selected.
  @MainActor
  static func selection(_ appState: AicordAppState) -> Binding<ChannelSnowflake?> {
    Binding {
      appState.selectedChannel
    } set: { channel in
      guard let channel else { return }
      appState.selectedChannel = channel
      #if os(iOS)
        withAnimation {
          appState.chatOpen = true
        }
      #endif
    }
  }

  var body: some View {
    rowContent
      .channelListRow(isSelected: isSelected)
  }

  @ViewBuilder
  var rowContent: some View {
    switch channel.type {
    case .dm, .groupDm:
      privateChannelLabel
        .tag(channel.id)
    case .guildVoice:
      VoiceChannelButton(channel: channel)
    case .guildText, .guildAnnouncement:
      if isHidden {
        hiddenRow
      } else {
        serverChannelLabel
          .tag(channel.id)
          .modifier(OptionalChannelContextMenu(channel: channel, guildId: guild?.guildId))
      }
    default:
      // forums, media and stage channels don't open in Aicord yet
      if isHidden {
        hiddenRow
      } else {
        serverChannelLabel
          .foregroundStyle(.tertiary)
          .selectionDisabled()
          .modifier(OptionalChannelContextMenu(channel: channel, guildId: guild?.guildId))
      }
    }
  }

  /// A server channel's icon, name and mention badge.
  var serverChannelLabel: some View {
    HStack(spacing: 4) {
      Label {
        Text(channel.name ?? "unknown")
      } icon: {
        Image(systemName: Self.symbol(for: channel.type))
      }
      .lineLimit(1)
      Spacer(minLength: 4)
      MentionCountBadge(count: mentionCount)
    }
    .fontWeight(isUnread ? .semibold : nil)
    .foregroundStyle(isUnread || isSelected ? .primary : .secondary)
    .overlay(alignment: .leading) { unreadDot }
    .accessibilityElement(children: .combine)
    .accessibilityValue(isUnread ? Text("Unread") : Text(verbatim: ""))
  }

  /// A channel you can't view: locked, opens what Discord tells about it instead of the chat.
  @ViewBuilder
  var hiddenRow: some View {
    if showsHiddenChannels {
      Button {
        showsHiddenInfo = true
      } label: {
        HStack(spacing: 4) {
          Label {
            Text(channel.name ?? "unknown")
          } icon: {
            Image(systemName: Self.symbol(for: channel.type))
          }
          .lineLimit(1)
          Spacer(minLength: 4)
          Image(systemName: "lock.fill")
            .font(.caption)
        }
        .foregroundStyle(.tertiary)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .selectionDisabled()
      .accessibilityHint(Text("You can't view this channel"))
      .popover(isPresented: $showsHiddenInfo) {
        HiddenChannelInfo(channel: channel, guild: guild)
          .presentationCompactAdaptation(.sheet)
          .presentationDetents([.medium, .large])
      }
    }
  }

  /// A direct message or group: avatar, name, unread dot and mentions.
  var privateChannelLabel: some View {
    HStack(spacing: 10) {
      privateChannelAvatar
        .frame(width: 32, height: 32)
      Text(privateChannelName)
        .lineLimit(1)
      Spacer(minLength: 4)
      MentionCountBadge(count: mentionCount)
    }
    .fontWeight(isUnread ? .semibold : nil)
    .foregroundStyle(isUnread || isSelected ? .primary : .secondary)
    .background {
      if isHovered, channel.type == .dm,
        let nameplate = channel.recipients?.first?.collectibles?.nameplate
      {
        Profile.NameplateView(nameplate: nameplate)
          .opacity(0.5)
          .nameplateAnimated(true)
          .transition(.opacity.animation(.default))
          .clipShape(.rounded)
      }
    }
    .overlay(alignment: .leading) { unreadDot }
    .onHover { isHovered = $0 }
    .accessibilityElement(children: .combine)
    .accessibilityValue(isUnread ? Text("Unread") : Text(verbatim: ""))
  }

  var privateChannelName: String {
    channel.name
      ?? channel.recipients?.map { $0.global_name ?? $0.username }.joined(separator: ", ")
      ?? (channel.type == .dm ? "Unknown Channel" : "Unknown Group DM")
  }

  @ViewBuilder
  var privateChannelAvatar: some View {
    if channel.type == .dm {
      if let user = channel.recipients?.first {
        Profile.AvatarWithPresence(member: nil, user: user)
          .profileAnimated(isHovered)
          .profileShowsAvatarDecoration()
      }
    } else if let icon = channel.icon {
      NukeImage(url: DiscordImageURL.channelIcon(id: channel.id, icon: icon))
        .resizable()
        .scaledToFit()
        .clipShape(.circle)
    } else if let firstUser = channel.recipients?.first(where: { $0.id != gw.user.currentUser?.id }),
      let lastUser = channel.recipients?.last(where: {
        $0.id != gw.user.currentUser?.id && $0.id != firstUser.id
      })
    {
      Profile.Avatar(member: nil, user: firstUser.toPartialUser())
        .profileShowsAvatarDecoration()
        .scaleEffect(0.75, anchor: .topLeading)
        .overlay(
          Profile.Avatar(member: nil, user: lastUser.toPartialUser())
            .profileShowsAvatarDecoration()
            .scaleEffect(0.75, anchor: .bottomTrailing)
        )
    } else if let user = channel.recipients?.first {
      Profile.Avatar(member: nil, user: user.toPartialUser())
        .profileShowsAvatarDecoration()
    } else {
      Circle().fill(Color.gray)
    }
  }

  /// Discord's unread pip, in the row's leading margin.
  @ViewBuilder
  var unreadDot: some View {
    if isUnread {
      Circle()
        .fill(.primary)
        .frame(width: 6, height: 6)
        .offset(x: -11)
        .accessibilityHidden(true)
    }
  }

  /// Direct messages and groups have no channel menu.
  struct OptionalChannelContextMenu: ViewModifier {
    let channel: DiscordChannel
    let guildId: GuildSnowflake?
    func body(content: Content) -> some View {
      if let guildId {
        content.channelContextMenu(channel, in: guildId)
      } else {
        content
      }
    }
  }

  /// Icon for each kind of server channel.
  static func symbol(for type: DiscordChannel.Kind?) -> String {
    switch type {
    case .guildAnnouncement: "megaphone.fill"
    case .guildVoice: "speaker.wave.2.fill"
    case .guildForum: "bubble.left.and.text.bubble.right"
    case .guildMedia: "photo.on.rectangle"
    case .guildStageVoice: "person.wave.2"
    default: "number"
    }
  }
}

/// What can be shown about a channel you can't view: what the gateway already
/// sends (name, topic, permission overwrites), never its messages.
struct HiddenChannelInfo: View {
  let channel: DiscordChannel
  let guild: GuildStore?

  /// Roles an overwrite lets view the channel, highest first.
  private var allowedRoles: [Role] {
    (channel.permission_overwrites ?? [])
      .filter { $0.type == .role && $0.allow.contains(.viewChannel) }
      .compactMap { guild?.role(RoleSnowflake($0.id)) }
      .filter { $0.id.rawValue != guild?.guildId.rawValue }  // not @everyone
      .sorted { $0.position > $1.position }
  }

  private var allowedMemberCount: Int {
    (channel.permission_overwrites ?? [])
      .filter { $0.type == .member && $0.allow.contains(.viewChannel) }
      .count
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Label {
          Text(channel.name ?? "unknown")
            .font(.title2.bold())
        } icon: {
          Image(systemName: "lock.fill")
            .foregroundStyle(.secondary)
        }

        Text("You don't have permission to view this channel. Aicord shows only what Discord already sends about it.")
          .font(.callout)
          .foregroundStyle(.secondary)

        if let topic = channel.topic, !topic.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text("Topic")
              .font(.headline)
            MarkdownText(content: topic)
              .handlesInteractions(false)
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          Text("Who Can View")
            .font(.headline)
          if allowedRoles.isEmpty && allowedMemberCount == 0 {
            Text("Members with special permissions, such as administrators.")
              .foregroundStyle(.secondary)
          } else {
            FlowLayout(spacing: 6) {
              ForEach(allowedRoles, id: \.id) { role in
                Text(role.name)
                  .font(.callout)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .foregroundStyle(role.color.value != 0 ? role.color.asColor() ?? .primary : .primary)
                  .background(.quaternary, in: .capsule)
              }
            }
            if allowedMemberCount > 0 {
              Text(
                allowedRoles.isEmpty
                  ? "^[\(allowedMemberCount) member](inflect: true) added by name"
                  : "and ^[\(allowedMemberCount) member](inflect: true) added by name"
              )
              .foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    #if os(macOS)
      .frame(width: 360)
      .frame(maxHeight: 420)
    #endif
  }
}

extension View {
  /// Channel and member lists: a sidebar on Mac and iPad; on iPhone a plain list like
  /// Apple Music's, with full-width rows and pinned section headers on the app's own
  /// background, dense enough to show a lot of names.
  func channelListStyle() -> some View {
    modifier(ChannelListStyle())
  }
}

extension View {
  /// A row of a list styled with `channelListStyle()`: shorter on iOS, and on iPhone
  /// without the plain list's opaque cell, so the app's background shows through.
  /// That also drops the cell's selection, so a selected row passes `isSelected`.
  func channelListRow(isSelected: Bool = false) -> some View {
    modifier(ChannelListRow(isSelected: isSelected))
  }
}

private struct ChannelListRow: ViewModifier {
  @Environment(\.userInterfaceIdiom) var idiom
  var isSelected: Bool

  func body(content: Content) -> some View {
    #if os(iOS)
      if idiom == .phone {
        content
          .listRowInsets(.vertical, 6)
          .listRowBackground(
            Rectangle().fill(isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear))
          )
      } else {
        content
          .listRowInsets(.vertical, 6)
      }
    #else
      content
    #endif
  }
}

private struct ChannelListStyle: ViewModifier {
  @Environment(\.userInterfaceIdiom) var idiom

  func body(content: Content) -> some View {
    if idiom == .phone {
      content
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 36)
    } else {
      content
        .listStyle(.sidebar)
    }
  }
}
