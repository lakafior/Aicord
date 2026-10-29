//
//  DebugSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Logging
import SwiftUIX

extension SettingsView {
  @ViewBuilder
  var debugSection: some View {
    Section("Tools") {
      NavigationLink {
        ShellView().eraseToAnyView()
      } label: {
        Label("View Logs", systemImage: "apple.terminal")
      }
    }

    Section("Playgrounds") {
      Button("PresentSponsorSheet") {
        NotificationCenter.default.post(
          name: .presentSponsorSheet,
          object: nil
        )
      }
    }

    Section("Sketchy shit") {
      AsyncButton("Force fallback account switcher") {
        gw.accounts.currentAccountID = nil
        await gw.disconnectIfNeeded()
        gw.resetStores()
      } catch: { _ in
      }
    }
  }
}
