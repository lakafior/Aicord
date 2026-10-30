//
//  MessageRequestsView.swift
//  Aicord
//
//  The Requests and Spam folders: DMs from people you don't know wait in
//  Requests until you accept them, and the ones Discord's spam filter caught
//  sit in Spam. Both are ordinary DM channels flagged by Discord
//  (`is_message_request`, `is_spam`), so they come with READY and change
//  through Channel Update and Channel Delete.
//

import PaicordLib
import SwiftUI

enum MessageFolder: Hashable, CaseIterable, Identifiable {
  case requests, spam
  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .requests: "Message Requests"
    case .spam: "Spam"
    }
  }

  var symbol: String {
    switch self {
    case .requests: "tray.and.arrow.down"
    case .spam: "xmark.bin"
    }
  }
}

extension CurrentUserStore {
  /// Requests waiting for an answer, newest first. Requests from people you
  /// ignored are left out unless asked for.
  func messageRequests(includingIgnored: Bool = false) -> [DiscordChannel] {
    privateChannels.values
      .filter(\.isPendingMessageRequest)
      .filter { includingIgnored || !isIgnored($0) }
      .sorted(by: Self.newestFirst)
  }

  var spamChannels: [DiscordChannel] {
    privateChannels.values.filter(\.isSpam).sorted(by: Self.newestFirst)
  }

  /// Whether the person behind a one-to-one request is on your ignore list.
  func isIgnored(_ channel: DiscordChannel) -> Bool {
    guard channel.type == .dm, let id = channel.recipients?.first?.id else { return false }
    return relationships[id]?.user_ignored == true
  }

  static func newestFirst(_ a: DiscordChannel, _ b: DiscordChannel) -> Bool {
    let left = a.last_message_id?.rawValue ?? a.id.rawValue
    let right = b.last_message_id?.rawValue ?? b.id.rawValue
    return left.compare(right, options: .numeric) == .orderedDescending
  }
}

/// Accept, ignore and reject for message requests and spam, shared by the
/// folder lists and the bar shown in place of the message field.
@MainActor
struct MessageRequestActions {
  let gw: GatewayStore
  let appState: PaicordAppState

  /// Moves a request (or something wrongly marked as spam) into your DMs.
  func accept(_ channel: DiscordChannel) async {
    do {
      let res = try await gw.client.acceptMessageRequest(channelId: channel.id)
      try res.guardSuccess()
      var updated = (try? res.decode()) ?? channel
      updated.is_message_request = false
      updated.is_spam = false
      updated.flags?.remove(.spam)
      gw.user.privateChannels[channel.id] = updated
    } catch {
      appState.error = error
    }
  }

  /// Rejects a request or deletes a spam DM. Discord removes the channel.
  func reject(_ channel: DiscordChannel) async {
    do {
      try await gw.client.rejectMessageRequest(channelId: channel.id).guardSuccess()
      gw.user.privateChannels.removeValue(forKey: channel.id)
      leave(channel.id)
    } catch {
      appState.error = error
    }
  }

  /// Rejects many at once, 50 per call.
  func reject(all channels: [DiscordChannel]) async {
    let ids = channels.map(\.id)
    for start in stride(from: 0, to: ids.count, by: 50) {
      let chunk = Array(ids[start..<min(start + 50, ids.count)])
      do {
        try await gw.client.batchRejectMessageRequests(payload: .init(channel_ids: chunk))
          .guardSuccess()
        for id in chunk {
          gw.user.privateChannels.removeValue(forKey: id)
          leave(id)
        }
      } catch {
        appState.error = error
        return
      }
    }
  }

  /// Ignores the sender: the request leaves the list without them being told,
  /// and Discord keeps their messages and friend requests quiet.
  func ignore(_ channel: DiscordChannel) async {
    guard let user = channel.recipients?.first?.id else { return }
    await setIgnored(true, user: user)
  }

  func unignore(_ channel: DiscordChannel) async {
    guard let user = channel.recipients?.first?.id else { return }
    await setIgnored(false, user: user)
  }

  private func setIgnored(_ ignored: Bool, user: UserSnowflake) async {
    do {
      let res =
        ignored
        ? try await gw.client.ignoreUser(userID: user)
        : try await gw.client.unignoreUser(userID: user)
      try res.guardSuccess()
      // the gateway confirms with Relationship Add/Update; reflect it right away
      gw.user.relationships[user]?.user_ignored = ignored
    } catch {
      appState.error = error
    }
  }

  /// Closes the chat if it was showing a channel that just went away.
  private func leave(_ id: ChannelSnowflake) {
    guard appState.selectedChannel == id else { return }
    appState.selectedChannel = nil
    appState.chatOpen = false
  }
}

/// One folder's list.
struct MessageFolderView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  let folder: MessageFolder
  var open: (ChannelSnowflake) -> Void

  @State var previews: [ChannelSnowflake: DiscordChannel.Message] = [:]
  @State var confirmingRejectAll = false
  @State var pendingReject: DiscordChannel? = nil
  @State var showsIgnored = false

  var actions: MessageRequestActions { .init(gw: gw, appState: appState) }

  var channels: [DiscordChannel] {
    switch folder {
    case .requests: gw.user.messageRequests()
    case .spam: gw.user.spamChannels
    }
  }

  var ignored: [DiscordChannel] {
    folder == .requests ? gw.user.messageRequests(includingIgnored: true).filter(gw.user.isIgnored) : []
  }

  var body: some View {
    List {
      if channels.isEmpty {
        ContentUnavailableView(
          folder == .requests ? "No Message Requests" : "No Spam",
          systemImage: folder.symbol,
          description: Text(
            folder == .requests
              ? "DMs from people you don't share a friendship with wait here until you accept them."
              : "Messages Discord's spam filter catches end up here."
          )
        )
        .listRowBackground(Color.clear)
      } else {
        Section {
          ForEach(channels) { channel in
            row(for: channel)
          }
        } footer: {
          Text(
            folder == .requests
              ? "They won't know you've seen their message until you reply. Accepting moves the conversation to your messages."
              : "Opening a spam message is safe; links and images stay as they are, so be careful with them."
          )
        }
      }

      if !ignored.isEmpty {
        Section(isExpanded: $showsIgnored) {
          ForEach(ignored) { channel in
            row(for: channel, isIgnored: true)
          }
        } header: {
          Text("Ignored — \(ignored.count)")
        }
      }
    }
    .navigationTitle(folder.title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .toolbar {
      if !channels.isEmpty {
        ToolbarItem(placement: .primaryAction) {
          Button(role: .destructive) {
            confirmingRejectAll = true
          } label: {
            Label(folder == .requests ? "Reject All" : "Delete All", systemImage: "trash")
          }
        }
      }
    }
    .confirmationDialog(
      folder == .requests ? "Reject all \(channels.count) requests?" : "Delete all \(channels.count) spam messages?",
      isPresented: $confirmingRejectAll,
      titleVisibility: .visible
    ) {
      Button(folder == .requests ? "Reject All" : "Delete All", role: .destructive) {
        Task { await actions.reject(all: channels) }
      }
    } message: {
      Text("The conversations are removed for you. The senders aren't told.")
    }
    .confirmationDialog(
      folder == .requests ? "Reject this request?" : "Delete this message?",
      isPresented: Binding(get: { pendingReject != nil }, set: { if !$0 { pendingReject = nil } }),
      titleVisibility: .visible,
      presenting: pendingReject
    ) { channel in
      Button(folder == .requests ? "Reject" : "Delete", role: .destructive) {
        Task { await actions.reject(channel) }
      }
    } message: { _ in
      Text("The conversation is removed for you. The sender isn't told.")
    }
    .task(id: channels.map(\.id)) { await loadPreviews() }
  }

  @ViewBuilder
  func row(for channel: DiscordChannel, isIgnored: Bool = false) -> some View {
    Button {
      open(channel.id)
    } label: {
      MessageRequestRow(channel: channel, preview: previews[channel.id])
    }
    .tint(.primary)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(folder == .requests ? "Reject" : "Delete", systemImage: "trash", role: .destructive) {
        pendingReject = channel
      }
      if folder == .requests && channel.type == .dm {
        Button(isIgnored ? "Unignore" : "Ignore", systemImage: isIgnored ? "eye" : "eye.slash") {
          Task { isIgnored ? await actions.unignore(channel) : await actions.ignore(channel) }
        }
        .tint(.orange)
      }
    }
    .swipeActions(edge: .leading) {
      Button(folder == .requests ? "Accept" : "Not Spam", systemImage: "checkmark") {
        Task { await actions.accept(channel) }
      }
      .tint(.green)
    }
    .contextMenu {
      Button(folder == .requests ? "Accept" : "Not Spam", systemImage: "checkmark") {
        Task { await actions.accept(channel) }
      }
      if folder == .requests && channel.type == .dm {
        Button(isIgnored ? "Unignore" : "Ignore", systemImage: isIgnored ? "eye" : "eye.slash") {
          Task { isIgnored ? await actions.unignore(channel) : await actions.ignore(channel) }
        }
      }
      Button(folder == .requests ? "Reject" : "Delete", systemImage: "trash", role: .destructive) {
        pendingReject = channel
      }
    }
  }

  /// The message that started each request, 25 channels per call.
  func loadPreviews() async {
    let missing = (channels + ignored).map(\.id).filter { previews[$0] == nil }
    guard !missing.isEmpty else { return }
    for start in stride(from: 0, to: missing.count, by: 25) {
      let chunk = Array(missing[start..<min(start + 25, missing.count)])
      guard let res = try? await gw.client.getMessageRequestSupplementalData(channelIds: chunk),
        let data = try? res.decode()
      else { return }
      for item in data {
        if let message = item.message_preview { previews[item.channel_id] = message }
      }
    }
  }
}

struct MessageRequestRow: View {
  @Environment(\.gateway) var gw
  var channel: DiscordChannel
  var preview: DiscordChannel.Message?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Group {
        if channel.type == .dm, let user = channel.recipients?.first {
          Profile.Avatar(member: nil, user: user.toPartialUser())
            .profileAnimated(false)
        } else {
          Circle()
            .fill(.secondary.opacity(0.25))
            .overlay {
              Image(systemName: "person.2.fill")
                .foregroundStyle(.secondary)
            }
        }
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(MessagesView.title(of: channel))
            .fontWeight(.semibold)
            .lineLimit(1)
          Spacer(minLength: 4)
          if let date = channel.is_message_request_timestamp?.date {
            Text(date, format: .relative(presentation: .numeric))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if let username = channel.recipients?.first?.username, channel.type == .dm {
          Text("@\(username)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if let preview {
          if WordFilter.hides(preview.content, origin: .otherDM) {
            HiddenContentNote(text: "Hidden by your word filter")
          } else {
            Text(preview.content.isEmpty ? String(localized: "Attachment") : preview.content)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }
      }
    }
    .contentShape(.rect)
  }
}

/// Takes the place of the message field in a request or spam DM: replying
/// would accept it, so the choice comes first.
struct MessageRequestBar: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  var channel: DiscordChannel
  @State var confirmingReject = false

  var actions: MessageRequestActions { .init(gw: gw, appState: appState) }

  var body: some View {
    VStack(spacing: 10) {
      Text(
        channel.isSpam
          ? "Discord thinks this might be spam. Move it to your messages to reply."
          : "This is a message request. Accept it to reply; the sender isn't told until you do."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)

      HStack(spacing: 10) {
        Button(role: .destructive) {
          confirmingReject = true
        } label: {
          Text(channel.isSpam ? "Delete" : "Reject")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        if !channel.isSpam && channel.type == .dm {
          Button {
            Task { await actions.ignore(channel) }
          } label: {
            Text(gw.user.isIgnored(channel) ? "Ignored" : "Ignore")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(gw.user.isIgnored(channel))
        }
        Button {
          Task { await actions.accept(channel) }
        } label: {
          Text(channel.isSpam ? "Not Spam" : "Accept")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
      }
      .controlSize(.large)
    }
    .padding(.horizontal)
    .padding(.vertical, 10)
    .confirmationDialog(
      channel.isSpam ? "Delete this message?" : "Reject this request?",
      isPresented: $confirmingReject,
      titleVisibility: .visible
    ) {
      Button(channel.isSpam ? "Delete" : "Reject", role: .destructive) {
        Task { await actions.reject(channel) }
      }
    } message: {
      Text("The conversation is removed for you. The sender isn't told.")
    }
  }
}
