-- Stamps: short ready-made celebrations to stamp on a feed card (stamps.lua,
-- ui\stamps.lua). Like KekChat, never typed: only these ids travel, and
-- KekChat's muting and spam timeouts apply.
--   id      what travels (letters, numbers, _)
--   text    the stamp's word, inked on the card (none: the emblem alone)
--   emblem  the game's atlas inked beside the word (a garrison class emblem;
--           /qps lab, Stamp emblems, shows which the game has); icon is used
--           where the game lacks it
--   texture  a whole file path, used before the emblem and icon (our own art)
--   icon    under Interface\Icons
--   color   the ink
local _, ns = ...
local L = ns.L

ns.Stamps = {
	{ id = "gg", emblem = "GarrMission_ClassIcon-Monk-Brewmaster", text = L.STAMP_GG, icon = "Achievement_Quests_Completed_06", color = { 1, 0.82, 0 } },
	{ id = "gratz", emblem = "GarrMission_ClassIcon-Priest-Holy", text = L.STAMP_GRATZ, icon = "INV_Misc_Ribbon_01", color = { 0.95, 0.30, 0.72 } },
	{ id = "legend", emblem = "GarrMission_ClassIcon-Paladin-Retribution", text = L.STAMP_LEGEND, icon = "INV_Crown_01", color = { 1, 0.52, 0.08 } },
	{ id = "nice", emblem = "GarrMission_ClassIcon-Hunter-Marksmanship", text = L.STAMP_NICE, icon = "INV_Misc_Gem_Diamond_01", color = { 0.12, 0.80, 0.88 } },
	{ id = "wow", emblem = "GarrMission_ClassIcon-Mage-Arcane", text = L.STAMP_WOW, icon = "Spell_Holy_HolyBolt", color = { 0.98, 0.84, 0.12 } },
	{ id = "lol", emblem = "GarrMission_ClassIcon-Rogue-Outlaw", text = L.STAMP_LOL, icon = "INV_Misc_Toy_10", color = { 0.18, 0.78, 0.28 } },
	{ id = "oof", emblem = "GarrMission_ClassIcon-Warrior-Protection", text = L.STAMP_OOF, icon = "INV_Misc_Bone_HumanSkull_01", color = { 0.90, 0.18, 0.18 } },
	{ id = "rip", emblem = "GarrMission_ClassIcon-DeathKnight-Unholy", text = L.STAMP_RIP, icon = "Spell_Holy_GuardianSpirit", color = { 0.62, 0.30, 0.92 } },
}

ns.StampById = {}
for _, stamp in ipairs(ns.Stamps) do
	ns.StampById[stamp.id] = stamp
end

-- Which cards can be stamped, and the fields that name one of them the same
-- way on every client: the card's player and kind, then these. A card a
-- feed type does not list here has no stamp button.
ns.StampKeys = {
	quest_accepted = { "quest" },
	quest_complete = { "quest" },
	quest_progress = { "quest", "objective" },
	level = { "level" },
	achievement = { "name" },
	discovery = { "zone" },
	death = { "zone", "level" },
}

-- A stamp's impact: KekChat's own effects and sounds (data\effects.lua), a
-- small one at the stamp as it lands, picked at random each time.
--   presets   KekChat's presets to draw from (their effect and images)
--   sounds    KekChat's celebration sounds (SOUNDKIT ids), one at random
--   scale     the effect's size, count and speed, against KekChat's
--   box       the area it plays over, centered on the stamp (width, height)
ns.StampImpact = {
	presets = { "party", "cheers", "fireworks", "gemFountain", "coinRain", "storm" },
	sounds = { 23404, 74702, 73277, 46893 }, -- quest chime, crowd cheer, fanfare, level-up flourish
	scale = 0.55,
	box = { 240, 150 },
}

ns.StampRules = {
	perCard = 24, -- stamps kept on one card (the newest); added up by kind when shown
	perPlayer = 2, -- different stamps one player can put on one card
	keepDays = 7, -- stamps kept, like the stats
	fadeSeconds = 15, -- with Stamps fade on, how long one stays inked
	maxText = 64, -- the longest card key that travels
}
