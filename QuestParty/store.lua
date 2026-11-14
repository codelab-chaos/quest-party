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
	if card.kind == "quest" and entry.data.questID then
		parts[#parts + 1] = "id"
		parts[#parts + 1] = tostring(entry.data.questID)
		return table.concat(parts, KEY_SEPARATOR)
	end
	for _, key in ipairs(card.keys) do
		parts[#parts + 1] = tostring(entry.data[key])
	end
	return table.concat(parts, KEY_SEPARATOR)
end

-- Older saves and the emulator identify quests by title. Adopt the stable ID
-- when the owner supplies it, retaining the existing progress and start time.
local function FindCard(entry, card)
	local key = CardKey(entry, card)
	local record = db.cards[key]
	if not record and card.kind == "quest" and entry.data.questID then
		local legacyKey = CardKey({ player = entry.player, data = { quest = entry.data.quest } }, card)
		record = db.cards[legacyKey]
		if record then
			db.cards[legacyKey] = nil
			db.cards[key] = record
		end
	end
	return record, key
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

local function IsNewer(a, b)
	local aTime, bTime = a.time or 0, b.time or 0
	if aTime ~= bTime then return aTime > bTime end
	local aSequence, bSequence = a.sequence or 0, b.sequence or 0
	if aSequence ~= bSequence then return aSequence > bSequence end
	return (a.order or 0) > (b.order or 0)
end

local function NormalizeObjectives(record)
	local grouped = {}
	for key, objective in pairs(record.data.objectives) do
		local name = ns.ObjectiveName(objective.name or key) or key
		local group = grouped[name]
		if not group then
			grouped[name] = { objective = objective, order = objective.order or 0 }
		else
			group.order = math.min(group.order, objective.order or 0)
			if IsNewer(objective, group.objective) then group.objective = objective end
		end
	end
	local names = {}
	for name in pairs(grouped) do names[#names + 1] = name end
	table.sort(names, function(a, b)
		if grouped[a].order ~= grouped[b].order then return grouped[a].order < grouped[b].order end
		return a < b
	end)
	local objectives = {}
	for index, name in ipairs(names) do
		local objective = grouped[name].objective
		objective.order, objective.name = index, name
		objectives[name] = objective
	end
	record.data.objectives, record.data.objectiveCount = objectives, #names
end

function Store:Init()
	db = ns.db
	db.feed = db.feed or {}
	db.cards = db.cards or {}
	db.members = db.members or {}
	db.trackers = nil -- replaced by cards
	DropOldCards()
	for _, record in pairs(db.cards) do NormalizeObjectives(record) end
	for _, entry in ipairs(db.feed) do
		if entry.type == "quest_progress" then
			entry.data.objective = ns.ObjectiveName(entry.data.objective) or entry.data.objective
		end
	end
	Resequence()
end

function Store:Clear()
	wipe(db.feed)
	wipe(db.cards)
	wipe(db.members)
	Bus:Fire("STORE_CHANGED")
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
	local record, key = FindCard(entry, card)
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
	if card.kind == "quest" and entry.data.questID then
		record.data.questID = entry.data.questID
		record.data.quest = entry.data.quest
	end
	record.class = entry.class
	record.time = entry.time
	record.sequence = NextSequence()
	return record
end

-- Restore the owner's current log without replaying acceptance, completion,
-- chat echoes or outgoing events. A snapshot replaces old objective lines, but
-- keeps the saved start time and kill/XP tallies on the existing card.
function Store:HydrateQuest(player, class, quest, includeDetails)
	local record = TouchCard({ player = player, class = class, time = GetServerTime(), data = quest }, ns.FeedTypes.quest_accepted.card)
	if includeDetails then
		local previous, objectives = record.data.objectives, {}
		for order, entry in ipairs(quest.objectives) do
			local objective = previous[entry.objective]
			for _, candidate in pairs(previous) do
				if candidate.index == entry.index then objective = candidate; break end
			end
			if not objective or objective.have ~= entry.have or objective.need ~= entry.need then
				objective = { time = record.time, sequence = record.sequence }
			end
			objective.name, objective.index, objective.order = entry.objective, entry.index, order
			objective.have, objective.need = entry.have, entry.need
			objectives[entry.objective] = objective
		end
		record.data.objectives, record.data.objectiveCount = objectives, #quest.objectives
	end
	Bus:Fire("STORE_CHANGED")
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
	local objective
	local key = data.objective
	if data.objectiveIndex then
		for name, candidate in pairs(record.data.objectives) do
			if candidate.index == data.objectiveIndex then
				objective = candidate
				if name ~= key then record.data.objectives[name] = nil end
				break
			end
		end
	end
	objective = objective or record.data.objectives[key]
	if not objective then
		record.data.objectiveCount = record.data.objectiveCount + 1
		objective = { order = record.data.objectiveCount }
	end
	record.data.objectives[key] = objective
	objective.name, objective.index = data.objective, data.objectiveIndex or objective.index
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
	local _, key = FindCard(entry, def.card)
	db.cards[key] = nil
	return true
end

-- Reattach a saved, unidentified objective once the owning player's quest log
-- supplies its ID. Other players' cards are never inferred from our quest log.
function Store:IdentifyQuest(player, questID, title, objectiveName)
	local card = ns.FeedTypes.quest_progress.card
	local entry = { player = player, data = { questID = questID, quest = title } }
	local record = FindCard(entry, card)
	local changed = record and (record.data.questID ~= questID or record.data.quest ~= title)
	if record then
		record.data.questID, record.data.quest = questID, title
	end
	if objectiveName then
		local oldKey = CardKey({ player = player, data = { quest = ns.L.UNKNOWN_QUEST } }, card)
		local old = db.cards[oldKey]
		local objective = old and old.data.objectives[objectiveName]
		if objective then
			if not record then
				entry.class, entry.time = old.class, objective.time or old.time
				record = TouchCard(entry, card)
			end
			local current = record.data.objectives[objectiveName]
			if not current then
				record.data.objectiveCount = record.data.objectiveCount + 1
				current = { order = record.data.objectiveCount }
				record.data.objectives[objectiveName] = current
			end
			if not current.time or (objective.time or old.time) > current.time then
				current.have, current.need = objective.have, objective.need
				current.time, current.sequence = objective.time or old.time, objective.sequence or old.sequence
			end
			record.time = math.max(record.time, objective.time or old.time)
			record.sequence = math.max(record.sequence, objective.sequence or old.sequence)
			old.data.objectives[objectiveName] = nil
			old.data.objectiveCount = old.data.objectiveCount - 1
			if not next(old.data.objectives) then db.cards[oldKey] = nil end
			for _, row in ipairs(db.feed) do
				if row.player == player and row.type == "quest_progress"
					and row.data.quest == ns.L.UNKNOWN_QUEST and row.data.objective == objectiveName then
					row.data.quest, row.data.questID = title, questID
				end
			end
			changed = true
		end
	end
	if changed then Bus:Fire("STORE_CHANGED") end
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
	if entry.type == "quest_progress" then
		entry.data.objective = ns.ObjectiveName(entry.data.objective) or entry.data.objective
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

-- True for a card worth showing. A quest card is shown while the quest is
-- underway (see ns.QuestUnderway). With quest details off no objective counts
-- are kept, so there is nothing to judge by and every quest card is shown.
local function WorthShowing(record)
	if record.kind ~= "quest" or not ns.IsEnabled("questDetails") then
		return true
	end
	return ns.QuestUnderway(record.data.objectives)
end

-- All cards of one kind. Unordered: the view sorts.
-- shownOnly leaves out the cards that are kept but not worth showing.
function Store:GetCards(kindName, shownOnly)
	local result = {}
	local kind = ns.CardKinds[kindName]
	if not kind or not ns.IsEnabled(kind.setting) then
		return result
	end
	for key, record in pairs(db.cards) do
		if record.kind == kindName and (not shownOnly or WorthShowing(record)) then
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
