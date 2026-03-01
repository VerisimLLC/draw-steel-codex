--- @class analytics Provides Lua access to the analytics system for sending analytics events.
analytics = {}

--- Event: Sends an analytics event with the given arguments table. The table should contain a 'type' key identifying the event type.
--- @param args {type: string, [string]: any} Table of event data including at minimum a 'type' field.
function analytics.Event(args)
	-- dummy implementation for documentation purposes only
end
