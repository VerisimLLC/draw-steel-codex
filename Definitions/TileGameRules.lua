---@meta

--- @class TileGameRules
--- @field hole boolean
--- @field water boolean
--- @field difficultTerrain boolean
--- @field stairs boolean
--- @field concealment boolean
--- @field climbHeight number
--- @field climbersOnly boolean
--- @field surfaceType number
TileGameRules = {}

--- CloneInto
--- @param other? TileGameRules
--- @return TileGameRules
function TileGameRules:CloneInto(other) end

--- Clone
--- @return TileGameRules
function TileGameRules:Clone() end

--- AppendGameRulesFromAura
--- @param aura? Aura
--- @param scratchRules? TileGameRules
--- @param climbableGrantHeight? number
--- @return TileGameRules
function TileGameRules:AppendGameRulesFromAura(aura, scratchRules, climbableGrantHeight) end
