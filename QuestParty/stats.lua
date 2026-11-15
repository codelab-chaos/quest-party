-- Stats: a week of daily tallies per player (XP, kills, quests and the rest,
-- see data\stats.lua), kept apart from the feed. The feed folds runs into a
-- row and forgets old rows; the tallies keep counting, so a week can be
-- added up. Small by design: one short table per player per day, and days
-- older than ns.StatDays are dropped.
--
-- Saved in QuestPartyDB.stats as stats[player][day] = { [tally id] = number },
-- where day is the number of whole days since 1970 (server time).
--
-- An advanced feature for now: tallies are kept only in debug mode, which a
-- local source install always has on (X-Debug in the TOC). Released builds
-- keep nothing unless a player turns debug mode on.
local _, ns = ...
local Bus = ns.Bus

local Stats = {}
ns.Stats = Stats

local SECONDS_PER_DAY = 86400

local function Today()
	return math.floor(GetServerTime() / SECONDS_PER_DAY)
end

local function Filled(value)
	return value ~= nil and value ~= ""
end

-- Drops the days that have aged out, and any player left with none.
function Stats:Prune()
	local oldest = Today() - ns.StatDays + 1
	for player, days in pairs(ns.db.stats) do
		for day in pairs(days) do
			if day < oldest then
				days[day] = nil
			end
		end
		if next(days) == nil then
			ns.db.stats[player] = nil
		end
	end
end

-- Adds an entry to its player's tally for the day it happened.
function Stats:Record(entry)
	local saved = ns.db.stats
	if not saved or not ns.IsDebug() or entry.emulated or not entry.player or type(entry.data) ~= "table" then
		return -- the emulator's pretend players are not counted
	end
	local def = ns.FeedTypes[entry.type]
	if not def or not ns.IsEnabled(def.setting) then
		return
	end
	local day = math.floor((entry.time or GetServerTime()) / SECONDS_PER_DAY)
	for _, kind in ipairs(ns.StatKinds) do
		if kind.from == entry.type and (not kind.when or Filled(entry.data[kind.when])) then
			local amount = 1
			if kind.sum then
				amount = entry.data[kind.sum]
			end
			if type(amount) == "number" and amount > 0 then
				saved[entry.player] = saved[entry.player] or {}
				local tally = saved[entry.player][day] or {}
				saved[entry.player][day] = tally
				tally[kind.id] = (tally[kind.id] or 0) + amount
			end
		end
	end
end

-- One player's tallies added up over the days kept: { [tally id] = number }.
function Stats:Week(player)
	local totals = {}
	for _, tally in pairs(ns.db.stats[player] or {}) do
		for id, amount in pairs(tally) do
			totals[id] = (totals[id] or 0) + amount
		end
	end
	return totals
end

-- The players with any tallies, by name.
function Stats:Players()
	local players = {}
	for player in pairs(ns.db.stats) do
		players[#players + 1] = player
	end
	table.sort(players)
	return players
end

Bus:On("INIT", function()
	ns.db.stats = ns.db.stats or {}
	Stats:Prune()
end)

Bus:On("ENTRY_RECEIVED", function(entry)
	Stats:Record(entry)
end)
