-- Location: where this character is, sent with every update (comms\sharing.lua)
-- so each feed entry knows where it happened, and each player's last known
-- spot can go on the map (ui\map-pins.lua). Plain data, no frames.
--
-- On the wire: wm the map (a uiMapID), wx and wy the spot on it in
-- thousandths (0 to 1000). In a dungeon the game gives no spot: wm alone.
-- A place read back: { m = uiMapID, x = 0..1, y = 0..1 } (x and y nil when
-- there is no spot).
local _, ns = ...
local L = ns.L

local Location = {}
ns.Location = Location

local function Readable(value)
	return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

-- The fields to send for where you are now, or nil when the game says nothing.
function Location.Fields()
	local maps = C_Map
	local map = maps and maps.GetBestMapForUnit and maps.GetBestMapForUnit("player")
	if not Readable(map) or map <= 0 then return nil end
	local fields = { wm = map }
	local spot = maps.GetPlayerMapPosition and maps.GetPlayerMapPosition(map, "player")
	if spot and spot.GetXY then
		local x, y = spot:GetXY()
		if Readable(x) and Readable(y) and (x > 0 or y > 0) then
			fields.wx = math.floor(math.max(0, math.min(1, x)) * 1000 + 0.5)
			fields.wy = math.floor(math.max(0, math.min(1, y)) * 1000 + 0.5)
		end
	end
	return fields
end

-- A place from fields read off the wire (or an entry's data), checked: or nil.
function Location.Read(fields)
	local map = fields and fields.wm
	if type(map) ~= "number" or map <= 0 or map ~= math.floor(map) then return nil end
	local place = { m = map }
	local x, y = fields.wx, fields.wy
	if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1000 and y >= 0 and y <= 1000 then
		place.x, place.y = x / 1000, y / 1000
	end
	return place
end

-- A place as words: "The Barrens (52, 30)", or the map's name alone, or nil.
function Location.Describe(place)
	if not place then return nil end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(place.m)
	local name = type(info) == "table" and info.name or nil
	if not name then return nil end
	if place.x then
		return L.LOCATION_AT:format(name, math.floor(place.x * 100 + 0.5), math.floor(place.y * 100 + 0.5))
	end
	return name
end
