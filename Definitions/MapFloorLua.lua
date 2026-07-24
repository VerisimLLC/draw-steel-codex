--- @class MapFloorLua 
--- @field isPrimaryLayerOnFloor boolean 
--- @field parentFloor any 
--- @field actualFloor any 
--- @field preview boolean 
--- @field valid boolean 
--- @field mapFloor any 
--- @field description any 
--- @field objects any 
--- @field layerDescription any 
--- @field invisible any 
--- @field floorInvisible any 
--- @field locked any 
--- @field opacity any 
--- @field opacityNoUpload any 
--- @field floorOpacity any 
--- @field floorOpacityNoUpload any 
--- @field ceilingHeightInTiles number The floor's physical ceiling in tiles above floor zero (the primary floor slab's height; layers report their parent floor's). Solid terrain or wall voxels stacked to this height touch the ceiling.
--- @field floorHeightInTiles number 
--- @field shadowCasting any 
--- @field renderOrder any 
--- @field shareLighting any 
--- @field shareVision any 
--- @field roof any 
--- @field canopy any 
--- @field roofShowWhenInside any 
--- @field visionMultiplierNoUpload number 
--- @field visionMultiplier number 
--- @field roofVisionExclusion number 
--- @field roofVisionExclusionNoUpload any 
--- @field roofMinimumOpacity number 
--- @field roofMinimumOpacityNoUpload any 
--- @field roofVisionExclusionFade number 
--- @field roofVisionExclusionFadeNoUpload any 
--- @field charactersOnFloor any 
--- @field playerCharactersOnFloor any 
--- @field playerCharactersOnLayer any 
MapFloorLua = {}

--- AdjustParallaxPositionOnGround
--- @param x any
--- @param y any
--- @return any
function MapFloorLua:AdjustParallaxPositionOnGround(x, y)
	-- dummy implementation for documentation purposes only
end

--- HasObject
--- @param keyid string
--- @return boolean
function MapFloorLua:HasObject(keyid)
	-- dummy implementation for documentation purposes only
end

--- GetObject
--- @param keyid string
--- @return any
function MapFloorLua:GetObject(keyid)
	-- dummy implementation for documentation purposes only
end

--- CreateObjectCopy
--- @param luaObjectInstance any
--- @return any
function MapFloorLua:CreateObjectCopy(luaObjectInstance)
	-- dummy implementation for documentation purposes only
end

--- CreateObject
--- @param obj any
--- @return any
function MapFloorLua:CreateObject(obj)
	-- dummy implementation for documentation purposes only
end

--- CreateLocalObjectFromBlueprint
--- @param options any
--- @return any
function MapFloorLua:CreateLocalObjectFromBlueprint(options)
	-- dummy implementation for documentation purposes only
end

--- SpawnEphemeralLevelObject
--- @param options any
--- @return any
function MapFloorLua:SpawnEphemeralLevelObject(options)
	-- dummy implementation for documentation purposes only
end

--- GetNumberOfProjectiles
--- @param tokenid string
--- @return number
function MapFloorLua:GetNumberOfProjectiles(tokenid)
	-- dummy implementation for documentation purposes only
end

--- GetProjectiles
--- @param tokenid string
--- @return any
function MapFloorLua:GetProjectiles(tokenid)
	-- dummy implementation for documentation purposes only
end

--- ChangeElevation
--- @param options {type: 'rectangle'|'ellipse'|'polygon', center: nil|Vector2, radius: nil|number|Vector2, p1: nil|Vector2, p2: nil|Vector2, points = nil|(Vector2[]), opacity: number, blend: nil|number, add: nil|boolean, height: number, recalculateTokenElevation: nil|boolean}
function MapFloorLua:ChangeElevation(options)
	-- dummy implementation for documentation purposes only
end

--- ScaleMapElevations
--- @param factorValue any
--- @param optionsValue any
--- @return nil
function MapFloorLua:ScaleMapElevations(factorValue, optionsValue)
	-- dummy implementation for documentation purposes only
end

--- SpawnObjectLocal
--- @param objectid any
--- @param options any
--- @return any
function MapFloorLua:SpawnObjectLocal(objectid, options)
	-- dummy implementation for documentation purposes only
end

--- GetAltitudeAtLoc
--- @param loc any
--- @return number
function MapFloorLua:GetAltitudeAtLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- SampleHeightmapAt
--- @param xv any
--- @param yv any
--- @return number
function MapFloorLua:SampleHeightmapAt(xv, yv)
	-- dummy implementation for documentation purposes only
end

--- DumpHeightmap
--- @return any
function MapFloorLua:DumpHeightmap()
	-- dummy implementation for documentation purposes only
end

--- ClearHeightmapPreviousSamples
--- @return nil
function MapFloorLua:ClearHeightmapPreviousSamples()
	-- dummy implementation for documentation purposes only
end

--- SetHeightmapZoneSkipDisabled
--- @param disabledVal any
--- @return nil
function MapFloorLua:SetHeightmapZoneSkipDisabled(disabledVal)
	-- dummy implementation for documentation purposes only
end

--- ExecutePolygonOperation: Executes a building operation on this floor. Options: points (list of interleaved x,y point lists), tileid, wallid, wallheight, erase, eraseInvisibleOnly (erase only walls with invisible assets), walls, floor, terrain, closed, layer, fade.
--- @param options any
--- @return nil
function MapFloorLua:ExecutePolygonOperation(options)
	-- dummy implementation for documentation purposes only
end

--- GetNearestWallSegment: Finds the drawn wall geometry nearest to a point on this floor's building layer. Options: x, y (world coords), maxDistance (tiles, default 1), invisibleOnly (default false: when true only walls with invisible assets are considered), atMouse (default false: when true x/y are ignored, the current mouse position is used, and walls are matched in projected screen space -- each vertex projected by its surface-altitude parallax like wall rendering -- so the result is what is visually under the cursor even on steep slopes or raised/lowered ground). Returns nil, or a table with wallid, wallheight, distance, points (interleaved x,y list of the wall's full path, suitable for passing to ExecutePolygonOperation), segmentIndex (1-based index of the nearest edge within the path) and segment (interleaved x,y of that nearest edge's two endpoints, in floor space).
--- @param options {x: nil|number, y: nil|number, maxDistance: nil|number, invisibleOnly: nil|boolean, atMouse: nil|boolean}
--- @return nil|{wallid: string, wallheight: number, distance: number, points: number[], segmentIndex: number, segment: number[]}
function MapFloorLua:GetNearestWallSegment(options)
	-- dummy implementation for documentation purposes only
end

--- BreakWallSegment: Break a wall segment, removing it from the map and optionally spawning a rubble object found by keyword.
--- @param segLocVal any
--- @param segDirVal any
--- @param rubbleKeywordVal any
--- @return nil
function MapFloorLua:BreakWallSegment(segLocVal, segDirVal, rubbleKeywordVal)
	-- dummy implementation for documentation purposes only
end

--- GetWallVoxelsAt: Get the wall-voxel objects (ObjectComponentWallVoxel) stacked on the given tile, ordered bottom to top. Returns an array of object instances; empty if the tile has no wall voxels.
--- @param locVal any
--- @return any
function MapFloorLua:GetWallVoxelsAt(locVal)
	-- dummy implementation for documentation purposes only
end

--- SyncWallVoxelColumn: Reconcile the wall-voxel column on the given tile with its solid building operation. Call after spawning wall-voxel objects locally (SpawnObjectLocal) and BEFORE uploading them: this assigns stack ordering to new voxels, snaps them to the tile center, and rewrites the column's map operation. Also safe to call any time to repair a desynced column.
--- @param locVal any
--- @return nil
function MapFloorLua:SyncWallVoxelColumn(locVal)
	-- dummy implementation for documentation purposes only
end

--- DestroyWallVoxel: Destroy the wall voxel occupying the given altitude (in tiles above floor zero) on the given tile. The column collapses by one cube. Returns true if a voxel was destroyed, false if the tile has no wall voxels.
--- @param locVal any
--- @param altitudeVal any
--- @return boolean
function MapFloorLua:DestroyWallVoxel(locVal, altitudeVal)
	-- dummy implementation for documentation purposes only
end
