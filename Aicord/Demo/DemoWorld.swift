//
//  DemoWorld.swift
//  Aicord
//

#if DEBUG
  import Foundation

  /// The made-up account behind demo mode: people, servers, channels and
  /// messages, written as the JSON Discord would send, so they go through the
  /// same decoders as real data. Message times are relative to launch, so the
  /// chat always reads as today.
  enum DemoWorld {
    typealias JSON = [String: Any]

    /// Today at 9:41, the time screenshots show in the status bar.
    static let now =
      Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()

    // MARK: - Snowflakes

    private static let discordEpoch: Double = 1_420_070_400_000

    /// A snowflake for `date`. `n` tells apart several made in the same
    /// millisecond.
    static func snowflake(_ date: Date, _ n: Int = 0) -> String {
      let ms = UInt64(date.timeIntervalSince1970 * 1000 - discordEpoch)
      return String(ms << 22 | UInt64(n & 0xFFF))
    }

    /// Fixed IDs for things that exist before the demo starts: people,
    /// servers, channels and roles. All made in 2024, so they never clash
    /// with message IDs.
    static func fixedID(_ n: Int) -> String {
      snowflake(Date(timeIntervalSince1970: 1_704_067_200 + Double(n) * 3600))
    }

    private static let timestampFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: "UTC")
      formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxx"
      return formatter
    }()

    /// The way Discord writes times: `2026-11-02T08:47:05.715000+00:00`.
    static func timestamp(_ date: Date) -> String {
      timestampFormatter.string(from: date)
    }

    /// `minutes` before launch.
    static func ago(minutes: Double) -> Date {
      now.addingTimeInterval(-minutes * 60)
    }

    // MARK: - People

    struct Person {
      let id: String
      let username: String
      let name: String
      /// Read by `DemoImages` to draw the avatar.
      let avatar: String
      var bot = false
      var status = "online"
    }

    static let me = Person(
      id: fixedID(1), username: "maya.chen", name: "Maya", avatar: "demo-avatar-0")

    static let leo = Person(id: fixedID(2), username: "leopark", name: "Leo Park", avatar: "demo-avatar-1")
    static let ana = Person(id: fixedID(3), username: "anasouza", name: "Ana Souza", avatar: "demo-avatar-2")
    static let tom = Person(
      id: fixedID(4), username: "tbecker", name: "Tom Becker", avatar: "demo-avatar-3", status: "idle")
    static let priya = Person(id: fixedID(5), username: "priya.n", name: "Priya", avatar: "demo-avatar-4")
    static let jonas = Person(
      id: fixedID(6), username: "jonaslind", name: "Jonas Lind", avatar: "demo-avatar-5", status: "dnd")
    static let sofia = Person(id: fixedID(7), username: "sofiarossi", name: "Sofia Rossi", avatar: "demo-avatar-6")
    static let kenji = Person(id: fixedID(8), username: "kenji", name: "Kenji Mori", avatar: "demo-avatar-7")
    static let emma = Person(
      id: fixedID(9), username: "emmaclarke", name: "Emma Clarke", avatar: "demo-avatar-8", status: "offline")
    static let omar = Person(id: fixedID(10), username: "omarh", name: "Omar Haddad", avatar: "demo-avatar-9")
    static let lena = Person(
      id: fixedID(11), username: "lenanovak", name: "Lena Novak", avatar: "demo-avatar-10", status: "offline")
    static let bot = Person(
      id: fixedID(12), username: "Builder", name: "Builder", avatar: "demo-avatar-11", bot: true)

    static let people = [me, leo, ana, tom, priya, jonas, sofia, kenji, emma, omar, lena, bot]

    static func user(_ p: Person) -> JSON {
      var json: JSON = [
        "id": p.id,
        "username": p.username,
        "global_name": p.name,
        "discriminator": "0",
        "avatar": p.avatar,
        "public_flags": 0,
        "flags": 0,
      ]
      if p.bot { json["bot"] = true }
      return json
    }

    /// The account as READY and the account list see it.
    static var meUser: JSON {
      var json = user(me)
      json["email"] = "maya@example.com"
      json["verified"] = true
      json["mfa_enabled"] = true
      json["premium_type"] = 0
      json["locale"] = "en-US"
      json["bio"] = "Building things with Swift. Mostly SwiftUI, sometimes trails."
      return json
    }

    // MARK: - Servers

    struct Channel {
      let id: String
      let type: Int
      let name: String
      var parent: String? = nil
      var topic: String? = nil
      var position = 0
    }

    struct Server {
      let id: String
      let name: String
      let icon: String
      let owner: String
      let channels: [Channel]
      let roles: [JSON]
      let members: [(Person, [String])]
    }

    /// Everything, in a JSON permission string.
    static let allPermissions = "2251799813685247"
    /// What @everyone may do on the demo servers: react, view, send, embed,
    /// attach, read history, use external emoji, connect, speak, use voice
    /// activity and use application commands.
    static let memberPermissions = "2184563776"

    static let swiftStudioID = fixedID(100)
    enum SwiftStudio {
      static let information = fixedID(110)
      static let welcome = fixedID(111)
      static let announcements = fixedID(112)
      static let community = fixedID(120)
      static let general = fixedID(121)
      static let swiftui = fixedID(122)
      static let designCrit = fixedID(123)
      static let showcase = fixedID(124)
      static let help = fixedID(125)
      static let voice = fixedID(130)
      static let lounge = fixedID(131)
      static let pairing = fixedID(132)

      static let moderator = fixedID(140)
      static let mentor = fixedID(141)
      static let member = fixedID(142)
      static let botRole = fixedID(143)
    }

    static var swiftStudio: Server {
      typealias S = SwiftStudio
      return Server(
        id: swiftStudioID,
        name: "Swift Studio",
        icon: "demo-icon-0",
        owner: me.id,
        channels: [
          Channel(id: S.information, type: 4, name: "Information", position: 0),
          Channel(
            id: S.welcome, type: 0, name: "welcome", parent: S.information,
            topic: "Start here: rules and how the server works", position: 0),
          Channel(
            id: S.announcements, type: 5, name: "announcements", parent: S.information,
            topic: "Events, releases and news", position: 1),
          Channel(id: S.community, type: 4, name: "Community", position: 1),
          Channel(
            id: S.general, type: 0, name: "general", parent: S.community,
            topic: "Anything goes, within the rules", position: 0),
          Channel(
            id: S.swiftui, type: 0, name: "swiftui", parent: S.community,
            topic: "Views, layout, animation and the new design", position: 1),
          Channel(
            id: S.designCrit, type: 0, name: "design-crit", parent: S.community,
            topic: "Post a screen, get honest feedback", position: 2),
          Channel(
            id: S.showcase, type: 0, name: "showcase", parent: S.community,
            topic: "Things you made", position: 3),
          Channel(
            id: S.help, type: 0, name: "help", parent: S.community,
            topic: "Stuck? Ask here, with code", position: 4),
          Channel(id: S.voice, type: 4, name: "Voice", position: 2),
          Channel(id: S.lounge, type: 2, name: "Lounge", parent: S.voice, position: 0),
          Channel(id: S.pairing, type: 2, name: "Pair Programming", parent: S.voice, position: 1),
        ],
        roles: [
          role(id: swiftStudioID, name: "@everyone", color: 0, position: 0, permissions: memberPermissions),
          role(
            id: S.moderator, name: "Moderator", color: 0xE67E22, position: 4, hoist: true,
            permissions: "8"),
          role(id: S.mentor, name: "Mentor", color: 0x3498DB, position: 3, hoist: true),
          role(id: S.botRole, name: "Bots", color: 0x9B59B6, position: 2, hoist: true),
          role(id: S.member, name: "Member", color: 0x2ECC71, position: 1, hoist: true),
        ],
        members: [
          (me, [S.moderator]),
          (leo, [S.mentor]),
          (ana, [S.mentor]),
          (tom, [S.member]),
          (priya, [S.moderator]),
          (jonas, [S.member]),
          (sofia, [S.member]),
          (kenji, [S.member]),
          (emma, [S.member]),
          (omar, [S.member]),
          (lena, [S.member]),
          (bot, [S.botRole]),
        ]
      )
    }

    /// Smaller servers for the server list, each with one channel.
    static var otherServers: [Server] {
      let names = ["Trail Club", "Night Owls", "Book Nook", "Pixel Garden"]
      return names.enumerated().map { i, name in
        let id = fixedID(200 + i * 10)
        return Server(
          id: id,
          name: name,
          icon: "demo-icon-\(i + 1)",
          owner: leo.id,
          channels: [
            Channel(id: fixedID(201 + i * 10), type: 0, name: "general", topic: nil, position: 0)
          ],
          roles: [
            role(id: id, name: "@everyone", color: 0, position: 0, permissions: memberPermissions)
          ],
          members: [(me, []), (leo, []), (ana, []), (jonas, [])]
        )
      }
    }

    static var servers: [Server] { [swiftStudio] + otherServers }

    static func role(
      id: String, name: String, color: Int, position: Int, hoist: Bool = false,
      permissions: String = memberPermissions
    ) -> JSON {
      [
        "id": id,
        "name": name,
        "color": color,
        "hoist": hoist,
        "position": position,
        "permissions": permissions,
        "managed": false,
        "mentionable": true,
        "flags": 0,
      ]
    }

    static func channel(_ c: Channel, guild: String) -> JSON {
      var json: JSON = [
        "id": c.id,
        "type": c.type,
        "guild_id": guild,
        "name": c.name,
        "position": c.position,
        "permission_overwrites": [],
        "nsfw": false,
      ]
      if let parent = c.parent { json["parent_id"] = parent }
      if let topic = c.topic { json["topic"] = topic }
      if let last = lastMessageID[c.id] { json["last_message_id"] = last }
      if c.type == 2 {
        json["bitrate"] = 64000
        json["user_limit"] = 0
        json["rtc_region"] = NSNull()
      }
      return json
    }

    static func member(_ p: Person, roles: [String], joined: Date = Date(timeIntervalSince1970: 1_704_067_200))
      -> JSON
    {
      [
        "user": user(p),
        "roles": roles,
        "joined_at": timestamp(joined),
        "deaf": false,
        "mute": false,
        "flags": 0,
        "pending": false,
      ]
    }

    /// The server list puts the server joined last first, so Swift Studio
    /// gets the newest date.
    static func joinDate(of s: Server) -> Date {
      let index = servers.firstIndex { $0.id == s.id } ?? 0
      return Date(timeIntervalSince1970: 1_720_000_000 - Double(index) * 86_400 * 30)
    }

    static func guild(_ s: Server) -> JSON {
      [
        "id": s.id,
        "name": s.name,
        "icon": s.icon,
        "owner_id": s.owner,
        "afk_timeout": 300,
        "verification_level": 1,
        "default_message_notifications": 1,
        "explicit_content_filter": 2,
        "roles": s.roles,
        "emojis": [],
        "features": ["COMMUNITY", "NEWS"],
        "mfa_level": 0,
        "system_channel_flags": 0,
        "premium_tier": 1,
        "premium_subscription_count": 4,
        "preferred_locale": "en-US",
        "nsfw_level": 0,
        "stickers": [],
        "premium_progress_bar_enabled": false,
        "nsfw": false,
        "lazy": true,
        "large": false,
        "joined_at": timestamp(joinDate(of: s)),
        "member_count": s.members.count,
        "members": s.members.filter { $0.0.id == me.id }.map {
          member($0.0, roles: $0.1, joined: joinDate(of: s))
        },
        "channels": s.channels.map { channel($0, guild: s.id) },
        "threads": [],
        "voice_states": s.id == swiftStudioID ? loungeVoiceStates : [],
        "presences": [],
        "guild_scheduled_events": [],
        "stage_instances": [],
        "application_command_counts": [:],
        "version": 1,
      ]
    }

    /// Who sits in the Lounge voice channel.
    static var loungeVoiceStates: [JSON] {
      [leo, ana, kenji].map { p in
        [
          "user_id": p.id,
          "member": member(p, roles: [SwiftStudio.mentor]),
          "channel_id": SwiftStudio.lounge,
          "session_id": "demo-\(p.username)",
          "deaf": false,
          "mute": false,
          "self_deaf": false,
          "self_mute": p.id == kenji.id,
          "self_video": false,
          "suppress": false,
          "request_to_speak_timestamp": NSNull(),
        ]
      }
    }

    // MARK: - Direct messages

    static let dmLeo = fixedID(300)
    static let dmAna = fixedID(301)
    static let dmPriya = fixedID(302)
    static let dmOmar = fixedID(303)
    static let groupTrip = fixedID(304)

    static var privateChannels: [JSON] {
      func dm(_ id: String, _ p: Person) -> JSON {
        var json: JSON = [
          "id": id, "type": 1, "recipients": [user(p)], "flags": 0,
        ]
        if let last = lastMessageID[id] { json["last_message_id"] = last }
        return json
      }
      var group: JSON = [
        "id": groupTrip,
        "type": 3,
        "name": "Weekend trip",
        "recipients": [user(ana), user(jonas), user(sofia)],
        "owner_id": ana.id,
        "flags": 0,
      ]
      if let last = lastMessageID[groupTrip] { group["last_message_id"] = last }
      return [dm(dmLeo, leo), dm(dmAna, ana), dm(dmPriya, priya), dm(dmOmar, omar), group]
    }

    // MARK: - READY

    static var ready: JSON {
      [
        "v": 9,
        "user": meUser,
        "session_id": "demo-session",
        "resume_gateway_url": "wss://gateway.discord.gg",
        "sessions": [],
        "connected_accounts": [],
        "user_guild_settings": [],
        "read_state": readStates,
        "presences": people.filter { $0.id != me.id && $0.status != "offline" }.map(presence),
        "relationships": [leo, ana, tom, priya, jonas, sofia, kenji, omar].map { p in
          ["id": p.id, "type": 1, "user": user(p), "nickname": NSNull(), "user_ignored": false] as JSON
        },
        "private_channels": privateChannels,
        "guilds": servers.map(guild),
        "geo_ordered_rtc_regions": ["rotterdam", "madrid"],
      ]
    }

    static func presence(_ p: Person) -> JSON {
      var activities: [JSON] = []
      if p.id == kenji.id {
        activities = [["name": "Xcode", "type": 0, "created_at": Int(now.timeIntervalSince1970 * 1000)]]
      }
      return [
        "user": ["id": p.id],
        "status": p.status,
        "activities": activities,
        "client_status": ["desktop": p.status],
      ]
    }

    /// Unread channels and mentions: #swiftui is read, #general and two
    /// smaller servers have new messages, Leo's DM mentions you.
    static var readStates: [JSON] {
      var states: [JSON] = []
      for (channel, messages) in messages {
        guard let last = messages.last?["id"] as? String else { continue }
        let read: String
        var mentions = 0
        switch channel {
        case SwiftStudio.general, groupTrip:
          read = messages[max(0, messages.count - 4)]["id"] as! String
        case dmLeo:
          read = messages[max(0, messages.count - 2)]["id"] as! String
          mentions = 1
        default:
          read = last
        }
        states.append([
          "id": channel, "last_message_id": read, "mention_count": mentions, "flags": 0,
        ])
      }
      return states
    }

    // MARK: - Messages

    /// Messages per channel, oldest first.
    /// Built once and never changed.
    nonisolated(unsafe) static let messages: [String: [JSON]] = MessageScript.all()

    static var lastMessageID: [String: String] {
      messages.compactMapValues { $0.last?["id"] as? String }
    }

    static func message(
      channel: String, guild: String?, author: Person, at date: Date, n: Int = 0,
      content: String, extra: JSON = [:]
    ) -> JSON {
      var json: JSON = [
        "id": snowflake(date, n),
        "channel_id": channel,
        "author": user(author),
        "content": content,
        "timestamp": timestamp(date),
        "edited_timestamp": NSNull(),
        "tts": false,
        "mention_everyone": false,
        "mentions": [],
        "mention_roles": [],
        "attachments": [],
        "embeds": [],
        "pinned": false,
        "type": 0,
        "flags": 0,
      ]
      if let guild { json["guild_id"] = guild }
      for (key, value) in extra { json[key] = value }
      return json
    }

    // MARK: - Member list

    /// A member list SYNC for a server's channels: hoisted roles, online
    /// first, then offline.
    static func memberListSync(for server: Server, listID: String) -> JSON {
      let hoisted = server.roles
        .filter { $0["hoist"] as? Bool == true }
        .sorted { ($0["position"] as! Int) > ($1["position"] as! Int) }
        .map { $0["id"] as! String }
      var items: [JSON] = []
      var groups: [JSON] = []
      var online = 0
      func add(group id: String, _ people: [(Person, [String])]) {
        guard !people.isEmpty else { return }
        groups.append(["id": id, "count": people.count])
        items.append(["group": ["id": id, "count": people.count]])
        for (p, roles) in people {
          var m = member(p, roles: roles)
          m["presence"] = presence(p)
          items.append(["member": m])
        }
      }
      var placed: Set<String> = []
      for roleID in hoisted {
        let inRole = server.members.filter {
          $0.1.contains(roleID) && $0.0.status != "offline" && !placed.contains($0.0.id)
        }
        inRole.forEach { placed.insert($0.0.id) }
        online += inRole.count
        add(group: roleID, inRole)
      }
      let rest = server.members.filter { $0.0.status != "offline" && !placed.contains($0.0.id) }
      online += rest.count
      add(group: "online", rest)
      add(group: "offline", server.members.filter { $0.0.status == "offline" })
      return [
        "id": listID,
        "guild_id": server.id,
        "member_count": server.members.count,
        "online_count": online,
        "groups": groups,
        "ops": [["op": "SYNC", "range": [0, 99], "items": items]],
      ]
    }

    // MARK: - Frames

    static func frame(_ type: String, _ data: Any, sequence: Int = 1) -> Data {
      let json: JSON = ["op": 0, "t": type, "s": sequence, "d": data]
      return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    static func data(_ json: Any) -> Data {
      (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
  }
#endif
