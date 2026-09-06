---@meta

--- @class LuaGameInfo
--- @field gameSystem any
--- @field storage number
--- @field hasLocalData boolean
--- @field description any
--- @field descriptionDetails any
--- @field password any
--- @field coverart any
--- @field owner any
--- @field ownerDisplayName any
--- @field dm any
--- @field players any
--- @field deleted any
--- @field timePlayed number
--- @field playerSummary any
--- @field characterAppearance any
--- @field characterIndex table Index of the game's important characters (assigned to a player or a party), read from the game's cached metadata without connecting to the game. Returns a table keyed by character id; each entry has id, name, and optionally owner (userid), party (party asset id), summary, and portrait (image id, registered so it can be used directly as a bgimage). Games last saved by older client versions may lack the party and portrait fields.
--- @field contentSummary nil|table Summary counts of the game's own content from cached metadata: monsters, classes, races, kits, and other (remaining compendium entries). Nil for games that have not yet been opened by a client version that records summaries.
--- @field playerInfo table Per-player info for this game keyed by userid, read from the game's cached metadata: displayName, summary, and appearance (a CharacterAppearance whose portrait images are usable in the current context).
LuaGameInfo = {}

--- MatchesSearch
--- @param searchString? string
--- @return boolean
function LuaGameInfo:MatchesSearch(searchString) end

--- Leave
function LuaGameInfo:Leave() end

--- Permanently destroy this game. For a game the user owns: marks it deleted in the lobby record, releases its server storage (the game's Durable Object for DO-backed games, the on-disk files for Local games), and removes it from the account's game list / Encounter of the Week slot. For a game the user does not own, this degrades to Leave(). Options: 'complete' (function(success, error) -- success reflects the storage release; the deleted flag and account cleanup happen regardless).
--- @param options table Options with an optional 'complete' callback field.
function LuaGameInfo:DeleteAndReleaseStorage(options) end

--- Delete
function LuaGameInfo:Delete() end

--- Undelete
function LuaGameInfo:Undelete() end

--- IsDM
--- @param s? any
--- @return boolean
function LuaGameInfo:IsDM(s) end

--- IsOwner
--- @param s? any
--- @return boolean
function LuaGameInfo:IsOwner(s) end

--- GetLocalTimePlayed
--- @param gameid? string
--- @return number
function LuaGameInfo.GetLocalTimePlayed(gameid) end

--- SetLocalTimePlayed
--- @param gameid? string
--- @param t? number
function LuaGameInfo.SetLocalTimePlayed(gameid, t) end

--- UploadCoverArt
--- @param options? any
--- @return any
function LuaGameInfo:UploadCoverArt(options) end
