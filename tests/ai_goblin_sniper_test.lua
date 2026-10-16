--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_goblin_sniper_test.lua
--Exercise sniper positioning and target assignment through the real squad planner.
local file = assert(io.open("Monster AI/MonsterAI.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
local function noop() end
--The AI profiler's file locals are no-ops here.
ProfBegin, ProfEnd, ProfCount, ProfPhaseBegin, ProfPhaseEnd, ProfRequestReport = noop, noop, noop, noop, noop, noop
--Exercise the actual manual-targeting rule as well as the AI planner.
local rulesFile = assert(io.open("Draw Steel Core Rules/MCDMActivatedAbility.lua", "r"))
local rulesSource = rulesFile:read("*a")
rulesFile:close()
ActivatedAbility = {}
--The loaded rules slice wraps the crit action replenish; stub the base behavior.
ActivatedAbilityReplenishBehavior = {Cast = function() end}
local ruleStart = assert(rulesSource:find("function ActivatedAbility:CanTargetAdditionalTimes(", 1, true))
local ruleEnd = assert(rulesSource:find("local function GetTargetsWithTokens", ruleStart, true))
assert(load(rulesSource:sub(ruleStart, ruleEnd - 1)))()
local function try_get(self, key, default)
    local value = self[key]
    if value == nil then return default end
    return value
end
function FindAbilityByName(abilities, name)
    for _,ability in ipairs(abilities) do
        if ability.name == name then return ability end
    end
end
function RunYieldingFunction(fn) return pcall(fn) end
function AIAbilityUnavailableReason() return "no action" end
table.values = function(t) local r = {}; for _,v in pairs(t) do r[#r+1] = v end; return r end
MonsterAI = {
    try_get = try_get,
    TokenIsLiveCombatant = function(t) return t ~= nil and t.valid end,
    TokenLogName = function(t) return t.name end,
    LocLogName = tostring, TargetsLogName = function() return "targets" end,
    AbilityActionLogName = function() return "Main Action" end,
    LogDecision = noop, LogMove = noop, SetLogContext = noop, SetMoveLogContext = noop,
    RefreshCombatants = noop, Sleep = noop,
    --The squad's speech, reservations and side-by-side movement are covered by
    --ai_squad_volley_test.lua; these fixtures use string locs, so every square is free.
    SpeakNow = noop, AnnounceSquadStrike = noop, ReserveSquadOption = noop,
    NewSquadReservations = function() return {squares = {}, lanes = {}} end,
    SquadFootprintOffsets = function() return {{0, 0}} end,
    SquadOptionIsFree = function() return true end,
    RunConcurrently = function(_, fns) for _,fn in ipairs(fns) do fn() end end,
    MovementTokenIsAtLoc = function(_, t, loc) return t.loc == loc end,
}
assert(load(section("function MonsterAI.TargetDistance", "-- Use the real token volume")))()
assert(load(section("function MonsterAI:ExecuteSquadStrike(ability)", "function MonsterAI:FindBestMoveToUseStrike")))()

local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function fixture(count)
    local tokens, members, casts = {}, {}, {}
    local enemy = {id = "enemy", charid = "enemy", name = "enemy", valid = true, altitude = 0, tileSize = 1}
    tokens.enemy = enemy
    dmhub = {
        unitsPerSquare = 1,
        initiativeQueue = {hidden = false, round = 1},
        GetTokenById = function(id) return tokens[id] end,
        Schedule = function(_, fn) fn() end,
        MarkLineOfSight = function() return {DestroyLineOfSight = noop} end,
    }
    local ability = {name = "Whistling Axes", categorization = "Signature Ability"}
    function ability:GetRange() return 1 end
    function ability:CanAfford(t) return t.actions > 0 end
    function ability:UsesSquadStrike() return true end
    ability.CanTargetAdditionalTimes = ActivatedAbility.CanTargetAdditionalTimes
    for i=1,count do
        local t = {charid = tostring(i), name = "Minion " .. i, valid = true, altitude = 0, tileSize = 1, actions = 1, moved = 0, loc = "start"}
        function t:Distance() return 1 end
        function t:GetLineOfSight() return 1 end
        t.properties = {minion = true, monster_type = "Dwarf Axethrower", try_get = try_get,
            has_key = function(self, key) return self[key] ~= nil end,
            GetActivatedAbilities = function() return {ability} end,
            CurrentMovementSpeed = function() return 5 end,
            DistanceMovedThisTurn = function() return t.moved end,
            CalculateNamedCustomAttribute = function(_, name)
                assert(name == "Ignore Minion Target Limit")
                return t.ignoreTargetLimit and 1 or 0
            end,
            GetPierceWalls = function() return 0 end}
        tokens[t.charid] = t
        members[#members+1] = {token = t}
    end
    local ai = setmetatable({squadMembers = members, squadCaptain = false, casts = casts,
        pathBudgets = {}, moveCounts = {}, _tmp_failedMoves = {}}, {__index = MonsterAI})
    function ai:SetupCombatants(t) self.token = t; self.abilities = t.properties:GetActivatedAbilities() end
    function ai:GetMovementToken(t) return t end
    function ai:ExecuteAdvanceFallback(t)
        if self.advanceFallback then return self.advanceFallback(t) end
        return false
    end
    function ai:CalculateMovementPaths(t, budget)
        self.pathBudgets[#self.pathBudgets+1] = {token = t, budget = budget}
        return {{loc = budget > 0 and "attack position" or t.loc, cost = budget}}
    end
    function ai:FindSquadMemberStrikeOptions(member)
        if self.noTargets then return {} end
        local options = {{token = enemy, loc = member.paths[1].loc, cost = 0}}
        if self.otherEnemy then
            tokens[self.otherEnemy.charid] = self.otherEnemy
            options[#options+1] = {token = self.otherEnemy, loc = member.paths[1].loc, cost = 100000}
        end
        return options
    end
    function ai:MoveToken(t, loc)
        self.moveCounts[t.charid] = (self.moveCounts[t.charid] or 0) + 1
        t.loc = loc; t.moved = 5
        if self.afterMove then self.afterMove(t) end
        return nil, t.valid
    end
    function ai:ExecuteAbility(caster, _, _, options)
        local ids = {}
        for _,pair in ipairs(options.symbols.targetPairs) do
            local t = tokens[pair.a]
            check(t.valid and t.actions > 0, "every attacker must be alive and able to pay")
            t.actions = t.actions - 1
            ids[#ids+1] = t.charid
        end
        casts[#casts+1] = {caster = caster.charid, ids = ids, pairs = options.symbols.targetPairs}
        --The normal critical-hit rule restores a Main Action after the cast.
        if self.afterCast then self.afterCast(#casts, tokens) end
    end
    return ai, tokens
end

-- Exercise sniper positioning through the real squad option and assignment code.
assert(load(section("function MonsterAI:FindSquadMemberStrikeOptions", "function MonsterAI:ExecuteSquadStrike")))()
local sniperTactic
function MonsterAI:RegisterTactic(tactic) sniperTactic = tactic end
function MonsterAI:RegisterMaliceAbility() end
dmhub = {GetModLoading = function() return {} end}
dofile("Monster AI/MonsterAIGoblins.lua")

local function sniperFixture(count, stationaryTargets)
    local squad, registry = fixture(count)
    local start, moved = {str = "start"}, {str = "moved"}
    registry.other = {id = "other", charid = "other", name = "other", valid = true, altitude = 0, tileSize = 1}
    local bow = registry["1"].properties:GetActivatedAbilities()[1]
    bow.name = "Bow"
    function bow:GetRange() return 10 end
    function bow:GetNumTargets() return 1 end
    for i=1,count do
        registry[tostring(i)].properties.monster_type = "Goblin Sniper"
        registry[tostring(i)].loc = start
    end
    squad.FindSquadMemberStrikeOptions = MonsterAI.FindSquadMemberStrikeOptions
    function squad:CalculateRemainingMovementPaths()
        return {{loc = start, cost = 0}, {loc = moved, cost = 10}}
    end
    function squad:FindValidTargetsOfStrike(token, ability, loc)
        local oldLoc = token.loc
        token.loc = loc -- Match the engine's hypothetical-location probe.
        local result = {}
        for _,id in ipairs(loc == start and stationaryTargets or {"enemy", "other"}) do
            result[#result+1] = {token = registry[id], edges =
                (sniperTactic.score(self, token, loc, registry[id], ability) or 0)
                + (loc == moved and 3 or 0)}
        end
        token.loc = oldLoc
        return result
    end
    squad:SetupCombatants(registry["1"])
    return squad, registry, bow, start, moved
end

local ai, tokens, bow, start, moved
ai, tokens, bow, start, moved = sniperFixture(2, {"enemy", "other"})
ai:ExecuteSquadStrike(bow)
check(tokens["1"].loc == start and tokens["2"].loc == start,
    "snipers stay still despite better tactical bonuses after moving")
check(ai.casts[1].pairs[1].b ~= ai.casts[1].pairs[2].b,
    "stationary snipers spread shots across available targets")

ai, tokens, bow, start, moved = sniperFixture(2, {"enemy"})
ai:ExecuteSquadStrike(bow)
check(tokens["2"].loc == start and ai.casts[1].pairs[2].b == "enemy",
    "a legal stationary shot outranks moving solely to spread fire")

ai, tokens, bow, start, moved = sniperFixture(1, {})
ai:ExecuteSquadStrike(bow)
check(tokens["1"].loc == moved and #ai.casts == 1,
    "sniper moves and shoots when no stationary target is available")

-- Verify target caps when supported by the shared squad planner.
if source:find("memberAbility:CanTargetAdditionalTimes", 1, true) then
    ai, tokens, bow, start, moved = sniperFixture(4, {"enemy"})
    ai:ExecuteSquadStrike(bow)
    check(tokens["4"].loc == moved and ai.casts[1].pairs[4].b == "other",
        "sniper moves to a legal target when the stationary target reaches its cap")
end
check(sniperTactic.score(ai, tokens["1"], start, tokens.enemy, {name = "Other"}) == nil,
    "hold position only applies to Bow")
tokens["1"].properties.monster_type = "Goblin Archer"
check(sniperTactic.score(ai, tokens["1"], start, tokens.enemy, bow) == nil,
    "hold position does not affect another monster type")
print(string.format("PASS: %d goblin sniper positioning checks", checks))
