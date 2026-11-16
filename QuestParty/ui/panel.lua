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
	filterHeight = 18,
	filterGap = 3,
	tabMinWidth = 64, -- tabs fit their labels, at least this wide
	tabPad = 14, -- either side of a tab's label
	-- The filter row: a row of icons along the bottom of the panel, under the
	-- feed (the code calls it the gutter). Sizes at a scale of 1; the Filter icon
	-- size slider scales them.
	gutterIcon = 22,
	gutterIconGap = 4,
	gutterRowGap = 4, -- between the feed and the row
	gutterOffAlpha = 0.35, -- an icon whose rows are hidden
	gutterEdge = 1, -- the border around each icon
	gutterIconInset = 2, -- the icon inside its border
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
	gutterOff = { 0.35, 0.35, 0.35, 0.6 }, -- a gutter icon's border when its rows are hidden
	row = { 1, 1, 1, 0.05 },
	rowHighlight = { 0.45, 0.20, 0.75, 0.45 }, -- a level-up
	rowHighlightQuest = { 0.70, 0.52, 0.12, 0.42 }, -- a quest handed in
	rowCard = { 0.20, 0.45, 0.75, 0.18 },
	tab = { 0.10, 0.09, 0.13, 1 },
	tabSelected = { 0.42, 0.33, 0.10, 1 },
	tabEdge = { 0.80, 0.65, 0.20, 1 }, -- the selected tab's outline and the line under the tabs
	bar = { 0.25, 0.75, 0.30, 1 },
	barBack = { 0, 0, 0, 0.5 },
	pulse = { 1, 0.85, 0.35, 0.55 },
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

-- The Settings window.
local SETTINGS = {
	width = 480,
	height = 560,
	titleHeight = 32, -- the title, then a gold rule under it
	headingHeight = 26, -- a section's title and its rule
	sectionGap = 12,
	rowHeight = 26, -- a row of switches
	checkSize = 24,
	buttonWidth = 96,
	sliderHeight = 30,
	scenarioWidth = 230, -- the scenario dropdown
	goWidth = 70,
	sliderLeft = 140, -- the bar, after its label
	sliderRight = 50, -- room for its value
	dataButtonWidth = 120,
	rule = { 0.80, 0.65, 0.20, 0.45 },
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
	optionsIcon = "Interface\\WorldMap\\GEAR_64GREY", -- a gear, tinted with glyph
	iconInset = 2,
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

local frame, scrollBox, scrollBar, listView, emptyText, optionsView, optionsButton, viewButton, titleIcon, soundButton

-- The speaker shows the volume: crossed out at Mute, fainter the softer.
local VOLUME_ALPHA = { [0] = 0.6, [1] = 0.55, [2] = 0.8, [3] = 1 }
local function UpdateSoundButton()
	if not soundButton then return end
	local value = ns.GetSlider("volume") or 2
	soundButton.icon:SetAtlas(value > 0 and "voicechat-icon-speaker" or "voicechat-icon-speaker-mute")
	soundButton.icon:SetDesaturated(value == 0)
	soundButton.icon:SetAlpha(VOLUME_ALPHA[value] or 1)
end
local filterBar, xpStrip, gutter
local PlaceList, PlaceUnderStrip, BuildShrink
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
-- The filter row's icon size and the gap between icons, at the slider's scale.
local function GutterSizes()
	local scale = ns.GetSlider("gutterScale") or 1
	local function Scaled(value)
		return math.floor(value * scale + 0.5)
	end
	return Scaled(LAYOUT.gutterIcon), Scaled(LAYOUT.gutterIconGap)
end

-- The filter row shows on tabs that show the feed.
local function GutterShown()
	local filter = ns.FilterById[ns.charDb.filter]
	return filter ~= nil and filter.feed ~= nil
end

-- How much room the filter row takes above the list, when it shows.
local function GutterHeight()
	if not GutterShown() then
		return 0
	end
	return (GutterSizes()) + LAYOUT.gutterRowGap
end

-- Where the tabs and the list start.
local function ContentLeft()
	return LAYOUT.inset
end

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
	return height - ListTop() - LAYOUT.inset - GutterHeight()
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
	if not frame or not frame:IsShown() then
		return
	end
	local filter = ns.FilterById[ns.charDb.filter] or ns.Filters[1]
	-- The Chat tab shows Quest Party chat (ui\chat.lua) in place of the list.
	scrollBox:SetShown(not filter.chat)
	scrollBar:SetShown(not filter.chat)
	if filter.chat then
		emptyText:Hide()
		ns.ChatView:ShowDocked(ListTop(), LAYOUT.inset)
		return
	end
	ns.ChatView:HideDocked()
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
	if filter.chat and ns.Chat.unread > 0 and ns.charDb.filter ~= filter.id then
		return label .. " " .. ns.Chat.unread -- new messages not seen yet
	end
	return label
end

local function UpdateGutter()
	if not gutter then
		return
	end
	for _, button in ipairs(gutter.buttons) do
		local hidden = ns.charDb.hidden[button.filter.id] == true
		button.icon:SetDesaturated(hidden)
		button.icon:SetAlpha(hidden and LAYOUT.gutterOffAlpha or 1)
		button:SetBackdropBorderColor(unpack(hidden and COLORS.gutterOff or COLORS.border))
	end
end

local function UpdateFilter()
	UpdateGutter()
	for _, filter in ipairs(ns.Tabs) do
		local tab = filterTabs[filter.id]
		local selected = filter.id == ns.charDb.filter
		tab.background:SetColorTexture(unpack(selected and COLORS.tabSelected or COLORS.tab))
		tab.label:SetFontObject(selected and "GameFontNormalSmall" or "GameFontDisableSmall")
		tab.label:SetText(FilterLabel(filter))
		-- The selected tab is outlined and open at the bottom, over the line
		-- under the tabs, so it reads as joined to the feed below it.
		for _, edge in ipairs(tab.edges) do
			edge:SetShown(selected)
		end
		tab:SetHeight(LAYOUT.filterHeight + (selected and 1 or 0))
	end
	-- As wide as their labels, from the left (the Party count changes them).
	-- Most tabs from the left; align = "right" ones from the right end.
	local left, right = 0, 0
	for _, filter in ipairs(ns.Tabs) do
		local tab = filterTabs[filter.id]
		local width = math.max(LAYOUT.tabMinWidth, math.ceil(tab.label:GetStringWidth()) + 2 * LAYOUT.tabPad)
		tab:SetWidth(width)
		tab:ClearAllPoints()
		if filter.align == "right" then
			tab:SetPoint("TOPRIGHT", -right, 0)
			right = right + width + LAYOUT.filterGap
		else
			tab:SetPoint("TOPLEFT", left, 0)
			left = left + width + LAYOUT.filterGap
		end
	end
end

local function LayoutFilter()
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

-- The Debug section: shown only in debug mode, with GO and STOP set by
-- whether a scenario is running.
local function UpdateEmulatorButton()
	local controls = optionsView and optionsView.debug
	if not controls then return end
	local debug = ns.IsDebug()
	for _, part in ipairs(controls.parts) do
		part:SetShown(debug)
	end
	local running = ns.ScenarioRunner:Running()
	controls.go:SetEnabled(not running)
	controls.stop:SetEnabled(running)
	controls.status:SetText(running and L.SCENARIO_RUNNING:format(ns.ScenarioRunner:Selected().label) or L.SCENARIO_IDLE)
	if controls.cycle then
		controls.cycle:SetText(ns.ScenarioRunner:Selected().label)
	end
end

function Panel:SelectFilter(id)
	-- The Chat tab while chat is popped out docks it back (ui\chat.lua).
	local filter = ns.FilterById[id]
	if filter and filter.chat and ns.ChatView:IsPopped() then
		ns.ChatView:SetPopped(false)
		return
	end
	ns.charDb.filter = id
	UpdateFilter()
	if PlaceUnderStrip and filterBar then
		PlaceUnderStrip() -- the filter row shows on feed tabs only
	end
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
-- Settings is its own window, over the game; the feed stays as it is.
function Panel:ShowOptions(show)
	optionsView:SetShown(show)
	optionsButton.lit = show
	optionsButton:UpdateFill()
	if show then
		emptyText:Hide()
		UpdateConnectionOptions(true)
		UpdateEmulatorButton()
		for _, check in ipairs(optionsView.checks) do
			check:SetChecked(ns.IsEnabled(check.settingId))
		end
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
-- An icon drawn in the button's glyph color. The game's icon art is mid-grey,
-- so a tint alone comes out dimmer than the solid glyphs beside it; a second
-- copy blended additively on top brings it up to their brightness.
local function AddIcon(button, file)
	for layer, blend in ipairs({ "BLEND", "ADD" }) do
		local icon = button:CreateTexture(nil, "ARTWORK", nil, layer)
		icon:SetPoint("TOPLEFT", HEADER_BUTTON.iconInset, -HEADER_BUTTON.iconInset)
		icon:SetPoint("BOTTOMRIGHT", -HEADER_BUTTON.iconInset, HEADER_BUTTON.iconInset)
		icon:SetTexture(file)
		icon:SetDesaturated(true)
		icon:SetVertexColor(unpack(HEADER_BUTTON.glyph))
		icon:SetBlendMode(blend)
	end
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
		return L.OPTIONS
	end, function()
		Panel:ShowOptions(not optionsView:IsShown())
	end)
	optionsButton:SetPoint("RIGHT", close, "LEFT", -HEADER_BUTTON.gap, 0)
	AddIcon(optionsButton, HEADER_BUTTON.optionsIcon)

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

	-- Minimize to the dock (ui\dock.lua): a bar, as a window's minimize has.
	local minimize = CreateHeaderButton(function()
		return L.DOCK_MINIMIZE, L.DOCK_MINIMIZE_TIP
	end, function()
		Panel:Minimize()
	end)
	minimize:SetPoint("RIGHT", viewButton, "LEFT", -HEADER_BUTTON.gap, 0)
	local dash = minimize:CreateTexture(nil, "ARTWORK")
	dash:SetSize(HEADER_BUTTON.barWidth, HEADER_BUTTON.barHeight)
	dash:SetPoint("CENTER", 0, -4)
	dash:SetColorTexture(unpack(HEADER_BUTTON.glyph))

	-- Sounds on and off (the Sounds switch in Settings): a speaker.
	-- Steps the volume down: loud, regular, soft, mute, then loud again.
	soundButton = CreateHeaderButton(function()
		local level = ns.VolumeLevels[ns.GetSlider("volume") or 2]
		return L.SOUNDS_LEVEL:format(level and level.label or ""), L.SOUNDS_TIP
	end, function()
		local value = ns.GetSlider("volume") or 2
		ns.SetSlider("volume", value == 0 and 3 or value - 1)
	end)
	soundButton:SetPoint("RIGHT", minimize, "LEFT", -HEADER_BUTTON.gap, 0)
	soundButton.icon = soundButton:CreateTexture(nil, "ARTWORK")
	soundButton.icon:SetPoint("TOPLEFT", 2, -2)
	soundButton.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	UpdateSoundButton()

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

-- The filter row: an icon per kind of row (data\filters.lua, GutterFilters),
-- to show or hide it in your feed. Placed by PlaceUnderStrip.
local function BuildGutter()
	gutter = CreateFrame("Frame", nil, frame)
	gutter:SetClipsChildren(true) -- icons past the right edge are cut off; widen the panel to see them
	local back = gutter:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(unpack(COLORS.row))
	gutter.buttons = {}
	for index, filter in ipairs(ns.GutterFilters) do
		local button = CreateFrame("Button", nil, gutter, "BackdropTemplate")
		button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = LAYOUT.gutterEdge })
		button:SetBackdropColor(0, 0, 0, 0.6)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		local inset = LAYOUT.gutterIconInset
		button.icon:SetPoint("TOPLEFT", inset, -inset)
		button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
		button.icon:SetTexture(filter.icon)
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button.filter = filter
		button:SetScript("OnClick", function()
			ns.charDb.hidden[filter.id] = (not ns.charDb.hidden[filter.id]) or nil
			UpdateGutter()
			Panel:Refresh()
		end)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(filter.label)
			GameTooltip:AddLine(ns.charDb.hidden[filter.id] and L.GUTTER_HIDDEN or L.GUTTER_SHOWN, 1, 1, 1, true)
			GameTooltip:AddLine(L.GUTTER_NOTE, 0.7, 0.7, 0.7, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		gutter.buttons[index] = button
	end
end

-- Sizes the filter row and its icons to the slider's scale, left to right.
local function LayoutGutter()
	local icon, gap = GutterSizes()
	gutter:SetHeight(icon)
	for index, button in ipairs(gutter.buttons) do
		button:SetSize(icon, icon)
		button:ClearAllPoints()
		button:SetPoint("LEFT", (index - 1) * (icon + gap), 0)
	end
end

-- The tabs stay on one row, below the title bar.
local function BuildFilter()
	BuildGutter()
	LayoutGutter()
	filterBar = CreateFrame("Frame", nil, frame)
	filterBar:SetHeight(LAYOUT.filterHeight)
	filterBar:SetPoint("TOPLEFT", ContentLeft(), -LAYOUT.headerHeight)
	filterBar:SetPoint("TOPRIGHT", -LAYOUT.inset, -LAYOUT.headerHeight)
	-- A line under the tabs; the selected tab covers it.
	local line = filterBar:CreateTexture(nil, "BACKGROUND")
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetColorTexture(unpack(COLORS.tabEdge))
	for _, filter in ipairs(ns.Tabs) do
		local tab = CreateFrame("Button", nil, filterBar)
		tab.background = tab:CreateTexture(nil, "BACKGROUND")
		tab.background:SetAllPoints()
		tab.edges = {}
		for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
			local edge = tab:CreateTexture(nil, "BORDER")
			edge:SetColorTexture(unpack(COLORS.tabEdge))
			edge:SetPoint(side[1])
			edge:SetPoint(side[2])
			if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end
			tab.edges[#tab.edges + 1] = edge
		end
		tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		tab.label:SetPoint("CENTER", 0, 0)
		tab.label:SetWordWrap(false)
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
	-- The level, in the middle of the bar.
	bar.level = fill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	bar.level:SetPoint("CENTER")
	bar.level:SetShadowOffset(1, -1)
	bar.name = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.name:SetPoint("LEFT", 3, 0)
	bar.name:SetPoint("RIGHT", bar.level, "LEFT", -6, 0)
	bar.name:SetJustifyH("LEFT")
	bar.name:SetWordWrap(false)
	bar.name:SetShadowOffset(1, -1)

	bar:EnableMouse(true)
	bar:SetScript("OnEnter", ShowBarTip)
	bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return bar
end

-- Puts the tabs and the list under however many bars there are, and the
-- filter row (on feed tabs) along the bottom.
PlaceUnderStrip = function()
	local top = LAYOUT.headerHeight + StripHeight()
	filterBar:ClearAllPoints()
	filterBar:SetPoint("TOPLEFT", ContentLeft(), -top)
	filterBar:SetPoint("TOPRIGHT", -LAYOUT.inset, -top)
	-- The filter row sits along the bottom, clear of the resize grip.
	gutter:ClearAllPoints()
	gutter:SetPoint("BOTTOMLEFT", LAYOUT.inset, LAYOUT.inset)
	gutter:SetPoint("BOTTOMRIGHT", -(LAYOUT.inset + LAYOUT.gripSize + 2), LAYOUT.inset)
	gutter:SetShown(GutterShown())
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
		bar.level:SetText(entry.levelText)
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
	scrollBox:SetPoint("TOPLEFT", ContentLeft(), -ListTop())
	scrollBox:SetPoint("BOTTOMRIGHT", -(LAYOUT.inset + LAYOUT.scrollBarWidth + 4), LAYOUT.inset + GutterHeight())
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
-- Settings: a window of its own, in Quest Party's colors. The channel first,
-- then a section for each group of switches (data\settings.lua), saved data,
-- and in debug mode the emulator.
local function SettingsTip(owner, title, line)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		if line then
			GameTooltip:AddLine(type(line) == "function" and line() or line, 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildSettingsWindow()
	-- Dragged by its title, closed with its button or Escape.
	optionsView = CreateFrame("Frame", ns.Globals.frame("Settings"), UIParent, "BackdropTemplate")
	optionsView:SetSize(SETTINGS.width, SETTINGS.height)
	optionsView:SetPoint("CENTER")
	optionsView:SetFrameStrata("DIALOG")
	optionsView:SetToplevel(true)
	optionsView:SetClampedToScreen(true)
	optionsView:EnableMouse(true)
	optionsView:SetMovable(true)
	optionsView:RegisterForDrag("LeftButton")
	optionsView:SetScript("OnDragStart", optionsView.StartMoving)
	optionsView:SetScript("OnDragStop", optionsView.StopMovingOrSizing)
	optionsView:SetScript("OnHide", function()
		optionsButton.lit = false
		optionsButton:UpdateFill()
	end)
	tinsert(UISpecialFrames, optionsView:GetName())
	optionsView:SetBackdrop(BACKDROP)
	optionsView:SetBackdropColor(unpack(COLORS.panel))
	optionsView:SetBackdropBorderColor(unpack(COLORS.border))
	optionsView:Hide()
	optionsView.checks = {}

	local close = CreateFrame("Button", nil, optionsView, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	close:SetScript("OnClick", function()
		Panel:ShowOptions(false)
	end)
	local icon = optionsView:CreateTexture(nil, "ARTWORK")
	icon:SetSize(HEADER_BUTTON.size, HEADER_BUTTON.size)
	icon:SetPoint("TOPLEFT", LAYOUT.inset, -HEADER_BUTTON.top)
	icon:SetTexture(HEADER_BUTTON.optionsIcon)
	icon:SetDesaturated(true)
	icon:SetVertexColor(unpack(HEADER_BUTTON.glyph))
	local title = optionsView:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	title:SetText(L.OPTIONS_TITLE:format(ns.version))
	local rule = optionsView:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", LAYOUT.inset, -SETTINGS.titleHeight)
	rule:SetPoint("TOPRIGHT", -LAYOUT.inset, -SETTINGS.titleHeight)
	rule:SetColorTexture(unpack(SETTINGS.rule))

	local scroll = CreateFrame("ScrollFrame", nil, optionsView, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LAYOUT.inset + 4, -(SETTINGS.titleHeight + 8))
	scroll:SetPoint("BOTTOMRIGHT", -30, LAYOUT.inset + 4)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, -14)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 14)
	local content = CreateFrame("Frame", nil, scroll)
	local width = SETTINGS.width - 2 * LAYOUT.inset - 4 - 30
	content:SetWidth(width)
	scroll:SetScrollChild(content)
	return content, width
end

-- A section's title over a thin gold line. Returns the y below it.
local function SettingsHeading(content, text, y)
	local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", 2, -y)
	label:SetText(text)
	local line = content:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", 2, -(y + 17))
	line:SetPoint("TOPRIGHT", -2, -(y + 17))
	line:SetColorTexture(unpack(SETTINGS.rule))
	return y + SETTINGS.headingHeight, label, line
end

local function BuildChannel(content, y)
	y = SettingsHeading(content, L.CHANNEL_LABEL, y)
	local name = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	name:SetHeight(22)
	name:SetPoint("TOPLEFT", 8, -y)
	name:SetPoint("TOPRIGHT", -(2 * SETTINGS.buttonWidth + 14), -y)
	name:SetAutoFocus(false)
	name:SetMaxLetters(30)
	name.Instructions = name:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	name.Instructions:SetPoint("LEFT", 2, 0)
	name.Instructions:SetText(L.CHANNEL_HINT)
	local join = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	join:SetSize(SETTINGS.buttonWidth, 22)
	join:SetPoint("LEFT", name, "RIGHT", 6, 0)
	join:SetText(L.CHANNEL_CONNECT)
	local disconnect = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	disconnect:SetSize(SETTINGS.buttonWidth, 22)
	disconnect:SetPoint("LEFT", join, "RIGHT", 4, 0)
	disconnect:SetText(L.CHANNEL_DISCONNECT)
	local status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", 4, -(y + 28))
	status:SetPoint("TOPRIGHT", -4, -(y + 28))
	status:SetJustifyH("LEFT")
	status:SetWordWrap(true)
	optionsView.connection = { name = name, join = join, disconnect = disconnect, status = status }
	-- Letters and numbers only: anything else typed or pasted is taken out
	-- as it goes in, and the status line says why.
	name:SetScript("OnTextChanged", function(self, byUser)
		local text = self:GetText()
		self.Instructions:SetShown(text == "")
		if not byUser then
			return
		end
		local clean = ns.CleanChannelName(text)
		if clean ~= text then
			local cursor = self:GetCursorPosition() - (#text - #clean)
			self:SetText(clean)
			self:SetCursorPosition(math.max(0, cursor))
			status:SetText(L.CHANNEL_LETTERS_ONLY)
			status:SetTextColor(1, 0.82, 0)
		end
	end)
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
	return y + 50
end

-- One slider: its label, the bar, and its value beside it.
local function BuildSlider(content, width, slider, y)
	local label = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 6, -(y + 6))
	label:SetText(slider.label)
	local value = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	value:SetPoint("TOPRIGHT", -4, -(y + 6))
	local bar = CreateFrame("Slider", nil, content, "UISliderTemplate")
	bar:SetPoint("TOPLEFT", SETTINGS.sliderLeft, -(y + 4))
	bar:SetPoint("TOPRIGHT", -SETTINGS.sliderRight, -(y + 4))
	bar:SetHeight(17)
	bar:SetMinMaxValues(slider.min, slider.max)
	bar:SetValueStep(slider.step)
	bar:SetObeyStepOnDrag(true)
	-- How its value reads: a label from its list, or its format.
	local function Reads(number)
		local list = slider.labels and ns[slider.labels]
		if list and list[number] then
			return list[number].label
		end
		return (slider.format or "%s"):format(number)
	end
	bar:SetValue(ns.GetSlider(slider.id))
	value:SetText(Reads(ns.GetSlider(slider.id)))
	bar:SetScript("OnValueChanged", function(_, moved, byUser)
		if byUser then
			value:SetText(Reads(ns.SetSlider(slider.id, moved)))
		end
	end)
	-- Kept in step when the value changes elsewhere (the speaker).
	Bus:On("SLIDER_CHANGED", function(id, number)
		if id == slider.id and bar:GetValue() ~= number then
			bar:SetValue(number)
			value:SetText(Reads(number))
		end
	end)
	SettingsTip(bar, slider.label, slider.tip)
	return y + SETTINGS.sliderHeight
end

-- A group's switches, in two columns, then its sliders.
local function BuildSwitches(content, width, group, y)
	y = SettingsHeading(content, group.label, y)
	local column = (width - 4) / 2
	local index = 0
	for _, setting in ipairs(ns.Settings) do
		if setting.group == group.id then
			local check = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
			check:SetSize(SETTINGS.checkSize, SETTINGS.checkSize)
			check:SetPoint("TOPLEFT", 2 + (index % 2) * column, -(y + math.floor(index / 2) * SETTINGS.rowHeight))
			check.settingId = setting.id
			check.Text:SetFontObject("GameFontHighlight")
			check.Text:SetText(setting.label)
			check:SetScript("OnClick", function(self)
				ns.SetEnabled(setting.id, self:GetChecked())
			end)
			SettingsTip(check, setting.label, setting.tip)
			optionsView.checks[#optionsView.checks + 1] = check
			index = index + 1
		end
	end
	y = y + math.ceil(index / 2) * SETTINGS.rowHeight
	for _, slider in ipairs(ns.SettingSliders) do
		if slider.group == group.id then
			y = BuildSlider(content, width, slider, y)
		end
	end
	return y + SETTINGS.sectionGap
end

-- Clearing and forgetting: each forget button says how much it holds.
local function BuildData(content, y)
	y = SettingsHeading(content, L.SET_GROUP_DATA, y)
	local actions = {
		{ label = L.CLEAR, tip = L.CLEAR_TIP, run = function() ns.ConfirmClear() end },
		{ label = L.FORGET_PLAYERS, tip = L.FORGET_PLAYERS_TIP, what = "players", count = "members" },
		{ label = L.FORGET_CARDS, tip = L.FORGET_CARDS_TIP, what = "cards", count = "cards" },
	}
	local previous
	for _, action in ipairs(actions) do
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetSize(SETTINGS.dataButtonWidth, 22)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
		else
			button:SetPoint("TOPLEFT", 4, -y)
		end
		button:SetText(action.label)
		button:SetScript("OnClick", action.run or function()
			ns.Store:Prune(action.what)
			ns.Print(L.FORGOT:format(action.label))
		end)
		SettingsTip(button, action.label, function()
			if not action.count then
				return action.tip
			end
			return action.tip .. "\n" .. L.FORGET_HOLDS:format(ns.Store:Counts()[action.count])
		end)
		previous = button
	end
	return y + 22 + SETTINGS.sectionGap
end

-- Test runs, in debug mode only: a scenario to choose (emulator\scenarios.lua,
-- or the sandbox's), Clear on go, and GO and STOP.
local function ScenarioChooser(content)
	local runner = ns.ScenarioRunner
	local ok, dropdown = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	if ok and dropdown and dropdown.SetupMenu then
		dropdown:SetupMenu(function(_, root)
			for _, scenario in ipairs(ns.Scenarios) do
				root:CreateRadio(scenario.label, function(id) return runner:Selected().id == id end, function(id) runner:Select(id) end, scenario.id)
			end
		end)
		return dropdown
	end
	-- Without the game's menus: a button that steps through the scenarios.
	local cycle = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	cycle:SetScript("OnClick", function()
		local list, current = ns.Scenarios, runner:Selected()
		for index, scenario in ipairs(list) do
			if scenario == current then
				runner:Select(list[index % #list + 1].id)
				break
			end
		end
		UpdateEmulatorButton()
	end)
	return cycle, true
end

local function BuildDebug(content, y)
	local _, label, line = SettingsHeading(content, L.SET_GROUP_DEBUG, y)
	y = y + SETTINGS.headingHeight
	local chooser, isCycle = ScenarioChooser(content)
	chooser:SetSize(SETTINGS.scenarioWidth, 24)
	chooser:SetPoint("TOPLEFT", 4, -y)
	local clear = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	clear:SetSize(SETTINGS.checkSize, SETTINGS.checkSize)
	clear:SetPoint("LEFT", chooser, "RIGHT", 10, 0)
	clear.Text:SetFontObject("GameFontHighlight")
	clear.Text:SetText(L.SCENARIO_CLEAR)
	clear:SetChecked(ns.charDb.scenarioClear ~= false)
	clear:SetScript("OnClick", function(self) ns.charDb.scenarioClear = self:GetChecked() and true or false end)
	SettingsTip(clear, L.SCENARIO_CLEAR, L.SCENARIO_CLEAR_TIP)
	y = y + 32
	local go = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	go:SetSize(SETTINGS.goWidth, 24)
	go:SetPoint("TOPLEFT", 4, -y)
	go:SetText(L.SCENARIO_GO)
	go:SetScript("OnClick", function()
		local started, problem = ns.ScenarioRunner:Go(ns.charDb.scenarioClear ~= false)
		if not started then
			ns.Print(problem or L.SCENARIO_IDLE)
		end
		UpdateEmulatorButton()
	end)
	local stop = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	stop:SetSize(SETTINGS.goWidth, 24)
	stop:SetPoint("LEFT", go, "RIGHT", 6, 0)
	stop:SetText(L.SCENARIO_STOP)
	stop:SetScript("OnClick", function()
		ns.ScenarioRunner:Stop()
		UpdateEmulatorButton()
	end)
	local status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("LEFT", stop, "RIGHT", 10, 0)
	status:SetPoint("RIGHT", -4, 0)
	status:SetJustifyH("LEFT")
	optionsView.debug = {
		go = go, stop = stop, status = status, cycle = isCycle and chooser or nil,
		parts = { label, line, chooser, clear, go, stop, status },
	}
	UpdateEmulatorButton()
	return y + 24 + SETTINGS.sectionGap
end

local function BuildOptions()
	local content, width = BuildSettingsWindow()
	local y = BuildChannel(content, 0)
	for _, group in ipairs(ns.SettingGroups) do
		y = BuildSwitches(content, width, group, y)
	end
	y = BuildData(content, y)
	y = BuildDebug(content, y)
	content:SetHeight(y)
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
	frame = CreateFrame("Frame", ns.Globals.frame("Panel"), UIParent, "BackdropTemplate")
	local size = ns.charDb.size
	frame:SetSize(size and size.width or LAYOUT.width, size and size.height or LAYOUT.height)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(unpack(COLORS.panel))
	frame:SetBackdropBorderColor(unpack(COLORS.border))
	frame:SetFrameStrata("MEDIUM")
	frame:SetToplevel(true) -- a click brings it in front of other windows
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
	BuildShrink()
	C_Timer.NewTicker(LAYOUT.refreshSeconds, function()
		Panel:Refresh()
	end)

	-- A saved filter that is no longer a tab falls back to the first tab.
	local saved = ns.FilterById[ns.charDb.filter]
	if not (saved and saved.tab) then
		ns.charDb.filter = ns.Tabs[1].id
	end
	UpdateFilter()
	PlaceUnderStrip()
	UpdateEmulatorButton()
	frame:SetShown(ns.charDb.shown and not ns.charDb.docked)
	if ns.charDb.docked then
		C_Timer.After(0, function() ns.Dock:Show() end)
	end
	Panel:Refresh(true)
	-- Again on the next frame: the first pass runs before the list has its real size,
	-- and the scroll position it sets does not survive the first layout.
	C_Timer.After(0, function()
		LayoutFilter()
		Panel:Refresh(true)
	end)
end

-- The window, for frames that sit beside it (ui\party.lua).
function Panel:GetFrame()
	return frame
end

function Panel:Toggle()
	if not frame then return end
	if ns.charDb.docked then
		self:Restore()
		return
	end
	frame:SetShown(not frame:IsShown())
end

-- ========= Minimized to the dock ============================================
-- The panel shrinks and fades toward the dock's edge (ui\dock.lua), and grows
-- back out of it to where it was. Moving it while open is remembered as usual,
-- so it comes back to the latest spot.
local SHRINK = { scale = 0.08, seconds = 0.28 }
local shrink, shrinkMove, shrinkScale, growing

-- Points the shrink at the dock: from the panel's middle to the dock's edge.
local function AimShrink()
	local dockX, dockY = ns.Dock:Point()
	local x, y = frame:GetCenter()
	local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	shrinkMove:SetOffset((dockX - x * scale) / scale, (dockY - y * scale) / scale)
end

BuildShrink = function()
	shrink = frame:CreateAnimationGroup()
	shrinkScale = shrink:CreateAnimation("Scale")
	if shrinkScale.SetScaleFrom then
		shrinkScale:SetScaleFrom(1, 1)
		shrinkScale:SetScaleTo(SHRINK.scale, SHRINK.scale)
	else
		shrinkScale:SetFromScale(1, 1)
		shrinkScale:SetToScale(SHRINK.scale, SHRINK.scale)
	end
	shrinkScale:SetDuration(SHRINK.seconds)
	shrinkScale:SetSmoothing("IN")
	shrinkMove = shrink:CreateAnimation("Translation")
	shrinkMove:SetDuration(SHRINK.seconds)
	shrinkMove:SetSmoothing("IN")
	local fade = shrink:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(SHRINK.seconds)
	shrink:SetScript("OnFinished", function()
		if not growing then
			frame:Hide()
		end
		growing = false
	end)
end

function Panel:Minimize()
	if not frame or not frame:IsShown() or shrink:IsPlaying() then return end
	SavePosition()
	ns.charDb.docked = true
	self:ShowOptions(false)
	ns.Dock:Show()
	AimShrink()
	growing = false
	shrink:Play()
end

-- Opens the panel out of the dock, on a tab when one is given.
function Panel:Restore(tab)
	if not frame then return end
	ns.charDb.docked = false
	ns.Dock:Hide()
	RestorePosition()
	frame:Show()
	if tab and ns.FilterById[tab] then
		self:SelectFilter(tab)
	end
	AimShrink()
	growing = true
	shrink:Play(true) -- the shrink, backwards: it grows out of the dock
end

Bus:On("READY", Build)

-- A busy channel changes the store many times a second: draw once for all
-- of them, a moment later.
local REDRAW_SECONDS = 0.2
local redrawPending = false
Bus:On("STORE_CHANGED", function()
	if redrawPending then
		return
	end
	redrawPending = true
	C_Timer.After(REDRAW_SECONDS, function()
		redrawPending = false
		Panel:UpdateXpBars()
		ns.Confetti:SetHost(frame)
		Panel:Refresh()
	end)
end)

Bus:On("CHAT_CHANGED", function()
	if frame then
		UpdateFilter() -- the Chat tab's count of new messages
	end
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

-- The Filter icon size slider: resize the filter row and move the list.
Bus:On("SLIDER_CHANGED", function(id)
	if id == "gutterScale" and gutter then
		LayoutGutter()
		PlaceUnderStrip()
		Panel:Refresh()
	end
end)

Bus:On("SLIDER_CHANGED", function(id)
	if id == "volume" then
		UpdateSoundButton()
	end
end)
