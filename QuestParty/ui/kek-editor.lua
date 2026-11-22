-- KekChat editor: your saved KekChats (chat.lua), up to maxMessages, each a
-- row: an icon (click: the icon browser, ui\icon-browser.lua), your words (up
-- to maxText), a sound (click to step through ns.KekSounds; the play button
-- hears it) and an effect (click to step through ns.ChatEffects), and a clear
-- button. Each change is saved as it is made. Under them, who and what you
-- have blocked (ui\kek-blocked.lua), the window as tall as that list needs.
-- Opened from Settings, KekChat.
-- It owns frames only.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local KekEditor = {}
ns.KekEditor = KekEditor

local LAYOUT = {
	pad = 10, header = 46, blockedTitle = 24, row = 30, icon = 26, text = 240, sound = 100, play = 22, effect = 96, clear = 22, gap = 6,
}
local COLORS = { back = { 0.05, 0.04, 0.08, 0.97 }, edge = { 0.80, 0.65, 0.20, 1 }, cell = { 0.35, 0.30, 0.18, 1 } }
local NO_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, status
local rows = {}

-- The choices to step through: none first, then each in order.
local function Step(list, current, direction)
	local index = 0
	for position, item in ipairs(list) do
		if item.id == current then index = position end
	end
	index = (index + direction) % (#list + 1)
	return index > 0 and list[index].id or nil
end

local function Say(text, good)
	status:SetFontObject(good and "GameFontGreenSmall" or "GameFontRedSmall")
	status:SetText(text or "")
end

-- Plays a row as it would land: its sound, and its effect (its icon as the
-- particles) over the editor.
local function Preview(index)
	local message = ns.Chat:KekMessages()[index] or {}
	ns.Chat.PlayKekSound(message.sound)
	local effect = message.effect and ns.ChatEffectById[message.effect]
	if effect and message.icon and ns.ParticleView then
		ns.ParticleView:Play(frame, effect, { message.icon })
	end
end

-- Saves one row with a change: its icon, words, sound or effect.
local function Save(index, change)
	local current = ns.Chat:KekMessages()[index] or {}
	local merged = { icon = current.icon, text = current.text, sound = current.sound, effect = current.effect }
	for key, value in pairs(change) do
		if value == false then merged[key] = nil else merged[key] = value end
	end
	if not merged.icon and (not merged.text or merged.text == "") then
		ns.Chat:RemoveKekMessage(index)
		return
	end
	local ok, problem = ns.Chat:SetKekMessage(index, merged)
	if not ok then Say(problem) end
end

local function DrawRow(row)
	local message = ns.Chat:KekMessages()[row.index] or {}
	row.icon.texture:SetTexture(message.icon or NO_ICON)
	row.icon.texture:SetDesaturated(message.icon == nil)
	if not row.text:HasFocus() then row.text:SetText(message.text or "") end
	local sound = message.sound and ns.KekSoundById[message.sound]
	row.sound.label:SetText(sound and sound.label or L.KEK_NO_SOUND)
	row.play:SetEnabled(sound ~= nil or (message.effect ~= nil and message.icon ~= nil))
	local effect = message.effect and ns.ChatEffectById[message.effect]
	row.effect.label:SetText(effect and effect.label or L.KEK_NO_EFFECT)
end

function KekEditor:Refresh()
	if not frame or not frame:IsShown() then return end
	for _, row in ipairs(rows) do DrawRow(row) end
end

-- A small framed button with a label, for the sound and the effect.
local function LabelButton(parent, width, onClick, tip)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, LAYOUT.icon)
	button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	button:SetBackdropColor(0.10, 0.09, 0.13, 1)
	button:SetBackdropBorderColor(unpack(COLORS.cell))
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("LEFT", 6, 0)
	button.label:SetPoint("RIGHT", -6, 0)
	button.label:SetWordWrap(false)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

local function BuildRow(index)
	local row = { index = index }
	local top = -(LAYOUT.header + (index - 1) * LAYOUT.row)
	local x = LAYOUT.pad

	row.icon = CreateFrame("Button", nil, frame, "BackdropTemplate")
	row.icon:SetSize(LAYOUT.icon, LAYOUT.icon)
	row.icon:SetPoint("TOPLEFT", x, top)
	row.icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	row.icon:SetBackdropColor(0, 0, 0, 0.6)
	row.icon:SetBackdropBorderColor(unpack(COLORS.cell))
	row.icon.texture = row.icon:CreateTexture(nil, "ARTWORK")
	row.icon.texture:SetPoint("TOPLEFT", 2, -2)
	row.icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
	row.icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	row.icon:SetScript("OnClick", function(self)
		ns.IconBrowser:Open(self, function(icon) Save(index, { icon = icon }) end)
	end)
	x = x + LAYOUT.icon + LAYOUT.gap

	row.text = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	row.text:SetSize(LAYOUT.text, LAYOUT.icon - 4)
	row.text:SetPoint("TOPLEFT", x + 4, top - 2)
	row.text:SetAutoFocus(false)
	row.text:SetMaxLetters(ns.ChatRules.maxText)
	local function SaveText(self)
		Save(index, { text = self:GetText() ~= "" and self:GetText() or false })
	end
	row.text:SetScript("OnEnterPressed", function(self) SaveText(self) self:ClearFocus() end)
	row.text:SetScript("OnEditFocusLost", SaveText)
	row.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	x = x + LAYOUT.text + LAYOUT.gap + 4

	row.sound = LabelButton(frame, LAYOUT.sound, function(_, button)
		local current = (ns.Chat:KekMessages()[index] or {}).sound
		local chosen = Step(ns.KekSounds, current, button == "RightButton" and -1 or 1)
		Save(index, { sound = chosen or false })
		ns.Chat.PlayKekSound(chosen)
	end, L.KEK_SOUND_TIP)
	row.sound:SetPoint("TOPLEFT", x, top)
	x = x + LAYOUT.sound + 2

	row.play = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	row.play:SetSize(LAYOUT.play, LAYOUT.icon)
	row.play:SetPoint("TOPLEFT", x, top)
	row.play:SetText(">")
	row.play:SetScript("OnClick", function() Preview(index) end)
	row.play:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.KEK_PREVIEW)
		GameTooltip:Show()
	end)
	row.play:SetScript("OnLeave", function() GameTooltip:Hide() end)
	x = x + LAYOUT.play + LAYOUT.gap

	row.effect = LabelButton(frame, LAYOUT.effect, function(_, button)
		local message = ns.Chat:KekMessages()[index] or {}
		local chosen = Step(ns.ChatEffects, message.effect, button == "RightButton" and -1 or 1)
		Save(index, { effect = chosen or false })
		local effect = chosen and ns.ChatEffectById[chosen]
		if effect and message.icon and ns.ParticleView then ns.ParticleView:Play(frame, effect, { message.icon }) end
	end, L.KEK_EFFECT_TIP)
	row.effect:SetPoint("TOPLEFT", x, top)
	x = x + LAYOUT.effect + LAYOUT.gap

	local clear = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	clear:SetSize(LAYOUT.clear, LAYOUT.clear)
	clear:SetPoint("TOPLEFT", x, top - 2)
	clear:SetScript("OnClick", function() ns.Chat:RemoveKekMessage(index) end)
	clear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.KEK_CLEAR)
		GameTooltip:Show()
	end)
	clear:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return row
end

local function Build()
	local count = ns.ChatRules.maxMessages
	local width = 2 * LAYOUT.pad + LAYOUT.icon + LAYOUT.text + LAYOUT.sound + LAYOUT.play + LAYOUT.effect + LAYOUT.clear + 4 * LAYOUT.gap + 6
	local rowsBottom = LAYOUT.header + count * LAYOUT.row
	local height = rowsBottom + LAYOUT.blockedTitle + LAYOUT.pad
	frame = CreateFrame("Frame", ns.Globals.frame("KekEditor"), UIParent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	frame:SetBackdropColor(unpack(COLORS.back))
	frame:SetBackdropBorderColor(unpack(COLORS.edge))
	frame:Hide()
	tinsert(UISpecialFrames, frame:GetName())
	frame:SetScript("OnHide", function() ns.IconBrowser:Close() end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LAYOUT.pad, -LAYOUT.pad)
	title:SetText(L.KEK_EDITOR_TITLE)
	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	hint:SetText(L.KEK_EDITOR_HINT:format(count, ns.ChatRules.maxText))
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	status = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	status:SetPoint("TOPRIGHT", -30, -LAYOUT.pad - 4)

	for index = 1, count do rows[index] = BuildRow(index) end

	-- Who and what you have blocked, each with Unblock: as tall as that is.
	local blocked = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	blocked:SetPoint("TOPLEFT", LAYOUT.pad, -(rowsBottom + 4))
	blocked:SetText(L.KEK_BLOCKED_TITLE)
	local listTop = rowsBottom + LAYOUT.blockedTitle
	local listHeight = ns.KekBlocked:Build(frame, listTop, LAYOUT.pad, width - 2 * LAYOUT.pad, function(tall)
		frame:SetHeight(listTop + tall + LAYOUT.pad)
	end)
	frame:SetHeight(listTop + listHeight + LAYOUT.pad)
end

function KekEditor:Toggle()
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
	Say("")
	self:Refresh()
end

Bus:On("CHAT_PRESETS_CHANGED", function() KekEditor:Refresh() end)
