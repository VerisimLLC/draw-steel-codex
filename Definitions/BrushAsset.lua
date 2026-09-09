---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class BrushAsset:GameAsset
--- @field tipAsset ImageAsset
--- @field textureAsset ImageAsset
--- @field parameters table<string, any>
--- @field tip string
--- @field blend any
--- @field tipRotation any
--- @field tex string
--- @field texScale number
--- @field opacity number
--- @field radius number
--- @field fadeRadius number
--- @field displayFields string[]
BrushAsset = {}

--- CalculateParameter
--- @param paramid? string
--- @return number
function BrushAsset:CalculateParameter(paramid) end

--- OnLoad
function BrushAsset:OnLoad() end
