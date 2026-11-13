-- Sample game events for /qp test, taken from Quest Tweet's own test list.
-- Each row is an event name followed by the arguments the game would pass.
local _, ns = ...

ns.CollectorSamples = {
	{ "PLAYER_LEVEL_UP", 20 },
	{ "UI_INFO_MESSAGE", 368, "Discovered: Echo Ridge Mine" },
	{ "CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 26 experience." },
	{ "UI_INFO_MESSAGE", 286, "Kobold Workers slain: 1/10" },
	{ "CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 26 experience. (+13 exp Rested bonus)" },
	{ "UI_INFO_MESSAGE", 286, "Kobold Workers slain: 2/10" },
	{ "CHAT_MSG_COMBAT_XP_GAIN", "Vale Moth dies, you gain 26 experience." },
	{ "CHAT_MSG_SKILL", "Your skill in Herbalism has increased to 62." },
}
