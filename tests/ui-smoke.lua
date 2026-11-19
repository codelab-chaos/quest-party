-- Loads every ui\ file of the TOC against a permissive fake of the game's
-- frame API, starts up and opens each tab, so an error that would stop the
-- panel from building (a missing color, a nil) fails a test instead of
-- leaving /qp doing nothing in game. It cannot judge how anything looks.
return function(Harness, options)
	local w = Harness.new(nil, nil, true, nil, options)
	local env, ns = w.env, w.ns
	-- A fake frame: any capitalized field is another fake, which can be called
	-- (a method, doing nothing) or indexed (a template's child, like .Text).
	local function object()
		return setmetatable({}, { __call = function() end, __index = function(_, key)
			if type(key) ~= "string" then return nil end
			if key:match("^Get") then
				return function()
					if key == "GetFont" then return "Fonts\\FRIZQT__.TTF", 12, "" end
					if key == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
					if key == "GetFontString" or key == "GetParent" or key:match("Texture$") then return object() end
					return 0
				end
			end
			if key:match("^Is") or key:match("^Has") then return function() return false end end
			if key:match("^Create") then return function() return object() end end
			if key:match("^%u") then return object() end
		end })
	end
	env.CreateFrame = function() return object() end
	env.UIParent, env.GameTooltip, env.ScrollUtil, env.MenuUtil = object(), object(), object(), object()
	env.CreateColor = function(...) return { ... } end
	env.CreateDataProvider = function() return object() end
	env.CreateScrollBoxListLinearView = function() return object() end
	env.ScrollBoxConstants = {}
	env.GetCursorPosition = function() return 0, 0 end
	env.UISpecialFrames, env.tinsert = {}, table.insert
	env.RAID_CLASS_COLORS = {}
	env.PlaySound = function() end
	local problems = {}
	for line in io.open("QuestParty/QuestParty.toc"):read("*a"):gmatch("[^\r\n]+") do
		local path = line:gsub("\\", "/")
		if path:match("^ui/.*%.lua$") then
			local chunk = assert(loadfile("QuestParty/" .. path))
			setfenv(chunk, env)
			local ok, problem = pcall(chunk, "QuestParty", ns)
			if not ok then problems[#problems + 1] = problem end
		end
	end
	for _, handler in ipairs(ns.Bus.handlers.READY or {}) do
		local ok, problem = pcall(handler)
		if not ok then problems[#problems + 1] = problem end
	end
	for _, filter in ipairs(ns.Filters) do
		local ok, problem = pcall(function() ns.Panel:SelectFilter(filter.id) end)
		if not ok then problems[#problems + 1] = filter.id .. ": " .. tostring(problem) end
	end
	local ok, problem = pcall(function() ns.Panel:Toggle() ns.Panel:Toggle() end)
	if not ok then problems[#problems + 1] = problem end
	-- A full party: options.players on the channel, every one drawn (the XP
	-- strip, the side bar) at the cap options.cap.
	if options and options.players then
		if options.cap then ns.SetSlider("partyCap", options.cap) end
		for index = 1, options.players do
			local name = "Player" .. index
			ns.Session.peers[name] = { name = name, class = "MAGE", level = 10 + index, currentXP = 100 * index, maxXP = 7600, vitals = { h = 80, p = 50, t = "MANA" }, heard = index }
			ns.Bus:Fire("ENTRY_RECEIVED", { type = "level", player = name, class = "MAGE", data = { level = 10 + index } })
		end
		-- Stamps on a card, of each kind: words, an emblem alone, a mark.
		for index, id in ipairs({ "gg", "nice", "lol", "rip" }) do
			ns.Stamping:Add("Player1~level~11", id, "Stamper" .. index)
		end
		local drawn, why = pcall(function()
			ns.Panel:UpdateXpBars()
			ns.Party:Redraw()
			ns.Panel:Refresh()
		end)
		if not drawn then problems[#problems + 1] = "a full party: " .. tostring(why) end
		-- The stamp picker opens on a card (a right-click), built whole.
		local opened, openProblem = pcall(function()
			return ns.StampView:Open({ stampEntry = { type = "level", player = "Player2", data = { level = 12 } } })
		end)
		if not opened then problems[#problems + 1] = "the stamp picker: " .. tostring(openProblem) end
		-- The Quest tab in each quest card layout (ui\\quest-card.lua).
		ns.Bus:Fire("ENTRY_RECEIVED", { type = "quest_progress", player = "Player1", class = "MAGE", data = { questID = 9, quest = "Q", objective = "Rats", have = 2, need = 5 } })
		ns.Bus:Fire("ENTRY_RECEIVED", { type = "quest_progress", player = "Player1", class = "MAGE", data = { questID = 9, quest = "Q", objective = "Wolves", have = 3, need = 3 } })
		-- More on the same quest: a party card, with a section past its rows.
		for index = 2, 7 do
			ns.Bus:Fire("ENTRY_RECEIVED", { type = "quest_progress", player = "Player" .. index, class = "MAGE", data = { questID = 9, quest = "Q", objective = "Rats", have = index % 5, need = 5 } })
		end
		ns.Panel:SelectFilter("party")
		for step = 0, 3 do
			local laid, layProblem = pcall(function()
				ns.SetSlider("questCardStyle", step)
				ns.Panel:Refresh()
			end)
			if not laid then problems[#problems + 1] = "quest cards, style " .. step .. ": " .. tostring(layProblem) end
		end
	end
	assert(#problems == 0, table.concat(problems, "\n"))
	return w
end
