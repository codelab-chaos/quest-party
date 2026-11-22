local Harness = dofile("tests/harness.lua")
local passed, failed = 0, 0
-- KekChat messages in the feed (data\feed-types.lua, chat), oldest first.
local function chatRows(w)
	local rows = {}
	local feed = w.ns.Store:GetFeed(true)
	for index = #feed, 1, -1 do
		if feed[index].type == "chat" then rows[#rows + 1] = feed[index] end
	end
	return rows
end

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

test("what makes Quest Party work has no switch: it is always on", function()
	local w = Harness.new({ switches = { levels = false, quests = false } }) -- from an older save
	for _, id in ipairs({ "quests", "questDetails", "kills", "levels", "discovery", "professions", "achievements", "deaths" }) do
		equal(w.ns.IsEnabled(id), true)
		equal(w.ns.SetEnabled(id, false), false)
		equal(w.ns.SettingById[id], nil)
	end
	equal(w.ns.db.switches.levels, nil) -- the old saved choice is gone
	w:ingest("level", { level = 20 })
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(w.ns.IsEnabled("shareGear"), true) -- gear is the one choice
	w.ns.SetEnabled("shareGear", false)
	equal(w.ns.IsEnabled("shareGear"), false)
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
	equal(reloaded.ns.ViewModel:Build("quests")[1].quest, "Buddy's Quest")
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
	progress(w, 1) -- a quest shows once it is underway
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
		w:share() -- the channel is the feed: your own news comes back on it
		w.ns.SetEnabled("kills", true)
		local function kill() w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 26 experience. (+13 exp Rested bonus)") end
		local function credit() w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: 2/3") end -- one more than the log had
		if killFirst then kill() else credit() end
		w:advance(0.4)
		if killFirst then credit() else kill() end
		w:advance(w.ns.Timing.killQuietSeconds + 1) -- the kill goes out once you stop, and comes back
		local card = w.ns.Store:GetCards("quest")[1]
		equal(card.data.quest, "A Quest")
		equal(card.data.kills, 1)
		equal(card.data.xp, 26)
	end)
end

test("collectors do not attach an old unrelated kill to a quest", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w:quest(1, 3)
	w.ns.SetEnabled("kills", true)
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Rabbit dies, you gain 1 experience.")
	w:advance(2)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", "Kobolds slain: 1/3")
	equal(w.ns.Store:GetCards("quest")[1].data.kills, 0)
end)

test("a place found is one row with the XP it gave, and that XP is not a second row", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w.xp = 100
	w:event("PLAYER_LOGIN")
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Thunder Ridge")
	w.xp = 180
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(2)
	local rows = w.ns.ViewModel:Build("all")
	equal(#rows, 1)
	equal(rows[1].title, "Discovered: |cffffd100Thunder Ridge|r")
	equal(rows[1].summary, "+80 XP")
	-- The XP still counts: the bar moved.
	local mine
	for _, bar in ipairs(w.ns.ViewModel:PartyBars()) do if bar.name == w.ns.MyName() then mine = bar end end
	equal(mine.have, 180)
	-- A place found with no XP (or none yet) still has its row, and later XP is its own.
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Red Cloud Mesa")
	w:advance(2)
	w.xp = 230
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(2)
	equal(#w.ns.ViewModel:Build("all"), 3)
end)

test("a quest handed in is one gold row with its XP, and its XP is not a second row", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share() -- the channel is the feed: your own news comes back on it
	local sent = {}
	w.ns.Bus:On("ENTRY_OUTGOING", function(entry) sent[#sent + 1] = entry end)
	w:quest(3, 3)
	w.xp = 100
	w:event("PLAYER_LOGIN")
	w.ns.Collectors:Handle("QUEST_TURNED_IN", 1, 90)
	w.xp = 190
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(2)
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].type, "quest_complete")
	local row = w.ns.ViewModel:Build("all")[1]
	equal(row.title, "|cffffd100A Quest|r Complete!")
	equal(row.highlight, "quest")
	equal(w.ns.Store:GetMembers()[1].currentXP, 190) -- the XP is still counted
	equal(#sent, 2) -- and still shared, for friends' bars
	equal(sent[2].data.quest, "A Quest")
	-- XP a while later is a row of its own again.
	w:advance(5)
	w.xp = 250
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 2)
end)

test("a finished objective reads as done, with a check mark, not as the quest handed in", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:ingest("quest_progress", { quest = "A Quest", objective = "Scarlet Insignia Ring", have = 10, need = 10 })
	local row = w.ns.ViewModel:Build("all")[1]
	equal(row.title, "Done: 10/10 |cffffd100Scarlet Insignia Ring|r")
	equal(row.icon, "Interface\\RaidFrame\\ReadyCheck-Ready")
	equal(row.highlight, nil)
end)

-- ========= XP runs ==========================================================
test("kills of one creature add up in one row, and other XP in another", function()
	local w = Harness.new({ switches = { chatEcho = false, kills = true } })
	w:share() -- the channel is the feed: your own news comes back on it
	w.xp = 100
	w:event("PLAYER_LOGIN")
	local function kill(mob, xp)
		w:advance(20)
		w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", ("%s dies, you gain %d experience."):format(mob, xp))
		w.xp = w.xp + xp
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(0)
	end
	kill("Wandering Spirit", 81)
	kill("Wandering Spirit", 81)
	kill("Rotting Ghoul", 70)
	kill("Wandering Spirit", 81)
	w:advance(w.ns.Timing.killQuietSeconds + 1) -- the last kill goes out, and comes back
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 2)
	equal(feed[1].data.mob, "Wandering Spirit") -- moved to the newest end
	equal(feed[1].data.xp, 243)
	equal(feed[1].data.gains, 3)
	local rows = w.ns.ViewModel:Build("xp")
	equal(rows[2].title, "Kills Wandering Spirit |cffff8c1ax3|r for 243 XP") -- the multiplier in orange
	-- 1000 - 413 = 587 to go, at 81 a kill.
	equal(rows[2].summary, "Lv 20, 8 kills to 21")
	equal(rows[1].title, "Kills Rotting Ghoul for 70 XP")
	-- Other XP adds up on its own row.
	w:advance(20)
	w.xp = w.xp + 50
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	w:advance(20)
	w.xp = w.xp + 30
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 3)
	equal(w.ns.ViewModel:Build("xp")[3].title, "+80 XP in 2 gains")
	-- After five quiet minutes, a new run.
	w:advance(6 * 60)
	kill("Wandering Spirit", 81)
	w:advance(w.ns.Timing.killQuietSeconds + 1)
	equal(#w.ns.Store:GetFeed(true), 4)
end)

test("a friend's XP runs add up too, kept apart from yours", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	for gained = 1, 3 do
		w:hear("E", { t = "xp", c = "WARRIOR", xp = 79, level = 14, currentXP = 100 + gained * 79, maxXP = 12900 }, "Tombert Roams")
	end
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].data.xp, 237)
	equal(w.ns.ViewModel:Build("xp")[1].title, "+237 XP in 3 gains")
end)

-- ========= Stats ============================================================
test("stats tally each player's week, even what the feed folds or hides", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.ns.SetDebug(true)
	w:share()
	w.xp = 100
	w:event("PLAYER_LOGIN")
	for _ = 1, 3 do -- kills fold into one row, but each counts
		w:advance(20)
		w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Wandering Spirit dies, you gain 81 experience.")
		w.xp = w.xp + 81
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(0)
	end
	w:advance(w.ns.Timing.killQuietSeconds + 1) -- the last kill goes out, and comes back
	equal(#w.ns.Store:GetFeed(true), 1) -- three kills fold into one row
	w.ns.Collectors:Handle("PLAYER_DEAD")
	w:hear("E", { t = "quest_complete", c = "WARRIOR", quest = "Leonid's Letter", xp = 90 }, "Tombert Roams")
	w:hear("E", { t = "level", c = "WARRIOR", level = 15 }, "Tombert Roams")
	local mine = w.ns.Stats:Total("Tester")
	equal(mine.xp, 243)
	equal(mine.kills, 3)
	equal(mine.deaths, 1)
	local theirs = w.ns.Stats:Total("Tombert Roams")
	equal(theirs.quests, 1)
	equal(theirs.levels, 1)
	equal(theirs.kills, nil)
	w.env.SlashCmdList.QUESTPARTY("stats")
	assert(w.chat[#w.chat - 1]:find("Tester: XP 243, kills 3, deaths 1", 1, true), w.chat[#w.chat - 1])
	assert(w.chat[#w.chat]:find("Tombert Roams: quests 1, levels 1", 1, true), w.chat[#w.chat])
end)

test("fuel is kept for good, one book per channel, and the emulator's players are not counted", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.ns.SetDebug(true)
	w:share("Alpha")
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "Jaina", class = "MAGE", emulated = true, data = { level = 23 } })
	equal(#w.ns.Stats:Players(), 0)
	w:ingest("level", { level = 21 })
	w.now = w.now + 40 * 86400
	w:ingest("level", { level = 22 })
	local reloaded = Harness.new(w.ns.db, w.ns.charDb, nil, w.now)
	equal(reloaded.ns.Stats:Total("Tester").levels, 2) -- 40 days on, nothing dropped
	reloaded.env.SlashCmdList.QUESTPARTY("stats")
	assert(reloaded.chat[#reloaded.chat]:find("Tester: levels 2", 1, true))
	-- Another channel has its own book.
	w.ns.db.connection.name = "Beta"
	equal(#w.ns.Stats:Players(), 0)
	w:ingest("level", { level = 23 })
	equal(w.ns.Stats:Total("Tester").levels, 1)
	w.ns.db.connection.name = "Alpha"
	equal(w.ns.Stats:Total("Tester").levels, 2)
	local empty = Harness.new()
	empty.ns.SetDebug(true)
	empty.env.SlashCmdList.QUESTPARTY("stats")
	assert(empty.chat[#empty.chat]:find("No fuel yet", 1, true))
end)

test("XP fuel is by level: a tenth of a level is 20 x level fuel, at any level, and nothing at the cap", function()
	local w = Harness.new()
	local XPFuel = w.ns.Stats.XPFuel
	equal(#w.ns.XPToLevel, 59)
	local total = 0
	for _, need in ipairs(w.ns.XPToLevel) do total = total + need end
	equal(total, 4084700) -- 1 to 60, as published
	-- A tenth of a level, by the table: 760 XP at 10, 18,080 at 55.
	equal(XPFuel(760, 10), 200)
	equal(XPFuel(18080, 55), 1100)
	-- The gain's own requirement wins over the table.
	equal(XPFuel(100, 10, 1000), 200)
	-- The cap, or no level: nothing.
	equal(XPFuel(500, 60), nil)
	equal(XPFuel(500, nil), nil)
	-- In Fuel: two players each gain a tenth of a level; the one at 55 gets
	-- 5.5 times the fuel, not the 24 times their raw XP is.
	w:ingest("xp", { xp = 760, level = 10, currentXP = 1000, maxXP = 7600 }, "Low")
	w:ingest("xp", { xp = 18080, level = 55, currentXP = 20000, maxXP = 180800 }, "High")
	local fuel = {}
	for _, person in ipairs(w.ns.Report:Everyone()) do fuel[person.name] = person.kinds[1].fuel end
	equal(fuel.Low, 200)
	equal(fuel.High, 1100)
	-- The feed keeps the real XP.
	equal(w.ns.Stats:Total("High").xp, 18080)
	-- A day counted before XP fuel: its XP is turned into fuel at the level now.
	w.ns.Stats:Book().Old = { [20000] = { xp = 3800 } }
	w.ns.Store:Ingest({ type = "level", player = "Old", class = "MAGE", data = { level = 10 } })
	equal(math.floor(w.ns.Stats:Total("Old").xpFuel + 0.5), 1000)
end)

test("a week of tallies saved before channel books moves into the current channel's book", function()
	local saved = { stats = { Bram = { [20000] = { xp = 300, kills = 4 } } }, connection = { name = "Gamma", enabled = true } }
	local w = Harness.new(saved)
	equal(w.ns.db.stats, nil)
	equal(w.ns.Stats:Total("Bram").xp, 300)
	equal(w.ns.db.fuel.gamma.Bram[20000].kills, 4)
end)

test("stats are kept for everyone now, for the 123 tab", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:ingest("level", { level = 21 })
	equal(w.ns.Stats:Total("Tester").levels, 1) -- a released build keeps them too
end)

test("the 123 tab: totals by kind stacked by player, by player for a kind, and one player's shares", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("E", { t = "level", c = "WARRIOR", level = 15 }, "Bram")
	w:hear("E", { t = "level", c = "WARRIOR", level = 16 }, "Bram")
	w:hear("E", { t = "level", c = "MAGE", level = 9 }, "Cora")
	w:hear("E", { t = "death", c = "MAGE", zone = "Duskwood", level = 9 }, "Cora")
	local report = w.ns.Report:Build()
	equal(report.mode, "stacked")
	local levels
	for _, row in ipairs(report.rows) do if row.id == "levels" then levels = row end end
	equal(levels.value, 3)
	equal(levels.segments[1].player, "Bram") -- the biggest part first
	equal(levels.segments[1].value, 2)
	local byPlayer = w.ns.Report:Build("levels")
	equal(byPlayer.mode, "players")
	equal(byPlayer.rows[1].label, "Bram")
	equal(byPlayer.rows[1].share, 1)
	equal(byPlayer.rows[2].share, 0.5)
	local shares = w.ns.Report:Build(nil, "Cora")
	equal(shares.mode, "shares")
	for _, row in ipairs(shares.rows) do
		if row.id == "levels" then equal(math.floor(row.share * 100 + 0.5), 33) end
		if row.id == "deaths" then equal(row.share, 1) end
	end
	equal(#w.ns.Report:Build("levels", "Cora").rows, 1)
	equal(w.ns.Report:Build("quests").total, 0)
end)

test("Fuel's vat: whole, sliced by kind, by player and by one player's kinds, scrolling when it must", function()
	dofile("tests/report-view.lua")(Harness)
end)

-- ========= Profession runs ==================================================
test("a run of skill-ups is one row that climbs and moves to the newest end", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	local function skillUp(skill, level)
		w.ns.Collectors:Handle("CHAT_MSG_SKILL", ("Your skill in %s has increased to %d."):format(skill, level))
	end
	skillUp("Cooking", 19)
	equal(w.ns.ViewModel:Build("all")[1].summary, nil) -- one step: nothing more to say
	equal(w.ns.ViewModel:Build("all")[1].name, w.ns.ColorName("Tester", w.ns.ViewModel:Build("all")[1].class)) -- who: on hover
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	for level = 20, 26 do
		w:advance(5)
		skillUp("Cooking", level)
	end
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 2) -- the level-up, and one Cooking row
	equal(feed[1].type, "skill")
	equal(feed[1].data.level, 26)
	equal(feed[1].data.from, 19)
	local rows = w.ns.ViewModel:Build("all")
	equal(rows[#rows].title, "Cooking 19 > |cffffd10026|r") -- newest at the bottom
	equal(rows[#rows].summary, "7 skill-ups")
	equal(#w.chat, 2) -- announced once in chat, plus the level-up, not once a point
	skillUp("Herbalism", 62)
	equal(#w.ns.Store:GetFeed(true), 3) -- another profession is its own row
	w:advance(5)
	skillUp("Herbalism", 63)
	equal(w.ns.ViewModel:Build("professions")[2].summary, "1 skill-up")
	w:advance(11 * 60)
	skillUp("Cooking", 27)
	equal(#w.ns.Store:GetFeed(true), 4) -- long after, a new run
	equal(w.ns.Store:GetFeed(true)[1].data.from, nil)
end)

test("a friend's run of skill-ups is kept apart from yours", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w.ns.Collectors:Handle("CHAT_MSG_SKILL", "Your skill in Cooking has increased to 10.")
	w:hear("E", { t = "skill", c = "WARRIOR", skill = "Cooking", level = 40 }, "Tombert Roams")
	w:hear("E", { t = "skill", c = "WARRIOR", skill = "Cooking", level = 41 }, "Tombert Roams")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 2)
	equal(feed[1].player, "Tombert Roams")
	equal(feed[1].data.level, 41)
	equal(feed[1].data.from, 40)
end)

-- ========= Level-ups ========================================================
test("a level-up says DING first", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	local row = w.ns.ViewModel:Build("all")[1]
	equal(row.title, "DING!! Reached Level 21!")
	equal(row.highlight, "level")
	equal(row.badge.style, "level") -- a gold badge with the new level, in place of the icon
	equal(row.badge.text, "21")
	equal(w.ns.ViewModel:Build("all")[1].kind, "feed")
	assert(w.chat[#w.chat]:find("DING!! ", 1, true), w.chat[#w.chat])
end)

test("confetti bursts for anyone's level-up while the panel shows, and only then", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local confetti = w.ns.Confetti
	local bursts = 0
	confetti.Burst = function() bursts = bursts + 1 end
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(bursts, 0) -- no panel yet
	local shown = true
	confetti:SetHost({ IsShown = function() return shown end })
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 22)
	equal(bursts, 1)
	w:hear("E", { t = "level", c = "WARRIOR", level = 14 }, "Tombert Roams")
	equal(bursts, 2) -- a friend's ding too
	w:ingest("quest_complete", { quest = "A Quest", xp = 90 })
	equal(bursts, 2) -- only level-ups
	shown = false
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 23)
	equal(bursts, 2) -- the panel is hidden
	shown = true
	w.ns.SetEnabled("confetti", false)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 24)
	equal(bursts, 2) -- switched off
end)

test("/qp testloc shows a test in your own panel and sends nothing", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local confetti = w.ns.Confetti
	local bursts = 0
	confetti.Burst = function() bursts = bursts + 1 end
	confetti:SetHost({ IsShown = function() return true end })
	w:share()
	local sent = #w.sent
	w.env.SlashCmdList.QUESTPARTY("testloc confetti")
	assert(w.chat[#w.chat]:find(w.ns.L.CMD_DEBUG_REQUIRED, 1, true)) -- debug mode only
	equal(bursts, 0)
	w.ns.SetDebug(true)
	w.env.SlashCmdList.QUESTPARTY("testloc confetti")
	equal(bursts, 1)
	equal(#w.ns.Store:GetFeed(true), 0) -- confetti alone, no row
	w.env.SlashCmdList.QUESTPARTY("testloc LEVEL")
	equal(w.ns.Store:GetFeed(true)[1].type, "level")
	equal(w.ns.Store:GetFeed(true)[1].data.level, 21)
	equal(bursts, 2) -- a level-up row sets off confetti too
	w.env.SlashCmdList.QUESTPARTY("testloc all")
	equal(bursts, 4)
	equal(#w.sent, sent) -- nothing at all went to the channel
	w.env.SlashCmdList.QUESTPARTY("testloc")
	assert(w.chat[#w.chat]:find("confetti, level, death, quest, kill", 1, true), w.chat[#w.chat])
	w.env.SlashCmdList.QUESTPARTY("testloc nonsense")
	assert(w.chat[#w.chat]:find("Local tests", 1, true))
end)

test("confetti falls, sways, spins and fades, then is done", function()
	local confetti = Harness.new().ns.Confetti
	local seed = 1
	local function random()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local pieces = confetti.Spawn(390, random)
	equal(#pieces, confetti.Config.pieces)
	for _, piece in ipairs(pieces) do
		assert(piece.x >= 0 and piece.x <= 390)
		assert(piece.delay >= 0 and piece.delay <= confetti.Config.stagger)
	end
	local first = pieces[1]
	local startY, startRotation = first.y, first.rotation
	local left = confetti.Step(pieces, 0.05, 420)
	equal(left, #pieces) -- nothing is done yet
	for _ = 1, 30 do confetti.Step(pieces, 0.05, 420) end
	assert(first.y > startY, "it falls")
	assert(first.rotation ~= startRotation, "it spins")
	assert(first.vy <= confetti.Config.terminal, "never faster than paper falls")
	local seconds = 0
	repeat
		left = confetti.Step(pieces, 0.05, 420)
		seconds = seconds + 0.05
	until left == 0 or seconds > 10
	equal(left, 0)
	assert(seconds <= confetti.Config.stagger + confetti.Config.duration + 0.1, "all done within its time")
	-- A long frame is stepped as a short one, so nothing leaps across the panel.
	local more = confetti.Spawn(390, random)
	more[1].delay = 0
	local y = more[1].y
	confetti.Step(more, 5, 420)
	assert(more[1].y - y <= confetti.Config.terminal * confetti.Config.maxStep + 0.001)
end)

test("turn-in after quest removal is not announced as abandonment", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
	w:quest(1, 3)
	w.ns.Collectors:Handle("QUEST_ACCEPTED", 1)
	w.ns.Collectors:Handle("QUEST_REMOVED", 1)
	w:advance(2)
	equal(w.ns.Store:GetFeed(true)[1].type, "quest_abandoned")
	equal(#w.ns.Store:GetCards("quest"), 0)
end)

test("you are a player like any other: your own events show and go out, with no switch", function()
	local w = Harness.new({ switches = { showSelf = false } }) -- an old saved switch changes nothing
	w:share()
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function() outgoing = outgoing + 1 end)
	equal(w.ns.SettingById.showSelf, nil)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(outgoing, 1)
end)

test("progress is always stored and shared, even with its rows hidden in the gutter", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	local sent = {}
	w.ns.Bus:On("ENTRY_OUTGOING", function(entry) sent[#sent + 1] = entry end)
	w.ns.charDb.hidden.levels = true
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#sent, 1)
	equal(#w.ns.Store:GetFeed(true), 1)
	equal(#w.ns.ViewModel:Build("all"), 0)
end)

test("XP gains show current level and percentage remaining without duplicate updates", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
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
	equal(row.summary, "Lv 20, 45% to 21")
	equal(row.progress.have, 550)
	equal(row.progress.need, 1000)
	equal(#w.chat, 1)
	assert(w.chat[1]:find("Lv 20, 45%% to 21"))
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.Store:GetFeed(true), 1)
	local xpSent = 0
	for _, message in ipairs(w.sent) do
		if message.text:find("t=xp", 1, true) then xpSent = xpSent + 1 end
	end
	equal(xpSent, 1) -- went out once
end)

test("XP rollover reads settled level data and includes XP earned before leveling", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
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
	equal(rows[2].summary, "Lv 21, 90% to 22")
end)

test("saved XP history survives reload without announcing old gains again", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w:event("PLAYER_LOGIN")
	w.xp = 100
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded.xp = 100
	reloaded:share()
	reloaded:event("PLAYER_LOGIN")
	reloaded:event("PLAYER_XP_UPDATE", "player")
	reloaded:advance(0)
	equal(#reloaded.ns.Store:GetFeed(true), 1)
	equal(reloaded.ns.ViewModel:Build("xp")[1].title, "+100 XP")
	equal(#reloaded.chat, 0)
	reloaded.xp = 125
	reloaded:event("PLAYER_XP_UPDATE", "player")
	reloaded:advance(0)
	-- A new gain soon after joins the run: one row that adds up.
	equal(#reloaded.ns.Store:GetFeed(true), 1)
	equal(reloaded.ns.Store:GetFeed(true)[1].data.xp, 125)
	equal(reloaded.ns.Store:GetFeed(true)[1].data.gains, 2)
end)

test("unreadable or reduced XP cannot create a fake gain", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
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
		w:share()
		w:event("PLAYER_LOGIN")
		w.level, w.xp, w.xpMax = 22, capped and 0 or 250, capped and 0 or 2000
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(0)
		local row, level
		for _, built in ipairs(w.ns.ViewModel:Build("xp")) do
			if built.title == "XP progress updated" then row = built end
			if built.title:find("Reached Level 22") then level = built end
		end
		equal(row ~= nil, true)
		equal(level ~= nil, true) -- the jump is a level-up too
		if capped then
			equal(row.summary, "Level 22")
			equal(row.progress, nil)
		else
			equal(row.summary, "Lv 22, 88% to 23")
		end
	end
end)

test("XP gains keep each player's XP, and your own bar comes first", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w.xp = 400
	w:event("PLAYER_LOGIN")
	w.xp = 550
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	local member = w.ns.Store:GetMembers()[1]
	equal(member.lastXP, 150)
	equal(member.currentXP, 550)
	equal(member.maxXP, 1000)
	equal(#w.ns.ViewModel:PartyBars(), 1) -- your own bar, first
	equal(w.ns.ViewModel:PartyBars()[1].me, true)
	equal(w.ns.ViewModel:PartyBars()[1].have, 550)
end)

test("a kill row wears the Kills square, the filter that hides it; other XP keeps the XP square", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:ingest("xp", { xp = 50, mob = "Kobold", level = 9, currentXP = 100, maxXP = 1000 }, "Friend")
	w:ingest("xp", { xp = 85, level = 9, currentXP = 185, maxXP = 1000 }, "Friend")
	local marks = {}
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do
		if row.title:find("Kobold", 1, true) then marks.kill = row.mark else marks.xp = row.mark end
	end
	equal(marks.kill, "kills")
	equal(marks.xp, "xp")
end)

test("an XP gain names the kill behind it when the game said, and not otherwise", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w.ns.SetEnabled("kills", true)
	w.xp = 100
	w:event("PLAYER_LOGIN")
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Riverpaw Gnoll dies, you gain 65 experience.")
	w.xp = 165
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(w.ns.Timing.killQuietSeconds + 1) -- the kill goes out once you stop, and comes back
	equal(w.ns.Store:GetMembers()[1].lastMob, "Riverpaw Gnoll")
	equal(w.ns.Store:GetFeed(true)[1].data.mob, "Riverpaw Gnoll")
	local row = w.ns.ViewModel:Build("xp")[1]
	equal(row.title, "Kills Riverpaw Gnoll for 65 XP")
	equal(row.progress, nil) -- no bar: it would read as quest progress
	equal(row.lines[1].progress, nil)
	equal(row.summary, "Lv 20, 13 kills to 21") -- 835 left, 65 a kill
	w:advance(5)
	w.xp = 265 -- a quest turn-in: no kill
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(w.ns.Store:GetMembers()[1].lastMob, "")
	equal(#w.ns.Store:GetFeed(true), 2) -- every gain is a feed row
	equal(w.ns.ViewModel:Build("xp")[2].title, "+100 XP")
	equal(w.ns.ViewModel:Build("xp")[2].progress.have, 265) -- other XP keeps its bar
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Old Kill dies, you gain 9 experience.")
	w:advance(5)
	w.xp = 300 -- long after that kill: not named after it
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(w.ns.Store:GetMembers()[1].lastMob, "")
end)

test("the party's XP bars: yours first, then one per player sharing, sorted by name, with level and how far to go", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("H", { v = "0.2.0", c = "WARRIOR", l = 13, z = "Duskwood", x = 5400, m = 11400 }, "Tombert Roams")
	w:hear("H", { v = "0.2.0", c = "PRIEST", l = 9, z = "Westfall" }, "Another")
	local bars = w.ns.ViewModel:PartyBars()
	equal(#bars, 3)
	equal(bars[1].name, "Tester") -- you first
	equal(bars[1].have, 0)
	table.remove(bars, 1)
	equal(bars[1].name, "Another")
	equal(bars[1].have, nil) -- an older build's hello says no XP: level only, until it gains some
	equal(bars[1].levelText, "9")
	equal(bars[1].text, "")
	equal(bars[2].name, "Tombert Roams")
	equal(bars[2].have, 5400)
	equal(bars[2].need, 11400)
	equal(bars[2].levelText, "13")
	equal(bars[2].text, "47%") -- 5,400 of 11,400
end)

test("XP from a kill is a Kills row: the gutter can hide it, and the bar moves either way", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	equal(w.ns.IsEnabled("kills"), true) -- always on
	w.xp = 100
	w:event("PLAYER_LOGIN")
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Riverpaw Gnoll dies, you gain 65 experience.")
	w.xp = 165
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(w.ns.Timing.killQuietSeconds + 1) -- the kill goes out once you stop, and comes back
	equal(#w.ns.ViewModel:Build("all"), 1)
	w.ns.charDb.hidden.kills = true
	equal(#w.ns.ViewModel:Build("all"), 0)
	equal(w.ns.Store:GetMembers()[1].currentXP, 165) -- kept all the same
	w:advance(5)
	w.xp = 265 -- not a kill: a Leveling row, still shown
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(0)
	equal(#w.ns.ViewModel:Build("all"), 1)
	equal(w.ns.ViewModel:Build("all")[1].title, "+100 XP")
	-- A friend's kill XP follows your gutter too, and still moves their bar.
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 75, level = 13, currentXP = 5400, maxXP = 11400, mob = "Murloc" }, "Tombert Roams")
	equal(#w.ns.ViewModel:Build("all"), 1)
	equal(w.ns.ViewModel:PartyBars()[2].have, 5400)
end)


test("a player at the level cap, who never gains XP, still has a bar from the hello", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("H", { v = "0.2.0", c = "WARRIOR", l = 60, z = "Orgrimmar", x = 0, m = 0 }, "Old Timer")
	local bar = w.ns.ViewModel:PartyBars()[2]
	equal(bar.name, "Old Timer")
	equal(bar.maxLevel, true)
	equal(bar.levelText, "60")
	equal(bar.text, "max level")
end)

test("a friend's XP is a feed row that names the kill, and it moves their bar", function()
	local w = Harness.new({ switches = { chatEcho = false, kills = true } })
	w:share()
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 75, level = 13, currentXP = 5400, maxXP = 11400, mob = "Riverpaw Gnoll" }, "Tombert Roams")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].player, "Tombert Roams")
	equal(w.ns.ViewModel:Build("xp")[1].title, "Kills Riverpaw Gnoll for 75 XP")
	local bar = w.ns.ViewModel:PartyBars()[2]
	equal(bar.have, 5400)
	equal(bar.text, "47%")
	equal(bar.lastXP, 75)
	equal(bar.lastMob, "Riverpaw Gnoll")
	-- An older build sends no kill name: the row is the plain gain.
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 59, level = 13, currentXP = 5459, maxXP = 11400 }, "Tombert Roams")
	equal(w.ns.ViewModel:Build("xp")[2].title, "+59 XP")
	equal(w.ns.ViewModel:PartyBars()[2].have, 5459)
end)

test("the emulator's players have bars in debug mode only", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "xp", player = "Jaina", class = "MAGE", emulated = true, data = { xp = 3000, level = 23, currentXP = 22000, maxXP = 25000 } })
	equal(#w.ns.ViewModel:PartyBars(), 1) -- only you
	w.ns.SetDebug(true)
	equal(w.ns.ViewModel:PartyBars()[2].name, "Jaina")
end)

test("logged messages from others survive a reload and replay into the panel without sending anything", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("H", { v = "0.2.0", c = "WARRIOR", l = 13, z = "Duskwood", x = 6000, m = 11400 }, "Tombert Roams")
	w:hear("E", { t = "level", c = "WARRIOR", level = 14 }, "Tombert Roams")
	w:hear("Q", { id = 9, quest = "Wolves", c = "WARRIOR", o1 = "Wolves slain", h1 = 3, n1 = 8 }, "Tombert Roams")
	w.ns.Store:Clear()
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded.ns.SetDebug(true)
	local sent = #reloaded.sent
	reloaded.env.SlashCmdList.QUESTPARTY("replay")
	equal(#reloaded.sent, sent) -- the replayed hello is not answered
	equal(#reloaded.ns.Store:GetFeed(true), 1)
	equal(reloaded.ns.Store:GetFeed(true)[1].player, "Tombert Roams")
	equal(#reloaded.ns.Store:GetCards("quest"), 1)
	equal(reloaded.ns.Store:GetMembers()[1].name, "Tombert Roams")
	assert(reloaded.chat[#reloaded.chat]:find("Replayed 3 messages", 1, true), reloaded.chat[#reloaded.chat])
end)

test("replay needs debug mode", function()
	local w = Harness.new()
	w.env.SlashCmdList.QUESTPARTY("replay")
	assert(w.chat[#w.chat]:find(w.ns.L.CMD_DEBUG_REQUIRED, 1, true))
end)

test("learning a profession is a row of its own, each time; a weapon skill is not", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w.ns.Collectors:Handle("CHAT_MSG_SKILL", "You have gained the Fishing skill.")
	w.ns.Collectors:Handle("CHAT_MSG_SKILL", "You have gained the Daggers skill.")
	local rows = {}
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do rows[#rows + 1] = row end
	equal(#rows, 1)
	equal(rows[1].title, "Learned |cffffd100Fishing|r!")
	equal(rows[1].mark, "skill")
	equal(rows[1].markIcon, "Interface\\Icons\\Trade_Fishing")
	equal(rows[1].stampKey ~= nil, true) -- a card to stamp
end)

test("only profession skill-ups are reported, not weapon skills or Defense", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share() -- the channel is the feed: your own news comes back on it
	local function skillUp(skill, level)
		w.ns.Collectors:Handle("CHAT_MSG_SKILL", ("Your skill in %s has increased to %d."):format(skill, level))
	end
	skillUp("Swords", 64)
	skillUp("Defense", 62)
	equal(#w.ns.Store:GetFeed(true), 0)
	skillUp("Herbalism", 62)
	skillUp("Cooking", 40)
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 2)
	equal(feed[1].data.skill, "Cooking")
	equal(feed[2].data.skill, "Herbalism")
	skillUp("Some New Craft", 5) -- not in the list: reported, as before
	equal(#w.ns.Store:GetFeed(true), 3)
end)

test("a death is reported with where it happened and the level", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share() -- the channel is the feed: your own news comes back on it
	local sent = {}
	w.ns.Bus:On("ENTRY_OUTGOING", function(entry) sent[#sent + 1] = entry end)
	w.ns.Collectors:Handle("PLAYER_DEAD")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].type, "death")
	equal(feed[1].data.zone, "Elwynn Forest")
	equal(feed[1].data.level, 20)
	equal(#sent, 1) -- and shared with the channel
	local row = w.ns.ViewModel:Build("all")[1]
	assert(row.title:find("Elwynn Forest", 1, true), row.title)
end)

test("a friend's death arrives over the channel", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("E", { t = "death", c = "WARRIOR", zone = "Duskwood", level = 13 }, "Tombert Roams")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].player, "Tombert Roams")
	equal(feed[1].data.zone, "Duskwood")
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
end)

test("ambiguous objective messages wait for the owning quest's ID", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
	for have = 1, 3 do w.ns.Collectors:Handle("UI_INFO_MESSAGE", 286, "Kobolds slain: " .. have .. "/5") end
	w:quest(3, 5)
	w:advance(0.1)
	equal(w.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 3)
end)

test("a deferred log read can report a genuine objective count decrease", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
	w:quest(2, 3)
	w.quests[1].objectives[2] = { text = "Ribs: 5/5", numFulfilled = 5, numRequired = 5 }
	w.quests[2] = { questID = 2, title = "Delivery", objectives = {} }
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function() outgoing = outgoing + 1 end)
	w:event("PLAYER_LOGIN")
	-- The quest being worked on comes back as a card; Delivery, with nothing
	-- started, is not sent (as for anyone).
	equal(#w.ns.Store:GetCards("quest"), 1)
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
end)

test("each player keeps one bright color, the same everywhere, and a party of 16 shares none", function()
	local w = Harness.new()
	local C = w.ns.PlayerColors
	equal(#w.ns.PlayerPalette, 16)
	local seen = {}
	for index = 1, 16 do
		local slot = C:Index("Player" .. index)
		assert(not seen[slot], "two players share a color: " .. slot)
		seen[slot] = true
	end
	-- Kept: the same color every time, and after a reload.
	local first = C:Index("Player3")
	local reloaded = Harness.new(w.ns.db)
	equal(reloaded.ns.PlayerColors:Index("Player3"), first)
	-- The 17th gets the least used, so colors spread out again.
	local seventeenth = C:Index("Player17")
	equal(seventeenth >= 1 and seventeenth <= 16, true)
	local r = C:For("Player1")
	equal(r, w.ns.PlayerPalette[C:Index("Player1")][1])
end)

test("fuel gained in the last hour, day and week", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local S = w.ns.Stats
	-- A week ago, a day ago, now: a level-up each (1 fuel) and a quest (1).
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "A", class = "MAGE", time = w.now - 6 * 86400, data = { level = 10 } })
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "A", class = "MAGE", time = w.now - 20 * 3600, data = { level = 11 } })
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "B", class = "MAGE", time = w.now - 600, data = { level = 12 } })
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "quest_complete", player = "B", class = "MAGE", time = w.now - 60, data = { quest = "Q", xp = 0 } })
	equal(S:Recent(3600), 2)
	equal(S:Recent(86400), 3)
	equal(S:Recent(7 * 86400), 4)
	equal(S:Recent(3600, "A"), 0)
	equal(S:Recent(86400, "A"), 1)
	-- XP counts by level here too: a tenth of level 10.
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "xp", player = "B", class = "MAGE", time = w.now, data = { xp = 760, level = 10, currentXP = 900, maxXP = 7600 } })
	equal(S:Recent(3600, "B"), 2 + 200)
	-- The reset empties them too.
	S:Clear()
	equal(S:Recent(7 * 86400), 0)
end)

test("/qp fuel reset empties this channel's fuel on this client, after asking", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:ingest("level", { level = 21 })
	equal(#w.ns.Stats:Players(), 1)
	w.env.SlashCmdList[w.ns.Globals.slashKey]("fuel reset")
	equal(#w.ns.Stats:Players(), 1) -- not until confirmed
	w:dismissPopup(true)
	equal(#w.ns.Stats:Players(), 0)
	w:ingest("level", { level = 22 })
	equal(w.ns.Stats:Total("Tester").levels, 1) -- counting again
end)

test("/qp reset and /qp repos forget the panel's and dock's places", function()
	local w = Harness.new()
	local calls = 0
	w.ns.Panel = { ResetPosition = function() calls = calls + 1 end }
	w.env.SlashCmdList[w.ns.Globals.slashKey]("reset")
	w.env.SlashCmdList[w.ns.Globals.slashKey]("repos")
	equal(calls, 2)
	equal(w.chat[#w.chat]:find("first size and place") ~= nil, true)
end)

test("the panel builds, starts up and opens every tab without an error", function()
	local smoke = dofile("tests/ui-smoke.lua")
	smoke(Harness)
end)

test("Players shown: 10 by default, up to 20, keeping you, your group and the most active", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	for index = 1, 14 do
		w:hear("H", { v = "0.3.5", c = "MAGE", l = 10, x = 100, m = 1000 }, "Player" .. index)
		w:advance(1) -- each heard a moment after the last
	end
	w.group = { "Player1" } -- the first heard: least lately, but in your group
	w:event("GROUP_ROSTER_UPDATE")
	equal(w.ns.ViewModel.PartyCap(), 10)
	local bars = w.ns.ViewModel:PartyBars()
	equal(#bars, 10)
	equal(bars[1].me, true) -- you, first
	local names = {}
	for _, bar in ipairs(bars) do names[bar.name] = true end
	equal(names.Player1, true) -- your group is kept
	equal(names.Player14, true) -- the most lately heard kept
	equal(names.Player2, nil) -- among the least lately heard: left out
	w.ns.SetSlider("partyCap", 20)
	equal(#w.ns.ViewModel:PartyBars(), 15) -- everyone: you and the 14
	w.ns.SetSlider("partyCap", 50)
	equal(w.ns.ViewModel.PartyCap(), 20) -- 20 at most
end)

test("quest cards: one player's card carries its objectives and avatar; four layouts, the List the panel's own", function()
	local w = Harness.new()
	w:ingest("quest_progress", { questID = 1, quest = "Q", objective = "Rats", have = 2, need = 5 }, "Friend")
	w:ingest("quest_progress", { questID = 1, quest = "Q", objective = "Wolves", have = 3, need = 3 }, "Friend")
	local card
	for _, row in ipairs(w.ns.ViewModel:Build("party")) do
		if row.kind == "tracker" then card = row end
	end
	equal(card.player, "Friend")
	equal(#card.objectives, 2)
	equal(card.mark, "questTaken")
	equal(card.ready, nil)
	local QC = w.ns.QuestCard
	equal(w.ns.GetSlider("questCardStyle"), 0)
	equal(QC:For(card), QC.layouts.segmented) -- the default
	w.ns.SetSlider("questCardStyle", 1)
	equal(QC:For(card), QC.layouts.grid)
	equal(QC.layouts.grid.Height(card), QC.layouts.grid.Height({ objectives = { 1 } })) -- two to a line
	w.ns.SetSlider("questCardStyle", 2)
	equal(QC:For(card).hidesMark, true)
	w.ns.SetSlider("questCardStyle", 3)
	equal(QC:For(card), nil) -- the List: the panel's own lines
	-- Every objective done: it leaves the Quest tab, as before.
	w:ingest("quest_progress", { questID = 1, quest = "Q", objective = "Rats", have = 5, need = 5 }, "Friend")
	local still = false
	for _, row in ipairs(w.ns.ViewModel:Build("party")) do
		if row.kind == "tracker" and row.quest == "Q" then still = true end
	end
	equal(still, false)
end)

test("a quest a party is on: a section per objective, those working on it latest first, the done collapsed", function()
	local w = Harness.new()
	local function Progress(player, objective, have, need, ago)
		w:ingest("quest_progress", { questID = 7, quest = "Sharing the Land", objective = objective, have = have, need = need }, player)
		w:advance(ago or 1)
	end
	Progress("Ann", "Tanner slain", 3, 10)
	Progress("Bob", "Tanner slain", 10, 10)
	Progress("Cat", "Tanner slain", 5, 10)
	Progress("Ann", "Skinner slain", 8, 8)
	Progress("Dan", "Tanner slain", 1, 10)
	Progress("Ann", "Tanner slain", 4, 10) -- Ann's newest: first
	local card
	for _, row in ipairs(w.ns.ViewModel:Build("party")) do
		if row.kind == "tracker" and row.quest == "Sharing the Land" then card = row end
	end
	equal(#card.party, 4)
	equal(w.ns.QuestCard:For(card), w.ns.QuestCard.layouts.party) -- whatever the slider
	local tanner = card.sections[1]
	equal(tanner.name, "Tanner slain")
	local order = {}
	for _, entry in ipairs(tanner.active) do order[#order + 1] = entry.name end
	equal(table.concat(order, ","), "Ann,Dan,Cat") -- the latest progress first
	equal(#tanner.done, 1) -- Bob, collapsed
	equal(tanner.done[1].name, "Bob")
	equal(card.sections[2].name, "Skinner slain")
	equal(#card.sections[2].done, 1)
	equal(w.ns.QuestCard.layouts.party.Height(card) > 0, true)
end)

test("stress: a party of 20 at the cap of 20 draws, bars and side bar, without an error", function()
	local smoke = dofile("tests/ui-smoke.lua")
	local w = smoke(Harness, { players = 20, cap = 20 })
	equal(#w.ns.ViewModel:PartyBars(), 20) -- you and 19 of the 20, at the cap
	equal(#w.ns.PartyModel:Heads(), 20)
end)

test("themes: every theme has the whole palette, and the Theme slider picks one", function()
	local w = Harness.new()
	local ns = w.ns
	local slider = ns.SliderById.theme
	for index = slider.min, slider.max do
		local theme = ns.Themes[index]
		assert(theme and theme.label, "theme " .. index)
		for _, key in ipairs({ "row", "card", "level", "handIn", "accepted", "joined" }) do
			equal(#theme[key], 2)
			equal(#theme[key][1], 4)
			equal(#theme[key][2], 4)
		end
		for _, key in ipairs({ "panel", "rim", "well", "wellEdge", "divider" }) do
			equal(#theme[key], 4)
		end
	end
	equal(ns.Theme().id, "concept")
	ns.SetSlider("theme", 2)
	equal(ns.Theme().id, "midnight")
end)

test("magnet: the pull falls off smoothly, the nearest most", function()
	local Magnet = Harness.new().ns.Magnet
	equal(Magnet.Influence(0, 70), 1)
	equal(Magnet.Influence(70, 70), 0)
	equal(Magnet.Influence(-90, 70), 0)
	assert(math.abs(Magnet.Influence(35, 70) - 0.5) < 1e-9)
	assert(Magnet.Influence(10, 70) > Magnet.Influence(20, 70))
	equal(Magnet.Influence(-20, 70), Magnet.Influence(20, 70))
end)

test("magnet: drawers glide out and back with friction, no bounce", function()
	local dock = Harness.new().ns.Magnet.New()
	dock:Push({ id = "a" }, true)
	dock:Step(0.01)
	local entry = dock.entries[1]
	local most = 0
	for _ = 1, 100 do
		dock:Step(1 / 60, function() return 1 end)
		most = math.max(most, entry.extension)
	end
	assert(most <= 1.005, "no bounce past fully out: " .. most)
	assert(math.abs(entry.extension - 1) < 0.01, "settles out " .. entry.extension)
	for _ = 1, 120 do dock:Step(1 / 60) end
	assert(math.abs(entry.extension) < 0.01, "settles back " .. entry.extension)
	equal(dock:Busy(), false)
end)

test("magnet: new entries arrive at the bottom one by one, show themselves, and push the oldest out", function()
	local dock = Harness.new().ns.Magnet.New({ maxEntries = 3 })
	for index = 1, 3 do dock:Push({ id = index }, true) end
	dock:Step(2)
	equal(#dock.entries, 3)
	-- Slots: the newest at the bottom.
	assert(math.abs(dock.entries[3].slot - 1) < 0.01)
	assert(math.abs(dock.entries[1].slot - 3) < 0.01)
	-- A burst of two: the second waits its turn.
	dock:Push({ id = "x" })
	dock:Push({ id = "y" })
	dock:Step(0.1)
	equal(dock.entries[#dock.entries].item.id, "x")
	dock:Step(0.3)
	equal(dock.entries[#dock.entries].item.id, "y")
	-- New arrivals nudge out a little to show themselves while nothing pulls them.
	dock:Step(0.3)
	local nudge = dock.entries[#dock.entries].extension
	assert(nudge > 0.15 and nudge < 0.45, "nudge " .. nudge)
	-- The two oldest were pushed out: they fade and go.
	dock:Step(3)
	local ids = {}
	for _, entry in ipairs(dock.entries) do ids[#ids + 1] = tostring(entry.item.id) end
	equal(table.concat(ids, ","), "3,x,y")
	assert(dock.entries[3].extension < 0.05, "settled after showing itself")
	-- A click takes one out.
	dock:Remove("x")
	dock:Step(1)
	equal(#dock.entries, 2)
end)

test("scenes: 16 in the atlas, picked by type or skill, cropped to a card's shape", function()
	local w = Harness.new()
	local ns = w.ns
	equal(#ns.Scenes, 16)
	for kind, id in pairs(ns.SceneByType) do
		assert(ns.SceneById[id], kind .. " names a scene that is not there: " .. id)
	end
	for skill, id in pairs(ns.SceneBySkill) do
		assert(ns.SceneById[id], skill .. " names a scene that is not there: " .. id)
	end
	equal(ns.Scene:For({ type = "level", data = {} }).id, "starfall")
	equal(ns.Scene:For({ type = "skill", data = { skill = "Fishing" } }).id, "harbor")
	equal(ns.Scene:For({ type = "skill", data = { skill = "Something New" } }).id, "forge")
	equal(ns.Scene:File(), "Interface\\AddOns\\QuestParty\\media\\scenes")
	local function close(a, b) assert(math.abs(a - b) < 1e-9, ("%s ~= %s"):format(a, b)) end
	-- Scene 4 sits at column 2, row 2: x 512 to 1024, y 64 to 128.
	local scene = ns.SceneById.graveyard
	local left, right, top, bottom = ns.Scene:Coords(scene)
	close(left, 512.5 / 1024) close(right, 1023.5 / 1024) close(top, 64.5 / 512) close(bottom, 127.5 / 512)
	-- A one-line row (18 to 1) shows a band across the middle, all the width.
	left, right, top, bottom = ns.Scene:Coords(scene, 360, 20)
	close(left, 512.5 / 1024) close(right, 1023.5 / 1024)
	close((bottom - top) * 512, 512 / 18 - 1)
	close((top + bottom) / 2 * 512, 96)
	-- A tall card (4 to 1) shows the middle of the width, all the height.
	left, right, top = ns.Scene:Coords(scene, 200, 50)
	close((right - left) * 1024, 256 - 1)
	close((left + right) / 2 * 1024, 768)
	close(top, 64.5 / 512)
end)

test("your own level-up is one row, even when the game hides the event's level in combat", function()
	for _, hidden in ipairs({ false, true }) do
		local w = Harness.new()
		w.level, w.xp = 6, 900
		w:share()
		w:event("PLAYER_LOGIN")
		w.level, w.xp, w.xpMax = 7, 26, 1300
		w:event("PLAYER_XP_UPDATE", "player")
		w:event("PLAYER_LEVEL_UP", hidden and "<secret>" or 7)
		w:advance(1)
		local levels = 0
		for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
			if entry.type == "level" then
				levels = levels + 1
				equal(entry.data.level, 7)
			end
		end
		equal(levels, 1)
	end
end)

test("the 123 XP is whole numbers, even from fractional gains or old tallies", function()
	local w = Harness.new()
	w:ingest("xp", { xp = 26.5, mob = "Kobold", level = 5, currentXP = 10, maxXP = 100 }, "Bram")
	w:ingest("xp", { xp = 13.25, mob = "Kobold", level = 5, currentXP = 20, maxXP = 100 }, "Bram")
	equal(w.ns.Stats:Total("Bram").xp, 27 + 13)
	-- A tally saved by an older build, with a fraction in it.
	local day = next(w.ns.Stats:Book().Bram)
	w.ns.Stats:Book().Bram[day].xp = 40.75
	for _, row in ipairs(w.ns.Report:Build(nil, nil).rows) do
		equal(row.value, math.floor(row.value))
	end
	equal(w.ns.Report:Build("xp", nil).rows[1].value, 41)
end)

test("every row has its mark from the concept: the game's ! and ?, XP, and one for each kind", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { questID = 1, quest = "Q" }, "Friend")
	w:ingest("quest_progress", { questID = 1, quest = "Q", objective = "Rats", have = 2, need = 5 }, "Friend")
	w:ingest("quest_complete", { questID = 2, quest = "R", xp = 100 }, "Friend")
	w:ingest("level", { level = 12 }, "Friend")
	local marks = {}
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do
		marks[row.kind .. ":" .. tostring(row.mark or (row.badge and row.badge.style))] = true
	end
	equal(marks["feed:questTaken"], true)
	equal(marks["feed:questDone"], true)
	equal(marks["progress:questTaken"], true)
	equal(marks["feed:level"], true) -- a level-up keeps its crest and number
	for _, row in ipairs(w.ns.ViewModel:Build("party")) do
		if row.kind == "tracker" then equal(row.mark, "questTaken") end
	end
	-- The game's own quest marks, and every feed type has a mark or a crest.
	equal(w.ns.MarkLooks.questTaken.texture, "Interface\\GossipFrame\\AvailableQuestIcon")
	equal(w.ns.MarkLooks.questDone.texture, 236669)
	equal(w.ns.MarkLooks.xp.text, "XP")
	for id, def in pairs(w.ns.FeedTypes) do
		assert(def.badge or (def.mark and w.ns.MarkLooks[def.mark]), "a mark for " .. id)
	end
	for _, filter in ipairs(w.ns.GutterFilters) do
		assert(w.ns.MarkLooks[filter.mark], "a mark for the " .. filter.id .. " filter")
	end
	for id, look in pairs(w.ns.MarkLooks) do
		assert(look.edge and look.fill and (look.texture or look.text), "a whole look for " .. id)
	end
end)

test("a quest two or more are on is one card as a party, a column each, and shared quests lead", function()
	local w = Harness.new()
	w:ingest("quest_progress", { questID = 1, quest = "Solo", objective = "Rats", have = 1, need = 5 }, "Friend")
	w:ingest("quest_progress", { questID = 2, quest = "Together", objective = "Wolves", have = 6, need = 6 }, "Friend")
	w:ingest("quest_progress", { questID = 2, quest = "Together", objective = "Wolves", have = 2, need = 6 }, "Tester")
	local rows = {}
	for _, row in ipairs(w.ns.ViewModel:Build("party")) do
		if row.kind == "tracker" then rows[#rows + 1] = row end
	end
	equal(rows[1].quest, "Together") -- shared, so it leads
	equal(#rows[1].party, 2)
	local byName = {}
	for _, member in ipairs(rows[1].party) do byName[member.name] = member end
	equal(byName.Friend.done, true)
	equal(byName.Tester.done, false)
	equal(byName.Tester.have, 2)
	equal(byName.Tester.me, true)
	equal(byName.Friend.objectives[1].name, "Wolves")
	equal(rows[2].quest, "Solo")
	equal(rows[2].party, nil) -- one player: the simple card
end)

test("kills that finish an objective fold into its Done row, other kills stay", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	for _ = 1, 8 do
		w:ingest("xp", { xp = 55, mob = "Palemane Tanner", level = 7, currentXP = 100, maxXP = 2000 }, "Friend")
	end
	w:ingest("xp", { xp = 60, mob = "Wiry Swoop", level = 7, currentXP = 160, maxXP = 2000 }, "Friend")
	w:ingest("quest_progress", { questID = 4, quest = "Sharing the Land", objective = "Palemane Tanner slain", have = 10, need = 10 }, "Friend")
	local rows = w.ns.ViewModel:Build("all")
	local done, tanners, swoop
	for _, row in ipairs(rows) do
		if row.title:find("Palemane Tanner slain", 1, true) then done = row end
		if row.title:find("Kills Palemane Tanner", 1, true) then tanners = row end
		if row.title:find("Wiry Swoop", 1, true) then swoop = row end
	end
	equal(tanners, nil) -- folded into the Done row
	equal(done.summary, "+8 kills, +440 XP")
	equal(swoop ~= nil, true) -- no quest of its own: stays
	equal(w.ns.Stats:Total("Friend").kills, 9) -- every kill still counted
	-- A collection: the creature that drops it folds in too.
	w:ingest("xp", { xp = 51, mob = "Prairie Wolf", level = 7, currentXP = 211, maxXP = 2000 }, "Friend")
	w:ingest("quest_progress", { questID = 5, quest = "Poison Water", objective = "Prairie Wolf Paw", have = 6, need = 6 }, "Friend")
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do
		if row.title:find("Prairie Wolf Paw", 1, true) then equal(row.summary, "+1 kill, +51 XP") end
		assert(not row.title:find("Kills Prairie Wolf", 1, true), "the wolf run folded in")
	end
end)

test("event sounds: quest complete, level up and an objective done, one per moment, none for old rows", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local played = {}
	w.env.PlaySound = function(kit) played[#played + 1] = kit return true end
	-- A kill finishes the objective, the quest is handed in and the level comes:
	-- one moment, one sound, the level's.
	w:ingest("quest_progress", { questID = 1, quest = "Q", objective = "Rats", have = 10, need = 10 }, "Friend")
	w:ingest("quest_complete", { questID = 1, quest = "Q", xp = 700 }, "Friend")
	w:ingest("level", { level = 11 }, "Friend")
	w:advance(1)
	equal(#played, 1)
	equal(played[1], 46893)
	-- On its own, a quest handed in sounds its own.
	w:ingest("quest_complete", { questID = 2, quest = "R", xp = 300 }, "Friend")
	w:advance(1)
	equal(played[2], 23404)
	-- An objective done.
	w:ingest("quest_progress", { questID = 3, quest = "S", objective = "Wolves", have = 6, need = 6 }, "Friend")
	w:advance(1)
	equal(played[3], 878)
	-- Rows with no sound, and an old row caught up, are quiet.
	w:ingest("death", { zone = "X", level = 5 }, "Friend")
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "Old", class = "MAGE", time = w.now - 3600, data = { level = 9 } })
	w:advance(1)
	equal(#played, 3)
end)

test("stamps add up by kind, in the order each was first used, one per player", function()
	local w = Harness.new()
	local S = w.ns.Stamping
	local key = "Friend~level~12"
	S:Add(key, "gg", "Ann", 100)
	S:Add(key, "gratz", "Bob", 101)
	S:Add(key, "gg", "Cat", 102)
	S:Add(key, "gg", "Dan", 103)
	local tallies = S:Tally(key)
	equal(#tallies, 2)
	equal(tallies[1].id, "gg") -- first used, first spot
	equal(tallies[1].count, 3)
	equal(tallies[1].time, 103)
	equal(table.concat(tallies[1].from, ","), "Ann,Cat,Dan")
	equal(tallies[2].id, "gratz")
	equal(tallies[2].count, 1)
	-- Stamping the same again: refused, the first stays.
	equal(S:Add(key, "gg", "Dan", 200), nil)
	tallies = S:Tally(key)
	equal(tallies[1].count, 3)
	equal(tallies[1].time, 103)
	equal(w.ns.L.STAMP_TALLY:format(w.ns.L.STAMP_GG, 3), "Hooray! x3")
end)

test("one tab per player: a friend's or your own other characters have no tab, their history stays", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.ns.SetEnabled("showAlts", false) -- alts as greyed heads is its own test
	w:share()
	-- A friend on one character, then on another.
	w:hear("H", { v = "0.3.5", c = "WARRIOR", l = 10, z = "Mulgore", a = "abc123" }, "Mainchar")
	w:hear("E", { t = "level", c = "WARRIOR", level = 10 }, "Mainchar")
	w.ns.Session.peers.Mainchar = nil -- logged off
	w:hear("H", { v = "0.3.5", c = "MAGE", l = 3, z = "Elwynn Forest", a = "abc123" }, "Altchar")
	-- Someone else, and an older client that sends no player id.
	w:hear("H", { v = "0.3.5", c = "ROGUE", l = 7, a = "fff000" }, "Stranger")
	w:hear("H", { v = "0.2.0", c = "PRIEST", l = 5 }, "Oldclient")
	local names = {}
	for _, head in ipairs(w.ns.PartyModel:Heads()) do names[head.name] = true end
	equal(names.Altchar, true)
	equal(names.Mainchar, nil) -- the same player: no second tab
	equal(names.Stranger, true)
	equal(names.Oldclient, true)
	equal(#w.ns.Store:GetFeed(true) > 0, true) -- Mainchar's level row is still there
	-- Your own other character: filed under your id, so no tab.
	w.ns.Store:SetPlayerId("Myalt", w.ns.Sharing.PlayerId())
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "Myalt", class = "MAGE", data = { level = 4 } })
	names = {}
	for _, head in ipairs(w.ns.PartyModel:Heads()) do names[head.name] = true end
	equal(names.Myalt, nil)
	-- Your hello carries your player id, the same every time.
	local id = w.ns.Sharing.PlayerId()
	equal(id, w.ns.Sharing.PlayerId())
	local sent
	for _, message in ipairs(w.sent) do if message.text:match("^1:H:") then sent = message.text end end
	equal(sent:find("a=" .. id, 1, true) ~= nil, true)
end)

test("Stamps fade: off by default; on, a card shows only stamps from the last 15 seconds", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	equal(w.ns.IsEnabled("stampFade"), false)
	equal(w.ns.StampRules.fadeSeconds, 15)
	local key = "Friend~level~12"
	local S = w.ns.Stamping
	S:Add(key, "gg", "Ann", w.now - 20)
	S:Add(key, "lol", "Bob", w.now - 5)
	equal(#S:Showing(key, w.now), 2) -- off: nothing fades
	w.ns.SetEnabled("stampFade", true)
	local showing = S:Showing(key, w.now)
	equal(#showing, 1) -- the 20 second old one has faded
	equal(showing[1].id, "lol")
	S:Add(key, "gg", "Cat", w.now) -- stamped again: back
	equal(#S:Showing(key, w.now), 2)
	equal(#S:For(key), 3) -- still all kept, only not inked
end)

test("stamps: eight words, each with an emblem; one since retired is left off the card", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	equal(#w.ns.Stamps, 8)
	for _, stamp in ipairs(w.ns.Stamps) do
		assert(stamp.id:match("^[%w_]+$"), "a plain id: " .. stamp.id)
		assert(stamp.text and stamp.icon and stamp.color, "a word, a fallback icon and a color: " .. stamp.id)
	end
	-- A card stamped before a stamp was retired (the garrison and raid marks).
	local S = w.ns.Stamping
	local list = { { id = "c_priest", from = "Ann", time = w.now }, { id = "gg", from = "Bob", time = w.now } }
	w.ns.db.stamps = w.ns.db.stamps or {}
	S:Add("Friend~level~12", "gg", "Bob", w.now)
	table.insert(S:For("Friend~level~12"), 1, list[1])
	local tallies = S:Tally("Friend~level~12")
	equal(#tallies, 1)
	equal(tallies[1].id, "gg")
	-- Nor does it count toward anyone's stamps per card: Ann may still stamp it.
	table.insert(S:For("Friend~level~12"), { id = "m_star", from = "Ann", time = w.now })
	equal(S:May("Friend~level~12", "Ann", "nice"), true)
	-- And it is cleared from what is kept.
	S:Prune(w.now)
	for _, stamp in ipairs(S:For("Friend~level~12")) do
		assert(w.ns.StampById[stamp.id], "only stamps this version has are kept")
	end
end)

test("a stamp's impact is one of KekChat's effects and sounds at random, made small", function()
	local w = Harness.new()
	local S = w.ns.Stamping
	local seen, sounds = {}, {}
	for _ = 1, 200 do
		local impact = S.Impact("gg")
		seen[impact.preset] = true
		sounds[impact.sound] = true
		equal(impact.icons[1], "Interface\\Icons\\" .. w.ns.StampById.gg.icon) -- the stamp's own image leads
		local base = w.ns.ChatEffectById[impact.effect.id]
		assert(impact.effect.size[2] < base.size[2], "smaller than KekChat's")
	end
	local presets, kinds = 0, 0
	for _ in pairs(seen) do presets = presets + 1 end
	for _ in pairs(sounds) do kinds = kinds + 1 end
	equal(presets > 1, true) -- not always the same effect
	equal(kinds > 1, true) -- nor the same sound
	for id in pairs(sounds) do
		local found = false
		for _, sound in ipairs(w.ns.StampImpact.sounds) do if sound == id then found = true end end
		equal(found, true)
	end
	for _, id in ipairs(w.ns.StampImpact.presets) do
		local found = false
		for _, preset in ipairs(w.ns.EffectPresets) do if preset.id == id then found = true end end
		assert(found, "KekChat has " .. id)
	end
end)

test("each death is its own card for stamps, named by when it happened, the same on every client", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w.ns.Collectors:Handle("PLAYER_DEAD")
	w:advance(30)
	w.ns.Collectors:Handle("PLAYER_DEAD") -- same zone, same level
	local keys = {}
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
		if entry.type == "death" then keys[#keys + 1] = w.ns.Stamping:KeyFor(entry) end
	end
	equal(#keys, 2)
	assert(keys[1] ~= keys[2], "two deaths, two cards")
	-- The moment travels with it: a friend names it the same way.
	local sent
	for _, message in ipairs(w.sent) do
		if message.text:find("t=death", 1, true) then sent = message.text end
	end
	local _, fields = w.ns.Protocol.Decode(sent)
	equal(type(fields.w), "number")
	local friend = Harness.new({ switches = { chatEcho = false } })
	friend:share()
	friend:event("CHAT_MSG_ADDON", "QuestParty", sent, "CHANNEL", "Tester-TestRealm", "", 0, 5, "QuestFriends")
	local theirs
	for _, entry in ipairs(friend.ns.Store:GetFeed(true)) do
		if entry.type == "death" then theirs = friend.ns.Stamping:KeyFor(entry) end
	end
	equal(theirs, keys[1])
end)

test("a card with a long name and quest title can still be stamped, and its stamp fits one message", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local entry = { type = "quest_complete", player = "Mcdouble Whopper", data = { quest = "Cry of the Thunderhawk and the Longest Quest Name", w = 1795125540 } }
	local key = w.ns.Stamping:KeyFor(entry)
	assert(key ~= nil, "stampable")
	equal(w.ns.Stamping:Send(entry, "wow"), true)
	local text
	for _, message in ipairs(w.sent) do
		if message.text:match("^1:T:") then text = message.text end
	end
	assert(text and #text <= w.ns.Protocol.maxLength, "fits one message")
	equal(w.ns.Stamping:For(key)[1].id, "wow") -- and it lands when it comes back
end)

test("a quest picked up, dropped and picked up again is a new card each time; a kill run keeps one", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local S = w.ns.Stamping
	local function key(kind, data) return S:KeyFor({ type = kind, player = "Friend", data = data }) end
	local first = key("quest_accepted", { quest = "Rite of Vision", w = 1000 })
	local dropped = key("quest_abandoned", { quest = "Rite of Vision", w = 1100 })
	local again = key("quest_accepted", { quest = "Rite of Vision", w = 1200 })
	assert(first ~= again, "picked up again: its own card")
	assert(dropped ~= first and dropped ~= again, "the drop is its own card")
	-- A kill run that grows keeps its name, and so its stamps.
	equal(key("xp", { mob = "Kobold", level = 9, xp = 50, w = 1000 }), key("xp", { mob = "Kobold", level = 9, xp = 120, w = 1300 }))
end)

test("stamps: a card is named the same on every client, five per player, and travels", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local S = w.ns.Stamping
	local entry = { type = "quest_complete", player = "Friend", data = { quest = "The Venture Co.", xp = 700 } }
	equal(S:KeyFor(entry), "Friend~quest_complete~The Venture Co.~") -- no w on this hand-made entry
	equal(S:KeyFor({ type = "xp", player = "Friend", data = { xp = 5, mob = "Kobold", level = 9 } }), "Friend~xp~Kobold~9") -- every card can be stamped
	equal(S:KeyFor({ type = "joined", player = "Friend", data = {} }), "Friend~joined")
	-- Yours: on the card at once, and out on the channel.
	w:ingest("quest_complete", { quest = "The Venture Co.", xp = 700 }, "Friend")
	equal(S:Send(entry, "gg"), true)
	local text
	for _, message in ipairs(w.sent) do
		if message.text:match("^1:T:") then text = message.text end
	end
	equal(text ~= nil, true)
	equal(S:For(S:KeyFor(entry))[1].id, "gg")
	-- More different stamps from you are added, up to perPlayer each.
	local per = w.ns.StampRules.perPlayer
	equal(per, 5)
	local yours = { "gg", "legend", "nice", "wow", "lol" }
	for index = 2, per do
		w:advance(30) -- past the spam limit
		equal(S:Send(entry, yours[index]), true)
	end
	equal(#S:For(S:KeyFor(entry)), per)
	-- Then you are done with this card: another is refused and not sent, and
	-- so is the same one again. Yours stay.
	w:advance(30)
	local sentBefore = #w.sent
	local ok, why = S:Send(entry, "oof")
	equal(ok, false)
	equal(why, w.ns.L.STAMP_DONE)
	equal(S:Send(entry, "legend"), false)
	equal(#w.sent, sentBefore)
	local mine = {}
	for _, stamp in ipairs(S:For(S:KeyFor(entry))) do mine[#mine + 1] = stamp.id end
	equal(table.concat(mine, ","), table.concat(yours, ","))
	equal(S:May(S:KeyFor(entry), w.ns.MyName()), false)
	-- The feed row carries them, so the panel can draw them.
	local row
	for _, built in ipairs(w.ns.ViewModel:Build("all")) do
		if built.stampKey then row = built end
	end
	equal(row.stamps[#row.stamps].id, "lol") -- the newest last
	-- From the channel: a friend's stamp lands; a muted player's and an
	-- unknown stamp do not.
	w:hear("T", { k = S:KeyFor(entry), s = "gratz" }, "Buddy")
	equal(#S:For(S:KeyFor(entry)), per + 1) -- yours and Buddy's
	-- A client that sends past the rule: only Buddy's first five show here.
	local theirs = { "gratz", "gratz", "lol", "oof", "rip", "gg", "nice" } -- one again, then six different
	for index = 2, #theirs do
		w:advance(30) -- past the spam timeout
		w:hear("T", { k = S:KeyFor(entry), s = theirs[index] }, "Buddy")
	end
	local buddy = {}
	for _, stamp in ipairs(S:For(S:KeyFor(entry))) do
		if stamp.from == "Buddy" then buddy[#buddy + 1] = stamp.id end
	end
	equal(table.concat(buddy, ","), "gratz,lol,oof,rip,gg")
	w.ns.Chat:ToggleMute("Pest")
	w:hear("T", { k = S:KeyFor(entry), s = "gratz" }, "Pest")
	w:hear("T", { k = S:KeyFor(entry), s = "typed words" }, "Buddy")
	equal(#S:For(S:KeyFor(entry)), 2 * per) -- your five and Buddy's five
	-- A stamp for a card not here yet is kept, and shows when the card comes.
	w:hear("T", { k = "Other~level~12", s = "gg" }, "Buddy")
	w:ingest("level", { level = 12 }, "Other")
	local found
	for _, built in ipairs(w.ns.ViewModel:Build("all")) do
		if built.stampKey == "Other~level~12" then found = built end
	end
	equal(found.stamps[1].from, "Buddy")
end)

test("quests you and someone else are both on are marked shared, in the Quest tab and the feed", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { questID = 7, quest = "Together" }, "Tester")
	w:ingest("quest_accepted", { questID = 7, quest = "Together" }, "Friend")
	w:ingest("quest_accepted", { questID = 8, quest = "Theirs Alone" }, "Friend")
	w:ingest("quest_accepted", { questID = 9, quest = "Mine Alone" }, "Tester")
	-- Some progress, so each quest has a card in the Quest tab.
	for _, entry in ipairs({ { 7, "Together", "Tester" }, { 7, "Together", "Friend" }, { 8, "Theirs Alone", "Friend" }, { 9, "Mine Alone", "Tester" } }) do
		w:ingest("quest_progress", { questID = entry[1], quest = entry[2], objective = "Rats", have = 1, need = 5 }, entry[3])
	end
	local function Marks(filter)
		local marks = {}
		for _, row in ipairs(w.ns.ViewModel:Build(filter)) do
			if row.quest then marks[row.kind .. ":" .. row.quest .. ":" .. tostring(row.shared)] = true end
		end
		return marks
	end
	local quest = Marks("party")
	equal(quest["tracker:Together:true"], true)
	equal(quest["tracker:Theirs Alone:nil"], true)
	equal(quest["tracker:Mine Alone:nil"], true)
	local feed = Marks("all")
	equal(feed["feed:Together:true"], true)
	equal(feed["feed:Theirs Alone:nil"], true)
	equal(w.ns.FilterById.party.label, "Quest")
end)

test("backdrops rotate among the ones the game has, each card its own slice, never stretched", function()
	local S = Harness.new().ns.Scene
	local has = function(name) return name:find("Frostfire", 1, true) ~= nil end
	equal(S:Backdrop(0, has), "_GarrMissionLocation-FrostfireRidge-Back")
	equal(S:Backdrop(1, has), "_GarrMissionLocation-FrostfireSea-Back")
	equal(S:Backdrop(4, has), "_GarrMissionLocation-FrostfireRidge-Back") -- four usable: around again
	equal(S:Backdrop(7, function() return false end), nil)
	-- A wide painting (16:1) on a card shape (8:1): the full height, a slice of the width.
	local l, r, t, b = S:Slice({ 0, 1, 0, 1 }, 4096, 256, 280, 35, 0)
	equal(t, 0) equal(b, 1)
	assert(math.abs((r - l) - 0.5) < 1e-9, "half the width shows")
	equal(l, 0)
	local l2 = S:Slice({ 0, 1, 0, 1 }, 4096, 256, 280, 35, 3)
	assert(math.abs(l2 - 0.5) < 1e-9, "another card, another slice")
	-- A tall painting (1:1) on a card: the full width, a band from the middle.
	l, r, t, b = S:Slice({ 0, 1, 0, 1 }, 512, 512, 280, 35, 0)
	equal(l, 0) equal(r, 1)
	assert(math.abs((b - t) - 0.125) < 1e-9 and math.abs(t - 0.4375) < 1e-9, "a middle band")
end)

test("health and power drawn live from the game: you and your game group have a unit, friends elsewhere do not", function()
	local w = Harness.new()
	w.env.GetNumGroupMembers = function() return 1 end
	w.env.IsInRaid = function() return false end
	w.env.UnitExists = function(unit) return unit == "party1" or unit == "player" end
	local realName = w.env.UnitName
	w.env.UnitName = function(unit)
		if unit == "party1" then return "Buddy" end
		return realName(unit)
	end
	w.ns.Group:Refresh()
	equal(w.ns.Group:Unit(w.ns.MyName()), "player")
	equal(w.ns.Group:Unit("Buddy"), "party1")
	equal(w.ns.Group:Unit("Faraway"), nil)
	equal(w.ns.Group:Has("Buddy"), true)
end)

test("vitals: health and power in 5% steps, and a sliver still shows", function()
	local Vitals = Harness.new().ns.Vitals
	equal(Vitals.Percent(73, 100, 5), 70)
	equal(Vitals.Percent(100, 100, 5), 100)
	equal(Vitals.Percent(1, 1000, 5), 5) -- alive is never 0%
	equal(Vitals.Percent(0, 100, 5), 0)
	equal(Vitals.Percent(5, 0, 5), nil)
	local debounce = Vitals.NewDebounce(1.5)
	local a, b, c = { h = 100, p = 50, t = "MANA" }, { h = 90, p = 50, t = "MANA" }, { h = 80, p = 45, t = "MANA" }
	equal(debounce:Offer(a, 10), a) -- the first goes at once
	equal(debounce:Offer(b, 10.5), nil) -- too soon: held
	equal(debounce:Offer(c, 11), nil) -- the latest replaces it
	equal(debounce:DueAt(), 11.5)
	equal(debounce:Due(11.4), nil)
	equal(debounce:Due(11.5), c)
	equal(debounce:Offer({ h = 80, p = 45, t = "MANA" }, 20), nil) -- nothing new
end)

test("vitals go out stepped and debounced, and show on a friend's bar", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local function Vitals()
		local list = {}
		for _, message in ipairs(w.sent) do
			local h = message.text:match("^1:V:.-h=#(%d+)")
			if h then list[#list + 1] = tonumber(h) end
		end
		return list
	end
	local before = #Vitals()
	-- A fight: health drops many times in a second.
	for _, health in ipairs({ 97, 91, 84, 76, 68 }) do
		w.health = health
		w:event("UNIT_HEALTH", "player")
		w:advance(0.2)
	end
	w:advance(2)
	local sent = Vitals()
	assert(#sent - before <= 2, "a burst is one message now and one when the wait is up, not " .. (#sent - before))
	equal(sent[#sent], 65) -- the last word is the latest, in 5% steps
	-- A friend's health and power arrive and fill their bar's thin bars.
	w:hear("H", { v = "0.3.5", c = "WARRIOR", l = 7, z = "Mulgore" }, "Friend")
	w:hear("V", { h = 40, p = 75, t = "RAGE" }, "Friend")
	local friend
	for _, bar in ipairs(w.ns.ViewModel:PartyBars()) do
		if bar.name == "Friend" then friend = bar end
	end
	equal(friend.health, 40)
	equal(friend.power, 75)
	equal(friend.powerType, "RAGE")
	-- Your own bar has yours, from the game.
	equal(w.ns.ViewModel:PartyBars()[1].health, 65)
end)

test("your game group's members are marked: their rows and their XP bars, by full name", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("H", { v = "0.3.5", c = "SHAMAN", l = 12, x = 100, m = 1000 }, "Mcdouble Whopper")
	w:hear("H", { v = "0.3.5", c = "MAGE", l = 9, x = 100, m = 1000 }, "Stranger")
	w:ingest("level", { level = 12 }, "Mcdouble Whopper")
	w:ingest("level", { level = 9 }, "Stranger")
	equal(w.ns.Group:Has("Mcdouble Whopper"), false)
	-- They join your party (the game gives the name and surname apart).
	local changed = 0
	w.ns.Bus:On("GROUP_CHANGED", function() changed = changed + 1 end)
	w.group = { "Mcdouble Whopper" }
	w:event("GROUP_ROSTER_UPDATE")
	equal(changed, 1)
	equal(w.ns.Group:Has("Mcdouble Whopper"), true)
	local marks = {}
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do marks[row.player] = row.grouped end
	equal(marks["Mcdouble Whopper"], true)
	equal(marks.Stranger, nil)
	local bars = {}
	for _, bar in ipairs(w.ns.ViewModel:PartyBars()) do bars[bar.name] = bar.grouped end
	equal(bars["Mcdouble Whopper"], true)
	equal(bars.Stranger, nil)
	-- They leave the group.
	w.group = {}
	w:event("GROUP_ROSTER_UPDATE")
	equal(w.ns.Group:Has("Mcdouble Whopper"), false)
end)

test("Health and power can be switched off; the bars' numbers are still kept", function()
	local w = Harness.new()
	equal(w.ns.IsEnabled("showVitals"), true) -- on by default
	w.ns.SetEnabled("showVitals", false)
	equal(w.ns.IsEnabled("showVitals"), false)
	w:share()
	w:hear("V", { h = 40, p = 75, t = "RAGE" }, "Friend")
	equal(w.ns.Session.peers.Friend.vitals.h, 40) -- still known, only not drawn
end)

test("vitals: a hidden value keeps the last, and a hello carries them", function()
	local w = Harness.new()
	w:share()
	w.health = "<secret>"
	w:event("UNIT_HEALTH", "player")
	equal(w.ns.VitalsCollector.reading.h, 100)
	w:hear("H", { v = "0.3.5", c = "MAGE", l = 9, h = 55, p = 20, t = "MANA" }, "Newcomer")
	equal(w.ns.Session.peers.Newcomer.vitals.h, 55)
end)

test("your own events always show in the feed, and read exactly like a friend's", function()
	-- Your own play, every kind of event, with the old Include self saved off:
	-- nothing of yours is ever filtered out.
	local w = Harness.new({ switches = { showSelf = false } })
	w.level, w.xp = 6, 900
	w:share()
	w:event("PLAYER_LOGIN")
	local own = {}
	w.ns.Bus:On("ENTRY_RECEIVED", function(entry)
		if entry.player == "Tester" then own[#own + 1] = entry end
	end)
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Prairie Wolf dies, you gain 51 experience.")
	w.xp = 951
	w:event("PLAYER_XP_UPDATE", "player")
	w:advance(1)
	w.level, w.xp, w.xpMax = 7, 26, 1300
	w:event("PLAYER_XP_UPDATE", "player")
	w:event("PLAYER_LEVEL_UP", "<secret>") -- in combat: the game hides the level
	w:advance(1)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Red Cloud Mesa")
	w:advance(2) -- a discovery waits a moment for its XP
	w.ns.Collectors:Handle("CHAT_MSG_SKILL", "Your skill in First Aid has increased to 12.")
	w.ns.Collectors:Handle("ACHIEVEMENT_EARNED", 6)
	w.ns.Collectors:Handle("PLAYER_DEAD")
	w:advance(1)
	local kinds = {}
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
		equal(entry.player, "Tester")
		kinds[entry.type] = true
	end
	for _, kind in ipairs({ "xp", "level", "discovery", "skill", "achievement", "death" }) do
		assert(kinds[kind], "your own " .. kind .. " is missing from the feed")
	end
	-- The same events from a friend: each row reads the same, name aside.
	local friend = Harness.new()
	friend:share()
	for _, entry in ipairs(own) do
		friend.ns.Bus:Fire("ENTRY_RECEIVED", { type = entry.type, player = "Friend", class = entry.class, data = entry.data, time = entry.time })
	end
	local mine, theirs = w.ns.ViewModel:Build("all"), friend.ns.ViewModel:Build("all")
	local function Rows(rows)
		local list = {}
		for _, row in ipairs(rows) do
			if row.kind == "feed" then
				list[#list + 1] = row.title .. " | " .. (row.summary or ""):gsub("Tester", "<who>"):gsub("Friend", "<who>")
			end
		end
		return list
	end
	mine, theirs = Rows(mine), Rows(theirs)
	equal(#mine, #theirs)
	for index = 1, #mine do
		equal(mine[index], theirs[index])
	end
end)

test("everything of yours shows, your quests from the log at login, and goes out", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w:quest(1, 3)
	local outgoing = 0
	w.ns.Bus:On("ENTRY_OUTGOING", function() outgoing = outgoing + 1 end)
	w:event("PLAYER_LOGIN")
	equal(#w.ns.Store:GetCards("quest"), 1)
	equal(w.ns.Store:GetCards("quest")[1].player, "Tester")
	w:quest(2, 3)
	w:event("QUEST_LOG_UPDATE")
	w:event("UI_INFO_MESSAGE", 286, "Kobolds slain: 2/3")
	equal(w.ns.Store:GetCards("quest")[1].data.objectives["Kobolds slain"].have, 2)
	w.level = 21
	w:event("PLAYER_LEVEL_UP", 21)
	equal(outgoing > 0, true) -- sent, as anyone's
	-- Everything else of yours shows too: a level.
	local kinds = {}
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do kinds[entry.type] = true end
	equal(kinds.level, true)
end)

test("your own rows carry your full name (first and surname), and old first-name rows move to it", function()
	local w = Harness.new()
	w:share()
	-- Saved before the surname was used: under the first name alone.
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "quest_progress", player = "Tester", class = "MAGE", data = { questID = 9, quest = "Old", objective = "Rats", have = 1, need = 2 } })
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "quest_progress", player = "Friend", class = "MAGE", data = { questID = 9, quest = "Old", objective = "Rats", have = 1, need = 2 } })
	w.ns.Stats:Book().Tester = w.ns.Stats:Book().Tester or { [1] = { quests = 2 } }
	w.env.UnitName = function() return "Tester", "Bones" end
	equal(w.ns.MyName(), "Tester Bones")
	w.ns.Bus:Fire("READY")
	local players = {}
	for _, card in ipairs(w.ns.Store:GetCards("quest")) do players[#players + 1] = card.player end
	table.sort(players)
	equal(table.concat(players, ","), "Friend,Tester Bones")
	equal(w.ns.Stats:Book().Tester, nil)
	equal(w.ns.Stats:Book()["Tester Bones"] ~= nil, true)
	-- New events of yours carry the full name too.
	w.ns.Collectors:Handle("PLAYER_DEAD")
	equal(w.ns.Store:GetFeed(true)[1].player, "Tester Bones")
end)

test("hydration refreshes saved counts and preserves start time and kill tallies", function()
	local w = Harness.new()
	w:share() -- the channel is the feed: your own news comes back on it
	w.ns.SetEnabled("kills", true)
	w:ingest("quest_accepted", { questID = 1, quest = "A Quest" })
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Kobolds slain", objectiveIndex = 1, have = 3, need = 5 })
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Old duplicate line", have = 2, need = 5 })
	w:ingest("kill", { questID = 1, quest = "A Quest", xp = 26 })
	local created = w.ns.Store:GetCards("quest")[1].created
	local reloaded = Harness.new(w.ns.db, w.ns.charDb, false, w.now + 24 * 60 * 60)
	reloaded:quest(1, 5)
	reloaded:share() -- how the quest stands goes out, and comes back to refresh the card
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
	w:share() -- the channel is the feed: your own news comes back on it
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Kobolds slain", have = 2, need = 3 })
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded.quests[1] = { questID = 1, title = "A Quest" }
	reloaded:share()
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
	w:ingest("quest_progress", { questID = 1, quest = "A Quest", objective = "Ribs", objectiveIndex = 2, have = 2, need = 5 })
	local reloaded = Harness.new(w.ns.db, w.ns.charDb)
	reloaded:quest(3, 3)
	reloaded.quests[1].objectives[2] = { text = "<secret>", numFulfilled = 2, numRequired = 5 }
	reloaded:share()
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	w:share() -- the channel is the feed: your own news comes back on it
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
	equal(#w.ns.Store:GetFeed(true), 0) -- no channel, no feed: yours comes back on it
	w.env.SlashCmdList.QUESTPARTY("link Friend")
	equal(w.ns.Session.Link, nil)
	equal(w.popup, nil)
	equal(#w.sent, 0)
end)

test("the channel's name in the title is shown by default, and can be switched off for screenshots", function()
	local w = Harness.new()
	equal(w.ns.SettingById.titleChannel.default, true)
	equal(w.ns.IsEnabled("titleChannel"), true)
	w.ns.SetEnabled("titleChannel", false)
	equal(w.ns.IsEnabled("titleChannel"), false)
end)

test("dev mode is off by default, in every install, until /qp debug on", function()
	local w = Harness.new()
	equal(w.ns.IsDebug(), false)
	equal(w.ns.db.debug, false)
	w.env.SlashCmdList.QUESTPARTY("dev on")
	equal(w.ns.IsDebug(), true)
	w.env.SlashCmdList.QUESTPARTY("dev off")
	equal(w.ns.IsDebug(), false)
end)

test("debug command enables dev mode, persists, and stops a dev run when disabled", function()
	local w = Harness.new()
	w.env.SlashCmdList.QUESTPARTY("dev party 2")
	equal(w.ns.Dev.running, false) -- dev mode needs debug
	w.env.SlashCmdList.QUESTPARTY("debug on")
	equal(w.ns.IsDebug(), true)
	w.ns.Sharing.loopback = true
	w.env.SlashCmdList.QUESTPARTY("dev party 2 7 10")
	equal(w.ns.Dev.running, true)
	local restored = Harness.new(w.ns.db, w.ns.charDb)
	equal(restored.ns.IsDebug(), true)
	w.env.SlashCmdList.QUESTPARTY("debug off")
	equal(w.ns.IsDebug(), false)
	equal(w.ns.Dev.running, false)
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
	for _, name in ipairs({ "", "   ", "123", "two words", string.rep("a", 31), "name|cffff00", "qp-party", "quest_friends", "café" }) do
		equal(w.ns.Session:Connect(name), false)
	end
	equal(#w.joins, 0)
	equal(w.ns.db.connection.name, "")
	equal(w.ns.db.connection.enabled, false)
end)

test("a channel name is letters and numbers only: typing anything else takes it out", function()
	local w = Harness.new()
	equal(w.ns.CleanChannelName("Quest Friends-2!"), "QuestFriends2")
	equal(w.ns.CleanChannelName(string.rep("ab", 20)), string.rep("ab", 15))
	equal(w.ns.ValidChannelName("QuestFriends2"), true)
	equal(w.ns.ValidChannelName("2024"), false)
	equal(w.ns.ValidChannelName("qp-party"), false)
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

test("every message is sent once and counted, whatever the game answers: the channel is the truth", function()
	local w = Harness.new()
	w:share()
	local sent = w.ns.Sharing.sent
	w.sendResult = w.env.Enum.SendAddonMessageResult.ChannelThrottle
	equal(w.ns.Chat:Send({ 134071 }, "gz"), true)
	local before = #w.sent
	w:advance(5)
	equal(#w.sent, before) -- never sent again
	equal(w.ns.Sharing.sent, sent + 1) -- counted as sent
	equal(#chatRows(w), 1) -- and back on the channel, read as yours
	-- What comes after it goes out too: nothing waits behind it.
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Red Cloud Mesa")
	w:advance(2) -- a discovery waits a moment for its XP
	local kinds = {}
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do kinds[entry.type] = true end
	equal(kinds.discovery, true)
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

test("location: every update says where it happened, and each player's last known spot is kept", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local spot = { 0.5234, 0.3011 }
	w.env.C_Map = {
		GetBestMapForUnit = function() return 1413 end,
		GetPlayerMapPosition = function() return { GetXY = function() return spot[1], spot[2] end } end,
		GetMapInfo = function(map) return map == 1413 and { name = "The Barrens" } or nil end,
	}
	w:share()
	-- The hello says where you are.
	local hello = sentOfKind(w, "H")
	equal(hello[#hello].fields.wm, 1413)
	equal(hello[#hello].fields.wx, 523)
	equal(hello[#hello].fields.wy, 301)
	-- An update says where it happened, and its row keeps it.
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Red Cloud Mesa")
	w:advance(2) -- a discovery waits a moment for its XP
	local sent = sentOfKind(w, "E")
	equal(sent[#sent].fields.wm, 1413)
	local row
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
		if entry.type == "discovery" then row = entry end
	end
	equal(w.ns.Location.Describe(w.ns.Location.Read(row.data)), "The Barrens (52, 30)")
	-- A friend's update moves their spot; in a dungeon there is a map, no spot.
	w:hear("E", { t = "death", zone = "The Barrens", level = 13, wm = 1413, wx = 610, wy = 220 }, "Friend")
	local friend
	for _, member in ipairs(w.ns.Store:GetMembers()) do
		if member.name == "Friend" then friend = member end
	end
	equal(friend.where.m, 1413)
	equal(friend.where.x, 0.61)
	equal(w.ns.Location.Read({ wm = 1413 }).x, nil)
	equal(w.ns.Location.Read({ wm = "evil" }), nil)
	equal(w.ns.Location.Read({ wm = 1413, wx = 5000, wy = 1 }).x, nil) -- off the map: no spot
	-- Pretend players say nothing of where: they are not where you are.
	w.ns.Sharing:SendVirtual({ name = "Pretend", class = "MAGE" }, "discovery", { zone = "Elsewhere" })
	sent = sentOfKind(w, "E")
	equal(sent[#sent].fields.wm, nil)
end)

test("alts: with Show alts, a player's other characters stay as greyed heads after everyone; off, one head each", function()
	local w = Harness.new()
	w:share()
	-- Buddy's main is here; his alt and your own alt were seen before.
	w:hear("H", { c = "MAGE", l = 20, v = "0.3.8", a = "b0b0b0" }, "Buddy")
	w:hear("H", { c = "ROGUE", l = 9, v = "0.3.8", a = "b0b0b0" }, "Buddyalt")
	w:hear("H", { c = "DRUID", l = 7, v = "0.3.8", a = w.ns.Sharing.PlayerId() }, "Myalt")
	w:hear("H", { c = "PRIEST", l = 12, v = "0.3.8", a = "c0c0c0" }, "Gone")
	for _, name in ipairs({ "Buddyalt", "Myalt", "Gone" }) do w.ns.Session.peers[name] = nil end -- they left
	local function Names()
		local list = {}
		for _, head in ipairs(w.ns.PartyModel:Heads()) do
			list[#list + 1] = head.name .. (head.alt and "(alt)" or "") .. (head.here and "" or "-")
		end
		return table.concat(list, " ")
	end
	equal(Names(), w.ns.MyName() .. " Buddy Gone- Buddyalt(alt)- Myalt(alt)-")
	w.ns.SetEnabled("showAlts", false)
	equal(Names(), w.ns.MyName() .. " Buddy Gone-")
end)

test("AFK: you going away is said at once; a friend away keeps their bar, marked, and back clears it", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	-- You: the game's flag goes up, a presence says so.
	local afk = true
	w.env.UnitIsAFK = function() return afk end
	w.ns.Away:Check()
	local sent = sentOfKind(w, "P")
	equal(sent[#sent].fields.af, 1)
	local mine
	for _, bar in ipairs(w.ns.ViewModel:PartyBars()) do if bar.name == w.ns.MyName() then mine = bar end end
	equal(mine.afk, true)
	afk = false
	w.ns.Away:Check()
	sent = sentOfKind(w, "P")
	equal(sent[#sent].fields.af, nil) -- back: no af
	-- A friend: away in a presence, still away after an update, back in the next presence.
	local function Bar(name)
		for _, bar in ipairs(w.ns.ViewModel:PartyBars()) do if bar.name == name then return bar end end
	end
	w:hear("H", { c = "MAGE", l = 20, v = "0.3.8" }, "Buddy")
	equal(Bar("Buddy").afk, nil)
	w:hear("P", { c = "MAGE", l = 20, v = "0.3.8", af = 1 }, "Buddy")
	equal(Bar("Buddy").afk, true)
	w:hear("E", { t = "level", c = "MAGE", level = 21 }, "Buddy")
	equal(Bar("Buddy").afk, true) -- an update says nothing of it
	w:hear("P", { c = "MAGE", l = 21, v = "0.3.8" }, "Buddy")
	equal(Bar("Buddy").afk, nil)
	-- Gone is not away: no bar at all.
	w.ns.Session.peers.Buddy = nil
	equal(Bar("Buddy"), nil)
end)

test("stats tracker: each number reads as its kind says (data-driven formatters)", function()
	local w = Harness.new()
	local T = w.ns.TrackerText
	equal(T("k", 1234), "1,234")
	equal(T("x", 2450), "2,450 XP")
	equal(T("ta", 59), "0m")
	equal(T("ta", 3 * 3600 + 12 * 60), "3h 12m")
	equal(T("ta", 2 * 86400 + 5 * 3600), "2d 5h")
	equal(T("mg", 900), "900 yd")
	equal(T("mg", 3520), "2.0 mi")
	equal(T("gi", 123456), "12g 34s 56c")
	equal(T("go", 250), "2s 50c")
	equal(T("go", 7), "7c")
	-- Every stat has a known category and kind.
	local categories = {}
	for _, category in ipairs(w.ns.TrackerCategories) do categories[category.id] = true end
	for _, stat in ipairs(w.ns.TrackerStats) do
		assert(categories[stat.category], stat.id .. " has a category")
		assert(w.ns.TrackerFormat[stat.type], stat.id .. " has a format")
	end
end)

test("stats tracker: the game's played times beside ours, asked quietly, kept up by the clock", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local T, me = w.ns.Tracker, w.ns.MyName()
	-- Asked with the chat frames that print it not listening, then listening again.
	local chat, asked = { on = true }, false
	function chat:UnregisterEvent() self.on = false end
	function chat:RegisterEvent() self.on = true end
	w.env.GetFramesRegisteredForEvent = function() return chat end
	w.env.RequestTimePlayed = function() asked = chat.on == false end
	T:AskPlayed()
	equal(asked, true)
	T:Played(3600 * 50, 600)
	equal(chat.on, true)
	-- All time shows the game's; today does not.
	local function Row(period, label)
		for _, section in ipairs(T:View(me, period).sections) do
			for _, row in ipairs(section.rows) do if row.label == label then return row.text end end
		end
	end
	equal(Row("all", w.ns.L.TRACK_PLAYED_GAME), w.ns.TrackerText("gp", 3600 * 50))
	equal(Row("today", w.ns.L.TRACK_PLAYED_GAME), nil)
	-- Between asks, the clock keeps them current.
	T:Tick()
	equal(w.ns.db.tracker[me].game.gl, 600 + w.ns.TrackerRules.clock)
	-- Compared: the game's played time beside ours (active and AFK, added up).
	local function Compare(label)
		for _, section in ipairs(T:View(me, "all").sections) do
			for _, row in ipairs(section.rows) do if row.label == label then return row.compare, section.columns end end
		end
	end
	local ours, columns = Compare(w.ns.L.TRACK_PLAYED_GAME)
	equal(ours, w.ns.TrackerText("ta", (w.ns.db.tracker[me].total.ta or 0) + (w.ns.db.tracker[me].total.tk or 0)))
	equal(columns[1], w.ns.L.TRACK_COL_WOW)
end)

test("stats tracker: counts from the feed for everyone heard, yours measured, sparse, separate from Fuel", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("E", { t = "xp", c = "MAGE", xp = 300, gains = 3, mob = "Kobold", level = 9, currentXP = 300, maxXP = 1000 }, "Friend")
	w:hear("E", { t = "quest_complete", c = "MAGE", quest = "Rite", xp = 500 }, "Friend")
	w:hear("E", { t = "death", c = "MAGE", zone = "The Barrens", level = 9 }, "Friend")
	local view = w.ns.Tracker:View("Friend", "all")
	local found = {}
	for _, section in ipairs(view.sections) do
		for _, row in ipairs(section.rows) do found[row.label] = row.text end
	end
	equal(found[w.ns.L.TRACK_KILLS], "3")
	equal(found[w.ns.L.TRACK_KILL_XP], "300 XP")
	equal(found[w.ns.L.TRACK_QUESTS_DONE], "1")
	equal(found[w.ns.L.TRACK_DEATHS], "1")
	equal(found[w.ns.L.TRACK_JUMPS], nil) -- nothing happened: not stored, not shown
	equal(w.ns.db.tracker.Friend.total.j, nil)
	-- Yours, measured: jumps, time, money, a kill by creature id.
	local me = w.ns.MyName()
	w.ns.Tracker:Jumped()
	w.ns.Tracker:Tick()
	w.env.GetMoney = function() return 1000 end
	w.ns.Tracker:Money()
	w.env.GetMoney = function() return 6000 end
	w.ns.Tracker:Money()
	w.ns.Tracker:Kill(w.ns.Tracker.NpcId("Creature-0-1-0-1-3098-0000ABCDEF"))
	w.ns.Tracker:NameKills("Scorpid Worker", 1)
	local mine = w.ns.db.tracker[me]
	equal(mine.total.j, 1)
	equal(mine.total.ta, w.ns.TrackerRules.clock)
	equal(mine.total.gi, 5000)
	equal(mine.mobs[3098].n, "Scorpid Worker")
	equal(mine.mobs[3098].k, 1)
	equal(w.ns.Tracker.NpcId("Player-1-0ABC"), nil)
	-- Dev mode's pretend players are never counted.
	w.ns.Tracker:Count({ type = "death", player = "Pretend", data = {}, emulated = true })
	equal(w.ns.db.tracker.Pretend, nil)
end)

test("stats tracker: old days fold into months and months into years; totals never change", function()
	local w = Harness.new()
	equal(select(1, w.ns.Tracker.YearMonth(0)), 1970)
	local year, month = w.ns.Tracker.YearMonth(20412) -- 2025-11-21
	equal(year, 2025)
	equal(month, 11)
	local book = w.ns.Tracker:Book("Friend")
	local now = 20412 * 86400
	w.ns.Tracker:Add("Friend", "k", 5, now)
	w.ns.Tracker:Add("Friend", "k", 7, now - 100 * 86400) -- past the days kept
	w.ns.Tracker:Add("Friend", "k", 9, now - 900 * 86400) -- past the months kept
	w.ns.Tracker:Rollup(now)
	local days, months, years = 0, 0, 0
	for _ in pairs(book.days) do days = days + 1 end
	for _ in pairs(book.months) do months = months + 1 end
	for _ in pairs(book.years) do years = years + 1 end
	equal(days, 1)
	equal(months, 1)
	equal(years, 1)
	equal(book.total.k, 21)
	equal(w.ns.Tracker:Period("Friend", "today", now).k, 5)
end)

test("opacity: the slider sets it, and On hover leaves it, makes it solid, or fainter", function()
	local w = Harness.new()
	local O = w.ns.Opacity
	equal(O.Now(false), 1) -- out of the box: solid, nothing changes
	equal(O.Now(true), 1)
	w.ns.SetSlider("opacity", 60)
	equal(O.Now(false), 0.6)
	equal(O.Now(true), 0.6) -- On hover off: the same either way
	w.ns.SetSlider("hoverOpacity", 1)
	equal(O.Now(true), 1) -- solid on hover
	equal(O.Now(false), 0.6)
	w.ns.SetSlider("hoverOpacity", 2)
	equal(O.Now(true), 0.3) -- fainter on hover: half of it
	w.ns.SetSlider("opacity", 30)
	equal(O.Now(true), 0.2) -- never fainter than 20%, the slider's own bottom
	equal(O.least, w.ns.SliderById.opacity.min / 100)
	equal(w.ns.SetSlider("opacity", 5), 20) -- held to the slider's range
end)

test("where you are goes out alone after a quiet minute, only if you moved; a friend's pin follows", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local spot = { 0.50, 0.30 }
	w.env.C_Map = {
		GetBestMapForUnit = function() return 1413 end,
		GetPlayerMapPosition = function() return { GetXY = function() return spot[1], spot[2] end } end,
	}
	w:share() -- the hello says where you are
	local function Alone() return #sentOfKind(w, "L") end
	w.ns.Sharing.SendWhere()
	equal(Alone(), 0) -- the hello just said it
	w:advance(61)
	w.ns.Sharing.SendWhere()
	equal(Alone(), 0) -- a minute on, but you have not moved
	spot[1] = 0.55
	w.ns.Sharing.SendWhere()
	equal(Alone(), 1) -- moved: it goes
	local sent = sentOfKind(w, "L")
	equal(sent[1].fields.wx, 550)
	spot[1] = 0.60
	w:advance(30)
	w.ns.Sharing.SendWhere()
	equal(Alone(), 1) -- not a minute yet
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Red Cloud Mesa") -- an update says it
	w:advance(2) -- a discovery waits a moment for its XP
	w:advance(45)
	w.ns.Sharing.SendWhere()
	equal(Alone(), 1) -- the update reset the minute
	-- Share location off: nothing of where goes, with updates or alone.
	w.ns.SetEnabled("shareLocation", false)
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 368, "Discovered: Camp Taurajo")
	w:advance(2) -- a discovery waits a moment for its XP
	sent = sentOfKind(w, "E")
	equal(sent[#sent].fields.wm, nil)
	spot[1] = 0.9
	w:advance(120)
	w.ns.Sharing.SendWhere()
	equal(Alone(), 1)
	w.ns.SetEnabled("shareLocation", true)
	-- A friend's: their last known position moves.
	w:hear("H", { c = "MAGE", l = 20, v = "0.3.8", wm = 1413, wx = 100, wy = 100 }, "Buddy")
	w:hear("L", { wm = 1413, wx = 700, wy = 200 }, "Buddy")
	local buddy
	for _, member in ipairs(w.ns.Store:GetMembers()) do if member.name == "Buddy" then buddy = member end end
	equal(buddy.where.x, 0.7)
end)

test("recent channels: the last five used, newest first, one click to switch back", function()
	local w = Harness.new()
	local session = w.ns.Session
	equal(session:Connect("QuestFriends"), true)
	equal(#session:RecentChannels(), 0) -- the one you are on is not offered
	equal(session:SwitchTo("OtherCrew"), true) -- leaves QuestFriends first
	equal(w.ns.db.connection.name, "OtherCrew")
	equal(table.concat(session:RecentChannels(), ","), "QuestFriends")
	session:SwitchTo("questfriends") -- the same channel, any case
	equal(table.concat(w.ns.db.recentChannels, ","), "questfriends,OtherCrew")
	for _, name in ipairs({ "A1", "B2", "C3", "D4" }) do session:SwitchTo(name) end
	equal(#w.ns.db.recentChannels, 5)
	equal(w.ns.db.recentChannels[1], "D4")
	equal(w.ns.db.recentChannels[5], "questfriends") -- OtherCrew, the oldest past five, is dropped
	session:Forget("B2")
	equal(#w.ns.db.recentChannels, 4)
	equal(Harness.new(w.ns.db).ns.db.recentChannels[1], "D4") -- kept across a reload
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
	equal(w.ns.version, "0.1.0") -- the TOC's version, also shown in Options
	equal(hellos[1].fields.v, w.ns.version)
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

-- ========= Resolving what arrives ===========================================
test("every entry sent carries the sender's plain summary of it", function()
	local w = Harness.new()
	w:share()
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	local _, fields = w.ns.Protocol.Decode(w.sent[#w.sent].text)
	equal(fields.t, "level")
	equal(fields.s, "DING!! Reached Level 21!")
	w.ns.Collectors:Handle("PLAYER_DEAD")
	_, fields = w.ns.Protocol.Decode(w.sent[#w.sent].text)
	equal(fields.s, "Died in Elwynn Forest") -- no color codes on the wire
end)

test("an entry too long with its summary is sent without it", function()
	local w = Harness.new()
	w:share()
	local long = string.rep("Very Long Quest Name ", 6)
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "quest_complete", data = { quest = long, xp = 875 } })
	local _, fields = w.ns.Protocol.Decode(w.sent[#w.sent].text)
	equal(fields.t, "quest_complete")
	equal(fields.quest, long)
	equal(fields.s, nil)
end)

test("a type this version does not know shows as a generic card with the sender's summary", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("E", { t = "pet_battle_won", c = "HUNTER", s = "Won a pet battle against Squirrel", pet = "Squirrel" }, "Newer Friend")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].type, "unknown")
	equal(feed[1].data.kind, "pet_battle_won")
	local row = w.ns.ViewModel:Build("all")[1]
	equal(row.title, "Won a pet battle against Squirrel")
	equal(row.summary, nil) -- who it was is on hover (name)
	equal(#w.ns.ViewModel:Build("xp"), 0) -- the All tab only
	w.ns.SetEnabled("otherUpdates", false)
	equal(#w.ns.Store:GetFeed(true), 0) -- and it has a switch
end)

test("with no summary, the generic card guesses from the type's name", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("E", { t = "pet_battle_won", c = "HUNTER" }, "Newer Friend")
	equal(w.ns.ViewModel:Build("all")[1].title, "Pet battle won")
end)

test("a known type missing what its card needs falls back to the sender's summary", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	-- A newer version that changed the xp entry's fields, say.
	w:hear("E", { t = "xp", c = "WARRIOR", s = "+79 XP", gain = 79 }, "Newer Friend")
	equal(w.ns.ViewModel:Build("all")[1].title, "+79 XP")
	-- An older sender's entry with what it needs resolves as it always did.
	w:hear("E", { t = "level", c = "WARRIOR", level = 15 }, "Tombert Roams")
	equal(w.ns.Store:GetFeed(true)[1].type, "level")
	equal(w.ns.ViewModel:Build("all")[2].title, "DING!! Reached Level 15!")
	-- And without a summary, an unreadable known type is dropped, as before.
	w:hear("E", { t = "xp", c = "WARRIOR", gain = 79 }, "Old Friend")
	equal(#w.ns.Store:GetFeed(true), 2)
end)

test("messages that are not for us are ignored", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "level", c = "PRIEST", level = 12 }, "Friend", 9) -- another channel
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
	equal(#sentOfKind(w, "A"), before + 1) -- answered straight away
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
	for level = 1, 250 do w:hear("E", { t = "level", c = "ROGUE", level = level }, "Veteran") end
	equal(#log, 200) -- the newest are kept
end)

test("our own messages coming back from the server are counted, and read as ours", function()
	local w = Harness.new()
	w:share()
	local echoed, received = w.ns.Sharing.echoed, w.ns.Sharing.received
	w.ns.Bus:Fire("ENTRY_OUTGOING", { type = "level", data = { level = 21 } })
	equal(w.ns.Sharing.echoed, echoed + 1) -- it came back
	equal(w.ns.Sharing.received, received) -- not someone else's
	equal(w.ns.Session:Count(), 0) -- you are not your own peer
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].player, "Tester") -- the channel is the feed: yours, read as anyone's
	assert(w.ns.Sharing:Status():find("came back", 1, true), w.ns.Sharing:Status())
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

test("someone else's emulator does not put pretend players in your panel", function()
	local w = Harness.new()
	w:share()
	w:hear("E", { t = "level", c = "MAGE", as = "Jaina", level = 23 }, "Friend")
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("XP from kills goes out in batches, one message per creature, so grinding does not flood the channel", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w.xp = 100
	w:event("PLAYER_LOGIN")
	local before = #sentOfKind(w, "E")
	for _ = 1, 3 do
		w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Wandering Spirit dies, you gain 81 experience.")
		w.xp = w.xp + 81
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(3)
	end
	equal(#sentOfKind(w, "E"), before) -- still killing: nothing sent yet
	equal(#w.ns.Store:GetFeed(true), 0) -- nor in your feed: you see what friends see
	w:advance(w.ns.Timing.killQuietSeconds)
	equal(#w.ns.Store:GetFeed(true), 1) -- the batch, back from the channel
	local entries = sentOfKind(w, "E")
	equal(#entries, before + 1)
	local fields = entries[#entries].fields
	equal(fields.xp, 243)
	equal(fields.gains, 3)
	equal(fields.currentXP, 343)
	-- A friend's batch counts as every kill in it.
	w.ns.SetDebug(true)
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 150, gains = 2, level = 13, currentXP = 5400, maxXP = 11400, mob = "Murloc" }, "Friend")
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 75, level = 13, currentXP = 5475, maxXP = 11400, mob = "Murloc" }, "Friend")
	equal(w.ns.Stats:Total("Friend").kills, 3)
	local row
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
		if entry.player == "Friend" then row = entry end
	end
	equal(row.data.gains, 3)
	equal(row.data.xp, 225)
end)

test("a long grind still sends its kills at the longest wait", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w.xp = 100
	w:event("PLAYER_LOGIN")
	local before = #sentOfKind(w, "E")
	local timing = w.ns.Timing
	local kills = math.ceil(timing.killLongestSeconds / 5) + 1
	for _ = 1, kills do -- a kill every 5 seconds, never quiet for long
		w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", "Vale Moth dies, you gain 26 experience.")
		w.xp = w.xp + 26
		w:event("PLAYER_XP_UPDATE", "player")
		w:advance(5)
	end
	assert(#sentOfKind(w, "E") > before, "sent before the grind ended")
end)

-- ========= Test runs (Settings, debug) =====================================
test("a test run: choose a scenario, GO starts it, Clear on go wipes first, STOP stops it", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local runner = w.ns.ScenarioRunner
	equal(runner:Go(false), false) -- debug mode only
	w.ns.SetDebug(true)
	equal(runner:Selected().id, "trio")
	runner:Select("sharedQuest")
	runner:Select("no such scenario")
	equal(w.ns.charDb.scenario, "sharedQuest")
	w:ingest("level", { level = 20 }) -- yours: real
	w.ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = "Pretend", class = "MAGE", emulated = true, data = { level = 3 } })
	equal(runner:Go(true), true)
	-- Clear on go wipes the pretend players only; yours stays.
	local players = {}
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do players[entry.player] = true end
	equal(players.Tester, true)
	equal(players.Pretend, nil)
	equal(runner:Running(), true)
	runner:Stop()
	equal(runner:Running(), false)
end)

-- ========= Quest Party chat (decals) =======================================
test("images, a saying and an effect go out as one short message, and show once the channel sends it back", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	equal(w.ns.Chat:Send({ 134071 }, "gz"), false) -- no channel yet
	w:share()
	w.echo = false -- the server holds it a moment: sent, not yet back
	local _, problem = w.ns.Chat:Send({}, nil)
	equal(problem, w.ns.L.CHAT_PICK) -- nothing chosen
	equal(w.ns.Chat:Send({}, "not a saying"), false)
	equal(w.ns.Chat:Send({ 134071 }, "gz", "no such effect"), false)
	ok, problem = w.ns.Chat:Send({}, "gz", "rain")
	equal(problem, w.ns.L.CHAT_EFFECT_NEEDS_IMAGE)
	equal(w.ns.Chat:Send({ 134071, 134072, 134073, 134074 }, "gz", "fireworks"), true)
	local sent = sentOfKind(w, "S")
	equal(#sent, 1)
	equal(sent[1].fields.i, 134071)
	equal(sent[1].fields.i3, 134073) -- three at most
	equal(sent[1].fields.k, "gz")
	equal(sent[1].fields.e, "fireworks")
	equal(type(sent[1].fields.w), "number") -- when it was said: each message its own card
	equal(#chatRows(w), 0) -- not until the channel sends it back
	w:event("CHAT_MSG_ADDON", "QuestParty", sent[1].message.text, "CHANNEL", "Tester-TestRealm", "", 0, 5, "QuestFriends")
	equal(#chatRows(w), 1)
	local message = chatRows(w)[1]
	equal(message.player, "Tester")
	equal(#message.data.icons, 3)
	equal(message.data.saying, "gz")
	equal(message.data.effect, "fireworks")
	equal(message.time, sent[1].fields.w)
	equal(w.ns.Chat:Send({ 134071 }, nil), true) -- an image alone
	equal(w.ns.Chat:Send({}, "hi"), true) -- a saying alone
end)

test("a KekChat message is a distinct feed row: its images and saying, its own card to stamp", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("S", { i = 133000, i2 = 133001, k = "gz", w = 5000 }, "Friend")
	w:hear("S", { i = 133000, i2 = 133001, k = "gz", w = 5003 }, "Friend") -- the same again
	local rows = {}
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do
		if row.mark == "chat" then rows[#rows + 1] = row end
	end
	equal(#rows, 2) -- never folded together
	equal(rows[1].title, "|T133001:0|t |cffffffffGratz!|r") -- the first image is the square
	equal(rows[1].markIcon, 133000)
	assert(rows[1].stampKey and rows[2].stampKey and rows[1].stampKey ~= rows[2].stampKey, "each its own card")
	-- The filter row's KekChat icon hides them from your feed.
	w.ns.charDb.hidden.chat = true
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do
		assert(row.mark ~= "chat", "hidden by the filter row")
	end
end)

test("a KekChat effect plays over the feed when the message lands", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local played = {}
	w.ns.Bus:On("CHAT_PLAY", function(message) played[#played + 1] = message end)
	w:share()
	w:hear("S", { i = 133000, e = "fireworks" }, "Friend")
	equal(#played, 1)
	equal(played[1].effect, "fireworks")
	equal(played[1].icons[1], 133000)
end)

test("KekChat's old list moves into the feed at its times, and goes", function()
	local w = Harness.new({
		feed = {
			{ type = "death", player = "Friend", time = 3000, data = { zone = "The Barrens", level = 13 } },
			{ type = "death", player = "Friend", time = 1000, data = { zone = "Durotar", level = 5 } },
		},
		chat = {
			{ player = "Friend", class = "MAGE", icons = { 133000 }, saying = "gz", time = 2000 },
			{ system = true, player = "Spammer", text = "timed out", time = 2100 },
			{ player = "Friend", kind = "board", id = "hi", icons = {}, time = 2500 }, -- an older shape
		},
	})
	equal(w.ns.db.chat, nil)
	local order = {}
	local feed = w.ns.Store:GetFeed(true)
	for index = #feed, 1, -1 do order[#order + 1] = feed[index].type .. "@" .. feed[index].time end
	equal(table.concat(order, " "), "death@1000 chat@2000 chat@2500 death@3000")
	equal(feed[2].data.saying, "hi")
	equal(feed[3].data.icons[1], 133000)
	equal(feed[3].data.w, 2000) -- named by its moment, like a new one
end)

test("KekChats seeded from the old quick chats take the new defaults; your own words stay", function()
	local old = Harness.new({ kekMessages = { { text = "Hi all!" }, { icon = 5, text = "Be right back." } } })
	equal(#old.ns.Chat:KekMessages(), old.ns.ChatRules.maxMessages)
	equal(old.ns.Chat:KekMessages()[1].text, old.ns.L.KEK_DEFAULT_WELCOME)
	local mine = Harness.new({ kekMessages = { { text = "Hi all!" }, { text = "loot pls" } } })
	equal(#mine.ns.Chat:KekMessages(), 2)
	equal(mine.ns.Chat:KekMessages()[2].text, "loot pls")
end)

test("your own KekChats: up to ten, words of your own made safe and short, a sound and an effect", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.env.GetFileIDFromPath = function(path) return #path * 10 end
	local Chat = w.ns.Chat
	-- They start as the ten defaults, each with its sound and effect.
	local list = Chat:KekMessages()
	equal(#list, w.ns.ChatRules.maxMessages)
	equal(list[1].text, w.ns.L.KEK_DEFAULT_WELCOME)
	equal(list[1].sound, "cheer")
	equal(list[8].text, w.ns.L.KEK_DEFAULT_DANCE)
	equal(list[8].sound, "party")
	-- Every default's sound and effect is one we have (an effect shows once its icon resolves).
	for _, default in ipairs(w.ns.KekDefaults) do
		assert(default.sound == nil or w.ns.KekSoundById[default.sound], default.text)
		assert(default.effect == nil or w.ns.ChatEffectById[default.effect], default.text)
		assert(#default.text <= w.ns.ChatRules.maxText, default.text)
	end
	-- Words: the game's escapes gone, spaces tidied, cut to maxText letters.
	equal(Chat.CleanText("  hi |cffff0000there|r\n  friend  "), "hi there friend")
	equal(Chat.CleanText("get |Hitem:19019|h[Thunderfury]|h |TInterface\\Icons\\x:0|tnow"), "get [Thunderfury] now")
	equal(#Chat.CleanText(string.rep("a", 300)), w.ns.ChatRules.maxText)
	equal(Chat.CleanText(string.rep("é", 150)), string.rep("é", w.ns.ChatRules.maxText)) -- letters, not bytes
	-- Saving checks it; a sound or effect we do not have is left off.
	equal(Chat:SetKekMessage(1, { icon = 133000, text = "Pull the next pack!", sound = "cheer", effect = "fireworks" }), true)
	equal(Chat:SetKekMessage(2, { icon = 133001, text = "hey", sound = "nope", effect = "nope" }), true)
	equal(list[2].sound, nil)
	equal(list[2].effect, nil)
	equal(Chat:SetKekMessage(11, { icon = 133000 }), false) -- ten at most
	-- Sent in one message, read back by everyone: the words, the sound, the effect.
	w:share()
	local played = {}
	w.env.PlaySound = function(kit) played[#played + 1] = kit end
	equal(Chat:SendKek(1), true)
	local sent = sentOfKind(w, "S")
	equal(sent[#sent].fields.t, "Pull the next pack!")
	equal(sent[#sent].fields.n, "cheer")
	assert(#sent[#sent].message.text <= w.ns.Protocol.maxLength, "fits")
	local row = chatRows(w)[1]
	equal(row.data.text, "Pull the next pack!")
	equal(row.data.sound, "cheer")
	equal(#played, 1)
	-- A friend's words arrive cleaned, whatever they sent.
	w:hear("S", { t = "|Hitem:1|hfree loot|h " .. string.rep("x", 200), i = 133000 }, "Friend")
	local theirs = chatRows(w)[2].data.text
	equal(theirs:find("|", 1, true), nil)
	equal(#theirs, w.ns.ChatRules.maxText)
end)

test("blocking KekChat: one message from a player, or all of theirs; unblocking brings them back", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local Chat = w.ns.Chat
	w:hear("S", { t = "buy gold cheap", i = 133000 }, "Pest")
	w:hear("S", { t = "hello all", i = 133000 }, "Pest")
	w:hear("S", { t = "hello all", i = 133000 }, "Friend")
	equal(#chatRows(w), 3)
	Chat:BlockText("Pest", "buy gold cheap", true)
	equal(#chatRows(w), 2) -- that message, from that player, is hidden
	w:hear("S", { t = "buy gold cheap", i = 133000 }, "Pest")
	equal(#chatRows(w), 2) -- and not taken again
	Chat:BlockAll("Pest", true)
	equal(#chatRows(w), 1) -- all of theirs; Friend's "hello all" still shows
	equal(chatRows(w)[1].player, "Friend")
	Chat:BlockAll("Pest", false)
	Chat:BlockText("Pest", "buy gold cheap", false)
	equal(#chatRows(w), 3)
	Chat:BlockAll(w.ns.MyName(), true)
	equal(Chat:IsBlocked(w.ns.MyName()), false) -- not yourself
end)

test("what friends send is only ever an image number and a known saying", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	w:hear("S", { i = 133000, k = "ty", c = "MAGE" }, "Friend")
	w:hear("S", { i = "|Tevil|t", k = "|cffff0000words" }, "Friend") -- neither is usable
	w:hear("S", { i = 1.5 }, "Friend")
	w:hear("S", { k = "danceparty" }, "Friend") -- a saying this version does not know
	w:hear("S", { i = 133001, k = "a newer saying" }, "Friend") -- the image still shows
	w:hear("D", { i = 133002 }, "Friend") -- kinds from earlier builds are not read
	w:hear("T", { x = "free text" }, "Friend")
	w:hear("S", { i = 133003, e = "|cffevil" }, "Friend") -- not an effect: the image alone
	local messages = chatRows(w)
	equal(#messages, 3)
	equal(messages[1].data.saying, "ty")
	equal(messages[1].class, "MAGE")
	equal(messages[2].data.icons[1], 133001)
	equal(messages[2].data.saying, nil)
	equal(messages[3].data.effect, nil)
end)

test("a saying with an effect does it on every screen", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local effects = {}
	w.ns.Bus:On("CHAT_EFFECT", function(effect, player) effects[#effects + 1] = effect .. ":" .. player end)
	w:share()
	w:hear("S", { k = "cheer" }, "Friend")
	equal(effects[1], "confetti:Friend")
end)

test("a spammer is timed out here: hidden for a while, with one notice, longer each time", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local rules = w.ns.ChatRules
	for _ = 1, rules.burst + 3 do
		w:hear("S", { k = "lol" }, "Spammer")
	end
	equal(#chatRows(w), rules.burst)
	local notices = 0
	for _, line in ipairs(w.chat) do
		if line:find("Spammer", 1, true) then notices = notices + 1 end
	end
	equal(notices, 1) -- said once, here only, not for every dropped message
	equal(w.ns.Chat:TimeoutLeft("Spammer"), rules.timeoutSeconds)
	w:advance(rules.burstSeconds) -- the burst has passed, but the timeout has not
	w:hear("S", { k = "lol" }, "Spammer")
	equal(#chatRows(w), rules.burst)
	w:advance(rules.timeoutSeconds)
	w:hear("S", { k = "hi" }, "Spammer") -- served their time
	equal(#chatRows(w), rules.burst + 1)
	for _ = 1, rules.burst do
		w:hear("S", { k = "lol" }, "Spammer")
	end
	equal(w.ns.Chat:TimeoutLeft("Spammer"), rules.timeoutSeconds * 2) -- again soon: doubled
	equal(w.ns.Chat:TimeoutLeft("Friend"), 0) -- others are not affected
end)

test("your own chat times out too: past the burst nothing goes out until the time is up", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local rules = w.ns.ChatRules
	for _ = 1, rules.burst do
		equal(w.ns.Chat:Send({}, "hi"), true)
	end
	local ok, problem = w.ns.Chat:Send({}, "hi")
	equal(ok, false)
	equal(problem, w.ns.L.CHAT_TIMEOUT:format(rules.timeoutSeconds))
	local sent = #sentOfKind(w, "S")
	w:advance(rules.timeoutSeconds - 1)
	equal(w.ns.Chat:Send({}, "hi"), false) -- still timed out
	equal(#sentOfKind(w, "S"), sent)
	w:advance(1)
	equal(w.ns.Chat:TimeoutLeft(), 0)
	equal(w.ns.Chat:Send({}, "hi"), true)
	w:advance(rules.timeoutForgetSeconds + 1) -- a long quiet spell: the next one is short again
	for _ = 1, rules.burst do w.ns.Chat:Send({}, "hi") end
	w.ns.Chat:Send({}, "hi")
	equal(w.ns.Chat:TimeoutLeft(), rules.timeoutSeconds)
end)

test("presets: built-in ones first, then the player's own, saved once each and kept", function()
	local w = Harness.new()
	w.env.GetFileIDFromPath = function(path) return path:find("BattleShout") and 2001 or nil end
	local presets = w.ns.Chat:Presets()
	equal(presets[1].builtIn, true)
	equal(presets[1].icons[1], 2001)
	equal(presets[1].saying, "hi")
	equal(#presets[2].icons, 0) -- icons the game does not know: the saying alone
	equal(presets[2].effect, nil) -- and no effect without images
	local builtIn = #presets
	equal(w.ns.Chat:SavePreset({ 133000, 133001 }, "gz", "rain"), true)
	local _, problem = w.ns.Chat:SavePreset({ 133000, 133001 }, "gz", "rain")
	equal(problem, w.ns.L.CHAT_PRESET_KNOWN)
	equal(w.ns.Chat:SavePreset({}, nil), false)
	presets = w.ns.Chat:Presets()
	equal(#presets, builtIn + 1)
	equal(presets[#presets].own, 1)
	local again = Harness.new(w.ns.db)
	equal(again.ns.db.chatPresets[1].saying, "gz") -- kept across a reload
	equal(again.ns.db.chatPresets[1].effect, "rain")
	again.ns.Chat:DeletePreset(1)
	equal(#again.ns.db.chatPresets, 0)
end)

test("muting: a muted player's messages and effects do not show, and the ignore list mutes too", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	local effects = 0
	w.ns.Bus:On("CHAT_EFFECT", function() effects = effects + 1 end)
	w:share()
	w:hear("S", { k = "hi" }, "Friend")
	equal(w.ns.Chat:ToggleMute("Friend"), true)
	equal(#chatRows(w), 0) -- what they said before is hidden too
	w:hear("S", { k = "cheer" }, "Friend")
	w:hear("S", { i = 133000 }, "Friend")
	equal(effects, 0)
	equal(w.ns.Chat:ToggleMute("Friend"), false)
	equal(#chatRows(w), 1)
	equal(w.ns.Chat:ToggleMute("Tester"), false) -- not yourself
	w.env.C_FriendList = { IsIgnored = function(name) return name == "Troll" end }
	w:hear("S", { k = "hi" }, "Troll")
	equal(#chatRows(w), 1)
	equal(w.ns.Chat:IsMuted("Troll"), true)
end)

test("typing a word suggests sayings and images for it; the word itself is never sent", function()
	local w = Harness.new()
	w.env.GetFileIDFromPath = function(path) return path:find("Gem") and (#path * 100) or nil end
	local chat = w.ns.Chat
	equal(chat:Suggest("gr")[1].id, "gz") -- "Gratz!"
	equal(chat:Suggest("GRATZ")[1].kind, "saying")
	equal(#chat:Suggest("rai"), 0) -- effects are not built by typing: they are the strip's
	local gems = chat:Suggest("gem")
	assert(#gems > 0, "gems suggested")
	for _, entry in ipairs(gems) do equal(entry.kind, "image") end
	equal(#chat:Suggest(""), #w.ns.Sayings) -- an empty word: every saying
	equal(#chat:Suggest("zzzq"), 0)
	equal(#chat:Suggest("e", 3), 3) -- at most the limit
	local before = #w.sent
	chat:Suggest("hello there")
	equal(#w.sent, before)
end)

test("every effect has a button icon of its own: no two alike in the grid", function()
	local w = Harness.new()
	local seen = {}
	for _, preset in ipairs(w.ns.EffectPresets) do
		assert(type(preset.icon) == "string", preset.id .. " has its own icon")
		assert(not seen[preset.icon], preset.id .. " shares its icon with " .. tostring(seen[preset.icon]))
		seen[preset.icon] = preset.id
	end
end)

test("an effect played on a card: everyone sees it over that card, and it leaves no row and no stamp", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.env.GetFileIDFromPath = function(path) return #path * 10 end
	local presets = w.ns.Chat:EffectPresets()
	equal(#presets, #w.ns.EffectPresets)
	local worded
	for _, preset in ipairs(presets) do worded = worded or (preset.saying and preset) end
	local played = {}
	w.ns.Bus:On("CARD_EFFECT", function(key, id, sender) played[#played + 1] = key .. "|" .. id .. "|" .. sender end)
	local entry = { type = "death", player = "Friend", data = { zone = "The Barrens", level = 13, w = 900 } }
	equal(w.ns.Stamping:SendEffect(entry, worded.id), false) -- no channel yet
	w:share()
	local feedBefore = #w.ns.Store:GetFeed(true)
	equal(w.ns.Stamping:SendEffect(entry, worded.id), true)
	local sent = sentOfKind(w, "T")
	equal(sent[#sent].fields.e, worded.id)
	equal(sent[#sent].fields.s, nil) -- not a stamp
	local key = w.ns.Stamping:KeyFor(entry)
	equal(played[1], key .. "|" .. worded.id .. "|Tester") -- yours plays when it comes back
	equal(#w.ns.Store:GetFeed(true), feedBefore) -- no row
	equal(#(w.ns.Stamping:For(key) or {}), 0) -- no stamp
	w:hear("T", { k = key, e = worded.id }, "Friend")
	equal(#played, 2)
	w:hear("T", { k = key, e = "nope" }, "Friend") -- not an effect: nothing
	w.ns.Chat:ToggleMute("Friend")
	w:hear("T", { k = key, e = worded.id }, "Friend") -- muted: nothing
	equal(#played, 2)
	equal(w.ns.Stamping:SendEffect(entry, "nope"), false)
	-- From KekChat's list: no card, so it goes under the feed's key and plays
	-- over the feed, still leaving no row.
	w.ns.Chat:ToggleMute("Friend")
	w:advance(60)
	equal(w.ns.Stamping:SendFeedEffect(worded.id), true)
	equal(played[#played], w.ns.Stamping.FEED_KEY .. "|" .. worded.id .. "|Tester")
	equal(#w.ns.Store:GetFeed(true), feedBefore)
end)

test("every effect fills a big window, and is as tuned in a small one", function()
	local w = Harness.new()
	local P = w.ns.Particles
	local seed = 11
	local function random() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
	local small = w.ns.ChatEffectById.rain
	equal(P.Fit(small, 240, 150), small) -- a stamp's box: untouched
	local width, height = 400, 640
	-- How far each spreads over its life: lowest point, highest, widest from the middle.
	local function Run(id)
		local list = P.Spawn(w.ns.ChatEffectById[id], { 11 }, width, height, random)
		local low, high, wide = -math.huge, math.huge, 0
		for _ = 1, 400 do
			P.Step(list, 0.02, height, random)
			for _, particle in ipairs(list) do
				if particle.age and particle.age > 0 and not particle.fuse then
					low, high = math.max(low, particle.y), math.min(high, particle.y)
					wide = math.max(wide, math.abs(particle.x - width / 2))
				end
			end
		end
		return low, high, wide
	end
	local low = Run("rain")
	assert(low >= 0.85 * height, "rain falls the whole way: " .. low)
	local _, high = Run("fireworks")
	assert(high <= 0.5 * height, "fireworks pop high up: " .. high)
	local _, _, wide = Run("celebrate")
	assert(wide >= 0.35 * width, "a burst spreads wide: " .. wide)
	_, _, wide = Run("swirl")
	assert(wide >= 0.3 * width, "a swirl spreads wide: " .. wide)
	local fit = P.Fit(w.ns.ChatEffectById.celebrate, width, height)
	assert(fit.count > w.ns.ChatEffectById.celebrate.count, "more of them in more room")
end)

test("the fountain is launched to reach the top of whatever it plays over, and stays inside it", function()
	local w = Harness.new()
	local seed = 7
	local function random() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
	for _, size in ipairs({ { 300, 160 }, { 380, 620 } }) do
		local width, height = size[1], size[2]
		local list = w.ns.Particles.Spawn(w.ns.ChatEffectById.fountain, { 11 }, width, height, random)
		local top, left, right = math.huge, math.huge, -math.huge
		for _ = 1, 200 do
			w.ns.Particles.Step(list, 0.02, height, random)
			for _, particle in ipairs(list) do
				if particle.age and particle.age > 0 then
					top = math.min(top, particle.y)
					left, right = math.min(left, particle.x), math.max(right, particle.x)
				end
			end
		end
		assert(top <= 0.25 * height, ("reaches near the top of %d: peaked at %d"):format(height, top))
		assert(top >= -0.05 * height, "not far past it")
		assert(left >= 0 and right <= width, "inside the area")
	end
end)

test("a worded effect turns some of its particles into its words, rockets included", function()
	local w = Harness.new()
	local seed = 3
	local function random() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
	local list = w.ns.Particles.Spawn(w.ns.ChatEffectById.rain, { 11 }, 300, 200, random, "Gratz!")
	local words = 0
	for _, particle in ipairs(list) do
		if particle.text then
			words = words + 1
			equal(particle.text, "Gratz!")
			equal(particle.icon, nil)
		end
	end
	assert(words > 0 and words <= w.ns.ParticleRules.maxWords, "some words: " .. words)
	local rockets = w.ns.Particles.Spawn(w.ns.ChatEffectById.fireworks, { 11 }, 300, 200, random, "Gratz!")
	local time, sparkWords = 0, 0
	while time < 3 do
		w.ns.Particles.Step(rockets, 0.05, 200, random)
		time = time + 0.05
	end
	for _, particle in ipairs(rockets) do
		if particle.text then sparkWords = sparkWords + 1 end
	end
	assert(sparkWords > 0, "the rockets burst into words")
end)

test("every effect starts particles from its images, moves them, and they all end", function()
	local w = Harness.new()
	local seed = 7
	local function random() seed = (seed * 1103515245 + 12345) % 2147483648 return seed / 2147483648 end
	for _, effect in ipairs(w.ns.ChatEffects) do
		local list = w.ns.Particles.Spawn(effect, { 11, 22 }, 300, 200, random)
		assert(#list > 0, effect.id .. " starts with nothing")
		for _, particle in ipairs(list) do
			assert(particle.icon == 11 or particle.icon == 22, effect.id .. " used another image")
		end
		local left, time, popped = #list, 0, false
		while left > 0 and time < 20 do
			local before = #list
			left = w.ns.Particles.Step(list, 0.05, 200, random)
			popped = popped or #list > before
			time = time + 0.05
		end
		equal(left, 0) -- everything ends
		if effect.pattern == "fireworks" then
			equal(popped, true) -- rockets pop into sparks
		end
	end
	equal(#w.ns.Particles.Spawn(w.ns.ChatEffectById.rain, {}, 300, 200, random), 0) -- no images, nothing
end)

test("sounds play at the volume set: loud, regular, soft, or not at all on mute", function()
	local w = Harness.new({ switches = { chatSounds = false } }) -- an old switch is cleaned away
	local played = {}
	w.env.PlaySound = function(kit, _, _, _, _, volume) played[#played + 1] = { kit = kit, volume = volume } end
	equal(w.ns.db.switches.chatSounds, nil)
	equal(w.ns.GetSlider("volume"), 2) -- regular
	w.ns.PlaySound(74702)
	equal(played[1].kit, 74702)
	equal(played[1].volume, w.ns.VolumeLevels[2].volume)
	w.ns.SetSlider("volume", 3)
	w.ns.PlaySound(74702)
	equal(played[2].volume, 1)
	w.ns.SetSlider("volume", 0)
	equal(w.ns.PlaySound(74702), false)
	equal(#played, 2) -- mute plays nothing
	equal(w.ns.SetSlider("volume", 7), 3) -- kept in range
end)

test("the image picker searches our catalog by path and tags; paths the game does not know are dropped", function()
	local w = Harness.new()
	local ids = { ["Interface\\Icons\\INV_Misc_Gem_Ruby_01"] = 1001, ["Interface\\Icons\\INV_Misc_Gem_01"] = 1002, ["Interface\\Icons\\XP_Icon"] = 1003 }
	w.env.GetFileIDFromPath = function(path) return ids[path] end
	equal(#w.ns.Chat:Search(""), 3)
	local found = w.ns.Chat:Search("gem ruby")
	equal(#found, 1)
	equal(found[1], 1001)
	equal(#w.ns.Chat:Search("GEM"), 2)
	equal(w.ns.Chat:Search("ding")[1], 1003) -- a tag
end)

-- ========= Which quests are shown and told ==================================
test("a quest is underway when something is started and something is left", function()
	local underway = Harness.new().ns.QuestUnderway
	equal(underway({ { have = 1, need = 3 } }), true)
	equal(underway({ { have = 8, need = 8 }, { have = 6, need = 6 }, { have = 1, need = 3 } }), true)
	equal(underway({ { have = 2, need = 2 }, { have = 0, need = 1 } }), true)
	equal(underway({ { have = 0, need = 8 }, { have = 0, need = 8 } }), false) -- not started
	equal(underway({ { have = 1, need = 1 } }), false) -- only needs handing in
	equal(underway({}), false) -- nothing to count
	equal(underway(nil), false)
end)

test("the panel shows a quest only while it is underway", function()
	local w = Harness.new()
	local function shown() return #w.ns.ViewModel:Build("quests") end
	w:ingest("quest_accepted", { quest = "A Quest" })
	equal(shown(), 0) -- accepted, nothing done yet
	equal(#w.ns.Store:GetCards("quest"), 1) -- the card is kept all the same
	progress(w, 1)
	equal(shown(), 1)
	progress(w, 3)
	equal(shown(), 0) -- every objective complete: it only needs handing in
end)

test("only quests that are underway are told to the channel", function()
	local w = Harness.new()
	local function objective(have, need) return { text = "Things: " .. have .. "/" .. need, numFulfilled = have, numRequired = need } end
	w.quests[1] = { questID = 1, title = "Not started", objectives = { objective(0, 8) } }
	w.quests[2] = { questID = 2, title = "Underway", objectives = { objective(3, 8), objective(2, 2) } }
	w.quests[3] = { questID = 3, title = "Ready to hand in", objectives = { objective(5, 5) } }
	w:share()
	w:advance(5)
	local states = sentOfKind(w, "Q")
	equal(#states, 1)
	equal(states[1].fields.quest, "Underway")
end)

-- ========= How quests stand =================================================
local function questStates(w)
	return sentOfKind(w, "Q")
end

test("connecting says how every quest in your log stands", function()
	local w = Harness.new()
	w:quest(2, 3)
	w:share() -- the hello, then a moment later how your quests stand
	local states = questStates(w)
	equal(#states, 1)
	equal(states[1].fields.id, 1)
	equal(states[1].fields.quest, "A Quest")
	equal(states[1].fields.c, "MAGE")
	equal(states[1].fields.o1, "Kobolds slain")
	equal(states[1].fields.h1, 2)
	equal(states[1].fields.n1, 3)
end)

test("hearing a hello answers straight away with how your quests stand, for each newcomer", function()
	local w = Harness.new()
	w:quest(1, 3)
	w:share()
	w:advance(5)
	local before = #questStates(w)
	w:hear("H", { v = "0.2.0", c = "PRIEST", l = 14, z = "Westfall" }, "Newcomer")
	equal(#questStates(w), before + 1)
	w:hear("H", { v = "0.2.0", c = "ROGUE", l = 14, z = "Westfall" }, "Another")
	equal(#questStates(w), before + 2)
end)

test("a friend's quest state fills in their card without a feed row, and a later one replaces it", function()
	local w = Harness.new()
	w:share()
	w:hear("Q", { id = 9, quest = "Wolves", c = "PRIEST", o1 = "Wolves slain", h1 = 3, n1 = 8, o2 = "Pelts", h2 = 1, n2 = 4 }, "Friend")
	local cards = w.ns.Store:GetCards("quest")
	equal(#cards, 1)
	equal(cards[1].player, "Friend")
	equal(cards[1].class, "PRIEST")
	equal(cards[1].data.quest, "Wolves")
	equal(cards[1].data.objectives["Wolves slain"].have, 3)
	equal(cards[1].data.objectives["Pelts"].need, 4)
	equal(#w.ns.Store:GetFeed(true), 0)
	equal(w.ns.Session:IsConnected("Friend"), true)
	w:hear("Q", { id = 9, quest = "Wolves", c = "PRIEST", o1 = "Wolves slain", h1 = 5, n1 = 8, o2 = "Pelts", h2 = 1, n2 = 4 }, "Friend")
	w:hear("Q", { id = 9, quest = "Wolves", c = "PRIEST", o1 = "Wolves slain", h1 = 5, n1 = 8, o2 = "Pelts", h2 = 1, n2 = 4 }, "Friend") -- repeated: no harm
	cards = w.ns.Store:GetCards("quest")
	equal(#cards, 1)
	equal(cards[1].data.objectives["Wolves slain"].have, 5)
	w:hear("Q", { quest = "No id" }, "Friend")
	w:hear("Q", { id = 10 }, "Friend")
	equal(#w.ns.Store:GetCards("quest"), 1)
end)

test("a quest with too much to say in one message leaves objectives off the end", function()
	local w = Harness.new()
	local objectives = {}
	for index = 1, 12 do
		objectives[index] = { text = ("A long objective name number %d: 1/9"):format(index), numFulfilled = 1, numRequired = 9 }
	end
	w.quests[1] = { questID = 1, title = "A Quest With A Great Deal To Do", objectives = objectives }
	w:share()
	w:advance(5)
	local states = questStates(w)
	equal(#states, 1)
	assert(#states[1].message.text <= 255)
	equal(states[1].fields.o1, "A long objective name number 1")
	assert(states[1].fields.o12 == nil)
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

-- ========= Who a message is from (origin) ===================================
test("the origin rule: friends are peers, yours is self, pretend players only in debug mode", function()
	local w = Harness.new()
	local Origin = w.ns.Origin
	equal(select(2, Origin("Friend", false, nil, false)), "Friend")
	equal(Origin("Friend", false, "Jaina", true), nil) -- someone else's pretend players
	equal(Origin("Tester", true, nil, false), "self")
	equal(Origin("Tester", true, nil, true), "self")
	equal(Origin("Tester", true, "Jaina", false), nil)
	equal(select(2, Origin("Tester", true, "Jaina", true)), "Jaina")
end)

-- An addon message from this character, as the server sends it back.
local function echo(w, text)
	w:event("CHAT_MSG_ADDON", "QuestParty", text, "CHANNEL", "Tester-TestRealm", "", 0, 5, "QuestFriends")
end

test("a pretend player's hello from this character makes it a peer here in debug, not counted as sharing", function()
	local w = Harness.new()
	w.ns.SetDebug(true)
	w:share()
	echo(w, w.ns.Protocol.Encode("H", { as = "Fenwick", c = "PRIEST", l = 12, z = "Westfall", r = "Dwarf", g = 3 }))
	local peer = w.ns.Session.peers.Fenwick
	equal(peer.level, 12)
	equal(peer.race, "Dwarf")
	equal(peer.sex, 3)
	equal(peer.virtual, true)
	equal(w.ns.Session:Count(), 0)
	w.ns.SetDebug(false)
	echo(w, w.ns.Protocol.Encode("H", { as = "Other", c = "PRIEST", l = 12 }))
	equal(w.ns.Session.peers.Other, nil)
end)

-- ========= How things stand: hello, counter, presence =======================
test("the hello says race and sex", function()
	local w = Harness.new()
	w:share()
	local hello = sentOfKind(w, "H")[1].fields
	equal(hello.r, "Human")
	equal(hello.g, 3)
end)

test("a newcomer is answered once, after a short wait; a presence is never answered", function()
	local w = Harness.new()
	w:share()
	w:hear("H", { c = "PRIEST", l = 14 }, "Friend")
	w:hear("H", { c = "PRIEST", l = 14 }, "Friend") -- said again
	w:advance(5)
	equal(#sentOfKind(w, "A"), 1)
	w:hear("P", { c = "PRIEST", l = 14 }, "Other")
	w:advance(5)
	equal(#sentOfKind(w, "A"), 1)
	equal(w.ns.Session.peers.Other.level, 14)
end)

test("presence goes out every few minutes, and a silent player is taken to have gone", function()
	local w = Harness.new()
	w:share()
	w:hear("H", { c = "PRIEST", l = 14 }, "Friend")
	w:advance(5 * 60 + 1)
	equal(#sentOfKind(w, "P"), 1)
	equal(w.ns.Session.peers.Friend ~= nil, true)
	w:advance(20 * 60)
	equal(w.ns.Session.peers.Friend, nil)
end)

test("a welcome row when someone joins, always on", function()
	local w = Harness.new({ switches = { chatEcho = false } }, nil, nil, nil, { welcomes = true })
	w:share()
	w:hear("H", { c = "PRIEST", l = 14 }, "Friend")
	local feed = w.ns.Store:GetFeed(true)
	equal(#feed, 1)
	equal(feed[1].type, "joined")
	equal(w.ns.ViewModel:Build("all")[1].title, "Joined the party")
	equal(w.ns.SettingById.welcome, nil) -- no switch to turn it off
end)

test("welcomes are rate limited: once per player, and a few a minute at most", function()
	local w = Harness.new({ switches = { chatEcho = false } }, nil, nil, nil, { welcomes = true })
	local sharing, timing = w.ns.Sharing, w.ns.Timing
	equal(sharing:MayWelcome("Friend"), true)
	equal(sharing:MayWelcome("Friend"), false) -- coming and going again
	w:advance(timing.welcomeSeconds)
	equal(sharing:MayWelcome("Friend"), true)
	for index = 1, timing.welcomeBurst - 1 do
		equal(sharing:MayWelcome("Arrival" .. index), true)
	end
	equal(sharing:MayWelcome("OneTooMany"), false) -- a crowd arriving at once
	w:advance(timing.welcomeBurstSeconds)
	equal(sharing:MayWelcome("OneTooMany"), true)
end)

test("the gutter hides kinds of rows from your feed, and only from your view", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:ingest("level", { level = 20 })
	w:ingest("death", { zone = "Duskwood", level = 20 })
	w:ingest("xp", { xp = 65, level = 20, currentXP = 500, maxXP = 1000, mob = "Riverpaw Gnoll" })
	equal(#w.ns.ViewModel:Build("all"), 3)
	w.ns.charDb.hidden.deaths = true
	w.ns.charDb.hidden.kills = true -- XP from a kill is a Kills row
	local rows = w.ns.ViewModel:Build("all")
	equal(#rows, 1)
	equal(rows[1].badge ~= nil or rows[1].title ~= nil, true)
	equal(w.ns.IsEnabled("deaths"), true) -- still collected and shared
	equal(#w.ns.Store:GetFeed(true), 3)
end)

-- ========= Gear ==============================================================
test("our gear goes out as a whole set: with the hello, and 30 seconds after the last change", function()
	local w = Harness.new()
	w.gear[16] = "|cffffffff|Hitem:25:0:0:0:0:0:0:0:20|h[Worn Shortsword]|h|r"
	w.gear[1] = "|cff1eff00|Hitem:3887:15:0:0:0:0:592:0:20|h[Hat of the Bear]|h|r"
	w:share()
	w:advance(5)
	-- The fields of the gear messages sent after the first "from" of them.
	local function Since(from)
		local found = {}
		for index, message in ipairs(sentOfKind(w, "G")) do
			if index > from then
				for key, value in pairs(message.fields) do found[key] = value end
			end
		end
		return found
	end
	local found = Since(0)
	equal(found.s16, "25:0:0")
	equal(found.s1, "3887:15:592")
	equal(w.ns.Timing.gearSeconds, 30)
	-- Changes: each one waits again; the whole set goes out once they stop.
	local before = #sentOfKind(w, "G")
	w.gear[16] = "|cffffffff|Hitem:2092:0:0:0:0:0:0:0:20|h[Worn Dagger]|h|r"
	w:event("PLAYER_EQUIPMENT_CHANGED", 16)
	w:advance(20)
	w.gear[16] = "|cffffffff|Hitem:35:0:0:0:0:0:0:0:20|h[Bent Staff]|h|r"
	w:event("PLAYER_EQUIPMENT_CHANGED", 16)
	w.gear[1] = nil
	w:event("PLAYER_EQUIPMENT_CHANGED", 1)
	w:advance(20)
	equal(#sentOfKind(w, "G"), before) -- still changing: nothing yet
	w:advance(11)
	found = Since(before)
	equal(found.s16, "35:0:0") -- the latest, with both changes, as one set
	equal(found.s1, "")
	-- With Share my gear off, nothing goes out.
	w.ns.SetEnabled("shareGear", false)
	before = #sentOfKind(w, "G")
	w.gear[16] = nil
	w:event("PLAYER_EQUIPMENT_CHANGED", 16)
	w:advance(w.ns.Timing.gearSeconds + 1)
	equal(#sentOfKind(w, "G"), before)
end)

test("a friend's gear lands on their card, a slot at a time, and junk is not an item", function()
	local w = Harness.new()
	w:share()
	w:hear("G", { c = "WARRIOR", s1 = "3887:15:592", s16 = "25:0:0", n = 10 }, "Friend")
	w:hear("G", { c = "WARRIOR", s16 = "2092:0:0", n = 20 }, "Friend")
	w:hear("G", { c = "WARRIOR", s5 = "|cff|Hevil|h", n = 30 }, "Friend")
	local gear = w.ns.Store:GetMember("Friend").gear
	equal(gear[1], "3887:15:592")
	equal(gear[16], "2092:0:0")
	equal(gear[5], "")
	equal(w.ns.ItemString(gear[1]), "item:3887:15:0:0:0:0:592")
	equal(w.ns.ItemString(""), nil)
end)

-- ========= Requests ==========================================================
-- ========= XP over time, lifetimes, pruning =================================
test("a player's XP is added up for the session and by day, from what is heard", function()
	local w = Harness.new()
	w:share()
	w:hear("H", { c = "WARRIOR", l = 14 }, "Friend")
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 100, level = 14, currentXP = 500, maxXP = 9000 }, "Friend")
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 50, level = 14, currentXP = 550, maxXP = 9000 }, "Friend")
	local member = w.ns.Store:GetMember("Friend")
	equal(member.sessionXP, 150)
	equal(member.xpDays[w.ns.Day(w.now)], 150)
end)

test("a player not seen for a week is forgotten; dev mode's measures count what is saved", function()
	local w = Harness.new()
	w:ingest("level", { level = 9 }, "Buddy")
	equal(w.ns.Store:Counts().members, 1)
	w:advance(8 * 24 * 60 * 60)
	w.ns.Store:Expire(w.now)
	equal(w.ns.Store:GetMember("Buddy"), nil)
end)

test("pruning forgets players not here, and friends' cards", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { questID = 47, quest = "Buddy's Quest" }, "Buddy")
	w:ingest("quest_accepted", { questID = 48, quest = "My Quest" }, "Tester")
	w.ns.Store:Prune("cards")
	local cards = w.ns.Store:GetCards("quest")
	equal(#cards, 1)
	equal(cards[1].player, "Tester")
	w.ns.Store:Prune("players")
	equal(w.ns.Store:GetMember("Buddy"), nil)
end)

-- ========= Dev mode (debug on): pretend players, recordings, test runs =====
-- Quest Party in dev mode (debug on): pretend players, recordings, test runs.
local function devWorld(saved)
	return Harness.new(saved or { switches = { chatEcho = false } }, nil, true)
end

test("your gear comes back to your own card from the channel, and your head comes first", function()
	local w = Harness.new()
	w.gear[1] = "|cffffffff|Hitem:1234::::::::20:::::::|h[Cap]|h|r"
	w:share() -- your gear goes out with how you stand, and comes back
	local member = w.ns.Store:GetMember("Tester")
	equal(member ~= nil and member.gear ~= nil, true)
	equal(member.gear[1] ~= nil and member.gear[1] ~= "", true)
	w.gear[1] = nil
	w:event("PLAYER_EQUIPMENT_CHANGED", 1)
	w:advance(w.ns.Timing.gearSeconds + 1) -- a change goes out under the gear wait
	equal(w.ns.Store:GetMember("Tester").gear[1], "")
	local heads = w.ns.PartyModel:Heads()
	equal(heads[1].name, "Tester")
	equal(heads[1].level, 20)
end)

test("dev mode's test runs: parties and recordings, over loopback", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	local runner = w.ns.ScenarioRunner
	equal(w.ns.Scenarios[1].id, "trio")
	runner:Select("party8")
	equal(runner:Go(true), true)
	equal(w.ns.Sharing.loopback, true)
	equal(w.ns.Dev.running, true)
	equal(#w.ns.Dev.order, 8)
	w:advance(30)
	runner:Select("evening")
	equal(runner:Go(true), true) -- stops the party, wipes, plays the recording
	equal(#w.ns.Dev.order, 2)
	runner:Stop()
	equal(runner:Running(), false)
end)

test("a pretend player's changed gear goes out as a whole set, after the scenario's wait", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	local dev = w.ns.Dev
	dev.gearSeconds = 15 -- real seconds, as the party scenarios set
	equal(dev:StartParty(1, 7, 10), true)
	local sends = 0
	local send = w.ns.Sharing.SendGear
	w.ns.Sharing.SendGear = function(...) sends = sends + 1 return send(...) end
	w:advance(60) -- arrived, and sent its gear with its hello
	local persona = dev.personas[dev.order[1]]
	equal(persona.here, true)
	persona.gearSentAt = dev.clock -- as if it had just gone out
	persona.gearPending = true -- then it swapped something
	sends = 0
	w:advance(5)
	equal(sends, 0) -- not yet: 15 seconds
	w:advance(11)
	equal(sends, 1)
	equal(persona.gearPending, nil)
end)

test("pretend players wear your gear, so a card fills like a real player's", function()
	local w = devWorld()
	w.gear[1] = "|cff1eff00|Hitem:3887:15:0:0:0:0:592:0:20|h[Hat of the Bear]|h|r"
	w.gear[16] = "|cffffffff|Hitem:2092:0:0:0:0:0:0:0:20|h[Worn Dagger]|h|r"
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartParty(2, 7, 10), true)
	w:advance(60)
	local name = w.ns.Dev.order[1]
	local persona = w.ns.Dev.personas[name]
	equal(persona.gear[1], "3887:15:592")
	equal(persona.gear[16], "2092:0:0")
	local card = w.ns.PartyModel:Card(name)
	equal(card.hasGear, true)
	local worn = {}
	for _, slot in ipairs(card.gear) do
		if slot.itemString then worn[slot.id] = slot.itemString end
	end
	equal(worn[1] ~= nil, true) -- arrived with their hello, as a whole set
	equal(worn[16] ~= nil, true)
end)

test("dev mode off quiets every dev tool, and loopback never holds back your own messages", function()
	local w = devWorld()
	w:share()
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartParty(2, 7, 10), true)
	-- During a loopback run your own messages still go out on the channel.
	local before = #w.sent
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	w:advance(5)
	local mine = 0
	for index = before + 1, #w.sent do
		local _, fields = w.ns.Protocol.Decode(w.sent[index].text)
		if not fields.as then mine = mine + 1 end
	end
	equal(mine > 0, true)
	-- Dev mode off: the run stops, loopback is off, and every tool refuses.
	w.env.SlashCmdList.QUESTPARTY("dev off")
	equal(w.ns.Dev.running, false)
	equal(w.ns.Sharing.loopback, false)
	equal(w.ns.ScenarioRunner:Go(false), false)
	w.env.SlashCmdList.QUESTPARTY("dev party 2")
	equal(w.ns.Dev.running, false)
	-- And pretend players are no longer shown.
	for _, head in ipairs(w.ns.PartyModel:Heads()) do
		assert(not head.virtual, "a pretend player shows with dev mode off: " .. head.name)
	end
end)

test("the same seed makes the same party", function()
	local w = devWorld()
	local first = w.ns.DevParty.Make(42, 5)
	local second = w.ns.DevParty.Make(42, 5)
	for index = 1, 5 do
		equal(first[index].name, second[index].name)
		equal(first[index].class, second[index].class)
		equal(first[index].level, second[index].level)
	end
	local other = w.ns.DevParty.Make(43, 5)
	assert(other[1].name ~= first[1].name or other[1].level ~= first[1].level, "another seed, another party")
end)

test("a dev party over the channel is marked as its pretend players, and shows when it comes back", function()
	local w = devWorld()
	w:share()
	w:advance(30) -- your own hello and its answers go first, as anyone's
	local before = #w.sent
	equal(w.ns.Dev:StartParty(2, 7, 1), true)
	w:advance(30)
	local hellos = {}
	for index = before + 1, #w.sent do
		local message = w.sent[index]
		local kind, fields = w.ns.Protocol.Decode(message.text)
		if fields.as then
			if kind == "H" then hellos[#hellos + 1] = { fields = fields, message = message } end
		end
	end
	equal(#hellos >= 1, true)
	local name = hellos[1].fields.as
	equal(w.ns.Dev.personas[name] ~= nil, true)
	-- The server sends it back; dev mode's panel shows the pretend player.
	echo(w, hellos[1].message.text)
	equal(w.ns.Session.peers[name].virtual, true)
	-- Too many for one character's send budget over the channel.
	local ok = w.ns.Dev:StartParty(20, 7, 1)
	equal(ok, false)
	-- A friend on the channel: their older Quest Party would take the
	-- pretend players for this character, so the channel is refused.
	w:hear("H", { c = "WARRIOR", l = 14, v = "0.1.2" }, "Tombert")
	local started, why = w.ns.Dev:StartParty(2, 7, 1)
	equal(started, false)
	assert(why:find("Tombert", 1, true), why)
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartParty(2, 7, 1), true)
end)

test("after your own reload, players already here are not welcomed again; a real arrival is", function()
	local w = Harness.new({ switches = { chatEcho = false } }, nil, nil, nil, { welcomes = true })
	w:share()
	local function Joins(name)
		local count = 0
		for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
			if entry.type == "joined" and entry.player == name then count = count + 1 end
		end
		return count
	end
	w:hear("H", { v = "0.3.5", c = "SHAMAN", l = 12 }, "Mcdouble Whopper")
	equal(Joins("Mcdouble Whopper"), 1)
	-- You reload: the session is new, what is saved stays.
	local w2 = Harness.new({ switches = { chatEcho = false } }, nil, nil, nil, { welcomes = true })
	w2.ns.db.lastHeard = w.ns.db.lastHeard
	w2:share()
	w2:hear("H", { v = "0.3.5", c = "SHAMAN", l = 12 }, "Mcdouble Whopper")
	local again = 0
	for _, entry in ipairs(w2.ns.Store:GetFeed(true)) do
		if entry.type == "joined" and entry.player == "Mcdouble Whopper" then again = again + 1 end
	end
	equal(again, 0) -- already here: no welcome
	equal(w2.ns.Session.peers["Mcdouble Whopper"] ~= nil, true) -- but back in the list
	-- Someone new is still welcomed.
	w2:hear("H", { v = "0.3.5", c = "MAGE", l = 5 }, "Newcomer")
	local newcomer = 0
	for _, entry in ipairs(w2.ns.Store:GetFeed(true)) do
		if entry.type == "joined" and entry.player == "Newcomer" then newcomer = newcomer + 1 end
	end
	equal(newcomer, 1)
end)

test("dev mode's Shared quest scenario: ten pretend players on one quest card, sections filling", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	local scenario
	for _, item in ipairs(w.ns.Scenarios) do if item.id == "sharedQuest" then scenario = item end end
	equal(scenario.run(), true)
	w:advance(150)
	local card
	for _, row in ipairs(w.ns.ViewModel:Build("party")) do
		if row.kind == "tracker" and row.quest == "Sharing the Land" then card = row end
	end
	if not card then
		local names = {}
		for _, row in ipairs(w.ns.ViewModel:Build("party")) do names[#names + 1] = row.kind .. ":" .. tostring(row.quest) end
		error("no card; rows: " .. table.concat(names, ", ") .. "; peers " .. #w.ns.Dev.order)
	end
	equal(#card.party >= 5, true) -- most have arrived
	equal(#card.sections, 3)
	local moved = 0
	for _, section in ipairs(card.sections) do
		for _, entry in ipairs(section.active) do if entry.have > 0 then moved = moved + 1 end end
		moved = moved + #section.done
	end
	equal(moved > 0, true)
	w.ns.Dev:Stop()
end)

test("dev mode's pretend players send health and power, which their bars show", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartParty(4, 2, 60), true)
	w:advance(30)
	local withVitals = 0
	for _, name in ipairs(w.ns.Dev.order) do
		local peer = w.ns.Session.peers[name]
		if peer and peer.vitals then
			withVitals = withVitals + 1
			assert(peer.vitals.h >= 5 and peer.vitals.h <= 100, "health in range")
			assert(peer.vitals.t == "MANA" or peer.vitals.t == "RAGE" or peer.vitals.t == "ENERGY", "a power by class")
		end
	end
	equal(withVitals >= 3, true)
	local bars = 0
	for _, bar in ipairs(w.ns.ViewModel:PartyBars()) do if bar.health then bars = bars + 1 end end
	equal(bars >= 3, true)
end)

test("in loopback a party of 20 plays for an hour without the network, and every player is seen", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartParty(20, 3, 60), true)
	w:advance(60)
	equal(#w.sent, 0) -- nothing on the wire
	local measure = w.ns.Dev:Measure()
	equal(measure.players, 20)
	equal(measure.failed, 0)
	-- Every one of the 20 was seen; those here now are exactly the ones whose
	-- session (20 to 120 pretend minutes) has not ended in the hour.
	local seen, staying = 0, 0
	for _, name in ipairs(w.ns.Dev.order) do
		if w.ns.Store:GetMember(name) then seen = seen + 1 end
		if w.ns.Dev.personas[name].leaveAt > w.ns.Dev.clock then staying = staying + 1 end
	end
	equal(seen, 20)
	equal(measure.peers, staying)
	assert(measure.feed > 20, "they have been busy: " .. measure.feed)
	assert(measure.feed <= 200, "the feed stays capped")
	local gear = 0
	for _, member in pairs(w.ns.db.members) do
		if member.gear then gear = gear + 1 end
	end
	assert(gear >= 10, "their gear arrived: " .. gear)
	w.ns.Dev:Wipe()
	equal(w.ns.Store:Counts().feed, 0)
	equal(w.ns.Session:Count(), 0)
end)

test("two recorded players play back together as 0.3.5 clients", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartRecording("all", 100), true)
	w:advance(10)
	local warrior = w.ns.Session.peers["Replay Warrior"]
	equal(warrior ~= nil, true)
	equal(warrior.version, "0.3.5")
	equal(warrior.race, "Scourge")
	equal(warrior.maxXP, 12900)
	equal(w.ns.Session.peers["Replay Paladin"] ~= nil, true)
	-- 0.3.5 sends profession skill-ups only, and tags a turn-in's XP.
	for _, entry in ipairs(w.ns.Store:GetFeed(true)) do
		assert(not (entry.type == "skill" and entry.player == "Replay Warrior"), "a weapon skill-up came through")
	end
	equal(w.ns.Sharing.failed or 0, 0)
end)

test("the recorded session plays back as a pretend player", function()
	local w = devWorld()
	w.ns.Bus:Fire("READY")
	w.ns.Sharing.loopback = true
	equal(w.ns.Dev:StartRecording("tirisfal", 100), true)
	w:advance(60)
	local peer = w.ns.Session.peers["Replay Paladin"]
	equal(peer ~= nil, true)
	equal(peer.class, "PALADIN")
	assert(peer.level >= 11, "the recorded level: " .. tostring(peer.level))
	assert(#w.ns.Store:GetFeed(true) > 5, "its feed came back")
	assert(#w.ns.Store:GetCards("quest") > 0, "its quests came back")
end)

-- ========= Party heads and the player card ==================================
test("race portraits use the game's atlas names", function()
	local w = Harness.new()
	local Atlas = w.ns.PartyModel.RaceAtlas
	equal(Atlas("Scourge", 3), "raceicon128-undead-female")
	equal(Atlas("NightElf", 2), "raceicon128-nightelf-male")
	equal(Atlas(nil, 2), nil)
	equal(Atlas("Human", 0), nil)
end)

test("heads come in arrival order, and players who left stay greyed when remembered", function()
	local w = Harness.new()
	w:share()
	w:hear("H", { c = "PRIEST", l = 14, r = "Dwarf", g = 3 }, "Second")
	w:advance(1)
	w:hear("H", { c = "ROGUE", l = 20 }, "Third")
	local heads = w.ns.PartyModel:Heads()
	equal(#heads, 3)
	equal(heads[1].name, "Tester") -- yours first
	equal(heads[2].name, "Second")
	equal(heads[2].atlas, "raceicon128-dwarf-female")
	equal(heads[2].here, true)
	equal(heads[3].name, "Third")
	w:event("CHAT_MSG_CHANNEL_LEAVE", "", "Second-TestRealm", "", "", "", "", 0, 5, "QuestFriends")
	heads = w.ns.PartyModel:Heads()
	equal(heads[2].name, "Third")
	equal(heads[3].name, "Second")
	equal(heads[3].here, false)
	w.ns.SetEnabled("rememberPlayers", false)
	equal(#w.ns.PartyModel:Heads(), 2)
	w.ns.SetEnabled("partyHeads", false)
	equal(#w.ns.PartyModel:Heads(), 0)
end)

test("a card's gear: one item's details, and the stats of all of them added up", function()
	local w = Harness.new()
	local items = {
		["item:3887:15:0:0:0:0:592"] = { "Hat of the Bear", "|Hitem:3887|h[Hat of the Bear]|h", 2, 22, 17, { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_STRENGTH_SHORT = 3, RESISTANCE0_NAME = 60 } },
		["item:25:0:0:0:0:0:0"] = { "Worn Shortsword", "|Hitem:25|h[Worn Shortsword]|h", 1, 2, 1, { ITEM_MOD_STRENGTH_SHORT = 1 } },
	}
	local stats = {}
	w.env.C_Item = {
		GetItemInfo = function(itemString)
			local item = items[itemString]
			if not item then return nil end
			stats[item[2]] = item[6]
			return item[1], item[2], item[3], item[4], item[5]
		end,
		GetItemStats = function(link) return stats[link] end,
	}
	w:share()
	w:hear("G", { c = "WARRIOR", s1 = "3887:15:592", s16 = "25:0:0", s5 = "999:0:0", n = 10 }, "Friend")
	local hat = w.ns.PartyModel:SlotDetails("Friend", 1)
	equal(hat.name, "Hat of the Bear")
	equal(hat.level, 22)
	equal(hat.required, 17)
	equal(hat.lines[1].label, "Strength")
	equal(hat.lines[2].label, "Stamina")
	equal(hat.lines[3].label, "Armor")
	equal(hat.lines[3].value, 60)
	equal(w.ns.PartyModel:SlotDetails("Friend", 2), nil) -- nothing worn there
	equal(w.ns.PartyModel:SlotDetails("Friend", 5).loading, true) -- not loaded yet
	local totals = w.ns.PartyModel:GearTotals("Friend")
	equal(totals.lines[1].label, "Strength")
	equal(totals.lines[1].value, 4)
	equal(totals.loading, true)
end)

test("your professions are read from the skill list, sent when they change, once it settles", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w:share()
	local lines = {
		{ skillID = 185, name = "Cooking", rank = 20, isHeader = false },
		{ skillID = 182, name = "Herbalism", rank = 12, isHeader = false },
		{ skillID = 98, name = "Language: Orcish", rank = 300, isHeader = false }, -- not a profession
	}
	w.env.C_SkillInfo = { GetNumSkillLines = function() return #lines end, GetSkillLineInfo = function(index) return lines[index] end }
	local P = w.ns.ProfessionsCollector
	P:Check()
	equal(P.text, "182.12,185.20")
	local function Presences()
		local count, last = 0, nil
		for _, message in ipairs(w.sent) do
			if message.text:match("^1:P:") then count = count + 1 last = message.text end
		end
		return count, last
	end
	local before = Presences()
	-- A burst of skill-ups: one read, a moment after, one presence.
	lines[1].rank = 21
	for _ = 1, 5 do P:Soon() end
	equal(Presences(), before)
	w:advance(w.ns.Timing.professionSeconds + 1)
	local after, text = Presences()
	equal(after, before + 1)
	equal(text:find("k=182.12,185.21", 1, true) ~= nil, true)
	-- Nothing changed: nothing sent.
	P:Soon()
	w:advance(w.ns.Timing.professionSeconds + 1)
	equal(Presences(), after)
	-- The skill row's mark shows the profession's own icon.
	equal(w.ns.ProfessionIcon("Cooking"), "Interface\\Icons\\INV_Misc_Food_15")
	equal(#w.ns.DecodeProfessions("185.20,999.5,182.12"), 2) -- unknown ids dropped
	w:ingest("skill", { skill = "Cooking", level = 22 }, "Friend")
	local found
	for _, row in ipairs(w.ns.ViewModel:Build("all")) do
		if row.mark == "skill" then found = row.markIcon end
	end
	equal(found, "Interface\\Icons\\INV_Misc_Food_15")
end)

test("your own head leads the side bar and opens your card", function()
	local w = Harness.new({ switches = { chatEcho = false } })
	w.gear[1] = "|cffffffff|Hitem:1234::::::::20:::::::|h[Cap]|h|r"
	w:share()
	w:hear("H", { v = "0.3.5", c = "SHAMAN", l = 12 }, "Friend")
	local heads = w.ns.PartyModel:Heads()
	equal(heads[1].name, w.ns.MyName())
	equal(heads[2].name, "Friend")
	equal(w.ns.PartyModel:Card(w.ns.MyName()) ~= nil, true)
	-- Your own gear is on your card, back from the channel as anyone's is.
	equal(w.ns.Store:GetMember(w.ns.MyName()).gear ~= nil, true)
end)

test("a player's card: level, XP, session XP, their quests, shared ones marked, and gear", function()
	local w = Harness.new()
	w:share()
	w.quests[1] = { questID = 356, title = "Rear Guard Patrol", objectives = {
		{ text = "Wandering Spirit slain: 3/8", numFulfilled = 3, numRequired = 8 },
	} }
	w:hear("H", { c = "WARRIOR", l = 14, x = 500, m = 9000, r = "Orc", g = 2, v = "0.3.5" }, "Friend")
	w:hear("E", { t = "xp", c = "WARRIOR", xp = 120, level = 14, currentXP = 620, maxXP = 9000 }, "Friend")
	w:hear("Q", { id = 356, quest = "Rear Guard Patrol", o1 = "Wandering Spirit", h1 = 5, n1 = 8 }, "Friend")
	w:hear("G", { c = "WARRIOR", s16 = "25:0:0" }, "Friend")
	w:advance(5)
	w:hear("Q", { id = 400, quest = "Only Theirs", o1 = "Boars", h1 = 1, n1 = 6 }, "Friend")
	local card = w.ns.PartyModel:Card("Friend")
	equal(card.quests[2].quest, "Only Theirs") -- newer, but not on your log
	equal(card.quests[2].mine, nil)
	-- Info: sections of lines, professions at their latest level.
	w:hear("E", { t = "skill", c = "WARRIOR", skill = "Mining", level = 26 }, "Friend")
	w:hear("E", { t = "skill", c = "WARRIOR", skill = "Mining", level = 27 }, "Friend")
	w:hear("E", { t = "skill", c = "WARRIOR", skill = "Cooking", level = 5 }, "Friend")
	local info = w.ns.PartyModel:Card("Friend").info
	equal(info[1].title, "Professions") -- first
	equal(info[2].title, "About")
	equal(#info[1].lines, 2)
	equal(info[1].lines[1].label:match("Mining$") ~= nil, true) -- highest first, with its icon
	equal(info[1].lines[1].label:find("Trade_Mining", 1, true) ~= nil, true)
	equal(info[1].lines[1].value, "27")
	equal(info[1].lines[2].label:match("Cooking$") ~= nil, true)
	-- All their professions, as they say them (a presence), not only those
	-- seen rising.
	w:hear("P", { c = "WARRIOR", l = 14, k = "185.30,186.27,182.12" }, "Friend")
	info = w.ns.PartyModel:Card("Friend").info
	equal(#info[1].lines, 3)
	equal(info[1].lines[1].label:match("Cooking$") ~= nil, true)
	equal(info[1].lines[1].value, "30")
	equal(info[1].lines[3].label:match("Herbalism$") ~= nil, true)
	equal(card.level, 14)
	equal(card.here, true)
	equal(card.version, "0.3.5")
	equal(card.xp.need, 9000)
	equal(card.sessionXP, 120)
	equal(card.todayXP, 120)
	equal(card.quests[1].quest, "Rear Guard Patrol")
	equal(card.quests[1].progress, "5/8")
	equal(card.quests[1].mine, "3/8") -- on your log too, so it comes first
	equal(card.hasGear, true)
	local mainHand
	for _, slot in ipairs(card.gear) do
		if slot.id == 16 then mainHand = slot end
	end
	equal(mainHand.itemString, "item:25:0:0:0:0:0:0")
	equal(mainHand.itemId, 25)
	equal(mainHand.column, "bottom")
	equal(#card.gear, 19)
	equal(w.ns.PartyModel:Card("Nobody"), nil)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
