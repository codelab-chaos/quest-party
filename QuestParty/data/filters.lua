-- Filter tabs, in display order. Short labels keep them on one row at small widths.
--   members   show one roster card per party member
--   progress  a card kind to show as two-line progress rows, one per unfinished objective
--   tracker   a card kind to show in full, grouped across the party: one tall row per
--             quest, with every member who is on it
--   feed      show feed rows: true for every type, or a key matched against FeedTypes[x].filters
-- questTab is the tab a clicked quest row jumps to.
local _, ns = ...
local L = ns.L

ns.Filters = {
	{ id = "all", label = L.FILTER_ALL, shortLabel = L.FILTER_ALL, progress = "quest", feed = true },
	{ id = "quests", label = L.FILTER_QUESTS, shortLabel = L.FILTER_QUESTS_SHORT, tracker = "quest" },
	{ id = "xp", label = L.FILTER_XP, shortLabel = L.FILTER_XP, feed = "xp" },
	{ id = "achievements", label = L.FILTER_ACHIEVEMENTS, shortLabel = L.FILTER_ACHIEVEMENTS_SHORT, feed = "achievements" },
	{ id = "professions", label = L.FILTER_PROFESSIONS, shortLabel = L.FILTER_PROFESSIONS_SHORT, feed = "professions" },
	{ id = "party", label = L.FILTER_PARTY, shortLabel = L.FILTER_PARTY_SHORT, members = true, progress = "quest" },
}

ns.QuestTab = "quests"

ns.FilterById = {}
for _, filter in ipairs(ns.Filters) do
	ns.FilterById[filter.id] = filter
end
