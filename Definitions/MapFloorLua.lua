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

--- ExecutePolygonOperation
--- @param options any
--- @return nil
function MapFloorLua:ExecutePolygonOperation(options)
	-- dummy implementation for documentation purposes only
end
