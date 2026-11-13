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
local function peer(world, name, channel)
	world:receive("H", { v = "0.1.0", c = "MAGE", l = 20, z = "Elwynn" }, channel, name)
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

test("old cards expire while feed history remains", function()
	local w = Harness.new()
	w:ingest("quest_accepted", { quest = "A Quest" })
	w:advance(w.ns.Timing.expireSeconds + w.ns.Timing.pruneSeconds)
	equal(#w.ns.Store:GetCards("quest"), 0)
	equal(#w.ns.Store:GetFeed(true), 1)
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

test("hiding own progress still allows outgoing sharing", function()
	local w = Harness.new()
	w.ns.SetEnabled("showSelf", false)
	w.ns.Session.peers.Friend = { link = true }
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.ns.Store:GetFeed(true), 0)
	equal(#w.sent, 1)
	equal(w.sent[1].target, "Friend")
end)

test("disabled event categories are neither stored nor shared", function()
	local w = Harness.new()
	w.ns.Session.peers.Friend = { link = true }
	w.ns.SetEnabled("levels", false)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.sent, 0)
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("collectors ignore secret and non-text messages", function()
	local w = Harness.new()
	w.ns.Collectors:Handle("UI_INFO_MESSAGE", 1, "<secret>")
	w.ns.Collectors:Handle("CHAT_MSG_SKILL", {})
	w.ns.Collectors:Handle("CHAT_MSG_COMBAT_XP_GAIN", nil)
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("localized message patterns escape punctuation and reject reordered arguments", function()
	local ns = Harness.new().ns
	local pattern = ns.FromFormat("Found [%s]: %d.")
	local name, count = ("Found [Copper]: 12."):match(pattern)
	equal(name, "Copper")
	equal(count, "12")
	equal(ns.FromFormat("%2$s: %1$d"), nil)
end)

test("detail chat is local, opt-in, and obeys the master chat switch", function()
	local w = Harness.new()
	progress(w, 1)
	equal(#w.chat, 0)
	w.ns.SetEnabled("chatDetails", true)
	progress(w, 2)
	equal(#w.chat, 1)
	assert(w.chat[1]:find("2/3", 1, true))
	w.ns.SetEnabled("chatEcho", false)
	progress(w, 1)
	equal(#w.chat, 1)
	equal(#w.sent, 0)
end)

test("unlinked strangers cannot connect by whisper or inject feed entries", function()
	local w = Harness.new()
	peer(w, "Stranger", "WHISPER")
	w:receive("E", { t = "level", level = 99 }, "WHISPER", "Stranger")
	equal(w.ns.Session:Count(), 0)
	equal(#w.ns.Store:GetFeed(true), 0)
end)

test("linked friends' messages reach the feed", function()
	local w = Harness.new()
	w.ns.db.links.Friend = true
	peer(w, "Friend", "WHISPER")
	w:receive("E", { t = "level", level = 21 }, "WHISPER", "Friend")
	equal(w.ns.Session:Count(), 1)
	equal(w.ns.Store:GetFeed(true)[1].player, "Friend")
end)

test("sharing broadcasts once to the group and once to an ungrouped friend", function()
	local w = Harness.new()
	w.party.Alice, w.party.Bob = true, true
	w.ns.Session.peers = { Alice = { party = true, link = true }, Bob = { party = true }, Friend = { link = true } }
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.sent, 2)
	local channels = {}
	for _, sent in ipairs(w.sent) do channels[sent.channel] = sent end
	assert(channels.PARTY)
	equal(channels.WHISPER.target, "Friend")
end)

test("sharing off keeps local progress but sends nothing", function()
	local w = Harness.new()
	w.ns.Session.peers.Friend = { link = true }
	w.ns.SetEnabled("share", false)
	w.ns.Collectors:Handle("PLAYER_LEVEL_UP", 21)
	equal(#w.sent, 0)
	equal(#w.ns.Store:GetFeed(true), 1)
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

test("sample party replays into every filter without sending real messages", function()
	local w = Harness.new()
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
	equal(#w.sent, 0)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
