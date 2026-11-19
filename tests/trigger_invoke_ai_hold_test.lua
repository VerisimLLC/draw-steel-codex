--Run from C:/dev/dmhub: dependencies/lua/bin/lua.exe draw-steel-codex/tests/trigger_invoke_ai_hold_test.lua
--2026-11-16 playtest N3 (report 6BP3KFZ6) and N5. Runs slices of the real source
--against stubs:
--  * TriggeredAbility:HasInvokeBehavior, which decides when a mandatory trigger
--    holds the Monster AI.
--  * CompleteAIReactionFromOptions: a mandatory trigger's marker is written as
--    completed even when this client cannot see it.
--  * MCDMCreature's ConsumeResource override: an invoked or triggered cast's
--    Action/Maneuver does not claim the hero's turn; a hero's own cast still does.
--  * ExecuteInvoke's formula targeting from a remote invocation, which has no
--    options.symbols (it used to crash in table.shallow_copy(nil)).

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local function source(path, first, last)
    local f = assert(io.open(path))
    local s = f:read("*a")
    f:close()
    local start = assert(s:find(first, 1, true), "start marker not found: " .. first)
    local finish = assert(s:find(last, start + #first, true), "end marker not found: " .. last)
    return s:sub(start, finish - 1)
end

--Globals go through stub(): a plain assignment would retype the real global for
--LuaLS across the codex (see LUA_TYPING_REFERENCE.md).
local function stub(name, value) rawset(_G, name, value) end
local function put(t, k, v) rawset(t, k, v) end

local triggeredPath = "draw-steel-codex/DMHub Game Rules/TriggeredAbility.lua"
local invokePath = "draw-steel-codex/DMHub Game Rules/AbilityInvokeAbility.lua"
local creaturePath = "draw-steel-codex/Draw Steel Core Rules/MCDMCreature.lua"

put(table, "shallow_copy", function(t)
    local r = {}
    for k,v in pairs(t) do r[k] = v end
    return r
end)

local placeholder = "__serverTimestamp"
stub("ServerTimestamp", function() return placeholder end)

--A game-typed object: try_get / get_or_add like the engine's.
local GameObject = {}
GameObject.__index = GameObject
function GameObject:try_get(k, default)
    local v = rawget(self, k)
    if v == nil then return default end
    return v
end
function GameObject:get_or_add(k, default)
    local v = rawget(self, k)
    if v == nil then self[k] = default; return default end
    return v
end
local function obj(t) return setmetatable(t or {}, GameObject) end

----------------------------------------------------------------------------
--HasInvokeBehavior
local triggeredAbilityStub = {}
stub("TriggeredAbility", triggeredAbilityStub)
assert(load(source(triggeredPath, "function TriggeredAbility:HasInvokeBehavior()", "ActivatedAbility.OnTypeRegistered = function()")))()

local function trig(behaviors)
    local t = obj{behaviors = behaviors}
    t.HasInvokeBehavior = triggeredAbilityStub.HasInvokeBehavior
    return t
end
check(trig({{typeName = "ActivatedAbilityLimitBehavior"}, {typeName = "ActivatedAbilityInvokeAbilityBehavior"}}):HasInvokeBehavior(),
    "a trigger with an invoke behavior holds the AI")
check(not trig({{typeName = "ActivatedAbilityReplenishBehavior"}}):HasInvokeBehavior(),
    "a trigger with no invoke behavior does not")
check(not trig({}):HasInvokeBehavior(), "a trigger with no behaviors does not")

----------------------------------------------------------------------------
--CompleteAIReactionFromOptions
local completeSrc = source(triggeredPath, "local function CompleteAIReactionFromOptions(", "--A trigger fired by a DispatchEventAndWait event")
local CompleteAIReactionFromOptions = assert(load(completeSrc .. "\nreturn CompleteAIReactionFromOptions"))()

local function makeToken()
    local props = obj{}
    local completed = {}
    function props:CompletePendingAIActivityReaction(activityId, reactionId)
        completed[#completed+1] = {activityId, reactionId}
        self.pendingAIActivityReactions[reactionId].state = "completed"
    end
    local token = {properties = props, valid = true, writes = 0}
    function token:ModifyProperties(options)
        self.writes = self.writes + 1
        options.execute()
    end
    return token, props, completed
end

--A marker this client can see completes through the normal path.
do
    local token, props, completed = makeToken()
    props.pendingAIActivityReactions = {r1 = {activityId = "a1", state = "resolving"}}
    CompleteAIReactionFromOptions(token, {aiActivityId = "a1", aiReactionId = "r1", aiReactionForceComplete = true})
    check(#completed == 1 and completed[1][2] == "r1", "a visible marker completes the normal way")
    check(props.pendingAIActivityReactions.r1.state == "completed", "marker state is completed")
end

--A forced marker this client cannot see is still written as completed (WTUDE5S5).
do
    local token, props, completed = makeToken()
    CompleteAIReactionFromOptions(token, {aiActivityId = "a1", aiReactionId = "r2",
        aiReactionForceComplete = true, aiReactionAbility = "Metakinetic Mastery"})
    check(#completed == 0, "the existence-checked path is not used for a missing forced marker")
    local entry = props.pendingAIActivityReactions and props.pendingAIActivityReactions.r2
    check(entry ~= nil and entry.state == "completed" and entry.activityId == "a1"
        and entry.ability == "Metakinetic Mastery" and entry.timestamp == placeholder,
        "a missing forced marker is written as completed")
end

--Without the force flag a missing marker is left alone, as before.
do
    local token, props, completed = makeToken()
    props.pendingAIActivityReactions = {}
    props.CompletePendingAIActivityReaction = function(self, activityId, reactionId)
        completed[#completed+1] = {activityId, reactionId}
    end
    CompleteAIReactionFromOptions(token, {aiActivityId = "a1", aiReactionId = "r3"})
    check(#completed == 1 and token.writes == 0, "an unforced marker goes to CompletePendingAIActivityReaction only")
end

----------------------------------------------------------------------------
--ConsumeResource / TryClaimTurn
do
    local claims = 0
    stub("mod", {unloaded = false})
    local creatureStub = obj{}
    put(creatureStub, "ConsumeResource", function() end)
    put(creatureStub, "TryClaimTurn", function() claims = claims + 1 end)
    stub("creature", creatureStub)
    stub("CharacterResource", {tableName = "characterResources"})
    stub("dmhub", {GetTable = function()
        return {maneuver = {name = "Maneuver"}, action = {name = "Action"}, surge = {name = "Surges"}}
    end})

    --The base ConsumeResources pays through creature:ConsumeResource, as the real one does.
    local activatedAbilityStub = {}
    put(activatedAbilityStub, "ConsumeResources", function(ability, casterToken, options)
        casterToken.properties:ConsumeResource(ability.cost, "round", 1, ability.name)
    end)
    stub("ActivatedAbility", activatedAbilityStub)

    assert(load(source(creaturePath, "--Above zero while ActivatedAbility:ConsumeResources pays", "--function to claim our turn if we are ready")))()

    local hero = setmetatable({}, {__index = creatureStub})
    local heroToken = {properties = hero}
    local function ability(fields)
        local a = obj(fields)
        a.typeName = fields.typeName or "ActivatedAbility"
        a.ConsumeResources = activatedAbilityStub.ConsumeResources
        return a
    end

    claims = 0
    ability{name = "Knockback", cost = "maneuver"}:ConsumeResources(heroToken, {symbols = {}})
    check(claims == 1, "a hero's own Maneuver still claims the turn")

    claims = 0
    ability{name = "Knockback", cost = "maneuver"}:ConsumeResources(heroToken, {symbols = {invoker = function() end}})
    check(claims == 0, "an invoked cast's Maneuver (symbols.invoker) does not claim the turn")

    claims = 0
    ability{name = "Knockback", cost = "maneuver", invoker = {}}:ConsumeResources(heroToken, {})
    check(claims == 0, "an invoked clone (ability.invoker) does not claim the turn")

    claims = 0
    ability{name = "Reaction", cost = "action", typeName = "TriggeredAbility"}:ConsumeResources(heroToken, {})
    check(claims == 0, "a triggered ability's Action does not claim the turn")

    claims = 0
    ability{name = "Strike", cost = "action"}:ConsumeResources(heroToken, {})
    check(claims == 1, "the guard is released after an invoked payment")

    claims = 0
    ability{name = "Spend", cost = "surge"}:ConsumeResources(heroToken, {})
    check(claims == 0, "other resources never claimed the turn")

    --An error while paying must not leave the guard up.
    local failing = ability{name = "Broken", cost = "maneuver", invoker = {}}
    local saved = hero.ConsumeResource
    hero.ConsumeResource = function() error("boom") end
    local ok, err = pcall(failing.ConsumeResources, failing, heroToken, {})
    hero.ConsumeResource = saved
    check(not ok and tostring(err):find("boom", 1, true) ~= nil, "a payment error is rethrown")
    claims = 0
    ability{name = "Strike", cost = "action"}:ConsumeResources(heroToken, {})
    check(claims == 1, "the guard is released after a payment error")
    stub("mod", nil)
end

----------------------------------------------------------------------------
--ExecuteInvoke formula targeting from a remote invocation (options has no symbols).
do
    local executeSrc = source(invokePath, "function ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(", "ActivatedAbilityInvokeAbilityBehavior.abilityType = \"custom\"")
    local function noop() end
    --A literal table rather than assignments, so LuaLS does not read these as the real globals.
    local env = setmetatable({
        ActivatedAbilityInvokeAbilityBehavior = {SquadSuppressionTurnKey = function() return "k" end},
        ActivatedAbility = {MarkCastProgress = noop, GetActiveCastSnapshot = function() return {} end,
            HasCoroutinesNotInSnapshot = function() return false end, CountActiveCasts = function() return 0 end},
        gamehud = {rollDialog = {valid = false}, actionBarPanel = {valid = false}},
        creature = {GetTokenAIPromptCallback = function() return false end, GetTokenDescription = function(t) return t.name end,
            IsTokenAIControlled = function() return false end},
        print = noop,
        printf = noop,
        GenerateSymbols = function(p) return function() return p end end,
        coroutine = setmetatable({safe_sleep_while = function(pred) pred() end}, {__index = coroutine}),
        dmhub = {Time = function() return 0 end},
        trim = function(str) return str end,
        GoblinScriptTrue = function(v) return v == 1 end,
        --"Target = Invoker": compare the creatures the symbols hold.
        ExecuteGoblinScript = function(formula, lookup)
            assert(formula == "Target = Invoker", "the remote formula reached ExecuteInvoke: " .. tostring(formula))
            if lookup.target == lookup.invoker then return 1 end
            return 0
        end,
    }, {__index = _G})
    assert(load(executeSrc, "ExecuteInvoke", "t", env))()
    local ExecuteInvoke = env.ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke

    local function makeCreature(name)
        local p = obj{name = name}
        function p:LookupSymbol(symbols) return symbols end
        return p
    end
    local monk = {name = "Monk", valid = true, charid = "monk"}
    monk.properties = makeCreature("Monk")
    local muceron = {name = "Demon Muceron 1", valid = true, charid = "muceron"}
    muceron.properties = makeCreature("Demon Muceron 1")
    local bystander = {name = "Orikk", valid = true, charid = "orikk"}
    bystander.properties = makeCreature("Orikk")
    put(env.dmhub, "allTokens", {muceron, monk, bystander})

    local castTargets = nil
    local strike = obj{name = "Melee Free Strike"}
    function strike:RequiresPromptWhenCast() return false end
    function strike:Cast(casterToken, targets, castOptions)
        castTargets = targets
        for _,handler in ipairs(castOptions.OnFinishCastHandlers) do
            handler(self, casterToken, {})
        end
    end

    --Exactly what AbilityInvocation:Invoke passes: its own symbols, and options
    --holding only the targeting formula.
    local remoteSymbols = {spellname = "Escape Grab"}
    local co = coroutine.create(function()
        return ExecuteInvoke(monk, strike, muceron, "formula", remoteSymbols, {targetingFormula = "Target = Invoker"})
    end)
    local ok, err = coroutine.resume(co)
    check(ok, "a remote formula invoke runs without error: " .. tostring(err))
    check(castTargets ~= nil and #castTargets == 1 and castTargets[1].token == monk,
        "the grabber's free strike targets the creature that escaped")
    check(remoteSymbols.allowedtargets ~= nil and remoteSymbols.allowedtargets.monk == true,
        "the player is held to the formula's targets")
end

----------------------------------------------------------------------------
--The remote invocation record carries the formula.
do
    local s = source(invokePath, "local invocation = AbilityInvocation.new{", "invokerid = invokeSource.id,")
    check(s:find("targetingFormula = self:try_get(\"targetingFormula\", \"\")", 1, true) ~= nil,
        "the runOnController invocation record includes targetingFormula")
end

print(string.format("trigger_invoke_ai_hold_test: %d checks passed", checks))
