---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class TileImageAsset:ImageAsset
--- @field pivot Loc
TileImageAsset = {}

--- GetPivot
--- @param tex? any
--- @return Vector2
function TileImageAsset:GetPivot(tex) end

--- GetPPU
--- @param tex? any
--- @return number
function TileImageAsset:GetPPU(tex) end
