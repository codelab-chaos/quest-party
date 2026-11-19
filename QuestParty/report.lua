-- Report: the 123 tab's numbers, as plain data from the stats (stats.lua):
-- every player's tallies added up over the days kept, by kind (data\stats.lua,
-- StatKinds), filtered by kind and player. ui\report.lua draws it.
--
-- Report:Build(kind, player) gives { mode, rows, total } where mode says how
-- to draw the rows:
--   stacked  no kind, no player: a row per kind, its total split by player
--            ({ label, value, fuel, segments = { { player, class, value } } }),
--            and fuel, the party's whole fuel (each kind by its weight)
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

-- The kinds in the Fuel tab: those with a fuel weight (data\stats.lua).
function Report:Kinds()
	local kinds = {}
	for _, kind in ipairs(ns.StatKinds) do
		if kind.fuel ~= nil then kinds[#kinds + 1] = kind end
	end
	return kinds
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
		local week = ns.Stats:Total(player)
		-- Whole numbers, even from tallies saved before they were rounded.
		for id, amount in pairs(week) do
			week[id] = math.floor(amount + 0.5)
		end
		totals[player] = week
	end
	return totals
end

-- A kind's fuel over these players' totals ({ [player] = totals }): its
-- fuel tally when it has one (XP's, by level), else its count, times its
-- weight. A whole number.
function Report.Fuel(kind, totals)
	local fuel = 0
	for _, week in pairs(totals) do
		local amount = kind.fuelFrom and (week[kind.fuelFrom] or 0) or (week[kind.id] or 0)
		fuel = fuel + amount * kind.fuel
	end
	return math.floor(fuel + 0.5)
end

function Report:Build(kindId, player)
	local totals = Totals()
	local players = ns.Stats:Players()
	local kinds = kindId and { KindOf(kindId) } or self:Kinds()
	local rows, total = {}, 0

	if player then
		for _, kind in ipairs(kinds) do
			local party = 0
			for _, name in ipairs(players) do
				party = party + (totals[name][kind.id] or 0)
			end
			local value = totals[player] and totals[player][kind.id] or 0
			rows[#rows + 1] = { id = kind.id, label = kind.name, class = ClassOf(player), value = value, share = party > 0 and value / party or 0, fuel = Report.Fuel(kind, { [player] = totals[player] or {} }) }
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
		rows[#rows + 1] = { id = kind.id, label = kind.name, value = value, segments = segments, fuel = Report.Fuel(kind, totals) }
		total = total + value
	end
	-- The party's fuel: every kind's count by its weight, as one number.
	local fuel = 0
	for _, row in ipairs(rows) do fuel = fuel + row.fuel end
	return { mode = "stacked", rows = rows, total = total, fuel = fuel }
end

-- Everyone who ever added fuel on this channel, the most first: each with
-- their fuel and its kinds { name, class, fuel, kinds = { { id, label,
-- value, fuel } } } (only kinds they have any of).
function Report:Everyone()
	local everyone = {}
	for _, player in ipairs(ns.Stats:Players()) do
		local week = ns.Stats:Total(player)
		local person = { name = player, class = ClassOf(player), fuel = 0, kinds = {} }
		for _, kind in ipairs(self:Kinds()) do
			local value = math.floor((week[kind.id] or 0) + 0.5)
			if value > 0 then
				local fuel = Report.Fuel(kind, { [player] = week })
				person.kinds[#person.kinds + 1] = { id = kind.id, label = kind.name, value = value, fuel = fuel }
				person.fuel = person.fuel + fuel
			end
		end
		if #person.kinds > 0 then everyone[#everyone + 1] = person end
	end
	table.sort(everyone, function(a, b)
		if a.fuel ~= b.fuel then return a.fuel > b.fuel end
		return a.name < b.name
	end)
	return everyone
end

