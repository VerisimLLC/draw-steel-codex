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
