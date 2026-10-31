//
//  AicordApp.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 31/08/2025.
//  Copyright © 2025 Lakhan Lothiyi. All rights reserved.
//

import Logging
import AicordKit
import SwiftUI
import UserNotifications

@main
struct AicordApp: App {
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
    AicordImagePipeline.configure()
    UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    NotificationStore.registerCategories()
    #if os(macOS)
      // the MCP bridge listens from launch when allowed; tools wait for the gateway
      Task { @MainActor in MCPBridge.shared.update() }
    #endif
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
    #if os(macOS)
      .commands {
        AicordCommands()
        MacCommands()
      }
    #elseif os(iOS)
      .commands {
        AicordCommands()
      }
    #endif
    .environment(\.challenges, challenges)

    #if os(macOS)
      // a channel in a window of its own (Go → Open Channel in New Window)
      WindowGroup("Channel", for: ChannelWindowValue.self) { $value in
        if let value {
          ChannelWindow(value: value)
            .appAppearance()
            .environment(\.challenges, challenges)
        }
      }
      .defaultSize(width: 720, height: 760)
      .restorationBehavior(.disabled)

      // the system Settings window: ⌘, and Aicord → Settings…
      Settings {
        SettingsView()
          .appAppearance()
          .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
      }
    #endif
  }
}
