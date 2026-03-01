--- @class LuaPlayerActionRequest Represents a player action request that can be inspected and modified by Lua scripts.
--- @field valid boolean True if this action request has a valid requester.
--- @field requester string The user ID of the player who made this action request.
--- @field info table The Lua table containing the action request data.
LuaPlayerActionRequest = {}

--- BeginChanges: Begins tracking changes to this action request's info for undo support.
--- @return nil
function LuaPlayerActionRequest:BeginChanges()
	-- dummy implementation for documentation purposes only
end

--- CompleteChanges: Commits tracked changes and creates an undoable game command with the given description.
--- @param description string
--- @return nil
function LuaPlayerActionRequest:CompleteChanges(description)
	-- dummy implementation for documentation purposes only
end
