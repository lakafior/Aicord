//
//  SettingsView.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 16/09/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

struct SettingsView: View {
  @Environment(\.gateway) var gw
  @Environment(\.openURL) var openURL
  @Environment(\.dismiss) var dismiss

  @AppStorage("Paicord.Appearance.ChatMessagesAnimated")
  var chatMessagesAnimated: Bool = false

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
    case about = "Aicord"
    case user = "User Settings"
    case app = "App Settings"
    case debug = "Debug"
  }

  enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case you
    case about
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
      case .you:
        .you
      case .about:
        .about
      case .account, .profiles, .contentSocial, .dataPrivacy,
        .authorisedApps, .devices, .connections:
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
            if category == .you {
              Section {
                NavigationLink(value: SettingsTab.you) {
                  SettingsProfileCard()
                }
              }
            } else {
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
