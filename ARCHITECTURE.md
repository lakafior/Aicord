# Architecture

A map of the repository and the decisions that aren't obvious from the code.
What changed and when is in the [changelog](CHANGELOG.md).

## Layout

| Path | What it is |
| --- | --- |
| `Aicord/` | The app, one target for iOS and macOS. `App/` (entry point, app state, commands), `Baseplates/` (the window layouts: `SmallBaseplate` on iPhone, `LargeBaseplate` on iPad, `MacBaseplate` on the Mac), `Common/` (views shared by both platforms), `Stores/` (observable state fed by the gateway), `iOS/` and `macOS/` (platform-only views) |
| `AicordKit/` | The Discord library, a fork of [DiscordBM](https://github.com/DiscordBM/DiscordBM) trimmed to what a user client needs. Modules: `DiscordModels`, `DiscordHTTP`, `DiscordGateway`, `DiscordVoice`, `COpusShim`, and the umbrella `AicordKit` the app imports |
| `Textual/` | Markdown rendering, a modified [Textual](https://github.com/gonzalezreal/textual) |
| `AicordShared/` | Types compiled into both the app and the widget extension, without `AicordKit`: `AicordLink`, the App Group ID, the widget snapshot, Live Activity attributes and intents |
| `AicordWidgets/` | The unread widget and the voice call Live Activity |
| `AicordSafari/` | The Safari extension that sends `discord.gg` links to the app |
| `AicordMCP/` | `aicord-mcp`, the read-only MCP helper for the Mac (a standalone SwiftPM package) |
| `scripts/` | `altstore_source.py`, which builds the AltStore source from GitHub releases |
| `tools/testbot/` | A small bot for testing slash commands, buttons, menus and forms |

Mac-only behaviour sits behind `#if os(macOS)`. Shared code changed for the Mac keeps behaving the same on iOS.

## The library

- **Modules stay split.** The `Discord*` names describe the protocol, and separate modules keep incremental builds fast. `DiscordVoice` has to be its own module anyway, because it uses C++ interop for DaveKit.
- **Bot-only code is gone:** sharding, bot authentication and endpoints a user client never calls. `APIEndpoint.swift` is edited by hand.
- **`@Indirect`** (`DiscordModels/Types/Shared.swift`) boxes the large nested fields of messages, users and invites. A copy of a message is then one retain instead of a field-by-field copy, which cut megabytes of copying code from the app binary.
- **Lossy decoding where Discord adds types often.** Components V2 decode into a tree where an unknown or broken component becomes `.unknown` instead of failing the whole message. `Interaction.ComponentSwitch` keeps legacy action rows when every top-level component is one.

## Voice

| Layer | Where | Does |
| --- | --- | --- |
| Models | `DiscordModels/Types/VoiceGateway*.swift`, `RTP/` | Voice gateway v8 payloads, RTP, close codes with their recovery policy |
| Transport | `DiscordVoice/VoiceGatewayManager.swift`, `VoiceUDPConnection.swift` | WebSocket on `URLSessionWebSocketTask`, UDP on `NWConnection`, the state machine and timeouts |
| Encryption | `DiscordVoice/TransportCipher.swift` | `aead_aes256_gcm_rtpsize` and `aead_xchacha20_poly1305_rtpsize` on CryptoKit |
| DAVE | `DiscordVoice/DaveSession.swift` | End-to-end encryption through libdave's C API from DaveKit |
| Codec | `DiscordVoice/OpusCodec.swift`, `JitterBuffer.swift` | Opus, jitter buffer with packet loss concealment, mixing |
| Audio | `Aicord/Utilities/Audio/` | `AVAudioEngine` with voice processing, voice activity, push-to-talk, devices |
| Call logic | `Aicord/Stores/VoiceConnectionStore.swift` | Joining through gateway op 4, mute and deafen, ringing in DMs |
| UI | `Aicord/Common/Voice/` | The call panel, voice channel rows, settings |

## The chat

- **Older history** loads a page of 50 at a time once the user has scrolled within three screens of the top, at most once a second. SwiftUI doesn't adjust the offset when rows are inserted above, so `ChatView` moves by the height the page added. The comments in `ChatView.swift` and `ChannelStore.swift` explain why it's matched by size and not by timing.
- **Up to 1000 messages** stay loaded while reading history. New messages trim the oldest down to 200 only while the newest are on screen.
- **Rendering cost.** No `scrollTargetLayout()`, and the header and composer are separate views. Both used to re-render the whole chat as rows scrolled by or members loaded.
- **Member lists.** An `INVALIDATE` makes the channel ask for its ranges again, and lists are sent again after every READY. A guild subscription leaves `channels` out, because an empty one drops the member list a channel has just subscribed to.

## The system

- **One link format.** Widgets, Spotlight, Handoff, Shortcuts and notifications all open `aicord://channel/<server or @me>/<channel>[/<message>]` through `SystemIntegration`.
- **App Group:** `group.net.smigi.aicord` on iOS and `$(DEVELOPMENT_TEAM).net.smigi.aicord` on macOS, set once as `AICORD_APP_GROUP` and read from `Info.plist`.
- **Three App IDs** (the app, Safari and widgets) is the limit of a free account in AltStore. Don't add another extension without dropping one.
- **Nothing runs with the token in the background.** No push server, and App Intents bring the app to the foreground (`supportedModes = .foreground`). The widget only shows counts the app wrote while it was open.
- **Updates** are checked against `GET /repos/lakafior/Aicord/releases/latest` (`UpdateChecker.swift`), not Sparkle. The same check works on iOS, where AltStore installs the update, and it needs no signing keys.

## The MCP server (macOS)

`aicord-mcp` speaks MCP over stdio and forwards each call to the running app. A build phase compiles it into `Aicord.app/Contents/Helpers`. In the app, `MCPBridge.swift` listens on `127.0.0.1:47823` only, checks a key from Settings → Advanced and allows 30 calls a minute. It answers through the same filtered transcript as Intelligence, so blocked users, the word filter, spoilers and hidden media stay hidden. DMs stay out unless the user turns them on. The port and key live in the settings and not in a file, because macOS keeps other apps out of the app's container.
