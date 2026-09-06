---@meta

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
--- @param id? string
--- @param val? any
function LuaObjectComponent:SetProperty(id, val) end

--- Execute
--- @param commandDescription? any
function LuaObjectComponent:Execute(commandDescription) end

--- ThinkEdit
function LuaObjectComponent:ThinkEdit() end

--- UpdateBlueprint
--- @param newAsset? boolean
function LuaObjectComponent:UpdateBlueprint(newAsset) end

--- GetFieldDisplayInfo
--- @param obj? any
--- @param fieldName? string
--- @return any
function LuaObjectComponent:GetFieldDisplayInfo(obj, fieldName) end

--- Randomize
--- @param options? any
function LuaObjectComponent:Randomize(options) end

--- BeginChanges
function LuaObjectComponent:BeginChanges() end

--- CompleteChanges
--- @param description? string
function LuaObjectComponent:CompleteChanges(description) end

--- DestroyObject
function LuaObjectComponent:DestroyObject() end

--- RecordUndo
function LuaObjectComponent:RecordUndo() end

--- Upload
--- @param cmdgroupid? string
function LuaObjectComponent:Upload(cmdgroupid) end

--- SetAndUploadProperties
--- @param dict? any
function LuaObjectComponent:SetAndUploadProperties(dict) end

--- CreateCustomEditor
--- @return any
function LuaObjectComponent:CreateCustomEditor() end

--- CreateMultiCustomEditor
--- @param components? any
--- @return any
function LuaObjectComponent:CreateMultiCustomEditor(components) end
