-- Dock: Quest Party minimized to the edge of the screen (left, or right with
-- Dock on the right). Recent events (feed rows and KekChat messages) stand as
-- thin stick bars; as the mouse comes near they grow toward it, the nearest
-- most, like the macOS dock, and the one under it says what it was. Click a
-- bar to open the panel again (ui\panel.lua, Restore). While docked, each new
-- event puffs its icon out of the dock (ui\particles.lua).
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local Dock = { items = {} }
ns.Dock = Dock

local LAYOUT = {
	maxItems = 14, -- bars shown, newest on top
	barWidth = 24, -- a resting stick
	barHeight = 5,
	grownWidth = 70, -- fully grown, under the mouse
	grownHeight = 26,
	gap = 3,
	reach = 220, -- how far from the edge the mouse starts to matter
	radius = 70, -- how far up and down a bar feels the mouse
	ease = 12, -- how quickly bars follow (per second)
	icon = 20,
	puffSize = 180, -- the area a puff plays over
	edgeGap = 2,
}

local COLORS = {
	feed = { 0.80, 0.65, 0.20, 0.95 },
	chat = { 0.45, 0.70, 1.00, 0.95 },
	back = { 0, 0, 0, 0.55 },
	label = { 1, 1, 1 },
}

local frame, puff
local bars = {}

local function Right()
	return ns.IsEnabled("dockRight")
end

-- ========= What the bars stand for ==========================================
local function ClassColor(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	return color and { color.r, color.g, color.b, 0.95 } or nil
end

local function Add(item)
	table.insert(Dock.items, 1, item)
	while #Dock.items > LAYOUT.maxItems do
		table.remove(Dock.items)
	end
	if frame and frame:IsShown() then
		Dock:Draw()
		Dock:Puff(item)
	end
end

Bus:On("FEED_ADDED", function(entry, def)
	if not def then return end
	local ok, summary = pcall(ns.Resolver.Summary, entry)
	Add({
		kind = "feed",
		icon = def.icon,
		color = ClassColor(entry.class) or COLORS.feed,
		label = (entry.player and (entry.player .. ": ") or "") .. (ok and summary or ""),
	})
end)

Bus:On("CHAT_CHANGED", function(message)
	if not message or message.system then return end
	local saying = message.saying and ns.SayingById[message.saying]
	Add({
		kind = "chat",
		icon = message.icons and message.icons[1] or "Interface\\Icons\\INV_Misc_Note_01",
		color = ClassColor(message.class) or COLORS.chat,
		label = (message.player or "") .. ": " .. (saying and saying.text or "(image)"),
	})
end)

-- ========= Drawing ==========================================================
local function CreateBar()
	local bar = CreateFrame("Button", nil, frame)
	bar.fill = bar:CreateTexture(nil, "BACKGROUND")
	bar.fill:SetAllPoints()
	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetSize(LAYOUT.icon, LAYOUT.icon)
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.label:SetWordWrap(false)
	bar.label:SetShadowOffset(1, -1)
	bar.scale = 1
	bar:SetScript("OnClick", function(self)
		ns.Panel:Restore(self.item and self.item.kind == "chat" and "chat" or nil)
	end)
	return bar
end

-- Lays the bars out for their current growth: each as wide and tall as its
-- scale says, stacked from the middle of the screen, out from the edge.
local function Layout()
	local right = Right()
	local total = 0
	for index = 1, #Dock.items do
		local bar = bars[index]
		local grow = bar.scale - 1
		bar.height = LAYOUT.barHeight + grow * (LAYOUT.grownHeight - LAYOUT.barHeight)
		total = total + bar.height + LAYOUT.gap
	end
	local top = total / 2
	for index = 1, #Dock.items do
		local bar = bars[index]
		local grow = bar.scale - 1
		local width = LAYOUT.barWidth + grow * (LAYOUT.grownWidth - LAYOUT.barWidth)
		bar:SetSize(width, bar.height)
		bar:ClearAllPoints()
		bar:SetPoint(right and "TOPRIGHT" or "TOPLEFT", frame, right and "RIGHT" or "LEFT", 0, top)
		bar.center = top - bar.height / 2
		top = top - bar.height - LAYOUT.gap
		local showIcon = grow > 0.35
		bar.icon:SetShown(showIcon)
		bar.icon:SetAlpha(math.min(1, (grow - 0.35) * 2.5))
		bar.icon:ClearAllPoints()
		bar.icon:SetPoint(right and "LEFT" or "RIGHT", bar, right and "LEFT" or "RIGHT", right and 3 or -3, 0)
		bar.icon:SetSize(math.min(LAYOUT.icon, bar.height - 4), math.min(LAYOUT.icon, bar.height - 4))
	end
end

function Dock:Draw()
	if not frame then return end
	for index, item in ipairs(self.items) do
		local bar = bars[index] or CreateBar()
		bars[index] = bar
		bar.item = item
		bar.fill:SetColorTexture(unpack(item.color))
		bar.icon:SetTexture(item.icon)
		bar.label:SetText(item.label)
		bar:Show()
	end
	for index = #self.items + 1, #bars do
		bars[index]:Hide()
	end
	Layout()
end

-- Each frame: every bar eases toward how much the mouse says it should grow.
-- Far from the dock, they all rest; the nearest shows its line.
local function OnUpdate(_, elapsed)
	if #Dock.items == 0 then return end
	local scale = UIParent:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	cursorX, cursorY = cursorX / scale, cursorY / scale
	local fromEdge = Right() and (UIParent:GetWidth() - cursorX) or cursorX
	local middle = UIParent:GetHeight() / 2
	local near = fromEdge < LAYOUT.reach
	local closest, closestDistance
	local moving = false
	for index = 1, #Dock.items do
		local bar = bars[index]
		local distance = math.abs((middle + (bar.center or 0)) - cursorY)
		local target = 1
		if near then
			local pull = math.max(0, 1 - distance / LAYOUT.radius) * (1 - fromEdge / LAYOUT.reach * 0.5)
			target = 1 + pull
			if not closestDistance or distance < closestDistance then
				closest, closestDistance = bar, distance
			end
		end
		local step = math.min(1, elapsed * LAYOUT.ease)
		local before = bar.scale
		bar.scale = bar.scale + (target - bar.scale) * step
		if math.abs(bar.scale - before) > 0.001 then moving = true end
	end
	if moving then Layout() end
	for index = 1, #Dock.items do
		local bar = bars[index]
		local showLabel = bar == closest and closestDistance < LAYOUT.radius / 2 and bar.scale > 1.4
		bar.label:SetShown(showLabel)
		if showLabel then
			bar.label:ClearAllPoints()
			if Right() then
				bar.label:SetPoint("RIGHT", bar, "LEFT", -6, 0)
			else
				bar.label:SetPoint("LEFT", bar, "RIGHT", 6, 0)
			end
		end
	end
end

-- A small burst of the item's icon out of the dock, at the top bar.
function Dock:Puff(item)
	if not puff or not ns.IsEnabled("chatEffects") or not item.icon then return end
	local bar = bars[1]
	puff:ClearAllPoints()
	puff:SetPoint("CENTER", bar or frame, Right() and "LEFT" or "RIGHT", 0, 0)
	ns.ParticleView:Play(puff, ns.DockPuff, { item.icon })
end

-- ========= Showing and hiding ===============================================
local function Place()
	frame:ClearAllPoints()
	if Right() then
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -LAYOUT.edgeGap, 0)
	else
		frame:SetPoint("LEFT", UIParent, "LEFT", LAYOUT.edgeGap, 0)
	end
end

function Dock:Show()
	if not frame then return end
	Place()
	frame:Show()
	self:Draw()
end

function Dock:Hide()
	if frame then frame:Hide() end
end

-- Where the panel shrinks to and grows from: the dock's edge, mid screen.
function Dock:Point()
	local right = Right()
	return right and UIParent:GetWidth() or 0, UIParent:GetHeight() / 2
end

local function Build()
	frame = CreateFrame("Frame", ns.Globals.frame("Dock"), UIParent)
	frame:SetSize(LAYOUT.grownWidth + 4, (LAYOUT.grownHeight + LAYOUT.gap) * LAYOUT.maxItems)
	frame:SetFrameStrata("MEDIUM")
	frame:SetScript("OnUpdate", OnUpdate)
	frame:Hide()
	puff = CreateFrame("Frame", nil, UIParent)
	puff:SetSize(LAYOUT.puffSize, LAYOUT.puffSize)
	puff:SetFrameStrata("HIGH")
	Place()
end

Bus:On("READY", Build)
Bus:On("SETTING_CHANGED", function(id)
	if id == "dockRight" and frame and frame:IsShown() then
		Place()
		Dock:Draw()
	end
end)
