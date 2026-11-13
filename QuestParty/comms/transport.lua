-- Transport: sends and receives raw addon messages. It knows nothing about what
-- they mean. Outgoing messages go through a queue that respects the game's
-- throttle and waits out chat lockdown (instances, some combat states).
local addonName, ns = ...
local Bus = ns.Bus

local PREFIX = "QuestParty" -- 16 characters at most

local LIMITS = {
	burst = 8, -- messages allowed at once
	perSecond = 1, -- refill rate after a burst
	queue = 60, -- older messages are dropped past this
	retrySeconds = 1,
}

local Transport = { queue = {}, tokens = LIMITS.burst, last = 0, waiting = false }
ns.Transport = Transport

-- Results that mean "try again later" instead of "this message failed".
local function ShouldRetry(result)
	local results = Enum and Enum.SendAddonMessageResult
	if not results or type(result) ~= "number" then
		return false
	end
	return result == results.AddonMessageThrottle
		or result == results.ChannelThrottle
		or result == results.AddOnMessageLockdown
end

local function Refill()
	local now = GetTime()
	Transport.tokens = math.min(LIMITS.burst, Transport.tokens + (now - Transport.last) * LIMITS.perSecond)
	Transport.last = now
end

local function Pump()
	Transport.waiting = false
	Refill()
	local queue = Transport.queue
	while queue[1] and Transport.tokens >= 1 do
		if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
			break
		end
		local message = queue[1]
		local result = C_ChatInfo.SendAddonMessage(PREFIX, message.text, message.chatType, message.target)
		if ShouldRetry(result) then
			break
		end
		table.remove(queue, 1)
		Transport.tokens = Transport.tokens - 1
	end
	if queue[1] and not Transport.waiting then
		Transport.waiting = true
		C_Timer.After(LIMITS.retrySeconds, Pump)
	end
end

-- chatType is "PARTY", "RAID" or "WHISPER". target is the character for a whisper.
function Transport:Send(text, chatType, target)
	local queue = self.queue
	queue[#queue + 1] = { text = text, chatType = chatType, target = target }
	while #queue > LIMITS.queue do
		table.remove(queue, 1)
	end
	Pump()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, channel, sender)
	if prefix ~= PREFIX then
		return
	end
	-- Same-realm names lose their realm, so they match what the player types.
	local name = Ambiguate(sender, "none")
	if name == UnitName("player") then
		return -- our own party message, echoed back
	end
	Bus:Fire("COMMS_RECEIVED", text, channel, name)
end)

Bus:On("INIT", function()
	Transport.last = GetTime()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)
