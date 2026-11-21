-- ViewModel: turns store state into plain row descriptions for the panel.
-- The panel only draws rows, it never reads the store or the feed type data.
--
-- A row is:
--   { kind, icon, badge, title, right, lines, summary, progress, quest, highlight, pulse, sequence }
--   badge     drawn in place of the icon: { style, text } (a level's crest)
--   mark      the square on the right, by id (data\marks.lua)
--   kind      "feed", "progress" (one objective), "tracker" (a whole quest) or "member"
--   lines     the detail lines under the title: { text, right, progress = { have, need } }
--   summary   what to show after the title when the row is drawn on one line
--   progress  overall { have, need }, drawn as a strip in the one-line view
--   quest     set when the row is about a quest, so clicking it can jump to that quest
--   shared    a quest you and someone else are both on: the row glows
--   player, class  whose row it is: its avatar on the left
--   grouped   that player is in your game party or raid: the row is marked
--   pulse     set when the row changed in the last few seconds. It is a string unique
--             to that change, so the panel can flash the row exactly once.
-- Progress rows and feed rows share one timeline, ordered by when each last changed, so
-- a row that gets an update moves to the newest end of the list, the way a chat line would.
local _, ns = ...
local L = ns.L

local PULSE_SECONDS = 3

local ViewModel = {}
ns.ViewModel = ViewModel

-- Template fields and an entry's text come from the resolver (resolver.lua).
ViewModel.Fields = ns.Resolver.Fields
local KillXP = ns.Resolver.KillXP


-- A card's objectives in the order they were first seen.
local function SortedObjectives(record)
	local result = {}
	for name, objective in pairs(record.data.objectives) do
		result[#result + 1] = {
			name = objective.name or name,
			have = objective.have,
			need = objective.need,
			order = objective.order,
			time = objective.time or record.time,
			sequence = objective.sequence or record.sequence or 0,
		}
	end
	table.sort(result, function(a, b)
		return a.order < b.order
	end)
	return result
end

local function MemberRow(member, now)
	local status
	if member.zone then
		status = L.MEMBER_STATUS:format(member.level or L.UNKNOWN, member.zone)
	else
		status = L.MEMBER_STATUS_NO_ZONE:format(member.level or L.UNKNOWN)
	end
	local lines = { { text = status } }
	local peer = ns.Session.peers[member.name]
	if peer then
		lines[#lines + 1] = { text = L.DONE_COLOR:format(L.MEMBER_CONNECTED:format(tostring(peer.version))) }
	end
	return {
		kind = "member",
		icon = ns.CardIcons.member,
		mark = "joined",
		title = ns.ColorName(member.name, member.class),
		right = ns.Ago(now - (member.time or now)),
		lines = lines,
		summary = status,
	}
end

-- One unfinished objective: the two-line progress indicator used on the feed tabs.

local function ProgressRow(record, objective, now)
	local age = now - objective.time
	local detail = record.data.quest -- who: the avatar, and the tooltip (name)
	local progress = { have = objective.have, need = objective.need }
	return {
		kind = "progress",
		mark = "questTaken", -- the game's yellow ! (data\marks.lua)
		player = record.player, -- the row's avatar (ui\\panel.lua)
		class = record.class,
		sequence = objective.sequence,
		icon = ns.CardKinds[record.kind].icon,
		title = objective.name,
		right = L.CARD_COUNT:format(objective.have, objective.need),
		lines = { { text = detail, progress = progress } },
		summary = detail,
		name = ns.ColorName(record.player, record.class),
		progress = progress,
		quest = record.data.quest,
		questID = record.data.questID,
		pulse = (age <= PULSE_SECONDS) and (record.key .. "/" .. objective.name .. "/" .. objective.have),
	}
end

local function ProgressRows(kindName, now)
	local rows = {}
	for _, record in ipairs(ns.Store:GetCards(kindName, true)) do
		for _, objective in ipairs(SortedObjectives(record)) do
			if objective.have < objective.need then
				rows[#rows + 1] = ProgressRow(record, objective, now)
			end
		end
	end
	return rows
end

-- A quest a party is on, as sections: one per objective, in the quest's
-- order. In each, the players still working on it, the latest to make
-- progress first (a mini feed), and those done with it, collapsed together.
--   { name, need, active = { { name, class, have, need, ago, me } },
--     done = { the same, the latest done first } }
function ViewModel.QuestSections(party, now)
	local sections, byName = {}, {}
	for _, member in ipairs(party) do
		for _, objective in ipairs(member.objectives) do
			local section = byName[objective.name]
			if not section then
				section = { name = objective.name, need = objective.need, order = objective.order or #sections + 1, active = {}, done = {} }
				byName[objective.name] = section
				sections[#sections + 1] = section
			end
			local entry = {
				name = member.name,
				class = member.class,
				have = objective.have,
				need = objective.need,
				time = objective.time or 0,
				ago = now - (objective.time or now),
				me = member.me,
			}
			local list = objective.have >= objective.need and section.done or section.active
			list[#list + 1] = entry
		end
	end
	table.sort(sections, function(a, b) return a.order < b.order end)
	local function Latest(a, b)
		if a.time ~= b.time then return a.time > b.time end
		return a.name < b.name
	end
	for _, section in ipairs(sections) do
		table.sort(section.active, Latest)
		table.sort(section.done, Latest)
	end
	return sections
end

-- One quest across the party. For each member on it: who, when they started and
-- their kills, then a line per objective.
local function TrackerRow(quest, records, now)
	table.sort(records, function(a, b)
		return a.player < b.player
	end)
	local lines = {}
	local overall = { have = 0, need = 0 }
	local newest, sequence = records[1].time, 0
	-- Two or more on it: a party doing it together, one column each
	-- (ui\panel.lua, LayoutParty): who is ahead, who is done, what is left.
	local party = #records >= 2 and {} or nil
	-- One player on it: their objectives, for the quest card layouts
	-- (ui\\quest-card.lua).
	local objectiveList = {}
	for _, record in ipairs(records) do
		local data = record.data
		local name = ns.ColorName(record.player, record.class)
		local startedSeconds = now - record.created
		local started = startedSeconds < 60 and L.STARTED_NOW or L.STARTED_AGO:format(ns.Ago(startedSeconds))
		if data.kills > 0 then
			lines[#lines + 1] = { text = L.TRACKER_WHO_KILLS:format(name, started, data.kills, ns.Comma(data.xp)) }
		else
			lines[#lines + 1] = { text = L.TRACKER_WHO:format(name, started) }
		end

		local objectives = SortedObjectives(record)
		for _, objective in ipairs(objectives) do
			local done = objective.have >= objective.need
			lines[#lines + 1] = {
				text = done and L.DONE_COLOR:format(objective.name) or objective.name,
				right = L.CARD_COUNT:format(objective.have, objective.need),
				progress = { have = objective.have, need = objective.need },
			}
			overall.have = overall.have + math.min(objective.have, objective.need)
			overall.need = overall.need + objective.need
			objectiveList[#objectiveList + 1] = { name = objective.name, have = objective.have, need = objective.need, done = done }
		end
		if #objectives == 0 then
			lines[#lines + 1] = { text = L.TRACKER_NO_OBJECTIVES }
		end
		if party then
			local have, need, parts = 0, 0, {}
			for _, objective in ipairs(objectives) do
				have = have + math.min(objective.have, objective.need)
				need = need + objective.need
				parts[#parts + 1] = { name = objective.name, have = objective.have, need = objective.need, time = objective.time, order = objective.order }
			end
			party[#party + 1] = {
				name = record.player,
				class = record.class,
				have = have,
				need = need,
				done = need > 0 and have >= need,
				objectives = parts,
				me = ns.IsMe(record.player) or nil,
			}
		end

		newest = math.max(newest, record.time)
		sequence = math.max(sequence, record.sequence or 0)
	end
	local age = now - newest
	local single = #records == 1 and records[1] or nil
	local sections, doneCount = party and ViewModel.QuestSections(party, now) or nil, 0
	for _, member in ipairs(party or {}) do
		if member.done then doneCount = doneCount + 1 end
	end
	local ready = overall.need > 0 and overall.have >= overall.need
	return {
		kind = "tracker",
		-- The game's yellow ! (data\marks.lua); its ? once every objective is
		-- done, ready to hand in.
		mark = ready and "questDone" or "questTaken",
		ready = ready or nil,
		player = single and single.player or nil, -- one player on it: their avatar
		class = single and single.class or nil,
		objectives = single and objectiveList or nil,
		started = single and (now - single.created) or nil,
		sequence = sequence,
		icon = ns.CardKinds[records[1].kind].icon,
		title = quest,
		right = ns.Ago(age),
		lines = lines,
		summary = L.TRACKER_MEMBERS:format(#records),
		progress = overall.need > 0 and overall or nil,
		party = party,
		sections = sections, -- the party card's sections (ViewModel.QuestSections)
		doneCount = party and doneCount or nil,
		quest = quest,
		questID = records[1].data.questID,
		pulse = (age <= PULSE_SECONDS) and ("tracker/" .. quest .. "/" .. sequence),
	}
end

-- Groups one kind of card by quest, for the party tracker.
local function TrackerRows(kindName, now)
	-- A quest shows while anyone's card for it is still worth showing; then
	-- everyone on it is in, finished ones too, so a party card shows who is done.
	local active = {}
	for _, record in ipairs(ns.Store:GetCards(kindName, true)) do
		active[record.data.questID or record.data.quest] = true
	end
	local byQuest, order = {}, {}
	for _, record in ipairs(ns.Store:GetCards(kindName)) do
		local key = record.data.questID or record.data.quest
		if active[key] then
			if not byQuest[key] then
				byQuest[key] = {}
				order[#order + 1] = key
			end
			table.insert(byQuest[key], record)
		end
	end
	local rows = {}
	for _, key in ipairs(order) do
		local records = byQuest[key]
		rows[#rows + 1] = TrackerRow(records[1].data.quest, records, now)
	end
	return rows
end

-- A row's badge: a fixed mark (a quest's ! or ?), or a field's value (a
-- level-up's new level), drawn in place of the icon (ui\\panel.lua).
local function Badge(def, entry)
	local badge = def.badge
	if not badge then return nil end
	if badge.mark then return { style = badge.style, text = badge.mark } end
	local value = entry.data[badge.field]
	return value ~= nil and { style = badge.style, text = tostring(value) } or nil
end

-- A row's square (data\marks.lua): its type's, unless the row belongs to
-- another filter (feedOnlyIf: XP from a kill is a Kills row), then that
-- filter's, so the square always matches the filter icon that hides it.
local function MarkFor(entry, def)
	local category = ns.FeedCategory(entry, def)
	if category ~= def.setting then
		local gutter = ns.GutterBySetting[category]
		if gutter and gutter.mark then return gutter.mark end
	end
	return def.mark
end

local function FeedRow(entry, now)
	local def = ns.FeedTypes[entry.type]
	local stampKey = ns.Stamping:KeyFor(entry)
	local title, detail, fields = ns.Resolver.Text(entry, def)
	-- Who it was is the row's avatar, and its tooltip's first line (name):
	-- the second line is only what else there is to say.
	local subtitle = detail or ""
	local progress
	-- A kill's row has no bar: it would read as quest progress.
	if def.experience and entry.data.maxXP and entry.data.maxXP > 0 and not KillXP(entry.data) then
		progress = { have = entry.data.currentXP, need = entry.data.maxXP }
	end
	return {
		kind = "feed",
		player = entry.player, -- the row's avatar (ui\\panel.lua)
		class = entry.class,
		sequence = entry.sequence or 0,
		icon = def.icon,
		mark = MarkFor(entry, def), -- the square on the right
		markIcon = def.markIcon and def.markIcon(entry) or nil, -- its own art, if any
		title = title,
		right = ns.Ago(now - entry.time),
		lines = { { text = subtitle, progress = progress } },
		summary = subtitle ~= "" and subtitle or nil,
		name = fields.player, -- in its color, for the tooltip (ui\\panel.lua)
		progress = progress,
		quest = entry.data.quest,
		questID = entry.data.questID,
		-- Stamps (stamps.lua): the card's key, what is on it, and the entry to
		-- stamp it from here.
		stampKey = stampKey,
		stamps = ns.Stamping:For(stampKey),
		entry = stampKey and entry or nil,
		highlight = def.highlight,
		tint = def.tint, -- the row's light by kind (data\\themes.lua)
		badge = Badge(def, entry),
		pulse = (now - entry.time <= PULSE_SECONDS) and (entry.player .. "/" .. entry.time .. "/" .. title),
	}
end

-- One entry as a feed row, for elsewhere (the dock: ui\dock.lua).
function ViewModel:FeedRowFor(entry)
	return FeedRow(entry, GetServerTime())
end

-- ========= The party's XP bars ==============================================
-- One bar for everyone on the channel: this player first (from the game
-- itself, so it is always there and current), then everyone sharing on the
-- channel and, in debug mode, the emulator's players, sorted by name. Each
-- bar is:
--   { name, class, level, have, need, maxLevel, text, lastXP, lastMob,
--     health, power, powerType }  (health and power in percent, when known)
--   have, need  the XP bar's fill, nil when that player's XP is not known yet
--   text        the level and how far there is to go, for the bar's right side
-- This player's own record: the game's numbers, with the last kill as the
-- store saw it.
local function Me()
	local name = ns.MyName()
	local _, class = UnitClass("player")
	local saved = ns.Store:GetMember(name) or {}
	return {
		name = name,
		class = class,
		level = UnitLevel("player"),
		currentXP = UnitXP("player"),
		maxXP = UnitXPMax("player"),
		lastXP = saved.lastXP,
		lastMob = saved.lastMob,
		me = true,
	}
end

-- ========= The players shown: a cap ========================================
-- At most this many players show at once (the Players shown slider, 10 to
-- 20): a busy channel stays readable and light to draw.
function ViewModel.PartyCap()
	return math.floor(ns.GetSlider("partyCap") or 10)
end

-- Keeps the cap's worth of a list, in its own order: you first, then your
-- game group, then whoever was active most lately (recent gives a time,
-- larger is later). name(item) names each.
function ViewModel.Cap(list, cap, name, recent)
	if #list <= cap then return list end
	local ranked = {}
	for index, item in ipairs(list) do
		local who = name(item)
		local rank = ns.IsMe(who) and 0 or (ns.Group:Has(who) and 1 or 2)
		ranked[#ranked + 1] = { item = item, index = index, rank = rank, recent = recent(item) or 0 }
	end
	table.sort(ranked, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.recent ~= b.recent then return a.recent > b.recent end
		return a.index < b.index
	end)
	local keep = {}
	for index = 1, cap do keep[ranked[index].index] = true end
	local kept = {}
	for index, item in ipairs(list) do
		if keep[index] then kept[#kept + 1] = item end
	end
	return kept
end

function ViewModel:PartyBars()
	local bars = {}
	if not ns.IsEnabled("levels") then
		return bars
	end
	local members = { Me() }
	for _, member in ipairs(ns.Store:GetMembers()) do
		local inParty = ns.Session.peers[member.name] ~= nil or (member.emulated and ns.IsDebug())
		if inParty and not ns.IsMe(member.name) and member.name ~= members[1].name then
			members[#members + 1] = member
		end
	end
	members = ViewModel.Cap(members, ViewModel.PartyCap(), function(member) return member.name end, function(member)
		local peer = ns.Session.peers[member.name]
		return (peer and peer.heard) or member.time
	end)
	for _, member in ipairs(members) do
		do
			local bar = {
				name = member.name,
				class = member.class,
				level = member.level,
				lastXP = member.lastXP,
				lastMob = member.lastMob,
				me = member.me,
				grouped = ns.Group:Has(member.name) or nil, -- in your game group
			}
			-- Health and power: yours from the game, a friend's from the channel.
			local vitals
			if member.me then
				vitals = ns.VitalsCollector and ns.VitalsCollector.reading
			else
				local peer = ns.Session.peers[member.name]
				vitals = peer and peer.vitals
			end
			if vitals then
				bar.health, bar.power, bar.powerType = vitals.h, vitals.p, vitals.t
			end
			-- Away from the keyboard: still here, unlike someone gone (no bar).
			if member.me or ns.IsMe(member.name) then
				bar.afk, bar.afkSince = ns.Away and ns.Away.afk or nil, ns.Away and ns.Away.since
			else
				local peer = ns.Session.peers[member.name]
				bar.afk, bar.afkSince = peer and peer.afk, peer and peer.afkSince
			end
			-- The level goes in the middle of the bar; text is what is left.
			bar.levelText = tostring(member.level or "?")
			if member.maxXP == 0 then
				bar.maxLevel = true
				bar.text = L.XPBAR_BAR_MAX
			elseif member.maxXP and member.currentXP then
				bar.have, bar.need = member.currentXP, member.maxXP
				bar.text = L.XPBAR_BAR_DONE:format(math.floor(100 * member.currentXP / member.maxXP))
			else
				bar.text = ""
			end
			bars[#bars + 1] = bar
		end
	end
	return bars
end

-- Quests you and someone else are both on: a quest card of yours and one of
-- another player's. By quest id and by title (older entries have no id).
function ViewModel:SharedQuests()
	local mine, theirs = {}, {}
	-- Every card, shown or not: being on the same quest counts before any
	-- objective moves.
	for _, record in ipairs(ns.Store:GetCards("quest")) do
		local into = ns.IsMe(record.player) and mine or theirs
		if record.data.questID then into["id:" .. record.data.questID] = true end
		if record.data.quest then into["title:" .. record.data.quest] = true end
	end
	local shared = {}
	for key in pairs(mine) do
		if theirs[key] then shared[key] = true end
	end
	return shared
end

local function IsShared(shared, row)
	return (row.questID and shared["id:" .. row.questID]) or (row.quest and shared["title:" .. row.quest]) or false
end
ViewModel.IsShared = IsShared

function ViewModel:Build(filterId)
	local filter = ns.FilterById[filterId] or ns.Filters[1]
	local now = GetServerTime()
	local rows = {}

	if filter.members then
		for _, member in ipairs(ns.Store:GetMembers()) do
			rows[#rows + 1] = MemberRow(member, now)
		end
	end

	-- The timeline. Chat order puts the newest last.
	local timeline = {}
	local function Add(list)
		for _, row in ipairs(list) do
			timeline[#timeline + 1] = row
		end
	end
	-- The gutter's filters hide kinds of rows from the feed views.
	local kind = filter.progress and ns.CardKinds[filter.progress]
	if filter.progress and not (filter.feed and kind and ns.GutterHides(kind.setting)) then
		Add(ProgressRows(filter.progress, now))
	end
	if filter.tracker then
		Add(TrackerRows(filter.tracker, now))
	end
	if filter.feed then
		-- The store keeps the feed newest first. Walk it backwards so that rows saved
		-- before sequences existed (all 0) still tie-break oldest first.
		local feed = ns.Store:GetFeed(filter.feed)
		for i = #feed, 1, -1 do
			local entry = feed[i]
			if not ns.GutterHides(ns.FeedCategory(entry, ns.FeedTypes[entry.type])) then
				timeline[#timeline + 1] = FeedRow(entry, now)
			end
		end
	end
	for index, row in ipairs(timeline) do
		row.index = index
	end
	local newestLast = ns.IsEnabled("chatOrder")
	table.sort(timeline, function(a, b)
		local first, second = a, b
		if not newestLast then
			first, second = b, a
		end
		if first.sequence ~= second.sequence then
			return first.sequence < second.sequence
		end
		if first.title ~= second.title then
			return first.title < second.title
		end
		return first.index < second.index
	end)
	-- Quests you share with someone glow (ui\panel.lua), wherever they show,
	-- and in the Quest tab they lead. Rows of players in your game group are
	-- marked (grouped).
	local shared = self:SharedQuests()
	for _, row in ipairs(timeline) do
		row.shared = IsShared(shared, row) or nil
		row.grouped = row.player and ns.Group:Has(row.player) or nil
	end
	if filter.tracker and not filter.feed then
		local first, rest = {}, {}
		for _, row in ipairs(timeline) do
			if row.shared then first[#first + 1] = row else rest[#rest + 1] = row end
		end
		timeline = first
		for _, row in ipairs(rest) do timeline[#timeline + 1] = row end
	end
	for _, row in ipairs(timeline) do
		rows[#rows + 1] = row
	end
	return rows
end
