-- Party: a head for each player in the party, down the right edge of the
-- panel, and the card a head opens: Overview, Quests and Items tabs. It draws
-- what ui\party-model.lua gives it, and owns nothing but frames.
-- Kept simple on purpose: plain buttons and text, to grow as we learn what
-- we want from it.
local _, ns = ...
local Bus = ns.Bus
local L = ns.L

local Party = { selected = nil, tab = "equipped", offset = 0 }
ns.Party = Party

local LAYOUT = {
	-- Heads are circles that overlap a little, as big as fits: headMax with a
	-- small party, shrinking to headMin as it grows, then scrolling.
	headMax = 46,
	headMin = 26,
	headOverlap = 0.15, -- of a head's size, under the next one
	headTop = 2, -- the first head's top, from the drawer's top
	ring = 2, -- the ring around a head, in its class color
	ringSelected = 3,
	drawerPad = 5, -- inside the drawer, around the heads
	-- The heads sit behind the panel's right edge: this much of a head shows,
	-- more when hovered, most when selected. The drawer is only as wide as
	-- the selected head needs.
	peek = 0.5,
	peekHover = 0.6,
	peekSelected = 0.75,
	slideSeconds = 0.06,
	-- The panel, drawer and card are one group on the panel's layer. Front to
	-- back: the panel, the heads, the card (and everything in it), the drawer.
	-- They sit in the raiseRoom frame levels under the panel's, so a head that
	-- slides out passes over the card's edge and under the panel's.
	raiseRoom = 60,
	headLevel = 10, -- above the card's own frames
	headOrders = 40, -- heads past this share a level
	headSelected = 45, -- the selected head, in front of the others
	dockOverlap = 3, -- the drawer and card tuck under each other's edges, so all read as one
	-- The card: docked to the top of the drawer and only as tall as its slots
	-- need, so the panel can grow with the feed while the card stays small.
	cardWidth = 300,
	cardPad = 8,
	portraitSize = 54,
	portraitRing = 3,
	classIconSize = 14,
	crestSize = 56,
	crestRight = 26, -- clear of the close button
	headerHeight = 70, -- the portrait and its padding
	tabHeight = 22,
	tabGap = 4,
	areaPad = 5,
	slotSize = 30,
	slotGap = 3,
	slotRows = 9, -- the longest column, and the weapons under it
	figureSize = 110,
	questRowPad = 5, -- inside a quest row
	questRowGap = 3, -- between quest rows
	infoLine = 16, -- a label and value line on the Info tab
	infoHeading = 20, -- a section's title
	infoGap = 8, -- before each section after the first
	scrollBarWidth = 16,
	redrawSeconds = 0.2, -- many messages, one redraw
}

local COLORS = {
	back = { 0.05, 0.04, 0.08, 0.92 }, -- as the panel
	border = { 0.80, 0.65, 0.20, 1 },
	ringGone = { 0.45, 0.45, 0.45, 1 }, -- someone who left or went quiet
	selected = { 1, 0.85, 0.35, 1 },
	drawer = { 0.05, 0.04, 0.08, 0.92 }, -- as the panel
	tab = { 0.08, 0.07, 0.10, 1 },
	tabSelected = { 0.62, 0.48, 0.12, 1 },
	tabText = { 1, 1, 1, 1 },
	tabTextSelected = { 1, 0.85, 0.35, 1 },
	xp = { 0.58, 0.36, 0.86, 1 },
	slotBack = { 0, 0, 0, 0.75 },
	slotEdge = { 0.55, 0.45, 0.18, 1 },
	area = { 0.02, 0.02, 0.03, 0.9 },
	stage = { 0, 0, 0, 0.6 },
	figureAlpha = 0.15, -- the portrait behind the item details, standing in for a model
	crestAlpha = 0.18,
	questRow = { 1, 1, 1, 0.05 },
	questRowShared = { 0.70, 0.52, 0.12, 0.22 }, -- on your log too
	questTitle = { 1, 0.82, 0 },
	mine = { 0.45, 0.85, 0.45 },
	infoLabel = { 0.75, 0.75, 0.75 },
	muted = { 0.75, 0.75, 0.75 },
}

local TABS = {
	{ id = "equipped", label = L.CARD_EQUIPPED },
	{ id = "quests", label = L.CARD_QUESTS },
	{ id = "info", label = L.CARD_INFO },
}

local CRESTS = {
	Alliance = "Interface\\Timer\\Alliance-Logo",
	Horde = "Interface\\Timer\\Horde-Logo",
}

local SLOT_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14, -- as the panel's, so the three read as one
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local host, strip, card

-- Shows or hides the head drawer, once per change: DRAWER_CHANGED says so,
-- for what docks beside it (a popped-out chat). Never showing it and hiding
-- it again in one redraw, which would make those listeners churn.
local function SetDrawerShown(shown)
	if strip:IsShown() == shown then
		return
	end
	strip:SetShown(shown)
	Bus:Fire("DRAWER_CHANGED", shown)
end
local LayoutArea -- defined with the card's area
local ListWidth -- defined with the card's lists
local heads = {}

local function ClassColor(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return unpack(COLORS.border)
end

-- A portrait: the game's race art when it has it, or the class icon.
local SetPortrait = ns.Look.SetPortrait -- shared with KekChat (ui\look.lua)

local function StatusLine(data)
	if data.here then
		return L.CARD_ONLINE
	end
	return L.CARD_AS_OF:format(ns.Ago(data.seenAgo or 0))
end

-- ========= Heads ============================================================
local function ShowHeadTip(button)
	local data = button.data
	if not data then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.ColorName(data.name, data.class))
	if data.level then
		GameTooltip:AddLine(L.CARD_LEVEL_CLASS:format(data.level, data.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or ""), 1, 1, 1)
	end
	if data.zone then
		GameTooltip:AddLine(data.zone, unpack(COLORS.muted))
	end
	GameTooltip:AddLine(StatusLine(data), unpack(COLORS.muted))
	GameTooltip:Show()
end

local Round = ns.Look.Round

-- Moves a head toward where it should be (see Slide), a little each frame.
local function SlideStep(button, elapsed)
	local step = math.min(1, elapsed / LAYOUT.slideSeconds)
	button.x = button.x + (button.targetX - button.x) * step
	if math.abs(button.targetX - button.x) < 0.5 then
		button.x = button.targetX
		button:SetScript("OnUpdate", nil)
	end
	button:SetPoint("TOPLEFT", host, "TOPRIGHT", button.x, -button.top)
end

-- How much of a head shows past the panel's edge, as an offset from it.
local function HeadX(button)
	local peek = LAYOUT.peek
	if button.data and button.data.name == Party.selected then
		peek = LAYOUT.peekSelected
	elseif button.hovered then
		peek = LAYOUT.peekHover
	end
	return -math.floor(button.size * (1 - peek) + 0.5)
end

-- Slides a head to its place; jump puts it there at once (a new layout).
local function Slide(button, jump)
	button.targetX = HeadX(button)
	if jump or not button.x then
		button.x = button.targetX
	end
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", host, "TOPRIGHT", button.x, -button.top)
	button:SetScript("OnUpdate", button.x ~= button.targetX and SlideStep or nil)
end

local function CreateHead()
	local button = CreateFrame("Button", nil, strip)
	button.ring = button:CreateTexture(nil, "BACKGROUND")
	button.ring:SetAllPoints()
	button.ring:SetTexture("Interface\\Buttons\\WHITE8x8")
	Round(button.ring, button)
	button.portrait = button:CreateTexture(nil, "ARTWORK")
	Round(button.portrait, button)
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function(self)
		if self.data then
			Party:Open(self.data.name)
		end
	end)
	button:SetScript("OnEnter", function(self)
		self.hovered = true
		Slide(self)
		ShowHeadTip(self)
	end)
	button:SetScript("OnLeave", function(self)
		self.hovered = false
		Slide(self)
		GameTooltip:Hide()
	end)
	return button
end

-- How big each head is, the step from one head to the next (they overlap),
-- and how many fit beside the panel, for count players.
local function Fit(count)
	local height = math.max(0, (host:GetHeight() or 0) - LAYOUT.headTop - LAYOUT.drawerPad)
	local share = 1 - LAYOUT.headOverlap
	local size = math.floor(height / (1 + math.max(0, count - 1) * share))
	size = math.max(LAYOUT.headMin, math.min(LAYOUT.headMax, size))
	local step = math.floor(size * share + 0.5)
	return size, step, math.max(1, math.floor((height - size) / step) + 1)
end

local function DrawHead(button, data, size, top)
	local moved = button.data ~= data and (not button.data or button.data.name ~= data.name) or button.size ~= size or button.top ~= top
	button.data, button.size, button.top = data, size, top
	button:SetSize(size, size)
	-- Above the card; each head over the one before, the selected one in front.
	local order = data.name == Party.selected and LAYOUT.headSelected or math.min(button.order, LAYOUT.headOrders)
	button:SetFrameLevel(strip:GetFrameLevel() + LAYOUT.headLevel + order)
	Slide(button, moved)
	local ring = data.name == Party.selected and LAYOUT.ringSelected or LAYOUT.ring
	button.portrait:ClearAllPoints()
	button.portrait:SetPoint("TOPLEFT", ring, -ring)
	button.portrait:SetPoint("BOTTOMRIGHT", -ring, ring)
	SetPortrait(button.portrait, data)
	-- In color only when selected.
	button.portrait:SetDesaturated(data.name ~= Party.selected)
	if data.name == Party.selected then
		button.ring:SetVertexColor(unpack(COLORS.selected))
	elseif not data.here then
		button.ring:SetVertexColor(unpack(COLORS.ringGone))
	else
		button.ring:SetVertexColor(ClassColor(data.class))
	end
	button:Show()
end

local function DrawHeads(list)
	local size, step, fits = Fit(#list)
	Party.offset = math.max(0, math.min(Party.offset, #list - fits))
	local shown = 0
	for index = Party.offset + 1, math.min(#list, Party.offset + fits) do
		shown = shown + 1
		local button = heads[shown] or CreateHead()
		heads[shown] = button
		button.order = shown
		DrawHead(button, list[index], size, LAYOUT.headTop + (shown - 1) * step)
	end
	-- The drawer is only as tall as its heads, and not there with none.
	SetDrawerShown(shown > 0)
	if shown > 0 then
		strip:SetHeight(LAYOUT.headTop + size + (shown - 1) * step + LAYOUT.drawerPad)
	end
	for index = shown + 1, #heads do
		heads[index]:Hide()
		heads[index].data = nil
	end
end

-- ========= The card =========================================================
-- A header (portrait, name, level and class, where they are, their XP), two
-- tabs, and what the chosen tab shows: their gear laid out as on the game's
-- character window, or their quests. The middle of the gear tab is kept for
-- a model of the player, later.
local function CreateTab(index, tab)
	local button = CreateFrame("Button", nil, card)
	button:SetHeight(LAYOUT.tabHeight)
	button.back = button:CreateTexture(nil, "BACKGROUND")
	button.back:SetAllPoints()
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.text:SetPoint("CENTER")
	button.text:SetText(tab.label)
	button:SetScript("OnClick", function()
		Party.tab = tab.id
		Party:Redraw()
	end)
	local inner = LAYOUT.cardWidth - 2 * LAYOUT.cardPad
	local width = (inner - (#TABS - 1) * LAYOUT.tabGap) / #TABS
	button:SetWidth(width)
	button:SetPoint("TOPLEFT", card, "TOPLEFT", LAYOUT.cardPad + (index - 1) * (width + LAYOUT.tabGap), -LAYOUT.headerHeight)
	return button
end

local function ShowItemTip(button)
	local slot = button.slot
	if not slot then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	if slot.itemString then
		GameTooltip:SetHyperlink(slot.itemString)
	else
		GameTooltip:SetText(L.CARD_EMPTY_SLOT:format(slot.label))
	end
	GameTooltip:Show()
end

-- A click selects the slot (again clears it) and shows it in the middle of
-- the tab; shift-click links the item in chat, as anywhere in the game.
local function ClickItem(button)
	local slot = button.slot
	if not slot then
		return
	end
	if IsModifiedClick and IsModifiedClick("CHATLINK") then
		local item = ns.ReadItem(slot.itemString)
		if item and item.link and ChatEdit_InsertLink then
			ChatEdit_InsertLink(item.link)
		end
		return
	end
	Party.selectedSlot = Party.selectedSlot ~= slot.id and slot.id or nil
	Party:Redraw()
end

local function ItemIcon(itemId)
	if not itemId then
		return nil
	end
	if C_Item and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(itemId)
	end
	return GetItemIcon and GetItemIcon(itemId)
end

-- Where a slot sits, as on the game's character window: two columns down
-- the sides, the weapons in a row under the middle.
local function PlaceSlot(button, slot, area, size)
	local gap, pad = LAYOUT.slotGap, LAYOUT.areaPad
	button:SetSize(size, size)
	button:ClearAllPoints()
	if slot.column == "left" then
		button:SetPoint("TOPLEFT", area, "TOPLEFT", pad, -pad - (slot.row - 1) * (size + gap))
	elseif slot.column == "right" then
		button:SetPoint("TOPRIGHT", area, "TOPRIGHT", -pad, -pad - (slot.row - 1) * (size + gap))
	else
		local offset = (slot.row - 2) * (size + gap) -- three, centered
		button:SetPoint("BOTTOM", area, "BOTTOM", offset, pad)
	end
end

local function CreateSlot(area)
	local button = CreateFrame("Button", nil, area, "BackdropTemplate")
	button:SetBackdrop(SLOT_BACKDROP)
	button:SetBackdropColor(unpack(COLORS.slotBack))
	button:SetBackdropBorderColor(unpack(COLORS.slotEdge))
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 2, -2)
	button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	button:SetScript("OnEnter", ShowItemTip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", ClickItem)
	return button
end

local function BuildHeader()
	card.ring = card:CreateTexture(nil, "BORDER")
	card.ring:SetSize(LAYOUT.portraitSize, LAYOUT.portraitSize)
	card.ring:SetPoint("TOPLEFT", LAYOUT.cardPad, -LAYOUT.cardPad)
	card.ring:SetTexture("Interface\\Buttons\\WHITE8x8")
	card.ring:SetVertexColor(unpack(COLORS.selected))
	Round(card.ring, card)
	card.portrait = card:CreateTexture(nil, "ARTWORK")
	card.portrait:SetPoint("TOPLEFT", card.ring, "TOPLEFT", LAYOUT.portraitRing, -LAYOUT.portraitRing)
	card.portrait:SetPoint("BOTTOMRIGHT", card.ring, "BOTTOMRIGHT", -LAYOUT.portraitRing, LAYOUT.portraitRing)
	Round(card.portrait, card)

	-- The crest of the faction: everyone on a channel shares yours.
	card.crest = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.crest:SetSize(LAYOUT.crestSize, LAYOUT.crestSize)
	card.crest:SetPoint("TOPRIGHT", -LAYOUT.crestRight, -LAYOUT.cardPad)
	card.crest:SetAlpha(COLORS.crestAlpha)
	local faction = UnitFactionGroup and UnitFactionGroup("player")
	card.crest:SetTexture(CRESTS[faction] or nil)

	local textLeft = LAYOUT.cardPad + LAYOUT.portraitSize + 10
	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.name:SetPoint("TOPLEFT", textLeft, -(LAYOUT.cardPad + 6))
	card.name:SetPoint("RIGHT", -30, 0)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.classIcon = card:CreateTexture(nil, "ARTWORK")
	card.classIcon:SetSize(LAYOUT.classIconSize, LAYOUT.classIconSize)
	card.classIcon:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
	card.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	card.sub:SetPoint("LEFT", card.classIcon, "RIGHT", 5, 0)

	local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		Party:Close()
	end)
end

-- The area's height: the longest column of slots and the weapons under it.
local function AreaHeight()
	return 3 * LAYOUT.areaPad + LAYOUT.slotRows * LAYOUT.slotSize + (LAYOUT.slotRows - 1) * LAYOUT.slotGap
end

-- The card's height: the header, the tabs and the area.
local function CardHeight()
	return LAYOUT.headerHeight + LAYOUT.tabHeight + 2 + AreaHeight() + LAYOUT.cardPad
end

-- The slots around the stage.
LayoutArea = function(area)
	local pad, size = LAYOUT.areaPad, LAYOUT.slotSize
	for index, slot in ipairs(ns.EquipmentSlots) do
		PlaceSlot(area.slots[index], slot, area, size)
	end
	local side = 2 * pad + size
	area.stage:ClearAllPoints()
	area.stage:SetPoint("TOPLEFT", side, -pad)
	area.stage:SetPoint("BOTTOMRIGHT", -side, size + 2 * pad)
end

-- A scrolling list filling the area, and the frame its contents go in.
local function CreateScrollList(area)
	local pad = LAYOUT.areaPad
	local scroll = CreateFrame("ScrollFrame", nil, area, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", pad, -pad)
	scroll:SetPoint("BOTTOMRIGHT", -(pad + LAYOUT.scrollBarWidth), pad)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -14)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 14)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(1, 1)
	scroll:SetScrollChild(list)
	return scroll, list
end

local function BuildArea()
	local area = CreateFrame("Frame", nil, card, "BackdropTemplate")
	area:SetPoint("TOPLEFT", card.tabs[1], "BOTTOMLEFT", 0, -2)
	area:SetPoint("RIGHT", -LAYOUT.cardPad, 0)
	area:SetHeight(AreaHeight())
	area:SetBackdrop(SLOT_BACKDROP)
	area:SetBackdropColor(unpack(COLORS.area))
	area:SetBackdropBorderColor(unpack(COLORS.slotEdge))
	card.area = area

	-- Equipped: the slots around a stage kept for the player's model. Until
	-- then it shows their portrait, faded.
	area.stage = area:CreateTexture(nil, "BORDER")
	area.stage:SetColorTexture(unpack(COLORS.stage))
	area.figure = area:CreateTexture(nil, "ARTWORK")
	area.figure:SetSize(LAYOUT.figureSize, LAYOUT.figureSize)
	area.figure:SetPoint("CENTER", area.stage, "CENTER")
	area.figure:SetAlpha(COLORS.figureAlpha)
	Round(area.figure, area)
	-- The selected item, or the stats from all of them, over the portrait.
	area.detailTitle = area:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	area.detailTitle:SetPoint("TOPLEFT", area.stage, "TOPLEFT", 8, -8)
	area.detailTitle:SetPoint("TOPRIGHT", area.stage, "TOPRIGHT", -8, -8)
	area.detailTitle:SetJustifyH("LEFT")
	area.detailSub = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	area.detailSub:SetPoint("TOPLEFT", area.detailTitle, "BOTTOMLEFT", 0, -3)
	area.detailSub:SetPoint("TOPRIGHT", area.detailTitle, "BOTTOMRIGHT", 0, -3)
	area.detailSub:SetJustifyH("LEFT")
	area.detailLabels = area:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	area.detailLabels:SetPoint("TOPLEFT", area.detailSub, "BOTTOMLEFT", 0, -8)
	area.detailLabels:SetJustifyH("LEFT")
	area.detailLabels:SetSpacing(3)
	area.detailValues = area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	area.detailValues:SetPoint("TOPRIGHT", area.detailSub, "BOTTOMRIGHT", 0, -8)
	area.detailValues:SetJustifyH("RIGHT")
	area.detailValues:SetSpacing(3)
	area.gearNote = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	area.gearNote:SetPoint("BOTTOMLEFT", area.stage, "BOTTOMLEFT", 4, 6)
	area.gearNote:SetPoint("BOTTOMRIGHT", area.stage, "BOTTOMRIGHT", -4, 6)
	area.slots = {}
	for index in ipairs(ns.EquipmentSlots) do
		area.slots[index] = CreateSlot(area)
	end
	area:SetScript("OnSizeChanged", LayoutArea)

	-- Quests: lines of text.
	-- Quests: a row for each, scrolling.
	local pad = LAYOUT.areaPad
	area.quests, area.questList = CreateScrollList(area)
	area.questRows = {}
	-- Info: sections of lines, scrolling.
	area.info, area.infoList = CreateScrollList(area)
	area.infoTexts = {}
	area.noQuests = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	area.noQuests:SetPoint("TOP", 0, -2 * pad)
	area.noQuests:SetText(L.CARD_NO_QUESTS)
end

local function BuildCard()
	-- On the heads' layer, below them: its left edge meets a resting head's
	-- right edge, and a head sliding out passes over it.
	card = CreateFrame("Frame", ns.Globals.frame("PlayerCard"), host, "BackdropTemplate")
	card:SetFrameStrata(strip:GetFrameStrata())
	card:SetFrameLevel(strip:GetFrameLevel())
	card:SetSize(LAYOUT.cardWidth, CardHeight())
	Party:PlaceCard()
	card:SetBackdrop(BACKDROP)
	card:SetBackdropColor(unpack(COLORS.back))
	card:SetBackdropBorderColor(unpack(COLORS.border))
	card:EnableMouse(true)
	card:Hide()
	BuildHeader()
	card.tabs = {}
	for index, tab in ipairs(TABS) do
		card.tabs[index] = CreateTab(index, tab)
	end
	BuildArea()
end

-- One quest: its name and how far they are, how far you are when it is on
-- your log too, and its objectives.
local function CreateQuestRow(list)
	local row = CreateFrame("Frame", nil, list, "BackdropTemplate")
	row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	local pad = LAYOUT.questRowPad
	row.progress = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.progress:SetPoint("TOPRIGHT", -pad, -pad - 1)
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.title:SetPoint("TOPLEFT", pad, -pad)
	row.title:SetPoint("RIGHT", row.progress, "LEFT", -6, 0)
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)
	row.title:SetTextColor(unpack(COLORS.questTitle))
	row.mine = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.mine:SetPoint("TOPRIGHT", row.progress, "BOTTOMRIGHT", 0, -3)
	row.mine:SetTextColor(unpack(COLORS.mine))
	row.objectives = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.objectives:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 6, -3)
	row.objectives:SetPoint("RIGHT", row.mine, "LEFT", -6, 0)
	row.objectives:SetJustifyH("LEFT")
	row.objectives:SetWordWrap(false) -- one line each, so the row's height is known
	row.objectives:SetSpacing(2)
	return row
end

local function ObjectivesText(quest)
	local lines = {}
	for _, objective in ipairs(quest.objectives) do
		lines[#lines + 1] = L.CARD_OBJECTIVE:format(objective.name, tostring(objective.have or 0), tostring(objective.need or 0))
	end
	return table.concat(lines, "\n")
end

-- A scroll list's width, from the layout, not the frame: right even before
-- the card first shows.
ListWidth = function()
	return LAYOUT.cardWidth - 2 * LAYOUT.cardPad - 2 * LAYOUT.areaPad - LAYOUT.scrollBarWidth
end

-- The Info tab's font strings, made as needed and reused.
local function InfoText(index, list, font)
	local area = card.area
	local text = area.infoTexts[index]
	if not text then
		text = list:CreateFontString(nil, "OVERLAY")
		area.infoTexts[index] = text
	end
	text:SetFontObject(font)
	text:ClearAllPoints()
	text:SetTextColor(1, 1, 1)
	text:Show()
	return text
end

local function DrawInfo(data)
	local area = card.area
	local list = area.infoList
	local width = ListWidth()
	list:SetWidth(width)
	local used, top = 0, 0
	local function Put(font, value, x, color, justify)
		used = used + 1
		local text = InfoText(used, list, font)
		text:SetJustifyH(justify or "LEFT")
		if justify == "RIGHT" then
			text:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -top)
		else
			text:SetPoint("TOPLEFT", list, "TOPLEFT", x, -top)
		end
		text:SetText(value)
		if color then
			text:SetTextColor(unpack(color))
		end
	end
	for index, section in ipairs(data.info) do
		if index > 1 then
			top = top + LAYOUT.infoGap
		end
		Put("GameFontNormal", section.title, 2, COLORS.questTitle)
		top = top + LAYOUT.infoHeading
		if #section.lines == 0 and section.empty then
			Put("GameFontDisableSmall", section.empty, 8)
			top = top + LAYOUT.infoLine
		end
		for _, line in ipairs(section.lines) do
			Put("GameFontHighlightSmall", line.label, 8, COLORS.infoLabel)
			Put("GameFontHighlightSmall", line.value, 0, nil, "RIGHT")
			top = top + LAYOUT.infoLine
		end
	end
	for index = used + 1, #area.infoTexts do
		area.infoTexts[index]:Hide()
	end
	list:SetHeight(math.max(1, top))
end

local function DrawQuests(data)
	local area = card.area
	local list = area.questList
	local width = ListWidth()
	list:SetWidth(width)
	local top = 0
	for index, quest in ipairs(data.quests) do
		local row = area.questRows[index] or CreateQuestRow(list)
		area.questRows[index] = row
		row:SetWidth(width)
		row:SetBackdropColor(unpack(quest.mine and COLORS.questRowShared or COLORS.questRow))
		row.title:SetText(quest.quest)
		row.progress:SetText(quest.progress or "")
		row.mine:SetText(quest.mine and L.CARD_QUEST_YOURS:format(quest.mine) or "")
		row.objectives:SetText(ObjectivesText(quest))
		local text = #quest.objectives > 0 and (row.objectives:GetStringHeight() + 3) or 0
		local height = 2 * LAYOUT.questRowPad + row.title:GetStringHeight() + math.max(text, quest.mine and 14 or 0)
		row:SetHeight(math.ceil(height))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -top)
		row:Show()
		top = top + row:GetHeight() + LAYOUT.questRowGap
	end
	for index = #data.quests + 1, #area.questRows do
		area.questRows[index]:Hide()
	end
	list:SetHeight(math.max(1, top))
	area.noQuests:SetShown(#data.quests == 0)
end

local function DrawHeader(data)
	SetPortrait(card.portrait, data)
	card.portrait:SetDesaturated(not data.here)
	card.ring:SetVertexColor(unpack(data.here and COLORS.selected or COLORS.ringGone))
	card.name:SetText(ns.ColorName(data.name, data.class))
	local coords = data.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
	card.classIcon:SetShown(coords ~= nil)
	if coords then
		card.classIcon:SetTexCoord(unpack(coords))
	end
	local className = data.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or ""
	card.sub:SetText(L.CARD_LEVEL_CLASS:format(data.level or "?", className))
end

-- An item's name in its quality's color.
local function QualityName(item)
	local color = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
	if color and color.hex then
		return color.hex .. item.name .. "|r"
	end
	return item.name
end

local function Lines(lines)
	local labels, values = {}, {}
	for _, line in ipairs(lines) do
		labels[#labels + 1] = line.label
		local value = line.value
		-- Whole numbers with commas; fractions (damage per second) to three places.
		values[#values + 1] = value == math.floor(value) and ns.Comma(value) or ("%.3f"):format(value)
	end
	return table.concat(labels, "\n"), table.concat(values, "\n")
end

-- The middle of the Equipped tab: the selected item, or the totals.
local function DrawDetails(data)
	local area = card.area
	local title, subtitle, labels, values = "", "", "", ""
	local slotId = Party.selectedSlot
	if slotId then
		local item = ns.PartyModel:SlotDetails(data.name, slotId)
		local slot = ns.EquipmentSlotById[slotId]
		if not item then
			title = L.CARD_EMPTY_SLOT:format(slot and slot.label or "")
		elseif item.loading then
			title = L.GEAR_LOADING
		else
			title = QualityName(item)
			subtitle = L.GEAR_ITEM_LINE:format(tostring(item.level or "?"), item.slotLabel or "")
			if item.required and item.required > 1 then
				subtitle = subtitle .. "\n" .. L.GEAR_REQUIRES:format(item.required)
			end
			labels, values = Lines(item.lines)
		end
	else
		-- Nothing selected: the stats from all of it, no title needed.
		local totals = ns.PartyModel:GearTotals(data.name)
		if #totals.lines > 0 then
			labels, values = Lines(totals.lines)
		elseif data.hasGear then
			labels = totals.loading and L.GEAR_LOADING or L.GEAR_TOTALS_NONE
		end
	end
	area.detailTitle:SetText(title)
	area.detailSub:SetText(subtitle)
	area.detailLabels:SetText(labels)
	area.detailValues:SetText(values)
end

local function DrawGear(data)
	local area = card.area
	SetPortrait(area.figure, data)
	area.figure:SetDesaturated(true)
	for index, slot in ipairs(data.gear) do
		local button = area.slots[index]
		button.slot = slot
		button:SetBackdropBorderColor(unpack(slot.id == Party.selectedSlot and COLORS.selected or COLORS.slotEdge))
		local icon = ItemIcon(slot.itemId)
		if icon then
			button.icon:SetTexture(icon)
			button.icon:SetAlpha(1)
		else
			-- The game's empty slot art (a faded helmet, a ring).
			local ok, _, art = pcall(GetInventorySlotInfo, slot.name)
			button.icon:SetTexture(ok and art or nil)
			button.icon:SetAlpha(0.5)
		end
	end
	DrawDetails(data)
	if not data.hasGear then
		area.gearNote:SetText(L.CARD_NO_GEAR)
	elseif data.gearAgo then
		area.gearNote:SetText(L.CARD_GEAR_AS_OF:format(ns.Ago(data.gearAgo)))
	else
		area.gearNote:SetText("")
	end
end

local function DrawCard()
	local data = Party.selected and ns.PartyModel:Card(Party.selected)
	if not data then
		card:Hide()
		return
	end
	DrawHeader(data)
	for index, tab in ipairs(TABS) do
		local button = card.tabs[index]
		local selected = tab.id == Party.tab
		button.back:SetColorTexture(unpack(selected and COLORS.tabSelected or COLORS.tab))
		button.text:SetTextColor(unpack(selected and COLORS.tabTextSelected or COLORS.tabText))
	end
	local area = card.area
	local equipped = Party.tab == "equipped"
	area.stage:SetShown(equipped)
	area.figure:SetShown(equipped)
	for _, part in ipairs({ area.detailTitle, area.detailSub, area.detailLabels, area.detailValues }) do
		part:SetShown(equipped)
	end
	area.gearNote:SetShown(equipped)
	for _, button in ipairs(area.slots) do
		button:SetShown(equipped)
	end
	area.quests:SetShown(Party.tab == "quests")
	area.info:SetShown(Party.tab == "info")
	area.noQuests:SetShown(false)
	if equipped then
		LayoutArea(area)
		DrawGear(data)
	elseif Party.tab == "quests" then
		DrawQuests(data)
	else
		DrawInfo(data)
	end
	card:Show()
end

-- ========= Drawing, coalesced ===============================================
local pending = false

function Party:Redraw()
	if not strip then
		return
	end
	local show = ns.IsEnabled("partyHeads") and host:IsShown()
	if not show then
		SetDrawerShown(false)
		card:Hide()
		return
	end
	DrawHeads(ns.PartyModel:Heads())
	if card:IsShown() or self.opening then
		self.opening = false
		DrawCard()
	end
end

-- Asks for a redraw; many asks in a moment make one.
function Party:Changed()
	if pending then
		return
	end
	pending = true
	C_Timer.After(LAYOUT.redrawSeconds, function()
		pending = false
		Party:Redraw()
	end)
end

function Party:Open(name)
	if self.selected == name and card:IsShown() then
		self:Close()
		return
	end
	if self.selected ~= name then
		self.selectedSlot = nil -- a slot chosen on someone else's card
	end
	self.selected = name
	self.opening = true
	-- Nothing of their gear yet: ask them, once (comms\sharing.lua Request).
	local member = ns.Store:GetMember(name)
	if ns.Session.peers[name] and not (member and member.gear) then
		ns.Sharing:Request(name)
	end
	self:Redraw()
end

function Party:Close()
	self.selected = nil
	card:Hide()
	self:Redraw()
end

local function Build()
	host = ns.Panel:GetFrame()
	if not host then
		return
	end
	-- The drawer: framed like the panel and tucked under its right edge.
	strip = CreateFrame("Frame", nil, host, "BackdropTemplate")
	strip:SetPoint("TOPLEFT", host, "TOPRIGHT", -LAYOUT.dockOverlap, 0)
	-- As wide as a resting head shows, so the card meets the heads' edge.
	strip:SetWidth(2 * LAYOUT.dockOverlap + math.ceil(LAYOUT.headMax * LAYOUT.peek))
	strip:SetBackdrop(BACKDROP)
	strip:SetBackdropColor(unpack(COLORS.drawer))
	strip:SetBackdropBorderColor(unpack(COLORS.border))
	strip:EnableMouseWheel(true)
	strip:SetScript("OnMouseWheel", function(_, delta)
		Party.offset = Party.offset - delta
		Party:Redraw()
	end)
	BuildCard()
	host:HookScript("OnShow", function() Party:Redraw() end)
	host:HookScript("OnHide", function() card:Hide() end)
	host:HookScript("OnSizeChanged", function() Party:Changed() end)
	-- A click anywhere on the group brings all of it to the front.
	local clicks = CreateFrame("Frame")
	clicks:RegisterEvent("GLOBAL_MOUSE_DOWN")
	clicks:SetScript("OnEvent", function()
		if host:IsShown() and (host:IsMouseOver() or strip:IsMouseOver() or (card:IsShown() and card:IsMouseOver())) then
			Party:Raise()
		end
	end)
	Party:Raise()
end

-- Brings the panel to the front of its layer, and the drawer and card with
-- it, just under it in the order LAYOUT describes.
-- What the popped-out chat docks to (ui\chat.lua): the head drawer.
function Party:Dock()
	return strip
end

-- The card sits beside the drawer, or beside the chat when it is popped out.
function Party:PlaceCard()
	if not card then
		return
	end
	local chat = ns.ChatView and ns.ChatView:IsPopped() and _G[ns.Globals.frame("Chat")]
	card:ClearAllPoints()
	card:SetPoint("TOPLEFT", chat or strip, "TOPRIGHT", -LAYOUT.dockOverlap, 0)
end

function Party:Raise()
	if not host then
		return
	end
	host:Raise()
	local level = math.max(host:GetFrameLevel(), LAYOUT.raiseRoom)
	host:SetFrameLevel(level)
	local base = level - LAYOUT.raiseRoom + 1
	for _, part in ipairs({ strip, card }) do
		part:SetFrameStrata(host:GetFrameStrata())
		part:SetFrameLevel(base)
	end
	if ns.ChatView then
		ns.ChatView:Raise(host:GetFrameStrata(), base)
	end
	self:Redraw() -- the heads take their levels from the drawer's
end

Bus:On("READY", Build)
Bus:On("STORE_CHANGED", function() Party:Changed() end)
Bus:On("PEERS_CHANGED", function() Party:Changed() end)
Bus:On("SETTING_CHANGED", function() Party:Changed() end)
Bus:On("DEBUG_CHANGED", function() Party:Changed() end)

-- An item the game had not loaded yet has arrived: the card can show it now.
local itemLoads = CreateFrame("Frame")
itemLoads:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemLoads:SetScript("OnEvent", function()
	if card and card:IsShown() then
		Party:Changed()
	end
end)

Bus:On("CHAT_POPPED", function() Party:PlaceCard() Party:Raise() end)
