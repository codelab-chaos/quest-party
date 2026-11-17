-- Look: small drawing helpers shared by the party heads (ui\party.lua) and
-- KekChat (ui\chat.lua), so a player's portrait looks the same everywhere.
local _, ns = ...

local Look = {}
ns.Look = Look

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Cuts a texture to a circle filling its own bounds.
function Look.Round(texture, parent)
	local mask = parent:CreateMaskTexture()
	mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

-- A portrait: the game's race art when it has it (data.atlas), or the class
-- icon (data.class), or a question mark.
function Look.SetPortrait(texture, data)
	if data.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(data.atlas) then
		texture:SetAtlas(data.atlas)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end
	texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	local coords = data.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
	if coords then
		texture:SetTexCoord(unpack(coords))
	else
		texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

-- A class's color as r, g, b, or gold when the class is not known.
-- Paints a feed card's scene (data\scenes.lua) on a texture, cropped to the
-- card's size; nil hides it.
function Look.SetScene(texture, scene, width, height)
	if not scene then
		texture:Hide()
		return
	end
	texture:SetTexture(ns.Scene:File())
	texture:SetTexCoord(ns.Scene:Coords(scene, width, height))
	texture:Show()
end

function Look.ClassColor(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return 0.80, 0.65, 0.20
end
