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
local function Emit(typeName, data)
	local def = ns.FeedTypes[typeName]
	if not def or not ns.IsEnabled(def.setting) then
		return
	end
	Bus:Fire("ENTRY_OUTGOING", { type = typeName, data = Copy(data) })
	if ns.IsEnabled("showSelf") then
		local _, class = UnitClass("player")
		Bus:Fire("ENTRY_RECEIVED", { type = typeName, player = UnitName("player"), class = class, data = Copy(data) })
	end
end

-- ========= Quest log lookups ================================================
local function QuestTitle(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	if title then
		questTitles[questID] = title
	end
	return title or questTitles[questID] or L.UNKNOWN_QUEST
end

-- Finds which quest an objective line belongs to, by looking for a quest objective
-- with the same counts whose text contains the same words.
local function QuestForObjective(objective, have, need)
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID then
			questTitles[info.questID] = info.title
			for _, entry in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
				if entry.numRequired == need and entry.numFulfilled == have
					and Readable(entry.text) and entry.text:find(objective, 1, true) then
					return info.title
				end
			end
		end
	end
	return L.UNKNOWN_QUEST
end

-- ========= Kill and credit pairing ==========================================
local function EmitKill(kill, quest)
	Emit("kill", { mob = kill.mob, xp = kill.xp, quest = quest })
end

local function OnKill(mob, xp)
	local now = GetTime()
	if lastCredit and now - lastCredit.time <= KILL_LINK_SECONDS then
		EmitKill({ mob = mob, xp = xp }, lastCredit.quest)
		lastCredit = nil
	else
		lastKill = { mob = mob, xp = xp, time = now }
	end
end

local function OnCredit(quest)
	local now = GetTime()
	if lastKill and now - lastKill.time <= KILL_LINK_SECONDS then
		EmitKill(lastKill, quest)
		lastKill = nil
	else
		lastCredit = { quest = quest, time = now }
	end
end

-- ========= Event handlers ===================================================
local handlers = {}

function handlers.QUEST_ACCEPTED(questID)
	Emit("quest_accepted", { quest = QuestTitle(questID) })
end

function handlers.QUEST_TURNED_IN(questID, xpReward)
	turnedIn[questID] = true
	Emit("quest_complete", { quest = QuestTitle(questID), xp = xpReward or 0 })
end

function handlers.QUEST_REMOVED(questID)
	local title = QuestTitle(questID)
	C_Timer.After(ABANDON_WAIT_SECONDS, function()
		if not turnedIn[questID] then
			Emit("quest_abandoned", { quest = title })
		end
		turnedIn[questID] = nil
		questTitles[questID] = nil
	end)
end

-- Quest progress and discoveries arrive as on-screen info messages. The message is
-- the second argument on current clients and the first on old ones.
function handlers.UI_INFO_MESSAGE(first, second)
	local message = second or first
	if not Readable(message) then
		return
	end
	local objective, have, need = message:match(Patterns.progress)
	if objective then
		have, need = tonumber(have), tonumber(need)
		local quest = QuestForObjective(objective, have, need)
		Emit("quest_progress", { quest = quest, objective = objective, have = have, need = need })
		OnCredit(quest)
		return
	end
	local zone = message:match(Patterns.discoveryXp) or message:match(Patterns.discovery)
	if zone then
		Emit("discovery", { zone = zone })
	end
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(text)
	if not Readable(text) then
		return
	end
	local mob, xp = text:match(Patterns.kill)
	if mob then
		OnKill(mob, tonumber(xp) or 0)
	end
end

function handlers.CHAT_MSG_SKILL(text)
	if not Readable(text) then
		return
	end
	local skill, level = text:match(Patterns.skill)
	if skill then
		Emit("skill", { skill = skill, level = tonumber(level) or 0 })
	end
end

function handlers.PLAYER_LEVEL_UP(level)
	Emit("level", { level = level })
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
	local frame = CreateFrame("Frame")
	for event in pairs(handlers) do
		frame:RegisterEvent(event)
	end
	frame:SetScript("OnEvent", function(_, event, ...)
		Collectors:Handle(event, ...)
	end)
end)
