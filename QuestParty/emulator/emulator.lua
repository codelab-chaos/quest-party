-- Emulator: a stand-in transport that plays emulator\script.lua as if party members
-- were sending us entries. It fires the same ENTRY_RECEIVED message real comms will,
-- so everything downstream (store, panel, chat echo) is exercised for real.
local _, ns = ...
local Bus = ns.Bus

local Emulator = {
	running = false,
	speed = 1,
	index = 1,
	steps = nil,
}
ns.Emulator = Emulator

local function Copy(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

-- Seconds between a kill and the quest credit it causes.
local KILL_CREDIT_DELAY = 0.4

-- Adds one step, preceded by its kill when the script step has one.
local function AddStep(steps, step, persona, delay, data)
	if step.kill then
		-- The kill carries the quest it gave credit for, so the card clears with the quest.
		local kill = Copy(step.kill)
		kill.quest = step.data.quest
		steps[#steps + 1] = { delay = delay, persona = persona, type = "kill", data = kill }
		delay = KILL_CREDIT_DELAY
	end
	steps[#steps + 1] = { delay = delay, persona = persona, type = step.type, data = data }
end

-- Flattens script steps, turning each "count" step into one step per value.
local function Expand(script)
	local steps = {}
	for _, step in ipairs(script.steps) do
		local persona = script.personas[step.who]
		if persona and ns.FeedTypes[step.type] then
			if step.count then
				local count = step.count
				for value = count.from, count.to do
					local data = Copy(step.data)
					data[count.field] = value
					AddStep(steps, step, persona, (value == count.from) and step.after or count.every, data)
				end
			else
				AddStep(steps, step, persona, step.after, step.data)
			end
		end
	end
	return steps
end

function Emulator:GetSteps()
	if not self.steps then
		self.steps = Expand(ns.EmulatorScript)
	end
	return self.steps
end

-- Emits the current step and moves to the next, looping at the end.
function Emulator:Step()
	local steps = self:GetSteps()
	local step = steps[self.index]
	if not step then
		return
	end
	self.index = (self.index % #steps) + 1
	Bus:Fire("ENTRY_RECEIVED", {
		type = step.type,
		player = step.persona.name,
		class = step.persona.class,
		data = Copy(step.data),
		emulated = true,
	})
	-- For testing the connection: also send the step out as if it were ours.
	if ns.IsEnabled("emulatorShare") then
		Bus:Fire("ENTRY_OUTGOING", { type = step.type, data = Copy(step.data) })
	end
end

function Emulator:Burst(count)
	for _ = 1, count do
		self:Step()
	end
end

local function ScheduleNext()
	local steps = Emulator:GetSteps()
	local step = steps[Emulator.index]
	if not step then
		Emulator:Stop()
		return
	end
	Emulator.timer = C_Timer.NewTimer(step.delay / Emulator.speed, function()
		if not Emulator.running then
			return
		end
		Emulator:Step()
		ScheduleNext()
	end)
end

function Emulator:Start()
	if self.running then
		return
	end
	self.running = true
	Bus:Fire("EMULATOR_STATE", true)
	ScheduleNext()
end

function Emulator:Stop()
	if not self.running then
		return
	end
	self.running = false
	if self.timer then
		self.timer:Cancel()
		self.timer = nil
	end
	Bus:Fire("EMULATOR_STATE", false)
end

function Emulator:Toggle()
	if self.running then
		self:Stop()
	else
		self:Start()
	end
end

function Emulator:SetSpeed(speed)
	self.speed = math.max(0.25, math.min(20, speed))
end
