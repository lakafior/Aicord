//
//  AccountSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 15/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

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
  }
}
