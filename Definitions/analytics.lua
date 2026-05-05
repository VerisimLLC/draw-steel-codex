--- @class analytics Provides Lua access to the analytics system for sending analytics events.
analytics = {}

--- Event: Sends an analytics event with the given arguments table. The table should contain a 'type' key identifying the event type. If a 'deduplicate' field (number of seconds) is present, the event is queued instead of sent immediately; subsequent events of the same type within that window replace the queued one and reset the timer, so only the final event in a burst is actually sent.
--- @param args {type: string, deduplicate: number?, [string]: any} Table of event data including at minimum a 'type' field. Optional 'deduplicate' specifies a coalescing window in seconds.
function analytics.Event(args)
	-- dummy implementation for documentation purposes only
end
