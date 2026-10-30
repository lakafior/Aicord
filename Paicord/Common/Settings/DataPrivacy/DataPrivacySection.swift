//
//  DataPrivacySection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 02/12/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import PaicordLib
import SwiftProtobuf
import SwiftUI

extension SettingsView {
  @ViewBuilder
  var dataPrivacySection: some View {
    DataPrivacySettings()
  }
}

/// Activity privacy and data use. Most of it lives in the account's settings
/// proto; the two data consents and data requests are separate endpoints.
struct DataPrivacySettings: View {
  typealias Settings = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings
  typealias ActivityDefault = Settings.GuildActivityStatusRestrictionDefaultV2

  @Environment(\.gateway) var gw
  @Environment(\.appState) var appState

  @State private var consents: DiscordUserConsents?
  @State private var harvest: HarvestState = .loading
  @State private var confirmsDataRequest = false

  private var settings: Settings { gw.settings.userSettings }
  private var privacy: Settings.PrivacySettings { settings.privacy }

  var body: some View {
    Section {
      settingToggle(
        "Share Your Activity",
        isOn: settings.status.hasShowCurrentGame ? settings.status.showCurrentGame.value : true
      ) { $0.status.showCurrentGame = .init($1) }
      Picker("Share Activity in New Servers", selection: activityDefault) {
        Text("All Servers").tag(ActivityDefault.activityStatusOff)
        Text("Except Large Servers").tag(ActivityDefault.activityStatusOnForLargeGuilds)
        Text("No Servers").tag(ActivityDefault.activityStatusOn)
      }
      settingToggle(
        "Friends Can Join Without Asking",
        isOn: boolValue(privacy.hasAllowActivityPartyPrivacyFriends, privacy.allowActivityPartyPrivacyFriends, unset: true)
      ) { $0.privacy.allowActivityPartyPrivacyFriends = .init($1) }
      settingToggle(
        "Voice Channel Members Can Join Without Asking",
        isOn: boolValue(
          privacy.hasAllowActivityPartyPrivacyVoiceChannel, privacy.allowActivityPartyPrivacyVoiceChannel, unset: true)
      ) { $0.privacy.allowActivityPartyPrivacyVoiceChannel = .init($1) }
      settingToggle(
        "Recent Games on Your Profile",
        isOn: boolValue(privacy.hasRecentGamesEnabled, privacy.recentGamesEnabled, unset: true)
      ) { $0.privacy.recentGamesEnabled = .init($1) }
    } header: {
      Text("Activity Privacy")
    } footer: {
      Text(
        "Your activity is the game you play or what you listen to. The server option applies to servers you join from now on; joining without asking does not apply to community servers."
      )
    }

    Section {
      consentToggle("Use Data to Improve Discord", kind: .usageStatistics)
      consentToggle("Use Data to Personalise Discord", kind: .personalization)
      settingToggle(
        "Personalise Quests with Third-Party Data",
        isOn: !privacy.quests3PDataOptedOut.value
      ) { $0.privacy.quests3PDataOptedOut = .init(!$1) }
      settingToggle(
        "Allow Screen Reader Detection",
        isOn: privacy.allowAccessibilityDetection
      ) { $0.privacy.allowAccessibilityDetection = $1 }
      settingToggle(
        "Help Improve the Spam Filter",
        isOn: privacy.nonSpamRetrainingOptIn.value
      ) { $0.privacy.nonSpamRetrainingOptIn = .init($1) }
    } header: {
      Text("How Discord Uses Your Data")
    } footer: {
      Text(
        "Usage data covers how you use Discord, not your messages. The spam filter learns from messages you mark as not spam."
      )
    }

    Section {
      LabeledContent("Last Request") {
        switch harvest {
        case .loading:
          ProgressView()
        case .none:
          Text("None")
        case .request(let request):
          Text(harvestSummary(request))
        case .failed:
          Text("Couldn't Load")
        }
      }
      Button("Request a Copy of Your Data") {
        confirmsDataRequest = true
      }
      .disabled(!canRequestData)
      .confirmationDialog(
        "Request a Copy of Your Data?",
        isPresented: $confirmsDataRequest,
        titleVisibility: .visible
      ) {
        Button("Request Data") { requestData() }
      } message: {
        Text("Discord emails a download link to your account's address. This can take up to 30 days.")
      }
    } header: {
      Text("Your Data")
    } footer: {
      Text("You can ask for a new copy once every 30 days.")
    }
    .task { await load() }
  }

  // MARK: - Values

  private enum HarvestState {
    case loading
    case none
    case request(DiscordUserHarvest)
    case failed
  }

  private var canRequestData: Bool {
    switch harvest {
    case .none: true
    case .request(let request):
      Date.now.timeIntervalSince(request.created_at.date) > 30 * 24 * 60 * 60
    case .loading, .failed: false
    }
  }

  private func harvestSummary(_ request: DiscordUserHarvest) -> String {
    let date = request.created_at.date.formatted(date: .abbreviated, time: .omitted)
    switch request.status {
    case .queued, .running: return String(localized: "Preparing, requested \(date)")
    case .completed: return String(localized: "Sent \(date)")
    case .failed: return String(localized: "Failed, requested \(date)")
    case .cancelled: return String(localized: "Cancelled, requested \(date)")
    default:
      return request.state == .delivered ? String(localized: "Sent \(date)") : date
    }
  }

  /// Discord has a deprecated and a v2 field for this; both are written, the
  /// v2 one wins when reading. Unset depends on the region, shown as "All".
  private var activityDefault: Binding<ActivityDefault> {
    Binding(
      get: {
        switch privacy.defaultGuildsActivityRestrictedV2 {
        case .activityStatusUnset, .UNRECOGNIZED:
          switch privacy.defaultGuildsActivityRestricted {
          case .onForLargeGuilds: .activityStatusOnForLargeGuilds
          case .on: .activityStatusOn
          default: .activityStatusOff
          }
        case let value: value
        }
      },
      set: { value in
        patch {
          $0.privacy.defaultGuildsActivityRestrictedV2 = value
          $0.privacy.defaultGuildsActivityRestricted =
            switch value {
            case .activityStatusOnForLargeGuilds: .onForLargeGuilds
            case .activityStatusOn: .on
            default: .off
            }
        }
      }
    )
  }

  private func boolValue(_ isSet: Bool, _ value: Google_Protobuf_BoolValue, unset: Bool) -> Bool {
    isSet ? value.value : unset
  }

  // MARK: - Rows

  private func settingToggle(
    _ title: LocalizedStringKey,
    isOn: Bool,
    write: @escaping (inout Settings, Bool) -> Void
  ) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { isOn },
        set: { newValue in patch { write(&$0, newValue) } }
      )
    )
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
  }

  private func consentToggle(_ title: LocalizedStringKey, kind: DiscordUserConsent.Kind) -> some View {
    Toggle(
      title,
      isOn: Binding(
        get: { consents?[kind.rawValue]?.consented ?? false },
        set: { newValue in setConsent(kind, newValue) }
      )
    )
    .disabled(consents == nil)
    #if os(macOS)
      .toggleStyle(.switch)
    #endif
  }

  // MARK: - Requests

  private func load() async {
    async let consentsResponse = try? gw.client.getUserConsents().decode()
    async let harvestResponse = try? gw.client.getUserHarvest()
    let loadedConsents = await consentsResponse
    let loadedHarvest = await harvestResponse
    // Leaving the screen cancels the requests; that is not a failure.
    guard !Task.isCancelled else { return }
    consents = loadedConsents
    guard let response = loadedHarvest, (200..<300).contains(response.status.code) else {
      harvest = .failed
      return
    }
    if response.status.code == 204 || response.body?.isEmpty != false {
      harvest = .none
    } else if let request = try? response.decode(as: DiscordUserHarvest.self) {
      harvest = .request(request)
    } else {
      harvest = .failed
    }
  }

  private func setConsent(_ kind: DiscordUserConsent.Kind, _ granted: Bool) {
    let previous = consents
    consents?[kind.rawValue] = .init(consented: granted)
    Task {
      do {
        let payload = granted ? Payloads.ModifyUserConsents(grant: [kind]) : .init(revoke: [kind])
        let updated = try await gw.client.modifyUserConsents(payload: payload).decode()
        // The response leaves out usage statistics, so merge instead of replacing.
        consents?.merge(updated) { $1 }
      } catch {
        consents = previous
        appState.error = error
      }
    }
  }

  private func requestData() {
    Task {
      do {
        harvest = .request(try await gw.client.createUserHarvest().decode())
      } catch {
        appState.error = error
      }
    }
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
