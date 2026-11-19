-- Quest cards: how one player's quest card lays out its objectives on the
-- Quest tab, below its title (ui\panel.lua draws the title, the avatar and
-- the time). One component per layout, picked with the Quest cards slider
-- (ns.QuestCardStyles); each knows its own height and draws its own parts,
-- made on first use and hidden when another layout draws the row.
--   Height(data)            the body's height, under the title
--   Draw(row, data, kit)    lays the body out; kit is the panel's helpers:
--                           left, room (from the right), top (under the
--                           title), CreateBar, SetProgress
--   Hide(row)               hides its parts
--   hidesMark               it shows progress where the quest's mark goes
-- The List layout is the panel's own (a line and a bar per objective).
local _, ns = ...
local L = ns.L

local QuestCard = { layouts = {} }
ns.QuestCard = QuestCard

local LAYOUT = {
	segmentBar = 6, -- the segmented bar's height
	segmentGap = 2, -- between two segments
	countWidth = 44, -- the overall count right of the segmented bar
	line = 14, -- a line of text
	gridLine = 19, -- a grid cell: its name and count, then its bar
	gridBar = 3,
	gridGap = 10, -- between the grid's two columns
	ring = 30, -- the progress ring, in the mark's place
}

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"

local COLORS = {
	done = { 0.25, 0.85, 0.25 },
	going = { 1, 0.82, 0 },
	ringBack = { 0, 0, 0, 0.55 },
	ringGoing = { 1, 0.70, 0.10, 0.9 },
	ringDone = { 0.25, 0.85, 0.25, 0.9 },
}

-- An objective on one line: "Tanner slain 8/10", or a check and its name
-- once done.
local function Short(objective)
	if objective.done then
		return CHECK .. " " .. objective.name
	end
	return objective.name .. " " .. L.CARD_COUNT:format(objective.have, objective.need)
end

-- All of a quest's objectives on one line, finished ones collapsed.
local function OneLine(objectives)
	local parts = {}
	for _, objective in ipairs(objectives) do
		parts[#parts + 1] = Short(objective)
	end
	return table.concat(parts, "  |cff808080·|r  ")
end

local function Overall(objectives)
	local have, need = 0, 0
	for _, objective in ipairs(objectives) do
		have = have + math.min(objective.have, objective.need)
		need = need + objective.need
	end
	return have, need
end

-- A font string the layout owns on this row, made once.
local function Text(row, key, font)
	row.questCard = row.questCard or {}
	local text = row.questCard[key]
	if not text then
		text = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
		row.questCard[key] = text
	end
	return text
end

local function List(row, key)
	row.questCard = row.questCard or {}
	row.questCard[key] = row.questCard[key] or {}
	return row.questCard[key]
end

-- ========= Segmented: one bar, a segment per objective ======================
local segmented = {}

function segmented.Height(data)
	return 4 + LAYOUT.segmentBar + 4 + LAYOUT.line
end

function segmented.Draw(row, data, kit)
	local objectives = data.objectives
	local segments = List(row, "segments")
	local width = (row:GetWidth() > 0 and row:GetWidth() or 300) - kit.left - kit.room - LAYOUT.countWidth
	local count = math.max(1, #objectives)
	local each = (width - (count - 1) * LAYOUT.segmentGap) / count
	local top = kit.top - 4
	for index, objective in ipairs(objectives) do
		local bar = segments[index]
		if not bar then
			bar = kit.CreateBar(row)
			segments[index] = bar
		end
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", kit.left + (index - 1) * (each + LAYOUT.segmentGap), top)
		bar:SetSize(math.max(2, each), LAYOUT.segmentBar)
		kit.SetProgress(bar, { have = objective.have, need = objective.need }, true)
		bar:Show()
	end
	for index = #objectives + 1, #segments do segments[index]:Hide() end
	local have, need = Overall(objectives)
	local total = Text(row, "segmentCount", "GameFontNormalSmall")
	total:ClearAllPoints()
	total:SetPoint("RIGHT", row, "TOPRIGHT", -kit.room, top - LAYOUT.segmentBar / 2)
	total:SetJustifyH("RIGHT")
	total:SetText(need > 0 and L.CARD_COUNT:format(have, need) or "")
	total:SetTextColor(unpack(have >= need and COLORS.done or COLORS.going))
	total:Show()
	local line = Text(row, "segmentLine")
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", kit.left, top - LAYOUT.segmentBar - 4)
	line:SetPoint("RIGHT", row, "RIGHT", -kit.room, 0)
	line:SetText(#objectives > 0 and OneLine(objectives) or L.TRACKER_NO_OBJECTIVES)
	line:Show()
end

function segmented.Hide(row)
	for _, bar in ipairs(List(row, "segments")) do bar:Hide() end
	Text(row, "segmentCount"):Hide()
	Text(row, "segmentLine"):Hide()
end

-- ========= Grid: objectives two to a line, each with its bar ================
local grid = {}

function grid.Height(data)
	return math.ceil(math.max(1, #data.objectives) / 2) * LAYOUT.gridLine + 2
end

function grid.Draw(row, data, kit)
	local cells = List(row, "cells")
	local width = (row:GetWidth() > 0 and row:GetWidth() or 300) - kit.left - kit.room
	local cellWidth = (width - LAYOUT.gridGap) / 2
	for index, objective in ipairs(data.objectives) do
		local cell = cells[index]
		if not cell then
			cell = {
				name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
				count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
				bar = kit.CreateBar(row),
			}
			cell.name:SetJustifyH("LEFT")
			cell.name:SetWordWrap(false)
			cell.count:SetJustifyH("RIGHT")
			cells[index] = cell
		end
		local column, line = (index - 1) % 2, math.floor((index - 1) / 2)
		local x = kit.left + column * (cellWidth + LAYOUT.gridGap)
		local y = kit.top - line * LAYOUT.gridLine
		cell.count:ClearAllPoints()
		cell.count:SetPoint("TOPRIGHT", row, "TOPLEFT", x + cellWidth, y)
		cell.count:SetText(objective.done and CHECK or L.CARD_COUNT:format(objective.have, objective.need))
		cell.count:SetTextColor(unpack(objective.done and COLORS.done or COLORS.going))
		cell.name:ClearAllPoints()
		cell.name:SetPoint("TOPLEFT", row, "TOPLEFT", x, y)
		cell.name:SetPoint("RIGHT", cell.count, "LEFT", -4, 0)
		cell.name:SetText(objective.name)
		cell.name:SetTextColor(unpack(objective.done and COLORS.done or { 1, 1, 1 }))
		cell.bar:ClearAllPoints()
		cell.bar:SetPoint("TOPLEFT", row, "TOPLEFT", x, y - 13)
		cell.bar:SetSize(math.max(2, cellWidth), LAYOUT.gridBar)
		kit.SetProgress(cell.bar, { have = objective.have, need = objective.need }, true)
		for _, part in pairs(cell) do part:Show() end
	end
	for index = #data.objectives + 1, #cells do
		for _, part in pairs(cells[index]) do part:Hide() end
	end
end

function grid.Hide(row)
	for _, cell in ipairs(List(row, "cells")) do
		for _, part in pairs(cell) do part:Hide() end
	end
end

-- ========= Ring: overall progress in the mark's place =======================
local ring = { hidesMark = true }

function ring.Height(data)
	return LAYOUT.line + 2
end

-- The ring: a dark disc, a pie of progress over it (the game's cooldown
-- swipe, held still), and the percent in its middle.
local function Ring(row)
	row.questCard = row.questCard or {}
	local made = row.questCard.ring
	if made then return made end
	made = CreateFrame("Frame", nil, row)
	made:SetSize(LAYOUT.ring, LAYOUT.ring)
	made.back = made:CreateTexture(nil, "BACKGROUND")
	made.back:SetAllPoints()
	made.back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	made.back:SetVertexColor(unpack(COLORS.ringBack))
	made.pie = CreateFrame("Cooldown", nil, made, "CooldownFrameTemplate")
	made.pie:SetAllPoints()
	pcall(made.pie.SetDrawEdge, made.pie, false)
	pcall(made.pie.SetDrawBling, made.pie, false)
	pcall(made.pie.SetHideCountdownNumbers, made.pie, true)
	pcall(made.pie.SetReverse, made.pie, true)
	pcall(made.pie.SetSwipeTexture, made.pie, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	made.percent = made:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	made.percent:SetPoint("CENTER")
	row.questCard.ring = made
	return made
end

-- Holds the pie at a share: a cooldown that has run that far, paused.
local function HoldPie(pie, share, color)
	pcall(pie.SetSwipeColor, pie, unpack(color))
	local duration = 100
	pcall(pie.SetCooldown, pie, GetTime() - duration * (1 - share), duration)
	pcall(pie.Pause, pie)
end

function ring.Draw(row, data, kit)
	local have, need = Overall(data.objectives)
	local share = need > 0 and math.min(1, have / need) or 0
	local made = Ring(row)
	made:ClearAllPoints()
	made:SetPoint("CENTER", row.icon, "CENTER")
	made:SetFrameLevel(row:GetFrameLevel() + 4)
	HoldPie(made.pie, share, share >= 1 and COLORS.ringDone or COLORS.ringGoing)
	made.percent:SetText(math.floor(share * 100 + 0.5) .. "%")
	made:Show()
	local line = Text(row, "ringLine")
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", kit.left, kit.top - 1)
	line:SetPoint("RIGHT", row, "RIGHT", -kit.room, 0)
	line:SetText(#data.objectives > 0 and OneLine(data.objectives) or L.TRACKER_NO_OBJECTIVES)
	line:Show()
end

function ring.Hide(row)
	if row.questCard and row.questCard.ring then row.questCard.ring:Hide() end
	Text(row, "ringLine"):Hide()
end

-- ========= A party on one quest: a section per objective ===================
-- Each objective is a section: the players still working on it, the latest
-- to make progress first (a mini feed: they move up and flash), each with a
-- bar in their own color; at most PARTY.rows of them, the rest a scroll
-- away (the mouse wheel over the section). Those done with it collapse into
-- one completed bar under them. Used for any quest two or more are on,
-- whatever the Quest cards slider says.
local party = {}

local PARTY = {
	head = 15, -- the objective's name
	row = 16, -- one player working on it
	rows = 4, -- the most shown at once
	doneLine = 15, -- the completed bar
	gap = 5, -- between sections
	avatar = 12,
	nameWidth = 78,
	countWidth = 40,
	agoWidth = 30,
	doneAvatars = 8, -- the most small avatars on the completed bar
	flashSeconds = 3, -- progress this new flashes its row
}

local scrolls = {} -- quest~objective -> how far its section is scrolled
local flashed = {} -- quest~objective~player~have -> true once flashed

local function SectionHeight(section)
	return PARTY.head + math.min(#section.active, PARTY.rows) * PARTY.row + (#section.done > 0 and PARTY.doneLine or 0) + PARTY.gap
end

function party.Height(data)
	local height = 0
	for _, section in ipairs(data.sections) do
		height = height + SectionHeight(section)
	end
	return height
end

local function Avatar(parent, size)
	local texture = parent:CreateTexture(nil, "ARTWORK")
	texture:SetSize(size, size)
	ns.Look.Round(texture, parent)
	return texture
end

-- One player's line in a section, made once per slot.
local function PlayerLine(section, index, kit)
	section.lines = section.lines or {}
	local line = section.lines[index]
	if line then return line end
	line = CreateFrame("Frame", nil, section)
	line:SetHeight(PARTY.row)
	line.flash = line:CreateTexture(nil, "BACKGROUND")
	line.flash:SetAllPoints()
	line.flash:SetColorTexture(1, 1, 1, 0.18)
	line.flash:SetAlpha(0)
	line.pulse = line.flash:CreateAnimationGroup()
	local up = line.pulse:CreateAnimation("Alpha")
	up:SetFromAlpha(0) up:SetToAlpha(1) up:SetDuration(0.2)
	local down = line.pulse:CreateAnimation("Alpha")
	down:SetFromAlpha(1) down:SetToAlpha(0) down:SetDuration(0.9) down:SetStartDelay(0.2)
	line.avatar = Avatar(line, PARTY.avatar)
	line.avatar:SetPoint("LEFT", 2, 0)
	line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.name:SetPoint("LEFT", line.avatar, "RIGHT", 4, 0)
	line.name:SetWidth(PARTY.nameWidth)
	line.name:SetJustifyH("LEFT")
	line.name:SetWordWrap(false)
	line.ago = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	line.ago:SetPoint("RIGHT", -2, 0)
	line.ago:SetWidth(PARTY.agoWidth)
	line.ago:SetJustifyH("RIGHT")
	line.count = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line.count:SetPoint("RIGHT", line.ago, "LEFT", -4, 0)
	line.count:SetWidth(PARTY.countWidth)
	line.count:SetJustifyH("RIGHT")
	line.bar = kit.CreateBar(line)
	line.bar:SetPoint("LEFT", line.name, "RIGHT", 4, 0)
	line.bar:SetPoint("RIGHT", line.count, "LEFT", -4, 0)
	line.bar:SetHeight(5)
	section.lines[index] = line
	return line
end

local function Section(row, index)
	local list = List(row, "partySections")
	local section = list[index]
	if section then return section end
	section = CreateFrame("Frame", nil, row)
	section.head = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	section.head:SetPoint("TOPLEFT", 0, 0)
	section.head:SetJustifyH("LEFT")
	section.more = section:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	section.more:SetPoint("TOPRIGHT", -2, 0)
	-- The completed bar: everyone done with this objective, together.
	section.done = CreateFrame("Frame", nil, section)
	section.done:SetHeight(PARTY.doneLine - 2)
	section.done.back = section.done:CreateTexture(nil, "BACKGROUND")
	section.done.back:SetAllPoints()
	section.done.back:SetColorTexture(0.15, 0.55, 0.15, 0.35)
	section.done.text = section.done:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	section.done.text:SetPoint("LEFT", 4, 0)
	section.done.avatars = {}
	for slot = 1, PARTY.doneAvatars do
		local avatar = Avatar(section.done, PARTY.avatar - 2)
		avatar:SetPoint("RIGHT", -(4 + (slot - 1) * (PARTY.avatar - 4)), 0)
		section.done.avatars[slot] = avatar
	end
	section:SetScript("OnMouseWheel", function(self, delta)
		local key = self.key
		if not key then return end
		scrolls[key] = math.max(0, math.min(self.overflow or 0, (scrolls[key] or 0) - delta))
		if ns.Panel and ns.Panel.Refresh then ns.Panel:Refresh() end
	end)
	list[index] = section
	return section
end

function party.Draw(row, data, kit)
	local width = (row:GetWidth() > 0 and row:GetWidth() or 300) - kit.left - kit.room
	-- The title, with how many are on it and how many are done.
	row.title:SetText(data.title .. "  |cff9d9d9d" .. L.QUEST_PARTY_COUNT:format(#data.party, data.doneCount or 0) .. "|r")
	local y = kit.top
	local sections = List(row, "partySections")
	for index, info in ipairs(data.sections) do
		local section = Section(row, index)
		local key = (data.quest or "") .. "~" .. info.name
		local overflow = math.max(0, #info.active - PARTY.rows)
		local offset = math.min(scrolls[key] or 0, overflow)
		section.key, section.overflow = key, overflow
		section:EnableMouseWheel(overflow > 0)
		section:ClearAllPoints()
		section:SetPoint("TOPLEFT", row, "TOPLEFT", kit.left, y)
		section:SetSize(math.max(60, width), SectionHeight(info))
		section.head:SetText(info.name .. (info.need and info.need > 1 and ("  |cff9d9d9d" .. info.need .. "|r") or ""))
		section.more:SetText(overflow > 0 and L.QUEST_PARTY_MORE:format(offset + 1, math.min(#info.active, offset + PARTY.rows), #info.active) or "")
		local shown = 0
		for slot = 1, math.min(#info.active, PARTY.rows) do
			local entry = info.active[slot + offset]
			local line = PlayerLine(section, slot, kit)
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", 0, -(PARTY.head + (slot - 1) * PARTY.row))
			line:SetPoint("RIGHT", section, "RIGHT", 0, 0)
			ns.Look.SetPortrait(line.avatar, ns.PartyModel:Portrait(entry.name))
			line.name:SetText(ns.ColorName(entry.name, entry.class))
			line.count:SetText(L.CARD_COUNT:format(entry.have, entry.need))
			line.ago:SetText(ns.Ago(entry.ago))
			kit.SetProgress(line.bar, { have = entry.have, need = entry.need }, false)
			line.bar:SetStatusBarColor(ns.PlayerColors:For(entry.name)) -- their own color
			-- Just made progress: its line flashes, once.
			local mark = key .. "~" .. entry.name .. "~" .. entry.have
			if entry.ago <= PARTY.flashSeconds and not flashed[mark] then
				flashed[mark] = true
				line.pulse:Stop()
				line.pulse:Play()
			end
			line:Show()
			shown = slot
		end
		for slot = shown + 1, #(section.lines or {}) do section.lines[slot]:Hide() end
		-- Those done with it: one completed bar.
		if #info.done > 0 then
			section.done:ClearAllPoints()
			section.done:SetPoint("TOPLEFT", 0, -(PARTY.head + shown * PARTY.row + 1))
			section.done:SetPoint("RIGHT", section, "RIGHT", 0, 0)
			section.done.text:SetText(CHECK .. " " .. L.QUEST_PARTY_DONE:format(#info.done))
			for slot, avatar in ipairs(section.done.avatars) do
				local entry = info.done[slot]
				if entry then ns.Look.SetPortrait(avatar, ns.PartyModel:Portrait(entry.name)) end
				avatar:SetShown(entry ~= nil)
			end
			section.done:Show()
		else
			section.done:Hide()
		end
		section:Show()
		y = y - SectionHeight(info)
	end
	for index = #data.sections + 1, #sections do sections[index]:Hide() end
end

function party.Hide(row)
	for _, section in ipairs(List(row, "partySections")) do section:Hide() end
end

QuestCard.layouts.party = party
QuestCard.layouts.segmented = segmented
QuestCard.layouts.grid = grid
QuestCard.layouts.ring = ring

-- ========= Choosing =========================================================
-- The layout the slider picks, or nil for the panel's own List.
function QuestCard:Chosen()
	local step = ns.QuestCardStyles[math.floor(ns.GetSlider("questCardStyle") or 0)]
	return step and self.layouts[step.id] or nil
end

-- The layout for a row: a quest card one player is on, in the detailed view.
function QuestCard:For(data)
	if data.kind ~= "tracker" then return nil end
	if data.sections then return party end -- two or more on it
	if not data.objectives then return nil end
	return self:Chosen()
end

-- Hides every layout's parts but the one drawing this row.
function QuestCard:HideAll(row, except)
	if not row.questCard then return end
	for _, layout in pairs(self.layouts) do
		if layout ~= except then layout.Hide(row) end
	end
end
