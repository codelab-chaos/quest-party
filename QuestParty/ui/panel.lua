-- Panel: the Quest Party window. It draws the rows the ViewModel gives it and
-- owns nothing but frames, the selected filter and the window position.
local _, ns = ...
local Bus = ns.Bus
local L = ns.L

local Panel = {}
ns.Panel = Panel

-- ========= Layout and colors, as data =======================================
local LAYOUT = {
	width = 390,
	height = 420,
	minWidth = 230, -- room for the icon, title and three header buttons
	minHeight = 200,
	maxWidth = 800,
	maxHeight = 1000,
	gripSize = 16,
	headerHeight = 30,
	filterHeight = 22,
	filterGap = 2,
	inset = 8,
	rowSpacing = 2,
	pulseSeconds = 0.9,
	pulseMemory = 400,
	staleAlpha = 0.45,
	optionHeight = 22,
	scrollBarWidth = 12,
	refreshSeconds = 30,
	-- The party's XP bars, stacked above the tabs. Past xpBarMax players the
	-- rest are left out, so the bars never crowd out the list.
	xpBarHeight = 14,
	xpBarEdge = 7, -- the rounded border's size: half the height makes round ends
	xpBarInset = 2, -- the fill sits this far inside the border
	xpBarGap = 2,
	xpBarMax = 8,
	xpStripGap = 4, -- between the last bar and the tabs
	xpBarNotches = 3, -- marks splitting each bar into equal parts (3 makes quarters)
}

local COLORS = {
	panel = { 0.05, 0.04, 0.08, 0.92 },
	border = { 0.80, 0.65, 0.20, 1 },
	options = { 0.04, 0.08, 0.15, 0.98 },
	optionsBorder = { 0.35, 0.65, 0.95, 1 },
	optionsHeader = { 0.12, 0.24, 0.40, 1 },
	row = { 1, 1, 1, 0.05 },
	rowHighlight = { 0.45, 0.20, 0.75, 0.45 }, -- a level-up
	rowHighlightQuest = { 0.70, 0.52, 0.12, 0.42 }, -- a quest handed in
	rowCard = { 0.20, 0.45, 0.75, 0.18 },
	tab = { 1, 1, 1, 0.08 },
	tabSelected = { 0.80, 0.65, 0.20, 0.45 },
	bar = { 0.25, 0.75, 0.30, 1 },
	barBack = { 0, 0, 0, 0.5 },
	pulse = { 1, 0.85, 0.35, 0.55 },
	emulatorOn = { 0.10, 0.48, 0.16, 1 },
	emulatorOff = { 0.52, 0.12, 0.10, 1 },
	-- The party's XP bars. Each player keeps the same color from this list,
	-- picked from their name, so a bar is easy to follow as others come and go.
	xpBars = {
		{ 0.58, 0.36, 0.86 }, -- violet
		{ 0.27, 0.56, 0.90 }, -- blue
		{ 0.20, 0.70, 0.66 }, -- teal
		{ 0.38, 0.72, 0.32 }, -- green
		{ 0.86, 0.66, 0.22 }, -- gold
		{ 0.88, 0.45, 0.25 }, -- orange
		{ 0.86, 0.36, 0.56 }, -- rose
		{ 0.30, 0.74, 0.88 }, -- sky
	},
	xpBarAlpha = 0.95,
	xpBarBack = { 0.02, 0.02, 0.04, 0.85 },
	xpBarBorder = { 0.80, 0.65, 0.20, 0.70 }, -- the panel's gold, a little softer
	xpBarNotch = { 0, 0, 0, 0.45 },
	-- The game's own glossy status bar: a light top fading to a darker bottom.
	xpBarTexture = "Interface\\TargetingFrame\\UI-StatusBar",
}

-- The two row views, picked with the toggle in the title bar.
--   detailed  a title line, then one line per detail. Rows grow with their content.
--   oneLine   everything on one short line
local ROW_STYLES = {
	detailed = {
		iconSize = 26,
		titleFont = "GameFontHighlight",
		titleHeight = 21, -- top edge to the first detail line
		lineHeight = 14,
		barLineHeight = 19, -- a detail line with a progress bar under it
		barOffset = 13, -- from the top of a line to its bar
		barHeight = 3,
		bottomPadding = 3,
	},
	oneLine = {
		height = 20,
		iconSize = 16,
		titleFont = "GameFontHighlightSmall",
		barHeight = 2,
	},
}

-- Styling for the view and options buttons in the title bar.
local HEADER_BUTTON = {
	size = 20,
	top = 6, -- from the top edge of the window, lines the row up with the title
	gap = 4,
	edge = { 0.80, 0.65, 0.20, 0.55 },
	fill = { 0.10, 0.09, 0.14, 1 },
	fillLit = { 0.42, 0.33, 0.10, 1 },
	glyph = { 1.00, 0.82, 0.00, 1 },
	-- The view icon's bars, as offsets from the center of the button.
	barWidth = 10,
	barHeight = 2,
	barOffsets = { 4, 0, -4 },
	compactBar = 2, -- the one bar left showing in the compact view
	titleIcon = "Interface\\Icons\\spell_nature_astralrecalgroup", -- beside the title
}

-- Badges drawn in place of a row's icon, by style (see badge in
-- data\feed-types.lua). Each layer is one of the game's own pieces of art,
-- by its atlas name; a layer the game does not have is left out.
--   size        the badge's size against the icon's
--   glow, ring  a soft glow behind, and a ring around the text
--   burst       rays behind the ring, turning slowly, spinSeconds a turn
--   text        the font and color of what is shown on it, such as the level
local BADGES = {
	level = {
		size = 1.35,
		glow = "ChallengeMode-SoftYellowGlow",
		glowColor = { 1, 0.85, 0.35, 0.9 },
		burst = "AftLevelup-WhiteStarBurst",
		burstColor = { 1, 0.80, 0.30, 0.85 },
		spinSeconds = 14,
		ring = "Azerite-GoldRing-Rank3",
		fill = { 0.20, 0.08, 0.32, 1 }, -- behind the number, the level-up purple
		font = { detailed = "GameFontNormalLarge", oneLine = "GameFontNormalSmall" },
		textColor = { 1, 0.88, 0.35 },
	},
}

-- Sets a texture to one of the game's atlases. False when the game has none
-- by that name, so the caller can leave the layer out.
local function UseAtlas(texture, atlas)
	if not atlas or not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then
		return false
	end
	texture:SetAtlas(atlas)
	return true
end

-- Room kept on the right of each line for the count or time.
local RIGHT_TEXT_WIDTH = 58

local function StyleName()
	return ns.charDb.oneLine and "oneLine" or "detailed"
end

local function RowHeight(data)
	local style = ROW_STYLES[StyleName()]
	if style.height then
		return style.height
	end
	local height = style.titleHeight + style.bottomPadding
	for _, line in ipairs(data.lines) do
		height = height + (line.progress and style.barLineHeight or style.lineHeight)
	end
	return height
end

local ROW_BACKGROUND = {
	feed = COLORS.row,
	progress = COLORS.rowCard,
	tracker = COLORS.rowCard,
	member = COLORS.rowCard,
}

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local frame, scrollBox, scrollBar, listView, emptyText, optionsView, optionsButton, viewButton, titleIcon
local filterBar, xpStrip
local PlaceList
local xpBars = {} -- the bar frames, reused
local xpBarsShown = 0
local filterTabs = {}

-- Pulses already shown, so a row flashes once per change and not on every redraw.
local pulsesPlayed = {}
local pulsesPlayedCount = 0

-- ========= Rows =============================================================
local function CreateBar(row)
	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:SetStatusBarColor(unpack(COLORS.bar))
	bar.back = bar:CreateTexture(nil, "BACKGROUND")
	bar.back:SetAllPoints()
	bar.back:SetColorTexture(unpack(COLORS.barBack))
	return bar
end

local function BuildRow(row)
	row.background = row:CreateTexture(nil, "BACKGROUND")
	row.background:SetAllPoints()

	row.hover = row:CreateTexture(nil, "BORDER")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.08)
	row.hover:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")

	-- A badge, drawn in place of the icon for some rows (a level-up). Built
	-- here once and dressed per row in ShowBadge.
	local badge = CreateFrame("Frame", nil, row)
	badge.glow = badge:CreateTexture(nil, "BACKGROUND")
	badge.burst = badge:CreateTexture(nil, "BORDER")
	badge.fill = badge:CreateTexture(nil, "ARTWORK", nil, 1)
	badge.fill:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	badge.ring = badge:CreateTexture(nil, "ARTWORK", nil, 2)
	badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	badge.text:SetPoint("CENTER", 0, 0)
	badge.text:SetShadowOffset(1, -1)
	badge.spin = badge.burst:CreateAnimationGroup()
	badge.spin:SetLooping("REPEAT")
	badge.turn = badge.spin:CreateAnimation("Rotation")
	badge.turn:SetDegrees(-360)
	badge:Hide()
	row.badge = badge

	row.right = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.right:SetJustifyH("RIGHT")

	row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)

	-- Detail lines are created as a row needs them, see AcquireLine.
	row.lines = {}
	-- The overall progress strip, only used in the one-line view.
	row.strip = CreateBar(row)
	row.strip:SetPoint("BOTTOMLEFT")
	row.strip:SetPoint("BOTTOMRIGHT")

	-- A flash that fades out, played when the row's content just changed.
	row.pulse = row:CreateTexture(nil, "BORDER")
	row.pulse:SetAllPoints()
	row.pulse:SetColorTexture(COLORS.pulse[1], COLORS.pulse[2], COLORS.pulse[3], 1)
	row.pulse:SetAlpha(0)
	row.pulseAnimation = row.pulse:CreateAnimationGroup()
	local fade = row.pulseAnimation:CreateAnimation("Alpha")
	fade:SetFromAlpha(COLORS.pulse[4])
	fade:SetToAlpha(0)
	fade:SetDuration(LAYOUT.pulseSeconds)

	-- Rows about a quest can be clicked to jump to the Quests filter.
	row:SetScript("OnEnter", function(self)
		if self.quest then
			self.hover:Show()
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(self.quest)
			GameTooltip:AddLine(L.ROW_CLICK_TIP, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnMouseUp", function(self)
		if self.quest then
			Panel:FocusQuest(self.quest)
		end
	end)

	row.built = true
end

local function AcquireLine(row, index)
	local line = row.lines[index]
	if not line then
		line = {}
		line.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		line.text:SetJustifyH("LEFT")
		line.text:SetWordWrap(false)
		line.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		line.right:SetJustifyH("RIGHT")
		line.bar = CreateBar(row)
		row.lines[index] = line
	end
	return line
end

local function HideLines(row, from)
	for index = from, #row.lines do
		local line = row.lines[index]
		line.text:Hide()
		line.right:Hide()
		line.bar:Hide()
	end
end

local function PlayPulse(row, pulse)
	row.pulseAnimation:Stop()
	if not pulse or pulsesPlayed[pulse] then
		return
	end
	if pulsesPlayedCount >= LAYOUT.pulseMemory then
		wipe(pulsesPlayed)
		pulsesPlayedCount = 0
	end
	pulsesPlayed[pulse] = true
	pulsesPlayedCount = pulsesPlayedCount + 1
	row.pulseAnimation:Play()
end

-- Every anchor below pairs a left point with a right point at the same height, so a
-- line's position never depends on another widget's size.
local function LayoutOneLine(row, data, style)
	row.icon:SetPoint("LEFT", 5, 0)
	row.right:SetPoint("RIGHT", -6, 0)
	local left = 5 + style.iconSize + 6
	row.title:SetPoint("LEFT", left, 0)
	row.title:SetPoint("RIGHT", -(RIGHT_TEXT_WIDTH + 6), 0)
	if data.summary then
		row.title:SetText(data.title .. "  " .. data.summary)
	else
		row.title:SetText(data.title)
	end
	HideLines(row, 1)

	if data.progress then
		row.strip:SetHeight(style.barHeight)
		row.strip:SetMinMaxValues(0, data.progress.need)
		row.strip:SetValue(data.progress.have)
		row.strip:Show()
	else
		row.strip:Hide()
	end
end

local function LayoutDetailed(row, data, style)
	row.icon:SetPoint("TOPLEFT", 5, -6)
	row.right:SetPoint("TOPRIGHT", -6, -6)
	local left = 5 + style.iconSize + 7
	row.title:SetPoint("TOPLEFT", left, -5)
	row.title:SetPoint("TOPRIGHT", -(RIGHT_TEXT_WIDTH + 6), -5)
	row.title:SetText(data.title)
	row.strip:Hide()

	local y = -style.titleHeight
	for index, lineData in ipairs(data.lines) do
		local line = AcquireLine(row, index)
		line.text:ClearAllPoints()
		line.text:SetPoint("TOPLEFT", left, y)
		line.text:SetPoint("TOPRIGHT", -(RIGHT_TEXT_WIDTH + 6), y)
		line.text:SetText(lineData.text)
		line.text:Show()

		line.right:ClearAllPoints()
		line.right:SetPoint("TOPRIGHT", -6, y)
		line.right:SetText(lineData.right or "")
		line.right:Show()

		if lineData.progress then
			line.bar:ClearAllPoints()
			line.bar:SetPoint("TOPLEFT", left, y - style.barOffset)
			line.bar:SetPoint("TOPRIGHT", -6, y - style.barOffset)
			line.bar:SetHeight(style.barHeight)
			line.bar:SetMinMaxValues(0, lineData.progress.need)
			line.bar:SetValue(lineData.progress.have)
			line.bar:Show()
			y = y - style.barLineHeight
		else
			line.bar:Hide()
			y = y - style.lineHeight
		end
	end
	HideLines(row, #data.lines + 1)
end

-- Dresses the row's badge for data.badge and puts it over the icon's place,
-- or hides it.
local function ShowBadge(row, data, style)
	local badge = row.badge
	local look = data.badge and BADGES[data.badge.style]
	if not look then
		badge.spin:Stop()
		badge:Hide()
		row.icon:Show()
		return
	end
	local size = math.floor(style.iconSize * look.size + 0.5)
	badge:ClearAllPoints()
	badge:SetPoint("CENTER", row.icon, "CENTER")
	badge:SetSize(size, size)
	badge:SetFrameLevel(row:GetFrameLevel() + 2)
	for _, layer in ipairs({ "glow", "burst", "ring" }) do
		badge[layer]:ClearAllPoints()
		badge[layer]:SetPoint("CENTER")
	end
	badge.glow:SetSize(size * 1.6, size * 1.6)
	badge.glow:SetShown(UseAtlas(badge.glow, look.glow))
	badge.glow:SetVertexColor(unpack(look.glowColor))
	badge.burst:SetSize(size * 1.5, size * 1.5)
	badge.burst:SetShown(UseAtlas(badge.burst, look.burst))
	badge.burst:SetVertexColor(unpack(look.burstColor))
	badge.fill:ClearAllPoints()
	badge.fill:SetPoint("CENTER")
	badge.fill:SetSize(size * 0.78, size * 0.78)
	badge.fill:SetVertexColor(unpack(look.fill))
	badge.ring:SetSize(size, size)
	badge.ring:SetShown(UseAtlas(badge.ring, look.ring))
	badge.text:SetFontObject(look.font[StyleName()] or look.font.detailed)
	badge.text:SetTextColor(unpack(look.textColor))
	badge.text:SetText(data.badge.text)
	badge:SetAlpha(data.stale and LAYOUT.staleAlpha or 1)
	row.icon:Hide()
	badge:Show()
	badge.turn:SetDuration(look.spinSeconds)
	if badge.burst:IsShown() and not badge.spin:IsPlaying() then
		badge.spin:Play()
	end
end

local function InitRow(row, data)
	if not row.built then
		BuildRow(row)
	end
	local style = ROW_STYLES[StyleName()]

	local background = (data.highlight == "quest" and COLORS.rowHighlightQuest)
		or (data.highlight and COLORS.rowHighlight)
		or ROW_BACKGROUND[data.kind] or COLORS.row
	row.background:SetColorTexture(unpack(background))
	row.icon:SetTexture(data.icon)
	row.icon:SetSize(style.iconSize, style.iconSize)
	row.icon:SetDesaturated(data.stale and true or false)
	row.title:SetFontObject(style.titleFont)
	row.right:SetText(data.right or "")

	row.icon:ClearAllPoints()
	row.right:ClearAllPoints()
	row.title:ClearAllPoints()
	if style.height then
		LayoutOneLine(row, data, style)
	else
		LayoutDetailed(row, data, style)
	end

	row.quest = data.quest
	row.hover:Hide()
	row:EnableMouse(data.quest ~= nil)
	row:SetAlpha(data.stale and LAYOUT.staleAlpha or 1)
	ShowBadge(row, data, style)
	PlayPulse(row, data.pulse)
end

-- ========= Refresh ==========================================================
-- Height of the visible list area, from the layout data.
-- Distance from the top of the window to the top of the list.
-- How tall the XP bars above the tabs are, with the gap under them.
local function StripHeight()
	if xpBarsShown == 0 then
		return 0
	end
	return xpBarsShown * (LAYOUT.xpBarHeight + LAYOUT.xpBarGap) - LAYOUT.xpBarGap + LAYOUT.xpStripGap
end

local function ListTop()
	return LAYOUT.headerHeight + StripHeight() + LAYOUT.filterHeight + 6
end

local function ListHeight()
	local height = frame:GetHeight() or LAYOUT.height
	return height - ListTop() - LAYOUT.inset
end

-- Empty space to leave above the rows so that a list too short to fill the view sits
-- at the bottom and grows upward, the way chat does.
local function TopPadding(rows)
	if #rows == 0 or not ns.IsEnabled("chatOrder") then
		return 0
	end
	local rowsHeight = (#rows - 1) * LAYOUT.rowSpacing
	for _, data in ipairs(rows) do
		rowsHeight = rowsHeight + RowHeight(data)
	end
	return math.max(0, ListHeight() - rowsHeight)
end

-- A quest to bring into view on the next refresh, set by Panel:FocusQuest.
local focusQuest

-- In chat order new rows and updated cards land at the bottom, so the list follows the bottom
-- unless the player has scrolled up to read. jumpToEnd forces it, for a fresh view.
function Panel:Refresh(jumpToEnd)
	if not frame or not frame:IsShown() or optionsView:IsShown() then
		return
	end
	local filter = ns.FilterById[ns.charDb.filter] or ns.Filters[1]
	local follow = ns.IsEnabled("chatOrder")
		and (jumpToEnd or not scrollBox:HasScrollableExtent() or scrollBox:IsAtEnd())

	local rows = ns.ViewModel:Build(filter.id)
	local focusIndex
	if focusQuest then
		for index, data in ipairs(rows) do
			if data.kind == "tracker" and data.quest == focusQuest then
				focusIndex = index
				data.pulse = "focus/" .. focusQuest .. "/" .. GetTime() -- always flash it
				break
			end
		end
		focusQuest = nil
	end

	listView:SetPadding(TopPadding(rows), 0, 0, 0, LAYOUT.rowSpacing)
	scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
	if focusIndex then
		scrollBox:ScrollToElementDataIndex(focusIndex, ScrollBoxConstants.AlignCenter, nil, true)
	elseif follow then
		scrollBox:ScrollToEnd(true)
	elseif jumpToEnd then
		scrollBox:ScrollToBegin(true)
	end
	emptyText:SetText(ns.IsDebug() and L.EMPTY_DEBUG or L.EMPTY)
	emptyText:SetShown(#rows == 0)
end

-- Jumps to the Quests filter and brings one quest into view with a flash.
function Panel:FocusQuest(quest)
	focusQuest = quest
	self:SelectFilter(ns.QuestTab)
end

local function FilterLabel(filter, compact)
	local label = compact and filter.shortLabel or filter.label
	if filter.id == "party" then
		local count = ns.Session:Count()
		return count > 0 and (label .. " " .. count) or label
	end
	return label
end

local function UpdateFilter()
	for _, filter in ipairs(ns.Filters) do
		local tab = filterTabs[filter.id]
		local selected = filter.id == ns.charDb.filter
		tab.background:SetColorTexture(unpack(selected and COLORS.tabSelected or COLORS.tab))
		tab.label:SetFontObject(selected and "GameFontNormalSmall" or "GameFontHighlightSmall")
		tab.label:SetText(FilterLabel(filter))
		if tab.label:GetStringWidth() > tab:GetWidth() - 8 then
			tab.label:SetText(FilterLabel(filter, true))
		end
	end
end

local function LayoutFilter()
	local count = #ns.Filters
	local width = math.max(1, (filterBar:GetWidth() - (count - 1) * LAYOUT.filterGap) / count)
	for index, filter in ipairs(ns.Filters) do
		local tab = filterTabs[filter.id]
		tab:SetSize(width, LAYOUT.filterHeight)
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", (index - 1) * (width + LAYOUT.filterGap), 0)
	end
	UpdateFilter()
end

local function UpdateConnectionOptions(resetName)
	if not optionsView or not optionsView.connection then return end
	local controls = optionsView.connection
	local session, config = ns.Session, ns.db.connection
	if resetName then controls.name:SetText(config.name) end
	controls.join:SetEnabled(session.state ~= "joining" and session.state ~= "connected")
	controls.disconnect:SetEnabled(config.enabled)
	if session.state == "connected" then
		controls.status:SetText(L.CHANNEL_CONNECTED:format(config.name))
		controls.status:SetTextColor(0.4, 1, 0.5)
	elseif session.state == "joining" then
		controls.status:SetText(L.CHANNEL_JOINING:format(config.name))
		controls.status:SetTextColor(1, 0.82, 0)
	elseif session.state == "failed" then
		controls.status:SetText(session.error or L.CHANNEL_JOIN_FAILED)
		controls.status:SetTextColor(1, 0.4, 0.4)
	else
		controls.status:SetText(L.CHANNEL_DISCONNECTED)
		controls.status:SetTextColor(0.7, 0.7, 0.7)
	end
end

local function UpdateEmulatorButton()
	if not optionsView or not optionsView.emulator then return end
	local button = optionsView.emulator
	button:SetShown(ns.IsDebug())
	button.fill:SetColorTexture(unpack(ns.Emulator.running and COLORS.emulatorOn or COLORS.emulatorOff))
	button.label:SetText(ns.Emulator.running and L.EMULATOR_ON or L.EMULATOR_OFF)
end

function Panel:SelectFilter(id)
	ns.charDb.filter = id
	UpdateFilter()
	self:ShowOptions(false)
	self:Refresh(true)
end

-- The view icon mirrors the current state: every bar for detailed rows, only the
-- middle one for compact.
local function UpdateViewButton()
	for index, bar in ipairs(viewButton.bars) do
		bar:SetShown(not ns.charDb.oneLine or index == HEADER_BUTTON.compactBar)
	end
end

-- Switches between one-line and detailed rows.
function Panel:SetOneLine(oneLine)
	ns.charDb.oneLine = oneLine and true or false
	UpdateViewButton()
	self:Refresh(true)
end

-- Swaps the list for the feature switches and back.
function Panel:ShowOptions(show)
	filterBar:SetShown(not show)
	optionsView:SetShown(show)
	scrollBox:SetShown(not show)
	scrollBar:SetShown(not show)
	optionsButton.lit = show
	optionsButton:UpdateFill()
	if show then
		emptyText:Hide()
		UpdateConnectionOptions(true)
		UpdateEmulatorButton()
		for _, check in ipairs(optionsView.checks) do
			check:SetChecked(ns.IsEnabled(check.settingId))
		end
	else
		self:Refresh(true)
	end
end

-- ========= Construction =====================================================
local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.charDb.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition()
	local position = ns.charDb.position
	frame:ClearAllPoints()
	if position then
		frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
	end
end

-- Sets the icon beside the title. Pass an icon name, a full texture path or a file id.
-- Nothing (or an empty string) goes back to the default.
function Panel:SetTitleIcon(icon)
	if icon == "" then
		icon = nil
	end
	ns.charDb.titleIcon = icon
	icon = icon or HEADER_BUTTON.titleIcon
	if type(icon) == "string" and not icon:find("[\\/]") then
		icon = tonumber(icon) or ("Interface\\Icons\\" .. icon)
	end
	if titleIcon then
		titleIcon:SetTexture(icon)
	end
end

-- Shared gold styling for the header buttons.
--   tooltip  a function returning the tooltip title and an optional second line
-- The button stays lit while button.lit is true.
local function CreateHeaderButton(tooltip, onClick)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(HEADER_BUTTON.size, HEADER_BUTTON.size)

	local edge = button:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(unpack(HEADER_BUTTON.edge))
	button.fill = button:CreateTexture(nil, "BORDER")
	button.fill:SetPoint("TOPLEFT", 1, -1)
	button.fill:SetPoint("BOTTOMRIGHT", -1, 1)

	function button:UpdateFill()
		local lit = self.lit or self.hovered
		self.fill:SetColorTexture(unpack(lit and HEADER_BUTTON.fillLit or HEADER_BUTTON.fill))
	end
	button:UpdateFill()

	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		self.hovered = true
		self:UpdateFill()
		local title, line = tooltip()
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(title)
		if line then
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self.hovered = false
		self:UpdateFill()
		GameTooltip:Hide()
	end)
	return button
end

-- A letter drawn in the middle of a header button.
local function AddGlyph(button, text)
	local glyph = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	glyph:SetPoint("CENTER", 0, 0)
	glyph:SetText(text)
end

local function BuildHeader()
	titleIcon = frame:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(HEADER_BUTTON.size, HEADER_BUTTON.size)
	titleIcon:SetPoint("TOPLEFT", LAYOUT.inset, -HEADER_BUTTON.top)
	Panel:SetTitleIcon(ns.charDb.titleIcon)

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("LEFT", titleIcon, "RIGHT", 6, 0)
	title:SetText(L.TITLE)

	-- Right to left: close, options, view.
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -(LAYOUT.inset - 2), -(HEADER_BUTTON.top - 2))
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	-- Opens the options. It stays lit while they are open.
	optionsButton = CreateHeaderButton(function()
		return optionsView:IsShown() and L.OPTIONS_BACK or L.OPTIONS
	end, function()
		Panel:ShowOptions(not optionsView:IsShown())
	end)
	optionsButton:SetPoint("RIGHT", close, "LEFT", -HEADER_BUTTON.gap, 0)
	AddGlyph(optionsButton, L.OPTIONS_ICON)

	-- Shows the current view: three bars for detailed rows, one for compact.
	viewButton = CreateHeaderButton(function()
		if ns.charDb.oneLine then
			return L.VIEW_COMPACT, L.VIEW_TIP_TO_DETAILED
		end
		return L.VIEW_DETAILED, L.VIEW_TIP_TO_COMPACT
	end, function()
		Panel:SetOneLine(not ns.charDb.oneLine)
	end)
	viewButton:SetPoint("RIGHT", optionsButton, "LEFT", -HEADER_BUTTON.gap, 0)
	viewButton.bars = {}
	for index, offset in ipairs(HEADER_BUTTON.barOffsets) do
		local bar = viewButton:CreateTexture(nil, "ARTWORK")
		bar:SetSize(HEADER_BUTTON.barWidth, HEADER_BUTTON.barHeight)
		bar:SetPoint("CENTER", 0, offset)
		bar:SetColorTexture(unpack(HEADER_BUTTON.glyph))
		viewButton.bars[index] = bar
	end
	UpdateViewButton()

	-- Drag the header to move the window.
	local drag = CreateFrame("Frame", nil, frame)
	drag:SetPoint("TOPLEFT")
	drag:SetPoint("TOPRIGHT", viewButton, "TOPLEFT")
	drag:SetHeight(LAYOUT.headerHeight)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	drag:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		SavePosition()
	end)
end

-- All filters stay visible on one row, directly below the title bar.
local function BuildFilter()
	filterBar = CreateFrame("Frame", nil, frame)
	filterBar:SetHeight(LAYOUT.filterHeight)
	filterBar:SetPoint("TOPLEFT", LAYOUT.inset, -LAYOUT.headerHeight)
	filterBar:SetPoint("TOPRIGHT", -LAYOUT.inset, -LAYOUT.headerHeight)
	for _, filter in ipairs(ns.Filters) do
		local tab = CreateFrame("Button", nil, filterBar)
		tab.background = tab:CreateTexture(nil, "BACKGROUND")
		tab.background:SetAllPoints()
		tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		tab.label:SetPoint("LEFT", 4, 0)
		tab.label:SetPoint("RIGHT", -4, 0)
		tab.label:SetWordWrap(false)
		tab.label:SetJustifyH("CENTER")
		tab:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
		tab:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
		tab:SetScript("OnClick", function()
			Panel:SelectFilter(filter.id)
		end)
		tab:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(FilterLabel(filter))
			GameTooltip:Show()
		end)
		tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
		filterTabs[filter.id] = tab
	end
	filterBar:SetScript("OnSizeChanged", LayoutFilter)
	LayoutFilter()
end

-- ========= The party's XP bars ==============================================
local function BarColor(name)
	local sum = 0
	for index = 1, #name do
		sum = (sum * 31 + name:byte(index)) % 65521
	end
	return COLORS.xpBars[sum % #COLORS.xpBars + 1]
end

local function ShowBarTip(bar)
	local data = bar.data
	if not data then
		return
	end
	GameTooltip:SetOwner(bar, "ANCHOR_BOTTOM")
	GameTooltip:SetText(ns.ColorName(data.name, data.class))
	GameTooltip:AddLine(data.text, 1, 1, 1)
	if data.have then
		GameTooltip:AddLine(L.XPBAR_TIP_XP:format(ns.Comma(data.have), ns.Comma(data.need)), 0.8, 0.8, 0.8)
	end
	if data.lastXP then
		local gain = L.XP_GAIN:format(ns.Comma(data.lastXP))
		local line = (data.lastMob and data.lastMob ~= "") and L.XPBAR_TIP_GAIN_FROM:format(gain, data.lastMob) or L.XPBAR_TIP_GAIN:format(gain)
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
	end
	GameTooltip:Show()
end

-- A rounded, glossy bar: a frame with a rounded gold border and a dark
-- inside, and the colored fill set just within it. Name, text and notches sit
-- on the fill.
local XP_BAR_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = LAYOUT.xpBarEdge,
	insets = { left = LAYOUT.xpBarInset, right = LAYOUT.xpBarInset, top = LAYOUT.xpBarInset, bottom = LAYOUT.xpBarInset },
}

-- Puts a bar's notches at equal parts of its width.
local function PlaceNotches(fill, width)
	if not width or width <= 0 then
		return
	end
	local parts = #fill.notches + 1
	for index, notch in ipairs(fill.notches) do
		local x = math.floor(width * index / parts + 0.5)
		notch:ClearAllPoints()
		notch:SetPoint("TOPLEFT", x, 0)
		notch:SetPoint("BOTTOMLEFT", x, 0)
	end
end

local function CreateXpBar()
	local bar = CreateFrame("Frame", nil, xpStrip, "BackdropTemplate")
	bar:SetHeight(LAYOUT.xpBarHeight)
	bar:SetBackdrop(XP_BAR_BACKDROP)
	bar:SetBackdropColor(unpack(COLORS.xpBarBack))
	bar:SetBackdropBorderColor(unpack(COLORS.xpBarBorder))

	local fill = CreateFrame("StatusBar", nil, bar)
	fill:SetPoint("TOPLEFT", LAYOUT.xpBarInset, -LAYOUT.xpBarInset)
	fill:SetPoint("BOTTOMRIGHT", -LAYOUT.xpBarInset, LAYOUT.xpBarInset)
	fill:SetStatusBarTexture(COLORS.xpBarTexture)
	fill:SetMinMaxValues(0, 1)
	bar.fill = fill

	-- Notches split the bar into equal parts, so a gain is easy to see.
	fill.notches = {}
	for index = 1, LAYOUT.xpBarNotches do
		local notch = fill:CreateTexture(nil, "OVERLAY")
		notch:SetWidth(1)
		notch:SetColorTexture(unpack(COLORS.xpBarNotch))
		fill.notches[index] = notch
	end
	fill:SetScript("OnSizeChanged", PlaceNotches)

	bar.text = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.text:SetPoint("RIGHT", -3, 0)
	bar.text:SetShadowOffset(1, -1)
	bar.name = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.name:SetPoint("LEFT", 3, 0)
	bar.name:SetPoint("RIGHT", bar.text, "LEFT", -6, 0)
	bar.name:SetJustifyH("LEFT")
	bar.name:SetWordWrap(false)
	bar.name:SetShadowOffset(1, -1)

	bar:EnableMouse(true)
	bar:SetScript("OnEnter", ShowBarTip)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return bar
end

-- Puts the tabs and the list under however many bars there are.
local function PlaceUnderStrip()
	local top = LAYOUT.headerHeight + StripHeight()
	filterBar:ClearAllPoints()
	filterBar:SetPoint("TOPLEFT", LAYOUT.inset, -top)
	filterBar:SetPoint("TOPRIGHT", -LAYOUT.inset, -top)
	if scrollBox then
		PlaceList()
	end
end

-- Draws one bar per other player in the party, and moves everything under
-- them when how many there are changes.
function Panel:UpdateXpBars()
	if not xpStrip then
		return
	end
	local data = ns.ViewModel:PartyBars()
	local shown = math.min(#data, LAYOUT.xpBarMax)
	for index = 1, shown do
		local bar = xpBars[index] or CreateXpBar()
		xpBars[index] = bar
		local entry = data[index]
		bar.data = entry
		local r, g, b = unpack(BarColor(entry.name))
		local fill = bar.fill
		fill:SetStatusBarColor(r, g, b, COLORS.xpBarAlpha)
		if entry.maxLevel then
			fill:SetMinMaxValues(0, 1)
			fill:SetValue(1)
		elseif entry.have then
			fill:SetMinMaxValues(0, entry.need)
			fill:SetValue(entry.have)
		else
			fill:SetMinMaxValues(0, 1)
			fill:SetValue(0)
		end
		bar.name:SetText(entry.name)
		bar.text:SetText(entry.text)
		bar:ClearAllPoints()
		local top = (index - 1) * (LAYOUT.xpBarHeight + LAYOUT.xpBarGap)
		bar:SetPoint("TOPLEFT", 0, -top)
		bar:SetPoint("TOPRIGHT", 0, -top)
		bar:Show()
		-- Also placed here, in case the width settled before the bar was shown.
		PlaceNotches(bar.fill, xpStrip:GetWidth() - 2 * LAYOUT.xpBarInset)
	end
	for index = shown + 1, #xpBars do
		xpBars[index]:Hide()
		xpBars[index].data = nil
	end
	if shown ~= xpBarsShown then
		xpBarsShown = shown
		xpStrip:SetHeight(math.max(1, StripHeight()))
		PlaceUnderStrip()
		Panel:Refresh()
	end
end

local function BuildXpStrip()
	xpStrip = CreateFrame("Frame", nil, frame)
	xpStrip:SetPoint("TOPLEFT", LAYOUT.inset, -LAYOUT.headerHeight)
	xpStrip:SetPoint("TOPRIGHT", -LAYOUT.inset, -LAYOUT.headerHeight)
	xpStrip:SetHeight(1)
end

function PlaceList()
	scrollBox:ClearAllPoints()
	scrollBox:SetPoint("TOPLEFT", LAYOUT.inset, -ListTop())
	scrollBox:SetPoint("BOTTOMRIGHT", -(LAYOUT.inset + LAYOUT.scrollBarWidth + 4), LAYOUT.inset)
end

local function BuildList()
	scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	PlaceList()

	scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, -2)
	-- Leave the resize grip accessible while the rows use the full window height.
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, LAYOUT.gripSize + 2)

	listView = CreateScrollBoxListLinearView()
	-- Rows size themselves: one line in the compact view, or as tall as their content.
	listView:SetElementExtentCalculator(function(_, data)
		return RowHeight(data)
	end)
	listView:SetPadding(0, 0, 0, 0, LAYOUT.rowSpacing)
	listView:SetElementInitializer("Frame", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, listView)

	emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("CENTER", scrollBox, "CENTER")
	emptyText:SetWidth((frame:GetWidth() or LAYOUT.width) - 40)
	emptyText:SetText(L.EMPTY)
end

-- Channel setup, feed controls and one check box per feature switch.
local function BuildOptions()
	optionsView = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	optionsView:SetPoint("TOPLEFT", filterBar, "TOPLEFT")
	optionsView:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LAYOUT.inset, LAYOUT.inset)
	optionsView:SetBackdrop(BACKDROP)
	optionsView:SetBackdropColor(unpack(COLORS.options))
	optionsView:SetBackdropBorderColor(unpack(COLORS.optionsBorder))
	optionsView:Hide()
	optionsView.checks = {}

	-- Use the filter row for an unmistakable options heading and a way back.
	local heading = optionsView:CreateTexture(nil, "BACKGROUND")
	heading:SetPoint("TOPLEFT", 3, -3)
	heading:SetPoint("TOPRIGHT", -3, -3)
	heading:SetHeight(LAYOUT.filterHeight)
	heading:SetColorTexture(unpack(COLORS.optionsHeader))

	local back = CreateFrame("Button", nil, optionsView, "UIPanelButtonTemplate")
	back:SetSize(100, LAYOUT.filterHeight)
	back:SetPoint("TOPRIGHT", -4, -3)
	back:SetText(L.OPTIONS_BACK)
	back:SetScript("OnClick", function()
		Panel:ShowOptions(false)
	end)

	local title = optionsView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -7)
	title:SetPoint("TOPRIGHT", back, "TOPLEFT", -6, -4)
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	title:SetText(L.OPTIONS)

	local contentTop = LAYOUT.filterHeight + 6
	local optionsScroll = CreateFrame("ScrollFrame", nil, optionsView, "ScrollFrameTemplate")
	optionsScroll:SetPoint("TOPLEFT", 6, -contentTop)
	optionsScroll:SetPoint("BOTTOMRIGHT", -28, 8)
	optionsScroll.ScrollBar:ClearAllPoints()
	optionsScroll.ScrollBar:SetPoint("TOPLEFT", optionsScroll, "TOPRIGHT", 6, -2)
	optionsScroll.ScrollBar:SetPoint("BOTTOMLEFT", optionsScroll, "BOTTOMRIGHT", 6, 2)
	local content = CreateFrame("Frame", nil, optionsScroll)
	local actionsHeight = LAYOUT.optionHeight + 8
	content:SetSize(1, actionsHeight + 112 + #ns.Settings * LAYOUT.optionHeight)
	optionsScroll:SetScrollChild(content)
	local function ResizeOptions(self)
		content:SetWidth(self:GetWidth())
	end
	optionsScroll:HookScript("OnSizeChanged", ResizeOptions)
	optionsScroll:HookScript("OnShow", ResizeOptions)
	ResizeOptions(optionsScroll)

	local clear = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	clear:SetSize(70, LAYOUT.optionHeight)
	clear:SetPoint("TOPLEFT", 4, 0)
	clear:SetText(L.CLEAR)
	clear:SetScript("OnClick", function()
		ns.ConfirmClear()
	end)
	clear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.CLEAR)
		GameTooltip:AddLine(L.CLEAR_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local emulator = CreateFrame("Button", nil, content)
	emulator:SetSize(70, LAYOUT.optionHeight)
	emulator:SetPoint("TOPRIGHT", -4, 0)
	local edge = emulator:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(unpack(HEADER_BUTTON.edge))
	emulator.fill = emulator:CreateTexture(nil, "BORDER")
	emulator.fill:SetPoint("TOPLEFT", 1, -1)
	emulator.fill:SetPoint("BOTTOMRIGHT", -1, 1)
	emulator.label = emulator:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	emulator.label:SetPoint("CENTER")
	emulator:SetScript("OnClick", function()
		ns.Emulator:Toggle()
		UpdateEmulatorButton()
	end)
	emulator:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ns.Emulator.running and L.EMULATOR_ON or L.EMULATOR_OFF)
		GameTooltip:AddLine(L.EMULATOR_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	emulator:SetScript("OnLeave", function() GameTooltip:Hide() end)
	optionsView.emulator = emulator
	UpdateEmulatorButton()

	local channelLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	channelLabel:SetPoint("TOPLEFT", 4, -actionsHeight - 2)
	channelLabel:SetText(L.CHANNEL_LABEL)
	local name = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	name:SetHeight(22)
	name:SetPoint("TOPLEFT", 8, -actionsHeight - 20)
	name:SetPoint("TOPRIGHT", -4, -actionsHeight - 20)
	name:SetAutoFocus(false)
	name:SetMaxLetters(30)
	local join = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	join:SetSize(88, 22)
	join:SetPoint("TOPLEFT", 4, -actionsHeight - 47)
	join:SetText(L.CHANNEL_CONNECT)
	local disconnect = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	disconnect:SetSize(76, 22)
	disconnect:SetPoint("TOPRIGHT", -4, -actionsHeight - 47)
	disconnect:SetText(L.CHANNEL_DISCONNECT)
	local status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", 4, -actionsHeight - 75)
	status:SetPoint("TOPRIGHT", -4, -actionsHeight - 75)
	status:SetHeight(30)
	status:SetJustifyH("LEFT")
	status:SetJustifyV("TOP")
	status:SetWordWrap(true)
	optionsView.connection = { name = name, join = join, disconnect = disconnect, status = status }
	local function Connect()
		local ok, errorMessage = ns.Session:Connect(name:GetText())
		name:ClearFocus()
		UpdateConnectionOptions(ok)
		if not ok then
			status:SetText(errorMessage)
			status:SetTextColor(1, 0.4, 0.4)
		end
	end
	join:SetScript("OnClick", Connect)
	name:SetScript("OnEnterPressed", Connect)
	name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	disconnect:SetScript("OnClick", function()
		ns.Session:Disconnect()
		UpdateConnectionOptions(true)
	end)
	UpdateConnectionOptions(true)

	for index, setting in ipairs(ns.Settings) do
		local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
		check:SetSize(LAYOUT.optionHeight, LAYOUT.optionHeight)
		check:SetPoint("TOPLEFT", 0, -actionsHeight - 112 - (index - 1) * LAYOUT.optionHeight)
		check.settingId = setting.id
		check.Text:SetFontObject("GameFontHighlight")
		check.Text:SetText(setting.label)
		check:SetScript("OnClick", function(self)
			ns.SetEnabled(setting.id, self:GetChecked())
		end)
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(setting.label)
			GameTooltip:AddLine(setting.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		check:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		optionsView.checks[index] = check
	end
end

local function SaveSize()
	ns.charDb.size = { width = frame:GetWidth(), height = frame:GetHeight() }
end

-- A grip in the bottom right corner. Drag it to resize the window.
local function BuildResizeGrip()
	frame:SetResizable(true)
	frame:SetResizeBounds(LAYOUT.minWidth, LAYOUT.minHeight, LAYOUT.maxWidth, LAYOUT.maxHeight)

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(LAYOUT.gripSize, LAYOUT.gripSize)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		SaveSize()
		SavePosition() -- sizing re-anchors the window
	end)

	frame:SetScript("OnSizeChanged", function()
		emptyText:SetWidth(frame:GetWidth() - 40)
		Panel:Refresh()
	end)
end

local function Build()
	frame = CreateFrame("Frame", "QuestPartyPanel", UIParent, "BackdropTemplate")
	local size = ns.charDb.size
	frame:SetSize(size and size.width or LAYOUT.width, size and size.height or LAYOUT.height)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(unpack(COLORS.panel))
	frame:SetBackdropBorderColor(unpack(COLORS.border))
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	RestorePosition()

	BuildHeader()
	BuildXpStrip()
	BuildFilter()
	BuildList()
	BuildOptions()
	Panel:UpdateXpBars()
	ns.Confetti:SetHost(frame)
	BuildResizeGrip()

	-- Remember visibility, and keep the relative times fresh while visible.
	frame:SetScript("OnShow", function()
		ns.charDb.shown = true
		Panel:Refresh(true)
	end)
	frame:SetScript("OnHide", function()
		ns.charDb.shown = false
	end)
	C_Timer.NewTicker(LAYOUT.refreshSeconds, function()
		Panel:Refresh()
	end)

	-- A saved filter that no longer exists falls back to the first one.
	if not ns.FilterById[ns.charDb.filter] then
		ns.charDb.filter = ns.Filters[1].id
	end
	UpdateFilter()
	UpdateEmulatorButton()
	frame:SetShown(ns.charDb.shown)
	Panel:Refresh(true)
	-- Again on the next frame: the first pass runs before the list has its real size,
	-- and the scroll position it sets does not survive the first layout.
	C_Timer.After(0, function()
		LayoutFilter()
		Panel:Refresh(true)
	end)
end

function Panel:Toggle()
	if frame then
		frame:SetShown(not frame:IsShown())
	end
end

Bus:On("READY", Build)

Bus:On("STORE_CHANGED", function()
	Panel:UpdateXpBars()
	ns.Confetti:SetHost(frame)
	Panel:Refresh()
end)

Bus:On("PEERS_CHANGED", function()
	if frame then
		UpdateFilter()
		Panel:UpdateXpBars()
	ns.Confetti:SetHost(frame)
	end
end)

Bus:On("EMULATOR_STATE", function()
	if frame then
		UpdateEmulatorButton()
	end
end)

Bus:On("DEBUG_CHANGED", function()
	if frame then
		UpdateEmulatorButton()
		Panel:UpdateXpBars()
	ns.Confetti:SetHost(frame)
		Panel:Refresh()
	end
end)

Bus:On("CONNECTION_CHANGED", function()
	UpdateConnectionOptions(false)
end)
