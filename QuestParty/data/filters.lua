-- Views of the feed, and which of them are tabs. Short labels keep tabs on one row
-- at small widths.
--   tab       shown as a tab, in this order; the others are views kept for use
--             elsewhere (and tests)
--   align     "right" puts the tab at the right end of the row
--   chat      the tab shows Quest Party chat (ui\chat.lua) in place of the list
--   report    the tab shows the 123 graphs (ui\report.lua) in place of the list
--   members   show one roster card per party member
--   progress  a card kind to show as two-line progress rows, one per unfinished objective
--   tracker   a card kind to show in full, grouped across the party: one tall row per
--             quest, with every member who is on it
--   feed      show feed rows: true for every type, or a key matched against FeedTypes[x].filters
-- questTab is the tab a clicked quest row jumps to.
local _, ns = ...
local L = ns.L

ns.Filters = {
	{ id = "all", label = L.FILTER_FEED, shortLabel = L.FILTER_FEED, progress = "quest", feed = true, tab = true },
	{ id = "quests", label = L.FILTER_QUESTS, shortLabel = L.FILTER_QUESTS_SHORT, tracker = "quest" },
	{ id = "xp", label = L.FILTER_XP, shortLabel = L.FILTER_XP, feed = "xp" },
	{ id = "achievements", label = L.FILTER_ACHIEVEMENTS, shortLabel = L.FILTER_ACHIEVEMENTS_SHORT, feed = "achievements" },
	{ id = "professions", label = L.FILTER_PROFESSIONS, shortLabel = L.FILTER_PROFESSIONS_SHORT, feed = "professions" },
	-- The party and their quests, together: a roster card each, then every quest
	-- in full with who is on it.
	{ id = "party", label = L.FILTER_PARTY, shortLabel = L.FILTER_PARTY_SHORT, members = true, tracker = "quest", tab = true },
	{ id = "report", label = L.FILTER_REPORT, shortLabel = L.FILTER_REPORT, report = true, tab = true },
	{ id = "chat", label = L.FILTER_CHAT, shortLabel = L.FILTER_CHAT, chat = true, tab = true, align = "right" },
}

ns.QuestTab = "party"

ns.FilterById = {}
ns.Tabs = {}
for _, filter in ipairs(ns.Filters) do
	ns.FilterById[filter.id] = filter
	if filter.tab then
		ns.Tabs[#ns.Tabs + 1] = filter
	end
end

-- The filter row along the bottom of the panel (the code calls it the gutter): one
-- icon per kind of row, to show or hide it in your feed. Only what you see changes; what is shared does not
-- (Settings has those switches).
--   settings  the feature switches of the rows it covers (see FeedCategory)
--   icon      its icon in the gutter
ns.GutterFilters = {
	{ id = "levels", label = L.GUTTER_LEVELING, settings = { "levels" }, icon = "Interface\\Icons\\XP_Icon" },
	{ id = "discovery", label = L.GUTTER_DISCOVERY, settings = { "discovery" }, icon = "Interface\\Icons\\INV_Misc_Map_01" },
	{ id = "kills", label = L.GUTTER_KILLS, settings = { "kills" }, icon = "Interface\\Icons\\INV_Misc_Bone_Skull_02" },
	{ id = "achievements", label = L.GUTTER_ACHIEVEMENTS, settings = { "achievements" }, icon = "Interface\\Icons\\achievement_reputation_01" },
	{ id = "deaths", label = L.GUTTER_DEATHS, settings = { "deaths" }, icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01" },
	{ id = "professions", label = L.GUTTER_PROFESSIONS, settings = { "professions" }, icon = "Interface\\Icons\\INV_SideTab_Professions_c60" },
	{ id = "quests", label = L.GUTTER_QUESTS, settings = { "quests" }, icon = "Interface\\Icons\\INV_Misc_Note_01" },
}

ns.GutterBySetting = {}
for _, gutter in ipairs(ns.GutterFilters) do
	for _, setting in ipairs(gutter.settings) do
		ns.GutterBySetting[setting] = gutter
	end
end

-- The switch an entry's row belongs to: its type's, except XP from a kill,
-- which is a Kills row (feedOnlyIf in data\feed-types.lua).
function ns.FeedCategory(entry, def)
	local rule = def and def.feedOnlyIf
	local value = rule and entry.data and entry.data[rule.field]
	if value ~= nil and value ~= "" then
		return rule.setting
	end
	return def and def.setting
end

-- True when the gutter hides this category of row.
function ns.GutterHides(setting)
	local gutter = setting and ns.GutterBySetting[setting]
	return gutter ~= nil and ns.charDb.hidden[gutter.id] == true
end
