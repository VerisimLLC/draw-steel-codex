---@meta

--- @class LuaPath
--- @field hasCollision boolean
--- @field freeMovementSteps number
--- @field collisionForce number
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
--- @field fallDistance number Number of tiles of altitude the token would fall when executing this path. Zero when there's no fall (or when shift-held descent has converted the move into a climb-down). Floor-aware: a fall that carries onto a lower floor (walking or being pushed off a ledge above a chasm) reports the full drop from where the fall starts down to the landing floor's ground.
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
--- @field properties any
--- @field valid boolean
--- @field teleport boolean
LuaPath = {}

--- DeepCopy
--- @return any
function LuaPath:DeepCopy() end

--- Serialize
--- @return any
function LuaPath:Serialize() end

--- Deserialize
--- @param dict? any
function LuaPath:Deserialize(dict) end

--- Equals
--- @overload fun(other?: any): boolean
--- @param other? any
--- @return boolean
function LuaPath:Equals(other) end

--- GetStepSurfaceType
--- @param nstep? number
--- @return number
function LuaPath:GetStepSurfaceType(nstep) end

--- GetStepFlags
--- @param nstep? number
--- @return any
function LuaPath:GetStepFlags(nstep) end

--- If step nstep enters its tile by climbing over a climbable wall, returns the wall's height in tiles above the floor's zero altitude (full-height walls resolve to the floor's height). Returns nil when the step doesn't climb a wall. Step indexes are 0-based, matching GetStepFlags.
--- @param nstep number
--- @return nil|number
function LuaPath:GetClimbOverWallHeight(nstep) end

--- Height in tiles above the floor's zero altitude of the tallest height-limited wall or solid block crossed moving from step nstep-1 to step nstep, or nil when none is crossed. Full-height walls never yield a height (they can't be crossed except by breaking). Lets a flying path illustrate walls the token passes over.
--- @param nstep number
--- @return nil|number
function LuaPath:GetStepWallHeight(nstep) end

--- CalculateHazards
--- @param tok CharacterToken
--- @return nil|{type: 'damage', damageAmount: number, damageType: string, aura: AuraInstance}[]
function LuaPath:CalculateHazards(tok) end

--- GetCreaturesCollidingWith
--- @param token? any
--- @return any
function LuaPath:GetCreaturesCollidingWith(token) end

--- GetObjectsCollidingWith
--- @param token? any
--- @return any
function LuaPath:GetObjectsCollidingWith(token) end
