---@meta

--- @class Aura
--- @field token nil|CharacterToken The token that cast and controls this aura, if any.
--- @field auraInstance AuraInstance
Aura = {}

--- MovementDamageFor
--- @param forced? boolean
--- @return number
function Aura:MovementDamageFor(forced) end

--- EntersFromFront
--- @param from? Loc
--- @param to? Loc
--- @return boolean
function Aura:EntersFromFront(from, to) end

--- StepEntryCounts
--- @param from? Loc
--- @param to? Loc
--- @param carried? boolean
--- @return boolean
function Aura:StepEntryCounts(from, to, carried) end

--- MovementDamageApplies
--- @param movementType? any
--- @param forced? boolean
--- @return boolean
function Aura:MovementDamageApplies(movementType, forced) end

--- True if the given loc lies on this aura's adjacent extension (includeAdjacent) rather than on a true aura tile.
--- @param loc Loc
--- @return boolean
function Aura:LocOnlyAdjacent(loc) end

--- True if this aura's area was extended to adjacent tiles (includeAdjacent) and the given token touches the aura only via those adjacent tiles, not via any true aura tile.
--- @param token CharacterToken
--- @return boolean
function Aura:TokenOnlyAdjacent(token) end

--- ApplyTo
--- @param target? CharacterToken
--- @param ignoreHeight? boolean
--- @param altitudeOverride? number?
--- @return boolean
function Aura:ApplyTo(target, ignoreHeight, altitudeOverride) end

--- Destroy the Aura.
function Aura:Destroy() end
