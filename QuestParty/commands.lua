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
	ns.Print(L.CMD_HELP_EMU)
	ns.Print(L.CMD_HELP_CLEAR)
	ns.Print(L.CMD_HELP_SET)
	ns.Print(L.CMD_HELP_LINK)
	ns.Print(L.CMD_HELP_TEST)
	ns.Print(L.CMD_HELP_ICON)
end

local function PrintSwitch(setting)
	ns.Print(L.CMD_SET_LINE:format(setting.id:lower(), ns.IsEnabled(setting.id) and L.ON or L.OFF, setting.label))
end

local function PrintPeers()
	local any = false
	for name, peer in pairs(ns.Session.peers) do
		local via = (peer.party and peer.link) and L.PEER_VIA_BOTH or (peer.party and L.PEER_VIA_PARTY or L.PEER_VIA_LINK)
		ns.Print(L.PEERS_LINE:format(ns.ColorName(name, peer.class), tostring(peer.level), peer.zone or L.UNKNOWN, via))
		any = true
	end
	if not any then
		ns.Print(L.PEERS_NONE)
	end
	local offline = {}
	for name in pairs(ns.db.links) do
		if not ns.Session.peers[name] then
			offline[#offline + 1] = name
		end
	end
	if #offline > 0 then
		table.sort(offline)
		ns.Print(L.LINKS_OFFLINE:format(table.concat(offline, ", ")))
	end
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
	emu = function(sub, arg)
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
	link = function(name)
		if not name then
			PrintHelp()
			return
		end
		ns.Session:Link(name)
		ns.Print(L.LINK_SENT:format(name))
	end,
	unlink = function(name)
		local removed = name and ns.Session:Unlink(name)
		ns.Print((removed and L.LINK_REMOVED or L.LINK_UNKNOWN):format(removed or name or "?"))
	end,
	peers = PrintPeers,
	test = function()
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
