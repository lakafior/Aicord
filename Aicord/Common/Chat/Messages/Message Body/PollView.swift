//
//  PollView.swift
//  Aicord
//

import AicordKit
import SwiftUI

extension MessageCell {
  /// A message's poll: the question, its answers and, once you voted or it ended,
  /// how the votes split. Reads the poll from the channel store so gateway votes
  /// show up even when the message cell itself doesn't redraw.
  struct PollView: View {
    let messageID: MessageSnowflake
    let fallback: Poll
    let channelStore: ChannelStore

    @Environment(\.gateway) var gw
    @Environment(\.theme) var theme

    @State private var selection: Set<Int> = []
    @State private var showsResults = false
    @State private var isSending = false
    @State private var failed = false

    private var poll: Poll { channelStore.messages[messageID]?.poll ?? fallback }

    private func count(_ answerID: Int?) -> Poll.Results.AnswerCount? {
      poll.results?.answer_counts.first { $0.id == answerID }
    }

    private var totalVotes: Int {
      poll.results?.answer_counts.reduce(0) { $0 + $1.count } ?? 0
    }

    private var hasVoted: Bool {
      poll.results?.answer_counts.contains { $0.me_voted } ?? false
    }

    private var hasEnded: Bool {
      poll.results?.is_finalized == true || (poll.expiry.map { $0.date <= .now } ?? false)
    }

    private var revealsResults: Bool { hasVoted || hasEnded || showsResults }

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(poll.question.text ?? "")
            .font(.headline)
          Text(poll.allow_multiselect ? "Select one or more answers" : "Select one answer")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        VStack(spacing: 6) {
          ForEach(poll.answers, id: \.answer_id) { answer in
            answerRow(answer)
          }
        }

        footer
      }
      .padding(12)
      .frame(maxWidth: 425, alignment: .leading)
      .background(theme.common.tertiaryBackground, in: .rounded)
      .alert("The vote couldn't be sent.", isPresented: $failed) {
        Button("OK", role: .cancel) {}
      }
    }

    @ViewBuilder
    private func answerRow(_ answer: Poll.Answer) -> some View {
      let counted = count(answer.answer_id)
      let votes = counted?.count ?? 0
      let share = totalVotes > 0 ? Double(votes) / Double(totalVotes) : 0
      let isMine = counted?.me_voted == true
      let isSelected = answer.answer_id.map(selection.contains) ?? false
      Button {
        toggle(answer.answer_id)
      } label: {
        HStack(spacing: 8) {
          if let emoji = answer.poll_media.emoji {
            ComponentEmoji(emoji: emoji)
          }
          Text(answer.poll_media.text ?? "")
            .frame(maxWidth: .infinity, alignment: .leading)
          if revealsResults {
            Text("^[\(votes) vote](inflect: true)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(share, format: .percent.precision(.fractionLength(0)))
              .font(.caption.weight(.semibold).monospacedDigit())
              .frame(minWidth: 36, alignment: .trailing)
          }
          if isMine || isSelected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(Color.accentColor)
          } else if !revealsResults {
            Image(systemName: poll.allow_multiselect ? "square" : "circle")
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(alignment: .leading) {
          if revealsResults {
            GeometryReader { geo in
              Rectangle()
                .fill(Color.accentColor.opacity(isMine ? 0.35 : 0.18))
                .frame(width: geo.size.width * share)
            }
          }
        }
        .background(theme.common.secondaryBackground)
        .clipShape(.rounded)
        .overlay {
          if isSelected || isMine {
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor)
          }
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      // not .disabled: that would grey out the results
      .allowsHitTesting(!(hasVoted || hasEnded || isSending))
      .accessibilityAddTraits(isSelected || isMine ? .isSelected : [])
    }

    /// Votes and time left beside the buttons, or above them when that doesn't fit.
    private var footer: some View {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) {
          footerInfo
          Spacer(minLength: 0)
          footerButtons
        }
        VStack(alignment: .leading, spacing: 6) {
          footerInfo
          HStack(spacing: 8) {
            Spacer(minLength: 0)
            footerButtons
          }
        }
      }
    }

    private var footerInfo: some View {
      HStack(spacing: 4) {
        Text("^[\(totalVotes) vote](inflect: true)")
        Text(verbatim: "·")
        if hasEnded {
          Text("Poll closed")
        } else if let expiry = poll.expiry?.date {
          Text("Ends \(expiry, format: .relative(presentation: .named))")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .fixedSize()
    }

    @ViewBuilder
    private var footerButtons: some View {
      HStack(spacing: 8) {
        if !hasEnded {
          if hasVoted {
            Button("Remove Vote") { send([]) }
              .buttonStyle(.borderless)
          } else {
            Button(showsResults ? "Hide Results" : "Show Results") {
              showsResults.toggle()
              if showsResults { selection = [] }
            }
            .buttonStyle(.borderless)
            Button("Vote") { send(Array(selection)) }
              .buttonStyle(.borderedProminent)
              .disabled(selection.isEmpty)
          }
        }
        if isSending {
          ProgressView().controlSize(.small)
        }
      }
      .font(.callout)
      .lineLimit(1)
      .fixedSize()
      .disabled(isSending)
    }

    private func toggle(_ id: Int?) {
      guard let id else { return }
      showsResults = false
      if selection.contains(id) {
        selection.remove(id)
      } else if poll.allow_multiselect {
        selection.insert(id)
      } else {
        selection = [id]
      }
    }

    private func send(_ answerIDs: [Int]) {
      guard let channelID = channelStore.messages[messageID]?.channel_id else { return }
      isSending = true
      Task {
        defer { isSending = false }
        do {
          try await gw.client.createPollVote(
            channelId: channelID, messageId: messageID, answerIds: answerIDs
          ).guardSuccess()
          // the gateway echoes the vote too; applying it twice is a no-op
          channelStore.applyOwnPollVote(messageID: messageID, answerIDs: Set(answerIDs))
          selection = []
        } catch {
          print("[Poll] Vote failed:", error)
          failed = true
        }
      }
    }
  }
}
