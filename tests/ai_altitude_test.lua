-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/ai_altitude_test.lua
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
local function noop() end
--The AI profiler's file locals are no-ops here.
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = noop, noop, noop, noop, noop, noop
MonsterAI = {TokenIsLiveCombatant = function(t) return t and t.valid end,
    TokenLogName = tostring, TargetsLogName = tostring, AbilityActionLogName = tostring,
    LogDecision = noop}
--Planning answers are not remembered between calls here.
function MonsterAI:PlanningMemo() return {filters = {}, lineOfSight = {}, chargeProbes = {}, chargeRoutes = false} end
dmhub = {unitsPerSquare = 1}
assert(load(section("function MonsterAI.TargetDistance", "function MonsterAI:MovementTokenIsAtLoc")))()
assert(load(section("function MonsterAI:FindValidTargetsOfStrike", "function MonsterAI:FindSquadMemberStrikeOptions")))()
-- Run the actual cast preflight, stopping before presentation and resource spending.
assert(load(section("function MonsterAI:ExecuteAbility(", "    if targetArea ~= nil and options.telegraphArea") .. "return true, targets, ability end"))()
table.resize_array = function(t, n) for i = #t,n+1,-1 do t[i] = nil end end
local function token(x, altitude, size)
    local t = {valid = true, charid = "token" .. x, loc = {x = x, altitude = altitude, str = x .. ":" .. altitude}, tileSize = size or 1}
    setmetatable(t, {__index = function(self, key)
        if key == "altitude" then return self.loc.altitude end
    end})
    t.properties = {GetPierceWalls = function() return 0 end,
        HasNamedCondition = function() return false end,
        CurrentMovementSpeed = function() return 6 end}
    function t:Distance(other) return math.abs(self.loc.x - other.loc.x) * dmhub.unitsPerSquare end
    function t:GetLineOfSight() return 1 end
    function t:ExecuteWithTheoreticalLoc(loc, fn)
        local old = self.loc; self.loc = loc; fn(); self.loc = old
    end
    return t
end
local goblin, pixie = token(0, 2), token(1, 7)
local ai = setmetatable({enemyTokens = {pixie}, activeTactics = {}}, {__index = MonsterAI})
function ai:try_get(k, default) if self[k] == nil then return default end return self[k] end
function ai:GetMovementToken(t) return t end
local ability = {name = "Sword Stab", targetType = "target", range = 1}
function ability:try_get(k, default) if self[k] == nil then return default end return self[k] end
function ability:GetRangeSource(actor) return self.rangeSource or actor end
function ability:GetRange() return self.range end
function ability:GetNumTargets() return 1 end
function ability:TargetPassesFilter() return true end
function ability:CanAfford() return true end
function ability:HasKeyword(k) return k == "Strike" or k == "Melee" end
assert(MonsterAI.TargetDistance(goblin, pixie) == 5, "live goblin/pixie altitude regression")
assert(#ai:FindValidTargetsOfStrike(goblin, ability, goblin.loc) == 0, "reject elevated melee target")
assert(ai:ExecuteAbility(goblin, ability, {{token = pixie}}) == false, "reject stale or custom out-of-range plan")
local landing = {x = 0, altitude = 6}
assert(#ai:FindValidTargetsOfStrike(goblin, ability, landing) == 1, "allow reachable elevated attack position")
assert(goblin.altitude == 2, "theoretical planning restores actual altitude")
assert(ai:ExecuteAbility(goblin, ability, {{token = pixie}}) == false, "planned location cannot authorize actual cast")
ability.range = 5
assert(#ai:FindValidTargetsOfStrike(goblin, ability, goblin.loc) == 1, "exact vertical range boundary is legal")
assert(ai:ExecuteAbility(goblin, ability, {{token = pixie}}), "legal ranged-distance preflight passes")
ability.range = 4
assert(#ai:FindValidTargetsOfStrike(goblin, ability, goblin.loc) == 0, "vertical distance limits longer range too")
local ranged = setmetatable({range = 10}, {__index = ability})
local mixed = setmetatable({meleeAndRanged = true, meleeVariation = ability,
    rangedVariation = ranged}, {__index = ability})
ability.range = 1
assert(ai:ExecuteAbility(goblin, mixed, {{token = pixie}}), "dual-mode attack can use legal ranged variation")
ranged.range = 4
assert(ai:ExecuteAbility(goblin, mixed, {{token = pixie}}) == false, "reject both out-of-range variations")
goblin.tileSize = 5
assert(MonsterAI.TargetDistance(goblin, pixie) == 1, "large creature can reach above its top square")
assert(MonsterAI.TargetDistance(pixie, goblin) == 1, "size-aware distance is symmetric")
goblin.tileSize = 1; pixie.loc.altitude = 3
assert(MonsterAI.TargetDistance(goblin, pixie) == 1, "vertical diagonal adjacency is legal")
pixie.loc.x = 8
assert(MonsterAI.TargetDistance(goblin, pixie) == 8, "horizontal separation still limits range")
pixie.loc.x = 1; pixie.loc.altitude = 7; dmhub.unitsPerSquare = 5
assert(MonsterAI.TargetDistance(goblin, pixie) == 25, "convert altitude to native range units")
dmhub.unitsPerSquare = 1
ability.rangeSource = token(0, 6)
assert(ai:ExecuteAbility(goblin, ability, {{token = pixie}}), "respect explicit casting origin")
ability.rangeSource = nil
local ok, _, chosen = ai:ExecuteAbility(goblin, mixed, {{token = pixie}})
assert(ok == false)
ranged.range = 10
ok, _, chosen = ai:ExecuteAbility(goblin, mixed, {{token = pixie}})
assert(ok and chosen == ranged, "altitude chooses ranged instead of melee variation")
dmhub.allTokens = {goblin, pixie}
local burst = setmetatable({targetType = "all", range = 1}, {__index = ability})
local _, targets = ai:ExecuteAbility(goblin, burst)
assert(targets ~= nil, "burst resolves targets")
assert(#targets == 1 and targets[1].token == goblin, "burst excludes vertically distant creatures")
local map = setmetatable({targetType = "map"}, {__index = ability})
_, targets = ai:ExecuteAbility(goblin, map)
assert(#targets == 2, "map-wide effects remain unlimited")
assert(ai:ExecuteAbility(goblin, ability, {{token = pixie}}, {targetArea = {}, telegraphArea = false}),
    "placed area membership is independent of direct creature range")
assert(load(section("function MonsterAI:HandlePrompt", "--AI actions yield")))()
function goblin.properties:try_get(_, default) return default end
goblin.charid = "goblin"
ai.prompts = {[ability.name] = {handler = function() return {targets = {{token = pixie}}} end}}
assert(ai:HandlePrompt(goblin, goblin, ability, {}, {}) == "prompt", "invalid custom prompt defers to Director")
pixie.loc.altitude = 3
local options = {}
assert(ai:HandlePrompt(goblin, goblin, ability, {}, options) == "inherit", "legal custom prompt remains automatic")
assert(options.targets[1].token == pixie)
print("AI altitude distance, size, planning, and cast preflight tests passed")
