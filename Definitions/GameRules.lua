---@meta

--- @class GameRules
--- @field CreatureSizes any
GameRules = {}

--- GetSizeInfo
--- @param index? number
--- @return any
function GameRules.GetSizeInfo(index) end

--- NormalizeSizeIndex
--- @param index? number
--- @return number
function GameRules.NormalizeSizeIndex(index) end

--- StringToCreatureSizeIndex
--- @param name? string
--- @return number
function GameRules.StringToCreatureSizeIndex(name) end

--- CreatureSizeIndexToString
--- @param index? number
--- @return string
function GameRules.CreatureSizeIndexToString(index) end
