-- Scenarios: the test runs Settings offers in debug mode, as data, and the
-- runner behind its GO and STOP buttons. Quest Party's are the emulator's;
-- the sandbox build replaces both lists with its own (sandbox\scenarios.lua).
--   id      the key saved as the last one chosen
--   label   its name in the dropdown
--   run     starts it; returns true, or false and why
-- ScenarioHooks: how to stop a run, wipe what runs left behind (Clear on go),
-- and tell whether one is running.
local _, ns = ...
local L = ns.L

ns.Scenarios = {
	{ id = "sample", label = L.SCENARIO_SAMPLE, run = function()
		ns.Emulator:Use(nil)
		ns.Emulator:Start()
		return true
	end },
	{ id = "evening", label = L.SCENARIO_EVENING, run = function()
		ns.Emulator:Use("evening")
		ns.Emulator:SetSpeed(20)
		ns.Emulator:Start()
		return true
	end },
}

ns.ScenarioHooks = {
	stop = function() ns.Emulator:Stop() end,
	clear = function() ns.Store:Clear() end,
	running = function() return ns.Emulator.running end,
}

-- The runner: GO and STOP, and the chosen scenario (saved per character).
local Runner = {}
ns.ScenarioRunner = Runner

function Runner:Find(id)
	for _, scenario in ipairs(ns.Scenarios) do
		if scenario.id == id then
			return scenario
		end
	end
end

function Runner:Selected()
	return self:Find(ns.charDb.scenario) or ns.Scenarios[1]
end

function Runner:Select(id)
	if self:Find(id) then
		ns.charDb.scenario = id
	end
end

-- Starts the chosen scenario, stopping any run first and, with clear,
-- wiping what earlier runs left. Returns true, or false and why.
function Runner:Go(clear)
	local scenario = self:Selected()
	if not scenario or not ns.IsDebug() then
		return false, L.CMD_DEBUG_REQUIRED
	end
	ns.ScenarioHooks.stop()
	if clear then
		ns.ScenarioHooks.clear()
	end
	return scenario.run()
end

function Runner:Stop()
	ns.ScenarioHooks.stop()
end

function Runner:Running()
	return ns.ScenarioHooks.running() == true
end
