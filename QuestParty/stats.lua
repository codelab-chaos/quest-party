-- Stats: daily tallies per player (XP, kills, quests and the rest, see
-- data\stats.lua), kept apart from the feed: the party's fuel. The feed
-- folds runs into a row and forgets old rows; the tallies keep counting.
-- Kept for good, one book per channel: each channel's party has its own
-- fuel. Small by design: one short table per player per day.
--
-- Saved in the account saved variables (QuestPartyDB) as
--   fuel[channel][player][day] = { [tally id] = number }
-- where channel is the channel's name in lower case ("" with none) and day is
-- the number of whole days since 1970 (server time).
--
-- Kept for everyone: the Fuel tab (ui\report.lua) graphs them. Pretend
-- players (dev mode's) are never counted: Fuel is real.
local _, ns = ...
local Bus = ns.Bus

local Stats = {}
ns.Stats = Stats

local SECONDS_PER_DAY = 86400

local function Filled(value)
	return value ~= nil and value ~= ""
end

-- The channel a book belongs to: the one Quest Party is set to.
local function Channel()
	local config = ns.db.connection
	return (config and config.name or ""):lower()
end

-- The current channel's book: { [player] = { [day] = tally } }.
function Stats:Book(channel)
	ns.db.fuel = ns.db.fuel or {}
	channel = channel or Channel()
	ns.db.fuel[channel] = ns.db.fuel[channel] or {}
	return ns.db.fuel[channel]
end

-- Empties the current channel's book, its
-- recent buckets too.
function Stats:Clear()
	wipe(self:Book())
	local recent = ns.db.fuelRecent and ns.db.fuelRecent[(ns.db.connection and ns.db.connection.name or ""):lower()]
	if recent then wipe(recent) end
end

-- Moves one player's tallies to another name, in every channel's book.
function Stats:RenamePlayer(old, new)
	for _, book in pairs(ns.db.fuel or {}) do
		if book[old] then
			book[new] = book[new] or {}
			for day, tally in pairs(book[old]) do
				local into = book[new][day] or {}
				book[new][day] = into
				for id, amount in pairs(tally) do
					into[id] = (into[id] or 0) + amount
				end
			end
			book[old] = nil
		end
	end
end

-- Tallies saved before books were kept per channel (stats[player][day], a
-- week's worth) move into the current channel's book.
local function Migrate()
	local old = ns.db.stats
	if type(old) ~= "table" then return end
	local book = Stats:Book()
	for player, days in pairs(old) do
		book[player] = book[player] or {}
		for day, tally in pairs(days) do
			local into = book[player][day] or {}
			book[player][day] = into
			for id, amount in pairs(tally) do
				into[id] = (into[id] or 0) + amount
			end
		end
	end
	ns.db.stats = nil
end

-- Adds an entry to its player's tally for the day it happened.
function Stats:Record(entry)
	local saved = self:Book()
	if entry.emulated or not entry.player or type(entry.data) ~= "table" then
		return -- dev mode's pretend players never count: Fuel is real
	end
	local def = ns.FeedTypes[entry.type]
	if not def or not ns.IsEnabled(def.setting) then
		return
	end
	local day = math.floor((entry.time or GetServerTime()) / SECONDS_PER_DAY)
	for _, kind in ipairs(ns.StatKinds) do
		if kind.from == entry.type and (not kind.when or Filled(entry.data[kind.when])) then
			local amount = kind.count and tonumber(entry.data[kind.count]) or 1
			if kind.sum then
				-- Whole numbers only: XP is counted in points, and a fraction (a
				-- pretend player's scaled gain) would show as one.
				amount = tonumber(entry.data[kind.sum])
				amount = amount and math.floor(amount + 0.5)
			end
			if type(amount) == "number" and amount > 0 then
				saved[entry.player] = saved[entry.player] or {}
				local tally = saved[entry.player][day] or {}
				saved[entry.player][day] = tally
				tally[kind.id] = (tally[kind.id] or 0) + amount
			end
		end
	end
	-- The entry's fuel, in the recent buckets too (Stats:Recent).
	Stats:AddRecent(entry.player, Stats.EntryFuel(entry), entry.time or GetServerTime())
	-- XP's fuel, counted by level (see Stats.XPFuel).
	if entry.type == "xp" then
		local fuel = Stats.XPFuel(tonumber(entry.data.xp), tonumber(entry.data.level), tonumber(entry.data.maxXP))
		if fuel and fuel > 0 then
			saved[entry.player] = saved[entry.player] or {}
			local tally = saved[entry.player][day] or {}
			saved[entry.player][day] = tally
			tally.xpFuel = (tally.xpFuel or 0) + fuel
		end
	end
end

-- ========= Fuel gained recently ===============================================
-- Each gain's fuel also goes in ten-minute buckets, per channel and player,
-- kept a week: the last hour, day and week are added up from them.
--   fuelRecent[channel][player][bucket] = fuel, bucket = time / RECENT_BUCKET
local RECENT_BUCKET = 600
local RECENT_KEEP = 7 * 86400

local function RecentBook()
	ns.db.fuelRecent = ns.db.fuelRecent or {}
	local channel = (ns.db.connection and ns.db.connection.name or ""):lower()
	ns.db.fuelRecent[channel] = ns.db.fuelRecent[channel] or {}
	return ns.db.fuelRecent[channel]
end

-- What one entry adds to the fuel: each kind it counts toward, by its weight
-- (XP by level, Stats.XPFuel).
function Stats.EntryFuel(entry)
	local fuel = 0
	for _, kind in ipairs(ns.StatKinds) do
		if kind.fuel and kind.from == entry.type and (not kind.when or Filled(entry.data[kind.when])) then
			if kind.fuelFrom == "xpFuel" then
				fuel = fuel + (Stats.XPFuel(tonumber(entry.data.xp), tonumber(entry.data.level), tonumber(entry.data.maxXP)) or 0) * kind.fuel
			else
				local amount = kind.count and tonumber(entry.data[kind.count]) or 1
				if kind.sum then amount = tonumber(entry.data[kind.sum]) or 0 end
				fuel = fuel + amount * kind.fuel
			end
		end
	end
	return fuel
end

function Stats:AddRecent(player, fuel, time)
	if not player or not fuel or fuel <= 0 then return end
	local book = RecentBook()
	book[player] = book[player] or {}
	local bucket = math.floor(time / RECENT_BUCKET)
	book[player][bucket] = (book[player][bucket] or 0) + fuel
end

-- Fuel gained in the last seconds, by one player or (with none) everyone on
-- this channel. A whole number.
function Stats:Recent(seconds, player, now)
	local from = math.floor(((now or GetServerTime()) - seconds) / RECENT_BUCKET)
	local total = 0
	for name, buckets in pairs(RecentBook()) do
		if not player or name == player then
			for bucket, fuel in pairs(buckets) do
				if bucket > from then total = total + fuel end
			end
		end
	end
	return math.floor(total + 0.5)
end

-- Drops buckets older than a week.
function Stats:PruneRecent(now)
	local from = math.floor(((now or GetServerTime()) - RECENT_KEEP) / RECENT_BUCKET)
	for _, book in pairs(ns.db.fuelRecent or {}) do
		for name, buckets in pairs(book) do
			for bucket in pairs(buckets) do
				if bucket <= from then buckets[bucket] = nil end
			end
			if next(buckets) == nil then book[name] = nil end
		end
	end
end

-- XP as fuel: the share of a level it is, times ns.XPFuelPerLevel times the
-- level, so a level's worth is 2,000 at level 10 and 11,800 at 59 (a straight
-- line, not the game's steep curve). The level's requirement is the gain's
-- own (need) when it has one, else ns.XPToLevel. At the cap (or an unknown
-- level) XP adds no fuel.
function Stats.XPFuel(xp, level, need)
	if not xp or xp <= 0 or not level or level < 1 then return nil end
	level = math.floor(level)
	if not need or need <= 0 then need = ns.XPToLevel[level] end
	if not need or need <= 0 then return nil end
	return xp / need * ns.XPFuelPerLevel * level
end

-- One player's tallies on this channel, all added up: { [tally id] = number }.
-- A day counted before XP fuel was kept has its XP turned into fuel at the
-- player's level now (as near as can be known).
function Stats:Total(player)
	local totals = {}
	local member = ns.Store:GetMember(player)
	for _, tally in pairs(self:Book()[player] or {}) do
		for id, amount in pairs(tally) do
			totals[id] = (totals[id] or 0) + amount
		end
		if tally.xp and not tally.xpFuel then
			totals.xpFuel = (totals.xpFuel or 0) + (Stats.XPFuel(tally.xp, member and member.level or 1) or 0)
		end
	end
	return totals
end

-- The players with any tallies, by name.
function Stats:Players()
	local players = {}
	for player in pairs(self:Book()) do
		players[#players + 1] = player
	end
	table.sort(players)
	return players
end

Bus:On("INIT", function()
	Migrate()
	Stats:PruneRecent()
end)

Bus:On("ENTRY_RECEIVED", function(entry)
	Stats:Record(entry)
end)
