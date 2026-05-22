--- @class CompanionSession A per-character Codex <-> Companion channel session.
--- @field characterId string The character id this session belongs to.
--- @field gameId string The game id this session belongs to.
CompanionSession = {}

--- IsConnected: True if the channel to the Companion is currently connected.
--- @return boolean
function CompanionSession:IsConnected()
	-- dummy implementation for documentation purposes only
end

--- SendEvent: Send a fire-and-forget event to this companion window.
--- @param type any
--- @param payload any
--- @return nil
function CompanionSession:SendEvent(type, payload)
	-- dummy implementation for documentation purposes only
end

--- SendRequest: Send a request to this companion window. onResponse(payload) or onError(message) is called when it resolves.
--- @param type any
--- @param payload any
--- @param onResponse any
--- @param onError any
--- @return nil
function CompanionSession:SendRequest(type, payload, onResponse, onError)
	-- dummy implementation for documentation purposes only
end

--- OnEvent: Register a handler fn(payload) for inbound events of the given type.
--- @param type any
--- @param handler any
--- @return nil
function CompanionSession:OnEvent(type, handler)
	-- dummy implementation for documentation purposes only
end

--- OnRequest: Register the handler fn(payload) for inbound requests of the given type. Return a table to answer; v1 handlers are synchronous.
--- @param type any
--- @param handler any
--- @return nil
function CompanionSession:OnRequest(type, handler)
	-- dummy implementation for documentation purposes only
end

--- DispatchEvent
--- @param type string
--- @param payload any
--- @return nil
function CompanionSession:DispatchEvent(type, payload)
	-- dummy implementation for documentation purposes only
end

--- DispatchRequest
--- @param id string
--- @param type string
--- @param payload any
--- @return nil
function CompanionSession:DispatchRequest(id, type, payload)
	-- dummy implementation for documentation purposes only
end
