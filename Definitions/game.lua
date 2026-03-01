--- @class game Provides access to game state including maps, floors, tokens, and characters.
--- @field currentMap MapManifestLua Gets the current active map.
--- @field currentMapId string Gets the ID string of the current active map.
--- @field currentFloorIndex number Gets the zero-based index of the current floor in the map's floor list.
--- @field currentFloor MapFloorLua Gets the current active floor.
--- @field currentFloorId string Gets the ID string of the current active floor.
--- @field coverart string Gets the cover art image ID for the current game.
--- @field rootMapFolder MapFolderLua Gets the root map folder.
--- @field maps MapManifestLua[] Gets a list of all map manifests in the current game.
--- @field mapFolders MapFolderLua[] Gets a list of all map folders in the current game.
game = {}

--- GetFloor: Gets a floor by its ID. Returns nil if the floor does not exist.
--- @param floorid string|number The floor ID.
--- @return nil|MapFloorLua
function game.GetFloor(floorid)
	-- dummy implementation for documentation purposes only
end

--- DeleteFloor: Deletes a floor and all its child floors from the current map.
--- @param luaFloorid string|number The floor ID to delete.
function game.DeleteFloor(luaFloorid)
	-- dummy implementation for documentation purposes only
end

--- PrepareDeleteFloor: Prepares patch and unpatch dictionaries for deleting a floor. Used internally by DeleteFloor.
--- @param floorid string
--- @param evacuationFloor any
--- @param patch any
--- @param unpatch any
--- @return nil
function game.PrepareDeleteFloor(floorid, evacuationFloor, patch, unpatch)
	-- dummy implementation for documentation purposes only
end

--- MergeFloors: Merges two floors together, combining their terrain, objects, and raster data. Returns the resulting floor ID.
--- @param floorid string|number The target floor ID.
--- @param srcid string|number The source floor ID to merge into the target.
--- @return string
function game.MergeFloors(floorid, srcid)
	-- dummy implementation for documentation purposes only
end

--- PrepareMergeFloors: Prepares patch and unpatch dictionaries for merging two floors. Used internally by MergeFloors.
--- @param groupid string
--- @param floorid string
--- @param srcid string
--- @param patch any
--- @param unpatch any
--- @return string
function game.PrepareMergeFloors(groupid, floorid, srcid, patch, unpatch)
	-- dummy implementation for documentation purposes only
end

--- ChangeMap: Changes the active map, optionally navigating to a specific floor.
--- @param map MapManifestLua The map to switch to.
--- @param floor nil|MapFloorLua Optional floor to navigate to.
function game.ChangeMap(map, floor)
	-- dummy implementation for documentation purposes only
end

--- FloorIsAboveGround: Returns whether the given floor is above ground level. Accepts a floor ID string, MapFloorLua, or nil for the current floor.
--- @return number
function game.FloorIsAboveGround()
	-- dummy implementation for documentation purposes only
end

--- Refresh: Refreshes game details from the server. Options table can specify currentMap, floors, and tokens to selectively refresh.
--- @param options nil|table Optional refresh filters with currentMap (boolean), floors (string[]), and tokens (string[]).
function game.Refresh(options)
	-- dummy implementation for documentation purposes only
end

--- CreateCharacter: Creates a new character of the given type and subtype, returning its ID. Defaults to type 'character' and empty subtype.
--- @param chartype nil|string The character type, e.g. 'character'.
--- @param subtype nil|string The character subtype.
--- @return string
function game.CreateCharacter(chartype, subtype)
	-- dummy implementation for documentation purposes only
end

--- DeleteCharacters: Deletes multiple characters by their IDs.
--- @param charids string[] A table of character ID strings to delete.
function game.DeleteCharacters(charids)
	-- dummy implementation for documentation purposes only
end

--- LookupObject: Looks up an object instance on a floor by its floor and object IDs.
--- @param floorid string The floor ID.
--- @param objectid string The object ID.
--- @return LuaObjectInstance
function game.LookupObject(floorid, objectid)
	-- dummy implementation for documentation purposes only
end

--- GetObjectsWithAffinityToCharacter: Gets all objects on visible floors that have an affinity to the specified character.
--- @param charid string The character ID.
--- @return table
function game.GetObjectsWithAffinityToCharacter(charid)
	-- dummy implementation for documentation purposes only
end

--- GetAurasAtLoc: Gets all auras active at the given location. Returns nil if no auras are found.
--- @param loc LuaLoc The location to query.
--- @return nil|Aura[]
function game.GetAurasAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- GetCharacterById: Gets a character token by its ID. Returns nil if not found.
--- @param id string The character ID.
--- @return nil|LuaCharacterToken
function game.GetCharacterById(id)
	-- dummy implementation for documentation purposes only
end

--- GetGameGlobalCharacters: Gets a table of all characters that have an owner, keyed by character ID.
--- @return table<string, LuaCharacterToken>
function game.GetGameGlobalCharacters()
	-- dummy implementation for documentation purposes only
end

--- GetTokensAtLoc: Gets all character tokens at the given location. Returns nil if none are found.
--- @param loc LuaLoc The location to query.
--- @return nil|LuaCharacterToken[]
function game.GetTokensAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- UnsummonTokens: Removes the specified tokens from the game with an unsummon animation.
--- @param tokenidList string[] A table of token ID strings to unsummon.
function game.UnsummonTokens(tokenidList)
	-- dummy implementation for documentation purposes only
end

--- SpawnTokenFromBestiaryLocally: Spawns a token from a bestiary entry at the given location locally without uploading. Returns the created token, or nil if the bestiary entry is not found.
--- @param id string The bestiary entry ID.
--- @param loc LuaLoc The location to spawn at.
--- @param options nil|table Optional settings; fitLocation (boolean) controls whether the location is adjusted for token size.
--- @return nil|LuaCharacterToken
function game.SpawnTokenFromBestiaryLocally(id, loc, options)
	-- dummy implementation for documentation purposes only
end

--- UpdateCharacterTokens: Forces a refresh of all character token visuals.
--- @return nil
function game.UpdateCharacterTokens()
	-- dummy implementation for documentation purposes only
end

--- GetMap: Gets a map manifest by its ID. Returns nil if not found.
--- @param id string The map ID.
--- @return nil|MapManifestLua
function game.GetMap(id)
	-- dummy implementation for documentation purposes only
end

--- CreateMapFolder: Creates a new map folder with a default name and appends it after existing folders.
--- @return nil
function game.CreateMapFolder()
	-- dummy implementation for documentation purposes only
end

--- CreateMap: Creates a new map with the given options and returns its GUID.
--- @param options nil|table Optional map creation settings.
function game.CreateMap(options)
	-- dummy implementation for documentation purposes only
end

--- DuplicateMap: Asynchronously duplicates a map and calls the callback when complete.
--- @param mapid string The ID of the map to duplicate.
--- @param oncomplete function Called when duplication is complete.
function game.DuplicateMap(mapid, oncomplete)
	-- dummy implementation for documentation purposes only
end
