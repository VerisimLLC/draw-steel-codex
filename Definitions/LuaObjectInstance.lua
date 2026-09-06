---@meta

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
--- @param imageAssetId? string
--- @return boolean
function LuaObjectInstance:SetBaseImageFromAsset(imageAssetId) end

--- Centre the camera on this map object. Pass {smooth=true} to pan instead of jump.
--- @param args? any
function LuaObjectInstance:CenterCamera(args) end

--- Show a falloff radius ring centred on this map object (single shared marker; replaces any existing). Optional args {color="#rrggbb"}.
--- @param radius? number
--- @param args? any
function LuaObjectInstance:ShowRadiusMarker(radius, args) end

--- Clear the shared falloff radius ring shown by ShowRadiusMarker.
function LuaObjectInstance:ClearRadiusMarker() end

--- Play a brief, purely visual squash-and-stretch wobble on this map object -- click feedback for squishy things. Optional args {intensity=0.06, duration=0.4}. Local-only: never serialized or networked, so callers that want other clients to see it must broadcast it themselves.
--- @param args? any
function LuaObjectInstance:PlaySquishAnimation(args) end

--- AddComponentFromJson
--- @param id? any
--- @param json? any
function LuaObjectInstance:AddComponentFromJson(id, json) end

--- ApplyMapCalibration
--- @param calibration? any
function LuaObjectInstance:ApplyMapCalibration(calibration) end

--- GetComponent
--- @param description? string
--- @return any
function LuaObjectInstance:GetComponent(description) end

--- AddComponent
--- @param componentName? string
--- @return any
function LuaObjectInstance:AddComponent(componentName) end

--- BuildObjectComponentByName
--- @param componentName? string
--- @return any
function LuaObjectInstance.BuildObjectComponentByName(componentName) end

--- IsValidComponentJson
--- @param doc? any
--- @return any
function LuaObjectInstance:IsValidComponentJson(doc) end

--- ConstructComponent
--- @param doc? any
--- @return any
function LuaObjectInstance:ConstructComponent(doc) end

--- ComponentToJson
--- @param key? string
--- @return any
function LuaObjectInstance:ComponentToJson(key) end

--- RemoveComponent
--- @param key? string
function LuaObjectInstance:RemoveComponent(key) end

--- MarkUndo
function LuaObjectInstance:MarkUndo() end

--- Upload
--- @param cmdgroupid? string
function LuaObjectInstance:Upload(cmdgroupid) end

--- Starts a live-edit session for this object's image, opening it in the configured external image editor; the live-edit dialog then tracks the session. No-op if the object is not on a currently loaded floor.
function LuaObjectInstance:LiveEdit() end

--- Replaces this object's image with the image file at the given path, uploading it to the cloud and pointing the object at the new image. If provided, onError is called with a message string if the file cannot be read or the upload fails.
--- @param filePath? string
--- @param onError? any
function LuaObjectInstance:ReplaceImageFromFile(filePath, onError) end

--- SetAndUploadZOrder
--- @param zorder? number
function LuaObjectInstance:SetAndUploadZOrder(zorder) end

--- SetAndUploadPos
--- @param x? number
--- @param y? number
function LuaObjectInstance:SetAndUploadPos(x, y) end

--- Destroy
function LuaObjectInstance:Destroy() end

--- DestroyWithBehavior
--- @param behavior? any
function LuaObjectInstance:DestroyWithBehavior(behavior) end
