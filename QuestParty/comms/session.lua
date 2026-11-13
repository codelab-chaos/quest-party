-- Channel connection. Creating and joining use the same client operation,
-- as in Blizzard's channel window. Joining is confirmed by channel membership,
-- not by the return value of the join request. Progress transport is separate.
local _, ns = ...
local Bus, L = ns.Bus, ns.L

local Session = { peers = {}, state = "disconnected" }
ns.Session = Session

local attempt = 0
local joinTimer
local function Subscribe(name)
	for _, channel in pairs(DEFAULT_CHAT_FRAME.channelList or {}) do
		if channel:lower() == name:lower() then return end
	end
	DEFAULT_CHAT_FRAME:AddChannel(name)
end

local function CancelJoin()
	attempt = attempt + 1
	if joinTimer then
		joinTimer:Cancel()
		joinTimer = nil
	end
end

local function SetState(state, id, errorMessage)
	if Session.state == state and Session.channelId == id and Session.error == errorMessage then
		return
	end
	Session.state, Session.channelId, Session.error = state, id, errorMessage
	Bus:Fire("CONNECTION_CHANGED")
end

function Session:RefreshConnection()
	local config = ns.db.connection
	if not config.enabled or config.name == "" then
		SetState("disconnected")
		return
	end
	local id = GetChannelName(config.name)
	if id and id > 0 then
		CancelJoin()
		SetState("connected", id)
	elseif self.state == "connected" then
		SetState("disconnected")
	end
end

function Session:Connect(value)
	local name = type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
	if name == "" or #name > 30 or name:find("[%s%c|]") or name:match("^%d+$") then
		return false, L.CHANNEL_INVALID_NAME
	end
	local config = ns.db.connection
	if config.enabled and config.name:lower() ~= name:lower()
		and (self.state == "connected" or self.state == "joining") then
		return false, L.CHANNEL_DISCONNECT_FIRST
	end
	CancelJoin()
	config.name, config.enabled = name, true
	SetState("joining")
	self:RefreshConnection()
	if self.state == "connected" then
		Subscribe(name)
		return true
	end
	local zoneChannel, channelName = JoinPermanentChannel(name, nil, DEFAULT_CHAT_FRAME:GetID(), 1)
	if not zoneChannel then
		SetState("failed", nil, L.CHANNEL_JOIN_FAILED)
		return false, L.CHANNEL_JOIN_FAILED
	end
	-- Mirror the stock chat frame's subscription so normal channel chat is visible.
	Subscribe(channelName or name)
	self:RefreshConnection()
	if self.state == "joining" then
		local currentAttempt = attempt
		joinTimer = C_Timer.NewTimer(15, function()
			if attempt ~= currentAttempt or not config.enabled then return end
			Session:RefreshConnection()
			if Session.state == "joining" then
				SetState("failed", nil, L.CHANNEL_JOIN_FAILED)
			end
		end)
	end
	return true
end

function Session:Disconnect()
	local config = ns.db.connection
	local name, wasEnabled = config.name, config.enabled
	CancelJoin()
	config.enabled = false
	SetState("disconnected")
	if wasEnabled and name ~= "" then
		LeaveChannelByName(name)
	end
end

function Session:IsConnected(name)
	return self.peers[name] ~= nil
end

function Session:Count()
	local count = 0
	for _ in pairs(self.peers) do
		count = count + 1
	end
	return count
end

local failures = {
	WRONG_PASSWORD = true, BANNED = true, INVALID_NAME = true,
	THROTTLED = true, TOO_MANY_CHANNELS = true, NOT_ALLOWED_IN_CHANNEL = true,
}

Bus:On("READY", function()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("CHANNEL_UI_UPDATE")
	frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:SetScript("OnEvent", function(_, event, notice, _, _, _, _, _, _, _, channelName)
		local config = ns.db.connection
		if event == "CHAT_MSG_CHANNEL_NOTICE" then
			if not config.enabled or type(channelName) ~= "string" or channelName:lower() ~= config.name:lower() then
				return
			end
			if type(notice) ~= "string" or (issecretvalue and issecretvalue(notice)) then return end
			if notice == "YOU_LEFT" then
				CancelJoin()
				config.enabled = false
				SetState("disconnected")
				return
			elseif failures[notice] then
				CancelJoin()
				SetState("failed", nil, L.CHANNEL_JOIN_FAILED)
				return
			end
		end
		Session:RefreshConnection()
		if event == "PLAYER_ENTERING_WORLD" and config.enabled and Session.state == "disconnected" then
			Session:Connect(config.name)
		end
	end)
	local config = ns.db.connection
	if config.enabled and config.name ~= "" then
		Session:Connect(config.name)
	end
end)
