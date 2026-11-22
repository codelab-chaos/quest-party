-- Stamp view: what stamps look like on a feed card (stamps.lua is the model,
-- data\stamps.lua the list). The panel calls Build once per row frame and
-- Show for each row it draws.
--   right-click a card for the picker (ui\panel.lua calls Open)
--   each kind of stamp inked big across the card in its own spot, on a see-through plate,
--     with a count when repeated ("Cheers! x3"); the kind that just landed
--     (new or once more) flies in again, with its sound
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local StampView = {}
ns.StampView = StampView

local LAYOUT = {
	inkSize = 15, -- the stamp word's font size
	landSeconds = 0.28,
	landScale = 2.4, -- how big it starts as it comes down
	freshSeconds = 2, -- a stamp this new lands with its animation
	fadeSeconds = 1.2, -- how long fading away takes
	pickerColumns = 4,
	pickerCell = 44, -- each stamp's cell in the picker
	pickerEmblem = 34, -- its framed emblem
	pickerWord = 14, -- its word under it
	pickerPad = 8,
	pickerTop = 22, -- room at the top for the close button
	pickerClose = 24,
	pickerGap = 6, -- between cells
	pickerMute = 20, -- the line under the stamps: mute the card's player
	emblemInk = 27, -- an emblem stamp (no word) on a card
}

local COLORS = {
	plateTint = 0.30, -- the plate: the stamp's color darkened to this share
	plateAlpha = 0.70, -- and this see-through, so the card shows under it
	plateEdge = 0.85, -- its thin edge, in the stamp's color
	picker = { 0.05, 0.04, 0.08, 0.96 },
	pickerEdge = { 0.80, 0.65, 0.20, 1 },
}

local FONT = "Fonts\\FRIZQT__.TTF"

local fresh = {} -- card key -> when a stamp last landed on it, for the animation
local rowsByKey = {} -- card key -> the row last drawn for it (rows are reused)
local played = {} -- card key .. time -> true once its landing has played

-- ========= The picker =======================================================
local picker
local Options -- below: the lines about a card's player

local function ClosePicker()
	if picker then picker:Hide() end
end

local function BuildPicker()
	-- A child of the panel: it moves, hides and closes with the feed.
	local host = ns.Panel and ns.Panel.GetFrame and ns.Panel:GetFrame() or UIParent
	picker = CreateFrame("Frame", ns.Globals.frame("StampPicker"), host, "BackdropTemplate")
	picker:SetFrameStrata("DIALOG")
	picker:SetToplevel(true)
	picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	picker:SetBackdropColor(unpack(COLORS.picker))
	picker:SetBackdropBorderColor(unpack(COLORS.pickerEdge))
	picker:EnableMouse(true)
	picker:SetClampedToScreen(true)
	-- Closing: its X, Escape, or a click anywhere else.
	tinsert(UISpecialFrames, picker:GetName())
	local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
	close:SetSize(LAYOUT.pickerClose, LAYOUT.pickerClose)
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", ClosePicker)
	pcall(picker.RegisterEvent, picker, "GLOBAL_MOUSE_DOWN") -- a client without it: the X and Escape still close it
	picker:SetScript("OnEvent", function(self, event)
		if event == "GLOBAL_MOUSE_DOWN" and self:IsShown() and not self:IsMouseOver() then
			ClosePicker()
		end
	end)
	-- One grid of the stamps, each its emblem in a gold frame over its word.
	local cell = LAYOUT.pickerCell
	local columns = LAYOUT.pickerColumns
	picker.cells = {}
	for index, stamp in ipairs(ns.Stamps) do
		local button = CreateFrame("Button", nil, picker)
		button:SetSize(cell, cell + LAYOUT.pickerWord)
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		button:SetPoint("TOPLEFT", LAYOUT.pickerPad + column * (cell + LAYOUT.pickerGap), -(LAYOUT.pickerTop + row * (cell + LAYOUT.pickerWord + LAYOUT.pickerGap)))
		local frame = CreateFrame("Frame", nil, button, "BackdropTemplate")
		frame:SetSize(LAYOUT.pickerEmblem + 4, LAYOUT.pickerEmblem + 4)
		frame:SetPoint("TOP", 0, 0)
		frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		frame:SetBackdropColor(0, 0, 0, 0.6)
		frame:SetBackdropBorderColor(unpack(COLORS.pickerEdge))
		local icon = frame:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		ns.Look.StampEmblem(icon, stamp)
		local word = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		word:SetPoint("BOTTOM", 0, 0)
		word:SetText(stamp.text or stamp.label or "")
		word:SetTextColor(unpack(stamp.color))
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:GetHighlightTexture():SetAllPoints(frame)
		button.id = stamp.id
		picker.cells[#picker.cells + 1] = button
		button:SetScript("OnClick", function()
			local entry = picker.entry
			ClosePicker()
			if not entry then return end
			local ok, problem = ns.Stamping:Send(entry, stamp.id)
			if not ok and problem then ns.Print(problem) end
		end)
	end
	local rows = math.ceil(#ns.Stamps / columns)
	local width = 2 * LAYOUT.pickerPad + columns * cell + (columns - 1) * LAYOUT.pickerGap
	local stampsBottom = LAYOUT.pickerTop + rows * (cell + LAYOUT.pickerWord) + (rows - 1) * LAYOUT.pickerGap
	-- Under the stamps, KekChat's effects (ui\effect-grid.lua): one plays over
	-- this card on everyone's screen and leaves nothing behind.
	local effects = ns.EffectGrid.Build(picker, width - 2 * LAYOUT.pickerPad, L.EFFECTS_HEADING, L.STAMP_EFFECTS_TIP, function(preset)
		local entry = picker.entry
		ClosePicker()
		if not entry then return end
		local ok, problem = ns.Stamping:SendEffect(entry, preset.id)
		if not ok and problem then ns.Print(problem) end
	end)
	effects:SetPoint("TOPLEFT", LAYOUT.pickerPad, -(stampsBottom + LAYOUT.pickerGap))
	local effectsBottom = effects.height > 0 and (stampsBottom + LAYOUT.pickerGap + effects.height) or stampsBottom
	picker.width, picker.optionsTop = width, effectsBottom + 2
	-- Under the effects, lines about the card's player (not on your own):
	-- mute them; on a KekChat, block that message or all of theirs (chat.lua).
	-- Which show is up to Open (Options).
	local function Option(onClick)
		local line = CreateFrame("Button", nil, picker)
		line:SetHeight(LAYOUT.pickerMute)
		line.text = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		line.text:SetPoint("CENTER")
		line:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
		line:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
		line:SetScript("OnClick", function()
			local entry = picker.entry
			ClosePicker()
			if entry and entry.player then onClick(entry) end
		end)
		return line
	end
	picker.mute = Option(function(entry)
		local muted = ns.Chat:ToggleMute(entry.player)
		ns.Print((muted and L.CHAT_MUTED or L.CHAT_UNMUTED):format(entry.player))
	end)
	picker.blockText = Option(function(entry)
		local text = entry.data and entry.data.text
		local blocked = ns.Chat:IsBlocked(entry.player, text)
		ns.Chat:BlockText(entry.player, text, not blocked)
		ns.Print((blocked and L.KEK_UNBLOCKED_MESSAGE or L.KEK_BLOCKED_MESSAGE):format(entry.player))
	end)
	picker.blockAll = Option(function(entry)
		local blocked = ns.Chat:IsBlocked(entry.player)
		ns.Chat:BlockAll(entry.player, not blocked)
		ns.Print((blocked and L.KEK_UNBLOCKED_ALL or L.KEK_BLOCKED_ALL):format(entry.player))
	end)
	picker:SetScript("OnHide", function(self) self.entry = nil end)
	picker:Hide()
end

-- Closes the picker (the panel closing, say).
function StampView:Close()
	ClosePicker()
end

-- The picker's lines about the card's player, under the effects, and its
-- height to fit them: none on your own; mute on anyone else's; on their
-- KekChat, block that message (when it has words) or all of theirs.
function Options(entry)
	local lines = {}
	local player = entry.player
	if not ns.IsMe(player) then
		picker.mute.text:SetText((ns.Chat:IsMuted(player) and L.CHAT_UNMUTE_PLAYER or L.CHAT_MUTE_PLAYER):format(player))
		lines[#lines + 1] = picker.mute
		if entry.type == "chat" then
			local text = entry.data and entry.data.text
			if text then
				picker.blockText.text:SetText((ns.Chat:IsBlocked(player, text) and L.KEK_UNBLOCK_MESSAGE or L.KEK_BLOCK_MESSAGE):format(player))
				lines[#lines + 1] = picker.blockText
			end
			picker.blockAll.text:SetText((ns.Chat:IsBlocked(player) and L.KEK_UNBLOCK_ALL or L.KEK_BLOCK_ALL):format(player))
			lines[#lines + 1] = picker.blockAll
		end
	end
	for _, line in ipairs({ picker.mute, picker.blockText, picker.blockAll }) do line:Hide() end
	for index, line in ipairs(lines) do
		line:ClearAllPoints()
		local top = picker.optionsTop + (index - 1) * LAYOUT.pickerMute
		line:SetPoint("TOPLEFT", LAYOUT.pickerPad, -top)
		line:SetPoint("TOPRIGHT", -LAYOUT.pickerPad, -top)
		line:Show()
	end
	picker:SetSize(picker.width, picker.optionsTop + #lines * LAYOUT.pickerMute + LAYOUT.pickerPad)
end

-- Whether a frame is inside another (a feed card inside the panel).
local function Inside(frame, outer)
	while frame do
		if frame == outer then return true end
		frame = frame.GetParent and frame:GetParent()
	end
	return false
end

-- The picker for a feed card (a right-click on it).
function StampView:Open(row)
	return self:OpenFor(row.stampEntry, row)
end

-- The picker for an entry, opened from a frame showing it: a feed card in
-- the panel, or a drawer of the minimized dock (ui\dock.lua) while the
-- panel is hidden.
function StampView:OpenFor(entry, at)
	if not entry then return false end
	-- Done with this card (all your stamps on it): say so instead.
	local key = ns.Stamping:KeyFor(entry)
	if not ns.Stamping:May(key, ns.MyName()) then
		ns.Print(L.STAMP_DONE)
		return true
	end
	if not picker then BuildPicker() end
	picker.entry = entry
	Options(entry)
	-- The one you already put on it is greyed out.
	local _, used = ns.Stamping:Used(key, ns.MyName())
	for _, cell in ipairs(picker.cells or {}) do
		cell:SetEnabled(not used[cell.id])
		cell:SetAlpha(used[cell.id] and 0.35 or 1)
	end
	local panel = ns.Panel and ns.Panel.GetFrame and ns.Panel:GetFrame()
	picker:ClearAllPoints()
	if panel and panel:IsVisible() and Inside(at, panel) then
		-- Under the card, its right edge with the card's, held to the panel
		-- (the list redraws its cards, so not to the card itself).
		picker:SetParent(panel)
		picker:SetFrameStrata("DIALOG")
		local right, bottom = at.GetRight and at:GetRight(), at.GetBottom and at:GetBottom()
		local hostLeft, hostTop = panel:GetLeft(), panel:GetTop()
		if type(right) == "number" and type(bottom) == "number" and type(hostLeft) == "number" and type(hostTop) == "number" then
			picker:SetPoint("TOPRIGHT", panel, "TOPLEFT", right - hostLeft, bottom - hostTop - 2)
		else
			picker:SetPoint("CENTER", panel, "CENTER")
		end
	else
		-- From the dock: over the screen, just above the mouse.
		picker:SetParent(UIParent)
		picker:SetFrameStrata("DIALOG")
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		picker:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", x / scale, y / scale + 12)
	end
	picker:Show()
	picker:Raise()
	return true
end

-- A player's initials: "Mcdouble Whopper" is MW, "Bagoe" is B.
local function Initials(name)
	local letters = {}
	for word in tostring(name or "?"):gmatch("%S+") do
		letters[#letters + 1] = word:sub(1, 1):upper()
	end
	return table.concat(letters)
end

-- A color as the start of colored text.
local function Hex(r, g, b)
	return ("|cff%02x%02x%02x"):format(math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5))
end

-- The tooltip lines for a card: how to stamp it, and who has.
function StampView:Tip(row)
	if not row.stampEntry then return end
	-- A KekChat's words, whole: its row's title may cut them off.
	local words = row.stampEntry.type == "chat" and row.stampEntry.data and row.stampEntry.data.text
	if words then GameTooltip:AddLine(words, 1, 1, 1, true) end
	-- Where it happened, when its sender said (collectors\location.lua).
	local place = ns.Location.Describe(ns.Location.Read(row.stampEntry.data))
	if place then GameTooltip:AddLine(L.LOCATION_TIP:format(place), 1, 1, 1) end
	local done = not ns.Stamping:May(ns.Stamping:KeyFor(row.stampEntry), ns.MyName())
	GameTooltip:AddLine(done and L.STAMP_DONE or L.STAMP_RIGHT_CLICK, 0.75, 0.75, 1, true)
	for _, stamp in ipairs(row.stampList or {}) do
		local look = ns.StampById[stamp.id]
		if look then
			-- Who, by their initials in their own color; the stamp in its color.
			GameTooltip:AddLine(L.STAMP_BY:format(Hex(ns.PlayerColors:For(stamp.from)) .. Initials(stamp.from) .. "|r",
				Hex(unpack(look.color)) .. (look.text or look.label or look.id) .. "|r"))
		end
	end
end

-- ========= On a card ========================================================
-- Stamps spread along a card, right to left from its mark across to
-- LEFT_KEEP from its left edge (the avatar and the start of the title stay
-- clear), each at its own height. They are placed from the card's left edge
-- as if the card were LAID_WIDTH wide, so resizing the panel never moves them.
-- The height comes from the card and the stamp: the same on every redraw.
local LEFT_KEEP = 150
local LAID_WIDTH = 440
local MIN_LEFT = 40 -- stamps start no further left than this (clear of the avatar)
local MIN_SCALE = 0.5 -- the smallest stamps get on a narrow card
local STAMP_GAP = 6 -- between two stamps, packed
local MAX_RISE = 4 -- pixels up or down
local MAX_TILT = math.rad(35) -- each stamp's tilt, at most this either way
local SPREAD = 40 -- the most room between two stamps, past their widths

-- A number from 0 to 1 for a text, the same every time.
local function Hash(text)
	local value = 0
	for index = 1, #text do
		value = (value * 31 + text:byte(index)) % 1000003
	end
	return value / 1000003
end

-- The spots are from the left of the time and the row's mark, which sit at
-- its right edge (ui\\panel.lua): stamps never cover them.
local CLEAR_OF_MARK = 70

-- Where a stamp's impact plays: an area centered on its ink, over the panel
-- (not clipped to the row), one per row so impacts on two cards both show.
local function ImpactHost(row, ink)
	local over = ns.Panel and ns.Panel.GetFrame and ns.Panel:GetFrame()
	if not over then return nil end
	if not row.stampImpact then
		row.stampImpact = CreateFrame("Frame", nil, over)
		row.stampImpact:EnableMouse(false)
	end
	local host = row.stampImpact
	host:SetSize(ns.StampImpact.box[1], ns.StampImpact.box[2])
	host:ClearAllPoints()
	host:SetPoint("CENTER", ink, "CENTER")
	host:SetFrameLevel(row:GetFrameLevel() + 20)
	return host
end

-- The impact: KekChat's effect (picked when it was stamped) bursting from
-- the ink as it hits the card, when KekChat's effects are on.
local function Impact(row, ink, impact)
	if not impact or not ns.IsEnabled("chatEffects") then return end
	local host = ImpactHost(row, ink)
	if host then ns.ParticleView:Play(host, impact.effect, impact.icons) end
end

-- One inked word, in its own frame so it can grow as it lands.
local function Ink(row, index)
	row.stampInks = row.stampInks or {}
	local ink = row.stampInks[index]
	if ink then return ink end
	ink = CreateFrame("Frame", nil, row)
	ink:SetSize(120, 36)
	-- The plate: a see-through square in the stamp's color and a thin edge
	-- of four lines, all textures so they tilt with the word.
	ink.plate = ink:CreateTexture(nil, "BACKGROUND")
	ink.plate:SetColorTexture(1, 1, 1, 1)
	ink.edges = {}
	for side = 1, 4 do
		ink.edges[side] = ink:CreateTexture(nil, "BORDER")
		ink.edges[side]:SetColorTexture(1, 1, 1, 1)
	end
	ink:EnableMouse(false)
	ink.emblem = ink:CreateTexture(nil, "ARTWORK")
	ink.word = ink:CreateFontString(nil, "OVERLAY")
	ink.word:SetFont(FONT, LAYOUT.inkSize, "THICKOUTLINE")
	ink.word:SetPoint("CENTER")
	ink.land = ink:CreateAnimationGroup()
	local grow = ink.land:CreateAnimation("Scale")
	grow:SetScaleFrom(LAYOUT.landScale, LAYOUT.landScale)
	grow:SetScaleTo(1, 1)
	grow:SetDuration(LAYOUT.landSeconds)
	grow:SetSmoothing("IN")
	-- Fading away once its time is up (the Stamps fade slider).
	ink.fade = ink:CreateAnimationGroup()
	local away = ink.fade:CreateAnimation("Alpha")
	away:SetFromAlpha(1)
	away:SetToAlpha(0)
	away:SetDuration(LAYOUT.fadeSeconds)
	ink.fade:SetScript("OnFinished", function() ink:Hide() end)
	local appear = ink.land:CreateAnimation("Alpha")
	appear:SetFromAlpha(0)
	appear:SetToAlpha(1)
	appear:SetDuration(LAYOUT.landSeconds * 0.6)
	ink:Hide()
	row.stampInks[index] = ink
	return ink
end

function StampView:Build(row)
	row.stampInks = {}
	-- The card resized (the panel did): its stamps placed again to fit.
	row:HookScript("OnSizeChanged", function(card)
		if card.stampData then StampView:Show(card, card.stampData) end
	end)
end

-- Each kind of stamp on the card, inked in its spot, with its count when
-- repeated ("Cheers! x3"). The kind that just landed (new, or once more)
-- flies in again.
function StampView:Show(row, data)
	local key = data.kind == "feed" and data.stampKey or nil
	if key then rowsByKey[key] = row end -- where a card effect plays (CARD_EFFECT)
	row.stampData = data -- kept to place the stamps again on a resize
	row.stampEntry = key and data.entry or nil
	row.stampList = key and data.stamps or nil
	local tallies = key and ns.Stamping:Showing(key) or {}
	-- Measure each first, then spread them (oldest the rightmost).
	local fadeAfter, now = ns.Stamping.FadeAfter(), GetServerTime()
	local sizes, total = {}, 0
	for index, tally in ipairs(tallies) do
		local look = ns.StampById[tally.id]
		local ink = Ink(row, index)
		-- A worded stamp: "Cheers! x3". An emblem alone: "x3" beside it, if more.
		local words = look.text and (tally.count > 1 and L.STAMP_TALLY:format(look.text, tally.count) or look.text)
			or (tally.count > 1 and ("x" .. tally.count) or "")
		ink.word:SetText(words)
		local emblemSize = look.text and (LAYOUT.inkSize + 2) or LAYOUT.emblemInk
		local wordWidth = words ~= "" and math.ceil(ink.word:GetStringWidth() or 60) or 0
		local pad, gap = 6, wordWidth > 0 and 6 or 0
		local width = pad + emblemSize + gap + wordWidth + pad
		local height = math.max(LAYOUT.inkSize, emblemSize) + 6
		-- Its own tilt, the same every time; tilted, it takes this much of the
		-- card's width (its footprint), which is what is packed.
		local tilt = (Hash(key .. "~" .. tally.id) * 2 - 1) * MAX_TILT
		local footprint = width * math.abs(math.cos(tilt)) + height * math.abs(math.sin(tilt))
		sizes[index] = { emblem = emblemSize, word = wordWidth, pad = pad, gap = gap, width = width, height = height, tilt = tilt, footprint = footprint }
		total = total + sizes[index].footprint
	end
	-- Laid out on a card of a set width, from its left, so they stay put as
	-- the panel widens. Right to left from the mark, never on top of one
	-- another: spread out when there is room, packed when not, and all made
	-- smaller together when even packed they would not fit the card.
	local cardWidth = tonumber(row:GetWidth()) or 0
	local rowWidth = (cardWidth > 0 and cardWidth < LAID_WIDTH) and cardWidth or LAID_WIDTH
	local right = rowWidth - CLEAR_OF_MARK
	local needed = total + STAMP_GAP * math.max(0, #tallies - 1)
	local roomMost = math.max(40, rowWidth - CLEAR_OF_MARK - MIN_LEFT)
	local scale = needed > roomMost and math.max(MIN_SCALE, roomMost / needed) or 1
	local extra = 0 -- room added between stamps when there is plenty
	local roomSpread = rowWidth - CLEAR_OF_MARK - LEFT_KEEP
	if scale == 1 and #tallies > 1 and needed < roomSpread then
		extra = math.min(SPREAD, (roomSpread - needed) / (#tallies - 1))
	end
	local centers, cursor = {}, right
	for index, size in ipairs(sizes) do
		local width = size.footprint * scale
		centers[index] = cursor - width / 2
		cursor = cursor - width - (STAMP_GAP + extra) * scale
	end
	for index, tally in ipairs(tallies) do
		local look = ns.StampById[tally.id]
		local ink = Ink(row, index)
		local size = sizes[index]
		ink.fade:Stop()
		ink:SetAlpha(1)
		local seed = key .. "~" .. tally.id
		local rise = math.floor((Hash(seed .. "y") * 2 - 1) * MAX_RISE + 0.5)
		local center = centers[index]
		local plateHeight = size.height
		ink:SetSize(size.width, plateHeight)
		ink:ClearAllPoints()
		-- Made smaller as a whole; its offsets are in its own (scaled) units.
		ink:SetScale(scale)
		ink:SetPoint("CENTER", row, "LEFT", center / scale, rise / scale)
		ink:SetFrameLevel(row:GetFrameLevel() + 3 + index)
		-- Each part placed along the tilt about the stamp's middle, and
		-- turned with it, so the plate, its edge, the emblem and the word
		-- stay together.
		local tilt = size.tilt
		local cos, sin = math.cos(tilt), math.sin(tilt)
		local function Place(region, dx, dy, width, height)
			region:ClearAllPoints()
			region:SetPoint("CENTER", ink, "CENTER", dx * cos - dy * sin, dx * sin + dy * cos)
			if width then region:SetSize(width, height) end
			if region.SetRotation then pcall(region.SetRotation, region, tilt) end
		end
		local r, g, b = look.color[1], look.color[2], look.color[3]
		ink.plate:SetVertexColor(r * COLORS.plateTint, g * COLORS.plateTint, b * COLORS.plateTint, COLORS.plateAlpha)
		Place(ink.plate, 0, 0, size.width, plateHeight)
		local halfW, halfH = size.width / 2, plateHeight / 2
		local sides = { { 0, halfH, size.width, 1 }, { 0, -halfH, size.width, 1 }, { -halfW, 0, 1, plateHeight }, { halfW, 0, 1, plateHeight } }
		for side, at in ipairs(sides) do
			ink.edges[side]:SetVertexColor(r, g, b, COLORS.plateEdge)
			Place(ink.edges[side], at[1], at[2], at[3], at[4])
		end
		ns.Look.StampEmblem(ink.emblem, look)
		Place(ink.emblem, -halfW + size.pad + size.emblem / 2, 0, size.emblem, size.emblem)
		ink.word:SetTextColor(r, g, b, 1)
		ink.word:SetShown(size.word > 0)
		Place(ink.word, halfW - size.pad - size.word / 2, 0)
		ink:Show()
		local stamp = key .. "@" .. tally.id .. "@" .. tostring(tally.time) .. "@" .. tally.count
		-- Its time up: it fades away, and the card is drawn again without it.
		ink.showing = stamp
		-- One timer per stamp: the list redraws often (and every frame of a
		-- resize), and each redraw must not start another.
		if fadeAfter and ink.fadeFor ~= stamp then
			ink.fadeFor = stamp
			C_Timer.After(fadeAfter - (now - (tally.time or now)), function()
				if ink.showing == stamp and ink:IsShown() then
					ink.fade:Play()
					C_Timer.After(LAYOUT.fadeSeconds + 0.05, function()
						if ns.Panel and ns.Panel.Refresh then ns.Panel:Refresh() end
					end)
				end
			end)
		end
		-- This kind just landed: it flies in again, once per landing.
		local landed = fresh[key]
		if landed and landed.id == tally.id and GetTime() - landed.at <= LAYOUT.freshSeconds and not played[stamp] then
			played[stamp] = true
			ink.land:Stop()
			ink.land:Play()
			-- It hits the card as the landing ends.
			local impact = landed.impact
			C_Timer.After(LAYOUT.landSeconds, function()
				if ink:IsVisible() then Impact(row, ink, impact) end
			end)
		end
	end
	for index = #tallies + 1, #row.stampInks do
		row.stampInks[index].showing = nil
		row.stampInks[index].fadeFor = nil
		row.stampInks[index]:Hide()
	end
end

-- A stamp landed: its kind flies in on its card when next drawn, and as it
-- hits, KekChat's effect and sound, picked at random (Stamping.Impact). The
-- sound plays even when the card is not in view.
Bus:On("STAMPED", function(key, stamp)
	local impact = ns.Stamping.Impact(stamp.id)
	fresh[key] = { id = stamp.id, at = GetTime(), impact = impact }
	if impact and impact.sound then
		C_Timer.After(LAYOUT.landSeconds, function() ns.PlaySound(impact.sound) end)
	end
	if ns.Panel and ns.Panel.Refresh then ns.Panel:Refresh() end
end)

-- An effect played (stamps.lua), from a card's picker or KekChat's list: one
-- way for both, with its sound, when KekChat's effects are on. Over the whole
-- panel, as KekChat's; on a card in view, the panel from its top down to the
-- card's bottom, so a fountain rises from the card to the top and rain lands
-- on it.
Bus:On("CARD_EFFECT", function(key, presetId)
	if not ns.IsEnabled("chatEffects") then return end
	local preset = ns.Chat:EffectPreset(presetId)
	local effect = preset and ns.ChatEffectById[preset.effect]
	if not effect then return end
	local panel = ns.Panel and ns.Panel.GetFrame and ns.Panel:GetFrame()
	if not (panel and panel:IsVisible()) then return end
	local over = panel
	local row = rowsByKey[key]
	local top, bottom = panel:GetTop(), row and row:GetBottom()
	if row and row:IsVisible() and row.stampData and row.stampData.stampKey == key
		and type(top) == "number" and type(bottom) == "number" and top - bottom > 0 then
		if not row.cardEffect then
			row.cardEffect = CreateFrame("Frame", nil, panel)
			row.cardEffect:EnableMouse(false)
		end
		over = row.cardEffect
		over:ClearAllPoints()
		over:SetPoint("TOPLEFT", panel, "TOPLEFT")
		over:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
		over:SetHeight(top - bottom)
	end
	local saying = preset.saying and ns.SayingById[preset.saying]
	ns.ParticleView:Play(over, effect, preset.icons, saying and saying.text)
	if effect.sound then ns.PlaySound(effect.sound) end
end)

-- The Stamps fade switch: cards drawn again.
Bus:On("SETTING_CHANGED", function(id)
	if id == "stampFade" and ns.Panel and ns.Panel.Refresh then ns.Panel:Refresh() end
end)
