//
//  DemoMessages.swift
//  Aicord
//

#if DEBUG
  import Foundation

  /// What people say in demo mode, per channel, oldest first.
  enum MessageScript {
    typealias JSON = DemoWorld.JSON
    typealias W = DemoWorld
    typealias S = DemoWorld.SwiftStudio

    static func all() -> [String: [JSON]] {
      [
        S.swiftui: swiftui(),
        S.general: general(),
        S.showcase: showcase(),
        S.announcements: announcements(),
        S.welcome: welcome(),
        S.designCrit: designCrit(),
        W.dmLeo: dmLeo(),
        W.dmAna: dmAna(),
        W.dmPriya: dmPriya(),
        W.dmOmar: dmOmar(),
        W.groupTrip: groupTrip(),
      ].merging(otherServers()) { a, _ in a }
    }

    // MARK: - Helpers

    /// Builds one channel's messages in order, each `gap` minutes after the
    /// previous one, ending `endingAgo` minutes before launch.
    struct Thread {
      let channel: String
      let guild: String?
      var items: [(W.Person, Double, String, JSON)] = []

      mutating func say(_ who: W.Person, after gap: Double = 1, _ text: String, _ extra: JSON = [:]) {
        items.append((who, gap, text, extra))
      }

      func build(endingAgo: Double) -> [JSON] {
        let total = items.reduce(0) { $0 + $1.1 }
        var minute = endingAgo + total
        var built: [JSON] = []
        for (i, item) in items.enumerated() {
          minute -= item.1
          var extra = item.3
          if let replyIndex = extra.removeValue(forKey: "_replyTo") as? Int {
            let parent = built[replyIndex]
            extra["type"] = 19
            extra["message_reference"] = [
              "type": 0, "message_id": parent["id"]!, "channel_id": channel,
            ].merging(guild.map { ["guild_id": $0] } ?? [:]) { a, _ in a }
            extra["referenced_message"] = parent
          }
          built.append(
            W.message(
              channel: channel, guild: guild, author: item.0, at: W.ago(minutes: minute), n: i,
              content: item.2, extra: extra))
        }
        return built
      }
    }

    static func reactions(_ list: [(String, Int, Bool)]) -> JSON {
      [
        "reactions": list.map { emoji, count, me in
          [
            "emoji": ["id": NSNull(), "name": emoji],
            "count": count,
            "count_details": ["burst": 0, "normal": count],
            "me": me,
            "me_burst": false,
            "burst_colors": [],
          ] as JSON
        }
      ]
    }

    static func mentioning(_ people: W.Person...) -> JSON {
      ["mentions": people.map(W.user)]
    }

    static func image(_ name: String, width: Int, height: Int, n: Int = 0) -> JSON {
      let id = W.snowflake(W.now, 900 + n)
      return [
        "id": id,
        "filename": "\(name).png",
        "size": 482_113,
        "url": "https://cdn.discordapp.com/attachments/0/\(id)/demo-art-\(name).png",
        "proxy_url": "https://media.discordapp.net/attachments/0/\(id)/demo-art-\(name).png",
        "width": width,
        "height": height,
        "content_type": "image/png",
      ]
    }

    static func replying(to index: Int) -> JSON { ["_replyTo": index] }

    static func merge(_ parts: JSON...) -> JSON {
      parts.reduce(into: JSON()) { $0.merge($1) { a, _ in a } }
    }

    // MARK: - Swift Studio

    static func swiftui() -> [JSON] {
      var t = Thread(channel: S.swiftui, guild: W.swiftStudioID)
      t.say(W.leo, "Has anyone moved a sidebar to the new glass look yet? Mine looks great until the list scrolls under the toolbar 😅")
      t.say(W.ana, after: 2, "Yes! Drop your own background on the `List` and let the system draw it. The glass needs to see the content behind it.")
      t.say(W.ana, after: 0.3, "Something like this:")
      t.say(
        W.ana, after: 0.2,
        """
        ```swift
        List(selection: $selection) {
          ForEach(channels) { channel in
            Label(channel.name, systemImage: "number")
          }
        }
        .listStyle(.sidebar)
        .scrollEdgeEffectStyle(.soft, for: .top)
        ```
        """, reactions([("🙌", 4, false), ("🔥", 2, true)]))
      t.say(W.leo, after: 3, "Oh, that edge effect is the bit I was missing. Thanks!", replying(to: 3))
      t.say(W.kenji, after: 4, "Related: is `.glassEffect()` fine on every row, or does it get slow in long lists?")
      t.say(W.priya, after: 2, "I'd keep it on containers, not rows. Group the rows and give the group one glass shape, it composites much better.")
      t.say(W.priya, after: 0.4, "There's a **GlassEffectContainer** for exactly that, it also morphs shapes between states ✨")
      t.say(
        W.tom, after: 6, "<@\(W.me.id)> you did the server rail in the Mac app with that, right? How did you handle the hover state?",
        mentioning(W.me))
      t.say(
        W.me, after: 2,
        "Yep. The rail is one container, and each icon only changes its tint on hover. Moving the glass itself on hover felt jumpy.",
        replying(to: 8))
      t.say(W.me, after: 0.5, "Happy to share the code later in <#\(S.showcase)>", reactions([("👀", 3, false)]))
      t.say(W.sofia, after: 3, "Same question for iPad: do you keep the tab bar or switch to the sidebar adaptable style?")
      t.say(W.ana, after: 1, "`.tabViewStyle(.sidebarAdaptable)` and let people choose. Some love the tab bar on iPad, some don't.")
      t.say(W.leo, after: 5, "Got the sidebar working, it looks so much better now 🎉", reactions([("🎉", 6, true), ("❤️", 2, false)]))
      return t.build(endingAgo: 12)
    }

    static func general() -> [JSON] {
      var t = Thread(channel: S.general, guild: W.swiftStudioID)
      t.say(W.jonas, "Morning everyone ☕")
      t.say(W.sofia, after: 1, "Morning! Who's coming to the meetup on Thursday?")
      t.say(W.omar, after: 2, "Me, and I'm bringing the demo I promised last time")
      t.say(W.kenji, after: 1, "Count me in. Is it the same place as last month?")
      t.say(W.sofia, after: 1, "Same café, 6 pm, upstairs room", replying(to: 3))
      t.say(W.leo, after: 8, "Small win: my app finally passed review on the first try 🥳", reactions([("🥳", 9, true), ("🚀", 4, false)]))
      t.say(W.tom, after: 2, "Congrats! What was different this time?")
      t.say(W.leo, after: 1, "Wrote the review notes like a test plan. Step by step, with a demo account ready.")
      t.say(W.priya, after: 3, "Stealing that idea")
      t.say(W.jonas, after: 4, "Anyone tried the new Instruments template for SwiftUI updates? It found three views re-rendering on every scroll in my app")
      t.say(W.kenji, after: 2, "Yes, it's great. It showed me a whole screen redrawing because of one observable property.")
      return t.build(endingAgo: 3)
    }

    static func showcase() -> [JSON] {
      var t = Thread(channel: S.showcase, guild: W.swiftStudioID)
      t.say(
        W.sofia, "Weekend project: a little weather app with glass cards. Feedback welcome!",
        merge(["attachments": [image("weather", width: 1290, height: 2796)]], reactions([("😍", 7, true), ("🔥", 3, false)])))
      t.say(W.ana, after: 4, "The cards look lovely. Maybe a bit more contrast on the small labels?")
      t.say(W.sofia, after: 2, "Good call, I'll bump them to secondary instead of tertiary", replying(to: 1))
      t.say(
        W.omar, after: 30, "Finished the icon set for my habit tracker",
        merge(
          ["attachments": [image("icons-a", width: 1600, height: 1600, n: 1), image("icons-b", width: 1600, height: 1600, n: 2)]],
          reactions([("👏", 5, false)])))
      t.say(
        W.me, after: 20, "Here's the Mac server rail I mentioned in <#\(S.swiftui)>",
        merge(["attachments": [image("rail", width: 2400, height: 1500, n: 3)]], reactions([("🙌", 6, false), ("💯", 2, false)])))
      return t.build(endingAgo: 40)
    }

    static func announcements() -> [JSON] {
      var t = Thread(channel: S.announcements, guild: W.swiftStudioID)
      t.say(
        W.priya,
        "**Meetup this Thursday** 📍 Same café, 6 pm. Lightning talks are open, reply here or DM me to grab a slot.",
        reactions([("✅", 14, true)]))
      t.say(
        W.bot, after: 60,
        "New release notes are out.",
        [
          "embeds": [
            [
              "type": "rich",
              "title": "What's new in Swift",
              "description": "Faster builds, better diagnostics and a round-up of the proposals that landed this month.",
              "url": "https://www.swift.org/blog/",
              "color": 0xF05138,
              "footer": ["text": "swift.org"],
            ] as JSON
          ]
        ])
      return t.build(endingAgo: 120)
    }

    static func welcome() -> [JSON] {
      var t = Thread(channel: S.welcome, guild: W.swiftStudioID)
      t.say(
        W.me,
        """
        # Welcome to Swift Studio 👋
        A place to learn, share and build with Swift.

        **Rules**
        1. Be kind. Critique the work, not the person.
        2. Share code as text, not screenshots.
        3. Keep job posts in <#\(S.general)> on Fridays.
        """)
      return t.build(endingAgo: 60 * 24 * 30)
    }

    static func designCrit() -> [JSON] {
      var t = Thread(channel: S.designCrit, guild: W.swiftStudioID)
      t.say(W.emma, "Is a floating compose button still a thing with the new toolbar, or should it live in the bottom bar?")
      t.say(W.ana, after: 5, "Bottom toolbar. It sits on glass now, so it doesn't fight the content.")
      return t.build(endingAgo: 60 * 5)
    }

    static func otherServers() -> [String: [JSON]] {
      var result: [String: [JSON]] = [:]
      let lines: [[(W.Person, String)]] = [
        [(W.jonas, "Ridge loop on Saturday, 14 km. Who's in?"), (W.ana, "Me! Leaving at 8?")],
        [(W.kenji, "Co-op tonight at 9?"), (W.leo, "Yes, I'll bring snacks 🍿")],
        [(W.ana, "Finished the book. That ending!"), (W.leo, "No spoilers please 🙈")],
        [(W.leo, "New palette for the pixel challenge is up")],
      ]
      for (i, server) in W.otherServers.enumerated() {
        let channel = server.channels[0].id
        var t = Thread(channel: channel, guild: server.id)
        for (who, text) in lines[i] { t.say(who, after: 3, text) }
        result[channel] = t.build(endingAgo: Double(30 + i * 45))
      }
      return result
    }

    // MARK: - Direct messages

    static func dmLeo() -> [JSON] {
      var t = Thread(channel: W.dmLeo, guild: nil)
      t.say(W.leo, "Hey! Are you still up for pairing on the sync engine tomorrow?")
      t.say(W.me, after: 4, "Definitely. 10 am in the Pair Programming channel?")
      t.say(W.leo, after: 1, "Perfect 👍")
      t.say(W.leo, after: 120, "I pushed the branch, conflicts are mostly in the store")
      t.say(W.me, after: 10, "Looking now")
      t.say(W.leo, after: 2, "<@\(W.me.id)> also, can you review my talk slides before Thursday?", mentioning(W.me))
      return t.build(endingAgo: 6)
    }

    static func dmAna() -> [JSON] {
      var t = Thread(channel: W.dmAna, guild: nil)
      t.say(W.ana, "Thanks for the code review earlier, super helpful")
      t.say(W.me, after: 3, "Anytime! The new layout reads much better")
      return t.build(endingAgo: 90)
    }

    static func dmPriya() -> [JSON] {
      var t = Thread(channel: W.dmPriya, guild: nil)
      t.say(W.priya, "Can you pin the meetup post in #announcements?")
      t.say(W.me, after: 2, "Done ✅")
      return t.build(endingAgo: 150)
    }

    static func dmOmar() -> [JSON] {
      var t = Thread(channel: W.dmOmar, guild: nil)
      t.say(W.omar, "Do you have a link to that talk about animations?")
      t.say(W.me, after: 5, "Sending it tonight")
      return t.build(endingAgo: 60 * 26)
    }

    static func groupTrip() -> [JSON] {
      var t = Thread(channel: W.groupTrip, guild: nil)
      t.say(W.ana, "Cabin is booked for the 14th! 🏔️")
      t.say(W.jonas, after: 2, "Amazing. I'll handle the car")
      t.say(W.sofia, after: 3, "I can bring the board games")
      t.say(W.ana, after: 5, "Maya, are you driving with Jonas?")
      t.say(W.jonas, after: 1, "There's room for two more")
      return t.build(endingAgo: 25)
    }
  }
#endif
