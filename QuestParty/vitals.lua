-- Vitals: health and power as the party sees them. Plain data and timing, no
-- frames: what this character's reading is (in steps of ns.Timing.vitalsStep
-- percent), and when a changed one may go out (at most once in
-- ns.Timing.vitalsSeconds, the latest one winning). collectors\vitals.lua
-- feeds it from the game; comms\sharing.lua sends and reads it.
--
-- A reading is { h = 0..100, p = 0..100, t = "MANA" }.
local _, ns = ...

local Vitals = {}
ns.Vitals = Vitals

-- A value as a whole percent of its most, down to the step (but never 0
-- while above nothing, so a sliver of health still shows).
function Vitals.Percent(value, most, step)
	if type(value) ~= "number" or type(most) ~= "number" or most <= 0 then return nil end
	local percent = math.max(0, math.min(100, value / most * 100))
	local stepped = math.floor(percent / step) * step
	if stepped == 0 and value > 0 then stepped = step end
	return stepped
end

function Vitals.Same(a, b)
	return a and b and a.h == b.h and a.p == b.p and a.t == b.t
end

-- The debounce: Offer a new reading at a time; it says to send now, or
-- holds it for Due. One per sender.
local Debounce = {}
Debounce.__index = Debounce

function Vitals.NewDebounce(seconds)
	return setmetatable({ seconds = seconds, last = -math.huge }, Debounce)
end

-- Returns the reading to send now, or nil (held, or nothing new).
function Debounce:Offer(reading, now)
	if Vitals.Same(reading, self.sentReading) then
		self.pending = nil
		return nil
	end
	if now - self.last >= self.seconds then
		self.last, self.sentReading, self.pending = now, reading, nil
		return reading
	end
	self.pending = reading
	return nil
end

-- When a held reading may go: the time, or nil when nothing is held.
function Debounce:DueAt()
	return self.pending and (self.last + self.seconds) or nil
end

-- The held reading, if its time has come.
function Debounce:Due(now)
	if self.pending and now - self.last >= self.seconds then
		local reading = self.pending
		self.last, self.sentReading, self.pending = now, reading, nil
		return reading
	end
	return nil
end
