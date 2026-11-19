-- What the stats keep, as data: a running tally per player per day, from the
-- entries that arrive (your own and your friends'). See stats.lua.
--   id     the tally's name
--   from   the feed type that adds to it
--   sum    a data field to add up; without one, each entry counts 1
--   when   a data field that must be filled for the entry to count
--   count  a data field saying how many the entry stands for (a batch), else 1
--   label  how /qp stats says it, with the number in place of %s
--   name   what the 123 tab calls it
local _, ns = ...
local L = ns.L

-- color: the kind's own liquid in the Fuel gauges (ui\report.lua).
-- fuel:  what one of it is worth in the party's fuel (the vat's one number);
--        nil keeps the kind out of the Fuel tab (it is still counted).
-- fuelFrom: a tally that already holds the kind's fuel (XP's, counted by
--        level in stats.lua), times fuel.
ns.StatKinds = {
	{ id = "xp", from = "xp", sum = "xp", label = L.STAT_XP, name = L.STAT_NAME_XP, color = { 0.62, 0.30, 0.92 }, fuel = 1, fuelFrom = "xpFuel" }, -- purple, as the XP bar; fuel by level (ns.XPFuelPerLevel)
	{ id = "kills", from = "xp", when = "mob", count = "gains", label = L.STAT_KILLS, name = L.STAT_NAME_KILLS, color = { 0.90, 0.18, 0.18 }, fuel = 1 }, -- red; one each, on top of the kill's XP (1 to 1 for now)
	{ id = "quests", from = "quest_complete", label = L.STAT_QUESTS, name = L.STAT_NAME_QUESTS, color = { 0.98, 0.80, 0.12 }, fuel = 1 }, -- gold; one each, on top of the quest's XP
	{ id = "levels", from = "level", label = L.STAT_LEVELS, name = L.STAT_NAME_LEVELS, color = { 0.20, 0.45, 0.95 }, fuel = 1 }, -- blue; one each
	{ id = "skillups", from = "skill", label = L.STAT_SKILLUPS, name = L.STAT_NAME_SKILLUPS, color = { 0.18, 0.78, 0.28 }, fuel = 1 }, -- green; one each
	{ id = "achievements", from = "achievement", label = L.STAT_ACHIEVEMENTS, name = L.STAT_NAME_ACHIEVEMENTS, color = { 1.00, 0.52, 0.08 } }, -- orange; not in Fuel yet
	{ id = "deaths", from = "death", label = L.STAT_DEATHS, name = L.STAT_NAME_DEATHS, color = { 0.55, 0.60, 0.68 }, fuel = 0 }, -- bone gray; shown, worth nothing
}

-- XP to the next level, by level (1 to 59; 60 is the cap): Forever's curve is
-- Classic's (community tables, checked against readings from real Forever
-- play: 11,400 at 13, 12,900 at 14; 4,084,700 XP from 1 to 60). Used when an
-- XP gain does not say its level's requirement (stats.lua, XP fuel).
ns.XPToLevel = {
	400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
	8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
	25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
	95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
	153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

-- XP fuel: a full level's worth of XP is worth this times the level, so it
-- ramps up in a straight line with level instead of the game's steep curve.
ns.XPFuelPerLevel = 200

