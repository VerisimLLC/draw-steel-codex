-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_initiative_choice_test.lua
-- The cheap initiative choice: bids (minions, near death, everyone else) and
-- the reach check that decides whether a creature can strike this turn.
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
--The AI profiler's file locals are no-ops here.
local function noop() end
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = noop, noop, noop, noop, noop, noop
MonsterAI = {TokenIsLiveCombatant = function(t) return t.valid end}
dmhub = {unitsPerSquare = 1}
assert(load(section("function MonsterAI.TargetDistance", "-- Use the real token volume")))()
assert(load(section("--Initiative choice ----", "function MonsterAI:HandleMoveExecutionFailure")))()

local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

local function loc(x, y) return {x = x, y = y, str = x .. "," .. y} end
local function creature(x, options)
    options = options or {}
    local t = {valid = true, loc = loc(x, 0), altitude = 0, tileSize = 1}
    t.properties = {
        minion = options.minion or false,
        CharacterLevel = function() return options.level or 1 end,
        CurrentHitpoints = function() return options.stamina or 30 end,
        CurrentMovementSpeed = function() return options.speed or 5 end,
        DistanceMovedThisTurn = function() return 0 end,
    }
    function t:Distance(other) return math.abs(self.loc.x - other.loc.x) end
    return t
end

-- Bids: a minion and a creature at death's door bid 4, a healthy creature 1.
check(MonsterAI.TurnPriority(creature(0, {minion = true})) == 4, "minion bids high")
check(MonsterAI.TurnPriority(creature(0, {stamina = 30})) == 1, "healthy creature bids 1")
check(MonsterAI.TurnPriority(creature(0, {stamina = 5})) == 4, "creature near death bids as high as a minion")
local wounded = MonsterAI.TurnPriority(creature(0, {stamina = 10}))
check(wounded > 1 and wounded < 4, "wounded creature bids in between")
check(1*MonsterAI.initiativeCannotStrikeFactor*1.5*4 < 1, "any creature that can strike outranks any that cannot")

-- Reach: where it stands, after moving, by charging, and out of reach.
local function strike(range, charge)
    return {name = charge and "Melee Free Strike" or "Bow",
        HasKeyword = function(_, k) return k == "Strike" end,
        CanAfford = function() return true end,
        GetRange = function() return range end,
        try_get = function(_, _, default) return default end}
end
local pathsSearched = 0
local function ai(actor, enemies, abilities, reachable)
    local result = setmetatable({abilities = abilities, enemyTokens = enemies}, {__index = MonsterAI})
    function result:GetMovementToken(t) return t end
    function result:CalculateRemainingMovementPaths()
        pathsSearched = pathsSearched + 1
        local paths = {}
        for _,x in ipairs(reachable or {}) do paths[#paths+1] = {loc = loc(x, 0), cost = 10} end
        return paths
    end
    function result:TargetDistanceFromLoc(t, enemy, at)
        local old = t.loc; t.loc = at
        local d = MonsterAI.TargetDistance(t, enemy)
        t.loc = old
        return d
    end
    return result
end

local goblin = creature(0, {speed = 5})
pathsSearched = 0
check(ai(goblin, {creature(8)}, {strike(10)}):CanStrikeThisTurn(goblin), "ranged strike in reach where it stands")
check(pathsSearched == 0, "no pathfinding when already in reach")
check(not ai(goblin, {creature(30)}, {strike(1)}, {5}):CanStrikeThisTurn(goblin), "too far even after moving")
check(pathsSearched == 0, "no pathfinding when no route could be short enough")
check(ai(goblin, {creature(4)}, {strike(1)}, {3}):CanStrikeThisTurn(goblin), "in reach after moving")
check(not ai(goblin, {creature(4)}, {strike(1)}, {}):CanStrikeThisTurn(goblin), "walled in: no square in reach")
check(ai(goblin, {creature(6)}, {strike(1, true)}):CanStrikeThisTurn(goblin), "a charge from where it stands")
check(ai(goblin, {creature(10)}, {strike(1, true)}, {5}):CanStrikeThisTurn(goblin), "move, then charge")
check(not ai(goblin, {creature(8)}, {}):CanStrikeThisTurn(goblin), "no affordable strike")
local dead = creature(2); dead.valid = false
check(not ai(goblin, {dead}, {strike(10)}):CanStrikeThisTurn(goblin), "dead enemies do not count")

print(string.format("ai_initiative_choice_test: %d checks passed", checks))
