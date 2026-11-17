-- ViewModel: turns store state into plain row descriptions for the panel.
-- The panel only draws rows, it never reads the store or the feed type data.
--
-- A row is:
--   { kind, icon, badge, title, right, lines, summary, progress, quest, highlight, pulse, sequence }
--   badge     drawn in place of the icon: { style, text }
--   kind      "feed", "progress" (one objective), "tracker" (a whole quest) or "member"
--   lines     the detail lines under the title: { text, right, progress = { have, need } }
--   summary   what to show after the title when the row is drawn on one line
--   progress  overall { have, need }, drawn as a strip in the one-line view
--   quest     set when the row is about a quest, so clicking it can jump to that quest
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
		title = ns.ColorName(member.name, member.class),
		right = ns.Ago(now - (member.time or now)),
		lines = lines,
		summary = status,
	}
end

-- One unfinished objective: the two-line progress indicator used on the feed tabs.
local function ProgressRow(record, objective, now)
	local age = now - objective.time
	local detail = L.PROGRESS_DETAIL:format(ns.ColorName(record.player, record.class), record.data.quest)
	local progress = { have = objective.have, need = objective.need }
	return {
		kind = "progress",
		sequence = objective.sequence,
		icon = ns.CardKinds[record.kind].icon,
		title = objective.name,
		right = L.CARD_COUNT:format(objective.have, objective.need),
		lines = { { text = detail, progress = progress } },
		summary = detail,
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

-- One quest across the party. For each member on it: who, when they started and
-- their kills, then a line per objective.
local function TrackerRow(quest, records, now)
	table.sort(records, function(a, b)
		return a.player < b.player
	end)
	local lines = {}
	local overall = { have = 0, need = 0 }
	local newest, sequence = records[1].time, 0
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
		end
		if #objectives == 0 then
			lines[#lines + 1] = { text = L.TRACKER_NO_OBJECTIVES }
		end

		newest = math.max(newest, record.time)
		sequence = math.max(sequence, record.sequence or 0)
	end
	local age = now - newest
	return {
		kind = "tracker",
		sequence = sequence,
		icon = ns.CardKinds[records[1].kind].icon,
		title = quest,
		right = ns.Ago(age),
		lines = lines,
		summary = L.TRACKER_MEMBERS:format(#records),
		progress = overall.need > 0 and overall or nil,
		quest = quest,
		questID = records[1].data.questID,
		pulse = (age <= PULSE_SECONDS) and ("tracker/" .. quest .. "/" .. sequence),
	}
end

-- Groups one kind of card by quest, for the party tracker.
local function TrackerRows(kindName, now)
	local byQuest, order = {}, {}
	for _, record in ipairs(ns.Store:GetCards(kindName, true)) do
		local key = record.data.questID or record.data.quest
		if not byQuest[key] then
			byQuest[key] = {}
			order[#order + 1] = key
		end
		table.insert(byQuest[key], record)
	end
	local rows = {}
	for _, key in ipairs(order) do
		local records = byQuest[key]
		rows[#rows + 1] = TrackerRow(records[1].data.quest, records, now)
	end
	return rows
end

local function FeedRow(entry, now)
	local def = ns.FeedTypes[entry.type]
	local title, detail, fields = ns.Resolver.Text(entry, def)
	local subtitle = fields.player
	if detail then
		subtitle = subtitle .. ", " .. detail
	end
	local progress
	-- A kill's row has no bar: it would read as quest progress.
	if def.experience and entry.data.maxXP and entry.data.maxXP > 0 and not KillXP(entry.data) then
		progress = { have = entry.data.currentXP, need = entry.data.maxXP }
	end
	return {
		kind = "feed",
		sequence = entry.sequence or 0,
		icon = def.icon,
		title = title,
		right = ns.Ago(now - entry.time),
		lines = { { text = subtitle, progress = progress } },
		summary = subtitle,
		progress = progress,
		quest = entry.data.quest,
		highlight = def.highlight,
		badge = def.badge and entry.data[def.badge.field] ~= nil and { style = def.badge.style, text = tostring(entry.data[def.badge.field]) } or nil,
		pulse = (now - entry.time <= PULSE_SECONDS) and (entry.player .. "/" .. entry.time .. "/" .. title),
	}
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
	local name = UnitName("player")
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
	for _, member in ipairs(members) do
		do
			local bar = {
				name = member.name,
				class = member.class,
				level = member.level,
				lastXP = member.lastXP,
				lastMob = member.lastMob,
				me = member.me,
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
	for _, row in ipairs(timeline) do
		rows[#rows + 1] = row
	end
	return rows
end
