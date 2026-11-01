//
//  SavedItemsView.swift
//  Aicord
//
//  Created by Lakafior on 01/11/2026.
//

import AicordKit
import SwiftUI

// MARK: - Message Menu

/// Remind Me and Save Message in a message's menu.
struct SavedItemsMenuItems: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  let message: DiscordChannel.Message
  let guildId: GuildSnowflake?

  var body: some View {
    let store = SavedItemsStore.shared
    Menu {
      ForEach(SavedItemsStore.ReminderTime.allCases, id: \.self) { time in
        Button(String(localized: time.title)) {
          let snapshot = snapshot
          Task { await store.remind(snapshot, at: time.date) }
        }
      }
      Button("Custom Time…") {
        appState.reminderTarget = snapshot
      }
    } label: {
      Label("Remind Me", systemImage: "alarm")
    }
    let saved = store.isSaved(message.id)
    Button {
      store.toggleSaved(snapshot)
    } label: {
      if saved {
        Label("Remove from Saved", systemImage: "bookmark.slash")
      } else {
        Label("Save Message", systemImage: "bookmark")
      }
    }
  }

  private var snapshot: MessageSnapshot { gw.snapshot(of: message, guildId: guildId) }
}

// MARK: - Custom Time

extension View {
  func reminderSheet() -> some View {
    self.modifier(ReminderSheetModifier())
  }
}

private struct ReminderSheetModifier: ViewModifier {
  @Environment(\.appState) var appState

  func body(content: Content) -> some View {
    @Bindable var appState = appState
    content
      .sheet(item: $appState.reminderTarget) { message in
        ReminderTimeSheet(message: message)
          #if os(macOS)
            .frame(width: 380, height: 300)
          #endif
      }
  }
}

struct ReminderTimeSheet: View {
  @Environment(\.dismiss) var dismiss
  let message: MessageSnapshot
  @State private var date = Date.now.addingTimeInterval(3_600)

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SnapshotRow(message: message)
        }
        DatePicker("Remind Me", selection: $date, in: Date.now...)
      }
      .formStyle(.grouped)
      .navigationTitle("Remind Me")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Set") {
            let message = message
            let date = date
            Task { await SavedItemsStore.shared.remind(message, at: date) }
            dismiss()
          }
        }
      }
    }
  }
}

// MARK: - Lists

/// Saved messages, reminders and ghost pings, all kept on this device.
struct SavedItemsView: View {
  enum Page: Hashable { case saved, reminders, ghostPings }

  @State var page: Page = .saved
  /// Opens the channel on the message.
  var open: (MessageSnapshot) -> Void

  private var store: SavedItemsStore { .shared }

  var body: some View {
    List {
      Picker("Show", selection: $page) {
        Text("Saved").tag(Page.saved)
        Text("Reminders").tag(Page.reminders)
        Text("Ghost Pings").tag(Page.ghostPings)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

      switch page {
      case .saved: savedList
      case .reminders: remindersList
      case .ghostPings: ghostPingsList
      }
    }
    .navigationTitle("Saved")
  }

  @ViewBuilder
  private var savedList: some View {
    if store.saved.isEmpty {
      empty(
        "No Saved Messages", symbol: "bookmark",
        description: "Save a message from its menu to find it here.")
    } else {
      Section {
        ForEach(store.saved) { item in
          row(item.message) { store.removeSaved([item.id]) }
        }
        .onDelete { store.removeSaved(Set($0.map { store.saved[$0].id })) }
      } footer: {
        Text("Only on this device.")
      }
    }
  }

  @ViewBuilder
  private var remindersList: some View {
    if store.reminders.isEmpty {
      empty(
        "No Reminders", symbol: "alarm",
        description: "Choose Remind Me in a message's menu to get a notification about it later.")
    } else {
      let upcoming = store.reminders.filter { $0.fireDate > .now }
      let past = store.reminders.filter { $0.fireDate <= .now }
      if !upcoming.isEmpty {
        Section("Upcoming") {
          ForEach(upcoming) { reminder in
            row(reminder.message, detail: reminder.fireDate) {
              store.removeReminders([reminder.id])
            }
          }
          .onDelete { store.removeReminders(Set($0.map { upcoming[$0].id })) }
        }
      }
      if !past.isEmpty {
        Section("Past") {
          ForEach(past) { reminder in
            row(reminder.message, detail: reminder.fireDate) {
              store.removeReminders([reminder.id])
            }
          }
          .onDelete { store.removeReminders(Set($0.map { past[$0].id })) }
        }
      }
    }
  }

  @ViewBuilder
  private var ghostPingsList: some View {
    if store.ghostPings.isEmpty {
      empty(
        "No Ghost Pings", symbol: "bell.slash",
        description:
          "When a message that mentioned you is deleted, it shows up here. Turn this off in Settings → Notifications."
      )
    } else {
      Section {
        ForEach(store.ghostPings) { ping in
          row(ping.message, detail: ping.deletedAt, deleted: true) {
            store.removeGhostPings([ping.id])
          }
        }
        .onDelete { store.removeGhostPings(Set($0.map { store.ghostPings[$0].id })) }
      } footer: {
        Text("Messages that mentioned you and were deleted while Aicord was running.")
      }
    }
  }

  private func row(
    _ message: MessageSnapshot, detail: Date? = nil, deleted: Bool = false,
    remove: @escaping () -> Void
  ) -> some View {
    Button {
      open(message)
    } label: {
      SnapshotRow(message: message, detail: detail, deleted: deleted)
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Go to Message", systemImage: "arrow.right.circle") { open(message) }
      Button("Remove", systemImage: "trash", role: .destructive, action: remove)
    }
  }

  private func empty(
    _ title: LocalizedStringKey, symbol: String, description: LocalizedStringKey
  ) -> some View {
    ContentUnavailableView(title, systemImage: symbol, description: Text(description))
      .listRowBackground(Color.clear)
  }
}

/// A kept message: who wrote it, where, when, and what it said.
struct SnapshotRow: View {
  let message: MessageSnapshot
  /// A reminder's time, or when a ghost ping was deleted.
  var detail: Date? = nil
  var deleted = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      NukeImage(url: message.avatarURL.flatMap(URL.init(string:)))
        .resizable()
        .scaledToFill()
        .frame(width: 32, height: 32)
        .clipShape(.circle)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(verbatim: message.authorName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
          Text(verbatim: message.place)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(message.date, format: .dateTime.day().month(.abbreviated).hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if !message.text.isEmpty {
          Text(verbatim: message.text)
            .font(.subheadline)
            .lineLimit(4)
            .strikethrough(deleted, color: .secondary)
        }
        if let detail {
          Label {
            Text(detail, format: .relative(presentation: .named))
          } icon: {
            Image(systemName: deleted ? "trash" : "alarm")
          }
          .font(.caption)
          .foregroundStyle(deleted ? Color.red : Color.accentColor)
        }
      }
    }
    .contentShape(.rect)
  }
}
