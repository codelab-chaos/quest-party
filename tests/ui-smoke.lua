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
			local ok, problem = pcall(chunk, options and options.sandbox and "QuestPartySandbox" or "QuestParty", ns)
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
	assert(#problems == 0, table.concat(problems, "\n"))
end
