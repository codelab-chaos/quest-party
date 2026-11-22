-- Chat view: KekChat's bar (chat.lua, docs\chat.md), under the feed on the
-- Feed tab, above the filter row (ui\panel.lua places it):
--                                                   [KekChat v]  quick chats only
--   [images] [type to pick] [Send] [Save] [your saves] [KekChat v]
--   (the second with Custom KekChat on, in Settings)
-- Messages are feed rows (data\feed-types.lua, chat), sent and read like
-- every other entry: this only builds and sends them. KekChat's list holds
-- the quick chats (presets and effects), and one click sends one. An effect
-- plays its images (and a worded one its saying's words) as particles
-- (ui\particles.lua) over the feed, with its sound, when it lands.
-- Nobody types words of their own. It owns frames only.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local ChatView = { icons = {}, effect = nil, saying = nil }
ns.ChatView = ChatView

local LAYOUT = {
	pad = 6,
	debounce = 0.5, -- a second press this soon is the same press
	bar = 24, -- the chat bar's height
	barGap = 3,
	sendWidth = 44,
	saveWidth = 40,
	-- Pickers open above the bar.
	columns = 7, -- the image picker: a page of icons at a time
	rows = 4,
	cell = 34,
	cellGap = 3,
	searchHeight = 20,
	listRow = 22, -- a row in the saying and preset pickers
	listRows = 9, -- rows shown before they scroll
	readyWidth = 100, -- KekChat: its name and a down arrow
}

-- Where the bar goes (ui\panel.lua places it on the line between the feed
-- and the filter row). With quick chats only, KekChat's button straddles the
-- line and takes no room of its own; with Custom KekChat, the bar sits on
-- the line in a row of its own.
ChatView.height = LAYOUT.bar

-- Custom KekChat (the builder: images, typing, Send, Save, your saves) is
-- off for now (owner, 2026-11-20): KekChat is its quick chats. Set true to
-- bring it back, with its switch in data\settings.lua (kekChatCustom).
local CUSTOM = false
function ChatView:CustomOn()
	return CUSTOM and ns.IsEnabled("kekChatCustom")
end

function ChatView:Straddles()
	return not ChatView:CustomOn()
end
-- Room the bar takes above the line.
function ChatView:Room()
	return self:Straddles() and 0 or LAYOUT.bar + 2
end

local COLORS = {
	picker = { 0.03, 0.03, 0.05, 0.97 },
	border = { 0.80, 0.65, 0.20, 1 },
	selected = { 1, 0.85, 0.35, 1 },
	cellEdge = { 0.35, 0.30, 0.18, 1 },
	barButton = { 0.10, 0.09, 0.13, 1 },
	barEdge = { 0.45, 0.36, 0.14, 1 },
	saying = { 1, 1, 1 },
	effect = { 1, 0.82, 0 }, -- a saying that does something (Cheers!)
	heading = { 1, 0.82, 0 },
	muted = { 0.55, 0.55, 0.55 },
}

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local EDGE = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local NO_IMAGE = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame, bar, status
local imageButton, compose
local pickers = {} -- image, suggest, presets, saves: one open at a time

local function SayingText(id)
	local saying = id and ns.SayingById[id]
	return saying and saying.text or nil
end

-- A line just above the bar, for why something did not go (red) or what
-- just happened (green): shown in the chat itself, where you are looking.
function ChatView:Say(text, good)
	status:SetFontObject(good and "GameFontGreenSmall" or "GameFontRedSmall")
	status:SetText(text or "")
	status.until_ = GetTime() + 6
	C_Timer.After(6.1, function()
		if status.until_ and GetTime() >= status.until_ then
			status:SetText("")
		end
	end)
end

-- ========= Effects ==========================================================
-- Plays a message's effect (its feed entry's data), if it has one and effects
-- are on, over the panel while it shows, with its sound.
function ChatView:PlayEffect(message)
	local effect = message.effect and ns.ChatEffectById[message.effect]
	if not effect or not ns.IsEnabled("chatEffects") then
		return
	end
	local over = ns.Panel:GetFrame()
	if not (over and over:IsVisible()) then
		return
	end
	local saying = message.saying and ns.SayingById[message.saying]
	ns.ParticleView:Play(over, effect, message.icons or {}, saying and saying.text)
	if effect.sound then
		ns.PlaySound(effect.sound) -- at the Volume in Settings
	end
end

-- ========= The chat bar =====================================================
local function DrawBar()
	local first = ChatView.icons[1]
	imageButton.texture:SetTexture(first or NO_IMAGE)
	imageButton.texture:SetDesaturated(first == nil)
	imageButton.texture:SetAlpha(first and 1 or 0.4)
	imageButton.count:SetText(#ChatView.icons > 1 and #ChatView.icons or "")
	local text = SayingText(ChatView.saying)
	-- The typing box shows the saying chosen, faintly, while it is empty.
	compose.Instructions:SetText(text and ("|cffffffff" .. text .. "|r") or L.CHAT_TYPE_HINT)
end

local function ClosePickers()
	for _, picker in pairs(pickers) do
		picker:Hide()
	end
end

local Place -- below: where a picker opens, filled first

local function Toggle(name, open)
	local picker = pickers[name]
	local wasShown = picker:IsShown()
	ClosePickers()
	if not wasShown then
		picker:Show()
		if open then open() end
		Place(picker)
	end
end

-- A picker: a framed box above the bar.
local function Picker(width, height)
	local picker = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	picker:SetSize(width, height)
	picker:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -4, 4)
	picker:SetBackdrop(BACKDROP)
	picker:SetBackdropColor(unpack(COLORS.picker))
	picker:SetBackdropBorderColor(unpack(COLORS.border))
	picker:EnableMouse(true)
	picker:SetClampedToScreen(true) -- never off the screen, whatever happens
	picker:Hide()
	return picker
end

-- ========= Picking an image =================================================
local images -- the image picker: search box, grid, pages

local function PerPage()
	return LAYOUT.columns * LAYOUT.rows
end

local function ImageResults()
	local search = images.search:GetText()
	local found = ns.Chat:Search(search)
	if search:match("^%s*$") then
		-- Nothing typed: our icons first, then every icon in the game.
		local seen = {}
		for _, icon in ipairs(found) do seen[icon] = true end
		for _, icon in ipairs(ns.Chat:AllIcons()) do
			if not seen[icon] then found[#found + 1] = icon end
		end
	end
	return found
end

local function DrawImages()
	local results, per = images.results, PerPage()
	local pages = math.max(1, math.ceil(#results / per))
	images.page = math.max(1, math.min(images.page, pages))
	local first = (images.page - 1) * per
	for index, cell in ipairs(images.cells) do
		local icon = results[first + index]
		cell.icon = icon
		cell.texture:SetTexture(icon)
		cell:SetShown(icon ~= nil)
		local chosen = false
		for _, picked in ipairs(ChatView.icons) do
			if picked == icon then chosen = true end
		end
		cell:SetBackdropBorderColor(unpack((chosen or first + index == images.selected) and COLORS.selected or COLORS.cellEdge))
		cell:SetAlpha(chosen and 0.55 or 1)
	end
	images.pageText:SetText(L.CHAT_PAGE:format(images.page, pages) .. "   " .. L.CHAT_IMAGES_PICKED:format(#ChatView.icons))
end

local function SearchImages()
	images.results = ImageResults()
	images.page, images.selected = 1, 1
	DrawImages()
end

-- Picking an image adds it (up to three), or takes it out again; the picker
-- stays open so more can be picked, and closes once three are chosen.
local function PickImage(icon)
	if not icon then return end
	for index, picked in ipairs(ChatView.icons) do
		if picked == icon then
			table.remove(ChatView.icons, index)
			DrawBar()
			DrawImages()
			return
		end
	end
	if #ChatView.icons >= ns.ParticleRules.maxImages then
		table.remove(ChatView.icons, 1)
	end
	ChatView.icons[#ChatView.icons + 1] = icon
	DrawBar()
	DrawImages()
	if #ChatView.icons >= ns.ParticleRules.maxImages then
		ClosePickers()
	end
end

local function MoveSelection(step)
	local count = #images.results
	if count == 0 then return end
	images.selected = math.max(1, math.min(count, images.selected + step))
	images.page = math.ceil(images.selected / PerPage())
	DrawImages()
end

local function BuildImagePicker()
	local width = LAYOUT.columns * (LAYOUT.cell + LAYOUT.cellGap) - LAYOUT.cellGap + 2 * LAYOUT.pad
	local height = LAYOUT.searchHeight + LAYOUT.rows * (LAYOUT.cell + LAYOUT.cellGap) + 3 * LAYOUT.pad + 18
	images = Picker(width, height)
	pickers.image = images

	local search = CreateFrame("EditBox", nil, images, "InputBoxTemplate")
	search:SetHeight(LAYOUT.searchHeight)
	search:SetPoint("TOPLEFT", LAYOUT.pad + 4, -LAYOUT.pad)
	search:SetPoint("TOPRIGHT", -LAYOUT.pad, -LAYOUT.pad)
	search:SetAutoFocus(false)
	search:SetAltArrowKeyMode(false)
	search:SetScript("OnTextChanged", function(self, byUser)
		self.Instructions:SetShown(self:GetText() == "")
		if byUser then SearchImages() end
	end)
	search:SetScript("OnEnterPressed", function() PickImage(images.results[images.selected]) end)
	search:SetScript("OnEscapePressed", ClosePickers)
	search:SetScript("OnArrowPressed", function(_, key)
		local steps = { LEFT = -1, RIGHT = 1, UP = -LAYOUT.columns, DOWN = LAYOUT.columns }
		if steps[key] then MoveSelection(steps[key]) end
	end)
	search.Instructions = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	search.Instructions:SetPoint("LEFT", 2, 0)
	search.Instructions:SetText(L.CHAT_SEARCH)
	images.search = search

	images.cells = {}
	for index = 1, PerPage() do
		local column, row = (index - 1) % LAYOUT.columns, math.floor((index - 1) / LAYOUT.columns)
		local cell = CreateFrame("Button", nil, images, "BackdropTemplate")
		cell:SetSize(LAYOUT.cell, LAYOUT.cell)
		cell:SetPoint("TOPLEFT", LAYOUT.pad + column * (LAYOUT.cell + LAYOUT.cellGap), -(2 * LAYOUT.pad + LAYOUT.searchHeight + row * (LAYOUT.cell + LAYOUT.cellGap)))
		cell:SetBackdrop(EDGE)
		cell:SetBackdropColor(0, 0, 0, 0.6)
		cell.texture = cell:CreateTexture(nil, "ARTWORK")
		cell.texture:SetPoint("TOPLEFT", 2, -2)
		cell.texture:SetPoint("BOTTOMRIGHT", -2, 2)
		cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		cell:SetScript("OnClick", function(self) PickImage(self.icon) end)
		images.cells[index] = cell
	end

	local previous = CreateFrame("Button", nil, images)
	previous:SetSize(20, 20)
	previous:SetPoint("BOTTOMLEFT", LAYOUT.pad, LAYOUT.pad - 2)
	previous:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	previous:SetScript("OnClick", function() MoveSelection(-PerPage()) end)
	local following = CreateFrame("Button", nil, images)
	following:SetSize(20, 20)
	following:SetPoint("BOTTOMRIGHT", -LAYOUT.pad, LAYOUT.pad - 2)
	following:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	following:SetScript("OnClick", function() MoveSelection(PerPage()) end)
	images.pageText = images:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	images.pageText:SetPoint("BOTTOM", 0, LAYOUT.pad + 2)
end

-- ========= Lists: sayings and presets =======================================
-- A scrolling list of rows, each an optional icon and a line of text.
local function ListPicker(name, width)
	local picker = Picker(width, LAYOUT.listRows * LAYOUT.listRow + 2 * LAYOUT.pad)
	pickers[name] = picker
	local scroll = CreateFrame("ScrollFrame", nil, picker, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LAYOUT.pad, -LAYOUT.pad)
	scroll:SetPoint("BOTTOMRIGHT", -(LAYOUT.pad + 18), LAYOUT.pad)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(width - 2 * LAYOUT.pad - 18)
	content:SetHeight(1)
	scroll:SetScrollChild(content)
	picker.content, picker.rows, picker.scroll = content, {}, scroll
	return picker
end

-- Fills a list picker: entries are { icon, text, heading, onClick, onRightClick, color }.
-- A list picker as tall as its entries, up to listRows (then it scrolls),
-- with picker.below of room under the list (the effects grid); the
-- scrollbar only when it scrolls.
local function SizeList(picker, count)
	local most = picker.maxRows or LAYOUT.listRows
	picker.count = count
	local scrolls = count > most
	local below = picker.below or 0
	local rows = math.max(1, math.min(count, most))
	picker:SetHeight(rows * LAYOUT.listRow + 2 * LAYOUT.pad + below)
	local scrollRoom = scrolls and 18 or 0
	picker.scroll:SetPoint("BOTTOMRIGHT", -(LAYOUT.pad + scrollRoom), LAYOUT.pad + below)
	if picker.scroll.ScrollBar then picker.scroll.ScrollBar:SetShown(scrolls) end
	picker.content:SetWidth(picker:GetWidth() - 2 * LAYOUT.pad - scrollRoom)
end

local function FillList(picker, entries)
	picker.maxRows = nil -- as many as it wants; Place cuts it to the screen
	SizeList(picker, #entries)
	local width = picker.content:GetWidth()
	for index, entry in ipairs(entries) do
		local row = picker.rows[index]
		if not row then
			row = CreateFrame("Button", nil, picker.content)
			row:SetHeight(LAYOUT.listRow)
			row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row.icon = row:CreateTexture(nil, "ARTWORK")
			row.icon:SetSize(LAYOUT.listRow - 4, LAYOUT.listRow - 4)
			row.icon:SetPoint("LEFT", 2, 0)
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
			row.text:SetPoint("RIGHT", -2, 0)
			row.text:SetJustifyH("LEFT")
			row.text:SetWordWrap(false)
			row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
			picker.rows[index] = row
		end
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, -(index - 1) * LAYOUT.listRow)
		row:SetWidth(width)
		row.icon:SetTexture(entry.icon)
		row.icon:SetShown(entry.icon ~= nil)
		row.text:SetText(entry.text)
		row.text:SetTextColor(unpack(entry.color or (entry.heading and COLORS.heading) or COLORS.saying))
		row:SetEnabled(not entry.heading)
		row:SetScript("OnClick", function(_, button)
			if button == "RightButton" then
				if entry.onRightClick then entry.onRightClick() end
			elseif entry.onClick then
				entry.onClick()
			end
		end)
		row:Show()
	end
	for index = #entries + 1, #picker.rows do
		picker.rows[index]:Hide()
	end
	picker.content:SetHeight(math.max(1, #entries * LAYOUT.listRow))
	if picker:IsShown() then Place(picker) end
end

-- Where a picker opens: above the bar when it fits, else below when that
-- fits, else on the roomier side, a list cut to fit there (it scrolls). It
-- never leaves the screen. KekChat's arrow points the way its list opened.
local SCREEN_MARGIN = 8

local function Room()
	local scale, screen = bar:GetEffectiveScale(), UIParent:GetEffectiveScale()
	local screenTop = (UIParent:GetTop() or 768) * screen
	local top, bottom = (bar:GetTop() or 0) * scale, (bar:GetBottom() or 0) * scale
	return (screenTop - top) / scale - SCREEN_MARGIN, bottom / scale - SCREEN_MARGIN
end

function Place(picker)
	if not bar then return end
	local above, below = Room()
	local height = picker:GetHeight()
	if picker.count and height > math.max(above, below) then
		local room = math.max(above, below) - 2 * LAYOUT.pad - (picker.below or 0)
		picker.maxRows = math.max(1, math.floor(room / LAYOUT.listRow))
		SizeList(picker, picker.count)
		height = picker:GetHeight()
	end
	local up = height <= above or (height > below and above >= below)
	picker:ClearAllPoints()
	if up then
		picker:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -4, 4)
	else
		picker:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -4, -4)
	end
	if picker == pickers.presets and ChatView.readyArrow then
		ChatView.readyArrow:SetTexCoord(0, 1, up and 0.5 or 0, up and 0 or 0.5)
	end
end

-- ========= Typing to pick ===================================================
-- The box suggests sayings, effects and images for the word typed
-- (chat.lua, Suggest); space, Tab or Enter takes the highlighted one, the
-- arrows move it, Enter on an empty box sends. The word is never sent.
local suggestions, highlighted = {}, 1

local function ApplySuggestion(entry)
	if not entry then return end
	if entry.kind == "image" then
		for _, picked in ipairs(ChatView.icons) do
			if picked == entry.icon then return end
		end
		if #ChatView.icons >= ns.ParticleRules.maxImages then
			table.remove(ChatView.icons, 1)
		end
		ChatView.icons[#ChatView.icons + 1] = entry.icon
	elseif entry.kind == "effect" then
		ChatView.effect = entry.id
	elseif entry.kind == "saying" then
		ChatView.saying = entry.id
	elseif entry.kind == "clear" then
		ChatView.saying = nil
	end
	DrawBar()
end

local SUGGEST_ICONS = { saying = "Interface\\Icons\\INV_Misc_Note_01" }

local function FillSuggestions()
	local entries = {}
	for index, entry in ipairs(suggestions) do
		local icon = entry.icon or (entry.path and ("Interface\\Icons\\" .. entry.path)) or SUGGEST_ICONS[entry.kind]
		local text = entry.text or ""
		if entry.kind == "effect" then text = text .. "  |cff999999" .. L.CHAT_EFFECT_WORD .. "|r" end
		if entry.kind == "image" then text = "|cff999999" .. L.CHAT_IMAGE_WORD .. "|r" end
		entries[index] = {
			icon = icon,
			text = (index == highlighted and "|cffffd100> |r" or "") .. text,
			color = entry.kind == "clear" and COLORS.muted or (entry.kind == "effect" and COLORS.effect) or nil,
			onClick = function()
				ApplySuggestion(entry)
				compose:SetText("")
				ClosePickers()
			end,
		}
	end
	FillList(pickers.suggest, entries)
	pickers.suggest:SetShown(#entries > 0)
end

local function Suggest(text)
	suggestions = ns.Chat:Suggest(text)
	if text:match("^%s*$") and ChatView.saying then
		table.insert(suggestions, 1, { kind = "clear", text = L.CHAT_NO_SAYING })
	end
	highlighted = 1
	for name, picker in pairs(pickers) do
		if name ~= "suggest" then picker:Hide() end
	end
	FillSuggestions()
end

-- Takes the highlighted suggestion for what is typed, and clears the box.
local function TakeSuggestion()
	local entry = suggestions[highlighted]
	if entry then
		ApplySuggestion(entry)
	elseif compose:GetText():match("%S") then
		ChatView:Say(L.CHAT_NO_MATCH)
	end
	compose:SetText("")
	Suggest("")
end

-- One press, one message: a second press within debounce seconds (a
-- double-click) does nothing.
local lastPress = 0
local function Pressed()
	local now = GetTime()
	if now - lastPress < LAYOUT.debounce then
		return false
	end
	lastPress = now
	return true
end

local function SendNow()
	if not Pressed() then return end
	local ok, problem = ns.Chat:Send(ChatView.icons, ChatView.saying, ChatView.effect)
	if not ok then
		ChatView:Say(problem)
	end
	ChatView:WatchTimeout()
end

local function BuildCompose(left, right)
	compose = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
	compose:SetHeight(LAYOUT.bar - 4)
	compose:SetPoint("LEFT", left, "RIGHT", LAYOUT.barGap + 6, 0)
	compose:SetPoint("RIGHT", right, "LEFT", -LAYOUT.barGap, 0)
	compose:SetAutoFocus(false)
	compose:SetAltArrowKeyMode(false)
	compose:SetMaxLetters(30)
	compose.Instructions = compose:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	compose.Instructions:SetPoint("LEFT", 2, 0)
	compose.Instructions:SetPoint("RIGHT", -2, 0)
	compose.Instructions:SetJustifyH("LEFT")
	compose.Instructions:SetWordWrap(false)
	compose:SetScript("OnTextChanged", function(self, byUser)
		local text = self:GetText()
		self.Instructions:SetShown(text == "")
		if not byUser then return end
		if text:match("%s$") then
			self:SetText((text:gsub("%s+$", "")))
			TakeSuggestion() -- space takes the highlighted suggestion
		else
			Suggest(text)
		end
	end)
	compose:SetScript("OnTabPressed", TakeSuggestion)
	compose:SetScript("OnEnterPressed", function(self)
		if self:GetText():match("%S") then
			TakeSuggestion()
		else
			ClosePickers()
			SendNow()
		end
	end)
	compose:SetScript("OnArrowPressed", function(_, key)
		if #suggestions == 0 then return end
		if key == "UP" then highlighted = (highlighted - 2) % #suggestions + 1 end
		if key == "DOWN" then highlighted = highlighted % #suggestions + 1 end
		FillSuggestions()
	end)
	compose:SetScript("OnEditFocusGained", function(self) Suggest(self:GetText()) end)
	compose:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		ClosePickers()
		self:ClearFocus()
	end)
end

local function PresetEntry(preset)
	local effect = preset.effect and ns.ChatEffectById[preset.effect]
	local text = SayingText(preset.saying) or L.CHAT_NO_SAYING
	if effect then
		text = text .. "  |cffffd100" .. effect.label .. "|r"
	end
	if #preset.icons > 1 then
		text = ("x%d  "):format(#preset.icons) .. text
	end
	return {
		icon = preset.icons[1],
		text = text,
		onClick = preset.own == nil and function()
			ClosePickers()
			if not Pressed() then return end
			local ok, problem = ns.Chat:Send(preset.icons, preset.saying, preset.effect)
			if not ok then ChatView:Say(problem) end
			ChatView:WatchTimeout()
		end or function()
			ChatView.icons = {}
			for _, icon in ipairs(preset.icons) do ChatView.icons[#ChatView.icons + 1] = icon end
			ChatView.saying, ChatView.effect = preset.saying, preset.effect
			DrawBar()
			ClosePickers()
		end,
		onRightClick = preset.own and function()
			ns.Chat:DeletePreset(preset.own)
		end or nil,
	}
end

-- KekChat's quick chats (the KekChat button) or the player's own saves (the
-- book, with Custom KekChat), each in its own picker. A quick chat sends as
-- soon as it is clicked; a save loads into the bar to change first. Effects
-- are played on cards, from the stamp picker (ui\stamps.lua).
-- The KekChat button's list: your saved KekChats (chat.lua; one click sends
-- one). They are made in the editor, from Settings (ui\kek-editor.lua).
local function KekEntries()
	local entries = {}
	local list = ns.Chat:KekMessages()
	for index = 1, ns.ChatRules.maxMessages do
		local message = list[index]
		if message then
			local sound = message.sound and ns.KekSoundById[message.sound]
			local effect = message.effect and ns.ChatEffectById[message.effect]
			local extra = {}
			if effect then extra[#extra + 1] = effect.label end
			if sound then extra[#extra + 1] = sound.label end
			local text = message.text or ""
			if #extra > 0 then text = text .. "  |cffffd100" .. table.concat(extra, ", ") .. "|r" end
			entries[#entries + 1] = {
				icon = message.icon,
				text = text,
				onClick = function()
					ClosePickers()
					if not Pressed() then return end
					local ok, problem = ns.Chat:SendKek(index)
					if not ok then ChatView:Say(problem) end
					ChatView:WatchTimeout()
				end,
			}
		end
	end
	-- None saved: where to make them (Settings, KekChat).
	if #entries == 0 then
		entries[1] = { text = L.KEK_NONE, color = COLORS.muted }
	end
	return entries
end

local function FillPresets(own)
	if not own then
		FillList(pickers.presets, KekEntries())
		return
	end
	local entries = {}
	for _, preset in ipairs(ns.Chat:Presets()) do
		if (preset.own ~= nil) == own then
			entries[#entries + 1] = PresetEntry(preset)
		end
	end
	if own and #entries == 0 then
		entries[1] = { text = L.CHAT_SAVES_NONE, color = COLORS.muted }
	end
	FillList(own and pickers.saves or pickers.presets, entries)
end

-- ========= Building the bar =================================================
local function BarButton(width, onClick, tip, tipLine)
	local button = CreateFrame("Button", nil, bar, "BackdropTemplate")
	button:SetSize(width, LAYOUT.bar)
	button:SetBackdrop(EDGE)
	button:SetBackdropColor(unpack(COLORS.barButton))
	button:SetBackdropBorderColor(unpack(COLORS.barEdge))
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tip)
		if tipLine then GameTooltip:AddLine(tipLine, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

local function TextButton(width, text, onClick, tip, tipLine)
	local button = BarButton(width, onClick, tip, tipLine)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.label:SetPoint("CENTER")
	button.label:SetText(text)
	return button
end

local function BuildBar()
	bar = CreateFrame("Frame", nil, frame)
	bar:SetHeight(LAYOUT.bar)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)

	-- KekChat: the game's red button with an up arrow, as it was in
	-- KekChat's own window. It opens the quick chats (the ready-made messages
	-- and effects); one click sends one.
	local readyMade = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
	readyMade:SetSize(LAYOUT.readyWidth, LAYOUT.bar)
	readyMade:SetPoint("RIGHT")
	readyMade:SetText(L.FILTER_CHAT)
	readyMade:GetFontString():ClearAllPoints()
	readyMade:GetFontString():SetPoint("LEFT", 10, 0)
	readyMade.arrow = readyMade:CreateTexture(nil, "OVERLAY")
	-- The game's down arrow, flipped to point up: the list opens upward.
	-- Its art sits in the top half of its texture: show only that half.
	readyMade.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	readyMade.arrow:SetSize(16, 8)
	readyMade.arrow:SetTexCoord(0, 1, 0.5, 0)
	ChatView.readyArrow = readyMade.arrow -- flipped to where its list opened (Place)
	readyMade.arrow:SetPoint("RIGHT", -8, 0)
	readyMade:SetScript("OnClick", function() Toggle("presets", function() FillPresets(false) end) end)
	readyMade:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L.CHAT_PRESETS)
		GameTooltip:AddLine(L.CHAT_PRESETS_TIP, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	readyMade:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Left click picks an image; right click clears it.
	imageButton = BarButton(LAYOUT.bar, function(_, button)
		if button == "RightButton" then
			ChatView.icons = {}
			DrawBar()
			if images:IsShown() then DrawImages() end
			return
		end
		Toggle("image", function()
			images.search:SetText("")
			images.search:SetFocus()
			SearchImages()
		end)
	end, L.CHAT_IMAGE, L.CHAT_IMAGES_TIP)
	imageButton:SetPoint("LEFT")
	-- Like an action bar slot: the game's slot frame around it.
	imageButton.slot = imageButton:CreateTexture(nil, "OVERLAY")
	imageButton.slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	imageButton.slot:SetPoint("CENTER")
	imageButton.slot:SetSize(LAYOUT.bar * 1.75, LAYOUT.bar * 1.75)
	imageButton.texture = imageButton:CreateTexture(nil, "ARTWORK")
	imageButton.texture:SetPoint("TOPLEFT", 2, -2)
	imageButton.texture:SetPoint("BOTTOMRIGHT", -2, 2)
	imageButton.count = imageButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	imageButton.count:SetPoint("BOTTOMRIGHT", -1, 1)

	-- Your saves: the book, at the right end, beside Save.
	local saves = BarButton(LAYOUT.bar, function() Toggle("saves", function() FillPresets(true) end) end, L.CHAT_SAVES, L.CHAT_SAVES_TIP)
	saves:SetPoint("RIGHT", readyMade, "LEFT", -(LAYOUT.barGap + 4), 0)
	saves.texture = saves:CreateTexture(nil, "ARTWORK")
	saves.texture:SetPoint("TOPLEFT", 3, -3)
	saves.texture:SetPoint("BOTTOMRIGHT", -3, 3)
	saves.texture:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
	local presets = saves -- what Save sits beside

	local save = TextButton(LAYOUT.saveWidth, L.CHAT_SAVE, function()
		local ok, problem = ns.Chat:SavePreset(ChatView.icons, ChatView.saying, ChatView.effect)
		ChatView:Say(ok and L.CHAT_SAVED or problem, ok)
	end, L.CHAT_SAVE, L.CHAT_SAVE_TIP)
	save:SetPoint("RIGHT", presets, "LEFT", -LAYOUT.barGap, 0)

	local send = TextButton(LAYOUT.sendWidth, L.CHAT_SEND_BUTTON, SendNow, L.CHAT_SEND_BUTTON)
	ChatView.sendButton = send
	send:SetPoint("RIGHT", save, "LEFT", -LAYOUT.barGap, 0)

	BuildCompose(imageButton, send)
	-- Building your own (Custom KekChat in Settings): everything but KekChat.
	ChatView.custom = { imageButton, compose, send, save, saves }

	BuildImagePicker()
	ListPicker("suggest", 220)
	ListPicker("presets", 260)
	-- Under the quick chats, the effects (ui\effect-grid.lua): one plays over
	-- the feed for everyone and leaves nothing behind.
	local quick = pickers.presets
	local effects = ns.EffectGrid.Build(quick, 260 - 2 * LAYOUT.pad, L.EFFECTS_HEADING, L.CHAT_EFFECTS_TIP, function(preset)
		ClosePickers()
		if not Pressed() then return end
		local ok, problem = ns.Stamping:SendFeedEffect(preset.id)
		if not ok then ChatView:Say(problem) end
		ChatView:WatchTimeout()
	end)
	if effects.height > 0 then
		effects:SetPoint("BOTTOMLEFT", LAYOUT.pad, LAYOUT.pad)
		quick.below = effects.height + LAYOUT.pad -- the list sits right above it (SizeList)
	end
	ListPicker("saves", 240)
	DrawBar()
	ChatView:ShowCustom()
end

-- Custom KekChat (Settings, off by default): the images, the typing box,
-- Send, Save and your saves, beside KekChat. Off, KekChat's quick chats are
-- the whole bar.
function ChatView:ShowCustom()
	local on = self:CustomOn()
	for _, part in ipairs(self.custom or {}) do
		part:SetShown(on)
	end
	if not on then
		for name, picker in pairs(pickers) do
			if name ~= "presets" then picker:Hide() end
		end
	end
end

-- ========= Where it shows ===================================================
-- The bar's frame, for the panel to place under the feed (ui\panel.lua).
function ChatView:Frame()
	return frame
end

-- Lines the bar's right end up with the filter row's under it (ui\panel.lua).
function ChatView:SetRightInset(inset)
	if not bar then return end
	bar:SetPoint("BOTTOMRIGHT", -inset, 0)
end

function ChatView:SetShown(shown)
	if not frame then return end
	if not shown then ClosePickers() end
	frame:SetShown(shown)
end

local function Build()
	local host = ns.Panel:GetFrame()
	if not host then return end
	frame = CreateFrame("Frame", ns.Globals.frame("Chat"), host)
	frame:SetHeight(ChatView.height)
	frame:SetFrameLevel(host:GetFrameLevel() + 30) -- the button sits over the rows' edge
	-- Clicks pass through to the rows and filter icons around the buttons.
	frame:EnableMouse(false)
	frame:Hide()

	BuildBar()
	for _, picker in pairs(pickers) do
		picker:SetFrameStrata("DIALOG") -- over the feed's cards
	end

	-- Why something did not go, or what just happened: just above the bar.
	status = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	status:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, LAYOUT.pad + 2)
	status:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, LAYOUT.pad + 2)
	status:SetJustifyH("LEFT")
	status:SetHeight(12)
	status:SetShadowOffset(1, -1)

	ns.Panel:PlaceComposer() -- the panel drew before the bar existed
end

Bus:On("READY", Build)
Bus:On("SETTING_CHANGED", function(id)
	if CUSTOM and id == "kekChatCustom" then
		ChatView:ShowCustom()
		ns.Panel:PlaceComposer() -- on the line, or in a row of its own
	end
end)

Bus:On("CHAT_PRESETS_CHANGED", function()
	if pickers.saves and pickers.saves:IsShown() then
		FillPresets(true)
	end
	if pickers.presets and pickers.presets:IsShown() then
		FillPresets(false)
	end
end)

-- A saying that does something: what it does on this screen.
Bus:On("CHAT_EFFECT", function(effect)
	if effect == "confetti" and ns.IsEnabled("confetti") then
		ns.Confetti:Burst()
	end
end)

-- A message with an effect arrived (chat.lua): play it over the feed.
Bus:On("CHAT_PLAY", function(message)
	ChatView:PlayEffect(message)
end)

-- While your chat is timed out (chat.lua), Send counts down and it and the
-- effect tiles are greyed out; they come back when the time is up.
function ChatView:WatchTimeout()
	local send = self.sendButton
	if not send or self.watching then return end
	local function Update()
		local left = ns.Chat:TimeoutLeft()
		local out = left > 0
		send:SetEnabled(not out)
		send.label:SetText(out and ("%ds"):format(math.ceil(left)) or L.CHAT_SEND_BUTTON)
		send:SetAlpha(out and 0.5 or 1)
		if out then
			self.watching = true
			C_Timer.After(0.25, function()
				self.watching = false
				Update()
			end)
		end
	end
	Update()
end
