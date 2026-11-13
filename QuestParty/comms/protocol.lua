-- Protocol: turns messages into text for the wire and back. Pure, no game calls.
--
-- A message on the wire is "<version>:<kind>:<key>=<value>;<key>=<value>...".
-- Numbers are written as #123 so they come back as numbers.
-- Example: 1:E:t=quest_progress;quest=A Call to Arms;objective=Redridge Gnoll;have=#3;need=#10
local _, ns = ...

local Protocol = {
	version = 1,
	maxLength = 255, -- the game's limit for one addon message
}
ns.Protocol = Protocol

-- Message kinds.
Protocol.Kinds = {
	HELLO = "H", -- "I run Quest Party", with who I am. Answered with ACK.
	ACK = "A", -- the answer to HELLO, same fields
	ENTRY = "E", -- one feed entry. t is the feed type, the rest is its data.
}

local function Escape(value)
	return (tostring(value):gsub("[%%;=:#]", function(character)
		return ("%%%02X"):format(character:byte())
	end))
end

local function Unescape(text)
	return (text:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

-- Returns the wire text, or nil if the message is too long to send.
function Protocol.Encode(kind, fields)
	local keys = {}
	for key in pairs(fields) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		local value = fields[key]
		if type(value) == "number" then
			parts[#parts + 1] = Escape(key) .. "=#" .. value
		else
			parts[#parts + 1] = Escape(key) .. "=" .. Escape(value)
		end
	end
	local text = Protocol.version .. ":" .. kind .. ":" .. table.concat(parts, ";")
	if #text > Protocol.maxLength then
		return nil
	end
	return text
end

-- Returns kind and fields. Returns nil for text that is not ours or is from
-- another protocol version.
function Protocol.Decode(text)
	local version, kind, body = text:match("^(%d+):(%a+):(.*)$")
	if tonumber(version) ~= Protocol.version then
		return nil
	end
	local fields = {}
	for pair in body:gmatch("[^;]+") do
		local key, value = pair:match("^([^=]+)=(.*)$")
		if key then
			if value:sub(1, 1) == "#" then
				fields[Unescape(key)] = tonumber(value:sub(2))
			else
				fields[Unescape(key)] = Unescape(value)
			end
		end
	end
	return kind, fields
end
