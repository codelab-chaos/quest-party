-- A seeded random source: the same seed gives the same numbers, so a dev
-- run can be repeated exactly to compare a change before and after. Pure.
local _, ns = ...

local Random = {}
ns.DevRandom = Random

-- A park-miller generator: small, and the same in every Lua.
local MODULUS, MULTIPLIER = 2147483647, 16807

-- Returns next(), a number from 0 up to 1, and a few helpers on it.
function Random.New(seed)
	local state = math.floor(tonumber(seed) or 1) % MODULUS
	if state <= 0 then
		state = state + MODULUS - 1
	end
	local generator = {}
	function generator.next()
		state = (state * MULTIPLIER) % MODULUS
		return (state - 1) / (MODULUS - 1)
	end
	-- A whole number from low to high, both included.
	function generator.int(low, high)
		return low + math.floor(generator.next() * (high - low + 1))
	end
	function generator.pick(list)
		return list[generator.int(1, #list)]
	end
	-- True with this chance, from 0 to 1.
	function generator.chance(odds)
		return generator.next() < odds
	end
	-- Seconds until the next of something that happens perHour times an hour,
	-- at random as in life (exponential gaps).
	function generator.gap(perHour)
		if perHour <= 0 then
			return math.huge
		end
		return -math.log(1 - generator.next() * 0.999999) * 3600 / perHour
	end
	return generator
end
