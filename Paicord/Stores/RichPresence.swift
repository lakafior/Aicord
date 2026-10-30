//
//  RichPresence.swift
//  Aicord
//
//  A user-made activity ("Playing …", "Listening to …") shown next to the custom
//  status, in the spirit of Vencord's CustomRPC and Serein's custom-rpc plugin.
//

import Foundation
import PaicordLib

struct RichPresence: Codable, Equatable {
  enum Kind: String, Codable, CaseIterable, Identifiable {
    case playing, streaming, listening, watching, competing
    var id: Self { self }

    var activityKind: Gateway.Activity.Kind {
      switch self {
      case .playing: .playing
      case .streaming: .streaming
      case .listening: .listening
      case .watching: .watching
      case .competing: .competing
      }
    }
  }

  enum TimerMode: String, Codable, CaseIterable, Identifiable {
    case none, sinceApplied, sinceMidnight, countdown
    var id: Self { self }
  }

  var kind: Kind = .playing
  var name = ""
  var details = ""
  var state = ""
  /// Twitch or YouTube link, used only for `.streaming`.
  var streamURL = ""

  /// Asset key of the application, or an `https://` image link.
  var largeImage = ""
  var largeText = ""
  var smallImage = ""
  var smallText = ""

  var timer: TimerMode = .none
  var countdownEnd = Date.now.addingTimeInterval(60 * 60)
  /// Set the first time the presence is applied; kept across edits, reset by Stop.
  var appliedAt: Date? = nil

  var showsParty = false
  var partySize = 1
  var partyMax = 4

  var button1Label = ""
  var button1URL = ""
  var button2Label = ""
  var button2URL = ""

  var buttons: [Gateway.Activity.Button] {
    [(button1Label, button1URL), (button2Label, button2URL)]
      .filter { !$0.0.isEmpty && URL(string: $0.1)?.scheme?.hasPrefix("http") == true }
      .map { .init(label: $0.0, url: $0.1) }
  }

  var startDate: Date? {
    switch timer {
    case .none, .countdown: nil
    case .sinceApplied: appliedAt ?? .now
    case .sinceMidnight: Calendar.current.startOfDay(for: .now)
    }
  }

  var endDate: Date? { timer == .countdown ? countdownEnd : nil }

  /// What's missing before the presence can be applied, or nil when it's ready.
  var problem: LocalizedStringResource? {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    if trimmedName.isEmpty { return "Give the activity a name." }
    if UInt64(DiscordApplication.id) == nil {
      return "Add your Discord application in Settings → My Account."
    }
    if kind == .streaming, URL(string: streamURL)?.host == nil {
      return "Streaming needs a Twitch or YouTube link."
    }
    if timer == .countdown, countdownEnd <= .now { return "The countdown has to end in the future." }
    if showsParty, partySize > partyMax { return "The party can't have more people than its size." }
    return nil
  }

  /// Builds the gateway activity. Image links are swapped for Discord media proxy paths.
  func activity(using client: any DiscordClient) async throws -> Gateway.Activity {
    let appID = ApplicationSnowflake(DiscordApplication.id)
    var activity = Gateway.Activity(
      name: name.trimmingCharacters(in: .whitespaces),
      type: kind.activityKind,
      url: kind == .streaming ? streamURL : nil,
      state: state.isEmpty ? nil : state
    )
    activity.application_id = appID
    activity.details = details.isEmpty ? nil : details

    if startDate != nil || endDate != nil {
      activity.timestamps = .init(
        start: startDate.map { Int($0.timeIntervalSince1970 * 1_000) },
        end: endDate.map { Int($0.timeIntervalSince1970 * 1_000) }
      )
    }
    if showsParty {
      activity.party = .init(size: IntPair(partySize, partyMax))
    }

    let links = [largeImage, smallImage].filter(Self.isLink)
    var proxied: [String: String] = [:]
    if !links.isEmpty {
      let res = try await client.createApplicationExternalAssets(
        applicationID: appID,
        payload: .init(urls: links)
      )
      try res.guardSuccess()
      for asset in try res.decode() {
        proxied[asset.url] = "mp:\(asset.external_asset_path)"
      }
    }
    func image(_ value: String) -> String? {
      guard !value.isEmpty else { return nil }
      return Self.isLink(value) ? proxied[value] : value
    }
    let large = image(largeImage)
    let small = image(smallImage)
    if large != nil || small != nil {
      activity.assets = .init(
        large_image: large,
        large_text: largeText.isEmpty || large == nil ? nil : largeText,
        small_image: small,
        small_text: smallText.isEmpty || small == nil ? nil : smallText
      )
    }

    let buttons = buttons
    activity.buttons = buttons.isEmpty ? nil : buttons
    return activity
  }

  static func isLink(_ value: String) -> Bool {
    value.hasPrefix("https://") || value.hasPrefix("http://")
  }

  // MARK: - Storage (per account)

  private static func key(_ kind: String, account: UserSnowflake) -> String {
    "Aicord.RichPresence.\(kind).\(account.rawValue)"
  }

  static func saved(for account: UserSnowflake) -> RichPresence? {
    guard let data = UserDefaults.standard.data(forKey: key("Fields", account: account)) else {
      return nil
    }
    return try? JSONDecoder().decode(RichPresence.self, from: data)
  }

  func save(for account: UserSnowflake) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    UserDefaults.standard.set(data, forKey: Self.key("Fields", account: account))
  }

  static func isEnabled(for account: UserSnowflake) -> Bool {
    UserDefaults.standard.bool(forKey: key("Enabled", account: account))
  }

  static func setEnabled(_ enabled: Bool, for account: UserSnowflake) {
    UserDefaults.standard.set(enabled, forKey: key("Enabled", account: account))
  }
}

extension PresenceStore {
  private var accountID: UserSnowflake? { gateway?.accounts.currentAccountID }

  /// Sends the presence and remembers it, so it comes back after reconnecting.
  func applyRichPresence(_ fields: RichPresence) async throws {
    guard let client = gateway?.client, let accountID else { return }
    var fields = fields
    if fields.timer == .sinceApplied, fields.appliedAt == nil { fields.appliedAt = .now }
    let activity = try await fields.activity(using: client)
    fields.save(for: accountID)
    RichPresence.setEnabled(true, for: accountID)
    richPresenceActivity = activity
    await setPresence(activities: ourActivities)
  }

  /// Removes the activity; the fields stay saved for next time.
  func stopRichPresence() async {
    if let accountID {
      RichPresence.setEnabled(false, for: accountID)
      if var fields = RichPresence.saved(for: accountID) {
        fields.appliedAt = nil
        fields.save(for: accountID)
      }
    }
    richPresenceActivity = nil
    await setPresence(activities: ourActivities)
  }

  /// Rebuilds the saved presence after connecting, if it was left on.
  func restoreRichPresence() async {
    guard
      let client = gateway?.client, let accountID,
      RichPresence.isEnabled(for: accountID),
      let fields = RichPresence.saved(for: accountID),
      fields.problem == nil
    else {
      richPresenceActivity = nil
      return
    }
    richPresenceActivity = try? await fields.activity(using: client)
  }
}

extension PresenceStore {
  /// "Share my activity" — whether others see what you're playing or listening to.
  var sharesActivity: Bool {
    guard let status = gateway?.settings.userSettings.status, status.hasShowCurrentGame else {
      return true
    }
    return status.showCurrentGame.value
  }

  func setSharesActivity(_ shares: Bool) async throws {
    var partial = DiscordProtos_DiscordUsers_V1_PreloadedUserSettings()
    partial.status.showCurrentGame = .init(shares)
    try await gateway?.settings.patchUserSettings(partial)
  }
}
