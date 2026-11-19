-- Transport: sends and receives raw addon messages, the game's own way for an
-- addon to talk to the same addon on other players' machines. Nothing here
-- shows in anyone's chat. It knows nothing about what the messages mean.
-- Each outgoing message is sent once, straight away; the game's answer is not
-- judged: the channel is the truth, what comes back on it.
local _, ns = ...
local Bus = ns.Bus

local PREFIX = "QuestParty" -- 16 characters at most

local Transport = { prefix = PREFIX }
ns.Transport = Transport

-- Sends one message straight away. chatType is "PARTY", "RAID", "WHISPER"
-- or "CHANNEL"; target is the character for a whisper, the channel's number
-- for a channel. The game's answer is not judged: the channel is the truth,
-- what comes back on it (/qp share: sent against came back).
function Transport:Send(text, chatType, target)
	local message = { text = text, chatType = chatType, target = target }
	C_ChatInfo.SendAddonMessage(PREFIX, text, chatType, target)
	Bus:Fire("COMMS_SENT", message)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, text, chatType, sender, _, _, channelId)
	if prefix ~= PREFIX then
		return
	end
	-- Inside instances messages arrive as secret values, which cannot be read.
	if issecretvalue and (issecretvalue(text) or issecretvalue(sender)) then
		return
	end
	if type(text) ~= "string" or type(sender) ~= "string" then
		return
	end
	-- Same-realm names lose their realm, so they match what the player types.
	local name = Ambiguate(sender, "none")
	if ns.IsMe(name) then
		-- Our own message. The server sends a channel's messages to everyone
		-- on it, the sender included, so this one made the whole trip.
		Bus:Fire("COMMS_ECHOED", text, chatType, name, channelId)
		return
	end
	-- channelId is the channel's number when the message came over a channel.
	Bus:Fire("COMMS_RECEIVED", text, chatType, name, channelId)
end)

Bus:On("INIT", function()
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end)
