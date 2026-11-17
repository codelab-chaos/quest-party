-- Vitals collector: this character's health and power from the game, as a
-- reading in steps (vitals.lua). Says VITALS_CHANGED when the stepped reading
-- changes; comms\sharing.lua sends it (debounced), the panel shows it.
-- A value the game hides (in combat it may) is left as it was.
local _, ns = ...
local Bus = ns.Bus

local Collector = { reading = nil }
ns.VitalsCollector = Collector

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- The reading now, or nil when the game says nothing readable.
function Collector:Read()
	local step = ns.Timing.vitalsStep
	local health, healthMax = UnitHealth("player"), UnitHealthMax("player")
	local power, powerMax = UnitPower("player"), UnitPowerMax("player")
	local _, token = UnitPowerType("player")
	local previous = self.reading or {}
	local h = (Readable(health) and Readable(healthMax)) and ns.Vitals.Percent(health, healthMax, step) or previous.h
	local p = (Readable(power) and Readable(powerMax)) and ns.Vitals.Percent(power, powerMax, step) or previous.p
	if not h then return nil end
	return { h = h, p = p or 0, t = type(token) == "string" and token or "MANA" }
end

function Collector:Check()
	local reading = self:Read()
	if reading and not ns.Vitals.Same(reading, self.reading) then
		self.reading = reading
		Bus:Fire("VITALS_CHANGED", reading)
	end
end

local EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }

Bus:On("READY", function()
	Collector:Check()
	local frame = CreateFrame("Frame")
	for _, event in ipairs(EVENTS) do
		pcall(frame.RegisterEvent, frame, event) -- one the client lacks is skipped
	end
	frame:SetScript("OnEvent", function(_, _, unit)
		if unit == "player" then
			Collector:Check()
		end
	end)
end)
