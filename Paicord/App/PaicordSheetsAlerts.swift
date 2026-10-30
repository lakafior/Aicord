//
//  PaicordSheetsAlerts.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 18/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct PaicordSheetsAlerts: ViewModifier {
  let gatewayStore: GatewayStore
  @Bindable var appState: PaicordAppState
  @Bindable var challenges: Challenges

  func body(content: Content) -> some View {
    content
      .sheet(item: $challenges.captchaChallenge) { challenge in
        CaptchaSheet(challenge: challenge) { submitData in
          challenges.completeCaptcha(submitData)
        }
        .frame(idealWidth: 400, idealHeight: 400)
      }
      .sheet(item: $challenges.mfaVerification) { mfaData in
        MFASheet(verificationData: mfaData) { response in
          challenges.completeMFA(response)
        }
        .frame(idealWidth: 400, idealHeight: 300)
      }
      .alert(
        "Error",
        isPresented: $appState.showingError,
        actions: {
          Button("OK", role: .cancel) { appState.error = nil }
          Button("Details") {
            appState.showingErrorSheet = true
            appState.showingError = false
          }
        },
        message: {
          errorTextView(error: appState.error)
        }
      )
      .sheet(isPresented: $appState.showingErrorSheet) {
        ScrollView { errorTextView(error: appState.error) }
      }
  }

  @ViewBuilder
  private func errorTextView(error: Error?) -> some View {
    if let error = error as? DiscordHTTPErrorResponse {
      Text(error.description)
    } else if let error = error as? DiscordHTTPError {
      Text(error.description)
    } else if let error = error {
      Text(error.localizedDescription)
    } else {
      Text("An unknown error occurred.")
    }
  }
}

extension View {
  /// The app's error alert, for sheets: the one at the root can't show above them.
  func sheetErrorAlert() -> some View {
    modifier(SheetErrorAlert())
  }
}

private struct SheetErrorAlert: ViewModifier {
  @Environment(\.appState) var appState

  func body(content: Content) -> some View {
    @Bindable var appState = appState
    content.alert(
      "Error",
      isPresented: $appState.showingError,
      actions: { Button("OK", role: .cancel) { appState.error = nil } },
      message: {
        if let error = appState.error as? DiscordHTTPErrorResponse {
          Text(error.description)
        } else {
          Text(appState.error?.localizedDescription ?? String(localized: "An unknown error occurred."))
        }
      }
    )
  }
}
