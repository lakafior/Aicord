//
//  AicordWidgets.swift
//  AicordWidgets
//
//  Created by Lakafior on 01/11/2026.
//
//  Unread and mentions from the file the app writes to the App Group. The
//  extension never connects to Discord and has no token; the numbers are as
//  fresh as the last time Aicord ran.
//

import SwiftUI
import WidgetKit

@main
struct AicordWidgets: WidgetBundle {
  var body: some Widget {
    UnreadWidget()
    #if os(iOS)
      VoiceCallLiveActivity()
    #endif
  }
}

struct UnreadEntry: TimelineEntry {
  var date: Date
  /// `nil` before the app has written anything, or after logging out.
  var snapshot: WidgetSnapshot?
}

struct UnreadProvider: TimelineProvider {
  func placeholder(in context: Context) -> UnreadEntry {
    UnreadEntry(date: .now, snapshot: .preview)
  }

  func getSnapshot(in context: Context, completion: @escaping (UnreadEntry) -> Void) {
    completion(
      UnreadEntry(date: .now, snapshot: context.isPreview ? .preview : WidgetSnapshot.load()))
  }

  /// One entry; the app reloads the timeline when the counts change.
  func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadEntry>) -> Void) {
    completion(Timeline(entries: [UnreadEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .never))
  }
}

struct UnreadWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: UnreadProvider()) { entry in
      UnreadWidgetView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Unread")
    .description("Mentions and unread messages, as of the last time Aicord was open.")
    #if os(iOS)
      .supportedFamilies([
        .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline,
      ])
    #else
      .supportedFamilies([.systemSmall, .systemMedium])
    #endif
  }
}

struct UnreadWidgetView: View {
  let entry: UnreadEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let snapshot = entry.snapshot {
      content(snapshot)
    } else {
      switch family {
      #if os(iOS)
        case .accessoryCircular, .accessoryInline, .accessoryRectangular:
          Image(systemName: "bubble.left.and.bubble.right")
      #endif
      default:
        VStack(spacing: 6) {
          Image(systemName: "bubble.left.and.bubble.right")
            .font(.title2)
          Text("Open Aicord to see your unread messages here.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func content(_ snapshot: WidgetSnapshot) -> some View {
    switch family {
    #if os(iOS)
      case .accessoryCircular:
        ZStack {
          AccessoryWidgetBackground()
          VStack(spacing: 0) {
            Image(systemName: "at")
              .font(.caption)
            Text(snapshot.mentions, format: .number)
              .font(.title3.bold())
              .minimumScaleFactor(0.5)
          }
        }
        .widgetURL(snapshot.places.first?.link.url)
      case .accessoryInline:
        Text("\(snapshot.mentions) mentions")
      case .accessoryRectangular:
        VStack(alignment: .leading, spacing: 2) {
          Label("\(snapshot.mentions) mentions", systemImage: "at")
            .font(.headline)
          Text("\(snapshot.unreadDirectMessages) unread DMs")
          Text("\(snapshot.unreadServers) servers with unread")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(snapshot.places.first?.link.url)
    #endif
    case .systemMedium:
      HStack(alignment: .top, spacing: 16) {
        counts(snapshot)
        places(snapshot, limit: 4)
      }
    default:
      VStack(alignment: .leading, spacing: 8) {
        counts(snapshot)
        Spacer(minLength: 0)
        if let first = snapshot.places.first {
          Link(destination: first.link.url) { placeRow(first) }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .widgetURL(snapshot.places.first?.link.url)
    }
  }

  private func counts(_ snapshot: WidgetSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Image(systemName: "at")
          .foregroundStyle(.red)
        Text(snapshot.mentions, format: .number)
          .font(.largeTitle.bold())
          .contentTransition(.numericText())
          .minimumScaleFactor(0.5)
      }
      Text("\(snapshot.unreadDirectMessages) unread DMs")
        .font(.caption)
      Text("\(snapshot.unreadServers) servers with unread")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(snapshot.updatedAt, style: .relative)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
  }

  @ViewBuilder
  private func places(_ snapshot: WidgetSnapshot, limit: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if snapshot.places.isEmpty {
        Text("No mentions")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ForEach(snapshot.places.prefix(limit)) { place in
        Link(destination: place.link.url) { placeRow(place) }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func placeRow(_ place: WidgetSnapshot.Place) -> some View {
    HStack(spacing: 6) {
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: place.name)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        if !place.server.isEmpty {
          Text(verbatim: place.server)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      Text(place.mentions, format: .number)
        .font(.caption2.bold())
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.red, in: .capsule)
        .foregroundStyle(.white)
    }
  }
}

extension WidgetSnapshot {
  static let preview = WidgetSnapshot(
    mentions: 3, unreadDirectMessages: 2, unreadServers: 4,
    places: [
      .init(
        link: AicordLink(guildID: "1", channelID: "2"), name: "#general", server: "Aicord",
        mentions: 2),
      .init(link: AicordLink(guildID: nil, channelID: "3"), name: "Alex", server: "", mentions: 1),
    ],
    updatedAt: .now)
}
