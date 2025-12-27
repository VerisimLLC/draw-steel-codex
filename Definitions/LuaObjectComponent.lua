--- @class LuaObjectComponent 
--- @field componentType string 
--- @field commands any 
--- @field _levelObject any 
--- @field preview boolean 
--- @field sheet any 
--- @field type any 
--- @field behaviorDescription any 
--- @field valid boolean 
--- @field name string 
--- @field displayPriority number 
--- @field tooltip string 
--- @field fields any 
--- @field disabled boolean 
--- @field deletable boolean 
--- @field properties any 
--- @field objectInstance any 
--- @field levelObject any 
LuaObjectComponent = {}

--- SetProperty
--- @param id string
--- @param val any
--- @return nil
function LuaObjectComponent:SetProperty(id, val)
	-- dummy implementation for documentation purposes only
end

--- Execute
--- @param commandDescription any
--- @return nil
function LuaObjectComponent:Execute(commandDescription)
	-- dummy implementation for documentation purposes only
end

--- ThinkEdit
--- @return nil
function LuaObjectComponent:ThinkEdit()
	-- dummy implementation for documentation purposes only
end

--- UpdateBlueprint
--- @param newAsset boolean?
--- @return nil
function LuaObjectComponent:UpdateBlueprint(newAsset)
	-- dummy implementation for documentation purposes only
end

--- GetFieldDisplayInfo
--- @param obj any
--- @param fieldName string
--- @return any
function LuaObjectComponent:GetFieldDisplayInfo(obj, fieldName)
	-- dummy implementation for documentation purposes only
end

--- Randomize
--- @param options any
--- @return nil
function LuaObjectComponent:Randomize(options)
	-- dummy implementation for documentation purposes only
end

--- BeginChanges
--- @return nil
function LuaObjectComponent:BeginChanges()
	-- dummy implementation for documentation purposes only
end

--- CompleteChanges
--- @param description string
--- @return nil
function LuaObjectComponent:CompleteChanges(description)
	-- dummy implementation for documentation purposes only
end

--- DestroyObject
--- @return nil
function LuaObjectComponent:DestroyObject()
	-- dummy implementation for documentation purposes only
end

--- RecordUndo
--- @return nil
function LuaObjectComponent:RecordUndo()
	-- dummy implementation for documentation purposes only
end

--- Upload
--- @param cmdgroupid string?
--- @return nil
function LuaObjectComponent:Upload(cmdgroupid)
	-- dummy implementation for documentation purposes only
end

--- SetAndUploadProperties
--- @param dict any
--- @return nil
function LuaObjectComponent:SetAndUploadProperties(dict)
	-- dummy implementation for documentation purposes only
end

--- CreateCustomEditor
--- @return any
function LuaObjectComponent:CreateCustomEditor()
	-- dummy implementation for documentation purposes only
end

--- CreateMultiCustomEditor
--- @param components any
--- @return any
function LuaObjectComponent:CreateMultiCustomEditor(components)
	-- dummy implementation for documentation purposes only
end
