-- Stats tracker view (experimental: tracker.lua, docs\stats-tracker.md): a
-- small window with what a player did, today, this week or all time, drawn
-- from Tracker:View, section by section (data\tracker.lua says the sections,
-- labels and how each number reads). The player button steps through
-- everyone this client has numbers for, you first. /qp tracker opens it.
-- It owns frames only.
local _, ns = ...
local L = ns.L

local TrackerView = {}
ns.TrackerView = TrackerView

local LAYOUT = { width = 320, height = 440, pad = 10, header = 64, line = 16, heading = 22, tab = 22 }
local COLORS = { back = { 0.05, 0.04, 0.08, 0.97 }, edge = { 0.80, 0.65, 0.20, 1 }, heading = { 1, 0.82, 0 }, label = { 0.85, 0.85, 0.85 } }
local PERIODS = { { id = "today", label = L.TRACK_TODAY }, { id = "week", label = L.TRACK_WEEK }, { id = "all", label = L.TRACK_ALL } }

local frame, content, playerButton, sinceText
local tabs, lines = {}, {}
local state = { period = "all", player = nil }

-- A line: a label at the left and its value at the right, or a heading.
local function Line(index)
	local line = lines[index]
	if not line then
		line = {}
		line.label = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.label:SetJustifyH("LEFT")
		line.value = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.value:SetJustifyH("RIGHT")
		lines[index] = line
	end
	return line
end

function TrackerView:Refresh()
	if not frame or not frame:IsShown() then return end
	state.player = state.player or ns.MyName()
	playerButton:SetText(state.player)
	for _, tab in ipairs(tabs) do tab:SetEnabled(tab.period ~= state.period) end
	local view = ns.Tracker:View(state.player, state.period)
	sinceText:SetText(view.since and L.TRACK_SINCE:format(date("%b %d, %Y", view.since)) or L.TRACK_NOTHING)

	-- Sections, then your most killed creatures, as lines down the page.
	local items = {}
	for _, section in ipairs(view.sections) do
		items[#items + 1] = { heading = section.label }
		for _, row in ipairs(section.rows) do items[#items + 1] = row end
	end
	if #view.mobs > 0 then
		items[#items + 1] = { heading = L.TRACK_TOP_MOBS }
		for _, row in ipairs(view.mobs) do items[#items + 1] = row end
	end
	local y = 0
	for index, item in ipairs(items) do
		local line = Line(index)
		line.label:ClearAllPoints()
		line.value:ClearAllPoints()
		local height = item.heading and LAYOUT.heading or LAYOUT.line
		line.label:SetPoint("TOPLEFT", item.heading and 0 or 8, -y - (item.heading and 6 or 0))
		line.label:SetPoint("RIGHT", content, "RIGHT", -90, 0)
		line.value:SetPoint("TOPRIGHT", 0, -y)
		line.label:SetFontObject(item.heading and "GameFontNormal" or "GameFontHighlightSmall")
		line.label:SetTextColor(unpack(item.heading and COLORS.heading or COLORS.label))
		line.label:SetText(item.heading or item.label)
		line.value:SetText(item.text or "")
		line.label:Show()
		line.value:Show()
		y = y + height
	end
	for index = #items + 1, #lines do
		lines[index].label:Hide()
		lines[index].value:Hide()
	end
	content:SetHeight(math.max(1, y))
	frame.empty:SetShown(#items == 0)
end

local function Build()
	frame = CreateFrame("Frame", ns.Globals.frame("Tracker"), UIParent, "BackdropTemplate")
	frame:SetSize(LAYOUT.width, LAYOUT.height)
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

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LAYOUT.pad, -LAYOUT.pad)
	title:SetText(L.TRACK_TITLE)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	-- Whose: steps through everyone with numbers here, you first.
	playerButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	playerButton:SetSize(150, LAYOUT.tab)
	playerButton:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.pad + 26))
	playerButton:SetScript("OnClick", function()
		local players = ns.Tracker:Players()
		local at = 1
		for index, name in ipairs(players) do if name == state.player then at = index end end
		state.player = players[at % #players + 1]
		TrackerView:Refresh()
	end)

	-- When: today, this week, all time.
	local previous
	for index = #PERIODS, 1, -1 do
		local period = PERIODS[index]
		local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		tab:SetSize(52, LAYOUT.tab)
		if previous then tab:SetPoint("RIGHT", previous, "LEFT", -2, 0) else tab:SetPoint("TOPRIGHT", -LAYOUT.pad, -(LAYOUT.pad + 26)) end
		tab:SetText(period.label)
		tab.period = period.id
		tab:SetScript("OnClick", function()
			state.period = period.id
			TrackerView:Refresh()
		end)
		tabs[#tabs + 1] = tab
		previous = tab
	end

	sinceText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	sinceText:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.header + 2))

	local scroll = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.header + 18))
	scroll:SetPoint("BOTTOMRIGHT", -(LAYOUT.pad + 20), LAYOUT.pad)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(LAYOUT.width - 2 * LAYOUT.pad - 24, 1)
	scroll:SetScrollChild(content)

	frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	frame.empty:SetPoint("CENTER", scroll, "CENTER")
	frame.empty:SetWidth(LAYOUT.width - 40)
	frame.empty:SetText(L.TRACK_EMPTY)
end

function TrackerView:Toggle()
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
	self:Refresh()
end

-- Kept current while it is open: a minute's counting at a time.
C_Timer.NewTicker(5, function() TrackerView:Refresh() end)
