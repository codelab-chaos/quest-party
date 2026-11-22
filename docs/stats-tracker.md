# Stats tracker (experimental, ideas)

Started 2026-11-21. Stats for stats' sake: a growing table of what each player
did, for reports, records and fun comparisons. **It has no effect on Party
Fuel**: Fuel keeps its own tallies (`stats.lua`, `data\stats.lua`) and its own
rules. This is a separate, experimental layer, off the critical path, that can
be switched off or thrown away without touching anything else.

## Principles

- **Per client, like Fuel.** Each client builds its own tables from what it
  hears on the channel. Your own numbers are complete (your client hears all
  of your events); a friend's are what you heard while you were both online.
  Nothing is synced. Designed as if there are no cheaters (see Fuel).
- **In memory, small, bounded.** Saved variables load whole at login, so the
  tables must stay small however long anyone plays:
  - **sparse:** a zero is never stored; a record holds only what happened;
  - **rolled up:** daily detail for recent days, then months, then years;
  - **naturally bounded breakdowns:** per creature, per zone, per profession
    (the world has a few thousand creatures; a player meets a few hundred).
- **Ids over names.** Keys are the game's ids where it gives them (an NPC id
  from a creature's GUID, a quest id, a map id), so they mean the same in
  every client language and two creatures that share a name stay apart. The
  name is kept once, beside the id, for display.
- **The additive convention.** Stats never have messages or requests of
  their own: they tag along on messages that already go out, as extra fields
  an older client ignores (a kill entry carries the killer's count for that
  creature; a presence carries a few totals). As where (`wm`), when (`w`) and
  away (`af`) already do. No new traffic, nothing to ask, nothing to abuse.
- **Fall back, never break.** Where the game hides an id (a secret value in
  an instance), the name is the key instead.

## The table

```lua
statsTracker[channel][player] = {
  days   = { [day]   = { k = 37, x = 1850, ... } }, -- the last 90 days
  months = { [month] = { ... } },                   -- then 24 months
  years  = { [year]  = { ... } },                   -- then for good
  mobs   = { [npcId] = { n = "Kobold Miner", k = 37, x = 1850, d = 1, t = 1795125540 } },
  zones  = { [mapId] = { n = "The Barrens", d = 2, f = 1795000000, ... } },
  records = { bestXpDay = { v = 41250, at = day }, streak = { v = 12, at = ... } },
}
```

Period counters (`days`, `months`, `years`) answer "how much, when". The
breakdowns (`mobs`, `zones`, `skills`) answer "which", all time, never per
day: days times creatures would explode. Together they answer both "kills
this week" and "favourite target".

### Size

With ~25 counters and the rollup, a player is at most ~120 period records:

| Layout | 10 busy players |
|---|---|
| named fields, every counter written | ~1.6 MB in memory, ~550 KB on disk |
| sparse (zeros not stored) | grows with what happened; near nothing when idle |

Lua keeps each distinct string once, so names as keys cost about what ids do
in memory; ids are for correctness (language, uniqueness), not size.

## What to track

| Counter | From | Notes |
|---|---|---|
| kills, XP by source (kill, quest, discovery) | feed entries | have them |
| kills per creature (NPC id) | `PARTY_KILL` (dead unit's GUID) | secret when unit identity is restricted (instances): fall back to the name |
| quests done, accepted, dropped | feed entries | have them |
| levels, skill-ups per profession, professions learned | feed entries | have them |
| deaths, by zone and by what killed you | feed entries; killer from the game if it says | killer may not be readable |
| discoveries, zones visited | feed entries, location (`wm`) | have them |
| distance travelled | location samples (`wm`, `wx`, `wy`) | rough: straight lines between samples |
| active time and AFK time, sessions | your own client (`collectors\afk.lua`) | yours only: a friend's comes from what you heard |
| stamps given and received, KekChats sent, effects played | channel messages | have them |
| records: best XP day, most kills in an hour, longest streak | derived as counters change | stored, not recomputed |
| gold | the game | probably secret on Forever, like health: check first |

## Constraints (checked against the Forever client, 2026-11-21)

What an addon may read decides what can be tracked:

| Thing | Readable? | How |
|---|---|---|
| Kills by creature | yes, outside restricted moments | `PARTY_KILL` (attacker and target GUIDs; the NPC id is in the target's). Secret "when unit identity is restricted" (instances): then the creature's name is the key |
| The full combat log | no | `COMBAT_LOG_EVENT_UNFILTERED` is restricted for addons |
| Jumps | yes | the game's `JumpOrAscendStart`, listened to after it runs (`hooksecurefunc`); swimming, flying and flights do not count |
| Distance | yes | your world position (HereBeDragons, already shipped) every second; a step longer than 60 yards in a second was a teleport (hearth, portal), not travel; a flight path counts apart |
| Money | yes | `GetMoney` is not secret: each change is money in or out |
| Time played, AFK | yes | your own client's clock, with the AFK flag |
| Health, power | no (health is secret) | not tracked |
| Your speed | sometimes secret | not needed |

Measured stats (time, distance, jumps, money) are your own only: a friend's
client measures theirs, and nothing is sent yet (phase 3, by the additive
convention). Everything counted from feed entries is kept for everyone this
client hears.

## Phase 1, built (2026-11-21)

- `data\tracker.lua`: every stat as data (id, category, kind of number,
  label) and one formatter per kind (count, XP, duration, distance in yards
  and miles, money in gold, silver and copper).
- `tracker.lua`: the table, sparse, with the rollup (90 days, then 24 months,
  then years); counted from the feed, measured by your client; your kills by
  NPC id, named from the kill that follows; `Tracker:View` turns a player and a
  period (today, week, all) into sections of rows, data driven.
- `ui\tracker.lua`: a small window, `/qp tracker`: whose (you first, then
  everyone with numbers), today, week or all time, and your most killed.
- **Always on**, with no switch: it only counts, locally, and is part of Quest Party.

## Comparing across the channel

Each client only has partial numbers for others, and asking a client for its
numbers is a request (the protocol avoids those: they can be abused). Ideas
that need no requests:

- **A number rides along.** A kill entry already goes to everyone; it could
  carry the killer's **all-time count for that creature** (one small number).
  Every client then compares that with its own count locally. No new
  messages, no requests.
- **Milestones travel, totals do not.** When a counter crosses a milestone
  (1st, 10th, 100th, 1,000th of something), the entry says so; everyone can
  react to it, nobody has to ask.
- **A summary in the presence.** A few headline totals (level, all-time
  kills, quests done) in the presence every few minutes: cheap, and enough for
  a channel leaderboard.

## Trivia and contrasts (later)

A crab kill could set off "Danimopets just killed their 100th Coastal Crab;
Mcdouble is on 340". Fun once; noise the tenth time. Rules to keep it rare:

- **Milestones only:** the 1st, 10th, 100th and 1,000th of a creature, a quest
  count, a profession step; never "another one".
- **Once per pair and thing:** never the same comparison between the same two
  players about the same thing again.
- **A daily cap**, per channel, and a cooldown after one shows.
- **Local and quiet:** a trivia row is made on each client from what it
  knows; it is not sent, and it is its own filter icon (off with one click).

## Reports

- **You:** today, this week, all time; XP per hour (active time only);
  favourite creatures and zones; records.
- **The channel:** leaderboards from what each client knows (labelled as
  such), and from presence summaries once those exist.

## Phases

1. **Grow the table.** Track the counters above into `statsTracker`, sparse,
   with the rollup; kills keyed by NPC id from `PARTY_KILL`. No UI beyond
   `/qp tracker`. Always on: local, never sent.
2. **The You page** in the Fuel tab: today, week, all time, records.
3. **Numbers on the wire:** the per-creature count on kill entries, milestones,
   a presence summary. Then channel comparisons.
4. **Trivia rows**, under the rules above.

## Open questions

- Which counters matter most for the first report?
- Should friends' tables be kept at all, or only yours, until phase 3?
- How long is "recent" for daily detail: 90 days, or less?
- Is gold readable on Forever?
