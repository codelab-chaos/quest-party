-- Sample game events for /qp test, taken from Quest Tweet's own test list.
-- Each row is an event name followed by the arguments the game would pass.
local _, ns = ...

-- Local tests for /qp testloc <target>: what each shows, as your own
-- character, in your panel only. Each gives the entries to show (feed rows,
-- through the store as if they had happened) and may set off an effect.
-- Nothing is sent to the channel: they never pass through the collectors.
local function Me()
	local _, class = UnitClass("player")
	return UnitName("player"), class, UnitLevel("player") or 1
end

local function Entry(typeName, data)
	local player, class = Me()
	return { type = typeName, player = player, class = class, data = data }
end

ns.LocalTests = {
	{ id = "confetti", effect = "confetti" },
	{ id = "level", entries = function()
		local _, _, level = Me()
		return { Entry("level", { level = level + 1 }) }
	end },
	{ id = "death", entries = function()
		local _, _, level = Me()
		return { Entry("death", { zone = GetRealZoneText() or "Elwynn Forest", level = level }) }
	end },
	{ id = "quest", entries = function()
		return { Entry("quest_complete", { quest = "A Test of Courage", xp = 875 }) }
	end },
	{ id = "kill", entries = function()
		local _, _, level = Me()
		return { Entry("xp", { xp = 65, level = level, currentXP = 400, maxXP = 1000, mob = "Riverpaw Gnoll" }) }
	end },
}

ns.LocalTestById = {}
for _, localTest in ipairs(ns.LocalTests) do
	ns.LocalTestById[localTest.id] = localTest
end

ns.CollectorSamples = {
	{ "PLAYER_LEVEL_UP", 20 },
	{ "UI_INFO_MESSAGE", 368, "Discovered: Echo Ridge Mine" },
	{ "CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 26 experience." },
	{ "UI_INFO_MESSAGE", 286, "Kobold Workers slain: 1/10" },
	{ "CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 26 experience. (+13 exp Rested bonus)" },
	{ "UI_INFO_MESSAGE", 286, "Kobold Workers slain: 2/10" },
	{ "CHAT_MSG_COMBAT_XP_GAIN", "Vale Moth dies, you gain 26 experience." },
	{ "CHAT_MSG_SKILL", "Your skill in Herbalism has increased to 62." },
	{ "PLAYER_DEAD" },
}
