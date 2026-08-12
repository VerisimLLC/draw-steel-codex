--- @class Aura 
--- @field token nil|CharacterToken The token that cast and controls this aura, if any.
Aura = {}

--- MovementDamageApplies
--- @param movementType any
--- @return boolean
function Aura:MovementDamageApplies(movementType)
	-- dummy implementation for documentation purposes only
end

--- ApplyTo
--- @param target any
--- @param ignoreHeight boolean?
--- @return boolean
function Aura:ApplyTo(target, ignoreHeight)
	-- dummy implementation for documentation purposes only
end

--- Destroy: Destroy the Aura.
--- @return nil
function Aura:Destroy()
	-- dummy implementation for documentation purposes only
end

--- TokenOnlyAdjacent: True if this aura's area was extended to adjacent tiles
--- (includeAdjacent) and the given token touches the aura only via those
--- adjacent tiles, not via any true aura tile.
--- @param token CharacterToken
--- @return boolean
function Aura:TokenOnlyAdjacent(token)
	-- dummy implementation for documentation purposes only
end

--- LocOnlyAdjacent: True if the given loc lies on this aura's adjacent
--- extension (includeAdjacent) rather than on a true aura tile.
--- @param loc Loc
--- @return boolean
function Aura:LocOnlyAdjacent(loc)
	-- dummy implementation for documentation purposes only
end
