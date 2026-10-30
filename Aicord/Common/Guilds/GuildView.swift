//
//  GuildView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 22/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

/// A server's channels as a system sidebar list: categories are collapsible sections,
/// the open channel is the list's selection.
struct GuildView: View {
  var guild: GuildStore
  @AppStorage(ChannelButton.showsHiddenChannelsKey) private var showsHiddenChannels = false
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.appState) var appState
  /// Categories start expanded; only the ones the user collapses are remembered.
  @State private var collapsedCategories: Set<ChannelSnowflake> = []

  var body: some View {
    // pinned channels show at the top of the list, out of their category
    let pinnedIDs = PinnedPlacesStore.shared.channels[guild.guildId] ?? []
    let pinnedChannels = pinnedIDs.compactMap { guild.channels[$0] }.filter(isListed)
    let topLevel = guild.channels.values
      .filter { $0.parent_id == nil && !pinnedIDs.contains($0.id) }
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
    let uncategorized = topLevel.filter { $0.type != .guildCategory && isListed($0) }
    let categories = topLevel.filter { $0.type == .guildCategory }

    List(selection: ChannelButton.selection(appState)) {
      header

      if !pinnedChannels.isEmpty || !uncategorized.isEmpty {
        Section {
          ForEach(pinnedChannels + uncategorized) { channel in
            ChannelButton(channel: channel)
              .listRowSeparator(.hidden)
          }
        }
      }

      ForEach(categories) { category in
        let children = children(of: category, excluding: pinnedIDs)
        if !children.isEmpty {
          Section(isExpanded: isExpanded(category.id)) {
            ForEach(children) { channel in
              ChannelButton(channel: channel)
                .listRowSeparator(.hidden)
            }
          } header: {
            CategoryHeader(
              name: category.name ?? "Unknown Category",
              isExpanded: isExpanded(category.id)
            )
          }
        }
      }
    }
    .channelListStyle()
    .environment(\.guildStore, guild)
    .task(id: guild.guildId) { loadCollapsedCategories() }
  }

  /// The banner, and on iPhone the server's name, which Mac and iPad show in the toolbar.
  @ViewBuilder
  var header: some View {
    let bannerURL = Utils.fetchGuildBannerURL(guild: guild, animated: true)
    if bannerURL != nil || idiom == .phone {
      Section {
        VStack(alignment: .leading, spacing: 0) {
          if let bannerURL {
            Color.clear
              .aspectRatio(16 / 9, contentMode: .fit)
              .overlay(
                NukeImage(url: bannerURL)
                  .resizable()
                  .scaledToFill()
              )
              .clipped()
              .accessibilityHidden(true)
          }
          if idiom == .phone {
            VStack(alignment: .leading, spacing: 2) {
              Text(guild.guild?.name ?? "Unknown Guild")
                .font(.title3)
                .bold()
              Text("\(guild.guild?.member_count ?? 0) members")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
          }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .selectionDisabled()
        .modifier(OptionalGuildContextMenu(guild: guild.guild))
      }
    }
  }

  /// A category's name. Sidebar lists on Mac and iPad collapse the section themselves;
  /// the plain list on iPhone doesn't, so there the header toggles it.
  struct CategoryHeader: View {
    @Environment(\.userInterfaceIdiom) var idiom
    var name: String
    @Binding var isExpanded: Bool

    var body: some View {
      if idiom == .phone {
        Button {
          withAnimation(.smooth(duration: 0.2)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(spacing: 6) {
            Text(name)
              .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .accessibilityHidden(true)
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(isExpanded ? Text("Collapse") : Text("Expand"))
      } else {
        Text(name)
          .lineLimit(1)
      }
    }
  }

  /// The server menu on the header, the same one the server bar shows.
  private struct OptionalGuildContextMenu: ViewModifier {
    let guild: Guild?
    func body(content: Content) -> some View {
      if let guild {
        content.guildContextMenu(guild)
      } else {
        content
      }
    }
  }

  /// Whether a channel shows at all: hidden ones only with Show Hidden Channels on.
  func isListed(_ channel: DiscordChannel) -> Bool {
    showsHiddenChannels || guild.hasPermission(channel: channel, .viewChannel)
  }

  /// A category's listed channels, in Discord's order. Empty hides the category.
  func children(of category: DiscordChannel, excluding pinned: [ChannelSnowflake])
    -> [DiscordChannel]
  {
    let categoryID = AnySnowflake(category.id)
    return guild.channels.values
      .filter { $0.parent_id == categoryID && !pinned.contains($0.id) && isListed($0) }
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
  }

  static func collapsedKey(_ category: ChannelSnowflake) -> String {
    "GuildCategory.\(category).Collapsed"
  }

  func isExpanded(_ category: ChannelSnowflake) -> Binding<Bool> {
    Binding {
      !collapsedCategories.contains(category)
    } set: { expanded in
      if expanded {
        collapsedCategories.remove(category)
      } else {
        collapsedCategories.insert(category)
      }
      UserDefaults.standard.set(!expanded, forKey: Self.collapsedKey(category))
    }
  }

  func loadCollapsedCategories() {
    collapsedCategories = Set(
      guild.channels.values
        .filter { $0.type == .guildCategory }
        .map(\.id)
        .filter { UserDefaults.standard.bool(forKey: Self.collapsedKey($0)) }
    )
  }
}
