//
//  MacBackground.swift
//  Aicord
//
//  Running without a window. With the MCP server or Notifications Through
//  the Mac on, closing the last window (red button, ⌘W) leaves Aicord running
//  in the menu bar: no Dock icon, no windows and their views, only the
//  gateway, the MCP server, the relay and the Mac's own banners. ⌘Q and Quit
//  in the menu bar item stop everything. Advanced → Keep Running in the
//  Background turns it off.
//
//  The window stays a SwiftUI WindowGroup: SwiftUI releases a closed window's
//  views, so there's nothing to rebuild in AppKit, and the process keeps its
//  gateway session (Midden restarts its process instead, which here would
//  mean logging in to Discord again). The menu bar item's label is also the
//  only view left while headless, so it's the one that opens the window again.
//

#if os(macOS)
  import AicordKit
  import AppKit
  import OSLog
  import SwiftUI

  @MainActor
  @Observable
  final class MacBackground {
    static let shared = MacBackground()

    static let enabledKey = "Aicord.Mac.KeepRunningInBackground"
    /// The main window's scene; SwiftUI names its windows `main-AppWindow-N`.
    static let mainWindowID = "main"

    /// The setting, on by default.
    static var isEnabled: Bool {
      UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Something that only works while Aicord runs: the MCP server or the relay.
    static var hasBackgroundWork: Bool {
      guard GatewayStore.shared.accounts.currentAccountID != nil else { return false }
      return MCPPreferences.enabled || CloudRelayStore.shared.isEnabled
    }

    /// No windows, no Dock icon, the menu bar item shows.
    private(set) var isHeadless = false
    /// Bumped to have the menu bar item's label open the main window.
    private(set) var windowRequest = 0

    @ObservationIgnored private var isQuitting = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var checkScheduled = false
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let logger = Logger(
      subsystem: "net.smigi.aicord", category: "Background")

    private init() {}

    func start() {
      guard observers.isEmpty else { return }
      let names: [Notification.Name] = [
        NSWindow.willCloseNotification,
        NSWindow.didBecomeKeyNotification,
        NSWindow.didBecomeMainNotification,
        NSWindow.didChangeOcclusionStateNotification,
        NSWindow.didDeminiaturizeNotification,
      ]
      observers = names.map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.scheduleCheck() }
        }
      }
    }

    // MARK: - Windows

    /// Windows the user can lose track of: the main window, channel windows,
    /// server settings and Settings, visible or minimized. Not panels (the
    /// global Quick Switcher, open/save panels), menus or the menu bar item.
    static var appWindows: [NSWindow] {
      NSApp.windows.filter { window in
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal
          && (window.isVisible || window.isMiniaturized)
      }
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
      let id = window.identifier?.rawValue ?? ""
      return id.hasPrefix("\(mainWindowID)-") || id.contains("RootView")
    }

    static var mainWindow: NSWindow? {
      let windows = appWindows.filter(isMainWindow)
      return windows.first { $0.isVisible } ?? windows.first
    }

    /// Changes come in bursts, and on `willClose` the window is still
    /// visible: decide once, on the next turn of the run loop.
    private func scheduleCheck() {
      guard !checkScheduled else { return }
      checkScheduled = true
      DispatchQueue.main.async { [weak self] in
        MainActor.assumeIsolated {
          self?.checkScheduled = false
          self?.check()
        }
      }
    }

    private func check() {
      guard !isQuitting else { return }
      let hasWindows = !Self.appWindows.isEmpty
      if isHeadless {
        // a window SwiftUI opened by itself (an aicord:// link, Spotlight)
        if hasWindows { leave() }
      } else if !hasWindows, Self.isEnabled, Self.hasBackgroundWork {
        enter()
      }
    }

    // MARK: - Headless

    private func enter() {
      isHeadless = true
      logger.notice(
        "Last window closed: running in the background (MCP \(MCPPreferences.enabled), relay \(CloudRelayStore.shared.isEnabled))"
      )
      print("[Background] last window closed, running in the menu bar")
      // focus goes back to the app before, then the Dock icon goes
      NSApp.hide(nil)
      NSApp.setActivationPolicy(.accessory)
      AicordAppState.releaseWindowStates()
      ImagePipeline.shared.clearMemory()
      // no App Nap: the heartbeat, MCP answers and relay timers stay on time
      // (idle sleep is still allowed)
      activity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Discord connection, MCP server and Notifications Through the Mac")
    }

    private func leave() {
      guard isHeadless else { return }
      isHeadless = false
      if let activity { ProcessInfo.processInfo.endActivity(activity) }
      activity = nil
      if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
      print("[Background] window open again, back in the Dock")
    }

    /// Shows the main window: brings an open one forward, or opens a new one
    /// while headless (the Dock icon first: activation is only granted with it).
    func openMainWindow() {
      if let window = Self.mainWindow {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return
      }
      guard isHeadless else {
        NSApp.activate()
        return
      }
      NSApp.setActivationPolicy(.regular)
      NSApp.unhide(nil)
      windowRequest += 1
    }

    /// The Dock icon, or Aicord opened again from Finder or Spotlight.
    /// `true` lets SwiftUI open a new window when there's none.
    func handleReopen(hasVisibleWindows: Bool) -> Bool {
      guard isHeadless else { return true }
      if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
      NSApp.unhide(nil)
      return Self.mainWindow == nil
    }

    func willQuit() {
      isQuitting = true
    }
  }

  // MARK: - App delegate

  final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
      MainActor.assumeIsolated { MacBackground.shared.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
      -> Bool
    {
      MainActor.assumeIsolated { MacBackground.shared.handleReopen(hasVisibleWindows: flag) }
    }

    /// ⌘Q, Quit in the Dock or the menu bar item, log out: windows closing
    /// from here on don't mean "keep running".
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
      MainActor.assumeIsolated { MacBackground.shared.willQuit() }
      return .terminateNow
    }
  }

  // MARK: - Menu bar item

  /// The icon in the menu bar; also what opens the window while headless,
  /// since it's the only view left.
  struct MacBackgroundLabel: View {
    let background: MacBackground
    @Environment(\.openWindow) private var openWindow

    var body: some View {
      Image(systemName: "bubble.left.and.bubble.right.fill")
        .accessibilityLabel(Text(verbatim: "Aicord"))
        .onChange(of: background.windowRequest) {
          openWindow(id: MacBackground.mainWindowID)
          NSApp.activate()
        }
    }
  }

  struct MacBackgroundMenu: View {
    let background: MacBackground
    let gateway: GatewayStore
    let relay: CloudRelayStore
    let mcp: MCPBridge

    var body: some View {
      Text("Aicord Is Running in the Background")
      Text(gatewayStatus)
      Text(mcpStatus)
      Text(relayStatus)
      Divider()
      Button("Open Aicord") { background.openMainWindow() }
        .keyboardShortcut("o")
      Divider()
      Button("Quit Aicord") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    }

    private var gatewayStatus: String {
      gateway.state == .connected
        ? String(localized: "Discord: Connected")
        : String(localized: "Discord: Connecting…")
    }

    private var mcpStatus: String {
      guard MCPPreferences.enabled else { return String(localized: "MCP Server: Off") }
      return mcp.isRunning
        ? String(localized: "MCP Server: Running")
        : String(localized: "MCP Server: Not Running")
    }

    private var relayStatus: String {
      guard relay.isEnabled else {
        return String(localized: "Notifications Through the Mac: Off")
      }
      return switch relay.availability {
      case .available: String(localized: "Notifications Through the Mac: Sending")
      case .checking, .off: String(localized: "Notifications Through the Mac: Checking iCloud…")
      case .notEntitled, .noAccount, .unreachable:
        String(localized: "Notifications Through the Mac: iCloud Unavailable")
      }
    }
  }
#endif
