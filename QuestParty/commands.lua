-- Slash commands: /qp and /questparty. Commands are a data table of handlers.
local _, ns = ...
local L = ns.L

local emulatorCommands = {
	start = function()
		ns.Emulator:Start()
		ns.Print(L.CMD_EMU_STARTED)
	end,
	stop = function()
		ns.Emulator:Stop()
		ns.Print(L.CMD_EMU_STOPPED)
	end,
	step = function()
		ns.Emulator:Step()
	end,
	burst = function(arg)
		ns.Emulator:Burst(tonumber(arg) or 10)
	end,
	speed = function(arg)
		ns.Emulator:SetSpeed(tonumber(arg) or 1)
		ns.Print(L.CMD_EMU_SPEED:format(ns.Emulator.speed))
	end,
}

local function PrintHelp()
	ns.Print(L.CMD_HELP)
	ns.Print(L.CMD_HELP_TOGGLE)
	ns.Print(L.CMD_HELP_DEBUG)
	if ns.IsDebug() then
		ns.Print(L.CMD_HELP_EMU)
		ns.Print(L.CMD_HELP_TEST)
	end
	ns.Print(L.CMD_HELP_CLEAR)
	ns.Print(L.CMD_HELP_SET)
	ns.Print(L.CMD_HELP_ICON)
end

local function PrintSwitch(setting)
	ns.Print(L.CMD_SET_LINE:format(setting.id:lower(), ns.IsEnabled(setting.id) and L.ON or L.OFF, setting.label))
end

-- Switch ids are matched without case.
local function FindSwitch(name)
	for _, setting in ipairs(ns.Settings) do
		if setting.id:lower() == name then
			return setting
		end
	end
end

local commands = {
	[""] = function()
		ns.Panel:Toggle()
	end,
	debug = function(value)
		value = value and value:lower()
		ns.SetDebug(value == "on" or (value ~= "off" and not ns.IsDebug()))
		ns.Print(ns.IsDebug() and L.CMD_DEBUG_ON or L.CMD_DEBUG_OFF)
	end,
	emu = function(sub, arg)
		if not ns.IsDebug() then
			ns.Print(L.CMD_DEBUG_REQUIRED)
			return
		end
		local handler = emulatorCommands[(sub or ""):lower()]
		if handler then
			handler(arg)
		else
			ns.Emulator:Toggle()
		end
	end,
	clear = function()
		ns.Store:Clear()
		ns.Print(L.CMD_CLEARED)
	end,
	set = function(name, value)
		if not name then
			for _, setting in ipairs(ns.Settings) do
				PrintSwitch(setting)
			end
			return
		end
		local setting = FindSwitch(name:lower())
		value = value and value:lower()
		if not setting then
			ns.Print(L.CMD_SET_UNKNOWN:format(name))
			return
		end
		if value == "on" or value == "off" then
			ns.SetEnabled(setting.id, value == "on")
		else
			ns.SetEnabled(setting.id, not ns.IsEnabled(setting.id))
		end
		PrintSwitch(setting)
	end,
	-- Tries an icon beside the panel title: /qp icon inv_misc_note_02, or no name to reset.
	icon = function(name)
		ns.Panel:SetTitleIcon(name)
		ns.Print(name and L.CMD_ICON_SET:format(name) or L.CMD_ICON_RESET)
	end,
	test = function()
		if not ns.IsDebug() then
			ns.Print(L.CMD_DEBUG_REQUIRED)
			return
		end
		ns.Collectors:RunTest()
	end,
	help = PrintHelp,
}

SLASH_QUESTPARTY1 = "/qp"
SLASH_QUESTPARTY2 = "/questparty"
SlashCmdList["QUESTPARTY"] = function(text)
	local words = {}
	for word in (text or ""):gmatch("%S+") do
		words[#words + 1] = word
	end
	-- The command word is matched without case. Arguments keep theirs, for names.
	local handler = commands[(words[1] or ""):lower()]
	if handler then
		handler(words[2], words[3])
	else
		PrintHelp()
	end
end

-- Click target for the minimap addon menu (see AddonCompartmentFunc in the TOC).
function QuestParty_OnAddonCompartmentClick()
	ns.Panel:Toggle()
end
