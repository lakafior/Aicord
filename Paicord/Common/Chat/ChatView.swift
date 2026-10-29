//
//  ChatView.swift
//  PaiCord
//
// Created by Lakhan Lothiyi on 31/08/2025.
// Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

struct ChatView: View {
  @State var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.theme) var theme

  @State private var currentScrollPosition: MessageSnowflake?
  @State private var isScrolling: Bool = false

  var drain: MessageDrainStore { gw.messageDrain }

  @AppStorage("Paicord.Appearance.ChatMessagesAnimated")
  var chatAnimatesMessages: Bool = false

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
      #if os(macOS)
        // esc to scroll to bottom of chat, its a little jank
        .focusable()
        .focusEffectDisabled()
        .onTapGesture { isChatFocused = true }
        .focused($isChatFocused)
        .onKeyPress(.escape, phases: .down) { _ in
          vm.requestScrollToBottom(immediate: true)
          InputBar.inputVMs[vm.channelId]?.uploadItems = []
          return .handled
        }
      #endif
      .onScrollPhaseChange { _, newPhase in
        isScrolling = newPhase.isScrolling
      }
      .scrollPosition(id: $currentScrollPosition, anchor: .bottom)  // causes issues with input bar height changes:
      // currently, the input bar changing size can cause the scrollview position to jump unexpectedly.
      // not sure how to fix.
      .bottomAnchored()
      .scrollClipDisabled()
      .frame(maxHeight: .infinity)
      .overlay(alignment: .bottomTrailing) {
        let lastMessages = orderedMessages.suffix(10).map { $0.id }
        if let current = currentScrollPosition,
          !lastMessages.contains(current)
        {
          Button(action: {
            vm.requestScrollToBottom(immediate: true)
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

      if vm.hasPermission(.sendMessages) {
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
      ToolbarItem(placement: .navigation) {
        ChannelHeader(vm: vm)
      }
    }
    .onChange(of: vm.scrollRequest) { _, request in
      guard let request else { return }
      switch request.kind {
      case .bottom(let immediate, let pending):
        let isNearBottom =
          (orderedMessages.suffix(10).map(\.id)
          + pendingMessages.values.compactMap(\.nonce).map({
            MessageSnowflake($0.asString)
          }))
          .contains {
            $0 == self.currentScrollPosition
          }
        guard isNearBottom || immediate else {
          return
        }
        let resolvedId = pending ?? orderedMessages.last?.id
        withAnimation(immediate ? .default : nil) {
          self.currentScrollPosition = resolvedId ?? self.currentScrollPosition
        }
        if let resolvedId {
          acknowledge(messageId: resolvedId)
        }
      case .message(let messageId):
        self.currentScrollPosition = messageId
      }
    }
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

  @State var ackTask: Task<Void, Error>? = nil
  private func acknowledge(messageId: MessageSnowflake) {
    guard gw.readStates.isUnread(channelId: vm.channelId, lastMessageId: messageId) else {
      return
    }
    let channelId = vm.channelId
    ackTask?.cancel()
    ackTask = Task {
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      _ = try await gw.client.acknowledgeMessage(
        channelId: channelId,
        messageId: messageId,
        payload: Payloads.AcknowledgeMessage()
      )
      gw.readStates.applyAck(channelId: channelId, messageId: messageId)
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
