--- @class LuaObjectInstance 
--- @field id string 
--- @field imageid string 
--- @field assetid string 
--- @field parentid string 
--- @field childids any 
--- @field artist string 
--- @field floorIndex number 
--- @field inactive boolean 
--- @field editingInfo any 
--- @field x number 
--- @field y number 
--- @field rotation number 
--- @field scale number 
--- @field description any 
--- @field name any 
--- @field keywords any 
--- @field zorder number 
--- @field editorFocus boolean 
--- @field editorSelection boolean 
--- @field childEditorSelection boolean 
--- @field childEditorFocus boolean 
--- @field locked any 
--- @field attachedRulesObjects any 
--- @field area any 
--- @field mapAlignmentDiagnostic any 
--- @field valid boolean 
--- @field components any 
--- @field path string 
LuaObjectInstance = {}

--- AddComponentFromJson
--- @param id any
--- @param json any
--- @return nil
function LuaObjectInstance:AddComponentFromJson(id, json)
	-- dummy implementation for documentation purposes only
end

--- ApplyMapCalibration
--- @param calibration any
--- @return nil
function LuaObjectInstance:ApplyMapCalibration(calibration)
	-- dummy implementation for documentation purposes only
end

--- GetComponent
--- @param description string
--- @return any
function LuaObjectInstance:GetComponent(description)
	-- dummy implementation for documentation purposes only
end

--- AddComponent
--- @param componentName string
--- @return any
function LuaObjectInstance:AddComponent(componentName)
	-- dummy implementation for documentation purposes only
end

--- BuildObjectComponentByName
--- @param componentName string
--- @return any
function LuaObjectInstance.BuildObjectComponentByName(componentName)
	-- dummy implementation for documentation purposes only
end

--- IsValidComponentJson
--- @param doc any
--- @return any
function LuaObjectInstance:IsValidComponentJson(doc)
	-- dummy implementation for documentation purposes only
end

--- ConstructComponent
--- @param doc any
--- @return any
function LuaObjectInstance:ConstructComponent(doc)
	-- dummy implementation for documentation purposes only
end

--- ComponentToJson
--- @param key string
--- @return any
function LuaObjectInstance:ComponentToJson(key)
	-- dummy implementation for documentation purposes only
end

--- RemoveComponent
--- @param key string
--- @return nil
function LuaObjectInstance:RemoveComponent(key)
	-- dummy implementation for documentation purposes only
end

--- MarkUndo
--- @return nil
function LuaObjectInstance:MarkUndo()
	-- dummy implementation for documentation purposes only
end

--- Upload
--- @param cmdgroupid string?
--- @return nil
function LuaObjectInstance:Upload(cmdgroupid)
	-- dummy implementation for documentation purposes only
end

--- SetAndUploadZOrder
--- @param zorder number
--- @return nil
function LuaObjectInstance:SetAndUploadZOrder(zorder)
	-- dummy implementation for documentation purposes only
end

--- SetAndUploadPos
--- @param x number
--- @param y number
--- @return nil
function LuaObjectInstance:SetAndUploadPos(x, y)
	-- dummy implementation for documentation purposes only
end

--- Destroy
--- @return nil
function LuaObjectInstance:Destroy()
	-- dummy implementation for documentation purposes only
end

--- DestroyWithBehavior
--- @param behavior any
--- @return nil
function LuaObjectInstance:DestroyWithBehavior(behavior)
	-- dummy implementation for documentation purposes only
end
