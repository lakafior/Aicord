//
//  FormattedMessageSheet.swift
//  Aicord
//
//  A bigger editor for Discord markdown, with a live preview.
//

import AicordKit
import SwiftUI

struct FormattedMessageSheet: View {
  var channel: ChannelStore
  /// Sends the text (with the field's reply and attachments).
  var onSend: (String) -> Void
  /// Puts the text back into the message field.
  var onMoveToField: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.gateway) private var gw
  @State private var text: String
  @State private var selection: TextSelection?
  @State private var showingTimestamp = false
  @State private var showingMention = false
  @State private var showingEmoji = false

  init(
    channel: ChannelStore,
    initialText: String,
    onSend: @escaping (String) -> Void,
    onMoveToField: @escaping (String) -> Void
  ) {
    self.channel = channel
    self.onSend = onSend
    self.onMoveToField = onMoveToField
    self._text = State(initialValue: initialText)
  }

  static let codeLanguages = [
    "swift", "python", "js", "ts", "json", "bash", "c", "cpp", "cs", "java", "kotlin",
    "go", "rust", "html", "css", "sql", "yaml", "diff", "md", "ansi",
  ]

  private var characterLimit: Int {
    switch gw.user.premiumKind {
    case .nitro, .nitroClassic: 4000
    default: 2000
    }
  }

  private var trimmed: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 12) {
          editor.frame(minWidth: 320)
          preview.frame(minWidth: 320)
        }
        .frame(minWidth: 700)
        VStack(spacing: 12) {
          editor
          preview
        }
      }
      .padding()
      .navigationTitle("Formatted Message")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 10) {
          Button {
            onMoveToField(text)
            dismiss()
          } label: {
            Label("Move to Message Field", systemImage: "arrow.down.to.line")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.glass)
          Button {
            onSend(trimmed)
            dismiss()
          } label: {
            Label("Send", systemImage: "paperplane.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.glassProminent)
          .disabled(trimmed.isEmpty || trimmed.count > characterLimit)
          .keyboardShortcut(.return, modifiers: .command)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.bottom, 8)
      }
      .sheet(isPresented: $showingTimestamp) {
        TimestampInsertSheet { insert($0) }
      }
      .sheet(isPresented: $showingMention) {
        MentionInsertSheet(channel: channel) { insert($0) }
      }
      #if os(iOS)
        .sheet(isPresented: $showingEmoji) {
          EmojiPicker()
            .guild(channel.guildStore?.guildId)
            .onPickedEmoji { insert(Self.text(for: $0)) }
            .presentationDetents([.medium, .large])
        }
      #endif
    }
    #if os(macOS)
      .frame(minWidth: 520, idealWidth: 820, minHeight: 480, idealHeight: 560)
    #endif
  }

  // MARK: - Editor

  private var editor: some View {
    VStack(alignment: .leading, spacing: 8) {
      insertBar
      TextEditor(text: $text, selection: $selection)
        .font(.body.monospaced())
        .scrollContentBackground(.hidden)
        .padding(6)
        .frame(minHeight: 160)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
      HStack {
        Spacer()
        Text("\(trimmed.count) / \(characterLimit)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(trimmed.count > characterLimit ? .red : .secondary)
      }
    }
  }

  private var insertBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        Menu {
          ForEach(MessageFormat.allCases) { format in
            Button(format.title, systemImage: format.systemImage) { apply(format) }
          }
        } label: {
          Label("Style", systemImage: "textformat")
        }
        Menu {
          Button("Heading 1") { prefixLines("# ") }
          Button("Heading 2") { prefixLines("## ") }
          Button("Heading 3") { prefixLines("### ") }
          Button("Small Text") { prefixLines("-# ") }
        } label: {
          Label("Heading", systemImage: "textformat.size")
        }
        Menu {
          Button("Bulleted List", systemImage: "list.bullet") { prefixLines("- ") }
          Button("Numbered List", systemImage: "list.number") { numberLines() }
          Button("Quote", systemImage: "text.quote") { prefixLines("> ") }
        } label: {
          Label("List", systemImage: "list.bullet")
        }
        Menu {
          Button("Plain") { codeBlock(language: "") }
          Divider()
          ForEach(Self.codeLanguages, id: \.self) { language in
            Button(language) { codeBlock(language: language) }
          }
        } label: {
          Label("Code Block", systemImage: "curlybraces")
        }
        Button("Timestamp", systemImage: "clock") { showingTimestamp = true }
        Button("Mention", systemImage: "at") { showingMention = true }
        Button("Emoji", systemImage: "face.smiling") { showingEmoji.toggle() }
          #if os(macOS)
            .popover(isPresented: $showingEmoji, arrowEdge: .bottom) {
              EmojiPicker()
                .guild(channel.guildStore?.guildId)
                .onPickedEmoji { insert(Self.text(for: $0)) }
            }
          #endif
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.bordered)
      .menuStyle(.button)
      .controlSize(.regular)
    }
  }

  // MARK: - Preview

  private var preview: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Preview")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ScrollView {
        Group {
          if trimmed.isEmpty {
            Text("Nothing to preview yet.")
              .foregroundStyle(.secondary)
          } else {
            MarkdownText(content: text, channelStore: channel)
              .handlesInteractions(false)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
      }
      .frame(minHeight: 120)
      .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
  }

  // MARK: - Editing

  /// The selection as UTF-16, or the end of the text.
  private var selectedRange: NSRange {
    if case .selection(let range) = selection?.indices,
      range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
    {
      return NSRange(range, in: text)
    }
    return NSRange(location: (text as NSString).length, length: 0)
  }

  private func replace(_ range: NSRange, with replacement: String, select: NSRange) {
    let updated = (text as NSString).replacingCharacters(in: range, with: replacement)
    text = updated
    if let newRange = Range(select, in: updated) {
      selection = TextSelection(range: newRange)
    }
  }

  private func apply(_ format: MessageFormat) {
    let edit = format.edit(in: text, selection: selectedRange)
    replace(edit.range, with: edit.replacement, select: edit.selection)
  }

  private func insert(_ snippet: String) {
    let range = selectedRange
    // keep mentions, emoji and timestamps apart from the word before them
    var snippet = snippet
    if range.location > 0,
      let previous = (text as NSString).substring(
        with: NSRange(location: range.location - 1, length: 1)).unicodeScalars.first,
      !CharacterSet.whitespacesAndNewlines.contains(previous)
    {
      snippet = " " + snippet
    }
    let end = NSRange(location: range.location + (snippet as NSString).length, length: 0)
    replace(range, with: snippet, select: end)
  }

  /// The whole lines the selection touches.
  private var selectedLines: NSRange {
    (text as NSString).lineRange(for: selectedRange)
  }

  private func transformLines(_ transform: ([String]) -> [String]) {
    let ns = text as NSString
    let range = selectedLines
    var block = ns.substring(with: range)
    let trailingNewline = block.hasSuffix("\n")
    if trailingNewline { block.removeLast() }
    let lines = transform(block.components(separatedBy: "\n"))
    let replacement = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
    let selectionLength = (replacement as NSString).length - (trailingNewline ? 1 : 0)
    replace(
      range, with: replacement,
      select: NSRange(location: range.location + selectionLength, length: 0))
  }

  /// Toggles a line prefix such as `# ` or `> ` on every selected line.
  private func prefixLines(_ prefix: String) {
    transformLines { lines in
      let allHave = lines.allSatisfy { $0.hasPrefix(prefix) }
      return lines.map { allHave ? String($0.dropFirst(prefix.count)) : prefix + $0 }
    }
  }

  private func numberLines() {
    transformLines { lines in
      lines.enumerated().map { "\($0.offset + 1). \($0.element)" }
    }
  }

  private func codeBlock(language: String) {
    let range = selectedRange
    let selected = (text as NSString).substring(with: range)
    let ns = text as NSString
    // Fences must start on their own line.
    let needsLeadingBreak =
      range.location > 0 && ns.substring(with: NSRange(location: range.location - 1, length: 1)) != "\n"
    let open = (needsLeadingBreak ? "\n" : "") + "```\(language)\n"
    let replacement = open + selected + "\n```"
    let caret = range.location + (open as NSString).length + (selected as NSString).length
    replace(range, with: replacement, select: NSRange(location: caret, length: 0))
  }

  static func text(for emoji: Emoji) -> String {
    if let id = emoji.id, let name = emoji.name {
      return emoji.animated == true
        ? DiscordUtils.customAnimatedEmoji(name: name, id: id)
        : DiscordUtils.customEmoji(name: name, id: id)
    }
    return emoji.name ?? ""
  }
}

// MARK: - Timestamp

/// Picks a date and a Discord timestamp style, and gives back `<t:…:style>`.
struct TimestampInsertSheet: View {
  var onInsert: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var date = Date.now.addingTimeInterval(3600)
  @State private var style = "F"

  static let styles: [(code: String, name: LocalizedStringKey)] = [
    ("t", "Short Time"), ("T", "Long Time"), ("d", "Short Date"), ("D", "Long Date"),
    ("f", "Short Date and Time"), ("F", "Long Date and Time"), ("R", "Relative"),
  ]

  private var tag: String { "<t:\(Int(date.timeIntervalSince1970)):\(style)>" }

  var body: some View {
    NavigationStack {
      Form {
        DatePicker("Date", selection: $date)
        Picker("Style", selection: $style) {
          ForEach(Self.styles, id: \.code) { style in
            Text(style.name).tag(style.code)
          }
        }
        Section("Preview") {
          MarkdownText(content: tag).handlesInteractions(false)
          Text(tag)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Timestamp")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Insert") {
            onInsert(tag)
            dismiss()
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    #if os(macOS)
      .frame(minWidth: 380, minHeight: 360)
    #endif
  }
}

// MARK: - Mentions

/// Members, roles and channels of the server (or the people in a DM), to mention.
struct MentionInsertSheet: View {
  var channel: ChannelStore
  var onInsert: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.gateway) private var gw
  @State private var query = ""

  private struct Entry: Identifiable {
    var id: String { tag }
    var name: String
    var tag: String
    var systemImage: String
  }

  private var people: [Entry] {
    var entries: [Entry]
    if let guild = channel.guildStore {
      entries = guild.loadedMembers.compactMap { member in
        guard let user = member.user else { return nil }
        let name = member.nick ?? user.global_name ?? user.username
        return Entry(name: name, tag: "<@\(user.id.rawValue)>", systemImage: "person")
      }
    } else {
      var users = channel.channel?.recipients ?? []
      if let me = gw.user.currentUser { users.append(me) }
      entries = users.map {
        Entry(
          name: $0.global_name ?? $0.username, tag: "<@\($0.id.rawValue)>",
          systemImage: "person")
      }
    }
    return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var roles: [Entry] {
    (channel.guildStore?.allRoles ?? []).map { role in
      if role.name == "@everyone" {
        return Entry(name: "@everyone", tag: "@everyone", systemImage: "person.3")
      }
      return Entry(name: "@" + role.name, tag: "<@&\(role.id.rawValue)>", systemImage: "tag")
    }
    + (channel.guildStore == nil ? [] : [Entry(name: "@here", tag: "@here", systemImage: "person.3")])
  }

  private var channels: [Entry] {
    guard let guild = channel.guildStore else { return [] }
    return guild.channels.values
      .filter { $0.type != .guildCategory }
      .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
      .map {
        Entry(name: "#" + ($0.name ?? ""), tag: "<#\($0.id.rawValue)>", systemImage: "number")
      }
  }

  private func filtered(_ entries: [Entry]) -> [Entry] {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return entries }
    return entries.filter { $0.name.localizedCaseInsensitiveContains(q) }
  }

  var body: some View {
    NavigationStack {
      List {
        section("People", filtered(people))
        section("Roles", filtered(roles))
        section("Channels", filtered(channels))
      }
      .searchable(text: $query)
      .navigationTitle("Mention")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    #if os(macOS)
      .frame(minWidth: 360, minHeight: 420)
    #endif
  }

  @ViewBuilder
  private func section(_ title: LocalizedStringKey, _ entries: [Entry]) -> some View {
    if !entries.isEmpty {
      Section(title) {
        ForEach(entries) { entry in
          Button {
            onInsert(entry.tag + " ")
            dismiss()
          } label: {
            Label(entry.name, systemImage: entry.systemImage)
          }
          .foregroundStyle(.primary)
        }
      }
    }
  }
}
