---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class TilesheetAsset:ImageAsset
TilesheetAsset = {}

--- OnBeforeLoadImage
function TilesheetAsset:OnBeforeLoadImage() end

--- GetTilePPU
--- @return number
function TilesheetAsset:GetTilePPU() end

--- GetTileScale
--- @return number
function TilesheetAsset:GetTileScale() end

--- Clone
--- @return TilesheetAsset
function TilesheetAsset:Clone() end
