//
//  ProfileBar.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 24/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct ProfileBar: View {
  @Environment(\.gateway) var gw
  #if os(macOS)
    @Environment(\.openWindow) var openWindow
  #endif

  @State var showingUsername = false
  @State var showingPopover = false
  @State var barHovered = false

  var body: some View {
    HStack {
      Button {
        showingPopover.toggle()
      } label: {
        HStack {
          if let user = gw.user.currentUser {
            Profile.AvatarWithPresence(
              member: nil,
              user: user
            )
            .frame(maxHeight: 30)
            .profileAnimated(barHovered)
            .profileShowsAvatarDecoration()
          }

          VStack(alignment: .leading) {
            Text(
              gw.user.currentUser?.global_name ?? gw.user.currentUser?.username
                ?? "Unknown User"
            )
            .bold()
            if showingUsername {
              Text(verbatim: "@\(gw.user.currentUser?.username ?? "Unknown User")")
                .transition(.opacity)
            } else {
              if let session = gw.user.sessions.first(where: { $0.id == "all" }
              ),
                let status = session.activities.first,
                status.type == .custom
              {
                if let emoji = status.emoji {
                  if let url = emojiURL(for: emoji, animated: true) {
                    NukeImage(url: url)
                      .resizable()
                      .scaledToFit()
                      .frame(width: 16, height: 16)
                  } else {
                    Text(emoji.name)
                      .font(.system(size: 14))
                  }
                }

                Text(status.state ?? "")
                  .transition(.opacity)
              }
            }
          }
          .background(.black.opacity(0.001))
          .onHover { showingUsername = $0 }
          .animation(.spring(), value: showingUsername)
          .frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(.rect)
      }
      .buttonStyle(.plain)
      .popover(isPresented: $showingPopover) {
        ProfileButtonPopout()
      }

      Button {
        #if os(macOS)
          openWindow(id: "settings")
        #elseif os(iOS)
          NotificationCenter.default.post(
            name: .presentSettingsSheet,
            object: nil
          )
        #endif
      } label: {
        Image(systemName: "gearshape.fill")
          .font(.title2)
          .padding(5)
          .glassEffect(.regular.interactive(), in: .circle)
      }
      .buttonStyle(.borderless)
    }
    .padding(8)
    .background {
      if let nameplate = gw.user.currentUser?.collectibles?.nameplate {
        Profile.NameplateView(nameplate: nameplate)
          .nameplateAnimated(barHovered)
          .saturation(0.9)
          .brightness(0.1)
      }
    }
    .clipped()
    .onHover { barHovered = $0 }
  }

  func emojiURL(for emoji: Gateway.Activity.ActivityEmoji, animated: Bool)
    -> URL?
  {
    guard let id = emoji.id else { return nil }
    return DiscordImageURL.customEmoji(
      id: id,
      animated: animated && emoji.animated == true,
      size: 44
    )
  }

  struct ProfileButtonPopout: View {
    @Environment(\.gateway) var gw

    var body: some View {
      List {
        Section {
          HStack {
            if let user = gw.user.currentUser {
              Profile.AvatarWithPresence(
                member: nil,
                user: user
              )
              .frame(maxWidth: 40)
              .frame(maxHeight: 40)
              .profileAnimated(false)
              .profileShowsAvatarDecoration()
            }

            VStack(alignment: .leading) {
              Text(
                gw.user.currentUser?.global_name ?? gw.user.currentUser?.username
                  ?? "Unknown User"
              )
              .bold()
              Text(verbatim: "@\(gw.user.currentUser?.username ?? "Unknown User")")
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 5)

          CustomStatusRow()
        }

        StatusSection()
        ActivitySection()
        AccountInfoSection()
        AccountsSection()
      }
      #if os(macOS)
        .frame(width: 340, height: 560)
      #else
        .frame(minWidth: 280)
        .frame(minHeight: 420)
      #endif
    }

    static let statuses: [Gateway.Status] = [
      .online,
      .afk,
      .doNotDisturb,
      .invisible,
    ]

    @ViewBuilder
    static func statusItem(_ status: Gateway.Status) -> some View {
      let color: Color = {
        switch status {
        case .online: return .init(hexadecimal6: 0x42a25a)
        case .afk: return .init(hexadecimal6: 0xca9653)
        case .doNotDisturb: return .init(hexadecimal6: 0xd83a42)
        default: return .init(hexadecimal6: 0x82838b)
        }
      }()

      Label {
        switch status {
        case .online: Text("Online")
        case .afk: Text("Idle")
        case .doNotDisturb: Text("Do Not Disturb")
        default: Text("Invisible")
        }
      } icon: {
        Group {
          switch status {
          case .online:
            StatusIndicatorShapes.OnlineShape()
          case .afk:
            StatusIndicatorShapes.IdleShape()
          case .doNotDisturb:
            StatusIndicatorShapes.DNDShape()
          default:
            StatusIndicatorShapes.InvisibleShape()
          }
        }
        .foregroundStyle(color)
        .frame(width: 15, height: 15)
      }
    }
  }

  // MARK: - Profile sections
  // Shared by the macOS popover and the iPhone Profile tab.

  struct CustomStatusRow: View {
    @Environment(\.gateway) var gw
    @State var editing = false

    var body: some View {
      Button {
        editing = true
      } label: {
        if let activity = gw.presence.currentClientStatusActivity {
          HStack(spacing: 6) {
            if let emoji = activity.emoji {
              CustomStatusEmoji(emoji: emoji)
            }
            Text(activity.state ?? "")
              .lineLimit(2)
            Spacer()
            Image(systemName: "pencil")
              .foregroundStyle(.secondary)
          }
          .contentShape(.rect)
        } else {
          Label("Set Custom Status", systemImage: "face.smiling")
            .contentShape(.rect)
        }
      }
      .buttonStyle(.borderless)
      .tint(.primary)
      .sheet(isPresented: $editing) {
        CustomStatusEditor()
      }
    }
  }

  struct StatusSection: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState

    var body: some View {
      Section("Status") {
        ForEach(ProfileButtonPopout.statuses, id: \.self) { status in
          AsyncButton {
            try await gw.presence.changeStatus(status)
          } catch: { error in
            appState.error = error
          } label: {
            HStack {
              ProfileButtonPopout.statusItem(status)
              Spacer()
              if gw.presence.currentClientStatus == status {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
            .contentShape(.rect)
          }
          .buttonStyle(.borderless)
          .tint(.primary)
        }
      }
    }
  }

  struct ActivitySection: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @State var editing = false

    var body: some View {
      Section {
        if gw.presence.richPresenceActivity != nil,
          let id = gw.accounts.currentAccountID,
          let fields = RichPresence.saved(for: id)
        {
          RichPresenceCard(fields: fields)
            .padding(.vertical, 4)
        }
        Button {
          editing = true
        } label: {
          Label(
            gw.presence.richPresenceActivity == nil
              ? "Set Rich Presence" : "Edit Rich Presence",
            systemImage: "gamecontroller"
          )
          .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .sheet(isPresented: $editing) {
          RichPresenceEditor()
        }
        Toggle(
          "Share My Activity",
          isOn: Binding(
            get: { gw.presence.sharesActivity },
            set: { newValue in
              Task {
                do {
                  try await gw.presence.setSharesActivity(newValue)
                } catch {
                  appState.error = error
                }
              }
            }
          )
        )
        #if os(macOS)
          .toggleStyle(.switch)
        #endif
      } header: {
        Text("Activity")
      } footer: {
        Text("Rich presence shows while Aicord is connected.")
      }
    }
  }

  struct AccountInfoSection: View {
    @Environment(\.gateway) var gw
    @State var editing = false

    var body: some View {
      Section {
        if let created = gw.user.currentUser?.id.parse()?.date {
          LabeledContent("Member Since") {
            Text(created, format: .dateTime.day().month(.wide).year())
          }
        }
        Button {
          editing = true
        } label: {
          Label("Edit Profile", systemImage: "pencil")
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $editing) {
          ProfileEditorSheet()
        }
      }
    }
  }

  /// The Profiles settings page on its own, for "Edit Profile".
  struct ProfileEditorSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
      NavigationStack {
        Form {
          ProfileEditor()
        }
        .formStyle(.grouped)
        .navigationTitle("Edit Profile")
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
        .frame(minWidth: 480, minHeight: 600)
      #endif
    }
  }

  struct AccountsSection: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @State var confirmingLogOut = false

    var body: some View {
      Section("Accounts") {
        ForEach(gw.accounts.accounts, id: \.id) { account in
          let isSignedInAccount = account.id == gw.accounts.currentAccountID
          AsyncButton {
            gw.accounts.currentAccountID = nil
            await gw.disconnectIfNeeded()
            gw.resetStores()
            AicordAppState.instances.values.forEach { $0.resetStore() }
            gw.accounts.currentAccountID = account.id
          } catch: { error in
            appState.error = error
          } label: {
            HStack {
              Profile.AvatarWithPresence(
                member: nil,
                user: account.user
              )
              .frame(maxWidth: 25)
              .frame(maxHeight: 25)
              .profileAnimated(false)
              .profileShowsAvatarDecoration()

              VStack(alignment: .leading) {
                Text(
                  account.user.global_name
                    ?? account.user.username
                )
                .lineSpacing(1)
                .bold()
                Text(verbatim: "@\(account.user.username)")
                  .lineSpacing(1)
                  .foregroundStyle(.secondary)
              }

              Spacer()

              if isSignedInAccount {
                Image(systemName: "checkmark")
                  .foregroundStyle(.tint)
              }
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
          }
          .buttonStyle(.borderless)
          .tint(.primary)
          .disabled(isSignedInAccount)
        }

        AsyncButton {
          gw.accounts.currentAccountID = nil
          await gw.disconnectIfNeeded()
          gw.resetStores()
        } catch: { error in
          appState.error = error
        } label: {
          Label("Add Account", systemImage: "person.crop.circle.badge.plus")
        }
        .buttonStyle(.borderless)
        .tint(.primary)

        Button(role: .destructive) {
          confirmingLogOut = true
        } label: {
          Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
            .foregroundStyle(.red)
        }
        .buttonStyle(.borderless)
        .confirmationDialog(
          "Log out of this account?",
          isPresented: $confirmingLogOut
        ) {
          Button("Log Out", role: .destructive) {
            guard
              let id = gw.accounts.currentAccountID,
              let account = gw.accounts.account(for: id)
            else { return }
            Task {
              await gw.disconnectIfNeeded()
              gw.resetStores()
              gw.accounts.removeAccount(account)
            }
          }
        }
      }
    }
  }

  struct CustomStatusEmoji: View {
    var emoji: Gateway.Activity.ActivityEmoji

    var body: some View {
      if let id = emoji.id {
        NukeImage(
          url: DiscordImageURL.customEmoji(
            id: id,
            animated: emoji.animated == true,
            size: 44
          )
        )
        .resizable()
        .scaledToFit()
        .frame(width: 18, height: 18)
      } else {
        Text(emoji.name)
      }
    }
  }

  struct CustomStatusEditor: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @Environment(\.dismiss) var dismiss

    enum ClearAfter: Hashable, CaseIterable {
      case never, thirtyMinutes, oneHour, fourHours, today

      var title: LocalizedStringKey {
        switch self {
        case .never: "Don't Clear"
        case .thirtyMinutes: "30 Minutes"
        case .oneHour: "1 Hour"
        case .fourHours: "4 Hours"
        case .today: "Today"
        }
      }

      var date: Date? {
        switch self {
        case .never: nil
        case .thirtyMinutes: .now.addingTimeInterval(30 * 60)
        case .oneHour: .now.addingTimeInterval(60 * 60)
        case .fourHours: .now.addingTimeInterval(4 * 60 * 60)
        case .today:
          Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: .now)
          )
        }
      }
    }

    @State var text = ""
    @State var emojiText = ""
    @State var clearAfter: ClearAfter = .never
    @State var saving = false
    /// A server emoji can't be typed, so the existing one is kept until the field changes.
    @State var keptEmoji: Gateway.Activity.ActivityEmoji? = nil

    var body: some View {
      NavigationStack {
        Form {
          Section {
            HStack {
              TextField("Emoji", text: $emojiText)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .onChange(of: emojiText) { _, newValue in
                  if newValue != keptEmoji?.name { keptEmoji = nil }
                  // keep a single emoji (one grapheme)
                  if newValue.count > 1, let last = newValue.last {
                    emojiText = String(last)
                  }
                }
              TextField("What's on your mind?", text: $text)
            }
          }

          Section {
            Picker("Clear After", selection: $clearAfter) {
              ForEach(ClearAfter.allCases, id: \.self) { option in
                Text(option.title).tag(option)
              }
            }
          }

          if gw.presence.currentClientStatusActivity != nil {
            Section {
              Button("Clear Status", role: .destructive) {
                save(text: "", emoji: nil, expiresAt: nil)
              }
            }
          }
        }
        .formStyle(.grouped)
        .navigationTitle("Custom Status")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              save(text: text, emoji: emoji, expiresAt: clearAfter.date)
            }
            .disabled(saving)
          }
        }
      }
      .onAppear {
        let activity = gw.presence.currentClientStatusActivity
        text = activity?.state ?? ""
        keptEmoji = activity?.emoji
        emojiText = activity?.emoji?.name ?? ""
      }
      #if os(iOS)
        .presentationDetents([.medium, .large])
      #else
        .frame(minWidth: 360, minHeight: 260)
      #endif
    }

    var emoji: Gateway.Activity.ActivityEmoji? {
      if let keptEmoji { return keptEmoji }
      let trimmed = emojiText.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? nil : .init(name: trimmed)
    }

    func save(text: String, emoji: Gateway.Activity.ActivityEmoji?, expiresAt: Date?) {
      saving = true
      Task {
        defer { saving = false }
        do {
          try await gw.presence.changeCustomStatus(
            text: text,
            emoji: emoji,
            expiresAt: expiresAt
          )
          dismiss()
        } catch {
          appState.error = error
        }
      }
    }
  }

}
