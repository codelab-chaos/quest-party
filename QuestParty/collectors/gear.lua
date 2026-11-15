-- Gear: this character's equipped items, slot by slot, for the player card
-- on everyone else's panel. Says when a slot changes (GEAR_CHANGED), and
-- gives the whole set when someone new needs it (Gear:Snapshot).
-- The sandbox build has no gear of its own: its pretend players bring theirs.
local _, ns = ...
local Bus = ns.Bus

local Gear = { items = {} }
ns.Gear = Gear

local function Read(slot)
	return ns.ShortItem(GetInventoryItemLink("player", slot))
end

-- { [slot] = "item:enchant:suffix" or "" } for every slot.
function Gear:Snapshot()
	local gear = {}
	for _, slot in ipairs(ns.EquipmentSlotIds) do
		gear[slot] = Read(slot)
		self.items[slot] = gear[slot]
	end
	return gear
end

function Gear:Check(slot)
	if not ns.EquipmentSlotById[slot] then
		return
	end
	local item = Read(slot)
	if item ~= self.items[slot] then
		self.items[slot] = item
		Bus:Fire("GEAR_CHANGED", slot, item)
	end
end

Bus:On("READY", function()
	if ns.IsSandbox() then
		return
	end
	Gear:Snapshot()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	frame:SetScript("OnEvent", function(_, _, slot)
		Gear:Check(slot)
	end)
end)
