---@meta

--- Represents a single analytics event, providing read access to its data fields.
--- @class LuaAnalyticsEvent
LuaAnalyticsEvent = {}

--- Gets the value of the event data field with the given ID. Returns nil if the field does not exist.
--- @param id string The key of the data field to retrieve.
--- @return any
function LuaAnalyticsEvent:Get(id) end
