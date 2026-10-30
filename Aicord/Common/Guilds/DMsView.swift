//
//  DMsView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 06/10/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

//
//  DMsView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 22/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct DMsView: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.userInterfaceIdiom) var idiom

  /// What the shortcuts above the list open on Mac and iPad.
  enum Panel: Identifiable {
    case friends, search, folder(MessageFolder)
    var id: String {
      switch self {
      case .friends: "friends"
      case .search: "search"
      case .folder(let folder): "folder-\(folder)"
      }
    }
  }
  @State var panel: Panel? = nil

  var body: some View {
    // requests and spam have their own folders
    let channels = gw.user.privateChannels.values.filter {
      !$0.isPendingMessageRequest && !$0.isSpam
    }
    List(selection: ChannelButton.selection(appState)) {
      if idiom != .phone {
        shortcuts
      }

      Section {
        ForEach(channels) { channel in
          ChannelButton(channel: channel)
            .listRowSeparator(.hidden)
        }
      } header: {
        if idiom == .phone {
          Text("Direct Messages")
        }
      }
    }
    .listStyle(.sidebar)
    .sheet(item: $panel) { panel in
      sheet(for: panel)
        #if os(macOS)
          .frame(width: 460, height: 600)
        #endif
    }
  }

  /// Friends, Search, Message Requests and Spam, which live in the Messages and
  /// Search tabs on iPhone.
  var shortcuts: some View {
    Section {
      shortcut("Friends", symbol: "person.2", count: gw.user.incomingFriendRequestCount) {
        panel = .friends
      }
      shortcut("Search", symbol: "magnifyingglass", count: 0) { panel = .search }
      shortcut(
        "Message Requests", symbol: MessageFolder.requests.symbol,
        count: gw.user.messageRequests().count
      ) { panel = .folder(.requests) }
      shortcut("Spam", symbol: MessageFolder.spam.symbol, count: gw.user.spamChannels.count, quiet: true) {
        panel = .folder(.spam)
      }
    }
  }

  func shortcut(
    _ title: LocalizedStringKey, symbol: String, count: Int, quiet: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Label(title, systemImage: symbol)
        Spacer()
        if count > 0 {
          if quiet {
            Text("\(count)")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else {
            MentionCountBadge(count: count)
          }
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .selectionDisabled()
  }

  @ViewBuilder
  func sheet(for panel: Panel) -> some View {
    switch panel {
    case .friends:
      FriendsSheet(open: open(user:))
    case .search:
      SearchSheet()
    case .folder(let folder):
      NavigationStack {
        MessageFolderView(folder: folder) { channel in
          self.panel = nil
          open(channel: channel)
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") { self.panel = nil }
          }
        }
      }
      .sheetErrorAlert()
    }
  }

  func open(channel: ChannelSnowflake) {
    appState.selectedGuild = nil
    appState.selectedChannel = channel
  }

  /// Opens the existing DM with someone, or creates one.
  func open(user: UserSnowflake) {
    if let existing = gw.user.privateChannels.values.first(where: {
      $0.type == .dm && $0.recipients?.first?.id == user
    }) {
      open(channel: existing.id)
      return
    }
    Task {
      do {
        let res = try await gw.client.createDm(payload: .init(recipient: user))
        try res.guardSuccess()
        let channel = try res.decode()
        gw.user.privateChannels[channel.id] = channel
        open(channel: channel.id)
      } catch {
        appState.error = error
      }
    }
  }
}

/// Search in a sheet on Mac and iPad, closed when a result is opened.
private struct SearchSheet: View {
  @Environment(\.dismiss) var dismiss

  var body: some View {
    SearchView(onOpen: { dismiss() }, onClose: { dismiss() })
  }
}
