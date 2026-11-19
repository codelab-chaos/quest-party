-- Game options: a Quest Party page in the game's own Options, under AddOns,
-- as other addons have. It only opens Quest Party's Settings (ui\panel.lua):
-- one place for settings, reached from where players look for them.
local _, ns = ...
local L = ns.L

ns.Bus:On("READY", function()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
		return -- a client without the game's options screen
	end
	local page = CreateFrame("Frame")
	local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(L.TITLE)
	title:SetTextColor(1, 0.82, 0)
	local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	open:SetText(L.GAME_OPTIONS_OPEN)
	open:SetSize(math.max(220, (open:GetFontString() and open:GetFontString():GetStringWidth() or 0) + 40), 26)
	open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	open:SetScript("OnClick", function()
		if SettingsPanel and HideUIPanel then HideUIPanel(SettingsPanel) end
		ns.Panel:OpenSettings()
	end)
	local category = Settings.RegisterCanvasLayoutCategory(page, L.TITLE)
	Settings.RegisterAddOnCategory(category)
end)
