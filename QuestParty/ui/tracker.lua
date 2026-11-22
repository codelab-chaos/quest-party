-- The Stats tab (tracker.lua, docs\stats-tracker.md): what a player did,
-- today, this week or all time, in the panel where the feed's list would be.
-- Data driven: Tracker:View says the sections and rows (data\tracker.lua says
-- the categories, labels and how each number reads), and each item is drawn
-- by the renderer for its kind (RENDER below). The player button steps through
-- everyone this client has numbers for, you first. It owns frames only.
local _, ns = ...
local L = ns.L

local StatsView = {}
ns.StatsView = StatsView

local LAYOUT = { pad = 6, controls = 24, since = 18, line = 18, heading = 26, indent = 10, scrollbar = 20, edge = 4, gap = 12, period = 50 }
local COLORS = {
	heading = { 1, 0.82, 0 },
	rule = { 0.80, 0.65, 0.20, 0.35 },
	label = { 0.85, 0.85, 0.85 },
	value = { 1, 1, 1 },
	compare = { 0.65, 0.85, 1 }, -- Quest Party's number beside the game's
	column = { 0.75, 0.75, 0.75 },
	stripe = { 1, 1, 1, 0.04 },
}
local PERIODS = { { id = "today", label = L.TRACK_TODAY }, { id = "week", label = L.TRACK_WEEK }, { id = "all", label = L.TRACK_ALL } }

local frame, scroll, content, playerButton, sinceText, empty
local tabs, lines = {}, {}
local state = { period = "all", player = nil }

-- ========= The model: what to draw, as a flat list of items =================
-- { kind = "heading", label, columns? } then { kind = "stat", label, text,
-- compare? } rows; the most killed creatures as "stat" rows under their own
-- heading. A section with columns (From WoW) titles its two values.
local function Items(view)
	local items = {}
	for _, section in ipairs(view.sections) do
		items[#items + 1] = { kind = "heading", label = section.label, columns = section.columns }
		for index, row in ipairs(section.rows) do
			items[#items + 1] = { kind = "stat", label = row.label, text = row.text, compare = row.compare, odd = index % 2 == 1 }
		end
	end
	if #view.mobs > 0 then
		items[#items + 1] = { kind = "heading", label = L.TRACK_TOP_MOBS }
		for index, row in ipairs(view.mobs) do
			items[#items + 1] = { kind = "stat", label = row.label, text = row.text, odd = index % 2 == 1 }
		end
	end
	return items
end

-- ========= Renderers: one per kind ==========================================
-- Each sets a line's words, fonts and colours for its item at y (pixels
-- down) and returns how tall it is. Where the numbers go across is worked out
-- after, from the widest number in each column (Place, below).
local RENDER = {
	heading = function(line, item, y)
		line.label:SetFontObject("GameFontNormal")
		line.label:SetTextColor(unpack(COLORS.heading))
		line.label:SetText(item.label)
		-- Column titles, over the values: the game's at the right, ours beside it.
		local columns = item.columns
		line.value:SetFontObject("GameFontDisableSmall")
		line.value:SetText(columns and columns[1] or "")
		line.other:SetFontObject("GameFontDisableSmall")
		line.other:SetText(columns and columns[2] or "")
		line.top = y + 6
		line.rule:SetPoint("TOPLEFT", 0, -(y + 22))
		line.rule:SetPoint("TOPRIGHT", 0, -(y + 22))
		line.rule:Show()
		line.stripe:Hide()
		line.indent = 0
		return LAYOUT.heading
	end,
	stat = function(line, item, y)
		line.label:SetFontObject("GameFontHighlight")
		line.label:SetTextColor(unpack(COLORS.label))
		line.label:SetText(item.label)
		line.value:SetFontObject("GameFontHighlight")
		line.value:SetTextColor(unpack(COLORS.value))
		line.value:SetText(item.text)
		line.other:SetFontObject("GameFontHighlight")
		line.other:SetTextColor(unpack(COLORS.compare))
		line.other:SetText(item.compare or "")
		line.top = y + 2
		line.stripe:SetPoint("TOPLEFT", 0, -y)
		line.stripe:SetPoint("TOPRIGHT", 0, -y)
		line.stripe:SetShown(item.odd)
		line.rule:Hide()
		line.indent = LAYOUT.indent
		return LAYOUT.line
	end,
}

local function Line(index)
	local line = lines[index]
	if not line then
		line = {}
		line.stripe = content:CreateTexture(nil, "BACKGROUND")
		line.stripe:SetHeight(LAYOUT.line)
		line.stripe:SetColorTexture(unpack(COLORS.stripe))
		line.rule = content:CreateTexture(nil, "ARTWORK")
		line.rule:SetHeight(1)
		line.rule:SetColorTexture(unpack(COLORS.rule))
		line.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line.label:SetJustifyH("LEFT")
		line.label:SetWordWrap(false)
		line.value = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line.value:SetJustifyH("RIGHT")
		line.value:SetTextColor(unpack(COLORS.value))
		line.other = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		line.other:SetJustifyH("RIGHT")
		lines[index] = line
	end
	return line
end

local function Hide(line)
	line.label:Hide()
	line.value:Hide()
	line.other:Hide()
	line.rule:Hide()
	line.stripe:Hide()
end

function StatsView:Draw()
	if not frame or not frame:IsShown() then return end
	state.player = state.player or ns.MyName()
	playerButton:SetText(state.player)
	for _, tab in ipairs(tabs) do tab:SetEnabled(tab.period ~= state.period) end
	local view = ns.Tracker:View(state.player, state.period)
	sinceText:SetText(view.since and L.TRACK_SINCE:format(date("%b %d, %Y", view.since)) or L.TRACK_NOTHING)

	content:SetWidth(math.max(1, scroll:GetWidth()))
	local items = Items(view)
	-- Words first, then the widest number in each column, then where all go.
	local widest = { value = 0, other = 0 }
	local y = 0
	for index, item in ipairs(items) do
		local line = Line(index)
		for _, part in ipairs({ line.label, line.value, line.other, line.rule, line.stripe }) do part:ClearAllPoints() end
		line.label:Show()
		line.value:Show()
		line.other:Show()
		y = y + RENDER[item.kind](line, item, y)
		widest.value = math.max(widest.value, line.value:GetStringWidth() or 0)
		widest.other = math.max(widest.other, line.other:GetStringWidth() or 0)
	end
	for index, item in ipairs(items) do
		local line = lines[index]
		local right = -LAYOUT.edge
		line.value:SetPoint("TOPRIGHT", right, -line.top)
		local labelRight = right - (line.value:GetStringWidth() or 0) - LAYOUT.gap
		-- A compared row (and its section's titles): ours right-justified in
		-- its own column, just left of the game's.
		if item.compare or item.columns then
			local otherRight = right - widest.value - LAYOUT.gap
			line.other:SetPoint("TOPRIGHT", otherRight, -line.top)
			labelRight = otherRight - widest.other - LAYOUT.gap
		end
		line.label:SetPoint("TOPLEFT", line.indent, -line.top)
		line.label:SetPoint("RIGHT", content, "RIGHT", labelRight, 0)
	end
	for index = #items + 1, #lines do Hide(lines[index]) end
	content:SetHeight(math.max(1, y))
	empty:SetShown(#items == 0)
end

-- Takes the list's place in the panel, top pixels down, inset from the sides.
function StatsView:Show(top, inset)
	if not frame then self:Build() end
	local host = ns.Panel:GetFrame()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -top)
	frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -inset, inset)
	frame:SetFrameLevel(host:GetFrameLevel() + 5)
	frame:Show()
	self:Draw()
end

function StatsView:Hide()
	if frame then frame:Hide() end
end

function StatsView:Build()
	local host = ns.Panel:GetFrame()
	if not host or frame then return end
	frame = CreateFrame("Frame", nil, host)
	frame:Hide()

	-- Whose: steps through everyone with numbers here, you first.
	playerButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	playerButton:SetHeight(LAYOUT.controls)
	playerButton:SetPoint("TOPLEFT", LAYOUT.pad, -LAYOUT.pad)
	playerButton:SetScript("OnClick", function()
		local players = ns.Tracker:Players()
		local at = 1
		for index, name in ipairs(players) do if name == state.player then at = index end end
		state.player = players[at % #players + 1]
		StatsView:Draw()
	end)

	-- When: today, this week, all time.
	local previous
	for index = #PERIODS, 1, -1 do
		local period = PERIODS[index]
		local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		tab:SetSize(LAYOUT.period, LAYOUT.controls)
		if previous then tab:SetPoint("RIGHT", previous, "LEFT", -2, 0) else tab:SetPoint("TOPRIGHT", -LAYOUT.pad, -LAYOUT.pad) end
		tab:SetText(period.label)
		tab.period = period.id
		tab:SetScript("OnClick", function()
			state.period = period.id
			StatsView:Draw()
		end)
		tabs[#tabs + 1] = tab
		previous = tab
	end

	playerButton:SetPoint("RIGHT", previous, "LEFT", -6, 0)
	local name = playerButton:GetFontString()
	if name then
		name:SetPoint("LEFT", 8, 0)
		name:SetPoint("RIGHT", -8, 0)
		name:SetWordWrap(false)
	end
	local below = LAYOUT.pad + LAYOUT.controls + 4
	sinceText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sinceText:SetPoint("TOPLEFT", LAYOUT.pad, -below)
	sinceText:SetPoint("RIGHT", -LAYOUT.pad, 0)
	sinceText:SetJustifyH("LEFT")
	sinceText:SetWordWrap(false)

	scroll = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LAYOUT.pad, -(below + LAYOUT.since))
	scroll:SetPoint("BOTTOMRIGHT", -(LAYOUT.pad + LAYOUT.scrollbar), LAYOUT.pad)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:SetScript("OnSizeChanged", function() StatsView:Draw() end)

	empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER", scroll, "CENTER")
	empty:SetText(L.TRACK_EMPTY)
end

-- Kept current while it shows: the tracker adds up time each minute.
C_Timer.NewTicker(5, function() StatsView:Draw() end)
