---@meta

--- @class CharacterAppearance
--- @field effectiveTokenScaling number
CharacterAppearance = {}

--- GetPortraitId
--- @return string
function CharacterAppearance:GetPortraitId() end

--- GetOffTokenPortraitId
--- @return string
function CharacterAppearance:GetOffTokenPortraitId() end

--- Equals
--- @param other? CharacterAppearance
--- @return boolean
function CharacterAppearance:Equals(other) end

--- SameAsBestiary
--- @param other? CharacterAppearance
--- @return boolean
function CharacterAppearance:SameAsBestiary(other) end
