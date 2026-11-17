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

local ReportView = { kind = nil, player = nil }
ns.ReportView = ReportView

local LAYOUT = {
	filters = 26,
	dropdown = 140,
	note = 26,
	cellMinWidth = 44,
	cellMinHeight = 144,
	gap = 6,
	labelHeight = 28, -- above the gauge
	vialWidth = 44, -- the widest a gauge gets (narrower in a narrow cell)
	vialMaxHeight = 240,
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
}

local VIAL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local frame, note, chart, content
local kindPicker, playerPicker
local rows = {}

-- A player's color: the palette's entry at their place in the report's list
-- of players (data\themes.lua).
local function PlayerColor(name)
	for index, player in ipairs(ns.Report:Players()) do
		if player == name then
			local color = ns.PlayerPalette[(index - 1) % #ns.PlayerPalette + 1]
			return color[1], color[2], color[3]
		end
	end
	return unpack(COLORS.fill)
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
			GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 0.82, 0)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

function ReportView:Draw()
	if not (frame and frame:IsShown()) then return end
	kindPicker:Refresh()
	playerPicker:Refresh()
	local report = ns.Report:Build(self.kind, self.player)
	note:SetText(report.total == 0 and L.REPORT_EMPTY or L.REPORT_NOTE)
	local pickerWidth = math.min(LAYOUT.dropdown, math.max(80, (frame:GetWidth() - 8) / 2))
	kindPicker:SetWidth(pickerWidth)
	playerPicker:SetWidth(pickerWidth)
	local available = chart:GetWidth()
	local height = chart:GetHeight()
	if available <= 0 or height <= 0 then return end
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
			row.value:SetText(Number(data.value))
			row.tip = { title = data.label, lines = lines }
		else
			local r, g, b = kind[1], kind[2], kind[3]
			Fill(row, { { data.share or 0, r, g, b } })
			if report.mode == "shares" then
				-- The number, and the share under it: a gauge is narrow.
				row.value:SetText(Number(data.value) .. "\n" .. math.floor((data.share or 0) * 100 + 0.5) .. "%")
			else
				row.value:SetText(Number(data.value))
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
		ReportView:Draw()
	end)
	kindPicker:SetPoint("TOPLEFT", 0, 0)
	playerPicker = Picker(frame, LAYOUT.dropdown, PlayerChoices, function() return ReportView.player or ALL end, function(value)
		ReportView.player = value ~= ALL and value or nil
		ReportView:Draw()
	end)
	playerPicker:SetPoint("LEFT", kindPicker, "RIGHT", 8, 0)
	note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", 2, -(LAYOUT.filters + 2))
	note:SetPoint("TOPRIGHT", -2, -(LAYOUT.filters + 2))
	note:SetHeight(LAYOUT.note)
	note:SetJustifyH("LEFT")
	note:SetJustifyV("TOP")
	note:SetText(L.REPORT_NOTE)
	chart = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
	chart:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.filters + LAYOUT.note + 4))
	chart:SetPoint("BOTTOMRIGHT", -(LAYOUT.pad + LAYOUT.scrollbar), LAYOUT.pad)
	chart.ScrollBar:ClearAllPoints()
	chart.ScrollBar:SetPoint("TOPLEFT", chart, "TOPRIGHT", 3, -2)
	chart.ScrollBar:SetPoint("BOTTOMLEFT", chart, "BOTTOMRIGHT", 3, 2)
	chart.ScrollBar:SetWidth(10)
	content = CreateFrame("Frame", nil, chart)
	content:SetSize(1, 1)
	chart:SetScrollChild(content)
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
