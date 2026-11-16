-- What the stats keep, as data: a running tally per player per day, from the
-- entries that arrive (your own and your friends'). See stats.lua.
--   id     the tally's name
--   from   the feed type that adds to it
--   sum    a data field to add up; without one, each entry counts 1
--   when   a data field that must be filled for the entry to count
--   count  a data field saying how many the entry stands for (a batch), else 1
--   label  how /qp stats says it, with the number in place of %s
local _, ns = ...
local L = ns.L

-- How many days of tallies are kept. Older days are dropped.
ns.StatDays = 7

ns.StatKinds = {
	{ id = "xp", from = "xp", sum = "xp", label = L.STAT_XP },
	{ id = "kills", from = "xp", when = "mob", count = "gains", label = L.STAT_KILLS },
	{ id = "quests", from = "quest_complete", label = L.STAT_QUESTS },
	{ id = "levels", from = "level", label = L.STAT_LEVELS },
	{ id = "skillups", from = "skill", label = L.STAT_SKILLUPS },
	{ id = "achievements", from = "achievement", label = L.STAT_ACHIEVEMENTS },
	{ id = "deaths", from = "death", label = L.STAT_DEATHS },
}
