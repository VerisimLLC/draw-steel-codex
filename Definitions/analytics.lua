---@meta

--- Provides Lua access to the analytics system for sending analytics events.
--- @class analytics
analytics = {}

--- Sends an analytics event with the given arguments table. The table should contain a 'type' key identifying the event type. If a 'deduplicate' field (number of seconds) is present, the event is queued instead of sent immediately; subsequent events of the same type within that window replace the queued one and reset the timer, so only the final event in a burst is actually sent.
--- @param args {type: string, deduplicate: number?, [string]: any} Table of event data including at minimum a 'type' field. Optional 'deduplicate' specifies a coalescing window in seconds.
function analytics.Event(args) end

--- Sets a context field that is stamped onto every analytics event sent afterwards, from Lua and from the engine alike (a field the event sets itself wins). Pass nil as the value to clear it. 'scope' limits where it applies: 'game' = only while the game that is loaded now stays loaded, 'titlescreen' = only while no game is loaded, nil = everywhere. Used to tag events with the mode the player is in, e.g. eotwWhere = 'town'.
--- @param key string The field name stamped onto each event.
--- @param value any The value (string, number or boolean), or nil to clear the field.
--- @param scope? 'game'|'titlescreen' Where the field applies; omit for everywhere.
function analytics.SetContext(key, value, scope) end

--- True when analytics would currently tag an event as Encounter of the Week (eotw = true): the loaded game is the account's Encounter of the Week game, or Lua set the 'eotw' context.
--- @return boolean
function analytics.IsEotw() end
