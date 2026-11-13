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
	{ id = "chatEcho", label = L.SET_CHAT_ECHO, tip = L.SET_CHAT_ECHO_TIP, default = true },
	{ id = "chatDetails", label = L.SET_CHAT_DETAILS, tip = L.SET_CHAT_DETAILS_TIP, default = false },
	{ id = "chatOrder", label = L.SET_CHAT_ORDER, tip = L.SET_CHAT_ORDER_TIP, default = true },
	{ id = "showSelf", label = L.SET_SHOW_SELF, tip = L.SET_SHOW_SELF_TIP, default = true },
	{ id = "share", label = L.SET_SHARE, tip = L.SET_SHARE_TIP, default = true },
	{ id = "emulatorShare", label = L.SET_EMULATOR_SHARE, tip = L.SET_EMULATOR_SHARE_TIP, default = false },
}

ns.SettingById = {}
for _, setting in ipairs(ns.Settings) do
	ns.SettingById[setting.id] = setting
end

-- How long a persistent card can go without an update.
ns.Timing = {
	staleSeconds = 5 * 60, -- then it is drawn grayed out
	expireSeconds = 60 * 60, -- then it is removed
	pruneSeconds = 60, -- how often expired cards are swept
}
