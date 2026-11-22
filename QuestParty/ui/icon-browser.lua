-- Icon browser: pick any of the game's icons. An icon is a number (a file
-- ID), and showing one is like showing any, so this pages through them all:
-- with nothing typed, every icon the game lists (as the macro icon picker
-- does); with words, ours whose names or tags hold them (data\chat.lua,
-- IconCatalog). A click picks one and closes it. Used by the KekChat editor
-- (ui\kek-editor.lua). It owns frames only.
local _, ns = ...
local L = ns.L

local IconBrowser = {}
ns.IconBrowser = IconBrowser

local LAYOUT = { columns = 8, rows = 6, cell = 32, gap = 3, pad = 8, search = 22, footer = 22 }
local COLORS = { back = { 0.05, 0.04, 0.08, 0.97 }, edge = { 0.80, 0.65, 0.20, 1 }, cell = { 0.35, 0.30, 0.18, 1 } }

local frame, search, cells, pageText
local results, page, onPick = {}, 1, nil

local function PerPage()
	return LAYOUT.columns * LAYOUT.rows
end

local function Pages()
	return math.max(1, math.ceil(#results / PerPage()))
end

local function Draw()
	local first = (page - 1) * PerPage()
	for index, cell in ipairs(cells) do
		local icon = results[first + index]
		cell.icon = icon
		cell.texture:SetTexture(icon)
		cell:SetShown(icon ~= nil)
	end
	pageText:SetText(L.ICONS_PAGE:format(page, Pages(), #results))
end

local function Find()
	local words = search:GetText() or ""
	results = words:match("%S") and ns.Chat:Search(words) or ns.Chat:AllIcons()
	page = 1
	Draw()
end

local function Turn(step)
	page = math.max(1, math.min(Pages(), page + step))
	Draw()
end

local function Build()
	local width = 2 * LAYOUT.pad + LAYOUT.columns * (LAYOUT.cell + LAYOUT.gap) - LAYOUT.gap
	local height = 3 * LAYOUT.pad + LAYOUT.search + LAYOUT.rows * (LAYOUT.cell + LAYOUT.gap) - LAYOUT.gap + LAYOUT.footer
	frame = CreateFrame("Frame", ns.Globals.frame("IconBrowser"), UIParent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta) Turn(delta > 0 and -1 or 1) end)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	frame:SetBackdropColor(unpack(COLORS.back))
	frame:SetBackdropBorderColor(unpack(COLORS.edge))
	frame:Hide()
	tinsert(UISpecialFrames, frame:GetName())

	search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	search:SetHeight(LAYOUT.search)
	search:SetPoint("TOPLEFT", LAYOUT.pad + 4, -LAYOUT.pad)
	search:SetPoint("TOPRIGHT", -(LAYOUT.pad + 22), -LAYOUT.pad)
	search:SetAutoFocus(false)
	search.Instructions = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	search.Instructions:SetPoint("LEFT", 2, 0)
	search.Instructions:SetText(L.ICONS_SEARCH)
	search:SetScript("OnTextChanged", function(self)
		self.Instructions:SetShown(self:GetText() == "")
		Find()
	end)
	search:SetScript("OnEscapePressed", function() frame:Hide() end)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", 2, 2)

	cells = {}
	for index = 1, PerPage() do
		local column, row = (index - 1) % LAYOUT.columns, math.floor((index - 1) / LAYOUT.columns)
		local cell = CreateFrame("Button", nil, frame, "BackdropTemplate")
		cell:SetSize(LAYOUT.cell, LAYOUT.cell)
		cell:SetPoint("TOPLEFT", LAYOUT.pad + column * (LAYOUT.cell + LAYOUT.gap), -(2 * LAYOUT.pad + LAYOUT.search + row * (LAYOUT.cell + LAYOUT.gap)))
		cell:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		cell:SetBackdropColor(0, 0, 0, 0.6)
		cell:SetBackdropBorderColor(unpack(COLORS.cell))
		cell.texture = cell:CreateTexture(nil, "ARTWORK")
		cell.texture:SetPoint("TOPLEFT", 2, -2)
		cell.texture:SetPoint("BOTTOMRIGHT", -2, 2)
		cell.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		cell:SetScript("OnClick", function(self)
			local pick = onPick
			frame:Hide()
			if pick and self.icon then pick(self.icon) end
		end)
		cells[index] = cell
	end

	local back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	back:SetSize(24, 20)
	back:SetPoint("BOTTOMLEFT", LAYOUT.pad, LAYOUT.pad - 2)
	back:SetText("<")
	back:SetScript("OnClick", function() Turn(-1) end)
	local forward = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	forward:SetSize(24, 20)
	forward:SetPoint("BOTTOMRIGHT", -LAYOUT.pad, LAYOUT.pad - 2)
	forward:SetText(">")
	forward:SetScript("OnClick", function() Turn(1) end)
	pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pageText:SetPoint("BOTTOM", 0, LAYOUT.pad + 2)
end

-- Opens it beside a frame; pick(iconID) is called with the one clicked.
function IconBrowser:Open(beside, pick)
	if not frame then Build() end
	onPick = pick
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", beside, "TOPRIGHT", 6, 0)
	search:SetText("")
	Find()
	frame:Show()
	frame:Raise()
end

function IconBrowser:Close()
	if frame then frame:Hide() end
end
