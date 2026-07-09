--- @class LuaPath 
--- @field hasCollision boolean 
--- @field freeMovementSteps number 
--- @field wallBreaks nil|table[] 
--- @field movementType string
--- @field jumpHeight number For a jump, the jump distance in tiles -- the mover clears height-limited walls up to this tall. Zero for every other movement type.
--- @field shifting boolean
--- @field forced boolean 
--- @field forcedDest nil|Loc 
--- @field bounceCollisions any Array of collision records from rebound movement. Each entry has speed (int), collideWith (table of tokens), and destination (Loc).
--- @field forcedMovementTotalDistance number 
--- @field collisionSpeed number 
--- @field hasClimbing boolean 
--- @field fallDistance number Number of tiles of altitude the token would fall when executing this path. Zero when there's no fall (or when shift-held descent has converted the move into a climb-down).
--- @field landsInWater boolean True if the tile this path ends on has the water rule -- a fall that lands in water is safer (larger safe-fall distance). False when there is no destination or no water.
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

--- GetClimbOverWallHeight: If step nstep enters its tile by climbing over a climbable wall, returns the wall's height in tiles above the floor's zero altitude (full-height walls resolve to the floor's height). Returns nil when the step doesn't climb a wall. Step indexes are 0-based, matching GetStepFlags.
--- @param nstep number
--- @return nil|number
function LuaPath:GetClimbOverWallHeight(nstep)
	-- dummy implementation for documentation purposes only
end

--- GetStepWallHeight: Height in tiles above the floor's zero altitude of the tallest height-limited wall or solid block crossed moving from step nstep-1 to step nstep, or nil when none is crossed. Full-height walls never yield a height (they can't be crossed except by breaking). Lets a flying path illustrate walls the token passes over.
--- @param nstep number
--- @return nil|number
function LuaPath:GetStepWallHeight(nstep)
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
