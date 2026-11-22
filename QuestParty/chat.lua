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

-- ========= Words of your own ================================================
-- A KekChat's words, made safe and short: the game's escape character (|,
-- colors, links, textures) taken out, line breaks and runs of spaces made one
-- space, cut to maxText characters without splitting a letter. "" for none.
function Chat.CleanText(text)
	if type(text) ~= "string" then return "" end
	-- Whole escapes first (a color, a link, a texture), keeping a link's words,
	-- then any | left.
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|[TAK].-|[tak]", "")
		:gsub("|", ""):gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
	local most = ns.ChatRules.maxText
	if #text > most then
		-- Count letters, not bytes: stop before the letter that goes past it.
		local letters, cut = 0, #text
		for position in text:gmatch("()[^\128-\191]") do
			letters = letters + 1
			if letters > most then cut = position - 1 break end
		end
		text = text:sub(1, cut)
	end
	return text
end

-- ========= Sending ==========================================================
-- Sends images (up to three) and/or a saying, words of your own (text), a
-- sound (ns.KekSounds) and an effect, as one message. Returns true, or false
-- and why. It shows here once the server sends it back (comms\sharing.lua),
-- as it does for everyone else.
function Chat:Send(icons, saying, effect, text, sound)
	icons = ValidIcons(icons)
	text = Chat.CleanText(text)
	if text == "" then text = nil end
	if sound ~= nil and not ns.KekSoundById[sound] then
		return false, L.CHAT_PICK
	end
	if saying ~= nil and not ns.SayingById[saying] then
		return false, L.CHAT_PICK
	end
	if effect ~= nil and not ns.ChatEffectById[effect] then
		return false, L.CHAT_PICK
	end
	if #icons == 0 and not saying and not text then
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
	if not ns.Sharing.SendSay(icons, saying, effect, class, nil, text, sound) then
		return false, L.CHAT_NO_CHANNEL
	end
	return true
end

-- ========= Your KekChats ====================================================
-- Up to maxMessages saved KekChats, made in the editor (ui\kek-editor.lua)
-- and sent from the KekChat button in one click: { icon, text, sound, effect }.
-- Saved for the account. The first time, they start as the built-in quick
-- chats, to change.
function Chat:KekMessages()
	return ns.db.kekMessages
end

-- Saves one (index 1 to maxMessages): its icon and words checked, the sound
-- and effect only if they are ones we have. Returns true, or false and why.
function Chat:SetKekMessage(index, message)
	if type(index) ~= "number" or index < 1 or index > ns.ChatRules.maxMessages then return false, L.CHAT_PICK end
	local icon = ValidIcon(message and message.icon)
	local text = Chat.CleanText(message and message.text)
	if not icon and text == "" then return false, L.CHAT_PICK end
	local list = ns.db.kekMessages
	list[index] = {
		icon = icon,
		text = text ~= "" and text or nil,
		sound = message.sound and ns.KekSoundById[message.sound] and message.sound or nil,
		effect = icon and message.effect and ns.ChatEffectById[message.effect] and message.effect or nil,
	}
	Bus:Fire("CHAT_PRESETS_CHANGED")
	return true
end

-- Empties one slot (the others stay where they are: the editor's rows).
function Chat:RemoveKekMessage(index)
	local list = ns.db.kekMessages
	if list[index] then
		list[index] = nil
		Bus:Fire("CHAT_PRESETS_CHANGED")
	end
end

-- Sends one of your KekChats. Returns true, or false and why.
function Chat:SendKek(index)
	local message = ns.db.kekMessages[index]
	if not message then return false, L.CHAT_PICK end
	return self:Send(message.icon and { message.icon } or {}, nil, message.effect, message.text, message.sound)
end

-- Plays one of the KekChat sounds (ns.KekSounds) by its id, at the Volume.
function Chat.PlayKekSound(id)
	local sound = id and ns.KekSoundById[id]
	if sound then ns.PlaySound((SOUNDKIT and SOUNDKIT[sound.name]) or sound.kit) end
end

-- ========= Blocking =========================================================
-- A player's KekChat can be blocked whole, or one message of theirs (by its
-- words): nothing blocked shows, plays or sounds here. Saved for the account.
--   kekBlocks[player] = { all = true, texts = { [words] = true } }
function Chat:IsBlocked(player, text)
	local block = player and ns.db.kekBlocks[player]
	if not block then return false end
	return block.all == true or (text ~= nil and block.texts[text] == true)
end

local function Block(player)
	ns.db.kekBlocks[player] = ns.db.kekBlocks[player] or { texts = {} }
	return ns.db.kekBlocks[player]
end

local function Tidy(player)
	local block = ns.db.kekBlocks[player]
	if block and not block.all and not next(block.texts) then ns.db.kekBlocks[player] = nil end
	Bus:Fire("STORE_CHANGED") -- their rows hide or come back
	Bus:Fire("KEK_BLOCKS_CHANGED")
end

-- Blocks (or unblocks) all of a player's KekChat.
function Chat:BlockAll(player, on)
	if not player or ns.IsMe(player) then return end
	Block(player).all = on and true or nil
	Tidy(player)
end

-- Blocks (or unblocks) one message of a player's, by its words.
function Chat:BlockText(player, text, on)
	if not player or ns.IsMe(player) or type(text) ~= "string" or text == "" then return end
	Block(player).texts[text] = on and true or nil
	Tidy(player)
end

-- Whether a KekChat entry shows here: not from someone muted or blocked.
function Chat:Hides(entry)
	return self:IsMuted(entry.player) or self:IsBlocked(entry.player, entry.data and entry.data.text)
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
	if not saying and #icons == 0 and not say.text then
		return
	end
	local effect = #icons > 0 and say.effect and ns.ChatEffectById[say.effect] or nil
	local text = say.text and Chat.CleanText(say.text) or nil
	if text == "" then text = nil end
	if Chat:IsMuted(say.player) or Chat:IsBlocked(say.player, text) then
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
	local sound = say.sound and ns.KekSoundById[say.sound] or nil
	local entry = Entry(say.player, say.class, say.time or GetServerTime(), icons,
		saying and saying.id or nil, effect and effect.id or nil, say.virtual)
	entry.data.text, entry.data.sound = text, sound and sound.id or nil
	Bus:Fire("ENTRY_RECEIVED", entry)
	if saying and saying.effect then
		Bus:Fire("CHAT_EFFECT", saying.effect, say.player)
	end
	if effect then
		Bus:Fire("CHAT_PLAY", entry.data) -- its effect, over the feed
	end
	if sound and ns.IsEnabled("chatEffects") then
		Chat.PlayKekSound(sound.id)
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

-- Your KekChats to start with (data\chat.lua, KekDefaults), icons as file IDs.
local function DefaultKekMessages()
	local list = {}
	for _, default in ipairs(ns.KekDefaults) do
		local icon = IconID(default.icon)
		if (icon or default.text) and #list < ns.ChatRules.maxMessages then
			list[#list + 1] = {
				icon = icon,
				text = default.text,
				sound = ns.KekSoundById[default.sound] and default.sound or nil,
				effect = icon and ns.ChatEffectById[default.effect] and default.effect or nil,
			}
		end
	end
	return list
end

-- A list seeded from the old quick chats (0.3.8 before its release), never
-- given words of your own: it takes the new defaults instead.
local function OldSeed(list)
	local old = {}
	for _, saying in ipairs(ns.Sayings) do old[saying.text] = true end
	for _, message in pairs(list) do
		if message.text and not old[message.text] or message.sound or message.effect then return false end
	end
	return next(list) ~= nil
end

Bus:On("INIT", function()
	ns.db.muted = ns.db.muted or {}
	ns.db.chatPresets = ns.db.chatPresets or {}
	ns.db.kekBlocks = ns.db.kekBlocks or {}
	-- Your KekChats: the first time, the defaults, to change.
	if not ns.db.kekMessages or OldSeed(ns.db.kekMessages) then
		ns.db.kekMessages = DefaultKekMessages()
	end
	RestoreOldMessages()
	if ns.charDb then ns.charDb.chatPopped = nil end -- KekChat no longer pops out
	-- Presets from before a message carried a list of images.
	for _, preset in ipairs(ns.db.chatPresets) do
		if preset.icon then
			preset.icons, preset.icon = { preset.icon }, nil
		end
	end
end)
