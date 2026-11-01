//
//  OfflineReaderView.swift
//  Aicord
//
//  Reads the messages saved by OfflineCache, without a connection.
//

import AicordKit
import SwiftUI

struct OfflineReaderView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var cache = OfflineCache.shared
  @State private var network = NetworkMonitor.shared

  var body: some View {
    NavigationStack {
      List {
        if !network.isOnline {
          Label("You're offline. These are the messages saved on this device.", systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        ForEach(cache.channels) { channel in
          NavigationLink {
            OfflineChannelView(channelID: channel.id)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: channel.place.isEmpty ? String(localized: "Direct Message") : channel.place)
                .lineLimit(1)
              Text("Saved \(Text(channel.savedAt, format: .relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .onDelete { offsets in
          for index in offsets { cache.remove(cache.channels[index].id) }
        }
      }
      .overlay {
        if cache.channels.isEmpty {
          ContentUnavailableView(
            "No Saved Messages", systemImage: "tray",
            description: Text("Channels you open are saved here to read without a connection."))
        }
      }
      .navigationTitle("Saved for Offline")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 480, minHeight: 520)
    #endif
  }
}

/// One saved channel, oldest message first.
struct OfflineChannelView: View {
  let channelID: String
  @State private var channel: OfflineChannel?

  var body: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(channel?.messages ?? []) { message in
          OfflineMessageRow(message: message)
            .id(message.id)
        }
      }
      .listStyle(.plain)
      .onAppear {
        channel = OfflineCache.shared.load(channelID)
        if let last = channel?.messages.last?.id {
          proxy.scrollTo(last, anchor: .bottom)
        }
      }
    }
    .navigationTitle(Text(verbatim: channel?.place ?? ""))
  }
}

struct OfflineMessageRow: View {
  let message: OfflineMessage

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      NukeImage(url: message.message.avatarURL.flatMap(URL.init(string:)))
        .resizable()
        .scaledToFill()
        .frame(width: 32, height: 32)
        .clipShape(.circle)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(verbatim: message.message.authorName)
            .font(.subheadline.weight(.semibold))
          Text(message.message.date, format: .dateTime.day().month(.abbreviated).hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if !message.message.text.isEmpty {
          MarkdownText(content: message.message.text)
            .handlesInteractions(false)
        }
        ForEach(message.attachments, id: \.url) { attachment in
          if let url = URL(string: attachment.url) {
            Link(destination: url) {
              Label(attachment.filename, systemImage: "paperclip")
                .font(.caption)
            }
          }
        }
      }
    }
  }
}

/// "Offline" over the chat while there's no network.
struct OfflinePill: View {
  @State private var network = NetworkMonitor.shared

  var body: some View {
    if !network.isOnline {
      Label("Offline", systemImage: "wifi.slash")
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .padding(.top, 6)
        .transition(.opacity)
        .accessibilityLabel("Offline. New messages won't load until you're connected.")
    }
  }
}
