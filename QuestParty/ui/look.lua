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

-- "ALPHA!": a pink rubber stamp over a pop-out window's title, at its right,
-- saying the window is still being made. Tilted like the feed's stamps.
-- point, x and y place it on parent (its top right, by default).
Look.ALPHA = {
	text = "ALPHA!",
	color = { 1, 0.35, 0.72, 0.9 }, -- pink
	size = 16,
	tilt = 0.22,
}

function Look.AlphaStamp(parent, point, x, y)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(80, 24)
	holder:SetPoint(point or "TOPRIGHT", x or -36, y or -8)
	holder:SetFrameLevel(parent:GetFrameLevel() + 20)
	holder:EnableMouse(false)
	local word = holder:CreateFontString(nil, "OVERLAY")
	word:SetFont("Fonts\\FRIZQT__.TTF", Look.ALPHA.size, "THICKOUTLINE")
	word:SetPoint("CENTER")
	word:SetText(ns.L.ALPHA_STAMP or Look.ALPHA.text)
	word:SetTextColor(unpack(Look.ALPHA.color))
	if word.SetRotation then pcall(word.SetRotation, word, Look.ALPHA.tilt) end
	holder.word = word
	return holder
end

-- The party chat's color, as this player has it set in the game (lavender by
-- default): what marks your game group's members, and quests you share.
function Look.PartyColor()
	local info = ChatTypeInfo and ChatTypeInfo.PARTY
	if info and info.r then
		return info.r, info.g, info.b
	end
	return 0.667, 0.667, 1
end

-- Draws a mark's art (data\marks.lua) at size: the atlas when the game has
-- it, else the texture, else its text. art is a texture, text a font string;
-- the caller colors the square around them.
-- icon, when given, is this row's own art in place of the look's (a
-- profession's icon), cropped like any Interface\Icons file.
function Look.DrawMark(art, text, look, size, icon)
	local scaled = math.floor(size * (look.scale or 1) + 0.5)
	if icon then
		text:Hide()
		art:SetSize(scaled, scaled)
		art:SetTexture(icon)
		art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		art:SetDesaturated(false)
		art:SetVertexColor(1, 1, 1)
		art:Show()
		return
	end
	local hasAtlas = look.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(look.atlas)
	if look.text and not hasAtlas and not look.texture then
		art:Hide()
		local font = text:GetFont() or "Fonts\\FRIZQT__.TTF"
		text:SetFont(font, math.max(8, math.floor(size * 0.48)), "THICKOUTLINE")
		text:SetTextColor(unpack(look.textColor or { 1, 1, 1 }))
		text:SetText(look.text)
		text:Show()
		return
	end
	text:Hide()
	art:SetSize(scaled, scaled)
	if look.atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(look.atlas) then
		art:SetAtlas(look.atlas)
	else
		art:SetTexture(look.texture)
		if look.crop then
			art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		else
			art:SetTexCoord(0, 1, 0, 1)
		end
	end
	art:SetDesaturated(look.desaturate == true)
	art:SetVertexColor(unpack(look.tint or { 1, 1, 1 }))
	art:Show()
end

-- Sets a texture to a stamp's emblem (data\stamps.lua): its atlas when the
-- game has it, else its icon.
function Look.StampEmblem(texture, stamp)
	if stamp.texture then
		texture:SetTexture(stamp.texture)
		texture:SetTexCoord(0, 1, 0, 1)
		return
	end
	if stamp.emblem and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(stamp.emblem) then
		texture:SetAtlas(stamp.emblem)
		return
	end
	texture:SetTexture("Interface\\Icons\\" .. stamp.icon)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

function Look.ClassColor(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return 0.80, 0.65, 0.20
end
