---@meta

--- @class BrushAssetLua
--- @field hidden boolean
--- @field tipAsset string
--- @field blend string
--- @field tipRotation string
--- @field textureAsset string
--- @field textureScale number
--- @field opacity number
--- @field radius number
--- @field fadeRadius number
--- @field description string
--- @field ord any
BrushAssetLua = {}

--- GetParameter
--- @param fieldName? string
--- @return any
function BrushAssetLua:GetParameter(fieldName) end

--- SetParameter
--- @param fieldName? string
--- @param info? any
function BrushAssetLua:SetParameter(fieldName, info) end

--- GetDisplayField
--- @param fieldName? string
--- @return boolean
function BrushAssetLua:GetDisplayField(fieldName) end

--- SetDisplayField
--- @param fieldName? string
--- @param value? boolean
function BrushAssetLua:SetDisplayField(fieldName, value) end

--- Upload
function BrushAssetLua:Upload() end
