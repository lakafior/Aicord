//
//  ReactionPicker.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 15/09/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

// Presents the emoji picker for adding a reaction to a message. Lives at the
// root so the picker survives the message cell that asked for it going away.

import AicordKit
import SwiftUI

/// Identifies the message a reaction is being picked for.
struct ReactionPickerTarget: Identifiable, Hashable {
  let channelID: ChannelSnowflake
  let messageID: MessageSnowflake
  /// The guild the reaction lands in, or nil in a DM. Decides whether a custom
  /// emoji counts as external.
  let guildID: GuildSnowflake?

  var id: String { "\(channelID.rawValue)/\(messageID.rawValue)" }

  init(
    channelID: ChannelSnowflake,
    messageID: MessageSnowflake,
    guildID: GuildSnowflake?
  ) {
    self.channelID = channelID
    self.messageID = messageID
    self.guildID = guildID
  }

  init(message: DiscordChannel.Message, guildID: GuildSnowflake?) {
    self.init(
      channelID: message.channel_id,
      messageID: message.id,
      guildID: guildID
    )
  }
}

extension View {
  @ViewBuilder
  func reactionPicker() -> some View {
    self.modifier(ReactionPickerModifier())
  }
}

private struct ReactionPickerModifier: ViewModifier {
  @Environment(\.appState) var appState
  @Environment(\.gateway) var gw

  #if os(iOS)
    @State private var detent: PresentationDetent = .medium

    func body(content: Content) -> some View {
      @Bindable var appState = appState
      content
        .sheet(item: $appState.reactionPickerTarget) { target in
          EmojiPicker(detent: $detent)
            .variant(.reactions)
            .guild(target.guildID)
            .allowsShiftToKeepOpen(false)
            .onPickedEmoji { emoji in
              appState.reactionPickerTarget = nil
              target.react(with: emoji, gw: gw, appState: appState)
            }
            .presentationDetents([.medium, .large], selection: $detent)
        }
        .onChange(of: appState.reactionPickerTarget) {
          // always open at the smaller detent
          if appState.reactionPickerTarget != nil { detent = .medium }
        }
    }
  #else
    // the Mac's picker is a popover on the message (`ReactionPickerAnchor`)
    func body(content: Content) -> some View { content }
  #endif
}

#if os(macOS)
  /// On the Mac the picker is a popover on the message it reacts to, as the
  /// system's emoji picker opens at the text it types into. It sits behind
  /// every message that has the menu with Add Reaction; a view of its own, so
  /// only it follows the picker's target, not the message.
  struct ReactionPickerAnchor: View {
    @Environment(\.appState) var appState
    @Environment(\.gateway) var gw
    let messageID: MessageSnowflake

    var body: some View {
      let target = appState.reactionPickerTarget
      Color.clear
        .popover(
          isPresented: Binding(
            get: { target?.messageID == messageID },
            set: { if !$0, appState.reactionPickerTarget?.messageID == messageID {
              appState.reactionPickerTarget = nil
            } }
          ),
          arrowEdge: .top
        ) {
          if let target {
            EmojiPicker()
              .variant(.reactions)
              .guild(target.guildID)
              .allowsShiftToKeepOpen(false)
              .onPickedEmoji { emoji in
                appState.reactionPickerTarget = nil
                target.react(with: emoji, gw: gw, appState: appState)
              }
          }
        }
    }
  }
#endif

extension ReactionPickerTarget {
  /// Why this custom emoji can't be reacted with here, or nil if it can.
  ///
  /// Discord answers a reaction with an emoji the account isn't entitled to use
  /// with the same "Unknown Emoji" (10014) it gives for a malformed one, so the
  /// reason has to be worked out locally to say anything useful. Only reports a
  /// reason when the outcome is certain - anything uncertain is left to Discord
  /// rather than refusing a reaction that would have worked.
  @MainActor
  private func customEmojiUnavailableReason(
    _ emoji: DiscordModels.Emoji,
    gw: GatewayStore
  ) -> String? {
    guard let id = emoji.id else { return nil }  // unicode, nothing to check
    let label = emoji.name.map { ":\($0):" } ?? "That emoji"

    let source = gw.user.emojis.first { _, emojis in emojis[id] != nil }
    guard let (sourceGuildID, emojis) = source, let custom = emojis[id] else {
      return "\(label) isn't from a server you're in, so Discord won't accept it."
    }
    if custom.available == false {
      return "\(label) is currently unavailable on its server."
    }
    guard sourceGuildID != guildID else { return nil }  // same server: fine

    // Emoji from another server (or used in a DM) need Nitro.
    guard gw.user.premiumKind == .none else { return nil }
    let sourceName = gw.user.guilds[sourceGuildID]?.name ?? "another server"
    return
      "\(label) is from \(sourceName). Reacting with emoji from another server requires Nitro."
  }

  /// Adds a reaction to the message, reporting why through `appState.error`
  /// when Discord would refuse it. Shared by the picker and the context menu's
  /// quick reactions.
  @MainActor
  func react(
    with emoji: DiscordModels.Emoji,
    gw: GatewayStore,
    appState: AicordAppState
  ) {
    ImpactGenerator.impact(style: .light)
    // The grid is built from SwiftEmojiIndex, which spells some sequences
    // differently to Discord; send Discord's spelling or it rejects the
    // reaction with "Unknown Emoji".
    if let reason = customEmojiUnavailableReason(emoji, gw: gw) {
      appState.error = reason
      return
    }
    var emoji = emoji
    if emoji.id == nil, let name = emoji.name {
      guard let character = DiscordEmojiNameIndex.discordCharacter(matching: name)
      else {
        appState.error = "Discord doesn't support reacting with \(name)."
        return
      }
      emoji = .init(name: character)
    }
    Task { @MainActor in
      do {
        let reaction = try Reaction(emoji: emoji)
        try await gw.client.addMessageReaction(
          channelId: channelID,
          messageId: messageID,
          emoji: reaction,
          type: .normal
        )
        .guardSuccess()
      } catch {
        appState.error = error
      }
    }
  }
}
