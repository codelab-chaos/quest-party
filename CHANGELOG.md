# Changelog

Features and fixes shipped in each release. Copy a version's section into
CurseForge's changelog field using Markdown formatting.

## Unreleased

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

- XP from kills is no longer a feed row unless Kills is on (it is off by default), as Quest Tweet kept kill XP behind its own option. Other XP gains show as before, and every gain still moves the XP bars.
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
