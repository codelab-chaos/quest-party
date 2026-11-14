-- Emulator: plays emulator\script.lua as if other players were sharing with us.
-- Its pretend players use the real protocol: while connected to a channel,
-- each of their entries is sent over it, and is read and shown only when the
-- server sends it back (comms\sharing.lua). So it tests how this client picks
-- up messages from another client, with real traffic.
-- With no channel there is nothing to send over, so the entries are handed
-- straight to the panel, which still shows how the panel looks with a party.
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
	if not ns.IsDebug() then
		return
	end
	local steps = self:GetSteps()
	local step = steps[self.index]
	if not step then
		return
	end
	self.index = (self.index % #steps) + 1
	if ns.Sharing:SendVirtual(step.persona, step.type, step.data) then
		return -- it shows when the server sends it back
	end
	Bus:Fire("ENTRY_RECEIVED", {
		type = step.type,
		player = step.persona.name,
		class = step.persona.class,
		data = Copy(step.data),
		emulated = true,
	})
end

-- The channel the pretend players are sent over, or nil when there is none
-- and they are handed straight to the panel.
function Emulator:Channel()
	local session = ns.Session
	return session.state == "connected" and session.channelId and ns.db.connection.name or nil
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
	if not ns.IsDebug() or self.running then
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

Bus:On("DEBUG_CHANGED", function(enabled)
	if not enabled then
		Emulator:Stop()
	end
end)
