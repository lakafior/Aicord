//
//  DemoMode.swift
//  Aicord
//

import AicordKit
import Foundation

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// Keeps the app's real settings safe while demo mode runs. Demo mode puts
/// them in a file and starts from empty settings; quitting puts them back.
/// If the demo app didn't quit cleanly, the next normal launch puts them
/// back. This part is in every build, so a Release build restores them too.
enum DemoSettingsBackup {
  private static var file: URL {
    URL.applicationSupportDirectory.appending(path: "DemoModeSettingsBackup.plist")
  }

  private static var domain: String? { Bundle.main.bundleIdentifier }

  /// Puts the real settings aside and clears them. Keeps an existing
  /// backup: a second demo launch would otherwise back up demo settings.
  static func putAside() -> Bool {
    guard let domain else { return false }
    let defaults = UserDefaults.standard
    if !FileManager.default.fileExists(atPath: file.path()) {
      let settings = defaults.persistentDomain(forName: domain) ?? [:]
      guard
        let data = try? PropertyListSerialization.data(
          fromPropertyList: settings, format: .binary, options: 0)
      else { return false }
      try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      guard (try? data.write(to: file)) != nil else { return false }
    }
    defaults.removePersistentDomain(forName: domain)
    return true
  }

  /// Puts the real settings back, if demo mode put them aside.
  static func restore() {
    guard let domain,
      let data = try? Data(contentsOf: file),
      let settings = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { return }
    UserDefaults.standard.setPersistentDomain(settings, forName: domain)
    UserDefaults.standard.synchronize()
    try? FileManager.default.removeItem(at: file)
  }
}

#if DEBUG
  /// Demo mode runs the app on made-up data from `DemoWorld`, without a
  /// Discord account or a network connection. It's for screenshots and only
  /// exists in Debug builds. Turn it on with the launch argument
  /// `-AicordDemo YES`.
  ///
  /// The real account stays untouched: the keychain isn't read or written,
  /// and `DemoSettingsBackup` keeps the settings.
  enum DemoMode {
    static let isEnabled = UserDefaults.standard.bool(forKey: "AicordDemo")

    /// Call before anything reads the settings.
    @MainActor
    static func prepare() {
      guard isEnabled else { return }
      guard DemoSettingsBackup.putAside() else {
        // without a backup the real settings would be lost: quit instead
        exit(1)
      }
      let defaults = UserDefaults.standard
      // nothing of the demo goes into Spotlight or the offline cache on disk
      defaults.set(false, forKey: SystemIntegration.spotlightEnabledKey)
      defaults.set(false, forKey: OfflineCache.enabledKey)
      URLProtocol.registerClass(DemoImages.self)
      #if os(macOS)
        let quit = NSApplication.willTerminateNotification
      #else
        let quit = UIApplication.willTerminateNotification
      #endif
      NotificationCenter.default.addObserver(forName: quit, object: nil, queue: nil) { _ in
        DemoSettingsBackup.restore()
      }
    }

    /// Opens the place named by the launch argument `-AicordDemoOpen`, once
    /// the demo is ready: `server` for Swift Studio's channel list, a Swift
    /// Studio channel by name (`swiftui`), or a DM by username with an @
    /// (`@leopark`). For screenshots.
    @MainActor
    static func openRequestedPlace() {
      guard let name = UserDefaults.standard.string(forKey: "AicordDemoOpen") else { return }
      if name == "server" {
        AicordAppState.externalTarget?.selectedGuild = GuildSnowflake(DemoWorld.swiftStudioID)
        return
      }
      let guild: String?
      let channel: String?
      if name.hasPrefix("@") {
        let username = name.dropFirst()
        let person = DemoWorld.people.first { $0.username == username }
        guild = nil
        channel = DemoWorld.privateChannels.first { dm in
          (dm["recipients"] as? [DemoWorld.JSON])?.count == 1
            && (dm["recipients"] as? [DemoWorld.JSON])?.first?["id"] as? String == person?.id
        }?["id"] as? String
      } else {
        guild = DemoWorld.swiftStudioID
        channel = DemoWorld.swiftStudio.channels.first { $0.name == name }?.id
      }
      guard let channel else { return }
      AicordAppState.openExternally(
        guild: guild.map(GuildSnowflake.init), channel: ChannelSnowflake(channel))
    }

    /// The demo account, as the account list holds it.
    static var account: TokenStore.AccountData? {
      guard
        let user = try? DiscordGlobalConfiguration.decoder.decode(
          DiscordUser.self, from: DemoWorld.data(DemoWorld.meUser))
      else { return nil }
      return TokenStore.AccountData(user: user, token: Secret("demo"))
    }

    @MainActor
    static func makeGateway(
      stateCallback: @escaping @Sendable (GatewayState) -> Void
    ) async -> UserGatewayManager {
      await UserGatewayManager(
        replaying: DemoGateway(), client: DemoDiscordClient(), stateCallback: stateCallback)
    }
  }

  /// Discord's side of the gateway in demo mode.
  struct DemoGateway: GatewayReplaySource {
    func initialFrames() -> [Data] {
      [DemoWorld.frame("READY", DemoWorld.ready)]
    }

    func frames(answering payload: Gateway.Event) -> [Data] {
      switch payload.data {
      case .updateGuildSubscriptions(let update):
        // a channel asking for its member list gets the whole list at once
        return update.subscriptions.compactMap { guildID, subscription in
          guard subscription.channels?.isEmpty == false,
            let server = DemoWorld.servers.first(where: { $0.id == guildID.rawValue })
          else { return nil }
          return DemoWorld.frame(
            "GUILD_MEMBER_LIST_UPDATE", DemoWorld.memberListSync(for: server, listID: "everyone"))
        }
      default:
        return []
      }
    }
  }

  /// Discord's HTTP API in demo mode. Reads come from `DemoWorld`; anything
  /// else gets an empty success, so nothing reaches Discord.
  struct DemoDiscordClient: DiscordClient {
    var captchaCallback: CaptchaChallengeHandler?
    var mfaCallback: MFAVerificationHandler?
    var authentication: AuthenticationHeader { .userToken(Secret("demo")) }

    func send(request: DiscordHTTPRequest) async throws -> DiscordHTTPResponse {
      respond(to: request)
    }

    func send<E: Sendable & Encodable & ValidatablePayload>(
      request: DiscordHTTPRequest, payload: E
    ) async throws -> DiscordHTTPResponse {
      respond(to: request)
    }

    func sendMultipart<E: Sendable & MultipartEncodable & ValidatablePayload>(
      request: DiscordHTTPRequest, payload: E
    ) async throws -> DiscordHTTPResponse {
      respond(to: request)
    }

    private func respond(to request: DiscordHTTPRequest) -> DiscordHTTPResponse {
      let url = URL(string: request.endpoint.url)
      let parts = url?.pathComponents.filter { $0 != "/" } ?? []
      // drop "api" and the version
      let path = Array(parts.drop { $0 == "api" || $0.hasPrefix("v") && Int($0.dropFirst()) != nil })
      let method = request.endpoint.httpMethod

      if method == .GET, path.count == 3, path[0] == "channels", path[2] == "messages" {
        return ok(messages(in: path[1], queries: request.queries))
      }
      if method == .GET, path.count >= 3, path[0] == "users", path[2] == "profile" {
        return ok(profile(for: path[1]))
      }
      if method == .GET, path.starts(with: ["users", "@me", "settings-proto"]) {
        // empty settings: the app keeps its defaults
        return ok(["settings": ""])
      }
      if method == .GET, path.count == 3, path[0] == "guilds", path[2] == "scheduled-events" {
        return ok([])
      }
      if method == .GET, path.last == "application-command-index" {
        return ok(["applications": [], "application_commands": [], "version": "0"])
      }
      print("[DemoMode] Unhandled \(method) /\(path.joined(separator: "/"))")
      return DiscordHTTPResponse(
        host: "discord.com", status: method == .GET ? .notFound : .noContent,
        headers: ["Content-Type": "application/json"],
        body: method == .GET
          ? DemoWorld.data(["message": "Not in demo mode", "code": 0]) : nil)
    }

    private func ok(_ json: Any) -> DiscordHTTPResponse {
      DiscordHTTPResponse(
        host: "discord.com", status: .ok, headers: ["Content-Type": "application/json"],
        body: DemoWorld.data(json))
    }

    /// Newest first, like Discord. Every channel fits in one page, so a
    /// page `before` or `after` the loaded one is empty.
    private func messages(in channel: String, queries: [(String, String?)]) -> [Any] {
      let paging = queries.contains { ($0.0 == "before" || $0.0 == "after") && $0.1 != nil }
      if paging { return [] }
      return (DemoWorld.messages[channel] ?? []).reversed()
    }

    private func profile(for id: String) -> Any {
      let person = DemoWorld.people.first { $0.id == id } ?? DemoWorld.me
      return [
        "user": DemoWorld.user(person).merging(["bio": "Swift Studio regular."]) { a, _ in a },
        "user_profile": ["bio": "Swift Studio regular.", "accent_color": NSNull()],
        "badges": [],
        "mutual_guilds": [["id": DemoWorld.swiftStudioID, "nick": NSNull()]],
        "connected_accounts": [],
        "premium_type": 0,
      ]
    }
  }
#endif
