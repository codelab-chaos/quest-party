-- Lab: a debug window for trying what the Forever client gives us (see
-- docs\idea.md, "What the Forever client gives us") before building it in.
-- One section per idea; where success is doubtful, two buttons try two ways.
-- Every action runs protected and says what happened on the status line.
-- Debug mode only: /qp lab (or /qps lab in the sandbox). Nothing is sent.
local _, ns = ...
local L = ns.L

local Lab = {}
ns.Lab = Lab

local LAYOUT = {
	width = 470,
	height = 600,
	pad = 10,
	button = 22,
	gap = 6,
	section = 16, -- space before each section
	model = 150,
	head = 64,
	stamp = 36,
	dockArea = 320, -- the magnetic dock's mock feed panel, its height
}

-- What the lab tries, as data.
local DATA = {
	creature = 448, -- Hogger: a creature id to start from
	animations = { stand = 0, death = 1, dead = 6 },
	fanfareKit = 259750, -- the shop's "fanfare" spell visual
	fanfareCreature = 27823, -- the creature the shop shows it on
	saying = "Gratz!",
	banner = "Quest Party: Gratz, everyone!",
	emote = "DANCE",
	stamps = {
		"QuestNormal", "QuestTurnin", "Waypoint-MapPin-Tracked", "VignetteKill", "VignetteKillElite",
		"vignettekillboss", "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged",
		"UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star", "ui-achievement-shield-1",
		"UI-Achievement-Shield-NoPoints", "BonusLoot-Chest", "LootToast-MoreAwesome",
		"questlog-questtypeicon-daily", "classicon-warrior", "classicon-mage", "raceicon128-human-male",
	},
}

local frame, content, status, creatureBox, model, head, cinematic
local y = 0

local function Say(text, good)
	status:SetText(text)
	status:SetTextColor(good and 0.4 or 1, good and 1 or 0.4, good and 0.5 or 0.4)
end

-- Runs one try: says it worked, or the error the game gave.
local function Try(label, action)
	local ok, result = pcall(action)
	if ok then
		Say(label .. ": " .. (result ~= nil and tostring(result) or "ok"), true)
	else
		Say(label .. ": " .. tostring(result))
	end
end

local function Heading(text, note)
	y = y + LAYOUT.section
	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	title:SetText(text)
	if note then
		local line = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		line:SetPoint("LEFT", title, "RIGHT", 8, 0)
		line:SetText(note)
	end
	y = y + 18
end

-- A row of buttons at the current y, from the left (or after left).
local function Buttons(list, left)
	local previous
	for _, entry in ipairs(list) do
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
		button:SetHeight(LAYOUT.button)
		button:SetText(entry[1])
		button:SetWidth(math.max(70, button:GetFontString():GetStringWidth() + 20))
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", LAYOUT.gap, 0)
		else
			button:SetPoint("TOPLEFT", left or LAYOUT.pad, -y)
		end
		button:SetScript("OnClick", function() Try(entry[1], entry[2]) end)
		previous = button
	end
	y = y + LAYOUT.button + LAYOUT.gap
end

local function CreatureId()
	return tonumber(creatureBox:GetText()) or DATA.creature
end

-- ========= 1. A 3D creature playing an animation ============================
local function BuildModel()
	Heading("1. 3D creature, animated", "creature id below, or your target")
	creatureBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	creatureBox:SetSize(70, 20)
	creatureBox:SetPoint("TOPLEFT", LAYOUT.pad + 6, -y)
	creatureBox:SetAutoFocus(false)
	creatureBox:SetNumeric(true)
	creatureBox:SetText(tostring(DATA.creature))
	y = y + 26
	model = CreateFrame("PlayerModel", nil, content)
	model:SetSize(LAYOUT.model, LAYOUT.model)
	model:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	local back = model:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)
	local top = y
	local left = LAYOUT.pad + LAYOUT.model + LAYOUT.gap
	y = top
	Buttons({
		{ "Show creature", function()
			model:SetCreature(CreatureId())
			return "display id " .. tostring(model:GetDisplayInfo())
		end },
	}, left)
	Buttons({
		{ "A: Death (1)", function() model:SetAnimation(DATA.animations.death) end },
		{ "B: Dead (6)", function() model:FreezeAnimation(DATA.animations.dead, 0, 1) end },
	}, left)
	Buttons({
		{ "Stand (0)", function() model:SetAnimation(DATA.animations.stand) end },
		{ "Me", function() model:SetUnit("player") end },
	}, left)
	Buttons({
		{ "A: My target's id", function()
			local id = UnitCreatureID and UnitCreatureID("target")
			if not id and C_CreatureInfo and UnitGUID then
				id = C_CreatureInfo.GetCreatureID(UnitGUID("target"))
			end
			creatureBox:SetText(tostring(id or ""))
			return id and ("creature " .. id) or "no creature id (no target, or hidden)"
		end },
		{ "B: Model my target", function() model:SetUnit("target") end },
	}, left)
	y = math.max(y, top + LAYOUT.model + LAYOUT.gap)
end

-- ========= 2. A creature's head as an image =================================
local function BuildHead()
	Heading("2. Creature head", "from the model's display id, or your target")
	head = content:CreateTexture(nil, "ARTWORK")
	head:SetSize(LAYOUT.head, LAYOUT.head)
	head:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	local top = y
	Buttons({
		{ "A: From display id", function()
			local display = model:GetDisplayInfo()
			if not display or display == 0 then error("show a creature in 1 first") end
			SetPortraitTextureFromCreatureDisplayID(head, display)
			return "display " .. display
		end },
		{ "B: My target", function() SetPortraitTexture(head, "target") end },
	}, LAYOUT.pad + LAYOUT.head + LAYOUT.gap)
	y = math.max(y, top + LAYOUT.head + LAYOUT.gap)
end

-- ========= 3. A spell visual on a model ======================================
local function BuildSpellKit()
	Heading("3. Spell visual (fanfare)", "kit " .. DATA.fanfareKit)
	cinematic = CreateFrame("CinematicModel", nil, content)
	cinematic:SetSize(LAYOUT.model, LAYOUT.model)
	cinematic:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	local back = cinematic:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)
	local top = y
	local left = LAYOUT.pad + LAYOUT.model + LAYOUT.gap
	Buttons({
		{ "A: Fanfare on me", function()
			cinematic:SetUnit("player")
			cinematic:SetSpellVisualKit(DATA.fanfareKit, true)
		end },
	}, left)
	Buttons({
		{ "B: On shop creature", function()
			cinematic:SetCreature(DATA.fanfareCreature)
			cinematic:SetSpellVisualKit(DATA.fanfareKit, true)
		end },
	}, left)
	y = math.max(y, top + LAYOUT.model + LAYOUT.gap)
end

-- ========= 4. Text to speech =================================================
local function Voice()
	local voices = C_VoiceChat.GetTtsVoices()
	local voice = voices and voices[1]
	if not voice then error("no voices (text to speech may be off in Options)") end
	return voice.voiceID
end

local function BuildSpeech()
	Heading("4. Speak a saying", '"' .. DATA.saying .. '", on your machine only')
	Buttons({
		{ "A: Speak", function()
			-- As the forever docs read: voice, text, rate, volume, overlap.
			C_VoiceChat.SpeakText(Voice(), DATA.saying, 0, 100, true)
		end },
		{ "B: Speak (retail way)", function()
			local destination = Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback or 1
			C_VoiceChat.SpeakText(Voice(), DATA.saying, destination, 0, 100)
		end },
		{ "Stop", function() C_VoiceChat.StopSpeakingText() end },
	})
end

-- ========= 5. A "meet here" waypoint ========================================
local function BuildWaypoint()
	Heading("5. Meet here", "a gold pin and arrow where you stand")
	Buttons({
		{ "Pin where I stand", function()
			local map = C_Map.GetBestMapForUnit("player")
			if not map then error("no map here") end
			if not C_Map.CanSetUserWaypointOnMap(map) then error("no pins on this map") end
			local position = C_Map.GetPlayerMapPosition(map, "player")
			if not position then error("no position here") end
			local mapX, mapY = position:GetXY()
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, mapX, mapY))
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			return ("map %d at %.1f, %.1f"):format(map, x * 100, y * 100)
		end },
		{ "Clear pin", function() C_Map.ClearUserWaypoint() end },
	})
end

-- ========= 6. A big banner, and a taskbar flash ==============================
local function BuildBanner()
	Heading("6. Banner and flash", "flash: alt-tab out within 3 seconds")
	Buttons({
		{ "A: Banner", function()
			RaidWarningUtil.AddMessage(DATA.banner, ChatTypeInfo and ChatTypeInfo.RAID_WARNING)
			ns.PlaySound(8959)
		end },
		{ "B: Banner (old way)", function()
			RaidNotice_AddMessage(RaidWarningFrame, DATA.banner, ChatTypeInfo.RAID_WARNING)
			ns.PlaySound(8959)
		end },
		{ "Flash in 3s", function()
			C_Timer.After(3, function() FlashClientIcon() end)
		end },
	})
end

-- ========= 7. Atlas stamps ===================================================
local function BuildStamps()
	Heading("7. Atlas stamps", "faded: the game does not have it")
	local columns = math.floor((LAYOUT.width - 2 * LAYOUT.pad - 20) / (LAYOUT.stamp + LAYOUT.gap))
	for index, atlas in ipairs(DATA.stamps) do
		local cell = CreateFrame("Frame", nil, content)
		cell:SetSize(LAYOUT.stamp, LAYOUT.stamp)
		local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
		cell:SetPoint("TOPLEFT", LAYOUT.pad + column * (LAYOUT.stamp + LAYOUT.gap), -(y + row * (LAYOUT.stamp + LAYOUT.gap)))
		local texture = cell:CreateTexture(nil, "ARTWORK")
		texture:SetAllPoints()
		local known = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
		if known then
			texture:SetAtlas(atlas)
		else
			texture:SetColorTexture(0.3, 0.3, 0.3, 0.4)
		end
		cell:EnableMouse(true)
		cell:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(atlas)
			GameTooltip:AddLine(known and "in the game" or "not found", 1, 1, 1)
			GameTooltip:Show()
		end)
		cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	y = y + math.ceil(#DATA.stamps / columns) * (LAYOUT.stamp + LAYOUT.gap)
end

-- ========= 8. An emote, from a click ========================================
local function BuildEmote()
	Heading("8. Emote", "your own character, from this click")
	Buttons({
		{ "A: Dance", function() C_ChatInfo.PerformEmote(DATA.emote) end },
		{ "B: Dance (old way)", function() DoEmote(DATA.emote) end },
	})
end

-- The magnetic event dock (ui\magnet-dock.lua) on a mock feed panel, with
-- made-up events: fire one, a burst, or clear it, and move the mouse over
-- the panel's right edge to pull the drawers out.
local MOCK_EVENTS = {
	{ icon = "Interface\\Icons\\XP_Icon", title = "Kills Defias Thug x4 for 200 XP", meta = "Orinion" },
	{ icon = "Interface\\Icons\\Achievement_Level_10", title = "Reached level 24!", meta = "Hala" },
	{ icon = "Interface\\Icons\\INV_Misc_Note_01", title = "Accepted: The Battleboars", meta = "Liowyn" },
	{ icon = "Interface\\Icons\\Trade_BlackSmithing", title = "Blacksmithing 149 > 150", meta = "Bramwick" },
	{ icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", title = "Died in Tanaris", meta = "Corel" },
	{ icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Discovered: Ashenvale", meta = "Maeric" },
	{ icon = "Interface\\Icons\\INV_Misc_Coin_02", title = "Completed: The Defias Brotherhood", meta = "Ulfdor" },
	{ icon = "Interface\\Icons\\Achievement_Quests_Completed_01", title = "Earned: Quest for the Quest Giver", meta = "Halys" },
}

-- ========= Card backdrops: which painted backdrops the game has =============
-- Atlases a card could use as its scene (docs\\scenes.md): the garrison and
-- class hall mission backdrops (a zone in three layers: Back, Mid, Fore) and
-- the group finder's buttons and backgrounds. The game names them by zone or
-- expansion, and only the game knows which it has: each candidate is asked
-- (C_Texture.GetAtlasInfo), those it has are shown, and the list is saved
-- (ns.db.atlasProbe) for reading after a /reload.
local BACKDROP_ZONES = {
	-- Draenor
	"FrostfireRidge", "FrostfireSea", "ShadowmoonValley", "ShadowmoonSea", "Gorgrond", "Talador", "SpiresofArak",
	"SpiresOfArak", "Nagrand", "TannanJungle", "Ashran", "Draenor", "BlackrockMountain", "Highmaul",
	-- Legion
	"Azsuna", "Valsharah", "ValSharah", "Highmountain", "Stormheim", "Suramar", "BrokenShore", "Argus", "Dalaran",
	"Azshara", "Krokuun", "MacAree", "Antoran", "Eredath", "BrokenIsles",
	-- Battle for Azeroth
	"Drustvar", "TiragardeSound", "Tiragarde", "StormsongValley", "Stormsong", "Zuldazar", "Nazmir", "Voldun",
	"KulTiras", "Kultiras", "Zandalar", "Nazjatar", "Mechagon", "Uldum", "Valley", "Boralus", "Darkshore", "Arathi",
	-- Shadowlands
	"Maw", "Bastion", "Maldraxxus", "Ardenweald", "Revendreth", "Oribos", "Korthia", "ZerethMortis",
	-- Elsewhere
	"Kalimdor", "EasternKingdoms", "Northrend", "Pandaria", "Outland", "Undercity", "Stormwind", "Orgrimmar",
	"Ironforge", "Silvermoon", "Exodar", "Darnassus", "ThunderBluff", "Barrens", "Desolace", "Tanaris",
}
local BACKDROP_LAYERS = { "Back", "Mid", "Fore" }
local GROUPFINDER = {
	"groupfinder-button-raids-classic", "groupfinder-button-raids-bc", "groupfinder-button-raids-wrathlk",
	"groupfinder-button-raids-wrath", "groupfinder-button-raids-cataclysm", "groupfinder-button-raids-mop",
	"groupfinder-button-raids-wod", "groupfinder-button-raids-legion", "groupfinder-button-raids-bfa",
	"groupfinder-button-raids-shadowlands", "groupfinder-button-raids-dragonflight", "groupfinder-button-dungeons",
	"groupfinder-button-scenarios", "groupfinder-button-questing", "groupfinder-button-pvp",
	"groupfinder-button-arenas", "groupfinder-button-battlegrounds", "groupfinder-button-ashran",
	"groupfinder-button-custom", "groupfinder-button-rated-battlegrounds", "groupfinder-background-dungeons",
	"groupfinder-background-raids", "groupfinder-background-scenarios", "groupfinder-background-questing",
	"groupfinder-background-pvp", "groupfinder-background-arenas", "groupfinder-background-battlegrounds",
}

local function Candidates()
	local names = {}
	for _, zone in ipairs(BACKDROP_ZONES) do
		for _, layer in ipairs(BACKDROP_LAYERS) do
			names[#names + 1] = "_GarrMissionLocation-" .. zone .. "-" .. layer
			names[#names + 1] = "GarrMissionLocation-" .. zone .. "-" .. layer
		end
		names[#names + 1] = "GarrMissionLocation-" .. zone
	end
	for _, name in ipairs(GROUPFINDER) do names[#names + 1] = name end
	return names
end

-- Asks the game for each candidate: { name, width, height } of those it has.
local function Probe()
	local found = {}
	local candidates = Candidates()
	for _, name in ipairs(candidates) do
		local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
		if info then
			found[#found + 1] = { name = name, width = info.width, height = info.height }
		end
	end
	ns.db.atlasProbe = { checked = #candidates, found = found, time = GetServerTime() }
	return found, #candidates
end

local function BuildBackdrops()
	Heading("Card backdrops", "which painted backdrops the game has")
	local previews = {}
	local note = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	note:SetPoint("RIGHT", content, "RIGHT", -LAYOUT.pad, 0)
	note:SetJustifyH("LEFT")
	note:SetText("Probe asks the game for each name; previews go at the bottom of the lab. /reload after it to save the list.")
	y = y + 16
	local listTop -- the lab's end, where the previews go (after every section)
	Buttons({ { "Probe", function()
		local found, checked = Probe()
		-- A preview strip for each, card shaped, its name over it, after the
		-- lab's last section.
		listTop = listTop or content:GetHeight()
		local top = listTop
		for index, atlas in ipairs(found) do
			local strip = previews[index]
			if not strip then
				strip = CreateFrame("Frame", nil, content)
				strip.texture = strip:CreateTexture(nil, "ARTWORK")
				strip.texture:SetAllPoints()
				strip.label = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				strip.label:SetPoint("BOTTOMLEFT", 3, 2)
				previews[index] = strip
			end
			strip:SetSize(LAYOUT.width - 60, 44)
			strip:ClearAllPoints()
			strip:SetPoint("TOPLEFT", LAYOUT.pad, -top)
			strip.texture:SetAtlas(atlas.name)
			strip.label:SetText(("%s  %dx%d"):format(atlas.name, atlas.width or 0, atlas.height or 0))
			strip:Show()
			top = top + 48
		end
		for index = #found + 1, #previews do previews[index]:Hide() end
		content:SetHeight(math.max(content:GetHeight(), top + LAYOUT.pad))
		return ("%d of %d found"):format(#found, checked)
	end } })
end

-- The garrison's class and spec emblems: which the game has, to pick stamp
-- emblems from (data\\stamps.lua). Names are GarrMission_ClassIcon-Class or
-- -Class-Spec.
local EMBLEM_CLASSES = {
	DeathKnight = { "Blood", "Frost", "Unholy" }, DemonHunter = { "Havoc", "Vengeance" },
	Druid = { "Balance", "Feral", "Guardian", "Restoration" }, Hunter = { "BeastMastery", "Marksmanship", "Survival" },
	Mage = { "Arcane", "Fire", "Frost" }, Monk = { "Brewmaster", "Mistweaver", "Windwalker" },
	Paladin = { "Holy", "Protection", "Retribution" }, Priest = { "Discipline", "Holy", "Shadow" },
	Rogue = { "Assassination", "Combat", "Outlaw", "Subtlety" }, Shaman = { "Elemental", "Enhancement", "Restoration" },
	Warlock = { "Affliction", "Demonology", "Destruction" }, Warrior = { "Arms", "Fury", "Protection" },
}

local function BuildEmblems()
	Heading("Stamp emblems", "the garrison's class and spec emblems the game has")
	local cells = {}
	Buttons({ { "Probe", function()
		local names = {}
		local classes = {}
		for class in pairs(EMBLEM_CLASSES) do classes[#classes + 1] = class end
		table.sort(classes)
		for _, class in ipairs(classes) do
			names[#names + 1] = "GarrMission_ClassIcon-" .. class
			for _, spec in ipairs(EMBLEM_CLASSES[class]) do
				names[#names + 1] = "GarrMission_ClassIcon-" .. class .. "-" .. spec
			end
		end
		local found = {}
		for _, name in ipairs(names) do
			if C_Texture.GetAtlasInfo(name) then found[#found + 1] = name end
		end
		-- A grid at the lab's end: each emblem with its name under it (hover
		-- for the whole name).
		local top = content:GetHeight()
		local size, columns = 48, 6
		local cellWidth = math.floor((LAYOUT.width - 60) / columns)
		for index, name in ipairs(found) do
			local cell = cells[index]
			if not cell then
				cell = CreateFrame("Frame", nil, content)
				cell.texture = cell:CreateTexture(nil, "ARTWORK")
				cell.texture:SetSize(size, size)
				cell.texture:SetPoint("TOP")
				cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				cell.label:SetPoint("TOP", cell.texture, "BOTTOM", 0, -1)
				cell.label:SetWidth(cellWidth)
				cell.label:SetWordWrap(false)
				cell:EnableMouse(true)
				cell:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:SetText(self.name)
					GameTooltip:Show()
				end)
				cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
				cells[index] = cell
			end
			local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
			cell:SetSize(cellWidth, size + 14)
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", LAYOUT.pad + column * cellWidth, -(top + row * (size + 18)))
			cell.texture:SetAtlas(name)
			cell.name = name
			cell.label:SetText((name:gsub("^GarrMission_ClassIcon%-", "")))
			cell:Show()
		end
		for index = #found + 1, #cells do cells[index]:Hide() end
		content:SetHeight(top + math.ceil(#found / columns) * (size + 18) + LAYOUT.pad)
		return ("%d of %d found"):format(#found, #names)
	end } })
end

local function BuildDock()
	Heading("Magnetic event dock", "move the mouse to the panel's right edge")
	local area = CreateFrame("Frame", nil, content, "BackdropTemplate")
	area:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	area:SetPoint("RIGHT", content, "RIGHT", -LAYOUT.pad, 0)
	area:SetHeight(LAYOUT.dockArea)
	area:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	area:SetBackdropColor(0.03, 0.03, 0.06, 1)
	area:SetBackdropBorderColor(0.80, 0.65, 0.20, 0.6)
	area:SetClipsChildren(true) -- drawers tuck under the panel's edge
	local note = area:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	note:SetPoint("CENTER", -30, 0)
	note:SetText("(the feed)")
	local count = 0
	local dock = ns.MagnetDock.Create(area, { side = "RIGHT", onClick = function(item)
		Say("Restored: " .. item.title, true)
	end })
	dock:GetFrame():SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -4, 8)
	local function Fire()
		count = count + 1
		local mock = MOCK_EVENTS[(count - 1) % #MOCK_EVENTS + 1]
		dock:Push({ id = count, icon = mock.icon, title = mock.title, meta = mock.meta })
	end
	y = y + LAYOUT.dockArea + LAYOUT.gap
	Buttons({
		{ "Event", Fire },
		{ "Burst of 5", function() for _ = 1, 5 do Fire() end end },
		{ "Fill 7 quietly", function()
			for _ = 1, 7 do
				count = count + 1
				local mock = MOCK_EVENTS[(count - 1) % #MOCK_EVENTS + 1]
				dock:Push({ id = count, icon = mock.icon, title = mock.title, meta = mock.meta }, true)
			end
		end },
		{ "Clear", function() dock:Clear() end },
	})
end

local function Build()
	frame = CreateFrame("Frame", ns.Globals.frame("Lab"), UIParent, "BackdropTemplate")
	frame:SetSize(LAYOUT.width, LAYOUT.height)
	frame:SetPoint("CENTER", 120, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
	frame:SetBackdropColor(0.05, 0.04, 0.08, 0.95)
	frame:SetBackdropBorderColor(0.80, 0.65, 0.20, 1)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, frame:GetName())
	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LAYOUT.pad, -8)
	title:SetText("Quest Party lab")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 1, 1)
	status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", LAYOUT.pad, 8)
	status:SetPoint("BOTTOMRIGHT", -LAYOUT.pad, 8)
	status:SetJustifyH("LEFT")
	status:SetText("Try something. What happens shows here.")

	local scroll = CreateFrame("ScrollFrame", nil, frame, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -30)
	scroll:SetPoint("BOTTOMRIGHT", -26, 26)
	content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(LAYOUT.width - 34)
	scroll:SetScrollChild(content)

	for _, section in ipairs({ BuildEmblems, BuildBackdrops, BuildDock, BuildModel, BuildHead, BuildSpellKit, BuildSpeech, BuildWaypoint, BuildBanner, BuildStamps, BuildEmote }) do
		local ok, problem = pcall(section)
		if not ok then
			Heading("(a section could not be built)", tostring(problem))
		end
	end
	content:SetHeight(y + LAYOUT.pad)
end

function Lab:Toggle()
	if not ns.IsDebug() then
		ns.Print(L.CMD_DEBUG_REQUIRED)
		return
	end
	if not frame then
		Build()
		frame:Show()
		return
	end
	frame:SetShown(not frame:IsShown())
end
