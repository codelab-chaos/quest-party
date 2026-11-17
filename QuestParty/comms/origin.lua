-- Origin: who a message on the channel is from, as this client should treat
-- it. Pure, no game calls, so every case can be checked on its own.
--
-- Messages can carry as, the pretend player they stand for: the emulator's,
-- or the sandbox's (a second build of Quest Party, QuestPartySandbox, that
-- plays pretend players from this same character). Both copies send as this
-- character, so the game reports this character as the sender of both.
--
--   from      what the game says sent it
--   fromMe    true when that is this character
--   as        the pretend player it stands for, or nil
--   sandbox   true in the sandbox build
--   debug     true in debug mode
--
-- Returns "peer" and the player to treat it as from, "self" for our own
-- message back from the server, or nil to ignore it.
local _, ns = ...

function ns.Origin(from, fromMe, as, sandbox, debug)
	if fromMe then
		if as then
			-- A pretend player: shown in the sandbox, and here in debug only.
			if sandbox or debug then
				return "peer", as
			end
			return nil
		end
		-- In the sandbox, this character's own regular Quest Party (loaded
		-- beside it, a developer's setup only) is not a friend: ignored. The
		-- sandbox shows this character from its own tracking.
		if sandbox then
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
