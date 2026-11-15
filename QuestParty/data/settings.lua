-- Feature switches, in display order. These follow Quest Tweet's categories.
-- Each feed type names one of these in its "setting" field (see data\feed-types.lua).
--   default  the value for a new install
local _, ns = ...
local L = ns.L

ns.Settings = {
	{ id = "quests", label = L.SET_QUESTS, tip = L.SET_QUESTS_TIP, default = true },
	{ id = "questDetails", label = L.SET_QUEST_DETAILS, tip = L.SET_QUEST_DETAILS_TIP, default = true },
	{ id = "kills", label = L.SET_KILLS, tip = L.SET_KILLS_TIP, default = false },
	{ id = "levels", label = L.SET_LEVELS, tip = L.SET_LEVELS_TIP, default = true },
	{ id = "discovery", label = L.SET_DISCOVERY, tip = L.SET_DISCOVERY_TIP, default = true },
	{ id = "professions", label = L.SET_PROFESSIONS, tip = L.SET_PROFESSIONS_TIP, default = true },
	{ id = "achievements", label = L.SET_ACHIEVEMENTS, tip = L.SET_ACHIEVEMENTS_TIP, default = true },
	{ id = "deaths", label = L.SET_DEATHS, tip = L.SET_DEATHS_TIP, default = true },
	{ id = "otherUpdates", label = L.SET_OTHER_UPDATES, tip = L.SET_OTHER_UPDATES_TIP, default = true },
	{ id = "welcome", label = L.SET_WELCOME, tip = L.SET_WELCOME_TIP, default = true },
	{ id = "shareGear", label = L.SET_SHARE_GEAR, tip = L.SET_SHARE_GEAR_TIP, default = true },
	{ id = "partyHeads", label = L.SET_PARTY_HEADS, tip = L.SET_PARTY_HEADS_TIP, default = true },
	{ id = "rememberPlayers", label = L.SET_REMEMBER, tip = L.SET_REMEMBER_TIP, default = true },
	{ id = "confetti", label = L.SET_CONFETTI, tip = L.SET_CONFETTI_TIP, default = true },
	{ id = "chatEcho", label = L.SET_CHAT_ECHO, tip = L.SET_CHAT_ECHO_TIP, default = true },
	{ id = "chatOrder", label = L.SET_CHAT_ORDER, tip = L.SET_CHAT_ORDER_TIP, default = true },
	{ id = "showSelf", label = L.SET_SHOW_SELF, tip = L.SET_SHOW_SELF_TIP, default = true },
}

ns.SettingById = {}
for _, setting in ipairs(ns.Settings) do
	ns.SettingById[setting.id] = setting
end

-- The game's skill line categories that count as professions. A skill-up in
-- any other (weapon skills, Defense, languages) is not reported: they rise all
-- the time while fighting and would bury everything else. The numbers are the
-- game's own (C_SkillInfo skillLineCategoryID).
ns.ProfessionCategories = {
	[9] = true, -- Secondary Skills: Cooking, First Aid, Fishing
	[11] = true, -- Professions: Blacksmithing, Herbalism and the rest
}

-- Cached cards remain available until cleared or closed by a quest update.
ns.Timing = {
	staleSeconds = 5 * 60, -- then it is drawn grayed out
	-- A friend's quest card without news goes after this; nil keeps cards
	-- until cleared, as decided for 0.1.2 (to revisit: docs\side-quest.md, B5).
	cardSeconds = nil,
	memberSeconds = 7 * 24 * 60 * 60, -- a player not seen goes after this
	expireSeconds = 60 * 60, -- how often lifetimes are checked
	xpDays = 7, -- days of XP kept for each player
}
