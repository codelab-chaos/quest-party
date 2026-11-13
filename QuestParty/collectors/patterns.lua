-- Patterns: how to recognize the game's own messages, as Quest Tweet did.
-- Each pattern is built from the game's localized format string when there is one,
-- so it follows the client's language. The English fallbacks are Quest Tweet's.
local _, ns = ...

-- Turns a format string such as "%s slain: %d/%d" into a Lua pattern with captures.
-- open leaves the end unanchored, for messages with optional trailing text.
-- Returns nil for formats with reordered arguments ("%2$s"), which we cannot map.
local function FromFormat(format, open)
	if type(format) ~= "string" or format:find("%%%d+%$") then
		return nil
	end
	local pattern = format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	pattern = pattern:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
	if open then
		return "^" .. pattern:gsub("%%%.$", "")
	end
	return "^" .. pattern .. "$"
end
ns.FromFormat = FromFormat

-- Global format strings are looked up by name at load, since the game defines them.
local function Global(name)
	return _G[name]
end

ns.Patterns = {
	-- "Kobold Workers slain: 3/10", "Linen Cloth: 2/8". Captures: objective, have, need.
	-- One loose pattern covers kills, items and other counted objectives.
	progress = "^(.+):%s*(%d+)%s*/%s*(%d+)%s*$",

	-- "Discovered: Echo Ridge Mine". Captures: zone.
	discovery = FromFormat(Global("ERR_ZONE_EXPLORED")) or "^Discovered: (.+)$",
	-- "Discovered Echo Ridge Mine: 150 experience gained". Captures: zone, xp.
	discoveryXp = FromFormat(Global("ERR_ZONE_EXPLORED_XP")) or "^Discovered (.+): (%d+) experience gained$",

	-- "Vale Moth dies, you gain 26 experience." with or without a rested bonus after it.
	-- Captures: mob, xp.
	kill = FromFormat(Global("COMBATLOG_XPGAIN_FIRSTPERSON"), true) or "^(.+) dies, you gain (%d+) experience",

	-- "Your skill in Herbalism has increased to 62". Captures: skill, level.
	skill = FromFormat(Global("ERR_SKILL_UP_SI"), true) or "^Your skill in (.+) has increased to (%d+)",
}

-- Quest-log text can put counts before the item ("1/5 Vile Fin Scale")
-- or after it ("Vile Fin Scale: 1/5"). Counts are never part of its identity.
function ns.ObjectiveName(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("%[([^%]]+)%]", "%1")
	local _, _, prefixName = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.+)$")
	text = prefixName or text:match(ns.Patterns.progress) or text
	return (text:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end

function ns.ParseObjectiveProgress(text)
	local objective, have, need = text:match(ns.Patterns.progress)
	if not objective then
		have, need, objective = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.+)$")
	end
	if objective then return ns.ObjectiveName(objective), tonumber(have), tonumber(need) end
end
