--- @class CompanionChannelLua The Codex <-> Companion channel. Accessed via dmhub.companionChannel.
CompanionChannelLua = {}

--- IsAvailable: True if a Companion is currently connected to the channel.
--- @return boolean
function CompanionChannelLua:IsAvailable()
	-- dummy implementation for documentation purposes only
end

--- GetSessions: Returns an array of the active companion sessions, one per opened character.
--- @return any
function CompanionChannelLua:GetSessions()
	-- dummy implementation for documentation purposes only
end

--- GetSession: Returns the companion session for a character id, or nil if none is open.
--- @param characterId any
--- @return any
function CompanionChannelLua:GetSession(characterId)
	-- dummy implementation for documentation purposes only
end

--- OnCompanionConnected: Register fn(session), called when a companion session connects.
--- @param fn any
--- @return nil
function CompanionChannelLua:OnCompanionConnected(fn)
	-- dummy implementation for documentation purposes only
end

--- OnCompanionDisconnected: Register fn(session), called when a companion session disconnects.
--- @param fn any
--- @return nil
function CompanionChannelLua:OnCompanionDisconnected(fn)
	-- dummy implementation for documentation purposes only
end
