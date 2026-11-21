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
local Bus = ns.Bus

local Dock = {}
ns.Dock = Dock

local LAYOUT = {
	edgeGap = 0,
}

-- The drawers: feed rows this long. At rest the housing shows each row's
-- mark and half its avatar (Panel:DockRest); sliding out shows the rest.
-- Compact dock (Settings): one-line rows, so twice as many fit.
local DRAWER = { length = 232, entries = 7, compactEntries = 14 }

local view
local nextId = 0
local items = {} -- the dock's items by id, for their stamps

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
	items[nextId] = item
	if view then view:Push(item, quiet) end
end

-- A drawer is the feed's own row for its entry (ui\panel.lua), drawn in the
-- dock's style: the same look, stamps, tooltip and right-click as the feed.
local function DockStyle()
	return ns.IsEnabled("dockCompact") and "oneLine" or "detailed"
end

local function FeedItem(entry)
	return { entry = entry }
end

-- Every drawer drawn again: for the side they come out on now.
local function RedrawAll()
	if not view then return end
	for itemId in pairs(items) do view:Retext(itemId) end
end

-- Fills a drawer with its row (made once per drawer, drawn again for each
-- entry it shows); a click restores the panel on it.
local function Content(key, item)
	if not key.row then
		key.row = ns.Panel:NewFeedRow(key)
		key.row:SetAllPoints(key)
	end
	key.row.onLeftClick = function() key:Click("LeftButton") end
	local data = ns.ViewModel:FeedRowFor(item.entry)
	data.right = nil -- no time since: the dock is about what just happened
	-- The mark and the avatar at the end resting in the housing (ui\panel.lua,
	-- TextEnds): the right end on a left-side dock, the left on a right-side one.
	data.ends = (view ~= nil and view.side == "LEFT") and "RIGHT" or "LEFT"
	ns.Panel:DrawFeedRow(key.row, data, DockStyle())
	return key.row
end

Bus:On("FEED_ADDED", function(entry, def)
	if not def or not ns.charDb.docked then return end
	Push(FeedItem(entry))
end)

-- A stamp landed: any drawer for that card is drawn again, with it.
Bus:On("STAMPED", function(key)
	if not view then return end
	for id, item in pairs(items) do
		if item.entry and ns.Stamping:KeyFor(item.entry) == key then
			view:Retext(id)
		end
	end
end)

-- A drawer clicked: the panel opens on what it stood for.
local function Open(item)
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
	RedrawAll()
end

-- Docking fills the dock with the feed's latest rows, quietly, oldest first
-- so the newest ends at the bottom.
function Dock:Show()
	if not view then return end
	Place()
	view:SetSide(Side())
	RedrawAll()
	view:GetFrame():Show()
	view:Clear()
	wipe(items)
	local feed = ns.Store:GetFeed(true) -- newest first
	for index = math.min(#feed, view.model.config.maxEntries), 1, -1 do
		Push(FeedItem(feed[index]), true)
	end
end

function Dock:Hide()
	if not view then return end
	view:GetFrame():Hide()
	view:Clear() -- the panel shows them now; the next docking starts empty
	wipe(items)
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
	local compact = ns.IsEnabled("dockCompact")
	view = ns.MagnetDock.Create(UIParent, {
		side = Side(), onClick = Open, onMoved = Moved, content = Content,
		layout = (function()
			local peek = math.ceil(ns.Panel:DockRest(DockStyle()))
			return { key = ns.Panel:FeedRowHeight(DockStyle()), peek = peek, extend = DRAWER.length - peek }
		end)(),
		model = { maxEntries = compact and DRAWER.compactEntries or DRAWER.entries },
	})
	local frame = view:GetFrame()
	frame:SetFrameStrata("MEDIUM")
	frame:Hide()
	Place()
end

Bus:On("READY", Build)
Bus:On("SETTING_CHANGED", function(id)
	-- Compact dock: a new dock in the new shape, where the old one was.
	if id == "dockCompact" and view then
		local shown = view:GetFrame():IsShown()
		view:GetFrame():Hide()
		Build()
		view:GetFrame():SetShown(shown)
		return
	end
	if id == "dockRight" and view then
		ns.charDb.dockPoint = nil -- back to the chosen edge
		Place()
		view:SetSide(Side())
		RedrawAll()
	end
end)
