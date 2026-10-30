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
  @Environment(\.theme) var theme

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
    ScrollView {
      if idiom == .phone {
        VStack(spacing: 0) {
          VStack(alignment: .leading) {
            Text("Direct Messages")
              .font(.title3)
              .bold()
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding()

          Divider()
        }
      }

      if idiom != .phone {
        shortcuts
      }

      // requests and spam have their own folders
      let channels = gw.user.privateChannels.values.filter {
        !$0.isPendingMessageRequest && !$0.isSpam
      }
      LazyVStack(spacing: 4) {
        ForEach(channels) { channel in
          ChannelButton(channels: [:], channel: channel)
        }
      }
      .padding(.vertical, 4)
    }
    // macos 26/27 bug workaround
    .padding(.top, 1)
    .frame(maxWidth: .infinity)
    .background(theme.common.secondaryBackground.opacity(0.5))
    .roundedCorners(radius: 10, corners: .topLeft)
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
    VStack(spacing: 2) {
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
      Divider()
        .padding(.top, 4)
    }
    .padding(.horizontal, 6)
    .padding(.top, 6)
  }

  func shortcut(
    _ title: LocalizedStringKey, symbol: String, count: Int, quiet: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .frame(width: 22)
          .foregroundStyle(.secondary)
        Text(title)
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
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
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
