---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class ObjectAsset:ImageAsset
--- @field textureReadable boolean
--- @field previewType string
--- @field components table<string, any>
--- @field children table<string, any>
ObjectAsset = {}

--- OnBeforeLoadImage
function ObjectAsset:OnBeforeLoadImage() end

--- GetPivot
--- @param tex? any
--- @return Vector2
function ObjectAsset:GetPivot(tex) end

--- GetComponentByName
--- @param name? string
--- @return any
function ObjectAsset:GetComponentByName(name) end
