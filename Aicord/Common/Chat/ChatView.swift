//
//  ChatView.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct ChatView: View {
  @State var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme
  @Environment(\.scenePhase) var scenePhase

  @State private var currentScrollPosition: MessageSnowflake?
  @State private var summaryRange: SummaryRange?
  @State private var askingChannel = false
  @AppStorage(IntelligencePreferences.Key.allowsDMs) private var intelligenceInDMs = false
  @State private var isScrolling: Bool = false

  var drain: MessageDrainStore { gw.messageDrain }

  @AppStorage(AppearancePreferences.Key.chatMessagesAnimated)
  var animatesMessagesSetting: Bool = false
  @Environment(\.reducesMotion) var reducesMotion
  var chatAnimatesMessages: Bool { animatesMessagesSetting && !reducesMotion }

  init(vm: ChannelStore) { self._vm = .init(initialValue: vm) }

  #if os(macOS)
    @FocusState private var isChatFocused: Bool
  #endif

  var body: some View {
    let orderedMessages = vm.messages.values
    let pendingMessages = drain.pendingMessages[vm.channelId, default: [:]]

    let shouldAnimate =
      orderedMessages.last?.author?.id != gw.user.currentUser?.id
    VStack(spacing: 20) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if !vm.messages.isEmpty {
            if vm.hasMoreHistory && vm.hasPermission(.readMessageHistory) {
              //                PlaceholderMessageSet()
              //                  .onAppear {
              //                    vm.tryFetchMoreMessageHistory()
              //                  }
            } else {
              if vm.hasPermission(.readMessageHistory) {
                ChatHeaders.WelcomeStartOfChannelHeader()
              } else {
                ChatHeaders.NoHistoryPermissionHeader()
              }
            }
          }

          ForEach(orderedMessages) { msg in
            let prior = vm.getMessage(before: msg)
            if messageAllowed(msg) {
              MessageCell(
                for: msg,
                prior: prior,
                channel: vm,
                scrolling: isScrolling
              )
            }
          }

          //            if !vm.messages.isEmpty {
          //              if !vm.hasLatestMessages && vm.hasPermission(.readMessageHistory) {
          //                PlaceholderMessageSet()
          //                  .onAppear {
          //                    vm.tryFetchMoreMessageHistory()
          //                  }
          //              }
          //            } else {
          ForEach(pendingMessages.values) { message in
            // if there is only one message, there is no prior. use the latest message from channelstore
            if pendingMessages.count > 1,
              let messageIndex = pendingMessages.values.firstIndex(where: {
                $0.nonce == message.nonce
              }),
              messageIndex > 0
            {
              let priorMessage = pendingMessages.values[messageIndex - 1]
              SendMessageCell(for: message, prior: priorMessage)
            } else if let latestMessage = orderedMessages.last {
              // if there is a prior message from the channel store, use that
              SendMessageCell(for: message, prior: latestMessage)
            } else {
              // no prior message
              SendMessageCell(
                for: message,
                prior: Optional<DiscordChannel.Message>.none
              )
            }
          }
          //          }

          // message drain view, represents messages being sent etc
        }
        .scrollTargetLayout()
      }
      // macos 26/27 bug workaround
      .safeAreaPadding(.top, 1)
      .safeAreaInset(edge: .top, spacing: 0) {
        ScamWarningBanner(vm: vm)
      }
      #if os(macOS)
        // esc to scroll to bottom of chat, its a little jank
        .focusable()
        .focusEffectDisabled()
        // no tap gesture here: on macOS a click recogniser on the whole list
        // swallowed mouse-downs before Textual's text view saw them, so links
        // in messages (invite links among them) did nothing when clicked
        .focused($isChatFocused)
        .onKeyPress(.escape, phases: .down) { _ in
          vm.requestScrollToBottom(immediate: true)
          InputBar.inputVMs[vm.channelId]?.uploadItems = []
          return .handled
        }
      #endif
      .onScrollPhaseChange { _, newPhase in
        isScrolling = newPhase.isScrolling
        #if os(macOS)
          // scrolling the chat is what makes Esc jump back to the bottom
          if newPhase == .interacting { isChatFocused = true }
        #endif
      }
      .scrollPosition(id: $currentScrollPosition, anchor: .bottom)  // causes issues with input bar height changes:
      // currently, the input bar changing size can cause the scrollview position to jump unexpectedly.
      // not sure how to fix.
      .bottomAnchored()
      .scrollClipDisabled()
      .frame(maxHeight: .infinity)
      .overlay(alignment: .bottomTrailing) {
        let lastMessages = orderedMessages.suffix(10).map { $0.id }
        if !vm.hasLatestMessages
          || currentScrollPosition.map({ !lastMessages.contains($0) }) == true
        {
          Button(action: {
            if vm.hasLatestMessages {
              vm.requestScrollToBottom(immediate: true)
            } else {
              vm.returnToLatest()
            }
          }) {
            Image(systemName: "arrow.down")
              .tint(.primary)
              .imageScale(.large)
              .padding(10)
              .glassEffect(.regular.interactive(), in: .circle)
          }
          .buttonStyle(.plain)
          .padding()
          .transition(.blurReplace.animation(.default))
        }
      }

      if let channel = gw.user.privateChannels[vm.channelId],
        channel.isPendingMessageRequest || channel.isSpam
      {
        // replying would accept the request, so ask first
        MessageRequestBar(channel: channel)
      } else if vm.hasPermission(.sendMessages) {
        InputBar(vm: vm)
          .id(vm.channelId)
      } else {
        Spacer().frame(height: 10)
      }
    }
    .animation(
      shouldAnimate && chatAnimatesMessages ? .default : nil,
      value: orderedMessages
    )
    .animation(chatAnimatesMessages ? .default : nil, value: pendingMessages)
    .scrollDismissesKeyboard(.interactively)
    .background(theme.common.secondaryBackground)
    .ignoresSafeArea(.keyboard, edges: .all)

    .toolbar {
      // a plain title rather than a glass pill: the leading pill on iOS is too narrow for
      // most channel names, and the centre slot truncates gracefully when space runs out
      #if os(iOS)
        ToolbarItem(placement: .principal) {
          ChannelHeader(vm: vm)
        }
        .sharedBackgroundVisibility(.hidden)
      #else
        ToolbarItem(placement: .navigation) {
          ChannelHeader(vm: vm)
        }
        .sharedBackgroundVisibility(.hidden)
      #endif
      // read-only summaries; in DMs only when allowed in Settings → Intelligence
      if !isPrivateChannel || intelligenceInDMs {
        ToolbarItem(placement: .primaryAction) {
          ChannelIntelligenceMenu(
            channelId: vm.channelId, summary: $summaryRange, asking: $askingChannel)
        }
      }
      // no calls before a request is accepted
      if vm.channel?.type == .dm || vm.channel?.type == .groupDm,
        gw.user.privateChannels[vm.channelId].map({ !$0.isPendingMessageRequest && !$0.isSpam })
          ?? true
      {
        ToolbarItem(placement: .primaryAction) {
          DMCallButton(channelID: vm.channelId)
        }
      }
    }
    .sheet(item: $summaryRange) { range in
      ChannelSummarySheet(
        channelId: vm.channelId,
        guildId: vm.guildStore?.guildId,
        channelName: channelTitle,
        range: range
      )
    }
    .sheet(isPresented: $askingChannel) {
      AskChannelSheet(
        channelId: vm.channelId, guildId: vm.guildStore?.guildId, channelName: channelTitle)
    }
    .onChange(of: vm.scrollRequest) { _, request in
      guard let request else { return }
      switch request.kind {
      case .bottom(let immediate, let pending):
        guard isNearBottom || immediate else {
          return
        }
        let resolvedId = pending ?? orderedMessages.last?.id
        withAnimation(immediate ? .default : nil) {
          self.currentScrollPosition = resolvedId ?? self.currentScrollPosition
        }
        acknowledgeLatestIfVisible()
      case .message(let messageId):
        self.currentScrollPosition = messageId
      }
    }
    // opening a channel whose messages are already loaded doesn't produce a scroll request
    .onAppear { acknowledgeLatestIfVisible() }
    // a channel marked unread goes back to normal once the user leaves it
    .onDisappear { gw.readStates.manuallyUnread.remove(vm.channelId) }
    .onChange(of: vm.channelId) { old, _ in gw.readStates.manuallyUnread.remove(old) }
    // on iPhone the chat only slides away, so closing it counts as leaving
    .onChange(of: appState.chatOpen) { _, open in
      if open {
        acknowledgeLatestIfVisible()
      } else {
        gw.readStates.manuallyUnread.remove(vm.channelId)
      }
    }
    .onChange(of: currentScrollPosition) { acknowledgeLatestIfVisible() }
    // a jump from Search or a forward's source, for this channel
    .task(id: appState.pendingJump) {
      guard let jump = appState.pendingJump, jump.channelID == vm.channelId else { return }
      appState.pendingJump = nil
      await vm.jump(to: jump.messageID)
    }
    .onChange(of: scenePhase) { acknowledgeLatestIfVisible() }
  }

  private var isPrivateChannel: Bool {
    vm.channel?.type == .dm || vm.channel?.type == .groupDm
  }

  /// How summaries name the channel.
  private var channelTitle: String {
    if let name = vm.channel?.name, !name.isEmpty {
      return isPrivateChannel ? name : "#" + name
    }
    let people = vm.channel?.recipients?.map { $0.global_name ?? $0.username } ?? []
    return people.isEmpty ? String(localized: "this conversation") : people.joined(separator: ", ")
  }

  /// Whether the chat is scrolled to (or near) the newest messages. A `nil` scroll position
  /// means the user hasn't scrolled yet, so the view is still resting on its bottom anchor.
  private var isNearBottom: Bool {
    guard let currentScrollPosition else { return true }
    let pendingIds = drain.pendingMessages[vm.channelId, default: [:]].values
      .compactMap(\.nonce)
      .map { MessageSnowflake($0.asString) }
    return (vm.messages.values.suffix(10).map(\.id) + pendingIds)
      .contains(currentScrollPosition)
  }

  func messageAllowed(_ msg: DiscordChannel.Message) -> Bool {
    // Currently only filters out messages from blocked users
    guard let authorId = msg.author?.id else { return true }

    // check relationship
    if let relationship = gw.user.relationships[authorId] {
      if relationship.type == .blocked || relationship.user_ignored {
        return false
      }
    }

    return true
  }

  //  private func scheduleScrollToBottom(
  //    proxy: ScrollViewProxy,
  //    lastID: DiscordChannel.Message.ID? = nil,
  //  ) {
  //    pendingScrollWorkItem?.cancel()
  //    guard let lastID else { return }
  //
  //    let workItem = DispatchWorkItem { [proxy] in
  //      //      withAnimation(accessibilityReduceMotion ? .none : .default) {
  //      proxy.scrollTo(lastID, anchor: .top)
  //      //      }
  //    }
  //    pendingScrollWorkItem = workItem
  //    DispatchQueue.main.asyncAfter(deadline: .now(), execute: workItem)
  //  }

  @State var ackTask: Task<Void, Never>? = nil
  /// Marks the channel as read up to its newest message, if the user can actually see it:
  /// the app is active, the newest messages are loaded, and the chat is scrolled to the bottom.
  private func acknowledgeLatestIfVisible() {
    guard scenePhase == .active, vm.hasLatestMessages, isNearBottom,
      !gw.readStates.manuallyUnread.contains(vm.channelId),
      let messageId = vm.messages.values.last?.id,
      gw.readStates.isUnread(channelId: vm.channelId, lastMessageId: messageId)
    else { return }
    let channelId = vm.channelId
    ackTask?.cancel()
    ackTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      do {
        try await gw.client.acknowledgeMessage(
          channelId: channelId,
          messageId: messageId,
          payload: Payloads.AcknowledgeMessage()
        ).guardSuccess()
        gw.readStates.applyAck(channelId: channelId, messageId: messageId)
      } catch {
        print("[ChatView] Failed to acknowledge message \(messageId.rawValue):", error)
      }
    }
  }
}

extension View {
  fileprivate func bottomAnchored() -> some View {
    self
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .defaultScrollAnchor(.bottom, for: .alignment)
      .defaultScrollAnchor(.bottom, for: .sizeChanges)
  }
}
