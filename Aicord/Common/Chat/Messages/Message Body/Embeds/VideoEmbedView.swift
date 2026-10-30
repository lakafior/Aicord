//
//  VideoEmbedView.swift
//  Aicord
//
//  Copyright © 2026 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension MessageCell.EmbedsView {
  /// A `video` embed (YouTube, Vimeo, Twitch…): provider, author, title and a
  /// thumbnail with a play button. Videos Discord can proxy play in the viewer;
  /// the rest open the link, in the provider's app when one handles it.
  struct VideoEmbedView: View {
    let embed: Embed
    var message: DiscordChannel.PartialMessage? = nil
    /// Off when "Show Media from Links" is off: the card keeps its text only.
    var showsMedia: Bool = true

    @Environment(\.appState) var appState
    @Environment(\.openURL) var openURL
    @Environment(\.userInterfaceIdiom) var idiom
    @Environment(\.theme) var theme

    private var embedWidth: CGFloat { idiom == .phone ? 345 : 425 }

    private var link: URL? { embed.url.flatMap(URL.init(string:)) }

    /// A file Discord proxies plays inline; a player page doesn't.
    private var playableVideo: Embed.Media? {
      guard let video = embed.video, video.proxy_url != nil else { return nil }
      return video
    }

    private var thumbnailURL: URL? {
      guard let thumbnail = embed.thumbnail ?? embed.image else { return nil }
      return URL(string: thumbnail.proxy_url ?? thumbnail.url.asString)
    }

    private var aspectRatio: CGFloat {
      let media = embed.video ?? embed.thumbnail
      if let width = media?.width, let height = media?.height, width > 0, height > 0 {
        return CGFloat(width) / CGFloat(height)
      }
      return 16 / 9
    }

    private var stripeColor: Color {
      embed.color?.asColor() ?? Color(hexadecimal6: 0x202225)
    }

    var body: some View {
      HStack(spacing: 0) {
        stripeColor.frame(width: 4)
        VStack(alignment: .leading, spacing: 6) {
          if let provider = embed.provider?.name {
            Text(provider)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }

          if let author = embed.author {
            if let url = author.url.flatMap(URL.init(string:)) {
              Link(destination: url) {
                Text(author.name).font(.subheadline.weight(.semibold))
              }
              .tint(theme.markdown.text)
            } else {
              Text(author.name)
                .font(.subheadline.weight(.semibold))
            }
          }

          if let title = embed.title {
            if let link {
              Link(destination: link) {
                Text(title)
                  .font(.headline)
                  .multilineTextAlignment(.leading)
              }
              .tint(Color(hexadecimal6: 0x00aafc))
            } else {
              Text(title).font(.headline)
            }
          }

          if let description = embed.description, !isYouTube {
            Text(description)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(3)
          }

          if showsMedia, thumbnailURL != nil {
            Button(action: play) { thumbnail }
              .buttonStyle(.borderless)
              .accessibilityLabel(Text("Play \(embed.title ?? "video")"))
          }
        }
        .padding(8)
        .frame(maxWidth: embedWidth, alignment: .leading)
        .background(theme.common.tertiaryBackground)
      }
      .clipShape(.rounded)
      .fixedSize(horizontal: false, vertical: true)
    }

    private var isYouTube: Bool {
      let host = link?.host() ?? ""
      return host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be")
    }

    private var thumbnail: some View {
      Color.black
        .aspectRatio(aspectRatio, contentMode: .fit)
        .overlay {
          NukeImage(url: thumbnailURL)
            .resizable()
            .scaledToFill()
        }
        .overlay {
          Image(systemName: "play.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.black.opacity(0.6), in: .circle)
        }
        .clipShape(.rect(cornerRadius: 6))
        .contentShape(.rect)
    }

    private func play() {
      if let video = playableVideo {
        appState.attachmentViewerAttachments = [video]
        appState.attachmentViewerIndex = 0
        appState.attachmentViewerContextMessage = message
        appState.showingAttachmentViewer = true
      } else if let link {
        openURL(link)
      }
    }
  }

  /// The card a poll leaves behind when it ends (message type 46). Its data
  /// comes as embed fields named like `poll_question_text`.
  struct PollResultEmbedView: View {
    let embed: Embed
    @Environment(\.theme) var theme

    private func field(_ name: String) -> String? {
      embed.fields?.first { $0.name == name }?.value
    }

    var body: some View {
      let question = field("poll_question_text") ?? ""
      let total = Int(field("total_votes") ?? "") ?? 0
      let winnerVotes = Int(field("victor_answer_votes") ?? "") ?? 0
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "chart.bar.fill")
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(question)
            .font(.headline)
          if let answer = field("victor_answer_text"), winnerVotes > 0 {
            let emoji = field("victor_answer_emoji_name").map { "\($0) " } ?? ""
            Text("Winner: \(emoji)\(answer)")
              .font(.subheadline)
            Text("^[\(winnerVotes) vote](inflect: true) of \(total)")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text(total == 0 ? "The poll ended with no votes." : "The poll ended in a tie.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(10)
      .frame(maxWidth: 425, alignment: .leading)
      .background(theme.common.tertiaryBackground, in: .rounded)
    }
  }

  /// AutoMod's alert in a server's log channel: the blocked message and the rule.
  struct AutoModerationEmbedView: View {
    let embed: Embed
    @Environment(\.theme) var theme

    private func field(_ name: String) -> String? {
      embed.fields?.first { $0.name == name }?.value
    }

    var body: some View {
      HStack(spacing: 0) {
        Color.orange.frame(width: 4)
        VStack(alignment: .leading, spacing: 6) {
          Label("AutoMod", systemImage: "shield.lefthalf.filled")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          if let description = embed.description, !description.isEmpty {
            Text(description)
          }
          if let rule = field("rule_name") {
            Text("Rule: \(rule)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let keyword = field("keyword") {
            Text("Keyword: \(keyword)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(8)
        .frame(maxWidth: 425, alignment: .leading)
        .background(theme.common.tertiaryBackground)
      }
      .clipShape(.rounded)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}
