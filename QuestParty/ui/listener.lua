-- Listener: a small window that lists the hidden messages on the Quest Party
-- channel as they pass: what this client sent, what the server sent back, and
-- what arrived from other players. It only shows what comms\sharing.lua has
-- already logged, and changes nothing. Debug mode only: /qp listen.
--
-- It can only show Quest Party's own messages. The game hands an addon the
-- messages sent under its own prefix, and nobody else's.
local _, ns = ...
local Bus = ns.Bus
local L = ns.L

local Listener = {}
ns.Listener = Listener

local LAYOUT = { width = 560, height = 240, pad = 8, titleHeight = 22, lines = 500 }

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- How each direction of travel is written, as data.
local DIRECTIONS = {
	out = { color = "ff888888", label = function() return L.LISTENER_OUT end },
	back = { color = "ff40d040", label = function() return L.LISTENER_BACK end },
	["in"] = { color = "ff3b9dff", label = function(record) return L.LISTENER_IN:format(record.sender or "?") end },
}

local frame, messages, title

local function Line(record)
	local direction = DIRECTIONS[record.direction]
	if not direction then
		return nil
	end
	return ("|cff666666%s|r  |c%s%s|r  %s"):format(date("%H:%M:%S", record.time), direction.color, direction.label(record), record.text)
end

local function Add(record)
	local line = Line(record)
	if messages and line then
		messages:AddMessage(line)
	end
end

local function UpdateTitle()
	if not title then
		return
	end
	local session, config = ns.Session, ns.db.connection
	title:SetText(session.state == "connected" and L.LISTENER_TITLE:format(config.name) or L.LISTENER_TITLE_OFF)
end

local function SavePosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.charDb.listener = ns.charDb.listener or {}
	ns.charDb.listener.position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function Build()
	frame = CreateFrame("Frame", "QuestPartyListener", UIParent, "BackdropTemplate")
	frame:SetSize(LAYOUT.width, LAYOUT.height)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.04, 0.05, 0.08, 0.94)
	frame:SetBackdropBorderColor(0.5, 0.42, 0.2, 1)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	local saved = ns.charDb.listener and ns.charDb.listener.position
	if saved then
		frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
	else
		frame:SetPoint("CENTER", 0, -160)
	end

	title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT", LAYOUT.pad + 2, -LAYOUT.pad)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetScript("OnClick", function()
		Listener:Show(false)
	end)

	messages = CreateFrame("ScrollingMessageFrame", nil, frame)
	messages:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.pad + LAYOUT.titleHeight))
	messages:SetPoint("BOTTOMRIGHT", -LAYOUT.pad, LAYOUT.pad)
	messages:SetFontObject(ChatFontSmall or ChatFontNormal)
	messages:SetJustifyH("LEFT")
	messages:SetFading(false)
	messages:SetMaxLines(LAYOUT.lines)
	messages:EnableMouseWheel(true)
	messages:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)

	-- What passed before the window was opened.
	for _, record in ipairs(ns.Sharing.log) do
		Add(record)
	end
	UpdateTitle()
end

function Listener:IsShown()
	return frame ~= nil and frame:IsShown()
end

-- Shows or hides the window. It only opens in debug mode.
function Listener:Show(show)
	show = show and ns.IsDebug()
	if show and not frame then
		Build()
	end
	if frame then
		frame:SetShown(show)
	end
	ns.charDb.listener = ns.charDb.listener or {}
	ns.charDb.listener.shown = show and true or false
end

function Listener:Toggle()
	self:Show(not self:IsShown())
end

Bus:On("COMMS_LOGGED", Add)
Bus:On("CONNECTION_CHANGED", UpdateTitle)

Bus:On("READY", function()
	if ns.charDb.listener and ns.charDb.listener.shown then
		Listener:Show(true)
	end
end)

Bus:On("DEBUG_CHANGED", function(enabled)
	if not enabled then
		Listener:Show(false)
	end
end)
