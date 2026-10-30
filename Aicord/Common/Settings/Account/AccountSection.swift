//
//  AccountSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var accountSection: some View {
    AccountDetails()
    ProfileBar.AccountsSection()
    DiscordApplicationSettings()
  }
}

/// Read-only details of the signed-in account.
struct AccountDetails: View {
  @Environment(\.gateway) var gw
  @State var revealsEmail = false

  var body: some View {
    if let user = gw.user.currentUser {
      Section {
        HStack(spacing: 12) {
          Profile.AvatarWithPresence(member: nil, user: user)
            .frame(width: 48, height: 48)
            .profileAnimated(false)
            .profileShowsAvatarDecoration()
          VStack(alignment: .leading) {
            Text(user.global_name ?? user.username)
              .font(.headline)
            Text(verbatim: "@\(user.username)")
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      }

      Section("Account") {
        if let email = user.email {
          LabeledContent("Email") {
            Button {
              revealsEmail.toggle()
            } label: {
              Text(verbatim: revealsEmail ? email : Self.masked(email))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
          }
          .accessibilityHint(Text("Shows or hides the email address"))
        }
        LabeledContent("Two-Factor Authentication") {
          Text(user.mfa_enabled == true ? "On" : "Off")
        }
        LabeledContent("Nitro") {
          Text(Self.nitroName(user.premium_type))
        }
        if let created = user.id.parse()?.date {
          LabeledContent("Member Since") {
            Text(created, format: .dateTime.day().month(.wide).year())
          }
        }
        LabeledContent("User ID") {
          Button {
            Self.copy(user.id.rawValue)
          } label: {
            Label(user.id.rawValue, systemImage: "doc.on.doc")
              .labelStyle(.titleAndIcon)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          .buttonStyle(.borderless)
        }
        .accessibilityHint(Text("Copies the user ID"))
      }
    }
  }

  /// "jo•••@example.com", like Discord shows it before you tap Reveal.
  static func masked(_ email: String) -> String {
    guard let at = email.firstIndex(of: "@") else { return email }
    let name = email[..<at]
    return name.prefix(2) + String(repeating: "•", count: max(name.count - 2, 3)) + email[at...]
  }

  static func nitroName(_ kind: DiscordUser.PremiumKind?) -> LocalizedStringKey {
    switch kind {
    case .nitro: "Nitro"
    case .nitroClassic: "Nitro Classic"
    case .nitroBasic: "Nitro Basic"
    default: "None"
    }
  }

  static func copy(_ string: String) {
    #if os(iOS)
      UIPasteboard.general.string = string
    #else
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(string, forType: .string)
    #endif
  }
}

/// The user's own Discord application, used by rich presence for images and buttons.
struct DiscordApplicationSettings: View {
  @Environment(\.gateway) var gw
  @AppStorage(DiscordApplication.idKey) var applicationID = ""
  @AppStorage(DiscordApplication.nameKey) var verifiedName = ""

  @State var draft = ""
  @State var checking = false
  @State var failure: String? = nil

  var body: some View {
    Section {
      TextField("Application ID", text: $draft)
        .autocorrectionDisabled()
        #if os(iOS)
          .keyboardType(.numberPad)
        #endif
        .onSubmit(verify)
        .onChange(of: draft) { _, newValue in
          failure = nil
          if newValue != applicationID { verifiedName = "" }
        }

      if !verifiedName.isEmpty, draft == applicationID {
        Label(verifiedName, systemImage: "checkmark.seal.fill")
          .foregroundStyle(.green)
      } else if let failure {
        Label(failure, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }

      HStack {
        Button("Check and Save", action: verify)
          .disabled(checking || UInt64(draft) == nil)
        if checking { ProgressView().controlSize(.small) }
        Spacer()
        if !applicationID.isEmpty {
          Button("Remove", role: .destructive) {
            applicationID = ""
            verifiedName = ""
            draft = ""
          }
        }
      }
      .buttonStyle(.borderless)
    } header: {
      Text("Discord Application")
    } footer: {
      Text(
        "Rich presence shows images and buttons only for an application. Create one in the [Developer Portal](https://discord.com/developers/applications) and paste its ID here; its name isn't shown on your profile."
      )
    }
    .onAppear { draft = applicationID }
  }

  func verify() {
    guard UInt64(draft) != nil else { return }
    checking = true
    failure = nil
    Task {
      defer { checking = false }
      do {
        let res = try await gw.client.getApplicationRPC(
          applicationID: ApplicationSnowflake(draft)
        )
        try res.guardSuccess()
        let app = try res.decode()
        applicationID = draft
        verifiedName = app.name ?? draft
      } catch {
        failure = String(localized: "No application with this ID.")
      }
    }
  }
}

enum DiscordApplication {
  static let idKey = "Aicord.DiscordApplication.ID"
  static let nameKey = "Aicord.DiscordApplication.Name"

  static var id: String { UserDefaults.standard.string(forKey: idKey) ?? "" }
  static var name: String { UserDefaults.standard.string(forKey: nameKey) ?? "" }
}
