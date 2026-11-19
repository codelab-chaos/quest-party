-- Player colors: each player's own color from ns.PlayerPalette, the same in
-- every view (XP bar, portrait ring, Fuel). Given the first time a player is
-- seen and kept (ns.db.playerColors), choosing the color fewest players have,
-- so colors never shift as people come and go and a party rarely shares one.
local _, ns = ...

local Colors = {}
ns.PlayerColors = Colors

local function Saved()
	ns.db.playerColors = ns.db.playerColors or {}
	return ns.db.playerColors
end

-- The palette index for a player, given now if they have none.
function Colors:Index(name)
	local saved = Saved()
	if saved[name] and ns.PlayerPalette[saved[name]] then return saved[name] end
	local uses = {}
	for _, index in pairs(saved) do uses[index] = (uses[index] or 0) + 1 end
	local best
	for index = 1, #ns.PlayerPalette do
		if not best or (uses[index] or 0) < (uses[best] or 0) then best = index end
	end
	saved[name] = best
	return best
end

-- A player's color: r, g, b.
function Colors:For(name)
	if not name then return 1, 1, 1 end
	local color = ns.PlayerPalette[self:Index(name)]
	return color[1], color[2], color[3]
end
