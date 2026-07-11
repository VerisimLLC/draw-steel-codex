--- @class LuaObjectInstance 
--- @field id string 
--- @field imageid string 
--- @field displayImageId string The object's current base image id in a form usable as a bgimage. Unlike imageid (which returns the source blueprint/asset id for blueprinted objects), this always reflects the object's actual current image, so a preview using it updates after a live-edit upload or a Replace Image.
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

--- SetBaseImageFromAsset
--- @param imageAssetId string
--- @return boolean
function LuaObjectInstance:SetBaseImageFromAsset(imageAssetId)
	-- dummy implementation for documentation purposes only
end

--- CenterCamera: Centre the camera on this map object. Pass {smooth=true} to pan instead of jump.
--- @param args any
--- @return nil
function LuaObjectInstance:CenterCamera(args)
	-- dummy implementation for documentation purposes only
end

--- ShowRadiusMarker: Show a falloff radius ring centred on this map object (single shared marker; replaces any existing). Optional args {color="#rrggbb"}.
--- @param radius number
--- @param args any
--- @return nil
function LuaObjectInstance:ShowRadiusMarker(radius, args)
	-- dummy implementation for documentation purposes only
end

--- ClearRadiusMarker: Clear the shared falloff radius ring shown by ShowRadiusMarker.
--- @return nil
function LuaObjectInstance:ClearRadiusMarker()
	-- dummy implementation for documentation purposes only
end

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

--- LiveEdit: Starts a live-edit session for this object's image, opening it in the configured external image editor; the live-edit dialog then tracks the session. No-op if the object is not on a currently loaded floor.
--- @return nil
function LuaObjectInstance:LiveEdit()
	-- dummy implementation for documentation purposes only
end

--- ReplaceImageFromFile: Replaces this object's image with the image file at the given path, uploading it to the cloud and pointing the object at the new image. If provided, onError is called with a message string if the file cannot be read or the upload fails.
--- @param filePath string
--- @param onError any?
--- @return nil
function LuaObjectInstance:ReplaceImageFromFile(filePath, onError)
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
