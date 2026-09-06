---@meta

--- @class MapFloorLua
--- @field isPrimaryLayerOnFloor boolean
--- @field parentFloor any
--- @field actualFloor any
--- @field preview boolean
--- @field valid boolean
--- @field mapFloor any
--- @field description any
--- @field objects any
--- @field supportsMarkupZones boolean Probe property: true on engine builds with the markup zone storage API (markupZones / SetMarkupZone / RemoveMarkupZone). Read inside pcall to detect older builds.
--- @field floorIndex number The index of this floor in the currently visible floor list, or -1 if this floor is not part of the current map.
--- @field markupZones table<string,table> The markup zone records stored on this floor, keyed by zone id. Treat the returned records as read-only; to modify a zone build a fresh table and call SetMarkupZone.
--- @field layerDescription any
--- @field invisible any
--- @field floorInvisible any
--- @field locked any
--- @field opacity any
--- @field opacityNoUpload any
--- @field floorOpacity any
--- @field floorOpacityNoUpload any
--- @field ceilingHeightInTiles number The floor's slab height in tiles above floor zero (the primary floor slab's height; layers report their parent floor's). Solid terrain or wall voxels stack no higher than this. Whether the plane caps the floor is 'hasCeiling'.
--- @field ceiling any The floor's ceiling override: 'auto' (default -- has a ceiling when another floor is above it or the floor is below ground level), 'yes' (always has a ceiling), or 'no' (open-topped). See hasCeiling for the resolved value.
--- @field hasCeiling boolean Read-only. Whether this floor is capped by a ceiling at its slab height, after resolving the 'ceiling' override and the automatic rule (another floor above it, or below ground level). Layers report their parent floor's value.
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
--- @field supportsSolidOperations boolean True when this engine build supports solid=true in ExecutePolygonOperation (solid block drawing) and invisible-only solid erasing. Callers drawing solids must check this: older engines treat a solid op as a plain floor draw.
--- @field floorid string
MapFloorLua = {}

--- AdjustParallaxPositionOnGround
--- @param x? any
--- @param y? any
--- @return any
function MapFloorLua:AdjustParallaxPositionOnGround(x, y) end

--- HasObject
--- @param keyid? string
--- @return boolean
function MapFloorLua:HasObject(keyid) end

--- GetObject
--- @param keyid? string
--- @return any
function MapFloorLua:GetObject(keyid) end

--- Creates or replaces the markup zone record with the given id on this floor. Undoable; syncs to other clients; triggers an aura rebuild.
--- @param zoneid? string
--- @param data? any
function MapFloorLua:SetMarkupZone(zoneid, data) end

--- Deletes the markup zone record with the given id from this floor. Undoable; syncs to other clients; triggers an aura rebuild.
--- @param zoneid? string
function MapFloorLua:RemoveMarkupZone(zoneid) end

--- CreateObjectCopy
--- @param luaObjectInstance? any
--- @return any
function MapFloorLua:CreateObjectCopy(luaObjectInstance) end

--- CreateObject
--- @param obj? any
--- @return any
function MapFloorLua:CreateObject(obj) end

--- CreateLocalObjectFromBlueprint
--- @param options? any
--- @return any
function MapFloorLua:CreateLocalObjectFromBlueprint(options) end

--- SpawnEphemeralLevelObject
--- @param options? any
--- @return any
function MapFloorLua:SpawnEphemeralLevelObject(options) end

--- GetNumberOfProjectiles
--- @param tokenid? string
--- @return number
function MapFloorLua:GetNumberOfProjectiles(tokenid) end

--- GetProjectiles
--- @param tokenid? string
--- @return any
function MapFloorLua:GetProjectiles(tokenid) end

--- ChangeElevation
--- @param options {type: 'rectangle'|'ellipse'|'polygon', center: nil|Vector2Arg, radius: nil|number|Vector2Arg, p1: nil|Vector2Arg, p2: nil|Vector2Arg, points: nil|(Vector2Arg[]), opacity: number, blend: nil|number, add: nil|boolean, height: number, recalculateTokenElevation: nil|boolean}
function MapFloorLua:ChangeElevation(options) end

--- ScaleMapElevations
--- @param factorValue? any
--- @param optionsValue? any
function MapFloorLua:ScaleMapElevations(factorValue, optionsValue) end

--- SpawnObjectLocal
--- @param objectid? any
--- @param options? any
--- @return any
function MapFloorLua:SpawnObjectLocal(objectid, options) end

--- GetAltitudeAtLoc
--- @param loc? any
--- @return number
function MapFloorLua:GetAltitudeAtLoc(loc) end

--- SampleHeightmapAt
--- @param xv? any
--- @param yv? any
--- @return number
function MapFloorLua:SampleHeightmapAt(xv, yv) end

--- DumpHeightmap
--- @return any
function MapFloorLua:DumpHeightmap() end

--- ClearHeightmapPreviousSamples
function MapFloorLua:ClearHeightmapPreviousSamples() end

--- SetHeightmapZoneSkipDisabled
--- @param disabledVal? any
function MapFloorLua:SetHeightmapZoneSkipDisabled(disabledVal) end

--- ExecutePolygonOperation
--- @param options? any
function MapFloorLua:ExecutePolygonOperation(options) end

--- Finds the drawn wall geometry nearest to a point on this floor's building layer. Options: x, y (world coords), maxDistance (tiles, default 1), invisibleOnly (default false: when true only walls with invisible assets are considered), atMouse (default false: when true x/y are ignored, the current mouse position is used, and walls are matched in projected screen space -- each vertex projected by its surface-altitude parallax like wall rendering -- so the result is what is visually under the cursor even on steep slopes or raised/lowered ground). Returns nil, or a table with wallid, wallheight, distance, points (interleaved x,y list of the wall's full path, suitable for passing to ExecutePolygonOperation), segmentIndex (1-based index of the nearest edge within the path) and segment (interleaved x,y of that nearest edge's two endpoints, in floor space).
--- @param options {x: nil|number, y: nil|number, maxDistance: nil|number, invisibleOnly: nil|boolean, atMouse: nil|boolean}
--- @return nil|{wallid: string, wallheight: number, distance: number, points: number[], segmentIndex: number, segment: number[]}
function MapFloorLua:GetNearestWallSegment(options) end

--- Changes the wall type of drawn markup wall geometry on this floor. Options: wallid (required, the new wall asset id) plus exactly one selection: segment = {ax, ay, bx, by} (floor-space endpoints of one drawn edge, e.g. GetNearestWallSegment's segment result - every operation with an edge coincident with it is retyped WHOLE, the click-a-wall gesture) or rect = {x1, y1, x2, y2} (floor-space axis-aligned rectangle - every operation edge intersecting it, boundary inclusive, is retyped at EDGE granularity). Only non-erase, non-solid wall operations whose current wall asset is invisible are considered (markup scope; art walls are never touched). In rect mode an operation with only some edges caught is split at its own vertices into a kept part and a retyped part - no polygon clipping is involved - and every replacement keeps the original operation's timestamp (so it re-applies in the same order relative to erases) under a new id, which is what makes clients rebuild. One undoable command per call. Returns the number of edges retyped. Probe inside pcall: older engine builds lack this method.
--- @param options {wallid: string, segment: nil|number[], rect: nil|number[]}
--- @return number
function MapFloorLua:RetypeWallEdges(options) end

--- Read-only companion to RetypeWallEdges' rect mode, for live previews: returns the drawn markup wall edges a rect-mode call with the same rectangle would retype, as a flat interleaved list {a1x, a1y, b1x, b1y, a2x, ...} of floor-space edge endpoints. Options: rect = {x1, y1, x2, y2} (required); wallid (optional - edges of operations already of this type are omitted, matching what a retype to that type would skip). Same eligibility as RetypeWallEdges: non-erase, non-solid wall operations with an invisible wall asset. Capped at 300 edges. Probe inside pcall: older engine builds lack this method.
--- @param options {rect: number[], wallid: nil|string}
--- @return number[]
function MapFloorLua:GetWallEdgesInRect(options) end

--- Break a wall segment, removing it from the map and optionally spawning a rubble object found by keyword.
--- @param segLocVal? any
--- @param segDirVal? any
--- @param rubbleKeywordVal? any
function MapFloorLua:BreakWallSegment(segLocVal, segDirVal, rubbleKeywordVal) end

--- Get the wall-voxel objects (ObjectComponentWallVoxel) stacked on the given tile, ordered bottom to top. Returns an array of object instances; empty if the tile has no wall voxels.
--- @param locVal? any
--- @return any
function MapFloorLua:GetWallVoxelsAt(locVal) end

--- Reconcile the wall-voxel column on the given tile with its solid building operation. Call after spawning wall-voxel objects locally (SpawnObjectLocal) and BEFORE uploading them: this assigns stack ordering to new voxels, snaps them to the tile center, and rewrites the column's map operation. Also safe to call any time to repair a desynced column.
--- @param locVal? any
function MapFloorLua:SyncWallVoxelColumn(locVal) end

--- Destroy the wall voxel occupying the given altitude (in tiles above floor zero) on the given tile. The column collapses by one cube. Returns true if a voxel was destroyed, false if the tile has no wall voxels.
--- @param locVal? any
--- @param altitudeVal? any
--- @return boolean
function MapFloorLua:DestroyWallVoxel(locVal, altitudeVal) end
