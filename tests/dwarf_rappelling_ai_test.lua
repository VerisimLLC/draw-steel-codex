-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/dwarf_rappelling_ai_test.lua
local f = assert(io.open("Monster AI/MonsterAIDwarves.lua", "r"))
local source = f:read("*a")
f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start, true)) - 1)
end

function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = DeepCopy(child) end
    return copy
end
local registration
MonsterAI = {
    tactics = {dwarf = {}},
    MoveMatchesMonster = function() return true end,
    RegisterMaliceAbility = function(_, entry) registration = entry end,
}
local turnId = "dwarves"
dmhub = {initiativeQueue = {round = 1, CurrentInitiativeId = function() return turnId end}}
local findPlan = assert(load(
    "local movementPause, stationaryPause, abilityPause = 0.6, 0.35, 0.9\n"
    .. "local function ClearAbilityCosts(a) a.actionResourceId = nil end\n"
    .. "local function Speak() end\n"
    .. section("local function LiveCreature", "local function PortableBallistaForAI")
    .. section("local function FindAbility", "local function HasCondition")
    .. section("local function DefaultTargetScore", "local function ExecuteStrikePlan")
    .. section("local rappellingBarrageSpeech", "MonsterAI:RegisterMaliceAbility{\n    id = \"Dwarf Malice: Snaring Line\"")
    .. "return FindGrantedFreeStrikePlan", "@Dwarf-rappelling-AI"))()

local function eq(actual, expected, message)
    assert(actual == expected, message .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function ability(name)
    return {
        name = name, keywords = {Charge = true},
        GetRange = function() return 1 end,
        GetNumTargets = function() return 1 end,
        try_get = function(self, key, default)
            if self[key] == nil then return default end
            return self[key]
        end,
        CanAfford = function() return true end,
    }
end
local malice = ability("Rappelling Barrage")
local function actor(id, needsClimb)
    local token = {charid = id, valid = true, loc = {str = id .. "-start"}, needsClimb = needsClimb}
    token.destination = {str = id .. "-end"}
    local strike = ability("Melee Free Strike")
    strike.actionResourceId = "main-action"
    local grant = ability("Rappelling Free Strike")
    grant.guid = "91620000-17a3-4dc8-a7ca-b6488918fe0b"
    grant.marker = {}
    token.grant = grant
    token.properties = {
        max_hitpoints = 10,
        CurrentHitpoints = function() return 10 end,
        CurrentMovementSpeed = function() return 5 end,
        DistanceMovedThisTurn = function() return token.moved or 2 end,
        IsDead = function() return token.dead end,
        GetActivatedAbilities = function()
            local result = {strike}
            if token.granted then result[#result+1] = grant end
            return result
        end,
    }
    return token
end
local function fixture(actors)
    turnId = "dwarves"
    local ai = {activeTactics = {original = true}, moves = {}, strikes = {}, pathCalls = {}}
    local enemy = actor("hero")
    local context = {groupTokens = actors, actingTokens = actors, round = 1, initiativeId = turnId}
    function ai:CalculateRemainingMovementPaths(token)
        self.pathCalls[#self.pathCalls+1] = {actor = token, granted = token.granted}
        if token.moved == 5 then return {{loc = token.loc, cost = 0}} end
        return {{loc = token.destination, cost = 30}}
    end
    function ai:FindValidTargetsOfStrike(token, scoring, loc)
        assert(scoring.disableSquadCoordination and not scoring.keywords.Charge)
        if self.failScoring then error("scoring failure") end
        if token.lostTarget or (token.needsClimb and not token.granted) then return {} end
        if loc.str == token.destination.str then return {{token = enemy, edges = 0}} end
        return {}
    end
    function ai:MovementTokenIsAtLoc(token, loc) return token.loc.str == loc.str end
    function ai:GetMovementToken(token) return token end
    function ai:MoveToken(token, loc, options)
        self.moves[#self.moves+1] = options
        if not self.rejectMovement then token.loc = loc end
        token.moved = 5
        if self.afterMove then self.afterMove(token) end
    end
    function ai:FindMostSeniorInitiativeGroupMember() return nil end
    function ai:RunWithTokenControl(_, fn) return pcall(fn) end
    function ai:ExecuteAbility(token, cast, targets)
        if cast == malice then
            assert(targets == nil, "cast original malice with its authored targeting")
            for _, dwarf in ipairs(actors) do dwarf.granted = not dwarf.noGrant end
        else
            eq(cast, token.grant, "execute actual content grant, preserving callbacks")
            eq(targets[1].token, token, "execute self wrapper, leaving target choice to generic prompt")
            assert(token.granted, "cannot cast a spent grant")
            token.granted = false
            self.strikes[#self.strikes+1] = token
        end
    end
    ai.Sleep = function() end
    return ai, context
end

local first, climber = actor("first"), actor("climber", true)
local ai, context = fixture({first, climber})
local priorTactics = ai.activeTactics
local score = registration:score(ai, first, malice, context)
eq(score.score, 0.66, "only ordinary reachable actor contributes before grant")
eq(first.granted, nil, "scoring never grants climbing")
eq(#ai.moves, 0, "scoring never moves")
eq(ai.activeTactics, priorTactics, "scoring restores tactics")
registration:execute(ai, first, score, malice, context)
eq(#ai.strikes, 2, "replan includes actor newly reachable with climbing")
eq(ai.moves[1].maxCost, 30, "movement bounded to speed minus movement already spent")
eq(ai.moves[1].freeMovement, nil, "barrage grants no extra movement")
eq(first.granted, false, "same content grant consumed")
assert(ai.pathCalls[3].granted and ai.pathCalls[4].granted, "paths recomputed after climb applies")

local function interrupted(afterMove, message)
    local dwarf = actor(message)
    local testAI, testContext = fixture({dwarf})
    testAI.afterMove = afterMove
    registration:execute(testAI, dwarf, {}, malice, testContext)
    eq(#testAI.strikes, 0, message)
end
interrupted(function(token) token.dead = true end, "dead after reaction")
interrupted(function(token) token.granted = false end, "grant spent during reaction")
interrupted(function(token) token.lostTarget = true end, "target lost during reaction")
interrupted(function() turnId = "heroes" end, "turn advanced during reaction")

local blocked = actor("blocked")
ai, context = fixture({blocked})
ai.rejectMovement = true
registration:execute(ai, blocked, {}, malice, context)
eq(#ai.strikes, 0, "failed movement cannot strike from planned destination")

local exhausted = actor("exhausted")
exhausted.moved = 5
ai, context = fixture({exhausted})
registration:execute(ai, exhausted, {}, malice, context)
eq(#ai.moves, 0, "no movement remains")
eq(#ai.strikes, 0, "no charge extension reaches an otherwise inaccessible target")

local unavailable = actor("unavailable")
unavailable.noGrant = true
ai, context = fixture({unavailable})
registration:execute(ai, unavailable, {}, malice, context)
eq(#ai.pathCalls, 0, "actor without current grant is skipped")

ai.failScoring = true
priorTactics = ai.activeTactics
local ok = pcall(findPlan, ai, unavailable)
eq(ok, false, "scoring error propagates to framework containment")
eq(ai.activeTactics, priorTactics, "scoring error cannot leak actor tactics")
print("dwarf_rappelling_ai_test: passed")
