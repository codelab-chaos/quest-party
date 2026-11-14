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
--          l level, z zone. Everyone who hears it answers with ACK.
--   ACK    the same fields, so the newcomer learns who is already there.
--   ENTRY  one feed entry: t is its type, c the sender's class, the rest is
--          the entry's data. From the emulator it also carries as, the name
--          of the pretend player it stands for.
--   QUEST  where one of the sender's quests stands now: id, quest (its name),
--          c class, and for each objective o1 its name, h1 how many, n1 of
--          how many (then o2, h2, n2 and so on).
--
-- Two kinds of thing are shared. Things that happened (ENTRY) are said once,
-- as they happen. How things stand (QUEST) is said in full: by everyone when
-- someone new says hello, so the newcomer's panel fills in at once. A QUEST
-- message replaces whatever was known about that quest, so a lost or repeated
-- one does no harm.
local addonName, ns = ...
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
-- Keys of an ENTRY that are about the message, not the entry's data.
local TYPE_KEY, CLASS_KEY = "t", "c"
-- On an ENTRY from the emulator: the pretend player it stands for.
local VIRTUAL_KEY = "as"

-- sent      messages handed to the game
-- echoed    of those, how many the server sent back to us. It sends a
--           channel's messages to everyone on it, the sender included, so
--           this counts messages that made the whole trip
-- received  messages from other players
-- refused   messages the game would not send
local Sharing = { sent = 0, echoed = 0, received = 0, refused = 0, log = {} }
ns.Sharing = Sharing

local announced = false -- HELLO was sent for this connection
local complained = false -- a refused send was already reported for it

local function Session()
	return ns.Session
end

-- Every message on the channel is written down as it passes, for the debug
-- listener (ui\listener.lua): the newest LOG_LIMIT of them, oldest first.
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
	return {
		v = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?",
		c = class or "",
		l = UnitLevel("player") or 0,
		z = GetRealZoneText() or "",
	}
end

-- Sends one message to the channel. Returns false when there is no channel to
-- send to, or the message is too long for the game to carry.
-- key says what the message is the latest word on (see Transport:Send).
local function Send(kind, fields, key)
	local session = Session()
	if session.state ~= "connected" or not session.channelId then
		return false
	end
	local text = Protocol.Encode(kind, fields)
	if not text then
		return false
	end
	ns.Transport:Send(text, CHAT_TYPE, session.channelId, key)
	return true
end

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

local function AddPeer(name, fields)
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
	if type(fields.z) == "string" and fields.z ~= "" then
		peer.zone = Clean(fields.z)
	end
	if fields.v ~= nil then
		peer.version = Clean(tostring(fields.v))
	end
	if isNew then
		ns.Print(L.PEER_JOINED:format(ns.ColorName(name, peer.class), tostring(peer.version or "?")))
	end
	Bus:Fire("PEERS_CHANGED", peer)
end

local function DropPeer(name)
	local peers = Session().peers
	local peer = peers[name]
	if not peer then
		return
	end
	peers[name] = nil
	ns.Print(L.PEER_LEFT:format(ns.ColorName(name, peer.class)))
	Bus:Fire("PEERS_CHANGED")
end

local function DropEveryone()
	local peers = Session().peers
	if next(peers) then
		wipe(peers)
		Bus:Fire("PEERS_CHANGED")
	end
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
	return fields
end

-- Reads an ENTRY's fields back: its type, the sender's class, its data and the
-- pretend player it stands for, if any. Returns nothing for a type this build
-- does not know. This is the one place a message becomes an entry, whoever it
-- is from.
local function ReadEntry(fields)
	local typeName, class, virtual = fields[TYPE_KEY], fields[CLASS_KEY], fields[VIRTUAL_KEY]
	if type(typeName) ~= "string" or not ns.FeedTypes[typeName] then
		return nil
	end
	local data = {}
	for key, value in pairs(fields) do
		if key ~= TYPE_KEY and key ~= CLASS_KEY and key ~= VIRTUAL_KEY then
			data[key] = Clean(value)
		end
	end
	class = type(class) == "string" and class ~= "" and class or nil
	virtual = type(virtual) == "string" and virtual ~= "" and Clean(virtual) or nil
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

Bus:On("ENTRY_OUTGOING", function(entry)
	local _, class = UnitClass("player")
	Send(Kinds.ENTRY, EntryFields(entry.type, class, entry.data), LatestKey(entry))
end)

-- ========= How our quests stand =============================================
-- One QUEST message for a quest from the quest log (see
-- Collectors:GetQuestSnapshot). If it is too long to send, objectives are left
-- off the end until it fits.
local function SendQuest(quest, class)
	local objectives = quest.objectives
	for count = #objectives, 0, -1 do
		local fields = { id = quest.questID, quest = quest.quest, c = class or "" }
		for index = 1, count do
			local objective = objectives[index]
			fields["o" .. index], fields["h" .. index], fields["n" .. index] = objective.objective, objective.have, objective.need
		end
		if Send(Kinds.QUEST, fields, "quest:" .. tostring(quest.questID)) then
			return
		end
	end
end

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
	end)
end

-- The emulator's pretend players (emulator\emulator.lua) use the same
-- protocol as real ones. Each of their entries is sent over the channel as an
-- ENTRY that also names the pretend player. The server sends it back to us,
-- and only then is it read and shown, by the same code that reads a friend's
-- entry. So what the panel shows of them has made the real trip.
-- Returns false when there is no channel, so the caller knows nothing went out.
function Sharing:SendVirtual(persona, typeName, data)
	return Send(Kinds.ENTRY, EntryFields(typeName, persona.class, data, persona.name))
end

-- ========= Incoming, from other players =====================================
local handlers = {}

handlers[Kinds.HELLO] = function(sender, fields)
	AddPeer(sender, fields)
	Send(Kinds.ACK, MyFields())
	StateQuests() -- so the newcomer sees where we are
end

handlers[Kinds.ACK] = function(sender, fields)
	AddPeer(sender, fields)
end

handlers[Kinds.ENTRY] = function(sender, fields)
	local typeName, class, data, virtual = ReadEntry(fields)
	if not typeName or virtual then
		return -- unknown, or a pretend player from someone else's emulator
	end
	-- Someone who was here before us, and whose ACK we missed, still counts.
	if not Session().peers[sender] then
		AddPeer(sender, { c = class })
	end
	Bus:Fire("ENTRY_RECEIVED", { type = typeName, player = sender, class = class or Session().peers[sender].class, data = data })
end

-- Where one of a friend's quests stands. It replaces what was known of it.
handlers[Kinds.QUEST] = function(sender, fields)
	local id, title = fields.id, fields.quest
	if type(id) ~= "number" or type(title) ~= "string" or title == "" or not ns.IsEnabled("quests") then
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
		AddPeer(sender, { c = class })
	end
	ns.Store:HydrateQuest(sender, class or Session().peers[sender].class, { questID = id, quest = Clean(title), objectives = objectives }, ns.IsEnabled("questDetails"))
end

Bus:On("COMMS_RECEIVED", function(text, chatType, sender, channelId)
	if not OnOurChannel(chatType, channelId) then
		return
	end
	-- Logged whether or not it can be read, so the listener shows everything
	-- that arrives on the channel under Quest Party's name.
	Log("in", Clean(text), sender)
	local kind, fields = Protocol.Decode(text)
	local handler = kind and handlers[kind]
	if handler then
		Sharing.received = Sharing.received + 1
		handler(sender, fields)
	end
end)

-- ========= Incoming, our own coming back ====================================
-- The server sends a channel's messages to everyone on it, the sender
-- included. Our own entries are already in the panel, put there as they
-- happened, so they are only counted. A pretend player's entry is not in the
-- panel yet: this is where it arrives.
Bus:On("COMMS_ECHOED", function(text, chatType, _, channelId)
	if not OnOurChannel(chatType, channelId) then
		return
	end
	Log("back", text)
	local kind, fields = Protocol.Decode(text)
	if not kind then
		return
	end
	Sharing.echoed = Sharing.echoed + 1
	if kind ~= Kinds.ENTRY then
		return
	end
	local typeName, class, data, virtual = ReadEntry(fields)
	if typeName and virtual then
		Bus:Fire("ENTRY_RECEIVED", { type = typeName, player = virtual, class = class, data = data, emulated = true })
	end
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
		if announced then
			Send(Kinds.HELLO, MyFields())
			StateQuests() -- so those already here see where we are
		end
	end)
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
