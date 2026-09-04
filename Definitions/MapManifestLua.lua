--- @class MapManifestLua 
--- @field id string 
--- @field valid boolean 
--- @field mapManifest any 
--- @field dimensions any 
--- @field loadingScreenImage string 
--- @field defaultFloorId any 
--- @field groundLevel any 
--- @field description any 
--- @field floorsWithoutLayers any 
--- @field floors any 
--- @field parentFolder any 
--- @field ord number 
--- @field playerViewable boolean (Read-only) True if this map has the 'Player Viewable' map setting enabled. Player-viewable maps grant all players full vision and always appear in the player-facing Maps panel.
MapManifestLua = {}

--- MarkUndo
--- @return nil
function MapManifestLua:MarkUndo()
	-- dummy implementation for documentation purposes only
end

--- Upload
--- @param description string
--- @return nil
function MapManifestLua:Upload(description)
	-- dummy implementation for documentation purposes only
end

--- Delete
--- @return nil
function MapManifestLua:Delete()
	-- dummy implementation for documentation purposes only
end

--- GetWallOperationCount: Counts the building operations across all of this map's floors (every terrain layer) that draw with the given wall asset id. Erase operations do not count. The Map Markup panel uses this to tell whether removing a wall type from its palette orphans the asset. Probe inside pcall: older engine builds lack this method.
--- @param wallid string
--- @return number
function MapManifestLua:GetWallOperationCount(wallidVal)
	-- dummy implementation for documentation purposes only
end

--- ReplaceWallOperations: Rewrites every non-erase building operation on this map that draws with oldWallid so it draws with newWallid instead, across all floors and terrain layers, as one undoable command. Each rewritten operation keeps its timestamp (a fresh timestamp would re-order it after later erases on rebuilds) but gets a NEW id - the key change is what makes every client's terrain layers roll the old op back and apply the new one (the door-toggle swap pattern). Returns the number of operations rewritten. The Map Markup panel uses this to retype a map's walls when forking a shared wall type. Probe inside pcall: older engine builds lack this method.
--- @param oldWallid string
--- @param newWallid string
--- @return number
function MapManifestLua:ReplaceWallOperations(oldVal, newVal)
	-- dummy implementation for documentation purposes only
end

--- GetFloorFromLoc
--- @param loc any
--- @return any
function MapManifestLua:GetFloorFromLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- GetLayersForFloor
--- @param parentFloorId any
--- @return any
function MapManifestLua:GetLayersForFloor(parentFloorId)
	-- dummy implementation for documentation purposes only
end

--- CreateFloor
--- @param options any
--- @return nil
function MapManifestLua:CreateFloor(options)
	-- dummy implementation for documentation purposes only
end

--- CreatePreviewFloor
--- @param floorBasis string
--- @return any
function MapManifestLua:CreatePreviewFloor(floorBasis)
	-- dummy implementation for documentation purposes only
end

--- DestroyPreviewFloor
--- @param floorInfo any
--- @return nil
function MapManifestLua:DestroyPreviewFloor(floorInfo)
	-- dummy implementation for documentation purposes only
end

--- Travel
--- @return nil
function MapManifestLua:Travel()
	-- dummy implementation for documentation purposes only
end
