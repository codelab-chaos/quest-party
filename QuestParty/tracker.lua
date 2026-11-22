-- Stats tracker (experimental: docs\stats-tracker.md). A growing, sparse
-- table of what each player did, for stats' sake: separate from Party Fuel
-- (stats.lua), which it never touches. What it counts and how each reads is
-- data (data\tracker.lua); ui\tracker.lua shows it.
--
-- Saved for the account as tracker[player] = {
--   since  = when this client first counted them (server time),
--   total  = { [stat id] = number },            all time
--   days   = { [day]   = { [stat id] = n } },   the last TrackerRules.days
--   months = { [month] = { ... } },             then TrackerRules.months
--   years  = { [year]  = { ... } },             then for good
--   mobs   = { [npc id or name] = { n = name, k = kills, t = last } },  yours
-- }
-- Sparse: a number is only there once it is more than 0. Counted from the
-- feed's entries for everyone this client hears (dev mode's pretend players
-- never), and measured by your own client for you alone: time played and
-- AFK, sessions, distance on foot and flown, jumps, money in and out.
local _, ns = ...
local Bus = ns.Bus

local Tracker = {}
ns.Tracker = Tracker

local SECONDS_PER_DAY = 86400

-- The calendar month and year of a day (whole days since 1970), with no
-- clock library: the civil calendar, worked out.
local function YearMonth(day)
	local z = day + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local month = mp < 10 and mp + 3 or mp - 9
	local year = yoe + era * 400 + (month <= 2 and 1 or 0)
	return year, month
end
Tracker.YearMonth = YearMonth

local function MonthKey(day)
	local year, month = YearMonth(day)
	return year * 12 + (month - 1)
end

-- Always on: it only counts, on this computer, and costs little.
function Tracker:On()
	return true
end

-- A player's book, made the first time they are counted.
function Tracker:Book(player)
	local all = ns.db.tracker
	local book = all[player]
	if not book then
		book = { since = GetServerTime(), total = {}, days = {}, months = {}, years = {}, mobs = {} }
		all[player] = book
	end
	return book
end

-- Adds to one of a player's counters, all time and today.
function Tracker:Add(player, stat, amount, at)
	amount = tonumber(amount)
	if not player or not amount or amount <= 0 or not self:On() then return end
	local book = self:Book(player)
	book.total[stat] = (book.total[stat] or 0) + amount
	local day = math.floor((at or GetServerTime()) / SECONDS_PER_DAY)
	book.days[day] = book.days[day] or {}
	book.days[day][stat] = (book.days[day][stat] or 0) + amount
end

-- Days past TrackerRules.days fold into their month, months past
-- TrackerRules.months into their year. Totals never change.
local function Fold(into, key, tally)
	into[key] = into[key] or {}
	for stat, value in pairs(tally) do
		into[key][stat] = (into[key][stat] or 0) + value
	end
end

function Tracker:Rollup(now)
	local today = math.floor((now or GetServerTime()) / SECONDS_PER_DAY)
	local rules = ns.TrackerRules
	local thisMonth = MonthKey(today)
	for _, book in pairs(ns.db.tracker) do
		for day, tally in pairs(book.days) do
			if today - day >= rules.days then
				Fold(book.months, MonthKey(day), tally)
				book.days[day] = nil
			end
		end
		for month, tally in pairs(book.months) do
			if thisMonth - month >= rules.months then
				Fold(book.years, math.floor(month / 12), tally)
				book.months[month] = nil
			end
		end
	end
end

-- ========= Counting from the feed ===========================================
-- What an entry adds, by its type: { stat, amount } pairs.
local FROM = {
	xp = function(data)
		local xp = tonumber(data.xp) or 0
		local list = { { "x", xp } }
		if data.mob and data.mob ~= "" then
			list[#list + 1] = { "k", tonumber(data.gains) or 1 }
			list[#list + 1] = { "kx", xp }
		end
		if data.quest and data.quest ~= "" then list[#list + 1] = { "qx", xp } end
		if data.discovery and data.discovery ~= "" then list[#list + 1] = { "zx", xp } end
		return list
	end,
	quest_accepted = function() return { { "qa", 1 } } end,
	quest_complete = function() return { { "qd", 1 } } end,
	quest_abandoned = function() return { { "qq", 1 } } end,
	level = function() return { { "l", 1 } } end,
	skill = function() return { { "s", 1 } } end,
	skill_learned = function() return { { "p", 1 } } end,
	achievement = function() return { { "a", 1 } } end,
	discovery = function() return { { "z", 1 } } end,
	death = function() return { { "d", 1 } } end,
	chat = function() return { { "cs", 1 } } end,
}

function Tracker:Count(entry)
	if entry.emulated or type(entry.data) ~= "table" then return end
	local from = FROM[entry.type]
	if not from then return end
	for _, pair in ipairs(from(entry.data)) do
		self:Add(entry.player, pair[1], pair[2], entry.time)
	end
	-- Your own kills by creature (the id from PARTY_KILL, below).
	if entry.type == "xp" and ns.IsMe(entry.player) and entry.data.mob and entry.data.mob ~= "" then
		self:NameKills(entry.data.mob, tonumber(entry.data.gains) or 1)
	end
end

-- ========= Your kills, by creature ==========================================
-- PARTY_KILL says a creature died to you, with its GUID (the NPC id is in
-- it); the feed's kill entry, a moment later, says its name. Kills whose id
-- the game hid (a secret in an instance) are kept by name instead.
local unnamed = {} -- ids killed and not named yet, oldest first

function Tracker:Kill(npcId, at)
	if not self:On() then return end
	local mobs = self:Book(ns.MyName()).mobs
	local mob = mobs[npcId] or {}
	mobs[npcId] = mob
	mob.k = (mob.k or 0) + 1
	mob.t = at or GetServerTime()
	if not mob.n then unnamed[#unnamed + 1] = npcId end
end

function Tracker:NameKills(name, count)
	if not self:On() then return end
	local mobs = self:Book(ns.MyName()).mobs
	local named = 0
	for index = #unnamed, 1, -1 do
		if named >= count then break end
		local mob = mobs[unnamed[index]]
		if mob and not mob.n then
			mob.n = name
			named = named + 1
		end
		table.remove(unnamed, index)
	end
	-- None to name: the game gave no id (an instance). Kept by name.
	if named == 0 then
		local mob = mobs[name] or { n = name }
		mobs[name] = mob
		mob.k = (mob.k or 0) + count
		mob.t = GetServerTime()
	end
end

-- The NPC id in a creature's GUID ("Creature-0-1234-1-56-3098-0000ABCDEF"),
-- or nil for anything else (a player, a pet) or a value the game hides.
function Tracker.NpcId(guid)
	if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
	local kind, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)%-")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

-- ========= Measured by your client ==========================================
local position, travelled, flown = nil, 0, 0

-- Distance: your world position now and then (HereBeDragons, libs\README.md);
-- a step too long for the time between samples was a teleport, not travel.
function Tracker:Sample()
	local stub = LibStub
	local maps = stub and stub("HereBeDragons-2.0", true)
	if not (maps and self:On()) then return end
	local x, y, instance = maps:GetPlayerWorldPosition()
	if not (x and y and instance) then position = nil return end
	if position and position.instance == instance then
		local distance = maps:GetWorldDistance(instance, position.x, position.y, x, y)
		if distance and distance > 0 and distance <= ns.TrackerRules.leap * ns.TrackerRules.sample then
			if UnitOnTaxi and UnitOnTaxi("player") then flown = flown + distance else travelled = travelled + distance end
		end
	end
	position = { x = x, y = y, instance = instance }
	-- Whole yards into the book.
	local me = ns.MyName()
	if travelled >= 1 then self:Add(me, "mg", math.floor(travelled)) travelled = travelled - math.floor(travelled) end
	if flown >= 1 then self:Add(me, "mf", math.floor(flown)) flown = flown - math.floor(flown) end
end

-- A jump: on the ground (not swimming, flying or on a flight path).
function Tracker:Jumped()
	if (IsSwimming and IsSwimming()) or (IsFlying and IsFlying()) or (UnitOnTaxi and UnitOnTaxi("player")) then return end
	self:Add(ns.MyName(), "j", 1)
end

-- Time: every clock seconds, played or AFK (collectors\afk.lua).
function Tracker:Tick()
	local seconds = ns.TrackerRules.clock
	self:Add(ns.MyName(), (ns.Away and ns.Away.afk) and "tk" or "ta", seconds)
end

-- Money: what changed since the last look, in or out.
local money
function Tracker:Money()
	local now = GetMoney and GetMoney()
	if type(now) ~= "number" or (issecretvalue and issecretvalue(now)) then return end
	if money then
		if now > money then self:Add(ns.MyName(), "gi", now - money) end
		if now < money then self:Add(ns.MyName(), "go", money - now) end
	end
	money = now
end

-- ========= The view (data to rows) ==========================================
-- What a period adds up to for a player: "today", "week" (the last 7 days)
-- or "all" (every day, month and year: the all-time totals).
function Tracker:Period(player, period, now)
	local book = ns.db.tracker[player]
	if not book then return {} end
	if period == "all" then return book.total end
	local today = math.floor((now or GetServerTime()) / SECONDS_PER_DAY)
	local span = period == "week" and 7 or 1
	local sum = {}
	for day = today - span + 1, today do
		for stat, value in pairs(book.days[day] or {}) do sum[stat] = (sum[stat] or 0) + value end
	end
	return sum
end

-- The rows to show, data driven: one section per category (in order, an
-- empty one left out), each stat with a number past 0 as { label, text }.
-- { since, sections = { { label, rows } }, mobs = { { label, text } } }
function Tracker:View(player, period, now)
	local tally = self:Period(player, period, now)
	local sections = {}
	for _, category in ipairs(ns.TrackerCategories) do
		local rows = {}
		for _, stat in ipairs(ns.TrackerStats) do
			local value = tally[stat.id]
			if stat.category == category.id and value and value > 0 then
				rows[#rows + 1] = { label = stat.label, text = ns.TrackerText(stat.id, value) }
			end
		end
		if #rows > 0 then sections[#sections + 1] = { label = category.label, rows = rows } end
	end
	-- Your most killed creatures, all time.
	local mobs = {}
	local book = ns.db.tracker[player]
	for _, mob in pairs(book and book.mobs or {}) do
		if (mob.k or 0) > 0 then mobs[#mobs + 1] = mob end
	end
	table.sort(mobs, function(a, b) return a.k > b.k end)
	local top = {}
	for index = 1, math.min(5, #mobs) do
		top[index] = { label = mobs[index].n or ns.L.TRACK_UNNAMED, text = ns.TrackerText("k", mobs[index].k) }
	end
	return { since = book and book.since, sections = sections, mobs = top }
end

-- The players this client has a book for, you first, then by name.
function Tracker:Players()
	local list = {}
	for player in pairs(ns.db.tracker) do
		if not ns.IsMe(player) then list[#list + 1] = player end
	end
	table.sort(list)
	table.insert(list, 1, ns.MyName())
	return list
end

-- ========= Wiring ===========================================================
Bus:On("INIT", function()
	ns.db.tracker = ns.db.tracker or {}
	Tracker:Rollup()
end)

Bus:On("ENTRY_RECEIVED", function(entry)
	Tracker:Count(entry)
end)

-- A stamp landed: given by its stamper, received by the card's player.
Bus:On("STAMPED", function(key, stamp)
	if not stamp then return end
	Tracker:Add(stamp.from, "sg", 1)
	local owner = type(key) == "string" and key:match("^([^~]+)~")
	if owner then Tracker:Add(owner, "sr", 1) end
end)

Bus:On("READY", function()
	Tracker:Add(ns.MyName(), "ts", 1) -- a session
	Tracker:Money()
	C_Timer.NewTicker(ns.TrackerRules.sample, function() Tracker:Sample() end)
	C_Timer.NewTicker(ns.TrackerRules.clock, function() Tracker:Tick() end)
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "PARTY_KILL", "PLAYER_MONEY" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnEvent", function(_, event, attacker, target)
		if event == "PLAYER_MONEY" then
			Tracker:Money()
		elseif event == "PARTY_KILL" then
			-- A hidden value cannot even be compared: such a kill is named later.
			if issecretvalue and (issecretvalue(attacker) or issecretvalue(target)) then return end
			local mine = UnitGUID and UnitGUID("player")
			if mine and not (issecretvalue and issecretvalue(mine)) and attacker == mine then
				local id = Tracker.NpcId(target)
				if id then Tracker:Kill(id) end
			end
		end
	end)
	-- Jumps: after the game's own jump runs (a hook only listens).
	if hooksecurefunc and JumpOrAscendStart then
		hooksecurefunc("JumpOrAscendStart", function() Tracker:Jumped() end)
	end
end)
