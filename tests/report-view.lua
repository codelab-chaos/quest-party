-- A small frame boundary for checking the report's geometry. The real report
-- and renderer run unchanged; the game still decides the final appearance.
return function(Harness)
	local w = Harness.new({ switches = { chatEcho = false } })
	w:ingest("xp", { xp = 100, mob = "Kobold" }, "Bram")
	w:ingest("xp", { xp = 50, mob = "Kobold" }, "Cora")
	local objects, methods = {}, {}
	local function object(kind, parent)
		local frame = { kind = kind, parent = parent, scripts = {}, shown = true }
		objects[#objects + 1] = frame
		return setmetatable(frame, { __index = function(_, key)
			return methods[key] or (key:match("^%u") and function() end or nil)
		end })
	end
	function methods:SetSize(width, height) self.width, self.height = width, height end
	function methods:SetWidth(width) self.width = width end
	function methods:SetHeight(height) self.height = height end
	function methods:GetWidth() return self.width or 374 end
	function methods:GetHeight() return self.height or 240 end
	function methods:SetPoint(...) self.point = { ... } end
	function methods:SetText(text) self.text = text end
	function methods:SetShown(shown) self.shown = not not shown end
	function methods:Show() self.shown = true end
	function methods:Hide() self.shown = false end
	function methods:IsShown() return self.shown end
	function methods:GetFrameLevel() return 1 end
	function methods:SetScript(event, fn) self.scripts[event] = fn end
	function methods:HookScript(event, fn)
		local previous = self.scripts[event]
		self.scripts[event] = function(...)
			if previous then previous(...) end
			fn(...)
		end
	end
	function methods:CreateTexture() return object("Texture", self) end
	function methods:CreateFontString() return object("FontString", self) end
	function methods:SetScrollChild(child) self.child = child end
	function methods:SetVerticalScroll(value) self.scroll = value end
	function methods:GetVerticalScroll() return self.scroll or 0 end
	local chart
	w.env.CreateFrame = function(kind, _, parent)
		local frame = object(kind, parent)
		if kind == "ScrollFrame" then
			frame:SetSize(350, 210)
			frame.ScrollBar = object("ScrollBar", frame)
			chart = frame
		end
		return frame
	end
	local host = object("Frame")
	w.ns.Panel = { GetFrame = function() return host end, Refresh = function() end }
	for _, path in ipairs({ "ui/look.lua", "ui/report.lua" }) do
		local chunk
		if setfenv then
			chunk = assert(loadfile("QuestParty/" .. path))
			setfenv(chunk, w.env)
		else
			chunk = assert(loadfile("QuestParty/" .. path, "t", w.env))
		end
		chunk("QuestParty", w.ns)
	end
	w.ns.Bus:Fire("READY")
	w.ns.ReportView:Show(50, 8)
	local function cells()
		local found = {}
		for _, frame in ipairs(objects) do
			if frame.parts and frame.shown then found[#found + 1] = frame end
		end
		return found
	end
	local vials = cells()
	assert(#vials == 7, "all seven stats fit in the normal view")
	for _, vial in ipairs(vials) do
		assert(vial.point[3] == 0, "normal-width stats share a baseline")
		assert(vial.point[2] >= 0 and vial.point[2] + vial.width <= chart.width + 0.01, "vials stay inside the chart")
		assert(vial.glass.height > vial.glass.width, "vials stand upright")
	end
	local xp = vials[1]
	assert(xp.value.text == "150", "the total shows in the middle of its gauge")
	assert(xp.parts[1].point[1] == "BOTTOMLEFT", "liquid starts at the bottom")
	assert(xp.parts[1].height == xp.track.height, "one liquid, not slices by player: it fills the gauge")
	assert(not xp.parts[2] or not xp.parts[2].shown, "no second slice")
	assert(#xp.tip.lines == 2, "who did how much is in the tooltip")
	assert(vials[6].label.text == "Achiev." and vials[6].tip.title == "Achievements", "narrow labels keep their full hover title")
	assert(not chart.ScrollBar.shown, "the normal view needs no scroll bar")

	w.ns.ReportView.kind = "xp"
	w.ns.ReportView:Draw()
	vials = cells()
	assert(#vials == 2, "a type filter shows one vial per player")
	assert(vials[1].parts[1].height == vials[1].track.height, "the leading player fills the vial")
	assert(math.abs(vials[2].parts[1].height - vials[2].track.height / 2) <= 1, "the next player's height preserves its relative amount")
	w.ns.ReportView.player = "Cora"
	w.ns.ReportView:Draw()
	vials = cells()
	assert(#vials == 1 and vials[1].value.text:find("33%%"), "a player's share retains its percentage")
	assert(math.abs(vials[1].parts[1].height - vials[1].track.height / 3) <= 1, "the share fills only its part of the glass")
	w.ns.ReportView.kind = "quests"
	w.ns.ReportView:Draw()
	assert(not cells()[1].parts[1].shown and not cells()[1].surface.shown, "zero clears reused liquid and its surface")

	w.ns.ReportView.kind, w.ns.ReportView.player = nil, nil
	chart:SetSize(180, 144)
	chart.scripts.OnSizeChanged(chart)
	vials = cells()
	assert(#vials == 7 and chart.ScrollBar.shown, "narrow views wrap and scroll instead of losing stats")
	assert(vials[4].point[3] < 0 and vials[7].point[3] < vials[4].point[3], "narrow vials wrap into successive rows")
	for _, vial in ipairs(vials) do
		assert(vial.point[2] >= 0 and vial.point[2] + vial.width <= chart.width + 0.01, "wrapped vials stay inside the chart")
	end
	chart:SetVerticalScroll(200)
	chart:SetSize(350, 210)
	chart.scripts.OnSizeChanged(chart)
	assert(chart.scroll == 0 and not chart.ScrollBar.shown, "widening returns to one row and resets obsolete scrolling")
end
