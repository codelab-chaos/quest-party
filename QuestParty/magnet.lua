-- Magnet: the model behind a magnetic event dock (ui\magnet-dock.lua), plain
-- data and math, no frames, so it can be tested. It knows nothing of feed
-- entries: an item is anything with an id.
--
-- Entries sit in fixed slots, newest at the bottom (slot 1). Each has an
-- extension, 0 (only its icon peeks out) to 1 (fully out), that springs
-- toward a target: how hard the cursor pulls it (given by the view each
-- step), or a little way out while it is newly arrived and showing itself.
-- The springs are damped about critically: drawers glide out and stop, with
-- friction and no bounce.
-- Slots spring too: a new entry rises in from below the bottom and the rest
-- move up a place; past the most kept, the oldest slides off the top and
-- fades. Arrivals queue a moment apart, so a burst rolls in one by one.
local _, ns = ...

local Magnet = {}
ns.Magnet = Magnet

Magnet.DEFAULTS = {
	maxEntries = 7, -- the most keys shown
	stiffness = 60, -- the extension spring: unhurried, about half a second out
	damping = 16, -- about critical (2 * sqrt(stiffness) = 15.5): glides and stops, no bounce
	slotStiffness = 120, -- the slot spring: rolling up a place
	slotDamping = 22,
	revealSeconds = 1.0, -- a new arrival shows itself this long, then settles
	reveal = 0.3, -- how far out it comes to show itself: a nudge, not all the way
	arriveGap = 0.35, -- seconds between arrivals in a burst
	fadeSeconds = 0.35, -- a leaving entry fades out over this
	step = 1 / 120, -- the longest physics step; a slow frame takes several
}

local Dock = {}
Dock.__index = Dock

function Magnet.New(config)
	local settings = {}
	for key, value in pairs(Magnet.DEFAULTS) do
		settings[key] = (config and config[key] ~= nil) and config[key] or value
	end
	return setmetatable({ config = settings, entries = {}, queue = {}, clock = 0, lastArrival = -math.huge }, Dock)
end

-- How strongly the cursor pulls at a distance (0 to 1): full on top of it,
-- easing to nothing at the radius, a smooth bell rather than a cone.
function Magnet.Influence(distance, radius)
	if radius <= 0 then return 0 end
	local d = math.abs(distance) / radius
	if d >= 1 then return 0 end
	return 0.5 * (1 + math.cos(math.pi * d))
end

-- One spring step toward target: returns the new value and velocity.
local function Spring(value, velocity, target, stiffness, damping, dt)
	velocity = velocity + (stiffness * (target - value) - damping * velocity) * dt
	return value + velocity * dt, velocity
end

-- Queues an item ({ id, ... }); it arrives at the bottom in turn. Pushing an
-- id that is already in moves it to the bottom as new. quiet: it is placed
-- at once, without showing itself (filling the dock with what came before).
function Dock:Push(item, quiet)
	self:Remove(item.id, true)
	local at = self.clock
	if not quiet then
		at = math.max(self.clock, self.lastArrival + self.config.arriveGap)
		self.lastArrival = at
	end
	self.queue[#self.queue + 1] = { item = item, at = at, quiet = quiet }
end

-- Takes an entry out: it retracts and fades (or goes at once with now).
function Dock:Remove(id, now)
	for index = #self.queue, 1, -1 do
		if self.queue[index].item.id == id then table.remove(self.queue, index) end
	end
	for index = #self.entries, 1, -1 do
		local entry = self.entries[index]
		if entry.item.id == id then
			if now then
				table.remove(self.entries, index)
			else
				entry.leaving = true
			end
		end
	end
end

function Dock:Clear()
	self.entries, self.queue = {}, {}
end

-- The entries still in their slots (not leaving), oldest first.
function Dock:Staying()
	local list = {}
	for _, entry in ipairs(self.entries) do
		if not entry.leaving then list[#list + 1] = entry end
	end
	return list
end

local function Arrive(self)
	while self.queue[1] and self.queue[1].at <= self.clock do
		local queued = table.remove(self.queue, 1)
		local staying = #self:Staying()
		self.entries[#self.entries + 1] = {
			item = queued.item,
			slot = 0, slotVelocity = 0, -- rises in from just under the bottom
			extension = 0, velocity = 0,
			alpha = 0,
			revealUntil = not queued.quiet and (self.clock + self.config.revealSeconds) or nil,
		}
		-- Past the most kept, the oldest go.
		local over = staying + 1 - self.config.maxEntries
		for _, entry in ipairs(self.entries) do
			if over <= 0 then break end
			if not entry.leaving then
				entry.leaving = true
				over = over - 1
			end
		end
	end
end

-- Moves time on by dt. pull(entry) gives how hard the cursor pulls each
-- entry (0 to 1), from its slot; nil means nothing pulls.
function Dock:Step(dt, pull)
	local config = self.config
	while dt > 0 do
		local step = math.min(dt, config.step)
		dt = dt - step
		self.clock = self.clock + step
		Arrive(self)
		local staying = self:Staying()
		local place = {}
		for index, entry in ipairs(staying) do
			place[entry] = #staying - index + 1 -- the newest is slot 1, at the bottom
		end
		for index = #self.entries, 1, -1 do
			local entry = self.entries[index]
			local slotTarget = place[entry] or (#staying + 1) -- leaving: up off the top
			entry.slot, entry.slotVelocity = Spring(entry.slot, entry.slotVelocity, slotTarget, config.slotStiffness, config.slotDamping, step)
			local target = 0
			if not entry.leaving then
				target = pull and pull(entry) or 0
				if entry.revealUntil and self.clock < entry.revealUntil then
					target = math.max(target, config.reveal)
				end
			end
			entry.extension, entry.velocity = Spring(entry.extension, entry.velocity, target, config.stiffness, config.damping, step)
			local fade = step / config.fadeSeconds
			if entry.leaving then
				entry.alpha = math.max(0, entry.alpha - fade)
				if entry.alpha <= 0 then table.remove(self.entries, index) end
			else
				entry.alpha = math.min(1, entry.alpha + fade)
			end
		end
	end
end

-- Whether anything is still moving (so a view can rest when nothing is).
function Dock:Busy()
	if #self.queue > 0 then return true end
	for _, entry in ipairs(self.entries) do
		if entry.leaving or math.abs(entry.velocity) > 0.001 or math.abs(entry.slotVelocity) > 0.001
			or (entry.revealUntil and self.clock < entry.revealUntil) then
			return true
		end
	end
	return false
end
