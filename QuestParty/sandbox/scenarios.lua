-- The sandbox's scenarios, in place of Quest Party's emulator ones (see
-- emulator\scenarios.lua for the fields). Made-up parties come from a seed,
-- so the same scenario makes the same party every time. loopback reads the
-- pretend players straight back here, no network: big parties need it, since
-- one character's send budget cannot carry them over the channel.
local _, ns = ...
local L = ns.L
local Sandbox = ns.Sandbox

-- gearSeconds: how soon, in real seconds, a pretend player's changed gear
-- goes out, in place of the real few-minute wait, so a run shows it.
local function Party(count, seed, speed, loopback, gearSeconds)
	return function()
		ns.Sharing.loopback = loopback
		Sandbox.gearSeconds = gearSeconds
		return Sandbox:StartParty(count, seed, speed)
	end
end

local function Recording(name, speed)
	return function()
		ns.Sharing.loopback = true
		return Sandbox:StartRecording(name, speed)
	end
end

-- Count pretend players all on one quest of three objectives, arriving one
-- after another, most of their kills for it, a few starting ahead. Nobody
-- hands it in, so those done stay on the card, collapsed.
local function SharedQuest(count, seed, speed)
	return function()
		ns.Sharing.loopback = true
		Sandbox.gearSeconds = 15
		return Sandbox:StartParty(count, seed, speed, function(persona)
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
	stop = function() Sandbox:Stop() end,
	clear = function() Sandbox:Wipe() end,
	running = function() return Sandbox.running end,
}
