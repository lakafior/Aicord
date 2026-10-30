//
//  SettingsStore.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 20/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Foundation
import AicordKit
import SwiftProtobuf

@MainActor
@Observable
class SettingsStore: DiscordDataStore {
  var gateway: GatewayStore?
  var eventTask: Task<Void, Never>?

  // MARK: - Settings State
  var userSettings: DiscordProtos_DiscordUsers_V1_PreloadedUserSettings =
    .init()
  var frecencySettings: DiscordProtos_DiscordUsers_V1_FrecencyUserSettings =
    .init()

  // MARK: - Batching State
  private var userSettingsTimer: Timer?
  private var frecencySettingsTimer: Timer?
  private var hasPendingUserSettings = false
  private var hasPendingFrecencySettings = false
  /// Settings patches sent and not yet answered, and the newest one's number.
  /// Answers and gateway echoes of older patches arrive late and must not
  /// undo a newer change.
  private var patchesInFlight = 0
  private var latestPatch = 0

  // MARK: - Update Types for Timing
  enum UpdateType {
    case infrequent  // No delay - immediate
    case frequent  // 10 seconds
    case automated  // 30 seconds
    case daily  // 1 day (24 hours)
  }

  // MARK: - Protocol Methods

  func setupEventHandling() {
    guard let gateway = gateway?.gateway else { return }
    let events = gateway.events
    eventTask = Task {
      for await event in events {
        switch event.data {
        case .ready(let readyData):
          handleReady(readyData)

        case .userSettingsUpdate(let update):
          handleUserSettingsUpdate(update)

        default:
          break
        }
      }
    }
  }

  func cancelEventHandling() {
    // overrides default impl of protocol
    eventTask?.cancel()
    eventTask = nil

    // Cancel any pending timers
    userSettingsTimer?.invalidate()
    frecencySettingsTimer?.invalidate()
    userSettingsTimer = nil
    frecencySettingsTimer = nil
  }

  // MARK: - Event Handlers
  private func handleReady(_ readyData: Gateway.Ready) {
    if let settings = readyData.user_settings_proto {
      userSettings = settings
    }
    // get frecency settings from api
    guard let gateway else { return }
    Task {
      do {
        let res = try await gateway.client.getUserSettingsProto(type: .frecency)
        try res.guardSuccess()
        let frecencyProto = try res.decode()
        if case .frecency(let proto) = frecencyProto.settings {
          frecencySettings = proto
        }
      } catch {
        print("[Settings] Failed to fetch initial frecency settings: \(error)")
      }
    }
  }

  private func handleUserSettingsUpdate(
    _ update: Gateway.UserSettingsProtoUpdate
  ) {
    switch update.settings {
    case .preloaded(let proto):
      if update.partial {
        // Merge with existing settings
        mergeUserSettings(with: proto)
      } else if patchesInFlight == 0,
        proto.versions.dataVersion >= userSettings.versions.dataVersion
      {
        // Replace entire settings, unless it's an echo older than ours
        userSettings = proto
      }

    case .frecency(let proto):
      if update.partial {
        // Merge with existing frecency settings
        mergeFrecencySettings(with: proto)
      } else {
        // Replace entire frecency settings
        frecencySettings = proto
      }

    default:
      break
    }
  }

  // MARK: - Settings Merging
  private func mergeUserSettings(
    with newSettings: DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  ) {
    // protobuf merge: fields set in the partial update overwrite ours,
    // nested messages are merged field by field
    do {
      try userSettings.merge(serializedBytes: newSettings.serializedData())
    } catch {
      print("[Settings] Failed to merge user settings update: \(error)")
    }
  }

  private func mergeFrecencySettings(
    with newSettings: DiscordProtos_DiscordUsers_V1_FrecencyUserSettings
  ) {

  }

  // MARK: - Public Settings Update Methods

  /// Merges the given fields into our settings and sends the groups they touch.
  func patchUserSettings(
    _ partial: DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  ) async throws {
    let bytes: [UInt8] = try partial.serializedBytes()
    try await patchUserSettings { try? $0.merge(serializedBytes: bytes) }
  }

  /// Applies `change` to our settings and sends every top-level group it
  /// changed (privacy, status, text and images…) in full. Discord replaces each
  /// group it receives as a whole, so sending only the changed fields would
  /// reset the rest of the group. Fields set back to `false` or zero work too.
  func patchUserSettings(
    _ change: (inout DiscordProtos_DiscordUsers_V1_PreloadedUserSettings) -> Void
  ) async throws {
    guard let gateway else { return }
    var updated = userSettings
    change(&updated)
    var payload = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings()
    for group in Self.settingsGroups where group.differs(userSettings, updated) {
      group.copy(&payload, updated)
    }
    guard payload != .init() else { return }
    userSettings = updated
    latestPatch += 1
    let patch = latestPatch
    patchesInFlight += 1
    defer { patchesInFlight -= 1 }
    let res = try await gateway.client.modifyUserSettingsProto(
      type: .preloaded,
      payload: .init(settings: .preloaded(payload))
    )
    try res.guardSuccess()
    if patch == latestPatch, case .preloaded(let proto) = try res.decode().settings {
      userSettings = proto
    }
  }

  private struct SettingsGroup {
    typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
    let differs: (Settings, Settings) -> Bool
    let copy: (inout Settings, Settings) -> Void

    init<T: Equatable>(_ field: WritableKeyPath<Settings, T>) {
      differs = { $0[keyPath: field] != $1[keyPath: field] }
      copy = { $0[keyPath: field] = $1[keyPath: field] }
    }
  }

  private static let settingsGroups: [SettingsGroup] = [
    .init(\.versions), .init(\.inbox), .init(\.guilds), .init(\.userContent),
    .init(\.voiceAndVideo), .init(\.textAndImages), .init(\.notifications),
    .init(\.privacy), .init(\.debug), .init(\.gameLibrary), .init(\.status),
    .init(\.localization), .init(\.appearance), .init(\.guildFolders),
    .init(\.favorites), .init(\.audioContextSettings), .init(\.communities),
    .init(\.broadcast), .init(\.clips), .init(\.forLater), .init(\.safetySettings),
    .init(\.icymiSettings), .init(\.applications), .init(\.ads),
    .init(\.inAppFeedbackSettings),
  ]

  /// Request user settings modification with appropriate batching delay
  /// - Parameters:
  ///   - updateType: The type of update to determine delay timing
  ///   - immediate: If true, bypasses batching and sends immediately (for infrequent updates)
  func requestUserSettingsModify(
    updateType: UpdateType = .frequent,
    immediate: Bool = false
  ) {
    hasPendingUserSettings = true

    if immediate || updateType == .infrequent {
      performUserSettingsUpdate()
      return
    }

    // Cancel existing timer and start new one
    userSettingsTimer?.invalidate()

    let delay = delayInterval(for: updateType)
    userSettingsTimer = Timer.scheduledTimer(
      withTimeInterval: delay,
      repeats: false
    ) { [weak self] _ in
      Task { @MainActor in
        self?.performUserSettingsUpdate()
      }
    }
  }

  /// Request frecency settings modification with appropriate batching delay
  /// - Parameters:
  ///   - updateType: The type of update to determine delay timing
  ///   - immediate: If true, bypasses batching and sends immediately
  func requestFrecencySettingsModify(
    updateType: UpdateType = .daily,
    immediate: Bool = false
  ) {
    hasPendingFrecencySettings = true

    if immediate || updateType == .infrequent {
      performFrecencySettingsUpdate()
      return
    }

    // Cancel existing timer and start new one
    frecencySettingsTimer?.invalidate()

    let delay = delayInterval(for: updateType)
    frecencySettingsTimer = Timer.scheduledTimer(
      withTimeInterval: delay,
      repeats: false
    ) { [weak self] _ in
      Task { @MainActor in
        self?.performFrecencySettingsUpdate()
      }
    }
  }

  // MARK: - Helper Methods

  private func delayInterval(for updateType: UpdateType) -> TimeInterval {
    switch updateType {
    case .infrequent:
      return 0  // Should not be called
    case .frequent:
      return 10  // 10 seconds
    case .automated:
      return 30  // 30 seconds
    case .daily:
      return 24 * 60 * 60  // 1 day (24 hours)
    }
  }

  private func performUserSettingsUpdate() {
    guard hasPendingUserSettings else { return }

    userSettingsTimer?.invalidate()
    userSettingsTimer = nil
    hasPendingUserSettings = false

    Task {
      await sendUserSettingsUpdate()
    }
  }

  private func performFrecencySettingsUpdate() {
    guard hasPendingFrecencySettings else { return }

    frecencySettingsTimer?.invalidate()
    frecencySettingsTimer = nil
    hasPendingFrecencySettings = false

    Task {
      await sendFrecencySettingsUpdate()
    }
  }

  /// Sends the user settings update to the REST API
  private func sendUserSettingsUpdate() async {
    fatalError("Not implemented")
  }

  /// Sends the frecency settings update to the REST API
  private func sendFrecencySettingsUpdate() async {
    fatalError("Not implemented")
  }

  // MARK: - Convenience Methods for Common Settings Changes

  /// Updates a specific user setting and requests modification
  func updateUserSetting<T>(
    _ keyPath: WritableKeyPath<
      DiscordProtos_DiscordUsers_V1_PreloadedUserSettings, T
    >,
    to value: T,
    updateType: UpdateType = .frequent
  ) {
    userSettings[keyPath: keyPath] = value
    requestUserSettingsModify(updateType: updateType)
  }

  /// Updates a specific frecency setting and requests modification
  func updateFrecencySetting<T>(
    _ keyPath: WritableKeyPath<
      DiscordProtos_DiscordUsers_V1_FrecencyUserSettings, T
    >,
    to value: T,
    updateType: UpdateType = .daily
  ) {
    frecencySettings[keyPath: keyPath] = value
    requestFrecencySettingsModify(updateType: updateType)
  }

  /// Forces immediate send of any pending settings updates
  func flushPendingUpdates() {
    if hasPendingUserSettings {
      performUserSettingsUpdate()
    }
    if hasPendingFrecencySettings {
      performFrecencySettingsUpdate()
    }
  }

  /// Cancels any pending settings updates
  func cancelPendingUpdates() {
    userSettingsTimer?.invalidate()
    frecencySettingsTimer?.invalidate()
    userSettingsTimer = nil
    frecencySettingsTimer = nil
    hasPendingUserSettings = false
    hasPendingFrecencySettings = false
  }
}

// MARK: - Text & Images

extension SettingsStore {
  /// Discord's sticker setting, 0 when it was never changed.
  enum StickerAnimation: UInt32 {
    case always = 0
    case onInteraction = 1
    case never = 2
  }

  private var textAndImages: DiscordProtos_DiscordUsers_V1_PreloadedUserSettings.TextAndImagesSettings {
    userSettings.textAndImages
  }

  var animatesEmoji: Bool {
    textAndImages.hasAnimateEmoji ? textAndImages.animateEmoji.value : true
  }

  var autoplaysGIFs: Bool {
    textAndImages.hasGifAutoPlay ? textAndImages.gifAutoPlay.value : true
  }

  var stickerAnimation: StickerAnimation {
    StickerAnimation(rawValue: textAndImages.animateStickers.value) ?? .always
  }

  var showsImageDescriptions: Bool {
    textAndImages.viewImageDescriptions.value
  }

  /// Discord's spoiler setting, a string; unset means on click.
  enum SpoilerReveal: String {
    case onClick = "ON_CLICK"
    case ifModerator = "IF_MODERATOR"
    case always = "ALWAYS"
  }

  var rendersReactions: Bool {
    textAndImages.hasRenderReactions ? textAndImages.renderReactions.value : true
  }

  var rendersEmbeds: Bool {
    textAndImages.hasRenderEmbeds ? textAndImages.renderEmbeds.value : true
  }

  var inlinesAttachmentMedia: Bool {
    textAndImages.hasInlineAttachmentMedia ? textAndImages.inlineAttachmentMedia.value : true
  }

  var inlinesEmbedMedia: Bool {
    textAndImages.hasInlineEmbedMedia ? textAndImages.inlineEmbedMedia.value : true
  }

  var spoilerReveal: SpoilerReveal {
    SpoilerReveal(rawValue: textAndImages.renderSpoilers.value) ?? .onClick
  }

  /// Whether spoilers in this channel show without a tap.
  func revealsSpoilers(in channelStore: ChannelStore?) -> Bool {
    switch spoilerReveal {
    case .always: true
    case .onClick: false
    case .ifModerator:
      channelStore?.guildStore != nil && channelStore?.hasPermission(.manageMessages) == true
    }
  }

  /// Discord's Compact message display: no avatars, time and name on the text's line.
  var displaysCompactMessages: Bool {
    textAndImages.messageDisplayCompact.value
  }

  var convertsEmoticons: Bool {
    textAndImages.hasConvertEmoticons ? textAndImages.convertEmoticons.value : true
  }
}
