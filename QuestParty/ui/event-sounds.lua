-- Event sounds: a quest handed in, a level up, an objective done, on every
-- client. The sound is the feed type's (data\feed-types.lua, sound), played
-- at the volume setting (ns.PlaySound). One sound per moment: rows that land
-- together (a kill finishing an objective that completes the quest) play the
-- most important one only. Nothing sounds for old rows read again.
local _, ns = ...

local EventSounds = {}
ns.EventSounds = EventSounds

EventSounds.RULES = {
	gapSeconds = 0.6, -- rows this close together are one moment
	freshSeconds = 15, -- a row older than this (caught up, replayed) is quiet
}

-- Which sound wins when several land in one moment: the first listed.
EventSounds.ORDER = { "level", "quest_complete", "quest_progress" }

local pending, timer

local function Rank(typeName)
	for index, name in ipairs(EventSounds.ORDER) do
		if name == typeName then return index end
	end
	return #EventSounds.ORDER + 1
end

-- Whether a new feed row should sound, and holds it a moment for any that
-- land with it. Returns the type held (for tests).
function EventSounds:Offer(entry, def)
	if not (def and def.sound) then return nil end
	if ns.Sharing.IsReplaying and ns.Sharing.IsReplaying() then return nil end
	if math.abs(GetServerTime() - (entry.time or 0)) > self.RULES.freshSeconds then return nil end
	if not pending or Rank(entry.type) < Rank(pending.type) then
		pending = { type = entry.type, sound = def.sound }
	end
	if not timer then
		timer = true
		C_Timer.After(self.RULES.gapSeconds, function()
			timer = nil
			local play = pending
			pending = nil
			if play then
				EventSounds.last = play.type
				ns.PlaySound(play.sound)
			end
		end)
	end
	return pending.type
end

ns.Bus:On("FEED_ADDED", function(entry, def)
	EventSounds:Offer(entry, def)
end)
