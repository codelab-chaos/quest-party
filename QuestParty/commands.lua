-- Slash commands: /qp and /questparty. Commands are a data table of handlers.
local _, ns = ...
local L = ns.L

-- The Options button and slash command share the same destructive-action prompt.
StaticPopupDialogs["QUESTPARTY_CONFIRM_CLEAR"] = {
	text = L.CLEAR_CONFIRM,
	button1 = L.CLEAR,
	button2 = CANCEL,
	OnAccept = function()
		ns.Store:Clear()
		ns.Print(L.CMD_CLEARED)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function ns.ConfirmClear()
	StaticPopup_Show("QUESTPARTY_CONFIRM_CLEAR")
end

local emulatorCommands = {
	start = function()
		ns.Emulator:Start()
		local channel = ns.Emulator:Channel()
		ns.Print(channel and L.CMD_EMU_STARTED_CHANNEL:format(channel) or L.CMD_EMU_STARTED)
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
	play = function(name)
		if not name then
			ns.Print(L.CMD_EMU_RECORDINGS:format(table.concat(ns.Emulator:Recordings(), ", ")))
			return
		end
		name = name:lower()
		local recording = name ~= "sample" and name or nil
		if not ns.Emulator:Use(recording) then
			ns.Print(L.CMD_EMU_NO_RECORDING:format(name, table.concat(ns.Emulator:Recordings(), ", ")))
			return
		end
		ns.Emulator:Start()
		ns.Print(L.CMD_EMU_PLAYING:format(recording or "sample", ns.Emulator.speed))
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
		ns.Print(L.CMD_HELP_LISTEN)
		ns.Print(L.CMD_HELP_STATS)
		ns.Print(L.CMD_HELP_REPLAY)
		ns.Print(L.CMD_HELP_TEST)
		ns.Print(L.CMD_HELP_TESTLOC)
	end
	ns.Print(L.CMD_HELP_CLEAR)
	ns.Print(L.CMD_HELP_SET)
	ns.Print(L.CMD_HELP_SHARE)
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
		ns.ConfirmClear()
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
	share = function()
		ns.Print(ns.Sharing:Status())
	end,
	stats = function()
		if not ns.IsDebug() then
			ns.Print(L.CMD_DEBUG_REQUIRED)
			return
		end
		local players = ns.Stats:Players()
		if #players == 0 then
			ns.Print(L.CMD_STATS_NONE:format(ns.StatDays))
			return
		end
		ns.Print(L.CMD_STATS_TITLE:format(ns.StatDays))
		for _, player in ipairs(players) do
			local totals, parts = ns.Stats:Week(player), {}
			for _, kind in ipairs(ns.StatKinds) do
				if totals[kind.id] then
					parts[#parts + 1] = kind.label:format(ns.Comma(totals[kind.id]))
				end
			end
			ns.Print(player .. ": " .. table.concat(parts, ", "))
		end
	end,
	replay = function()
		if not ns.IsDebug() then
			ns.Print(L.CMD_DEBUG_REQUIRED)
			return
		end
		ns.Print(L.CMD_REPLAYED:format(ns.Sharing:Replay()))
	end,
	listen = function()
		if not ns.IsDebug() then
			ns.Print(L.CMD_DEBUG_REQUIRED)
			return
		end
		ns.Listener:Toggle()
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
	-- Shows one thing in your own panel only: /qp testloc confetti, /qp testloc all.
	testloc = function(target)
		if not ns.IsDebug() then
			ns.Print(L.CMD_DEBUG_REQUIRED)
			return
		end
		target = (target or ""):lower()
		local chosen = {}
		if target == "all" then
			chosen = ns.LocalTests
		elseif ns.LocalTestById[target] then
			chosen = { ns.LocalTestById[target] }
		end
		if #chosen == 0 then
			local ids = {}
			for _, localTest in ipairs(ns.LocalTests) do
				ids[#ids + 1] = localTest.id
			end
			ns.Print(L.CMD_TESTLOC_LIST:format(table.concat(ids, ", ")))
			return
		end
		for _, localTest in ipairs(chosen) do
			for _, entry in ipairs(localTest.entries and localTest.entries() or {}) do
				ns.Bus:Fire("ENTRY_RECEIVED", entry)
			end
			if localTest.effect == "confetti" then
				ns.Confetti:Burst()
			end
		end
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
