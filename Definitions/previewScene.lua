---@meta

--- Provides an interface for managing objects and settings in a fake (preview) game environment.
--- @class previewScene
previewScene = {}

--- Creates a new object instance from the given asset ID and adds it to the fake game environment.
--- @param assetid string The asset ID of the object to create.
--- @return LuaObjectInstance
function previewScene:CreateObject(assetid) end

--- Removes all objects from the fake game environment.
function previewScene:ClearObjects() end

--- Sets the time of day in the fake game environment, tracking the previous value for transitions.
--- @param id? string
function previewScene:SetTimeOfDay(id) end
