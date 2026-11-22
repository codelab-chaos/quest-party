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
	edgeGrab = 5, -- how thick each edge's invisible sizing strip is
	headerHeight = 30,
	filterHeight = 18,
	filterGap = 3,
	cycleSize = 14, -- the Quest tab's layout gear
	questBarHeight = 18, -- the Quest tab's own row at the top of its list
	tabMinWidth = 64, -- tabs fit their labels, at least this wide
	tabPad = 14, -- either side of a tab's label
	-- The filter row: a row of icons along the bottom of the panel, under the
	-- feed (the code calls it the gutter). Sizes at a scale of 1; the Filter icon
	-- size slider scales them.
	gutterIcon = 22,
	gutterIconGap = 4,
	afkBarAlpha = 0.55, -- an AFK player's bar: dimmer, still there
	gutterRowGap = 13, -- between the feed and the filter row, with a line across its middle
	gutterRule = { 0.80, 0.65, 0.20, 0.55 }, -- that line, gold
	kekChatClear = 2, -- between KekChat's button on the line and the filter icons under it
	gutterOffAlpha = 0.35, -- an icon whose rows are hidden
	gutterEdge = 1, -- the border around each icon
	gutterIconInset = 2, -- the icon inside its border
	inset = 8,
	rowSpacing = 2,
	pulseSeconds = 0.9,
	glowSeconds = 1.4, -- a shared quest's glow, one breath in or out
	pulseMemory = 400,
	optionHeight = 22,

	scrollBarWidth = 12,
	refreshSeconds = 30,
	-- The party's XP bars, stacked above the tabs. Past the Players shown cap the
	-- rest are left out, so the bars never crowd out the list.
	xpBarHeight = 14,
	xpBarEdge = 7, -- the rounded border's size: half the height makes round ends
	xpBarInset = 2, -- the fill sits this far inside the border
	xpBarGap = 2,
	-- Under each XP bar, health then power: thin, the bar's width.
	-- (how many show is the Players shown slider: ViewModel.PartyCap)
	xpStripGap = 4, -- between the last bar and the tabs
	xpBarNotches = 3, -- marks splitting each bar into equal parts (3 makes quarters)
}

local COLORS = {
	-- The rows' and panel's palette is the chosen theme (data\themes.lua).
	border = { 0.80, 0.65, 0.20, 1 },
	gutterOff = { 0.35, 0.35, 0.35, 0.6 }, -- a gutter icon's border when its rows are hidden
	count = { 1, 0.82, 0 }, -- an objective's count (4/8), in the title's size
	countDone = { 0.25, 1, 0.25 }, -- a count that is complete (8/8)
	rightMuted = { 0.78, 0.78, 0.78 }, -- a row's time, on the right: soft but readable
	tab = { 0.10, 0.09, 0.13, 1 },
	tabSelected = { 0.42, 0.33, 0.10, 1 },
	tabEdge = { 0.80, 0.65, 0.20, 1 }, -- the selected tab's outline and the line under the tabs
	bar = { 0.25, 0.75, 0.30, 1 }, -- a progress bar that is done (green, as its count)
	barGoing = { 0.85, 0.16, 0.14, 1 }, -- one still going (red)
	barBack = { 0, 0, 0, 0.5 },
	pulse = { 1, 0.85, 0.35, 0.55 },
	sharedGlow = { 0.667, 0.667, 1, 0.95 }, -- a quest you share: the party chat's color (PartyColor)
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
		avatarSize = 24, -- the player's round avatar, inside the card's top left corner (34, then 27, before)
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
		avatarSize = 16,
		titleFont = "GameFontHighlightSmall",
		barHeight = 2,
	},
}

-- The Settings window.
local SETTINGS = {
	width = 540,
	height = 660,
	titleHeight = 32, -- the title, then a gold rule under it
	headingHeight = 26, -- a section's title and its rule
	recentHeight = 24, -- the recent channels' row, under the channel's status
	sectionGap = 12,
	rowHeight = 26, -- a row of switches
	checkSize = 24,
	buttonWidth = 96,
	kekButtonWidth = 180, -- Edit your KekChats
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
	opacityGlyph = 12, -- the opacity button's half-solid square
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
	detailedBars = { [1] = true, [3] = true }, -- detailed (two-line) rows: two bars; compact (one-line) rows: all three
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
local RIGHT_TEXT_WIDTH = 58 -- the most the time or count can take

-- How far from the right a row's text must stop: just clear of what is on
-- the right (the time, a count), not a fixed width, so titles run as far as
-- they can. With nothing there, a small margin.
local function RightRoom(fontString, text)
	if not text or text == "" then return 8 end
	return math.min(RIGHT_TEXT_WIDTH, math.ceil(fontString:GetStringWidth() or RIGHT_TEXT_WIDTH)) + 12
end

-- The room kept at a detail line's right when it has nothing there: stamps
-- are inked over the card (ui\stamps.lua), not beside the text.
local LINE_END_ROOM = 8

-- The row style: one line or detailed, as the view button says, unless a
-- row is drawn for elsewhere in a style of its own (the dock: DrawFeedRow).
local styleOverride
local function StyleName()
	return styleOverride or (ns.charDb.oneLine and "oneLine" or "detailed")
end

local function RowHeight(data)
	local style = ROW_STYLES[StyleName()]
	if style.height then
		return style.height
	end
	-- A quest card in one of its layouts (ui\\quest-card.lua).
	local card = ns.QuestCard:For(data)
	if card then
		return style.titleHeight + card.Height(data) + style.bottomPadding
	end
	local height = style.titleHeight + style.bottomPadding
	for _, line in ipairs(data.lines) do
		height = height + (line.progress and style.barLineHeight or style.lineHeight)
	end
	return height
end

-- Which of the theme's row colors each kind of row takes (data\themes.lua).
-- The glow's soft edge: the tooltip border, tinted gold. Inside the row, so
-- the list's clipping and the next row never cut it.
local GLOW_BACKDROP = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
}

local ROW_BACKGROUND = {
	feed = "row",
	progress = "card",
	tracker = "card",
	member = "card",
}

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local frame, scrollBox, scrollBar, listView, emptyText, optionsView, optionsButton, viewButton, titleIcon, soundButton
local panelTitle

-- The title in full when it fits beside the header buttons, else its short
-- form; the font string cuts anything still too long.
-- The title: Quest Party, then (with Show channel in title on) the channel you
-- share on, in grey. It runs
-- under the header buttons, which sit over whatever does not fit; when even
-- "Quest Party" would not show before them, it is QP.
local function FitTitle()
	if not panelTitle then return end
	local channel = ns.IsEnabled("titleChannel") and ns.Session and ns.Session.state == "connected" and ns.db.connection and ns.db.connection.name
	local after = channel and channel ~= "" and ("  |cff9d9d9d" .. channel .. "|r") or ""
	panelTitle:SetText(L.TITLE)
	local wanted = panelTitle.GetUnboundedStringWidth and panelTitle:GetUnboundedStringWidth() or panelTitle:GetStringWidth()
	local left, buttons = panelTitle:GetLeft(), panelTitle.buttons and panelTitle.buttons:GetLeft()
	local room = (type(left) == "number" and type(buttons) == "number") and (buttons - 6 - left) or 0
	local name = (room > 0 and wanted > room) and L.TITLE_SHORT or L.TITLE
	panelTitle:SetText(name .. after)
end
local BarStep -- from one party bar to the next (defined with the bars)

-- The speaker shows the volume: a speaker and three rising bars beside it,
-- as many lit as the level (soft one, regular two, loud three); at Mute the
-- speaker is crossed out and no bar is lit.
local VOLUME_BARS = {
	heights = { 4, 7, 10 }, -- the three bars, rising
	width = 2,
	gap = 1,
	lit = { 1, 0.82, 0.10, 1 },
	dark = { 0.35, 0.35, 0.35, 0.6 },
}
local function UpdateSoundButton()
	if not soundButton then return end
	local value = ns.GetSlider("volume") or 2
	soundButton.icon:SetAtlas(value > 0 and "voicechat-icon-speaker" or "voicechat-icon-speaker-mute")
	soundButton.icon:SetDesaturated(value == 0)
	for index, bar in ipairs(soundButton.levels or {}) do
		bar:SetColorTexture(unpack(index <= value and VOLUME_BARS.lit or VOLUME_BARS.dark))
	end
end
local filterBar, xpStrip, gutter, gutterLine
local PlaceList, PlaceUnderStrip, BuildShrink
local xpBars = {} -- the bar frames, reused
local xpBarsShown = 0
local filterTabs = {}

-- Pulses already shown, so a row flashes once per change and not on every redraw.
local pulsesPlayed = {}
local pulsesPlayedCount = 0

-- ========= Rows =============================================================
-- The party chat's color (ui\look.lua): shared quests glow in it, and your
-- game group's members are marked in it.
local function PartyColor()
	return ns.Look.PartyColor()
end

-- A progress bar's fill and color. A quest's is red while going and green
-- once done; anything else's (an XP row's) stays green.
local function SetProgress(bar, progress, quest)
	bar:SetMinMaxValues(0, progress.need)
	bar:SetValue(progress.have)
	local going = quest and progress.have < progress.need
	bar:SetStatusBarColor(unpack(going and COLORS.barGoing or COLORS.bar))
end

local QUEST_ROWS = { progress = true, tracker = true }

-- ========= Opening a quest in the game's quest log =========================
-- Whether a quest is in your own quest log.
local function InMyLog(questID)
	return questID ~= nil and C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

-- Opens the game's quest log on a quest, with whichever of the game's own
-- calls this client has: the map's quest details (modern log), then the
-- classic quest log by its index, then just the log.
local QUEST_OPENERS = {
	function(questID)
		if not QuestMapFrame_OpenToQuestDetails then return false end
		QuestMapFrame_OpenToQuestDetails(questID)
		return true
	end,
	function(questID)
		local index = C_QuestLog.GetLogIndexForQuestID(questID)
		if not (QuestLog_OpenToQuest and index) then return false end
		QuestLog_OpenToQuest(index, true)
		return true
	end,
	function()
		if ToggleQuestLog then ToggleQuestLog() return true end
		return false
	end,
}

local function OpenQuest(questID)
	for _, opener in ipairs(QUEST_OPENERS) do
		local ok, opened = pcall(opener, questID)
		if ok and opened then return true end
	end
	return false
end

-- ========= Backdrops (a trial: the game's art behind the cards) ==============
local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function ShowBackdrop(row, data)
	local name = ns.IsEnabled("cardBackdrops") and (data.kind == "feed" or data.kind == "progress")
		and ns.Scene:Backdrop(data.sequence or data.index or 0, HasAtlas)
	local info = name and C_Texture.GetAtlasInfo(name)
	if not info or not info.file then
		row.backdrop:Hide()
		return
	end
	local rules = ns.BackdropRules
	local width = (row:GetWidth() or 0) * rules.share
	local height = row:GetHeight() or 0
	row.backdrop:ClearAllPoints()
	row.backdrop:SetPoint("TOPRIGHT")
	row.backdrop:SetPoint("BOTTOMRIGHT")
	row.backdrop:SetWidth(math.max(1, width))
	row.backdrop:SetTexture(info.file)
	local coords = { info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord }
	row.backdrop:SetTexCoord(ns.Scene:Slice(coords, info.width or 1, info.height or 1, width, height, data.sequence or 0))
	-- From nothing under the text to fuller at the right.
	row.backdrop:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, rules.fadeTo))
	row.backdrop:Show()
end

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
	-- The card's backdrop: the game's own art, faint at its left, fuller at
	-- the card's right (ShowBackdrop).
	row.backdrop = row:CreateTexture(nil, "BACKGROUND", nil, 1)

	-- A thin rim around each row, in the theme's color (InitRow).
	row.edges = {}
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local edge = row:CreateTexture(nil, "BACKGROUND", nil, 2)
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end
		row.edges[#row.edges + 1] = edge
	end

	-- The icon's well: a dark square in a gold edge, and a gold line down
	-- the row after it, as the concept art's.
	row.wellEdge = row:CreateTexture(nil, "BORDER", nil, 1)
	row.well = row:CreateTexture(nil, "BORDER", nil, 2)
	row.divider = row:CreateTexture(nil, "BORDER", nil, 2)
	row.divider:SetWidth(1)

	-- A shared quest's glow (ViewModel: shared): a soft gold light around the
	-- row that breathes slowly, so the quests you are on together stand out.
	row.glow = CreateFrame("Frame", nil, row, "BackdropTemplate")
	row.glow:SetAllPoints()
	row.glow:SetBackdrop(GLOW_BACKDROP)
	row.glow:EnableMouse(false)
	row.glow:Hide()
	row.glow.breathe = row.glow:CreateAnimationGroup()
	row.glow.breathe:SetLooping("BOUNCE")
	local breathe = row.glow.breathe:CreateAnimation("Alpha")
	breathe:SetFromAlpha(1)
	breathe:SetToAlpha(0.35)
	breathe:SetDuration(LAYOUT.glowSeconds)
	breathe:SetSmoothing("IN_OUT")

	-- A member of your game group: a stripe down the row's left edge.
	row.groupEdge = row:CreateTexture(nil, "BORDER", nil, 3)
	row.groupEdge:SetPoint("TOPLEFT", 1, -1)
	row.groupEdge:SetPoint("BOTTOMLEFT", 1, 1)
	row.groupEdge:SetWidth(3)
	row.groupEdge:Hide()

	-- The player's avatar: round, in a gold ring (ShowAvatar).
	row.avatarRing = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.avatarRing:SetTexture("Interface\\Buttons\\WHITE8x8")
	row.avatarRing:SetVertexColor(0.80, 0.65, 0.20, 1)
	ns.Look.Round(row.avatarRing, row)
	row.avatar = row:CreateTexture(nil, "ARTWORK", nil, 2)
	ns.Look.Round(row.avatar, row)

	row.hover = row:CreateTexture(nil, "BORDER")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.08)
	row.hover:Hide()

	row.icon = row:CreateTexture(nil, "ARTWORK")
	-- A mark's art or its text ("XP"), centered in the well (ShowMark).
	row.markArt = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.markArt:SetPoint("CENTER", row.icon, "CENTER")
	row.markArt:Hide()
	row.markText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	row.markText:SetPoint("CENTER", row.icon, "CENTER", 1, 0)
	row.markText:Hide()

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
	-- However it ends (finished, stopped, or cut off while hidden), the flash
	-- is gone: a flash left showing tints the whole row gold.
	local function Clear() row.pulse:SetAlpha(0) end
	row.pulseAnimation:SetScript("OnFinished", Clear)
	row.pulseAnimation:SetScript("OnStop", Clear)

	-- Rows about a quest can be clicked: in the feed, to show it in the Quest
	-- tab; in the Quest tab, a quest in your own log opens in the game's quest
	-- log (one only others have does not).
	row:SetScript("OnEnter", function(self)
		if not (self.quest or self.stampEntry) then return end
		self.hover:Show()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		-- Who it was: the rows show only their avatar.
		if self.playerName then
			GameTooltip:SetText(self.playerName)
		end
		if self.quest then
			if self.playerName then GameTooltip:AddLine(self.quest, 1, 0.82, 0) else GameTooltip:SetText(self.quest) end
			local tip = L.ROW_CLICK_TIP
			if ns.charDb.filter == ns.QuestTab then
				tip = InMyLog(self.questID) and L.ROW_OPEN_TIP or L.ROW_NOT_YOURS_TIP
			end
			GameTooltip:AddLine(tip, 1, 1, 1, true)
		elseif not self.playerName then
			GameTooltip:SetText(L.STAMP_TIP_TITLE)
		end
		ns.StampView:Tip(self) -- right-click to stamp, and who has
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.hover:Hide()
		GameTooltip:Hide()
	end)
	row:SetScript("OnMouseUp", function(self, button)
		-- Right-click: stamp the card (ui\stamps.lua).
		if button == "RightButton" then
			ns.StampView:Open(self)
			return
		end
		-- A row drawn elsewhere (a dock drawer) says what a click does there.
		if self.onLeftClick then
			self.onLeftClick()
			return
		end
		if not self.quest then return end
		if ns.charDb.filter == ns.QuestTab then
			if InMyLog(self.questID) then OpenQuest(self.questID) end
			return
		end
		Panel:FocusQuest(self.quest)
	end)

	ns.StampView:Build(row) -- stamps on the card (ui\stamps.lua)
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
	row.pulse:SetAlpha(0)
	if not pulse or pulsesPlayed[pulse] or not row:IsVisible() then
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
-- ========= The row's two ends (the winning concept) ===========================
-- On the left, the player's round avatar in a gold ring: their face (race
-- and sex) when known, their class otherwise (the game's round class icons). On the right, the event's mark in a gold
-- edged square (or a level-up's round crest), with the time just before it.
local MARK_EDGE = 8 -- the mark's distance from the row's right edge

-- Where the text starts: past the avatar, or near the edge without one.
local AVATAR_EDGE = 1 -- the avatar's gold ring, this thick
local AVATAR_INSET = 1 -- from the card's top and left: the ring touches its rim

local function TextLeft(data, style)
	return data.player and (AVATAR_INSET + style.avatarSize + 2 * AVATAR_EDGE + 6) or 8
end


-- How far from the right the text must stop: past the mark and the time.
local function MarkRoom(style)
	return MARK_EDGE + style.iconSize + 8
end

local function AvatarWidth(style)
	return style.avatarSize + 2 * AVATAR_EDGE
end

-- Where a row's mark and avatar sit. In the feed: the avatar at the left, the
-- mark at the right, the text between. A dock drawer (data.ends, "LEFT" or
-- "RIGHT": the end resting in the housing) has both at that end, the mark
-- outermost and the avatar beside it, and its text runs away from them:
--   ends RIGHT:  [ text, right aligned ][avatar][mark]
--   ends LEFT:   [mark][avatar][ text, left aligned ]
-- Returns the room kept at the row's left and right for its text.
local function TextEnds(row, data, style)
	local cluster = MarkRoom(style) + AvatarWidth(style) + 6
	if data.ends == "LEFT" then return cluster, 8 end
	if data.ends == "RIGHT" then return 8, cluster end
	return TextLeft(data, style), MarkRoom(style) + RightRoom(row.right, data.right)
end

-- The mark square, and the text beside it (a time), at its end.
local function PlaceMark(row, data, top)
	local left = data.ends == "LEFT"
	local side, inner = left and "LEFT" or "RIGHT", left and "RIGHT" or "LEFT"
	local edge, gap = left and MARK_EDGE or -MARK_EDGE, left and 8 or -8
	if top then
		row.icon:SetPoint("TOP" .. side, edge, -6)
		row.right:SetPoint("TOP" .. side, row.icon, "TOP" .. inner, gap, 0)
	else
		row.icon:SetPoint(side, edge, 0)
		row.right:SetPoint(side, row.icon, inner, gap, 0)
	end
	local justify = data.ends == "RIGHT" and "RIGHT" or "LEFT"
	row.title:SetJustifyH(justify)
	for _, line in ipairs(row.lines or {}) do line.text:SetJustifyH(justify) end
end

local function ShowAvatar(row, data, style, top)
	local shown = data.player ~= nil
	row.avatarRing:SetShown(shown)
	row.avatar:SetShown(shown)
	if not shown then return end
	local size = style.avatarSize
	row.avatarRing:ClearAllPoints()
	row.avatarRing:SetSize(size + 2 * AVATAR_EDGE, size + 2 * AVATAR_EDGE)
	-- In the feed: touching the card's top and left rim, inside it. In a dock
	-- drawer (data.ends): beside the mark, at that end (TextEnds).
	local side = data.ends or "LEFT"
	local inset = AVATAR_INSET
	if data.ends then inset = MarkRoom(style) end
	if side == "RIGHT" then inset = -inset end
	if top then
		row.avatarRing:SetPoint("TOP" .. side, inset, -AVATAR_INSET)
	else
		row.avatarRing:SetPoint(side, inset, 0)
	end
	row.avatar:ClearAllPoints()
	row.avatar:SetPoint("TOPLEFT", row.avatarRing, "TOPLEFT", AVATAR_EDGE, -AVATAR_EDGE)
	row.avatar:SetPoint("BOTTOMRIGHT", row.avatarRing, "BOTTOMRIGHT", -AVATAR_EDGE, AVATAR_EDGE)
	-- Their face when their race and sex are known (yours always; anyone on
	-- 0.3.5 or later says them in the hello), their class otherwise.
	local portrait = ns.PartyModel:Portrait(data.player)
	portrait.class = portrait.class or data.class
	ns.Look.SetPortrait(row.avatar, portrait)
end

local function LayoutOneLine(row, data, style)
	PlaceMark(row, data)
	ShowAvatar(row, data, style)
	local left, right = TextEnds(row, data, style)
	row.title:SetPoint("LEFT", left, 0)
	row.title:SetPoint("RIGHT", -right, 0)
	if data.summary then
		row.title:SetText(data.title .. "  " .. data.summary)
	else
		row.title:SetText(data.title)
	end
	HideLines(row, 1)

	if data.progress then
		row.strip:SetHeight(style.barHeight)
		SetProgress(row.strip, data.progress, QUEST_ROWS[data.kind])
		row.strip:Show()
	else
		row.strip:Hide()
	end
end

local function LayoutDetailed(row, data, style)
	PlaceMark(row, data, true)
	ShowAvatar(row, data, style, 5)
	local left, right = TextEnds(row, data, style)
	row.title:SetPoint("TOPLEFT", left, -5)
	row.title:SetPoint("TOPRIGHT", -right, -5)
	row.title:SetText(data.title)
	row.strip:Hide()

	-- The detail lines, under the title. In the feed each has its own count
	-- by the mark, when it has one; a dock drawer's run the title's width.
	local y = -style.titleHeight
	for index, lineData in ipairs(data.lines) do
		local line = AcquireLine(row, index)
		line.text:SetJustifyH(data.ends == "RIGHT" and "RIGHT" or "LEFT")
		line.text:ClearAllPoints()
		line.right:ClearAllPoints()
		local barLeft, barRight = left, right
		if data.ends then
			line.right:Hide()
			line.text:SetPoint("TOPLEFT", left, y)
			line.text:SetPoint("TOPRIGHT", -right, y)
		else
			line.right:SetPoint("TOPRIGHT", -MarkRoom(style), y)
			line.right:SetText(lineData.right or "")
			line.right:Show()
			-- Up to what is on its right: its own count, or the edge.
			local room = MarkRoom(style) + (lineData.right and RightRoom(line.right, lineData.right) or LINE_END_ROOM)
			line.text:SetPoint("TOPLEFT", left, y)
			line.text:SetPoint("TOPRIGHT", -room, y)
			barRight = MarkRoom(style)
		end
		line.text:SetText(lineData.text)
		line.text:Show()

		if lineData.progress then
			line.bar:ClearAllPoints()
			line.bar:SetPoint("TOPLEFT", barLeft, y - style.barOffset)
			line.bar:SetPoint("TOPRIGHT", -barRight, y - style.barOffset)
			line.bar:SetHeight(style.barHeight)
			SetProgress(line.bar, lineData.progress, QUEST_ROWS[data.kind])
			line.bar:Show()
			y = y - style.barLineHeight
		else
			line.bar:Hide()
			y = y - style.lineHeight
		end
	end
	HideLines(row, #data.lines + 1)
end

-- A quest card in one of its layouts (ui\\quest-card.lua): the title, the
-- avatar and the time as any detailed row, then the layout's body.
local function LayoutQuestCard(row, data, style, card)
	row.icon:SetPoint("TOPRIGHT", -MARK_EDGE, -6)
	row.right:SetPoint("TOPRIGHT", row.icon, "TOPLEFT", -8, 0)
	ShowAvatar(row, data, style, 5)
	local left = TextLeft(data, style)
	row.title:SetPoint("TOPLEFT", left, -5)
	row.title:SetPoint("TOPRIGHT", -(MarkRoom(style) + RightRoom(row.right, data.right)), -5)
	row.title:SetText(data.title)
	row.strip:Hide()
	HideLines(row, 1)
	card.Draw(row, data, {
		left = left,
		room = MarkRoom(style),
		top = -style.titleHeight,
		CreateBar = CreateBar,
		SetProgress = SetProgress,
	})
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
	badge.glow:SetShown(look.glow ~= nil and UseAtlas(badge.glow, look.glow))
	if look.glowColor then badge.glow:SetVertexColor(unpack(look.glowColor)) end
	badge.burst:SetSize(size * 1.5, size * 1.5)
	badge.burst:SetShown(look.burst ~= nil and UseAtlas(badge.burst, look.burst))
	if look.burstColor then badge.burst:SetVertexColor(unpack(look.burstColor)) end
	if not badge.burst:IsShown() then badge.spin:Stop() end
	badge.fill:ClearAllPoints()
	badge.fill:SetPoint("CENTER")
	badge.fill:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
	badge.fill:SetSize(size * 0.78, size * 0.78)
	badge.fill:SetVertexColor(unpack(look.fill))
	badge.ring:SetSize(size, size)
	badge.ring:SetShown(look.ring ~= nil and UseAtlas(badge.ring, look.ring))
	badge.text:SetFontObject(look.font[StyleName()] or look.font.detailed)
	badge.text:SetTextColor(unpack(look.textColor))
	badge.text:SetText(data.badge.text)
	row.icon:Hide()
	badge:Show()
	badge.turn:SetDuration(look.spinSeconds)
	if badge.burst:IsShown() and not badge.spin:IsPlaying() then
		badge.spin:Play()
	end
end

-- The row's mark (data\marks.lua): its art in the well, the well in the
-- mark's colors. A badge (a level's crest) takes its place. True when shown.
local function ShowMark(row, data, style)
	local look = not (data.badge and BADGES[data.badge.style]) and data.mark and ns.MarkLooks[data.mark]
	if not look then
		row.markArt:Hide()
		row.markText:Hide()
		return false
	end
	row.icon:Hide()
	ns.Look.DrawMark(row.markArt, row.markText, look, style.iconSize, data.markIcon)
	row.well:SetColorTexture(unpack(look.fill))
	row.wellEdge:SetColorTexture(unpack(look.edge))
	return true
end

local function InitRow(row, data)
	if not row.built then
		BuildRow(row)
	end
	local style = ROW_STYLES[StyleName()]

	local theme = ns.Theme()
	local background = (data.tint and theme[data.tint])
		or (data.highlight == "quest" and theme.handIn)
		or (data.highlight and theme.level)
		or theme[ROW_BACKGROUND[data.kind] or "row"]
	for _, edge in ipairs(row.edges) do
		edge:SetColorTexture(unpack(theme.rim))
	end
	row.well:SetColorTexture(unpack(theme.well))
	row.wellEdge:SetColorTexture(unpack(theme.wellEdge))
	row.divider:SetColorTexture(unpack(theme.divider))
	-- Lit from the left: a gradient across the row.
	row.background:SetColorTexture(1, 1, 1, 1)
	row.background:SetGradient("HORIZONTAL", CreateColor(unpack(background[1])), CreateColor(unpack(background[2])))
	row.icon:SetTexture(data.icon)
	row.icon:SetSize(style.iconSize, style.iconSize)
	row.icon:SetDesaturated(false)
	row.title:SetFontObject(style.titleFont)
	row.right:SetText(data.right or "")
	-- An objective's count stands out, as big as the title and gold (green
	-- when done); anything else on the right (a time) stays small and gray.
	if data.kind == "progress" then
		local done = data.progress and data.progress.have >= data.progress.need
		row.right:SetFontObject(style.titleFont)
		row.right:SetTextColor(unpack(done and COLORS.countDone or COLORS.count))
	else
		row.right:SetFontObject("GameFontDisableSmall")
		row.right:SetTextColor(unpack(COLORS.rightMuted)) -- a reused row may have held a count
	end

	row.icon:ClearAllPoints()
	row.right:ClearAllPoints()
	row.title:ClearAllPoints()
	local card = not style.height and ns.QuestCard:For(data) or nil
	ns.QuestCard:HideAll(row, card)
	if card then
		LayoutQuestCard(row, data, style, card)
	elseif style.height then
		LayoutOneLine(row, data, style)
	else
		LayoutDetailed(row, data, style)
	end

	row.quest = data.quest
	row.questID = data.questID
	row.playerName = data.name -- the tooltip's first line: who
	row.hover:Hide()
	row:EnableMouse(data.quest ~= nil or (data.kind == "feed" and data.stampKey ~= nil))
	row:SetAlpha(1)
	ShowBadge(row, data, style)
	-- The well frames the icon or the mark (in the mark's colors, with a
	-- bolder edge); a badge (a level's crest) has its own ring instead.
	local marked = ShowMark(row, data, style)
	-- A layout that shows progress in the mark's place (the Ring).
	if card and card.hidesMark then
		row.markArt:Hide()
		row.markText:Hide()
		marked = false
	end
	local hasIcon = row.icon:IsShown() or marked
	row.well:SetShown(hasIcon)
	row.wellEdge:SetShown(hasIcon)
	if hasIcon then
		local edge = marked and 2 or 1
		row.well:ClearAllPoints()
		row.well:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2, 2)
		row.well:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -2)
		row.wellEdge:ClearAllPoints()
		row.wellEdge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -2 - edge, 2 + edge)
		row.wellEdge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2 + edge, -2 - edge)
	end
	row.divider:Hide() -- no line between the avatar and the text
	PlayPulse(row, data.pulse)
	ShowBackdrop(row, data)
	-- The avatar's ring in the player's own color, as their head and XP bar
	-- (colors.lua); your game group's members in the party's color, with
	-- their stripe.
	if data.grouped then
		local r, g, b = PartyColor()
		row.groupEdge:SetColorTexture(r, g, b, 1)
		row.avatarRing:SetVertexColor(r, g, b, 1)
	elseif data.player then
		local r, g, b = ns.PlayerColors:For(data.player)
		row.avatarRing:SetVertexColor(r, g, b, 1)
	else
		row.avatarRing:SetVertexColor(0.80, 0.65, 0.20, 1)
	end
	row.groupEdge:SetShown(data.grouped == true)
	ns.StampView:Show(row, data)
	row.glow:SetShown(data.shared == true)
	if data.shared then
		local r, g, b = PartyColor()
		row.glow:SetBackdropBorderColor(r, g, b, COLORS.sharedGlow[4])
	end
	if data.shared then
		if not row.glow.breathe:IsPlaying() then row.glow.breathe:Play() end
	else
		row.glow.breathe:Stop()
	end
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

local ComposerShown -- below

-- The gap between the feed and the filter row, with its line across the
-- middle: tall enough, when KekChat's button sits on the line, for the
-- button to clear the filter icons under it.
local function RowGap()
	if ComposerShown() and ns.ChatView:Straddles() then
		return math.max(LAYOUT.gutterRowGap, ns.ChatView.height + 2 * LAYOUT.kekChatClear)
	end
	return LAYOUT.gutterRowGap
end

-- How much room the filter row takes above the list, when it shows.
local function GutterHeight()
	if not GutterShown() then
		return 0
	end
	return (GutterSizes()) + RowGap()
end

-- KekChat's bar (ui\chat.lua) shows under the list on the Feed tab.
function ComposerShown()
	local filter = ns.FilterById[ns.charDb.filter]
	return filter ~= nil and filter.composer == true and ns.ChatView:Frame() ~= nil
end

-- What sits under the list: the filter row, and the bar above it.
local function BelowList()
	return GutterHeight() + (ComposerShown() and ns.ChatView:Room() or 0)
end

-- Where the tabs and the list start.
local function ContentLeft()
	return LAYOUT.inset
end

local function StripHeight()
	if xpBarsShown == 0 then
		return 0
	end
	return xpBarsShown * BarStep() - LAYOUT.xpBarGap + LAYOUT.xpStripGap
end

-- The Quest tab has a short row of its own at the top of its list, with the
-- quest cards' layout gear (BuildFilter).
local function QuestBarHeight()
	return ns.charDb.filter == ns.QuestTab and LAYOUT.questBarHeight or 0
end

local function ListTop()
	return LAYOUT.headerHeight + StripHeight() + LAYOUT.filterHeight + 6 + QuestBarHeight()
end

local function ListHeight()
	local height = frame:GetHeight() or LAYOUT.height
	return height - ListTop() - LAYOUT.inset - BelowList()
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
local focusSequence -- a feed row to bring into view, from the dock

-- In chat order new rows and updated cards land at the bottom, so the list follows the bottom
-- unless the player has scrolled up to read. jumpToEnd forces it, for a fresh view.
function Panel:Refresh(jumpToEnd)
	if not frame or not frame:IsShown() then
		return
	end
	local filter = ns.FilterById[ns.charDb.filter] or ns.Filters[1]
	-- The 123 graphs (ui\report.lua) take the list's place on their tab.
	scrollBox:SetShown(not filter.report)
	scrollBar:SetShown(not filter.report)
	if filter.report then
		emptyText:Hide()
		ns.ReportView:Show(ListTop(), LAYOUT.inset)
		return
	end
	ns.ReportView:Hide()
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
	if focusSequence then
		for index, data in ipairs(rows) do
			if data.kind == "feed" and data.sequence == focusSequence then
				focusIndex = index
				data.pulse = "focus/" .. focusSequence .. "/" .. GetTime() -- always flash it
				break
			end
		end
		focusSequence = nil
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

-- ========= Feed rows elsewhere ==============================================
-- The feed's own rows, for other places that show feed entries (the dock,
-- ui\dock.lua): the same frame, drawing, stamps, tooltip and right-click.
-- style is "detailed" or "oneLine", whatever the feed's own view is.
function Panel:NewFeedRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	BuildRow(row)
	return row
end

function Panel:DrawFeedRow(row, data, style)
	styleOverride = style
	InitRow(row, data)
	styleOverride = nil
end

-- How much of a dock drawer rests in the housing, in a style: its mark and
-- half its avatar, beside it (data.ends: TextEnds).
function Panel:DockRest(style)
	local look = ROW_STYLES[style]
	return MarkRoom(look) + AvatarWidth(look) / 2
end

-- How tall a feed row is in a style: one with a bar on its second line, the
-- tallest a plain feed row gets.
function Panel:FeedRowHeight(style)
	styleOverride = style
	local height = RowHeight({ kind = "feed", lines = { { progress = true } } })
	styleOverride = nil
	return height
end

-- Opens the feed (All) and brings one row into view with a flash: the one a
-- dock drawer stood for.
function Panel:FocusEntry(sequence)
	focusSequence = sequence
	self:SelectFilter(ns.Filters[1].id)
end

-- Jumps to the Quests filter and brings one quest into view with a flash.
function Panel:FocusQuest(quest)
	focusQuest = quest
	self:SelectFilter(ns.QuestTab)
end

local function FilterLabel(filter, compact)
	return compact and filter.shortLabel or filter.label
end

local function UpdateGutter()
	if not gutter then
		return
	end
	for _, button in ipairs(gutter.buttons) do
		local hidden = ns.charDb.hidden[button.filter.id] == true
		local look = button.look
		button.icon:SetDesaturated(hidden or (look and look.desaturate) == true)
		button.icon:SetAlpha(hidden and LAYOUT.gutterOffAlpha or 1)
		button.markText:SetAlpha(hidden and LAYOUT.gutterOffAlpha or 1)
		button:SetBackdropBorderColor(unpack(hidden and COLORS.gutterOff or (look and look.edge) or COLORS.border))
		if look then button:SetBackdropColor(unpack(look.fill)) end
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
	-- The Quest tab's own row, with the layout gear: on that tab only.
	local questBar = filterBar and filterBar.questBar
	if questBar then
		questBar:SetShown(ns.charDb.filter == ns.QuestTab)
		local step = ns.QuestCardStyles[math.floor(ns.GetSlider("questCardStyle") or 0)]
		questBar.label:SetText(step and step.label or "")
	end
end

local function LayoutFilter()
	UpdateFilter()
end

local UpdateConnectionOptions -- below: the recent channels' buttons call it

-- The recent channels' buttons, in a row after their label, as many as fit.
local function UpdateRecentChannels(controls)
	local list = ns.Session:RecentChannels()
	-- Never an empty band: with none to offer, it says so.
	controls.recentLabel:SetText(#list > 0 and L.CHANNEL_RECENT or L.CHANNEL_RECENT_NONE)
	local x = (controls.recentLabel:GetStringWidth() or 40) + 12
	local room = (controls.content:GetWidth() or 300) - 8
	for index = 1, math.max(#list, #controls.recent) do
		local button = controls.recent[index]
		if not button and list[index] then
			button = CreateFrame("Button", nil, controls.content, "UIPanelButtonTemplate")
			button:SetHeight(SETTINGS.recentHeight - 4)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button:SetScript("OnClick", function(self, mouse)
				if mouse == "RightButton" then
					ns.Session:Forget(self.channel)
					return
				end
				local ok, problem = ns.Session:SwitchTo(self.channel)
				UpdateConnectionOptions(true)
				if not ok then
					controls.status:SetText(problem)
					controls.status:SetTextColor(1, 0.4, 0.4)
				end
			end)
			button:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(L.CHANNEL_RECENT_TIP:format(self.channel))
				GameTooltip:AddLine(L.CHANNEL_RECENT_FORGET, 0.8, 0.8, 0.8)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", function() GameTooltip:Hide() end)
			controls.recent[index] = button
		end
		local name = list[index]
		if button then
			button.channel = name
			if name then
				button:SetText(name)
				local width = button:GetFontString():GetStringWidth() + 20
				button:SetWidth(width)
				button:ClearAllPoints()
				button:SetPoint("LEFT", controls.recentLabel, "LEFT", x - 6, 0)
				button:SetShown(x + width <= room)
				x = x + width + 4
			else
				button:Hide()
			end
		end
	end
end

function UpdateConnectionOptions(resetName)
	if not optionsView or not optionsView.connection then return end
	local controls = optionsView.connection
	local session, config = ns.Session, ns.db.connection
	if resetName then controls.name:SetText(config.name) end
	UpdateRecentChannels(controls)
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
	ns.charDb.filter = id
	UpdateFilter()
	if PlaceUnderStrip and filterBar then
		PlaceUnderStrip() -- the filter row shows on feed tabs only
	end
	self:ShowOptions(false)
	self:Refresh(true)
end

-- The view icon mirrors the current state: three bars for compact (one-line)
-- rows, more of them; two (top and bottom) for detailed (two-line) rows.
-- Never one: that reads as minimize.
local function UpdateViewButton()
	for index, bar in ipairs(viewButton.bars) do
		bar:SetShown(ns.charDb.oneLine or HEADER_BUTTON.detailedBars[index] == true)
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

-- /qp reset: the panel back to its first size and place, shown and not
-- docked, and the dock back to its screen edge. For a panel lost off screen.
function Panel:ResetPosition()
	ns.charDb.position, ns.charDb.size, ns.charDb.dockPoint = nil, nil, nil
	if not frame then return end
	if ns.charDb.docked then
		ns.charDb.docked = false
		ns.Dock:Hide()
	end
	frame:SetSize(LAYOUT.width, LAYOUT.height)
	RestorePosition()
	ns.charDb.shown = true
	frame:SetAlpha(ns.Opacity.Now(false)) -- the Opacity slider's, not fully solid (opacity.lua)
	frame:SetScale(1)
	frame:Show()
	self:Refresh()
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
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	title:SetText(L.TITLE)
	panelTitle = title

	-- Right to left: close (always the far right), minimize, options, view,
	-- sounds, opacity.
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -(LAYOUT.inset - 2), -(HEADER_BUTTON.top - 2))
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	-- Minimize to the dock (ui\dock.lua): a bar, as a window's minimize has.
	local minimize = CreateHeaderButton(function()
		return L.DOCK_MINIMIZE, L.DOCK_MINIMIZE_TIP
	end, function()
		Panel:Minimize()
	end)
	minimize:SetPoint("RIGHT", close, "LEFT", -HEADER_BUTTON.gap, 0)
	local dash = minimize:CreateTexture(nil, "ARTWORK")
	dash:SetSize(HEADER_BUTTON.barWidth, HEADER_BUTTON.barHeight)
	dash:SetPoint("CENTER", 0, -4)
	dash:SetColorTexture(unpack(HEADER_BUTTON.glyph))

	-- Opens the options. It stays lit while they are open.
	optionsButton = CreateHeaderButton(function()
		return L.OPTIONS
	end, function()
		Panel:ShowOptions(not optionsView:IsShown())
	end)
	optionsButton:SetPoint("RIGHT", minimize, "LEFT", -HEADER_BUTTON.gap, 0)
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

	-- Sounds on and off (the Sounds switch in Settings): a speaker.
	-- Steps the volume down: loud, regular, soft, mute, then loud again.
	soundButton = CreateHeaderButton(function()
		local level = ns.VolumeLevels[ns.GetSlider("volume") or 2]
		return L.SOUNDS_LEVEL:format(level and level.label or ""), L.SOUNDS_TIP
	end, function()
		local value = ns.GetSlider("volume") or 2
		ns.SetSlider("volume", value == 0 and 3 or value - 1)
	end)
	soundButton:SetPoint("RIGHT", viewButton, "LEFT", -HEADER_BUTTON.gap, 0)

	-- Opacity (opacity.lua): opens a short upright slider under it to set it
	-- live (ui\opacity-slider.lua); the mouse wheel steps it. Its icon: a
	-- square half solid, half faded.
	local opacityButton = CreateHeaderButton(function()
		return L.OPACITY_BUTTON:format(ns.GetSlider("opacity") or 100), L.OPACITY_BUTTON_TIP
	end, function(self)
		ns.OpacitySlider:Toggle(self)
	end)
	opacityButton:SetPoint("RIGHT", soundButton, "LEFT", -HEADER_BUTTON.gap, 0)
	opacityButton:EnableMouseWheel(true)
	opacityButton:SetScript("OnMouseWheel", function(_, delta) ns.OpacitySlider:Nudge(delta) end)
	for index, alpha in ipairs({ 1, 0.35 }) do
		local half = opacityButton:CreateTexture(nil, "ARTWORK")
		half:SetSize(HEADER_BUTTON.opacityGlyph / 2, HEADER_BUTTON.opacityGlyph)
		half:SetPoint("CENTER", (index == 1 and -1 or 1) * HEADER_BUTTON.opacityGlyph / 4, 0)
		local r, g, b = unpack(HEADER_BUTTON.glyph)
		half:SetColorTexture(r, g, b, alpha)
	end

	-- The title runs under the buttons, which sit over it (FitTitle).
	title:SetPoint("RIGHT", frame, "RIGHT", -LAYOUT.inset, 0)
	title.buttons = opacityButton -- the leftmost button: where the name must end
	soundButton.icon = soundButton:CreateTexture(nil, "ARTWORK")
	soundButton.icon:SetPoint("TOPLEFT", 1, -3)
	soundButton.icon:SetPoint("BOTTOMRIGHT", soundButton, "BOTTOMLEFT", 11, 3)
	-- The level: three rising bars at the right, lit by UpdateSoundButton.
	soundButton.levels = {}
	for index, height in ipairs(VOLUME_BARS.heights) do
		local bar = soundButton:CreateTexture(nil, "ARTWORK")
		bar:SetSize(VOLUME_BARS.width, height)
		bar:SetPoint("BOTTOMLEFT", soundButton, "BOTTOMLEFT", 12 + (index - 1) * (VOLUME_BARS.width + VOLUME_BARS.gap), 5)
		soundButton.levels[index] = bar
	end
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
	gutter:SetClipsChildren(true) -- icons past the left edge are cut off; widen the panel to see them
	local back = gutter:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(unpack(ns.Theme().row[2])) -- the rows' dark end
	-- The line between the feed and the filter row (PlaceUnderStrip).
	gutterLine = frame:CreateTexture(nil, "ARTWORK")
	gutterLine:SetHeight(1)
	gutterLine:SetColorTexture(unpack(LAYOUT.gutterRule))
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
		-- The same marks as the rows (data\\marks.lua), drawn in LayoutGutter.
		button.look = filter.mark and ns.MarkLooks[filter.mark]
		button.markText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.markText:SetPoint("CENTER", 1, 0)
		button.markText:Hide()
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

-- Sizes the filter row and its icons to the slider's scale, right aligned
-- under KekChat's button (ui\chat.lua): on a narrow panel the first ones
-- are cut off at the left.
local function LayoutGutter()
	local icon, gap = GutterSizes()
	gutter:SetHeight(icon)
	local count = #gutter.buttons
	for index, button in ipairs(gutter.buttons) do
		button:SetSize(icon, icon)
		button:ClearAllPoints()
		button:SetPoint("RIGHT", -(count - index) * (icon + gap), 0)
		if button.look then
			button.icon:ClearAllPoints()
			button.icon:SetPoint("CENTER")
			ns.Look.DrawMark(button.icon, button.markText, button.look, icon - 2 * LAYOUT.gutterIconInset)
		end
	end
	UpdateGutter() -- a hidden filter stays grayed after drawing
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
	-- The Quest tab's own short row, at the top of its list: a small gear
	-- on the right cycles the quest cards' layout (ui\\quest-card.lua):
	-- Segmented, Grid, Ring, List, its name beside it.
	local questBar = CreateFrame("Frame", nil, frame)
	questBar:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -4)
	questBar:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", -(LAYOUT.scrollBarWidth + 4), -4)
	questBar:SetHeight(LAYOUT.questBarHeight - 4)
	local cycle = CreateFrame("Button", nil, questBar)
	cycle:SetPoint("RIGHT", -4, 0)
	cycle:SetSize(LAYOUT.cycleSize, LAYOUT.cycleSize)
	cycle.icon = cycle:CreateTexture(nil, "ARTWORK")
	cycle.icon:SetAllPoints()
	cycle.icon:SetTexture(HEADER_BUTTON.optionsIcon)
	cycle.icon:SetDesaturated(true)
	cycle.icon:SetVertexColor(unpack(HEADER_BUTTON.glyph)) -- gold, as the title bar's gear
	cycle:SetHighlightTexture(HEADER_BUTTON.optionsIcon, "ADD")
	local function CycleTip(self)
		local step = ns.QuestCardStyles[math.floor(ns.GetSlider("questCardStyle") or 0)]
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.QUEST_CARD_CYCLE:format(step and step.label or ""))
		GameTooltip:AddLine(L.QUEST_CARD_CYCLE_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end
	cycle:SetScript("OnClick", function(self)
		local count = #ns.QuestCardStyles + 1 -- steps from 0
		ns.SetSlider("questCardStyle", ((ns.GetSlider("questCardStyle") or 0) + 1) % count)
		CycleTip(self)
	end)
	cycle:SetScript("OnEnter", CycleTip)
	cycle:SetScript("OnLeave", function() GameTooltip:Hide() end)
	questBar.label = questBar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	questBar.label:SetPoint("RIGHT", cycle, "LEFT", -4, 0)
	questBar.cycle = cycle
	filterBar.questBar = questBar
	filterBar:SetScript("OnSizeChanged", LayoutFilter)
	LayoutFilter()
end

-- ========= The party's XP bars ==============================================
-- A player's bar is their own color (colors.lua), as their portrait's ring.
local function BarColor(name)
	return { ns.PlayerColors:For(name) }
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
	if data.afk then
		local away = data.afkSince and GetServerTime() - data.afkSince or 0
		GameTooltip:AddLine(away >= 60 and L.XPBAR_TIP_AFK_FOR:format(ns.Ago(away)) or L.XPBAR_TIP_AFK, 1, 0.69, 0)
	end
	if data.lastXP then
		local gain = L.XP_GAIN:format(ns.Comma(data.lastXP))
		local line = (data.lastMob and data.lastMob ~= "") and L.XPBAR_TIP_GAIN_FROM:format(gain, data.lastMob) or L.XPBAR_TIP_GAIN:format(gain)
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8)
	end
	if data.health then
		local powerName = ((data.powerType or "MANA"):lower():gsub("_", " "))
		GameTooltip:AddLine(L.XPBAR_TIP_VITALS:format(data.health, powerName, data.power or 0), 0.8, 0.8, 0.8)
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

-- From one party bar to the next: the XP bar and the gap. (Health and power
-- are beside the heads and on the player card, ui\\party.lua.)
BarStep = function()
	return LAYOUT.xpBarHeight + LAYOUT.xpBarGap
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
	-- The filter row sits along the bottom, clear of the resize grip, under
	-- a line between it and the feed. KekChat's button (ui\chat.lua) sits on
	-- that line at the right end, half above and half below, clear of the
	-- filter icons (RowGap); both are right aligned.
	local gripRoom = LAYOUT.gripSize + 2
	local composer = ns.ChatView:Frame()
	local shown = ComposerShown()
	local straddles = shown and ns.ChatView:Straddles()
	gutter:ClearAllPoints()
	gutter:SetPoint("BOTTOMLEFT", LAYOUT.inset, LAYOUT.inset)
	gutter:SetPoint("BOTTOMRIGHT", -(LAYOUT.inset + gripRoom), LAYOUT.inset)
	gutter:SetShown(GutterShown())
	local lineY = LAYOUT.inset + GutterHeight() - math.floor(RowGap() / 2)
	gutterLine:ClearAllPoints()
	gutterLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LAYOUT.inset, lineY)
	gutterLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -LAYOUT.inset, lineY)
	gutterLine:SetShown(GutterShown())
	if composer then
		-- Centred on the line, or standing on it in a row of its own.
		local bottom = straddles and lineY - math.floor(ns.ChatView.height / 2) or lineY + 2
		composer:ClearAllPoints()
		composer:SetPoint("BOTTOMLEFT", LAYOUT.inset, bottom)
		composer:SetPoint("BOTTOMRIGHT", -LAYOUT.inset, bottom)
		ns.ChatView:SetRightInset(gripRoom) -- KekChat's right end over the filter row's
		ns.ChatView:SetShown(shown)
	end
	if scrollBox then
		PlaceList()
	end
end

-- KekChat's bar was built (ui\chat.lua): put it in its place.
function Panel:PlaceComposer()
	if PlaceUnderStrip and filterBar then
		PlaceUnderStrip()
		self:Refresh()
	end
end

-- Draws one bar per other player in the party, and moves everything under
-- them when how many there are changes.
function Panel:UpdateXpBars()
	if not xpStrip then
		return
	end
	local data = ns.ViewModel:PartyBars()
	local shown = #data -- already capped (ViewModel.PartyCap)
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
		-- Away: an AFK tag after the name and a dimmer bar. (Gone has no bar.)
		bar.name:SetText(entry.afk and (entry.name .. " " .. L.XPBAR_AFK) or entry.name)
		bar:SetAlpha(entry.afk and LAYOUT.afkBarAlpha or 1)
		bar.level:SetText(entry.levelText)
		bar.text:SetText(entry.text)
		-- Health and power, when known (a friend on an older version sends none).
		-- A member of your game group: the bar's frame in the party's color.
		if entry.grouped then
			bar:SetBackdropBorderColor(PartyColor())
		else
			bar:SetBackdropBorderColor(unpack(COLORS.xpBarBorder))
		end
		bar:ClearAllPoints()
		local top = (index - 1) * BarStep()
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
	scrollBox:SetPoint("BOTTOMRIGHT", -(LAYOUT.inset + LAYOUT.scrollBarWidth + 4), LAYOUT.inset + BelowList())
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
	optionsView:SetBackdropColor(unpack(ns.Theme().panel))
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
	-- Recent channels: one click switches to one, right-click forgets it.
	local recentLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	recentLabel:SetPoint("TOPLEFT", 6, -(y + 50))
	recentLabel:SetText(L.CHANNEL_RECENT)
	optionsView.connection = { name = name, join = join, disconnect = disconnect, status = status,
		recentLabel = recentLabel, recent = {}, content = content }
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
	return y + 50 + SETTINGS.recentHeight
end

-- One slider: its label, the bar, and its value beside it.
local function BuildSlider(content, _width, slider, y)
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

-- KekChat: a word on keeping it clean, your saved messages' editor
-- (ui\kek-editor.lua, where the blocked list is too), and how to block.
local function SettingsNote(content, text, y, width)
	local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", 4, -y)
	note:SetWidth(width - 8)
	note:SetJustifyH("LEFT")
	note:SetWordWrap(true)
	note:SetText(text)
	return y + math.ceil(note:GetStringHeight() or 14) + 8
end

local function KekChatLead(content, width, y)
	y = SettingsNote(content, L.KEK_CLEAN_NOTE, y, width)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	button:SetSize(SETTINGS.kekButtonWidth, 22)
	button:SetPoint("TOPLEFT", 4, -y)
	button:SetText(L.KEK_EDIT)
	button:SetScript("OnClick", function() ns.KekEditor:Toggle() end)
	SettingsTip(button, L.KEK_EDIT, L.KEK_EDIT_TIP)
	y = y + 30
	return SettingsNote(content, L.KEK_BLOCK_HOW, y, width)
end

-- What a section draws under its heading before its switches (its lead in
-- data\settings.lua, SettingGroups).
local SettingsLeads = { kekchat = KekChatLead }

-- A group's switches, in two columns, then its sliders.
local function BuildSwitches(content, width, group, y)
	y = SettingsHeading(content, group.label, y)
	local lead = group.lead and SettingsLeads[group.lead]
	if lead then y = lead(content, width, y) end
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

-- Test runs, in debug mode only: a scenario to choose (dev\scenarios.lua),
-- Clear on go (the pretend players only), and GO and STOP.
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
	-- Never taller than the screen, so an edge is always in reach.
	local maxHeight = math.min(LAYOUT.maxHeight, math.floor(UIParent:GetHeight() or LAYOUT.maxHeight))
	frame:SetResizeBounds(LAYOUT.minWidth, LAYOUT.minHeight, LAYOUT.maxWidth, math.max(LAYOUT.minHeight, maxHeight))

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(LAYOUT.gripSize, LAYOUT.gripSize)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	-- While dragging, the rows stretch with the window by their anchors, so
	-- nothing is rebuilt each frame (that was the hitching); one redraw at the
	-- end lays everything out for the new size.
	grip:SetScript("OnMouseDown", function()
		Panel.sizing = true
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		Panel.sizing = false
		SaveSize()
		SavePosition() -- sizing re-anchors the window
		Panel:Refresh()
	end)

	-- Every edge can be dragged too, not only the corner: a strip along each,
	-- so a window grown past the screen can still be brought back.
	for _, edge in ipairs({
		{ "TOP", "TOPLEFT", "TOPRIGHT", true }, { "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "LEFT", "TOPLEFT", "BOTTOMLEFT" }, { "RIGHT", "TOPRIGHT", "BOTTOMRIGHT" },
	}) do
		local strip = CreateFrame("Frame", nil, frame)
		strip:SetPoint(edge[2])
		strip:SetPoint(edge[3])
		if edge[4] then strip:SetHeight(LAYOUT.edgeGrab) else strip:SetWidth(LAYOUT.edgeGrab) end
		strip:SetFrameLevel(frame:GetFrameLevel() + 20)
		strip:EnableMouse(true)
		strip:SetScript("OnMouseDown", function()
			Panel.sizing = true
			frame:StartSizing(edge[1])
		end)
		strip:SetScript("OnMouseUp", function()
			frame:StopMovingOrSizing()
			Panel.sizing = false
			SaveSize()
			SavePosition()
			Panel:Refresh()
		end)
	end

	frame:SetScript("OnSizeChanged", function()
		emptyText:SetWidth(frame:GetWidth() - 40)
		FitTitle()
		if not Panel.sizing then
			Panel:Refresh()
		end
	end)
end

local function Build()
	frame = CreateFrame("Frame", ns.Globals.frame("Panel"), UIParent, "BackdropTemplate")
	-- A saved size taller than this screen is cut to fit it.
	local size = ns.charDb.size
	local screen = math.floor(UIParent:GetHeight() or 0)
	local height = size and size.height or LAYOUT.height
	if screen > 0 then height = math.min(height, screen) end
	frame:SetSize(size and size.width or LAYOUT.width, height)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(unpack(ns.Theme().panel))
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
	C_Timer.After(0, FitTitle) -- once laid out, the title fits its room

	-- Remember visibility, and keep the relative times fresh while visible.
	frame:SetScript("OnShow", function()
		ns.charDb.shown = true
		Panel:Refresh(true)
	end)
	frame:SetScript("OnHide", function()
		if ns.StampView then ns.StampView:Close() end -- the stamp picker goes with it
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

-- Opens the panel on its Settings, wherever it was (docked, hidden): from the
-- game's own Options (ui\game-options.lua).
function Panel:OpenSettings()
	if not frame then return end
	if ns.charDb.docked then
		self:Restore()
	end
	frame:Show()
	self:ShowOptions(true)
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


-- Your own XP bar follows the game's.
local xpEvents = CreateFrame("Frame")
xpEvents:RegisterEvent("PLAYER_XP_UPDATE")
xpEvents:RegisterEvent("PLAYER_LEVEL_UP")
xpEvents:SetScript("OnEvent", function()
	if frame then Panel:UpdateXpBars() end
end)

-- Your game group changed: mark its members afresh.
Bus:On("GROUP_CHANGED", function()
	if frame then
		Panel:UpdateXpBars()
		Panel:Refresh()
	end
end)

-- You went away or came back (collectors\afk.lua): your bar's AFK tag.
Bus:On("AFK_CHANGED", function()
	if frame then Panel:UpdateXpBars() end
end)

Bus:On("PEERS_CHANGED", function()
	if frame then
		UpdateFilter()
		Panel:UpdateXpBars()
	ns.Confetti:SetHost(frame)
	end
end)

Bus:On("DEV_STATE", function()
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
	FitTitle() -- the channel's name after the title
end)

Bus:On("SETTING_CHANGED", function(id)
	if id == "titleChannel" then FitTitle() end
end)

-- The Filter icon size slider: resize the filter row and move the list.
Bus:On("SLIDER_CHANGED", function(id)
	if id == "gutterScale" and gutter then
		LayoutGutter()
		PlaceUnderStrip()
		Panel:Refresh()
	end
end)

-- The Players shown slider: the bars and the side bar, to the new cap.
Bus:On("SLIDER_CHANGED", function(id)
	if id == "partyCap" and frame then
		xpBarsShown = -1
		Panel:UpdateXpBars()
		if ns.Party then ns.Party:Redraw() end
	end
end)

-- The Quest cards slider: the quest cards in their new layout.
Bus:On("SLIDER_CHANGED", function(id)
	if id == "questCardStyle" and frame then
		UpdateFilter() -- the Quest tab's row names the new layout
		Panel:Refresh()
	end
end)

-- The Health and power switch changes the strip's spacing: lay it out again.
Bus:On("SETTING_CHANGED", function(id)
	if id == "showVitals" and frame then
		xpBarsShown = -1
		Panel:UpdateXpBars()
	end
end)

-- The Theme slider: the panel and every row in the new palette, at once.
Bus:On("SLIDER_CHANGED", function(id)
	if id ~= "theme" or not frame then return end
	frame:SetBackdropColor(unpack(ns.Theme().panel))
	if optionsView then optionsView:SetBackdropColor(unpack(ns.Theme().panel)) end
	Panel:Refresh()
end)

Bus:On("SLIDER_CHANGED", function(id)
	if id == "volume" then
		UpdateSoundButton()
	end
end)

-- A channel remembered or forgotten (comms\session.lua): Settings' recent row.
Bus:On("RECENT_CHANNELS_CHANGED", function()
	if optionsView and optionsView.connection then UpdateRecentChannels(optionsView.connection) end
end)
