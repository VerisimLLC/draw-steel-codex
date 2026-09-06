---@meta

--- @class ObjectNodeLua:AssetNodeBaseLua
--- @field previewType any
--- @field keywords any
--- @field isfolder any
--- @field image any
--- @field imageId any
--- @field thumbnailId any
--- @field scale any
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
