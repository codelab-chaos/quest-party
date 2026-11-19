-- Dev mode: off by default; /qp dev on (or /qp debug on) shows the tools.
-- Its commands, under /qp dev while it is on:
--   /qp dev party [count] [seed] [speed]  start a made-up party
--   /qp dev replay [name|all] [speed]     play recorded players back, all together by default
--   /qp dev stop                          stop, the pretend players leave
--   /qp dev wipe                          forget the pretend players and what they did
--   /qp dev loopback on|off               read messages back here, no network
--   /qp dev measure                       what this run costs
--   /qp dev burst [count]                 measure the game's send budget
local _, ns = ...
local L = ns.L
local Dev = ns.Dev

local function Report(ok, problem)
	if ok then
		ns.Print(L.DEV_STARTED:format(#Dev.order, Dev.speed, ns.Sharing.loopback and L.DEV_LOOPBACK or L.DEV_CHANNEL))
	else
		ns.Print(problem)
	end
end

local commands = {
	party = function(count, seed, speed)
		Dev.gearSeconds = nil -- the real gear wait, in pretend time
		Report(Dev:StartParty(count, seed, speed))
	end,
	replay = function(name, speed)
		if tonumber(name) then
			name, speed = "all", name
		end
		Report(Dev:StartRecording(name or "all", speed))
	end,
	stop = function()
		Dev:Stop()
		ns.Print(L.DEV_STOPPED)
	end,
	wipe = function()
		Dev:Wipe()
		ns.Print(L.DEV_WIPED)
	end,
	loopback = function(value)
		ns.Sharing.loopback = value ~= "off"
		ns.Print(ns.Sharing.loopback and L.DEV_LOOPBACK_ON or L.DEV_LOOPBACK_OFF)
	end,
	measure = function()
		local m = Dev:Measure()
		ns.Print(L.DEV_MEASURE_1:format(m.here, m.players, m.peers, m.memoryKB, m.clockMinutes, m.speed))
		ns.Print(L.DEV_MEASURE_2:format(m.sent, m.perMinute, m.received, m.failed, m.readMilliseconds))
		ns.Print(L.DEV_MEASURE_3:format(m.feed, m.cards, m.members))
	end,
	burst = function(count)
		local result, problem = Dev:BurstTest(count)
		if not result then
			ns.Print(problem)
			return
		end
		local parts = {}
		for name, number in pairs(result.results) do
			parts[#parts + 1] = name .. " " .. number
		end
		table.sort(parts)
		ns.Print(L.DEV_BURST:format(result.sent, table.concat(parts, ", "), tostring(result.firstRefusal or "-")))
	end,
}

ns.Commands.dev = function(sub, ...)
	local word = (sub or ""):lower()
	if word == "on" or word == "off" then
		ns.SetDebug(word == "on")
		ns.Print(ns.IsDebug() and L.CMD_DEBUG_ON or L.CMD_DEBUG_OFF)
		return
	end
	if not ns.IsDebug() then
		ns.Print(L.CMD_DEBUG_REQUIRED)
		return
	end
	local handler = commands[(sub or ""):lower()]
	if handler then
		handler(...)
	else
		ns.Print(L.CMD_HELP_DEV)
	end
end
