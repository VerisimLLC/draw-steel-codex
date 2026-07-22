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
--- @field characterIndex table<string,{id: string, name: string, owner: nil|string, party: nil|string, summary: nil|string, portrait: nil|string}> Index of the game's important characters (assigned to a player or a party), from cached metadata; available without connecting to the game. The portrait field is an image id registered for use as a bgimage. Games last saved by older client versions may lack party/portrait.
--- @field playerInfo table<string,{displayName: nil|string, summary: any, appearance: any}> Per-player info for this game keyed by userid, from cached metadata. appearance is a CharacterAppearance whose portrait images are usable in the current context.
--- @field contentSummary nil|{monsters: number, classes: number, races: number, kits: number, other: number} Summary counts of the game's own content from cached metadata. Nil for games not yet opened by a client version that records summaries.
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
