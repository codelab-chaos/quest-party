local Harness = dofile("tests/harness.lua")
local passed, failed = 0, 0
local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, body)
	local ok, errorMessage = xpcall(body, debug.traceback)
	if ok then
		passed = passed + 1
		print("PASS " .. name)
	else
		failed = failed + 1
		print("FAIL " .. name .. "\n" .. errorMessage)
	end
end
local function progress(world, have, player)
	world:ingest("quest_progress", { quest = "A Quest", objective = "Kobolds", have = have, need = 3 }, player)
end


test("startup fills defaults and preserves saved choices", function()
	local w = Harness.new({ switches = { chatEcho = false } }, { filter = "xp", shown = false })
	equal(w.ns.IsEnabled("quests"), true)
	equal(w.ns.IsEnabled("chatEcho"), false)
	equal(w.ns.charDb.filter, "xp")
	equal(w.ns.charDb.shown, false)
	equal(w.prefix, "QuestParty")
end)

test("protocol round-trips numbers, delimiters, unicode and numeric-looking strings", function()
	local p = Harness.new().ns.Protocol
	local text = p.Encode("E", { quest = "Élan;=#:%", have = 2, literal = "#12", empty = "" })
	local kind, fields = p.Decode(text)
	equal(kind, "E")
	equal(fields.quest, "Élan;=#:%")
	equal(fields.have, 2)
	equal(fields.literal, "#12")
	equal(fields.empty, "")
end)

test("protocol enforces the wire size limit", function()
	local p = Harness.new().ns.Protocol
	equal(#p.Encode("E", { x = string.rep("a", 249) }), 255)
	equal(p.Encode("E", { x = string.rep("a", 250) }), nil)
end)

test("protocol ignores unrelated text and incompatible versions", function()
	local p = Harness.new().ns.Protocol
	equal(p.Decode("hello"), nil)
	equal(p.Decode("2:E:t=level"), nil)
end)

test("quest lifecycle updates one card and announces completion only once", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { quest = "A Quest" })
	progress(w, 1)
	progress(w, 2)
	equal(#w.ns.Store:GetCards("quest"), 1)
	equal(#w.ns.Store:GetFeed(true), 1)
	progress(w, 3)
	progress(w, 3)
	equal(#w.ns.Store:GetFeed(true), 2)
	w:ingest("quest_complete", { quest = "A Quest", xp = 150 })
	equal(#w.ns.Store:GetCards("quest"), 0)
	equal(#w.ns.Store:GetFeed(true), 3)
end)

test("party quest tracker combines progress without merging players' cards", function()
	local w = Harness.new()
	progress(w, 1, "Alice")
	progress(w, 2, "Bob")
	equal(#w.ns.Store:GetCards("quest"), 2)
	local rows = w.ns.ViewModel:Build("quests")
	equal(#rows, 1)
	equal(rows[1].progress.have, 3)
	equal(rows[1].progress.need, 6)
	w:ingest("quest_abandoned", { quest = "A Quest" }, "Alice")
	equal(#w.ns.Store:GetCards("quest"), 1)
end)

test("kill tallies remain on the quest card and clear on turn-in", function()
	local w = Harness.new()
	w.ns.SetEnabled("kills", true)
	w:ingest("kill", { quest = "A Quest", mob = "Kobold", xp = 26 })
	w:ingest("kill", { quest = "A Quest", mob = "Kobold", xp = 30 })
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.kills, 2)
	equal(card.data.xp, 56)
	equal(#w.ns.Store:GetFeed(true), 0)
	w:ingest("quest_complete", { quest = "A Quest", xp = 100 })
	equal(#w.ns.Store:GetCards("quest"), 0)
end)

test("feature switches hide saved rows without deleting them", function()
	local w = Harness.new()
	w:ingest("level", { level = 20 })
	w.ns.SetEnabled("levels", false)
	equal(#w.ns.Store:GetFeed(true), 0)
	w:ingest("level", { level = 21 })
	w.ns.SetEnabled("levels", true)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(w.ns.Store:GetFeed(true)[1].data.level, 20)
end)

test("store ignores unknown events and kills without an associated quest", function()
	local w = Harness.new()
	w.ns.SetEnabled("kills", true)
	w:ingest("unknown", {})
	w:ingest("kill", { mob = "Rabbit", xp = 1 })
	equal(#w.ns.Store:GetCards("quest"), 0)
	equal(#w.ns.Store:GetMembers(), 0)
end)

test("feed keeps the latest 200 events", function()
	local w = Harness.new()
	for level = 1, 205 do w:ingest("level", { level = level }) end
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 200)
	equal(feed[1].data.level, 205)
	equal(feed[200].data.level, 6)
end)

test("requesting Clear preserves saved state until accepted, including in debug mode", function()
	for _, debugBuild in ipairs({ false, true }) do
		local w = Harness.new({ switches = { chatEcho = false }, connection = { name = "Friends", enabled = true } }, nil, debugBuild)
		w:ingest("quest_accepted", { quest = "A Quest" })
		progress(w, 2)
		w.ns.ConfirmClear()
		equal(#w.ns.Store:GetFeed(true), 1)
		equal(#w.ns.Store:GetCards("quest"), 1)
		equal(#w.ns.Store:GetMembers(), 1)
		local dialog = w.env.StaticPopupDialogs[w.popup.which]
		equal(dialog.button2, "Cancel")
		equal(dialog.hideOnEscape, true)
		w:dismissPopup(false)
		equal(#w.ns.Store:GetFeed(true), 1)
		equal(w.ns.Store:GetCards("quest")[1].data.objectives.Kobolds.have, 2)
		equal(#w.ns.Store:GetMembers(), 1)
		equal(#w.chat, 0)
	end
end)

test("slash Clear uses confirmation and accepting clears state while retaining settings and channel", function()
	local w = Harness.new({ switches = { chatEcho = false }, connection = { name = "Friends", enabled = true } })
	w:ingest("quest_accepted", { quest = "A Quest" })
	progress(w, 2)
	w.env.SlashCmdList.QUESTPARTY("clear")
	equal(#w.ns.Store:GetCards("quest"), 1)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(#w.chat, 0)
	w:dismissPopup(true)
	equal(#w.ns.Store:GetFeed(true), 0)
	equal(#w.ns.Store:GetCards("quest"), 0)
	equal(#w.ns.Store:GetMembers(), 0)
	equal(w.ns.IsEnabled("chatEcho"), false)
	equal(w.ns.db.connection.name, "Friends")
	equal(w.ns.db.connection.enabled, true)
	equal(#w.chat, 1)
	assert(w.chat[1]:find(w.ns.L.CMD_CLEARED, 1, true))
end)

test("cached cards survive a week offline and reload without a channel", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { questID = 47, quest = "Buddy's Quest" }, "Buddy")
	w:ingest("quest_progress", { questID = 47, quest = "Buddy's Quest", objective = "Ribs", have = 2, need = 5 }, "Buddy")
	local updated = w.ns.Store:GetCards("quest")[1].time
	w:advance(7 * 24 * 60 * 60)
	equal(#w.ns.Store:GetCards("quest"), 1)
	local reloaded = Harness.new(w.ns.db, w.ns.charDb, false, w.now)
	reloaded.ns.Bus:Fire("READY")
	local card = reloaded.ns.Store:GetCards("quest")[1]
	equal(card.player, "Buddy")
	equal(card.time, updated)
	equal(card.data.objectives.Ribs.have, 2)
	equal(reloaded.ns.ViewModel:Build("quests")[1].stale, true)
	equal(#reloaded.ns.Store:GetFeed(true), 1)
	equal(#reloaded.sent, 0)
	reloaded.ns.Store:Clear()
	equal(#reloaded.ns.Store:GetCards("quest"), 0)
end)

test("saved cards and ordering survive a fresh addon startup", function()
	local w = Harness.new()
	progress(w, 1)
	w:ingest("level", { level = 20 })
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	equal(#reloaded.ns.Store:GetCards("quest"), 1)
	local rows = reloaded.ns.ViewModel:Build("all")
	equal(rows[1].kind, "progress")
	equal(rows[2].kind, "feed")
end)

test("startup discards cards from an obsolete save format", function()
	local w = Harness.new({ cards = { old = { kind = "quest", data = {} } } })
	equal(#w.ns.Store:GetCards("quest"), 0)
end)

test("same-second progress moves below older feed events and reverses correctly", function()
	local w = Harness.new()
	progress(w, 1)
	w:ingest("level", { level = 20 })
	progress(w, 2)
	local rows = w.ns.ViewModel:Build("all")
	equal(rows[1].kind, "feed")
	equal(rows[2].progress.have, 2)
	w.ns.SetEnabled("chatOrder", false)
	equal(w.ns.ViewModel:Build("all")[1].progress.have, 2)
end)

test("category filters select their own events", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { quest = "A Quest" })
	w:ingest("level", { level = 20 })
	w:ingest("achievement", { name = "Explorer", points = 10 })
	w:ingest("skill", { skill = "Herbalism", level = 62 })
	equal(#w.ns.ViewModel:Build("xp"), 1)
	equal(#w.ns.ViewModel:Build("achievements"), 1)
	equal(#w.ns.ViewModel:Build("professions"), 1)
	equal(w.ns.ViewModel:Build("party")[1].kind, "member")
	equal(w.ns.ViewModel:Build("quests")[1].title, "A Quest")
	equal(#w.ns.ViewModel:Build("missing"), #w.ns.ViewModel:Build("all"))
end)

for _, killFirst in ipairs({ true, false }) do
	test("collectors pair kill and credit, kill first = " .. tostring(killFirst), function()
		local w = Harness.new()
		w:quest(1, 3)
		w.ns.SetEnabled("kills", true)
		local function kill() w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 26 experience. (+13 exp Rested bonus)") end
		local function credit() w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 1/3") end
		if killFirst then kill() else credit() end
		w:advance(0.4)
		if killFirst then credit() else kill() end
		local card = w.ns.Store:GetCards("quest")[1]
		equal(card.data.quest, "A Quest")
		equal(card.data.kills, 1)
		equal(card.data.xp, 26)
	end)
end

test("collectors do not attach an old unrelated kill to a quest", function()
	local w = Harness.new()
	w:quest(1, 3)
	w.ns.SetEnabled("kills", true)
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Rabbit dies, you gain 1 experience.")
	w:advance(2)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", "Kobolds slain: 1/3")
	equal(w.ns.Store:GetCards("quest")[1].data.kills, 0)
end)

test("turn-in after quest removal is not announced as abandonment", function()
	local w = Harness.new()
	w:quest(1, 3)
	w.ns.Collectors:Handle("QUEST_ACCEPTED", 1)
	w.ns.Collectors:Handle("QUEST_REMOVED", 1)
	w.ns.Collectors:Handle("QUEST_TURNED_IN", 1, 100)
	w:advance(2)
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 2)
	equal(feed[1].type, "quest_complete")
end)

test("quest removal without turn-in becomes abandonment", function()
	local w = Harness.new()
	w:quest(1, 3)
	w.ns.Collectors:Handle("QUEST_ACCEPTED", 1)
	w.ns.Collectors:Handle("QUEST_REMOVED", 1)
	w:advance(2)
	equal(w.ns.Store:GetFeed(true)[1].type, "quest_abandoned")
	equal(#w.ns.Store:GetCards("quest"), 0)
end)

test("Include self controls local collection while outgoing events remain available", function()
	local w = Harness.new()
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function() outgoing = outgoing + 1 end)
	w.ns.SetEnabled("showSelf", false)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.ns.Store:GetFeed(true), 0)
	equal(outgoing, 1)
	w.ns.SetEnabled("showSelf", true)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 22)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(#w.sent, 0)
end)

test("disabled event categories are neither stored nor shared", function()
	local w = Harness.new()
	w.ns.SetEnabled("levels", false)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.sent, 0)
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("XP gains show current level and percentage remaining without duplicate updates", function()
	local w = Harness.new()
	w.xp = 400
	w:event("PLAYER_LOGIN")
	equal(#w.ns.Store:GetFeed(true), 0)
	w.xp = 550
	w:event("PLAYER_XP_UPDATE", "pet")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 0)
	w:event("PLAYER_XP_UPDATE", "player")
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].type, "xp")
	equal(feed[1].data.xp, 150)
	equal(feed[1].data.level, 20)
	local row = w.ns.ViewModel:Build("xp")[1]
	equal(row.title, "+150 XP")
	equal(row.summary, "Tester, Level 20, 45.00% to Level 21")
	equal(row.progress.have, 550)
	equal(row.progress.need, 1000)
	equal(#w.chat, 1)
	assert(w.chat[1]:find("Level 20, 45.00%% to Level 21"))
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(#w.sent, 0)
end)

test("XP rollover reads settled level data and includes XP earned before leveling", function()
	local w = Harness.new()
	w.xp = 900
	w:event("PLAYER_LOGIN")
	w:event("PLAYER_LEVEL_UP", 21)
	w:event("PLAYER_XP_UPDATE", "player")
	w.level, w.xp, w.xpMax = 21, 150, 1400
	w:advance(0)
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 2)
	equal(feed[1].type, "xp")
	equal(feed[1].data.xp, 250)
	equal(feed[1].data.level, 21)
	local rows = w.ns.ViewModel:Build("xp")
	equal(rows[2].summary, "Tester, Level 21, 89.29% to Level 22")
end)

test("saved XP history survives reload without announcing old gains again", function()
	local w = Harness.new()
	w:event("PLAYER_LOGIN")
	w.xp = 100
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded.xp = 100
	reloaded:event("PLAYER_LOGIN")
	reloaded:event("PLAYER_XP_UPDATE", "player")
	reloaded:advance(0)
	equal(#reloaded.ns.Store:GetFeed(true), 1)
	equal(reloaded.ns.ViewModel:Build("xp")[1].title, "+100 XP")
	equal(#reloaded.chat, 0)
	reloaded.xp = 125
	reloaded:event("PLAYER_XP_UPDATE", "player")
	reloaded:advance(0)
	equal(#reloaded.ns.Store:GetFeed(true), 2)
	equal(reloaded.ns.Store:GetFeed(true)[1].data.xp, 25)
end)

test("XP collection respects Leveling and Include self without carrying disabled gains forward", function()
	local w = Harness.new()
	w:event("PLAYER_LOGIN")
	w.ns.SetEnabled("levels", false)
	w.xp = 100
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 0)
	w.ns.SetEnabled("levels", true)
	w.xp = 150
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(w.ns.Store:GetFeed(true)[1].data.xp, 50)
	w.ns.SetEnabled("showSelf", false)
	w.xp = 200
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(#w.sent, 0)
end)

test("unreadable or reduced XP cannot create a fake gain", function()
	local w = Harness.new()
	w.xp = 100
	w:event("PLAYER_LOGIN")
	for _, value in ipairs({ "<secret>", 2000, -1, 50 }) do
		w.xp = value
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(0)
	end
	equal(#w.ns.Store:GetFeed(true), 0)
	w.xp = 75
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(w.ns.Store:GetFeed(true)[1].data.xp, 25)
end)

test("multi-level XP updates avoid invented gain totals and capped levels avoid division by zero", function()
	for _, capped in ipairs({ false, true }) do
		local w = Harness.new()
		w:event("PLAYER_LOGIN")
		w.level, w.xp, w.xpMax = 22, capped and 0 or 250, capped and 0 or 2000
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(0)
		local row = w.ns.ViewModel:Build("xp")[1]
		equal(row.title, "XP progress updated")
		if capped then
			equal(row.summary, "Tester, Level 22")
			equal(row.progress, nil)
		else
			equal(row.summary, "Tester, Level 22, 87.50% to Level 23")
		end
	end
end)

test("collectors ignore secret and non-text messages", function()
	local w = Harness.new()
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 1, "<secret>")
	w.ns.Collectors:Handle("CHAT_MSG_SKILL", {})
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", nil)
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("own objective lookup retains quest ID when the quest log count lags", function()
	local w = Harness.new()
	w:quest(2, 5)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 3/5")
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.questID, 1)
	equal(card.data.quest, "A Quest")
	equal(card.data.objectives["Kobolds slain"].have, 3)
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	equal(card.data.objectives["Kobolds slain"].have, 3)
end)

test("ID-bearing quest events work without a prior QP card or visible log row", function()
	local w = Harness.new()
	w.questData[47] = { title = "Rib Harvest", objectives = {
		{ text = "Notched Rib: 3/5", numFulfilled = 3, numRequired = 5 },
	} }
	local outgoing
	w.ns.Bus:On("ENTRY_OUTGOING", function(entry) outgoing = entry end)
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 47)
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.questID, 47)
	equal(card.data.quest, "Rib Harvest")
	equal(card.data.objectives["Notched Rib"].have, 3)
	equal(outgoing.data.questID, 47)
	equal(outgoing.data.quest, "Rib Harvest")
	equal(#w.sent, 0) -- preparing an outgoing entry does not imply channel transport
end)

test("ambiguous objective messages wait for the owning quest's ID", function()
	local w = Harness.new()
	w:quest(1, 3)
	w.quests[2] = { questID = 2, title = "Another Quest", objectives = {
		{ text = "Kobolds slain: 1/3", numFulfilled = 1, numRequired = 3 },
	} }
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 2/3")
	equal(#w.ns.Store:GetCards("quest"), 0)
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 2)
	local cards = w.ns.Store:GetCards("quest")
	equal(#cards, 1)
	equal(cards[1].data.questID, 2)
	equal(cards[1].data.objectives["Kobolds slain"].have, 2)
end)

test("objective and title data arriving later resolve without an Unknown quest card", function()
	local w = Harness.new()
	w.quests[1] = { questID = 1 }
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Notched Rib: 3/5")
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	equal(#w.ns.Store:GetCards("quest"), 0)
	w.quests[1].title = "Rib Harvest"
	w.quests[1].objectives = { { text = "Notched Rib: 2/5", numFulfilled = 2, numRequired = 5 } }
	w:advance(0.1)
	equal(w.ns.Store:GetCards("quest")[1].data.quest, "Rib Harvest")
	equal(w.ns.Store:GetCards("quest")[1].data.questID, 1)
end)

test("matching counts do not disambiguate shared objectives when another quest's counts may lag", function()
	local w = Harness.new()
	w:quest(2, 3)
	w.quests[2] = { questID = 2, title = "Another Quest", objectives = {
		{ text = "Kobolds slain: 1/3", numFulfilled = 1, numRequired = 3 },
	} }
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 2/3")
	equal(#w.ns.Store:GetCards("quest"), 0)
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 2)
	equal(w.ns.Store:GetCards("quest")[1].data.questID, 2)
end)

test("queued progress resolves in order after quest data loads", function()
	local w = Harness.new()
	for have = 1, 3 do w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: " .. have .. "/5") end
	w:quest(3, 5)
	w:advance(0.1)
	equal(w.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 3)
end)

test("a deferred log read can report a genuine objective count decrease", function()
	local w = Harness.new()
	w:quest(3, 5)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 3/5")
	w:quest(2, 5)
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	equal(w.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 3)
	w:advance(1.1)
	equal(w.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 2)
end)

test("cached objective data for removed quests is excluded from active snapshots", function()
	local w = Harness.new()
	w.questData[47] = { title = "Rib Harvest", objectives = {
		{ text = "Notched Rib: 3/5", numFulfilled = 3, numRequired = 5 },
	} }
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 47)
	w.questData[47].removed = true
	equal(#w.ns.Collectors:GetQuestSnapshot(), 0)
end)

test("native and text progress events are deduplicated", function()
	local w = Harness.new()
	w:quest(1, 3)
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function(entry)
		if entry.type == "quest_progress" then outgoing = outgoing + 1 end
	end)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 1/3")
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	w.ns.Collectors:Handle("QUEST_LOG_UPDATE")
	equal(outgoing, 1)
	equal(#w.ns.Store:GetCards("quest"), 1)
end)

test("mid-quest snapshots supply ID, title and all current objective counts", function()
	local w = Harness.new()
	w:quest(3, 5)
	w.quests[1].objectives[2] = { text = "|cffffffff|Hitem:123|h[Notched Rib]|h|r: 2/4", numFulfilled = 2, numRequired = 4 }
	local snapshot = w.ns.Collectors:GetQuestSnapshot()
	equal(#snapshot, 1)
	equal(snapshot[1].questID, 1)
	equal(snapshot[1].quest, "A Quest")
	equal(snapshot[1].objectives[1].have, 3)
	equal(snapshot[1].objectives[2].objective, "Notched Rib")
	equal(snapshot[1].objectives[2].have, 2)
	equal(#w.ns.Store:GetCards("quest"), 0)
	equal(#w.sent, 0)
end)

test("startup hydrates active quests quietly and observes their next real progress", function()
	local w = Harness.new()
	w:quest(2, 3)
	w.quests[1].objectives[2] = { text = "Ribs: 5/5", numFulfilled = 5, numRequired = 5 }
	w.quests[2] = { questID = 2, title = "Delivery", objectives = {} }
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function() outgoing = outgoing + 1 end)
	w:event("PLAYER_LOGIN")
	equal(#w.ns.Store:GetCards("quest"), 2)
	local quest
	for _, card in ipairs(w.ns.Store:GetCards("quest")) do
		if card.data.questID == 1 then quest = card end
	end
	equal(quest.data.objectives["Kobolds slain"].have, 2)
	equal(quest.data.objectives.Ribs.have, 5)
	w:event("QUEST_LOG_UPDATE")
	w:event("QUEST_WATCH_UPDATE", 1)
	equal(outgoing, 0)
	equal(#w.ns.Store:GetFeed(true), 0)
	equal(#w.chat, 0)
	w:quest(3, 3)
	w:event("QUEST_LOG_UPDATE")
	w:event("UI_INFO_MESSAGE", 286, "Kobolds slain: 3/3")
	equal(quest.data.objectives["Kobolds slain"].have, 3)
	equal(outgoing, 1)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(#w.chat, 1)
	equal(#w.sent, 0)
end)

test("hydration refreshes saved counts and preserves start time and kill tallies", function()
	local w = Harness.new()
	w.ns.SetEnabled("kills", true)
	w:ingest("quest_accepted", { questID = 1, quest = "A Quest" })
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Kobolds slain", objectiveIndex = 1, have = 3, need = 5 })
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Old duplicate line", have = 2, need = 5 })
	w:ingest("kill", { questID = 1, quest = "A Quest", xp = 26 })
	local created = w.ns.Store:GetCards("quest")[1].created
	local reloaded = Harness.new(w.ns.db, w.ns.charDb, false, w.now + 24 * 60 * 60)
	reloaded:quest(1, 5)
	reloaded:event("PLAYER_LOGIN")
	local card = reloaded.ns.Store:GetCards("quest")[1]
	equal(card.created, created)
	equal(card.data.kills, 1)
	equal(card.data.xp, 26)
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Kobolds slain"].have, 1)
	equal(card.data.objectives["Old duplicate line"], nil)
	equal(#reloaded.ns.Store:GetFeed(true), 1)
	equal(#reloaded.chat, 0)
	reloaded:event("CHAT_MSG_COMBAT_XP_GAIN", "Rabbit dies, you gain 1 experience.")
	equal(card.data.kills, 1)
end)

test("cached objectives remain until delayed quest log data becomes available", function()
	local w = Harness.new()
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Kobolds slain", have = 2, need = 3 })
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded.quests[1] = { questID = 1, title = "A Quest" }
	reloaded:event("PLAYER_LOGIN")
	reloaded:event("QUEST_LOG_UPDATE")
	equal(reloaded.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 2)
	reloaded:quest(3, 3)
	reloaded:event("QUEST_LOG_UPDATE")
	equal(reloaded.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 3)
	equal(#reloaded.ns.Store:GetFeed(true), 0)
	equal(#reloaded.chat, 0)
end)

test("watched quests under collapsed headers hydrate without changing the log UI", function()
	local w = Harness.new()
	w.quests[1] = { isHeader = true, title = "Collapsed zone" }
	w.questWatches[1] = 47
	w.questData[47] = { title = "Rib Harvest", objectives = {
		{ text = "Notched Rib: 3/5", numFulfilled = 3, numRequired = 5 },
	} }
	w:event("PLAYER_LOGIN")
	equal(w.ns.Store:GetCards("quest")[1].data.questID, 47)
	equal(w.ns.Store:GetCards("quest")[1].data.objectives["Notched Rib"].have, 3)
	equal(#w.quests, 1)
end)

test("partial objective data cannot erase saved lines or replay old completions", function()
	local w = Harness.new()
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Ribs", objectiveIndex = 2, have = 2, need = 5 })
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded:quest(3, 3)
	reloaded.quests[1].objectives[2] = { text = "<secret>", numFulfilled = 2, numRequired = 5 }
	reloaded:event("PLAYER_LOGIN")
	equal(reloaded.ns.Store:GetCards("quest")[1].data.objectives.Ribs.have, 2)
	reloaded.quests[1].objectives[2].text = "Ribs: 2/5"
	reloaded:event("QUEST_LOG_UPDATE")
	local card = reloaded.ns.Store:GetCards("quest")[1]
	equal(card.data.objectives.Ribs.have, 2)
	equal(card.data.objectives["Kobolds slain"].have, 3)
	equal(#reloaded.ns.Store:GetFeed(true), 0)
	equal(#reloaded.chat, 0)
end)

test("hydration respects Include self and quest switches and refreshes when enabled", function()
	for _, setting in ipairs({ "showSelf", "quests", "questDetails" }) do
		local w = Harness.new({ switches = { [setting] = false } })
		w:quest(3, 3)
		w:event("PLAYER_LOGIN")
		local cards = w.ns.Store:GetCards("quest")
		if setting == "questDetails" then
			equal(#cards, 1)
			equal(cards[1].data.objectiveCount, 0)
		else
			equal(#cards, 0)
		end
		w.ns.SetEnabled(setting, true)
		equal(w.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 3)
		equal(#w.ns.Store:GetFeed(true), 0)
		equal(#w.chat, 0)
	end
end)

test("saved unidentified objectives are repaired only for the owning player", function()
	local w = Harness.new()
	for _, player in ipairs({ "Tester", "Buddy" }) do
		w:ingest("quest_progress", { quest = w.ns.L.UNKNOWN_QUEST, objective = "Kobolds slain", have = 3, need = 5 }, player)
	end
	w:quest(3, 5)
	w.ns.Bus:Fire("READY")
	local own, buddy
	for _, card in ipairs(w.ns.Store:GetCards("quest")) do
		if card.player == "Tester" then own = card else buddy = card end
	end
	equal(own.data.quest, "A Quest")
	equal(own.data.questID, 1)
	equal(own.data.objectives["Kobolds slain"].have, 3)
	equal(buddy.data.quest, w.ns.L.UNKNOWN_QUEST)
	equal(buddy.data.questID, nil)
end)

test("repairing a completed unidentified objective updates history without announcing twice", function()
	local w = Harness.new()
	w:ingest("quest_progress", { quest = w.ns.L.UNKNOWN_QUEST, objective = "Kobolds slain", have = 5, need = 5 })
	w:quest(5, 5)
	w.ns.Bus:Fire("READY")
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(w.ns.Store:GetFeed(true)[1].data.questID, 1)
	equal(w.ns.Store:GetFeed(true)[1].data.quest, "A Quest")
	equal(#w.chat, 1)
end)

test("title-only saved cards gain IDs without losing their start time or progress", function()
	local w = Harness.new()
	progress(w, 2)
	local created = w.ns.Store:GetCards("quest")[1].created
	w:advance(3)
	w:quest(2, 3)
	w.ns.Bus:Fire("READY")
	local cards = w.ns.Store:GetCards("quest")
	equal(#cards, 1)
	equal(cards[1].data.questID, 1)
	equal(cards[1].created, created)
	equal(cards[1].data.objectives["Kobolds slain"].have, 2)
	equal(cards[1].data.objectives.Kobolds, nil)
end)

test("quest IDs survive reload and keep one card when the title changes", function()
	local w = Harness.new()
	w:ingest("quest_progress", { questID = 47, quest = "Original Title", objective = "Ribs", have = 2, need = 5 })
	w = Harness.new(w.ns.db, w.ns.charDb)
	w:ingest("quest_progress", { questID = 47, quest = "Updated Title", objective = "Ribs", have = 3, need = 5 })
	equal(#w.ns.Store:GetCards("quest"), 1)
	equal(w.ns.Store:GetCards("quest")[1].data.quest, "Updated Title")
	w:ingest("quest_complete", { questID = 47, quest = "Completion Title", xp = 100 })
	equal(#w.ns.Store:GetCards("quest"), 0)
end)

test("quests sharing a title remain distinct when their IDs differ", function()
	local w = Harness.new()
	for _, id in ipairs({ 47, 48 }) do
		w:ingest("quest_progress", { questID = id, quest = "Same Title", objective = "Ribs", have = 2, need = 5 })
	end
	equal(#w.ns.Store:GetCards("quest"), 2)
	local rows = w.ns.ViewModel:Build("quests")
	equal(#rows, 2)
	assert(rows[1].questID ~= rows[2].questID)
end)

test("delayed objective resolution cannot claim a newer unrelated kill", function()
	local w = Harness.new()
	w.ns.SetEnabled("kills", true)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 1/3")
	w:advance(2)
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Rabbit dies, you gain 1 experience.")
	w:quest(1, 3)
	w.ns.Collectors:Handle("QUEST_LOG_UPDATE")
	equal(w.ns.Store:GetCards("quest")[1].data.kills, 0)
end)

test("counts before item names update one objective instead of adding a line", function()
	local w = Harness.new()
	w:quest(0, 5)
	w.quests[1].objectives[1].text = "0/5 Vile Fin Scale"
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	w.quests[1].objectives[1] = { text = "1/5 Vile Fin Scale", numFulfilled = 1, numRequired = 5 }
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Vile Fin Scale"].have, 1)
	equal(card.data.objectives["Vile Fin Scale"].index, 1)
	equal(card.data.objectives["0/5 Vile Fin Scale"], nil)
	local rows = w.ns.ViewModel:Build("quests")
	equal(#rows[1].lines, 2)
	equal(rows[1].lines[2].text, "Vile Fin Scale")
	equal(rows[1].progress.have, 1)
	equal(rows[1].progress.need, 5)
end)

test("item count decreases update the same line and remove completed styling", function()
	local w = Harness.new()
	w:quest(5, 5)
	w.quests[1].objectives[1].text = "5/5 Vile Fin Scale"
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	w.quests[1].objectives[1] = { text = "4/5 Vile Fin Scale", numFulfilled = 4, numRequired = 5 }
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	w:advance(1.1)
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Vile Fin Scale"].have, 4)
	local row = w.ns.ViewModel:Build("quests")[1]
	equal(row.lines[2].text, "Vile Fin Scale")
	equal(row.lines[2].right, "4/5")
end)

test("prefix progress messages and native quest updates use the same objective", function()
	local w = Harness.new()
	w:quest(0, 5)
	w.quests[1].objectives[1].text = "0/5 Vile Fin Scale"
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "1/5 Vile Fin Scale")
	w.quests[1].objectives[1] = { text = "1/5 Vile Fin Scale", numFulfilled = 1, numRequired = 5 }
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Vile Fin Scale"].have, 1)
end)

test("log changes refresh items first discovered through an info message", function()
	local w = Harness.new()
	w:quest(3, 5)
	w.quests[1].objectives[1].text = "3/5 Vile Fin Scale"
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "3/5 Vile Fin Scale")
	w:advance(2)
	w.quests[1].objectives[1] = { text = "2/5 Vile Fin Scale", numFulfilled = 2, numRequired = 5 }
	w.ns.Collectors:Handle("QUEST_LOG_UPDATE")
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Vile Fin Scale"].have, 2)
end)

test("objective index preserves identity when its displayed wording changes", function()
	local w = Harness.new()
	w:quest(1, 5)
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	w.quests[1].objectives[1].text = "1/5 Kobolds defeated"
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	local card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Kobolds slain"], nil)
	equal(card.data.objectives["Kobolds defeated"].have, 1)
end)

test("saved count-prefixed duplicates merge using latest state rather than highest count", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { quest = "A Quest" })
	local card = w.ns.Store:GetCards("quest")[1]
	card.data.objectives = {
		["3/5 Vile Fin Scale"] = { have = 3, need = 5, order = 1, time = w.now, sequence = 2 },
		["1/5 Vile Fin Scale"] = { have = 1, need = 5, order = 2, time = w.now, sequence = 3 },
	}
	card.data.objectiveCount = 2
	w = Harness.new(w.ns.db, w.ns.charDb)
	card = w.ns.Store:GetCards("quest")[1]
	equal(card.data.objectiveCount, 1)
	equal(card.data.objectives["Vile Fin Scale"].have, 1)
	equal(card.data.objectives["Vile Fin Scale"].order, 1)
	equal(#w.ns.ViewModel:Build("quests")[1].lines, 2)
end)

test("multiple item objectives maintain the correct aggregate progress", function()
	local w = Harness.new()
	w:quest(0, 3)
	w.quests[1].objectives = {
		{ text = "8/8 Duskbat Wing Membrane", numFulfilled = 8, numRequired = 8 },
		{ text = "6/6 Darkhound Hide", numFulfilled = 6, numRequired = 6 },
		{ text = "0/3 Vile Fin Murloc Skin", numFulfilled = 0, numRequired = 3 },
	}
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	w.quests[1].objectives[3] = { text = "1/3 Vile Fin Murloc Skin", numFulfilled = 1, numRequired = 3 }
	w.ns.Collectors:Handle("QUEST_WATCH_UPDATE", 1)
	local row = w.ns.ViewModel:Build("quests")[1]
	equal(#row.lines, 4)
	equal(row.progress.have, 15)
	equal(row.progress.need, 17)
end)

test("localized message patterns escape punctuation and reject reordered arguments", function()
	local ns = Harness.new().ns
	local pattern = ns.FromFormat("Found [%s]: %d.")
	local name, count = ("Found [Copper]: 12."):match(pattern)
	equal(name, "Copper")
	equal(count, "12")
	equal(ns.FromFormat("%2$s: %1$d"), nil)
end)

test("retired settings and friend links cannot reactivate through saved data", function()
	local w = Harness.new({ switches = { chatDetails = true, share = true, emulatorShare = true }, links = { Friend = true } })
	for _, id in ipairs({ "chatDetails", "share", "emulatorShare" }) do
		equal(w.ns.SettingById[id], nil)
		equal(w.ns.IsEnabled(id), false)
		equal(w.ns.SetEnabled(id, true), false)
	end
	equal(w.ns.db.links, nil)
	w.ns.Bus:Fire("READY")
	w:advance(3)
	equal(#w.sent, 0)
end)

test("chat output prints feed events but never intermediate detail updates", function()
	local w = Harness.new()
	progress(w, 1)
	progress(w, 2)
	equal(#w.chat, 0)
	progress(w, 3)
	equal(#w.chat, 1)
	w.ns.SetEnabled("chatEcho", false)
	w:ingest("level", { level = 21 })
	equal(#w.chat, 1)
	equal(#w.sent, 0)
end)

test("no automatic party discovery, friend linking or sharing before a channel exists", function()
	local w = Harness.new()
	w.party.Friend = true
	w.ns.Bus:Fire("READY")
	w:advance(3)
	w:receive("H", { v = "0.1.0", c = "MAGE", l = 20, z = "Elwynn" })
	w:receive("L", { v = "0.1.0", c = "MAGE", l = 20, z = "Elwynn" }, "WHISPER")
	w:receive("E", { t = "level", level = 99 }, "WHISPER")
	equal(w.ns.Session:Count(), 0)
	equal(w.popup, nil)
	equal(#w.ns.Store:GetFeed(true), 0)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.sent, 0)
	equal(#w.ns.Store:GetFeed(true), 1)
	w.env.SlashCmdList.QUESTPARTY("link Friend")
	equal(w.ns.Session.Link, nil)
	equal(w.popup, nil)
	equal(#w.sent, 0)
end)

test("emulator and collector samples are disabled outside debug mode", function()
	local w = Harness.new()
	equal(w.ns.IsDebug(), false)
	w.ns.Emulator:Start()
	w.ns.Emulator:Step()
	w.ns.Emulator:Burst(5)
	w.ns.Collectors:RunTest()
	w.env.SlashCmdList.QUESTPARTY("emu start")
	w.env.SlashCmdList.QUESTPARTY("test")
	equal(w.ns.Emulator.running, false)
	equal(#w.ns.Store:GetFeed(true), 0)
	equal(#w.sent, 0)
end)

test("debug command enables tools, persists, and stops the emulator when disabled", function()
	local w = Harness.new()
	w.env.SlashCmdList.QUESTPARTY("debug on")
	equal(w.ns.IsDebug(), true)
	w.ns.Emulator:Start()
	equal(w.ns.Emulator.running, true)
	local restored = Harness.new(w.ns.db, w.ns.charDb)
	equal(restored.ns.IsDebug(), true)
	w.env.SlashCmdList.QUESTPARTY("debug off")
	equal(w.ns.IsDebug(), false)
	equal(w.ns.Emulator.running, false)
	w:advance(60)
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("local development builds start in debug mode even after a saved off choice", function()
	local w = Harness.new({ debug = false }, nil, true)
	equal(w.ns.IsDebug(), true)
	w.ns.SetDebug(false)
	equal(w.ns.IsDebug(), false)
	local reloaded = Harness.new(w.ns.db, w.ns.charDb, true)
	equal(reloaded.ns.IsDebug(), true)
	equal(Harness.new().ns.IsDebug(), false)
end)

test("create or join saves the name and waits for confirmed membership", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	equal(w.ns.Session:Connect("  QuestFriends  "), true)
	equal(w.ns.db.connection.name, "QuestFriends")
	equal(w.ns.db.connection.enabled, true)
	equal(w.joins[1], "QuestFriends")
	equal(w.ns.Session.state, "joining")
	equal(w.ns.Session.channelId, nil)
	w:join("QuestFriends", 5)
	equal(w.ns.Session.state, "connected")
	equal(w.ns.Session.channelId, 5)
	w:advance(20)
	equal(w.ns.Session.state, "connected")
	equal(#w.sent, 1) -- the hello to the channel, and nothing else
end)

test("invalid channel names do not change the saved connection or join anything", function()
	local w = Harness.new()
	for _, name in ipairs({ "", "   ", "123", "two words", string.rep("a", 31), "name|cffff00" }) do
		equal(w.ns.Session:Connect(name), false)
	end
	equal(#w.joins, 0)
	equal(w.ns.db.connection.name, "")
	equal(w.ns.db.connection.enabled, false)
end)

test("selecting an already joined channel does not duplicate joins or chat subscriptions", function()
	local w = Harness.new()
	w:join("QuestFriends", 5)
	equal(w.ns.Session:Connect("questfriends"), true)
	equal(w.ns.Session.state, "connected")
	equal(#w.joins, 0)
	w.ns.Session:Connect("QuestFriends")
	equal(#w.env.DEFAULT_CHAT_FRAME.channelList, 1)
end)

test("login reconnects only when the saved connection is enabled", function()
	local w = Harness.new({ connection = { name = "QuestFriends", enabled = true } })
	w.ns.Bus:Fire("READY")
	equal(w.joins[1], "QuestFriends")
	equal(w.ns.Session.state, "joining")
	local off = Harness.new({ connection = { name = "QuestFriends", enabled = false } })
	off.ns.Bus:Fire("READY")
	equal(#off.joins, 0)
end)

test("disconnect leaves the channel and cancels reconnect on login", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	w.ns.Session:Connect("QuestFriends")
	w:join("QuestFriends")
	w.ns.Session:Disconnect()
	equal(w.leaves[1], "QuestFriends")
	equal(w.ns.Session.state, "disconnected")
	equal(w.ns.Session.channelId, nil)
	w:advance(20)
	equal(w.ns.Session.state, "disconnected")
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded.ns.Bus:Fire("READY")
	equal(#reloaded.joins, 0)
	equal(reloaded.ns.db.connection.name, "QuestFriends")
end)

test("failed or unanswered channel joins show failure and permit a corrected name", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	w.ns.Session:Connect("QuestFriends")
	w:advance(15)
	equal(w.ns.Session.state, "failed")
	assert(w.ns.Session.error)
	equal(w.ns.Session:Connect("NewChannel"), true)
	w:join("NewChannel")
	equal(w.ns.Session.state, "connected")
	local rejected = Harness.new()
	rejected.joinRejected = true
	equal(rejected.ns.Session:Connect("QuestFriends"), false)
	equal(rejected.ns.Session.state, "failed")
end)

test("channel notices are matched by name and manual leave disables reconnect", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	w.ns.Session:Connect("QuestFriends")
	w:event("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", nil, nil, nil, nil, nil, 0, 5, "OtherChannel")
	equal(w.ns.Session.state, "joining")
	w:event("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", nil, nil, nil, nil, nil, 0, 5, "QuestFriends")
	equal(w.ns.Session.state, "failed")
	w.ns.Session:Connect("QuestFriends")
	w:join("QuestFriends")
	w.channels.questfriends = nil
	w:event("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", nil, nil, nil, nil, nil, 0, 5, "QuestFriends")
	equal(w.ns.Session.state, "disconnected")
	equal(w.ns.db.connection.enabled, false)
end)

test("channel IDs can change without losing the saved channel name", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	w.ns.Session:Connect("QuestFriends")
	w:join("QuestFriends", 5)
	w.channels.questfriends.id = 7
	w:event("CHANNEL_UI_UPDATE")
	equal(w.ns.Session.channelId, 7)
	equal(w.ns.db.connection.name, "QuestFriends")
end)

test("switching active channels requires disconnect and stale join timers cannot interfere", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	w.ns.Session:Connect("QuestFriends")
	equal(w.ns.Session:Connect("NewChannel"), false)
	w.ns.Session:Disconnect()
	w:advance(5)
	equal(w.ns.Session:Connect("NewChannel"), true)
	w:advance(10)
	equal(w.ns.Session.state, "joining")
	w:join("NewChannel")
	equal(w.ns.Session.state, "connected")
end)

test("lockdown queues messages and resumes once restrictions clear", function()
	local w = Harness.new()
	w.lockdown = true
	w.ns.Transport:Send("test", "WHISPER", "Friend")
	equal(#w.sent, 0)
	equal(#w.ns.Transport.queue, 1)
	w.lockdown = false
	w:advance(1)
	equal(#w.sent, 1)
	equal(#w.ns.Transport.queue, 0)
end)

test("throttled messages retry, permanent failures do not", function()
	local w = Harness.new()
	w.sendResult = w.env.Enum.SendAddonMessageResult.AddonMessageThrottle
	w.ns.Transport:Send("test", "WHISPER", "Friend")
	equal(#w.ns.Transport.queue, 1)
	w.sendResult = 0
	w:advance(1)
	equal(#w.sent, 2)
	equal(#w.ns.Transport.queue, 0)
	w.sendResult = w.env.Enum.SendAddonMessageResult.TargetOffline
	w.ns.Transport:Send("offline", "WHISPER", "Friend")
	equal(#w.ns.Transport.queue, 0)
end)

test("lockdown queue is bounded to the latest 60 messages", function()
	local w = Harness.new()
	w.lockdown = true
	for index = 1, 65 do w.ns.Transport:Send(tostring(index), "PARTY") end
	equal(#w.ns.Transport.queue, 60)
	equal(w.ns.Transport.queue[1].text, "6")
end)

test("sample party replays into every filter without outgoing events", function()
	local w = Harness.new()
	w.ns.SetDebug(true)
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function() outgoing = outgoing + 1 end)
	w.ns.SetEnabled("kills", true)
	local count = #w.ns.Emulator:GetSteps()
	assert(count > 0)
	w.ns.Emulator:Burst(count)
	for _, filter in ipairs(w.ns.Filters) do
		for _, row in ipairs(w.ns.ViewModel:Build(filter.id)) do
			assert(type(row.title) == "string")
			assert(type(row.lines) == "table")
		end
	end
	assert(#w.ns.Store:GetFeed(true) > 0)
	equal(outgoing, 0)
	equal(#w.sent, 0)
end)


-- ========= Sharing over the channel =========================================
local function sentOfKind(w, kind)
	local found = {}
	for _, message in ipairs(w.sent) do
		local messageKind, fields = w.ns.Protocol.Decode(message.text)
		if messageKind == kind then found[#found + 1] = { message = message, fields = fields } end
	end
	return found
end

test("nothing is sent while there is no channel", function()
	local w = Harness.new()
	w.ns.Bus:Fire("READY")
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 21 } })
	equal(#w.sent, 0)
	equal(w.ns.Sharing:Status(), w.ns.L.SHARE_STATUS_OFF)
end)

test("connecting says hello to the channel once, even when its number changes", function()
	local w = Harness.new()
	w:share()
	local hellos = sentOfKind(w, "H")
	equal(#hellos, 1)
	equal(hellos[1].message.channel, "CHANNEL")
	equal(hellos[1].message.target, 5)
	equal(hellos[1].fields.c, "MAGE")
	equal(hellos[1].fields.l, 20)
	w.channels.questfriends.id = 7
	w:event("CHANNEL_UI_UPDATE")
	w:advance(3)
	equal(#sentOfKind(w, "H"), 1)
end)

test("your own progress goes to the channel you chose, as an addon message", function()
	local w = Harness.new()
	w:share()
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "quest_progress", data = { questID = 7, quest = "A Quest", objective = "Kobolds", have = 2, need = 3 } })
	local entries = sentOfKind(w, "E")
	equal(#entries, 1)
	equal(entries[1].message.prefix, "QuestParty")
	equal(entries[1].message.channel, "CHANNEL")
	equal(entries[1].message.target, 5)
	equal(entries[1].fields.t, "quest_progress")
	equal(entries[1].fields.c, "MAGE")
	equal(entries[1].fields.quest, "A Quest")
	equal(entries[1].fields.have, 2)
	equal(entries[1].fields.questID, 7)
end)

test("a level-up in game reaches the channel", function()
	local w = Harness.new()
	w:share()
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	local entries = sentOfKind(w, "E")
	equal(#entries, 1)
	equal(entries[1].fields.t, "level")
	equal(entries[1].fields.level, 21)
end)

test("what a friend sends on the channel shows in the feed under their name", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "level", c = "PRIEST", level = 12 }, "Friend")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].player, "Friend") -- the realm is dropped
	equal(feed[1].class, "PRIEST")
	equal(feed[1].type, "level")
	equal(feed[1].data.level, 12)
	equal(w.ns.Session:IsConnected("Friend"), true)
end)

test("a friend's quest progress becomes their quest card", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "quest_progress", c = "PRIEST", questID = 9, quest = "Wolves", objective = "Wolves slain", have = 1, need = 8 }, "Friend")
	local cards = w.ns.Store:GetCards("quest")
	equal(#cards, 1)
	equal(cards[1].player, "Friend")
	equal(cards[1].data.quest, "Wolves")
end)

test("messages that are not for us are ignored", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "level", c = "PRIEST", level = 12 }, "Friend", 9) -- another channel
	w:hear("E", { t = "level", c = "MAGE", level = 12 }, "Tester") -- our own, echoed back
	w:hear("E", { t = "no_such_type", level = 12 }, "Friend")
	w:event("CHAT_MSG_ADDON", "QuestParty", "<secret>", "CHANNEL", "Friend-TestRealm", "", 0, 5, "QuestFriends")
	w:event("CHAT_MSG_ADDON", "OtherAddon", w.ns.Protocol.Encode("E", { t = "level", level = 12 }), "CHANNEL", "Friend-TestRealm", "", 0, 5, "QuestFriends")
	w:event("CHAT_MSG_ADDON", "QuestParty", "not a quest party message", "CHANNEL", "Friend-TestRealm", "", 0, 5, "QuestFriends")
	w:event("CHAT_MSG_ADDON", "QuestParty", w.ns.Protocol.Encode("E", { t = "level", level = 12 }), "PARTY", "Friend-TestRealm", "", 0, 0, "")
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("escape codes in what others send are made harmless", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "discovery", c = "PRIEST", zone = "|TInterface\\Icons\\x:64|t|cffff0000Fake|r" }, "Friend")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].data.zone, "||TInterface\\Icons\\x:64||t||cffff0000Fake||r")
end)

test("a hello is answered and adds the newcomer, an answer adds who was already there", function()
	local w = Harness.new()
	w:share()
	local before = #sentOfKind(w, "A")
	w:hear("H", { v = "0.2.0", c = "PRIEST", l = 14, z = "Westfall" }, "Newcomer")
	equal(#sentOfKind(w, "A"), before + 1)
	equal(w.ns.Session.peers.Newcomer.class, "PRIEST")
	equal(w.ns.Session.peers.Newcomer.level, 14)
	equal(w.ns.Session.peers.Newcomer.version, "0.2.0")
	w:hear("A", { v = "0.1.1", c = "ROGUE", l = 30, z = "Duskwood" }, "Veteran")
	equal(#sentOfKind(w, "A"), before + 1) -- an answer is not answered
	equal(w.ns.Session:Count(), 2)
end)

test("leaving the channel, or disconnecting, ends the sharing", function()
	local w = Harness.new()
	w:share()
	w:hear("H", { v = "0.2.0", c = "PRIEST", l = 14, z = "Westfall" }, "Friend")
	w:hear("H", { v = "0.2.0", c = "ROGUE", l = 14, z = "Westfall" }, "Other")
	equal(w.ns.Session:Count(), 2)
	w:event("CHAT_MSG_CHANNEL_LEAVE", "", "Friend-TestRealm", "", "5. QuestFriends", "", "", 0, 5, "QuestFriends")
	equal(w.ns.Session:Count(), 1)
	w.ns.Session:Disconnect()
	equal(w.ns.Session:Count(), 0)
	local sent = #w.sent
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 21 } })
	equal(#w.sent, sent)
end)

test("every message on the channel is logged for the listener: out, back and in", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local heard = {}
	w.ns.Bus:On("COMMS_LOGGED", function(record) heard[#heard + 1] = record end)
	w:share()
	local chat = #w.chat
	local log = w.ns.Sharing.log
	equal(log[#log].direction, "out") -- the hello
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 22 } })
	equal(log[#log].direction, "out")
	equal(log[#log].text, w.sent[#w.sent].text)
	w:event("CHAT_MSG_ADDON", "QuestParty", w.sent[#w.sent].text, "CHANNEL", "Tester-TestRealm", "", 0, 5, "QuestFriends")
	equal(log[#log].direction, "back")
	w:hear("A", { v = "0.2.0", c = "ROGUE", l = 30, z = "Duskwood" }, "Veteran")
	equal(log[#log].direction, "in")
	equal(log[#log].sender, "Veteran")
	w:event("CHAT_MSG_ADDON", "QuestParty", "something Quest Party cannot read", "CHANNEL", "Veteran-TestRealm", "", 0, 5, "QuestFriends")
	equal(log[#log].text, "something Quest Party cannot read") -- still listed
	w:hear("E", { t = "level", c = "MAGE", level = 12 }, "Elsewhere", 9)
	equal(log[#log].text, "something Quest Party cannot read") -- another channel is not ours to list
	equal(#heard, #log)
	equal(#w.chat, chat + 1) -- only "Veteran is sharing with you": messages are not printed to chat
	for _ = 1, 250 do w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 22 } }) end
	equal(#log, 200) -- the newest are kept
end)

test("our own messages coming back from the server are counted and never shown as someone else's", function()
	local w = Harness.new()
	w:share()
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 21 } })
	w:event("CHAT_MSG_ADDON", "QuestParty", w.sent[#w.sent].text, "CHANNEL", "Tester-TestRealm", "", 0, 5, "QuestFriends")
	equal(w.ns.Sharing.echoed, 1)
	equal(w.ns.Sharing.received, 0)
	equal(w.ns.Session:Count(), 0)
	equal(#w.ns.Store:GetFeed(true), 0)
	assert(w.ns.Sharing:Status():find("1 of them came back", 1, true), w.ns.Sharing:Status())
end)

test("a character with a surname still knows its own messages", function()
	local w = Harness.new()
	w.env.UnitName = function() return "Bagoe", "Bones" end -- Forever: first name, surname
	w:share()
	equal(w.ns.IsMe("Bagoe Bones"), true)
	equal(w.ns.IsMe("Bagoe-Bones"), true)
	equal(w.ns.IsMe("Bagoe Smith"), false)
	equal(w.ns.IsMe("Tombert Roams"), false)
	w:hear("H", { v = "0.1.1", c = "PALADIN", l = 10, z = "Undercity" }, "Bagoe Bones")
	equal(w.ns.Session:Count(), 0) -- not "Bagoe Bones is sharing with you"
	equal(#sentOfKind(w, "A"), 0) -- and no answer to ourselves
	w:hear("H", { v = "0.1.1", c = "MAGE", l = 12, z = "Undercity" }, "Tombert Roams")
	equal(w.ns.Session:Count(), 1)
end)

test("the emulator's players go over the channel and show only when the server sends them back", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.ns.SetDebug(true)
	w:share()
	equal(w.ns.Emulator:Channel(), "QuestFriends")
	local before = #w.sent
	w.ns.Emulator:Step()
	equal(#w.sent, before + 1)
	local kind, fields = w.ns.Protocol.Decode(w.sent[#w.sent].text)
	equal(kind, "E")
	equal(fields.as, "Jaina")
	equal(fields.c, "MAGE")
	equal(fields.t, "level")
	equal(w.sent[#w.sent].channel, "CHANNEL")
	equal(#w.ns.Store:GetFeed(true), 0) -- sent, but not back yet
	w:event("CHAT_MSG_ADDON", "QuestParty", w.sent[#w.sent].text, "CHANNEL", "Tester-TestRealm", "", 0, 5, "QuestFriends")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].player, "Jaina")
	equal(feed[1].class, "MAGE")
	equal(feed[1].data.level, 23)
	equal(feed[1].data.as, nil)
	equal(w.ns.Session:Count(), 0) -- a pretend player is not someone sharing
end)

test("someone else's emulator does not put pretend players in your panel", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "level", c = "MAGE", as = "Jaina", level = 23 }, "Friend")
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("with no channel the emulator's players are shown directly and nothing is sent", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.ns.SetDebug(true)
	equal(w.ns.Emulator:Channel(), nil)
	w.ns.Emulator:Step()
	equal(#w.sent, 0)
	equal(#w.ns.Store:GetFeed(true), 1)
end)

test("nothing is ever posted as chat", function()
	local w = Harness.new()
	w.env.C_ChatInfo.SendChatMessage = function() error("Quest Party posted a chat line") end
	w.env.SendChatMessage = w.env.C_ChatInfo.SendChatMessage
	w:share()
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 21 } })
	w:hear("H", { v = "0.2.0", c = "PRIEST", l = 14, z = "Westfall" }, "Newcomer")
	for _, message in ipairs(w.sent) do
		equal(message.prefix, "QuestParty")
	end
end)

test("a send the game refuses is reported once and counted", function()
	local w = Harness.new()
	w:share()
	local lines = #w.chat
	w.sendResult = w.env.Enum.SendAddonMessageResult.InvalidChatType
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 21 } })
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 22 } })
	equal(#w.chat, lines + 1)
	assert(w.chat[#w.chat]:find("InvalidChatType", 1, true), w.chat[#w.chat])
	equal(w.ns.Sharing.refused, 2)
	assert(w.ns.Sharing:Status():find("refused 2", 1, true), w.ns.Sharing:Status())
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
