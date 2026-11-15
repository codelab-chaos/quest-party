-- Resolver: how an entry becomes something to show, kept apart from both the
-- wire and the panel.
--
--   interpret  an entry as it arrived (its type, data, and the sender's own
--              summary) becomes an entry this version can show. A type this
--              version does not know, or one missing what its card needs,
--              becomes a generic "unknown" entry that shows the sender's
--              summary, or a guess at one
--   resolve    a known entry's card text: title, detail and template fields,
--              from its type's definition in data\feed-types.lua
--   summary    a short plain text a sender puts on every entry it sends, so a
--              client that does not know the type can still show something
--
-- Older senders send no summary, and are resolved as they always were.
local _, ns = ...
local L = ns.L

local Resolver = {}
ns.Resolver = Resolver

-- True for an XP gain that came from a kill the game named.
function Resolver.KillXP(data)
	return type(data.mob) == "string" and data.mob ~= "" and type(data.xp) == "number" and data.xp > 0
end

-- Template fields: the data with number formatting applied, plus {player}.
function Resolver.Fields(player, class, data, def)
	local fields = { player = ns.ColorName(player, class) }
	for key, value in pairs(data) do
		if def.format and def.format[key] and type(value) == "number" then
			fields[key] = ns.Comma(value)
		else
			fields[key] = value
		end
	end
	if def.experience then
		-- A merged run of gains adds up its XP and counts them (data.gains).
		local gains = type(data.gains) == "number" and data.gains or 1
		fields.xpGain = data.xp and L.XP_GAIN:format(ns.Comma(data.xp)) or L.XP_UPDATED
		if data.xp and gains > 1 then
			fields.xpGain = L.XP_GAINS:format(ns.Comma(data.xp), gains)
		end
		if Resolver.KillXP(data) then
			fields.xpGain = gains > 1 and L.XP_KILLS:format(data.mob, gains, ns.Comma(data.xp)) or L.XP_KILL:format(data.mob, ns.Comma(data.xp))
		end
		fields.xpStatus = L.XP_LEVEL:format(data.level)
		if data.maxXP and data.maxXP > 0 and data.currentXP then
			if Resolver.KillXP(data) then
				-- A kill says how many more like it to the next level, not a percentage.
				local left = math.ceil(math.max(0, data.maxXP - data.currentXP) / (data.xp / gains))
				fields.xpStatus = L.XP_KILLS_LEFT:format(data.level, ns.Comma(left), data.level + 1)
			else
				local remaining = math.max(0, math.min(100, 100 * (data.maxXP - data.currentXP) / data.maxXP))
				fields.xpStatus = L.XP_STATUS:format(data.level, remaining, data.level + 1)
			end
		end
	end
	return fields
end

-- An entry's card text: its title, its detail (or nil), and the template
-- fields both were filled from. A merged run that has climbed says from
-- where, and by how much.
function Resolver.Text(entry, def)
	local fields = Resolver.Fields(entry.player, entry.class, entry.data, def)
	local titleTemplate, detailTemplate = def.text, def.detail
	local merge = def.merge
	local first, last = merge and entry.data[merge.first], merge and entry.data[merge.field]
	if type(first) == "number" and type(last) == "number" and last > first then
		fields.first, fields.gained = first, last - first
		titleTemplate = merge.text
		detailTemplate = fields.gained == 1 and merge.detailOne or merge.detail
	end
	local detail = detailTemplate and ns.Fill(detailTemplate, fields) or nil
	return ns.Fill(titleTemplate, fields), detail, fields
end

-- Text without the game's color codes.
local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- The short plain text a sender puts on an entry: its card's title, as this
-- version shows it. Nil for a type without a title.
function Resolver.Summary(entry)
	local def = ns.FeedTypes[entry.type]
	if not def or not def.text or type(entry.data) ~= "table" then
		return nil
	end
	local ok, title = pcall(Resolver.Text, entry, def)
	return ok and Plain(title) or nil
end

-- A guess at a summary from a type's name alone: "pet_battle_won" becomes
-- "Pet battle won".
local function Guess(typeName)
	local words = typeName:gsub("[_%-]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if words == "" then
		return L.UNKNOWN_UPDATE
	end
	return words:sub(1, 1):upper() .. words:sub(2):lower()
end

-- What an entry this version can show is, from what arrived: the type to use
-- and its data. summary is the sender's own, or nil from an older sender.
function Resolver.Interpret(typeName, data, summary)
	local def = ns.FeedTypes[typeName]
	local missing = false
	for _, key in ipairs(def and def.requires or {}) do
		if data[key] == nil then
			missing = true
		end
	end
	if def and not missing then
		return typeName, data
	end
	-- A type from a newer version, or one this version would have to drop.
	if missing and not summary then
		return typeName, data -- nothing better to show: the store drops it, as before
	end
	return "unknown", { summary = summary or Guess(typeName), kind = typeName }
end
