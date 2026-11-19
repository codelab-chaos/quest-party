-- Professions collector: this character's professions from the skill list,
-- as { { id, rank } } (data\professions.lua). Says PROFESSIONS_CHANGED when
-- they change, a moment after the game's skill lines settle (a skill-up and
-- learning one each fire a burst of events); comms\sharing.lua sends them.
local _, ns = ...
local Bus = ns.Bus

local Collector = { list = {}, text = "" }
ns.ProfessionsCollector = Collector

function Collector:Read()
	local skills = C_SkillInfo
	if not (skills and skills.GetNumSkillLines and skills.GetSkillLineInfo) then return nil end
	local list = {}
	for index = 1, skills.GetNumSkillLines() do
		local info = skills.GetSkillLineInfo(index)
		if info and not info.isHeader and ns.ProfessionById[info.skillID] then
			ns.LearnProfessionName(info.skillID, info.name)
			list[#list + 1] = { id = info.skillID, rank = info.rank or 0 }
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

function Collector:Check()
	local list = self:Read()
	if not list then return end
	local text = ns.EncodeProfessions(list)
	if text ~= self.text then
		self.list, self.text = list, text
		Bus:Fire("PROFESSIONS_CHANGED", list)
	end
end

-- Many events come at once: read once, a moment after the last.
local pending = false
function Collector:Soon()
	if pending then return end
	pending = true
	C_Timer.After(ns.Timing.professionSeconds, function()
		pending = false
		Collector:Check()
	end)
end

Bus:On("READY", function()
	Collector:Check()
	local frame = CreateFrame("Frame")
	for _, event in ipairs({ "SKILL_LINES_CHANGED", "PLAYER_ENTERING_WORLD" }) do
		pcall(frame.RegisterEvent, frame, event)
	end
	frame:SetScript("OnEvent", function() Collector:Soon() end)
end)
