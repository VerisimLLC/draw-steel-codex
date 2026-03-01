--- @class previewScene Provides an interface for managing objects and settings in a fake (preview) game environment.
previewScene = {}

--- CreateObject: Creates a new object instance from the given asset ID and adds it to the fake game environment.
--- @param assetid string The asset ID of the object to create.
--- @return LuaObjectInstance
function previewScene:CreateObject(assetid)
	-- dummy implementation for documentation purposes only
end

--- ClearObjects: Removes all objects from the fake game environment.
--- @return nil
function previewScene:ClearObjects()
	-- dummy implementation for documentation purposes only
end

--- SetTimeOfDay: Sets the time of day in the fake game environment, tracking the previous value for transitions.
--- @param id string
--- @return nil
function previewScene:SetTimeOfDay(id)
	-- dummy implementation for documentation purposes only
end
