-- Dev mode's test runs (with /qp debug on): what Settings' GO and STOP run,
-- as data, and the runner behind them. Made-up parties come from a seed, so
-- the same scenario makes the same party every time. loopback reads the
-- pretend players straight back here, no network: big parties need it, since
-- one character's send budget cannot carry them over the channel.
--   id      the key saved as the last one chosen
--   label   its name in the dropdown
--   run     starts it; returns true, or false and why
-- ScenarioHooks: how to stop a run, wipe what runs left behind (Clear on go:
-- the pretend players only), and tell whether one is running.
local _, ns = ...
local L = ns.L
local Dev = ns.Dev

-- gearSeconds: how soon, in real seconds, a pretend player's changed gear
-- goes out, in place of the real few-minute wait, so a run shows it.
local function Party(count, seed, speed, loopback, gearSeconds)
	return function()
		ns.Sharing.loopback = loopback
		Dev.gearSeconds = gearSeconds
		return Dev:StartParty(count, seed, speed)
	end
end

local function Recording(name, speed)
	return function()
		ns.Sharing.loopback = true
		return Dev:StartRecording(name, speed)
	end
end

-- Count pretend players all on one quest of three objectives, arriving one
-- after another, most of their kills for it, a few starting ahead. Nobody
-- hands it in, so those done stay on the card, collapsed.
local function SharedQuest(count, seed, speed)
	return function()
		ns.Sharing.loopback = true
		Dev.gearSeconds = 15
		return Dev:StartParty(count, seed, speed, function(persona)
			local random = persona.random
			persona.quests = {}
			persona.questFocus = 0.6
			persona.quests[990001] = {
				questID = 990001,
				quest = "Sharing the Land",
				keep = true,
				objectives = {
					{ index = 1, objective = "Palemane Tanner slain", creature = "Palemane Tanner", have = random.int(0, 3), need = 20 },
					{ index = 2, objective = "Palemane Skinner slain", creature = "Palemane Skinner", have = random.int(0, 2), need = 15 },
					{ index = 3, objective = "Palemane Poacher slain", creature = "Palemane Poacher", have = 0, need = 10 },
				},
			}
		end)
	end
end

ns.Scenarios = {
	{ id = "trio", label = L.SCENARIO_TRIO, run = Party(3, 7, 10, true, 15) },
	{ id = "sharedQuest", label = L.SCENARIO_SHARED_QUEST, run = SharedQuest(10, 13, 5) },
	{ id = "party8", label = L.SCENARIO_PARTY8, run = Party(8, 11, 10, true, 15) },
	{ id = "crowd20", label = L.SCENARIO_CROWD20, run = Party(20, 3, 30, true, 15) },
	{ id = "crowd50", label = L.SCENARIO_CROWD50, run = Party(50, 5, 30, true, 15) },
	{ id = "channel", label = L.SCENARIO_CHANNEL, run = Party(3, 7, 5, false) }, -- the real wait: one send budget
	{ id = "evening", label = L.SCENARIO_REPLAY_ALL, run = Recording("all", 10) },
	{ id = "tirisfal", label = L.SCENARIO_REPLAY_PALADIN, run = Recording("tirisfal", 10) },
	{ id = "silverpine", label = L.SCENARIO_REPLAY_WARRIOR, run = Recording("silverpine", 10) },
}

ns.ScenarioHooks = {
	stop = function() Dev:Stop() end,
	clear = function() Dev:Wipe() end,
	running = function() return Dev.running end,
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
