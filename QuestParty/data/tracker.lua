-- The stats tracker, as data (experimental: docs\stats-tracker.md; separate
-- from Party Fuel). What it counts, how each is shown, and where each comes
-- from. tracker.lua keeps the numbers; ui\tracker.lua shows them through
-- ns.TrackerFormat (below). Nothing here is sent: the additive convention
-- (docs\stats-tracker.md) is for later phases.
--   id        the counter's key in the tables (short: it is saved many times)
--   category  which group it is shown under (TrackerCategories)
--   type      how its number reads (TrackerFormat): count, xp, duration
--             (seconds), distance (yards), money (copper)
--   label     its name
--   mine      measured by your own client only (time, distance, jumps,
--             money): friends' are not known
--   source    "game": the game's own number (its latest value, not counted
--             up by us; shown for all time only), beside ours
--   compare   for a game number: the stats we count for the same thing,
--             added up and shown beside it (WoW | Quest Party)
local _, ns = ...
local L = ns.L

ns.TrackerRules = {
	days = 90, -- daily detail kept this long, then folded into months
	months = 24, -- monthly totals kept this long, then folded into years
	sample = 1, -- seconds between position samples (distance)
	leap = 60, -- yards in one sample past which it was a teleport, not travel
	clock = 60, -- seconds between adding up time played
}

-- Where a number comes from is its section: the game's own (source "game")
-- under From WoW, first; everything else is counted by Quest Party.
ns.TrackerCategories = {
	{ id = "game", label = L.TRACK_CAT_GAME, columns = { L.TRACK_COL_WOW, L.TRACK_COL_QP } },
	{ id = "combat", label = L.TRACK_CAT_COMBAT },
	{ id = "questing", label = L.TRACK_CAT_QUESTING },
	{ id = "growth", label = L.TRACK_CAT_GROWTH },
	{ id = "exploring", label = L.TRACK_CAT_EXPLORING },
	{ id = "time", label = L.TRACK_CAT_TIME },
	{ id = "wealth", label = L.TRACK_CAT_WEALTH },
	{ id = "social", label = L.TRACK_CAT_SOCIAL },
}

ns.TrackerStats = {
	{ id = "k", category = "combat", type = "count", label = L.TRACK_KILLS },
	{ id = "kx", category = "combat", type = "xp", label = L.TRACK_KILL_XP },
	{ id = "d", category = "combat", type = "count", label = L.TRACK_DEATHS },
	{ id = "qa", category = "questing", type = "count", label = L.TRACK_QUESTS_TAKEN },
	{ id = "qd", category = "questing", type = "count", label = L.TRACK_QUESTS_DONE },
	{ id = "qx", category = "questing", type = "xp", label = L.TRACK_QUEST_XP },
	{ id = "qq", category = "questing", type = "count", label = L.TRACK_QUESTS_DROPPED },
	{ id = "x", category = "growth", type = "xp", label = L.TRACK_XP },
	{ id = "l", category = "growth", type = "count", label = L.TRACK_LEVELS },
	{ id = "s", category = "growth", type = "count", label = L.TRACK_SKILLUPS },
	{ id = "p", category = "growth", type = "count", label = L.TRACK_PROFESSIONS },
	{ id = "a", category = "growth", type = "count", label = L.TRACK_ACHIEVEMENTS },
	{ id = "z", category = "exploring", type = "count", label = L.TRACK_DISCOVERIES },
	{ id = "zx", category = "exploring", type = "xp", label = L.TRACK_DISCOVERY_XP },
	{ id = "mg", category = "exploring", type = "distance", label = L.TRACK_DISTANCE, mine = true },
	{ id = "mf", category = "exploring", type = "distance", label = L.TRACK_FLOWN, mine = true },
	{ id = "j", category = "exploring", type = "count", label = L.TRACK_JUMPS, mine = true },
	{ id = "gp", category = "game", type = "duration", label = L.TRACK_PLAYED_GAME, mine = true, source = "game", compare = { "ta", "tk" } },
	{ id = "gq", category = "game", type = "count", label = L.TRACK_QUESTS_GAME, mine = true, source = "game", compare = { "qd" } },
	{ id = "gl", category = "game", type = "duration", label = L.TRACK_PLAYED_LEVEL, mine = true, source = "game" },
	{ id = "ta", category = "time", type = "duration", label = L.TRACK_ACTIVE, mine = true },
	{ id = "tk", category = "time", type = "duration", label = L.TRACK_AFK, mine = true },
	{ id = "ts", category = "time", type = "count", label = L.TRACK_SESSIONS, mine = true },
	{ id = "gi", category = "wealth", type = "money", label = L.TRACK_MONEY_IN, mine = true },
	{ id = "go", category = "wealth", type = "money", label = L.TRACK_MONEY_OUT, mine = true },
	{ id = "cs", category = "social", type = "count", label = L.TRACK_KEKCHATS },
	{ id = "sg", category = "social", type = "count", label = L.TRACK_STAMPS_GIVEN },
	{ id = "sr", category = "social", type = "count", label = L.TRACK_STAMPS_RECEIVED },
}

ns.TrackerStatById = {}
for _, stat in ipairs(ns.TrackerStats) do
	ns.TrackerStatById[stat.id] = stat
end

-- ========= How a number reads ===============================================
-- One formatter per type, pure (the tests read them).
local function Comma(value)
	return ns.Comma(math.floor(value + 0.5))
end

ns.TrackerFormat = {
	count = function(value) return Comma(value) end,
	xp = function(value) return L.TRACK_FORMAT_XP:format(Comma(value)) end,
	duration = function(seconds)
		seconds = math.floor(seconds)
		local days, hours, minutes = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60)
		if days > 0 then return L.TRACK_FORMAT_DAYS:format(days, hours) end
		if hours > 0 then return L.TRACK_FORMAT_HOURS:format(hours, minutes) end
		return L.TRACK_FORMAT_MINUTES:format(minutes)
	end,
	distance = function(yards)
		if yards >= 1760 then return L.TRACK_FORMAT_MILES:format(yards / 1760) end
		return L.TRACK_FORMAT_YARDS:format(Comma(yards))
	end,
	money = function(copper)
		copper = math.floor(copper)
		local gold, silver, rest = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
		if gold > 0 then return L.TRACK_FORMAT_GOLD:format(ns.Comma(gold), silver, rest) end
		if silver > 0 then return L.TRACK_FORMAT_SILVER:format(silver, rest) end
		return L.TRACK_FORMAT_COPPER:format(rest)
	end,
}

-- A number as its stat reads it.
function ns.TrackerText(statId, value)
	local stat = ns.TrackerStatById[statId]
	local format = stat and ns.TrackerFormat[stat.type] or ns.TrackerFormat.count
	return format(value or 0)
end
