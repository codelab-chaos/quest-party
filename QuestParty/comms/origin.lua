-- Origin: who a message on the channel is from, as this client should treat
-- it. Pure, no game calls, so every case can be checked on its own.
--
-- Messages can carry as, the pretend player they stand for: dev mode's
-- (dev\dev.lua), played from this same character, so the game reports this
-- character as the sender.
--
--   from      what the game says sent it
--   fromMe    true when that is this character
--   as        the pretend player it stands for, or nil
--   debug     true in debug mode
--
-- Returns "peer" and the player to treat it as from, "self" for our own
-- message back from the server, or nil to ignore it.
local _, ns = ...

function ns.Origin(from, fromMe, as, debug)
	if fromMe then
		if as then
			-- A pretend player: shown in debug mode only.
			if debug then
				return "peer", as
			end
			return nil
		end
		return "self"
	end
	-- Someone else's pretend players are theirs to look at, not ours.
	if as then
		return nil
	end
	return "peer", from
end
