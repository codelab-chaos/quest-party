-- Map pins: each player's last known spot (collectors\location.lua, kept on
-- their member record by store.lua) as their class icon on the world map and
-- the minimap, through HereBeDragons (libs\README.md). Map addons that show
-- HereBeDragons icons, OpenMap among them, show these too. Hover one for who,
-- where and how long ago: a last known position, not a live one. Off the minimap, a pin rides its edge, pointing the
-- way. Not you (the game shows you), and not a spot older than
-- ns.Timing.pinHours. The Players on the map switch turns them off.
-- It owns frames only.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local MapPins = {}
ns.MapPins = MapPins

local LAYOUT = {
	world = 18, -- a pin on the world map
	minimap = 14, -- on the minimap
	edge = 1,
}
local CLASS_ICONS = "Interface\\WorldStateFrame\\Icons-Classes"
local REF = "QuestParty" -- ours, to HereBeDragons

local pins = {} -- player name -> { world, minimap }

local function Library()
	local stub = LibStub
	return stub and stub("HereBeDragons-Pins-2.0", true)
end

local function Tip(self)
	local member = self.member
	if not member then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(ns.ColorName(member.name, member.class))
	local place = ns.Location.Describe(member.where)
	if place then GameTooltip:AddLine(place, 1, 1, 1) end
	GameTooltip:AddLine(L.PIN_SEEN:format(ns.Ago(GetServerTime() - (member.where.time or 0))), 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- One pin: the player's class icon in a frame of their color.
local function Pin(size)
	local pin = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
	pin:SetSize(size, size)
	pin:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = LAYOUT.edge })
	pin:SetBackdropColor(0, 0, 0, 0.8)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetPoint("TOPLEFT", LAYOUT.edge, -LAYOUT.edge)
	pin.icon:SetPoint("BOTTOMRIGHT", -LAYOUT.edge, LAYOUT.edge)
	pin:SetScript("OnEnter", Tip)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return pin
end

local function Dress(pin, member)
	pin.member = member
	local coords = member.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[member.class]
	if coords then
		pin.icon:SetTexture(CLASS_ICONS)
		pin.icon:SetTexCoord(unpack(coords))
	else
		pin.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	pin:SetBackdropBorderColor(ns.PlayerColors:For(member.name))
end

-- Who goes on the map: everyone with a spot, recent enough, but you (and dev
-- mode's pretend players only in dev mode).
local function Shown(member, now)
	local place = member.where
	return place ~= nil and place.x ~= nil and not ns.IsMe(member.name)
		and (not member.emulated or ns.IsDebug())
		and now - (place.time or 0) <= ns.Timing.pinHours * 3600
end

function MapPins:Refresh()
	local library = Library()
	if not library then return end
	local now, on, seen = GetServerTime(), ns.IsEnabled("mapPins"), {}
	for _, member in ipairs(ns.Store:GetMembers()) do
		if on and Shown(member, now) then
			seen[member.name] = true
			local pair = pins[member.name]
			if not pair then
				pair = { world = Pin(LAYOUT.world), minimap = Pin(LAYOUT.minimap) }
				pins[member.name] = pair
			end
			local place = member.where
			Dress(pair.world, member)
			Dress(pair.minimap, member)
			library:AddWorldMapIconMap(REF, pair.world, place.m, place.x, place.y, HBD_PINS_WORLDMAP_SHOW_CONTINENT)
			library:AddMinimapIconMap(REF, pair.minimap, place.m, place.x, place.y, true, true)
		end
	end
	for name, pair in pairs(pins) do
		if not seen[name] then
			library:RemoveWorldMapIcon(REF, pair.world)
			library:RemoveMinimapIcon(REF, pair.minimap)
			pair.world:Hide()
			pair.minimap:Hide()
		end
	end
end

-- Many changes at once (a busy channel) are one redraw a moment later.
local pending = false
local function Soon()
	if pending then return end
	pending = true
	C_Timer.After(1, function()
		pending = false
		MapPins:Refresh()
	end)
end

Bus:On("READY", function()
	MapPins:Refresh()
	C_Timer.NewTicker(60, function() MapPins:Refresh() end) -- old spots go
end)
Bus:On("STORE_CHANGED", Soon)
Bus:On("PEERS_CHANGED", Soon)
Bus:On("SETTING_CHANGED", function(id)
	if id == "mapPins" then MapPins:Refresh() end
end)
