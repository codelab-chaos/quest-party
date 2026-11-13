-- Session: who we are sharing feeds with, and how we find each other.
--
-- Two ways to be connected, and both can apply to the same person:
--   party  automatic. On joining a group we say HELLO to it, and everyone running
--          Quest Party answers.
--   link   a friend added once by name. Links are saved, and each side says HELLO
--          by whisper when it logs in, so being grouped is not needed.
local addonName, ns = ...
local Bus = ns.Bus
local L = ns.L
local Protocol = ns.Protocol
local Kinds = Protocol.Kinds

local HELLO_DELAY = 2 -- seconds to wait after a roster change before announcing

local Session = {
	peers = {}, -- [name] = { name, class, level, zone, version, party, link }
	pendingLinks = {}, -- [lowercase name] = true, links we asked for
}
ns.Session = Session

local helloTimer

-- ========= Who am I =========================================================
local function MyFields()
	local _, class = UnitClass("player")
	return {
		v = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?",
		c = class or "",
		l = UnitLevel("player") or 0,
		z = GetRealZoneText() or "",
	}
end

local function GroupChatType()
	if IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local function Send(kind, fields, chatType, target)
	local text = Protocol.Encode(kind, fields)
	if text then
		ns.Transport:Send(text, chatType, target)
	end
end

-- ========= Peers ============================================================
function Session:IsConnected(name)
	return self.peers[name] ~= nil
end

function Session:Count()
	local count = 0
	for _ in pairs(self.peers) do
		count = count + 1
	end
	return count
end

-- how is "party" or "link".
local function AddPeer(name, fields, how)
	local peer = Session.peers[name]
	local isNew = not peer
	if isNew then
		peer = { name = name }
		Session.peers[name] = peer
	end
	peer.class = fields.c ~= "" and fields.c or peer.class
	peer.level = fields.l
	peer.zone = fields.z ~= "" and fields.z or peer.zone
	peer.version = fields.v
	peer[how] = true
	if isNew then
		ns.Print(L.PEER_JOINED:format(ns.ColorName(name, peer.class), tostring(peer.version)))
	end
	Bus:Fire("PEERS_CHANGED", peer)
end

-- Removes one way of being connected. The peer goes when no way is left.
local function DropPeer(name, how)
	local peer = Session.peers[name]
	if not peer or not peer[how] then
		return
	end
	peer[how] = nil
	if not peer.party and not peer.link then
		Session.peers[name] = nil
		ns.Print(L.PEER_LEFT:format(ns.ColorName(name, peer.class)))
	end
	Bus:Fire("PEERS_CHANGED")
end

-- ========= Party ============================================================
local function AnnounceToGroup()
	helloTimer = nil
	local chatType = GroupChatType()
	if chatType and ns.IsEnabled("share") then
		Send(Kinds.HELLO, MyFields(), chatType)
	end
end

local function OnRosterChanged()
	if not GroupChatType() then
		for name in pairs(Session.peers) do
			DropPeer(name, "party")
		end
		return
	end
	for name, peer in pairs(Session.peers) do
		if peer.party and not (UnitInParty(name) or UnitInRaid(name)) then
			DropPeer(name, "party")
		end
	end
	-- One HELLO shortly after the roster settles, not one per change.
	if not helloTimer then
		helloTimer = C_Timer.NewTimer(HELLO_DELAY, AnnounceToGroup)
	end
end

-- ========= Links ============================================================
-- Asks a friend, by character name, to share feeds. They get a prompt.
function Session:Link(name)
	self.pendingLinks[name:lower()] = true
	Send(Kinds.LINK, MyFields(), "WHISPER", name)
end

function Session:Unlink(name)
	for linked in pairs(ns.db.links) do
		if linked:lower() == name:lower() then
			ns.db.links[linked] = nil
			Send(Kinds.UNLINK, {}, "WHISPER", linked)
			DropPeer(linked, "link")
			return linked
		end
	end
end

local function AcceptLink(name)
	ns.db.links[name] = true
	Send(Kinds.LINK_OK, MyFields(), "WHISPER", name)
end

StaticPopupDialogs["QUESTPARTY_LINK_REQUEST"] = {
	text = L.LINK_REQUEST,
	button1 = ACCEPT,
	button2 = DECLINE,
	OnAccept = function(_, data)
		AcceptLink(data.name)
		AddPeer(data.name, data.fields, "link")
	end,
	timeout = 60,
	whileDead = true,
	hideOnEscape = true,
}

-- ========= Incoming =========================================================
local handlers = {}

handlers[Kinds.HELLO] = function(sender, fields, channel)
	if channel == "WHISPER" then
		if not ns.db.links[sender] then
			return -- a whispered hello only counts from someone we linked with
		end
		AddPeer(sender, fields, "link")
	else
		AddPeer(sender, fields, "party")
	end
	if ns.IsEnabled("share") then
		Send(Kinds.ACK, MyFields(), "WHISPER", sender)
	end
end

handlers[Kinds.ACK] = function(sender, fields)
	local how = ns.db.links[sender] and "link" or "party"
	if how == "party" and not (UnitInParty(sender) or UnitInRaid(sender)) then
		return
	end
	AddPeer(sender, fields, how)
end

handlers[Kinds.ENTRY] = function(sender, fields)
	local peer = Session.peers[sender]
	if not peer or not fields.t then
		return
	end
	local data = {}
	for key, value in pairs(fields) do
		if key ~= "t" then
			data[key] = value
		end
	end
	Bus:Fire("ENTRY_RECEIVED", { type = fields.t, player = sender, class = peer.class, data = data })
end

handlers[Kinds.LINK] = function(sender, fields)
	if ns.db.links[sender] then
		AcceptLink(sender) -- already linked on our side, just confirm
		AddPeer(sender, fields, "link")
		return
	end
	StaticPopup_Show("QUESTPARTY_LINK_REQUEST", sender, nil, { name = sender, fields = fields })
end

handlers[Kinds.LINK_OK] = function(sender, fields)
	if not Session.pendingLinks[sender:lower()] and not ns.db.links[sender] then
		return -- we never asked
	end
	Session.pendingLinks[sender:lower()] = nil
	ns.db.links[sender] = true
	AddPeer(sender, fields, "link")
end

handlers[Kinds.UNLINK] = function(sender)
	ns.db.links[sender] = nil
	DropPeer(sender, "link")
end

Bus:On("COMMS_RECEIVED", function(text, channel, sender)
	local kind, fields = Protocol.Decode(text)
	local handler = kind and handlers[kind]
	if handler then
		handler(sender, fields, channel)
	end
end)

-- ========= Outgoing =========================================================
-- Sends one of our own entries to everyone we are connected to: once to the group,
-- and by whisper to linked friends who are not in it.
Bus:On("ENTRY_OUTGOING", function(entry)
	if not ns.IsEnabled("share") then
		return
	end
	local fields = { t = entry.type }
	for key, value in pairs(entry.data) do
		fields[key] = value
	end
	local text = Protocol.Encode(Kinds.ENTRY, fields)
	if not text then
		return
	end
	local chatType = GroupChatType()
	local sentToGroup = false
	for name, peer in pairs(Session.peers) do
		if peer.party and chatType then
			if not sentToGroup then
				ns.Transport:Send(text, chatType)
				sentToGroup = true
			end
		elseif peer.link then
			ns.Transport:Send(text, "WHISPER", name)
		end
	end
end)

-- ========= Startup ==========================================================
Bus:On("INIT", function()
	ns.db.links = ns.db.links or {}
end)

Bus:On("READY", function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	frame:SetScript("OnEvent", OnRosterChanged)
	OnRosterChanged()
	-- Tell linked friends we are on. Whoever logs in second reaches the other.
	if ns.IsEnabled("share") then
		for name in pairs(ns.db.links) do
			Send(Kinds.HELLO, MyFields(), "WHISPER", name)
		end
	end
end)
