-- The sandbox's commands, added to /qps:
--   /qps party [count] [seed] [speed]  start a made-up party
--   /qps replay [speed]                play the recorded session back
--   /qps stop                          stop, the pretend players leave
--   /qps wipe                          forget everything and stop
--   /qps loopback on|off               read messages back here, no network
--   /qps measure                       what this run costs
--   /qps burst [count]                 measure the game's send budget
local _, ns = ...
local L = ns.L
local Sandbox = ns.Sandbox

local function Report(ok, problem)
	if ok then
		ns.Print(L.SANDBOX_STARTED:format(#Sandbox.order, Sandbox.speed, ns.Sharing.loopback and L.SANDBOX_LOOPBACK or L.SANDBOX_CHANNEL))
	else
		ns.Print(problem)
	end
end

local commands = {
	party = function(count, seed, speed)
		Report(Sandbox:StartParty(count, seed, speed))
	end,
	replay = function(speed)
		Report(Sandbox:StartRecording("tirisfal", speed))
	end,
	stop = function()
		Sandbox:Stop()
		ns.Print(L.SANDBOX_STOPPED)
	end,
	wipe = function()
		Sandbox:Wipe()
		ns.Print(L.SANDBOX_WIPED)
	end,
	loopback = function(value)
		ns.Sharing.loopback = value ~= "off"
		ns.Print(ns.Sharing.loopback and L.SANDBOX_LOOPBACK_ON or L.SANDBOX_LOOPBACK_OFF)
	end,
	measure = function()
		local m = Sandbox:Measure()
		ns.Print(L.SANDBOX_MEASURE_1:format(m.here, m.players, m.peers, m.memoryKB, m.clockMinutes, m.speed))
		ns.Print(L.SANDBOX_MEASURE_2:format(m.sent, m.perMinute, m.received, m.failed, m.readMilliseconds))
		ns.Print(L.SANDBOX_MEASURE_3:format(m.feed, m.cards, m.members))
	end,
	burst = function(count)
		local result, problem = Sandbox:BurstTest(count)
		if not result then
			ns.Print(problem)
			return
		end
		local parts = {}
		for name, number in pairs(result.results) do
			parts[#parts + 1] = name .. " " .. number
		end
		table.sort(parts)
		ns.Print(L.SANDBOX_BURST:format(result.sent, table.concat(parts, ", "), tostring(result.firstRefusal or "-")))
	end,
}

for name, handler in pairs(commands) do
	ns.Commands[name] = handler
end
