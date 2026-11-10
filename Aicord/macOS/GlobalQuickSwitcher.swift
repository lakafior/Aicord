//
//  GlobalQuickSwitcher.swift
//  Aicord
//
//  A system-wide shortcut for the Quick Switcher: from any app, it brings
//  Aicord's main window to the front with the switcher open. Carbon's hot
//  keys need no Accessibility permission and only see the chosen keys.
//

#if os(macOS)
  import AppKit
  import Carbon.HIToolbox
  import SwiftUI

  @MainActor
  final class GlobalQuickSwitcher {
    static let shared = GlobalQuickSwitcher()

    static let enabledKey = "Aicord.QuickSwitcher.GlobalEnabled"
    static let shortcutKey = "Aicord.QuickSwitcher.GlobalShortcut"

    /// The shortcuts to choose from; free-form recording isn't worth the code.
    enum Shortcut: String, CaseIterable, Identifiable {
      case controlOptionSpace, commandShiftK, commandOptionK, controlOptionK, commandShiftSpace

      var id: String { rawValue }

      var label: String {
        switch self {
        case .controlOptionSpace: "⌃ ⌥ Space"
        case .commandShiftK: "⇧ ⌘ K"
        case .commandOptionK: "⌥ ⌘ K"
        case .controlOptionK: "⌃ ⌥ K"
        case .commandShiftSpace: "⇧ ⌘ Space"
        }
      }

      var keyCode: UInt32 {
        switch self {
        case .controlOptionSpace, .commandShiftSpace: UInt32(kVK_Space)
        default: UInt32(kVK_ANSI_K)
        }
      }

      var modifiers: UInt32 {
        switch self {
        case .controlOptionSpace, .controlOptionK: UInt32(controlKey | optionKey)
        case .commandShiftK, .commandShiftSpace: UInt32(cmdKey | shiftKey)
        case .commandOptionK: UInt32(cmdKey | optionKey)
        }
      }
    }

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Whether the last registration worked; another app may hold the keys.
    private(set) var registrationFailed = false

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var shortcut: Shortcut {
      UserDefaults.standard.string(forKey: shortcutKey).flatMap(Shortcut.init) ?? .controlOptionSpace
    }

    /// Registers or removes the hot key to match the settings.
    func update() {
      unregister()
      guard Self.isEnabled else {
        registrationFailed = false
        return
      }
      installHandlerIfNeeded()
      let shortcut = Self.shortcut
      let id = EventHotKeyID(signature: OSType(0x4149_4344), id: 1)  // "AICD"
      let status = RegisterEventHotKey(
        shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
      registrationFailed = status != noErr
    }

    private func unregister() {
      if let hotKey { UnregisterEventHotKey(hotKey) }
      hotKey = nil
    }

    private func installHandlerIfNeeded() {
      guard handler == nil else { return }
      var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      InstallEventHandler(
        GetApplicationEventTarget(),
        { _, _, _ in
          DispatchQueue.main.async {
            MainActor.assumeIsolated { GlobalQuickSwitcher.shared.show() }
          }
          return noErr
        },
        1, &type, nil, &handler)
    }

    /// Brings the main window forward with the switcher open, or closes it
    /// when it's already up in front.
    func show() {
      guard let state = AicordAppState.main else {
        NSApp.activate()
        return
      }
      if NSApp.isActive, state.showingQuickSwitcher {
        state.showingQuickSwitcher = false
        return
      }
      NSApp.activate()
      let window =
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0.identifier?.rawValue.contains("Channel") != true }
        ?? NSApp.windows.first { $0.canBecomeMain }
      if let window {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
      }
      if GatewayStore.shared.state == .connected {
        state.showingQuickSwitcher = true
      }
    }
  }

  /// Settings → Keybinds on the Mac.
  struct GlobalQuickSwitcherSettings: View {
    @AppStorage(GlobalQuickSwitcher.enabledKey) private var enabled = false
    @AppStorage(GlobalQuickSwitcher.shortcutKey) private var shortcut = GlobalQuickSwitcher.Shortcut
      .controlOptionSpace
    @State private var failed = false

    var body: some View {
      Section {
        Toggle("Quick Switcher from Any App", isOn: $enabled)
          .toggleStyle(.switch)
        Picker("Shortcut", selection: $shortcut) {
          ForEach(GlobalQuickSwitcher.Shortcut.allCases) { shortcut in
            Text(verbatim: shortcut.label).tag(shortcut)
          }
        }
        .disabled(!enabled)
        if failed {
          Label("Another app already uses this shortcut. Pick a different one.", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      } header: {
        Text("Global")
      } footer: {
        Text(
          "Brings Aicord forward with the Quick Switcher open, over the app you're in. Works while Aicord is running, also with no window in front."
        )
      }
      .onChange(of: enabled) { apply() }
      .onChange(of: shortcut) { apply() }
      .onAppear { failed = GlobalQuickSwitcher.shared.registrationFailed }
    }

    private func apply() {
      GlobalQuickSwitcher.shared.update()
      failed = GlobalQuickSwitcher.shared.registrationFailed
    }
  }
#endif
