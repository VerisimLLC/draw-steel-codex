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
--- @param searchString string
--- @return boolean
function LuaGameInfo:MatchesSearch(searchString)
	-- dummy implementation for documentation purposes only
end

--- Leave
--- @return nil
function LuaGameInfo:Leave()
	-- dummy implementation for documentation purposes only
end

--- Delete
--- @return nil
function LuaGameInfo:Delete()
	-- dummy implementation for documentation purposes only
end

--- Undelete
--- @return nil
function LuaGameInfo:Undelete()
	-- dummy implementation for documentation purposes only
end

--- IsDM
--- @param s any
--- @return boolean
function LuaGameInfo:IsDM(s)
	-- dummy implementation for documentation purposes only
end

--- IsOwner
--- @param s any
--- @return boolean
function LuaGameInfo:IsOwner(s)
	-- dummy implementation for documentation purposes only
end

--- GetLocalTimePlayed
--- @param gameid string
--- @return number
function LuaGameInfo.GetLocalTimePlayed(gameid)
	-- dummy implementation for documentation purposes only
end

--- SetLocalTimePlayed
--- @param gameid string
--- @param t number
--- @return nil
function LuaGameInfo.SetLocalTimePlayed(gameid, t)
	-- dummy implementation for documentation purposes only
end

--- UploadCoverArt
--- @param options any
--- @return any
function LuaGameInfo:UploadCoverArt(options)
	-- dummy implementation for documentation purposes only
end
