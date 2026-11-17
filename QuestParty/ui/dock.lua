-- Dock: Quest Party minimized to a small movable housing (first at the
-- right edge of the screen, or the left with Dock on the right off), as a
-- magnetic event dock (ui\magnet-dock.lua): the last events rest in it as
-- keys, newest at the bottom, and the cursor pulls the nearest ones out to
-- show who did what. Keys come out toward the middle of the screen: to the
-- left when the housing is on the right half, to the right otherwise. A new
-- event glides in at the bottom and shows itself a moment. Clicking a drawer
-- opens the panel on that event (ui\panel.lua, Restore and FocusEntry; a
-- KekChat message opens KekChat). This file only turns Quest Party's events
-- into the dock's items; the dock itself knows nothing of them.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local Dock = {}
ns.Dock = Dock

local LAYOUT = {
	edgeGap = 0,
}

local view
local nextId = 0

-- Which way keys come out: toward the middle of the screen.
local function Side()
	local frame = view and view:GetFrame()
	local x = ns.charDb.dockPoint and frame and frame:GetCenter()
	if x then
		return x > UIParent:GetWidth() / 2 and "RIGHT" or "LEFT"
	end
	return ns.IsEnabled("dockRight") and "RIGHT" or "LEFT"
end

-- An item for the dock: { id, icon, title, meta } plus what a click needs.
local function Push(item, quiet)
	nextId = nextId + 1
	item.id = nextId
	if view then view:Push(item, quiet) end
end

local function FeedItem(entry)
	local def = ns.FeedTypes[entry.type]
	local ok, summary = pcall(ns.Resolver.Summary, entry)
	return {
		icon = def and def.icon,
		title = ok and summary or "",
		meta = entry.player and ns.ColorName(entry.player, entry.class) or nil,
		entry = entry,
	}
end

Bus:On("FEED_ADDED", function(entry, def)
	if not def or not ns.charDb.docked then return end
	Push(FeedItem(entry))
end)

Bus:On("CHAT_CHANGED", function(message)
	if not message or message.system or not ns.charDb.docked then return end
	local saying = message.saying and ns.SayingById[message.saying]
	Push({
		icon = message.icons and message.icons[1] or "Interface\\Icons\\INV_Misc_Note_01",
		title = saying and saying.text or L.DOCK_IMAGE,
		meta = message.player and ns.ColorName(message.player, message.class) or nil,
		chat = true,
	})
end)

-- A drawer clicked: the panel opens on what it stood for.
local function Open(item)
	if item.chat then
		ns.Panel:Restore("chat")
		return
	end
	ns.Panel:Restore()
	if item.entry and item.entry.sequence then
		ns.Panel:FocusEntry(item.entry.sequence)
	end
end

-- ========= Where it sits ===================================================
local function AtEdge(frame)
	frame:ClearAllPoints()
	if ns.IsEnabled("dockRight") then
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -LAYOUT.edgeGap, 0)
	else
		frame:SetPoint("LEFT", UIParent, "LEFT", LAYOUT.edgeGap, 0)
	end
end

-- Whether the whole housing is on the screen.
local function OnScreen(frame)
	local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
	if not (left and right and top and bottom) then return true end -- not laid out yet
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	return left >= -1 and bottom >= -1 and right <= width + 1 and top <= height + 1
end

-- Where it was moved to (ns.charDb.dockPoint: the point, the screen point it
-- is tied to, and the offsets, as the game gives them after a drag), or first
-- at a screen edge. A saved place that is off the screen (or in an older,
-- shorter form) is forgotten.
local function Place()
	local frame = view:GetFrame()
	local saved = ns.charDb.dockPoint
	if saved and #saved == 4 then
		frame:ClearAllPoints()
		frame:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
		if OnScreen(frame) then return end
	end
	ns.charDb.dockPoint = nil
	AtEdge(frame)
end

local function Moved(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.charDb.dockPoint = { point, relativePoint or point, x, y }
	view:SetSide(Side())
end

-- Docking fills the dock with the feed's latest rows, quietly, oldest first
-- so the newest ends at the bottom.
function Dock:Show()
	if not view then return end
	Place()
	view:SetSide(Side())
	view:GetFrame():Show()
	view:Clear()
	local feed = ns.Store:GetFeed(true) -- newest first
	for index = math.min(#feed, ns.Magnet.DEFAULTS.maxEntries), 1, -1 do
		Push(FeedItem(feed[index]), true)
	end
end

function Dock:Hide()
	if not view then return end
	view:GetFrame():Hide()
	view:Clear() -- the panel shows them now; the next docking starts empty
end

-- Where the panel shrinks to and grows from: the housing.
function Dock:Point()
	if view then
		Place()
		local x, y = view:GetFrame():GetCenter()
		if x then return x, y end
	end
	return ns.IsEnabled("dockRight") and UIParent:GetWidth() or 0, UIParent:GetHeight() / 2
end

local function Build()
	view = ns.MagnetDock.Create(UIParent, { side = Side(), onClick = Open, onMoved = Moved })
	local frame = view:GetFrame()
	frame:SetFrameStrata("MEDIUM")
	frame:Hide()
	Place()
end

Bus:On("READY", Build)
Bus:On("SETTING_CHANGED", function(id)
	if id == "dockRight" and view then
		ns.charDb.dockPoint = nil -- back to the chosen edge
		Place()
		view:SetSide(Side())
	end
end)
