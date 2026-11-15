-- Feed entry types, as data. This is the successor to Quest Tweet's category toggles.
--
-- An entry on the wire looks like:
--   { type = "level", player = "Jaina", class = "MAGE", time = 1700000000, data = { level = 24 } }
--
-- Fields per type:
--   setting   the feature switch that turns this type on or off (see data\settings.lua)
--   requires  data keys an entry must carry, or it is ignored
--   filters   which filter tabs show this type's feed rows (see data\filters.lua)
--   icon      row icon
--   text      main feed row line, a template filled from entry.data
--   detail    optional second-line detail, a template filled from entry.data
--   chat      optional chat echo line, also gets {player}
--   celebrate set off confetti over the panel when the row arrives (ui\confetti.lua)
--   badge     draw a badge in place of the icon: { style, field }, where style
--             is a key of the panel's badge styles and field the data to show
--             on it (ui\panel.lua)
--   merge     fold a run of the same thing into one row: a new entry for the
--             same player and the same keys, within seconds of the last,
--             updates that row and moves it to the newest end. first keeps the
--             first value of field, so the row can say how far it went:
--             { keys, seconds, field, first, text, detail, detailOne, sum, count }
--             text, detail  the row's title and detail once it has climbed,
--             which may use {first} and {gained}. detailOne is for a gain of 1
--             sum     data fields added up across the run (XP gained)
--             count   a data field that counts the entries in the run
--   highlight draw the row with a celebration background: "level" or "quest"
--             (see ui\panel.lua for their colors)
--   member    maps roster fields to entry.data keys, so the entry updates the roster
--   feedOnlyIf  { field, setting }: an entry with that data field filled only
--             becomes a feed row while that switch is on. It still updates the
--             roster (member) either way
--   toldBy    a data field: an entry with it filled is already told by another
--             row (XP from a quest is on the quest's own row), so it is not a
--             feed row of its own. It still updates the roster
--   format    data keys to pass through ns.Comma before filling templates
--   card      makes the type feed a persistent card (see ns.CardKinds below):
--     kind    which kind of card
--     keys    data keys that, with the player, identify the card
--     mode    "open": make sure the card exists.
--             "objective": set one objective's have/need on the card. The entry also
--             becomes a feed row the first time have reaches need.
--             "tally": count the entry on the card and add up the sum fields. No feed row.
--             "close": remove the card.
--     count   tally only, the card field that counts entries
--     sum     tally only, data keys to add up on the card
local _, ns = ...
local L = ns.L

ns.FeedTypes = {
	quest_accepted = {
		setting = "quests",
		filters = { quests = true },
		icon = "Interface\\Icons\\INV_Misc_Note_02",
		text = L.FEED_QUEST_ACCEPTED,
		chat = L.CHAT_QUEST_ACCEPTED,
		card = { kind = "quest", keys = { "quest" }, mode = "open" },
	},
	quest_progress = {
		setting = "questDetails",
		filters = { quests = true },
		-- A finished objective. A check mark, so it is not mistaken for the quest
		-- being handed in.
		icon = "Interface\\RaidFrame\\ReadyCheck-Ready",
		text = L.FEED_QUEST_OBJECTIVE,
		chat = L.CHAT_QUEST_OBJECTIVE,
		card = { kind = "quest", keys = { "quest" }, mode = "objective" },
	},
	quest_complete = {
		setting = "quests",
		filters = { quests = true, xp = true },
		icon = "Interface\\Icons\\Achievement_Quests_Completed_06",
		text = L.FEED_QUEST_COMPLETE,
		detail = L.FEED_QUEST_COMPLETE_DETAIL,
		chat = L.CHAT_QUEST_COMPLETE,
		highlight = "quest",
		format = { xp = true },
		card = { kind = "quest", keys = { "quest" }, mode = "close" },
	},
	quest_abandoned = {
		setting = "quests",
		filters = { quests = true },
		icon = "Interface\\Icons\\INV_Misc_Note_02",
		text = L.FEED_QUEST_ABANDONED,
		card = { kind = "quest", keys = { "quest" }, mode = "close" },
	},
	kill = {
		setting = "kills",
		-- Only kills made for a quest. Quest Tweet's equivalent was its quest details line.
		requires = { "quest" },
		filters = {},
		icon = "Interface\\Icons\\INV_Misc_Bone_Skull_02",
		format = { xp = true },
		card = {
			kind = "quest",
			keys = { "quest" },
			mode = "tally",
			count = "kills",
			sum = { xp = true },
		},
	},
	level = {
		setting = "levels",
		filters = { xp = true },
		icon = "Interface\\Icons\\XP_Icon",
		text = L.FEED_LEVEL,
		chat = L.CHAT_LEVEL,
		highlight = "level",
		celebrate = true,
		badge = { style = "level", field = "level" }, -- the new level, on a gold ring
		member = { level = "level" },
	},
	-- An XP gain. A feed row, and it also moves the player's XP bar (member).
	-- mob names the kill the XP came from, "" when it was not a kill or the
	-- game did not name one.
	xp = {
		setting = "levels",
		requires = { "level", "currentXP", "maxXP" },
		filters = { xp = true },
		icon = "Interface\\Icons\\XP_Icon",
		text = L.FEED_XP,
		detail = L.FEED_XP_DETAIL,
		chat = L.CHAT_XP,
		experience = true,
		member = { level = "level", currentXP = "currentXP", maxXP = "maxXP", lastXP = "xp", lastMob = "mob" },
		-- XP from a kill is a row only with Kills on, as Quest Tweet kept kill XP
		-- behind its own switch. The XP bar moves either way.
		feedOnlyIf = { field = "mob", setting = "kills" },
		-- XP from handing in a quest is on the quest's own row.
		toldBy = "quest",
		-- A run of gains is one row that adds up: kills of the same creature
		-- ("Kills Wandering Spirit x3 for 243 XP"), or other XP ("+237 XP in 3
		-- gains"). A new run starts after five minutes without one.
		merge = { keys = { "mob" }, seconds = 5 * 60, sum = { "xp" }, count = "gains" },
	},
	discovery = {
		setting = "discovery",
		filters = { xp = true },
		icon = "Interface\\Icons\\inv_misc_map02",
		text = L.FEED_DISCOVERY,
		chat = L.CHAT_DISCOVERY,
		member = { zone = "zone" },
	},
	skill = {
		setting = "professions",
		filters = { professions = true },
		icon = "Interface\\Icons\\INV_SideTab_Professions_c60",
		text = L.FEED_SKILL,
		chat = L.CHAT_SKILL,
		-- Skill-ups come one point at a time (Cooking 19, 20, 21...). A run of
		-- them is one row that climbs, not a row per point: "Mining 10 > 19".
		merge = {
			keys = { "skill" }, seconds = 10 * 60, field = "level", first = "from",
			text = L.FEED_SKILL_RUN, detail = L.FEED_SKILL_RUN_DETAIL, detailOne = L.FEED_SKILL_RUN_DETAIL_ONE,
		},
	},
	death = {
		setting = "deaths",
		filters = {},
		icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
		text = L.FEED_DEATH,
		detail = L.FEED_DEATH_DETAIL,
		chat = L.CHAT_DEATH,
		member = { level = "level", zone = "zone" },
	},
	-- The generic card: an update of a type this version does not know (or
	-- cannot read), from a newer Quest Party. It shows what the sender said it
	-- was. See resolver.lua.
	unknown = {
		setting = "otherUpdates",
		requires = { "summary" },
		filters = {},
		icon = "Interface\\Icons\\INV_Misc_QuestionMark",
		text = L.FEED_UNKNOWN,
	},
	achievement = {
		setting = "achievements",
		filters = { achievements = true },
		icon = "Interface\\Icons\\achievement_reputation_01",
		text = L.FEED_ACHIEVEMENT,
		detail = L.FEED_ACHIEVEMENT_DETAIL,
		chat = L.CHAT_ACHIEVEMENT,
	},
}

-- Persistent cards. A card belongs to one player and is fed by the types above.
--   setting  the feature switch that shows or hides this kind of card
--   icon     card icon
ns.CardKinds = {
	quest = {
		setting = "quests",
		icon = "Interface\\GossipFrame\\AvailableQuestIcon",
	},
}

-- Which quests are worth showing and telling others about: the ones being
-- worked on. A quest is underway when at least one of its objectives has some
-- progress and not all of them are complete. One nobody has started, or one
-- that only needs handing in, is left out. With eight players on a channel,
-- every quest in every log would be far too much to say and to read.
-- objectives is a list or a map of { have, need }.
function ns.QuestUnderway(objectives)
	local started, unfinished = false, false
	for _, objective in pairs(objectives or {}) do
		if (objective.have or 0) > 0 then
			started = true
		end
		if (objective.have or 0) < (objective.need or 0) then
			unfinished = true
		end
	end
	return started and unfinished
end

-- Icons for rows that are not tied to a feed type or card kind.
ns.CardIcons = {
	member = "Interface\\Icons\\achievement_guildperk_everybodysfriend",
}
