//
//  ChannelExportSheet.swift
//  Aicord
//
//  Exports a channel's history to Markdown or PDF, on request, for the share sheet.
//

import AicordKit
import CoreText
import SwiftUI

struct ChannelExportSheet: View {
  let channelId: ChannelSnowflake
  let guildId: GuildSnowflake?
  let title: String

  @Environment(\.dismiss) private var dismiss
  @Environment(\.gateway) private var gw

  enum Range: Hashable {
    case last(Int)
    case since
  }

  enum Format: String, CaseIterable, Identifiable {
    case markdown, pdf
    var id: String { rawValue }
    var fileExtension: String { self == .markdown ? "md" : "pdf" }
  }

  enum Phase {
    case idle
    case fetching(Int)
    case done(URL, Int)
    case failed(String)
  }

  /// The most one export fetches, whatever the range.
  static let maxMessages = 5_000
  /// Pause between pages of 100, to stay well clear of rate limits.
  static let pagePause: Duration = .milliseconds(900)

  @State private var range: Range = .last(500)
  @State private var since = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
  @State private var format: Format = .markdown
  @State private var attachmentLinks = true
  @State private var phase: Phase = .idle
  @State private var task: Task<Void, Never>?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Range", selection: $range) {
            ForEach([100, 500, 1_000, Self.maxMessages], id: \.self) { count in
              Text("Last \(count) Messages").tag(Range.last(count))
            }
            Text("Since a Date").tag(Range.since)
          }
          if range == .since {
            DatePicker("Since", selection: $since, in: ...Date.now)
          }
        } header: {
          Text("Messages")
        } footer: {
          Text(
            "Fetched page by page, about one request a second, so a long history takes a while. At most \(Self.maxMessages) messages."
          )
        }
        Section("Format") {
          Picker("Format", selection: $format) {
            Text(verbatim: "Markdown").tag(Format.markdown)
            Text(verbatim: "PDF").tag(Format.pdf)
          }
          .pickerStyle(.segmented)
          Toggle("Attachments as Links", isOn: $attachmentLinks)
        }
        Section {
          status
        }
      }
      .formStyle(.grouped)
      .disabled(isFetching)
      .navigationTitle("Export Channel")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) {
            task?.cancel()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Export", action: start)
            .disabled(isFetching)
        }
      }
    }
    .onDisappear { task?.cancel() }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 440)
    #endif
  }

  private var isFetching: Bool {
    if case .fetching = phase { return true }
    return false
  }

  @ViewBuilder
  private var status: some View {
    switch phase {
    case .idle:
      Text(verbatim: title)
        .foregroundStyle(.secondary)
    case .fetching(let count):
      HStack {
        ProgressView()
        Text("Fetched \(count) messages…")
      }
    case .done(let url, let count):
      VStack(alignment: .leading, spacing: 8) {
        Text("\(count) messages exported.")
        ShareLink(item: url) {
          Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
        }
      }
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle")
        .foregroundStyle(.red)
    }
  }

  private func start() {
    task?.cancel()
    phase = .fetching(0)
    let range = range
    let since = since
    let format = format
    let links = attachmentLinks
    task = Task {
      do {
        let messages = try await fetch(range: range, since: since)
        guard !Task.isCancelled else { return }
        guard !messages.isEmpty else {
          phase = .failed(String(localized: "No messages in this range."))
          return
        }
        let url = try write(messages, format: format, attachmentLinks: links)
        phase = .done(url, messages.count)
      } catch is CancellationError {
      } catch {
        phase = .failed(error.localizedDescription)
      }
    }
  }

  /// Newest first from Discord; returned oldest first.
  private func fetch(range: Range, since: Date) async throws -> [DiscordChannel.Message] {
    let limit: Int
    switch range {
    case .last(let count): limit = min(count, Self.maxMessages)
    case .since: limit = Self.maxMessages
    }
    var collected: [DiscordChannel.Message] = []
    var before: MessageSnowflake?
    while collected.count < limit {
      try Task.checkCancellation()
      if before != nil { try await Task.sleep(for: Self.pagePause) }
      let page = min(100, limit - collected.count)
      let res = try await gw.client.listMessages(channelId: channelId, before: before, limit: page)
      try res.guardSuccess()
      var fetched = try res.decode()
      var reachedDate = false
      if range == .since {
        let kept = fetched.filter { $0.timestamp.date >= since }
        reachedDate = kept.count < fetched.count
        fetched = kept
      }
      collected += fetched
      phase = .fetching(collected.count)
      guard !reachedDate, fetched.count == page, let oldest = fetched.last else { break }
      before = oldest.id
    }
    return collected.reversed()
  }

  // MARK: - Files

  private struct Entry {
    var author: String
    var date: Date
    var text: String
    var attachments: [(name: String, url: String)]
  }

  private func entries(_ messages: [DiscordChannel.Message]) -> [Entry] {
    messages.map { message in
      let snapshot = gw.snapshot(of: message, guildId: guildId)
      return Entry(
        author: snapshot.authorName.isEmpty ? String(localized: "Unknown User") : snapshot.authorName,
        date: message.timestamp.date,
        text: gw.notifications.plainText(of: message, guildId: guildId),
        attachments: message.attachments.map { ($0.filename, $0.url) }
      )
    }
  }

  private func write(_ messages: [DiscordChannel.Message], format: Format, attachmentLinks: Bool)
    throws -> URL
  {
    let list = entries(messages)
    let safeTitle = title.replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    let day = Date.now.formatted(.iso8601.year().month().day())
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(safeTitle) \(day).\(format.fileExtension)")
    switch format {
    case .markdown:
      try Self.markdown(list, title: title, attachmentLinks: attachmentLinks)
        .write(to: url, atomically: true, encoding: .utf8)
    case .pdf:
      try Self.pdf(list, title: title, attachmentLinks: attachmentLinks).write(to: url)
    }
    return url
  }

  private static func header(count: Int, first: Date?, last: Date?) -> String {
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
    let span = [first, last].compactMap { $0?.formatted(style) }.joined(separator: " – ")
    return String(localized: "Exported from Aicord on \(Date.now.formatted(style)).") + " "
      + String(localized: "\(count) messages") + ", " + span + "."
  }

  private static func markdown(_ list: [Entry], title: String, attachmentLinks: Bool) -> String {
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
    var out = "# \(title)\n\n"
    out += "_" + header(count: list.count, first: list.first?.date, last: list.last?.date) + "_\n\n---\n"
    for entry in list {
      out += "\n**\(entry.author)** · \(entry.date.formatted(style))\n"
      if !entry.text.isEmpty { out += entry.text + "\n" }
      if attachmentLinks {
        for attachment in entry.attachments {
          out += "- [\(attachment.name)](\(attachment.url))\n"
        }
      }
    }
    return out
  }

  // MARK: PDF

  private static func pdf(_ list: [Entry], title: String, attachmentLinks: Bool) throws -> Data {
    let style = Date.FormatStyle(date: .abbreviated, time: .shortened)
    let text = NSMutableAttributedString()
    func add(_ string: String, size: CGFloat, bold: Bool = false, gray: Bool = false, after: CGFloat = 2) {
      let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
      let paragraph = NSMutableParagraphStyle()
      paragraph.paragraphSpacing = after
      paragraph.lineBreakMode = .byWordWrapping
      let color = CGColor(gray: gray ? 0.4 : 0.0, alpha: 1)
      text.append(
        NSAttributedString(
          string: string + "\n",
          attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
          ]))
    }
    add(title, size: 18, bold: true, after: 4)
    add(header(count: list.count, first: list.first?.date, last: list.last?.date), size: 9, gray: true, after: 14)
    for entry in list {
      add("\(entry.author) · \(entry.date.formatted(style))", size: 10, bold: true, after: 1)
      if !entry.text.isEmpty { add(entry.text, size: 10, after: 2) }
      if attachmentLinks {
        for attachment in entry.attachments {
          add("📎 \(attachment.name): \(attachment.url)", size: 8, gray: true, after: 1)
        }
      }
      add("", size: 4)
    }

    var page = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 in points
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &page, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    let framesetter = CTFramesetterCreateWithAttributedString(text)
    let body = CGPath(rect: page.insetBy(dx: 48, dy: 56), transform: nil)
    var start = 0
    let length = text.length
    var pageNumber = 1
    while start < length {
      context.beginPDFPage(nil)
      let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), body, nil)
      CTFrameDraw(frame, context)
      // page number at the bottom
      let number = NSAttributedString(
        string: "\(pageNumber)",
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
            "Helvetica" as CFString, 8, nil),
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.5, alpha: 1),
        ])
      context.textPosition = CGPoint(x: page.midX, y: 28)
      CTLineDraw(CTLineCreateWithAttributedString(number), context)
      context.endPDFPage()
      let visible = CTFrameGetVisibleStringRange(frame)
      guard visible.length > 0 else { break }
      start += visible.length
      pageNumber += 1
    }
    context.closePDF()
    return data as Data
  }
}
