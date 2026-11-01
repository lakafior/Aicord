//
//  ThreadBrowserSheet.swift
//  Aicord
//

import AicordKit
import SwiftUI

extension AicordAppState {
  /// Shows a thread in the chat. Threads aren't in `GuildStore.channels`, so the
  /// thread is kept in `threads` for `getChannelStore` to find.
  func openThread(_ thread: DiscordChannel, in guildStore: GuildStore?) {
    guildStore?.threads[thread.id] = thread
    selectedChannel = thread.id
    chatOpen = true
  }
}

/// A text channel's threads, active or archived, newest activity first.
/// Uses the same search as forum posts.
struct ThreadBrowserSheet: View {
  var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  @State private var archived = false
  @State private var threads: [DiscordChannel] = []
  @State private var firstMessages: [ChannelSnowflake: DiscordChannel.Message] = [:]
  @State private var hasMore = false
  @State private var isLoading = false
  @State private var failed = false
  @State private var indexing = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(threads, id: \.id) { thread in
            Button {
              dismiss()
              appState.openThread(thread, in: vm.guildStore)
            } label: {
              ForumPostRow(
                post: thread, firstMessage: firstMessages[thread.id], tags: [],
                guildStore: vm.guildStore)
            }
            .buttonStyle(.plain)
            .onAppear {
              if thread.id == threads.last?.id, hasMore { Task { await load(reset: false) } }
            }
          }
          if isLoading {
            ProgressView()
              .frame(maxWidth: .infinity)
          }
        } footer: {
          if indexing {
            Text("Discord is still indexing this channel. Try again in a moment.")
          } else if failed {
            Text("The threads couldn't be loaded.")
          } else if !isLoading && threads.isEmpty {
            Text(archived ? "No archived threads." : "No active threads.")
          }
        }
      }
      .safeAreaInset(edge: .top) {
        Picker("Threads", selection: $archived) {
          Text("Active").tag(false)
          Text("Archived").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal)
        .padding(.bottom, 4)
      }
      .refreshable { await load(reset: true) }
      .navigationTitle("Threads")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task(id: archived) { await load(reset: true) }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 480)
    #endif
  }

  private func load(reset: Bool) async {
    guard !isLoading || reset else { return }
    isLoading = true
    defer { isLoading = false }
    let query = ThreadSearchQuery(
      archived: archived,
      sortBy: archived ? .archiveTime : .lastMessageTime,
      offset: reset ? 0 : threads.count)
    // Discord answers 202 while it builds the index; it's usually ready in seconds
    for attempt in 0..<3 {
      do {
        let response = try await gw.client.searchForumThreads(channelID: vm.channelId, query: query)
        guard !Task.isCancelled else { return }
        if response.httpResponse.status == .accepted {
          indexing = true
          try await Task.sleep(for: .seconds(2 * (attempt + 1)))
          continue
        }
        try response.guardSuccess()
        let page = try response.decode()
        indexing = false
        failed = false
        if reset {
          threads = []
          firstMessages = [:]
        }
        let known = Set(threads.map(\.id))
        threads += page.threads.filter { !known.contains($0.id) }
        for message in page.first_messages ?? [] {
          firstMessages[message.channel_id] = message
        }
        hasMore = page.has_more ?? false
        return
      } catch {
        if !Task.isCancelled {
          print("[Threads] Thread search failed:", error)
          failed = true
        }
        return
      }
    }
  }
}

/// A channel's pinned messages, newest pin first. Tapping one jumps to it.
struct PinnedMessagesSheet: View {
  var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss

  @State private var pins: [DiscordChannel.Message] = []
  @State private var isLoading = true
  @State private var failed = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(pins) { message in
          Button {
            dismiss()
            appState.open(
              guild: vm.guildStore?.guildId, channel: message.channel_id, message: message.id)
          } label: {
            PinnedMessageRow(message: message, channelStore: vm)
          }
          .buttonStyle(.plain)
        }
      }
      .overlay {
        if isLoading {
          ProgressView()
        } else if failed {
          ContentUnavailableView(
            "Pins couldn't be loaded", systemImage: "pin.slash",
            description: Text("Pull to try again."))
        } else if pins.isEmpty {
          ContentUnavailableView(
            "No pinned messages", systemImage: "pin",
            description: Text("Pinned messages in this channel show up here."))
        }
      }
      .refreshable { await load() }
      .navigationTitle("Pinned Messages")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task { await load() }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 480)
    #endif
  }

  private func load() async {
    do {
      let response = try await gw.client.listPinnedMessages(channelId: vm.channelId)
      try response.guardSuccess()
      pins = try response.decode()
      failed = false
    } catch {
      if !Task.isCancelled {
        print("[Pins] Loading pins failed:", error)
        failed = true
      }
    }
    isLoading = false
  }
}

private struct PinnedMessageRow: View {
  let message: DiscordChannel.Message
  let channelStore: ChannelStore

  private var authorName: String {
    guard let author = message.author else { return "" }
    return channelStore.guildStore?.member(author.id)?.nick ?? message.member?.nick
      ?? author.global_name ?? author.username
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(authorName)
          .font(.subheadline.weight(.semibold))
        Text(message.timestamp.date, format: .dateTime.day().month().year().hour().minute())
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      MessageCell.MessageBody(message: message, channelStore: channelStore)
        .allowsHitTesting(false)
    }
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
  }
}
