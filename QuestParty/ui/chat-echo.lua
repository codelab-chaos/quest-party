-- ChatEcho: prints local "[Quest Party] ..." lines.
-- These lines are only shown to this player, nothing is sent to chat.
--   chatEcho     a line for each new feed row
--   chatDetails  also a line for each card update (every kill and every quest credit)
local _, ns = ...
local Fields = ns.ViewModel.Fields

ns.Bus:On("FEED_ADDED", function(entry, def)
	if def.chat and ns.IsEnabled("chatEcho") then
		ns.Print(ns.Fill(def.chat, Fields(entry.player, entry.class, entry.data, def)))
	end
end)

ns.Bus:On("CARD_UPDATED", function(record, def, entry)
	if def.card.chat and ns.IsEnabled("chatEcho") and ns.IsEnabled("chatDetails") then
		ns.Print(ns.Fill(def.card.chat, Fields(entry.player, entry.class, entry.data, def)))
	end
end)
