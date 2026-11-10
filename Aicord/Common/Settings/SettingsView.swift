//
//  SettingsView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 16/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.gateway) var gw
  @Environment(\.openURL) var openURL
  @Environment(\.dismiss) var dismiss

  @State private var selectedTab: SettingsTab?
  @State private var searchText: String = ""
  private let showsDoneButton: Bool

  /// Pass `initialTab: nil` where the split view collapses (the iPhone tab),
  /// so it opens on the category list instead of pushing a page.
  init(initialTab: SettingsTab? = .about, showsDoneButton: Bool = true) {
    _selectedTab = State(initialValue: initialTab)
    self.showsDoneButton = showsDoneButton
  }

  enum SettingsGroupCategory: String, CaseIterable {
    case you = ""
    case user = "Discord Settings"
    case app = "Aicord Settings"
  }

  enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case you
    case account
    case profiles
    case contentSocial
    case dataPrivacy
    case authorisedApps
    case devices
    case connections
    #if os(iOS)
      case scanQR
    #endif
    case appearance
    case voiceVideo
    case chat
    case intelligence
    case notifications
    case keybinds
    case language
    case advanced
    case about

    var id: String { rawValue }

    /// In the app's language; the cases below are the catalog's English keys.
    var title: String {
      Bundle.main.localizedString(forKey: englishTitle, value: englishTitle, table: nil)
    }

    private var englishTitle: String {
      switch self {
      case .you: "Profile & Status"
      case .about: "About Aicord"
      case .account: "My Account"
      case .profiles: "Profiles"
      case .contentSocial: "Content & Social"
      case .dataPrivacy: "Data & Privacy"
      case .authorisedApps: "Authorised Apps"
      case .devices: "Devices"
      case .connections: "Connections"
      #if os(iOS)
        case .scanQR: "Scan QR Code"
      #endif
      case .appearance: "Appearance"
      case .voiceVideo: "Voice & Video"
      case .chat: "Chat"
      case .intelligence: "Intelligence"
      case .notifications: "Notifications"
      case .keybinds: "Keybinds"
      case .language: "Language"
      case .advanced: "Advanced"
      }
    }

    var systemImage: String {
      switch self {
      case .you: "person.crop.circle"
      case .about: "info.circle"
      case .account: "person.crop.circle"
      case .profiles: "person.3.fill"
      case .contentSocial: "bubble.left.and.bubble.right"
      case .dataPrivacy: "hand.raised.fill"
      case .authorisedApps: "app"
      case .devices: "pc"
      case .connections: "link"
      #if os(iOS)
        case .scanQR: "qrcode"
      #endif
      case .appearance: "paintbrush"
      case .voiceVideo: "mic.fill"
      case .chat: "message"
      case .intelligence: "sparkles"
      case .notifications: "bell.fill"
      case .keybinds: "keyboard"
      case .language: "globe"
      case .advanced: "gear"
      }
    }

    var category: SettingsGroupCategory {
      switch self {
      case .you:
        .you
      case .account, .profiles, .contentSocial, .dataPrivacy,
        .authorisedApps, .devices, .connections:
        .user
      #if os(iOS)
        case .scanQR:
          .user
      #endif
      case .appearance, .voiceVideo, .chat, .intelligence,
        .notifications, .keybinds, .language, .advanced, .about:
        .app
      }
    }
  }

  private func tabs(for category: SettingsGroupCategory) -> [SettingsTab] {
    SettingsTab.allCases.filter { tab in
      tab.category == category
        && (searchText.isEmpty
          || tab.title.localizedCaseInsensitiveContains(searchText))
    }
  }

  #if os(macOS)
    /// The Settings window's toolbar tabs. Eighteen categories don't fit a
    /// toolbar, so related ones share a tab, each under its own headings.
    enum MacTab: String, CaseIterable, Identifiable {
      case account, profiles, privacy, appearance, chat, voiceVideo, notifications,
        intelligence, keybinds, advanced, about

      var id: String { rawValue }

      var sections: [SettingsTab] {
        switch self {
        case .account: [.you, .account, .devices]
        case .profiles: [.profiles]
        case .privacy: [.contentSocial, .dataPrivacy, .authorisedApps, .connections]
        case .appearance: [.appearance]
        case .chat: [.chat]
        case .voiceVideo: [.voiceVideo]
        case .notifications: [.notifications]
        case .intelligence: [.intelligence]
        case .keybinds: [.keybinds]
        case .advanced: [.language, .advanced]
        case .about: [.about]
        }
      }

      var title: String {
        let english =
          switch self {
          case .account: "Account"
          case .profiles: "Profiles"
          case .privacy: "Privacy"
          case .appearance: "Appearance"
          case .chat: "Chat"
          case .voiceVideo: "Voice & Video"
          case .notifications: "Notifications"
          case .intelligence: "Intelligence"
          case .keybinds: "Keybinds"
          case .advanced: "Advanced"
          case .about: "About Aicord"
          }
        return Bundle.main.localizedString(forKey: english, value: english, table: nil)
      }

      var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .profiles: "person.2"
        case .privacy: "hand.raised"
        case .appearance: "paintbrush"
        case .chat: "message"
        case .voiceVideo: "mic"
        case .notifications: "bell"
        case .intelligence: "sparkles"
        case .keybinds: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
      }
    }

    @AppStorage("Aicord.Settings.MacTab") private var macTab: MacTab = .account

    /// The Mac's Settings window: toolbar tabs, like Safari's or Mail's.
    var body: some View {
      TabView(selection: $macTab) {
        ForEach(MacTab.allCases) { tab in
          Tab(tab.title, systemImage: tab.systemImage, value: tab) {
            Form {
              ForEach(tab.sections) { section in
                detailContent(for: section)
              }
            }
            .formStyle(.grouped)
          }
        }
      }
      // a page opened from a tab is a sheet, and its title would replace the tab's
      .keepsWindowTitle(macTab.title)
    }
  #else
    var body: some View { splitBody }
  #endif

  private var splitBody: some View {
    NavigationSplitView {
      List(selection: $selectedTab) {
        ForEach(SettingsGroupCategory.allCases, id: \.self) { category in
          let items = tabs(for: category)
          if !items.isEmpty {
            if category == .you {
              Section {
                NavigationLink(value: SettingsTab.you) {
                  SettingsProfileCard()
                }
              }
            } else {
              Section(LocalizedStringKey(category.rawValue)) {
                ForEach(items) { tab in
                  NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.systemImage)
                  }
                }
              }
            }
          }
        }
      }
      .navigationTitle("Settings")
      .searchable(text: $searchText, prompt: "Search")
      #if os(iOS)
        .toolbar {
          if showsDoneButton {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Done") {
                dismiss()
              }
            }
          }
        }
      #endif
      .navigationSplitViewColumnWidth(min: 210, ideal: 230)
    } detail: {
      NavigationStack {
        if let selectedTab {
          #if os(iOS)
            if selectedTab == .scanQR {
              // the camera fills the screen instead of sitting in a form row
              scanQRSection
                .navigationTitle(selectedTab.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
              Form {
                detailContent(for: selectedTab)
              }
              .formStyle(.grouped)
              .navigationTitle(selectedTab.title)
            }
          #else
            Form {
              detailContent(for: selectedTab)
            }
            .formStyle(.grouped)
            .navigationTitle(selectedTab.title)
          #endif
        } else {
          ContentUnavailableView("Select a Category", systemImage: "gear")
        }
      }
    }
  }

  @ViewBuilder
  private func detailContent(for tab: SettingsTab) -> some View {
    switch tab {
    case .you:
      yourProfileSection
    case .about:
      aboutSection
    case .account:
      accountSection
    case .profiles:
      profilesSection
    case .contentSocial:
      contentSocialSection
    case .dataPrivacy:
      dataPrivacySection
    case .authorisedApps:
      authorisedAppsSection
    case .devices:
      devicesSection
    case .connections:
      connectionsSection
    #if os(iOS)
      case .scanQR:
        scanQRSection
    #endif
    case .appearance:
      appearanceSection
    case .voiceVideo:
      voiceVideoSection
    case .chat:
      chatSection
    case .intelligence:
      intelligenceSection
    case .notifications:
      notificationsSection
    case .keybinds:
      keybindsSection
    case .language:
      languageSection
    case .advanced:
      advancedSection
    }
  }
}

/// Like the Apple Account card in the Settings app: who you are and your status.
struct SettingsProfileCard: View {
  @Environment(\.gateway) var gw

  var body: some View {
    HStack(spacing: 12) {
      if let user = gw.user.currentUser {
        Profile.AvatarWithPresence(member: nil, user: user)
          .profileAnimated(false)
          .profileShowsAvatarDecoration()
          .frame(width: 52, height: 52)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(gw.user.currentUser?.global_name ?? gw.user.currentUser?.username ?? "")
          .font(.title3.weight(.semibold))
          .lineLimit(1)
        Group {
          if let status = gw.presence.currentClientStatusActivity?.state, !status.isEmpty {
            Text(status)
          } else {
            Text("Status, activity and profile")
          }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
  }
}

/// A row that opens a further page of settings. iOS pushes it. The Mac's
/// Settings window has its tabs in the toolbar, where a pushed page would add
/// a back button among them, so there the page opens as a sheet with Done,
/// as panes of System Settings do.
struct SettingsPageLink<Label: View, Destination: View>: View {
  private let destination: Destination
  private let label: Label
  #if os(macOS)
    @State private var isPresented = false
  #endif

  init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
    self.destination = destination()
    self.label = label()
  }

  var body: some View {
    #if os(macOS)
      Button {
        isPresented = true
      } label: {
        HStack {
          label
            .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .sheet(isPresented: $isPresented) {
        // a stack, so pages inside the sheet can still push
        NavigationStack {
          destination
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { isPresented = false }
              }
            }
        }
        .frame(width: 560, height: 520)
      }
    #else
      NavigationLink {
        destination
      } label: {
        label
      }
    #endif
  }
}

extension SettingsPageLink where Label == Text {
  init(_ title: LocalizedStringKey, @ViewBuilder destination: () -> Destination) {
    self.init(destination: destination) { Text(title) }
  }
}
