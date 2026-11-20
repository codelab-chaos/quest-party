-- Group: who is in your game party or raid right now, looked up on this
-- client, so they can be marked wherever they show (ui\panel.lua, ui\party.lua).
-- Names as the channel carries them: first name and surname on Forever.
-- Says GROUP_CHANGED when the roster changes.
local _, ns = ...
local Bus = ns.Bus

local Group = { members = {} }
ns.Group = Group

-- A unit's name as the channel has it ("Mcdouble Whopper").
local function FullName(unit)
	local first, second = UnitName(unit)
	if type(first) ~= "string" then return nil end
	if type(second) == "string" and second ~= "" and second ~= (GetRealmName and GetRealmName()) then
		return first .. " " .. second
	end
	return first
end

function Group:Refresh()
	local members = {}
	local count = GetNumGroupMembers and GetNumGroupMembers() or 0
	local raid = IsInRaid and IsInRaid()
	for index = 1, count do
		local unit = raid and ("raid" .. index) or ("party" .. index)
		local name = UnitExists and UnitExists(unit) and FullName(unit)
		if name and not ns.IsMe(name) then members[name] = unit end
	end
	local changed = false
	for name in pairs(members) do if not self.members[name] then changed = true end end
	for name in pairs(self.members) do if not members[name] then changed = true end end
	self.members = members
	if changed then Bus:Fire("GROUP_CHANGED") end
end

-- Whether a player is in your game group (not you).
function Group:Has(name)
	return name ~= nil and self.members[name] ~= nil
end

-- The game's unit for a player, when the game can show them now: "player"
-- for you, "party2" or "raid7" for someone in your game group, else nil.
function Group:Unit(name)
	if name == nil then return nil end
	if ns.IsMe(name) then return "player" end
	return self.members[name]
end

Bus:On("READY", function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("GROUP_ROSTER_UPDATE")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function() Group:Refresh() end)
	Group:Refresh()
end)
