# Changelog

Features and fixes shipped in each release. Copy a version's section into
CurseForge's changelog field using Markdown formatting.

## Unreleased

### Changed

- Settings reorganized by what each setting is about: Channel, Share my, Feed, Party, KekChat, Window, Data. The window is bigger, every section is evenly spaced, and the recent channels row says so when there are none yet.
- A place found is one row with the XP it gave ("Discovered: Thunder Ridge", "+80 XP"), as a quest handed in is; its XP is no longer a row of its own. Kill XP stays on kill rows.
- Custom KekChat is off for now: KekChat is its quick chats and effects. The builder (images, typing, saves) is gone from Settings.
- A feed row's avatar ring is in its player's own color, as their head and XP bar (your game group's in the party's color).
- Kill rows ("Kills Kolkar Wrangler x2 for 202 XP") wear the Kills square, now orange, not the XP one: a row's square now always matches the filter icon that hides it. XP rows are only XP.
- Minimize sits right beside close in the title bar; close stays at the far right.
- The view button shows three bars for compact rows and two for detailed (compact showed one, which looked like minimize).
- Share location in Settings (on by default): off, nothing of where you are is sent.
- Players on the map keep up while travelling: with no other update for a minute, a small message says where you are, only if you moved. Friends on 0.3.7 ignore it.
- The dock, minimized: a drawer comes out only when the mouse is on the dock or within a few pixels of it, only the one under the mouse, and it glides out more slowly.

### Added

- Stats tracker: a growing table of what you and your friends do, always on, kept only on your computer and separate from Party Fuel: kills (yours by creature), XP by source, quests, deaths, levels, skill-ups, discoveries, distance travelled and flown, jumps, time played and AFK, sessions, money in and out, KekChats and stamps. /qp tracker shows today, this week or all time. Old days fold into months and years, so it stays small.
- Your own KekChats: up to 10, made in a new editor (Edit your KekChats... in Settings, under KekChat), each an icon from a browser of every game icon, up to 100 characters of your own words, a sound from a curated list and an effect. They replace the built-in quick chats, which become your starting ten. Long messages show whole when you hover their row.
- Blocking KekChat: right-click a KekChat to block that message from its sender, or all of their KekChat. The editor lists what is blocked, with Unblock, as tall as that list; Settings, under KekChat, says how to block, beside a note to keep KekChat clean (everyone on the channel sees it).
- The minimized dock's drawers are the feed's own rows: the same look, stamps, hover and right-click to stamp (or mute) as in the feed. Compact dock in Settings uses one-line rows, so twice as many fit.
- AFK on the party bars: a player who goes AFK keeps their bar, dimmed with an AFK tag, and hovering it says for how long. It clears the moment they are back. Someone who logged off has no bar, so away and gone never look alike. Friends need 0.3.8 for theirs to show.
- Show alts: a player's other characters, yours included, stay in the side bar after everyone else as smaller heads with a violet ring and a dimmed portrait ("Alt" on hover), so they save room; click one for its card. On by default; off, each player has one head.
- Opacity: a slider in Settings makes Quest Party see-through (20% to 100%), its side bar, player card and KekChat included. On hover sets what happens while the mouse is over it: Off, Solid on hover, or Fainter on hover. An opacity button in the title bar opens a short slider to set it live, and its mouse wheel steps it.

### Fixed

- Cards with a long player name and quest title could not be stamped (right-click did nothing) since 0.3.7 added when each event happened to its card's name. Card names can now be much longer. A friend still on 0.3.7 will not see stamps on those cards until they update.
- The dock pulled a tucked-in drawer out with the mouse far from it, anywhere the drawer could reach once out.

## 0.3.7 - 2026-11-20

KekChat moves into the feed, effects move onto cards, and Quest Party learns
where everyone is. Friends on 0.3.6 still share with you: your chat shows in
their KekChat tab, and what they do not know yet (card effects, where you are)
they quietly skip.

### KekChat in the feed

- Every KekChat message is a feed row of its own, its images and saying together, stampable like any card. Messages you already had move into the feed at their times, and a KekChat icon in the filter row hides chat rows.
- Under the feed sits the red KekChat button: it opens the quick chats, with the effects in a grid below them. It opens upward, or downward when Quest Party sits high on the screen, and never off it. Custom KekChat in Settings adds the builder (images, sayings, Send, Save) beside it.
- The KekChat tab and its pop-out window are gone.

### Effects and stamps

- Effects (Coin rain, Fireworks, Gem fountain and the rest) play on cards: right-click any card and pick one under the stamps. It plays over that card for everyone and leaves nothing behind, no row and no stamp. One picked from KekChat plays over the feed.
- Effects fill the window they play in: faster, wider and higher on a bigger panel, with more particles. Rain falls the whole way down, fireworks pop high up, the fountain reaches the top. They always draw over the cards.
- Each effect has an icon of its own in the grid.
- Each player can put up to five different stamps on a card (was two).
- Muting moved to the stamp picker: right-click any of a player's cards to mute or unmute them.

### Where everyone is

- Every update says where its sender was. Hover a card for "Where: The Barrens (52, 30)".
- Players on the map: each player's last known position shows as their class icon on the world map and the minimap, riding the minimap's edge when they are far. OpenMap and other map addons that show HereBeDragons icons show them too. Hover one for who, where and how long ago. It moves when they next send an update; positions older than two hours are left off. Players on the map in Settings turns them off.

### Health and mana

- Two small upright bars beside every head in the side bar, and labeled bars across the player card with their numbers ("1240 / 1800"). Bars beside heads in Settings turns the side bar's off. The XP bars at the top show XP only.
- They show live for you and anyone in your game party or raid. WoW Forever keeps health secret from addons, so it cannot travel over the channel: before this, no bar ever showed.

### The feed

- Rows no longer repeat the player's name: the avatar says who, the second line goes straight to the details ("Lv 6, 14 kills to 7"), and hovering a row shows the name first.
- Learning a profession is a row of its own ("Learned Fishing!"), with the profession's icon.
- Settings remembers the last five channels you used: click one to switch to it, right-click to forget it.

### Fixed

- Every distinct event is its own card: dying twice in one zone at one level, or picking a quest up, dropping it and picking it up again, reused the first card's stamps. Each event now carries when it happened (the server's clock, the same for everyone). Kills, XP, skill-ups and objective progress still fold into one running row.

## 0.3.6 - 2026-11-19

One Quest Party, with the channel as its single feed: what you see of yourself
is exactly what your friends see. Quest Party relies on a channel; without one
joined there is no feed. Friends on 0.3.5 and 0.2.0 still share with you as
before: the messages are the same.

### The channel is the feed

- Your own events, quests, gear, stamps and KekChat go to the channel and show in your panel when they come back from it, read the same way as everyone else's. Your kills, for example, now arrive in the same batches your friends get.
- You are a player like any other: your own head leads the side bar and opens your card, with your gear on it. Include self is no longer a switch.
- Messages are sent once, straight away, with no queue, pacing or retries. You say hello and answer newcomers at once, and everything is shared at the handshake (the "tell me how you stand" request is gone). Your gear goes out 30 seconds after your last change. `/qp share` compares what you sent with what came back.

### Dev mode

- The separate QuestPartySandbox addon is gone. Its pretend players, recorded sessions and test runs are now dev mode, part of Quest Party, off by default: `/qp dev on` shows the tools (`/qp dev party`, `/qp dev replay`, `/qp dev stop` and the rest, and the test runs in Settings), and `/qp dev off` stops all of them.
- Pretend players never count toward Party Fuel, and wiping a dev run forgets only them: your own feed, friends and Fuel are never touched.

### The panel

- The title can name the channel you share on, in grey after Quest Party (Show channel in title in Settings, on by default; switch it off before screenshots so they do not invite strangers). On a narrow panel Quest Party collapses to QP.
- The Quest tab has a small gear at the top of its list that cycles the quest cards' layout: Segmented, Grid, Ring, List.
- Every feed card can be stamped: kills, XP, skill-ups, joins and dropped quests too.
- A kill row's multiplier ("x4") is orange, so it stands out.
- Quest Party has a page in the game's Options, under AddOns, with a button that opens its settings.

### Fixed

- Your own messages could get stuck: Forever answers a channel send with a throttle code yet delivers it, so Quest Party resent its first message over and over and nothing behind it went out.
- Your own head was missing from the side bar, so your own card could not be opened.

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
