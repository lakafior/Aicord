//
//  AppearanceSection.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import AicordKit
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var appearanceSection: some View {
    AppearanceSettings()
  }
}

/// Theme, accent, text and motion, plus the animation settings Discord keeps
/// in the account's text and images group.
struct AppearanceSettings: View {
  typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  typealias StickerAnimation = SettingsStore.StickerAnimation

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  @AppStorage(AppearancePreferences.Key.textSize)
  private var textSize = AppearancePreferences.systemTextSize
  @AppStorage(AppearancePreferences.Key.fontDesign)
  private var fontDesign = AppearancePreferences.FontDesign.default
  @AppStorage(AppearancePreferences.Key.reduceMotion)
  private var reduceMotion = false
  @AppStorage(AppearancePreferences.Key.chatMessagesAnimated)
  private var chatMessagesAnimated = false

  @Bindable private var theming = Theming.shared

  var body: some View {
    Section {
      Picker("Appearance", selection: colorScheme) {
        Text("Light").tag(SchemeChoice.light)
        Text("Dark").tag(SchemeChoice.dark)
        Text("Automatic").tag(SchemeChoice.automatic)
      }
      .pickerStyle(.segmented)
      AccentColorRow(accent: $theming.accentOverride)
      ColorPicker("Custom Color", selection: customAccent, supportsOpacity: false)
      toggle("Accent on Tab Bar and Icons", isOn: $theming.accentTintsChrome)
      NavigationLink {
        Form {
          CustomThemesSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Custom Themes")
      } label: {
        LabeledContent("Custom Themes") {
          if isCustomTheme {
            Text(theming.selectedTheme.metadata.name)
          }
        }
      }
    } header: {
      Text("Theme")
    } footer: {
      if isCustomTheme {
        Text("Using a custom theme. Picking Light, Dark or Automatic switches back to the built-in one.")
      } else {
        Text("The accent colours buttons, links and selections. On the tab bar and icons it replaces the grey.")
      }
    }

    Section {
      toggle("Use System Text Size", isOn: usesSystemTextSize)
      if !usesSystemTextSize.wrappedValue {
        LabeledContent("Text Size") {
          Text(textSizeName(textSizeIndex))
        }
        Slider(
          value: textSizeValue,
          in: 0...Double(AppearancePreferences.textSizes.count - 1),
          step: 1
        ) {
          Text("Text Size")
        } minimumValueLabel: {
          Image(systemName: "textformat.size.smaller")
        } maximumValueLabel: {
          Image(systemName: "textformat.size.larger")
        }
        .labelsHidden()
      }
      Picker("Font", selection: $fontDesign) {
        ForEach(AppearancePreferences.FontDesign.allCases) { design in
          Text(design.title)
            .fontDesign(design.design)
            .tag(design)
        }
      }
    } header: {
      Text("Text")
    } footer: {
      Text("Text size and font apply to the whole app, messages included.")
    }

    Section {
      toggle("Reduce Motion", isOn: reduceMotionBinding)
        .disabled(systemReduceMotion)
      toggle("Animate New Messages", isOn: $chatMessagesAnimated)
        .disabled(reduceMotion || systemReduceMotion)
    } header: {
      Text("Motion")
    } footer: {
      Text(
        systemReduceMotion
          ? "Reduce Motion is on in system settings. Aicord follows it: no animations, still stickers."
          : "Reduce Motion turns off animations and stops stickers. Animate New Messages slides new and sending messages into the chat instead of showing them at once."
      )
    }

    Section {
      settingToggle("Play Animated Emoji", isOn: gw.settings.animatesEmoji) {
        $0.textAndImages.animateEmoji = .init($1)
      }
      settingToggle("Autoplay GIFs", isOn: gw.settings.autoplaysGIFs) {
        $0.textAndImages.gifAutoPlay = .init($1)
      }
      Picker("Animate Stickers", selection: stickerAnimation) {
        Text("Always").tag(StickerAnimation.always)
        Text("On Interaction").tag(StickerAnimation.onInteraction)
        Text("Never").tag(StickerAnimation.never)
      }
      settingToggle("Show Image Descriptions", isOn: gw.settings.showsImageDescriptions) {
        $0.textAndImages.viewImageDescriptions = .init($1)
      }
    } header: {
      Text("Animated Content")
    } footer: {
      Text(
        "Saved to your Discord account. GIFs that don't autoplay show a GIF badge and play when opened\(hoverHint). Image descriptions add an ALT badge to images that have one."
      )
    }
  }

  // MARK: - Values

  private enum SchemeChoice: Hashable {
    case light, dark, automatic, custom
  }

  private var isCustomTheme: Bool {
    !Theming.defaultThemes.map(\.id).contains(theming.currentThemeID)
  }

  /// The built-in Auto, Light and Dark themes are the three appearances.
  private var colorScheme: Binding<SchemeChoice> {
    Binding(
      get: {
        switch theming.currentThemeID {
        case "Paicord.Light": .light
        case "Paicord.Dark": .dark
        case "Paicord.Auto": .automatic
        default: .custom
        }
      },
      set: { choice in
        switch choice {
        case .light: theming.currentThemeID = "Paicord.Light"
        case .dark: theming.currentThemeID = "Paicord.Dark"
        case .automatic: theming.currentThemeID = "Paicord.Auto"
        case .custom: break
        }
      }
    )
  }

  private var customAccent: Binding<Color> {
    Binding(
      get: { theming.accentOverride ?? theming.selectedTheme.common.accent },
      set: { theming.accentOverride = $0 }
    )
  }

  private var hoverHint: String {
    #if os(macOS)
      " or on hover"
    #else
      ""
    #endif
  }

  /// The index used while the slider is shown, starting from the default size.
  private var textSizeIndex: Int {
    AppearancePreferences.textSizes.indices.contains(textSize)
      ? textSize : AppearancePreferences.textSizes.firstIndex(of: .large) ?? 3
  }

  private var usesSystemTextSize: Binding<Bool> {
    Binding(
      get: { textSize == AppearancePreferences.systemTextSize },
      set: { useSystem in
        textSize = useSystem ? AppearancePreferences.systemTextSize : textSizeIndex
      }
    )
  }

  private var textSizeValue: Binding<Double> {
    Binding(
      get: { Double(textSizeIndex) },
      set: { textSize = Int($0.rounded()) }
    )
  }

  private func textSizeName(_ index: Int) -> LocalizedStringKey {
    switch AppearancePreferences.textSizes[index] {
    case .xSmall: "Extra Small"
    case .small: "Small"
    case .medium: "Medium"
    case .large: "Default"
    case .xLarge: "Large"
    case .xxLarge: "Extra Large"
    case .xxxLarge: "Extra Extra Large"
    case .accessibility1: "Accessibility 1"
    case .accessibility2: "Accessibility 2"
    case .accessibility3: "Accessibility 3"
    case .accessibility4: "Accessibility 4"
    case .accessibility5: "Accessibility 5"
    @unknown default: "Default"
    }
  }

  private var reduceMotionBinding: Binding<Bool> {
    Binding(
      get: { reduceMotion || systemReduceMotion },
      set: { reduceMotion = $0 }
    )
  }

  private var stickerAnimation: Binding<StickerAnimation> {
    Binding(
      get: { gw.settings.stickerAnimation },
      set: { value in patch { $0.textAndImages.animateStickers = .init(value.rawValue) } }
    )
  }

  // MARK: - Rows

  private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
    Toggle(title, isOn: isOn)
      #if os(macOS)
        .toggleStyle(.switch)
      #endif
  }

  private func settingToggle(
    _ title: LocalizedStringKey,
    isOn: Bool,
    write: @escaping (inout Settings, Bool) -> Void
  ) -> some View {
    toggle(
      title,
      isOn: Binding(
        get: { isOn },
        set: { newValue in patch { write(&$0, newValue) } }
      )
    )
  }

  private func patch(_ change: @escaping (inout Settings) -> Void) {
    Task {
      do {
        try await gw.settings.patchUserSettings(change)
      } catch {
        appState.error = error
      }
    }
  }
}

/// Swatches for the accent, the theme's own first.
private struct AccentColorRow: View {
  @Binding var accent: Color?

  private static let presets: [Color] = [
    Color(hexadecimal6: 0x0A84FF),
    Color(hexadecimal6: 0x30B0C7),
    Color(hexadecimal6: 0x34C759),
    Color(hexadecimal6: 0xFFCC00),
    Color(hexadecimal6: 0xFF9500),
    Color(hexadecimal6: 0xFF3B30),
    Color(hexadecimal6: 0xFF2D55),
    Color(hexadecimal6: 0xAF52DE),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Accent Color")
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          swatch(Theming.shared.selectedTheme.common.accent, isSelected: accent == nil) {
            accent = nil
          }
          .accessibilityLabel("Theme Default")
          ForEach(Self.presets.indices, id: \.self) { index in
            let color = Self.presets[index]
            swatch(color, isSelected: accent.map { matches($0, color) } ?? false) {
              accent = color
            }
          }
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
    }
  }

  private func swatch(
    _ color: Color,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Circle()
        .fill(color)
        .frame(width: 28, height: 28)
        .overlay {
          if isSelected {
            Image(systemName: "checkmark")
              .font(.caption.bold())
              .foregroundStyle(.white)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Compares the stored colour, which went through JSON, with a preset.
  private func matches(_ lhs: Color, _ rhs: Color) -> Bool {
    let environment = EnvironmentValues()
    let a = lhs.resolve(in: environment)
    let b = rhs.resolve(in: environment)
    return abs(a.red - b.red) < 0.01 && abs(a.green - b.green) < 0.01
      && abs(a.blue - b.blue) < 0.01
  }
}

/// Themes imported from JSON files.
struct CustomThemesSection: View {
  let theming = Theming.shared
  @State private var showingImportTheme = false
  @State private var importError: Error?

  var body: some View {
    Section {
      if theming.loadedThemes.isEmpty {
        Text("No custom themes")
          .foregroundStyle(.secondary)
      }
      ForEach(theming.loadedThemes) { theme in
        Button {
          theming.currentThemeID = theme.id
        } label: {
          themeRow(theme: theme)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
          Button(role: .destructive) {
            delete(theme)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
        .contextMenu {
          Button(role: .destructive) {
            delete(theme)
          } label: {
            Label("Delete", systemImage: "trash")
          }
        }
      }
    } footer: {
      Text("Swipe on a theme to delete it.")
    }
    Section {
      Button {
        showingImportTheme = true
      } label: {
        Text("Add Theme")
      }
      .fileImporter(
        isPresented: $showingImportTheme,
        allowedContentTypes: [.json],
        allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          guard let url = urls.first else { return }
          do {
            guard url.startAccessingSecurityScopedResource() else {
              throw NSError(
                domain: "net.smigi.aicord",
                code: 1,
                userInfo: [
                  NSLocalizedDescriptionKey:
                    "Unable to access the selected file."
                ]
              )
            }

            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let theme = try JSONDecoder().decode(
              Theming.Theme.self,
              from: data
            )
            theming.loadedThemes = theming.loadedThemes + [theme]
          } catch {
            self.importError = error
          }
        case .failure(let error):
          print("Failed to import theme: \(error)")
        }
      }
    } footer: {
      Text("A theme is a JSON file with its own colours and, optionally, a fixed light or dark appearance.")
    }
  }

  private func delete(_ theme: Theming.Theme) {
    if theming.currentThemeID == theme.id {
      theming.currentThemeID = "Paicord.Auto"
    }
    theming.loadedThemes = theming.loadedThemes.filter { $0.id != theme.id }
  }

  @ViewBuilder
  func themeRow(theme: Theming.Theme) -> some View {
    HStack {
      VStack(alignment: .leading) {
        Text(theme.metadata.name)
          .foregroundStyle(Color.primary)
        Text(verbatim: "\(theme.metadata.author) • v\(theme.metadata.version)")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }

      Spacer()

      if theming.currentThemeID == theme.id {
        Image(systemName: "checkmark")
          .foregroundStyle(theme.common.primaryButton)
      }
    }
    .contentShape(.rect)
  }
}
