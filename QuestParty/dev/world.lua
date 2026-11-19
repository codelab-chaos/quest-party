-- Dev mode's made-up world, as data: names, who can be what, where they
-- level, what they do and how often. Change this file to try other parties;
-- no code changes needed. Rates are per hour of play, taken roughly from a
-- real two hour session (14 November 2026).
local _, ns = ...

ns.DevWorld = {
	-- Pretend players' names are built from these.
	firstParts = { "Bram", "Cor", "Dele", "Ely", "Fen", "Gal", "Hal", "Isa", "Jor", "Kel", "Lio", "Mae", "Nor", "Orin", "Pell", "Quen", "Ros", "Syl", "Tam", "Ulf", "Vae", "Wyn", "Yor", "Zel" },
	lastParts = { "wick", "dor", "ra", "ith", "an", "mir", "eth", "wyn", "ric", "a", "ion", "us", "el", "ar", "ys" },
	-- Races (the game's English names, as UnitRace gives them) and their classes.
	races = {
		{ race = "Human", classes = { "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "MAGE", "WARLOCK" } },
		{ race = "Dwarf", classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST" } },
		{ race = "NightElf", classes = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "DRUID" } },
		{ race = "Gnome", classes = { "WARRIOR", "ROGUE", "MAGE", "WARLOCK" } },
		{ race = "Orc", classes = { "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "WARLOCK" } },
		{ race = "Scourge", classes = { "WARRIOR", "ROGUE", "PRIEST", "MAGE", "WARLOCK" } },
		{ race = "Tauren", classes = { "WARRIOR", "HUNTER", "SHAMAN", "DRUID" } },
		{ race = "Troll", classes = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE" } },
	},
	-- Where players of a level quest, and what lives there.
	zones = {
		{ name = "Elwynn Forest", levels = { 1, 12 }, creatures = { "Kobold Vermin", "Young Wolf", "Defias Thug", "Murloc Forager" } },
		{ name = "Tirisfal Glades", levels = { 1, 12 }, creatures = { "Rattlecage Skeleton", "Wandering Spirit", "Scarlet Missionary", "Bleeding Horror" } },
		{ name = "Westfall", levels = { 10, 20 }, creatures = { "Harvest Watcher", "Defias Trapper", "Coyote", "Murloc Coastrunner" } },
		{ name = "Silverpine Forest", levels = { 10, 20 }, creatures = { "Moonrage Whitescalp", "Ravenclaw Drudger", "Giant Rabid Bear" } },
		{ name = "Redridge Mountains", levels = { 15, 25 }, creatures = { "Redridge Gnoll", "Blackrock Grunt", "Tarantula" } },
		{ name = "Duskwood", levels = { 20, 30 }, creatures = { "Skeletal Warrior", "Nightbane Worgen", "Plague Spreader" } },
		{ name = "Stranglethorn Vale", levels = { 30, 45 }, creatures = { "Bloodscalp Warrior", "Jungle Stalker", "Venture Co. Mercenary" } },
		{ name = "Tanaris", levels = { 40, 50 }, creatures = { "Wastewander Bandit", "Sandfury Hideskinner", "Scorpid Hunter" } },
		{ name = "Winterspring", levels = { 52, 60 }, creatures = { "Frostsaber", "Chillwind Ravager", "Winterfall Shaman" } },
	},
	-- Quests are made from these, with the zone's creatures as objectives.
	questForms = { "Culling the %s", "Trouble with %s", "A Report on %s", "Hides of the %s", "WANTED: %s" },
	professions = { "Mining", "Herbalism", "Skinning", "Tailoring", "Cooking", "First Aid", "Fishing" },
	-- Starter items, by slot, so the Items tab has something to show. Item
	-- numbers are the game's; an unknown one shows as a question mark.
	gear = {
		[4] = { 38, 45, 6096 }, -- shirts
		[5] = { 56, 6125 }, -- chest
		[7] = { 39, 1366 }, -- legs
		[8] = { 40, 55 }, -- feet
		[16] = { 25, 35, 2092 }, -- main hand
		[17] = { 2362 }, -- off hand
		[18] = { 2504 }, -- ranged
	},
	-- What happens, and how often, an hour of play at each profile.
	profiles = {
		leveling = {
			kill = 70, -- each kill is XP, and often quest credit
			questCredit = 0.5, -- the chance a kill counts for a quest
			quest = 5, -- quests handed in
			death = 0.6,
			skill = 8,
			discovery = 3,
			newQuest = 6,
			gearChange = 4, -- a slot swapped for another item, or emptied
			decal = 6, -- an icon sent to Quest Party chat
			say = 10, -- a board button pressed in Quest Party chat
		},
		levelCap = {
			kill = 40,
			questCredit = 0.3,
			quest = 3,
			death = 0.3,
			skill = 4,
			discovery = 0.5,
			newQuest = 3,
			gearChange = 2,
			decal = 4,
			say = 6,
		},
	},
	maxLevel = 60,
	-- XP a level needs: a rough curve, close enough for testing.
	xpForLevel = function(level)
		return math.floor(400 + level * level * 40 + level * 160)
	end,
	-- XP for one kill of a creature of the player's level.
	xpForKill = function(level)
		return 45 + level * 5
	end,
	-- XP for a quest turned in.
	xpForQuest = function(level)
		return 100 + level * 60
	end,
	-- How long pretend players play before logging off, in minutes.
	session = { min = 20, max = 120 },
	-- Seconds between pretend players arriving at the start of a run.
	arrivals = { min = 2, max = 20 },
}
