---@meta

--- @class ModuleDependency
--- @field moduleid string
--- @field versionid string
--- @field versionnum string
--- @field ord number
--- @field autoUpdate boolean
--- @field parentModuleId string
--- @field disabled boolean
ModuleDependency = {}

--- CompareVersionNum
--- @param a? string
--- @param b? string
--- @return number
function ModuleDependency.CompareVersionNum(a, b) end

--- Clone
--- @return ModuleDependency
function ModuleDependency:Clone() end

--- Equals
--- @param other? ModuleDependency
--- @return boolean
function ModuleDependency:Equals(other) end
