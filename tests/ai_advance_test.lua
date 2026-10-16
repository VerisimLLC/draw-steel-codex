-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_advance_test.lua
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
local function noop() end
--The AI profiler's file locals are no-ops here.
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = noop, noop, noop, noop, noop, noop
local function try_get(t, k, default)
    if t[k] == nil then return default end
    return t[k]
end
MonsterAI = {TokenIsLiveCombatant = function(t) return t.valid end,
    LogDecision = noop, TokenLogName = tostring, LocLogName = tostring,
    TargetsLogName = tostring, Sleep = noop}
function RunYieldingFunction(fn)
    local ok, err = pcall(fn)
    if not ok then return false, err end
    return true
end
function FindAbilityByName(abilities, name)
    for _,a in ipairs(abilities) do if a.name == name then return a end end
end
dmhub = {unitsPerSquare = 1, GenerateGuid = function() return "activity" end}
--The per-token AI activity registry (Creature.lua).
local tokenActivity = {}
creature = {GetTokenAIActivity = function(charid) return tokenActivity[charid] end,
    SetTokenAIActivity = function(charid, activityId)
        local previous = tokenActivity[charid]
        tokenActivity[charid] = activityId
        return previous
    end}
assert(load(section("function MonsterAI.TargetDistance", "-- Use the real token volume")))()
assert(load(section("function MonsterAI:FindAdvancePlan", "function MonsterAI:FindAndExecuteMove")))()
local function loc(x, y)
    local result = {x = x, y = y, str = x .. "," .. y}
    result.xyfloorOnly = result
    function result:dir(dx, dy) return loc(x + dx, y + dy) end
    return result
end
local start, nearStep, farStep = loc(0, 0), loc(1, 0), loc(2, 0)
local nearEnemy = {valid = true, altitude = 0, tileSize = 1, loc = loc(3, 0)}
local farEnemy = {valid = true, altitude = 0, tileSize = 1, loc = loc(8, 0)}
local mover = {valid = true, altitude = 0, tileSize = 1, loc = start, charid = "actor"}
function mover:Distance(enemy)
    return math.max(math.abs(self.loc.x - enemy.loc.x), math.abs(self.loc.y - enemy.loc.y))
end
function mover:GetLineOfSight() return 1 end
function mover:ClearMovementArrow() self.cleared = true end
function mover:MarkMovementArrow(goal)
    local cost = goal.x < 5 and 200 or 90
    if self.unreachable and goal.x < 5 then return nil end
    return {path = {destination = goal, cost = cost, steps = {start, nearStep, farStep, goal}}}
end
local ai = setmetatable({enemyTokens = {nearEnemy, farEnemy}}, {__index = MonsterAI})
function ai:GetMovementToken() return mover end
function ai:MovementLocOverlapsCreature() return false end
function ai:ExecuteWithTheoreticalMovementLoc(_, goal, fn)
    local old = mover.loc; mover.loc = goal
    fn(); mover.loc = old
end
local paths = {{loc = start, cost = 0}, {loc = nearStep, cost = 10}, {loc = farStep, cost = 20}}
local plan = ai:FindAdvancePlan(mover, paths)
assert(plan ~= nil, "an advance plan is found")
assert(plan.enemy == farEnemy, "prefer cheaper traversable route over geometric distance")
assert(plan.loc == farStep, "use furthest affordable route step")
assert(mover.loc == start and mover.cleared, "planning restores position and clears preview")
mover.unreachable = true
assert(ai:FindAdvancePlan(mover, paths).enemy == farEnemy, "skip unreachable enemy")
assert(ai:FindAdvancePlan(mover, {{loc = start, cost = 0}}) == nil, "no movement means no plan")
ai.enemyTokens = {nearEnemy}; assert(ai:FindAdvancePlan(mover, paths) == nil, "no reachable enemy")

local advance = {name = "Use Move Action", CanAfford = function() return mover.actions > 0 end}
mover.actions = 1
mover.properties = {try_get = try_get, GetActivatedAbilities = function() return {advance} end,
    CurrentMovementSpeed = function() return 5 end}
function ai:CalculateRemainingMovementPaths() return self.remaining end
function ai:CalculateMovementPaths(_, budget) assert(budget == 50); return "full" end
function ai:FindAdvancePlan(_, available)
    if available == "none" or self.blocked then return nil end
    return {loc = farStep, enemy = farEnemy}
end
function ai:MoveToken(_, destination) mover.loc = destination; self.moves = (self.moves or 0) + 1 end
function ai:SetTargetsForExpectedPrompt(prompt) self._tmp_expectedPromptTarget = prompt end
function ai:ExecuteAbility(_, ability, targets, options)
    assert(ability == advance and options.symbols.mode == 1)
    assert(creature.GetTokenAIActivity(mover.charid) == "activity")
    if self.castError then error("cast failed") end
    mover.actions = mover.actions - 1
    mover.loc = self._tmp_expectedPromptTarget.targets[1].loc
end
function ai:WaitForMovementActivity(_, id) assert(id == "activity"); self.waited = true; return true end
ai.remaining = "remaining"
assert(ai:ExecuteAdvanceFallback(mover) and mover.actions == 1, "ordinary movement preserves main action")
mover.loc = start; ai.remaining = "none"
assert(ai:ExecuteAdvanceFallback(mover) and mover.actions == 0 and ai.waited, "convert and await reactions")
assert(creature.GetTokenAIActivity(mover.charid) == nil and ai._tmp_expectedPromptTarget == nil)
assert(not ai:ExecuteAdvanceFallback(mover), "cannot convert a spent main action")
mover.actions = 1; mover.loc = start; ai.blocked = true
assert(not ai:ExecuteAdvanceFallback(mover) and mover.actions == 1, "do not spend action without a route")
ai.blocked = false; ai.castError = true
assert(not pcall(ai.ExecuteAdvanceFallback, ai, mover), "surface cast failure")
assert(creature.GetTokenAIActivity(mover.charid) == nil and ai._tmp_expectedPromptTarget == nil,
    "clear temporary state after failed cast")
print("AI advance route and action-economy tests passed")

-- Exercise the real selector: an attack (including its charge plan) wins before
-- advancing, and a successful advance must keep the turn loop running.
local prefix = 'local g_moveResultExecuted="executed"; local g_moveResultNone="none";\n'
assert(load(prefix .. section("function MonsterAI:FindAndExecuteMove()", "function MonsterAI:DistanceFromNearestEnemy")))()
assert(load(section("function MonsterAI:MovesInScoringOrder()", "function MonsterAI.MoveMatchesMonster")))()
MonsterAI.SetMoveLogContext = noop
MonsterAI.SetLogContext = noop
MonsterAI.LogMove = noop
MonsterAI.AbilitiesLogName = tostring
MonsterAI.AbilityActionsLogName = tostring
MonsterAI.ScoringPlanLogName = tostring
MonsterAI.MoveMatchesMonster = function() return true end
local actor = {valid = true, properties = {minion = false, monster_type = "Test",
    has_key = function() return true end}}
local selector = setmetatable({token = actor, abilities = {}, moves = {}, try_get = try_get}, {__index = MonsterAI})
function selector:GetClaimedAbilityNames() return {} end
function selector:FindBestSynthesizedAbilityMove() return nil end
function selector:ExecuteAdvanceFallback() self.advanced = true; return true end
assert(selector:FindAndExecuteMove() == "executed" and selector.advanced,
    "successful fallback continues action cycles even though yielding boundary has no return value")
selector.advanced = false
selector.moves.strike = {id = "strike", score = function() return {score = 0.2} end,
    execute = function() selector.attacked = true end}
assert(selector:FindAndExecuteMove() == "executed" and selector.attacked and not selector.advanced,
    "legal strike or charge precedes advancement and action conversion")
-- A move with a maxScore is not scored once the best found already reaches
-- it, and still competes when nothing better exists.
selector.attacked = false
local fallbackScored = false
selector.moves.fallback = {id = "fallback", maxScore = 0.2,
    score = function() fallbackScored = true; return {score = 0.2} end,
    execute = function() selector.usedFallback = true end}
selector.moves.strike.score = function() return {score = 1} end
assert(selector:FindAndExecuteMove() == "executed" and selector.attacked and not fallbackScored,
    "capped move skipped once a better move is found")
selector.attacked = false
selector.moves.strike.score = function() return {score = 0.1} end
assert(selector:FindAndExecuteMove() == "executed" and fallbackScored and selector.usedFallback,
    "capped move still wins when it scores higher")
fallbackScored = false; selector.usedFallback = false
selector.moves.strike.score = function() return {score = 0.2} end
assert(selector:FindAndExecuteMove() == "executed" and selector.attacked and not fallbackScored,
    "a tie cannot replace the best, so the capped move is skipped")
selector.moves.fallback = nil
selector.moves.strike.score = function() return {score = 0.2} end
print("AI advance selection priority tests passed")

-- Band callbacks historically discard ExecuteAbility's false return. The
-- execution marker must still quarantine them and allow a lower-scoring move.
assert(load('local g_moveResultFailed="failed"; local g_moveResultUnsafe="unsafe"; ' ..
    section("function MonsterAI:HandleMoveExecutionFailure", "-- Compare complete routes")))()
function selector:WaitForAbilityIdle() return true end
selector.moves.strike.execute = function() selector._tmp_moveFailure = "charge blocked" end
assert(selector:FindAndExecuteMove() == "failed", "ignored cast failure must fail the move")
assert(selector._tmp_failedMoves.strike, "failed registration quarantined")
selector.advanced = false
assert(selector:FindAndExecuteMove() == "executed" and selector.advanced,
    "next cycle falls back instead of repeating failed charge")
selector._tmp_failedMoves = {}
selector.moves.strike.execute = function() return false end
assert(selector:FindAndExecuteMove() == "failed", "explicit false also fails the move")
print("AI failed move fallback tests passed")
