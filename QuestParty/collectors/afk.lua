-- AFK: whether this character is away (the game's AFK flag), so the party
-- can tell away from gone (comms\sharing.lua says it in a presence the
-- moment it changes; ui\panel.lua marks the bar). Says AFK_CHANGED.
local _, ns = ...
local Bus = ns.Bus

local Away = { afk = false }
ns.Away = Away

-- Whether you are AFK now, by the game (false when it will not say).
function Away.Read()
	local afk = UnitIsAFK and UnitIsAFK("player")
	if issecretvalue and issecretvalue(afk) then return false end
	return afk == true
end

function Away:Check()
	local afk = Away.Read()
	if afk ~= self.afk then
		self.afk = afk
		self.since = afk and GetServerTime() or nil
		Bus:Fire("AFK_CHANGED", afk)
	end
end

Bus:On("READY", function()
	Away:Check()
	local frame = CreateFrame("Frame")
	pcall(frame.RegisterEvent, frame, "PLAYER_FLAGS_CHANGED")
	frame:SetScript("OnEvent", function(_, _, unit)
		if unit == nil or unit == "player" then Away:Check() end
	end)
end)
