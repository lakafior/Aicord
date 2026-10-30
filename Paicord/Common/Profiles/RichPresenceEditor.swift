//
//  RichPresenceEditor.swift
//  Aicord
//

import PaicordLib
import SwiftUI

/// Form for the user's own rich presence. Edits stay a draft until Apply.
struct RichPresenceEditor: View {
  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.dismiss) var dismiss
  @Environment(\.openURL) var openURL

  @State var fields = RichPresence()
  @State var working = false

  var isActive: Bool { gw.presence.richPresenceActivity != nil }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          RichPresenceCard(fields: fields)
            .listRowInsets(.init(top: 12, leading: 12, bottom: 12, trailing: 12))
        } header: {
          Text("Preview")
        } footer: {
          if let problem = fields.problem {
            Text(problem)
          }
        }

        Section("Activity") {
          Picker("Type", selection: $fields.kind) {
            ForEach(RichPresence.Kind.allCases) { kind in
              Text(kind.title).tag(kind)
            }
          }
          TextField("Name", text: $fields.name)
          TextField("Details", text: $fields.details)
          TextField("State", text: $fields.state)
          if fields.kind == .streaming {
            TextField("Twitch or YouTube Link", text: $fields.streamURL)
              .textContentType(.URL)
              .autocorrectionDisabled()
          }
        }

        Section {
          LabeledContent("Application") {
            Text(DiscordApplication.name.isEmpty ? String(localized: "Not Set") : DiscordApplication.name)
          }
        } footer: {
          Text("Images and buttons come from your Discord application, set in Settings → My Account.")
        }

        Section {
          TextField("Large Image", text: $fields.largeImage)
            .autocorrectionDisabled()
          TextField("Large Image Text", text: $fields.largeText)
          TextField("Small Image", text: $fields.smallImage)
            .autocorrectionDisabled()
          TextField("Small Image Text", text: $fields.smallText)
        } header: {
          Text("Images")
        } footer: {
          Text("An image link (https://…) or the key of an asset uploaded to the application.")
        }

        Section("Time") {
          Picker("Timer", selection: $fields.timer) {
            ForEach(RichPresence.TimerMode.allCases) { mode in
              Text(mode.title).tag(mode)
            }
          }
          if fields.timer == .countdown {
            DatePicker("Ends", selection: $fields.countdownEnd, in: Date.now...)
          }
        }

        Section("Party") {
          Toggle("Show Party Size", isOn: $fields.showsParty)
          if fields.showsParty {
            Stepper("\(fields.partySize) in party", value: $fields.partySize, in: 1...99)
            Stepper("Room for \(fields.partyMax)", value: $fields.partyMax, in: 1...99)
          }
        }

        Section {
          TextField("First Button Label", text: $fields.button1Label)
          TextField("First Button Link", text: $fields.button1URL)
            .textContentType(.URL)
            .autocorrectionDisabled()
          TextField("Second Button Label", text: $fields.button2Label)
          TextField("Second Button Link", text: $fields.button2URL)
            .textContentType(.URL)
            .autocorrectionDisabled()
        } header: {
          Text("Buttons")
        } footer: {
          Text("Other people can click these; you can't click your own.")
        }

        if isActive {
          Section {
            Button("Stop Rich Presence", role: .destructive) {
              run { await gw.presence.stopRichPresence() }
            }
          } footer: {
            Text("Your fields stay saved for next time.")
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Rich Presence")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            run { try await gw.presence.applyRichPresence(fields) }
          }
          .disabled(working || fields.problem != nil)
        }
      }
    }
    .onAppear {
      if let id = gw.accounts.currentAccountID, let saved = RichPresence.saved(for: id) {
        fields = saved
      }
    }
    #if os(macOS)
      .frame(minWidth: 420, minHeight: 560)
    #endif
  }

  func run(_ action: @escaping @MainActor () async throws -> Void) {
    working = true
    Task {
      defer { working = false }
      do {
        try await action()
        dismiss()
      } catch {
        appState.error = error
      }
    }
  }
}

/// A local stand-in for how the activity looks on a profile.
struct RichPresenceCard: View {
  var fields: RichPresence

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(fields.kind.heading)
        .font(.caption)
        .bold()
        .foregroundStyle(.secondary)

      HStack(alignment: .top, spacing: 12) {
        artwork
        VStack(alignment: .leading, spacing: 2) {
          Text(fields.name.isEmpty ? String(localized: "Activity Name") : fields.name)
            .bold()
            .foregroundStyle(fields.name.isEmpty ? .secondary : .primary)
          if !fields.details.isEmpty { Text(fields.details) }
          if !fields.state.isEmpty || fields.showsParty {
            Text(stateLine)
          }
          timerLine
        }
        .font(.subheadline)
        .lineLimit(1)
        Spacer(minLength: 0)
      }

      ForEach(fields.buttons, id: \.label) { button in
        Text(button.label)
          .font(.subheadline.weight(.medium))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .background(.secondary.opacity(0.15), in: .rect(cornerRadius: 8))
      }
    }
  }

  var stateLine: String {
    let party = fields.showsParty ? "(\(fields.partySize) of \(fields.partyMax))" : ""
    return [fields.state, party].filter { !$0.isEmpty }.joined(separator: " ")
  }

  @ViewBuilder
  var timerLine: some View {
    if let end = fields.endDate, end > .now {
      Text("\(Text(timerInterval: Date.now...end, countsDown: true)) left")
    } else if let start = fields.startDate {
      Text("\(Text(timerInterval: start...Date.distantFuture, countsDown: false)) elapsed")
    }
  }

  @ViewBuilder
  var artwork: some View {
    ZStack(alignment: .bottomTrailing) {
      image(fields.largeImage)
        .frame(width: 64, height: 64)
        .clipShape(.rect(cornerRadius: 10))
      if !fields.smallImage.isEmpty {
        image(fields.smallImage)
          .frame(width: 22, height: 22)
          .clipShape(.circle)
          .overlay(Circle().stroke(.background, lineWidth: 2))
          .offset(x: 4, y: 4)
      }
    }
  }

  @ViewBuilder
  func image(_ value: String) -> some View {
    if let url = imageURL(value) {
      NukeImage(url: url)
        .resizable()
        .scaledToFill()
    } else {
      RoundedRectangle(cornerRadius: 10)
        .fill(.secondary.opacity(0.2))
        .overlay {
          Image(systemName: fields.kind.symbol)
            .foregroundStyle(.secondary)
        }
    }
  }

  func imageURL(_ value: String) -> URL? {
    if RichPresence.isLink(value) { return URL(string: value) }
    let appID = DiscordApplication.id
    guard !value.isEmpty, UInt64(appID) != nil, UInt64(value) != nil else { return nil }
    return URL(string: "https://cdn.discordapp.com/app-assets/\(appID)/\(value).png")
  }
}

extension RichPresence.Kind {
  var title: LocalizedStringKey {
    switch self {
    case .playing: "Playing"
    case .streaming: "Streaming"
    case .listening: "Listening"
    case .watching: "Watching"
    case .competing: "Competing"
    }
  }

  var heading: LocalizedStringKey {
    switch self {
    case .playing: "PLAYING A GAME"
    case .streaming: "LIVE ON STREAM"
    case .listening: "LISTENING"
    case .watching: "WATCHING"
    case .competing: "COMPETING"
    }
  }

  var symbol: String {
    switch self {
    case .playing: "gamecontroller.fill"
    case .streaming: "dot.radiowaves.left.and.right"
    case .listening: "headphones"
    case .watching: "play.rectangle.fill"
    case .competing: "trophy.fill"
    }
  }
}

extension RichPresence.TimerMode {
  var title: LocalizedStringKey {
    switch self {
    case .none: "None"
    case .sinceApplied: "Since Applying"
    case .sinceMidnight: "Since Midnight"
    case .countdown: "Countdown"
    }
  }
}
