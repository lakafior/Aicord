//
//  PersonNotesStore.swift
//  Aicord
//
//  Private notes and tags about people, kept only on this device.
//

import AicordKit
import SwiftUI

/// Who someone is, in your own words. Discord's own note syncs to your account;
/// this one never leaves the device.
struct PersonNote: Codable, Hashable {
  var text: String = ""
  var tags: [String] = []

  var isEmpty: Bool { text.isEmpty && tags.isEmpty }
}

@MainActor @Observable
final class PersonNotesStore {
  static let shared = PersonNotesStore()

  private static let key = "Aicord.PersonNotes"
  /// Keyed by user ID.
  private(set) var notes: [String: PersonNote]

  private init() {
    let data = UserDefaults.standard.data(forKey: Self.key)
    notes = data.flatMap { try? JSONDecoder().decode([String: PersonNote].self, from: $0) } ?? [:]
  }

  func note(for user: UserSnowflake) -> PersonNote {
    notes[user.rawValue] ?? PersonNote()
  }

  func set(_ note: PersonNote, for user: UserSnowflake) {
    notes[user.rawValue] = note.isEmpty ? nil : note
    if let data = try? JSONEncoder().encode(notes) {
      UserDefaults.standard.set(data, forKey: Self.key)
    }
  }

  /// Every tag in use, for suggestions.
  var allTags: [String] {
    Array(Set(notes.values.flatMap(\.tags)))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  func removeAll() {
    notes = [:]
    UserDefaults.standard.removeObject(forKey: Self.key)
  }
}

/// Small tag capsules, e.g. next to a name in the member list.
struct PersonTagsView: View {
  let user: UserSnowflake
  var limit = 2
  @State private var store = PersonNotesStore.shared

  var body: some View {
    let tags = store.note(for: user).tags
    if !tags.isEmpty {
      HStack(spacing: 3) {
        ForEach(tags.prefix(limit), id: \.self) { tag in
          Text(verbatim: tag)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.tint.opacity(0.18), in: .capsule)
        }
        if tags.count > limit {
          Text(verbatim: "+\(tags.count - limit)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text("Tags: \(tags.joined(separator: ", "))"))
    }
  }
}

/// The private note and tags in a profile, editable in place.
struct PersonNoteEditor: View {
  let user: UserSnowflake
  /// Servers you share, from the profile, as names.
  var mutualServers: [String] = []
  @State private var store = PersonNotesStore.shared
  @State private var text = ""
  @State private var tags: [String] = []
  @State private var newTag = ""
  @State private var loaded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Private Note", systemImage: "lock")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextField("Who is this? Where do you know them from?", text: $text, axis: .vertical)
        .lineLimit(1...6)
        .textFieldStyle(.plain)
        .padding(8)
        .background(.background.secondary.opacity(0.6), in: .rect(cornerRadius: 8))
        .onChange(of: text) { save() }
      FlowLayout(xSpacing: 4, ySpacing: 4) {
        ForEach(tags, id: \.self) { tag in
          Button {
            tags.removeAll { $0 == tag }
            save()
          } label: {
            HStack(spacing: 3) {
              Text(verbatim: tag)
              Image(systemName: "xmark").imageScale(.small)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.2), in: .capsule)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Remove tag \(tag)"))
        }
        TextField("Add Tag", text: $newTag)
          .font(.caption)
          .textFieldStyle(.plain)
          .frame(width: 90)
          .onSubmit(addTag)
        if !suggestions.isEmpty {
          Menu {
            ForEach(suggestions, id: \.self) { tag in
              Button(tag) {
                tags.append(tag)
                save()
              }
            }
          } label: {
            Image(systemName: "tag")
              .font(.caption)
          }
          .menuStyle(.button)
          .buttonStyle(.borderless)
          .accessibilityLabel("Existing Tags")
        }
      }
      if !mutualServers.isEmpty {
        Text("Mutual servers: \(mutualServers.joined(separator: ", "))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      Text("Only on this device. Not shared with Discord.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.top, 8)
    .onAppear {
      guard !loaded else { return }
      let note = store.note(for: user)
      text = note.text
      tags = note.tags
      loaded = true
    }
  }

  private var suggestions: [String] {
    store.allTags.filter { !tags.contains($0) }
  }

  private func addTag() {
    let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    newTag = ""
    guard !tag.isEmpty, !tags.contains(tag) else { return }
    tags.append(String(tag.prefix(24)))
    save()
  }

  private func save() {
    guard loaded else { return }
    store.set(PersonNote(text: text, tags: tags), for: user)
  }
}
