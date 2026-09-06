---@meta

--- A per-character Codex <-> Companion channel session.
--- @class CompanionSession
--- @field characterId string The character id this session belongs to.
--- @field gameId string The game id this session belongs to.
CompanionSession = {}

--- True if the channel to the Companion is currently connected.
--- @return boolean
function CompanionSession:IsConnected() end

--- Send a fire-and-forget event to this companion window.
--- @param type? any
--- @param payload? any
function CompanionSession:SendEvent(type, payload) end

--- Send a request to this companion window. onResponse(payload) or onError(message) is called when it resolves.
--- @param type? any
--- @param payload? any
--- @param onResponse? any
--- @param onError? any
function CompanionSession:SendRequest(type, payload, onResponse, onError) end

--- Register a handler fn(payload) for inbound events of the given type.
--- @param type? any
--- @param handler? any
function CompanionSession:OnEvent(type, handler) end

--- Register the handler fn(payload) for inbound requests of the given type. Return a table to answer; v1 handlers are synchronous.
--- @param type? any
--- @param handler? any
function CompanionSession:OnRequest(type, handler) end

--- DispatchEvent
--- @param type? string
--- @param payload? any
function CompanionSession:DispatchEvent(type, payload) end

--- DispatchRequest
--- @param id? string
--- @param type? string
--- @param payload? any
function CompanionSession:DispatchRequest(id, type, payload) end
