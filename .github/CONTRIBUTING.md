# Contributing

Aicord welcomes contributions, including ones written with AI tools. That is
the reason this fork exists: upstream [Paicord](https://github.com/llsc12/Paicord)
does not accept LLM-assisted work, so it lands here instead.

Before your pull request can be merged, please follow these guidelines:

1. AI-assisted code, assets, commit messages and pull request text are
   allowed. You are still responsible for what you submit: read it, build it,
   run it, and be ready to explain it. Untested or unreviewed output will be
   sent back.
2. Source code must be formatted and indented correctly. Use Swift Format for
   this (`ctrl + shift + R` in Xcode, or `swift format` on the command line).
3. Pull requests should come from a branch named after what they implement,
   for instance `feat/new-feature`, and stay focused on one part of the
   project. If the work is naturally large in scope, keep the commits
   well-named for review.
4. Include screenshots when the change is visible, for instance a UI
   redesign. Document `AicordKit` changes thoroughly.
5. Split unrelated contributions into separate pull requests, one branch per
   feature. That makes them easier to review and quicker to merge.
6. Bigger user-visible changes should also get a line in
   [CHANGELOG.md](../CHANGELOG.md), in the group it belongs to.

[ARCHITECTURE.md](../ARCHITECTURE.md) maps the repository and explains the
decisions that aren't obvious from the code.

## Testing voice

Voice needs a second person on the official Discord client, and headphones on
both sides (echo makes the result hard to judge). On the Mac, the log shows
every step:

```bash
/path/to/Aicord.app/Contents/MacOS/Aicord 2>&1 | grep -E "VoiceGateway|libdave|Voice"
```

1. **Server channel.** The other person joins a voice channel first, then you
   do. The log should go through `Session description received (dave=1)`,
   `DAVE key package sent`, `DAVE welcome received` (or `proposals`),
   `DAVE transition executed` and `Voice media ready`, and the call bar shows
   a lock. Talk both ways, mute (⌘⇧M) and deafen (⌘⇧D), and check the
   speaking rings and the icons the other person sees.
2. **Joining and leaving.** The other person leaves and comes back. A new DAVE
   transition runs and audio returns without you reconnecting. Then add a
   third person.
3. **Push-to-talk.** Settings → Voice & Video → Input Mode. Audio goes out only
   while the key (Mac) or the button in the call panel (iPhone) is held.
4. **DMs.** Call from a DM header, then from a group DM. The official client
   should ring.
5. **Network loss.** Turn Wi-Fi off for about 5 seconds during a call. The log
   should show `Voice socket closed`, `resuming` and `Voice session resumed`,
   and audio returns. A longer outage ends the call with a message.
6. **Devices.** Change input and output in Settings, leave and join again.

When something fails, the lines that matter are `DAVE …`,
`Voice deadline passed` and `Voice connection ending`.

## Releasing

Pushing a `v*` tag runs `.github/workflows/release.yml`:

1. builds an unsigned Release `.ipa`,
2. creates a GitHub release with the newest section of `CHANGELOG.md` as its
   notes,
3. rebuilds the AltStore source (`scripts/altstore_source.py`) from all
   releases and deploys it to GitHub Pages at
   `https://lakafior.github.io/Aicord/altstore.json`.

Before the first tag, set Settings → Pages → Source to **GitHub Actions**.
Running the workflow by hand builds `0.0.0-<sha>` without publishing.

`.github/workflows/release_macos.yml` signs and notarizes the Mac app. It does
nothing until these secrets exist:

| Secret | Where from |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | A "Developer ID Application" certificate with its key, exported as .p12 and base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | The password set on export |
| `MACOS_TEAM_ID` | developer.apple.com → Membership |
| `NOTARY_KEY_P8` | App Store Connect → Users and Access → Integrations → Keys, base64-encoded |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | The same page |

Check on the first signed run that the embedded Safari extension gets signed
with Developer ID and the hardened runtime too. After an AltStore install,
check that the widget still shows counts: AltStore rewrites App Group IDs, and
the ID the app reads from `Info.plist` may no longer match.
