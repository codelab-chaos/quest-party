# Companion (vision, 2026-11-21)

A WoW Forever helper outside the game (an MCP or a desktop app) that reads
what Quest Party knows, plans with a WoW database, and hands the plan back to
the game. Speculative: nothing here is built. It grows from the stats tracker
(`docs\stats-tracker.md`) and a journey log.

## The walls

- An addon has no network and writes no files except its saved variables,
  which the game writes on `/reload` and on logout. Nothing is live: help comes
  per reload, not per event.
- Reading files the game writes is fine (Warcraft Logs, TSM's desktop app);
  automating the client is not. The companion advises and shows; the player
  plays.

## The loop: two reloads

1. **Out.** `/reload` (or logout) writes Quest Party's saved file: bags, bank,
   gold, quests, location, the stats tracker, the journey. The companion reads
   it.
2. **Plan.** The companion works with a WoW database and writes the plan.
3. **In.** `/reload` again: the plan is live.

### Why the plan is a code file, not a saved one

On `/reload` the game first writes its in-memory saved variables over their
files, then reads them back: anything written into a saved file during play
is wiped. A code file the game only reads: a tiny addon, `QuestPartyPlan`,
ships an empty `Plan.lua` listed in its TOC; the companion rewrites it
whenever it likes, and a `/reload` loads it (deploys work the same way). The
file must exist when the game starts: a new file needs a restart, a changed
one only a reload.

### The format: JSON-like Lua tables

```lua
QuestPartyPlan = {
  v = 1,                       -- format version
  made = 1795125540,           -- when (server time)
  title = "Barrens, levels 14 to 16",
  steps = {
    { goal = "accept", quest = 855, map = 1413, x = 0.52, y = 0.30, note = "Centaur Bracers" },
    { goal = "kill", npc = 3275, count = 15, map = 1413, x = 0.45, y = 0.61 },
    { goal = "turnin", quest = 855, map = 1413, x = 0.52, y = 0.30 },
  },
  opportunities = {
    { kind = "record", stat = "x", target = 41250, note = "Beat your best XP day" },
  },
}
```

- Data only: table literals, every string escaped, no functions or calls (the
  game runs the file as code).
- Ids, not names: quest, NPC and map ids, as the stats tracker keys them.
- A version, so old plans still read and newer ones are skipped.
- Large is fine (Questie ships tens of MB of tables like these); split into
  chunks if one ever grows huge.
- One schema both ways: the saved file out, `Plan.lua` in.

## In game: handing the plan on

Through other addons' published APIs, never by editing their files:

- **RXPGuides** (`RXPGuides.RegisterGuide(group, text)`): the plan becomes an
  RXP guide, with its arrow, step list and auto-advance.
- **WaypointUI** (`WaypointUIAPI.Navigation.NewUserNavigation{ name, mapID,
  x, y }`, `NewPin{...}`): the next step's arrow, the rest as pins.
- **Neither installed:** Quest Party's own HereBeDragons pins (OpenMap shows
  them too) and a checklist.

Steps tick off from Quest Party's own events (a quest done, a place found,
kills counted), and the next waypoint takes over. Ready-made macros
(`/target Hogger`) are possible out of combat. No teleporting, moving or
clicking for the player.

## The companion's sources

| Source | What | Catch |
|---|---|---|
| Questie's database | every Classic quest, NPC, object, item location | open source; check its license before shipping its data |
| wago.tools | the game's own data tables per build | community-run; raw, needs joining |
| Blizzard Game Data API | items, spells, creatures (Classic namespaces) | free key; thin on Classic quests; Forever unknown |
| Wowhead | everything | no public API; scraping is against their terms |
| The game's Statistics | lifetime counts per character (`GetStatistic`; Forever has the panel) | aggregates only |

## What it could plan

- Routes: quests to take and turn in, in order, the walking shortest.
- Upgrades: gear from quests ahead, what to sell, what to keep.
- Professions: where to gather, what to craft for skill-ups.
- Opportunities from your own history: beat a record, a creature count
  against a friend's, three of you need Hogger: a shared waypoint, sent to the
  party the additive way.

## Related

- `docs\stats-tracker.md`: the memory (counts, records, the journey log).
- An archiver: keeps every session's saved file outside the game, for history
  the companion can search ("what did I do last Tuesday").
