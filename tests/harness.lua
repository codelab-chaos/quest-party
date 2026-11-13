-- Small game boundary for headless tests. Addon logic runs unchanged.
local Harness = {}

function Harness.new(saved, character, debugBuild)
	local world = { now = 10000, frames = {}, timers = {}, sent = {}, chat = {}, party = {}, quests = {}, questData = {}, channels = {}, joins = {}, leaves = {} }
	local env = setmetatable({}, { __index = _G })
	env._G = env
	env.unpack = unpack or table.unpack
	env.QuestPartyDB = saved
	env.QuestPartyCharDB = character
	env.ACCEPT, env.DECLINE = "Accept", "Decline"
	env.StaticPopupDialogs = {}
	env.SlashCmdList = {}
	env.StaticPopup_Show = function(_, sender, _, data) world.popup = { sender = sender, data = data } end
	env.DEFAULT_CHAT_FRAME = {
		channelList = {},
		GetID = function() return 1 end,
		AddMessage = function(_, text) world.chat[#world.chat + 1] = text end,
		AddChannel = function(self, name) self.channelList[#self.channelList + 1] = name end,
	}
	env.GetChannelName = function(name)
		local channel = world.channels[name:lower()]
		return channel and channel.id or 0, channel and channel.name
	end
	env.JoinPermanentChannel = function(name)
		world.joins[#world.joins + 1] = name
		if world.joinRejected then return nil end
		return 0, name
	end
	env.LeaveChannelByName = function(name)
		world.leaves[#world.leaves + 1] = name
		world.channels[name:lower()] = nil
	end
	env.GetTime = function() return world.now end
	env.GetServerTime = env.GetTime
	env.UnitName = function() return "Tester" end
	env.UnitClass = function() return "Mage", "MAGE" end
	env.UnitLevel = function() return 20 end
	env.GetRealZoneText = function() return "Elwynn Forest" end
	env.IsInGroup = function() return next(world.party) ~= nil end
	env.IsInRaid = function() return world.raid == true end
	env.UnitInParty = function(name) return world.party[name] == true end
	env.UnitInRaid = env.UnitInParty
	env.Ambiguate = function(name) return (name:gsub("%-TestRealm$", "")) end
	env.issecretvalue = function(value) return value == "<secret>" end
	env.GetAchievementInfo = function() return 1, "An Achievement", 10 end
	env.wipe = function(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
	env.CreateFrame = function()
		local frame = { scripts = {}, events = {} }
		function frame:RegisterEvent(event) self.events[event] = true end
		function frame:UnregisterEvent(event) self.events[event] = nil end
		function frame:SetScript(event, callback) self.scripts[event] = callback end
		world.frames[#world.frames + 1] = frame
		return frame
	end
	local function timer(delay, callback, repeating)
		local item = { at = world.now + delay, callback = callback, repeating = repeating }
		function item:Cancel() self.cancelled = true end
		world.timers[#world.timers + 1] = item
		return item
	end
	env.C_Timer = {
		After = function(delay, callback) timer(delay, callback) end,
		NewTimer = function(delay, callback) return timer(delay, callback) end,
		NewTicker = function(delay, callback) return timer(delay, callback, delay) end,
	}
	function world:advance(seconds)
		local finish = self.now + seconds
		while true do
			local nextTimer
			for _, item in ipairs(self.timers) do
				if not item.cancelled and item.at <= finish and (not nextTimer or item.at < nextTimer.at) then
					nextTimer = item
				end
			end
			if not nextTimer then break end
			self.now = nextTimer.at
			nextTimer.cancelled = true
			nextTimer.callback()
			if nextTimer.repeating then timer(nextTimer.repeating, nextTimer.callback, nextTimer.repeating) end
		end
		self.now = finish
	end
	env.C_AddOns = { GetAddOnMetadata = function(_, key)
		if key == "X-Debug" then return debugBuild and "true" or "false" end
		return "0.1.0"
	end }
	env.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 1, ChannelThrottle = 2, AddOnMessageLockdown = 3, TargetOffline = 4 } }
	env.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(prefix) world.prefix = prefix end,
		InChatMessagingLockdown = function() return world.lockdown == true end,
		SendAddonMessage = function(prefix, text, channel, target)
			world.sent[#world.sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
			return world.sendResult or 0
		end,
	}
	local function FindQuest(id)
		if world.questData[id] then return world.questData[id] end
		for _, quest in pairs(world.quests) do
			if quest.questID == id then return quest end
		end
	end
	env.C_QuestLog = {
		GetTitleForQuestID = function(id) local quest = FindQuest(id); return quest and quest.title end,
		GetLogIndexForQuestID = function(id)
			for index, quest in ipairs(world.quests) do if quest.questID == id then return index end end
			if world.questData[id] and not world.questData[id].removed then return 100 end
		end,
		GetNumQuestLogEntries = function() return #world.quests end,
		GetInfo = function(index) return world.quests[index] end,
		GetQuestObjectives = function(id) local quest = FindQuest(id); return quest and quest.objectives end,
	}
	local ns = {}
	local modules = {
		"core.lua", "locales/en-us.lua", "data/feed-types.lua", "data/filters.lua", "data/settings.lua",
		"store.lua", "comms/protocol.lua", "comms/transport.lua", "comms/session.lua",
		"collectors/patterns.lua", "collectors/samples.lua", "collectors/collectors.lua",
		"emulator/script.lua", "emulator/emulator.lua", "ui/view-model.lua", "ui/chat-echo.lua", "commands.lua",
	}
	for _, path in ipairs(modules) do
		local chunk
		if setfenv then
			chunk = assert(loadfile("QuestParty/" .. path))
			setfenv(chunk, env)
		else
			chunk = assert(loadfile("QuestParty/" .. path, "t", env))
		end
		chunk("QuestParty", ns)
	end
	world.ns, world.env = ns, env
	function world:event(event, ...)
		for _, frame in ipairs(self.frames) do
			if frame.events[event] and frame.scripts.OnEvent then
				frame.scripts.OnEvent(frame, event, ...)
			end
		end
	end
	function world:join(name, id)
		self.channels[name:lower()] = { id = id or 5, name = name }
		self:event("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", nil, nil, nil, nil, nil, 0, id or 5, name)
	end
	local startup = world.frames[1]
	startup.scripts.OnEvent(startup, "ADDON_LOADED", "QuestParty")
	function world:ingest(kind, data, player)
		ns.Bus:Fire("ENTRY_RECEIVED", { type = kind, data = data, player = player or "Tester", class = "MAGE" })
	end
	function world:receive(kind, data, channel, player)
		ns.Bus:Fire("COMMS_RECEIVED", ns.Protocol.Encode(kind, data), channel or "PARTY", player or "Friend")
	end
	function world:quest(have, need)
		self.quests[1] = { questID = 1, title = "A Quest", objectives = {
			{ text = "Kobolds slain: " .. have .. "/" .. need, numFulfilled = have, numRequired = need },
		} }
	end
	return world
end

return Harness
