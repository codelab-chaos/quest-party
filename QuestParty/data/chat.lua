-- Quest Party chat, as data: its limits, the sayings and the icons the image
-- picker can search. See
-- docs\chat.md and chat.lua.
local _, ns = ...
local L = ns.L

ns.ChatRules = {
	burst = 5, -- messages a player may send in burstSeconds
	burstSeconds = 10,
	-- Going over the burst is a timeout, as team chat has in Rocket League:
	-- yours can not be sent, and a spammer's are hidden here, for this long,
	-- doubling each time it happens again (to timeoutMax), back to the start
	-- after timeoutForgetSeconds without one.
	timeoutSeconds = 15,
	timeoutMax = 120,
	timeoutForgetSeconds = 300,
	maxPresets = 20, -- saved image and saying pairs
	-- Your KekChats (chat.lua, the editor ui\kek-editor.lua): this many, each
	-- an icon, words of your own up to maxText, a sound and an effect. One
	-- message carries it all: 255 characters, about 60 of them the rest of the
	-- message, and a few characters (; = : # %) travel as three.
	maxMessages = 10,
	maxText = 100,
}

-- The sounds a KekChat can carry: fun ones from the game's own (SOUNDKIT
-- names, so every client plays the same; kit is the id when the name is
-- missing). Only the id travels; one this version lacks plays nothing.
ns.KekSounds = {
	{ id = "cheer", label = L.KEK_SOUND_CHEER, name = "UI_MISSION_SUCCESS_CHEERS", kit = 74702 },
	{ id = "fanfare", label = L.KEK_SOUND_FANFARE, name = "UI_WORLDQUEST_COMPLETE", kit = 73277 },
	{ id = "chime", label = L.KEK_SOUND_CHIME, name = "UI_AUTO_QUEST_COMPLETE", kit = 23404 },
	{ id = "flourish", label = L.KEK_SOUND_FLOURISH, name = "UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP", kit = 46893 },
	{ id = "levelup", label = L.KEK_SOUND_LEVELUP, name = "UI_ADVENTURES_ADVENTURER_LEVEL_UP", kit = 167127 },
	{ id = "success", label = L.KEK_SOUND_SUCCESS, name = "UI_GARRISON_COMMAND_TABLE_MISSION_SUCCESS_STINGER", kit = 44330 },
	{ id = "fail", label = L.KEK_SOUND_FAIL, name = "UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER", kit = 43503 },
	{ id = "party", label = L.KEK_SOUND_PARTY, name = "TRADING_POST_UI_PURCHASE_CELEBRATION", kit = 218231 },
	{ id = "coins", label = L.KEK_SOUND_COINS, name = "TRADING_POST_UI_COLLECTING_COINS", kit = 218228 },
	{ id = "coin", label = L.KEK_SOUND_COIN, name = "LOOT_WINDOW_COIN_SOUND", kit = 120 },
	{ id = "ready", label = L.KEK_SOUND_READY, name = "READY_CHECK", kit = 8960 },
	{ id = "warning", label = L.KEK_SOUND_WARNING, name = "RAID_WARNING", kit = 8959 },
	{ id = "queue", label = L.KEK_SOUND_QUEUE, name = "PVP_THROUGH_QUEUE", kit = 8459 },
	{ id = "countdown", label = L.KEK_SOUND_COUNTDOWN, name = "UI_COUNTDOWN_FINISHED", kit = 158566 },
	{ id = "built", label = L.KEK_SOUND_BUILT, name = "UI_GARRISON_TOAST_BUILDING_COMPLETE", kit = 44295 },
	{ id = "alarm", label = L.KEK_SOUND_ALARM, name = "ALARM_CLOCK_WARNING_2", kit = 12867 },
}
ns.KekSoundById = {}
for _, sound in ipairs(ns.KekSounds) do
	ns.KekSoundById[sound.id] = sound
end

-- The sayings: the only words Quest Party chat carries. Only an id travels,
-- so what shows is always from this list, in the reader's own language, and
-- nobody can put words of their own on anyone's screen. An id this version
-- does not know (from a newer one) is not shown.
--   effect  something it also does on everyone's screen ("confetti")
ns.Sayings = {
	{ id = "hi", text = L.SAY_HI },
	{ id = "gz", text = L.SAY_GZ },
	{ id = "ty", text = L.SAY_TY },
	{ id = "omw", text = L.SAY_OMW },
	{ id = "wait", text = L.SAY_WAIT },
	{ id = "help", text = L.SAY_HELP },
	{ id = "ready", text = L.SAY_READY },
	{ id = "brb", text = L.SAY_BRB },
	{ id = "lol", text = L.SAY_LOL },
	{ id = "gn", text = L.SAY_GN },
	{ id = "cheer", text = L.SAY_CHEER, effect = "confetti" },
}

ns.SayingById = {}
for _, saying in ipairs(ns.Sayings) do
	ns.SayingById[saying.id] = saying
end

-- Built-in presets: messages ready to send, for anyone who does not want to
-- make their own. Shown above the player's own presets and cannot be
-- removed. icons are paths under Interface\Icons (one the game does not know
-- is left out), saying an id from Sayings. Effects are sent from the effects
-- strip instead (data\effects.lua, EffectPresets).
ns.ChatPresets = {
	{ icons = { "Ability_Warrior_BattleShout" }, saying = "hi" },
	{ icons = { "Achievement_Reputation_01" }, saying = "gz" },
	{ icons = { "INV_Misc_Ribbon_01" }, saying = "cheer" },
	{ icons = { "INV_Misc_Gift_01" }, saying = "ty" },
	{ icons = { "Ability_Rogue_Sprint" }, saying = "omw" },
	{ icons = { "Spell_Holy_Heal" }, saying = "help" },
	{ icons = { "INV_Drink_05" }, saying = "brb" },
	{ icons = { "INV_Misc_Rune_01" }, saying = "gn" },
}

-- Your KekChats to start with (chat.lua; changed in the editor): an icon
-- (a path under Interface\Icons; its picture is also the effect's particles),
-- the words, a sound (KekSounds) and an effect (ChatEffects), either optional.
ns.KekDefaults = {
	{ icon = "Ability_Warrior_RallyingCry", text = L.KEK_DEFAULT_WELCOME, sound = "cheer" },
	{ icon = "Ability_Warrior_BattleShout", text = L.KEK_DEFAULT_HEY, sound = "ready" },
	{ icon = "Achievement_Reputation_01", text = L.KEK_DEFAULT_GRATZ, sound = "cheer", effect = "celebrate" },
	{ icon = "INV_Misc_Gift_01", text = L.KEK_DEFAULT_THANKS, sound = "chime" },
	{ icon = "Ability_Rogue_Sprint", text = L.KEK_DEFAULT_OMW, sound = "queue" },
	{ icon = "INV_Drink_05", text = L.KEK_DEFAULT_BRB },
	{ icon = "Spell_Arcane_Starfire", text = L.KEK_DEFAULT_AMAZING, sound = "fanfare", effect = "fireworks" },
	{ icon = "INV_Misc_Ribbon_01", text = L.KEK_DEFAULT_DANCE, sound = "party", effect = "celebrate" },
	{ icon = "Spell_Holy_AuraOfLight", text = L.KEK_DEFAULT_AURA, sound = "flourish", effect = "swirl" },
	{ icon = "Spell_Nature_Sleep", text = L.KEK_DEFAULT_NIGHT },
}

-- The icons the image picker can search: a path under Interface\Icons and words to find
-- it by (the path's own words count too). Turned into file IDs at load;
-- paths the game does not know are dropped, so a wrong guess costs nothing.
ns.IconCatalog = {
	{ path = "INV_Misc_Gem_01", tags = "gem jewel" },
	{ path = "INV_Misc_Gem_02", tags = "gem jewel" },
	{ path = "INV_Misc_Gem_Ruby_01", tags = "gem ruby red jewel" },
	{ path = "INV_Misc_Gem_Sapphire_01", tags = "gem sapphire blue jewel" },
	{ path = "INV_Misc_Gem_Emerald_01", tags = "gem emerald green jewel" },
	{ path = "INV_Misc_Gem_Diamond_01", tags = "gem diamond jewel shiny" },
	{ path = "INV_Misc_Gem_Pearl_01", tags = "gem pearl jewel" },
	{ path = "INV_Misc_Coin_01", tags = "coin gold money rich" },
	{ path = "INV_Misc_Coin_02", tags = "coin silver money" },
	{ path = "INV_Misc_Bag_08", tags = "bag loot" },
	{ path = "INV_Box_01", tags = "box chest loot" },
	{ path = "INV_Misc_Gift_01", tags = "gift present thanks" },
	{ path = "INV_Misc_Food_15", tags = "food eat bread" },
	{ path = "INV_Drink_05", tags = "drink water thirsty" },
	{ path = "INV_Drink_04", tags = "drink ale beer cheers" },
	{ path = "INV_Misc_Fish_02", tags = "fish fishing" },
	{ path = "INV_Misc_Herb_10", tags = "herb flower herbalism" },
	{ path = "INV_Ore_Copper_01", tags = "ore copper mining" },
	{ path = "INV_Misc_Pelt_Wolf_01", tags = "pelt leather skinning wolf" },
	{ path = "INV_Fabric_Linen_01", tags = "cloth linen tailoring" },
	{ path = "INV_Misc_QuestionMark", tags = "question what huh" },
	{ path = "INV_Misc_Note_01", tags = "note quest letter" },
	{ path = "INV_Misc_Map_01", tags = "map where lost" },
	{ path = "INV_Misc_Key_03", tags = "key" },
	{ path = "INV_Misc_Rune_01", tags = "hearth home rune" },
	{ path = "INV_Misc_Spyglass_03", tags = "spyglass look scout" },
	{ path = "INV_Misc_Book_09", tags = "book read lore" },
	{ path = "INV_Misc_Bandage_15", tags = "bandage heal first aid" },
	{ path = "INV_Misc_Bone_HumanSkull_01", tags = "skull dead death rip" },
	{ path = "INV_Misc_Bone_Skull_02", tags = "skull kill" },
	{ path = "INV_Misc_Head_Dragon_01", tags = "dragon head boss" },
	{ path = "INV_Misc_Head_Murloc_01", tags = "murloc mrgl" },
	{ path = "INV_Misc_Bomb_08", tags = "bomb boom engineering" },
	{ path = "INV_Misc_Ribbon_01", tags = "ribbon party" },
	{ path = "INV_Jewelry_Ring_03", tags = "ring jewelry" },
	{ path = "INV_Potion_51", tags = "potion heal health red" },
	{ path = "INV_Potion_54", tags = "potion mana blue" },
	{ path = "INV_Sword_04", tags = "sword weapon fight" },
	{ path = "INV_Axe_01", tags = "axe weapon" },
	{ path = "INV_Mace_01", tags = "mace hammer weapon" },
	{ path = "INV_Staff_01", tags = "staff weapon" },
	{ path = "INV_Weapon_Bow_02", tags = "bow arrow hunter" },
	{ path = "INV_Shield_04", tags = "shield tank" },
	{ path = "INV_Helmet_01", tags = "helmet armor" },
	{ path = "INV_Chest_Plate01", tags = "armor chest plate" },
	{ path = "Spell_Holy_Heal", tags = "heal holy priest" },
	{ path = "Spell_Holy_PowerWordShield", tags = "shield priest bubble" },
	{ path = "Spell_Holy_SealOfMight", tags = "might strong paladin" },
	{ path = "Spell_Fire_Fireball02", tags = "fire fireball mage hot" },
	{ path = "Spell_Frost_FrostBolt02", tags = "frost ice cold mage" },
	{ path = "Spell_Nature_Lightning", tags = "lightning storm shaman" },
	{ path = "Spell_Nature_Polymorph", tags = "sheep polymorph baa" },
	{ path = "Spell_Shadow_ShadowBolt", tags = "shadow warlock" },
	{ path = "Spell_Shadow_DeathScream", tags = "scream fear" },
	{ path = "Spell_Nature_AstralRecalGroup", tags = "quest party group together" },
	{ path = "Spell_Holy_Resurrection", tags = "rez resurrect revive" },
	{ path = "Ability_Warrior_BattleShout", tags = "shout battle cheer hi" },
	{ path = "Ability_Rogue_Sprint", tags = "sprint run fast go" },
	{ path = "Ability_Mount_RidingHorse", tags = "horse mount ride" },
	{ path = "Ability_Hunter_Pet_Wolf", tags = "wolf pet" },
	{ path = "Ability_Seal", tags = "seal ok" },
	{ path = "Trade_Engineering", tags = "engineering gear gnome" },
	{ path = "Trade_Mining", tags = "mining pick" },
	{ path = "Trade_Herbalism", tags = "herbalism flower" },
	{ path = "Trade_Fishing", tags = "fishing pole" },
	{ path = "Trade_BlackSmithing", tags = "blacksmithing anvil" },
	{ path = "XP_Icon", tags = "xp level ding" },
	{ path = "Achievement_Reputation_01", tags = "achievement trophy win gg" },
}
