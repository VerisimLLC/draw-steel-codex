---@meta

--- @class MapManifestLua
--- @field id string
--- @field valid boolean
--- @field mapManifest any
--- @field dimensions any
--- @field loadingScreenImage string
--- @field packSource nil|{pack: string, mapid: string} The map pack this map was added from, or nil for a map that did not come from a map pack. pack is the pack's module fullid and mapid the map's id inside the pack. Maps added before provenance was recorded are recognised by their id when it is in the synced map pack index. (Read-only)
--- @field defaultFloorId any
--- @field groundLevel any
--- @field description any
--- @field floorsWithoutLayers any
--- @field floors any
--- @field parentFolder any
--- @field ord number
--- @field playerViewable boolean (Read-only) True if this map has the 'Player Viewable' map setting enabled. Player-viewable maps grant all players full vision and always appear in the player-facing Maps panel.
--- @field mapid string
MapManifestLua = {}

--- MarkUndo
function MapManifestLua:MarkUndo() end

--- Upload
--- @param description? string
function MapManifestLua:Upload(description) end

--- Delete
function MapManifestLua:Delete() end

--- Counts the building operations across all of this map's floors (every terrain layer) that draw with the given wall asset id. Erase operations do not count. The Map Markup panel uses this to tell whether removing a wall type from its palette orphans the asset. Probe inside pcall: older engine builds lack this method.
--- @param wallid string
--- @return number
function MapManifestLua:GetWallOperationCount(wallid) end

--- Rewrites every non-erase building operation on this map that draws with oldWallid so it draws with newWallid instead, across all floors and terrain layers, as one undoable command. Each rewritten operation keeps its timestamp (a fresh timestamp would re-order it after later erases on rebuilds) but gets a NEW id - the key change is what makes every client's terrain layers roll the old op back and apply the new one (the door-toggle swap pattern). Returns the number of operations rewritten. The Map Markup panel uses this to retype a map's walls when forking a shared wall type. Probe inside pcall: older engine builds lack this method.
--- @param oldWallid string
--- @param newWallid string
--- @return number
function MapManifestLua:ReplaceWallOperations(oldWallid, newWallid) end

--- GetFloorFromLoc
--- @param loc? any
--- @return any
function MapManifestLua:GetFloorFromLoc(loc) end

--- GetLayersForFloor
--- @param parentFloorId? any
--- @return any
function MapManifestLua:GetLayersForFloor(parentFloorId) end

--- CreateFloor
--- @param options? any
function MapManifestLua:CreateFloor(options) end

--- CreatePreviewFloor
--- @param floorBasis? string
--- @return any
function MapManifestLua:CreatePreviewFloor(floorBasis) end

--- DestroyPreviewFloor
--- @param floorInfo? any
function MapManifestLua:DestroyPreviewFloor(floorInfo) end

--- Travel
function MapManifestLua:Travel() end
