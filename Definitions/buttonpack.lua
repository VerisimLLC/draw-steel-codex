--- @class buttonpack Provides the Lua interface for community button packs: publishing a toolkit of script buttons, querying the public index, downloading packs, and reading the kill-switch index. See PANEL_LIBRARY_BRIEF.md for the design.
buttonpack = {}

--- Publish: Publishes a button pack. options.pack is the pack table: { id (nil to mint a new pack), name, description, icon, buttons = { {name, icon, script}, ... } }. Stamps id, owner, version (auto-incremented from the published record), and mtime onto the pack table, writes /ButtonPack/{id} and /ButtonPackIndex/{id}, then calls options.success with the pack id. Fails early -- before any write -- when the caller is not signed in, does not own the pack id, or the pack has been disabled by the kill switch.
--- @param options {pack: table, success: nil|fun(packid: string), failure: nil|fun(error: string)}
function buttonpack.Publish(options)
	-- dummy implementation for documentation purposes only
end

--- QueryIndex: Queries the public button-pack index. Calls options.success with a table mapping packid -> { owner, name, description, icon, version, mtime, buttonCount }, empty when no packs exist.
--- @param options {success: fun(index: table<string, table>), failure: nil|fun(error: string)}
function buttonpack.QueryIndex(options)
	-- dummy implementation for documentation purposes only
end

--- Download: Downloads a full button pack, scripts included. Calls options.success with the pack table, or options.failure when the pack does not exist.
--- @param options {packid: string, success: fun(pack: table), failure: nil|fun(error: string)}
function buttonpack.Download(options)
	-- dummy implementation for documentation purposes only
end

--- QueryKilled: Queries the kill-switch index. Calls options.success with a table mapping packid -> message for every disabled pack (empty when none are). Clients must check this before running any pack-sourced button.
--- @param options {success: fun(killed: table<string, string>), failure: nil|fun(error: string)}
function buttonpack.QueryKilled(options)
	-- dummy implementation for documentation purposes only
end

--- QueryStats: Queries the engagement stats for all packs. Calls options.success with a table mapping packid -> { downloads = {userid=true,...}, hearts = {userid=true,...} }; counts are the number of children (distinct users), and the caller's own userid appearing under hearts means they have hearted the pack.
--- @param options {success: fun(stats: table<string, {downloads: table<string, boolean>, hearts: table<string, boolean>}>), failure: nil|fun(error: string)}
function buttonpack.QueryStats(options)
	-- dummy implementation for documentation purposes only
end

--- RecordDownload: Records that the current user downloaded (added a button from) the given pack: a per-user mark, so repeat adds do not inflate the count. Fire-and-forget; requires being signed in.
--- @param options {packid: string}
function buttonpack.RecordDownload(options)
	-- dummy implementation for documentation purposes only
end

--- SetHeart: Sets or clears the current user's heart on the given pack. options.heart true writes the mark, false removes it. Fire-and-forget; requires being signed in.
--- @param options {packid: string, heart: boolean}
function buttonpack.SetHeart(options)
	-- dummy implementation for documentation purposes only
end
