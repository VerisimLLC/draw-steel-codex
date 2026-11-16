-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_hidden_reposition_test.lua
-- A Hidden monster with movement left slips to a random square where it stays
-- hidden, along a route hidden on every square, and never advances.
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
local function noop() end
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = noop, noop, noop, noop, noop, noop
local function try_get(t, k, default)
    if t[k] == nil then return default end
    return t[k]
end
MonsterAI = {TokenIsLiveCombatant = function(t) return t.valid end,
    TokenLogName = tostring, LocLogName = tostring, TargetsLogName = tostring, Sleep = noop}
local decisions = {}
function MonsterAI:LogDecision(event, fields) decisions[#decisions+1] = {event = event, fields = fields} end
function RunYieldingFunction(fn)
    local ok, err = pcall(fn)
    if not ok then return false, err end
    return true
end
dmhub = {unitsPerSquare = 1}
assert(load(section("function MonsterAI.TargetDistance", "-- Use the real token volume")))()
assert(load(section("--Hidden reposition", "--- True when the creature must stay on its Hold post")))()

local function loc(x, y)
    local result = {x = x, y = y, str = x .. "," .. y}
    result.xyfloorOnly = result
    return result
end
local function key(x, y) return x .. "," .. y end

--Map: the monster hid at (0,0). Concealed column x=0 going up; (3,0) is
--concealed but only reachable across the open square (1,0); (0,-2) has cover
--from every enemy. The enemy stands at (6,0).
local concealed = {[key(0,0)] = true, [key(0,1)] = true, [key(0,2)] = true, [key(0,3)] = true,
    [key(3,0)] = true, [key(5,1)] = true}
local covered = {[key(0,-1)] = true, [key(0,-2)] = true}
local enemy = {valid = true, altitude = 0, tileSize = 1, loc = loc(6, 0)}
local mover = {valid = true, altitude = 0, tileSize = 1, loc = loc(0, 0), charid = "assassin"}
function mover:Distance(other)
    return math.max(math.abs(self.loc.x - other.loc.x), math.abs(self.loc.y - other.loc.y))
end
local cachedCover = {time = 0, all = false}
mover.properties = {_tmp_coverFromEnemies = cachedCover, try_get = try_get}
function mover.properties:IsConcealed() return concealed[mover.loc.str] == true end
function mover.properties:CalculateCoverFromEnemies(fresh)
    assert(fresh, "cover is measured fresh at each square")
    local result = {all = covered[mover.loc.str] == true}
    self._tmp_coverFromEnemies = result
    return result
end
local hidden = true
function mover.properties:HasNamedCondition(name) return name == "Hidden" and hidden end
--Routes walk along x first, then y (the engine's route, every square).
local arrowCalls = 0
function mover:MarkMovementArrow(goal)
    arrowCalls = arrowCalls + 1
    local steps = {self.loc}
    local x, y = self.loc.x, self.loc.y
    while x ~= goal.x do x = x + (goal.x > x and 1 or -1); steps[#steps+1] = loc(x, y) end
    while y ~= goal.y do y = y + (goal.y > y and 1 or -1); steps[#steps+1] = loc(x, y) end
    return {path = {destination = goal, cost = (#steps - 1)*10, steps = steps}}
end
function mover:ClearMovementArrow() self.cleared = true end

local ai = setmetatable({enemyTokens = {enemy}, try_get = try_get}, {__index = MonsterAI})
function ai:GetMovementToken() return mover end
function ai:ExecuteWithTheoreticalMovementLoc(_, goal, fn)
    local old = mover.loc; mover.loc = goal
    fn(); mover.loc = old
end
local function Paths(locs)
    local result = {{loc = mover.loc, cost = 0}}
    for _,l in ipairs(locs) do
        result[#result+1] = {loc = l, cost = (math.abs(l.x - mover.loc.x) + math.abs(l.y - mover.loc.y))*10,
            provokes = l.provokes}
    end
    return result
end
ai.remaining = Paths{loc(0,1), loc(0,2), loc(0,3), loc(1,0), loc(2,0), loc(3,0), loc(0,-1), loc(0,-2),
    loc(5,1)}
function ai:CalculateRemainingMovementPaths() return self.remaining end
function ai:MoveToken(_, destination) mover.loc = destination; self.moves = (self.moves or 0) + 1 end

-- StaysHiddenAt: concealment or cover from all enemies, never next to an enemy.
assert(ai:StaysHiddenAt(mover, loc(0, 3)), "concealed square keeps it hidden")
assert(ai:StaysHiddenAt(mover, loc(0, -2)), "cover from every enemy keeps it hidden")
assert(not ai:StaysHiddenAt(mover, loc(1, 0)), "open square reveals it")
assert(not ai:StaysHiddenAt(mover, loc(5, 1)), "concealed but beside an enemy reveals it")
assert(mover.properties._tmp_coverFromEnemies == cachedCover,
    "the cached cover answer for where it really stands is kept")
assert(mover.loc.str == "0,0", "testing squares does not move it")
print("Hidden square tests passed")

-- FindHiddenReposition: random among squares whose whole route stays hidden.
local valid = {[key(0,1)] = true, [key(0,2)] = true, [key(0,3)] = true,
    [key(0,-1)] = true, [key(0,-2)] = true}
local seen = {}
math.randomseed(7)
for _=1,200 do
    local plan = ai:FindHiddenReposition(mover)
    assert(plan ~= nil, "a hidden square is reachable")
    assert(valid[plan.loc.str], "never " .. plan.loc.str .. ": its route or square is not hidden")
    seen[plan.loc.str] = true
end
local count = 0
for _ in pairs(seen) do count = count + 1 end
assert(count == 5, "the choice is random across every valid square, saw " .. count)
assert(mover.cleared, "the route preview arrow is cleared")
print("Hidden route and random choice tests passed")

-- Squares that provoke opportunity attacks are not used.
ai.remaining = Paths{loc(1,0), loc(3,0)}
local provoking = loc(0, 1); provoking.provokes = 1
ai.remaining[#ai.remaining+1] = {loc = provoking, cost = 10, provokes = 1}
assert(ai:FindHiddenReposition(mover) == nil,
    "(3,0) is only reached across the open (1,0); (0,1) provokes: nowhere to go")
decisions = {}
assert(ai:ExecuteHiddenReposition(mover) == false and (ai.moves or 0) == 0, "stays put")
assert(decisions[1].event == "HIDDEN REPOSITION" and decisions[1].fields.result == "stays put and hidden")
print("Stay put tests passed")

-- The selector: Hidden replaces the advance with one hidden reposition per turn.
assert(load('local g_moveResultExecuted="executed"; local g_moveResultNone="none"; '
    .. 'local g_moveResultUnsafe="unsafe"; local g_moveResultFailed="failed";\n'
    .. section("function MonsterAI:FindAndExecuteMove()", "function MonsterAI:DistanceFromNearestEnemy")))()
assert(load(section("function MonsterAI:MovesInScoringOrder()", "function MonsterAI.MoveMatchesMonster")))()
WeightedScoringInfo, ScoreWeightLogSuffix = assert(load(
    section("local function WeightedScoringInfo", "local function FindMaliceAbilityByName")
    .. "\nreturn WeightedScoringInfo, ScoreWeightLogSuffix"))()
MonsterAI.SetMoveLogContext = noop
MonsterAI.SetLogContext = noop
MonsterAI.LogMove = noop
MonsterAI.AbilitiesLogName = tostring
MonsterAI.MoveMatchesMonster = function() return true end
MonsterAI.Holds = function() return false end
MonsterAI.OpportunityAttackers = function() return nil end
MonsterAI.InDirectiveZone = function() return false end
MonsterAI.TurnTakenBeforeMove = function() return false end
mover.properties.minion = false
mover.properties.monster_type = "Goblin Assassin"
mover.properties.has_key = function() return true end
ai.token = mover
ai.abilities = {}
ai.moves = {}
function ai:GetClaimedAbilityNames() return {} end
function ai:ShouldDashInsteadOfShooting() return false end
function ai:FindBestSynthesizedAbilityMove() return nil end
function ai:ExecuteAdvanceFallback() self.advanced = true; return true end
ai.remaining = Paths{loc(0,1), loc(0,2), loc(1,0)}
local moved = 0
function ai:MoveToken(_, destination) mover.loc = destination; moved = moved + 1 end

assert(ai:FindAndExecuteMove() == "executed" and moved == 1 and not ai.advanced,
    "hidden: repositions instead of advancing")
assert(valid[mover.loc.str], "it ends on a hidden square")
assert(ai:FindAndExecuteMove() == "none" and moved == 1 and not ai.advanced,
    "only once per turn, and still never advances")
hidden = false
assert(ai:FindAndExecuteMove() == "executed" and ai.advanced, "not hidden: advances as before")
print("Hidden selector tests passed")
