//
//  CreatePollSheet.swift
//  Aicord
//

import AicordKit
import SwiftUI

/// Discord's poll form: a question, up to ten answers, how long it stays open
/// and whether people can pick more than one answer.
struct CreatePollSheet: View {
  var vm: ChannelStore
  @Environment(\.gateway) var gw
  @Environment(\.dismiss) var dismiss

  private struct Draft: Identifiable {
    let id = UUID()
    var text = ""
  }

  /// The lengths Discord's client offers, in hours.
  private static let durations: [(hours: Int, label: LocalizedStringKey)] = [
    (1, "1 hour"), (4, "4 hours"), (8, "8 hours"), (24, "24 hours"),
    (72, "3 days"), (168, "1 week"), (336, "2 weeks"),
  ]

  @State private var question = ""
  @State private var answers: [Draft] = [Draft(), Draft()]
  @State private var hours = 24
  @State private var allowsMultiple = false
  @State private var isSending = false
  @State private var error: String?
  @FocusState private var focused: UUID?

  private var filledAnswers: [String] {
    answers.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  private var canPost: Bool {
    !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !filledAnswers.isEmpty
      && !isSending
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Question") {
          TextField("What do you want to ask?", text: $question, axis: .vertical)
            .onChange(of: question) { _, new in
              if new.count > 300 { question = String(new.prefix(300)) }
            }
        }
        Section {
          ForEach($answers) { $answer in
            HStack {
              TextField("Answer", text: $answer.text)
                .focused($focused, equals: answer.id)
                .onChange(of: answer.text) { _, new in
                  if new.count > 55 { answer.text = String(new.prefix(55)) }
                }
              if answers.count > 1 {
                Button {
                  answers.removeAll { $0.id == answer.id }
                } label: {
                  Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove Answer"))
              }
            }
          }
          if answers.count < 10 {
            Button {
              let draft = Draft()
              answers.append(draft)
              focused = draft.id
            } label: {
              Label("Add Answer", systemImage: "plus")
            }
          }
        } header: {
          Text("Answers")
        } footer: {
          Text("Up to 10 answers, 55 characters each.")
        }
        Section {
          Picker("Duration", selection: $hours) {
            ForEach(Self.durations, id: \.hours) { Text($0.label).tag($0.hours) }
          }
          Toggle("Allow Multiple Answers", isOn: $allowsMultiple)
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.red)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Create Poll")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if isSending {
            ProgressView()
          } else {
            Button("Post") { post() }
              .disabled(!canPost)
          }
        }
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 480)
    #endif
  }

  private func post() {
    let request = Payloads.CreatePollRequest(
      question: .init(text: question.trimmingCharacters(in: .whitespacesAndNewlines)),
      answers: filledAnswers.map { Poll.Answer(poll_media: .init(text: $0)) },
      duration: hours,
      allow_multiselect: allowsMultiple,
      layout_type: .default
    )
    isSending = true
    error = nil
    let channelID = vm.channelId
    Task {
      defer { isSending = false }
      do {
        try await gw.client.createMessage(
          channelId: channelID,
          payload: Payloads.CreateMessage(poll: request)
        ).guardSuccess()
        dismiss()
      } catch {
        print("[Poll] Creating a poll failed:", error)
        self.error = String(localized: "The poll couldn't be posted.")
      }
    }
  }
}
