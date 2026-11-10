---@meta

--- @class ObjectNodeLua:AssetNodeBaseLua
--- @field previewType any
--- @field keywords any
--- @field isfolder any
--- @field image any
--- @field imageId any
--- @field thumbnailId any Image id of the object's small (96 px) thumbnail, made on demand: for grid entries and other small icons. nil for a folder.
--- @field previewId any Image id of the object's larger (512 px) preview, made on demand: for a tooltip or other close look. Shows the small thumbnail while it is made, if that is loaded. nil for a folder.
--- @field scale any
--- @field fromMapPack boolean True when this node belongs only to an overlay -- the current map's "Objects for this map" set (see mappacks.currentMapObjects) or a props pack (see propspacks) -- and has no copy in the game yet. Such a folder comes and goes with its overlay, so it should not be renamed, deleted, or have objects moved into it. (Read-only)
--- @field components any
--- @field hue number
--- @field brightness number
--- @field saturation number
ObjectNodeLua = {}

--- Restores this from json.
--- @param json? string
function ObjectNodeLua:Restore(json) end

--- Upload
function ObjectNodeLua:Upload() end

--- Delete
function ObjectNodeLua:Delete() end

--- Duplicate
function ObjectNodeLua:Duplicate() end

--- UpdateObjectInstances
function ObjectNodeLua:UpdateObjectInstances() end

--- AddComponent
--- @param componentName? string
--- @return any
function ObjectNodeLua:AddComponent(componentName) end

--- BuildObjectComponentByName
--- @param componentName? string
--- @return any
function ObjectNodeLua.BuildObjectComponentByName(componentName) end

--- IsValidComponentJson
--- @param doc? any
--- @return any
function ObjectNodeLua:IsValidComponentJson(doc) end

--- ConstructComponent
--- @param doc? any
--- @return any
function ObjectNodeLua:ConstructComponent(doc) end

--- ComponentToJson
--- @param key? string
--- @return any
function ObjectNodeLua:ComponentToJson(key) end

--- RemoveComponent
--- @param componentNameOrKey? string
function ObjectNodeLua:RemoveComponent(componentNameOrKey) end
