-- Core: the shared addon table, a small message bus, and startup.
-- Every other file talks through ns.Bus, so modules never call each other directly.
local addonName, ns = ...

ns.name = addonName

-- ========= Message bus ======================================================
-- Messages used across the addon:
--   INIT                      saved variables are loaded
--   READY                     the player is in the world, safe to build UI
--   ENTRY_RECEIVED(entry)     a feed entry arrived from any transport (emulator, later comms)
--   FEED_ADDED(entry, def)    the store accepted an entry as a new feed row
--   CARD_UPDATED(record, def, entry)  a persistent card was created or moved forward
--   SETTING_CHANGED(id, value) a feature switch was flipped
--   ENTRY_OUTGOING(entry)     one of our own entries, to send to everyone we share with
--   COMMS_RECEIVED(text, channel, sender)  a raw addon message arrived
--   PEERS_CHANGED(peer)       someone connected, updated or left. peer is nil on a leave.
--   STORE_CHANGED             anything in the store changed, views should refresh
--   EMULATOR_STATE(running)   the emulator started or stopped
--   DEBUG_CHANGED(enabled)    developer tools were enabled or disabled
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

function ns.ColorName(name, class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then
		return "|c" .. color.colorStr .. name .. "|r"
	end
	return name
end

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[" .. ns.L.TITLE .. "]|r " .. text)
end

-- ========= Saved variables ==================================================
local ACCOUNT_DEFAULTS = {
	switches = {}, -- filled from data\settings.lua at startup
	debug = false,
}

local CHARACTER_DEFAULTS = {
	filter = "all",
	shown = true,
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

function ns.IsEnabled(id)
	return ns.db.switches[id] == true
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
		QuestPartyDB = QuestPartyDB or {}
		QuestPartyCharDB = QuestPartyCharDB or {}
		for _, setting in ipairs(ns.Settings) do
			ACCOUNT_DEFAULTS.switches[setting.id] = setting.default
		end
		ApplyDefaults(QuestPartyDB, ACCOUNT_DEFAULTS)
		QuestPartyDB.settings = nil -- replaced by switches
		-- Retired controls must not remain active through older saved preferences.
		QuestPartyDB.switches.chatDetails = nil
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
