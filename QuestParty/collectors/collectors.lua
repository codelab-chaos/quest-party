-- Collectors: turn this player's own game events into feed entries.
-- The events are the ones Quest Tweet listened to. Each entry is shown locally and
-- handed to the session to send to everyone we share with.
local _, ns = ...
local Bus = ns.Bus
local L = ns.L
local Patterns = ns.Patterns

local Collectors = {}
ns.Collectors = Collectors

-- A kill and the quest credit it earns arrive as two separate messages, in either
-- order. They are paired when they land within this many seconds of each other.
local KILL_LINK_SECONDS = 1.5
-- A quest leaving the log is an abandon unless a turn-in follows within this long.
local ABANDON_WAIT_SECONDS = 1

local questTitles = {} -- [questID] = title, kept so a turn-in can still name the quest
local turnedIn = {} -- [questID] = true, briefly, to tell a turn-in from an abandon
local lastKill, lastCredit
local recentKill -- the last kill the game named, for naming an XP gain
local recentTurnIn -- the last quest handed in, whose XP is told on its own row
local pendingDiscovery -- a place just found, held a moment for the XP it gives
local knownQuests, watchedQuests, progressSeen, pending = {}, {}, {}, {}
local lastQuestUpdate
local ready = false
local experience, experienceQueued
local levelTold -- the last level a level-up row was made for, so it is made once

-- Text the game marks as secret (some combat states) cannot be read by addons.
local function Readable(text)
	return type(text) == "string" and not (issecretvalue and issecretvalue(text))
end

local function Copy(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

-- Shows the entry in our own panel and sends it out. A type whose feature switch
-- is off is neither shown nor sent.
-- Everything of yours is sent to the channel, and shows in your own panel
-- when it comes back, exactly as anyone else's: you are a player like any
-- other, and without a channel there is no feed.

local function Emit(typeName, data)
	local def = ns.FeedTypes[typeName]
	if not def or not ns.IsEnabled(def.setting) then
		return
	end
	-- Out to the channel. It shows in your own feed when it comes back, read
	-- like everyone's (comms\\sharing.lua): the channel is the feed.
	Bus:Fire("ENTRY_OUTGOING", { type = typeName, data = Copy(data) })
end

-- ========= Quest log lookups ================================================
local function QuestTitle(questID)
	knownQuests[questID] = true
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if Readable(title) and title ~= "" then
		questTitles[questID] = title
	end
	return questTitles[questID] or L.UNKNOWN_QUEST
end

local ObjectiveName = ns.ObjectiveName

local function ReadableNumber(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function ReadExperience()
	local level, currentXP, maxXP = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
	if not ReadableNumber(level) or not ReadableNumber(currentXP) or not ReadableNumber(maxXP)
		or level < 1 or currentXP < 0 or maxXP < 0 or currentXP > maxXP then return end
	return { level = level, currentXP = currentXP, maxXP = maxXP }
end

-- The owner can provide a full mid-quest snapshot even if QP never saw acceptance.
-- Titles and objective counts come from the owner's log, not the receiver's log.
function Collectors:GetQuestSnapshot(onlyQuestID)
	local ids = {}
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID then
			knownQuests[info.questID] = true
			if Readable(info.title) and info.title ~= "" then questTitles[info.questID] = info.title end
		end
	end
	-- Watched quests can be hidden beneath collapsed headers in the log.
	for index = 1, C_QuestLog.GetNumQuestWatches() do
		local id = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
		if id then knownQuests[id] = true end
	end
	for id in pairs(knownQuests) do ids[id] = true end
	for _, card in ipairs(ns.Store:GetCards("quest")) do
		if card.player == ns.MyName() and card.data.questID then ids[card.data.questID] = true end
	end
	if onlyQuestID then ids = { [onlyQuestID] = true } end
	local snapshot = {}
	for id in pairs(ids) do
		local entries = (onlyQuestID or C_QuestLog.GetLogIndexForQuestID(id)) and C_QuestLog.GetQuestObjectives(id)
		local title = QuestTitle(id)
		if entries and title ~= L.UNKNOWN_QUEST then
			local quest = { questID = id, quest = title, objectives = {}, objectivesReady = true }
			for index, entry in ipairs(entries) do
				local name = ObjectiveName(entry.text)
				if not name or name == "" or not ReadableNumber(entry.numFulfilled) or not ReadableNumber(entry.numRequired) then
					quest.objectivesReady = false
				elseif entry.numRequired > 0 then
					quest.objectives[#quest.objectives + 1] = {
						index = index, objective = name, have = entry.numFulfilled, need = entry.numRequired,
					}
				end
			end
			snapshot[#snapshot + 1] = quest
		end
	end
	table.sort(snapshot, function(a, b) return a.questID < b.questID end)
	return snapshot
end

-- Counts may lag behind the info message. A unique objective identifies its quest
-- without requiring equal counts; ambiguous matches wait for an ID-bearing event.
local function QuestForObjective(objective, _have, need, hint) -- have: not needed to match
	local name = ObjectiveName(objective)
	if not name then return nil end
	local matches = {}
	for _, quest in ipairs(Collectors:GetQuestSnapshot(hint)) do
		for _, entry in ipairs(quest.objectives) do
			if entry.need == need and entry.objective:lower() == name:lower() then
				local match = { questID = quest.questID, quest = quest.quest, objective = entry.objective, objectiveIndex = entry.index }
				matches[#matches + 1] = match
			end
		end
	end
	if #matches == 1 then return matches[1] end
end

-- ========= Kill and credit pairing ==========================================
local function EmitKill(kill, quest, questID)
	Emit("kill", { mob = kill.mob, xp = kill.xp, quest = quest, questID = questID })
end

local function OnKill(mob, xp)
	local now = GetTime()
	if lastCredit and now - lastCredit.time <= KILL_LINK_SECONDS then
		EmitKill({ mob = mob, xp = xp }, lastCredit.quest, lastCredit.questID)
		lastCredit = nil
	else
		lastKill = { mob = mob, xp = xp, time = now }
	end
end

local function OnCredit(quest, questID, creditTime)
	local now = creditTime or GetTime()
	if lastKill and math.abs(now - lastKill.time) <= KILL_LINK_SECONDS then
		EmitKill(lastKill, quest, questID)
		lastKill = nil
	else
		lastCredit = { quest = quest, questID = questID, time = now }
	end
end

local function EmitProgress(quest, objective, have, need, creditTime, fromLog, objectiveIndex)
	watchedQuests[quest.questID] = true
	local seen = progressSeen[quest.questID] or {}
	progressSeen[quest.questID] = seen
	objectiveIndex = objectiveIndex or quest.objectiveIndex
	local key = objectiveIndex or objective:lower()
	local previous = seen[key]
	if previous and previous.have == have and previous.need == need and previous.objective == objective then return end
	-- A message can arrive before the log's new count. Do not immediately undo it.
	if fromLog and previous and have < previous.have and GetTime() - previous.time < 1 then return false end
	seen[key] = { have = have, need = need, objective = objective, time = GetTime() }
	ns.Store:IdentifyQuest(ns.MyName(), quest.questID, quest.quest, objective)
	Emit("quest_progress", { questID = quest.questID, quest = quest.quest, objectiveIndex = objectiveIndex, objective = objective, have = have, need = need })
	if have > 0 and (not previous or have > previous.have) then
		OnCredit(quest.quest, quest.questID, creditTime)
	end
end

local function ResolvePending(hint)
	local index = 1
	while index <= #pending do
		local update = pending[index]
		if GetTime() - update.time > 10 then
			table.remove(pending, index)
		else
			local match = QuestForObjective(update.objective, update.have, update.need, hint)
			if match then
				table.remove(pending, index)
				EmitProgress(match, match.objective, update.have, update.need, update.time)
			else
				index = index + 1
			end
		end
	end
end

local function RefreshQuest(questID)
	local retry
	for _, quest in ipairs(Collectors:GetQuestSnapshot(questID)) do
		for _, objective in ipairs(quest.objectives) do
			if EmitProgress(quest, objective.objective, objective.have, objective.need, nil, true, objective.index) == false then retry = true end
		end
	end
	if retry then
		C_Timer.After(1, function()
			if watchedQuests[questID] and not turnedIn[questID] then RefreshQuest(questID) end
		end)
	end
end

local function RepairSavedQuests()
	local player = ns.MyName()
	for _, quest in ipairs(Collectors:GetQuestSnapshot()) do
		ns.Store:IdentifyQuest(player, quest.questID, quest.quest)
	end
	for _, card in ipairs(ns.Store:GetCards("quest")) do
		if card.player == player and card.data.quest == L.UNKNOWN_QUEST then
			for name, objective in pairs(card.data.objectives) do
				local match = QuestForObjective(name, objective.have, objective.need)
				if match then ns.Store:IdentifyQuest(player, match.questID, match.quest, name) end
			end
		end
	end
end

-- Baseline each local quest once its log data is available. Later log changes
-- go through the normal collector, so genuine progress still produces events.
local function HydrateOwnQuests(force)
	if not ns.IsEnabled("quests") then return end
	for _, quest in ipairs(Collectors:GetQuestSnapshot()) do
		if quest.objectivesReady and not turnedIn[quest.questID] and (force or not progressSeen[quest.questID]) then
			-- Where it stands now, so later changes are new progress; your
			-- cards come from the channel (the quest states we send).
			local seen = {}
			for _, objective in ipairs(quest.objectives) do
				seen[objective.index] = { objective = objective.objective, have = objective.have, need = objective.need, time = GetTime() }
			end
			progressSeen[quest.questID], watchedQuests[quest.questID] = seen, true
			-- How it stands goes to the channel, which makes your card when it
			-- comes back (comms\\sharing.lua), as a friend's does.
			Bus:Fire("OWN_QUEST_READ", quest)
		end
	end
end

-- ========= Event handlers ===================================================
local handlers = {}

function handlers.QUEST_ACCEPTED(questID)
	Emit("quest_accepted", { questID = questID, quest = QuestTitle(questID) })
end

function handlers.QUEST_TURNED_IN(questID, xpReward)
	turnedIn[questID] = true
	recentTurnIn = { quest = QuestTitle(questID), time = GetTime() }
	Emit("quest_complete", { questID = questID, quest = QuestTitle(questID), xp = xpReward or 0 })
	progressSeen[questID], watchedQuests[questID] = nil, nil
end

function handlers.QUEST_REMOVED(questID)
	local title = QuestTitle(questID)
	watchedQuests[questID] = nil
	C_Timer.After(ABANDON_WAIT_SECONDS, function()
		if not turnedIn[questID] then
			Emit("quest_abandoned", { questID = questID, quest = title })
		end
		turnedIn[questID] = nil
		questTitles[questID] = nil
		knownQuests[questID], watchedQuests[questID], progressSeen[questID] = nil, nil, nil
	end)
end

function handlers.QUEST_WATCH_UPDATE(questID)
	knownQuests[questID], watchedQuests[questID] = true, true
	lastQuestUpdate = { questID = questID, time = GetTime() }
	ResolvePending(questID)
	RefreshQuest(questID)
end

function handlers.QUEST_LOG_UPDATE()
	ResolvePending()
	HydrateOwnQuests()
	for questID in pairs(watchedQuests) do
		if not turnedIn[questID] then RefreshQuest(questID) end
	end
	RepairSavedQuests()
end

-- Quest progress and discoveries arrive as on-screen info messages. The message is
-- the second argument on current clients and the first on old ones.
function handlers.UI_INFO_MESSAGE(first, second)
	local message = second or first
	if not Readable(message) then
		return
	end
	local objective, have, need = ns.ParseObjectiveProgress(message)
	if objective then
		have, need = tonumber(have), tonumber(need)
		local match = QuestForObjective(objective, have, need)
		if not match and lastQuestUpdate and GetTime() - lastQuestUpdate.time <= KILL_LINK_SECONDS then
			match = QuestForObjective(objective, have, need, lastQuestUpdate.questID)
		end
		if match then
			EmitProgress(match, match.objective, have, need, GetTime())
		else
			pending[#pending + 1] = { objective = objective, have = have, need = need, time = GetTime() }
			if #pending > 64 then table.remove(pending, 1) end
			C_Timer.After(0.1, function() ResolvePending() end)
		end
		return
	end
	-- A place found: held a moment so the XP it gives (the next XP update,
	-- or the game's own words) goes on its row, as a quest's does.
	local zone, xp = message:match(Patterns.discoveryXp)
	zone = zone or message:match(Patterns.discovery)
	if zone and not pendingDiscovery then
		pendingDiscovery = { zone = zone, xp = tonumber(xp), time = GetTime() }
		C_Timer.After(KILL_LINK_SECONDS, function()
			local found = pendingDiscovery
			pendingDiscovery = nil
			if found then Emit("discovery", { zone = found.zone, xp = found.xp }) end
		end)
	elseif zone and xp and pendingDiscovery and pendingDiscovery.zone == zone then
		pendingDiscovery.xp = tonumber(xp)
	end
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(text)
	if not Readable(text) then
		return
	end
	local mob, xp = text:match(Patterns.kill)
	if mob then
		recentKill = { mob = mob, time = GetTime() }
		OnKill(mob, tonumber(xp) or 0)
	end
end

-- The game's skill line category for a skill, by its name, or nil when the
-- skill list cannot say.
local function SkillCategory(name)
	local skills = C_SkillInfo
	if not (skills and skills.GetNumSkillLines and skills.GetSkillLineInfo) then
		return nil
	end
	for index = 1, skills.GetNumSkillLines() do
		local info = skills.GetSkillLineInfo(index)
		if info and not info.isHeader and info.name == name then
			return info.skillLineCategoryID
		end
	end
end

function handlers.CHAT_MSG_SKILL(text)
	if not Readable(text) then
		return
	end
	-- A profession learned: a distinct event of its own, not a skill-up.
	local learned = text:match(Patterns.skillLearned)
	if learned then
		local category = SkillCategory(learned)
		if (category and ns.ProfessionCategories[category]) or (not category and ns.ProfessionNamed(learned)) then
			Emit("skill_learned", { skill = learned })
		end
		return
	end
	local skill, level = text:match(Patterns.skill)
	-- Only professions. A skill the list cannot place is reported, as before.
	local category = skill and SkillCategory(skill)
	if category and not ns.ProfessionCategories[category] then
		return
	end
	if skill then
		Emit("skill", { skill = skill, level = tonumber(level) or 0 })
	end
end

-- A level-up row, once per level. Two things can tell of one: the game's
-- level-up event, and the XP reading after it (which sees the level go up).
-- In combat the event's level can be a value addons cannot read, so either
-- may be the one that knows; whichever comes first makes the row.
local function TellLevel(level)
	if not ReadableNumber(level) or (levelTold and level <= levelTold) then return end
	levelTold = level
	Emit("level", { level = level })
end

function handlers.PLAYER_LEVEL_UP(level)
	TellLevel(level)
end

function handlers.PLAYER_XP_UPDATE(unit)
	if unit ~= "player" or experienceQueued then return end
	experienceQueued = true
	-- Level-up and XP events can precede the API's new values. Read once on the
	-- next frame, after the level, XP and next-level requirement have settled.
	C_Timer.After(0, function()
		experienceQueued = nil
		local current = ReadExperience()
		if not current then return end
		local previous = experience
		experience = current
		if not previous or current.level < previous.level then return end
		if current.level > previous.level then
			TellLevel(current.level)
		end
		if current.level == previous.level then
			if current.currentXP <= previous.currentXP then return end
			current.xp = current.currentXP - previous.currentXP
		elseif current.level == previous.level + 1 and current.maxXP > 0 then
			current.xp = previous.maxXP - previous.currentXP + current.currentXP
		end
		-- Across multiple levels the intermediate requirements are unavailable.
		-- Report the new level and percentage without inventing an XP amount.
		-- A kill the game named a moment ago is what gave the XP.
		current.mob = ""
		if recentKill and GetTime() - recentKill.time <= KILL_LINK_SECONDS then
			current.mob = recentKill.mob
		end
		recentKill = nil
		-- XP from a quest just handed in: the quest's row already says it.
		if recentTurnIn and GetTime() - recentTurnIn.time <= KILL_LINK_SECONDS then
			current.quest = recentTurnIn.quest
		end
		recentTurnIn = nil
		-- XP from a place just found: on the discovery's row.
		if not current.quest and current.mob == "" and pendingDiscovery then
			current.discovery = pendingDiscovery.zone
			pendingDiscovery.xp = pendingDiscovery.xp or current.xp
		end
		Emit("xp", current)
	end)
end

function handlers.PLAYER_DEAD()
	local zone = GetRealZoneText()
	local level = UnitLevel("player")
	Emit("death", {
		zone = Readable(zone) and zone ~= "" and zone or L.UNKNOWN_ZONE,
		level = ReadableNumber(level) and level or 0,
	})
end

function handlers.ACHIEVEMENT_EARNED(achievementID)
	local _, name, points = GetAchievementInfo(achievementID)
	if name then
		Emit("achievement", { name = name, points = points or 0 })
	end
end

-- Runs one event through its handler. Also used by /qp test.
function Collectors:Handle(event, ...)
	local handler = handlers[event]
	if handler then
		handler(...)
	end
end

-- Replays sample events as if this character had just played them, the way
-- /qtweet test did. Nothing here touches the real quest log.
function Collectors:RunTest()
	if not ns.IsDebug() then
		return
	end
	for _, sample in ipairs(ns.CollectorSamples) do
		self:Handle(unpack(sample))
	end
end

Bus:On("READY", function()
	-- Your own records saved under the first name alone (before the surname
	-- was used) move to the full name the channel carries.
	local first = UnitName("player")
	if first ~= ns.MyName() then
		ns.Store:RenamePlayer(first, ns.MyName())
	end
	-- This character is yours: filed under your player id, so on your next
	-- character it has no tab of its own (ui\party-model.lua).
	ns.Store:SetPlayerId(ns.MyName(), ns.Sharing.PlayerId())
	ready = true
	experience = ReadExperience() -- establish a baseline without replaying old gains
	levelTold = experience and experience.level -- the level we start at is not news
	RepairSavedQuests()
	HydrateOwnQuests()
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		Collectors:Handle(event, ...)
	end)
end)

Bus:On("SETTING_CHANGED", function(id, enabled)
	if ready and enabled and (id == "quests" or id == "questDetails") then
		HydrateOwnQuests(true)
	end
end)
