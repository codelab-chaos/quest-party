# Changelog

Features and fixes shipped in each release. Copy a version's section into
CurseForge's changelog field using Markdown formatting.

## Unreleased

### Added

- A quest two or more are on is one card that scales to a crowd: a section per objective, and in each the players still working on it, the latest to make progress first and flashing, with bars in their own colors. Four show at a time; scroll the section for the rest. As each finishes, they fold into the section's completed bar. The sandbox has a Shared quest scenario: ten pretend players on one quest.
- Quest cards in four layouts, picked with the Quest cards slider in Settings: Segmented (the default: one bar with a piece per objective, the total beside it, and the objectives on one line with finished ones checked), Grid (two objectives to a line, each with its bar), Ring (overall progress in a ring where the ! was, objectives on one line) and List (a line and a bar per objective, as before). A quest one player is on now shows their avatar.
- Stamp emblems: every stamp carries a picture beside its word (one of the garrison's class and spec emblems). The right-click picker is one compact grid, each emblem in a gold frame over its word. It opens under the card, as part of the panel (moving and hiding with it), and closes with its X, Escape or a click anywhere else. The lab has a Stamp emblems probe that shows which emblems the game has.
- A Stamps fade switch in Settings, off by default: on, a stamp fades off its card 15 seconds after it lands and the rest close up; stamping that kind again brings it back. The stamps are still kept and listed in the card's tooltip.
- Every player's professions: each client reads its own from the skill list and tells the channel when they change (once a burst of skill-ups settles), so a player's Info tab lists all of them, highest first, each with its icon. Professions now lead the Info tab.
- A stamp hits its card with one of KekChat's effects (confetti, fireworks, a gem fountain, coin rain, a storm), small and bursting from the stamp, and one of KekChat's celebration sounds, both picked at random each time. The effects follow KekChat's effects switch; the sound plays at your Volume.
- A Players shown slider in Settings (10 by default, up to 20): the most players the XP bars and the side bar show at once. Past it, you, your game group and whoever was active most lately are kept.
- The sandbox's pretend players send health and power: it drops in a fight and comes back after, power by class (rage, energy, mana), paced like a real client's.
- Fuel gained lately: under the vat's number, "+340 last hour", and in its tooltip the last hour, day and week (each gain's fuel kept in ten-minute steps for a week).
- Your game party or raid members are marked in the party chat's color wherever they show: a stripe down their feed rows' left edge and their avatar's ring, their XP bar's frame, and their side bar head's ring. Looked up on your own client as the roster changes.
- Card backdrops (a trial): the feed's cards show painted scenes from the game's own art (the garrison mission backdrops of Frostfire Ridge, Shadowmoon Valley, Tannan Jungle and the seas, and the group finder's backgrounds), rotated so neighbors differ, each card its own slice, faint under the text and fuller at the right. Settings has a switch to turn them off.
- An ALPHA! stamp, pink and tilted, over the title of the windows that pop out beside the panel (a player's card, KekChat): they are still being made.
- `/qp fuel reset` empties this channel's Party Fuel on your client (after asking), so it counts again from now. Friends keep theirs. The vat's tooltip explains how XP counts in plain words.
- Sounds for the big moments, on everyone's client at your volume: a quest handed in, a level up, an objective done. One sound per moment (the level's wins when they land together), and none for old rows caught up or replayed.
- Stamps on feed cards: right-click a quest, level, achievement, discovery or death card for a menu of eight ready-made stamps (Cheers!, Gratz!, Legend!, Nice!, Wow!, LOL, Oof!, RIP). Each kind of stamp is inked big across the card in its own spot and tilt, fanned like real rubber stamps, with a count when repeated ("Cheers! x3"); each time one lands (new, or once more) it flies in again with its sound, for everyone on the channel. Hovering the card lists who stamped what. Each player can put two different stamps on a card: the same one again lands again, and a third replaces their oldest. Like KekChat, nothing typed travels, and muting and the spam timeouts apply. Stamps are kept a week.
- Health and power over the channel: everyone's XP bar has a thin health bar (green) and power bar (blue mana, red rage, yellow energy) under it, yours included. They go out in 5% steps, at most once every 1.5 seconds (a change in between waits, and the latest goes out when the time is up), so a fight is a steady trickle rather than a flood. A hello carries them, so a newcomer sees them at once; older clients ignore them. Hover a bar for the numbers. They show on a player's side bar card too while they are here, and a Health and power switch in Settings turns the bars off.
- `/qp reset` (or `/qp repos`) puts the panel back at its first size and place, shown and not docked, and the dock back at its screen edge: for a panel lost off screen.
- A Theme slider in Settings (Display): Concept (charcoal and gold), Classic (black and silver, as the game's tooltips), Midnight (deep blue) and Quiet (plain dark rows). It changes the feed at once.
- Feed card scenes, groundwork: 16 painted scene slots in one atlas, chosen by feed type or profession, with a template for painting them and a script that builds the atlas (docs/scenes.md). Placeholders for now; not on the cards yet.
- A 123 tab: a graph of everything counted on your channel over the last 7 days (XP, kills, quests, levels, skill-ups, achievements, deaths), filtered by type and player: totals split by player, a bar per player for one type, or one player's share of the party. The daily tallies behind it are kept for everyone now, not only in debug mode.
- The 123 graph uses vertical glass vials, with totals above, labels below and player colors stacked inside. Vials wrap and scroll in narrow windows.
- Minimize Quest Party to a dock at the left edge of the screen (or the right, in Settings): new events stand as thin bars that grow toward the mouse like the macOS dock, puff their icons as they arrive, and open the panel again where you left it when clicked.
- A speaker in the title bar steps the volume through Loud, Regular, Soft and Mute (also Volume in Settings).
- KekChat, Quest Party's own chat between Quest Party users on your channel: a KekChat tab at the right end of the tabs, which pops out beside the feed. Along its bottom, a chat bar: choose up to three images (search the game's icons, or type a word to find images and sayings) and a saying ("Gratz!", "On my way!", "Cheers!" which drops confetti for everyone), then Send; Save keeps yours, and the book on the right lists your saves. KekChat's name is a red button that drops down ready-made messages and effects (coin rain, fireworks, a gem fountain and more, some with words that fall too, with sounds); one click sends any of them. Nothing typed is ever sent, so only pre-made words are ever shown. Sending too many at once times your chat out for a while (longer each time), and anyone spamming you is hidden for a while the same way. Right-click a message to mute its sender; anyone you ignore in the game is muted too.
- Two tabs, Feed and Party, with a row of icons along the bottom of the panel: Leveling, Discovery, Kills, Achievements, Deaths, Professions and Quests. Click an icon to hide or show those rows in your feed. It only changes what you see; friends still get your updates.
- Party shows everyone in the party and every quest in full with who is on it, in one tab (it was Quests and Party).
- Party heads down the right of the panel: one for each player in the party, with their race portrait, a ring in their class color and their level, in the order they arrived. Players who logged off stay as greyed heads for up to a week, unless Remember players who left is off. Turn the heads off with Party heads.
- Click a head for that player's card, beside the panel: Equipped (their items, laid out as on the character window, with the game's tooltips and shift-click links; click one to see its item level and stats in the middle, or see their stats from all their gear added up), Quests (a row for each, the ones on your log too first, with how far you are) and Info (where they are, their XP this session, today and this week, their professions).
- Your equipped items are shared with the party: the whole set with your hello, when someone asks, and when your gear changes (at most every 3 minutes, so changes in between go out together). Turn it off with Share my gear.
- A row in the feed when someone joins the party.
- Settings has Forget players and Forget cards, to free what is saved about others.

### Fixed

- After your own /reload, everyone already on the channel showed as joining again (a Joined the party row and an is sharing with you line each time). Who was heard lately is now kept across reloads, so only a real arrival is welcomed.
- The speaker button now shows the volume: three rising bars beside it, lit to the level (soft one, regular two, loud three), none at Mute.
- Right-clicking a card could say you had already stamped it when your stamps on it were ones since retired (hidden on the card). Retired stamps no longer count toward your two, and are cleared from what is kept.
- At narrow widths the panel's title ran under the header buttons. It stops short of them, switching to a short form ("QP Sandbox") when the full one does not fit.
- Someone who just left could come back as here when a message they sent (an entry, a quest, gear, health) arrived a moment after they went. A late message still shows, but only a hello (or news long after) brings them back.
- Your own rows, cards, XP bar and KekChat messages carried only your first name ("Unbearably") while everyone else saw your full Forever name ("Unbearably Huggable"). They now use the full name, and what was saved under the first name moves to it on load, stats included.
- XP in the 123 graphs could carry a fraction (from pretend players' scaled gains). Tallies are whole numbers when recorded, and the graphs round older ones.
- A panel sized taller than the screen could not be resized back: its corner grip was off screen. Every edge of the panel can now be dragged to resize it (top, bottom, left, right), and it is never taller than the screen.
- Your own level-up could go missing (no row, no DING): a level reached in combat comes with a value addons cannot read. The level-up is now also taken from the XP reading just after it, which sees the level go up, and made once whichever comes first. Jumping several levels at once is a level-up row too.
- The sandbox showed your own character twice when the regular Quest Party was loaded beside it: once from its own tracking (Bagoe) and once heard from the regular one as a friend (Bagoe Bones). The sandbox is a developer's tool, so it now ignores your own regular Quest Party entirely and forgets what it saved from it.
- The panel could not be built after the Theme change (its border color was lost), so /qp and /qps did nothing. A new test builds the whole panel and opens every tab, so an error like it fails a test.
- Resizing the panel was jerky: the whole feed was rebuilt on every step of the drag. Rows now stretch as you drag, with one redraw when you let go.
- A row's "just changed" flash could stay on, tinting rows tan.
- /qp stats counted XP from kills more than once when kills of one creature were folded into one row.
- Quests nobody had moved for 5 minutes were grayed out, so live quests looked disabled. Quest rows now stay at full color; the time on the right shows how long it has been.

### Changed

- A card's tooltip lists its stamps by who stamped them: their initials in their own player color, then the stamp in its color ("MW: Hooray!").
- The players' avatars on the cards are smaller (24 pixels, from 34), with a thinner gold ring, touching the card's top and left edges; the line between the avatar and the text is gone.
- XP marks (and the XP filter) use the garrison's purple XP icon (file 894556).
- Quest complete marks use icon file 236669.
- A skill-up row's mark shows the profession's own icon (a cooked meal for Cooking, a flower for Herbalism and so on).
- Stamps tilt at their own angle (up to 35 degrees either way, the same every time), smaller, spread along their card from the mark toward the title, each at its own height, on a see-through plate in their color with a thin edge. They hold their place as the panel widens; on a narrower panel they pack up side by side, never over one another, and shrink together (to half size at most) when they would not otherwise fit.
- The card's portrait sits on the card with a sliver (5%) over its left edge, joining it to the side bar; the ALPHA stamp moved off the name to the class line.
- Every row's mark follows the winning concept: a square in its kind's color with the art in the middle. Quests are back to the game's own yellow ! and ? (gold), XP and kills a purple XP, discoveries a map, skills a hammer and people a group (blue), deaths a skull (red), dropped quests and the unknown gray; a level-up keeps its gold crest. The filter row uses the same marks.
- Stamps: two different stamps each per card, and then you are done with it. The picker greys out the one you used and, after two, says you have stamped it. Every client keeps only each character's first two on a card, so stamping again changes nothing, whatever a client sends.
- Rows light by kind, as in the winning concept: a quest taken deep blue, someone joining blue, a quest handed in warm gold, a level-up purple, the rest charcoal; in every theme.
- Feed rows follow the winning concept: the player's round avatar in a gold ring on the left (their face, by race and sex, when known: yours, and anyone on 0.3.5 or later; their class otherwise), the title and details beside it, and the event's mark on the right in a gold-edged square (the XP gem, a gold ! or ?, the map, the party, the hammers; a level-up keeps its round crest), the time just before it.
- A player's card no longer shows their portrait twice: the selected head slides out onto the card as its portrait, grown to fit, and the card lines up with it. The other heads fade back while the card is open and come back as the mouse nears the side bar. With no card open, the heads work as before; beside the popped-out KekChat, the card keeps its own portrait.
- Each player has one bright color, the same everywhere: their XP bar, the ring around their portrait (side bar, party cards, KekChat), and their part of Fuel. Sixteen colors (bright primaries, then deep versions), given the first time a player is seen and kept, the one fewest players have, so colors never shift and a party rarely shares one. The pastel bars are gone.
- A kill's row says how many more like it to the next level in short: "Lv 12, 96 kills to 13". Other XP rows say how far to go the same way, in whole numbers: "Lv 16, 87% to 17".
- A quest two or more of the party are on is one card in the Quest tab, the party side by side: each member's portrait, name, count and bar (red while going, green when done), their objectives on hover. Quests you share lead the tab.
- Kills that finish an objective fold into its Done row ("Done: 10/10 Palemane Tanner slain", "+8 kills, +440 XP"), a collection too (the wolves in "Prairie Wolf Paw"), instead of a separate kill row. Other kills stay as they are; the XP bar and Fuel count every kill.
- The party's tabs show each player once, as the character they are on now: a player's other characters (and yours) have no tab of their own, their history kept. Each client makes a random player id once per game account and sends it in the hello; older clients send none, so their characters still show apart.
- Feed titles and detail lines run as far as the time or the stamp button allows, instead of stopping at a fixed width, so far less is cut off. The times and the stamp button are brighter.
- The 123 tab is Fuel (Party Fuel). It opens on one big red vat with the party's fuel as one number: each kind of activity counted by a weight. XP counts by level, not raw: a level's worth of XP is 200 x level fuel (2,000 at level 10, 11,800 at 59), a straight-line ramp instead of the game's steep curve, from the gain's own level requirement or Forever's XP table, and nothing at the cap; the feed keeps real XP. Everything else is one for one: each kill, quest, level-up and skill-up adds 1 (deaths add none). Click the vat to slice it into a section per kind, each in its color with its number and name on one line ("451 Kills"), sized by its share of the fuel with a small gap between; click again for everyone who ever added fuel on the channel, most first: a line each with their fuel and a bar sliced by kind (numbers where they fit, everything on hover), scrolling, with a link per player at the top that jumps to them; a click on empty space returns to the total, as does picking all types and all players, or the Party Fuel icon (a red flask beside the menus) from anywhere; click a player's bar for their own view. Pick a type to see the same wide vat sliced by player ("40k Bagoe Bones", in each player's color), or a player to see it sliced by kind with their share of the party's; it grows and scrolls when there are many. One type for one player is a single vial. Achievements are left out of Fuel for now (still counted). Big totals fit (74.3k, 1.2M), with the full number in the tooltip. The vat grows with the panel when you resize it, its numbers with it. Under the whole vat, "What is Party Fuel?" opens a short note: it is coming soon, with the party's total and how the clicks go.
- Fuel is kept for good and per channel (said in the vat's tooltip): each channel's party has its own, instead of the last 7 days. What was counted before moves to the current channel.
- Quest rows name the quest first: "{quest} Accepted" and "{quest} Complete!", with the game's quest marks: a big centered gold ! for a quest taken or under way (progress cards too), a ? for one handed in.
- The tab of everyone's quests is named Quest (it was Party), without the player count.
- Quests you and someone else are both on glow in the party chat's color (lavender by default, or whatever you set in the game's chat settings), breathing slowly, in the Quest tab and on their feed rows.
- In the Quest tab, a quest in your own quest log opens in the game's quest log when clicked; one only others have does not. In the feed, clicking a quest still shows it in the Quest tab.
- A quest's progress bar on the feed cards is red while it is going and turns green when done, like its count. XP bars stay green.
- The 123 graphs are glass gauges with the label on top and the total in the middle of the glass, no stopper. Each kind of activity has its own color (XP purple, kills red, quests gold, levels blue, skill-ups green, achievements orange, deaths gray), never sliced up by player: who did how much is in the gauge's tooltip, and the player menu shows one player's share. Player names take bright primary colors, each their own.
- Your own XP bar is in the party's XP bars too, first, so everyone on the channel has one. It follows the game's as you gain XP.
- The feed's look follows the concept art: charcoal rows lit from the left in thin gold rims, each icon in its own gold-edged well with a gold line after it, royal purple light for level-ups, warm gold light for hand-ins (instead of a flat mustard fill), and dark blue for quest progress.
- The dock is a magnetic event dock: a small housing you can drag anywhere (first at the right edge of the screen, or the left with Dock on the right off), holding the latest 7 events as keys the size of feed rows, packed like piano keys, only their icons showing, newest at the bottom. As the mouse comes near, the nearest keys glide out of the housing just far enough to show who did what, the closest furthest, gliding with a little friction, and slide back in when it leaves; they come out toward the middle of the screen. A new event rises in at the bottom and shows itself for a moment. Clicking a key opens the panel on that event, flashing it in the feed. Try it with mock events in `/qps lab`.
- The sandbox (QuestPartySandbox) shows everything of your own character's (quests, deaths, XP, kills, levels, skill-ups, achievements) beside the pretend party's, as a real client shows its own. It still sends nothing of yours. Include self is hard-coded on there, with no switch in Settings or `/qps set` (the regular build keeps its switch). A test checks that every kind of your own event shows in the sandbox's feed and reads exactly like the same event from a friend. Your own party card comes first in the sandbox's Party tab, with your level, zone, quests and equipment, so nearly everything can be tried on your own character.
- Objective counts in the feed (4/8) are as big as the title and gold, green when done, instead of small and gray.
- Welcomes are always shown, with no switch, and limited: one per player every 10 minutes, and at most 5 a minute, so players coming and going cannot flood the feed.
- The XP, Achievements and Professions tabs are replaced by the icons along the bottom of the panel.
- What makes Quest Party work is always shared, with no switch: quests and their objectives, leveling, kills, discoveries, deaths, professions and achievements. Hide their rows in your own feed with the icons along the bottom of the panel. Gear is the one thing you choose to share, under Share my in Settings.
- XP from kills goes to the party in batches, one message per creature once you stop killing it for a few seconds (at most every 30 seconds), so grinding does not flood the channel. Friends' feeds and stats still count every kill.
- Options is now Settings, a window of its own in Quest Party's colors, with sections for the channel, what you share, the party, display (with a Filter icon size slider) and saved data.
- Players who say hello are answered once, after a short random wait, so a big party does not answer at the same moment. Everyone also says where they stand every five minutes, and a player not heard from for 16 minutes is taken to have left.
- Messages about how things stand carry a number that only grows, so a late or repeated message never replaces newer news.
- A player not seen for a week is forgotten.

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
