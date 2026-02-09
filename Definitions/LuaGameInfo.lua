--- @class LuaGameInfo 
--- @field gameSystem any 
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
