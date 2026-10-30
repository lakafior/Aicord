//
//  AicordAppState.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 18/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

@MainActor
@Observable
final class AicordAppState {
  // each window gets its own app state
  static var instances: [UUID: AicordAppState] = [:]

  static var sharedEphemeral = AicordAppState()

  init() {
    Self.instances[id] = self

    loadPrevSelectedChannels()
    if let lastDM = self.rawPrevSelectedChannels[
      self.selectedGuild?.rawValue ?? "nil"
    ] {
      self.selectedChannel = ChannelSnowflake(lastDM)
    } else {
      self.selectedChannel = nil
    }
  }
  deinit {
    let instanceId = id
    Task { @MainActor in
      Self.instances.removeValue(forKey: instanceId)
    }
  }

  let id = UUID()

  // MARK: - iOS Specific
  /// iPhone opens on Home; the chat slides over once a channel is picked.
  var chatOpen: Bool = false

  /// Bumped when a notification opens a channel, so the iPhone tabs leave Settings.
  var openedFromNotification = 0

  // MARK: - General
  var showingQuickSwitcher: Bool = false

  // MARK: - Reaction Picker
  /// The message an emoji picker is currently open for, if any.
  var reactionPickerTarget: ReactionPickerTarget? = nil

  // MARK: - Forward
  /// The message the forward sheet is open for, if any.
  var forwardTarget: ForwardTarget? = nil

  // MARK: - Jump to Message
  /// A message the chat should scroll to and highlight once its channel is open,
  /// from Search or a forwarded message's source.
  var pendingJump: MessageJump? = nil

  struct MessageJump: Equatable {
    let id = UUID()
    let channelID: ChannelSnowflake
    let messageID: MessageSnowflake
  }

  /// Opens a channel and scrolls to one of its messages.
  func open(
    guild: GuildSnowflake?, channel: ChannelSnowflake, message: MessageSnowflake
  ) {
    pendingJump = MessageJump(channelID: channel, messageID: message)
    if selectedGuild != guild { selectedGuild = guild }
    selectedChannel = channel
    chatOpen = true
  }

  // MARK: - Attachment Viewer
  var showingAttachmentViewer: Bool = false
  var attachmentViewerAttachments: [DiscordMedia] = []
  var attachmentViewerIndex: Int? = nil
  var attachmentViewerContextMessage: DiscordChannel.PartialMessage? = nil

  // MARK: - Selected Guild & Channel Persistence

  private let storageKey = "AppState.PrevSelectedChannels"
  var suppressChannelSave = false

  private var _selectedGuild: GuildSnowflake? = nil {
    didSet {
      UserDefaults.standard.set(
        _selectedGuild?.rawValue,
        forKey: "AppState.PrevSelectedGuild"
      )
    }
  }
  var selectedGuild: GuildSnowflake? {
    get { _selectedGuild }
    set {
      let newGuildKey = newValue?.rawValue ?? "nil"

      suppressChannelSave = true
      defer { suppressChannelSave = false }

      let lastChannel = rawPrevSelectedChannels[newGuildKey]
      if let lastChannel {
        selectedChannel = ChannelSnowflake(lastChannel)
      } else {
        selectedChannel = nil
      }

      _selectedGuild = newValue
    }
  }

  var selectedChannel: ChannelSnowflake? {
    didSet {
      guard !suppressChannelSave else { return }
      let key = selectedGuild?.rawValue ?? "nil"
      if let channel = selectedChannel {
        rawPrevSelectedChannels[key] = channel.rawValue
      } else {
        rawPrevSelectedChannels.removeValue(forKey: key)
      }
      savePrevSelectedChannels()
    }
  }

  // persistent mapping as [String: String] where key == guild.rawValue or "nil"
  @ObservationIgnored
  private var rawPrevSelectedChannels: [String: String] = [:]

  func resetStore() {
    selectedGuild = nil
    selectedChannel = nil
    rawPrevSelectedChannels = [:]
    UserDefaults.standard.removeObject(
      forKey: "AppState.PrevSelectedGuild"
    )
    savePrevSelectedChannels()
  }

  // MARK: - Persistence Helpers

  func loadPrevGuild() {
    let guildIdString = UserDefaults.standard.string(
      forKey: "AppState.PrevSelectedGuild"
    )
    guard let guildIdString else { return }
    let guildId = GuildSnowflake(guildIdString)
    guard GatewayStore.shared.user.guilds.keys.contains(guildId) else { return }
    self.selectedGuild = GuildSnowflake(guildId)
  }

  private func loadPrevSelectedChannels() {
    let defaults = UserDefaults.standard

    if let data = defaults.data(forKey: storageKey) {
      if let obj = try? JSONSerialization.jsonObject(with: data),
        let dict = obj as? [String: String]
      {
        rawPrevSelectedChannels = dict
        return
      }
    }

    rawPrevSelectedChannels = [:]
  }

  private func savePrevSelectedChannels() {
    let json = rawPrevSelectedChannels
    if let data = try? JSONSerialization.data(withJSONObject: json) {
      UserDefaults.standard.set(data, forKey: storageKey)
    } else {
      // fallback: write dictionary directly
      UserDefaults.standard.set(json, forKey: storageKey)
    }
  }

  // MARK: - Error state
  var showingError = false
  var showingErrorSheet = false
  var error: Error? = nil {
    didSet {
      showingError = error != nil
    }
  }
}
