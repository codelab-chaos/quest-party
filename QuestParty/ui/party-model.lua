-- PartyModel: what the party heads and a player's card show, as plain data
-- from the store and the session. No frames, so it can be checked headless.
-- ui\party.lua draws it.
local _, ns = ...
local L = ns.L

local PartyModel = {}
ns.PartyModel = PartyModel

-- For these races the game's portrait atlas is named differently.
local RACE_ATLAS = {
	scourge = "undead",
	highmountaintauren = "highmountain",
	lightforgeddraenei = "lightforged",
	zandalaritroll = "zandalari",
}

-- The game's race portrait for a race (English name) and sex (2 male,
-- 3 female), or nil when either is not known.
function PartyModel.RaceAtlas(race, sex)
	if type(race) ~= "string" or race == "" or (sex ~= 2 and sex ~= 3) then
		return nil
	end
	local name = race:lower():gsub("%s", "")
	return ("raceicon128-%s-%s"):format(RACE_ATLAS[name] or name, sex == 3 and "female" or "male")
end

local function Head(member, peer, now)
	local level = (peer and peer.level) or member.level
	return {
		name = member.name,
		class = (peer and peer.class) or member.class,
		level = level,
		zone = (peer and peer.zone) or member.zone,
		atlas = PartyModel.RaceAtlas((peer and peer.race) or member.race, (peer and peer.sex) or member.sex),
		here = peer ~= nil,
		virtual = (peer and peer.virtual) or member.emulated or nil,
		seenAgo = member.time and math.max(0, now - member.time) or nil,
		arrived = peer and peer.arrived or nil,
	}
end

-- One head per other player in the party: those here now, in the order they
-- arrived, then (with Remember players who left on) those who left, the most
-- recently seen first. Pretend players are shown in debug and the sandbox.
function PartyModel:Heads()
	local heads, gone = {}, {}
	if not ns.IsEnabled("partyHeads") then
		return heads
	end
	local now = GetServerTime()
	local pretendShown = ns.IsDebug() or ns.IsSandbox()
	local peers = ns.Session.peers
	local seen = {}
	for name, peer in pairs(peers) do
		if not ns.IsMe(name) or ns.IsSandbox() then
			if not peer.virtual or pretendShown then
				local member = ns.Store:GetMember(name) or { name = name }
				heads[#heads + 1] = Head(member, peer, now)
				seen[name] = true
			end
		end
	end
	table.sort(heads, function(a, b)
		if (a.arrived or 0) ~= (b.arrived or 0) then
			return (a.arrived or 0) < (b.arrived or 0)
		end
		return a.name < b.name
	end)
	if ns.IsEnabled("rememberPlayers") then
		for _, member in ipairs(ns.Store:GetMembers()) do
			if not seen[member.name] and not ns.IsMe(member.name) and (not member.emulated or pretendShown) then
				gone[#gone + 1] = Head(member, nil, now)
			end
		end
		table.sort(gone, function(a, b)
			return (a.seenAgo or math.huge) < (b.seenAgo or math.huge)
		end)
		for _, head in ipairs(gone) do
			heads[#heads + 1] = head
		end
	end
	return heads
end

-- "3/8": the sum of a quest's objectives.
local function Progress(objectives)
	local have, need = 0, 0
	for _, objective in pairs(objectives or {}) do
		have = have + (objective.have or 0)
		need = need + (objective.need or 0)
	end
	if need == 0 then
		return nil
	end
	return ("%d/%d"):format(have, need)
end

-- A card's objectives in their order, as lines.
local function ObjectiveLines(record)
	local list = {}
	for name, objective in pairs(record.data.objectives or {}) do
		list[#list + 1] = { name = objective.name or name, have = objective.have, need = objective.need, order = objective.order or 0 }
	end
	table.sort(list, function(a, b) return a.order < b.order end)
	return list
end

local function TheirQuests(name)
	local quests = {}
	for _, record in ipairs(ns.Store:GetCards("quest")) do
		if record.player == name and record.data.quest then
			quests[#quests + 1] = {
				questID = record.data.questID,
				quest = record.data.quest,
				progress = Progress(record.data.objectives),
				objectives = ObjectiveLines(record),
				time = record.time,
			}
		end
	end
	table.sort(quests, function(a, b) return (a.time or 0) > (b.time or 0) end)
	return quests
end

-- Quests on both of your logs: matched by quest number, or by name for
-- quests heard without one.
local function InCommon(theirs)
	local mine = {}
	local ok, snapshot = pcall(function() return ns.Collectors:GetQuestSnapshot() end)
	for _, quest in ipairs(ok and snapshot or {}) do
		mine[quest.questID or quest.quest] = quest
		mine[quest.quest] = quest
	end
	local common = {}
	for _, quest in ipairs(theirs) do
		local own = (quest.questID and mine[quest.questID]) or mine[quest.quest]
		if own then
			common[#common + 1] = { quest = quest.quest, mine = Progress(own.objectives) or "-", theirs = quest.progress or "-" }
		end
	end
	return common
end

local function ItemId(short)
	return type(short) == "string" and tonumber(short:match("^(%d+)")) or nil
end

local function Gear(member)
	local slots = {}
	for _, slot in ipairs(ns.EquipmentSlots) do
		local short = member.gear and member.gear[slot.id]
		local itemString = ns.ItemString(short)
		slots[#slots + 1] = {
			id = slot.id,
			name = slot.name,
			label = slot.label,
			column = slot.column,
			row = slot.row,
			itemString = itemString,
			itemId = itemString and ItemId(short) or nil,
		}
	end
	return slots
end

-- Everything one player's card shows. nil for someone not known at all.
function PartyModel:Card(name)
	local member = ns.Store:GetMember(name)
	local peer = ns.Session.peers[name]
	if not member and not peer then
		return nil
	end
	member = member or { name = name }
	local now = GetServerTime()
	local head = Head(member, peer, now)
	local card = head
	card.version = (peer and peer.version) or member.version
	-- The XP bar, as on the party's bars.
	local currentXP = (peer and peer.currentXP) or member.currentXP
	local maxXP = (peer and peer.maxXP) or member.maxXP
	if maxXP == 0 then
		card.xp = { have = 1, need = 1, text = L.XPBAR_MAX:format(head.level or "?") }
	elseif currentXP and maxXP then
		card.xp = { have = currentXP, need = maxXP, text = L.XPBAR_TO_GO:format(head.level or "?", 100 * (maxXP - currentXP) / maxXP) }
	end
	card.sessionXP = member.sessionXP or 0
	local today, week = ns.Day(now), 0
	for day, xp in pairs(member.xpDays or {}) do
		if ns.DaysBetween(day, today) < 7 then
			week = week + xp
		end
	end
	card.todayXP = member.xpDays and member.xpDays[today] or 0
	card.weekXP = week
	card.quests = TheirQuests(name)
	card.inCommon = InCommon(card.quests)
	card.gear = Gear(member)
	card.hasGear = member.gear ~= nil
	card.gearAgo = member.gearTime and math.max(0, now - member.gearTime) or nil
	return card
end
