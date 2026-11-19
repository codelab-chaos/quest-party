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
	-- Fuel opens on one vat: the party's fuel as one number.
	local vat = cells()
	assert(#vat == 1, "Fuel opens on one vat")
	vat = vat[1]
	assert(vat.value.text == w.ns.ReportView.Short(w.ns.Report:Build().fuel), "the vat shows the party's fuel")
	assert(vat.label.text == "Party Fuel", "the vat is the party's fuel")
	assert(vat.parts[1].shown and vat.parts[1].height == vat.track.height, "one red liquid, full")
	-- Under it, a question that opens a short note.
	local question
	for _, frame in ipairs(objects) do
		if frame.text and frame.text.text == "What is Party Fuel?" then question = frame end
	end
	assert(question and question.shown, "a question under the whole vat")
	question.scripts.OnClick(question)
	assert(w.popup and w.ns.L.FUEL_ABOUT == "Party Fuel?\nWe are excited to use it!\nComing soon!", "it opens the note, on three lines")
	-- A click slices the same vat into a section per kind, each with one line.
	vat.scripts.OnMouseUp(vat)
	assert(#cells() == 1, "still one vat, not skinny vials")
	assert(not question.shown, "the question is for the whole vat only")
	local sections = {}
	for _, section in ipairs(vat.sections or {}) do
		if section.shown then sections[#sections + 1] = section end
	end
	assert(#sections == 2, "a section for each kind with any (XP and kills here)")
	assert(sections[1].text.text == "150 XP" and sections[2].text.text == "2 Kills", "each section says its number and name on one line")
	assert(sections[1].point[1] == "BOTTOMLEFT" and sections[1].point[5] == 0, "the first section sits on the bottom")
	assert(sections[2].point[5] == sections[1].height + 3, "sections stack with a small gap")
	assert(sections[1].height > sections[2].height, "more fuel, a bigger section")
	assert(sections[2].height >= 24, "even a small section has room for its line")
	assert(sections[2].point[5] + sections[2].height <= vat.track.height + 0.01, "the sections fit the vat")
	assert(not vat.parts[1].shown, "no whole liquid behind the sections")
	assert(w.ns.ReportView.Short(74321) == "74.3k" and w.ns.ReportView.Short(1200000) == "1.2M" and w.ns.ReportView.Short(9999) == "9,999", "big totals are short enough to fit")
	-- Another click: everyone's fuel, a line each, most first.
	vat.scripts.OnMouseUp(vat)
	assert(not vat.shown, "the vat makes way")
	local lines, links, back = {}, {}, nil
	for _, frame in ipairs(objects) do
		if frame.person and frame.shown then lines[#lines + 1] = frame end
		if frame.text and frame.scripts and frame.scripts.OnClick and frame.shown and not frame.person and frame.kind == "Button" and frame.height == 16 then links[#links + 1] = frame end
		if frame.text == "Back to Party Fuel" and frame.shown then back = frame end
	end
	assert(#lines == 2 and lines[1].person.name == "Bram" and lines[2].person.name == "Cora", "a line per player, the most fuel first")
	assert(lines[1].total.text == w.ns.ReportView.Short(lines[1].person.fuel) .. " fuel" and lines[1].person.fuel > lines[2].person.fuel, "their fuel beside their name")
	assert(lines[1].parts[1].shown, "their bar, sliced by kind")
	assert(#links == 2, "a link per player")
	assert(back == nil, "no button taking up a line: Party Fuel is an icon by the menus")
	-- A player's link scrolls to them; their bar opens their own view.
	lines[2].scripts.OnClick(lines[2])
	assert(w.ns.ReportView.player == "Cora", "a click on a player's bar opens their fuel")
	w.ns.ReportView.player = nil
	w.ns.ReportView:Draw()
	w.ns.ReportView.player = "Cora"
	w.ns.ReportView:Draw()
	w.ns.ReportView:Home()
	assert(w.ns.ReportView.player == nil and w.ns.ReportView.stage == "whole", "the Party Fuel icon goes home from anywhere")
	assert(vat.shown and vat.parts[1].shown and not sections[1].shown, "back to the party's fuel, whole")
	-- So does a click on empty space in the list of everyone.
	vat.scripts.OnMouseUp(vat)
	vat.scripts.OnMouseUp(vat)
	assert(w.ns.ReportView.stage == "everyone")
	local content = lines[1].parent
	content.scripts.OnMouseUp(content)
	assert(w.ns.ReportView.stage == "whole", "a click on empty space goes back to the total")
	-- And the note says the total and how the clicks go.
	question.scripts.OnClick(question)
	assert(w.popup.sender == w.ns.ReportView.fuelText, "the note has the party's total")
	-- Picking all types and all players starts over at the total.
	w.ns.ReportView.stage = "everyone"
	w.ns.ReportView:Reset()
	assert(w.ns.ReportView.stage == "whole", "all and all is the total")

	local function Sections(cell)
		local list = {}
		for _, section in ipairs(cell.sections or {}) do
			if section.shown then list[#list + 1] = section end
		end
		return list
	end

	-- One kind: the same wide vat, a section per player in their color.
	w.ns.ReportView.kind = "xp"
	w.ns.ReportView:Draw()
	assert(#cells() == 1, "one wide vat, not a vial per player")
	local players = Sections(cells()[1])
	assert(#players == 2 and players[1].text.text == "100 Bram" and players[2].text.text == "50 Cora", "a section per player, number and name on one line")
	assert(players[1].height > players[2].height, "more XP, a bigger section")
	assert(cells()[1].label.text == "XP: 150", "the kind and its total above")

	-- One player, every kind: a section per kind, with their share.
	w.ns.ReportView.kind, w.ns.ReportView.player = nil, "Cora"
	w.ns.ReportView:Draw()
	local kinds = Sections(cells()[1])
	assert(#kinds == 2 and kinds[1].text.text == "50 XP (33%)", "their number and share of the party's")

	-- One kind for one player: a single vial.
	w.ns.ReportView.kind = "xp"
	w.ns.ReportView:Draw()
	local vials = cells()
	assert(#vials == 1 and #Sections(vials[1]) == 0 and vials[1].value.text:find("33%%"), "a player's share of one kind, in one vial")
	assert(math.abs(vials[1].parts[1].height - vials[1].track.height / 3) <= 1, "the share fills only its part of the glass")
	w.ns.ReportView.kind = "quests"
	w.ns.ReportView:Draw()
	assert(not cells()[1].parts[1].shown and not cells()[1].surface.shown, "zero clears reused liquid and its surface")

	-- A big party: the vat grows to give every player room, and scrolls.
	for index = 1, 12 do
		w:ingest("xp", { xp = 10 * index, mob = "Kobold" }, "Player" .. index)
	end
	w.ns.ReportView.kind, w.ns.ReportView.player = "xp", nil
	w.ns.ReportView:Draw()
	players = Sections(cells()[1])
	assert(#players == 14, "every player has a section")
	for _, section in ipairs(players) do
		assert(section.height >= 24, "each with room for its line")
	end
	assert(chart.ScrollBar.shown, "taller than the view, so it scrolls")
	w.ns.ReportView.kind = nil
	w.ns.ReportView.stage = "whole"
	w.ns.ReportView:Draw()
	assert(not chart.ScrollBar.shown, "the whole vat fits again")
end
