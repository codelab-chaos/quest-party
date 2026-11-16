-- Particle view: draws chat effects over a frame. The motion is particles.lua
-- (pure data); this keeps one layer per frame it plays over, a pool of
-- textures moved once a frame while particles are alive, and nothing at all
-- otherwise. Effects that overlap share the layer, up to maxParticles.
local _, ns = ...

local ParticleView = {}
ns.ParticleView = ParticleView

local layers = {} -- [host frame] = { frame, particles, textures }

local function Layer(host)
	local layer = layers[host]
	if layer then
		return layer
	end
	local frame = CreateFrame("Frame", nil, host)
	frame:SetAllPoints()
	if frame.SetClipsChildren then
		frame:SetClipsChildren(true) -- nothing flies outside the frame
	end
	frame:Hide()
	layer = { frame = frame, particles = {}, textures = {}, words = {} }
	layers[host] = layer
	return layer
end

local function Texture(layer, index)
	local texture = layer.textures[index]
	if not texture then
		texture = layer.frame:CreateTexture(nil, "OVERLAY")
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- the icon without its border
		layer.textures[index] = texture
	end
	return texture
end

-- A worded effect's words: gold text with a shadow, sized like the images.
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

local function Word(layer, index)
	local word = layer.words[index]
	if not word then
		word = layer.frame:CreateFontString(nil, "OVERLAY")
		word:SetFont(FONT, 14, "OUTLINE")
		word:SetTextColor(1, 0.82, 0)
		word:SetShadowOffset(1, -1)
		layer.words[index] = word
	end
	return word
end

local function Draw(layer)
	for index, particle in ipairs(layer.particles) do
		local texture = Texture(layer, index)
		local word = Word(layer, index)
		local hidden = particle.done or particle.delay > 0
		if particle.text then
			texture:Hide()
			if hidden then
				word:Hide()
			else
				local size = math.floor(math.max(11, math.min(22, particle.size * 0.8)))
				if word.size ~= size then
					word:SetFont(FONT, size, "OUTLINE")
					word.size = size
				end
				word:SetText(particle.text)
				word:SetAlpha(particle.alpha)
				word:ClearAllPoints()
				word:SetPoint("CENTER", layer.frame, "TOPLEFT", particle.x, -particle.y)
				word:Show()
			end
		elseif hidden then
			texture:Hide()
			word:Hide()
		else
			word:Hide()
			if texture.icon ~= particle.icon then
				texture:SetTexture(particle.icon)
				texture.icon = particle.icon
			end
			texture:SetSize(particle.size, particle.size)
			texture:SetAlpha(particle.alpha)
			texture:ClearAllPoints()
			texture:SetPoint("CENTER", layer.frame, "TOPLEFT", particle.x, -particle.y)
			if texture.SetRotation then
				texture:SetRotation(particle.rotation)
			end
			texture:Show()
		end
	end
	for index = #layer.particles + 1, #layer.textures do
		layer.textures[index]:Hide()
	end
	for index = #layer.particles + 1, #layer.words do
		layer.words[index]:Hide()
	end
end

-- Plays an effect (data\effects.lua) over a frame, with these images and,
-- for a worded effect, the saying's text falling with them.
function ParticleView:Play(host, effect, icons, words)
	if not host or not effect or #icons == 0 then
		return
	end
	local layer = Layer(host)
	layer.frame:SetFrameLevel(host:GetFrameLevel() + 40)
	local alive = {}
	for _, particle in ipairs(layer.particles) do
		if not particle.done then alive[#alive + 1] = particle end
	end
	local width, height = host:GetWidth() or 0, host:GetHeight() or 0
	for _, particle in ipairs(ns.Particles.Spawn(effect, icons, width, height, nil, words)) do
		if #alive < ns.ParticleRules.maxParticles then
			alive[#alive + 1] = particle
		end
	end
	layer.particles = alive
	layer.frame:Show()
	layer.frame:SetScript("OnUpdate", function(_, elapsed)
		local left = ns.Particles.Step(layer.particles, elapsed, layer.frame:GetHeight() or 0)
		-- Sparks from fireworks count toward the cap too.
		while #layer.particles > ns.ParticleRules.maxParticles do
			table.remove(layer.particles)
		end
		Draw(layer)
		if left == 0 then
			layer.particles = {}
			layer.frame:SetScript("OnUpdate", nil)
			layer.frame:Hide()
		end
	end)
end
