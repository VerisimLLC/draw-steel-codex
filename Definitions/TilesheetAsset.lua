---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class TilesheetAsset:ImageAsset
--- @field layer any
--- @field effectLayer any
--- @field oneLargeTile boolean
--- @field randomOrientation boolean
--- @field useAlphaThreshold boolean
--- @field xtiles number
--- @field ytiles number
--- @field scale number
--- @field movement boolean
--- @field movex number
--- @field movey number
--- @field distortion boolean
--- @field distortx number
--- @field distorty number
--- @field distortTime number
--- @field distortWave number
--- @field rules TileGameRules
--- @field invisible boolean
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
