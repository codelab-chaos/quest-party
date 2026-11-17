-- Magnetic dock: a reusable view of a Magnet (magnet.lua). A small movable
-- housing holds a stack of drawers packed like piano keys, one against the
-- next with a thin gold line between. Each drawer is the size of a feed
-- row: an icon, then what happened, and who under it. At rest only the icon end shows, inside the
-- housing; the cursor pulls the nearest drawers out of the housing along
-- their rails (only sideways, slots fixed) in a smooth wave, and they glide
-- back in when it leaves. The housing clips them, so it can sit anywhere on
-- screen. Drag the housing (or any drawer) to move it.
--
-- Knows nothing of feed entries: items are { id, icon, title, meta } and a
-- click hands the item back.
--
--   local dock = ns.MagnetDock.Create(parent, { side = "RIGHT", onClick = fn, onMoved = fn })
--   dock:Push(item, quiet)  dock:Remove(id)  dock:Clear()  dock:SetSide(side)
--   dock:GetFrame()  -- the housing: place it, show it, hide it
--
-- side "RIGHT": drawers come out to the left (the housing sits at the right
-- of where they go); "LEFT": they come out to the right.
local _, ns = ...

local MagnetDock = {}
ns.MagnetDock = MagnetDock

MagnetDock.LAYOUT = {
	-- A key is a feed row's size (ui\panel.lua, the detailed style).
	key = 40, -- one drawer, top to bottom: they touch, like piano keys
	peek = 36, -- what shows at rest, inside the housing: the icon end
	extend = 330, -- how far a drawer can come out of the housing, at most;
	-- each comes out only as far as its own text needs (Fit)
	textPad = 14, -- past the end of a key's text
	icon = 26,
	pad = 3, -- the housing's frame around the keys
	radius = 56, -- how far up and down the cursor's pull reaches: about a key either side
	reach = 90, -- how far beyond a fully out drawer it starts to pull
}

MagnetDock.COLORS = {
	housing = { 0.03, 0.03, 0.06, 0.96 },
	housingRim = { 0.80, 0.65, 0.20, 1 },
	key = { 0.06, 0.07, 0.14, 0.98 },
	keyTarget = { 0.12, 0.15, 0.30, 1 }, -- the drawer the cursor is on
	line = { 0.80, 0.65, 0.20, 0.55 }, -- the thin line between keys
	lineTarget = { 1, 0.85, 0.35, 1 },
	meta = { 0.75, 0.75, 0.75 },
}

-- Flat, with a one-pixel edge: keys stack with a hairline between them.
local KEY_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
}

local HOUSING_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local View = {}
View.__index = View

-- ========= Moving the housing ==============================================
local function StartMove(view)
	view.frame:StartMoving()
	view.moving = true
end

local function StopMove(view)
	view.frame:StopMovingOrSizing()
	view.moving = false
	view.movedAt = GetTime()
	if view.onMoved then view.onMoved(view.frame) end
end

-- ========= Keys ============================================================
local function NewKey(view)
	local layout = view.layout
	local key = CreateFrame("Button", nil, view.clip, "BackdropTemplate")
	key:SetSize(layout.peek + layout.extend, layout.key)
	key:SetBackdrop(KEY_BACKDROP)
	key.icon = key:CreateTexture(nil, "ARTWORK")
	key.icon:SetSize(layout.icon, layout.icon)
	key.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	key.text = key:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	key.text:SetWordWrap(false)
	key.meta = key:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	key.meta:SetWordWrap(false)
	key:RegisterForDrag("LeftButton")
	key:SetScript("OnDragStart", function() StartMove(view) end)
	key:SetScript("OnDragStop", function() StopMove(view) end)
	key:SetScript("OnClick", function(self)
		local entry = self.entry
		if not entry or entry.leaving then return end
		if view.movedAt and GetTime() - view.movedAt < 0.3 then return end -- the end of a drag
		if view.onClick then view.onClick(entry.item) end
		view.model:Remove(entry.item.id) -- it retracts and fades: restored
		view:Wake()
	end)
	return key
end

-- How far a key travels: just past the end of its longer line, no further.
local function Width(fontString)
	if fontString.GetUnboundedStringWidth then
		return fontString:GetUnboundedStringWidth()
	end
	return fontString:GetStringWidth()
end

local function Fit(view, key)
	local layout = view.layout
	local text = math.max(Width(key.text), Width(key.meta))
	key.travel = math.max(layout.icon, math.min(layout.extend, math.ceil(text) + 4 + layout.textPad))
	key:SetWidth(layout.peek + key.travel)
end

-- Lays a key out for its side: the icon at the leading end (the one that
-- rests in the housing), then the title and the meta line under it, as a
-- feed row's, clipped to the key.
local function Dress(view, key)
	local right = view.side == "RIGHT"
	local lead = right and "LEFT" or "RIGHT"
	local far = right and "RIGHT" or "LEFT"
	local away = right and 1 or -1
	key.icon:ClearAllPoints()
	key.text:ClearAllPoints()
	key.meta:ClearAllPoints()
	key.icon:SetPoint(lead, (view.layout.peek - view.layout.icon) / 2 * away, 0)
	-- The title just above the middle, the meta line just below it.
	key.text:SetPoint("BOTTOM" .. lead, key, lead, (view.layout.peek + 4) * away, 1)
	key.text:SetPoint(far, key, far, -8 * away, 0)
	key.meta:SetPoint("TOP" .. lead, key, lead, (view.layout.peek + 4) * away, -2)
	key.meta:SetPoint(far, key, far, -8 * away, 0)
	key.text:SetJustifyH(right and "LEFT" or "RIGHT")
	key.meta:SetJustifyH(right and "LEFT" or "RIGHT")
end

-- The housing's size and the clip region the keys travel in: as wide as the
-- housing plus how far keys come out, on the side they come out.
local function Shape(view)
	local layout = view.layout
	local keys = view.model.config.maxEntries
	view.frame:SetSize(layout.peek + 2 * layout.pad, keys * layout.key + 2 * layout.pad)
	view.clip:ClearAllPoints()
	if view.side == "RIGHT" then
		view.clip:SetPoint("TOPRIGHT", -layout.pad, -layout.pad)
		view.clip:SetPoint("BOTTOMRIGHT", -layout.pad, layout.pad)
	else
		view.clip:SetPoint("TOPLEFT", layout.pad, -layout.pad)
		view.clip:SetPoint("BOTTOMLEFT", layout.pad, layout.pad)
	end
	view.clip:SetWidth(layout.peek + layout.extend)
end

-- ========= The pull ========================================================
-- How hard the cursor pulls an entry: by how far it is up or down from the
-- entry's key, and how near it is to the housing on the side keys come out.
function View:Pull(entry, cursorX, cursorY)
	local layout = self.layout
	local frame = self.frame
	local inner = self.side == "RIGHT" and frame:GetRight() or frame:GetLeft()
	local bottom = frame:GetBottom()
	if not (inner and bottom and cursorX) then return 0 end
	local center = bottom + layout.pad + (entry.slot - 0.5) * layout.key
	local across
	if self.side == "RIGHT" then
		across = inner - cursorX -- from the housing's far edge, toward where keys go
	else
		across = cursorX - inner
	end
	if across < 0 then return 0 end -- past the housing, on the other side
	-- Over a fully out key it stays out; further off, the pull fades.
	local key = self.keys[entry.item.id]
	local travel = key and key.travel or layout.extend
	local near = math.max(0, math.min(1, 1 - (across - (layout.peek + travel)) / layout.reach))
	return ns.Magnet.Influence(cursorY - center, layout.radius) * near
end

-- ========= Drawing =========================================================
function View:Draw()
	local layout, colors = self.layout, MagnetDock.COLORS
	local right = self.side == "RIGHT"
	-- The key the cursor is on gets the bright line and sits on top.
	local target, best
	for _, entry in ipairs(self.model.entries) do
		if not entry.leaving and entry.extension > 0.15 and (not best or entry.extension > best) then
			target, best = entry, entry.extension
		end
	end
	local used = {}
	for _, entry in ipairs(self.model.entries) do
		local key = self.keys[entry.item.id]
		if not key then
			key = table.remove(self.pool) or NewKey(self)
			self.keys[entry.item.id] = key
			key.icon:SetTexture(entry.item.icon)
			key.text:SetText(entry.item.title or "")
			key.meta:SetText(entry.item.meta or "")
			Dress(self, key)
			Fit(self, key)
			key:Show()
		end
		key.entry = entry
		used[entry.item.id] = true
		-- Only sideways: x from how far out, y from the slot. Out no further
		-- than the key is long, and never back past rest.
		local travel = key.travel or layout.extend
		local out = travel * math.max(0, math.min(1, entry.extension))
		local y = (entry.slot - 1) * layout.key
		key:ClearAllPoints()
		if right then
			key:SetPoint("BOTTOMLEFT", self.clip, "BOTTOMRIGHT", -layout.peek - out, y)
		else
			key:SetPoint("BOTTOMRIGHT", self.clip, "BOTTOMLEFT", layout.peek + out, y)
		end
		-- Only the part that shows takes the mouse: the rest, hidden past the
		-- housing, must not catch clicks meant for the world.
		local hidden = math.max(0, travel - out)
		if right then key:SetHitRectInsets(0, hidden, 0, 0) else key:SetHitRectInsets(hidden, 0, 0, 0) end
		key:SetAlpha(entry.alpha)
		local isTarget = entry == target
		key:SetBackdropColor(unpack(isTarget and colors.keyTarget or colors.key))
		key:SetBackdropBorderColor(unpack(isTarget and colors.lineTarget or colors.line))
		key:SetFrameLevel(self.clip:GetFrameLevel() + 2 + math.floor(entry.extension * 20) + (isTarget and 30 or 0))
		local shown = math.max(0, math.min(1, (entry.extension - 0.1) * 2))
		key.text:SetAlpha(shown)
		key.meta:SetAlpha(shown)
	end
	for id, key in pairs(self.keys) do
		if not used[id] then
			key:Hide()
			key.entry = nil
			self.keys[id] = nil
			self.pool[#self.pool + 1] = key
		end
	end
end

function View:Update(elapsed)
	local scale = self.frame:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local cursorX, cursorY = x / scale, y / scale
	self.model:Step(math.min(elapsed, 0.1), function(entry)
		if self.moving then return 0 end
		return self:Pull(entry, cursorX, cursorY)
	end)
	self:Draw()
end

-- Runs while there is anything to see; an empty dock does no work.
function View:Wake()
	if self.frame:GetScript("OnUpdate") then return end
	self.frame:SetScript("OnUpdate", function(_, elapsed)
		self:Update(elapsed)
		if #self.model.entries == 0 and #self.model.queue == 0 then
			self.frame:SetScript("OnUpdate", nil)
		end
	end)
end

function View:Push(item, quiet)
	self.model:Push(item, quiet)
	self:Wake()
end

function View:Remove(id)
	self.model:Remove(id)
	self:Wake()
end

function View:Clear()
	self.model:Clear()
	self:Draw()
end

function View:SetSide(side)
	self.side = side == "LEFT" and "LEFT" or "RIGHT"
	Shape(self)
	for _, key in pairs(self.keys) do Dress(self, key) end
	self:Draw()
end

function View:GetFrame()
	return self.frame
end

-- options: side ("RIGHT" or "LEFT"), onClick(item), onMoved(housing),
-- layout (overrides of LAYOUT), model (overrides of Magnet.DEFAULTS).
function MagnetDock.Create(parent, options)
	options = options or {}
	local layout = {}
	for key, value in pairs(MagnetDock.LAYOUT) do
		layout[key] = (options.layout and options.layout[key]) or value
	end
	local view = setmetatable({
		layout = layout,
		model = ns.Magnet.New(options.model),
		onClick = options.onClick,
		onMoved = options.onMoved,
		keys = {},
		pool = {},
	}, View)
	view.side = options.side == "LEFT" and "LEFT" or "RIGHT"

	local housing = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	housing:SetBackdrop(HOUSING_BACKDROP)
	housing:SetBackdropColor(unpack(MagnetDock.COLORS.housing))
	housing:SetBackdropBorderColor(unpack(MagnetDock.COLORS.housingRim))
	housing:SetMovable(true)
	housing:SetClampedToScreen(true)
	housing:EnableMouse(true)
	housing:RegisterForDrag("LeftButton")
	housing:SetScript("OnDragStart", function() StartMove(view) end)
	housing:SetScript("OnDragStop", function() StopMove(view) end)
	view.frame = housing

	-- The keys travel in here, and nothing of them shows outside it.
	view.clip = CreateFrame("Frame", nil, housing)
	view.clip:SetClipsChildren(true)
	Shape(view)
	return view
end
