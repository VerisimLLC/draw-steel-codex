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

--- ExecutePolygonOperation
--- @param options any
--- @return nil
function MapFloorLua:ExecutePolygonOperation(options)
	-- dummy implementation for documentation purposes only
end

--- BreakWallSegment: Break a wall segment, removing it from the map and optionally spawning a rubble object found by keyword.
--- If either tile bordering the segment is a wall-voxel column, its ground-level voxel is destroyed instead of erasing wall geometry.
--- @param segLocVal any
--- @param segDirVal any
--- @param rubbleKeywordVal any
--- @return nil
function MapFloorLua:BreakWallSegment(segLocVal, segDirVal, rubbleKeywordVal)
	-- dummy implementation for documentation purposes only
end

--- GetWallVoxelsAt: Get the wall-voxel objects (ObjectComponentWallVoxel) stacked on the given tile, ordered bottom to top.
--- Returns an array of object instances; empty if the tile has no wall voxels.
--- @param loc Loc
--- @return LuaObjectInstance[]
function MapFloorLua:GetWallVoxelsAt(loc)
	-- dummy implementation for documentation purposes only
end

--- SyncWallVoxelColumn: Reconcile the wall-voxel column on the given tile with its solid building operation.
--- Call after spawning wall-voxel objects locally (SpawnObjectLocal) and BEFORE uploading them: this assigns
--- stack ordering to new voxels, snaps them to the tile center, and rewrites the column's map operation.
--- Also safe to call at any time to repair a desynced column.
--- Typical ability flow, per cube placed (tiles are centered on integer coordinates):
---   local obj = floor:SpawnObjectLocal(wallVoxelAssetId, {posx = loc.x, posy = loc.y})
---   floor:SyncWallVoxelColumn(loc)
---   floor:Upload("Place wall")
--- @param loc Loc
--- @return nil
function MapFloorLua:SyncWallVoxelColumn(loc)
	-- dummy implementation for documentation purposes only
end

--- DestroyWallVoxel: Destroy the wall voxel occupying the given altitude (in tiles above floor zero) on the given tile.
--- The column collapses by one cube (a gap mid-column is not representable by solid terrain).
--- @param loc Loc
--- @param altitude number
--- @return boolean # true if a voxel was destroyed
function MapFloorLua:DestroyWallVoxel(loc, altitude)
	-- dummy implementation for documentation purposes only
end
