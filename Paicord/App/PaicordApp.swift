//
//  PaicordApp.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 31/08/2025.
//  Copyright © 2025 Lakhan Lothiyi. All rights reserved.
//

import Logging
import PaicordLib
import SwiftUI
import UserNotifications

@main
struct PaicordApp: App {
  let gatewayStore = GatewayStore.shared
  var challenges = Challenges()
  let console = StdOutInterceptor.shared

  #if os(iOS)
    class AppDelegate: NSObject, UIApplicationDelegate {

      // This method is called by the system to check if state restoration should occur.
      func application(
        _ application: UIApplication,
        shouldRestoreSecureApplicationState coder: NSCoder
      ) -> Bool {
        // Return false to prevent the app from restoring its previous state and windows.
        return false
      }

      // You might also want to prevent the system from saving the state in the first place:
      func application(
        _ application: UIApplication,
        shouldSaveSecureApplicationState coder: NSCoder
      ) -> Bool {
        // Return false to prevent the app from saving its current state when it is terminated.
        return false
      }
    }
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  #endif

  @Environment(\.scenePhase) private var scenePhase

  init() {
    console.startIntercepting()
    PaicordImagePipeline.configure()
    UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    NotificationStore.registerCategories()
  }

  var body: some Scene {
    WindowGroup {
      RootView(
        gatewayStore: gatewayStore
      )
      .appAppearance()
      #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .background: gatewayStore.notifications.enterBackground()
          case .active: gatewayStore.notifications.endBackground()
          default: break
          }
        }
      #endif
    }
    #if os(macOS)
      .defaultSize(width: 1280, height: 800)
      .restorationBehavior(.disabled)
      .windowToolbarStyle(.unified)
    #endif
    #if os(macOS) || os(iOS)
      .commands {
        PaicordCommands()
      }
    #endif
    .environment(\.challenges, challenges)

    #if os(macOS)
      // use a normal window instead of Settings
      Window("Settings", id: "settings") {
        SettingsView()
          .appAppearance()
      }
      .defaultSize(width: 860, height: 620)
      .restorationBehavior(.disabled)
    #endif
  }
}
