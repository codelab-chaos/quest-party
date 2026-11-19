-- Core: the shared addon table, a small message bus, and startup.
-- Every other file talks through ns.Bus, so modules never call each other directly.
local addonName, ns = ...

ns.name = addonName

-- The global names this addon owns, from its folder's name: its saved
-- variables, slash commands and frames.
ns.Globals = {
	db = addonName .. "DB",
	charDb = addonName .. "CharDB",
	slashKey = addonName:upper(),
	frame = function(name) return addonName .. name end,
	popup = function(name) return addonName:upper() .. "_" .. name end,
}

-- This build's version, from its TOC: told to the channel and shown in Settings.
ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

-- ========= Message bus ======================================================
-- Messages used across the addon:
--   INIT                      saved variables are loaded
--   READY                     the player is in the world, safe to build UI
--   ENTRY_RECEIVED(entry)     a feed entry arrived: our own, the channel's, or the emulator's
--   FEED_ADDED(entry, def)    the store accepted an entry as a new feed row
--   CARD_UPDATED(record, def, entry)  a persistent card was created or moved forward
--   SETTING_CHANGED(id, value) a feature switch was flipped
--   SLIDER_CHANGED(id, value)  a slider in Settings moved
--   ENTRY_OUTGOING(entry)     one of our own entries, to send to everyone we share with
--   COMMS_RECEIVED(text, chatType, sender, channelId)  a raw addon message arrived
--   COMMS_SENT(message)       the game took one of ours to send
--   COMMS_ECHOED(text, chatType, sender, channelId)  one of ours came back from the server
--   COMMS_LOGGED(record)      a message passed on the channel: out, back or in
--   PEERS_CHANGED(peer)       someone connected, updated or left. peer is nil on a leave.
--   STORE_CHANGED             anything in the store changed, views should refresh
--   OWN_QUEST_READ(quest)     one of your quests read from the log the first time
--   DEV_STATE(running)        a dev run (pretend players) started or stopped
--   DEBUG_CHANGED(enabled)    developer tools were enabled or disabled
--   CONNECTION_CHANGED        the configured chat channel changed state
local Bus = { handlers = {} }
ns.Bus = Bus

function Bus:On(message, handler)
	local list = self.handlers[message]
	if not list then
		list = {}
		self.handlers[message] = list
	end
	list[#list + 1] = handler
end

function Bus:Fire(message, ...)
	local list = self.handlers[message]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](...)
	end
end

-- ========= Text helpers =====================================================

-- Fills "{key}" tokens in a template from a table of fields.
function ns.Fill(template, fields)
	return (template:gsub("{(%w+)}", function(key)
		local value = fields[key]
		if value == nil then
			return "?"
		end
		return tostring(value)
	end))
end

-- 2450 -> "2,450"
function ns.Comma(number)
	local text = tostring(number)
	local count
	repeat
		text, count = text:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return text
end

-- Seconds ago -> "now", "4m", "2h", "3d"
function ns.Ago(seconds)
	if seconds < 60 then
		return ns.L.TIME_NOW
	elseif seconds < 3600 then
		return ns.L.TIME_MINUTES:format(math.floor(seconds / 60))
	elseif seconds < 86400 then
		return ns.L.TIME_HOURS:format(math.floor(seconds / 3600))
	end
	return ns.L.TIME_DAYS:format(math.floor(seconds / 86400))
end

-- A day's key, "2026-11-15", for a server time.
function ns.Day(time)
	return (date or os.date)("%Y-%m-%d", math.floor(time or 0))
end

-- Whole days from one day's key to another's.
function ns.DaysBetween(first, second)
	local function Stamp(day)
		local year, month, dayOfMonth = day:match("^(%d+)-(%d+)-(%d+)$")
		return (time or os.time)({ year = tonumber(year), month = tonumber(month), day = tonumber(dayOfMonth), hour = 12 })
	end
	return math.floor((Stamp(second) - Stamp(first)) / 86400 + 0.5)
end

function ns.ColorName(name, class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then
		return "|c" .. color.colorStr .. name .. "|r"
	end
	return name
end

-- A name with its spaces, hyphens and case taken out, so two spellings of the
-- same character's name compare equal.
local function PlainName(name)
	return (name:gsub("[%s%-]", ""):lower())
end

-- True when a sender's name is this player's own. On Forever a character has
-- a first name and a surname, and messages carry both ("Bagoe Bones"), while
-- UnitName gives them as two values.
-- This character's name as everyone else sees it: on Forever a character
-- has a first name and a surname, the game gives them as two values, and
-- the channel carries both ("Unbearably Huggable"). Your own rows use this,
-- so they read like everyone else's. Without a surname, the first name.
function ns.MyName()
	local first, second = UnitName("player")
	if type(second) == "string" and second ~= "" and second ~= (GetRealmName and GetRealmName()) then
		return first .. " " .. second
	end
	return first
end

function ns.IsMe(name)
	if type(name) ~= "string" then
		return false
	end
	local first, second = (UnitNameUnmodified or UnitName)("player")
	local full = NameUtil and NameUtil.GetUnmodifiedUnitFullName and NameUtil.GetUnmodifiedUnitFullName("player")
	local wanted = PlainName(name)
	for _, mine in ipairs({ first or "", (first or "") .. (second or ""), full or "" }) do
		if mine ~= "" and PlainName(mine) == wanted then
			return true
		end
	end
	return false
end

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[" .. ns.L.TITLE .. "]|r " .. text)
end

-- ========= Saved variables ==================================================
local ACCOUNT_DEFAULTS = {
	switches = {}, -- filled from data\settings.lua at startup
	sliders = {}, -- likewise
	debug = false,
	connection = { name = "", enabled = false },
}

local CHARACTER_DEFAULTS = {
	filter = "all",
	hidden = {}, -- gutter filters turned off: [id] = true (data\filters.lua)
	scenario = nil, -- the test run last chosen in Settings (dev\scenarios.lua)
	scenarioClear = true, -- Clear on go
	shown = true,
	docked = false, -- minimized to the dock (ui\dock.lua)
}

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			ApplyDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

-- ========= Feature switches =================================================
function ns.IsDebug()
	return ns.db ~= nil and ns.db.debug == true
end

function ns.SetDebug(enabled)
	ns.db.debug = enabled and true or false
	Bus:Fire("DEBUG_CHANGED", ns.db.debug)
end

-- What has no switch (a welcome, quests, leveling and the rest of what makes
-- Quest Party work) is always on.
function ns.IsEnabled(id)
	if id == nil or ns.AlwaysOn[id] then
		return true
	end
	return ns.db.switches[id] == true
end

function ns.GetSlider(id)
	local slider = ns.SliderById[id]
	return ns.db.sliders[id] or (slider and slider.default)
end

-- Keeps the value in range and on a step. Returns it, or nil for no such slider.
function ns.SetSlider(id, value)
	local slider = ns.SliderById[id]
	if not slider or type(value) ~= "number" then
		return nil
	end
	value = slider.min + math.floor((value - slider.min) / slider.step + 0.5) * slider.step
	value = math.max(slider.min, math.min(slider.max, value))
	ns.db.sliders[id] = value
	Bus:Fire("SLIDER_CHANGED", id, value)
	return value
end

-- Plays one of the game's sounds (a SOUNDKIT id) at the Volume set in
-- Settings (data\settings.lua, VolumeLevels), or not at all when it is Mute.
function ns.PlaySound(kit)
	local level = ns.VolumeLevels[ns.GetSlider("volume") or 2]
	if not level or level.volume <= 0 or not kit or not PlaySound then
		return false
	end
	return pcall(PlaySound, kit, "SFX", nil, nil, nil, level.volume)
end

function ns.SetEnabled(id, value)
	if not ns.SettingById[id] then
		return false
	end
	ns.db.switches[id] = value and true or false
	Bus:Fire("SETTING_CHANGED", id, ns.db.switches[id])
	return true
end

-- ========= Startup ==========================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		local QuestPartyDB = _G[ns.Globals.db] or {}
		local QuestPartyCharDB = _G[ns.Globals.charDb] or {}
		_G[ns.Globals.db], _G[ns.Globals.charDb] = QuestPartyDB, QuestPartyCharDB
		for _, setting in ipairs(ns.Settings) do
			ACCOUNT_DEFAULTS.switches[setting.id] = setting.default
		end
		for _, slider in ipairs(ns.SettingSliders) do
			ACCOUNT_DEFAULTS.sliders[slider.id] = slider.default
		end
		ApplyDefaults(QuestPartyDB, ACCOUNT_DEFAULTS)
		-- Dev mode (debug) is off unless turned on with /qp debug on; it stays
		-- as last set, in every install.
		QuestPartyDB.settings = nil -- replaced by switches
		-- Retired controls must not remain active through older saved preferences.
		QuestPartyDB.switches.chatDetails = nil
		-- Switches that are gone (welcomes, and what is always shared now).
		for id in pairs(QuestPartyDB.switches) do
			if not ns.SettingById[id] then
				QuestPartyDB.switches[id] = nil
			end
		end
		QuestPartyDB.switches.share = nil
		QuestPartyDB.switches.emulatorShare = nil
		QuestPartyDB.links = nil
		ApplyDefaults(QuestPartyCharDB, CHARACTER_DEFAULTS)
		ns.db = QuestPartyDB
		ns.charDb = QuestPartyCharDB
		Bus:Fire("INIT")
	elseif event == "PLAYER_LOGIN" then
		Bus:Fire("READY")
	end
end)
