//
//  AccountSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var accountSection: some View {
    Section("My Account") {
      AsyncButton("Log Out") {
        guard let currentAccount = gw.accounts.currentAccount else { return }
        gw.accounts.removeAccount(currentAccount)
        await gw.logOut()
      } catch: { _ in
      }
      .foregroundStyle(.red)
    }

    DiscordApplicationSettings()
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
