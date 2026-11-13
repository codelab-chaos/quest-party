-- Session roster. Sharing will be established by joining a channel.
-- Automatic group discovery and character-name friend links are retired.
local _, ns = ...

local Session = { peers = {} }
ns.Session = Session

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
