-- Particles: the motion of chat effects (data\effects.lua), as plain data in
-- and out, so it can be checked without drawing anything. ui\particles.lua
-- draws what this moves.
--
-- A particle: { icon or text, x, y, vx, vy, gravity, terminal, rotation,
-- spin, size, life, fade, age, delay, alpha, done }. A text particle is one of
-- a worded effect's words (its saying), moving like the images., plus for a rocket: fuse and burst
-- (the effect whose sparks it pops into), and for an orbiting one: cx, cy,
-- angle, radius, turn, grow.
local _, ns = ...

local Particles = {}
ns.Particles = Particles

local function Between(random, range)
	return range[1] + random() * (range[2] - range[1])
end

local function Either(random, limit)
	return (random() * 2 - 1) * (limit or 0)
end

-- One particle of an effect, its look and lifetime filled in.
local function New(effect, icons, random, fields)
	local particle = {
		icon = icons[math.floor(random() * #icons) + 1] or icons[1],
		size = Between(random, effect.size),
		rotation = random() * math.pi * 2,
		spin = Either(random, effect.spin),
		gravity = effect.gravity or 0,
		terminal = effect.terminal or 1000,
		life = effect.life,
		fade = effect.fade or 0.5,
		age = 0,
		delay = random() * (effect.stagger or 0),
		alpha = 1,
		vx = 0,
		vy = 0,
	}
	for key, value in pairs(fields) do
		particle[key] = value
	end
	return particle
end

-- A burst of sparks from a point, flying out in every direction.
local function Burst(effect, icons, random, x, y, list)
	list = list or {}
	for _ = 1, effect.count do
		local angle, speed = random() * math.pi * 2, Between(random, effect.speed)
		list[#list + 1] = New(effect, icons, random, {
			x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
		})
	end
	return list
end

local patterns = {}

function patterns.rain(effect, icons, random, width)
	local list = {}
	for _ = 1, effect.count do
		list[#list + 1] = New(effect, icons, random, {
			x = random() * width, y = -12, vx = Either(random, effect.drift), vy = Between(random, effect.speed),
		})
	end
	return list
end

function patterns.burst(effect, icons, random, width, height)
	return Burst(effect, icons, random, width / 2, height / 2)
end

function patterns.fireworks(effect, icons, random, width, height)
	local list = {}
	for index = 1, effect.rockets do
		list[#list + 1] = New(effect, icons, random, {
			x = width * (index / (effect.rockets + 1)) + Either(random, width * 0.08),
			y = height + 8,
			vy = -Between(random, effect.rocketSpeed),
			gravity = 0,
			delay = (index - 1) * (effect.rocketStagger or 0) / effect.rockets + random() * 0.2,
			fuse = Between(random, effect.fuse),
			burst = effect,
			life = 10, -- until it pops
			size = effect.size[1],
		})
	end
	return list
end

function patterns.fountain(effect, icons, random, width, height)
	local list = {}
	for _ = 1, effect.count do
		local angle, speed = -math.pi / 2 + Either(random, effect.spread), Between(random, effect.speed)
		list[#list + 1] = New(effect, icons, random, {
			x = width / 2, y = height + 6, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
		})
	end
	return list
end

function patterns.swirl(effect, icons, random, width, height)
	local list = {}
	for _ = 1, effect.count do
		list[#list + 1] = New(effect, icons, random, {
			cx = width / 2, cy = height / 2, x = width / 2, y = height / 2,
			angle = random() * math.pi * 2, radius = 0,
			turn = effect.turn * (random() < 0.5 and -1 or 1), grow = Between(random, effect.speed),
		})
	end
	return list
end

-- The particles one effect starts with, over an area this big, using these
-- images (file IDs) and, for a worded effect, the saying's text: some of the
-- particles become its words. random returns 0 to 1 (math.random when left out).
function Particles.Spawn(effect, icons, width, height, random, words)
	random = random or math.random
	local pattern = effect and patterns[effect.pattern]
	if not pattern or #icons == 0 then
		return {}
	end
	local list = pattern(effect, icons, random, width, height)
	if type(words) == "string" and words ~= "" then
		local rules = ns.ParticleRules
		local count = math.min(rules.maxWords, math.max(1, math.floor(#list * rules.wordShare)))
		-- Rockets carry the words up, to burst into them.
		for _, particle in ipairs(list) do
			if particle.fuse then particle.words = words end
		end
		-- Spread the words through the list, so they fly with the images.
		local step = #list / count
		for index = 1, count do
			local particle = list[math.floor((index - 1) * step) + 1]
			if particle and not particle.fuse then
				particle.text, particle.icon = words, nil
				particle.spin = 0
				particle.rotation = 0
			end
		end
	end
	return list
end

-- Moves every particle on by dt seconds, in an area this tall. A rocket whose
-- fuse runs out pops into a burst of sparks, added to the list. A particle is
-- done once it has lived its time or left the area. Returns how many are
-- still to come or in the air.
function Particles.Step(list, dt, height, random)
	random = random or math.random
	dt = math.min(dt, ns.ParticleRules.maxStep)
	local left, born = 0, {}
	for _, particle in ipairs(list) do
		if not particle.done then
			if particle.delay > 0 then
				particle.delay = particle.delay - dt
			else
				particle.age = particle.age + dt
				if particle.radius then
					particle.angle = particle.angle + particle.turn * dt
					particle.radius = particle.radius + particle.grow * dt
					particle.x = particle.cx + math.cos(particle.angle) * particle.radius
					particle.y = particle.cy + math.sin(particle.angle) * particle.radius
				else
					particle.vy = math.min(particle.vy + particle.gravity * dt, particle.terminal)
					particle.x = particle.x + particle.vx * dt
					particle.y = particle.y + particle.vy * dt
				end
				particle.rotation = particle.rotation + particle.spin * dt
				if particle.fuse and particle.age >= particle.fuse then
					local sparks = #born
					Burst(particle.burst, { particle.icon }, random, particle.x, particle.y, born)
					-- A worded rocket's burst carries its words too.
					if particle.words then
						for index = sparks + 1, #born, 4 do
							born[index].text, born[index].icon, born[index].spin = particle.words, nil, 0
						end
					end
					particle.done = true
				else
					local fadeFrom = particle.life - particle.fade
					particle.alpha = particle.age <= fadeFrom and 1 or math.max(0, (particle.life - particle.age) / particle.fade)
					if particle.age >= particle.life or particle.y > height + 40 then
						particle.done = true
					end
				end
			end
			if not particle.done then
				left = left + 1
			end
		end
	end
	for _, spark in ipairs(born) do
		spark.delay = 0
		list[#list + 1] = spark
		left = left + 1
	end
	return left
end
