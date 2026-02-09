--- @class LuaPath 
--- @field movementType string 
--- @field shifting boolean 
--- @field forced boolean 
--- @field forcedDest nil|Loc 
--- @field forcedMovementTotalDistance number 
--- @field collisionSpeed number 
--- @field hasClimbing boolean 
--- @field mount any 
--- @field waterSteps any 
--- @field difficultSteps any 
--- @field squeezeSteps any 
--- @field numDiagonals any 
--- @field cost number 
--- @field numSteps number 
--- @field destinationPosition any 
--- @field destination any 
--- @field origin any 
--- @field steps Loc[] 
LuaPath = {}

--- DeepCopy
--- @return any
function LuaPath:DeepCopy()
	-- dummy implementation for documentation purposes only
end

--- Serialize
--- @return any
function LuaPath:Serialize()
	-- dummy implementation for documentation purposes only
end

--- Deserialize
--- @param dict any
--- @return nil
function LuaPath:Deserialize(dict)
	-- dummy implementation for documentation purposes only
end

--- Equals
--- @param other any
--- @return boolean
function LuaPath:Equals(other)
	-- dummy implementation for documentation purposes only
end

--- Equals
--- @param other any
--- @return boolean
function LuaPath:Equals(other)
	-- dummy implementation for documentation purposes only
end

--- GetStepSurfaceType
--- @param nstep number
--- @return number
function LuaPath:GetStepSurfaceType(nstep)
	-- dummy implementation for documentation purposes only
end

--- GetStepFlags
--- @param nstep number
--- @return any
function LuaPath:GetStepFlags(nstep)
	-- dummy implementation for documentation purposes only
end

--- CalculateHazards
--- @param tok CharacterToken
--- @return nil|{type: 'damage', damageAmount: number, damageType: string, aura: AuraInstance}[]
function LuaPath:CalculateHazards(tok)
	-- dummy implementation for documentation purposes only
end

--- GetCreaturesCollidingWith
--- @param token any
--- @return any
function LuaPath:GetCreaturesCollidingWith(token)
	-- dummy implementation for documentation purposes only
end

--- GetObjectsCollidingWith
--- @param token any
--- @return any
function LuaPath:GetObjectsCollidingWith(token)
	-- dummy implementation for documentation purposes only
end
