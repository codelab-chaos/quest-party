-- Confetti: a small particle effect for a celebration, such as a level-up.
-- Pieces of colored paper drop from the top of a host frame (the panel) and
-- flutter down, swaying and spinning, then fade out.
--
-- The motion is plain data in and out (Confetti.Spawn, Confetti.Step), so it
-- can be checked without drawing anything. Drawing is a pool of textures moved
-- once a frame while pieces are in the air, and nothing at all otherwise.
--
-- A feed type marked celebrate (data\feed-types.lua) sets it off when it
-- arrives, for anyone's row, while the host is showing and the switch is on.
local _, ns = ...
local Bus = ns.Bus

local Confetti = {}
ns.Confetti = Confetti

-- The look and the motion, as data. Distances are in pixels, times in seconds.
-- y is measured down from the top of the host.
Confetti.Config = {
	pieces = 60, -- in one burst
	maxPieces = 180, -- in the air at once, however many bursts overlap
	stagger = 0.7, -- a burst's pieces start over this long, so they rain
	duration = 3.0, -- how long a piece lives once it starts
	fade = 0.8, -- it fades out over the last this long
	startSpeed = { min = 10, max = 70 }, -- falling speed at the start
	gravity = 380, -- added to the falling speed every second
	terminal = 95, -- the fastest a piece falls: paper flutters
	drift = 35, -- sideways speed, up to this either way
	sway = 14, -- how far a piece swings side to side
	swaySpeed = { min = 3, max = 6 }, -- how fast it swings
	spin = 7, -- turning speed, up to this either way
	width = { min = 4, max = 7 },
	height = { min = 2, max = 4 },
	colors = {
		{ 1.00, 0.82, 0.00 }, -- gold
		{ 0.58, 0.36, 0.86 }, -- violet
		{ 0.27, 0.56, 0.90 }, -- blue
		{ 0.38, 0.72, 0.32 }, -- green
		{ 0.86, 0.36, 0.56 }, -- rose
		{ 0.30, 0.74, 0.88 }, -- sky
		{ 1.00, 1.00, 1.00 }, -- white
	},
	maxStep = 0.05, -- a long frame is stepped as at most this, so nothing leaps
}

local function Between(random, range)
	return range.min + random() * (range.max - range.min)
end

local function Either(random, limit)
	return (random() * 2 - 1) * limit
end

-- New pieces for one burst across a host this wide. random returns a number
-- from 0 to 1 (math.random when left out).
function Confetti.Spawn(width, random)
	random = random or math.random
	local config = Confetti.Config
	local pieces = {}
	for index = 1, config.pieces do
		pieces[index] = {
			delay = random() * config.stagger,
			age = 0,
			x = random() * width,
			y = -2,
			vx = Either(random, config.drift),
			vy = Between(random, config.startSpeed),
			phase = random() * math.pi * 2,
			swaySpeed = Between(random, config.swaySpeed),
			rotation = random() * math.pi * 2,
			spin = Either(random, config.spin),
			width = Between(random, config.width),
			height = Between(random, config.height),
			color = config.colors[math.floor(random() * #config.colors) + 1] or config.colors[1],
			alpha = 1,
			offset = 0,
		}
	end
	return pieces
end

-- Moves every piece on by dt seconds, inside a host this tall. A piece is
-- done once it has lived its time or fallen out of sight. Returns how many
-- are not done, waiting ones included.
function Confetti.Step(pieces, dt, height)
	local config = Confetti.Config
	dt = math.min(dt, config.maxStep)
	local left = 0
	for _, piece in ipairs(pieces) do
		if not piece.done then
			if piece.delay > 0 then
				piece.delay = piece.delay - dt
			else
				piece.age = piece.age + dt
				piece.vy = math.min(piece.vy + config.gravity * dt, config.terminal)
				piece.x = piece.x + piece.vx * dt
				piece.y = piece.y + piece.vy * dt
				piece.phase = piece.phase + piece.swaySpeed * dt
				piece.offset = math.sin(piece.phase) * config.sway
				piece.rotation = piece.rotation + piece.spin * dt
				local fadeFrom = config.duration - config.fade
				piece.alpha = piece.age <= fadeFrom and 1 or math.max(0, (config.duration - piece.age) / config.fade)
				if piece.age >= config.duration or piece.y > height + 10 then
					piece.done = true
				end
			end
			if not piece.done then
				left = left + 1
			end
		end
	end
	return left
end

-- ========= Drawing ==========================================================
local host, layer
local pieces = {}
local textures = {}

local function Texture(index)
	local texture = textures[index]
	if not texture then
		texture = layer:CreateTexture(nil, "OVERLAY")
		texture:SetTexture("Interface\\Buttons\\WHITE8x8")
		textures[index] = texture
	end
	return texture
end

local function Draw()
	for index, piece in ipairs(pieces) do
		local texture = Texture(index)
		if piece.done or piece.delay > 0 then
			texture:Hide()
		else
			texture:SetSize(piece.width, piece.height)
			texture:SetVertexColor(piece.color[1], piece.color[2], piece.color[3], piece.alpha)
			texture:ClearAllPoints()
			texture:SetPoint("CENTER", layer, "TOPLEFT", piece.x + piece.offset, -piece.y)
			if texture.SetRotation then
				texture:SetRotation(piece.rotation)
			end
			texture:Show()
		end
	end
	for index = #pieces + 1, #textures do
		textures[index]:Hide()
	end
end

local function OnUpdate(_, elapsed)
	local left = Confetti.Step(pieces, elapsed, layer:GetHeight() or 0)
	Draw()
	if left == 0 then
		pieces = {}
		layer:SetScript("OnUpdate", nil)
		layer:Hide()
	end
end

-- The frame the confetti falls over. The panel calls this once it is built.
function Confetti:SetHost(frame)
	host = frame
end

-- Drops one burst over the host.
function Confetti:Burst()
	if not host then
		return
	end
	if not layer then
		layer = CreateFrame("Frame", nil, host)
		layer:SetAllPoints()
		if layer.SetClipsChildren then
			layer:SetClipsChildren(true) -- nothing falls outside the panel
		end
	end
	layer:SetFrameLevel(host:GetFrameLevel() + 50)
	local alive = {}
	for _, piece in ipairs(pieces) do
		if not piece.done then
			alive[#alive + 1] = piece
		end
	end
	for _, piece in ipairs(Confetti.Spawn(host:GetWidth() or 0)) do
		if #alive < Confetti.Config.maxPieces then
			alive[#alive + 1] = piece
		end
	end
	pieces = alive
	layer:Show()
	layer:SetScript("OnUpdate", OnUpdate)
end

-- True when a row arriving now should set off confetti.
function Confetti:ShouldCelebrate(def)
	return def and def.celebrate == true and ns.IsEnabled("confetti") and host ~= nil and host:IsShown() == true
end

Bus:On("FEED_ADDED", function(_, def)
	if Confetti:ShouldCelebrate(def) then
		Confetti:Burst()
	end
end)
