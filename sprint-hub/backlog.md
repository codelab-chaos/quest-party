## 0.3.8 (planned)

- **power-charge-event** (story, 0.3.8): a timed party event, such as 10 minutes to get as many kills as possible.
  How it starts is to be designed: someone kicks it off, a random trigger, or a smart trigger from what the party is
  doing (active factors). Each client keeps track of the event and every participant's stats from the feed, as Fuel
  does. With no channel history, the start message must carry what every client needs to agree on the window (an
  id, when it started, how long it runs, what counts); someone joining mid-event sees it from the next presence or
  its end. Designed for fun, as if there are no cheaters (see party-minigames).

## 0.3.6 (branch `v036`, from 2026-11-18)

Rule (owner, 2026-11-18): there is no sandbox, just the next version, tested in the one Quest Party install from
its branch. Pretend players are a debug-mode (dev mode) feature.

- **release-036** (chore, done 2026-11-19): change list in CHANGELOG.md, `v036` merged into `main`, pushed, tagged
  `v0.3.6` with a GitHub release. Still open: the CurseForge upload (manual).
- **message-order-numbers** (idea, later, if evidence): 0.3.6 removed the always-growing number (`n`) that status
  messages carried so a late or repeated one never replaced newer news. It guarded the old send queue's resends;
  with direct sending one sender's messages arrive in order. Bring it back only if out-of-order news shows in game.
- **own-head-in-release** (bug, fixed 2026-11-18): your own head was missing from the release's side bar (only the
  sandbox added it), so your own card could not be opened.
- **release-equals-sandbox** (story, built 2026-11-18, owner to look): the sandbox build is gone (owner: "no more
  sandbox mode, we just have the next version"). Its tools are dev mode in every build behind `/qp debug` (`/qp dev
  ...`, Settings' test runs), replacing `emulator/`; every `IsSandbox()` branch removed; you are always a player like
  any other (own gear, head and card; Include self no longer a switch); pretend players never count toward Fuel and a
  dev wipe forgets only them; one package, and deploy takes any branch; the old QuestPartySandbox folder and saved
  data deleted from the install.

## Owner's push, 2026-11-18: every feature forward (measure-first held)

Decided 2026-11-18: no friends-only sharing, no level-cap sharing profiles, and no share-on-request (reputation,
recipes, location and the rest): a player running a local script could ask everyone for everything, an opening for
abuse. Party minigames are to be decided, and will be what spends Party Fuel.

Always forward: no patches to older versions. Speculative ideas were taken out of this backlog (an all-players
gauge meaning, alts as one player, the game's big backdrops, a custom font); what is left was asked for.

- **backdrops-trial** (story, built 2026-11-18, owner to look): feed cards get painted backdrops from the game's own art, rotated so rows vary:
  the garrison mission scenes (Frostfire Ridge, Frostfire Sea, Shadowmoon Valley, Shadowmoon Sea, Tannan Jungle,
  each in Back, Mid and Fore layers) and the group finder backgrounds, faint under the text and fuller at the right.
  A trial until the backdrops are catalogued (wow-media-lab and the lab's probe). Only ones the game has are used;
  a Settings switch turns them off.
- **vitals-on-active-players** (story, built 2026-11-18, owner to look): health and power shown on the players active now (here on the
  channel): their side bar card and the XP strip, with a Settings switch to turn the bars off.
- **party-members-highlight** (story, built 2026-11-18, owner to look; whether it replaces the party cards is the owner's call): the players in your game party or raid (UnitInParty, looked up on each
  client) are marked clearly wherever they show: their rows, XP bars and side bar heads. May replace the party cards
  as the way to see who you are grouped with.

- **players-shown-cap** (story, built 2026-11-18, owner to look): a Players shown slider in Settings, 10 by default,
  up to 20. The XP strip and the side bar's heads show at most that many; past it you, your game group and whoever
  was heard most lately are kept, in their usual order. A stress test draws a party of 20 at the cap of 20 (bars and
  side bar) without an error. Still to do in game: a real 20 player channel at the cap of 20, to see it stays snappy.
- **busy-channel-pacing** (story, backlog, after `burst-and-scale-numbers`): a channel with many players and every
  kind of event is chatty. Instead of sending each change as it happens, the client paces what it sends so the
  channel stays snappy:
  - **Collapse state, latest wins.** XP, health and power, gear, quest progress and the like are state: only the
    newest value per kind (and per quest) is kept in an outbox, and the older unsent ones are dropped.
  - **Flush on a beat.** The outbox goes out on a steady beat, several changes in one message where they fit,
    rather than one message per change.
  - **The beat follows the channel.** The more players present, the slower the beat (a few seconds with a small
    party, longer with 20), so the channel's total stays under the server's budget whatever its size.
  - **Moments skip the queue.** A level-up, a quest handed in, a death, an achievement and a stamp still go out at
    once; those are what people watch for.
  - **Kills fold before they go.** A run of kills is one message (as the feed already folds them).
  - **Receivers change nothing.** Messages keep their kinds; only fewer of them, and newer.
  - Uses the numbers from `burst-and-scale-numbers` for the beat and the budget; the sandbox's party of 20 over
    loopback is the test (messages per minute per player, before and after), plus an in-game run at the cap of 20.

- **message-funnel** (story, backlog, mid priority): one receive pipeline that every incoming message passes
  through before any handler (`comms/sharing.lua`'s `handlers`) runs, so flood protection lives in one place
  instead of per feature (KekChat's spam timeout, the stamp rules). Clients can't be trusted, so the protection is
  how each client receives; it can't stop a modified client sending. In order, cheapest first:
  - **Muted:** a muted sender is dropped before parsing.
  - **Shape:** known kind, size within limits, fields as expected; anything else is dropped.
  - **Budget per sender:** a per sender, per kind token bucket (hellos, entries, vitals, stamps and says each with
    their own rate). Over budget: dropped, and counted.
  - **Cool off:** a sender far over budget is ignored entirely for a while (auto muted, a few minutes), with one
    line in chat on this client only.
  - **Dedupe:** the same message again from the same sender within a short window is dropped.
  - **Then the handler**, as today.
  - **Counts:** messages and drops per sender and kind, in `/qp debug`, so a flood can be seen and its numbers
    tuned.
  - The send side's partner is `busy-channel-pacing`; the budgets should sit comfortably above what a paced client
    sends, using the numbers from `burst-and-scale-numbers`. Test: the sandbox floods from one pretend player, and
    the others still flow and the panel stays drawn.

- **emote-stamps** (story, backlog, owner's art): stamps from our own graphics: emote faces of every race in WoW
  Forever (anime chibi and other styles), as a set of stamps beside the words. An addon can ship its own images:
  `QuestParty\media\stamps\<name>.tga` (32 bit with alpha) or `.blp`, square and a power of two (64 or 128
  pixels), drawn with the stamps' `texture` field, which already takes a whole path. Needs: the art (the owner's,
  made or commissioned), a conversion step (PNG to TGA) in `scripts/`, packaging that carries `media\`, and a
  client restart the first time (new files). One stamp per face, a plain id each (`e_orc_happy`); the picker
  stays one framed grid. Decided 2026-11-18: the GarrMission emblems and raid marks are out as stamps.

- **dock-polish** (story, later): the docked view (the magnetic dock's keys and drawers along the screen's edge) is
  OK but needs work; owner's list to come. Seen 2026-11-18: a drawer ("Discovered: Elder Rise") sits over the
  keys' column, and the keys show bare ! and ? icons rather than the rows' framed marks.

## Winning concept 0.3.5: the feed must look like this (2026-11-18, requirement)

`docs/concept-art/winning-concept-avatars-0.3.5.png` is how the feed must look (it replaces
`winning-concept-0.3.5.png`, which was not the winner: no rename, no ribbons). Each story says what done looks
like. Complexity, not time. Local planning entries; no Atlas cards yet.

- **row-avatars** (story, built 2026-11-18, owner to look): every row about a player starts with a round avatar in a gold ring on the left:
  for now the player's class (the game's round class icons, `UI-Classes-Circles`), the title and details beside it.
  Done: feed rows and quest progress rows show their player's class avatar. Complexity: medium (row layout).
- **row-mark-right** (story, built 2026-11-18, owner to look): the event's mark moves to the row's right edge, past the time, in a gold-edged
  square: the XP gem, a big gold ? or !, the map for a discovery, the party for a joined, the hammers for a
  skill-up; a level-up keeps its round gold crest with the number. Done: every row's mark on the right, centered,
  the same size. Complexity: medium (row layout, the quest marks as squares).
- **row-tints-by-kind** (story, built 2026-11-18, owner to look): each kind's row light, as in the concept: accepted a deep blue, complete a
  warm gold, level-up purple, joined blue, the rest charcoal, fading to dark on the right. Done: the concept's
  colors, in the theme data. Complexity: small.
- **player-avatars** (story, built 2026-11-18: race and sex faces when known, class otherwise; owner to look): the avatar becomes the player's own character (race and sex, then their
  look) once that is reliably known for everyone on the channel (the hello carries race and sex from 0.3.5; older
  clients do not). Until then, the class. Complexity: medium (portrait art per race and sex, fallbacks).
- **concept-scene-backdrops** (story, backlog): the concept's painted scenes in each row's right half (a kodo, a
  cougar, the place discovered, a quest's camp). Builds on `scenes-on-cards`; kills by creature family. Complexity:
  large (the art).

## Quests as a party, quieter feed, event sounds (2026-11-17, owner's request)

Written from the owner's description; the two screenshots that went with it did not come through, so look again
when they are pasted. Local planning entries; no Atlas cards yet.

- **quests-as-a-party** (story, built 2026-11-17, owner to look): in the Quest tab, a quest several of the party are on is shown as a real
  party doing it together: one card for the quest, with each member on it (portrait, name, their counts and bar)
  side by side, instead of a card per player. Shared quests (`shared-quest-glow`) lead; quests only one player has
  stay simple. Optimized to read at a glance: who is ahead, who is done, what is left.
- **fold-kills-into-quest-events** (story, built 2026-11-17, owner to look): a kill and its XP are often part of one moment: the kill that
  finishes an objective ("Done: 10/10"), or a quest handed in with its XP. Collapse them: the kill and XP rows that
  belong to a quest's "Done" or "Complete!" fold into it (shown as a detail, "+3 kills, +180 XP"), so the feed shows
  the event, not three rows. Kills and XP that belong to no quest event stay as they are. The XP bar and Fuel still
  count everything.
- **event-sounds** (story, built 2026-11-17, owner to listen: quest complete 23404, level up 46893, objective done 878): a sound for each of these, on everyone's client: quest complete, level up, and an
  objective done (a collection or kill count finished). Sounds as data (the game's own sound kits), following the
  volume setting (mute, soft, regular, loud); one sound per moment even when rows fold together, and none for old
  rows replayed or caught up.

## Party Fuel (2026-11-17, owner's request)

The 123 tab becomes **Fuel** ("Party Fuel"). Local planning entries; no Atlas cards yet.

- **fuel-tab-rename** (story, built 2026-11-17, owner to look): the tab is named Fuel; Achievements leave it (not a thing in this yet). The
  stats keep counting them, so they can come back.
- **fuel-numbers-fit** (story, built 2026-11-17, owner to look): totals no longer cut off ("74,3..."): short forms in the gauges (74.3k,
  1.2M), the full number in the tooltip.
- **fuel-vat** (story, built 2026-11-17, sliced into sections on click rather than separate vials, owner to look; fuel weights to tune): Fuel opens on one big red vat with a single number, the party's fuel: each kind of
  activity counted by a weight (data, `ns.StatKinds`). Clicking the vat separates it into the sub-fuel vials as now;
  clicking back pours them together again.
- **fuel-forever-per-channel** (story, built 2026-11-17, owner to look): Fuel is kept per channel and for good, not the last 7 days. What is
  saved now moves to the channel it was gathered on (the current one).
- **one-tab-per-player** (story, built 2026-11-17, owner to look): the party's heads (the side bar's tabs) show each player once, as the
  character they are on now. When a player comes back on another character, the old character's tab goes; their
  history stays. Needs a player id that spans characters: a random id made once per game account (account-wide
  saved variables) and sent in the hello. Older clients send none, so their characters still show apart.
- **feed-text-room** (story, built 2026-11-17, owner to look): feed card titles cut off far too soon ("Wildmane Totem Comp..."): the title
  stops a fixed 64 pixels short of the right edge, for the time, even when the time is "1m". Let the title run up to
  the time it actually has, and the detail line to the stamp button. The small hints on the right (the time, the
  stamp button) are too dim: brighten them.
- **fuel-gained-recently** (story, built 2026-11-18, owner to look): Fuel shows how much was gained lately: in the last hour, day and week, as
  well as all time on the channel. Days are already kept per player; the last hour needs finer tallies (by hour, or
  the recent gains themselves, kept a day). Shown on the vat (for example "+340 this hour", or a pick of hour, day,
  week and all time), and per kind when split.
- **xp-fuel-by-level** (story, built 2026-11-17, owner to look; everything else one for one, as the owner chose): XP gets huge at high level (a level is 7,600 XP at 10, 209,800 at 59), so
  Fuel counts XP by level, not raw: XP gained / XP to the next level at the gainer's level x (200 x level). A full
  level's worth is 2,000 fuel at 10 and 11,800 at 59: a straight-line ramp, not the game's steep curve. The
  requirement comes from the entry (maxXP) when it has one, else Forever's XP table (Classic's, community-compiled,
  checked against our recorded readings; data). At 60, XP adds no fuel. The feed and tooltips keep real XP. Kills,
  quests and skill-ups re-weighted to sit beside it. Complexity: medium (stats tally, data table, Fuel, saved
  tallies, tests; no protocol change).
- **kills-at-scale** (story, backlog): at the level cap and in dungeons, kills go way up. A client with kills on
  tracks every kill (turning Kills off in the gutter only hides the rows). If the channel's limits are hit, kills
  need cleverer debouncing or bundling (larger batches per creature, a per-minute summary, or a count only). Measure
  first with the sandbox's burst and scale runs (`burst-and-scale-numbers`).

## Quests together and stamps (2026-11-17, owner's request)

Five stories, in the order they are built. Local planning entries; no Atlas cards yet.

- **quest-row-titles** (story, built 2026-11-17, owner to look): a quest's feed row says "{name} Accepted" when taken and "{name} Complete!"
  when handed in, the quest's name first, in place of "Accepted: {name}" and "Quest complete: {name}".
- **quest-tab-rename** (story, built 2026-11-17, owner to look): the Party tab, which lists everyone's quests, is named **Quest**.
- **shared-quest-glow** (story, built 2026-11-17, owner to look): clicking a quest in the feed opens the Quest tab on it. Quests that you and
  someone else are both on (shared: in your quest log and on another player's card) glow, in the Quest tab and on
  their feed rows, so the overlap shows at a glance.
- **open-shared-quest** (story, built 2026-11-17, owner to look in game: which quest log the client opens): in the Quest tab, a shared quest (one in your own quest log) can be clicked to
  open it in the game's quest log, through the game's own open-quest call. Quests only others have do not open.
- **feed-stamps** (story, built 2026-11-17, owner to look in game: the stamp art, tilt and sound): a small icon on each feed card opens a picker of stamps: short KekChat-style
  celebrations (sayings or icons, from a ready-made list, never typed). Choosing one stamps that card for everyone
  on the channel, with a stamp animation and the stamp's own sound. Built on KekChat's rules: ready-made only,
  muting and the spam timeouts apply. Needs a message naming the card (its player, kind and time), so every client
  stamps the same one.

## Release (2026-11-17)

`main` holds 0.3.5 (`1e60a52`), fast-forwarded from `v023_chat`, not yet pushed or tagged. The owner's regular
install stays on the released 0.2.0 until 0.3.5 ships; the sandbox runs 0.3.5. Local planning entries; no Atlas
cards created yet.

- **push-main-035** (chore, done 2026-11-18): `main` pushed; the `v023_chat` and `side-quest` branches deleted
  (both held in `main`).
- **release-035** (story, done 2026-11-18): tagged `v0.3.5`, GitHub release with the packaged ZIP and the change
  list from CHANGELOG.md; the regular install runs it. Still open: the CurseForge upload (manual, as for 0.2.0).

## Bugs (2026-11-17)

- **flaky-party-of-20-test** (bug, fixed 2026-11-17: not flaky; a late message brought a player back after they left, and the test now checks what its title says): "in loopback a party of 20 plays for an hour without the network, and
  every player is seen" fails depending on the random seed (14 of 20 arrive). Make the run deterministic or the
  arrival check fair to the seed.
- **title-cut-at-narrow-width** (bug, built 2026-11-17, owner to look): at narrow panel widths the title ("Quest Party Sandbox") runs under
  the header buttons. Shorten or shrink it when the panel is narrow.

## Look and feel (2026-11-17)

- **scenes-on-cards** (story, backlog): draw the scene atlas (`docs/scenes.md`) behind feed cards, behind a
  Settings switch, so the placeholders can be seen in place; then paint the 16 scenes and build the atlas.
- **xp-strip-primary-palette** (idea, built 2026-11-18: one saved color per player for bars, rings and Fuel, owner to look): the party XP bars in the same primary palette as the 123 graphs, so
  a player is one color everywhere.
- **lab-results-review** (task, backlog): the owner's results from the prototype lab (3D creature, creature heads,
  fanfare, banners, stamps, dance) were never reported; decide what to build from them.

## Health and power (2026-11-17)

Built in 0.3.5: health and power over the channel under every XP bar.

- **vitals-on-party-cards** (story, built 2026-11-18 as vitals-on-active-players): health and power on each player's card in the Party tab, not only the
  XP strip.
- **vitals-for-pretend-players** (task, built 2026-11-18): the sandbox's pretend players send health and power, so a test
  party shows them and the message rate can be measured.

## Party state and sharing (carried from `docs/side-quest.md`, 2026-11-15)

From the side quest (code name for the side bar on the right: the party's heads and player cards).

- **card-lifetime** (story, backlog, B5): friends' quest cards go after a day without news. Needs the owner's word
  first; until then they stay until cleared (`ns.Timing.cardSeconds`).
- **burst-and-scale-numbers** (task, backlog, A4, E2, E3): take the send budget, and memory and time for 2, 8, 20
  and 50 players, in game with `/qps burst` and `/qps measure`, and write them into `docs/side-quest.md`.

## Later

- **party-minigames** (idea, tbd): light minigames for the party, which are what Party Fuel is spent on (multipliers,
  team pets and the like come from them). Designs to start from in `docs/side-quest.md`. Owner's intent
  (2026-11-18): Fuel is for fun, a side quest for playing the game: a very small incremental game or cosmetics, and
  reports for the data lovers. Each client counts its own Fuel from what it hears (never synced), so no anti-cheat:
  a player faking events only inflates their own slice, and mute handles anyone annoying.