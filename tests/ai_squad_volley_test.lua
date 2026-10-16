--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_squad_volley_test.lua
--A minion squad plans every member first, calls the attack, then moves together:
--side-by-side movement (RunConcurrently), squad reservations, and the volley order.
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

local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end

--A fake clock: the driver advances it by whatever delay the AI yields.
local clock = 0
dmhub = {unitsPerSquare = 1, Time = function() return clock end}
local function drive(fn)
    local co = coroutine.create(fn)
    while coroutine.status(co) ~= "dead" do
        local ok, delay = coroutine.resume(co)
        assert(ok, delay)
        if coroutine.status(co) ~= "dead" then
            clock = clock + (type(delay) == "number" and delay or 0.1)
        end
    end
end

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
MonsterAI = {
    try_get = try_get,
    squadMoveStagger = 0.2,
    TokenIsLiveCombatant = function(t) return t ~= nil and t.valid end,
    TokenLogName = function(t) return t.name end,
    LocLogName = function(loc) return loc and loc.str or "nil" end,
    TargetsLogName = function() return "targets" end,
    AbilityActionLogName = function() return "Main Action" end,
    LogDecision = noop, LogMove = noop, RefreshCombatants = noop,
    Sleep = function(seconds) if seconds > 0 then coroutine.yield(seconds) end end,
}
assert(load(section("MonsterAI.squadCallLines = {", "MonsterAI.abilities = {}")))()
assert(load(section("function MonsterAI.TargetDistance", "-- Use the real token volume")))()
assert(load(section("function MonsterAI:RunConcurrently", "--The control is kept in Creature.lua")))()
assert(load(section("--Squad reservations ---", "function MonsterAI:ExecuteSquadStrike(ability)")))()
assert(load(section("function MonsterAI:ExecuteSquadStrike(ability)", "function MonsterAI:FindBestMoveToUseStrike")))()
assert(load(section("function MonsterAI:AnnounceSquadStrike", "function MonsterAI:LogMove")))()

local function L(x, y) return {x = x, y = y, floor = 0, altitude = 0, str = x .. "," .. y} end

--RunConcurrently: staggered starts, overlapping runs, and errors held until all finish.
do
    clock = 0
    local log = {}
    local function action(name, duration)
        return function()
            log[#log+1] = {name = name, event = "start", t = clock}
            coroutine.yield(duration)
            log[#log+1] = {name = name, event = "end", t = clock}
        end
    end
    drive(function()
        MonsterAI:RunConcurrently({action("a", 1), action("b", 1), action("c", 1)}, 0.2)
    end)
    local starts, ends = {}, {}
    for _,entry in ipairs(log) do
        if entry.event == "start" then starts[entry.name] = entry.t else ends[entry.name] = entry.t end
    end
    check(starts.a == 0 and math.abs(starts.b - 0.2) < 1e-9 and math.abs(starts.c - 0.4) < 1e-9,
        "each action starts one stagger after the one before")
    check(starts.c < ends.a, "the actions run side by side, not one after another")
    check(ends.a and ends.b and ends.c, "every action finishes")

    clock = 0
    local finished = false
    local ok, err = pcall(function()
        drive(function()
            MonsterAI:RunConcurrently({
                function() coroutine.yield(0.1); error("boom") end,
                function() coroutine.yield(0.5); finished = true end,
            }, 0)
        end)
    end)
    check(not ok and tostring(err):find("boom", 1, true) ~= nil, "an action's error is raised")
    check(finished, "an error in one action does not abandon the others mid-move")
end

--Squad reservations.
do
    local reserved = MonsterAI.NewSquadReservations()
    local single = {{0, 0}}
    local mover = {loc = L(0, 0)}
    function mover:LocsOccupyingWhenAt(loc) return {loc} end
    local ai = setmetatable({}, {__index = MonsterAI})
    function ai:GetMovementToken(t) return t end
    ai:ReserveSquadOption(reserved, mover, {loc = L(3, 3)})
    check(not MonsterAI.SquadOptionIsFree(reserved, single, L(3, 3), nil), "a claimed square is taken")
    check(MonsterAI.SquadOptionIsFree(reserved, single, L(3, 4), nil), "the next square is free")
    check(not MonsterAI.SquadOptionIsFree(reserved, single, L(0, 3), L(6, 3)),
        "a charge through a claimed square is refused")
    check(MonsterAI.SquadOptionIsFree(reserved, single, L(0, 5), L(6, 5)), "a charge on a clear row is allowed")

    ai:ReserveSquadOption(reserved, mover, {loc = L(0, 8), charge = L(6, 8)})
    check(not MonsterAI.SquadOptionIsFree(reserved, single, L(3, 8), nil),
        "stopping in a squad-mate's charge lane is refused")
    check(not MonsterAI.SquadOptionIsFree(reserved, single, L(3, 10), L(3, 8)),
        "landing in a squad-mate's charge lane is refused")
    check(not MonsterAI.SquadOptionIsFree(reserved, single, L(6, 8), nil), "a charge's landing is claimed")
    check(MonsterAI.SquadOptionIsFree(reserved, single, L(0, 10), L(6, 10)), "lanes may run side by side")

    local large = {{0, 0}, {1, 0}, {0, 1}, {1, 1}}
    check(not MonsterAI.SquadOptionIsFree(reserved, large, L(2, 2), nil),
        "a large creature's whole footprint is checked")
    check(MonsterAI.SquadOptionIsFree(reserved, large, L(1, 4), nil), "a large creature fits beside a claim")
end

--The volley: plan everyone, call the attack, move together, then strike once.
local function fixture(starts, enemyLoc, charges)
    clock = 0
    local events, tokens, members = {}, {}, {}
    local function record(kind, t, extra)
        events[#events+1] = {kind = kind, id = t and t.charid, t = clock, extra = extra}
    end
    local enemy = {charid = "enemy", name = "enemy", valid = true, altitude = 0, tileSize = 1, loc = enemyLoc}
    tokens.enemy = enemy
    dmhub.GetTokenById = function(id) return tokens[id] end
    dmhub.Schedule = function(_, fn) fn() end
    dmhub.MarkLineOfSight = function() return {DestroyLineOfSight = noop} end
    dmhub.initiativeQueue = nil
    local ability = {name = "Spear", categorization = "Signature Ability"}
    function ability:GetRange() return 1 end
    function ability:GetNumTargets() return 1 end
    function ability:CanAfford(t) return t.actions > 0 end
    function ability:HasKeyword(keyword) return keyword == "Melee" end
    function ability:CanTargetAdditionalTimes() return true end
    local function Chebyshev(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end
    for i,start in ipairs(starts) do
        local t = {charid = tostring(i), name = "Minion " .. i, valid = true, altitude = 0, tileSize = 1,
            actions = 1, loc = start, start = start}
        function t:Distance(other) return Chebyshev(self.loc, other.loc) end
        function t:GetLineOfSight() return 1 end
        function t:LocsOccupyingWhenAt(loc) return {loc} end
        t.properties = {minion = true, try_get = try_get,
            GetActivatedAbilities = function() return {ability} end,
            GetPierceWalls = function() return 0 end}
        tokens[t.charid] = t
        members[#members+1] = {token = t}
    end
    local captain = {charid = "captain", name = "captain", valid = true}
    local ai = setmetatable({squadMembers = members, squadCaptain = captain, token = members[1].token},
        {__index = MonsterAI})
    function ai:GetMovementToken(t) return t end
    function ai:ExecuteAdvanceFallback() return false end
    function ai:MovementTokenIsAtLoc(t, loc) return t.loc.str == loc.str end
    function ai:CalculateRemainingMovementPaths(t)
        if charges then return {{loc = t.loc, cost = 0}} end
        --every square next to the enemy, priced by distance from the minion.
        local paths = {}
        for dx=-1,1 do
            for dy=-1,1 do
                if dx ~= 0 or dy ~= 0 then
                    local loc = L(enemyLoc.x + dx, enemyLoc.y + dy)
                    paths[#paths+1] = {loc = loc, cost = Chebyshev(t.loc, loc)}
                end
            end
        end
        return paths
    end
    function ai:FindValidTargetsOfStrike(t, _, loc)
        if charges then
            --like the engine's charge routes, a creature standing in the lane blocks it.
            local landing = charges[t.charid]
            for _,member in ipairs(members) do
                local other = member.token.loc
                if member.token ~= t and other.x >= math.min(loc.x, landing.x) and other.x <= math.max(loc.x, landing.x)
                    and other.y >= math.min(loc.y, landing.y) and other.y <= math.max(loc.y, landing.y) then
                    return {}
                end
            end
            return {{token = enemy, edges = 0, charge = landing}}
        end
        return Chebyshev(loc, enemyLoc) <= 1 and {{token = enemy, edges = 0}} or {}
    end
    function ai:SpeakNow(t, text)
        if type(text) == "table" then text = text[1] end
        record("speak", t, text)
    end
    function ai:MoveToken(t, loc)
        record("moveStart", t)
        coroutine.yield(0.5)
        t.loc = loc
        record("moveEnd", t)
        return {}, true
    end
    function ai:ExecuteChargeMovement(t, dest)
        record("chargeStart", t)
        coroutine.yield(0.3)
        t.loc = dest
        record("chargeEnd", t)
        return true, true
    end
    function ai:ExecuteAbility(caster, _, _, options)
        record("cast", caster, options.symbols.targetPairs)
    end
    local executed
    drive(function() executed = ai:ExecuteSquadStrike(ability) end)
    return events, tokens, executed
end

local function first(events, kind)
    for i,event in ipairs(events) do
        if event.kind == kind then return i, event end
    end
end
local function all(events, kind)
    local result = {}
    for _,event in ipairs(events) do
        if event.kind == kind then result[#result+1] = event end
    end
    return result
end

do
    math.randomseed(7)
    local events, tokens, executed = fixture({L(0, 4), L(0, 5), L(0, 6)}, L(5, 5))
    local firstSpeak, callEvent = first(events, "speak")
    local firstMove = first(events, "moveStart")
    check(callEvent.id == "captain", "the captain calls the attack")
    check(firstSpeak < firstMove, "the battle cry comes before anyone moves")
    local answers = 0
    for i=firstSpeak+1,firstMove-1 do
        if events[i].kind == "speak" then
            check(events[i].id ~= "captain", "squad members answer the call")
            answers = answers + 1
        end
    end
    check(answers >= 2 and answers <= 3, "two or three squad members shout back")

    local moves, moveEnds = all(events, "moveStart"), all(events, "moveEnd")
    check(#moves == 3, "every planned member moves once")
    check(math.abs(moves[2].t - moves[1].t - 0.2) < 1e-9 and math.abs(moves[3].t - moves[2].t - 0.2) < 1e-9,
        "members set off a stagger apart")
    check(moves[3].t < moveEnds[1].t, "the squad moves together, not one at a time")

    local seen = {}
    for i=1,3 do
        local loc = tokens[tostring(i)].loc.str
        check(not seen[loc], "squad members end on different squares")
        seen[loc] = true
    end
    local casts = all(events, "cast")
    check(executed and #casts == 1 and #casts[1].extra == 3, "the whole squad strikes in one volley")
    check(first(events, "cast") > #events - 1 and casts[1].t >= moveEnds[3].t, "the strike waits for every arrival")
end

do
    math.randomseed(11)
    --Two chargers on parallel rows: each starts where it stands and charges east.
    local events, tokens = fixture({L(0, 4), L(0, 6)}, L(5, 5), {["1"] = L(4, 4), ["2"] = L(4, 6)})
    local charges = all(events, "chargeStart")
    check(#charges == 2, "both chargers charge")
    local lastMoveEnd = 0
    for _,event in ipairs(all(events, "moveEnd")) do lastMoveEnd = math.max(lastMoveEnd, event.t) end
    check(charges[1].t > lastMoveEnd, "chargers wait until the whole squad is in place")
    local shouts = 0
    local firstCharge = first(events, "chargeStart")
    for i=1,firstCharge-1 do
        if events[i].kind == "speak" and events[i].extra == "Charge!" then shouts = shouts + 1 end
    end
    check(shouts == 2, "every charger shouts before the charges begin")
    check(math.abs(charges[2].t - charges[1].t - 0.2) < 1e-9 and charges[2].t < all(events, "chargeEnd")[1].t,
        "the charges run together, a stagger apart")
    check(tokens["1"].loc.str == "4,4" and tokens["2"].loc.str == "4,6", "both chargers land")
    check(#all(events, "cast") == 1 and #all(events, "cast")[1].extra == 2, "both chargers join the volley")
end

do
    --The second charger's lane would cross the first one's landing: it is not chosen.
    local events, tokens = fixture({L(0, 4), L(4, 2)}, L(5, 5), {["1"] = L(4, 4), ["2"] = L(4, 6)})
    check(tokens["1"].loc.str == "4,4", "the first charger keeps its charge")
    check(tokens["2"].loc.str == "4,2" and #all(events, "chargeStart") == 1,
        "a charge through a squad-mate's landing square is not planned")
end

print(string.format("PASS: %d squad volley checks", checks))
