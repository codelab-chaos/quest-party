# Changelog

Features and fixes shipped in each release. Copy a version's section into
CurseForge's changelog field using Markdown formatting.

## Unreleased (0.3.6)

### Added

- The Quest tab has a short row at the top of its list with a small gear that cycles the quest cards' layout (Segmented, Grid, Ring, List), the current one named beside it.

### Changed

- Plainer messaging: you say hello and answer newcomers straight away (no random waits), messages no longer carry ordering numbers, the "tell me how you stand" request is gone (everything comes at the handshake), the 10-second "just left" window is gone, and your gear goes out 30 seconds after your last change.
- Every feed card can be stamped: kills, XP, skill-ups, joins and dropped quests too.
- Quest Party relies on a channel: the channel is the feed. Your own events, quests, gear and KekChat go to the channel and show in your panel when they come back from the channel, read by exactly the same code as everyone else's, so you see yourself as your friends do (your kills, for example, now arrive in the same batches they get). Without a channel joined there is no feed.
- One Quest Party, no sandbox build: the separate QuestPartySandbox addon is gone. Its pretend players, recorded sessions and test runs are dev mode, part of every build, off by default and turned on with `/qp dev on` (or `/qp debug on`) (`/qp dev party`, `/qp dev replay`, `/qp dev stop` and the rest, and the test runs in Settings). The older emulator (`/qp emu`) is replaced by them.
- You are a player like any other, always: your own events, gear, head and card go through the same path as everyone's. Include self is no longer a switch.
- Pretend players never count toward Party Fuel, and wiping a dev run forgets only them: your own feed, friends and Fuel are never touched.
- Turning dev mode off quiets every dev tool: a run stops and its pretend players leave, loopback goes off, the lab and listener close, and the commands and test runs refuse until it is on again. Loopback only ever holds back pretend players' messages; yours always go to the channel.

### Fixed

- Your own messages could get stuck: Forever answers a channel send with a throttle code yet delivers it, so Quest Party kept resending the first message and everything behind it (your KekChat, your events) never went out. Every message is now sent once, straight away: no queue, pacing or retries, and the game's answer is not judged. The channel is the truth; /qp share compares sent with came back.
- Your own head was missing from the side bar, so your own card could not be opened, and your card's Equipped tab was empty: only the sandbox build kept them.

## 0.3.5 - 2026-11-18

A new look for the feed, a party side bar with player cards, stamps, KekChat,
Party Fuel and quest cards built for a crowd. Friends on 0.2.0 still share
quests, levels and the feed with you; stamps, KekChat, gear, health and power
and professions need 0.3.5 on both ends, so ask everyone to update.

### The feed

- A new look, after the winning concept: each card has the player's round avatar at its top left (their face when known, their class otherwise), a framed mark on the right for its kind (the game's ! and ? for quests, a purple XP, a map, a group, the profession's own icon for skill-ups, a skull), and a color by kind (quests taken blue, hand-ins gold, level-ups purple).
- Painted backdrops from the game's own art behind the cards (a trial, with a switch in Settings).
- Four themes in Settings: Concept, Classic, Midnight and Quiet.
- Quest rows name the quest first ("Fungal Spores Complete!"); kills that finish an objective fold into its Done row; XP rows say how far to the next level ("Lv 12, 96 kills to 13").
- Quests you share with someone glow in your party chat color, and your game party or raid members are marked in it too.
- Sounds for the big moments: a quest handed in, a level up, an objective done.
- A row of icons along the bottom hides or shows kinds of rows in your feed (only what you see changes).
- Every edge of the panel resizes it, rows stretch smoothly as you drag, and `/qp reset` brings back a panel lost off screen.

### Quests

- The Quest tab lists everyone's quests. Pick how a quest card lays out its objectives in Settings: Segmented (one bar with a piece per objective), Grid, Ring or List.
- A quest two or more of you share is one card that scales to ten and more: a section per objective, those still working on it first, latest progress on top in each player's color, the finished folded into a completed bar. Scroll a busy section for the rest.
- Click a quest that is in your own log to open it in the game's quest log.

### The party

- A side bar of party heads beside the panel: portrait, color ring and level for everyone on the channel, greyed for a while when they log off.
- Click a head for that player's card: their equipped gear (with the game's tooltips and links), their quests, and Info with their professions first, zone and XP this session, today and this week.
- Everyone's XP bar at the top, yours first, with thin health and power bars under each (switchable).
- Each player keeps one bright color everywhere: their XP bar, rings and their share of Fuel.
- A Players shown setting (10 to 20) caps how many bars and heads show at once, keeping you, your group and the most active.
- A player on several characters shows once, as the character they are on now.

### Stamps

- Right-click a quest, level, achievement, discovery or death card to stamp it: Hooray!, Gratz!, Legend!, Nice!, Wow!, LOL, Oof! or RIP, each with its emblem.
- A stamp lands on its card for everyone, tilted on a see-through plate, with one of KekChat's effects and sounds picked at random.
- Two different stamps per player per card, kept to that on every client. Hover a card to see who stamped what.
- An optional switch fades stamps off their card after 15 seconds.

### KekChat

- Quest Party's own chat between Quest Party users on your channel: up to three images and a ready-made saying per message, or one click on a ready-made effect (coin rain, fireworks, a gem fountain, confetti and more). Nothing typed is ever sent.
- Spam timeouts, and right-click to mute a sender; anyone you ignore in the game is muted too.

### Party Fuel

- The Fuel tab: one red vat with everything your party has done on this channel, kept for good. XP counts by level, everything else one for one.
- Click the vat to slice it by kind, again for everyone who added fuel, and again for the total; pick a type or a player to see their share.
- What was gained in the last hour, day and week, on the vat and in its tooltip. `/qp fuel reset` starts your count again.

### The dock

- Minimize to a magnetic dock you can drag anywhere: the latest events as keys that glide out as the mouse comes near. Click one to open the panel on it.

### Settings

- Settings is its own window: what you share (gear is the one thing you choose; everything else Quest Party needs is always shared), the party, the display and saved data.
- A speaker in the title bar steps the volume through Loud, Regular, Soft and Mute, its bars showing the level.

### Sharing

- Your gear, professions, health and power go to the channel when they change, paced so a fight or a burst of skill-ups is a trickle, not a flood.
- Kills go out in batches per creature, so grinding does not flood the channel.
- A late message can no longer replace newer news, or bring back someone who just left.
- Hellos are answered once, after a short random wait, and a player not heard from for 16 minutes is taken to have left.

### Fixed

- After your own /reload, everyone already on the channel no longer shows as joining again.
- Your own level-up no longer goes missing when reached in combat.
- Your own rows use your full Forever name, as everyone else sees it.
- Quests no longer look disabled after 5 minutes without progress.
- A row's change flash no longer gets stuck on.
- `/qp stats` no longer counts folded kills more than once.

## 0.2.0 - 2026-11-15

Friends on 0.1.2 and 0.2.0 can share a channel: the messages are the same format with more in them. A friend still on 0.1.2 does not see XP bars, deaths or the newer rows until they update, so ask everyone to update.

### Protocol

The message format is still version 1. Nothing was removed or given a new meaning, and there are no new kinds of message, only new fields and entry types:

- Hello and its answer also carry `x`, the XP so far this level, and `m`, the XP the level needs (0 at the level cap), so a newcomer sees everyone's XP bar at once.
- Every entry carries `s`, the sender's own plain description of it. A message too long with it is sent without it.
- An entry of a type this version does not know is shown as a plain card with that description, instead of being dropped. From now on, friends on an older version still see a newer version's news.
- New entry type `death`, with the zone and the level.
- An XP entry from handing in a quest carries the quest's name, so it is shown on the quest's row and not as a second row.
- Skill-up entries are sent for professions only.

With a friend still on 0.1.2:

- They ignore the new fields and drop the entry types they do not know, such as deaths, so they see less but nothing breaks.
- Their hello has no XP, so their bar shows on yours from their first XP gain.

### Added

- Party XP bars above the tabs: one bar per other player sharing on the channel, stacked, each in its own color, with their name, level and how far they have to go. Bars move as they gain XP, a player at the level cap shows as max level, and a newcomer sees everyone's bar as soon as they join. Hover a bar for that player's XP and last gain.
- With Kills on, XP from a kill gets a row naming what was killed, in Quest Tweet's words, and how many more like it to the next level: "Kills Riverpaw Gnoll for 65 XP", "Level 10, 13 kills like this to Level 11". It has no bar, so it cannot be mistaken for quest progress.
- Level-ups lead with "DING!! Reached Level 11!" and drop confetti over the panel, for your own level-ups and your friends'. Turn the confetti off with Level-up confetti in Options.
- Updates from a newer Quest Party that this version does not know yet show as a plain card with the sender's own description, so friends on different versions still see each other's news. Every update now carries that description. Turn them off with Other updates in Options.
- Deaths: where someone died and at what level. Turn them on or off with Deaths in Options.
- In debug mode, `/qp stats` shows what you and your friends have done over the last 7 days: XP, kills, quests, levels, skill-ups, achievements and deaths. A small daily tally per player is kept for a week, apart from the feed, and only while debug mode is on.
- In debug mode, `/qp testloc <target>` shows a test in your own panel only, with nothing sent to the channel: `confetti`, `level`, `death`, `quest`, `kill` or `all`.
- In debug mode, `/qp emu play evening` replays a real recorded session of two players through the emulator, sped up with `/qp emu speed`.
- In debug mode, `/qp replay` reads the saved messages from other players again to rebuild the panel from real traffic. The last 200 messages are now kept across reloads.

### Changed

- XP from kills is no longer a feed row unless Kills is on (it is off by default), as Quest Tweet kept kill XP behind its own option. Other XP gains show as before, and every gain still moves the XP bars.
- A quest handed in is one row with a gold background, "Quest complete: <quest>" with its XP. Its XP no longer shows again as a second row, though it still moves the XP bars.
- A finished objective reads "Done: 10/10 <objective>" with a check mark, so it is no longer mistaken for the quest being handed in.
- A run of XP gains is one row that adds up: kills of the same creature ("Kills Wandering Spirit x3 for 243 XP") or other XP ("+237 XP in 3 gains"). A new run starts after five minutes without one.
- A run of skill-ups in one profession is one row that climbs and moves to the bottom, "Cooking 19 > 26" with "7 skill-ups", instead of a row per point. A new run starts after ten minutes without one.
- Only profession skill-ups are reported. Weapon skills and Defense, which rise constantly while fighting, are left out.

## 0.1.2 - 2026-11-13

### Added

- Progress is now shared over the channel you choose, as addon messages that never show in chat: your quests, objectives, levels, discoveries, professions and achievements reach everyone on the same channel who runs Quest Party, and theirs show in your feed and as their quest cards.
- When someone joins the channel, everyone already there sends where each of their quests stands, so the newcomer sees their quest cards at once.
- The player list shows who is sharing on the channel, and says when someone joins or leaves.
- Rapid progress on one objective sends only the latest count, to stay under the game's message limit.
- `/qp share` reports what has been sent, how much of it came back from the server, what was received, and whether the game refused anything.
- XP updates show the amount gained, your current level and the percentage left to the next level, with a progress bar. Turn them on or off with Leveling in Options.
- Quest cards are kept across reloads, even without a channel. Your own refresh from your quest log; other players' stay visible and turn gray after five minutes without an update.
- Clearing saved history now asks for confirmation first, from both the Options button and `/qp clear`.
- In debug mode, the sample party emulator sends its players over the channel and shows them only when the server sends them back, and `/qp listen` opens a window listing the messages on the channel as they pass.

### Changed

- Quest cards are shown only while a quest is underway: at least one objective has progress and not all are complete. Quests not yet started, and quests that only need handing in, are left out of the panel and of what is told to others.
- Clear and the debug emulator button moved into Options.

### Fixed

- A character with a surname is recognized as itself, so its own messages are not mistaken for another player's.

## 0.1.1 - 2026-11-13

### Fixed

- Improved quest identification, including quests accepted before Quest Party started tracking them.
- Repaired saved "Unknown quest" objectives when they can be matched to your own quest log.
- Quest item counts now update the existing objective line as counts increase or decrease.
- Removed duplicate objective lines left by older builds and corrected total quest progress.

## 0.1.0 - 2026-11-13

### Added

- Initial release for World of Warcraft: Forever.
- A live feed for quest progress, level-ups, achievements, discoveries, and profession gains.
- Persistent quest cards with objective counts and progress bars.
- A single row of filter tabs and a choice of detailed or compact rows.
- Options for event categories, local chat output, feed order, and including your own progress.
- Channel creation, joining, connection status, saved reconnects, and disconnecting.
- A sample party emulator available in debug mode.
