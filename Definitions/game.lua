--- @class game 
--- @field currentMap any 
--- @field currentMapId any 
--- @field currentFloorIndex number 
--- @field currentFloor any 
--- @field currentFloorId any 
--- @field coverart string 
--- @field rootMapFolder any 
--- @field maps any 
--- @field mapFolders any 
game = {}

--- GetFloor
--- @param floorid any
--- @return any
function game.GetFloor(floorid)
	-- dummy implementation for documentation purposes only
end

--- DeleteFloor
--- @param luaFloorid any
--- @return nil
function game.DeleteFloor(luaFloorid)
	-- dummy implementation for documentation purposes only
end

--- PrepareDeleteFloor
--- @param floorid string
--- @param evacuationFloor any
--- @param patch any
--- @param unpatch any
--- @return nil
function game.PrepareDeleteFloor(floorid, evacuationFloor, patch, unpatch)
	-- dummy implementation for documentation purposes only
end

--- MergeFloors
--- @param floorid any
--- @param srcid any
--- @return any
function game.MergeFloors(floorid, srcid)
	-- dummy implementation for documentation purposes only
end

--- PrepareMergeFloors
--- @param groupid string
--- @param floorid string
--- @param srcid string
--- @param patch any
--- @param unpatch any
--- @return string
function game.PrepareMergeFloors(groupid, floorid, srcid, patch, unpatch)
	-- dummy implementation for documentation purposes only
end

--- ChangeMap
--- @param map any
--- @param floor any
--- @return nil
function game.ChangeMap(map, floor)
	-- dummy implementation for documentation purposes only
end

--- FloorIsAboveGround
--- @param floor any
--- @return boolean
function game.FloorIsAboveGround(floor)
	-- dummy implementation for documentation purposes only
end

--- Refresh
--- @param options any
--- @return nil
function game.Refresh(options)
	-- dummy implementation for documentation purposes only
end

--- CreateCharacter
--- @param chartype any
--- @param subtype any
--- @return any
function game.CreateCharacter(chartype, subtype)
	-- dummy implementation for documentation purposes only
end

--- DeleteCharacters
--- @param charids any
--- @return nil
function game.DeleteCharacters(charids)
	-- dummy implementation for documentation purposes only
end

--- LookupObject
--- @param floorid string
--- @param objectid string
--- @return any
function game.LookupObject(floorid, objectid)
	-- dummy implementation for documentation purposes only
end

--- GetObjectsWithAffinityToCharacter
--- @param charid string
--- @return any
function game.GetObjectsWithAffinityToCharacter(charid)
	-- dummy implementation for documentation purposes only
end

--- GetAurasAtLoc
--- @param loc any
--- @return any
function game.GetAurasAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- GetCharacterById
--- @param id any
--- @return any
function game.GetCharacterById(id)
	-- dummy implementation for documentation purposes only
end

--- GetGameGlobalCharacters
--- @return any
function game.GetGameGlobalCharacters()
	-- dummy implementation for documentation purposes only
end

--- GetTokensAtLoc
--- @param loc any
--- @return any
function game.GetTokensAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- UnsummonTokens
--- @param tokenidList any
--- @return nil
function game.UnsummonTokens(tokenidList)
	-- dummy implementation for documentation purposes only
end

--- SpawnTokenFromBestiaryLocally
--- @param id string
--- @param loc any
--- @param options any
--- @return any
function game.SpawnTokenFromBestiaryLocally(id, loc, options)
	-- dummy implementation for documentation purposes only
end

--- UpdateCharacterTokens
--- @return nil
function game.UpdateCharacterTokens()
	-- dummy implementation for documentation purposes only
end

--- GetMap
--- @param id string
--- @return any
function game.GetMap(id)
	-- dummy implementation for documentation purposes only
end

--- CreateMapFolder
--- @return nil
function game.CreateMapFolder()
	-- dummy implementation for documentation purposes only
end

--- CreateMap
--- @param options any
--- @return string
function game.CreateMap(options)
	-- dummy implementation for documentation purposes only
end

--- DuplicateMap
--- @param mapid string
--- @param oncomplete any
--- @return nil
function game.DuplicateMap(mapid, oncomplete)
	-- dummy implementation for documentation purposes only
end
