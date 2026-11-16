-- The sandbox's pretend players: made from a seed (Party.Make), each living
-- a small made-up life one event at a time (Party.Step). Pure: no game calls,
-- so a whole party's evening can be played and checked in a test.
--
-- A persona looks like:
--   { name, class, race, sex, level, currentXP, maxXP, zone, profile,
--     quests = { [questID] = { questID, quest, objectives = { { index, objective, have, need } } } },
--     gear = { [slot] = "item:enchant:suffix" }, skills = { [name] = level } }
--
-- Step returns what happened as a list of actions for the driver to send:
--   { send = "entry", type = feed type, data = entry data }
--   { send = "quest", quest = the quest as it stands now }
--   { send = "hello" }   the persona's hello fields changed (level, zone)
local _, ns = ...

local Party = {}
ns.SandboxParty = Party

local function World()
	return ns.SandboxWorld
end

local function ZonesFor(level)
	local zones = {}
	for _, zone in ipairs(World().zones) do
		if level >= zone.levels[1] and level <= zone.levels[2] then
			zones[#zones + 1] = zone
		end
	end
	return #zones > 0 and zones or { World().zones[#World().zones] }
end

local function ZoneByName(name)
	for _, zone in ipairs(World().zones) do
		if zone.name == name then
			return zone
		end
	end
end

-- A name not already taken in the party.
local function MakeName(random, taken)
	for _ = 1, 50 do
		local name = random.pick(World().firstParts) .. random.pick(World().lastParts)
		if not taken[name] then
			taken[name] = true
			return name
		end
	end
	local name = "Pretend" .. random.int(1000, 9999)
	taken[name] = true
	return name
end

local questNumber = 0
local function NewQuest(persona, random)
	local zone = ZoneByName(persona.zone) or ZonesFor(persona.level)[1]
	local creature = random.pick(zone.creatures)
	questNumber = questNumber + 1
	-- Pretend quest numbers sit far above the game's own.
	local id = 900000 + random.int(0, 89999) + questNumber
	local quest = {
		questID = id,
		quest = random.pick(World().questForms):format(creature),
		objectives = { { index = 1, objective = creature .. " slain", creature = creature, have = 0, need = random.int(5, 12) } },
	}
	persona.quests[id] = quest
	return quest
end

-- Makes count pretend players from a seed. The same seed makes the same party.
function Party.Make(seed, count)
	local random = ns.SandboxRandom.New(seed)
	local taken, personas = {}, {}
	for index = 1, count do
		local raceInfo = random.pick(World().races)
		local level = random.int(1, World().maxLevel)
		local zone = random.pick(ZonesFor(level))
		local persona = {
			name = MakeName(random, taken),
			class = random.pick(raceInfo.classes),
			race = raceInfo.race,
			sex = random.int(2, 3),
			level = level,
			maxXP = level >= World().maxLevel and 0 or World().xpForLevel(level),
			zone = zone.name,
			profile = level >= World().maxLevel and "levelCap" or "leveling",
			quests = {},
			gear = {},
			skills = { [random.pick(World().professions)] = random.int(1, 150) },
			random = ns.SandboxRandom.New(seed * 1000 + index),
		}
		persona.currentXP = persona.maxXP > 0 and random.int(0, persona.maxXP - 1) or 0
		for slot, items in pairs(World().gear) do
			if random.chance(0.8) then
				persona.gear[slot] = ("%d:0:0"):format(random.pick(items))
			end
		end
		for _ = 1, random.int(1, 3) do
			NewQuest(persona, persona.random)
		end
		personas[index] = persona
	end
	return personas
end

-- The persona's hello fields, as it stands now.
function Party.Hello(persona)
	return {
		v = persona.version or "sandbox",
		l = persona.level,
		z = persona.zone,
		x = persona.currentXP,
		m = persona.maxXP,
		r = persona.race,
		g = persona.sex,
	}
end

-- Seconds until the persona's next event.
function Party.NextGap(persona)
	local rates, total = World().profiles[persona.profile], 0
	for key, rate in pairs(rates) do
		if key ~= "questCredit" then
			total = total + rate
		end
	end
	return persona.random.gap(total)
end

local function GainXP(persona, xp, actions, data)
	if persona.maxXP == 0 then
		return
	end
	persona.currentXP = persona.currentXP + xp
	local leveled = false
	while persona.maxXP > 0 and persona.currentXP >= persona.maxXP do
		persona.currentXP = persona.currentXP - persona.maxXP
		persona.level = persona.level + 1
		leveled = true
		if persona.level >= World().maxLevel then
			persona.level, persona.maxXP, persona.currentXP, persona.profile = World().maxLevel, 0, 0, "levelCap"
		else
			persona.maxXP = World().xpForLevel(persona.level)
		end
	end
	data.xp, data.level, data.currentXP, data.maxXP = xp, persona.level, persona.currentXP, persona.maxXP
	actions[#actions + 1] = { send = "entry", type = "xp", data = data }
	if leveled then
		actions[#actions + 1] = { send = "entry", type = "level", data = { level = persona.level } }
		actions[#actions + 1] = { send = "hello" }
	end
end

local events = {}

function events.kill(persona, actions)
	local random = persona.random
	local zone = ZoneByName(persona.zone) or ZonesFor(persona.level)[1]
	local creature = random.pick(zone.creatures)
	local rates = World().profiles[persona.profile]
	-- Quest credit: a quest of the persona's that wants this kind of kill.
	if random.chance(rates.questCredit) then
		for _, quest in pairs(persona.quests) do
			local objective = quest.objectives[1]
			if objective.have < objective.need then
				creature = objective.creature or creature
				objective.have = objective.have + 1
				actions[#actions + 1] = { send = "entry", type = "kill", data = { mob = creature, quest = quest.quest, questID = quest.questID, xp = World().xpForKill(persona.level) } }
				actions[#actions + 1] = { send = "entry", type = "quest_progress", data = { quest = quest.quest, questID = quest.questID, objective = objective.objective, objectiveIndex = 1, have = objective.have, need = objective.need } }
				actions[#actions + 1] = { send = "quest", quest = quest }
				break
			end
		end
	end
	GainXP(persona, World().xpForKill(persona.level), actions, { mob = creature })
end

function events.quest(persona, actions)
	for id, quest in pairs(persona.quests) do
		local objective = quest.objectives[1]
		if objective.have >= objective.need then
			persona.quests[id] = nil
			local xp = World().xpForQuest(persona.level)
			actions[#actions + 1] = { send = "entry", type = "quest_complete", data = { quest = quest.quest, questID = quest.questID, xp = xp } }
			GainXP(persona, xp, actions, { quest = quest.quest })
			return
		end
	end
end

function events.newQuest(persona, actions)
	local count = 0
	for _ in pairs(persona.quests) do count = count + 1 end
	if count >= 5 then
		return
	end
	local quest = NewQuest(persona, persona.random)
	actions[#actions + 1] = { send = "entry", type = "quest_accepted", data = { quest = quest.quest, questID = quest.questID } }
	actions[#actions + 1] = { send = "quest", quest = quest }
end

function events.death(persona, actions)
	actions[#actions + 1] = { send = "entry", type = "death", data = { zone = persona.zone, level = persona.level } }
end

function events.skill(persona, actions)
	local name, level = next(persona.skills)
	if name and level < 300 then
		persona.skills[name] = level + 1
		actions[#actions + 1] = { send = "entry", type = "skill", data = { skill = name, level = level + 1 } }
	end
end

-- A slot swapped for another of the world's items for it, or emptied now and
-- then. The whole set goes out under the same rule as a real player's
-- (sandbox.lua, gear).
function events.gearChange(persona, actions)
	local slots = {}
	for slot in pairs(World().gear) do
		slots[#slots + 1] = slot
	end
	table.sort(slots) -- pairs has no order; the same seed must pick the same
	local slot = persona.random.pick(slots)
	if persona.gear[slot] and persona.random.chance(0.2) then
		persona.gear[slot] = nil
	else
		persona.gear[slot] = ("%d:0:0"):format(persona.random.pick(World().gear[slot]))
	end
	actions[#actions + 1] = { send = "gear" }
end

function events.discovery(persona, actions)
	local zone = persona.random.pick(ZonesFor(persona.level))
	if zone.name ~= persona.zone then
		persona.zone = zone.name
		actions[#actions + 1] = { send = "entry", type = "discovery", data = { zone = zone.name } }
		actions[#actions + 1] = { send = "hello" }
	end
end

-- One event in the persona's life, picked by the rates of its profile.
-- Returns the actions to send.
function Party.Step(persona)
	local rates = World().profiles[persona.profile]
	local names, total = {}, 0
	for key, rate in pairs(rates) do
		if events[key] then
			names[#names + 1] = key
			total = total + rate
		end
	end
	table.sort(names) -- pairs has no order; the same seed must pick the same
	local roll, actions = persona.random.next() * total, {}
	for _, key in ipairs(names) do
		roll = roll - rates[key]
		if roll <= 0 then
			events[key](persona, actions)
			return actions
		end
	end
	return actions
end

-- The quests a persona is working on, as QUEST messages want them.
function Party.Quests(persona)
	local list = {}
	for _, quest in pairs(persona.quests) do
		list[#list + 1] = quest
	end
	table.sort(list, function(a, b) return a.questID < b.questID end)
	return list
end
