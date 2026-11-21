-- Opacity slider: the title bar's opacity button opens this short upright
-- slider under it, to set Quest Party's opacity (the Opacity slider in
-- Settings, opacity.lua) live: top is solid, bottom the least. It stays solid
-- itself (a child of the screen, not the panel), and closes with Escape or a
-- click anywhere else. It owns frames only.
local _, ns = ...
local Bus = ns.Bus

local OpacitySlider = {}
ns.OpacitySlider = OpacitySlider

local LAYOUT = { width = 40, height = 140, track = 100, label = 16, pad = 6 }
local COLORS = { back = { 0.05, 0.04, 0.08, 0.96 }, edge = { 0.80, 0.65, 0.20, 1 } }

local pop, slider, label, owner
local syncing = false

local function Range()
	local setting = ns.SliderById.opacity
	return setting.min, setting.max, setting.step
end

-- The slider runs top to bottom; opacity runs the other way.
local function ToOpacity(value)
	local low, high = Range()
	return low + high - value
end

local function Show(value)
	label:SetText(("%d%%"):format(value))
	syncing = true
	slider:SetValue(ToOpacity(value))
	syncing = false
end

local function Build()
	pop = CreateFrame("Frame", ns.Globals.frame("OpacitySlider"), UIParent, "BackdropTemplate")
	pop:SetSize(LAYOUT.width, LAYOUT.height)
	pop:SetFrameStrata("DIALOG")
	pop:SetToplevel(true)
	pop:SetClampedToScreen(true)
	pop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	pop:SetBackdropColor(unpack(COLORS.back))
	pop:SetBackdropBorderColor(unpack(COLORS.edge))
	pop:EnableMouse(true)
	pop:Hide()
	tinsert(UISpecialFrames, pop:GetName())
	pcall(pop.RegisterEvent, pop, "GLOBAL_MOUSE_DOWN")
	pop:SetScript("OnEvent", function(self)
		if self:IsShown() and not self:IsMouseOver() and not (owner and owner:IsMouseOver()) then
			self:Hide()
		end
	end)

	label = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOP", 0, -LAYOUT.pad)

	slider = CreateFrame("Slider", nil, pop, "BackdropTemplate")
	slider:SetOrientation("VERTICAL")
	slider:SetSize(16, LAYOUT.track)
	slider:SetPoint("TOP", label, "BOTTOM", 0, -4)
	slider:SetBackdrop({ bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border", edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 } })
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Vertical")
	local low, high, step = Range()
	slider:SetMinMaxValues(low, high)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(true)
	slider:SetScript("OnValueChanged", function(_, value)
		if syncing then return end
		local set = ns.SetSlider("opacity", ToOpacity(value))
		if set then label:SetText(("%d%%"):format(set)) end
	end)
	slider:SetScript("OnMouseWheel", function(_, delta) OpacitySlider:Nudge(delta) end)
end

-- Opens it under a button (the title bar's), or closes it.
function OpacitySlider:Toggle(button)
	if not pop then Build() end
	if pop:IsShown() then
		pop:Hide()
		return
	end
	owner = button
	pop:ClearAllPoints()
	pop:SetPoint("TOP", button, "BOTTOM", 0, -4)
	Show(ns.GetSlider("opacity"))
	pop:Show()
	pop:Raise()
end

-- One step up (delta 1) or down (-1): the mouse wheel.
function OpacitySlider:Nudge(delta)
	local _, _, step = Range()
	ns.SetSlider("opacity", (ns.GetSlider("opacity") or 100) + (delta > 0 and step or -step))
end

function OpacitySlider:IsShown()
	return pop ~= nil and pop:IsShown()
end

-- Kept in step when Settings' slider moves it.
Bus:On("SLIDER_CHANGED", function(id, value)
	if id == "opacity" and pop and pop:IsShown() then Show(value) end
end)
