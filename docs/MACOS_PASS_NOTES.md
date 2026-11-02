# macOS pass

A pass on the Mac version only. iOS keeps its behaviour: Mac changes sit behind
`#if os(macOS)`, and shared code changed here behaves the same on iOS.

## Stage 1: Delete Server on the Mac

**Cause.** The sheet itself is shared with iOS and was never hidden by a `#if`.
`ServerSettingsSheet` showed Server Management and Delete Server only when the
server already had a `GuildStore` (`gw.existingGuildStore(for:)`), and a store
exists only once the server has been opened in this session. On the Mac the
usual way in is the server icon's menu (right click → Server Settings…), often
for a server that isn't open, so both sections were missing. On iOS settings
are usually opened from the server that is already showing.

**Fix.**
- The sheet makes the store when it opens (`getGuildStore`), so the
  permission checks behind the management links work.
- Ownership comes from the guild itself (`owner_id`), not from the store.
- On the Mac a destructive button in a grouped `Form` is drawn in the plain
  button colour. Delete Server is now red there.

**Checked on the Mac** (own build, server "Aicord Delete Test", not opened
before): the settings show Server Management and a red Delete Server. On
"Aicord Test" the confirmation (type the name) opens and was cancelled.
Nothing was deleted.

## Stage 2: the member list

### Why it sometimes stayed empty

Three causes, all found in the code, one also caught in a log:

1. **INVALIDATE with no new request.** Out of four launches of the old build,
   one got a `SYNC` and then an `INVALIDATE` for the same range two seconds
   later. Nothing asked for the range again (the view only asks when the
   ranges it wants change), so the list showed "Online — 1" with no rows.
   Opening a server sent a guild subscription with `channels: [:]`, which drops
   the member list subscription a channel has just sent. Discord answers that
   with INVALIDATE.
   - The guild subscription now leaves `channels` out.
   - An INVALIDATE now makes the channel ask for its ranges again, at most
     every 3 s.
2. **Lost after a reconnect.** A new session (READY) resubscribed the servers
   with `channels: [:]` and never sent the member lists again. The open list
   stayed as it was at the disconnect. After READY each server with member
   lists now sends them again.
3. **The wrong store, or no store.** On the Mac the server and channel come
   from two `.task`s that can run in either order. A channel store could be
   made with the previous server's store or with none. With no server, the
   store has no member list and the inspector stayed empty for good, because
   the store is cached.
   - The channel task now takes the server from the selection.
   - `getChannelStore` makes the store again if it was made without its server.
   - `attachMemberListIfNeeded()` runs again from the member list view.

   Also, of the channels that share a list (same permissions), only the first
   store to make it applied updates. If that store went away, the list froze.
   Now the store that last asked for the list owns it (checked by identity).

### Scrolling with many members

Causes found in the code:
- **Each row that scrolled in refreshed the whole list.** `onAppear` stored
  the row index in `@State`, and `body` read it. Now only the block of 100
  rows is kept, and only when it changes.
- **Every update refreshed the whole list.** The accumulator's `items`
  dictionary was observed as a whole, and `row(at:)` was read in the list's
  `body`. The groups and counts were also set again on every update, even
  unchanged.
  - Rows are now read in each cell.
  - `items` is no longer observed. A `layoutVersion` changes only when rows
    are added, removed or moved.
  - A SYNC keeps the boxes of rows that are already there.
  - Groups and counts are set only when they change.
- **Rows refreshed on other people's presence.** `presence(_:)` and
  `member(_:)` read the whole dictionary, so a presence or member loading for
  anyone refreshed every row (and every view that looks a person up).
  - Both stores now give each person looked up a slot of their own.
  - `memberCount` and `loadedMembers` follow a version that changes only when
    members are added or removed.
  - The API is the same, so iOS views get the same narrower refreshes.
- **Row height.** On the Mac every row, loaded or not, has a fixed height of
  32 pt.

Measured on the Mac with 600 fake members put straight into the list. This is a
debug-only test, not committed, and nothing was sent. Updates were coming in at
the same time: 4 times a second one member's nickname changed, and a presence
arrived for someone not in the list.

| `body` calls, per 2 s | before | after |
| --- | --- | --- |
| idle, 8 updates: list | 8 | 0 |
| idle, 8 updates: member rows | 4800 (all 600, each update) | 8 |
| scrolling about 140 rows: list | 9–12 | 1 |
| scrolling: member rows | about 3000–4800 | about 30 |

The "before" build was the Stage 1 commit with the same counters and fake list
(a separate worktree, removed afterwards). Not measured: a real server with
thousands of members. The only servers I was allowed to read have one to
three members.

## Stage 3 plan: a native Mac look

The Mac already has its own window layout (`MacBaseplate`): the system sidebar,
an inspector for members, a title and subtitle. What still reads as an iPhone
port, from the screenshots of the old build:

1. **Toolbar.** The channel name shows twice: the `# general ⌄` menu in the
   toolbar and the window title. The server name is the subtitle. Channel
   actions (pins, threads, media) sit behind a `…` menu, and search opens a
   sheet.
   - Plan: title `#channel`, subtitle the topic (or the server when there's
     no topic).
   - Plan: the Intelligence menu becomes a toolbar item with a symbol, and
     pins and threads become toolbar buttons.
   - Plan: `.searchable` in the toolbar, which opens the search with what was
     typed.
2. **Server rail.** It is 65 pt wide with 48 pt icons, Discord's size. Plan: a
   narrower column, about 52 pt, with smaller icons and tighter spacing.
3. **Composer.** An iPhone-style pill. Plan: a Messages-style field, a
   rounded rectangle with a thin border and 13 pt text, with the buttons
   beside it and no capsule background.
4. **Chat density.** Plan: tighter vertical spacing between message groups on
   the Mac, and hover states on rows, which are already there and only get
   checked.
5. **Inspector.** Plan: the toggle moves to ⌥⌘I (the standard inspector
   shortcut), keeping the toolbar button.
6. **Menu bar.**
   - Plan: Previous and Next Channel (⌥↑ / ⌥↓), Next Unread Channel (⌥⇧↓),
     servers ⌘1…⌘9, and Server Settings… for the open server.
   - Plan: Open Channel in New Window stays (⇧⌘O).
7. **Sheets.** Plan: on the Mac a sheet's `navigationTitle` took over the
   window title while it was open; that is fixed where it shows. The Settings
   scene already exists (⌘,) and is left as is.

The order is by impact: toolbar and title, rail, composer, density, then the
menus and details.
