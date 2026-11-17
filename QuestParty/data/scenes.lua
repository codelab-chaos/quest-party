-- Scenes: painted backgrounds for feed cards, from one atlas image
-- (media\scenes.tga). Each scene is a wide strip, the shape of a feed row;
-- a card shows the middle of it, cropped to the card's own shape
-- (scenes.lua, Scenes:Coords). docs\scenes.md is the artist's brief and
-- scripts\scenes.py builds the template and the atlas from this file.
--
-- The atlas: 1024 x 512, two columns of eight 512 x 64 cells (8 to 1, a
-- feed row's shape), scene 1 top left, 2 top right, 3 under 1, and so on.
local _, ns = ...

ns.SceneAtlas = {
	file = "media\\scenes", -- under the addon's own folder; no extension
	width = 1024,
	height = 512,
	columns = 2,
	cellWidth = 512,
	cellHeight = 64,
}

-- One line each (scripts\scenes.py reads them): id, name, tint (the
-- placeholder's color until the art is in, and the scene's main color),
-- and brief (what to paint).
ns.Scenes = {
	{ id = "meadow", name = "Meadow road", tint = { 0.33, 0.52, 0.22 }, brief = "Sunny rolling meadow, a dirt road, a stone keep far off on the right" },
	{ id = "tavern", name = "Tavern hearth", tint = { 0.55, 0.30, 0.12 }, brief = "Warm tavern inside, hearth fire on the right, mugs and beams" },
	{ id = "crypt", name = "Torchlit crypt", tint = { 0.30, 0.24, 0.20 }, brief = "Stone crypt corridor, torches, cobwebs, glowing eyes far off" },
	{ id = "graveyard", name = "Spirit graveyard", tint = { 0.22, 0.32, 0.42 }, brief = "Moonlit graveyard in mist, an angel's blue glow on the right" },
	{ id = "forge", name = "Dwarven forge", tint = { 0.60, 0.25, 0.08 }, brief = "Forge and anvil, molten glow and sparks on the right, dark stone" },
	{ id = "garden", name = "Herb garden", tint = { 0.30, 0.50, 0.30 }, brief = "Herb garden at dawn, flowers and leaves, soft light" },
	{ id = "starfall", name = "Starfall", tint = { 0.36, 0.14, 0.60 }, brief = "Purple night sky, falling stars and an aurora, for a level-up" },
	{ id = "hoard", name = "Treasure hoard", tint = { 0.62, 0.48, 0.12 }, brief = "Heaped gold coins and an open chest on the right, candle glow" },
	{ id = "map", name = "Explorer's map", tint = { 0.55, 0.45, 0.28 }, brief = "Old parchment map, a compass rose on the right, ink coastlines" },
	{ id = "hall", name = "Hall of heroes", tint = { 0.50, 0.38, 0.10 }, brief = "Grand hall, banners and golden light through tall windows" },
	{ id = "workshop", name = "Gnomish workshop", tint = { 0.42, 0.34, 0.20 }, brief = "Brass cogs, pipes and steam, a half-built contraption on the right" },
	{ id = "harbor", name = "Stormy harbor", tint = { 0.16, 0.30, 0.42 }, brief = "Harbor at dusk, waves, a ship's mast and a lighthouse on the right" },
	{ id = "peaks", name = "Snowy peaks", tint = { 0.45, 0.55, 0.65 }, brief = "Snowy mountains and pines, cold blue light, a lodge on the right" },
	{ id = "dunes", name = "Desert dunes", tint = { 0.70, 0.52, 0.28 }, brief = "Sand dunes at sunset, ruins and a palm on the right" },
	{ id = "woods", name = "Haunted woods", tint = { 0.18, 0.22, 0.20 }, brief = "Dark crooked woods, a pale moon, a lantern on the right" },
	{ id = "cavern", name = "Crystal cavern", tint = { 0.20, 0.35, 0.55 }, brief = "Cave of glowing crystals and gems, blue and violet light" },
}

ns.SceneById = {}
for index, scene in ipairs(ns.Scenes) do
	scene.index = index
	ns.SceneById[scene.id] = scene
end

-- Which scene a feed entry gets: by its type, and for a skill-up by the
-- skill. Swap or mix and match here; any scene can go anywhere.
ns.SceneByType = {
	quest_accepted = "meadow",
	quest_progress = "meadow",
	quest = "meadow",
	quest_complete = "hoard",
	quest_abandoned = "woods",
	kill = "crypt",
	xp = "crypt",
	level = "starfall",
	discovery = "map",
	skill = "forge",
	death = "graveyard",
	joined = "tavern",
	achievement = "hall",
	unknown = "tavern",
}

ns.SceneBySkill = {
	Blacksmithing = "forge",
	Mining = "cavern",
	Jewelcrafting = "cavern",
	Engineering = "workshop",
	Herbalism = "garden",
	Alchemy = "garden",
	Fishing = "harbor",
	Cooking = "tavern",
	Tailoring = "tavern",
	["First Aid"] = "tavern",
	Skinning = "woods",
	Leatherworking = "woods",
	Enchanting = "starfall",
	Inscription = "map",
}
