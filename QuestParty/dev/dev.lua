-- Dev mode's pretend players (with /qp debug on): Quest Party players played
-- from this one character, to test a party without a second account. They
-- are marked pretend everywhere (emulated), never count toward Fuel, and Wipe
-- forgets only them.
--
-- Two sources of pretend players:
--   party      made up from a seed (dev\party.lua), as many as wanted
--   recording  a real session played back (dev\recording.lua)
--
-- Two ways their messages travel (Sharing.loopback):
--   channel    over the real channel, marked with the pretend player (as), so
--              this panel and a Quest Party on the same character both see
--              them. One character's send budget is shared by all of them,
--              so keep it to a few
--   loopback   read straight back here, no network: for 20, 50, 100 players
--
-- Time runs at a speed: at 10, an hour of play takes six minutes.
local addonName, ns = ...
local Bus, L = ns.Bus, ns.L

local Dev = {
	running = false,
	speed = 1,
	personas = {}, -- by name
	order = {}, -- names, in the order they arrived
	started = 0,
	clock = 0, -- seconds of pretend play so far
}
ns.Dev = Dev

local TICK_SECONDS = 0.25
local PRESENCE_SECONDS = 5 * 60 -- pretend seconds, as for real players
local CHANNEL_LIMIT = 4 -- pretend players over the real channel at once

local ticker

-- Over the channel, friends' clients from before the as marker worked on
-- every message (0.1.2, 0.2.0) would take a pretend player's hello or quest
-- for this character's own. So channel runs need a channel with no friends
-- on it; loopback is always fine. Returns false and why.
local function ChannelUsable()
	if ns.Sharing.loopback then
		return true
	end
	if ns.Session.state ~= "connected" then
		return false, L.DEV_NO_CHANNEL
	end
	for name, peer in pairs(ns.Session.peers) do
		if not peer.virtual and not ns.IsMe(name) then
			return false, L.DEV_FRIENDS_HERE:format(name)
		end
	end
	return true
end

local function Sharing()
	return ns.Sharing
end

local function Copy(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

-- ========= Speaking as a persona ============================================
local function SendHello(persona, kind)
	persona.hello = ns.DevParty.Hello(persona)
	Sharing():SendHelloAs(persona, kind)
end

local function SendQuests(persona)
	for _, quest in ipairs(ns.DevParty.Quests(persona)) do
		Sharing().SendQuest(quest, persona.class, persona.name)
	end
end

local function SendGear(persona)
	persona.gearSentAt = Dev.clock
	persona.gearPending = nil
	Sharing().SendGear(persona.gear or {}, persona.class, persona.name)
end

-- ========= Health and power, as a pretend player =============================
-- Health drops while they fight (a kill lately) and comes back between
-- fights; power follows their class: rage climbs in a fight and fades after,
-- mana and energy spend in it and come back. Sent like a real client's: in
-- 5% steps, only when changed, at most every VITALS_EVERY pretend seconds.
local VITALS_EVERY = 6
local FIGHT_SECONDS = 15
local POWER = { WARRIOR = "RAGE", ROGUE = "ENERGY" }

local function Vitals(persona)
	if Dev.clock - (persona.vitalsAt or -math.huge) < VITALS_EVERY then return end
	persona.vitalsAt = Dev.clock
	local token = POWER[persona.class] or "MANA"
	persona.health = persona.health or 100
	persona.power = persona.power or (token == "RAGE" and 0 or 100)
	local random = persona.random
	local fighting = persona.lastKillAt and Dev.clock - persona.lastKillAt < FIGHT_SECONDS
	if fighting then
		persona.health = math.max(5, persona.health - random.int(5, 25))
		persona.power = token == "RAGE" and math.min(100, persona.power + random.int(10, 30)) or math.max(0, persona.power - random.int(5, 20))
	else
		persona.health = math.min(100, persona.health + random.int(10, 25))
		persona.power = token == "RAGE" and math.max(0, persona.power - random.int(10, 20)) or math.min(100, persona.power + random.int(10, 25))
	end
	local reading = { h = math.floor(persona.health / 5) * 5, p = math.floor(persona.power / 5) * 5, t = token }
	if not ns.Vitals.Same(reading, persona.vitalsSent) then
		persona.vitalsSent = reading
		Sharing().Send(ns.Protocol.Kinds.VITALS, { h = reading.h, p = reading.p, t = reading.t }, persona.name)
	end
end

local function Act(persona, actions)
	for _, action in ipairs(actions) do
		if action.send == "entry" and action.type == "xp" and action.data and action.data.mob and action.data.mob ~= "" then
			persona.lastKillAt = Dev.clock -- a fight: their health drops (Vitals)
		end
		if action.send == "entry" then
			Sharing():SendVirtual(persona, action.type, action.data)
		elseif action.send == "quest" then
			Sharing().SendQuest(action.quest, persona.class, persona.name)
		elseif action.send == "hello" then
			SendHello(persona, ns.Protocol.Kinds.PRESENCE)
		elseif action.send == "say" then
			Sharing().SendSay(action.icons, action.saying, action.effect, persona.class, persona.name)
		elseif action.send == "gear" then
			persona.gearPending = true -- goes out under the gear rule (Advance)
		end
	end
end

-- A recorded message, said again as the recording's persona.
local function PlayMessage(persona, text)
	local kind, fields = ns.Protocol.Decode(text)
	if not kind then
		return
	end
	fields.as = nil
	local Kinds = ns.Protocol.Kinds
	if kind == Kinds.ENTRY then
		local typeName = fields.t
		fields.t, fields.c, fields.s = nil, nil, nil
		Sharing():SendVirtual(persona, typeName, fields)
	else
		if kind == Kinds.HELLO or kind == Kinds.ACK or kind == Kinds.PRESENCE then
			fields.r, fields.g = fields.r or persona.race, fields.g or persona.sex
			persona.hello = Copy(fields)
		end
		fields.c = persona.class
		Sharing().Send(kind, fields, persona.name)
	end
end

-- ========= Arriving, playing, leaving =======================================
local function Arrive(persona)
	persona.here = true
	persona.nextPresence = Dev.clock + PRESENCE_SECONDS
	if persona.recording then
		return -- its first recorded message is its hello
	end
	SendHello(persona, ns.Protocol.Kinds.HELLO)
	SendQuests(persona)
	SendGear(persona)
end

local function Leave(persona)
	persona.here = false
	persona.gone = true
	-- Here the pretend player simply goes. A Quest Party elsewhere notices
	-- when it falls silent, as with anyone whose log-off it missed. In
	-- loopback their last messages are read a tick later, so the leave waits
	-- a tick too and lands after them, in order.
	C_Timer.After(0, function() Sharing():Forget(persona.name) end)
end

local function Advance(persona)
	if persona.gone then
		return
	end
	if not persona.here then
		if Dev.clock >= persona.arriveAt then
			Arrive(persona)
		end
		return
	end
	if persona.recording then
		local messages = persona.recording.messages
		while persona.next <= #messages and Dev.clock >= persona.nextAt do
			PlayMessage(persona, messages[persona.next].text)
			persona.next = persona.next + 1
			local following = messages[persona.next]
			persona.nextAt = persona.nextAt + (following and following.after or 0)
		end
		-- Done: it stays a moment, so its last messages are read before it goes.
		if persona.next > #messages then
			persona.leaveAt = persona.leaveAt or (Dev.clock + 30)
			if Dev.clock >= persona.leaveAt then
				Leave(persona)
			end
		end
		return
	end
	while Dev.clock >= persona.nextAt do
		Act(persona, ns.DevParty.Step(persona))
		persona.nextAt = persona.nextAt + ns.DevParty.NextGap(persona)
	end
	Vitals(persona)
	-- Gear changed: the whole set, at most once in the gear wait, as a real
	-- player's goes (comms\sharing.lua).
	if persona.gearPending and Dev.clock >= (persona.gearSentAt or -math.huge) + Dev:GearWait() then
		SendGear(persona)
	end
	if Dev.clock >= persona.nextPresence then
		persona.nextPresence = Dev.clock + PRESENCE_SECONDS
		SendHello(persona, ns.Protocol.Kinds.PRESENCE)
	end
	if Dev.clock >= persona.leaveAt then
		Leave(persona)
	end
end

function Dev:Tick(elapsed)
	if not self.running then
		return
	end
	self.clock = self.clock + elapsed * self.speed
	local anyone = false
	for _, name in ipairs(self.order) do
		local persona = self.personas[name]
		Advance(persona)
		anyone = anyone or not persona.gone
	end
	if not anyone then
		self:Stop()
	end
end

local function Add(persona, arriveAt)
	Dev.personas[persona.name] = persona
	Dev.order[#Dev.order + 1] = persona.name
	persona.arriveAt = arriveAt
	persona.nextAt = arriveAt + (persona.recording and 0 or ns.DevParty.NextGap(persona))
end

-- The gear wait, in pretend seconds: a scenario's gearSeconds (real seconds,
-- so a test run shows it soon), or the real rule's wait in pretend time.
function Dev:GearWait()
	if self.gearSeconds then
		return self.gearSeconds * self.speed
	end
	return ns.Timing.gearSeconds
end

local function Begin(speed)
	Dev.speed = math.max(0.1, tonumber(speed) or Dev.speed or 1)
	Dev.clock = 0
	Dev.running = true
	Dev.started = GetTime()
	Dev.sentAtStart = Sharing().sent
	if not ticker then
		ticker = C_Timer.NewTicker(TICK_SECONDS, function()
			Dev:Tick(TICK_SECONDS)
		end)
	end
	Bus:Fire("DEV_STATE", true)
end

-- Starts a made-up party: count players from seed, at a speed.
-- Returns false and why when it cannot run.
-- Pretend players wear your equipped items (wearMine, on by default): every
-- slot you have filled is your real item, so their cards look like a real
-- player's; slots you have empty keep the world's starter items.
Dev.wearMine = true

local function WearMine(persona)
	for _, slot in ipairs(ns.EquipmentSlotIds) do
		local item = ns.ShortItem(GetInventoryItemLink("player", slot))
		if item ~= "" then
			persona.gear[slot] = item
		end
	end
end

-- prepare(persona), when given, sets each pretend player up before they
-- arrive (a quest they all share, for one).
function Dev:StartParty(count, seed, speed, prepare)
	count = math.max(1, math.min(200, tonumber(count) or 5))
	seed = tonumber(seed) or 1
	if not Sharing().loopback and count > CHANNEL_LIMIT then
		return false, L.DEV_TOO_MANY:format(CHANNEL_LIMIT)
	end
	local usable, problem = ChannelUsable()
	if not usable then
		return false, problem
	end
	self:Stop()
	wipe(self.personas)
	wipe(self.order)
	local world = ns.DevWorld
	local arrival = 0
	for _, persona in ipairs(ns.DevParty.Make(seed, count)) do
		if self.wearMine then
			WearMine(persona)
		end
		if prepare then prepare(persona) end
		local random = persona.random
		persona.leaveAt = arrival + random.int(world.session.min, world.session.max) * 60
		Add(persona, arrival)
		arrival = arrival + random.int(world.arrivals.min, world.arrivals.max)
	end
	self.seed = seed
	Begin(speed)
	return true
end

-- Plays recordings back as pretend players: one by its id, or "all" of
-- them together, each starting when it did that evening.
function Dev:StartRecording(name, speed)
	local chosen = {}
	for id, recording in pairs(ns.DevRecordings) do
		if name == "all" or name == nil or id == name then
			chosen[#chosen + 1] = recording
		end
	end
	if #chosen == 0 then
		return false, L.DEV_NO_RECORDING
	end
	table.sort(chosen, function(a, b) return (a.start or 0) < (b.start or 0) end)
	local usable, problem = ChannelUsable()
	if not usable then
		return false, problem
	end
	self:Stop()
	wipe(self.personas)
	wipe(self.order)
	for _, recording in ipairs(chosen) do
		local persona = { name = recording.name, class = recording.class, race = recording.race, sex = recording.sex, recording = recording, next = 1 }
		Add(persona, recording.start or 0)
		persona.nextAt = (recording.start or 0) + (recording.messages[1] and recording.messages[1].after or 0)
	end
	Begin(speed)
	return true
end

function Dev:Stop()
	if not self.running then
		return
	end
	self.running = false
	for _, name in ipairs(self.order) do
		local persona = self.personas[name]
		if persona.here then
			Leave(persona)
		end
	end
	Bus:Fire("DEV_STATE", false)
end

-- Forgets the pretend players and everything they did, to run again from
-- nothing. Only theirs: your own feed, cards, friends and Fuel are real and
-- stay (pretend players never count toward Fuel: stats.lua).
function Dev:Wipe()
	self:Stop()
	local names = {}
	for _, name in ipairs(self.order) do names[name] = true end
	for _, member in ipairs(ns.Store:GetMembers()) do
		if member.emulated then names[member.name] = true end
	end
	for name in pairs(names) do
		ns.Store:ForgetName(name)
		Sharing():Forget(name)
	end
	wipe(self.personas)
	wipe(self.order)
end

-- ========= Answering, as the pretend players ================================
-- Someone said hello: each pretend player here answers it once, as a real
-- Quest Party would, after a short random wait.
Bus:On("PEER_HELLO", function(sender)
	for _, name in ipairs(Dev.order) do
		local persona = Dev.personas[name]
		if persona.here and name ~= sender and not persona.recording then
			C_Timer.After(0.5 + math.random() * 2.5, function()
				if persona.here then
					SendHello(persona, ns.Protocol.Kinds.ACK)
					SendQuests(persona)
					SendGear(persona)
				end
			end)
		end
	end
end)

-- ========= Measuring ========================================================
-- What a run costs: this addon's memory (its own, apart from any other
-- addon's), the store's counts, and the messages.
function Dev:Measure()
	if UpdateAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
	end
	local memory = GetAddOnMemoryUsage and GetAddOnMemoryUsage(addonName) or 0
	local here = 0
	for _, persona in pairs(self.personas) do
		if persona.here then here = here + 1 end
	end
	local counts = ns.Store:Counts()
	local minutes = math.max(1 / 60, self.clock / 60)
	local sharing = Sharing()
	return {
		memoryKB = memory,
		here = here,
		players = #self.order,
		peers = ns.Session:Count() + (function()
			local virtual = 0
			for _, peer in pairs(ns.Session.peers) do
				if peer.virtual then virtual = virtual + 1 end
			end
			return virtual
		end)(),
		feed = counts.feed,
		cards = counts.cards,
		members = counts.members,
		sent = sharing.sent - (self.sentAtStart or 0),
		received = sharing.received,
		failed = sharing.failed or 0,
		readMilliseconds = sharing.readMilliseconds or 0,
		perMinute = (sharing.sent - (self.sentAtStart or 0)) / minutes,
		clockMinutes = self.clock / 60,
		speed = self.speed,
		loopback = sharing.loopback == true,
	}
end

-- ========= The send budget ==================================================
-- Sends count messages as fast as the game takes them, past Quest Party's own
-- queue, and counts the game's answers: how many it took before it said
-- "throttled". The messages are of a kind no Quest Party reads.
function Dev:BurstTest(count)
	count = math.max(1, math.min(40, tonumber(count) or 20))
	local session = ns.Session
	if session.state ~= "connected" then
		return nil, L.DEV_NO_CHANNEL
	end
	local results, firstRefusal = {}, nil
	local names = {}
	for name, value in pairs(Enum and Enum.SendAddonMessageResult or {}) do
		names[value] = name
	end
	for index = 1, count do
		local result = C_ChatInfo.SendAddonMessage(ns.Transport.prefix, ns.Protocol.version .. ":X:burst=#" .. index, "CHANNEL", session.channelId)
		local name = names[result] or tostring(result)
		results[name] = (results[name] or 0) + 1
		if not firstRefusal and name ~= "Success" and result ~= true then
			firstRefusal = index
		end
	end
	return { sent = count, results = results, firstRefusal = firstRefusal }
end

-- Dev mode off: every dev tool goes quiet. A run stops, its pretend players
-- leave, and loopback is off again.
Bus:On("DEBUG_CHANGED", function(enabled)
	if not enabled then
		Dev:Stop()
		ns.Sharing.loopback = false
	end
end)
