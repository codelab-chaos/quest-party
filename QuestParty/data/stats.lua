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

-- How many days of tallies are kept. Older days are dropped.
ns.StatDays = 7

-- color: the kind's own liquid in the 123 gauges (ui\report.lua).
ns.StatKinds = {
	{ id = "xp", from = "xp", sum = "xp", label = L.STAT_XP, name = L.STAT_NAME_XP, color = { 0.62, 0.30, 0.92 } }, -- purple, as the XP bar
	{ id = "kills", from = "xp", when = "mob", count = "gains", label = L.STAT_KILLS, name = L.STAT_NAME_KILLS, color = { 0.90, 0.18, 0.18 } }, -- red
	{ id = "quests", from = "quest_complete", label = L.STAT_QUESTS, name = L.STAT_NAME_QUESTS, color = { 0.98, 0.80, 0.12 } }, -- gold
	{ id = "levels", from = "level", label = L.STAT_LEVELS, name = L.STAT_NAME_LEVELS, color = { 0.20, 0.45, 0.95 } }, -- blue
	{ id = "skillups", from = "skill", label = L.STAT_SKILLUPS, name = L.STAT_NAME_SKILLUPS, color = { 0.18, 0.78, 0.28 } }, -- green
	{ id = "achievements", from = "achievement", label = L.STAT_ACHIEVEMENTS, name = L.STAT_NAME_ACHIEVEMENTS, color = { 1.00, 0.52, 0.08 } }, -- orange
	{ id = "deaths", from = "death", label = L.STAT_DEATHS, name = L.STAT_NAME_DEATHS, color = { 0.55, 0.60, 0.68 } }, -- bone gray
}
