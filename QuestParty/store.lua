-- Store: the only owner of feed state. It turns incoming entries into three things:
--   feed     a capped, newest-first list of things that happened
--   cards    persistent cards for things still going on (one per player per quest)
--   members  a roster of everyone we have heard from
-- It does not care where entries come from (emulator now, addon comms later).
--
-- A quest card record looks like:
--   { kind = "quest", player, class, created, time, sequence,
--     data = { quest, objectives = { [name] = { have, need, order, time, sequence } },
--              objectiveCount, kills, xp } }
local _, ns = ...
local Bus = ns.Bus

local MAX_FEED = 200
local KEY_SEPARATOR = "\031"

local Store = {}
ns.Store = Store

local db

local function CardKey(entry, card)
	local parts = { card.kind, entry.player }
	for _, key in ipairs(card.keys) do
		parts[#parts + 1] = tostring(entry.data[key])
	end
	return table.concat(parts, KEY_SEPARATOR)
end

-- A counter that orders everything by when it last changed. Seconds are too coarse:
-- a kill and the quest credit it causes land in the same second.
local function NextSequence()
	db.sequence = (db.sequence or 0) + 1
	return db.sequence
end

-- Renumbers every feed row, card and objective by timestamp. Data saved by older
-- builds has no sequence, and this also keeps the counter small. Ties keep their order.
local function Resequence()
	local items = {}
	for i = #db.feed, 1, -1 do -- the feed is stored newest first
		items[#items + 1] = db.feed[i]
	end
	for _, record in pairs(db.cards) do
		items[#items + 1] = record
		for _, objective in pairs(record.data.objectives) do
			objective.time = objective.time or record.time
			items[#items + 1] = objective
		end
	end
	for index, item in ipairs(items) do
		item.sortIndex = index
	end
	table.sort(items, function(a, b)
		if a.time ~= b.time then
			return a.time < b.time
		end
		local aSequence, bSequence = a.sequence or 0, b.sequence or 0
		if aSequence ~= bSequence then
			return aSequence < bSequence
		end
		return a.sortIndex < b.sortIndex
	end)
	for index, item in ipairs(items) do
		item.sequence = index
		item.sortIndex = nil
	end
	db.sequence = #items
end

-- Drops cards saved in a shape this build does not understand.
local function DropOldCards()
	for key, record in pairs(db.cards) do
		if not ns.CardKinds[record.kind] or type(record.data) ~= "table" or type(record.data.objectives) ~= "table" then
			db.cards[key] = nil
		end
	end
end

function Store:Init()
	db = ns.db
	db.feed = db.feed or {}
	db.cards = db.cards or {}
	db.members = db.members or {}
	db.trackers = nil -- replaced by cards
	DropOldCards()
	self:Prune()
	Resequence()
	C_Timer.NewTicker(ns.Timing.pruneSeconds, function()
		if Store:Prune() then
			Bus:Fire("STORE_CHANGED")
		end
	end)
end

function Store:Clear()
	wipe(db.feed)
	wipe(db.cards)
	wipe(db.members)
	Bus:Fire("STORE_CHANGED")
end

-- Removes cards that have gone too long without an update. Returns true if any went.
function Store:Prune()
	local cutoff = GetServerTime() - ns.Timing.expireSeconds
	local removed = false
	for key, card in pairs(db.cards) do
		if card.time < cutoff then
			db.cards[key] = nil
			removed = true
		end
	end
	return removed
end

local function TouchMember(entry, def)
	local member = db.members[entry.player]
	if not member then
		member = { name = entry.player }
		db.members[entry.player] = member
	end
	member.class = entry.class or member.class
	member.time = entry.time
	if def.member then
		for memberField, dataKey in pairs(def.member) do
			if entry.data[dataKey] ~= nil then
				member[memberField] = entry.data[dataKey]
			end
		end
	end
end

local function AddFeed(entry, def)
	entry.sequence = NextSequence()
	table.insert(db.feed, 1, entry)
	for i = #db.feed, MAX_FEED + 1, -1 do
		db.feed[i] = nil
	end
	Bus:Fire("FEED_ADDED", entry, def)
end

-- Finds or creates the card an entry belongs to, and stamps it as just updated.
local function TouchCard(entry, card)
	local key = CardKey(entry, card)
	local record = db.cards[key]
	if not record then
		record = {
			kind = card.kind,
			player = entry.player,
			created = entry.time,
			data = { objectives = {}, objectiveCount = 0, kills = 0, xp = 0 },
		}
		for _, dataKey in ipairs(card.keys) do
			record.data[dataKey] = entry.data[dataKey]
		end
		db.cards[key] = record
	end
	record.class = entry.class
	record.time = entry.time
	record.sequence = NextSequence()
	return record
end

-- Card behaviors, keyed by card.mode. Each returns true when the entry should
-- also become a feed row.
local cardModes = {}

function cardModes.open(entry, def)
	local record = TouchCard(entry, def.card)
	Bus:Fire("CARD_UPDATED", record, def, entry)
	return true
end

function cardModes.objective(entry, def)
	local record = TouchCard(entry, def.card)
	local data = entry.data
	local objective = record.data.objectives[data.objective]
	if not objective then
		record.data.objectiveCount = record.data.objectiveCount + 1
		objective = { order = record.data.objectiveCount }
		record.data.objectives[data.objective] = objective
	end
	local wasDone = objective.have ~= nil and objective.have >= objective.need
	objective.have = data.have
	objective.need = data.need
	objective.time = entry.time
	objective.sequence = record.sequence
	local isDone = data.have >= data.need
	if isDone and not wasDone then
		return true -- the feed row announces it
	end
	Bus:Fire("CARD_UPDATED", record, def, entry)
	return false
end

function cardModes.tally(entry, def)
	local card = def.card
	local record = TouchCard(entry, card)
	local data = record.data
	data[card.count] = (data[card.count] or 0) + 1
	for key in pairs(card.sum) do
		data[key] = (data[key] or 0) + (entry.data[key] or 0)
	end
	Bus:Fire("CARD_UPDATED", record, def, entry)
	return false
end

function cardModes.close(entry, def)
	db.cards[CardKey(entry, def.card)] = nil
	return true
end

function Store:Ingest(entry)
	local def = ns.FeedTypes[entry.type]
	if not def or not entry.player or type(entry.data) ~= "table" then
		return
	end
	if not ns.IsEnabled(def.setting) then
		return
	end
	if def.requires then
		for _, key in ipairs(def.requires) do
			if entry.data[key] == nil then
				return
			end
		end
	end
	entry.time = entry.time or GetServerTime()
	TouchMember(entry, def)

	local toFeed = true
	if def.card then
		toFeed = cardModes[def.card.mode](entry, def)
	end
	if toFeed then
		AddFeed(entry, def)
	end
	Bus:Fire("STORE_CHANGED")
end

-- ========= Queries ==========================================================
-- Queries skip anything whose feature switch is off, so a switch hides existing
-- rows and cards without deleting them.

-- feedFilter is true for everything, or a key matched against the type's filters.
function Store:GetFeed(feedFilter)
	local result = {}
	for _, entry in ipairs(db.feed) do
		local def = ns.FeedTypes[entry.type]
		if def and ns.IsEnabled(def.setting) and (feedFilter == true or def.filters[feedFilter]) then
			result[#result + 1] = entry
		end
	end
	return result
end

-- All cards of one kind. Unordered: the view sorts.
function Store:GetCards(kindName)
	local result = {}
	local kind = ns.CardKinds[kindName]
	if not kind or not ns.IsEnabled(kind.setting) then
		return result
	end
	for key, record in pairs(db.cards) do
		if record.kind == kindName then
			record.key = key
			result[#result + 1] = record
		end
	end
	return result
end

function Store:GetMembers()
	local result = {}
	for _, member in pairs(db.members) do
		result[#result + 1] = member
	end
	table.sort(result, function(a, b)
		return a.name < b.name
	end)
	return result
end

Bus:On("INIT", function()
	Store:Init()
end)

Bus:On("ENTRY_RECEIVED", function(entry)
	Store:Ingest(entry)
end)

Bus:On("SETTING_CHANGED", function()
	Bus:Fire("STORE_CHANGED")
end)

-- Someone we share with shows on the roster as soon as they connect.
Bus:On("PEERS_CHANGED", function(peer)
	if peer then
		local member = db.members[peer.name]
		if not member then
			member = { name = peer.name }
			db.members[peer.name] = member
		end
		member.class = peer.class or member.class
		member.level = peer.level or member.level
		member.zone = peer.zone or member.zone
		member.time = GetServerTime()
	end
	Bus:Fire("STORE_CHANGED")
end)
