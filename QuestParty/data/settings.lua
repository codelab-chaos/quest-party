local _, ns = ...
local L = ns.L

-- What makes Quest Party work: always collected and shared, with no switch.
-- Feed types name these in their "setting" field like any switch, and
-- ns.IsEnabled says they are on. Which of their rows you see is the gutter's
-- job (data\filters.lua).
ns.AlwaysOn = {
	quests = true,
	questDetails = true,
	kills = true,
	levels = true,
	discovery = true,
	professions = true,
	achievements = true,
	deaths = true,
}

-- Switches, in display order. Gear is the one thing you choose to share.
--   group    the Settings section it is shown in (SettingGroups below)
--   default  the value for a new install
ns.Settings = {
	{ id = "otherUpdates", group = "display", label = L.SET_OTHER_UPDATES, tip = L.SET_OTHER_UPDATES_TIP, default = true },
	{ id = "shareGear", group = "share", label = L.SET_SHARE_GEAR, tip = L.SET_SHARE_GEAR_TIP, default = true },
	{ id = "partyHeads", group = "party", label = L.SET_PARTY_HEADS, tip = L.SET_PARTY_HEADS_TIP, default = true },
	{ id = "rememberPlayers", group = "party", label = L.SET_REMEMBER, tip = L.SET_REMEMBER_TIP, default = true },
	{ id = "confetti", group = "display", label = L.SET_CONFETTI, tip = L.SET_CONFETTI_TIP, default = true },
	{ id = "chatEffects", group = "display", label = L.SET_CHAT_EFFECTS, tip = L.SET_CHAT_EFFECTS_TIP, default = true },
	{ id = "dockRight", group = "display", label = L.SET_DOCK_RIGHT, tip = L.SET_DOCK_RIGHT_TIP, default = true },
	{ id = "chatEcho", group = "display", label = L.SET_CHAT_ECHO, tip = L.SET_CHAT_ECHO_TIP, default = true },
	{ id = "chatOrder", group = "display", label = L.SET_CHAT_ORDER, tip = L.SET_CHAT_ORDER_TIP, default = true },
	{ id = "showSelf", group = "display", label = L.SET_SHOW_SELF, tip = L.SET_SHOW_SELF_TIP, default = true, sandboxOn = true },
}
-- sandboxOn: in the sandbox build, always on, with no switch at all (not in
-- Settings, not in /qps set). The sandbox's own events must always show.

-- The sections of the Settings window that hold switches, in order.
ns.SettingGroups = {
	{ id = "share", label = L.SET_GROUP_SHARE },
	{ id = "party", label = L.SET_GROUP_PARTY },
	{ id = "display", label = L.SET_GROUP_DISPLAY },
}

-- Sliders, shown under their group's switches in Settings.
--   min, max, step  its range
--   default         the value for a new install
--   format          how its value reads beside it
--   labels          or the name of a list (ns[labels]) whose entry at the value has a label
-- Volume: four steps, from the speaker in the title bar or the slider.
--   volume  passed to PlaySound (0 plays nothing)
ns.VolumeLevels = {
	[0] = { id = "mute", label = L.VOLUME_MUTE, volume = 0 },
	[1] = { id = "soft", label = L.VOLUME_SOFT, volume = 0.35 },
	[2] = { id = "regular", label = L.VOLUME_REGULAR, volume = 0.7 },
	[3] = { id = "loud", label = L.VOLUME_LOUD, volume = 1 },
}

ns.SettingSliders = {
	{ id = "theme", group = "display", label = L.SET_THEME, tip = L.SET_THEME_TIP, min = 0, max = 3, step = 1, default = 0, labels = "Themes" },
	{ id = "volume", group = "display", label = L.SET_VOLUME, tip = L.SET_VOLUME_TIP, min = 0, max = 3, step = 1, default = 2, labels = "VolumeLevels" },
	{ id = "gutterScale", group = "display", label = L.SET_GUTTER_SCALE, tip = L.SET_GUTTER_SCALE_TIP, min = 0.75, max = 2, step = 0.05, default = 1.5, format = "%.2fx" },
}

ns.SliderById = {}
for _, slider in ipairs(ns.SettingSliders) do
	ns.SliderById[slider.id] = slider
end

-- Whether a switch exists in this build: a sandboxOn one does not in the
-- sandbox.
function ns.Switchable(setting)
	return not (setting.sandboxOn and ns.IsSandbox())
end

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
	-- Welcomes are always on, so they are rate limited: one per player in this
	-- many seconds, and at most welcomeBurst in welcomeBurstSeconds overall.
	welcomeSeconds = 10 * 60,
	-- XP from kills goes out in batches, one message per creature: sent once
	-- this long passes with no more kills of it, or at the longest after
	-- killLongestSeconds. Grinding with a big party would flood the channel.
	killQuietSeconds = 8,
	-- When your gear changes, the whole set goes out, at most this often;
	-- changes in between wait and go out together.
	gearSeconds = 3 * 60,
	killLongestSeconds = 30,
	welcomeBurst = 5,
	welcomeBurstSeconds = 60,
	-- A friend's quest card without news goes after this; nil keeps cards
	-- until cleared, as decided for 0.1.2 (to revisit: docs\side-quest.md, B5).
	cardSeconds = nil,
	memberSeconds = 7 * 24 * 60 * 60, -- a player not seen goes after this
	expireSeconds = 60 * 60, -- how often lifetimes are checked
	xpDays = 7, -- days of XP kept for each player
	-- Health and power go out in steps of this many percent (100, 95, 90...),
	-- at most once in vitalsSeconds: a change in between waits and the latest
	-- goes out when the time is up, so a fight is a steady trickle, not a
	-- flood, and the last word is always right.
	vitalsStep = 5,
	vitalsSeconds = 1.5,
}

-- Colors of the power bars, by the game's power token (UnitPowerType).
ns.PowerColors = {
	MANA = { 0.20, 0.45, 0.95 },
	RAGE = { 0.90, 0.18, 0.18 },
	ENERGY = { 0.98, 0.84, 0.12 },
	FOCUS = { 1.00, 0.52, 0.08 },
	RUNIC_POWER = { 0.12, 0.80, 0.88 },
}
ns.HealthColor = { 0.18, 0.78, 0.28 }
