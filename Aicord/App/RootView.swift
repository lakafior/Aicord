//
//  RootView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 18/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

// Handles using phone suitable layout or desktop suitable layout

struct RootView: View {
  let gatewayStore: GatewayStore
  @State var appState: AicordAppState = .init()
  @Environment(\.challenges) var challenges
  @Environment(\.userInterfaceIdiom) var idiom
  @Environment(\.horizontalSizeClass) var hSizeClass

  #if os(iOS)
    @State var hasLaunchedAlready: Bool = false
  #endif

  #if os(iOS)
    var isConnecting: Bool {
      hasLaunchedAlready == false && gatewayStore.state != .connected
    }
  #else
    var isConnecting: Bool {
      gatewayStore.state != .connected
    }
  #endif

  var body: some View {
    Group {
      if gatewayStore.accounts.currentAccountID == nil {
        LoginView()
          .tint(.primary)  // text tint in buttons etc.
      } else if isConnecting {
        ConnectionStateView(state: gatewayStore.state)
          .transition(.opacity.combined(with: .scale(scale: 1.1)))
          .task { await gatewayStore.connectIfNeeded() }
      } else {
        Group {
          if idiom == .phone || (idiom == .pad && hSizeClass == .compact) {
            #if os(iOS)
              SmallBaseplate(appState: self.appState)
            #endif
          } else {
            #if os(macOS)
              MacBaseplate()
            #else
              LargeBaseplate()
            #endif
          }
        }
        .quickSwitcher()
        .attachmentViewer()
        .reactionPicker()
        .forwardSheet()
        .reminderSheet()
        .messageIntelligenceSheet()
        .settingsSheet()
        .task {
          AicordAppState.main = appState
          appState.loadPrevGuild()
          #if os(iOS)
            self.hasLaunchedAlready = true
          #endif
        }
      }
    }
    .environment(\.appState, appState)
    .focusedSceneValue(\.appState, appState)
    .navigationTitle(Text(verbatim: ""))
    .animation(.default, value: gatewayStore.state.hashValue)
    .modifier(
      AicordSheetsAlerts(
        gatewayStore: gatewayStore,
        appState: appState,
        challenges: challenges!  // always exists, ref made in AicordApp.swift
      )
    )
    .onAppear { setupGatewayCallbacks() }
    // invite links handed over by the Safari extension (aicord://invite/…)
    .onOpenURL { url in
      guard gatewayStore.accounts.currentAccountID != nil,
        let code = InviteLink.code(from: url)
      else { return }
      SafariExtensionGuide.markWorking()
      appState.invitePreviewCode = code
    }
    #if os(macOS)
      // into the open window rather than a new one
      .handlesExternalEvents(preferring: [InviteLink.appScheme], allowing: ["*"])
    #endif
    #if os(macOS)
      .toolbarBackgroundVisibility(
        gatewayStore.accounts.currentAccountID == nil ? .hidden : .automatic,
        for: .windowToolbar
      )
    #else
      .onChange(of: gatewayStore.accounts.currentAccountID) {
        if gatewayStore.accounts.currentAccountID == nil {
          self.hasLaunchedAlready = false  // when logged out, allow connection screen. else connection wont be attempted.
        }
      }
    #endif
  }

  // MARK: - Gateway Callbacks

  private func setupGatewayCallbacks() {
    gatewayStore.captchaCallback = { captcha in
      await challenges?.presentCaptcha(captcha)
    }
    gatewayStore.mfaCallback = { mfaData in
      await challenges?.presentMFA(mfaData)
    }
  }
}
