<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/assets/icon-dark.png">
  <img src=".github/assets/icon-light.png" width="128" height="128" alt="Aicord icon">
</picture>

# Aicord

A native Discord client for iOS and macOS, written in pure Swift 6 and SwiftUI.

![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![iOS 26](https://img.shields.io/badge/iOS-26%2B-000000?logo=apple&logoColor=white)
![macOS 26](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)
![Dependencies](https://img.shields.io/badge/dependencies-4-EA6532)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

</div>

---

## Why a fork

Aicord is a fork of [Paicord](https://github.com/llsc12/Paicord) by [llsc12](https://github.com/llsc12). The upstream project doesn't accept AI-assisted pull requests, so the modernisation work lives here instead. Same app at heart, rebuilt on the newest Apple platforms with almost nothing but Apple's own frameworks.

## What changed

|                         | Paicord                         | Aicord                                   |
| ----------------------- | ------------------------------- | ---------------------------------------- |
| App size (macOS, arm64)  | 61.8 MB                        | **20.8 MB** (−66%)                       |
| Download (zipped)       | 24.0 MB                         | **9.2 MB** (−62%)                        |
| Swift packages          | 58 resolved (31 direct)         | **4**                                    |
| Language mode           | Swift 5                         | **Swift 6**, strict concurrency, no warnings |
| Minimum OS              | iOS 17 · macOS 14               | **iOS 26 · macOS 26**                    |
| Networking              | SwiftNIO, AsyncHTTPClient       | **URLSession**, `URLSessionWebSocketTask` |
| Code highlighting       | Prism.js in JavaScriptCore      | **Native Swift tokenizer**               |
| Design                  | Custom blur and mesh hacks      | **Liquid Glass**, `MeshGradient`          |

**Swapped for system APIs or removed:** SwiftUIX, Nuke, Sparkle, Lottie, SettingsKit, SwiftUIIntrospect, HCaptcha, KeychainAccess, CodeScanner, MijickCamera, MeshGradient, ColorCube, SwiftEmoji, FLEX, Loupe, Conditionals, SwiftPrettyPrint, UInt128, Yams, swift-crypto, multipart-kit and the whole SwiftNIO stack. What's left: swift-log, swift-protobuf, zstd and swift-syntax (build-time macros only).

The full history is in [ROADMAP.md](ROADMAP.md).

## New & fixed

- **New** · Liquid Glass app icon made in Icon Composer, with light, dark and tinted variants
- **New** · iOS draws the app with Liquid Glass: the compatibility flag that kept the old look is gone, the tab bar is the system glass one and lists scroll underneath it
- **New** · Settings is a tab on iPhone; the empty Notifications tab is gone
- **New** · Channel categories start expanded and have cleaner headers with a hairline between them
- **New** · Working status picker (online, idle, do not disturb, invisible) and a custom status editor with emoji and "clear after", saved to your account so other clients see it
- **New** · "Member since" on your profile, and Log Out next to account switching
- **New** · Settings → My Account shows your account details and accounts, and Keybinds lists the shortcuts
- **New** · One search for servers, channels, people and messages: pick a server, channel or person and the next results narrow to it
- **New** · Edit your profile in the app: display name, pronouns, about me and avatar, plus a nickname and pronouns per server
- **New** · iPhone tabs are Home, Messages, Search and Settings; Messages holds direct messages, group chats, mentions and friends, and your status and activity sit behind a profile card at the top of Settings
- **New** · Custom rich presence ("Playing …", "Listening to …") with images, timers, party size and buttons, a live preview, and a "Share my activity" switch; your Discord application ID lives in Settings → My Account and is checked before saving
- **New** · Settings → Content & Social: sensitive and graphic media (show, blur or block), keyword filters, DM spam filter, message requests and who can send you friend requests, saved to your Discord account
- **New** · Media Discord flags as sensitive is blurred or blocked in chats according to those settings, and an optional word filter hides matching messages behind a tap, using the community LDNOOBW lists (CC BY 4.0) plus your own words
- **New** · About Aicord in Settings with version, licence and a link to this repository
- **New** · Logging goes through `os.Logger` instead of capturing stdout into memory
- **New** · PaicordLib understands newer message payloads: voice message attachments, forwards, message requests and forum tags on channels (from [@tylertms](https://github.com/tylertms)' upstream PRs)
- **Fixed** · The macOS app no longer crashes a few seconds after loading: the chat and the member list stopped fighting over column widths, and the window now opens at a sensible size
- **Fixed** · The member list no longer scrolls itself out of view when it opens
- **Fixed** · Channel names in the title bar show in full instead of being cut off inside a glass pill
- **Fixed** · Opening a channel or scrolling to the bottom now marks it as read
- **Fixed** · Forum and media channels show an icon instead of a raw type name, and the macOS Settings window no longer cuts off section names
- **Fixed** · Requests that Discord answers with a captcha or a 2FA prompt go through once you solve it, instead of failing with 403
- **Fixed** · Changing one account setting no longer resets the others in the same group (for example "Share my activity" clearing your custom status)
- **Fixed** · Changing account settings actually reaches Discord (the request went out empty), and settings changed on another device are merged in
- **Fixed** · Incoming messages keep their slash command info, and a message reference without a type no longer breaks decoding
- **Fixed** · A failed attachment upload marks the message as failed instead of silently sending it without the file
- **Removed** · Third-party sponsor badges and the telemetry requests behind them
- **Removed** · Donate buttons, the sponsor pop-up and the update check, all of which pointed at the upstream app

## Building

Requires **Xcode 26** on macOS 26.

```bash
git clone https://github.com/lakafior/Aicord.git
open Aicord/Paicord.xcworkspace
```

Pick the **Paicord** scheme, choose a Mac or an iOS 26 device or simulator, and run. The macOS app is built for Apple silicon only. There are no prebuilt releases of Aicord yet.

## A word of caution

Like every third-party client, using Aicord breaks Discord's Terms of Service. It identifies itself as close to the official client as it can, but the risk of an account ban never goes away. Use it at your own risk.

## Credits

- [Paicord](https://github.com/llsc12/Paicord) by llsc12, the project this fork is built on
- [DiscordBM](https://github.com/DiscordBM/DiscordBM) and [Textual](https://github.com/gonzalezreal/textual), modified versions of which live in `PaicordLib` and `Textual`
- [Discord Userdoccers](https://docs.discord.food) for the unofficial API documentation

Licensed under [GPL-3.0](LICENSE).
