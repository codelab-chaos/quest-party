-- Chat effects, as data: what the particle engine (particles.lua) does with
-- the images a message carries. Distances in pixels, times in seconds, y down
-- from the top of the area the effect plays over. Only an effect's id
-- travels; every client plays it from its own copy of this list.
--   pattern  how particles start: rain (from the top), burst (from the
--            middle), fireworks (rockets that pop into bursts), fountain (up
--            from the bottom), swirl (spiralling out from the middle)
--   count    particles (for fireworks, sparks in each burst)
--   life     how long one lives; it fades over the last fade of it
--   size     the particle's size range
--   speed    the starting speed range
--   gravity  added to the falling speed each second; terminal caps it
--   spin     turning speed, up to this either way
--   stagger  particles start over this long, so they do not all appear at once
--   sound    a game sound (SOUNDKIT id) played with it, when Chat sounds is on;
--            one the client does not have just plays nothing
local _, ns = ...
local L = ns.L

ns.ChatEffects = {
	{ id = "rain", label = L.EFFECT_RAIN, icon = "Spell_Frost_FrostBolt02", pattern = "rain", sound = 23404, -- quest complete chime
		count = 34, stagger = 1.4, life = 2.6, fade = 0.6, size = { 14, 24 }, speed = { 40, 90 },
		gravity = 140, terminal = 170, spin = 3, drift = 20 },
	{ id = "celebrate", label = L.EFFECT_CELEBRATE, icon = "INV_Misc_Ribbon_01", pattern = "burst", sound = 74702, -- a crowd cheering
		count = 40, stagger = 0.15, life = 1.9, fade = 0.7, size = { 14, 26 }, speed = { 140, 280 },
		gravity = 320, terminal = 400, spin = 6 },
	{ id = "fireworks", label = L.EFFECT_FIREWORKS, icon = "INV_Misc_Bomb_08", pattern = "fireworks", sound = 73277, -- a victory fanfare
		rockets = 3, rocketSpeed = { 240, 300 }, fuse = { 0.55, 0.9 }, rocketStagger = 0.8,
		count = 16, life = 1.4, fade = 0.6, size = { 12, 22 }, speed = { 70, 170 },
		gravity = 120, terminal = 220, spin = 5 },
	{ id = "fountain", label = L.EFFECT_FOUNTAIN, icon = "INV_Drink_05", pattern = "fountain", sound = 46893, -- a level-up flourish
		count = 40, stagger = 1.2, life = 2.0, fade = 0.5, size = { 12, 22 }, speed = { 240, 330 },
		spread = 0.45, gravity = 420, terminal = 500, spin = 4 },
	{ id = "swirl", label = L.EFFECT_SWIRL, icon = "Spell_Nature_Lightning", pattern = "swirl",
		count = 24, stagger = 0.9, life = 2.2, fade = 0.7, size = { 14, 24 }, speed = { 50, 80 },
		turn = 4.5, spin = 3 },
}

-- The effects strip in chat: preset messages, one click to send. Not built
-- by the player (yet). Each comes empty (images only) or worded (with a
-- saying, whose words fall as particles among the images).
--   effect  an id above; icons, paths under Interface\Icons (ones the game
--           does not know are left out); saying, an id from data\chat.lua
ns.EffectPresets = {
	{ id = "coinRain", label = L.PRESET_COIN_RAIN, effect = "rain", icons = { "INV_Misc_Coin_01", "INV_Misc_Coin_02" } },
	{ id = "gratzRain", label = L.PRESET_GRATZ_RAIN, effect = "rain", icons = { "Achievement_Reputation_01", "INV_Misc_Coin_01" }, saying = "gz" },
	{ id = "party", label = L.PRESET_PARTY, effect = "celebrate", icons = { "INV_Misc_Ribbon_01", "INV_Misc_Gem_Ruby_01", "INV_Misc_Gem_Sapphire_01" } },
	{ id = "cheers", label = L.PRESET_CHEERS, effect = "celebrate", icons = { "INV_Misc_Ribbon_01", "INV_Drink_04" }, saying = "cheer" },
	{ id = "fireworks", label = L.PRESET_FIREWORKS, effect = "fireworks", icons = { "INV_Misc_Gem_Diamond_01", "INV_Misc_Gem_Emerald_01", "INV_Misc_Gem_Ruby_01" } },
	{ id = "gratzFireworks", label = L.PRESET_GRATZ_FIREWORKS, effect = "fireworks", icons = { "Achievement_Reputation_01", "INV_Misc_Gem_Diamond_01" }, saying = "gz" },
	{ id = "gemFountain", label = L.PRESET_GEM_FOUNTAIN, effect = "fountain", icons = { "INV_Misc_Gem_Emerald_01", "INV_Misc_Gem_Pearl_01", "INV_Misc_Gem_Sapphire_01" } },
	{ id = "thanksFountain", label = L.PRESET_THANKS_FOUNTAIN, effect = "fountain", icons = { "INV_Misc_Gift_01" }, saying = "ty" },
	{ id = "storm", label = L.PRESET_STORM, effect = "swirl", icons = { "Spell_Nature_Lightning", "Spell_Frost_FrostBolt02" } },
	{ id = "goodnight", label = L.PRESET_GOOD_NIGHT, effect = "swirl", icons = { "INV_Misc_Rune_01" }, saying = "gn" },
}

-- The dock's puff: a small burst of an event's icon from its bar, while the
-- panel is minimized (ui\dock.lua). Not one of chat's effects.
ns.DockPuff = { id = "puff", pattern = "burst", count = 10, stagger = 0.05, life = 0.9, fade = 0.5,
	size = { 10, 16 }, speed = { 60, 140 }, gravity = 220, terminal = 300, spin = 5 }

ns.ChatEffectById = {}
for _, effect in ipairs(ns.ChatEffects) do
	ns.ChatEffectById[effect.id] = effect
end

ns.ParticleRules = {
	maxParticles = 160, -- in the air at once, however many effects overlap
	maxStep = 0.05, -- a long frame is stepped as at most this, so nothing leaps
	maxImages = 3, -- images one message can carry
	wordShare = 0.3, -- of a worded effect's particles, this many are its words
	maxWords = 8,
}
