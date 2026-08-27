--- @class buttonpack Provides the Lua interface for community button packs: publishing a toolkit of script buttons, querying the public index, downloading packs, and reading the kill-switch index.
buttonpack = {}

--- Publish: Publishes a button pack. options.pack is the pack table: { id (nil to mint a new pack), name, description, icon, buttons = { {name, icon, script}, ... } }. Stamps id, owner, version (auto-incremented from the published record), and mtime onto the pack table, writes /ButtonPack/{id} and /ButtonPackIndex/{id}, then calls options.success with the pack id. Fails early -- before any write -- when the caller is not signed in, does not own the pack id, or the pack has been disabled by the kill switch.
--- @param options table Options table with 'pack' (table), 'success' (function(string)), and 'failure' (function(string)) fields.
function buttonpack.Publish(options)
	-- dummy implementation for documentation purposes only
end

--- Unpublish: Withdraws a published button pack from the community: deletes /ButtonPackIndex/{packid} and then /ButtonPack/{packid}. Only the pack's owner may withdraw it (ownership is pre-checked against the published record for a clear error). A pack that no longer exists counts as success, so callers can always clear their remembered packid. Buttons other users have already added keep working -- their scripts were copied at add time.
--- @param options table Options table with 'packid' (string), 'success' (function(string)), and 'failure' (function(string)) fields.
function buttonpack.Unpublish(options)
	-- dummy implementation for documentation purposes only
end

--- QueryIndex: Queries the public button-pack index. Calls options.success with a table mapping packid -> { owner, name, description, icon, version, mtime, buttonCount }, empty when no packs exist.
--- @param options table Options table with 'success' (function(table)) and 'failure' (function(string)) fields.
function buttonpack.QueryIndex(options)
	-- dummy implementation for documentation purposes only
end

--- Download: Downloads a full button pack, scripts included. Calls options.success with the pack table, or options.failure when the pack does not exist.
--- @param options table Options table with 'packid' (string), 'success' (function(table)), and 'failure' (function(string)) fields.
function buttonpack.Download(options)
	-- dummy implementation for documentation purposes only
end

--- QueryKilled: Queries the kill-switch index. Calls options.success with a table mapping packid -> message for every disabled pack (empty when none are). Clients must check this before running any pack-sourced button.
--- @param options table Options table with 'success' (function(table)) and 'failure' (function(string)) fields.
function buttonpack.QueryKilled(options)
	-- dummy implementation for documentation purposes only
end

--- QueryStats: Queries the engagement stats for all packs. Calls options.success with a table mapping packid -> { downloads = {userid=true,...}, hearts = {userid=true,...} }; counts are the number of children (distinct users), and the caller's own userid appearing under hearts means they have hearted the pack.
--- @param options table Options table with 'success' (function(table)) and 'failure' (function(string)) fields.
function buttonpack.QueryStats(options)
	-- dummy implementation for documentation purposes only
end

--- RecordDownload: Records that the current user downloaded (added a button from) the given pack: a per-user mark, so repeat adds do not inflate the count. Fire-and-forget; requires being signed in.
--- @param options table Options table with a 'packid' (string) field.
function buttonpack.RecordDownload(options)
	-- dummy implementation for documentation purposes only
end

--- SetHeart: Sets or clears the current user's heart on the given pack. options.heart true writes the mark, false removes it. Fire-and-forget; requires being signed in.
--- @param options table Options table with 'packid' (string) and 'heart' (boolean) fields.
function buttonpack.SetHeart(options)
	-- dummy implementation for documentation purposes only
end
