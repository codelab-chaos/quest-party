-- Scenes: which painted scene a feed entry gets, and the part of the atlas
-- that fills a card of a given size (data\scenes.lua). Plain data and math:
-- ui\look.lua puts it on a texture.
local addonName, ns = ...

local Scenes = {}
ns.Scene = Scenes

-- The scene for a feed entry ({ type, data }), or nil for none.
function Scenes:For(entry)
	if not entry then return nil end
	local id
	if entry.type == "skill" and entry.data then
		id = ns.SceneBySkill[entry.data.skill or entry.data.name or ""]
	end
	id = id or ns.SceneByType[entry.type]
	return id and ns.SceneById[id] or nil
end

-- The atlas file, from this addon's own folder (the sandbox has its own).
function Scenes:File()
	return "Interface\\AddOns\\" .. addonName .. "\\" .. ns.SceneAtlas.file
end

-- Texture coordinates (left, right, top, bottom) of a scene, cropped about
-- its middle to a card width x height so it is never stretched: a card wider
-- than the cell's 8 to 1 shows a band across the middle, a taller one shows
-- the middle part of its width. Half a texel in from each edge, so the next
-- cell never bleeds in.
function Scenes:Coords(scene, width, height)
	local atlas = ns.SceneAtlas
	local column = (scene.index - 1) % atlas.columns
	local row = math.floor((scene.index - 1) / atlas.columns)
	local left, top = column * atlas.cellWidth, row * atlas.cellHeight
	local cellWidth, cellHeight = atlas.cellWidth, atlas.cellHeight
	if width and height and width > 0 and height > 0 then
		local wanted = width / height
		local cell = cellWidth / cellHeight
		if wanted > cell then
			local shown = cellWidth / wanted
			top = top + (cellHeight - shown) / 2
			cellHeight = shown
		else
			local shown = cellHeight * wanted
			left = left + (cellWidth - shown) / 2
			cellWidth = shown
		end
	end
	local inset = 0.5
	return (left + inset) / atlas.width, (left + cellWidth - inset) / atlas.width,
		(top + inset) / atlas.height, (top + cellHeight - inset) / atlas.height
end

-- ========= Backdrops (the game's art, a trial) ==============================
-- Which backdrop a card gets: by a number the card keeps (its sequence), so a
-- card keeps its art and neighbors differ. Only the ones the game has (has is
-- asked for each name).
function Scenes:Backdrop(number, has)
	local usable = {}
	for _, name in ipairs(ns.CardBackdrops) do
		if has(name) then usable[#usable + 1] = name end
	end
	if #usable == 0 then return nil end
	return usable[(math.floor(number or 0) % #usable) + 1]
end

-- The part of a backdrop that fills a card width x height, never stretched:
-- a band from its middle when the art is taller than the card's shape, or a
-- slice along its width when wider, the slice chosen by number so cards
-- differ. coords are the atlas's own (left, right, top, bottom) in its file,
-- and its size in pixels. Returns left, right, top, bottom in the file.
function Scenes:Slice(coords, pixelWidth, pixelHeight, width, height, number)
	local left, right, top, bottom = coords[1], coords[2], coords[3], coords[4]
	if not (width and height and width > 0 and height > 0 and pixelWidth > 0 and pixelHeight > 0) then
		return left, right, top, bottom
	end
	local wanted, art = width / height, pixelWidth / pixelHeight
	if art > wanted then
		local share = wanted / art -- of the art's width that shows
		local steps = 4
		local at = (math.floor(number or 0) % steps) / (steps - 1) * (1 - share)
		local span = right - left
		return left + span * at, left + span * (at + share), top, bottom
	end
	local share = art / wanted -- of its height
	local span = bottom - top
	local from = top + span * (1 - share) / 2
	return left, right, from, from + span * share
end

