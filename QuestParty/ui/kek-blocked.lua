-- KekChat's blocked list (chat.lua, kekBlocks): who and what you have blocked,
-- each with Unblock, in the KekChat editor (ui\kek-editor.lua places it). As
-- tall as what is in it: one short line when nobody is blocked. Kept current
-- as blocks change; onResize is told its new height. It owns frames only.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local KekBlocked = {}
ns.KekBlocked = KekBlocked

local LAYOUT = { line = 20, shown = 6, unblock = 70 }

local area, none, more, onResize
local lines = {}
local height = LAYOUT.line

-- Every block as a line, sorted: { player, text?, label }.
local function Items()
	local items = {}
	for player, block in pairs(ns.db.kekBlocks or {}) do
		if block.all then items[#items + 1] = { player = player, label = L.KEK_BLOCKED_ALL_LINE:format(player) } end
		for text in pairs(block.texts or {}) do
			items[#items + 1] = { player = player, text = text, label = L.KEK_BLOCKED_TEXT_LINE:format(player, text) }
		end
	end
	table.sort(items, function(a, b) return a.label < b.label end)
	return items
end

function KekBlocked:Refresh()
	if not area then return end
	local items = Items()
	none:SetShown(#items == 0)
	for index, line in ipairs(lines) do
		local item = items[index]
		line.item = item
		line:SetShown(item ~= nil)
		if item then line.label:SetText(item.label) end
	end
	more:SetShown(#items > #lines)
	more:SetText(L.KEK_BLOCKED_MORE:format(#items - #lines))
	-- As tall as its lines (and the "more" line), or one line for "nobody".
	local shown = math.min(#items, #lines) + (#items > #lines and 1 or 0)
	height = math.max(1, shown) * LAYOUT.line
	area:SetHeight(height)
	if onResize then onResize(height) end
end

function KekBlocked:Height()
	return height
end

-- Builds the list in parent, from top (pixels down) across width; resized
-- is called with its height whenever that changes. Returns its height now.
function KekBlocked:Build(parent, top, left, width, resized)
	onResize = resized
	area = CreateFrame("Frame", nil, parent)
	area:SetPoint("TOPLEFT", left, -top)
	area:SetSize(width, LAYOUT.line)
	none = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	none:SetPoint("TOPLEFT")
	none:SetText(L.KEK_BLOCKED_NONE)
	for index = 1, LAYOUT.shown do
		local line = CreateFrame("Frame", nil, area)
		line:SetHeight(LAYOUT.line)
		line:SetPoint("TOPLEFT", 0, -(index - 1) * LAYOUT.line)
		line:SetPoint("TOPRIGHT", 0, -(index - 1) * LAYOUT.line)
		line.unblock = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
		line.unblock:SetSize(LAYOUT.unblock, 18)
		line.unblock:SetPoint("RIGHT")
		line.unblock:SetText(L.KEK_UNBLOCK)
		line.unblock:SetScript("OnClick", function()
			local item = line.item
			if not item then return end
			if item.text then ns.Chat:BlockText(item.player, item.text, false) else ns.Chat:BlockAll(item.player, false) end
		end)
		line.label = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		line.label:SetPoint("LEFT")
		line.label:SetPoint("RIGHT", line.unblock, "LEFT", -8, 0)
		line.label:SetJustifyH("LEFT")
		line.label:SetWordWrap(false)
		lines[index] = line
	end
	more = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	more:SetPoint("TOPLEFT", 0, -LAYOUT.shown * LAYOUT.line)
	self:Refresh()
	return height
end

Bus:On("KEK_BLOCKS_CHANGED", function() KekBlocked:Refresh() end)
