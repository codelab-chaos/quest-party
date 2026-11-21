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

-- How a player looks in a portrait: { atlas, class }. Yourself from the game,
-- anyone else from what they told the party.
function PartyModel:Portrait(name)
	if name == ns.MyName() or ns.IsMe(name) then
		local _, race = UnitRace("player")
		local _, class = UnitClass("player")
		return { atlas = PartyModel.RaceAtlas(race, UnitSex("player")), class = class }
	end
	local member = ns.Store:GetMember(name) or {}
	local peer = ns.Session.peers[name]
	return {
		atlas = PartyModel.RaceAtlas((peer and peer.race) or member.race, (peer and peer.sex) or member.sex),
		class = (peer and peer.class) or member.class,
	}
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
		playerId = (peer and peer.player) or member.playerId,
		seenAgo = member.time and math.max(0, now - member.time) or nil,
		arrived = peer and peer.arrived or nil,
	}
end

-- One head per other player in the party: those here now, in the order they
-- arrived, then (with Remember players who left on) those who left, the most
-- recently seen first. Pretend players are shown in debug mode only.
-- Your own head comes first, from the game itself, so your own
-- card (quests, gear) can be tried on a real character.
function PartyModel:Heads()
	local heads, gone = {}, {}
	if not ns.IsEnabled("partyHeads") then
		return heads
	end
	local now = GetServerTime()
	local pretendShown = ns.IsDebug() -- dev mode's pretend players
	local peers = ns.Session.peers
	local seen = {}
	for name, peer in pairs(peers) do
		if not ns.IsMe(name) then
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
	-- Your own head, first: you are a player like any other, and your own
	-- card opens from it.
	do
		local name = ns.MyName()
		if not seen[name] then
			local _, class = UnitClass("player")
			local _, race = UnitRace("player")
			local me = {
				class = class, level = UnitLevel("player"), zone = GetRealZoneText(),
				race = race, sex = UnitSex("player"), arrived = 0,
				player = ns.Sharing.PlayerId(),
			}
			table.insert(heads, 1, Head(ns.Store:GetMember(name) or { name = name }, me, now))
			heads[1].name = name
			seen[name] = true
		end
	end
	if ns.IsEnabled("rememberPlayers") then
		for _, member in ipairs(ns.Store:GetMembers()) do
			if not seen[member.name] and not ns.IsMe(member.name) and (not member.emulated or pretendShown) then
				gone[#gone + 1] = Head(member, nil, now)
			end
		end
		table.sort(gone, function(a, b)
			return (a.seenAgo or math.huge) < (b.seenAgo or math.huge)
		end)
		-- One tab per player: a character whose player is already shown (here
		-- on another character, or seen more lately on one) is an alt. With
		-- Show alts on, alts come after everyone else, greyed like anyone gone
		-- (alt = true); off, they have no tab. Their history stays either way.
		local players = { [ns.Sharing.PlayerId()] = true } -- your own other characters too
		for _, head in ipairs(heads) do
			if head.playerId then players[head.playerId] = true end
		end
		local alts = {}
		for _, head in ipairs(gone) do
			if not (head.playerId and players[head.playerId]) then
				heads[#heads + 1] = head
				if head.playerId then players[head.playerId] = true end
			elseif ns.IsEnabled("showAlts") then
				head.alt = true
				alts[#alts + 1] = head
			end
		end
		for _, head in ipairs(alts) do heads[#heads + 1] = head end
	end
	-- No more than the cap (ui\\view-model.lua): those here before those
	-- gone, alts last, the latest seen first.
	return ns.ViewModel.Cap(heads, ns.ViewModel.PartyCap(), function(head) return head.name end, function(head)
		if head.here then return math.huge end
		return -(head.seenAgo or math.huge) - (head.alt and 1e9 or 0)
	end)
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

-- Marks their quests that are on your log too with how far you are (mine),
-- matched by quest number, or by name for quests heard without one. Those
-- come first, newest first within each.
local function MarkShared(theirs)
	local mine = {}
	local ok, snapshot = pcall(function() return ns.Collectors:GetQuestSnapshot() end)
	for _, quest in ipairs(ok and snapshot or {}) do
		mine[quest.questID or quest.quest] = quest
		mine[quest.quest] = quest
	end
	for _, quest in ipairs(theirs) do
		local own = (quest.questID and mine[quest.questID]) or mine[quest.quest]
		if own then
			quest.mine = Progress(own.objectives) or "-"
		end
	end
	table.sort(theirs, function(a, b)
		if (a.mine ~= nil) ~= (b.mine ~= nil) then
			return a.mine ~= nil
		end
		return (a.time or 0) > (b.time or 0)
	end)
	return theirs
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

-- How a stat key reads: ours (data\slots.lua, GearStatOrder), the game's
-- own name for it, or the key itself.
local function StatLabel(key)
	for _, stat in ipairs(ns.GearStatOrder) do
		if stat.key == key then
			return stat.label
		end
	end
	local own = _G[key]
	if type(own) == "string" and own ~= "" then
		return own:sub(1, 1):upper() .. own:sub(2) -- "damage per second" reads as a label
	end
	return key
end

-- Stats as lines in order: the known ones first, then the rest by name.
local function StatLines(stats)
	local lines, used = {}, {}
	for _, stat in ipairs(ns.GearStatOrder) do
		local value = stats[stat.key]
		if type(value) == "number" and value ~= 0 then
			lines[#lines + 1] = { label = stat.label, value = value }
		end
		used[stat.key] = true
	end
	local rest = {}
	for key, value in pairs(stats) do
		if not used[key] and type(value) == "number" and value ~= 0 then
			rest[#rest + 1] = { label = StatLabel(key), value = value }
		end
	end
	table.sort(rest, function(a, b) return a.label < b.label end)
	for _, line in ipairs(rest) do
		lines[#lines + 1] = line
	end
	return lines
end

-- One equipped item on a player's card: its name, quality, item level,
-- the level it needs and its stats as lines. loading while the game has not
-- loaded it yet; nil for an empty slot.
function PartyModel:SlotDetails(name, slotId)
	local member = ns.Store:GetMember(name)
	local itemString = member and member.gear and ns.ItemString(member.gear[slotId])
	if not itemString then
		return nil
	end
	local slot = ns.EquipmentSlotById[slotId]
	local item = ns.ReadItem(itemString)
	if not item then
		return { loading = true, slotLabel = slot and slot.label }
	end
	return {
		name = item.name,
		link = item.link,
		quality = item.quality,
		level = item.level,
		required = item.required,
		slotLabel = slot and slot.label,
		lines = StatLines(item.stats),
	}
end

-- A player's stats added up over every item known on their card. loading
-- says some item has not loaded yet, so the sums will grow.
function PartyModel:GearTotals(name)
	local member = ns.Store:GetMember(name)
	local totals, loading = {}, false
	for _, slotId in ipairs(ns.EquipmentSlotIds) do
		local itemString = member and member.gear and ns.ItemString(member.gear[slotId])
		if itemString then
			local item = ns.ReadItem(itemString)
			if item then
				for key, value in pairs(item.stats) do
					if type(value) == "number" then
						totals[key] = (totals[key] or 0) + value
					end
				end
			else
				loading = true
			end
		end
	end
	return { lines = StatLines(totals), loading = loading }
end

-- A player's professions for their Info tab, each with its icon: all of
-- them as they last said (yours from the skill list), and any others their
-- skill-up rows told of (players on older versions). Highest first.
function PartyModel.Professions(name, member)
	local said
	if ns.IsMe(name) then
		said = ns.ProfessionsCollector and ns.ProfessionsCollector.list
	else
		local peer = ns.Session.peers[name]
		said = (peer and peer.professions) or (member and member.professions)
	end
	local ranks, names = {}, {}
	for _, item in ipairs(said or {}) do
		local profession = ns.ProfessionById[item.id]
		if profession then
			local label = profession.localName or profession.name
			ranks[label] = item.rank
			names[label] = profession
		end
	end
	for skill, level in pairs(member and member.skills or {}) do
		local profession = ns.ProfessionNamed(skill)
		local label = profession and (profession.localName or profession.name) or skill
		if not ranks[label] or (tonumber(level) or 0) > ranks[label] then
			ranks[label] = tonumber(level) or 0
			names[label] = profession
		end
	end
	local lines = {}
	for label, rank in pairs(ranks) do
		local profession = names[label]
		local icon = profession and ("|TInterface\\Icons\\" .. profession.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
		lines[#lines + 1] = { label = icon .. label, value = tostring(rank), rank = rank, sortName = label }
	end
	table.sort(lines, function(a, b)
		if a.rank ~= b.rank then return a.rank > b.rank end
		return a.sortName < b.sortName
	end)
	return lines
end

-- The Info tab: sections of label and value lines, in order. Add a section
-- here and the card shows it.
local function Info(card, member)
	local about = {}
	if card.zone then
		about[#about + 1] = { label = L.INFO_ZONE, value = card.zone }
	end
	about[#about + 1] = { label = L.INFO_SEEN, value = card.here and L.CARD_ONLINE or L.CARD_AS_OF:format(ns.Ago(card.seenAgo or 0)) }
	if card.version then
		about[#about + 1] = { label = L.INFO_VERSION, value = card.version }
	end
	local experience = {}
	if card.xp then
		experience[#experience + 1] = { label = L.INFO_LEVEL, value = card.xp.text }
	end
	experience[#experience + 1] = { label = L.INFO_XP_SESSION, value = ns.Comma(card.sessionXP) }
	experience[#experience + 1] = { label = L.INFO_XP_TODAY, value = ns.Comma(card.todayXP) }
	experience[#experience + 1] = { label = L.INFO_XP_WEEK, value = ns.Comma(card.weekXP) }
	return {
		{ title = L.INFO_PROFESSIONS, lines = PartyModel.Professions(member.name, member), empty = L.INFO_NONE_HEARD },
		{ title = L.INFO_ABOUT, lines = about },
		{ title = L.INFO_EXPERIENCE, lines = experience },
	}
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
		card.xp = { have = currentXP, need = maxXP, text = L.XPBAR_TO_GO:format(head.level or "?", math.ceil(100 * (maxXP - currentXP) / maxXP)) }
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
	card.quests = MarkShared(TheirQuests(name))
	card.info = Info(card, member)
	card.gear = Gear(member)
	card.hasGear = member.gear ~= nil
	card.gearAgo = member.gearTime and math.max(0, now - member.gearTime) or nil
	return card
end
