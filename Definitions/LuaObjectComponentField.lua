---@meta

--- @class LuaObjectComponentField
--- @field currentValue any
--- @field count number
--- @field fieldType string
--- @field id string
--- @field prettyName string
--- @field arguments any
--- @field canUpload boolean
LuaObjectComponentField = {}

--- GetEditingInfo
--- @return any
function LuaObjectComponentField:GetEditingInfo() end

--- GetValue
--- @param index? number
--- @return any
function LuaObjectComponentField:GetValue(index) end

--- SetValue
--- @param val? any
--- @param index? number
function LuaObjectComponentField:SetValue(val, index) end

--- Append
function LuaObjectComponentField:Append() end

--- Remove
--- @param index? number
function LuaObjectComponentField:Remove(index) end

--- MarkUndoPoint
function LuaObjectComponentField:MarkUndoPoint() end

--- Upload
--- @param cmdgroupid? string
function LuaObjectComponentField:Upload(cmdgroupid) end
