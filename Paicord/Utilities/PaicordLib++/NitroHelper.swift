//
//  NitroHelper.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 17/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib

extension DiscordUser.PremiumKind {
  /// Figures out if the user is able to upload a file of specified size to the specified channel.
  /// - Parameters:
  ///   - size: The size of the file in bytes.
  ///   - channel: The ChannelStore to upload to.
  /// - Returns: Whether the user can upload the file, and the upload limit in bytes.
  @MainActor
  func fileUpload(size: Int, to channel: ChannelStore) -> (allowed: Bool, limit: Int) {
    // https://docs.discord.food/reference#uploading-files

    let nitroLimit: Int = {
      switch self {
      case .none, .__undocumented:
        // No Nitro: 10MiB limit
        return 10 * 1024 * 1024
      case .nitroBasic, .nitroClassic:
        // Nitro Basic/Classic: 50MiB limit
        return 50 * 1024 * 1024
      case .nitro:
        // Nitro: 500MiB limit
        return 500 * 1024 * 1024
      }
    }()

    let serverLimit: Int = {
      if let guildStore = channel.guildStore {
        switch guildStore.guild?.premium_tier ?? .none {
        case .none, .tier1, .__undocumented:
          return 10 * 1024 * 1024
        case .tier2:
          return 50 * 1024 * 1024  // 50MiB limit
        case .tier3:
          return 100 * 1024 * 1024  // 100MiB limit
        }
      } else {
        return 10 * 1024 * 1024  // 10MiB limit
      }
    }()

    let uploadLimit = max(nitroLimit, serverLimit)

    return (size <= uploadLimit, uploadLimit)
  }
}
