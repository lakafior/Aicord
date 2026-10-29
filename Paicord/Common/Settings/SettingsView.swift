//
//  SettingsView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 16/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUIX

struct SettingsView: View {
  @Environment(\.gateway) var gw
  @Environment(\.openURL) var openURL
  @Environment(\.dismiss) var dismiss

  @AppStorage("Paicord.Appearance.ChatMessagesAnimated")
  var chatMessagesAnimated: Bool = false

  @State private var selectedTab: SettingsTab? = .paicord
  @State private var searchText: String = ""

  enum SettingsGroupCategory: String, CaseIterable {
    case paicord = "Paicord"
    case user = "User Settings"
    case app = "App Settings"
    case debug = "Debug"
  }

  enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case paicord
    case account
    case profiles
    case contentSocial
    case dataPrivacy
    case familyCentre
    case authorisedApps
    case devices
    case connections
    case clips
    #if os(iOS)
      case scanQR
    #endif
    case theming
    case appearance
    case accessibility
    case voiceVideo
    case chat
    case notifications
    case keybinds
    case language
    case advanced
    case debug

    var id: String { rawValue }

    var title: String {
      switch self {
      case .paicord: "Paicord"
      case .account: "My Account"
      case .profiles: "Profiles"
      case .contentSocial: "Content & Social"
      case .dataPrivacy: "Data & Privacy"
      case .familyCentre: "Family Centre"
      case .authorisedApps: "Authorised Apps"
      case .devices: "Devices"
      case .connections: "Connections"
      case .clips: "Clips"
      #if os(iOS)
        case .scanQR: "Scan QR Code"
      #endif
      case .theming: "Theming"
      case .appearance: "Appearance"
      case .accessibility: "Accessibility"
      case .voiceVideo: "Voice & Video"
      case .chat: "Chat"
      case .notifications: "Notifications"
      case .keybinds: "Keybinds"
      case .language: "Language"
      case .advanced: "Advanced"
      case .debug: "Debug"
      }
    }

    var systemImage: String {
      switch self {
      case .paicord: "leaf"
      case .account: "person.crop.circle"
      case .profiles: "person.3.fill"
      case .contentSocial: "bubble.left.and.bubble.right"
      case .dataPrivacy: "hand.raised.fill"
      case .familyCentre: "house"
      case .authorisedApps: "app"
      case .devices: "pc"
      case .connections: "link"
      case .clips: "scissors"
      #if os(iOS)
        case .scanQR: "qrcode"
      #endif
      case .theming: "paintbrush"
      case .appearance: "display"
      case .accessibility: "accessibility.fill"
      case .voiceVideo: "mic.fill"
      case .chat: "message"
      case .notifications: "bell.fill"
      case .keybinds: "keyboard"
      case .language: "globe"
      case .advanced: "gear"
      case .debug: "ladybug"
      }
    }

    var category: SettingsGroupCategory {
      switch self {
      case .paicord:
        .paicord
      case .account, .profiles, .contentSocial, .dataPrivacy, .familyCentre,
        .authorisedApps, .devices, .connections, .clips:
        .user
      #if os(iOS)
        case .scanQR:
          .user
      #endif
      case .theming, .appearance, .accessibility, .voiceVideo, .chat,
        .notifications, .keybinds, .language, .advanced:
        .app
      case .debug:
        .debug
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

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedTab) {
        ForEach(SettingsGroupCategory.allCases, id: \.self) { category in
          let items = tabs(for: category)
          if !items.isEmpty {
            Section(category.rawValue) {
              ForEach(items) { tab in
                NavigationLink(value: tab) {
                  Label(tab.title, systemImage: tab.systemImage)
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
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") {
              dismiss()
            }
          }
        }
      #endif
    } detail: {
      NavigationStack {
        if let selectedTab {
          Form {
            detailContent(for: selectedTab)
          }
          .formStyle(.grouped)
          .navigationTitle(selectedTab.title)
        } else {
          ContentUnavailableView("Select a Category", systemImage: "gear")
        }
      }
    }
  }

  @ViewBuilder
  private func detailContent(for tab: SettingsTab) -> some View {
    switch tab {
    case .paicord:
      paicordSection
    case .account:
      accountSection
    case .profiles:
      profilesSection
    case .contentSocial:
      contentSocialSection
    case .dataPrivacy:
      dataPrivacySection
    case .familyCentre:
      familyCentreSection
    case .authorisedApps:
      authorisedAppsSection
    case .devices:
      devicesSection
    case .connections:
      connectionsSection
    case .clips:
      clipsSection
    #if os(iOS)
      case .scanQR:
        scanQRSection
    #endif
    case .theming:
      themingSection
    case .appearance:
      appearanceSection
    case .accessibility:
      accessibilitySection
    case .voiceVideo:
      voiceVideoSection
    case .chat:
      chatSection
    case .notifications:
      notificationsSection
    case .keybinds:
      keybindsSection
    case .language:
      languageSection
    case .advanced:
      advancedSection
    case .debug:
      debugSection
    }
  }
}
