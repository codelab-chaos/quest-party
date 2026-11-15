# Side quest

The code name for the next Quest Party prototype, worked on the `side-quest`
branch. It explores two things:

1. **Channel party state:** what Quest Party knows about each player on the
   channel, how it stays current, and when it is forgotten.
2. **Channel party chat:** talking to the party from inside Quest Party.

The channel is the party, so these are two views of the same room.

Started 14 November 2026. Nothing here is built yet.

## Principles

Everything below follows one pipeline, the same at every stage:

```
collectors -> protocol -> resolvers -> state -> view models -> components
```

1. **The protocol is flexible and stable.** Messages are flat key and value
   fields. New fields and new kinds are added, never repurposed; unknown
   fields are ignored and unknown kinds become the generic card (0.1.3).
   Every message stands alone, and each piece of state has a key, so the
   latest for a key wins.
2. **Resolvers fail early and safe.** A message is checked as it arrives,
   against its definition (`requires`); what cannot be read becomes the
   generic card or is dropped, never an error in the panel. A resolver that
   fails is caught, and the rest of the panel goes on.
3. **State is composable, partial and async.** A player's picture is slices
   (hello, quests, gear slots, stats), each with its own key, owner, time
   and lifetime. Any slice can arrive alone, late or out of order, and
   updates only itself; a per-player counter keeps an old message from
   replacing a newer one.
4. **Rendering follows the same convention.** Each slice has a definition
   (like `data\feed-types.lua` for feed rows) that a view model turns into
   plain data for a small, fixed set of components: feed row, progress row,
   bar, head tab, card tab, item slot. Components draw data and never read
   state or messages.
5. **Components are built for the busiest channel.** A big party must not
   make the panel slow: lists draw only the rows in view, redraws are
   coalesced (many messages, one redraw a frame or less), lists have caps,
   and the head tabs scroll when full. The sandbox scale tests are what
   checks this.

Where the code stands: the feed already works this way (feed types as data,
the resolver with its generic card, merge rules, latest-only sends). Party
state, cards and items are to be built the same way, not added beside it.

## 1. Channel party state

### Today

The state is ad hoc:

- The hello carries level, zone and XP.
- Quest messages fill friends' quest cards.
- A player list remembers everyone ever heard from.
- Nothing expires. A friend's quest card is removed only when you see them hand
  in or abandon the quest, so cards from quests handed in while you were offline
  stay forever, as does everyone in the player list.

Measured on 14 November: the saved file was 89 KB, of which the feed (capped at
200 rows) was 41.6 KB, the message log (capped at 200) 32.4 KB, quest cards
10.3 KB and the player list 0.4 KB. Small, but cards and players have no limit.

### Aim: one picture per player, owned by that player

| Part | What it holds |
| --- | --- |
| Who | Name, class, Quest Party version |
| Presence | In the channel, active, idle, gone |
| Progress | Level, XP, zone |
| Working on | Quests underway |
| Recent | The last notable thing, such as a death or a level-up |

Each player's own client is the only authority on their picture. Everyone
else's copy is only ever replaced by what that player sends.

### Presence from the game

The Forever client exposes the channel's roster
(`C_ChatInfo.GetChannelRosterInfo`): each member's name, whether they are the
owner or a moderator, and their GUID, with `CHANNEL_ROSTER_UPDATE` when it
changes. Quest Party can use it to notice when a player leaves the channel
(logging off leaves every channel), but the party itself is only Quest Party
players. See Party members.

To verify in game: that the roster fills in for a custom channel without the
game's own channel window being open.

### Lifetimes

- A friend's quest card expires after a day without an update.
- A player who is gone (left the roster, or not seen) drops off after a week.
- State is saved across reloads, and shown as stale until the hello exchange
  refreshes it, so the panel is not empty at login.

### Order

A per-player counter on each message, so an old or replayed message can never
overwrite newer state. Cheap, and it matters more as more state flows.

## Party members (the first feature)

Chat is secondary. The first thing to build on the state is a view of the
people in the party. Rough design, 14 November 2026.

### What the owner wants

1. **A welcome** when another player handshakes with the channel (their hello
   arrives): a feed row and a chat line, "Tombert Roams joined the party".
2. **A headshot tab per player** down the right edge of the Quest Party window.
   Only Quest Party players: the party is the people whose Quest Party talks on
   the channel, not everyone in it.
3. **Clicking a head opens that player's card:**
   - who they are: class, race, level, zone, XP bar, online or away
   - the quests they are on, with their progress
   - the quests you have in common, with both of your progress side by side
   - XP gained over a session or a time period (today, this week)
   - the items they have equipped
4. **Tunable by each player:** what they share, and how much. Leveling and the
   level cap want different things.

### What the game tells us, without their Quest Party

Checked in the Forever client's API documentation:

| Information | Source | Works for |
| --- | --- | --- |
| Name, in the channel, owner or moderator, GUID | Channel roster (`C_ChatInfo.GetChannelRosterInfo`, `CHANNEL_ROSTER_UPDATE`) | Everyone in the channel |
| Class, race, sex | `GetPlayerInfoByGUID(guid)`, with the GUID from the roster | Everyone in the channel |
| A headshot icon | The game's race portraits: atlas `raceicon128-<race>-<male or female>`, from race and sex above (the client's own `GetRaceAtlas`) | Everyone in the channel |
| Level, zone, online, away, busy | Friends list (`C_FriendList.GetFriendInfoByIndex`), guild roster | Only your friends and guildmates |
| Level, class, zone | `/who` (`C_FriendList.SendWho`) | Anyone online, but the server throttles it hard: one lookup at a time, now and then |
| A live 3D portrait, equipped items, talents | `SetPortraitTexture(unit)`, `NotifyInspect(unit)` | Only someone grouped with you or nearby, as a unit |

Since every tab is a Quest Party player, the simplest headshot needs none of
the lookups above: each player's hello carries their own race and sex
(`UnitRace("player")`, `UnitSex("player")`), and the tab shows the matching
race portrait with a class-colored ring. A live portrait of their actual
character needs them to be a unit (grouped, targeted, nearby), and cannot be
sent or saved.

### What only their Quest Party can tell us

Quests and their progress, XP and session XP, equipped items from anywhere,
professions, deaths, and their stats. These travel over the protocol.

### How data travels: on the channel, like radio

The channel is broadcast like radio: every message reaches every client tuned
in at that moment, and nothing is kept. Whoever was not listening missed it,
which is why a hello brings answers with everyone's current state.

| Way | When | Holds |
| --- | --- | --- |
| **Stream** | As it happens | Hello (level, class, race, zone, XP, version), feed events, quests underway, a gear slot that changed |
| **Catch-up** | Answering a newcomer's hello | Current state: quests underway, the full gear set |
| **Request** | Someone opens a card and has nothing recent | The one player asked answers, on the channel |
| **Whisper** | Only for friends-only categories | The same answers, to each allowed friend |

Answers go on the channel, so one answer serves everyone: every client hears
it and updates that player's card. A client that heard a recent answer does
not ask; one that hears someone else's request waits for that answer instead
of sending its own. Ten people opening Tombert's card cost him one answer.

Size is not the issue: a full card is about five messages once, the feed
about 225 messages an hour per player. Every client stores every answer it
hears, so the scale tests check that memory.

Messages split by meaning, not bytes: each stands alone (one gear slot or a
few, one quest), and the latest for a slot or quest wins, so nothing needs
reassembling and a lost message loses only its piece. Catch-up goes at low
priority, spread over a few seconds; hellos, level-ups and deaths go first.

### The player card

Clicking a head opens that player's card. The card has tabs of its own, one
per kind of detail, so each stays readable and each is fetched only when
opened:

| Tab | Shows | Comes from |
| --- | --- | --- |
| Overview | Race portrait, class, level, zone, XP bar, online or as of when, XP this session, today and this week | The hello and broadcasts, plus stats on request |
| Quests | Their quests with progress, and the quests you have in common side by side | Broadcast quests, plus the full list on request |
| Items | Their equipped items, laid out like the game's character window | Streamed changes, full set on catch-up or request |

More tabs later (professions, achievements) are just more entries in the same
data table, and a tab a player does not share shows as unavailable.

### The Items tab: their character window

Each equipped item in its own slot, positioned as on the game's character
window, so it reads at a glance:

```
 Head                       Hands
 Neck                       Waist
 Shoulder                   Legs
 Back       [ portrait ]    Feet
 Chest                      Finger
 Shirt                      Finger
 Tabard                     Trinket
 Wrist                      Trinket
        Main hand  Off hand  Ranged
```

These are the Forever client's own slots (its character window has Head,
Neck, Shoulder, Back, Chest, Shirt, Tabard, Wrist, Hands, Waist, Legs, Feet,
two Fingers, two Trinkets, Main hand, Off hand, Ranged and Ammo). The layout is
data, one entry per slot with its column and row, so it is easy to adjust.

- **Our own compact control, kept very simple first:** the Forever client's
  inspect window (`Blizzard_InspectUI`) confirms the layout (left, right and
  weapon slot arrays around a model), but Quest Party does not inherit it or
  copy its weight. A first version is a small grid of plain buttons placed
  from the slot layout data, and it grows only as opinions form. Game parts
  worth borrowing when wanted, all global: `SetItemButtonQuality` for the
  quality border, `C_PaperDollInfo.GetInventorySlotInfo` for empty slot art.
- **Each slot:** the item's icon with its quality border; an empty slot shows
  the game's empty slot art.
- **Hover:** the game's own item tooltip for that exact item, enchant and
  random suffix included ("of the Bear"), from the item string, which works
  for any item, not only ones you have seen.
- **Shift-click:** links the item in chat, like any item.
- **On the wire:** per slot, the item ID, enchant and random suffix, about 14
  characters each, so a full set is two messages; a change is one slot.
- **Remembered:** with the remember option on, the last set is kept with the
  player's state, so it can be checked while they are offline (to make them
  better armor), and the tab says as of when.
- **The middle:** the race portrait to begin with. A 3D model wearing their
  items would be lovely, but the client documents no way to set another race
  on a model (only `TryOn` and `Undress` on your own), so that is an idea to
  test, not a plan.

### Quests in common

Compare quest IDs. This needs their whole accepted list, not only the quests
underway that are broadcast now, so it comes with the card request. Shown as
"Rear Guard Patrol: you 3/8, Tombert 5/8".

### Session and time-period XP

Each player's own client knows: XP since login and per hour, and the daily
tallies already kept by the stats (debug only today) for today and this week.
Sent with the card.

### Permissions: each player decides what they send

Receivers can never pull more than a player shares. The defaults are what
makes the shared state work: someone who installs Quest Party and joins a
channel is assumed willing to share what the party view needs. Each player
can then restrict any category.

| Category | Holds | Default |
| --- | --- | --- |
| Basic | Level, class, race, zone, XP | Shared with the channel (the party view needs it) |
| Progress | Quests and their progress, deaths | Shared with the channel |
| Gear | Equipped items | Shared with the channel: changes streamed, full set on catch-up or request |
| Stats | Session and weekly XP, kills, quests | Shared with the channel, on request |
| Professions | Skills and levels | Shared with the channel, on request |

Each category can be restricted to Off, or Friends and guild only (checked
against your friends list and guild roster, and whispered, since anything on
the channel reaches everyone). Requests are answered only for
players in the channel, and at most once a minute per player.

### Leveling and the level cap

A sharing profile picks what is streamed:

- **Leveling:** XP, quests, zone and deaths streamed; gear on change.
- **Level cap:** item level and gear, professions and achievements matter
  more; XP drops out.

Chosen by level automatically, and the player can override it.

### Throttling, and what is too much

- **The limits:** messages of 255 characters at most; per addon, a burst of
  about 10 and then about one a second; heavy traffic on several prefixes at
  once can get a client disconnected; addon messages are blocked during
  encounters, Mythic+ and PvP matches.
- **Only the sender's budget is spent:** receiving many players' messages
  costs nothing against yours.
- **Budget per player:** stream under one message a second while active
  (merging runs keeps it well under), and an answer of about five messages
  spread over a few seconds.
- **Too much:** anything per second or per step (positions, health, every
  kill to a big channel). Positions also fall under the game's restrictions.
- **The numbers** (10 messages per prefix, earning back 1 a second) are from
  community documentation, which says the server can change them; the
  sandbox measures the real budget on Forever with a burst test.

### No storms: the rules

A broadcast storm is messages causing messages that cause more. Quest Party
avoids it with a few rules, kept simple:

1. **One request, one answer, from one player.** Only the player asked
   answers. An answer never causes a request, and nothing chains.
2. **Heard answers count for everyone.** A recent answer or a pending request
   from someone else stops a client from asking.
3. **The hello is the one message many answer**, so each answer waits a
   short random moment, and each client answers a given newcomer once a
   session.
4. **Per-player limits** on both ends: a client answers a given requester at
   most once a minute, and ignores anyone sending past a sane rate.
5. **Derive, do not ask.** Anything that can be worked out from messages
   already heard (session XP, challenge progress) is worked out locally.

### The tabs: arriving, leaving, remembering

- **Order:** tabs stack top to bottom in the order players first show up in a
  session (their first hello or event), so the list does not reshuffle.
- **Arriving:** a new player's hello adds a feed row ("Tombert Roams joined the
  party"), a chat line, and their tab at the bottom.
- **Leaving:** the tab is removed when they log off (they leave the channel,
  seen in the roster or the channel's leave notice) or after a stretch with no
  activity at all from them (a timeout, tunable; a hello repeats while they
  play, so a quiet player is not dropped).
- **Remembering (an option):** keep the last state of players who have left,
  shown as greyed-out tabs, so you can still open their card: for instance, to
  see their gear and level and make them better armor while they are offline.
  The card says how old it is ("as of 2 hours ago"). Without the option, a
  player's tab and card go when they leave.

The remembered state is the "last player state" kept in the saved file, and
it follows the lifetimes above: dropped after a week without being seen.

### Open questions for party members

Answered 14 November 2026:

- Only Quest Party players get tabs.
- Defaults share what the party state needs; each player can restrict.
- Tabs stack in arrival order, go on log-off or a no-activity timeout, with
  an option to keep the last state of players who left.
- Gear is every item, laid out like the character window, on an Items tab of
  the player card.

Still open:

1. How many tabs fit down the window before they scroll (the panel is about
   eight heads tall)?

## Testing: pretend 0.1.3 players

Party members need other players to arrive, stream, answer card requests and
leave. Testing that with real friends is slow, so the emulator grows into a
pretend peer.

### What exists today

- **The emulator** (`emulator\script.lua`, `/qp test`): scripted pretend
  players send feed entries over the real channel, marked with the player they
  stand for (`as`), and are shown when the server echoes them back. Other
  clients ignore them. Since the resolver work, their entries carry summaries
  like any 0.1.3 entry.
- **The replay** (`/qp replay`): reads the saved incoming messages again, all
  at once. Real traffic, but only what friends sent (Tombert's is 0.1.2).

### What a pretend peer is missing

| A real 0.1.3 player | Emulator today |
| --- | --- |
| Hello and ACK with version, level, XP (and soon race and sex) | None; party bars use a debug-only shortcut |
| Quest messages that fill quest cards | None |
| Hello repeats while playing | None |
| Logs off (leaves the channel) | Never leaves |
| Answers card requests (items, stats, quest list) | Nothing to answer with |

### Plan

1. **Pretend peers speak the whole protocol.** Each persona sends its hello
   when the script starts, repeats it, sends entries and quest messages, and
   leaves when its script ends, all marked `as` and over the real channel.
   Personas get race, sex, XP and an equipped set in the script data, and the
   emulator answers card requests for them. The party view then never needs
   a debug shortcut: it sees pretend players exactly as real ones.
2. **Record and play back a real 0.1.3 stream.** Your own client is a 0.1.3
   player: a debug recording of what you send (the log's "out" records, with
   their times) can be played back as a persona, at its real pace or faster.
   That gives a realistic stream (real kills, quests, merges) without a
   second account. The log keeps 200 records today; a recording would want
   its own, debug-only and larger.

Both stay debug only, as now.

### QuestPartySandbox: a second copy as the other player

Instead of growing the emulator inside Quest Party, a second copy of the addon
can be deployed under another name, `QuestPartySandbox` (its AddOns folder,
packaged as `QuestPartySandbox.zip`, titled "Quest Party Sandbox"), into the
same game, on the same character. Built from the same source by the
packaging step, never a separate copy of the code. It is a separate addon with its own code, memory and
saved variables, so it can hold and lose state freely without touching yours.
Its stream comes from a recording or a script instead of your play, and it
speaks the real protocol over the real channel.

What makes it work:

- **Its own names.** A copy collides on only a few global names: the saved
  variables (`QuestPartyDB`, `QuestPartyCharDB`), the slash commands, one
  popup, two frame names (`QuestPartyPanel`, `QuestPartyListener`) and the
  compartment function. A sandbox build renames them (`QuestPartySandboxDB`,
  `/qps`, `QuestPartySandboxPanel`);
  the addon's own modules are already private to it.
- **Its own identity.** Both copies send as your character, and each client
  drops its own messages (`ns.IsMe` in `comms\transport.lua`). So the copy
  marks every message with the player it plays (`as`, already on emulator
  entries, extended to hello, answer, quest and card messages), and your copy
  accepts a marked message from yourself as that player, in debug only.
- **Its own source.** Collectors off (it must not mirror your play); the
  stream comes from a recording, such as the 2 hours of your "out" records in
  the saved log, or a script.

Benefits over an emulator inside the addon: real isolation (separate memory,
saved state, reloads), the real code path end to end, and the sandbox's code can
be a different build from yours, so a new version can talk to the one before
it. Only builds that know `as` can be the sandbox, so 0.1.3 onward, not 0.1.2.

Costs: both copies share your character's send budget, so a fast replay must
stay under the throttle; and nobody else should see sandbox traffic, so other
clients keep ignoring marked messages, as they do today.

### Scale tests: a procedural party of 20 or more

The sandbox can wipe itself and re-run a loop, and it can make up a whole
party: fantasy characters, each with a race, class, level and play style,
playing events from a model built on the real session's rates. The question
it answers: what has to be constrained for Quest Party to stay smooth at 20+
players, and what users need to prune.

**Two modes, because the send budget does not scale:**

| Mode | How messages travel | For |
| --- | --- | --- |
| Channel | Over the real channel, marked `as`, to your copy | Realism with a few players: the real server path, the real throttle |
| Loopback | Straight into the sandbox's own receive path, no network | Scale: 20, 50, 100 players, at real pace or faster |

The real session sent about 225 messages an hour per player. Twenty players
are about 75 a minute, over the roughly one a second one character may send,
so a big party cannot come from one character over the channel. It does not
need to: in a real channel each player sends only their own messages, so the
cost that grows with party size is on the receiving side (memory, drawing,
handling), and loopback measures exactly that. The sandbox's own panel is the
thing under test.

**Procedural, repeatable:**

- A seed makes the party: names, races, classes, levels, zones. The same seed
  gives the same party and the same run, so a change can be compared before
  and after.
- Event rates per profile (leveling: kills, quest progress, XP, skill-ups;
  level cap: different mix), taken from the recorded session, with arrivals
  and log-offs so tabs come and go.
- Commands: start with a seed and a party size, set the speed, wipe, re-run.

**Measured, per run, at sizes 2, 8, 20, 50:**

- Memory: `GetAddOnMemoryUsage`, which is per addon, so the sandbox's own use
  is clean of yours.
- Time: `C_AddOnProfiler` and `debugprofilestop` around receiving and drawing.
- Saved file size after a run, and counts: feed rows, quest cards, players,
  log records.
- Messages a minute in, and how many merged.

**What it tells us to constrain**, with today's state as the starting point
(feed capped at 200 rows, log at 200, quest cards and players uncapped):

- quest cards per player, and in total
- tabs shown, and how long gone players are remembered
- the feed cap at larger sizes, and whether a busy party needs more merging
- how often the panel redraws while a lot is arriving

### Pruning: giving users control of the memory

Two ways, both working on the same data:

- **Options buttons** in Quest Party: forget players not seen for a while,
  clear friends' quest cards, clear the feed (exists today as `/qp clear`),
  clear the message log. Each shows how much it holds before you press it.
- **A script in the repo** that prunes the saved file with the game closed,
  for a file that has grown before the options exist, or for bulk cleanup.

The scale tests set the defaults; pruning is for what defaults do not catch.

## Party minigames (last priority)

Ideas only, for later: fun the party can make for itself, between players of
different levels, leveling apart or doing dungeons together.

### Fair across levels

A level 12 and a level 30 cannot race on raw numbers, so challenges measure
things that are fair at any level:

- **Percent of a level:** XP as a share of the level being worked on ("most
  of a level gained tonight").
- **Counts:** quests turned in, objectives done, zones discovered, skill-ups.
- **Kills that count:** only creatures worth XP to the player who killed them.
- **Personal bests:** beating your own last session, not each other.
- **Together:** shared goals the whole party adds to.

### Kinds of minigame

| Minigame | How it plays |
| --- | --- |
| Member-made challenge | A player posts one: a goal, a time limit, who is in ("first to turn in 5 quests", "10 skill-ups by 22:00") |
| Bounty | A player asks for something ("5 Linen Cloth", "kill the rare in Duskwood"); someone claims it and it shows as done |
| Party goal | Together: "the party turns in 30 quests tonight", one shared bar |
| Bingo | Each player gets a card of event squares (a ding, a death, a discovery, a rare, a skill-up); the feed fills them in |
| Scavenger hunt | Discover a list of zones or subzones, with discovery events as proof |
| Streaks | Most quests without dying, longest night without a death |
| Dungeon run | A run's scoreboard: kills, deaths, time, from the group's own events |
| Predictions | "Tombert dings before 23:00?", a vote, settled by the ding row |
| Gifts | A crafted item for a party member, tied to the gear card ("made Tombert a better chest") |

### How it stays light

Most minigames need almost no new messages, because the feed already carries
the evidence: kills, quests, XP, deaths, discoveries and skill-ups.

- **Posting a challenge:** one message from its maker with its rules as
  data (goal, measure, time limit). Joining: one message from each player.
- **Progress:** each client works it out from feed events it already hears,
  by the same rules, so every client shows the same standings with no
  progress messages.
- **The result:** each client settles it the same way; the maker's client
  posts the final result as a feed row, so latecomers see it.
- **The storm rules above apply:** a challenge never causes requests, and
  catch-up for a newcomer includes open challenges like any other state.

Every minigame is a data definition (measure, goal, fairness rule), so new
ones are new entries, not new code.

## 2. Channel party chat

### Options

| Option | Who sees it | Catch |
| --- | --- | --- |
| A. Show the channel's own chat in Quest Party | Everyone in the channel, with or without Quest Party | Read-only on its own |
| B. A chat box in Quest Party that posts to the channel | Same | Typing and pressing Enter is a key press, which is what the game requires to post to a channel. Expected to work; test in game |
| C. Hidden Quest Party-only chat, as addon messages | Only Quest Party users | Not in normal chat at all; leaves out friends without the addon |

Recommendation: A and B. The channel's real chat, shown and typed inside Quest
Party. No new protocol, and it includes friends without the addon.

### Where chat lives

A Chat tab of its own, and optionally mixed into the All feed, so
"Tombert: lol" sits right after "DING!! Tombert reached Level 15", like a social
feed.

### A fun extra

A "gz" button on level-up rows that posts "gz Tombert!" to the channel. A click
counts as a key press too.

### Limits

- In dungeons the game hides chat text from addons, so Quest Party's chat view
  goes quiet there. The game's own chat window still works.
- Messages are capped at 255 characters, and the game's chat throttles apply.

### What we already know from the client

- Reading the channel's chat works: Quest Party read it during the first
  channel tests.
- An addon posting chat to a channel on its own, with no key press, is refused
  ("Interface action failed because of an AddOn"). A post made on a key press
  went through (`/qp post`, 13 November). Patch 8.2.5 (2019) made SAY, YELL and
  CHANNEL chat require a hardware event.

## Evaluation

Reviewed 14 November 2026, before building.

**Strong:**

- One pipeline for everything, already proven by the feed and the resolver,
  so the new work extends what exists instead of adding beside it.
- The protocol changes are additive: race and sex, a counter, the `as`
  marker on every kind, gear slots, requests. Older 0.1.3 clients show what
  they do not know as the generic card.
- The sandbox makes every later step testable in game without a second
  account, and the scale tests turn "will it be smooth" into numbers.

**Risks:**

- **The sandbox's identity.** Both copies send as one character; everything
  rests on the `as` marker being honoured by your copy and ignored by
  friends' copies. It must be built and tested first.
- **The send budget is shared** by both copies of one character, so channel
  mode stays small and scale runs use loopback.
- **Scope.** Party members alone is state, protocol, tabs, a card with three
  tabs, gear and sharing controls. The backlog below keeps each step small
  and shippable.

**To verify in game,** each in the step that needs it:

- two addons on one prefix both receive the channel's messages, including
  their own;
- the real throttle on Forever (a burst test from the sandbox);
- the channel's leave notice, or roster, when a member logs off;
- the race portrait atlas names on Forever (`raceicon128-<race>-<sex>`);
- item tooltips from item strings for items never seen.

## Backlog

Sandbox first: each step after it is tested against pretend players in game.
Every step ships on `side-quest` with tests; IDs are for reference.

### Status, 15 November 2026

Built on `side-quest`, with tests (158 Lua, 6 Python):

- **A1 to A4 done:** the sandbox build, the `as` marker on every kind
  (`comms\origin.lua`), the recorded session (`sandbox\recording.lua`) and the
  burst test (`/qps burst`). The burst numbers are still to be measured in game.
- **B1 to B4 done:** `n` on stateful messages, race and sex in the hello, one
  calm answer per newcomer, presence every 5 minutes, silent players dropped.
  **B5 partly:** players go after a week; friends' cards are still kept until
  cleared, as decided for 0.1.2 (a test holds that), so a day's lifetime for
  cards needs the owner's word first (`ns.Timing.cardSeconds`).
- **C1 to C8 done:** welcome rows, heads, the card with Overview, Quests and
  Items, remembered players, session and weekly XP, gear streaming.
- **D1 done:** requests, answered on the channel with the storm limits.
  **D2 and D3 not started:** friends-only sharing (whispers) and level
  profiles. Off works today through the switches (Share my gear, Quests,
  Deaths, Professions).
- **E1, E2 and E4 done:** loopback, the procedural party, `/qps measure`,
  Forget buttons and `scripts/prune-saved.py`. **E3 partly:** the list
  already draws only rows in view; redraws are now coalesced. Scale numbers
  are still to be taken in game.

Not yet seen in game: every frame added (heads, card, Items tab, Forget
buttons) and the sandbox itself.

### A. Sandbox (first)

| ID | Step | Done when |
| --- | --- | --- |
| A1 | Sandbox build: the packaging step also builds `QuestPartySandbox` (renamed saved variables, slash command `/qps`, frame and popup names, title) with a deploy target | Both addons load side by side, each with its own saved file |
| A2 | Identity: the `as` marker on every message kind; your copy accepts marked messages from yourself as that player, in debug only; friends' copies ignore them; the sandbox's collectors are off | A pretend player's hello shows them as a peer in your copy |
| A3 | Recording: your 75 "out" records from the saved log kept as a test fixture; the sandbox plays a recording as a persona, at real pace or faster | Your 2 hour session replays into your copy as another player |
| A4 | Burst test: the sandbox measures the send budget on Forever | The real numbers are written into this document |

### B. State foundation

| ID | Step | Done when |
| --- | --- | --- |
| B1 | Per-player counter on every message; the latest for each state key wins | An old or replayed message never replaces newer state |
| B2 | Player state as slices (hello, quests, gear, stats), each with key, time and lifetime | Slices update alone, in any order |
| B3 | Hello adds race and sex; answers to a hello wait a random moment; one answer per newcomer a session | 20 sandbox peers arriving cause no burst |
| B4 | Leaving: log-off from the channel's notice or roster, plus a no-activity timeout | A pretend player's log-off removes them |
| B5 | Lifetimes: friends' quest cards after a day, players after a week | Old state goes without user action |

### C. Party members

| ID | Step | Done when |
| --- | --- | --- |
| C1 | Welcome: a feed row and a chat line on a new player's hello | |
| C2 | Head tabs: race portrait, class ring, arrival order, gone on log-off, scroll when full | |
| C3 | Player card with tabs; Overview: level, zone, XP bar, as of when | |
| C4 | Remember option: last state of players who left, greyed out | |
| C5 | Quests tab: their quests, and quests in common side by side (full quest list in catch-up) | |
| C6 | Stats on Overview: session, today and week XP, worked out locally | |
| C7 | Gear: a collector for equipped slots, changes streamed, full set in catch-up | |
| C8 | Items tab: compact slot grid, item tooltips, shift-click links | |

### D. Sharing controls

| ID | Step | Done when |
| --- | --- | --- |
| D1 | Requests: one request, one answer on the channel; heard answers and pending requests stop asking; per-player limits | The storm rules hold in a 20 peer sandbox run |
| D2 | Categories: Off or Friends and guild only per category, whispered for friends-only | |
| D3 | Leveling and level cap profiles, chosen by level | |

### E. Scale and pruning

| ID | Step | Done when |
| --- | --- | --- |
| E1 | Loopback mode and a procedural party from a seed, with event rates from the recording | 20 and 50 player runs repeat exactly |
| E2 | Metrics per run: memory, time, counts, saved size | Numbers for 2, 8, 20 and 50 players |
| E3 | Components for a busy channel: rows in view only, coalesced redraws, caps | 50 players stay smooth |
| E4 | Pruning: options buttons, and a repo script for the saved file | |

### F. Later

- Channel chat (show and type the channel's chat, the "gz" button).
- Party minigames.

## Open questions

1. Chat visible in the channel (A and B), or Quest Party-only (C)?
2. Chat in its own tab, mixed into the feed, or both?
