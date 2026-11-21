-- Opacity: how see-through Quest Party is (the Opacity slider), and what the
-- On hover setting does while the mouse is over it: nothing, solid, or
-- fainter. Plain numbers; ui\fade.lua applies them to the panel.
local _, ns = ...

local Opacity = {}
ns.Opacity = Opacity

-- How much of the slider's opacity Fainter on hover keeps, and the least
-- it ever goes to.
Opacity.fainter = 0.5
Opacity.least = 0.2 -- the least it ever is, as the Opacity slider's bottom

-- The alpha (0 to 1) for this opacity (a percent), hover mode (an id from
-- ns.HoverOpacity) and whether the mouse is over Quest Party.
function Opacity.Target(percent, mode, hovered)
	local base = math.max(0, math.min(100, percent or 100)) / 100
	if not hovered or mode == "off" then return base end
	if mode == "solid" then return 1 end
	if mode == "fainter" then return math.max(Opacity.least, base * Opacity.fainter) end
	return base
end

-- The settings now: the alpha for whether the mouse is over it.
function Opacity.Now(hovered)
	local mode = ns.HoverOpacity[ns.GetSlider("hoverOpacity") or 0]
	return Opacity.Target(ns.GetSlider("opacity"), mode and mode.id, hovered)
end
