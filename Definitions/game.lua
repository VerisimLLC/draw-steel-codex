---@meta

--- Provides access to game state including maps, floors, tokens, and characters.
--- @class game
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

--- Gets a floor by its ID. Returns nil if the floor does not exist.
--- @param floorid string|number The floor ID.
--- @return nil|MapFloorLua
function game.GetFloor(floorid) end

--- Deletes a floor and all its child floors from the current map.
--- @param luaFloorid string|number The floor ID to delete.
function game.DeleteFloor(luaFloorid) end

--- Prepares patch and unpatch dictionaries for deleting a floor. Used internally by DeleteFloor.
--- @param floorid? string
--- @param evacuationFloor? number?
--- @param patch? table<string, any>
--- @param unpatch? table<string, any>
function game.PrepareDeleteFloor(floorid, evacuationFloor, patch, unpatch) end

--- Merges two floors together, combining their terrain, objects, and raster data. Returns the resulting floor ID.
--- @param floorid string|number The target floor ID.
--- @param srcid string|number The source floor ID to merge into the target.
--- @return string
function game.MergeFloors(floorid, srcid) end

--- Prepares patch and unpatch dictionaries for merging two floors. Used internally by MergeFloors.
--- @param groupid? string
--- @param floorid? string
--- @param srcid? string
--- @param patch? table<string, any>
--- @param unpatch? table<string, any>
--- @return string
function game.PrepareMergeFloors(groupid, floorid, srcid, patch, unpatch) end

--- Changes the active map, optionally navigating to a specific floor.
--- @param map MapManifestLua The map to switch to.
--- @param floor nil|MapFloorLua Optional floor to navigate to.
function game.ChangeMap(map, floor) end

--- Returns whether the given floor is above ground level. Accepts a floor ID string, MapFloorLua, or nil for the current floor.
--- @param floor nil|string|MapFloorLua
--- @return boolean
function game.FloorIsAboveGround(floor) end

--- Refreshes game details from the server. Options table can specify currentMap, floors, and tokens to selectively refresh.
--- @param options nil|table Optional refresh filters with currentMap (boolean), floors (string[]), and tokens (string[]).
function game.Refresh(options) end

--- Creates a new character of the given type and subtype, returning its ID. Defaults to type 'character' and empty subtype.
--- @param chartype nil|string The character type, e.g. 'character'.
--- @param subtype nil|string The character subtype.
--- @return string
function game.CreateCharacter(chartype, subtype) end

--- Deletes multiple characters by their IDs.
--- @param charids string[] A table of character ID strings to delete.
function game.DeleteCharacters(charids) end

--- Looks up an object instance on a floor by its floor and object IDs.
--- @param floorid string The floor ID.
--- @param objectid string The object ID.
--- @return LuaObjectInstance
function game.LookupObject(floorid, objectid) end

--- Gets all objects on visible floors that have an affinity to the specified character.
--- @param charid string The character ID.
--- @return table
function game.GetObjectsWithAffinityToCharacter(charid) end

--- Gets all auras active at the given location. Returns nil if no auras are found.
--- @param loc Loc The location to query.
--- @return nil|Aura[]
function game.GetAurasAtLoc(loc) end

--- Gets a character token by its ID. Returns nil if not found.
--- @param id string The character ID.
--- @return nil|CharacterToken
function game.GetCharacterById(id) end

--- Gets a table of all characters that have an owner, keyed by character ID.
--- @return table<string, CharacterToken>
function game.GetGameGlobalCharacters() end

--- Gets all character tokens at the given location. Returns nil if none are found.
--- @param loc Loc The location to query.
--- @return nil|CharacterToken[]
function game.GetTokensAtLoc(loc) end

--- Teleports tokens to a map, which need not be the current one; Director (or player host) only. The first token is centred on the world point x, y on floor index floor of that map (the terms of dmhub.GetMapSnapshotInfo and dmhub.GetMapTokens), and the others go on the nearest free tiles around it. On the current map this is an ordinary summon. On another map its walls and terrain are not loaded: tokens only avoid other tokens, and land at altitude 0. Mounted tokens take their mounts along. Undoable. Used by the tabletop to drop a token dragged out of the live map window onto another map's window.
--- @param charids string[]
--- @param mapid string
--- @param x number
--- @param y number
--- @param floor integer
function game.SendTokensToMap(charids, mapid, x, y, floor) end

--- Creates bestiary creatures on a map, which need not be the current one; Director (or player host) only. monsterids is a list of bestiary ids, which join initiative together (a minion squad lists its id once per minion), or a list of such lists, one per initiative group (an encounter). The first creature is centred on the world point x, y on floor index floor of that map (the terms of dmhub.GetMapSnapshotInfo), and the others go on the nearest free tiles around it, as game.SendTokensToMap places tokens; game.PlanTokensOnMap says where. Each runs its OnCreateFromBestiary. Undoable as one step. Unlike placing on the live map this does not fire spawnFromBestiary, whose handlers act on the current map. Returns the new charids. Used by the tabletop to drop a bestiary entry onto another map's window.
--- @param monsterids string[]|string[][]
--- @param mapid string
--- @param x number
--- @param y number
--- @param floor integer
--- @return string[]
function game.SpawnBestiaryOnMap(monsterids, mapid, x, y, floor) end

--- Where tokens would land if dropped on a map at a world point, without placing them: the plan game.SendTokensToMap (ids are charids) and game.SpawnBestiaryOnMap (ids are bestiary ids, decided by the first) follow for the same point, so a drag can preview a drop exactly. One entry per token that would arrive, in order: its id (a rider's mount stands in for it, as it moves in its place), the world point at the centre of its footprint, and the footprint's width in tiles. Only other tokens are in the way, as with those calls.
--- @param ids string[]
--- @param mapid string
--- @param x number
--- @param y number
--- @param floor integer
--- @return {id: string, x: number, y: number, tiles: integer}[]
function game.PlanTokensOnMap(ids, mapid, x, y, floor) end

--- Removes the specified tokens from the game with an unsummon animation.
--- @param tokenidList string[] A table of token ID strings to unsummon.
function game.UnsummonTokens(tokenidList) end

--- Spawns a token from a bestiary entry at the given location locally without uploading. Pass a nil loc to create the character without putting it on a map -- it exists in the game and can be placed later, like any character that hasn't been dropped on the map yet. A loc whose altitude is below the ground under the token's footprint is raised to that ground, so a loc built from x/y alone lands on raised terrain correctly; pass onGround = true when the loc has no real altitude (built from x/y alone) to stand the token on the surface under it in either direction -- lowered into a sunken area as well as raised onto high ground. Returns the created token, or nil if the bestiary entry is not found.
--- @param id string The bestiary entry ID.
--- @param loc nil|Loc The location to spawn at, or nil to create the character unplaced.
--- @param options nil|table Optional settings; fitLocation (boolean) controls whether the location is adjusted for token size; onGround (boolean) stands the token on the surface under its footprint (the highest at or below the loc) instead of only raising it.
--- @return nil|CharacterToken
function game.SpawnTokenFromBestiaryLocally(id, loc, options) end

--- Forces a refresh of all character token visuals.
function game.UpdateCharacterTokens() end

--- Gets a map manifest by its ID. Returns nil if not found.
--- @param id string The map ID.
--- @return nil|MapManifestLua
function game.GetMap(id) end

--- Creates a new map folder with a default name and appends it after existing folders.
function game.CreateMapFolder() end

--- Creates a new map with the given options and returns its GUID.
--- @param options nil|table Optional map creation settings.
--- @return string
function game.CreateMap(options) end

--- Asynchronously duplicates a map and calls the callback when complete.
--- @param mapid string The ID of the map to duplicate.
--- @param oncomplete function Called when duplication is complete.
function game.DuplicateMap(mapid, oncomplete) end

--- Lists the maps in another of the user's games (one from lobby.games), in that game's map order. Each entry has the map's id, name, floorCount, and folder (the name of the folder it is in there, or nil). Reads the other game's data without entering it. Calls options.success with the list, or options.error with a message.
--- @param options {gameid: string, success: nil|fun(maps: {id: string, name: string, floorCount: integer, folder: nil|string}[]), error: nil|fun(message: string)}
function game.ListOtherGameMaps(options) end

--- Looks up a preview for a map in another of the user's games. result.imported is true when the map was made from an imported image (it has an object with a Map component); then result.imageid is a bgimage id for that image, registered for this session; width and height are its pixel size when the image record has one, else 0 (usual for map images). Maps built by hand have no image. Downloads the map's floors, so call it only for maps being shown. Calls options.success with the result, or options.error with a message.
--- @param options {gameid: string, mapid: string, success: nil|fun(result: {imported: boolean, imageid: nil|string, width: nil|integer, height: nil|integer}), error: nil|fun(message: string)}
function game.GetOtherGameMapPreview(options) end

--- Copies a map from another of the user's games into the current game under fresh ids: its floors, objects, walls and terrain, and the records of any images and custom objects it uses from that game's own asset store. Tokens, teleporter links and the map's folder are not copied; the copy goes at the top level of the map list, named options.name when given. Calls options.success with the new map's id, or options.error with a message.
--- @param options {gameid: string, mapid: string, name: nil|string, success: nil|fun(mapid: string), error: nil|fun(message: string)}
function game.ImportMapFromOtherGame(options) end

--- Begin recording destructive map modifications (heightmap and terrain edits) into a persistent record. All map edits until EndRecordingMapModification is called are captured so they can be reverted later. Recordings with the same key merge into a single record, grouping the edits of one ability cast.
--- @param options {key: nil|string, name: nil|string, casterid: nil|string, casterName: nil|string, floorid: nil|string, loc: nil|{x: number, y: number}}
function game.BeginRecordingMapModification(options) end

--- End the active map modification recording, persisting the record if any map edits were captured. Safe to call when no recording is active.
function game.EndRecordingMapModification() end

--- Begin batching wall-voxel column synchronization. Column terrain operations remain current locally, but their server patches and the expensive map rebuild are deferred until EndWallVoxelBatch. Batches nest: Begin/End are refcounted and only the outermost End publishes, so a helper that batches internally composes with a batched caller. Pair every Begin with an End in the same synchronous burst -- a batch left open is flushed when the next one starts on a later frame, and may not span a coroutine yield.
function game.BeginWallVoxelBatch() end

--- End the active wall-voxel batch. The outermost End publishes all accumulated terrain-operation edits in one non-undoable patch and rebuilds the map once if any column changed; an inner End of a nested batch just decrements the count. Safe to call when no batch is active.
function game.EndWallVoxelBatch() end

--- Attach a wall-voxel object (as returned by floor:SpawnObjectLocal) to the active map modification recording. Wall voxels persist outside the map document, so recordings reference them directly instead of capturing commands; deleting the record destroys whichever of its voxels still survive. No-op if no recording is active.
--- @param obj LuaObjectInstance The spawned wall-voxel object.
function game.AddMapModificationVoxel(obj) end

--- Get the recorded map modifications for the current map, sorted newest first. Each entry has id, key, name, casterid, casterName, floorid, x, y, timestamp, count (the number of captured edit commands), voxelCount (wall voxels recorded, for wall-building records), and voxelsRemaining (how many of those voxels still exist on the map).
--- @return {id: string, key: string, name: string, casterid: nil|string, casterName: nil|string, floorid: string, x: number, y: number, timestamp: number, count: number, voxelCount: number, voxelsRemaining: number}[]
function game.GetMapModifications() end

--- Revert a recorded map modification, restoring the captured pre-modification state, and delete its record. For wall-building records this destroys whichever recorded wall voxels still survive. Command reverts are a single undoable step (undoing re-applies the modification and restores the record); wall-voxel removal is not undoable.
--- @param id string The modification record id, as returned by GetMapModifications.
function game.DeleteMapModification(id) end
