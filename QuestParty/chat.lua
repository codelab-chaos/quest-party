-- Chat: KekChat, Quest Party's own chat over the channel (docs\chat.md). A
-- message is up to three images (any icons, by file ID) and/or a saying
-- (data\chat.lua, Sayings), and can carry an effect (data\effects.lua) that
-- plays its images as particles, with a sound: nobody types words of their
-- own. A message heard is a distinct feed entry of type chat (data\feed-types.lua):
-- the feed keeps it, like everything else. This keeps the player's saved
-- presets, offers the built-in ones, the icon catalog and its search, muting
-- and the limits; ui\chat.lua is the bar that sends.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local Chat = {}
ns.Chat = Chat

-- The limit, per sender (ours under the key "you"): the times of their
-- latest messages, and any timeout. { times, until, strikes, lastStrike }
local limits = {}
local YOU = "\001you" -- not a name anyone can have

local function Limit(key)
	limits[key] = limits[key] or { times = {}, strikes = 0 }
	return limits[key]
end

-- Seconds left of a sender's timeout, or 0.
local function TimeoutLeft(key)
	local limit = limits[key]
	if not limit or not limit.until_ then
		return 0
	end
	return math.max(0, limit.until_ - GetTime())
end

-- True when another message from this sender fits, and counts it. Going over
-- the burst starts a timeout (doubling on repeats) and returns false and its
-- length; during one, false and what is left.
local function Allow(key)
	local now, rules = GetTime(), ns.ChatRules
	local limit = Limit(key)
	local left = TimeoutLeft(key)
	if left > 0 then
		return false, left, false
	end
	local times = limit.times
	while times[1] and now - times[1] >= rules.burstSeconds do
		table.remove(times, 1)
	end
	if #times >= rules.burst then
		if limit.lastStrike and now - limit.lastStrike > rules.timeoutForgetSeconds then
			limit.strikes = 0
		end
		limit.strikes = limit.strikes + 1
		limit.lastStrike = now
		local seconds = math.min(rules.timeoutMax, rules.timeoutSeconds * 2 ^ (limit.strikes - 1))
		limit.until_ = now + seconds
		wipe(times)
		return false, seconds, true -- true: a timeout just began
	end
	times[#times + 1] = now
	return true
end

-- Shared with stamps (stamps.lua): one limit for everything said, per sender.
Chat.Allow, Chat.YOU = Allow, YOU

-- Seconds before you can chat again, or 0.
function Chat:TimeoutLeft(player)
	return TimeoutLeft(player or YOU)
end


local function ValidIcon(icon)
	icon = tonumber(icon)
	return icon and icon > 0 and icon == math.floor(icon) and icon or nil
end

-- The images of a list that are icons, at most maxImages, in order.
local function ValidIcons(icons)
	local list = {}
	for _, icon in ipairs(icons or {}) do
		icon = ValidIcon(icon)
		if icon and #list < ns.ParticleRules.maxImages then
			list[#list + 1] = icon
		end
	end
	return list
end
Chat.ValidIcons = ValidIcons

local function IconID(path)
	local toID = GetFileIDFromPath or (C_Texture and C_Texture.GetFileIDFromPath)
	local icon = toID and toID("Interface\\Icons\\" .. path)
	return type(icon) == "number" and icon > 0 and icon or nil
end

-- A message as a feed entry (data\feed-types.lua, chat): its images as a
-- list, its saying and effect by id, and w, when it was said.
local function Entry(player, class, time, icons, saying, effect, virtual)
	return {
		type = "chat",
		player = player,
		class = class,
		time = time,
		data = { icons = icons, saying = saying, effect = effect, w = time },
		emulated = virtual or nil,
	}
end

-- ========= Sending ==========================================================
-- Sends images (up to three) and/or a saying, with an effect if wanted, as
-- one message. Returns true, or false and why. It shows here once the server
-- sends it back (comms\sharing.lua), as it does for everyone else.
function Chat:Send(icons, saying, effect)
	icons = ValidIcons(icons)
	if saying ~= nil and not ns.SayingById[saying] then
		return false, L.CHAT_PICK
	end
	if effect ~= nil and not ns.ChatEffectById[effect] then
		return false, L.CHAT_PICK
	end
	if #icons == 0 and not saying then
		return false, L.CHAT_PICK
	end
	if effect and #icons == 0 then
		return false, L.CHAT_EFFECT_NEEDS_IMAGE -- an effect plays its images
	end
	if not (ns.Sharing.loopback or (ns.Session.state == "connected")) then
		return false, L.CHAT_NO_CHANNEL
	end
	local allowed, seconds = Allow(YOU)
	if not allowed then
		return false, L.CHAT_TIMEOUT:format(math.ceil(seconds))
	end
	local _, class = UnitClass("player")
	if not ns.Sharing.SendSay(icons, saying, effect, class) then
		return false, L.CHAT_NO_CHANNEL
	end
	return true
end

-- ========= Presets ==========================================================
-- Ready-to-send messages: the built-in ones (data\chat.lua, ChatPresets),
-- then the player's own, newest last. { icons, saying, effect, builtIn or own }.
local builtIn -- the built-in presets with their icons as file IDs, built once

function Chat:Presets()
	if not builtIn then
		builtIn = {}
		for _, preset in ipairs(ns.ChatPresets) do
			local icons = {}
			for _, path in ipairs(preset.icons or {}) do
				icons[#icons + 1] = IconID(path)
			end
			icons = ValidIcons(icons)
			local saying = ns.SayingById[preset.saying] and preset.saying or nil
			local effect = #icons > 0 and ns.ChatEffectById[preset.effect] and preset.effect or nil
			if #icons > 0 or saying then
				builtIn[#builtIn + 1] = { icons = icons, saying = saying, effect = effect, builtIn = true }
			end
		end
	end
	local list = {}
	for _, preset in ipairs(builtIn) do
		list[#list + 1] = preset
	end
	for index, preset in ipairs(ns.db.chatPresets) do
		list[#list + 1] = { icons = preset.icons or {}, saying = preset.saying, effect = preset.effect, own = index }
	end
	return list
end

local function SameIcons(a, b)
	if #a ~= #b then return false end
	for index = 1, #a do
		if a[index] ~= b[index] then return false end
	end
	return true
end

-- Saves a message as one of the player's own presets; one already saved is
-- not saved twice. Returns true, or false and why.
function Chat:SavePreset(icons, saying, effect)
	icons = ValidIcons(icons)
	if saying ~= nil and not ns.SayingById[saying] then
		saying = nil
	end
	if #icons == 0 or not ns.ChatEffectById[effect] then
		effect = nil
	end
	if #icons == 0 and not saying then
		return false, L.CHAT_PICK
	end
	local presets = ns.db.chatPresets
	for _, preset in ipairs(presets) do
		if SameIcons(preset.icons or {}, icons) and preset.saying == saying and preset.effect == effect then
			return false, L.CHAT_PRESET_KNOWN
		end
	end
	presets[#presets + 1] = { icons = icons, saying = saying, effect = effect }
	while #presets > ns.ChatRules.maxPresets do
		table.remove(presets, 1)
	end
	Bus:Fire("CHAT_PRESETS_CHANGED")
	return true
end

-- Removes one of the player's own presets (built-in ones stay).
function Chat:DeletePreset(index)
	if ns.db.chatPresets[index] then
		table.remove(ns.db.chatPresets, index)
		Bus:Fire("CHAT_PRESETS_CHANGED")
	end
end

-- ========= The icon catalog =================================================
local catalog -- { { icon, words } }, from data\chat.lua, built once

local function Catalog()
	if catalog then
		return catalog
	end
	catalog = {}
	for _, entry in ipairs(ns.IconCatalog) do
		local icon = IconID(entry.path)
		if icon then
			catalog[#catalog + 1] = { icon = icon, words = (entry.path .. " " .. (entry.tags or "")):lower() }
		end
	end
	return catalog
end

-- Our icons whose path or tags hold every word of the search, in order.
-- An empty search gives them all.
function Chat:Search(text)
	local words = {}
	for word in (text or ""):lower():gmatch("%S+") do
		words[#words + 1] = word
	end
	local found = {}
	for _, entry in ipairs(Catalog()) do
		local match = true
		for _, word in ipairs(words) do
			if not entry.words:find(word, 1, true) then
				match = false
				break
			end
		end
		if match then
			found[#found + 1] = entry.icon
		end
	end
	return found
end

-- ========= Effect presets (the stamp picker's effects) ======================
-- Preset effects (data\effects.lua, EffectPresets), played on a card from
-- its stamp picker (stamps.lua): { id, label, effect, icons, saying }, with
-- images the game knows.
local effectPresets

function Chat:EffectPresets()
	if effectPresets then
		return effectPresets
	end
	effectPresets = {}
	for _, preset in ipairs(ns.EffectPresets) do
		local icons = {}
		for _, path in ipairs(preset.icons or {}) do
			icons[#icons + 1] = IconID(path)
		end
		icons = ValidIcons(icons)
		if #icons > 0 and ns.ChatEffectById[preset.effect] then
			effectPresets[#effectPresets + 1] = {
				id = preset.id,
				-- Its button (ui\effect-grid.lua): its own icon, else its first image.
				icon = (preset.icon and IconID(preset.icon)) or icons[1],
				label = preset.label,
				effect = preset.effect,
				icons = icons,
				saying = ns.SayingById[preset.saying] and preset.saying or nil,
			}
		end
	end
	return effectPresets
end

-- One effect preset by its id, or nil. They play on cards (stamps.lua).
function Chat:EffectPreset(id)
	for _, preset in ipairs(self:EffectPresets()) do
		if preset.id == id then return preset end
	end
	return nil
end

-- ========= Suggestions, for typing ==========================================
-- What a typed word could mean: sayings whose words start with it (or whose
-- id does), then images whose path or tags hold it. (Effects are sent from
-- the KekChat button's list, not built here.) Typing only
-- picks from these; the word itself is never sent. An empty word suggests
-- every saying. { kind = "saying" | "image", id or icon, text }
local function Starts(text, word)
	if text:lower():sub(1, #word) == word then
		return true
	end
	for part in text:lower():gmatch("[%w']+") do
		if part:sub(1, #word) == word then
			return true
		end
	end
	return false
end

function Chat:Suggest(text, limit)
	limit = limit or 8
	local word = (text or ""):lower():match("^%s*(.-)%s*$")
	local list = {}
	if word == "" then
		limit = math.huge -- every saying, to choose from: the list scrolls
	end
	local function Add(entry)
		if #list < limit then
			list[#list + 1] = entry
		end
	end
	for _, saying in ipairs(ns.Sayings) do
		if word == "" or Starts(saying.text, word) or Starts(saying.id, word) then
			Add({ kind = "saying", id = saying.id, text = saying.text })
		end
	end
	if word == "" then
		return list
	end
	for _, icon in ipairs(self:Search(word)) do
		Add({ kind = "image", icon = icon })
	end
	return list
end

-- Every icon the game lists (as the macro icon picker does), to browse:
-- file IDs only, so they cannot be searched. Built once.
local everyIcon
function Chat:AllIcons()
	if everyIcon then
		return everyIcon
	end
	everyIcon = {}
	local seen = {}
	for _, list in ipairs({ "GetMacroIcons", "GetMacroItemIcons" }) do
		local fill = _G[list]
		if fill then
			local icons = {}
			pcall(fill, icons)
			for _, icon in ipairs(icons) do
				icon = tonumber(icon)
				if icon and icon > 0 and not seen[icon] then
					seen[icon] = true
					everyIcon[#everyIcon + 1] = icon
				end
			end
		end
	end
	return everyIcon
end

-- ========= Muting ===========================================================
-- A player can be muted here: nothing they send to chat shows, and their
-- sayings do nothing on your screen. Anyone on the game's ignore list is
-- muted too. Saved across reloads.
function Chat:IsMuted(player)
	if ns.db.muted and ns.db.muted[player] then
		return true
	end
	local ignored = C_FriendList and C_FriendList.IsIgnored
	return ignored ~= nil and ignored(player) == true
end

-- Mutes a player, or unmutes one. Returns whether they are muted now.
function Chat:ToggleMute(player)
	if not player or ns.IsMe(player) then
		return false
	end
	ns.db.muted[player] = (not ns.db.muted[player]) or nil
	Bus:Fire("STORE_CHANGED") -- their KekChat rows hide or come back
	return ns.db.muted[player] == true
end

-- ========= Hearing ==========================================================
-- A message arrived (ours back from the server, a friend's, or a pretend
-- player's). A saying this version does not know is left out; what is left
-- goes into the feed, unless its sender is muted or over the limit. A saying
-- with an effect does it here (CHAT_EFFECT), and an effect plays over the
-- feed (CHAT_PLAY).
Bus:On("CHAT_SAY", function(say)
	local saying = say.saying and ns.SayingById[say.saying]
	local icons = ValidIcons(say.icons)
	if not saying and #icons == 0 then
		return
	end
	local effect = #icons > 0 and say.effect and ns.ChatEffectById[say.effect] or nil
	if Chat:IsMuted(say.player) then
		return
	end
	-- Others' spam is held back here; yours was limited once, when you sent.
	local allowed, seconds, began = true, 0, false
	if not ns.IsMe(say.player) then
		allowed, seconds, began = Allow(say.player)
	end
	if not allowed then
		if began then
			-- Said once, here only: their messages are hidden for a while.
			ns.Print(L.CHAT_SPAMMER:format(say.player, math.ceil(seconds)))
		end
		return
	end
	local entry = Entry(say.player, say.class, say.time or GetServerTime(), icons,
		saying and saying.id or nil, effect and effect.id or nil, say.virtual)
	Bus:Fire("ENTRY_RECEIVED", entry)
	if saying and saying.effect then
		Bus:Fire("CHAT_EFFECT", saying.effect, say.player)
	end
	if effect then
		Bus:Fire("CHAT_PLAY", entry.data) -- its effect, over the feed
	end
end)

-- KekChat's own list from before 0.3.7: its messages go into the feed at
-- their times (store.lua runs first), and the list goes. Notices of a
-- timeout were for the moment they happened; they are left out.
local function RestoreOldMessages()
	local old = ns.db.chat
	ns.db.chat = nil
	if type(old) ~= "table" then return end
	local entries = {}
	for _, message in ipairs(old) do
		local icons = ValidIcons(message.icons or { message.icon })
		local saying = message.kind == "board" and message.id or message.saying
		if not message.system and message.player and (#icons > 0 or saying) and message.time then
			entries[#entries + 1] = Entry(message.player, message.class, message.time, icons, saying,
				#icons > 0 and message.effect or nil, message.virtual)
		end
	end
	ns.Store:Restore(entries)
end

Bus:On("INIT", function()
	ns.db.muted = ns.db.muted or {}
	ns.db.chatPresets = ns.db.chatPresets or {}
	RestoreOldMessages()
	if ns.charDb then ns.charDb.chatPopped = nil end -- KekChat no longer pops out
	-- Presets from before a message carried a list of images.
	for _, preset in ipairs(ns.db.chatPresets) do
		if preset.icon then
			preset.icons, preset.icon = { preset.icon }, nil
		end
	end
end)
