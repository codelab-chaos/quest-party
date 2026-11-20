-- Marks: the square on the right of every row, as in the winning concept
-- (docs\concept-art\winning-concept-avatars-0.3.5.png): a colored edge, a dark
-- fill, and the art in the middle. Feed types, cards and the filter row name
-- one by id (data\feed-types.lua, data\filters.lua); ui\look.lua draws them.
--   edge, fill   the square's colors (one of the families below)
--   atlas        the game's atlas, tried first
--   texture      the file (a path or a file id), used when there is no atlas
--                (or the game lacks it); before text
--   crop         trims an Interface\Icons border
--   text         drawn instead of art ("XP"), in textColor
--   desaturate   gray art; tint colors it
--   scale        the art's share of the square (1 fills it)
local _, ns = ...

-- The concept's families: gold for quests and finds, purple for XP, blue for
-- people and skills, red for death, gray for what is gone or unknown.
local GOLD = { edge = { 0.88, 0.70, 0.22, 1 }, fill = { 0.14, 0.09, 0.02, 1 } }
local PURPLE = { edge = { 0.74, 0.38, 0.98, 1 }, fill = { 0.28, 0.07, 0.42, 1 } }
local BLUE = { edge = { 0.38, 0.64, 1.00, 1 }, fill = { 0.04, 0.11, 0.28, 1 } }
local RED = { edge = { 0.88, 0.22, 0.18, 1 }, fill = { 0.22, 0.04, 0.03, 1 } }
local GRAY = { edge = { 0.55, 0.55, 0.55, 1 }, fill = { 0.09, 0.09, 0.09, 1 } }
local GREEN = { edge = { 0.35, 0.80, 0.40, 1 }, fill = { 0.04, 0.18, 0.07, 1 } } -- KekChat

local function Mark(family, look)
	look.edge, look.fill = family.edge, family.fill
	look.scale = look.scale or 0.82
	return look
end

ns.MarkLooks = {
	-- The game's own quest marks: the yellow ! of a quest taken, the yellow ?
	-- of one to hand in.
	questTaken = Mark(GOLD, { texture = "Interface\\GossipFrame\\AvailableQuestIcon", scale = 0.95 }),
	questDone = Mark(GOLD, { texture = 236669, crop = true }), -- the owner's pick (file 236669)
	questDropped = Mark(GRAY, { texture = "Interface\\GossipFrame\\AvailableQuestIcon", scale = 0.95, desaturate = true, tint = { 1, 0.55, 0.50 } }),
	-- The garrison's purple XP (file 894556), the owner's pick.
	xp = Mark(PURPLE, { texture = 894556, scale = 1, text = "XP", textColor = { 1, 1, 1 } }),
	discovery = Mark(GOLD, { texture = "Interface\\Icons\\INV_Misc_Map_01", crop = true }),
	skill = Mark(BLUE, { texture = "Interface\\Icons\\Trade_BlackSmithing", crop = true }),
	joined = Mark(BLUE, { atlas = "socialqueuing-icon-group", texture = "Interface\\Icons\\achievement_guildperk_everybodysfriend", crop = true }),
	kills = Mark(PURPLE, { texture = "Interface\\Icons\\Ability_DualWield", crop = true }),
	death = Mark(RED, { texture = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", crop = true }),
	achievement = Mark(GOLD, { texture = "Interface\\Icons\\achievement_reputation_01", crop = true }),
	chat = Mark(GREEN, { texture = "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", scale = 0.9 }),
	unknown = Mark(GRAY, { texture = "Interface\\Icons\\INV_Misc_QuestionMark", crop = true }),
}
