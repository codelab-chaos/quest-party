-- Facade data for the emulator: who is "playing" and what they do.
-- Edit this file to try different situations in the panel. No code changes needed.
--
-- Step fields:
--   after  seconds to wait before this step
--   who    a key in personas
--   type   a key in data\feed-types.lua
--   data   the entry payload for that type
--   count  optional, repeats the step while counting a data field up:
--          { field = "have", from = 1, to = 10, every = 3 } emits ten entries, 3 seconds apart
--   kill   optional, a kill that happens just before the step (and before each repeat):
--          { mob = "Redridge Gnoll", xp = 65 }. Use it to tie quest credit to a kill.
--          A kill made for a quest that gave no credit (the item did not drop) is a plain
--          step with type = "kill" and a quest in its data.
--          A kill with no quest in its data is ignored by the addon. One is kept in the
--          script to prove that.
local _, ns = ...

-- The shared party quest. Each member works it at their own pace, in turns.
local CALL_TO_ARMS = "A Call to Arms"

local function GnollKills(who, from, to, every, after)
	return {
		after = after or every, who = who, type = "quest_progress",
		data = { quest = CALL_TO_ARMS, objective = "Redridge Gnoll", need = 10 },
		kill = { mob = "Redridge Gnoll", xp = 65 },
		count = { field = "have", from = from, to = to, every = every },
	}
end

ns.EmulatorScript = {
	personas = {
		jaina = { name = "Jaina", class = "MAGE" },
		thrall = { name = "Thrall", class = "SHAMAN" },
		uther = { name = "Uther", class = "PALADIN" },
	},

	steps = {
		-- Everyone checks in.
		{ after = 1, who = "jaina", type = "level", data = { level = 23 } },
		{ after = 1, who = "thrall", type = "level", data = { level = 22 } },
		{ after = 1, who = "uther", type = "level", data = { level = 24 } },
		{ after = 1, who = "jaina", type = "discovery", data = { zone = "Redridge Mountains" } },
		{ after = 1, who = "thrall", type = "discovery", data = { zone = "Redridge Mountains" } },
		{ after = 1, who = "uther", type = "discovery", data = { zone = "Redridge Mountains" } },

		-- The whole party picks up the same quest and works it together.
		{ after = 3, who = "jaina", type = "quest_accepted", data = { quest = CALL_TO_ARMS } },
		{ after = 1, who = "uther", type = "quest_accepted", data = { quest = CALL_TO_ARMS } },
		{ after = 2, who = "thrall", type = "quest_accepted", data = { quest = CALL_TO_ARMS } },
		GnollKills("jaina", 1, 2, 3),
		GnollKills("uther", 1, 1, 3),
		GnollKills("thrall", 1, 2, 3),
		GnollKills("jaina", 3, 5, 3),
		GnollKills("uther", 2, 4, 2),

		-- Thrall also has a gathering quest of his own.
		{ after = 2, who = "thrall", type = "quest_accepted", data = { quest = "Plainstrider Menace" } },
		{
			after = 2, who = "thrall", type = "quest_progress",
			data = { quest = "Plainstrider Menace", objective = "Plainstrider Beak", need = 7 },
			kill = { mob = "Greater Plainstrider", xp = 48 },
			count = { field = "have", from = 1, to = 3, every = 4 },
		},
		-- Quest kills with no credit: the beak did not drop.
		{ after = 3, who = "thrall", type = "kill", data = { mob = "Greater Plainstrider", xp = 48, quest = "Plainstrider Menace" } },
		{ after = 3, who = "thrall", type = "kill", data = { mob = "Greater Plainstrider", xp = 48, quest = "Plainstrider Menace" } },

		{ after = 2, who = "uther", type = "skill", data = { skill = "Blacksmithing", level = 150 } },
		GnollKills("jaina", 6, 8, 3),
		GnollKills("thrall", 3, 5, 3),
		GnollKills("uther", 5, 7, 2),
		-- Not a quest kill, so it never shows up.
		{ after = 2, who = "jaina", type = "kill", data = { mob = "Redridge Mongrel", xp = 58 } },
		GnollKills("jaina", 9, 10, 3),

		-- Jaina finishes first and turns in. The others are still on it.
		{ after = 4, who = "jaina", type = "quest_complete", data = { quest = CALL_TO_ARMS, xp = 3000 } },
		{ after = 1, who = "jaina", type = "level", data = { level = 24 } },
		GnollKills("uther", 8, 10, 2),
		{ after = 3, who = "uther", type = "quest_complete", data = { quest = CALL_TO_ARMS, xp = 3000 } },
		{ after = 1, who = "uther", type = "level", data = { level = 25 } },

		-- Uther moves on to a quest with two objectives.
		{ after = 2, who = "uther", type = "quest_accepted", data = { quest = "The Night Watch" } },
		{
			after = 2, who = "uther", type = "quest_progress",
			data = { quest = "The Night Watch", objective = "Skeletal Fiend", need = 8 },
			kill = { mob = "Skeletal Fiend", xp = 72 },
			count = { field = "have", from = 1, to = 4, every = 2 },
		},
		{
			after = 2, who = "uther", type = "quest_progress",
			data = { quest = "The Night Watch", objective = "Skeletal Horror", need = 3 },
			kill = { mob = "Skeletal Horror", xp = 80 },
			count = { field = "have", from = 1, to = 2, every = 3 },
		},

		{
			after = 3, who = "thrall", type = "quest_progress",
			data = { quest = "Plainstrider Menace", objective = "Plainstrider Beak", need = 7 },
			kill = { mob = "Greater Plainstrider", xp = 48 },
			count = { field = "have", from = 4, to = 7, every = 4 },
		},
		{ after = 3, who = "thrall", type = "quest_complete", data = { quest = "Plainstrider Menace", xp = 1250 } },
		{ after = 2, who = "thrall", type = "discovery", data = { zone = "Lakeshire" } },
		{ after = 3, who = "uther", type = "achievement", data = { name = "Explore Redridge", points = 10 } },

		{
			after = 3, who = "uther", type = "quest_progress",
			data = { quest = "The Night Watch", objective = "Skeletal Fiend", need = 8 },
			kill = { mob = "Skeletal Fiend", xp = 72 },
			count = { field = "have", from = 5, to = 8, every = 2 },
		},
		{
			after = 2, who = "uther", type = "quest_progress",
			data = { quest = "The Night Watch", objective = "Skeletal Horror", need = 3 },
			kill = { mob = "Skeletal Horror", xp = 80 },
			count = { field = "have", from = 3, to = 3, every = 3 },
		},
		{ after = 3, who = "uther", type = "quest_complete", data = { quest = "The Night Watch", xp = 2450 } },

		-- Thrall is the last one left on the party quest. He stops at 5/10, so his card
		-- goes stale: a member who wandered off.
		{ after = 4, who = "jaina", type = "quest_accepted", data = { quest = "The Defias Brotherhood" } },
		{ after = 6, who = "jaina", type = "quest_complete", data = { quest = "The Defias Brotherhood", xp = 2450 } },
	},
}
