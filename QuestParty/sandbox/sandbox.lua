-- Sandbox: plays pretend Quest Party players from this one character, for
-- testing a party without a second account. Only in the sandbox build
-- (QuestPartySandbox), which collects nothing of its own.
--
-- Two sources of pretend players:
--   party      made up from a seed (sandbox\party.lua), as many as wanted
--   recording  a real session played back (sandbox\recording.lua)
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

local Sandbox = {
	running = false,
	speed = 1,
	personas = {}, -- by name
	order = {}, -- names, in the order they arrived
	started = 0,
	clock = 0, -- seconds of pretend play so far
}
ns.Sandbox = Sandbox

local TICK_SECONDS = 0.25
local PRESENCE_SECONDS = 5 * 60 -- pretend seconds, as for real players
local CHANNEL_LIMIT = 4 -- pretend players over the real channel at once

local ticker

-- Over the channel, friends' clients from before the as marker worked on
-- every message (0.1.2, 0.1.3) would take a pretend player's hello or quest
-- for this character's own. So channel runs need a channel with no friends
-- on it; loopback is always fine. Returns false and why.
local function ChannelUsable()
	if ns.Sharing.loopback then
		return true
	end
	if ns.Session.state ~= "connected" then
		return false, L.SANDBOX_NO_CHANNEL
	end
	for name, peer in pairs(ns.Session.peers) do
		if not peer.virtual and not ns.IsMe(name) then
			return false, L.SANDBOX_FRIENDS_HERE:format(name)
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
	persona.hello = ns.SandboxParty.Hello(persona)
	Sharing():SendHelloAs(persona, kind)
end

local function SendQuests(persona)
	for _, quest in ipairs(ns.SandboxParty.Quests(persona)) do
		Sharing().SendQuest(quest, persona.class, persona.name)
	end
end

local function SendGear(persona)
	Sharing().SendGear(persona.gear or {}, persona.class, persona.name)
end

local function Act(persona, actions)
	for _, action in ipairs(actions) do
		if action.send == "entry" then
			Sharing():SendVirtual(persona, action.type, action.data)
		elseif action.send == "quest" then
			Sharing().SendQuest(action.quest, persona.class, persona.name)
		elseif action.send == "hello" then
			SendHello(persona, ns.Protocol.Kinds.PRESENCE)
		end
	end
end

-- A recorded message, said again as the recording's persona.
local function PlayMessage(persona, text)
	local kind, fields = ns.Protocol.Decode(text)
	if not kind then
		return
	end
	fields.as, fields.n = nil, nil
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
		Sharing().Send(kind, fields, nil, persona.name)
	end
end

-- ========= Arriving, playing, leaving =======================================
local function Arrive(persona)
	persona.here = true
	persona.nextPresence = Sandbox.clock + PRESENCE_SECONDS
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
	-- when it falls silent, as with anyone whose log-off it missed.
	Sharing():Forget(persona.name)
end

local function Advance(persona)
	if persona.gone then
		return
	end
	if not persona.here then
		if Sandbox.clock >= persona.arriveAt then
			Arrive(persona)
		end
		return
	end
	if persona.recording then
		local messages = persona.recording.messages
		while persona.next <= #messages and Sandbox.clock >= persona.nextAt do
			PlayMessage(persona, messages[persona.next].text)
			persona.next = persona.next + 1
			local following = messages[persona.next]
			persona.nextAt = persona.nextAt + (following and following.after or 0)
		end
		if persona.next > #messages then
			Leave(persona)
		end
		return
	end
	while Sandbox.clock >= persona.nextAt do
		Act(persona, ns.SandboxParty.Step(persona))
		persona.nextAt = persona.nextAt + ns.SandboxParty.NextGap(persona)
	end
	if Sandbox.clock >= persona.nextPresence then
		persona.nextPresence = Sandbox.clock + PRESENCE_SECONDS
		SendHello(persona, ns.Protocol.Kinds.PRESENCE)
	end
	if Sandbox.clock >= persona.leaveAt then
		Leave(persona)
	end
end

function Sandbox:Tick(elapsed)
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
	Sandbox.personas[persona.name] = persona
	Sandbox.order[#Sandbox.order + 1] = persona.name
	persona.arriveAt = arriveAt
	persona.nextAt = arriveAt + (persona.recording and 0 or ns.SandboxParty.NextGap(persona))
end

local function Begin(speed)
	Sandbox.speed = math.max(0.1, tonumber(speed) or Sandbox.speed or 1)
	Sandbox.clock = 0
	Sandbox.running = true
	Sandbox.started = GetTime()
	Sandbox.sentAtStart = Sharing().sent
	if not ticker then
		ticker = C_Timer.NewTicker(TICK_SECONDS, function()
			Sandbox:Tick(TICK_SECONDS)
		end)
	end
	Bus:Fire("EMULATOR_STATE", true)
end

-- Starts a made-up party: count players from seed, at a speed.
-- Returns false and why when it cannot run.
function Sandbox:StartParty(count, seed, speed)
	count = math.max(1, math.min(200, tonumber(count) or 5))
	seed = tonumber(seed) or 1
	if not Sharing().loopback and count > CHANNEL_LIMIT then
		return false, L.SANDBOX_TOO_MANY:format(CHANNEL_LIMIT)
	end
	local usable, problem = ChannelUsable()
	if not usable then
		return false, problem
	end
	self:Stop()
	wipe(self.personas)
	wipe(self.order)
	local world = ns.SandboxWorld
	local arrival = 0
	for _, persona in ipairs(ns.SandboxParty.Make(seed, count)) do
		local random = persona.random
		persona.leaveAt = arrival + random.int(world.session.min, world.session.max) * 60
		Add(persona, arrival)
		arrival = arrival + random.int(world.arrivals.min, world.arrivals.max)
	end
	self.seed = seed
	Begin(speed)
	return true
end

-- Plays a recording back as a pretend player.
function Sandbox:StartRecording(name, speed)
	local recording = ns.SandboxRecordings[name or "tirisfal"]
	if not recording then
		return false, L.SANDBOX_NO_RECORDING
	end
	local usable, problem = ChannelUsable()
	if not usable then
		return false, problem
	end
	self:Stop()
	wipe(self.personas)
	wipe(self.order)
	local persona = { name = recording.name, class = recording.class, race = recording.race, sex = recording.sex, recording = recording, next = 1 }
	Add(persona, 0)
	persona.nextAt = recording.messages[1] and recording.messages[1].after or 0
	Begin(speed)
	return true
end

function Sandbox:Stop()
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
	Bus:Fire("EMULATOR_STATE", false)
end

-- Forgets everything the sandbox has seen, to run again from nothing.
function Sandbox:Wipe()
	self:Stop()
	wipe(self.personas)
	wipe(self.order)
	ns.Store:Clear()
	Sharing():ForgetEveryone()
	if ns.db.commsLog then
		wipe(ns.db.commsLog)
	end
	if ns.db.stats then
		wipe(ns.db.stats)
	end
end

-- ========= Answering, as the pretend players ================================
-- Someone said hello: each pretend player here answers it once, as a real
-- Quest Party would, after a short random wait.
Bus:On("PEER_HELLO", function(sender)
	if not ns.IsSandbox() then
		return
	end
	for _, name in ipairs(Sandbox.order) do
		local persona = Sandbox.personas[name]
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

-- Someone asked one of the pretend players how it stands.
Bus:On("STATE_REQUESTED", function(to)
	local persona = Sandbox.personas[to]
	if ns.IsSandbox() and persona and persona.here and not persona.recording then
		SendQuests(persona)
		SendGear(persona)
	end
end)

-- ========= Measuring ========================================================
-- What a run costs: this addon's memory (its own, apart from any other
-- addon's), the store's counts, and the messages.
function Sandbox:Measure()
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
function Sandbox:BurstTest(count)
	count = math.max(1, math.min(40, tonumber(count) or 20))
	local session = ns.Session
	if session.state ~= "connected" then
		return nil, L.SANDBOX_NO_CHANNEL
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
