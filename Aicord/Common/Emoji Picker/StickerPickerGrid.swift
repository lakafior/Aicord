//
//  StickerPickerGrid.swift
//  Aicord
//
//  The Stickers tab of the picker: the stickers of your servers, the one
//  you're in first. Without Nitro only that server's stickers can be sent;
//  with "Stickers Without Nitro" on, the others go as a link to their image.
//

import AicordKit
import SwiftUI

extension EmojiPicker {
  enum StickerUse: Equatable {
    /// Sent as a sticker.
    case send
    /// Put into the message as a link to its image.
    case link(String)
    /// Needs Nitro (or can't be linked, like animated Lottie stickers).
    case locked
  }

  @MainActor
  static func stickerUse(
    _ sticker: Sticker, gw: GatewayStore, currentGuildID: GuildSnowflake?
  ) -> StickerUse {
    if sticker.available == false { return .locked }
    let hasNitro: Bool = {
      if case .none = gw.user.premiumKind { return false }
      return true
    }()
    if hasNitro || (sticker.guild_id != nil && sticker.guild_id == currentGuildID) {
      return .send
    }
    if ComposerPreferences.nitroFreeStickers,
      let link = NitroFreeLinks.sticker(id: sticker.id.rawValue, format: sticker.format_type)
    {
      return .link(link)
    }
    return .locked
  }

  struct StickerPickerGrid: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @Environment(\.dismiss) var dismiss
    @AppStorage(ComposerPreferences.Key.nitroFreeStickers) private var nitroFreeStickers = false
    var guildID: GuildSnowflake?
    var onStickerPicked: (Sticker) -> Void
    @State private var searchText = ""

    private var currentGuildID: GuildSnowflake? { guildID ?? appState.selectedGuild }

    private struct Section: Identifiable {
      var guildID: GuildSnowflake
      var name: String
      var stickers: [Sticker]
      var id: GuildSnowflake { guildID }
    }

    private var sections: [Section] {
      let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
      var sections = gw.user.stickers.compactMap { guildID, stickers -> Section? in
        let list = stickers.values
          .filter { sticker in
            query.isEmpty || sticker.name.lowercased().contains(query)
              || sticker.tags.lowercased().contains(query)
          }
          .sorted { ($0.sort_value ?? 0, $0.name) < ($1.sort_value ?? 0, $1.name) }
        guard !list.isEmpty else { return nil }
        return Section(guildID: guildID, name: gw.user.guilds[guildID]?.name ?? "", stickers: list)
      }
      sections.sort { a, b in
        if a.guildID == currentGuildID { return true }
        if b.guildID == currentGuildID { return false }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
      }
      return sections
    }

    var body: some View {
      VStack(spacing: 8) {
        TextField("Find the perfect sticker", text: $searchText)
          .textFieldStyle(.roundedBorder)
        let sections = sections
        if sections.isEmpty {
          Group {
            if searchText.isEmpty {
              ContentUnavailableView(
                "No Stickers", systemImage: "rectangle.on.rectangle.angled",
                description: Text("Your servers have no stickers."))
            } else {
              ContentUnavailableView(
                "No Results", systemImage: "magnifyingglass",
                description: Text("No sticker matches that name."))
            }
          }
          .frame(maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 8)],
              alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders
            ) {
              ForEach(sections) { section in
                SwiftUI.Section {
                  ForEach(section.stickers) { sticker in
                    cell(sticker)
                  }
                } header: {
                  Text(verbatim: section.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .background(.bar)
                }
              }
            }
          }
        }
      }
      .id(nitroFreeStickers)
    }

    @ViewBuilder
    private func cell(_ sticker: Sticker) -> some View {
      let use = EmojiPicker.stickerUse(sticker, gw: gw, currentGuildID: currentGuildID)
      Button {
        onStickerPicked(sticker)
        dismiss()
      } label: {
        StickerThumbnail(sticker: sticker)
          .frame(width: 72, height: 72)
          .opacity(use == .locked ? 0.4 : 1)
          .overlay(alignment: .bottomTrailing) {
            switch use {
            case .locked:
              Image(systemName: "lock.fill").font(.caption).padding(4)
            case .link:
              Image(systemName: "link").font(.caption).padding(4)
            case .send:
              EmptyView()
            }
          }
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .disabled(use == .locked)
      .help(sticker.name)
      .accessibilityLabel(Text(verbatim: sticker.name))
    }
  }

  /// A still preview; Lottie stickers show their name, having no image.
  struct StickerThumbnail: View {
    var sticker: Sticker

    var body: some View {
      if case .lottie = sticker.format_type {
        Text(verbatim: sticker.name)
          .font(.caption2)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.quaternary, in: .rect(cornerRadius: 8))
      } else {
        let url = URL(
          string: CDNEndpoint.sticker(stickerId: sticker.id, format: sticker.format_type).url
            + "?size=160")
        NukeImage(animation: .enabled(false)) { _ in url }
          .resizable()
          .scaledToFit()
      }
    }
  }
}
