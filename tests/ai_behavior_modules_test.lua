-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_behavior_modules_test.lua
-- Behavior modules (MonsterAI:RegisterBehavior, HasBehavior, behavior sources)
-- and the Avoid Opportunity Attacks move choice (ChooseAvoidingOpportunityAttacks).
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
local passed = 0
local function check(condition, message)
    assert(condition, message)
    passed = passed + 1
end
local function noop() end
local function try_get(t, k, default)
    if t[k] == nil then return default end
    return t[k]
end
--a file local in MonsterAI.lua that the registration section calls.
function RegistrationCallSite() return "test" end

MonsterAI = {tactics = {}, behaviors = {}, behaviorSources = {}, try_get = try_get,
    LogDecision = noop, SetLogContext = noop, TargetsLogName = tostring, LocLogName = tostring}
assert(load(section("--Behavior modules ---", "--- /testai support")))()
assert(load(section("--- Choose a move for a creature avoiding opportunity attacks.", "function MonsterAI:CalculateMovementPaths")))()
MonsterAI.opportunityAttackPenalty = 0.8

--- behavior modules -------------------------------------------------------
local function Token(monsterType)
    return {valid = true, properties = {try_get = function(_, k, default)
        if k == "monster_type" then return monsterType end
        return default
    end}}
end
MonsterAI:RegisterBehavior{id = "Bully", description = "test", aliases = {"Bullies"}, monsters = {"Gnoll"},
    targetEdges = function() return 1 end}
MonsterAI:RegisterBehavior{id = "Avoid Opportunity Attacks", description = "test", monsters = {}}
local gnoll, goblin = Token("Gnoll"), Token("Goblin")

check(MonsterAI.tactics["Bully"] ~= nil and MonsterAI.tactics["Avoid Opportunity Attacks"] == nil,
    "only a behavior with target edges runs as a tactic")
check(MonsterAI.FindBehavior("bullies") == MonsterAI.behaviors["Bully"], "alias, any case")
check(MonsterAI.FindBehavior("avoid opportunity-attacks.") == MonsterAI.behaviors["Avoid Opportunity Attacks"], "punctuation ignored")
check(MonsterAI.FindBehavior("Sulk") == nil, "unknown behavior")
check(MonsterAI.HasBehavior(gnoll, "Bully") and not MonsterAI.HasBehavior(goblin, "Bully"), "on for the listed monster type only")
check(not MonsterAI.HasBehavior(gnoll, "Avoid Opportunity Attacks"), "off with no monster types")

--an encounter's switches: the source answers; nil leaves the default.
local switches = {}
MonsterAI.RegisterBehaviorSource("test", function(token, id) return switches[id] end)
switches["Avoid Opportunity Attacks"] = true
switches["Bully"] = false
check(MonsterAI.HasBehavior(goblin, "Avoid Opportunity Attacks"), "a source switches a behavior on")
check(not MonsterAI.HasBehavior(gnoll, "Bully"), "a source switches a listed behavior off")
MonsterAI.RegisterBehaviorSource("test", function() return nil end)
check(#MonsterAI.behaviorSources == 1 and MonsterAI.HasBehavior(gnoll, "Bully"), "re-registering replaces the source")
MonsterAI.RegisterBehaviorSource("broken", function() error("boom") end)
check(MonsterAI.HasBehavior(gnoll, "Bully"), "a failing source is ignored")

MonsterAI.behaviors["Bully"].disabledForMonsters = {Gnoll = true}
check(not MonsterAI.HasBehavior(gnoll, "Bully") and MonsterAI.HasBehavior(gnoll, "Bully", true),
    "the panel's per-type switch, unless includeDisabled")
MonsterAI.behaviors["Bully"].disabledForMonsters = nil

--allMonsters: on for every type, and only an explicit switch turns it off.
MonsterAI:RegisterBehavior{id = "Everyone", description = "test", allMonsters = true}
check(MonsterAI.HasBehavior(gnoll, "Everyone") and MonsterAI.HasBehavior(goblin, "Everyone"), "allMonsters is on for every type")
switches["Everyone"] = false
MonsterAI.RegisterBehaviorSource("test", function(token, id) return switches[id] end)
check(not MonsterAI.HasBehavior(gnoll, "Everyone"), "a source switches an allMonsters behavior off")
MonsterAI.RegisterBehaviorSource("test", function() return nil end)
MonsterAI.behaviors["Everyone"].disabledForMonsters = {Goblin = true}
check(MonsterAI.HasBehavior(gnoll, "Everyone") and not MonsterAI.HasBehavior(goblin, "Everyone"), "the panel switch turns one type off")

--- Avoid Opportunity Attacks: the two-pass choice ---------------------------
local here = {str = "here"}
local away = {str = "away"}
local function NewAI()
    local ai = setmetatable({_tmp_aiLogContext = {}}, {__index = MonsterAI})
    ai.paths = {a = {loc = here, cost = 0, provokes = 0}, b = {loc = away, cost = 20, provokes = 1}}
    function ai:OpportunityAttacksProvokedAt(_, loc) return loc == away and 1 or 0 end
    return ai
end
--scoring: `safe` scores a plan that stays put, `risky` one that walks away
--(only when self.paths still offers the square).
local function Scorer(ai, safe, risky)
    local passes = {}
    return function()
        local canLeave = false
        for _,info in pairs(ai.paths) do
            if info.loc == away then canLeave = true end
        end
        passes[#passes+1] = {canLeave = canLeave, safeOnly = ai._tmp_oaSafeOnly}
        local best = {score = 0}
        local bestMove = nil
        if safe > 0 then best, bestMove = {score = safe, loc = here}, {id = "stay"} end
        if canLeave and risky > best.score then best, bestMove = {score = risky, loc = away}, {id = "leave"} end
        return best, bestMove, nil
    end, passes
end
--a stand-in token and attacker list; the stubs above never read them.
---@type any
local token = {charid = "monster"}
---@type any
local attackers = {{}}

local ai = NewAI()
local score, passes
score, passes = Scorer(ai, 0.2, 1.0)
local bestScore, bestMove = ai:ChooseAvoidingOpportunityAttacks(token, attackers, score)
check(#passes == 2 and not passes[1].canLeave and passes[1].safeOnly == "monster" and passes[2].canLeave,
    "pass one sees only safe squares, pass two every square")
check(bestMove ~= nil and bestMove.id == "stay" and bestScore.score == 0.2, "a free strike beats a 1.0 plan that provokes")
check(ai._tmp_oaSafeOnly == "monster" and ai.paths.b == nil and ai.paths.a ~= nil,
    "the safe squares stay in force for the move's execution")

ai = NewAI()
score = Scorer(ai, 0, 1.0)
bestScore, bestMove = ai:ChooseAvoidingOpportunityAttacks(token, attackers, score)
check(bestMove ~= nil and bestMove.id == "leave" and ai._tmp_oaSafeOnly == nil and ai.paths.b ~= nil,
    "with nothing safe to do, a strong enough plan provokes")

ai = NewAI()
score = Scorer(ai, 0, 0.6)
bestScore, bestMove = ai:ChooseAvoidingOpportunityAttacks(token, attackers, score)
check(bestMove == nil and bestScore.score == 0, "a weak plan is not worth the attack")

ai = NewAI()
score = Scorer(ai, 0.2, 1.1)
bestScore, bestMove = ai:ChooseAvoidingOpportunityAttacks(token, attackers, score)
check(bestMove ~= nil and bestMove.id == "leave", "a plan worth more than the penalty over the safe one provokes")

print(string.format("ai_behavior_modules_test: %d checks passed", passed))
