-- Stamps model: who stamped which feed card with what (data\stamps.lua).
-- Plain data, no frames; ui\stamps.lua draws them, comms\sharing.lua carries
-- them (kind T).
--
-- A card is named by a key every client can make the same way: its player,
-- its feed type and the fields in ns.StampKeys ("Bagoe Bones~level~7").
-- Stamps are kept by that key in ns.db.stamps, so one that arrives before
-- its card (or for a card not shown here) is still there when it shows.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local Stamping = {}
ns.Stamping = Stamping

-- Not "|": the game's text escape, which the channel's text is cleaned of.
local SEPARATOR = "~"
local SECONDS_PER_DAY = 24 * 60 * 60

-- The key naming a feed entry's card, or nil when it cannot be stamped.
function Stamping:KeyFor(entry)
	if not entry or not entry.player or not entry.type or type(entry.data) ~= "table" then return nil end
	local parts = { entry.player, entry.type }
	for _, field in ipairs(ns.StampKeys[entry.type] or {}) do
		local value = entry.data[field]
		parts[#parts + 1] = value == nil and "" or (tostring(value):gsub("[|~]", "/"))
	end
	local key = table.concat(parts, SEPARATOR)
	if #key > ns.StampRules.maxText then return nil end
	return key
end

local function Saved()
	ns.db.stamps = ns.db.stamps or {}
	return ns.db.stamps
end

-- The stamps on a card, oldest first: { { id, from, time } }.
function Stamping:For(key)
	return key and Saved()[key] or nil
end

-- The stamps on a card added up by kind, in the order each kind was first
-- used: { { id, count, time (the newest), from = { names } } }. Each kind is
-- inked in its own spot (ui\stamps.lua), with its count when repeated.
function Stamping:Tally(key)
	local tallies, byId = {}, {}
	for _, stamp in ipairs(self:For(key) or {}) do
		-- One this version does not have (since retired) is left out.
		if ns.StampById[stamp.id] then
			local tally = byId[stamp.id]
			if not tally then
				tally = { id = stamp.id, count = 0, time = 0, from = {} }
				byId[stamp.id] = tally
				tallies[#tallies + 1] = tally
			end
			tally.count = tally.count + 1
			tally.time = math.max(tally.time, stamp.time or 0)
			tally.from[#tally.from + 1] = stamp.from
		end
	end
	return tallies
end

-- The stamps one character has put on a card: how many, and which (id ->
-- true).
function Stamping:Used(key, from)
	local count, ids = 0, {}
	for _, stamp in ipairs(Saved()[key] or {}) do
		-- A retired stamp (one this version does not have) does not count.
		if stamp.from == from and not ids[stamp.id] and ns.StampById[stamp.id] then
			count = count + 1
			ids[stamp.id] = true
		end
	end
	return count, ids
end

-- Whether a character may still stamp a card, and if so with this stamp:
-- up to ns.StampRules.perPlayer different stamps, each once, and then they
-- are done with it. The first ones stay; nothing replaces them.
function Stamping:May(key, from, id)
	local count, ids = self:Used(key, from)
	if count >= ns.StampRules.perPlayer then return false end
	return not (id and ids[id])
end

-- Puts a stamp on a card, if its character may (Stamping:May): every client
-- keeps only the first ns.StampRules.perPlayer of each character's stamps on
-- a card, so stamping again changes nothing anywhere, whatever a client
-- sends. Returns the stamp, or nil when it is refused or unknown.
function Stamping:Add(key, id, from, time)
	if not key or not ns.StampById[id] or not from then return nil end
	if not self:May(key, from, id) then return nil end
	local list = Saved()[key] or {}
	Saved()[key] = list
	local stamp = { id = id, from = from, time = time or GetServerTime() }
	list[#list + 1] = stamp
	while #list > ns.StampRules.perCard do
		table.remove(list, 1)
	end
	Bus:Fire("STAMPED", key, stamp)
	return stamp
end

-- Stamps a card yourself: here at once, and to everyone on the channel.
-- Returns true, or false and why (no channel, timed out, not a stamp).
function Stamping:Send(entry, id)
	local key = self:KeyFor(entry)
	if not key or not ns.StampById[id] then
		return false, L.CHAT_PICK
	end
	if not (ns.Sharing.loopback or ns.Session.state == "connected") then
		return false, L.CHAT_NO_CHANNEL
	end
	if not self:May(key, ns.MyName(), id) then
		return false, L.STAMP_DONE
	end
	local allowed, seconds = ns.Chat.Allow(ns.Chat.YOU)
	if not allowed then
		return false, L.CHAT_TIMEOUT:format(math.ceil(seconds))
	end
	-- Out to the channel; it lands on the card when it comes back, as anyone's.
	ns.Sharing.SendStamp(key, id)
	return true
end

-- A stamp from the channel: muted players and anyone spamming are ignored,
-- as in KekChat.
function Stamping:Receive(sender, key, id)
	if type(key) ~= "string" or #key > ns.StampRules.maxText or not ns.StampById[id] then return end
	if ns.Chat:IsMuted(sender) then return end
	-- Others' spam is held back; yours was limited once, when you sent.
	if not ns.IsMe(sender) and not ns.Chat.Allow(sender) then return end
	self:Add(key, id, sender)
end

-- A stamp's impact (ns.StampImpact): one of KekChat's presets at random, made
-- small, with the stamp's own image among its images, and a random one of
-- KekChat's sounds. random() gives 0 to 1 (math.random by default).
-- Returns { effect, icons, sound }, or nil when nothing fits.
function Stamping.Impact(stampId, random)
	random = random or math.random
	local rules = ns.StampImpact
	local function Pick(list) return list[math.floor(random() * #list) + 1] or list[1] end
	local presets = {}
	for _, id in ipairs(rules.presets) do
		for _, preset in ipairs(ns.EffectPresets) do
			if preset.id == id and ns.ChatEffectById[preset.effect] then presets[#presets + 1] = preset end
		end
	end
	if #presets == 0 then return nil end
	local preset = Pick(presets)
	local base = ns.ChatEffectById[preset.effect]
	local effect, k = {}, rules.scale
	for key, value in pairs(base) do effect[key] = value end
	effect.count = math.max(6, math.floor((base.count or 10) * k))
	if base.rockets then effect.rockets = math.max(1, math.floor(base.rockets * k + 0.5)) end
	effect.size = { base.size[1] * k, base.size[2] * k }
	effect.speed = { base.speed[1] * k, base.speed[2] * k }
	if base.rocketSpeed then effect.rocketSpeed = { base.rocketSpeed[1] * k, base.rocketSpeed[2] * k } end
	effect.gravity = (base.gravity or 0) * k
	effect.terminal = (base.terminal or 1000) * k
	effect.stagger = (base.stagger or 0) * k
	local icons = {}
	local stamp = ns.StampById[stampId]
	if stamp then icons[1] = stamp.texture or ("Interface\\Icons\\" .. stamp.icon) end
	for _, icon in ipairs(preset.icons or {}) do icons[#icons + 1] = "Interface\\Icons\\" .. icon end
	return { effect = effect, icons = icons, sound = Pick(rules.sounds), preset = preset.id }
end

-- How long stamps stay inked before fading (the Stamps fade switch,
-- ns.StampRules.fadeSeconds), or nil to keep them.
function Stamping.FadeAfter()
	return ns.IsEnabled("stampFade") and ns.StampRules.fadeSeconds or nil
end

-- The kinds of stamp to ink on a card now (Tally): with Stamps fade set,
-- only those stamped within its time (a kind stamped again comes back).
function Stamping:Showing(key, now)
	local tallies = self:Tally(key)
	local fadeAfter = Stamping.FadeAfter()
	if not fadeAfter then return tallies end
	now = now or GetServerTime()
	local live = {}
	for _, tally in ipairs(tallies) do
		if now - (tally.time or 0) < fadeAfter then live[#live + 1] = tally end
	end
	return live
end

-- Forgets stamps older than the days kept, and any this version no longer
-- has (retired ones), so they hold no one's two per card.
function Stamping:Prune(now)
	local cutoff = (now or GetServerTime()) - ns.StampRules.keepDays * SECONDS_PER_DAY
	for key, list in pairs(Saved()) do
		for index = #list, 1, -1 do
			if (list[index].time or 0) < cutoff or not ns.StampById[list[index].id] then table.remove(list, index) end
		end
		if #list == 0 then Saved()[key] = nil end
	end
end

Bus:On("INIT", function()
	Stamping:Prune()
end)
