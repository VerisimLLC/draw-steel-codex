--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_minion_critical_test.lua
--Exercise the real action cycle, selection and squad planning with simulated casts.
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
--Newer rules helpers the loaded slices call. Squad narrowing (invokes) is off,
--and the crit-widened action replenish is exercised through afterCast below.
ActivatedAbility.SquadMemberParticipates = function() return true end
ActivatedAbilityReplenishBehavior = {Cast = function() end}
CharacterResource = {actionResourceId = "action"}
--Simulate the base payment for participating attackers, then exercise the real
--Draw Steel wrapper that also spends nonparticipants' shared action.
function ActivatedAbility:ConsumeResources(caster, options)
    local paid = {}
    for _,pair in ipairs(options.symbols.targetPairs) do
        if not paid[pair.a] then
            --The GetTokenById double below returns the plain minion tables built in this test.
            local t = dmhub.GetTokenById(pair.a) --[[@as {actions: integer}]]
            t.actions = t.actions - 1
            paid[pair.a] = true
        end
    end
end
local consumeStart = assert(rulesSource:find("local g_consumeResources_base =", 1, true))
local consumeEnd = assert(rulesSource:find("function ActivatedAbility:CanTargetAdditionalTimes(", consumeStart, true))
assert(load(rulesSource:sub(consumeStart, consumeEnd - 1)))()
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
    --ai_squad_volley_test.lua; here the moves simply run one after another.
    SpeakNow = noop, ReserveSquadOption = noop,
    NewSquadReservations = function() return {squares = {}, lanes = {}} end,
    AnnounceSquadStrike = function(self) self.announcements = (self.announcements or 0) + 1 end,
    RunConcurrently = function(_, fns) for _,fn in ipairs(fns) do fn() end end,
    MovementTokenIsAtLoc = function(_, t, loc) return t.loc == loc end,
}
local prefix = 'local g_moveResultExecuted="executed"; local g_moveResultNone="none"; local g_moveResultUnsafe="unsafe";\n'
assert(load(section("function MonsterAI.TargetDistance", "-- Use the real token volume")))()
assert(load(section("function MonsterAI:FindSquadActionToken()", "function MonsterAI:PlayTurnCoroutine")))()
assert(load(section("function MonsterAI:ExecuteSquadStrike(ability)", "function MonsterAI:FindBestMoveToUseStrike")))()
assert(load(section("function MonsterAI:CalculateRemainingMovementPaths", "function MonsterAI:CountPendingActivityReactions")))()
assert(load(prefix .. section("function MonsterAI:FindAndExecuteMove()", "function MonsterAI:ExecuteAbility(")))()
--The cycle loop also checks that its turn is still current (6TTFJWFP).
local turnCheck = section("local g_abortTurnTaken", "function MonsterAI:PlayTurnCoroutine")
local runCycles = assert(load(prefix .. turnCheck .. "return function(self, token, queue, initiativeid, squadid)\n" ..
    section("                    for cycle=1,6 do", "\n                end)") .. "\nend"))()

local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function fixture(count)
    local tokens, members, casts = {}, {}, {}
    local enemy = {id = "enemy", charid = "enemy", name = "enemy", valid = true, altitude = 0, tileSize = 1}
    tokens.enemy = enemy
    dmhub = {
        unitsPerSquare = 1,
        initiativeQueue = {hidden = false, round = 1, current = "turn",
            CurrentInitiativeId = function(q) return q.current end},
        GetTokenById = function(id) return tokens[id] end,
        Schedule = function(_, fn) fn() end,
        MarkLineOfSight = function() return {DestroyLineOfSight = noop} end,
    }
    local ability = {name = "Whistling Axes", categorization = "Signature Ability"}
    function ability:GetRange() return 1 end
    function ability:CanAfford(t) return t.actions > 0 end
    function ability:UsesSquadStrike() return true end
    function ability:UsesSquadCoordination() return true end
    function ability:UsesIndividualManeuver() return false end
    function ability:GetCost()
        return {details = {{paymentOptions = {{resourceid = "action", quantity = 1}}}}}
    end
    ability.ConsumeResources = ActivatedAbility.ConsumeResources
    ability.CanTargetAdditionalTimes = ActivatedAbility.CanTargetAdditionalTimes
    for i=1,count do
        local t = {charid = tostring(i), name = "Minion " .. i, valid = true, altitude = 0, tileSize = 1, actions = 1, moved = 0, loc = "start"}
        function t:Distance() return 1 end
        function t:GetLineOfSight() return 1 end
        t.properties = {minion = true, monster_type = "Dwarf Axethrower", try_get = try_get,
            IsDead = function() return not t.valid end,
            IsActiveInSquad = function() return true end,
            HasManeuverOrActionRule = function() return false end,
            GetResourceUsage = function() return 1 - t.actions end,
            ConsumeResource = function(_, _, _, quantity) t.actions = t.actions - quantity end,
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
        function t:ModifyProperties(options) options.execute() end
        members[#members+1] = {token = t}
    end
    local squadTokens = {}
    for _,member in ipairs(members) do squadTokens[#squadTokens+1] = member.token end
    for _,t in ipairs(squadTokens) do t.properties._tmp_minionSquad = {tokens = squadTokens} end
    local ai = setmetatable({squadMembers = members, squadCaptain = false, casts = casts,
        pathBudgets = {}, moveCounts = {}, decisions = {}, _tmp_failedMoves = {}}, {__index = MonsterAI})
    function ai:LogDecision(event, fields)
        self.decisions[#self.decisions+1] = {event = event, fields = fields}
    end
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
        if self.unreachable and self.unreachable[member.token.charid] then return {} end
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
            ids[#ids+1] = t.charid
        end
        ability:ConsumeResources(caster, options)
        casts[#casts+1] = {caster = caster.charid, ids = ids, pairs = options.symbols.targetPairs}
        --The normal critical-hit rule restores a Main Action after the cast.
        if self.afterCast then self.afterCast(#casts, tokens) end
    end
    return ai, tokens, function()
        runCycles(ai, members[1].token, dmhub.initiativeQueue, "turn", "squad")
    end
end

local ai, tokens, run = fixture(1)
tokens.enemy.altitude = 5
run()
check(#ai.casts == 0, "minions reject an elevated target even if a custom planner supplied it")
local function cancellation(ai)
    for _,entry in ipairs(ai.decisions) do
        if entry.event == "MINION ASSIGNMENT CANCELLED" then return entry.fields end
    end
    error("expected cancelled assignment")
end
check(cancellation(ai).reason == "target is out of range after movement" and cancellation(ai).distance == 5,
    "range cancellation records the actual distance, not a false death report")
ai, tokens, run = fixture(1)
tokens["1"].GetLineOfSight = function() return 0 end
run()
check(#ai.casts == 0 and cancellation(ai).reason == "target has no line of sight after movement"
    and cancellation(ai).lineOfSight == 0, "blocked sight is rejected and diagnosed explicitly")
ai, tokens, run = fixture(4)
ai.otherEnemy = {id = "other", charid = "other", name = "other", valid = true, altitude = 0, tileSize = 1}
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 4, "four eligible snipers join one volley across legal targets")
ai, tokens, run = fixture(1)
ai.afterMove = function() tokens.enemy.altitude = 5 end
run()
check(#ai.casts == 0, "minions recheck altitude after movement reactions")
ai, tokens, run = fixture(1)
ai.afterCast = function(n) if n == 1 then tokens["1"].actions = 1 end end
run()
check(#ai.casts == 2, "single minion uses its critical-hit action")
check(tokens["1"].actions == 0, "extra action is spent")
check(ai.pathBudgets[#ai.pathBudgets].budget == 0, "critical does not restore movement")

ai, tokens, run = fixture(3)
ai.afterCast = function(n) if n == 1 then tokens["2"].actions = 1 end end
run()
check(#ai.casts == 2 and ai.casts[2].caster == "2", "critical on another squad member selects that actor")
check(#ai.casts[2].ids == 1 and ai.casts[2].ids[1] == "2", "spent squadmates cannot join the extra strike")
check(ai.moveCounts["1"] == 1 and ai.moveCounts["3"] == 1, "spent squadmates cannot move again")

--The book rule: a squad critical hit restores the main action of EVERY minion
--that participated in the volley (the rules layer widens the Critical Hit
--replenish to options.symbols.squadparticipantids). Nonparticipants stay spent.
ai, tokens, run = fixture(3)
ai.afterCast = function(n, toks)
    if n == 1 then
        for _,id in ipairs(ai.casts[1].ids) do toks[id].actions = 1 end
    end
end
run()
check(#ai.casts == 2 and #ai.casts[1].ids == 3 and #ai.casts[2].ids == 3,
    "squad critical hit lets every participant strike again together")
for _,id in ipairs(ai.casts[2].ids) do
    check(tokens[id].actions == 0, "each participant's extra action is spent by the second volley")
end

ai, tokens, run = fixture(2)
run()
check(#ai.casts == 1, "ordinary squad turn still strikes once")

ai, tokens, run = fixture(2)
tokens["1"].actions = 0
run()
check(#ai.casts == 1 and ai.casts[1].caster == "2", "spent initial actor does not block another member")
check(#ai.casts[1].ids == 1, "initial planning also checks each member's resources")

ai, tokens, run = fixture(2)
ai.afterCast = function(n)
    if n == 1 then tokens["2"].actions = 1; tokens["1"].valid = false end
end
run()
check(#ai.casts == 2, "dead initial actor does not block surviving critical recipient")

ai, tokens, run = fixture(2)
ai.afterMove = function(t) if t.charid == "2" then tokens["1"].actions = 0 end end
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 1, "reaction spending an action removes an earlier assignment")

ai, tokens, run = fixture(1)
ai.afterCast = function(n) if n < 3 then tokens["1"].actions = 1 end end
run()
check(#ai.casts == 3, "chained critical hits use successive extra actions")

ai, tokens, run = fixture(1)
ai.afterCast = function() tokens["1"].actions = 1 end
run()
check(#ai.casts == 6, "existing six-cycle safety cap remains")

ai, tokens, run = fixture(1)
ai.noTargets = true
run()
check(#ai.casts == 0 and ai.moveCounts["1"] == nil, "no legal targets ends the squad turn")

ai, tokens, run = fixture(1)
ai.noTargets = true
local advances = 0
ai.advanceFallback = function()
    advances = advances + 1
    ai.noTargets = false
    return true
end
run()
check(advances == 1 and #ai.casts == 1, "advancing minion reconsiders its signature next cycle")

ai, tokens, run = fixture(1)
ai.afterCast = function() tokens["1"].actions = 1; ai._tmp_abortTurn = true end
run()
check(#ai.casts == 1, "stop request prevents the extra action")

ai, tokens, run = fixture(1)
ai.afterCast = function() tokens["1"].actions = 1; dmhub.initiativeQueue.current = "hero" end
run()
check(#ai.casts == 1 and ai._tmp_abortTurn ~= nil, "a turn taken by another entry stops the extra action")

ai, tokens, run = fixture(8)
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 3, "one enemy receives at most three attackers across ordinary action cycles")
check(ai.moveCounts["4"] == nil and tokens["4"].actions == 0, "capped-out minions spend the shared action without moving")

ai, tokens, run = fixture(7)
ai.otherEnemy = {id = "other", charid = "other", name = "other", valid = true, altitude = 0, tileSize = 1}
run()
local targetCounts = {}
for _,pair in ipairs(ai.casts[1].pairs) do targetCounts[pair.b] = (targetCounts[pair.b] or 0) + 1 end
check(#ai.casts == 1 and targetCounts.enemy == 3 and targetCounts.other == 3,
    "full preferred target forces another legal target even with a much higher movement cost")

ai, tokens, run = fixture(5)
for i=1,5 do tokens[tostring(i)].ignoreTargetLimit = true end
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 5, "Ignore Minion Target Limit preserves unlimited squad targeting")

ai, tokens, run = fixture(5)
tokens["1"].properties:GetActivatedAbilities()[1].repeatTargets = true
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 5, "explicit repeat-target abilities preserve the manual-targeting exception")

ai, tokens, run = fixture(5)
ai.afterCast = function(n) if n == 1 then tokens["2"].actions = 1 end end
run()
check(#ai.casts == 2 and #ai.casts[2].ids == 1 and ai.casts[2].ids[1] == "2",
    "genuine critical follow-up excludes minions skipped for the target cap")

ai, tokens, run = fixture(5)
ai.afterMove = function(t) if t.charid == "3" then tokens["1"].valid = false end end
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 3 and ai.casts[1].ids[3] == "4",
    "an attacker killed during movement frees its target slot for a surviving minion")
ai, tokens, run = fixture(2)
ai.unreachable = {["2"] = true}
ai.advanceFallback = function(t)
    ai.unreachable[t.charid] = nil
    return true
end
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 2, "advancing sniper joins the first volley, sharing a target")

ai, tokens, run = fixture(2)
ai.unreachable = {["2"] = true}
run()
check(#ai.casts == 1 and #ai.casts[1].ids == 1 and tokens["2"].actions == 0,
    "unreachable squadmate spends its action and cannot start a second volley")

ai, tokens, run = fixture(2)
ai.unreachable = {["2"] = true}
ai.afterCast = function(n)
    if n == 1 then tokens["1"].actions = 1; ai.unreachable = nil end
end
run()
check(#ai.casts == 2 and #ai.casts[2].ids == 1 and ai.casts[2].ids[1] == "1",
    "critical action does not let an earlier nonparticipant attack")

ai, tokens, run = fixture(2)
local signature = tokens["1"].properties:GetActivatedAbilities()[1]
signature:ConsumeResources(tokens["1"], {symbols = {targetPairs = {}}, costOverride = {details = {}}})
check(tokens["2"].actions == 1, "free invoked strikes do not spend other squad members' main actions")
tokens["2"].actions = 0
signature:ConsumeResources(tokens["1"], {symbols = {targetPairs = {}}})
check(tokens["2"].actions == 0, "already spent nonparticipants are not charged twice")
tokens["2"].actions = 1
tokens["2"].properties.IsActiveInSquad = function() return false end
signature:ConsumeResources(tokens["1"], {symbols = {targetPairs = {}}})
check(tokens["2"].actions == 1, "inactive squad members are excluded from shared action payment")
print(string.format("PASS: %d minion critical-hit checks", checks))
