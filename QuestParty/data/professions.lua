-- Professions: the game's skill line id, its name (as the game says it in
-- English; the skill list gives the local one), and its icon under
-- Interface\Icons. Skill rows show the icon in their mark (data\marks.lua),
-- and a player's Info tab lists theirs (ui\party-model.lua). Only the id and
-- rank travel (collectors\professions.lua).
local _, ns = ...

ns.Professions = {
	{ id = 171, name = "Alchemy", icon = "Trade_Alchemy" },
	{ id = 164, name = "Blacksmithing", icon = "Trade_BlackSmithing" },
	{ id = 333, name = "Enchanting", icon = "Trade_Engraving" },
	{ id = 202, name = "Engineering", icon = "Trade_Engineering" },
	{ id = 182, name = "Herbalism", icon = "Trade_Herbalism" },
	{ id = 773, name = "Inscription", icon = "INV_Inscription_Tradeskill01" },
	{ id = 755, name = "Jewelcrafting", icon = "INV_Misc_Gem_01" },
	{ id = 165, name = "Leatherworking", icon = "Trade_LeatherWorking" },
	{ id = 186, name = "Mining", icon = "Trade_Mining" },
	{ id = 393, name = "Skinning", icon = "INV_Misc_Pelt_Wolf_01" },
	{ id = 197, name = "Tailoring", icon = "Trade_Tailoring" },
	{ id = 185, name = "Cooking", icon = "INV_Misc_Food_15" },
	{ id = 129, name = "First Aid", icon = "Spell_Holy_SealOfSacrifice" },
	{ id = 356, name = "Fishing", icon = "Trade_Fishing" },
}

ns.ProfessionById, ns.ProfessionByName = {}, {}
for _, profession in ipairs(ns.Professions) do
	ns.ProfessionById[profession.id] = profession
	ns.ProfessionByName[profession.name:lower()] = profession
end

-- A profession by the name a skill-up row carries ("Cooking"), the English
-- name or the local one the skill list taught us (Learn). nil when unknown.
function ns.ProfessionNamed(name)
	return type(name) == "string" and ns.ProfessionByName[name:lower()] or nil
end

-- The local name for an id, from this client's skill list.
function ns.LearnProfessionName(id, name)
	local profession = ns.ProfessionById[id]
	if profession and type(name) == "string" and name ~= "" then
		profession.localName = name
		ns.ProfessionByName[name:lower()] = profession
	end
end

-- The full icon path for a profession's name, or nil.
function ns.ProfessionIcon(name)
	local profession = ns.ProfessionNamed(name)
	return profession and ("Interface\\Icons\\" .. profession.icon) or nil
end

-- On the wire: "185.20,182.12", id and rank, known professions only (a
-- colon would be escaped, so a dot).
function ns.EncodeProfessions(list)
	local parts = {}
	for _, item in ipairs(list or {}) do
		if ns.ProfessionById[item.id] then
			parts[#parts + 1] = item.id .. "." .. math.floor(item.rank or 0)
		end
	end
	return table.concat(parts, ",")
end

function ns.DecodeProfessions(text)
	if type(text) ~= "string" or #text > 120 then return nil end
	local list = {}
	for id, rank in text:gmatch("(%d+)%.(%d+)") do
		id, rank = tonumber(id), tonumber(rank)
		if ns.ProfessionById[id] and #list < 14 then
			list[#list + 1] = { id = id, rank = math.min(rank, 999) }
		end
	end
	return list
end
