-- The view switch: for a tab with more than one view (data\filters.lua,
-- views), a row of buttons over them, one per view, the shown one pressed
-- (Fuel | Stats). ui\panel.lua places it and says what was picked. It owns
-- frames only.
local _, ns = ...

local ViewSwitch = {}
ns.ViewSwitch = ViewSwitch

ViewSwitch.HEIGHT = 26 -- what it takes from the top of the tab's area
local LAYOUT = { button = 72, height = 20, gap = 2 }

local frame
local buttons = {}

-- Shows views ({ id, label }) in host, top pixels down, inset from the left;
-- chosen is pressed; pick(id) when another is clicked.
function ViewSwitch:Show(host, top, inset, views, chosen, pick)
	if not frame then
		frame = CreateFrame("Frame", nil, host)
		frame:SetHeight(LAYOUT.height)
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", host, "TOPLEFT", inset, -top)
	frame:SetPoint("RIGHT", host, "RIGHT", -inset, 0)
	frame:SetFrameLevel(host:GetFrameLevel() + 6)
	for index, view in ipairs(views) do
		local button = buttons[index]
		if not button then
			button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			button:SetSize(LAYOUT.button, LAYOUT.height)
			button:SetPoint("LEFT", (index - 1) * (LAYOUT.button + LAYOUT.gap), 0)
			buttons[index] = button
		end
		button:SetText(view.label)
		-- Pressed: the one shown can not be clicked.
		button:SetEnabled(view.id ~= chosen)
		button:SetScript("OnClick", function() pick(view.id) end)
		button:Show()
	end
	for index = #views + 1, #buttons do buttons[index]:Hide() end
	frame:Show()
end

function ViewSwitch:Hide()
	if frame then frame:Hide() end
end
