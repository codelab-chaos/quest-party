-- Sharing: the bridge between the feed and the channel. It sends this
-- player's feed entries to everyone on the Quest Party channel, and turns what
-- they send into feed entries here. It also keeps the list of who is sharing.
--
-- Messages travel as addon messages, the game's own way for an addon to talk
-- to itself on other players' machines. They are addressed to the channel the
-- player chose, which is how friends who are not grouped reach each other, but
-- nothing is posted in the channel's chat: the game does not let an addon post
-- chat lines on its own, and addon messages need no key press.
-- The connection itself (joining and leaving the channel) is comms\session.lua.
--
-- On the wire (see comms\protocol.lua):
--   HELLO  "I am here", sent a moment after connecting: v version, c class,
--          l level, z zone, x XP so far this level, m XP the level needs,
--          r race (the game's English name, such as "Scourge"), g sex (2 male,
--          3 female). Everyone who hears it answers with ACK, once for each
--          newcomer, after a short random wait.
--   ACK    the same fields, so the newcomer learns who is already there.
--   PRESENCE  the same fields again, every few minutes while connected. Never
--          answered: it keeps everyone's picture current, and shows the sender
--          is still here. A player not heard from for a while is dropped.
--   ENTRY  one feed entry: t is its type, c the sender's class, s a short
--          plain summary written by the sender (see resolver.lua), the rest
--          is the entry's data. From the emulator it also carries as, the
--          name of the pretend player it stands for. A message that would be
--          too long is sent without its summary.
--   QUEST  where one of the sender's quests stands now: id, quest (its name),
--          c class, and for each objective o1 its name, h1 how many, n1 of
--          how many (then o2, h2, n2 and so on).
--
-- Every message may carry as, the pretend player it stands for (from the
-- emulator or the sandbox; see comms\origin.lua). Messages about how things
-- stand (HELLO, ACK, PRESENCE, QUEST, GEAR) carry n, a number that only grows
-- for each sender, so an old or repeated one never replaces newer news.
--   GEAR   equipped items: s<slot> is the item in that slot ("item:enchant:suffix"
--          numbers, "" for empty). One slot when it changes; the whole set, a
--          few slots a message, when answering a newcomer or a request.
--   REQUEST  "tell me how you stand": to names the player asked. Only that
--          player answers, on the channel, so everyone hears the answer. See
--          the rules in docs\side-quest.md (No storms).
--
-- Two kinds of thing are shared. Things that happened (ENTRY) are said once,
-- as they happen. How things stand (QUEST) is said in full: by everyone when
-- someone new says hello, so the newcomer's panel fills in at once. A QUEST
-- message replaces whatever was known about that quest, so a lost or repeated
-- one does no harm.
local _, ns = ...
local Bus = ns.Bus
local L = ns.L
local Protocol = ns.Protocol
local Kinds = Protocol.Kinds

local CHAT_TYPE = "CHANNEL"
local HELLO_DELAY = 2 -- seconds after connecting, so the channel has settled
-- How long to wait before saying how our quests stand, in seconds: somewhere
-- between these, picked at random, so that everyone answering one hello does
-- not speak at the same moment.
local STATE_DELAY = { min = 1, max = 4 }
-- The same for the ACK that answers a hello.
local ACK_DELAY = { min = 0.5, max = 3 }
-- How often PRESENCE goes out, and how long a player may be silent before
-- they are taken to have gone, in seconds.
local PRESENCE_SECONDS = 5 * 60
local SILENT_SECONDS = 3 * PRESENCE_SECONDS + 60
-- A REQUEST is answered once a minute at most for each player asking.
local ANSWER_GAP_SECONDS = 60
-- n counts in eighths of a second from this time, so it keeps growing across
-- reloads without getting long.
local SEQUENCE_EPOCH = 1780000000
-- Keys of an ENTRY that are about the message, not the entry's data.
local TYPE_KEY, CLASS_KEY = "t", "c"
-- On an ENTRY from the emulator: the pretend player it stands for.
local VIRTUAL_KEY = "as"
-- On an ENTRY: the sender's own plain summary of it.
local SUMMARY_KEY = "s"

-- sent      messages handed to the game
-- echoed    of those, how many the server sent back to us. It sends a
--           channel's messages to everyone on it, the sender included, so
--           this counts messages that made the whole trip
-- received  messages from other players
-- refused   messages the game would not send
local Sharing = { sent = 0, echoed = 0, received = 0, refused = 0, log = {} }
ns.Sharing = Sharing

local announced = false -- HELLO was sent for this connection
local replaying = false -- reading the log again: nothing may be sent
local complained = false -- a refused send was already reported for it

local function Session()
	return ns.Session
end

-- Every message on the channel is written down as it passes, for the debug
-- listener (ui\listener.lua) and for replay: the newest LOG_LIMIT of them,
-- oldest first. The log is saved, so a real session outlives a reload.
--   direction  "out" as it is sent, "back" when the server sends ours back to
--              us, "in" when it arrives from another player
--   sender     for "in", who sent it
--   text       the message exactly as it travelled
local LOG_LIMIT = 200

local function Log(direction, text, sender)
	local log = Sharing.log
	local record = { time = GetServerTime(), direction = direction, text = text, sender = sender }
	log[#log + 1] = record
	if #log > LOG_LIMIT then
		table.remove(log, 1)
	end
	Bus:Fire("COMMS_LOGGED", record)
end

local function MyFields()
	local _, class = UnitClass("player")
	-- Where XP stands, so a newcomer sees everyone's bar at once. At the level
	-- cap the game reports nothing more to gain (m is 0).
	local _, race = UnitRace("player")
	return {
		v = ns.version,
		c = class or "",
		l = UnitLevel("player") or 0,
		z = GetRealZoneText() or "",
		x = UnitXP("player") or 0,
		m = UnitXPMax("player") or 0,
		r = race or "",
		g = UnitSex("player") or 0,
	}
end

-- The next n for a sender (this character, or a pretend player).
local sequences = {}
local function NextSequence(sender)
	local base = math.floor((GetServerTime() - SEQUENCE_EPOCH) * 8)
	local value = math.max((sequences[sender or ""] or 0) + 1, base)
	sequences[sender or ""] = value
	return value
end
Sharing.NextSequence = NextSequence

-- Kinds that say how things stand, and so carry n.
local STATEFUL = { [Kinds.HELLO] = true, [Kinds.ACK] = true, [Kinds.PRESENCE] = true, [Kinds.QUEST] = true, [Kinds.GEAR] = true }

-- Sends one message to the channel. Returns false when there is no channel to
-- send to, or the message is too long for the game to carry.
-- key says what the message is the latest word on (see Transport:Send).
-- as, when given, is the pretend player the message stands for. The sandbox
-- never speaks as this character: only as its pretend players.
-- In loopback (Sharing.loopback, the sandbox's scale runs) nothing goes on the
-- wire: the message is read back here as if the server had sent it.
local Dispatch
local function Send(kind, fields, key, as)
	if replaying then
		return false
	end
	local virtual = as or fields[VIRTUAL_KEY]
	if not virtual and ns.IsSandbox() then
		return false
	end
	fields[VIRTUAL_KEY] = virtual
	if STATEFUL[kind] and fields.n == nil then
		fields.n = NextSequence(virtual)
	end
	local text = Protocol.Encode(kind, fields)
	if not text then
		return false
	end
	if Sharing.loopback then
		Sharing.sent = Sharing.sent + 1
		C_Timer.After(0, function()
			Dispatch(text, CHAT_TYPE, UnitName("player"), nil, true, true)
		end)
		return true
	end
	local session = Session()
	if session.state ~= "connected" or not session.channelId then
		return false
	end
	ns.Transport:Send(text, CHAT_TYPE, session.channelId, key and virtual and (virtual .. ":" .. key) or key)
	return true
end
Sharing.Send = Send

-- Counted and listed when the game takes it, not when it is queued.
Bus:On("COMMS_SENT", function(message)
	if message.chatType == CHAT_TYPE then
		Sharing.sent = Sharing.sent + 1
		Log("out", message.text)
	end
end)

-- Text from another player is shown in the panel, so the game's escape codes
-- (colors, textures, links) are made harmless first.
local function Clean(value)
	if type(value) == "string" then
		return (value:gsub("|", "||"))
	end
	return value
end

-- Welcomes are always on, so how often they appear is limited: once per
-- player in welcomeSeconds, and welcomeBurst at most in welcomeBurstSeconds.
local welcomed = {} -- [name] = when they were last welcomed
local welcomes = {} -- when the latest welcomes were, oldest first

function Sharing:MayWelcome(name)
	local now, timing = GetTime(), ns.Timing
	if welcomed[name] and now - welcomed[name] < timing.welcomeSeconds then
		return false
	end
	while welcomes[1] and now - welcomes[1] >= timing.welcomeBurstSeconds do
		table.remove(welcomes, 1)
	end
	if #welcomes >= timing.welcomeBurst then
		return false
	end
	welcomed[name] = now
	welcomes[#welcomes + 1] = now
	return true
end

local function AddPeer(name, fields, virtual)
	local peers = Session().peers
	local peer = peers[name]
	local isNew = not peer
	if isNew then
		peer = { name = name }
		peers[name] = peer
	end
	if type(fields.c) == "string" and fields.c ~= "" then
		peer.class = fields.c
	end
	if type(fields.l) == "number" then
		peer.level = fields.l
	end
	if type(fields.x) == "number" and type(fields.m) == "number" then
		peer.currentXP, peer.maxXP = fields.x, fields.m
	end
	if type(fields.z) == "string" and fields.z ~= "" then
		peer.zone = Clean(fields.z)
	end
	if fields.v ~= nil then
		peer.version = Clean(tostring(fields.v))
	end
	if type(fields.r) == "string" and fields.r ~= "" then
		peer.race = Clean(fields.r)
	end
	if type(fields.g) == "number" and fields.g > 0 then
		peer.sex = fields.g
	end
	peer.virtual = virtual or nil
	peer.heard = GetTime()
	if isNew then
		peer.arrived = GetTime()
		ns.Print(L.PEER_JOINED:format(ns.ColorName(name, peer.class), tostring(peer.version or "?")))
		-- A welcome in the feed (see data\feed-types.lua, joined). Only ours to show:
		-- it is not sent anywhere. Rate limited, so coming and going cannot flood it.
		if Sharing:MayWelcome(name) then
			Bus:Fire("ENTRY_RECEIVED", { type = "joined", player = name, class = peer.class, data = { version = peer.version }, emulated = virtual or nil })
		end
	end
	Bus:Fire("PEERS_CHANGED", peer)
end

local answered = {} -- newcomers whose hello we answered, by name
local freshness = {} -- the newest n heard, by sender and what it was about
local lastAnswer = {} -- when we last answered a REQUEST, by who asked

local function DropPeer(name)
	local peers = Session().peers
	local peer = peers[name]
	if not peer then
		return
	end
	peers[name] = nil
	answered[name], freshness[name], lastAnswer[name] = nil, nil, nil
	ns.Print(L.PEER_LEFT:format(ns.ColorName(name, peer.class)))
	Bus:Fire("PEERS_CHANGED")
end

local function DropEveryone()
	local peers = Session().peers
	wipe(answered)
	wipe(freshness)
	wipe(lastAnswer)
	if next(peers) then
		wipe(peers)
		Bus:Fire("PEERS_CHANGED")
	end
end

-- For pretend players that go without leaving the channel (the sandbox's).
function Sharing:Forget(name)
	DropPeer(name)
end

function Sharing:ForgetEveryone()
	DropEveryone()
end

-- ========= An entry on the wire =============================================
-- An ENTRY's fields are the entry's data, plus who and what it is.

-- The fields for one entry. virtual is the pretend player it stands for, when
-- it comes from the emulator.
local function EntryFields(typeName, class, data, virtual)
	local fields = {}
	for key, value in pairs(data or {}) do
		if type(value) == "string" or type(value) == "number" then
			fields[key] = value
		end
	end
	fields[TYPE_KEY] = typeName
	fields[CLASS_KEY] = class or ""
	fields[VIRTUAL_KEY] = virtual
	fields[SUMMARY_KEY] = ns.Resolver.Summary({ type = typeName, player = "", class = class, data = data or {} })
	return fields
end

-- Sends an entry. When it is too long for one message with its summary, it
-- goes without one: the summary only matters to clients that do not know the
-- type, and the entry itself matters to everyone.
local function SendEntry(fields, key)
	if Send(Kinds.ENTRY, fields, key) then
		return true
	end
	if fields[SUMMARY_KEY] == nil then
		return false
	end
	fields[SUMMARY_KEY] = nil
	return Send(Kinds.ENTRY, fields, key)
end

-- Reads an ENTRY's fields back: its type, the sender's class, its data and the
-- pretend player it stands for, if any. Returns nothing for a type this build
-- does not know. This is the one place a message becomes an entry, whoever it
-- is from.
local function ReadEntry(fields)
	local typeName, class, virtual, summary = fields[TYPE_KEY], fields[CLASS_KEY], fields[VIRTUAL_KEY], fields[SUMMARY_KEY]
	if type(typeName) ~= "string" or typeName == "" then
		return nil
	end
	local data = {}
	for key, value in pairs(fields) do
		if key ~= TYPE_KEY and key ~= CLASS_KEY and key ~= VIRTUAL_KEY and key ~= SUMMARY_KEY then
			data[key] = Clean(value)
		end
	end
	class = type(class) == "string" and class ~= "" and class or nil
	virtual = type(virtual) == "string" and virtual ~= "" and Clean(virtual) or nil
	summary = type(summary) == "string" and summary ~= "" and Clean(summary) or nil
	-- What this version can show of it: the type itself, or the generic card.
	typeName, data = ns.Resolver.Interpret(typeName, data, summary)
	return typeName, class, data, virtual
end

-- True for a message that came over the channel we are connected to.
-- channelId is the number of the channel it came through.
local function OnOurChannel(chatType, channelId)
	local session = Session()
	if chatType ~= CHAT_TYPE or session.state ~= "connected" then
		return false
	end
	-- A different number is another channel this player happens to be in.
	return not (channelId and session.channelId and channelId ~= session.channelId)
end

-- ========= Outgoing =========================================================
-- Entry types that only say where a count stands, and the data that names
-- what is being counted. Of several waiting to go out for the same thing, only
-- the newest is worth sending.
local LATEST_ONLY = {
	quest_progress = { "questID", "quest", "objectiveIndex", "objective" },
	skill = { "skill" }, -- a friend's panel merges a run of them into one row anyway
}

local function LatestKey(entry)
	local names = LATEST_ONLY[entry.type]
	if not names then
		return nil
	end
	local parts = { entry.type }
	for _, name in ipairs(names) do
		parts[#parts + 1] = tostring(entry.data[name])
	end
	return table.concat(parts, ":")
end

-- XP from kills, held back and added up per creature (ns.Timing.kill*), so
-- grinding sends one message a creature, not one a kill. gains says how many
-- kills it stands for.
local killBatches = {} -- [mob] = { data, started, timer }

local function SendKills(mob)
	local batch = killBatches[mob]
	if not batch then
		return
	end
	killBatches[mob] = nil
	if batch.timer then
		batch.timer:Cancel()
	end
	local _, class = UnitClass("player")
	SendEntry(EntryFields("xp", class, batch.data))
end

local function BatchKill(data)
	local mob, now = data.mob, GetTime()
	local batch = killBatches[mob]
	if batch then
		local xp = (batch.data.xp or 0) + (data.xp or 0)
		local gains = (batch.data.gains or 1) + 1
		for key, value in pairs(data) do
			batch.data[key] = value -- the latest level and XP for the bars
		end
		batch.data.xp, batch.data.gains = xp, gains
		batch.timer:Cancel()
	else
		batch = { data = {}, started = now }
		for key, value in pairs(data) do
			batch.data[key] = value
		end
		killBatches[mob] = batch
	end
	local timing = ns.Timing
	local wait = math.min(timing.killQuietSeconds, timing.killLongestSeconds - (now - batch.started))
	if wait <= 0 then
		SendKills(mob)
		return
	end
	batch.timer = C_Timer.NewTimer(wait, function()
		SendKills(mob)
	end)
end

Bus:On("ENTRY_OUTGOING", function(entry)
	if entry.type == "xp" and type(entry.data.mob) == "string" and entry.data.mob ~= "" then
		BatchKill(entry.data)
		return
	end
	local _, class = UnitClass("player")
	SendEntry(EntryFields(entry.type, class, entry.data), LatestKey(entry))
end)

-- ========= How our quests stand =============================================
-- One QUEST message for a quest from the quest log (see
-- Collectors:GetQuestSnapshot). If it is too long to send, objectives are left
-- off the end until it fits.
local function SendQuest(quest, class, as)
	local objectives = quest.objectives
	for count = #objectives, 0, -1 do
		local fields = { id = quest.questID, quest = quest.quest, c = class or "" }
		for index = 1, count do
			local objective = objectives[index]
			fields["o" .. index], fields["h" .. index], fields["n" .. index] = objective.objective, objective.have, objective.need
		end
		if Send(Kinds.QUEST, fields, "quest:" .. tostring(quest.questID), as) then
			return
		end
	end
end
Sharing.SendQuest = SendQuest

-- ========= Equipped items ===================================================
-- Slots go a few to a message, each message standing alone, so a lost one
-- loses only its slots. A slot's newest message wins (see n).
local GEAR_SLOTS_PER_MESSAGE = 7

-- gear is { [slot number] = "item:enchant:suffix" or "" }. slots, when given,
-- are the only ones to send; otherwise every slot in ns.EquipmentSlots.
-- changed: slots that changed since the last set, sent even when empty now,
-- so taking something off is heard.
local function SendGear(gear, class, as, slots, changed)
	local list = {}
	for _, slot in ipairs(slots or ns.EquipmentSlotIds) do
		list[#list + 1] = slot
	end
	for first = 1, #list, GEAR_SLOTS_PER_MESSAGE do
		local fields = { c = class or "" }
		local keyParts, worn = {}, slots ~= nil
		for index = first, math.min(#list, first + GEAR_SLOTS_PER_MESSAGE - 1) do
			local slot = list[index]
			fields["s" .. slot] = gear[slot] or ""
			keyParts[#keyParts + 1] = slot
			worn = worn or fields["s" .. slot] ~= "" or (changed ~= nil and changed[slot] == true)
		end
		-- In a whole set, a message of nothing but empty slots says nothing new.
		if worn then
			Send(Kinds.GEAR, fields, "gear:" .. table.concat(keyParts, ","), as)
		end
	end
end
Sharing.SendGear = SendGear

local stating = false -- a statement of our quests is already on its way

-- Says how each quest we are working on stands, a moment from now.
local function StateQuests()
	if stating then
		return
	end
	stating = true
	C_Timer.After(STATE_DELAY.min + math.random() * (STATE_DELAY.max - STATE_DELAY.min), function()
		stating = false
		if Session().state ~= "connected" or not ns.IsEnabled("quests") then
			return
		end
		local _, class = UnitClass("player")
		for _, quest in ipairs(ns.Collectors:GetQuestSnapshot()) do
			-- Only the quests being worked on: the rest is not worth a message each.
			if quest.objectivesReady and ns.QuestUnderway(quest.objectives) then
				SendQuest(quest, class)
			end
		end
		if ns.Gear and ns.IsEnabled("shareGear") then
			SendGear(ns.Gear:Snapshot(), class)
		end
	end)
end

-- Our own gear, the whole set when it changes (collectors\gear.lua), at most
-- once in ns.Timing.gearSeconds: the first change goes at once, later ones
-- wait for the time to be up and go out together, as one set.
local gearSentAt, gearTimer
local gearChanged = {} -- slots changed since the last set went out

local function SendMyGear()
	gearTimer = nil
	if Session().state ~= "connected" or not ns.IsEnabled("shareGear") then
		return
	end
	gearSentAt = GetTime()
	local _, class = UnitClass("player")
	local changed = gearChanged
	gearChanged = {}
	SendGear(ns.Gear:Snapshot(), class, nil, nil, changed)
end

Bus:On("GEAR_CHANGED", function(slot)
	gearChanged[slot] = true
	if gearTimer or Session().state ~= "connected" or not ns.IsEnabled("shareGear") then
		return -- already waiting to send, or nowhere to send it
	end
	local wait = gearSentAt and (gearSentAt + ns.Timing.gearSeconds - GetTime()) or 0
	if wait <= 0 then
		SendMyGear()
	else
		gearTimer = C_Timer.NewTimer(wait, SendMyGear)
	end
end)

-- The emulator's pretend players (emulator\emulator.lua) use the same
-- protocol as real ones. Each of their entries is sent over the channel as an
-- ENTRY that also names the pretend player. The server sends it back to us,
-- and only then is it read and shown, by the same code that reads a friend's
-- entry. So what the panel shows of them has made the real trip.
-- Returns false when there is no channel, so the caller knows nothing went out.
function Sharing:SendVirtual(persona, typeName, data)
	return SendEntry(EntryFields(typeName, persona.class, data, persona.name))
end

-- The rest of the protocol for a pretend player (the sandbox's personas):
-- fields are the hello's, as the persona stands now.
function Sharing:SendHelloAs(persona, kind)
	local fields = {}
	for key, value in pairs(persona.hello or {}) do
		fields[key] = value
	end
	fields.c = persona.class or ""
	return Send(kind or Kinds.HELLO, fields, nil, persona.name)
end

-- A REQUEST to one player: "tell me how you stand". Not sent when an answer
-- was heard a moment ago, or someone else's request is already waiting.
local REQUEST_QUIET_SECONDS = 10
local requested = {} -- when a request to each player was last sent or heard
function Sharing:Request(name)
	local now = GetTime()
	if requested[name] and now - requested[name] < REQUEST_QUIET_SECONDS then
		return false
	end
	requested[name] = now
	return Send(Kinds.REQUEST, { to = name })
end

-- ========= Incoming, from other players =====================================
local handlers = {}

-- True when n is not older than the newest heard from sender about key, and
-- remembers it. Messages without n (from older versions) always count.
local function Fresh(sender, key, n)
	if type(n) ~= "number" or replaying then
		return true
	end
	local known = freshness[sender]
	if not known then
		known = {}
		freshness[sender] = known
	end
	if known[key] and n < known[key] then
		return false
	end
	known[key] = n
	return true
end

-- Answers a newcomer's hello once: an ACK after a short random wait, so a
-- big party does not answer at the same moment, then how our quests stand.
-- In the sandbox, its pretend players answer instead (PEER_HELLO).
local function Welcome(sender)
	if answered[sender] then
		return
	end
	answered[sender] = true
	Bus:Fire("PEER_HELLO", sender)
	if ns.IsSandbox() then
		return
	end
	C_Timer.After(ACK_DELAY.min + math.random() * (ACK_DELAY.max - ACK_DELAY.min), function()
		if answered[sender] then
			Send(Kinds.ACK, MyFields())
		end
	end)
	StateQuests() -- so the newcomer sees where we are
end

handlers[Kinds.HELLO] = function(sender, fields, virtual)
	if not Fresh(sender, "hello", fields.n) then
		return
	end
	AddPeer(sender, fields, virtual)
	Welcome(sender)
end

handlers[Kinds.ACK] = function(sender, fields, virtual)
	if Fresh(sender, "hello", fields.n) then
		AddPeer(sender, fields, virtual)
	end
end

handlers[Kinds.PRESENCE] = handlers[Kinds.ACK]

handlers[Kinds.ENTRY] = function(sender, fields, virtual)
	local typeName, class, data = ReadEntry(fields)
	if not typeName then
		return
	end
	-- Someone who was here before us, and whose ACK we missed, still counts.
	if not Session().peers[sender] then
		AddPeer(sender, { c = class }, virtual)
	else
		Session().peers[sender].heard = GetTime()
	end
	Bus:Fire("ENTRY_RECEIVED", { type = typeName, player = sender, class = class or Session().peers[sender].class, data = data, emulated = virtual or nil })
end

-- Equipped items: each slot replaces what was known of it, unless older.
handlers[Kinds.GEAR] = function(sender, fields, virtual)
	local class = type(fields.c) == "string" and fields.c ~= "" and fields.c or nil
	local gear = {}
	for key, value in pairs(fields) do
		local slot = type(key) == "string" and tonumber(key:match("^s(%d+)$"))
		if slot and ns.EquipmentSlotById[slot] and type(value) == "string" and Fresh(sender, "gear" .. slot, fields.n) then
			-- Only numbers and colons: anything else is not an item.
			gear[slot] = value:match("^[%d:]*$") or ""
		end
	end
	if not next(gear) then
		return
	end
	if not Session().peers[sender] then
		AddPeer(sender, { c = class }, virtual)
	end
	ns.Store:UpdateGear(sender, class or Session().peers[sender].class, gear)
end

-- Someone asking a player how they stand. Only that player answers, at most
-- once a minute for each asker; everyone else notes that an answer is coming.
handlers[Kinds.REQUEST] = function(sender, fields)
	local to = type(fields.to) == "string" and fields.to or nil
	if not to then
		return
	end
	requested[to] = GetTime()
	local now = GetTime()
	if lastAnswer[sender] and now - lastAnswer[sender] < ANSWER_GAP_SECONDS then
		return
	end
	if ns.IsMe(to) and not ns.IsSandbox() then
		lastAnswer[sender] = now
		StateQuests()
	else
		-- One of the sandbox's pretend players, if it has one by that name.
		Bus:Fire("STATE_REQUESTED", to, sender)
	end
end

-- Where one of a friend's quests stands. It replaces what was known of it.
handlers[Kinds.QUEST] = function(sender, fields, virtual)
	local id, title = fields.id, fields.quest
	if type(id) ~= "number" or type(title) ~= "string" or title == "" or not ns.IsEnabled("quests") then
		return
	end
	if not Fresh(sender, "quest" .. id, fields.n) then
		return
	end
	local objectives = {}
	for index = 1, math.huge do
		local name, have, need = fields["o" .. index], fields["h" .. index], fields["n" .. index]
		if type(name) ~= "string" or type(have) ~= "number" or type(need) ~= "number" then
			break
		end
		objectives[index] = { index = index, objective = Clean(name), have = have, need = need }
	end
	local class = type(fields.c) == "string" and fields.c ~= "" and fields.c or nil
	if not Session().peers[sender] then
		AddPeer(sender, { c = class }, virtual)
	end
	ns.Store:HydrateQuest(sender, class or Session().peers[sender].class, { questID = id, quest = Clean(title), objectives = objectives }, ns.IsEnabled("questDetails"))
end

-- Reads one message from another player (real or pretend). Returns true when
-- it was one of ours. A handler that fails is reported once and the message
-- dropped: one bad message must never stop the rest.
local reportedFailure = false
local function Read(text, sender, virtual)
	local kind, fields = Protocol.Decode(text)
	local handler = kind and handlers[kind]
	if not handler then
		return false
	end
	local started = debugprofilestop and debugprofilestop()
	local ok, problem = pcall(handler, sender, fields, virtual)
	if started then
		Sharing.readMilliseconds = (Sharing.readMilliseconds or 0) + (debugprofilestop() - started)
	end
	if not ok then
		Sharing.failed = (Sharing.failed or 0) + 1
		if not reportedFailure then
			reportedFailure = true
			ns.Print(L.READ_FAILED:format(tostring(problem)))
		end
	end
	return ok
end

-- Every message on the channel comes here: from other players, and our own
-- back from the server. comms\origin.lua says who it is from.
-- loopback is the sandbox's own message read back without the wire.
function Dispatch(text, chatType, sender, channelId, fromMe, loopback)
	if not loopback and not OnOurChannel(chatType, channelId) then
		return
	end
	local kind, fields = Protocol.Decode(text)
	local as = kind and type(fields[VIRTUAL_KEY]) == "string" and fields[VIRTUAL_KEY] ~= "" and Clean(fields[VIRTUAL_KEY]) or nil
	local origin, from = ns.Origin(sender, fromMe, as, ns.IsSandbox(), ns.IsDebug())
	if fromMe and not loopback then
		Log("back", text)
		if kind then
			Sharing.echoed = Sharing.echoed + 1
		end
	elseif not fromMe then
		-- Logged whether or not it can be read, so the listener shows
		-- everything that arrives on the channel under Quest Party's name.
		Log("in", Clean(text), sender)
	end
	if origin ~= "peer" then
		return
	end
	if Read(text, from, as ~= nil) then
		Sharing.received = Sharing.received + 1
	end
end
Sharing.Dispatch = function(...) return Dispatch(...) end

Bus:On("COMMS_RECEIVED", function(text, chatType, sender, channelId)
	Dispatch(text, chatType, sender, channelId, false)
end)

-- Reads every logged message from other players again, oldest first, as if
-- it had just arrived: the panel is rebuilt from real traffic. Nothing is sent
-- while it runs, so a replayed hello is not answered. Returns how many were read.
function Sharing:Replay()
	local count = 0
	replaying = true
	local ok, problem = pcall(function()
		for _, record in ipairs(self.log) do
			if record.direction == "in" and record.sender and Read(record.text, record.sender, false) then
				count = count + 1
			end
		end
	end)
	replaying = false
	if not ok then
		error(problem, 0)
	end
	return count
end

Bus:On("INIT", function()
	ns.db.commsLog = ns.db.commsLog or {}
	-- Anything logged before the saved log was loaded joins it.
	for _, record in ipairs(Sharing.log) do
		ns.db.commsLog[#ns.db.commsLog + 1] = record
	end
	Sharing.log = ns.db.commsLog
	while #Sharing.log > LOG_LIMIT do
		table.remove(Sharing.log, 1)
	end
end)

-- ========= Incoming, our own coming back ====================================
-- The server sends a channel's messages to everyone on it, the sender
-- included. Our own entries are already in the panel, put there as they
-- happened, so they are only counted. A pretend player's message is not in
-- the panel yet: this is where it arrives (comms\origin.lua).
Bus:On("COMMS_ECHOED", function(text, chatType, sender, channelId)
	Dispatch(text, chatType, sender, channelId, true)
end)

-- ========= The connection ===================================================
Bus:On("CONNECTION_CHANGED", function()
	if Session().state ~= "connected" then
		announced, complained = false, false
		DropEveryone()
		return
	end
	if announced then
		return -- still connected: only the channel's number changed
	end
	announced = true
	C_Timer.After(HELLO_DELAY, function()
		if announced and not ns.IsSandbox() then
			Send(Kinds.HELLO, MyFields())
			StateQuests() -- so those already here see where we are
		end
	end)
end)

-- Every few minutes: our presence, and anyone silent too long has gone.
local function Sweep()
	if Session().state ~= "connected" then
		return
	end
	if not ns.IsSandbox() then
		Send(Kinds.PRESENCE, MyFields())
	end
	local now = GetTime()
	for name, peer in pairs(Session().peers) do
		if peer.heard and now - peer.heard > SILENT_SECONDS then
			DropPeer(name)
		end
	end
end
Sharing.Sweep = Sweep

Bus:On("READY", function()
	C_Timer.NewTicker(PRESENCE_SECONDS, Sweep)
end)

-- The game refused a message outright. Say so once per connection, with the
-- game's own reason, since nothing else would show that sharing is not working.
Bus:On("COMMS_SEND_FAILED", function(result, message)
	if not message or message.chatType ~= CHAT_TYPE then
		return
	end
	Sharing.refused = Sharing.refused + 1
	Sharing.lastRefusal = result
	if not complained then
		complained = true
		ns.Print(L.SHARE_REFUSED:format(tostring(result)))
	end
end)

-- A line for /qp share: what has gone over the channel this session.
function Sharing:Status()
	local session, config = Session(), ns.db.connection
	if session.state ~= "connected" then
		return L.SHARE_STATUS_OFF
	end
	local line = L.SHARE_STATUS:format(config.name, self.sent, self.echoed, self.received, session:Count())
	if self.refused > 0 then
		line = line .. L.SHARE_STATUS_REFUSED:format(self.refused, tostring(self.lastRefusal))
	end
	return line
end

-- Someone leaving the channel is no longer sharing.
Bus:On("READY", function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
	frame:SetScript("OnEvent", function(_, _, _, playerName, _, _, _, _, _, _, channelName)
		local config = ns.db.connection
		if type(playerName) ~= "string" or type(channelName) ~= "string" then
			return
		end
		if (issecretvalue and (issecretvalue(playerName) or issecretvalue(channelName))) or not config.enabled then
			return
		end
		if channelName:lower() == config.name:lower() then
			DropPeer(Ambiguate(playerName, "none"))
		end
	end)
end)
