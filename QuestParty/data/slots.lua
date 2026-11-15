-- Equipment slots, as data: the game's slot number, its name for
-- GetInventorySlotInfo, and where it sits on the player card's Items tab,
-- laid out like the game's own character window (a left column, a right
-- column and a row of weapons under them).
--   column  "left", "right" or "bottom"
--   row     its place in that column (or along the bottom row)
local _, ns = ...
local L = ns.L

ns.EquipmentSlots = {
	{ id = 1, name = "HeadSlot", label = L.SLOT_HEAD, column = "left", row = 1 },
	{ id = 2, name = "NeckSlot", label = L.SLOT_NECK, column = "left", row = 2 },
	{ id = 3, name = "ShoulderSlot", label = L.SLOT_SHOULDER, column = "left", row = 3 },
	{ id = 15, name = "BackSlot", label = L.SLOT_BACK, column = "left", row = 4 },
	{ id = 5, name = "ChestSlot", label = L.SLOT_CHEST, column = "left", row = 5 },
	{ id = 4, name = "ShirtSlot", label = L.SLOT_SHIRT, column = "left", row = 6 },
	{ id = 19, name = "TabardSlot", label = L.SLOT_TABARD, column = "left", row = 7 },
	{ id = 9, name = "WristSlot", label = L.SLOT_WRIST, column = "left", row = 8 },
	{ id = 10, name = "HandsSlot", label = L.SLOT_HANDS, column = "right", row = 1 },
	{ id = 6, name = "WaistSlot", label = L.SLOT_WAIST, column = "right", row = 2 },
	{ id = 7, name = "LegsSlot", label = L.SLOT_LEGS, column = "right", row = 3 },
	{ id = 8, name = "FeetSlot", label = L.SLOT_FEET, column = "right", row = 4 },
	{ id = 11, name = "Finger0Slot", label = L.SLOT_FINGER, column = "right", row = 5 },
	{ id = 12, name = "Finger1Slot", label = L.SLOT_FINGER, column = "right", row = 6 },
	{ id = 13, name = "Trinket0Slot", label = L.SLOT_TRINKET, column = "right", row = 7 },
	{ id = 14, name = "Trinket1Slot", label = L.SLOT_TRINKET, column = "right", row = 8 },
	{ id = 16, name = "MainHandSlot", label = L.SLOT_MAIN_HAND, column = "bottom", row = 1 },
	{ id = 17, name = "SecondaryHandSlot", label = L.SLOT_OFF_HAND, column = "bottom", row = 2 },
	{ id = 18, name = "RangedSlot", label = L.SLOT_RANGED, column = "bottom", row = 3 },
}

ns.EquipmentSlotById = {}
ns.EquipmentSlotIds = {}
for _, slot in ipairs(ns.EquipmentSlots) do
	ns.EquipmentSlotById[slot.id] = slot
	ns.EquipmentSlotIds[#ns.EquipmentSlotIds + 1] = slot.id
end
table.sort(ns.EquipmentSlotIds)

-- An item link's short form for the wire: "item:enchant:suffix" numbers, the
-- parts that make the game's tooltip for that exact item. "" for no item.
function ns.ShortItem(link)
	if type(link) ~= "string" then
		return ""
	end
	local item, enchant, rest = link:match("item:(%-?%d+):?(%-?%d*):?([^|]*)")
	if not item then
		return ""
	end
	-- After the enchant come four gem slots, then the random suffix.
	local parts = {}
	for part in (rest .. ":"):gmatch("([^:]*):") do
		parts[#parts + 1] = part
	end
	local suffix = tonumber(parts[5] or "") or 0
	return ("%d:%d:%d"):format(tonumber(item), tonumber(enchant) or 0, suffix)
end

-- The item string the game reads back from a short form, for tooltips and
-- links. nil for an empty slot.
function ns.ItemString(short)
	if type(short) ~= "string" then
		return nil
	end
	local item, enchant, suffix = short:match("^(%d+):(%d*):(%-?%d*)$")
	if not item or item == "0" then
		return nil
	end
	return ("item:%s:%s:0:0:0:0:%s"):format(item, enchant ~= "" and enchant or "0", suffix ~= "" and suffix or "0")
end
