//
//  AicordSheetsAlerts.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 18/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

struct AicordSheetsAlerts: ViewModifier {
  let gatewayStore: GatewayStore
  @Bindable var appState: AicordAppState
  @Bindable var challenges: Challenges

  func body(content: Content) -> some View {
    content
      .challengeSheets(challenges)
      .sheet(
        item: Binding(
          get: { appState.invitePreviewCode.map(InviteCode.init(code:)) },
          set: { appState.invitePreviewCode = $0?.code }
        )
      ) { item in
        InvitePreviewSheet(code: item.code)
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

/// The captcha and MFA sheets, shown by whichever presenter is innermost.
/// Apply inside any sheet whose actions can hit a Discord challenge.
struct ChallengeSheets: ViewModifier {
  let challenges: Challenges?
  @State private var presenter = UUID()

  private var isActive: Bool { challenges?.presenters.last == presenter }

  func body(content: Content) -> some View {
    content
      .onAppear { challenges?.register(presenter) }
      .onDisappear { challenges?.unregister(presenter) }
      .sheet(
        item: Binding(
          get: { isActive ? challenges?.captchaChallenge : nil },
          // closed by the system (Esc, swipe down): nothing will answer it
          set: { if $0 == nil, isActive { challenges?.completeCaptcha(nil) } }
        )
      ) { challenge in
        CaptchaSheet(challenge: challenge) { submitData in
          challenges?.completeCaptcha(submitData)
        }
        .frame(idealWidth: 400, idealHeight: 400)
      }
      .sheet(
        item: Binding(
          get: { isActive ? challenges?.mfaVerification : nil },
          set: { if $0 == nil, isActive { challenges?.completeMFA(nil) } }
        )
      ) { mfaData in
        MFASheet(verificationData: mfaData) { response in
          challenges?.completeMFA(response)
        }
        .frame(idealWidth: 400, idealHeight: 300)
      }
  }
}

extension View {
  func challengeSheets(_ challenges: Challenges?) -> some View {
    modifier(ChallengeSheets(challenges: challenges))
  }

  /// The challenge sheets from the environment, for views inside a sheet.
  func challengeSheets() -> some View {
    modifier(EnvironmentChallengeSheets())
  }
}

private struct EnvironmentChallengeSheets: ViewModifier {
  @Environment(\.challenges) var challenges
  func body(content: Content) -> some View {
    content.challengeSheets(challenges)
  }
}
