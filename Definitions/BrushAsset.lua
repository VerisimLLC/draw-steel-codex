---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class BrushAsset:GameAsset
--- @field tipAsset ImageAsset
--- @field textureAsset ImageAsset
BrushAsset = {}

--- CalculateParameter
--- @param paramid? string
--- @return number
function BrushAsset:CalculateParameter(paramid) end

--- OnLoad
function BrushAsset:OnLoad() end
