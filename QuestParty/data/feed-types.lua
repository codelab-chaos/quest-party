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
--   highlight draw the row with the celebration background
--   member    maps roster fields to entry.data keys, so the entry updates the roster
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
		icon = "Interface\\GossipFrame\\ActiveQuestIcon",
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
		highlight = true,
		member = { level = "level" },
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

-- Icons for rows that are not tied to a feed type or card kind.
ns.CardIcons = {
	member = "Interface\\Icons\\achievement_guildperk_everybodysfriend",
}
