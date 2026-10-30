//
//  GuildScrollBar.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 23/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct GuildScrollBar: View {
  @Environment(\.gateway) var gw
  @Environment(\.userInterfaceIdiom) var idiom

  var body: some View {
    #if os(iOS)
      // plain scroll view so the list keeps scrolling under the glass tab bar
      ScrollView { guildList }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    #else
      ScrollFadeMask { guildList }
    #endif
  }

  private var guildList: some View {
    LazyVStack {
      // on iPhone direct messages have their own tab
      if idiom != .phone {
        GuildButton(guild: nil)  // becomes dms "guild"

        Divider()
          .padding(.horizontal, 8)
      }

      // servers pinned in Aicord, taken out of their place below
      let pinned = PinnedPlacesStore.shared.guilds
      ForEach(pinned.compactMap { gw.user.guilds[$0] }, id: \.id) { guild in
        GuildButton(guild: guild)
      }

      // the usersettings guild folders can sometimes not cover all guilds
      // in this case, we need to find the unlisted guilds, and order by join date, newest first
      // this code covers the case where the user never reordered their guilds.
      // reordering would trigger usage of the guild folders method of organisation.
      if let userID = gw.user.currentUser?.id {
        let unlistedGuilds = gw.user.guilds.values.filter { guild in
          !pinned.contains(guild.id) && !gw.settings.userSettings.guildFolders.folders.contains { folder in
            folder.guildIds.contains(where: {
              $0.description == guild.id.rawValue
            })
          }
        }.sorted(by: { a, b in
          let aMember = gw.user.guilds[a.id]?.members?.first(where: { $0.user?.id == userID })
          let bMember = gw.user.guilds[b.id]?.members?.first(where: { $0.user?.id == userID })
          return (bMember?.joined_at ?? .init(date: .now))
            < (aMember?.joined_at ?? .init(date: .now))
        })

        ForEach(unlistedGuilds, id: \.id) { guild in
          GuildButton(guild: guild)
        }
      }
      ForEach(
        0..<gw.settings.userSettings.guildFolders.folders.count,
        id: \.self
      ) { folderIndex in
        let folder = gw.settings.userSettings.guildFolders.folders[
          folderIndex
        ]
        Group {
          if folder.hasID == false {
            // anon folder, should have only one guild id
            if let guildIDString = folder.guildIds.first?.description,
              let guild = gw.user.guilds[GuildSnowflake(guildIDString)],
              !pinned.contains(guild.id)
            {
              GuildButton(guild: guild)
            }
          } else {
            let guilds = folder.guildIds.compactMap { guildID in
              let guildID = GuildSnowflake(guildID.description)
              return pinned.contains(guildID) ? nil : gw.user.guilds[guildID]
            }
            if !guilds.isEmpty {
              GuildButton(folder: folder, guilds: guilds)
            }
          }
        }
      }
    }
    .safeAreaPadding(.all, 10)
  }
}
