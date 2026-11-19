-- Report view: the 123 tab. Two dropdowns over glass gauges filled from the
-- bottom, each kind of activity in its own color (data\stats.lua, color),
-- never sliced up by player: a gauge per kind (all players: the party's
-- total, the split by player in its tooltip; one player: their share of the
-- party), or with one kind chosen, a gauge per player. Each gauge has its
-- label above it and its total in the middle of the glass. Player names take
-- colors from a palette of primaries (ns.PlayerPalette), in the order the
-- report lists them, so no two share one.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

-- stage: what clicking the party's fuel steps through: "whole" (one vat),
-- "sliced" (by kind), "everyone" (each player's fuel by kind, a line each).
local ReportView = { kind = nil, player = nil, stage = "whole" }
local STAGES = { whole = "sliced", sliced = "everyone", everyone = "whole" }
ns.ReportView = ReportView

local DrawEveryone -- each player's fuel by kind (defined with the views)

local LAYOUT = {
	filters = 26,
	dropdown = 140,
	home = 22, -- the Party Fuel icon beside the menus
	cellMinWidth = 44,
	cellMinHeight = 144,
	gap = 6,
	labelHeight = 28, -- above the gauge
	vialWidth = 44, -- the widest a gauge gets (narrower in a narrow cell)
	vialMaxHeight = 240,
	-- The vat grows with the panel: this share of its width (within the
	-- least and most), all of its height, and its numbers with it.
	vatShare = 0.6,
	question = 18, -- "What is Party Fuel?" under the whole vat
	vatMinWidth = 110,
	vatMaxWidth = 360,
	vatFontPer = 7, -- the vat's number: its width over this (within 18 to 40)
	sectionGap = 3, -- between the sliced vat's sections
	sectionMin = 24, -- the least a section gets, so its line fits
	sectionFontPer = 11, -- a section's line: the vat's width over this (within 12 to 22)
	vialFont = 13,
	glassInset = 3,
	scrollbar = 16,
	pad = 4,
	redrawSeconds = 0.5, -- many tallies, one redraw
}

local COLORS = {
	track = { 0.025, 0.035, 0.055, 0.85 },
	fill = { 0.80, 0.65, 0.20, 0.9 }, -- a gauge for no one player
	total = { 1, 1, 1 }, -- the number in the middle of a gauge
	label = { 0.85, 0.85, 0.85 },
	glass = { 0.60, 0.68, 0.77, 0.65 },
	muted = { 0.5, 0.5, 0.55 },
	vat = { 0.85, 0.12, 0.10 }, -- the party's fuel: a big red vat
}

local VIAL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local frame, home, chart, content
local HOME_ICON = "Interface\\Icons\\INV_Potion_51" -- a red flask: the party's fuel
local kindPicker, playerPicker
local rows = {}

-- A player's color: the palette's entry at their place in the report's list
-- of players (data\themes.lua).
-- A player's own color (colors.lua), as their XP bar and portrait ring.
local function PlayerColor(name)
	return ns.PlayerColors:For(name)
end

local function KindOf(id)
	for _, kind in ipairs(ns.StatKinds) do
		if kind.id == id then return kind end
	end
end

local function KindColor(id)
	for _, kind in ipairs(ns.StatKinds) do
		if kind.id == id then return kind.color end
	end
	return COLORS.fill
end

local function Colored(name)
	local r, g, b = PlayerColor(name)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end

-- ========= Dropdowns ========================================================
-- A dropdown of choices, or (without the game's menus) a button that steps
-- through them. choices() gives { { value, label } }; get and set the choice.
local function Picker(parent, width, choices, get, set)
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetWidth(width)
		dropdown:SetupMenu(function(_, root)
			for _, choice in ipairs(choices()) do
				root:CreateRadio(choice.label, function(value) return get() == value end, function(value) set(value) end, choice.value)
			end
		end)
		dropdown.Refresh = function(self)
			if self.GenerateMenu then self:GenerateMenu() end
		end
		return dropdown
	end
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button.Refresh = function(self)
		for _, choice in ipairs(choices()) do
			if choice.value == get() then self:SetText(choice.label) end
		end
	end
	button:SetScript("OnClick", function(self)
		local list = choices()
		for index, choice in ipairs(list) do
			if choice.value == get() then
				set(list[index % #list + 1].value)
				break
			end
		end
		self:Refresh()
	end)
	return button
end

local ALL = "\001all" -- the "all" choice: not a kind or a name anyone has

local function KindChoices()
	local list = { { value = ALL, label = L.REPORT_ALL_TYPES } }
	for _, kind in ipairs(ns.Report:Kinds()) do
		list[#list + 1] = { value = kind.id, label = kind.name }
	end
	return list
end

local function PlayerChoices()
	local list = { { value = ALL, label = L.REPORT_ALL_PLAYERS } }
	for _, name in ipairs(ns.Report:Players()) do
		list[#list + 1] = { value = name, label = name }
	end
	return list
end

-- ========= The graph ========================================================
local function Row(index)
	local row = rows[index]
	if row then return row end
	row = CreateFrame("Frame", nil, content)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetJustifyH("CENTER")
	row.label:SetWordWrap(true)
	row.label:SetNonSpaceWrap(true)
	row.label:SetTextColor(unpack(COLORS.label))
	-- The label on top, then the gauge, its total in the middle of it.
	row.label:SetPoint("TOP", 0, 0)
	row.label:SetHeight(LAYOUT.labelHeight)
	row.label:SetJustifyV("BOTTOM")
	row.glass = CreateFrame("Frame", nil, row, "BackdropTemplate")
	row.glass:SetBackdrop(VIAL_BACKDROP)
	row.glass:SetBackdropColor(unpack(COLORS.track))
	row.glass:SetBackdropBorderColor(unpack(COLORS.glass))
	row.glass:SetPoint("TOP", 0, -(LAYOUT.labelHeight + 4))
	row.track = CreateFrame("Frame", nil, row.glass)
	row.track:SetPoint("BOTTOMLEFT", LAYOUT.glassInset, LAYOUT.glassInset)
	-- On the liquid's own frame, on its top layer: drawn over the liquid, not
	-- under it.
	row.value = row.track:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.value:SetDrawLayer("OVERLAY", 7)
	local font, size = row.value:GetFont()
	row.value:SetFont(font, size, "OUTLINE") -- reads over any color of liquid
	row.value:SetPoint("CENTER", row.glass, "CENTER", 0, 0)
	row.value:SetJustifyH("CENTER")
	row.value:SetWordWrap(true)
	-- Under the vat's number: what was gained lately ("+340 last hour").
	row.recent = row.track:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.recent:SetDrawLayer("OVERLAY", 7)
	local recentFont, recentSize = row.recent:GetFont()
	row.recent:SetFont(recentFont, recentSize, "OUTLINE")
	row.recent:SetPoint("TOP", row.value, "BOTTOM", 0, -4)
	local shine = row.track:CreateTexture(nil, "OVERLAY")
	shine:SetPoint("TOPLEFT", 1, 0)
	shine:SetPoint("BOTTOMLEFT", 1, 0)
	shine:SetWidth(2)
	shine:SetColorTexture(1, 1, 1, 0.18)
	local edge = row.track:CreateTexture(nil, "OVERLAY")
	edge:SetPoint("TOPRIGHT", -1, 0)
	edge:SetPoint("BOTTOMRIGHT", -1, 0)
	edge:SetWidth(1)
	edge:SetColorTexture(1, 1, 1, 0.08)
	row.marks = {}
	for mark = 1, 3 do
		local tick = row.track:CreateTexture(nil, "OVERLAY")
		tick:SetSize(5, 1)
		tick:SetColorTexture(0.85, 0.90, 1, 0.30)
		row.marks[mark] = tick
	end
	row.surface = row.track:CreateTexture(nil, "OVERLAY", nil, 1)
	row.surface:SetHeight(1)
	row.surface:SetColorTexture(1, 1, 1, 0.55)
	row.parts = {}
	row:EnableMouse(true)
	row:SetScript("OnEnter", function(self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tip.title)
		for _, line in ipairs(self.tip.lines) do
			if line[2] == "" then
				GameTooltip:AddLine(line[1], 0.8, 0.8, 0.8, true) -- a note: wraps
			else
				GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 0.82, 0)
			end
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(self)
		if self.onClick then self.onClick() end
	end)
	rows[index] = row
	return row
end

-- Liquid parts are { fraction, r, g, b }, stacked from the bottom upward.
local function Fill(row, parts)
	local width = row.track:GetWidth() or 0
	local height = row.track:GetHeight() or 0
	local filled = 0
	for index, part in ipairs(parts) do
		local texture = row.parts[index]
		if not texture then
			texture = row.track:CreateTexture(nil, "ARTWORK")
			texture:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
			-- Turn the gloss across the tube, leaving the geometry vertical.
			texture:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
			row.parts[index] = texture
		end
		local bottom = math.floor(height * filled + 0.5)
		filled = math.min(1, filled + math.max(0, part[1]))
		local top = math.floor(height * filled + 0.5)
		texture:ClearAllPoints()
		texture:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT", 0, bottom)
		texture:SetSize(width, math.max(1, top - bottom))
		texture:SetVertexColor(part[2], part[3], part[4], 0.9)
		texture:SetShown(top > bottom)
	end
	for index = #parts + 1, #row.parts do
		row.parts[index]:Hide()
	end
	row.surface:ClearAllPoints()
	row.surface:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT", 0, math.max(0, math.floor(height * filled + 0.5) - 1))
	row.surface:SetWidth(width)
	row.surface:SetShown(filled > 0)
end

local function Number(value)
	return ns.Comma(math.floor(value + 0.5))
end

-- A total short enough for a gauge: 9,999, then 74.3k, then 1.2M. The full
-- number is in the tooltip.
local function Short(value)
	value = math.floor(value + 0.5)
	if value < 10000 then return ns.Comma(value) end
	if value < 1000000 then return (("%.1fk"):format(value / 1000):gsub("%.0k", "k")) end
	return (("%.1fM"):format(value / 1000000):gsub("%.0M", "M"))
end
ReportView.Short = Short

local function SetValueFont(row, size)
	local font = row.value:GetFont()
	row.value:SetFont(font or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
end

-- The sliced vat's sections: one per kind with any, bottom up in the kinds'
-- order, each as tall as its share of the fuel (but never less than
-- sectionMin), with a small gap between. Its number and name in the middle,
-- on one line.
local function Section(row, index)
	row.sections = row.sections or {}
	local section = row.sections[index]
	if section then return section end
	section = CreateFrame("Frame", nil, row.track)
	section.fill = section:CreateTexture(nil, "ARTWORK")
	section.fill:SetAllPoints()
	section.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	section.fill:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) -- the gloss across, as the vials'
	-- One line, the number and its name ("451 Kills"): easy to read.
	section.text = section:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	section.text:SetPoint("LEFT", 4, 0)
	section.text:SetPoint("RIGHT", -4, 0)
	section.text:SetJustifyH("CENTER")
	section.text:SetWordWrap(false)
	row.sections[index] = section
	return section
end

local function HideSections(row, from)
	for index = from or 1, #(row.sections or {}) do
		row.sections[index]:Hide()
	end
end

-- The least a section gets: room for its line at the vat's font size.
local function SectionMin(row)
	return math.max(LAYOUT.sectionMin, (row.sectionFont or 14) + 10)
end

-- Fills the vat's track with sections: items are { text, color, weight },
-- bottom up, each as tall as its share of the weights (never less than
-- sectionMin), with a small gap between.
local function DrawSections(row, items)
	local height = row.track:GetHeight() or 0
	local width = row.track:GetWidth() or 0
	local least = SectionMin(row)
	local space = height - math.max(0, #items - 1) * LAYOUT.sectionGap
	local spare = math.max(0, space - #items * least)
	local total = 0
	for _, item in ipairs(items) do total = total + math.max(0, item.weight) end
	local bottom = 0
	for index, item in ipairs(items) do
		local section = Section(row, index)
		local size = least + (total > 0 and spare * (math.max(0, item.weight) / total) or spare / #items)
		section:ClearAllPoints()
		section:SetPoint("BOTTOMLEFT", row.track, "BOTTOMLEFT", 0, bottom)
		section:SetSize(width, math.max(1, size))
		section.fill:SetVertexColor(item.color[1], item.color[2], item.color[3], 0.92)
		local font = section.text:GetFont()
		section.text:SetFont(font or "Fonts\\FRIZQT__.TTF", row.sectionFont or 14, "OUTLINE")
		section.text:SetText(item.text)
		section:Show()
		bottom = bottom + size + LAYOUT.sectionGap
	end
	HideSections(row, #items + 1)
end

-- The tall a vat must be to hold these sections, each at least its least.
local function SectionsHeight(row, count)
	return count * SectionMin(row) + math.max(0, count - 1) * LAYOUT.sectionGap + LAYOUT.glassInset * 2
end

-- One wide vat in the middle: its label above, and either one liquid with a
-- number in the middle (whole) or sections (items). Taller than the view when
-- its sections need it; the view scrolls then.
-- "What is Party Fuel?": a link under the whole vat, and what it says.
local FUEL_ABOUT = ns.Globals.popup("FUEL_ABOUT")
StaticPopupDialogs[FUEL_ABOUT] = {
	text = L.FUEL_ABOUT .. "\n\n" .. L.FUEL_ABOUT_HOW,
	button1 = OKAY,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local question
local function Question()
	if question then return question end
	question = CreateFrame("Button", nil, content)
	question:SetHeight(LAYOUT.question)
	question.text = question:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	question.text:SetPoint("CENTER")
	question.text:SetText(L.FUEL_QUESTION)
	question:SetWidth(math.ceil(question.text:GetStringWidth() or 120) + 12)
	question:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
	question:SetScript("OnClick", function() StaticPopup_Show(FUEL_ABOUT, ReportView.fuelText or "0") end)
	return question
end

local function DrawVat(available, height, label, whole, items, tip, onClick, asking)
	local row = Row(1)
	local width = math.min(available, math.max(LAYOUT.vatMinWidth, math.min(LAYOUT.vatMaxWidth, available * LAYOUT.vatShare)))
	local vatHeight = height - LAYOUT.labelHeight - 8 - (asking and LAYOUT.question + 4 or 0)
	row.fontSize = math.floor(math.max(18, math.min(40, width / LAYOUT.vatFontPer)))
	row.sectionFont = math.floor(math.max(12, math.min(22, width / LAYOUT.sectionFontPer)))
	if items then
		vatHeight = math.max(vatHeight, SectionsHeight(row, #items))
	end
	local rowHeight = vatHeight + LAYOUT.labelHeight + 8
	content:SetSize(available, math.max(height, rowHeight))
	local maxScroll = math.max(0, rowHeight - height)
	chart:SetVerticalScroll(math.min(chart:GetVerticalScroll(), maxScroll))
	chart.ScrollBar:SetShown(maxScroll > 0)
	row:ClearAllPoints()
	row:SetPoint("TOP", content, "TOP", 0, 0)
	row:SetSize(width, rowHeight)
	row.label:SetWidth(width)
	row.label:SetText(label)
	row.glass:SetSize(width - 8, vatHeight)
	row.track:SetSize(width - 8 - LAYOUT.glassInset * 2, vatHeight - LAYOUT.glassInset * 2)
	for index, mark in ipairs(row.marks) do
		mark:ClearAllPoints()
		mark:SetPoint("RIGHT", row.track, "BOTTOMRIGHT", 0, row.track:GetHeight() * index / 4)
	end
	if items then
		Fill(row, {})
		DrawSections(row, items)
		row.value:SetText("")
	else
		HideSections(row)
		if not whole then row.recent:Hide() end
		Fill(row, { { whole.fill, unpack(whole.color) } })
		SetValueFont(row, row.fontSize)
		row.value:SetWidth(width)
		row.value:SetTextColor(unpack(whole.muted and COLORS.muted or COLORS.total))
		row.value:SetText(whole.text)
		row.recent:SetText(whole.recent or "")
		row.recent:SetShown(whole.recent ~= nil)
	end
	row.tip = tip
	row.onClick = onClick
	row:Show()
	for index = 2, #rows do
		rows[index]:Hide()
	end
	-- Under the whole vat only: what is Party Fuel?
	if asking then
		local link = Question()
		link:ClearAllPoints()
		link:SetPoint("TOP", row.glass, "BOTTOM", 0, -4)
		link:Show()
	elseif question then
		question:Hide()
	end
end

-- The sections of each view: a kind in its color, or a player in theirs.
local function KindItems(report, withShare)
	local items = {}
	for _, data in ipairs(report.rows) do
		if data.value > 0 then
			local text = L.FUEL_SECTION:format(Short(data.value), data.label)
			if withShare then text = text .. L.FUEL_SHARE:format(math.floor((data.share or 0) * 100 + 0.5)) end
			-- Sized by fuel: the count by its kind's weight.
			local kind = KindOf(data.id)
			local weight = data.fuel or (data.value * (kind and kind.fuel or 1))
			items[#items + 1] = { text = text, color = KindColor(data.id), weight = weight }
		end
	end
	return items
end

local function PlayerItems(report)
	local items = {}
	for _, data in ipairs(report.rows) do
		local r, g, b = PlayerColor(data.label)
		items[#items + 1] = { text = L.FUEL_SECTION:format(Short(data.value), data.label), color = { r, g, b }, weight = data.value }
	end
	return items
end

-- ========= Everyone =========================================================
-- Each player's fuel, a line each, most first: their name and fuel, then a
-- bar sliced by kind (each kind's width its share of their fuel, with its
-- number where it fits; all of it on hover). Over them, a link for each
-- player that scrolls to them, and one back to the party's fuel. Clicking
-- a player's bar opens their own view.
local EVERYONE = {
	nameHeight = 16,
	barHeight = 22,
	gap = 8,
	link = 16, -- a link's height
	linkGap = 10,
	sectionMinText = 46, -- a section narrower than this shows no number
}

local everyonePool, linkPool = {}, {}

local function EveryoneRow(index)
	local line = everyonePool[index]
	if line then return line end
	line = CreateFrame("Button", nil, content)
	line:SetHeight(EVERYONE.nameHeight + EVERYONE.barHeight)
	line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	line.name:SetPoint("TOPLEFT", 0, 0)
	line.total = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.total:SetPoint("TOPRIGHT", 0, 0)
	line.bar = CreateFrame("Frame", nil, line)
	line.bar:SetPoint("TOPLEFT", 0, -EVERYONE.nameHeight)
	line.bar:SetPoint("TOPRIGHT", 0, -EVERYONE.nameHeight)
	line.bar:SetHeight(EVERYONE.barHeight)
	line.back = line.bar:CreateTexture(nil, "BACKGROUND")
	line.back:SetAllPoints()
	line.back:SetColorTexture(unpack(COLORS.track))
	line.parts = {}
	line:SetScript("OnEnter", function(self)
		if not self.person then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(Colored(self.person.name) .. ": " .. Number(self.person.fuel))
		for _, kind in ipairs(self.person.kinds) do
			GameTooltip:AddDoubleLine(kind.label, L.FUEL_LINE:format(Number(kind.value), Number(kind.fuel)), 1, 1, 1, 1, 0.82, 0)
		end
		GameTooltip:AddLine(L.FUEL_XP_EXPLAIN, 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine(L.FUEL_PLAYER_TIP, 0.75, 0.75, 1)
		GameTooltip:Show()
	end)
	line:SetScript("OnLeave", function() GameTooltip:Hide() end)
	line:SetScript("OnClick", function(self)
		if not self.person then return end
		ReportView.player, ReportView.kind = self.person.name, nil
		ReportView:Draw()
	end)
	everyonePool[index] = line
	return line
end

local function Part(line, index)
	local part = line.parts[index]
	if part then return part end
	part = CreateFrame("Frame", nil, line.bar)
	part.fill = part:CreateTexture(nil, "ARTWORK")
	part.fill:SetAllPoints()
	part.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	part.text = part:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	part.text:SetPoint("CENTER")
	local font, size = part.text:GetFont()
	part.text:SetFont(font or "Fonts\\FRIZQT__.TTF", size or 10, "OUTLINE")
	part.text:SetWordWrap(false)
	line.parts[index] = part
	return part
end

local function Link(index, onClick)
	local link = linkPool[index]
	if not link then
		link = CreateFrame("Button", nil, content)
		link:SetHeight(EVERYONE.link)
		link.text = link:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		link.text:SetPoint("LEFT")
		link:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
		linkPool[index] = link
	end
	link:SetScript("OnClick", onClick)
	return link
end

local function HideEveryone(fromLine, fromLink)
	for index = fromLine or 1, #everyonePool do everyonePool[index]:Hide() end
	for index = fromLink or 1, #linkPool do linkPool[index]:Hide() end
end

DrawEveryone = function(available, height)
	for _, row in ipairs(rows) do row:Hide() end
	if question then question:Hide() end
	local everyone = ns.Report:Everyone()
	-- The links: back to the party's fuel, then each player, wrapping.
	local x, y, linkCount = 0, 0, 0
	local tops = {}
	local function AddLink(text, onClick)
		linkCount = linkCount + 1
		local link = Link(linkCount, onClick)
		link.text:SetText(text)
		local width = math.ceil(link.text:GetStringWidth() or 40) + 4
		if x > 0 and x + width > available then
			x, y = 0, y + EVERYONE.link
		end
		link:SetWidth(width)
		link:ClearAllPoints()
		link:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
		link:Show()
		x = x + width + EVERYONE.linkGap
	end
	for index, person in ipairs(everyone) do
		AddLink(Colored(person.name), function()
			chart:SetVerticalScroll(math.min(tops[index] or 0, math.max(0, content:GetHeight() - chart:GetHeight())))
		end)
	end
	local top = y + EVERYONE.link + EVERYONE.gap
	for index, person in ipairs(everyone) do
		local line = EveryoneRow(index)
		line.person = person
		tops[index] = top
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
		line:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		line.name:SetText(Colored(person.name))
		line.total:SetText(L.FUEL_PLAYER_TOTAL:format(Short(person.fuel)))
		local barWidth = available
		local left = 0
		for partIndex, kind in ipairs(person.kinds) do
			local part = Part(line, partIndex)
			local width = person.fuel > 0 and barWidth * kind.fuel / person.fuel or barWidth / #person.kinds
			part:ClearAllPoints()
			part:SetPoint("TOPLEFT", line.bar, "TOPLEFT", left, 0)
			part:SetSize(math.max(1, width - 1), EVERYONE.barHeight)
			local color = KindColor(kind.id)
			part.fill:SetVertexColor(color[1], color[2], color[3], 0.92)
			part.text:SetText(width >= EVERYONE.sectionMinText and L.FUEL_SECTION:format(Short(kind.value), kind.label) or "")
			part:Show()
			left = left + width
		end
		for partIndex = #person.kinds + 1, #line.parts do line.parts[partIndex]:Hide() end
		line:Show()
		top = top + EVERYONE.nameHeight + EVERYONE.barHeight + EVERYONE.gap
	end
	HideEveryone(#everyone + 1, linkCount + 1)
	content:SetSize(available, math.max(height, top))
	local maxScroll = math.max(0, top - height)
	chart:SetVerticalScroll(math.min(chart:GetVerticalScroll(), maxScroll))
	chart.ScrollBar:SetShown(maxScroll > 0)
end

-- Every view but one kind for one player is a sliced vat; that one is a vial.
local function DrawFuel(self, report, available, height)
	local lines = {}
	if report.mode == "stacked" then
		for _, data in ipairs(report.rows) do
			lines[#lines + 1] = { data.label, L.FUEL_LINE:format(Short(data.value), Number(data.fuel)) }
		end
		if self.stage == "everyone" then
			DrawEveryone(available, height)
			return true
		end
		lines[#lines + 1] = { self.stage == "sliced" and L.FUEL_EVERYONE_TIP or L.FUEL_SPLIT_TIP, "" }
		-- Gained lately: the last hour, day and week.
		lines[#lines + 1] = { L.FUEL_RECENT_HOUR, "+" .. Number(ns.Stats:Recent(3600)) }
		lines[#lines + 1] = { L.FUEL_RECENT_DAY, "+" .. Number(ns.Stats:Recent(86400)) }
		lines[#lines + 1] = { L.FUEL_RECENT_WEEK, "+" .. Number(ns.Stats:Recent(7 * 86400)) }
		lines[#lines + 1] = { self.note or L.REPORT_NOTE, "" }
		lines[#lines + 1] = { L.FUEL_XP_EXPLAIN, "" }
		lines[#lines + 1] = { L.FUEL_COUNT_EXPLAIN, "" }
		local tip = { title = L.FUEL_VAT .. ": " .. Number(report.fuel), lines = lines }
		local function Toggle()
			ReportView.stage = STAGES[ReportView.stage] or "whole"
			ReportView:Draw()
		end
		if self.stage == "sliced" then
			DrawVat(available, height, L.FUEL_VAT .. ": " .. Short(report.fuel), nil, KindItems(report), tip, Toggle)
		else
			ReportView.fuelText = Number(report.fuel)
			local hour = ns.Stats:Recent(3600)
			DrawVat(available, height, L.FUEL_VAT, { fill = report.fuel > 0 and 1 or 0, color = COLORS.vat, text = Short(report.fuel), muted = report.fuel <= 0,
				recent = hour > 0 and L.FUEL_LAST_HOUR:format(Short(hour)) or nil }, nil, tip, Toggle, true)
		end
		return true
	end
	if report.mode == "players" then
		local kind = KindOf(self.kind)
		for _, data in ipairs(report.rows) do
			lines[#lines + 1] = { Colored(data.label), Number(data.value) }
		end
		local label = (kind and kind.name or "") .. ": " .. Short(report.total)
		DrawVat(available, height, label, nil, PlayerItems(report), { title = label, lines = lines })
		return true
	end
	if report.mode == "shares" and not self.kind then
		for _, data in ipairs(report.rows) do
			lines[#lines + 1] = { data.label, L.REPORT_SHARE:format(Number(data.value), math.floor((data.share or 0) * 100 + 0.5)) }
		end
		local label = Colored(self.player)
		DrawVat(available, height, label, nil, KindItems(report, true), { title = self.player, lines = lines })
		return true
	end
	return false
end

-- With all types and all players picked, Fuel starts over at the total.
function ReportView:Reset()
	if not self.kind and not self.player then self.stage = "whole" end
end

-- Home: all types, all players, the whole vat.
function ReportView:Home()
	self.kind, self.player, self.stage = nil, nil, "whole"
	self:Draw()
end

-- Back to the party's total.
function ReportView:Whole()
	self.stage = "whole"
	self:Draw()
end

function ReportView:Draw()
	if not (frame and frame:IsShown()) then return end
	kindPicker:Refresh()
	playerPicker:Refresh()
	local report = ns.Report:Build(self.kind, self.player)
	self.note = report.total == 0 and L.REPORT_EMPTY or L.REPORT_NOTE -- in the vat's tooltip
	local pickerWidth = math.min(LAYOUT.dropdown, math.max(80, (frame:GetWidth() - 16 - LAYOUT.home) / 2))
	kindPicker:SetWidth(pickerWidth)
	playerPicker:SetWidth(pickerWidth)
	local available = chart:GetWidth()
	local height = chart:GetHeight()
	if available <= 0 or height <= 0 then return end
	if not (report.mode == "stacked" and self.stage == "everyone") then
		HideEveryone()
	end
	if question and not (report.mode == "stacked" and self.stage == "whole") then
		question:Hide()
	end
	if DrawFuel(self, report, available, height) then
		return
	end
	if rows[1] then HideSections(rows[1]) end
	local columns = math.max(1, math.min(#report.rows, math.floor((available + LAYOUT.gap) / (LAYOUT.cellMinWidth + LAYOUT.gap))))
	local gridRows = math.max(1, math.ceil(#report.rows / columns))
	local cellWidth = (available - (columns - 1) * LAYOUT.gap) / columns
	local cellHeight = math.max(LAYOUT.cellMinHeight, (height - (gridRows - 1) * LAYOUT.gap) / gridRows)
	local contentHeight = gridRows * cellHeight + (gridRows - 1) * LAYOUT.gap
	content:SetSize(available, contentHeight)
	local maxScroll = math.max(0, contentHeight - height)
	chart:SetVerticalScroll(math.min(chart:GetVerticalScroll(), maxScroll))
	chart.ScrollBar:SetShown(maxScroll > 0)
	local shown = 0
	for _, data in ipairs(report.rows) do
		shown = shown + 1
		local row = Row(shown)
		local gridRow = math.floor((shown - 1) / columns)
		local column = (shown - 1) % columns
		local inRow = math.min(columns, #report.rows - gridRow * columns)
		local offset = (available - (inRow * cellWidth + (inRow - 1) * LAYOUT.gap)) / 2
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", offset + column * (cellWidth + LAYOUT.gap), -gridRow * (cellHeight + LAYOUT.gap))
		row:SetSize(cellWidth, cellHeight)
		row.value:SetWidth(cellWidth)
		SetValueFont(row, LAYOUT.vialFont)
		-- In the split vials, a click pours them back into the vat.
		row.onClick = report.mode == "stacked" and function()
			ReportView.stage = "whole"
			ReportView:Draw()
		end or nil
		row.value:SetTextColor(unpack(data.value > 0 and COLORS.total or COLORS.muted))
		row.label:SetWidth(cellWidth)
		local label = data.label
		if report.mode ~= "players" and data.id == "achievements" and cellWidth < 76 then label = L.STAT_SHORT_ACHIEVEMENTS end
		row.label:SetText(report.mode == "players" and Colored(label) or label)
		local vialHeight = math.min(LAYOUT.vialMaxHeight, cellHeight - LAYOUT.labelHeight - 8)
		local vialWidth = math.min(LAYOUT.vialWidth, cellWidth - 4)
		row.glass:SetSize(vialWidth, vialHeight)
		row.track:SetSize(vialWidth - LAYOUT.glassInset * 2, vialHeight - LAYOUT.glassInset * 2)
		for index, mark in ipairs(row.marks) do
			mark:ClearAllPoints()
			mark:SetPoint("RIGHT", row.track, "BOTTOMRIGHT", 0, row.track:GetHeight() * index / 4)
		end
		row.tip = { title = data.label, lines = { { L.REPORT_TOTAL, Number(data.value) } } }
		-- The kind's own color: the row's kind, or the chosen one's.
		local kind = KindColor(report.mode == "players" and self.kind or data.id)
		if report.mode == "stacked" then
			-- One liquid, not slices: full when the party did any of it. Who did
			-- how much is in the tooltip.
			local lines = {}
			for _, segment in ipairs(data.segments) do
				lines[#lines + 1] = { Colored(segment.player), Number(segment.value) }
			end
			Fill(row, { { data.value > 0 and 1 or 0, kind[1], kind[2], kind[3] } })
			row.value:SetText(Short(data.value))
			lines[#lines + 1] = { L.REPORT_TOTAL, Number(data.value) }
			lines[#lines + 1] = { L.FUEL_POUR_TIP, "" }
			row.tip = { title = data.label, lines = lines }
		else
			local r, g, b = kind[1], kind[2], kind[3]
			Fill(row, { { data.share or 0, r, g, b } })
			if report.mode == "shares" then
				-- The number, and the share under it: a gauge is narrow.
				row.value:SetText(Short(data.value) .. "\n" .. math.floor((data.share or 0) * 100 + 0.5) .. "%")
			else
				row.value:SetText(Short(data.value))
			end
		end
		row:Show()
	end
	for index = shown + 1, #rows do
		rows[index]:Hide()
	end
end

-- Many tallies arrive at once on a busy channel: one redraw a moment later.
local pending = false
local function Changed()
	if pending or not (frame and frame:IsShown()) then return end
	pending = true
	C_Timer.After(LAYOUT.redrawSeconds, function()
		pending = false
		ReportView:Draw()
	end)
end

-- ========= Where it shows ===================================================
-- In the panel's 123 tab: over the list area, top given by the panel.
function ReportView:Show(top, inset)
	if not frame then return end
	local host = ns.Panel:GetFrame()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -top)
	frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
	frame:SetFrameLevel(host:GetFrameLevel() + 5)
	frame:Show()
	self:Draw()
end

function ReportView:Hide()
	if frame then frame:Hide() end
end

local function Build()
	local host = ns.Panel:GetFrame()
	if not host then return end
	frame = CreateFrame("Frame", nil, host)
	frame:Hide()
	kindPicker = Picker(frame, LAYOUT.dropdown, KindChoices, function() return ReportView.kind or ALL end, function(value)
		ReportView.kind = value ~= ALL and value or nil
		ReportView:Reset()
		ReportView:Draw()
	end)
	kindPicker:SetPoint("TOPLEFT", 0, 0)
	playerPicker = Picker(frame, LAYOUT.dropdown, PlayerChoices, function() return ReportView.player or ALL end, function(value)
		ReportView.player = value ~= ALL and value or nil
		ReportView:Reset()
		ReportView:Draw()
	end)
	playerPicker:SetPoint("LEFT", kindPicker, "RIGHT", 8, 0)
	-- Party Fuel, as an icon beside the menus: back to the total from
	-- anywhere (all types, all players, the whole vat).
	home = CreateFrame("Button", nil, frame)
	home:SetSize(LAYOUT.home, LAYOUT.home)
	home:SetPoint("LEFT", playerPicker, "RIGHT", 6, 0)
	home.icon = home:CreateTexture(nil, "ARTWORK")
	home.icon:SetAllPoints()
	home.icon:SetTexture(HOME_ICON)
	home.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	home:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	home:SetScript("OnClick", function() ReportView:Home() end)
	home:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(L.FUEL_VAT)
		GameTooltip:AddLine(L.FUEL_HOME_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	home:SetScript("OnLeave", function() GameTooltip:Hide() end)
	chart = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
	chart:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.filters + 4))
	chart:SetPoint("BOTTOMRIGHT", -(LAYOUT.pad + LAYOUT.scrollbar), LAYOUT.pad)
	chart.ScrollBar:ClearAllPoints()
	chart.ScrollBar:SetPoint("TOPLEFT", chart, "TOPRIGHT", 3, -2)
	chart.ScrollBar:SetPoint("BOTTOMLEFT", chart, "BOTTOMRIGHT", 3, 2)
	chart.ScrollBar:SetWidth(10)
	content = CreateFrame("Frame", nil, chart)
	content:SetSize(1, 1)
	chart:SetScrollChild(content)
	-- In the list of everyone, a click on empty space goes back to the total.
	content:EnableMouse(true)
	content:SetScript("OnMouseUp", function()
		if ReportView.stage == "everyone" and not ReportView.kind and not ReportView.player then
			ReportView:Whole()
		end
	end)
	-- Not while the panel is being resized: its redraw at the end draws this.
	chart:HookScript("OnSizeChanged", function()
		if not ns.Panel.sizing then ReportView:Draw() end
	end)
	if ns.charDb.filter == "report" then
		ns.Panel:Refresh() -- the panel drew before the report existed
	end
end

Bus:On("READY", Build)
Bus:On("ENTRY_RECEIVED", Changed)
Bus:On("STORE_CHANGED", Changed) -- a reset, a clear
