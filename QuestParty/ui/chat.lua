-- Chat view: Quest Party chat (chat.lua, docs\chat.md), drawn in the panel's
-- Chat tab or popped out beside the feed. A list of messages over a chat bar:
--   [ready made] [images] [type to pick] [Send] [Save] [your saves]
-- and over it the effects strip: preset effects, one click to send.
-- Images pop in as they arrive; an effect plays them (and a worded one its
-- saying's words) as particles (ui\particles.lua) with its sound; click a
-- message's images to replay it.
-- Nobody types words of their own. Right-click a message to mute its sender.
-- It owns frames only.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local ChatView = { popped = false, icons = {}, effect = nil, saying = nil }
ns.ChatView = ChatView

local LAYOUT = {
	poppedWidth = 300,
	pad = 6,
	rowHeight = 58, -- a message with an image: the name line, then the image
	lineHeight = 40, -- a message with only a saying
	systemHeight = 20, -- a notice from this client
	debounce = 0.5, -- a second press this soon is the same press
	image = 36, -- each of a message's images
	imageGap = 4,
	popSeconds = 0.35, -- how long an image takes to pop in
	bar = 24, -- the chat bar's height
	barGap = 3,
	sendWidth = 44,
	strip = 28, -- the effects strip: a row of preset tiles
	tile = 26,
	tileGap = 3,
	saveWidth = 40,
	popSize = 20,
	-- Pickers open above the bar.
	columns = 7, -- the image picker: a page of icons at a time
	rows = 4,
	cell = 34,
	cellGap = 3,
	searchHeight = 20,
	listRow = 22, -- a row in the saying and preset pickers
	listRows = 9, -- rows shown before they scroll
}

local COLORS = {
	back = { 0.05, 0.04, 0.08, 0.92 }, -- as the panel
	border = { 0.80, 0.65, 0.20, 1 },
	row = { 1, 1, 1, 0.04 },
	picker = { 0.03, 0.03, 0.05, 0.97 },
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

local frame, scrollBox, scrollBar, bar, popButton, emptyText, status
local imageButton, compose
local pickers = {} -- image, saying, presets: one open at a time

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

-- ========= Messages =========================================================
local function ShowImageTip(images)
	local data = images:GetParent().data
	if not data then return end
	GameTooltip:SetOwner(images, "ANCHOR_RIGHT")
	GameTooltip:SetText(L.CHAT_DECAL_TIP:format(ns.ColorName(data.player, data.class), date("%H:%M", data.time or 0)))
	local effect = data.effect and ns.ChatEffectById[data.effect]
	if effect then
		GameTooltip:AddLine(effect.label, 1, 0.82, 0)
	end
	GameTooltip:AddLine(L.CHAT_REPLAY_TIP, 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

-- Plays a message's effect, if it has one and effects are on, over the chat
-- (or the panel when the chat is not showing), with its sound.
function ChatView:PlayEffect(message)
	local effect = message.effect and ns.ChatEffectById[message.effect]
	if not effect or not ns.IsEnabled("chatEffects") then
		return
	end
	local over = (frame and frame:IsVisible()) and frame or ns.Panel:GetFrame()
	if not (over and over:IsVisible()) then
		return
	end
	local saying = message.saying and ns.SayingById[message.saying]
	ns.ParticleView:Play(over, effect, message.icons or {}, saying and saying.text)
	if effect.sound then
		ns.PlaySound(effect.sound) -- at the Volume in Settings
	end
end

-- An image popping in: grows past its size and settles, fading in.
local function MakePop(images)
	local group = images:CreateAnimationGroup()
	local grow = group:CreateAnimation("Scale")
	if grow.SetScaleFrom then
		grow:SetScaleFrom(0.2, 0.2)
		grow:SetScaleTo(1.15, 1.15)
	else
		grow:SetFromScale(0.2, 0.2)
		grow:SetToScale(1.15, 1.15)
	end
	grow:SetDuration(LAYOUT.popSeconds * 0.7)
	grow:SetOrder(1)
	local settle = group:CreateAnimation("Scale")
	if settle.SetScaleFrom then
		settle:SetScaleFrom(1.15, 1.15)
		settle:SetScaleTo(1, 1)
	else
		settle:SetFromScale(1.15, 1.15)
		settle:SetToScale(1, 1)
	end
	settle:SetDuration(LAYOUT.popSeconds * 0.3)
	settle:SetOrder(2)
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(1)
	fade:SetDuration(LAYOUT.popSeconds * 0.5)
	fade:SetOrder(1)
	return group
end

-- Click a message's images: they pop in again, and its effect replays.
local function Replay(images)
	local data = images:GetParent().data
	if not data then return end
	images.pop:Stop()
	images.pop:Play()
	ChatView:PlayEffect(data)
end

-- Right-click a message: mute its sender, or unmute them.
local function ClickRow(row, button)
	if button ~= "RightButton" or not row.data or ns.IsMe(row.data.player) then
		return
	end
	local muted = ns.Chat:ToggleMute(row.data.player)
	ChatView:Say((muted and L.CHAT_MUTED or L.CHAT_UNMUTED):format(row.data.player), true)
end

local function InitRow(row, data)
	if not row.name then
		row.back = row:CreateTexture(nil, "BACKGROUND")
		row.back:SetAllPoints()
		row.back:SetColorTexture(unpack(COLORS.row))
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		row.name:SetPoint("TOPLEFT", 6, -4)
		row.time = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.time:SetPoint("TOPRIGHT", -6, -4)
		row.images = CreateFrame("Button", nil, row)
		row.images:SetHeight(LAYOUT.image)
		row.images:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 2, -3)
		row.images.textures = {}
		for index = 1, ns.ParticleRules.maxImages do
			local texture = row.images:CreateTexture(nil, "ARTWORK")
			texture:SetSize(LAYOUT.image, LAYOUT.image)
			texture:SetPoint("LEFT", (index - 1) * (LAYOUT.image + LAYOUT.imageGap), 0)
			row.images.textures[index] = texture
		end
		row.images.pop = MakePop(row.images)
		row.images:SetScript("OnEnter", ShowImageTip)
		row.images:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.images:SetScript("OnClick", Replay)
		row.saying = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.saying:SetJustifyH("LEFT")
		row.saying:SetWordWrap(false)
		row:EnableMouse(true)
		row:SetScript("OnMouseUp", ClickRow)
	end
	row.data = data
	row.time:SetText(date("%H:%M", data.time or 0))
	-- A notice from this client (a spammer's timeout): one grey line.
	if data.system then
		row.name:SetText("|cff999999" .. (data.text or "") .. "|r")
		row.images:Hide()
		row.saying:Hide()
		return
	end
	row.name:SetText(ns.ColorName(data.player, data.class))
	local icons = data.icons or {}
	row.images:SetShown(#icons > 0)
	row.images:SetWidth(math.max(1, #icons * (LAYOUT.image + LAYOUT.imageGap) - LAYOUT.imageGap))
	for index, texture in ipairs(row.images.textures) do
		texture:SetTexture(icons[index])
		texture:SetShown(icons[index] ~= nil)
	end
	local saying = data.saying and ns.SayingById[data.saying]
	row.saying:SetShown(saying ~= nil)
	row.saying:ClearAllPoints()
	if #icons > 0 then
		row.saying:SetPoint("LEFT", row.images, "RIGHT", 8, 0) -- beside the images
	else
		row.saying:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 2, -4)
	end
	row.saying:SetPoint("RIGHT", -6, 0)
	if saying then
		row.saying:SetText(saying.text)
		row.saying:SetTextColor(unpack(saying.effect and COLORS.effect or COLORS.saying))
	end
	-- New ones pop in, the first time they are drawn.
	if data.fresh then
		data.fresh = nil
		row.images.pop:Stop()
		row.images.pop:Play()
	end
end

local function RowHeight(data)
	if data.system then
		return LAYOUT.systemHeight
	end
	return data.icons and #data.icons > 0 and LAYOUT.rowHeight or LAYOUT.lineHeight
end

local function Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local messages = ns.Chat:VisibleMessages()
	local atEnd = not scrollBox:HasScrollableExtent() or scrollBox:IsAtEnd()
	scrollBox:SetDataProvider(CreateDataProvider(messages), ScrollBoxConstants.RetainScrollPosition)
	if atEnd then
		scrollBox:ScrollToEnd(true)
	end
	emptyText:SetShown(#messages == 0)
	ns.Chat:MarkRead()
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

local function Toggle(name, open)
	local picker = pickers[name]
	local wasShown = picker:IsShown()
	ClosePickers()
	if not wasShown then
		picker:Show()
		if open then open() end
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
	picker.content, picker.rows = content, {}
	return picker
end

-- Fills a list picker: entries are { icon, text, heading, onClick, onRightClick, color }.
local function FillList(picker, entries)
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
		onClick = function()
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

-- The ready-made presets (the arrow on the left) or the player's own saves
-- (the book on the right), each in its own picker.
local function FillPresets(own)
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

-- ========= The effects strip ================================================
-- Preset effects (chat.lua, EffectPresets) as a row of tiles over the bar,
-- paged with arrows at either end. One click sends one. A worded preset
-- shows a small gold "Aa": its saying falls with the images.
local strip

local function StripTiles()
	local width = strip:GetWidth() - 2 * (LAYOUT.tile + LAYOUT.tileGap)
	return math.max(1, math.floor((width + LAYOUT.tileGap) / (LAYOUT.tile + LAYOUT.tileGap)))
end

local function DrawStrip()
	local presets = ns.Chat:EffectPresets()
	local shown = StripTiles()
	strip.first = math.max(1, math.min(strip.first, math.max(1, #presets - shown + 1)))
	for index, tile in ipairs(strip.tiles) do
		local preset = index <= shown and presets[strip.first + index - 1] or nil
		tile.preset = preset
		tile:SetShown(preset ~= nil)
		if preset then
			tile.texture:SetTexture(preset.icons[1])
			tile.worded:SetShown(preset.saying ~= nil)
		end
	end
	strip.previous:SetEnabled(strip.first > 1)
	strip.following:SetEnabled(strip.first + shown - 1 < #presets)
end

local function ShowTileTip(tile)
	local preset = tile.preset
	if not preset then return end
	GameTooltip:SetOwner(tile, "ANCHOR_TOP")
	GameTooltip:SetText(preset.label)
	local effect = ns.ChatEffectById[preset.effect]
	GameTooltip:AddLine(effect and effect.label or "", 1, 0.82, 0)
	local saying = preset.saying and ns.SayingById[preset.saying]
	if saying then
		GameTooltip:AddLine(L.CHAT_EFFECTS_WORDED:format(saying.text), 1, 1, 1)
	end
	GameTooltip:AddLine(L.CHAT_EFFECTS_TIP, 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function BuildStrip()
	strip = CreateFrame("Frame", nil, frame)
	strip:SetHeight(LAYOUT.strip)
	strip:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 4)
	strip:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)
	strip.first = 1
	strip.previous = CreateFrame("Button", nil, strip)
	strip.previous:SetSize(LAYOUT.tile, LAYOUT.tile)
	strip.previous:SetPoint("LEFT")
	strip.previous:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	strip.previous:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
	strip.previous:SetScript("OnClick", function() strip.first = strip.first - StripTiles() DrawStrip() end)
	strip.following = CreateFrame("Button", nil, strip)
	strip.following:SetSize(LAYOUT.tile, LAYOUT.tile)
	strip.following:SetPoint("RIGHT")
	strip.following:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	strip.following:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
	strip.following:SetScript("OnClick", function() strip.first = strip.first + StripTiles() DrawStrip() end)
	strip.tiles = {}
	for index = 1, #ns.EffectPresets do
		local tile = CreateFrame("Button", nil, strip, "BackdropTemplate")
		tile:SetSize(LAYOUT.tile, LAYOUT.tile)
		tile:SetPoint("LEFT", strip.previous, "RIGHT", LAYOUT.tileGap + (index - 1) * (LAYOUT.tile + LAYOUT.tileGap), 0)
		tile:SetBackdrop(EDGE)
		tile:SetBackdropColor(0, 0, 0, 0.6)
		tile:SetBackdropBorderColor(unpack(COLORS.barEdge))
		tile.texture = tile:CreateTexture(nil, "ARTWORK")
		tile.texture:SetPoint("TOPLEFT", 2, -2)
		tile.texture:SetPoint("BOTTOMRIGHT", -2, 2)
		tile.worded = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tile.worded:SetPoint("BOTTOMRIGHT", -1, 1)
		tile.worded:SetText("Aa")
		tile:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		tile:SetScript("OnClick", function(self)
			if not self.preset or not Pressed() then return end
			local ok, problem = ns.Chat:SendEffectPreset(self.preset.id)
			if not ok then ChatView:Say(problem) end
			ChatView:WatchTimeout()
		end)
		tile:SetScript("OnEnter", ShowTileTip)
		tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
		strip.tiles[index] = tile
	end
	strip:SetScript("OnSizeChanged", DrawStrip)
end

local function BuildBar()
	bar = CreateFrame("Frame", nil, frame)
	bar:SetHeight(LAYOUT.bar)
	bar:SetPoint("BOTTOMLEFT", LAYOUT.pad, LAYOUT.pad)
	bar:SetPoint("BOTTOMRIGHT", -LAYOUT.pad, LAYOUT.pad)

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
	-- The ready-made presets: a big up arrow, at the left end.
	local readyMade = BarButton(LAYOUT.bar, function() Toggle("presets", function() FillPresets(false) end) end, L.CHAT_PRESETS, L.CHAT_PRESETS_TIP)
	readyMade:SetPoint("LEFT")
	readyMade.texture = readyMade:CreateTexture(nil, "ARTWORK")
	readyMade.texture:SetPoint("TOPLEFT", -3, 3)
	readyMade.texture:SetPoint("BOTTOMRIGHT", 3, -3)
	readyMade.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
	imageButton:SetPoint("LEFT", readyMade, "RIGHT", LAYOUT.barGap, 0)
	imageButton.texture = imageButton:CreateTexture(nil, "ARTWORK")
	imageButton.texture:SetPoint("TOPLEFT", 2, -2)
	imageButton.texture:SetPoint("BOTTOMRIGHT", -2, 2)
	imageButton.count = imageButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	imageButton.count:SetPoint("BOTTOMRIGHT", -1, 1)

	-- Your saves: the book, at the right end, beside Save.
	local saves = BarButton(LAYOUT.bar, function() Toggle("saves", function() FillPresets(true) end) end, L.CHAT_SAVES, L.CHAT_SAVES_TIP)
	saves:SetPoint("RIGHT")
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

	BuildImagePicker()
	ListPicker("suggest", 220)
	ListPicker("presets", 240)
	BuildStrip()
	ListPicker("saves", 240)
	DrawBar()
end

-- ========= Where it shows ===================================================
-- Puts the chat on a strata and level, and its parts just above it, the
-- pickers on top. Set every time it moves: docked it sits over the panel,
-- popped out it sits in the panel's group, below the panel (ui\party.lua).
local function SetLevels(strata, level)
	frame:SetFrameStrata(strata)
	frame:SetFrameLevel(level)
	for _, part in ipairs({ scrollBox, scrollBar, bar, strip, popButton }) do
		part:SetFrameStrata(strata)
		part:SetFrameLevel(level + 2)
	end
	for _, picker in pairs(pickers) do
		picker:SetFrameStrata(strata)
		picker:SetFrameLevel(level + 20)
	end
end

function ChatView:IsPopped()
	return self.popped == true
end

-- In the panel's Chat tab: over the list area, top given by the panel.
function ChatView:ShowDocked(top, inset)
	if self.popped or not frame then return end
	local host = ns.Panel:GetFrame()
	frame:SetParent(host)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -top)
	frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
	frame:SetBackdrop(nil)
	SetLevels(host:GetFrameStrata(), host:GetFrameLevel() + 5) -- over the panel, not behind it
	frame:Show()
	popButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	Refresh()
end

function ChatView:HideDocked()
	if not self.popped and frame then
		ClosePickers()
		frame:Hide()
	end
end

-- Beside the feed, where the player card goes (a card moves right of it):
-- as tall as the panel, right of the head drawer when it shows, or right
-- against the panel when nobody is there.
local DOCK_OVERLAP = 3 -- tucked under the edge it meets, as the drawer is

local function PlacePopped()
	local dock = ns.Party and ns.Party:Dock()
	local host = ns.Panel:GetFrame()
	local x = -DOCK_OVERLAP
	if dock and dock:IsShown() then
		x = x + dock:GetWidth() - DOCK_OVERLAP
	end
	frame:SetParent(host)
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", host, "TOPRIGHT", x, 0)
	frame:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", x, 0)
	frame:SetWidth(LAYOUT.poppedWidth)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(unpack(COLORS.back))
	frame:SetBackdropBorderColor(unpack(COLORS.border))
	frame:Show()
	popButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
	Refresh()
end

function ChatView:SetPopped(popped)
	self.popped = popped and true or false
	ns.charDb.chatPopped = self.popped
	ClosePickers()
	if self.popped then
		PlacePopped()
		if ns.charDb.filter == "chat" then
			ns.Panel:SelectFilter(ns.Tabs[1].id) -- the feed beside it
		end
	else
		frame:Hide()
		ns.Panel:SelectFilter("chat")
	end
	Bus:Fire("CHAT_POPPED", self.popped)
end

-- The panel, drawer and card come to the front together (ui\party.lua); a
-- popped chat goes with them.
function ChatView:Raise(strata, level)
	if frame and self.popped then
		SetLevels(strata, level)
	end
end

local function Build()
	local host = ns.Panel:GetFrame()
	if not host then return end
	frame = CreateFrame("Frame", ns.Globals.frame("Chat"), host, "BackdropTemplate")
	frame:EnableMouse(true)
	frame:Hide()

	popButton = CreateFrame("Button", nil, frame)
	popButton:SetSize(LAYOUT.popSize, LAYOUT.popSize)
	popButton:SetPoint("TOPRIGHT", -LAYOUT.pad, -LAYOUT.pad + 2)
	popButton:SetScript("OnClick", function() ChatView:SetPopped(not ChatView.popped) end)
	popButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ChatView.popped and L.CHAT_DOCK or L.CHAT_POP_OUT)
		GameTooltip:Show()
	end)
	popButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

	BuildBar()

	status = frame:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	status:SetPoint("BOTTOMLEFT", strip, "TOPLEFT", 0, 4)
	status:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", 0, 4)
	status:SetJustifyH("LEFT")
	status:SetHeight(12)

	scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	scrollBox:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.pad + LAYOUT.popSize + 2))
	scrollBox:SetPoint("BOTTOMRIGHT", strip, "TOPRIGHT", -14, 20)
	scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, data) return RowHeight(data) end)
	view:SetElementInitializer("Frame", InitRow)
	view:SetPadding(0, 0, 0, 0, 2)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

	emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER", scrollBox, "CENTER")
	emptyText:SetWidth(220)
	emptyText:SetText(L.CHAT_EMPTY)

	-- Players coming and going show and hide the drawer (ui\party.lua says
	-- when, once per change): the popped chat moves with it. Only moves: it
	-- must not set off another redraw.
	Bus:On("DRAWER_CHANGED", function()
		if ChatView.popped then
			PlacePopped()
		end
	end)
	if ns.charDb.chatPopped then
		C_Timer.After(0, function() ChatView:SetPopped(true) end)
	elseif ns.charDb.filter == "chat" then
		ns.Panel:Refresh() -- the panel drew before the chat existed
	end
end

Bus:On("READY", Build)
Bus:On("CHAT_CHANGED", Refresh)
Bus:On("CHAT_PRESETS_CHANGED", function()
	if pickers.presets and pickers.presets:IsShown() then
		FillPresets()
	end
end)

-- A saying that does something: what it does on this screen.
Bus:On("CHAT_EFFECT", function(effect)
	if effect == "confetti" and ns.IsEnabled("confetti") then
		ns.Confetti:Burst()
	end
end)

-- A message with an effect arrived (chat.lua): play it where chat is shown.
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
		for _, tile in ipairs(strip and strip.tiles or {}) do
			tile:SetEnabled(not out)
			tile:SetAlpha(out and 0.4 or 1)
		end
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
