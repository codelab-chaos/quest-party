-- Fade: Quest Party's opacity (opacity.lua) on the panel, and so on
-- everything that hangs from it: the side bar, the player card, KekChat's
-- bar and lists. With On hover set, it eases toward its hover opacity while
-- the mouse is over any of them, and back when it leaves.
-- It owns frames only.
local _, ns = ...
local Bus = ns.Bus

local SPEED = 4 -- alpha a second, easing to the target
local CHECK = 0.1 -- seconds between looks at where the mouse is

local driver = CreateFrame("Frame")
local current, target = 1, 1

-- The panel, looked up each time: it is built on READY too, maybe after this
-- file's own READY handler has run.
local function Host()
	return ns.Panel and ns.Panel.GetFrame and ns.Panel:GetFrame()
end

-- Whether the mouse is over Quest Party: the panel, or any frame of it (the
-- side bar and card sit outside the panel, but hang from it).
-- By what the mouse is on, not where it is: the opacity slider or Settings
-- over the panel are not Quest Party, so its opacity shows true while set.
local function Hovered(host)
	if not host:IsVisible() then return false end
	if not (GetMouseFoci or GetMouseFocus) then return host:IsMouseOver() end
	local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus() }
	for _, focus in ipairs(foci or {}) do
		local frame = focus
		while frame do
			if frame == host then return true end
			frame = frame.GetParent and frame:GetParent()
		end
	end
	return false
end

local function Step(_, elapsed)
	local host = Host()
	if not host then return end
	local delta = SPEED * elapsed
	if math.abs(target - current) <= delta then
		current = target
		driver:SetScript("OnUpdate", nil)
	else
		current = current + (target > current and delta or -delta)
	end
	host:SetAlpha(current)
end

local function Aim(jump)
	local host = Host()
	if not host then return end
	target = ns.Opacity.Now(Hovered(host))
	if jump then
		current = target
		host:SetAlpha(current)
	end
	if current ~= target then driver:SetScript("OnUpdate", Step) end
end

Bus:On("READY", function()
	-- After every READY handler, the panel's included.
	C_Timer.After(0, function() Aim(true) end)
	-- Where the mouse is, now and then, only while On hover does something.
	C_Timer.NewTicker(CHECK, function()
		if (ns.GetSlider("hoverOpacity") or 0) ~= 0 then Aim() end
	end)
end)

Bus:On("SLIDER_CHANGED", function(id)
	if id == "opacity" or id == "hoverOpacity" then Aim(true) end
end)
