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
