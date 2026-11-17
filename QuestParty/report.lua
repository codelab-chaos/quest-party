-- Report: the 123 tab's numbers, as plain data from the stats (stats.lua):
-- every player's tallies added up over the days kept, by kind (data\stats.lua,
-- StatKinds), filtered by kind and player. ui\report.lua draws it.
--
-- Report:Build(kind, player) gives { mode, rows, total } where mode says how
-- to draw the rows:
--   stacked  no kind, no player: a row per kind, its total split by player
--            ({ label, value, segments = { { player, class, value } } })
--   players  a kind, no player: a row per player, biggest first
--            ({ label, class, value, share of the biggest })
--   shares   a player (a kind or not): a row per kind, that player's part of
--            the party's total ({ label, class, value, share of the total })
local _, ns = ...

local Report = {}
ns.Report = Report

local function ClassOf(player)
	local member = ns.Store:GetMember(player)
	local peer = ns.Session.peers[player]
	return (peer and peer.class) or (member and member.class) or nil
end

-- Everyone with tallies, by name.
function Report:Players()
	return ns.Stats:Players()
end

function Report:Kinds()
	return ns.StatKinds
end

local function KindOf(id)
	for _, kind in ipairs(ns.StatKinds) do
		if kind.id == id then return kind end
	end
end

-- { [player] = { [kind id] = number } } for everyone.
local function Totals()
	local totals = {}
	for _, player in ipairs(ns.Stats:Players()) do
		local week = ns.Stats:Week(player)
		-- Whole numbers, even from tallies saved before they were rounded.
		for id, amount in pairs(week) do
			week[id] = math.floor(amount + 0.5)
		end
		totals[player] = week
	end
	return totals
end

function Report:Build(kindId, player)
	local totals = Totals()
	local players = ns.Stats:Players()
	local kinds = kindId and { KindOf(kindId) } or ns.StatKinds
	local rows, total = {}, 0

	if player then
		for _, kind in ipairs(kinds) do
			local party = 0
			for _, name in ipairs(players) do
				party = party + (totals[name][kind.id] or 0)
			end
			local value = totals[player] and totals[player][kind.id] or 0
			rows[#rows + 1] = { id = kind.id, label = kind.name, class = ClassOf(player), value = value, share = party > 0 and value / party or 0 }
			total = total + value
		end
		return { mode = "shares", rows = rows, total = total }
	end

	if kindId then
		local biggest = 0
		for _, name in ipairs(players) do
			local value = totals[name][kindId] or 0
			if value > 0 then
				rows[#rows + 1] = { id = name, label = name, class = ClassOf(name), value = value }
				biggest = math.max(biggest, value)
				total = total + value
			end
		end
		table.sort(rows, function(a, b)
			if a.value ~= b.value then return a.value > b.value end
			return a.label < b.label
		end)
		for _, row in ipairs(rows) do
			row.share = biggest > 0 and row.value / biggest or 0
		end
		return { mode = "players", rows = rows, total = total }
	end

	for _, kind in ipairs(kinds) do
		local segments, value = {}, 0
		for _, name in ipairs(players) do
			local part = totals[name][kind.id] or 0
			if part > 0 then
				segments[#segments + 1] = { player = name, class = ClassOf(name), value = part }
				value = value + part
			end
		end
		table.sort(segments, function(a, b) return a.value > b.value end)
		rows[#rows + 1] = { id = kind.id, label = kind.name, value = value, segments = segments }
		total = total + value
	end
	return { mode = "stacked", rows = rows, total = total }
end
