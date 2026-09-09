---@meta

--- The Codex <-> Companion channel. Accessed via dmhub.companionChannel.
--- @class CompanionChannelLua
CompanionChannelLua = {}

--- True if a Companion is currently connected to the channel.
--- @return boolean
function CompanionChannelLua:IsAvailable() end

--- Returns an array of the active companion sessions, one per opened character.
--- @return any
function CompanionChannelLua:GetSessions() end

--- Returns the companion session for a character id, or nil if none is open.
--- @param characterId? any
--- @return any
function CompanionChannelLua:GetSession(characterId) end

--- Register fn(session), called when a companion session connects.
--- @param fn? any
function CompanionChannelLua:OnCompanionConnected(fn) end

--- Register fn(session), called when a companion session disconnects.
--- @param fn? any
function CompanionChannelLua:OnCompanionDisconnected(fn) end
