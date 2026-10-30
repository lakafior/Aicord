//
//  ChannelButton.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 24/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

struct ChannelButton: View {
  /// Chat setting: list channels you can't view, locked, like Vencord's ShowHiddenChannels.
  static let showsHiddenChannelsKey = "Paicord.Chat.ShowsHiddenChannels"

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.guildStore) var guild
  var channels: [ChannelSnowflake: DiscordChannel]
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

  var body: some View {
    // switch channel type
    let selected = appState.selectedChannel == channel.id
    switch channel.type {
    case .dm:
      textChannelButton { hovered in
        HStack {
          if let user = channel.recipients?.first {
            Profile.AvatarWithPresence(
              member: nil,
              user: user
            )
            .profileAnimated(hovered)
            .profileShowsAvatarDecoration()
            .padding(2)
          }
          Text(
            channel.name ?? channel.recipients?.map({
              $0.global_name ?? $0.username
            }).joined(separator: ", ") ?? "Unknown Channel"
          )
          .foregroundStyle(isUnread || selected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .padding(4)
        .background {
          if hovered || selected,
            let nameplate = channel.recipients?.first?.collectibles?.nameplate
          {
            Profile.NameplateView(nameplate: nameplate)
              .opacity(0.5)
              .transition(.opacity.animation(.default))
              .nameplateAnimated(hovered)
          }
        }
        .clipShape(.rounded)
        .overlay(alignment: .leading) {
          if isUnread {
            Circle()
              .fill(.primary)
              .frame(width: 8, height: 8)
              .offset(x: -8)
          }
        }
      }
      .tint(.primary)
      .padding(.horizontal, 4)
    case .groupDm:
      textChannelButton { _ in
        HStack {
          if let icon = channel.icon {
            let url = DiscordImageURL.channelIcon(
              id: channel.id,
              icon: icon
            )
            NukeImage(url: url)
              .resizable()
              .scaledToFit()
              .clipShape(.circle)
              .padding(2)
          } else {
            VStack {
              if let firstUser = channel.recipients?.first(where: {
                $0.id != gw.user.currentUser?.id
              }),
                let lastUser = channel.recipients?.last(where: {
                  $0.id != gw.user.currentUser?.id && $0.id != firstUser.id
                })
              {
                Group {
                  Profile.Avatar(
                    member: nil,
                    user: firstUser.toPartialUser()
                  )
                  .profileShowsAvatarDecoration()
                  .scaleEffect(0.75, anchor: .topLeading)
                  .overlay(
                    Profile.Avatar(
                      member: nil,
                      user: lastUser.toPartialUser()
                    )
                    .profileShowsAvatarDecoration()
                    .scaleEffect(0.75, anchor: .bottomTrailing)
                  )
                }
                .padding(2)
              } else if let user = channel.recipients?.first {
                Profile.Avatar(
                  member: nil,
                  user: user.toPartialUser()
                )
                .profileShowsAvatarDecoration()
                .padding(2)
              } else {
                Circle()
                  .fill(Color.gray)
                  .padding(2)
              }
            }
            .aspectRatio(1, contentMode: .fit)
          }
          Text(
            channel.name ?? channel.recipients?.map({
              $0.global_name ?? $0.username
            }).joined(separator: ", ") ?? "Unknown Group DM"
          )
          .foregroundStyle(isUnread || selected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
        .padding(4)
        .overlay(alignment: .leading) {
          if isUnread {
            Circle()
              .fill(.primary)
              .frame(width: 8, height: 8)
              .offset(x: -8)
          }
        }
      }
      .tint(.primary)
      .padding(.horizontal, 4)

    case .guildCategory:
      let expectedParentID = channel.id
      let childChannels = channels.values
        .filter { $0.parent_id ?? (try! .makeFake()) == expectedParentID }
        .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
        .map { $0.id }

      category(channelIDs: childChannels)
        .tint(.primary)
    case .guildText:
      textChannelButton { _ in
        HStack {
          Image(systemName: "number")
            .imageScale(.medium)
          Text(channel.name ?? "unknown")
          if mentionCount > 0 {
            Spacer(minLength: 4)
            MentionCountBadge(count: mentionCount)
          }
        }
        .foregroundStyle(isUnread || selected ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 35)
        .padding(.horizontal, 12)
        .overlay(alignment: .leading) {
          if isUnread {
            Circle()
              .fill(.primary)
              .frame(width: 8, height: 8)
              .offset(x: -8)
          }
        }
      }
      .tint(.primary)
    case .guildAnnouncement:
      textChannelButton { _ in
        HStack {
          Image(systemName: "megaphone.fill")
            .imageScale(.medium)
          Text(channel.name ?? "unknown")
          if mentionCount > 0 {
            Spacer(minLength: 4)
            MentionCountBadge(count: mentionCount)
          }
        }
        .foregroundStyle(isUnread || selected ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 35)
        .padding(.horizontal, 12)
        .overlay(alignment: .leading) {
          if isUnread {
            Circle()
              .fill(.primary)
              .frame(width: 8, height: 8)
              .offset(x: -8)
          }
        }
      }
      .tint(.primary)
    case .guildVoice:
      textChannelButton { _ in
        HStack {
          Image(systemName: "speaker.wave.2.fill")
            .imageScale(.medium)
          Text(channel.name ?? "unknown")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 35)
        .padding(.horizontal, 12)
      }
      .tint(.primary)
      .disabled(true)
    default:
      textChannelButton { _ in
        HStack {
          Image(systemName: Self.symbol(for: channel.type))
            .imageScale(.medium)
          Text(channel.name ?? "unknown")
        }
        .foregroundStyle(isUnread || selected ? .primary : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 35)
        .padding(.horizontal, 12)
        .overlay(alignment: .leading) {
          if isUnread {
            Circle()
              .fill(.primary)
              .frame(width: 8, height: 8)
              .offset(x: -8)
          }
        }
      }
      .tint(.primary)
      .disabled(true)
    }
  }

  // Shim
  struct TextChannelButton<Content: View>: View {
    @Environment(\.appState) var appState
    @Environment(\.guildStore) var guild
    @AppStorage(ChannelButton.showsHiddenChannelsKey) private var showsHiddenChannels = false
    @State private var isHovered = false
    @State private var showsHiddenInfo = false
    var channels: [ChannelSnowflake: DiscordChannel]
    var channel: DiscordChannel
    var content: (_ hovered: Bool) -> Content

    var shouldHide: Bool {
      guard let guild else { return false }
      return guild.hasPermission(
        channel: channel,
        .viewChannel
      ) == false
    }
    var body: some View {
      if shouldHide {
        if showsHiddenChannels {
          // locked: opens what Discord tells about it instead of the chat
          Button {
            showsHiddenInfo = true
          } label: {
            content(isHovered)
              .opacity(0.5)
              .overlay(alignment: .trailing) {
                Image(systemName: "lock.fill")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.trailing, 12)
              }
          }
          .onHover { isHovered = $0 }
          .buttonStyle(.borderless)
          .accessibilityHint(Text("You can't view this channel"))
          .popover(isPresented: $showsHiddenInfo) {
            HiddenChannelInfo(channel: channel, guild: guild)
              .presentationCompactAdaptation(.sheet)
              .presentationDetents([.medium, .large])
          }
        }
      } else {
        Button {
          appState.selectedChannel = channel.id
          #if os(iOS)
            withAnimation {
              appState.chatOpen.toggle()
            }
          #endif
        } label: {
          content(isHovered)
        }
        .onHover { isHovered = $0 }
        .buttonStyle(.borderless)
      }
    }
  }

  /// Button that switches the chat to the given channel when clicked
  @ViewBuilder
  func textChannelButton<Content: View>(
    @ViewBuilder label: @escaping (_ hovered: Bool) -> Content
  )
    -> some View
  {
    TextChannelButton(
      channels: channels,
      channel: channel
    ) { hovered in
      label(hovered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1)
        .background(
          Group {
            if hovered {
              Color.gray.opacity(0.2)
            } else {
              Color.clear
            }
          }
          .clipShape(.rounded)
        )
        .background(
          Group {
            if appState.selectedChannel == channel.id {
              Color.gray.opacity(0.13)
            } else {
              Color.clear
            }
          }
          .clipShape(.rounded)
        )
    }
  }

  /// Icon for channel types that don't have their own row style yet.
  static func symbol(for type: DiscordChannel.Kind?) -> String {
    switch type {
    case .guildForum: "bubble.left.and.text.bubble.right"
    case .guildMedia: "photo.on.rectangle"
    case .guildStageVoice: "person.wave.2"
    default: "number"
    }
  }

  struct CategoryButton: View {
    @Environment(\.isFirstInChannelList) var isFirst
    @Environment(\.guildStore) var guild
    @AppStorage(ChannelButton.showsHiddenChannelsKey) private var showsHiddenChannels = false
    var channelIDs: [ChannelSnowflake]
    var channels: [ChannelSnowflake: DiscordChannel]
    var channel: DiscordChannel

    /// Categories start expanded; only the ones the user collapses are remembered.
    @State private var isExpanded: Bool {
      didSet {
        UserDefaults.standard.set(
          !isExpanded,
          forKey: "GuildCategory.\(channel.id).Collapsed"
        )
      }
    }

    /// Set by initialiser, hides the category if there are no visible channels inside it.
    var shouldHide: Bool {
      guard !showsHiddenChannels else { return channelIDs.isEmpty }
      // reduce channels by bool
      let channels = channelIDs.compactMap { self.channels[$0] }
      let allHidden = channels.reduce(true) { partialResult, channel in
        partialResult
          && guild?.hasPermission(channel: channel, .viewChannel)
            == false
      }
      return allHidden
    }

    init(
      channelIDs: [ChannelSnowflake],
      channels: [ChannelSnowflake: DiscordChannel],
      channel: DiscordChannel
    ) {
      self.channelIDs = channelIDs
      self.channels = channels
      self.channel = channel
      self._isExpanded = .init(
        initialValue: !UserDefaults.standard.bool(
          forKey: "GuildCategory.\(channel.id).Collapsed"
        )
      )
    }

    var body: some View {
      if !shouldHide {
        VStack(spacing: 1) {
          // a hairline between categories, not above the first item
          if !isFirst {
            Divider()
              .padding(.horizontal, 10)
              .padding(.bottom, 4)
          }
          Button {
            withAnimation(.smooth(duration: 0.2)) {
              isExpanded.toggle()
            }
          } label: {
            HStack(spacing: 6) {
              Text(channel.name ?? "Unknown Category")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)

              Spacer(minLength: 4)

              Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(.rect)
          }
          .buttonStyle(.borderless)
          .accessibilityAddTraits(.isHeader)
          .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

          if isExpanded {
            ForEach(channelIDs, id: \.self) { channelId in
              if let channel = channels[channelId] {
                ChannelButton(channels: channels, channel: channel)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        }
      }
    }
  }

  /// A disclosure group for a category, showing its child channels when expanded
  @ViewBuilder
  func category(channelIDs: [ChannelSnowflake]) -> some View {
    CategoryButton(
      channelIDs: channelIDs,
      channels: channels,
      channel: channel
    )
    .padding(.top, 4)
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

extension EnvironmentValues {
  /// Whether a channel list row is the first one, so it can skip its separator.
  @Entry var isFirstInChannelList: Bool = false
}
