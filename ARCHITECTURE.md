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
| Video (receive) | `DiscordVoice/VideoDepacketizer.swift`, `VideoFrame.swift` | RTP back into H.264 and H.265 frames, NACK and RTX, DAVE on the whole frame, sample buffers for `AVSampleBufferDisplayLayer` |
| Video (send) | `DiscordVoice/VideoEncoder.swift`, `Aicord/Common/Voice/VideoCapture.swift` | Camera and (Mac) screen capture, H.264 with VideoToolbox, RTP packets; announced with our own Video payload |
| Audio | `Aicord/Utilities/Audio/` | `AVAudioEngine` with voice processing, voice activity, push-to-talk, devices |
| Call logic | `Aicord/Stores/VoiceConnectionStore.swift` | Joining through gateway op 4, mute and deafen, ringing in DMs |
| UI | `Aicord/Common/Voice/` | The call panel, voice channel rows, settings |

- **Video is asked for, not sent by default.** The voice server forwards a camera only while `setVideoWanted` names its user (Media Sink Wants), and `VideoPanel` names only what is on screen. Only H.265 and H.264 are offered, receive-only, so senders fall back to them; AV1 is left out until it can be tested against a real sender.
- **We send H.264 only**, one layer, and nothing while the voice server says nobody is watching. Encoded frames reach the connection through one `AsyncStream` per source, so they go out in the order they were encoded. Screen sharing is Mac-only: on iOS it would need a Broadcast extension, a fourth App ID.
- **A Go Live is one more `VoiceGatewayManager`** (`isStream`) next to the call's, one per watched stream: its own socket, UDP flow, SSRCs and DAVE group, the call's session ID, and no media sent. The call's connection has to stay up.
- **Frames are rebuilt before they are decrypted.** DAVE encrypts a whole encoded frame, so `VideoDepacketizer` restores the sender's Annex B layout (4-byte start codes, as libdave writes them) and only then hands it to the decryptor. The display layer decodes; there is no `VTDecompressionSession` of our own.

## The chat

- **The list on iOS** is a `UICollectionView` (`MessageList.swift`) whose cells host the SwiftUI message rows; the Mac keeps a `LazyVStack`. A lazy stack built and measured every row from scratch as it appeared and laid a whole screen of new rows out in one frame when a page of history came in. The collection view is upside down (flipped, each cell flipped back) with the newest message first: it opens and stays at the bottom by itself, and older history is added at the far end, where wrong height estimates for unseen rows can't move what's on screen. Changes on the newer side of the screen are put right with an anchor row. The cells are separate SwiftUI hierarchies, so they get the chat's environment as a copy (`RowEnvironment`).
- **Older history** loads a page of 100 at a time once the user has scrolled within three screens of the top, at most every 0.3 s, and goes into the store as one change. On the Mac SwiftUI doesn't adjust the offset when rows are inserted above, so `ChatView` moves by the height the page added. The comments in `ChatView.swift` and `ChannelStore.swift` explain why it's matched by size and not by timing.
- **Catching up.** `ChannelStore.catchUp()` fetches what came after the newest loaded message when the chat appears, the app becomes active or the gateway starts a new session.
- **Up to 1000 messages** stay loaded while reading history. New messages trim the oldest down to 200 only while the newest are on screen.
- **Rendering cost.** No `scrollTargetLayout()`, and the header and composer are separate views. Both used to re-render the whole chat as rows scrolled by or members loaded. Regex literals in the markdown parser are static (a literal is compiled each time it is evaluated), parsed markdown is cached and there from a row's first layout, and JSON decoding, image and GIF frame decoding, the offline copy and Spotlight indexing run off the main thread.
- **Member lists.** An `INVALIDATE` makes the channel ask for its ranges again, and lists are sent again after every READY. A guild subscription leaves `channels` out, because an empty one drops the member list a channel has just subscribed to.

## The system

- **One link format.** Widgets, Spotlight, Handoff, Shortcuts and notifications all open `aicord://channel/<server or @me>/<channel>[/<message>]` through `SystemIntegration`.
- **App Group:** `group.net.smigi.aicord` on iOS and `$(DEVELOPMENT_TEAM).net.smigi.aicord` on macOS, set once as `AICORD_APP_GROUP` and read from `Info.plist`.
- **Three App IDs** (the app, Safari and widgets) is the limit of a free account in AltStore. Don't add another extension without dropping one.
- **Nothing runs with the token in the background.** No push server, and App Intents bring the app to the foreground (`supportedModes = .foreground`). The widget only shows counts the app wrote while it was open.
- **Updates** are checked against `GET /repos/lakafior/Aicord/releases/latest` (`UpdateChecker.swift`), not Sparkle. The same check works on iOS, where AltStore installs the update, and it needs no signing keys.

## The Mac's windows

- **Settings** is the system `Settings` scene with toolbar tabs (`SettingsView.MacTab`); related categories share a tab. A page inside a tab is a `SettingsPageLink`: a push on iOS, a sheet on the Mac, because a pushed page puts a back button among the tabs and shifts them.
- **Server settings** are a `WindowGroup` keyed by the server (`ServerSettingsWindow`), with app state of their own, so sheets opened there show there.
- **Popovers hold no toolbar.** A toolbar inside a popover lands in the window's toolbar, so `PinnedMessagesSheet` and `ThreadBrowserSheet` have their Done button on iOS only. The reaction picker's popover is anchored by `ReactionPickerAnchor`, which sits behind every message that has the menu.
- **`keepsWindowTitle`** (`MacBaseplate.swift`) sets the window's title back when presented content changes it: on the Mac a `navigationTitle` inside a sheet or a popover replaces the title of the window it is presented from.
- **The chat's background** is `Theme.chatBackground`: the window's own with the built-in themes on the Mac, the theme's everywhere else.

## The MCP server (macOS)

`aicord-mcp` speaks MCP over stdio and forwards each call to the running app. A build phase compiles it into `Aicord.app/Contents/Helpers`. In the app, `MCPBridge.swift` listens on `127.0.0.1:47823` only, checks a key from Settings → Advanced and allows 30 calls a minute. It answers through the same filtered transcript as Intelligence, so blocked users, the word filter, spoilers and hidden media stay hidden. DMs stay out unless the user turns them on. The port and key live in the settings and not in a file, because macOS keeps other apps out of the app's container. A server's readable channels come from its `GuildStore` (made if the server was never opened, as opening it would), because without one there are no permissions to check and every channel would pass. Discord's search has no regular expressions, so `regex` filters the fetched pages in the app.
