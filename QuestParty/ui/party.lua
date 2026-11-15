-- Party: a head for each player in the party, down the right edge of the
-- panel, and the card a head opens: Overview, Quests and Items tabs. It draws
-- what ui\party-model.lua gives it, and owns nothing but frames.
-- Kept simple on purpose: plain buttons and text, to grow as we learn what
-- we want from it.
local _, ns = ...
local Bus = ns.Bus
local L = ns.L

local Party = { selected = nil, tab = "overview", offset = 0 }
ns.Party = Party

local LAYOUT = {
	headSize = 34,
	headGap = 4,
	stripTop = 30, -- level with the panel's list, under its title
	stripGap = 3, -- between the panel and the heads
	cardWidth = 250,
	cardHeight = 372,
	cardGap = 4,
	portraitSize = 40,
	tabHeight = 20,
	slotSize = 28,
	slotGap = 4,
	xpBarHeight = 12,
	redrawSeconds = 0.2, -- many messages, one redraw
}

local COLORS = {
	back = { 0.05, 0.04, 0.08, 0.94 },
	border = { 0.80, 0.65, 0.20, 1 },
	gone = 0.45, -- the alpha of a head for someone who left
	selected = { 1, 0.85, 0.35, 1 },
	tab = { 1, 1, 1, 0.08 },
	tabSelected = { 0.80, 0.65, 0.20, 0.45 },
	xp = { 0.58, 0.36, 0.86, 1 },
	slotBack = { 0, 0, 0, 0.55 },
	muted = { 0.75, 0.75, 0.75 },
}

local TABS = {
	{ id = "overview", label = L.CARD_OVERVIEW },
	{ id = "quests", label = L.CARD_QUESTS },
	{ id = "items", label = L.CARD_ITEMS },
}

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local host, strip, card
local heads = {}

local function ClassColor(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return unpack(COLORS.border)
end

-- A portrait: the game's race art when it has it, or the class icon.
local function SetPortrait(texture, data)
	if data.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(data.atlas) then
		texture:SetAtlas(data.atlas)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end
	texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	local coords = data.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
	if coords then
		texture:SetTexCoord(unpack(coords))
	else
		texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

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

local function CreateHead()
	local button = CreateFrame("Button", nil, strip, "BackdropTemplate")
	button:SetSize(LAYOUT.headSize, LAYOUT.headSize)
	button:SetBackdrop(BACKDROP)
	button:SetBackdropColor(unpack(COLORS.back))
	button.portrait = button:CreateTexture(nil, "ARTWORK")
	button.portrait:SetPoint("TOPLEFT", 3, -3)
	button.portrait:SetPoint("BOTTOMRIGHT", -3, 3)
	button.level = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.level:SetPoint("BOTTOMRIGHT", -2, 2)
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function(self)
		if self.data then
			Party:Open(self.data.name)
		end
	end)
	button:SetScript("OnEnter", ShowHeadTip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

-- How many heads fit beside the panel.
local function Fits()
	local height = (host:GetHeight() or 0) - LAYOUT.stripTop
	return math.max(1, math.floor((height + LAYOUT.headGap) / (LAYOUT.headSize + LAYOUT.headGap)))
end

local function DrawHeads(list)
	local fits = Fits()
	Party.offset = math.max(0, math.min(Party.offset, #list - fits))
	local shown = 0
	for index = Party.offset + 1, math.min(#list, Party.offset + fits) do
		shown = shown + 1
		local button = heads[shown] or CreateHead()
		heads[shown] = button
		local data = list[index]
		button.data = data
		SetPortrait(button.portrait, data)
		button.portrait:SetDesaturated(not data.here)
		button:SetAlpha(data.here and 1 or COLORS.gone)
		button.level:SetText(data.level or "")
		if data.name == Party.selected then
			button:SetBackdropBorderColor(unpack(COLORS.selected))
		else
			button:SetBackdropBorderColor(ClassColor(data.class))
		end
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -(shown - 1) * (LAYOUT.headSize + LAYOUT.headGap))
		button:Show()
	end
	for index = shown + 1, #heads do
		heads[index]:Hide()
		heads[index].data = nil
	end
end

-- ========= The card =========================================================
local function CreateTab(index, tab)
	local button = CreateFrame("Button", nil, card)
	button:SetHeight(LAYOUT.tabHeight)
	button.back = button:CreateTexture(nil, "BACKGROUND")
	button.back:SetAllPoints()
	button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.text:SetPoint("CENTER")
	button.text:SetText(tab.label)
	button:SetScript("OnClick", function()
		Party.tab = tab.id
		Party:Redraw()
	end)
	local width = (LAYOUT.cardWidth - 16 - (#TABS - 1) * 2) / #TABS
	button:SetWidth(width)
	button:SetPoint("TOPLEFT", card.portrait, "BOTTOMLEFT", (index - 1) * (width + 2), -8)
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

local function ClickItem(button)
	local slot = button.slot
	if not (slot and slot.itemString) then
		return
	end
	if IsModifiedClick and IsModifiedClick("CHATLINK") and GetItemInfo then
		local _, link = GetItemInfo(slot.itemString)
		if link and ChatEdit_InsertLink then
			ChatEdit_InsertLink(link)
		end
	end
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

-- Where a slot sits on the Items tab, as on the game's character window.
local function PlaceSlot(button, slot, area)
	local size, gap = LAYOUT.slotSize, LAYOUT.slotGap
	button:ClearAllPoints()
	if slot.column == "left" then
		button:SetPoint("TOPLEFT", area, "TOPLEFT", 4, -(slot.row - 1) * (size + gap))
	elseif slot.column == "right" then
		button:SetPoint("TOPRIGHT", area, "TOPRIGHT", -4, -(slot.row - 1) * (size + gap))
	else
		local rowWidth = 3 * size + 2 * gap
		local left = (LAYOUT.cardWidth - 16 - rowWidth) / 2
		button:SetPoint("TOPLEFT", area, "TOPLEFT", left + (slot.row - 1) * (size + gap), -8 * (size + gap) - 4)
	end
end

local function CreateSlot(area)
	local button = CreateFrame("Button", nil, area, "BackdropTemplate")
	button:SetSize(LAYOUT.slotSize, LAYOUT.slotSize)
	button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	button:SetBackdropColor(unpack(COLORS.slotBack))
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 1, -1)
	button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	button:SetScript("OnEnter", ShowItemTip)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnClick", ClickItem)
	return button
end

local function BuildCard()
	card = CreateFrame("Frame", ns.Globals.frame("PlayerCard"), host, "BackdropTemplate")
	card:SetSize(LAYOUT.cardWidth, LAYOUT.cardHeight)
	card:SetPoint("TOPLEFT", strip, "TOPRIGHT", LAYOUT.cardGap, LAYOUT.stripTop)
	card:SetBackdrop(BACKDROP)
	card:SetBackdropColor(unpack(COLORS.back))
	card:SetBackdropBorderColor(unpack(COLORS.border))
	card:SetFrameStrata("MEDIUM")
	card:EnableMouse(true)
	card:Hide()

	card.portrait = card:CreateTexture(nil, "ARTWORK")
	card.portrait:SetSize(LAYOUT.portraitSize, LAYOUT.portraitSize)
	card.portrait:SetPoint("TOPLEFT", 8, -8)
	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.name:SetPoint("TOPLEFT", card.portrait, "TOPRIGHT", 8, -1)
	card.name:SetPoint("RIGHT", -26, 0)
	card.name:SetJustifyH("LEFT")
	card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
	card.sub:SetPoint("RIGHT", -8, 0)
	card.sub:SetJustifyH("LEFT")
	card.status = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.status:SetPoint("TOPLEFT", card.sub, "BOTTOMLEFT", 0, -2)

	local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		Party:Close()
	end)

	card.tabs = {}
	for index, tab in ipairs(TABS) do
		card.tabs[index] = CreateTab(index, tab)
	end

	-- What a tab shows sits in this area.
	local area = CreateFrame("Frame", nil, card)
	area:SetPoint("TOPLEFT", card.tabs[1], "BOTTOMLEFT", 0, -8)
	area:SetPoint("BOTTOMRIGHT", -8, 8)
	card.area = area

	-- Overview
	area.xpBar = CreateFrame("StatusBar", nil, area)
	area.xpBar:SetHeight(LAYOUT.xpBarHeight)
	area.xpBar:SetPoint("TOPLEFT")
	area.xpBar:SetPoint("TOPRIGHT")
	area.xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	area.xpBar:SetStatusBarColor(unpack(COLORS.xp))
	area.xpBar.back = area.xpBar:CreateTexture(nil, "BACKGROUND")
	area.xpBar.back:SetAllPoints()
	area.xpBar.back:SetColorTexture(0, 0, 0, 0.5)
	area.xpText = area.xpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	area.xpText:SetPoint("CENTER")

	-- Overview and Quests: lines of text.
	area.text = area:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	area.text:SetJustifyH("LEFT")
	area.text:SetJustifyV("TOP")
	area.text:SetSpacing(3)

	-- Items
	area.slots = {}
	for index, slot in ipairs(ns.EquipmentSlots) do
		local button = CreateSlot(area)
		PlaceSlot(button, slot, area)
		area.slots[index] = button
	end
	area.gearNote = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	area.gearNote:SetPoint("BOTTOM", 0, 2)
end

local function OverviewText(data)
	local lines = {}
	if data.zone then
		lines[#lines + 1] = data.zone
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = L.CARD_XP_SESSION:format(ns.Comma(data.sessionXP or 0))
	lines[#lines + 1] = L.CARD_XP_TODAY:format(ns.Comma(data.todayXP or 0))
	lines[#lines + 1] = L.CARD_XP_WEEK:format(ns.Comma(data.weekXP or 0))
	if data.version then
		lines[#lines + 1] = ""
		lines[#lines + 1] = L.CARD_VERSION:format(data.version)
	end
	return table.concat(lines, "\n")
end

local function QuestsText(data)
	local lines = {}
	if #data.inCommon > 0 then
		lines[#lines + 1] = "|cffffd100" .. L.CARD_IN_COMMON .. "|r"
		for _, quest in ipairs(data.inCommon) do
			lines[#lines + 1] = L.CARD_IN_COMMON_LINE:format(quest.quest, quest.mine, data.name, quest.theirs)
		end
		lines[#lines + 1] = ""
	end
	if #data.quests == 0 then
		lines[#lines + 1] = L.CARD_NO_QUESTS
	else
		lines[#lines + 1] = "|cffffd100" .. L.CARD_THEIRS .. "|r"
		for _, quest in ipairs(data.quests) do
			lines[#lines + 1] = quest.quest .. (quest.progress and ("  |cffbfbfbf" .. quest.progress .. "|r") or "")
			for _, objective in ipairs(quest.objectives) do
				lines[#lines + 1] = ("   %s %s/%s"):format(objective.name, tostring(objective.have or 0), tostring(objective.need or 0))
			end
		end
	end
	return table.concat(lines, "\n")
end

local function DrawCard()
	local data = Party.selected and ns.PartyModel:Card(Party.selected)
	if not data then
		card:Hide()
		return
	end
	SetPortrait(card.portrait, data)
	card.portrait:SetDesaturated(not data.here)
	card.name:SetText(ns.ColorName(data.name, data.class))
	local className = data.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[data.class] or data.class) or ""
	card.sub:SetText(L.CARD_LEVEL_CLASS:format(data.level or "?", className))
	card.status:SetText(StatusLine(data))
	for index, tab in ipairs(TABS) do
		local button = card.tabs[index]
		button.back:SetColorTexture(unpack(tab.id == Party.tab and COLORS.tabSelected or COLORS.tab))
	end

	local area = card.area
	local overview, items = Party.tab == "overview", Party.tab == "items"
	area.xpBar:SetShown(overview)
	area.text:SetShown(not items)
	for _, button in ipairs(area.slots) do
		button:SetShown(items)
	end
	area.gearNote:SetShown(items)
	area.text:ClearAllPoints()
	if overview then
		if data.xp then
			area.xpBar:SetMinMaxValues(0, data.xp.need)
			area.xpBar:SetValue(data.xp.have)
			area.xpText:SetText(data.xp.text)
		else
			area.xpBar:SetMinMaxValues(0, 1)
			area.xpBar:SetValue(0)
			area.xpText:SetText(L.XPBAR_LEVEL:format(data.level or "?"))
		end
		area.text:SetPoint("TOPLEFT", area.xpBar, "BOTTOMLEFT", 0, -8)
		area.text:SetPoint("BOTTOMRIGHT")
		area.text:SetText(OverviewText(data))
	elseif Party.tab == "quests" then
		area.text:SetPoint("TOPLEFT")
		area.text:SetPoint("BOTTOMRIGHT")
		area.text:SetText(QuestsText(data))
	else
		for index, slot in ipairs(data.gear) do
			local button = area.slots[index]
			button.slot = slot
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
		if not data.hasGear then
			area.gearNote:SetText(L.CARD_NO_GEAR)
		elseif data.gearAgo then
			area.gearNote:SetText(L.CARD_GEAR_AS_OF:format(ns.Ago(data.gearAgo)))
		end
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
	strip:SetShown(show)
	if not show then
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
	strip = CreateFrame("Frame", nil, host)
	strip:SetPoint("TOPLEFT", host, "TOPRIGHT", LAYOUT.stripGap, -LAYOUT.stripTop)
	strip:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", LAYOUT.stripGap, 0)
	strip:SetWidth(LAYOUT.headSize)
	strip:EnableMouseWheel(true)
	strip:SetScript("OnMouseWheel", function(_, delta)
		Party.offset = Party.offset - delta
		Party:Redraw()
	end)
	BuildCard()
	host:HookScript("OnShow", function() Party:Redraw() end)
	host:HookScript("OnHide", function() card:Hide() end)
	host:HookScript("OnSizeChanged", function() Party:Changed() end)
	Party:Redraw()
end

Bus:On("READY", Build)
Bus:On("STORE_CHANGED", function() Party:Changed() end)
Bus:On("PEERS_CHANGED", function() Party:Changed() end)
Bus:On("SETTING_CHANGED", function() Party:Changed() end)
Bus:On("DEBUG_CHANGED", function() Party:Changed() end)
