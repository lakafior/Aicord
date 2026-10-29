//
//  DebugSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import Logging
import SettingsKit
import SwiftUIX

extension SettingsView {
  var debugSection: some SettingsContent {
    CustomSettingsGroup("Debug", systemImage: "ladybug") {
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
        //        NavigationLink {
        //          TestMessageView().eraseToAnyView()
        //        } label: {
        //          Label("Message Attachments Playground", systemImage: "app.dashed")
        //        }
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
}
