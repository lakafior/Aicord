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
  let gatewayStore: GatewayStore = {
    // before any store reads the settings
    if DemoMode.isRequestedAtLaunch {
      DemoMode.prepare()
    } else {
      // from a demo that ended without a log out
      DemoSettingsBackup.restore()
    }
    if UserDefaults.standard.bool(forKey: "AicordRestoreSettings") {
      // only puts the settings back from demo mode, without connecting
      exit(0)
    }
    return GatewayStore.shared
  }()
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

      // Notifications Through the Mac: CloudKit sends the pushes, it only
      // needs the device registered
      func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
      ) {}

      func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
      ) {
        print("[CloudRelay] remote notifications unavailable: \(error.localizedDescription)")
      }
    }
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  #elseif os(macOS)
    // closing the last window can leave Aicord running in the menu bar
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    @State private var background = MacBackground.shared
  #endif

  @Environment(\.scenePhase) private var scenePhase

  #if os(macOS)
    private static let mainWindowID = MacBackground.mainWindowID
  #else
    private static let mainWindowID = "main"
  #endif

  init() {
    console.startIntercepting()
    AicordImagePipeline.configure()
    UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    NotificationStore.registerCategories()
    SystemIntegration.shared.start()
    Task { @MainActor in CloudRelayStore.shared.update() }
    #if os(macOS)
      // the MCP bridge listens from launch when allowed; tools wait for the gateway
      Task { @MainActor in
        MCPBridge.shared.update()
        GlobalQuickSwitcher.shared.update()
      }
    #endif
  }

  var body: some Scene {
    WindowGroup(id: Self.mainWindowID) {
      RootView(
        gatewayStore: gatewayStore
      )
      .appAppearance()
      #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .background:
            gatewayStore.notifications.enterBackground()
            CloudRelayStore.shared.appEnteredBackground()
            SystemIntegration.shared.flushWidgetSnapshot()
          case .active:
            gatewayStore.notifications.endBackground()
            CloudRelayStore.shared.appBecameActive()
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
      // no "New Channel Window" in File → New: it needs a channel
      .commandsRemoved()

      // a server's settings, one window per server (Go → Server Settings…)
      WindowGroup("Server Settings", id: ServerSettingsWindow.id, for: GuildSnowflake.self) { $guildId in
        if let guildId {
          ServerSettingsWindow(guildId: guildId)
            .appAppearance()
            .environment(\.challenges, challenges)
        }
      }
      .defaultSize(width: 520, height: 680)
      .windowResizability(.contentMinSize)
      .restorationBehavior(.disabled)
      .commandsRemoved()

      // while running without a window (MacBackground)
      MenuBarExtra(
        isInserted: Binding(get: { background.isHeadless }, set: { _ in })
      ) {
        MacBackgroundMenu(
          background: background, gateway: gatewayStore, relay: CloudRelayStore.shared,
          mcp: MCPBridge.shared)
      } label: {
        MacBackgroundLabel(background: background)
      }

      // the system Settings window: ⌘, and Aicord → Settings…
      Settings {
        SettingsView()
          .appAppearance()
          .frame(width: 760)
          .frame(minHeight: 560, maxHeight: 900)
      }
    #endif
  }
}
