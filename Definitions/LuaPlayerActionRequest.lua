---@meta

--- Represents a player action request that can be inspected and modified by Lua scripts.
--- @class LuaPlayerActionRequest
--- @field valid boolean True if this action request has a valid requester.
--- @field requester string The user ID of the player who made this action request.
--- @field info table The Lua table containing the action request data.
LuaPlayerActionRequest = {}

--- Begins tracking changes to this action request's info for undo support.
function LuaPlayerActionRequest:BeginChanges() end

--- Commits tracked changes and creates an undoable game command with the given description.
--- @param description? string
function LuaPlayerActionRequest:CompleteChanges(description) end
