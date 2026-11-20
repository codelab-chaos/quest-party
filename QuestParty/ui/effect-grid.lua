-- Effect grid: KekChat's effects (chat.lua, EffectPresets) as a grid of icons
-- under a heading, each named on hover. One component for both places they
-- are played from: a card's stamp picker (ui\stamps.lua) and KekChat's list
-- (ui\chat.lua). Only what a click does differs: onPick(preset).
-- It owns frames only.
local _, ns = ...

local EffectGrid = {}
ns.EffectGrid = EffectGrid

local LAYOUT = {
	cell = 26, -- an effect's icon
	gap = 4,
	heading = 16, -- the line over them
}
local EDGE_COLOR = { 0.80, 0.65, 0.20, 1 }
local EDGE = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

-- Builds a grid in parent, width wide, under heading; hint is a line on each
-- effect's tooltip, under its name. Place it by its
-- TOPLEFT; grid.height says how tall it is (0, and hidden, with no effects).
function EffectGrid.Build(parent, width, heading, hint, onPick)
	local grid = CreateFrame("Frame", nil, parent)
	local effects = ns.Chat:EffectPresets()
	local step = LAYOUT.cell + LAYOUT.gap
	local perRow = math.max(1, math.floor((width + LAYOUT.gap) / step))
	local title = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	title:SetPoint("TOPLEFT")
	title:SetText(heading)
	for index, preset in ipairs(effects) do
		local button = CreateFrame("Button", nil, grid, "BackdropTemplate")
		button:SetSize(LAYOUT.cell, LAYOUT.cell)
		local column, row = (index - 1) % perRow, math.floor((index - 1) / perRow)
		button:SetPoint("TOPLEFT", column * step, -(LAYOUT.heading + row * step))
		button:SetBackdrop(EDGE)
		button:SetBackdropColor(0, 0, 0, 0.6)
		button:SetBackdropBorderColor(unpack(EDGE_COLOR))
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexture(preset.icon or preset.icons[1])
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(preset.label)
			if hint then GameTooltip:AddLine(hint, 1, 1, 1, true) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
		button:SetScript("OnClick", function() onPick(preset) end)
	end
	local rows = math.ceil(#effects / perRow)
	grid.height = #effects > 0 and (LAYOUT.heading + rows * step - LAYOUT.gap) or 0
	grid:SetSize(width, math.max(1, grid.height))
	grid:SetShown(#effects > 0)
	return grid
end
