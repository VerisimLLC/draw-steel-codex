--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_end_effect_test.lua
--Exercises the Monster AI's End Effect decision and its purge-dialog chooser
--(the "Ending effects" section of Monster AI/MonsterAIPrompts.lua) with stubs.
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = last and assert(source:find(last, start + #first, true)) or #source + 1
    return source:sub(start, finish - 1)
end
local function try_get(self, key, default)
    if self[key] == nil then return default end
    return self[key]
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

function cond(a, b, c) if a then return b else return c end end
function table.resize_array(t, n)
    for i = #t, n + 1, -1 do t[i] = nil end
end

--Conditions and ongoing effects, keyed by id.
local conditions = {}
for id, name in pairs({dazed = "Dazed", weakened = "Weakened", slowed = "Slowed", prone = "Prone", judged = "Judged"}) do
    conditions[id] = {name = name, try_get = try_get}
end
conditions.hidden = {name = "Hidden", buffType = "buff", try_get = try_get}
local effects = {
    blessing = {name = "Blessing", buffType = "buff", try_get = try_get},
    curse = {name = "Curse", try_get = try_get},
    frightEffect = {name = "Frightful", condition = "dazed", try_get = try_get},
}

CharacterCondition = {tableName = "charConditions"}
dmhub = {
    GetTable = function(name)
        if name == CharacterCondition.tableName then return conditions end
        if name == "characterOngoingEffects" then return effects end
    end,
}

local aiControlled = {}
creature = {IsTokenAIControlled = function(charid) return aiControlled[charid] == true end}

local registeredTriggers = {}
MonsterAI = {
    RollsForCreature = function() return false end,
    TokenLogName = function(token) return token.charid end,
}
function MonsterAI:RegisterTrigger(args) registeredTriggers[args.id] = args end
ActivatedAbilityPurgeEffectsBehavior = {}

local chunk = section("Monster AI/MonsterAIPrompts.lua", "-- Ending effects:")
assert(load(chunk, "ending effects section"))()

local function Token(charid, side, hp, maxhp)
    local token = {charid = charid, id = charid, valid = true, side = side}
    token.properties = {
        hp = hp, maxhp = maxhp, triggered = {},
        CurrentHitpoints = function(self) return self.hp end,
        MaxHitpoints = function(self) return self.maxhp end,
        GetTriggeredAbilities = function(self) return self.triggered end,
    }
    function token:IsFriend(other) return self.side == other.side end
    return token
end

local function ConditionItem(id) return {type = "condition", conditionId = id, displayName = conditions[id].name} end
local function EffectItem(id) return {type = "effect", effectId = id, displayName = effects[id].name} end

--Stub tokens and items stand in for the real types, so call through untyped locals.
local chooser = ActivatedAbilityPurgeEffectsBehavior.aiChooser --[[@as any]]
local decide = MonsterAI.EndEffectDecision --[[@as any]]
local one = {purgeType = "one"}

--A creature the AI is not driving gets the normal dialog.
local demon = Token("demon", "monsters", 100, 120)
check(chooser(one, {{token = demon, items = {ConditionItem("dazed")}}}, nil, demon, nil) == nil,
    "an undriven caster falls through to the dialog")

--A "one" purge on itself ends the worst condition only.
aiControlled.demon = true
local ok, selections = chooser(one, {{token = demon, items = {
    ConditionItem("slowed"), ConditionItem("weakened"), ConditionItem("prone")}}}, nil, demon, nil)
check(ok == true and #selections.demon == 1 and selections.demon[1].conditionId == "weakened",
    "the worst condition (weakened) is chosen")

--An effect standing in for a condition is rated as that condition.
ok, selections = chooser(one, {{token = demon, items = {ConditionItem("weakened"), EffectItem("frightEffect")}}}, nil, demon, nil)
check(ok and selections.demon[1].effectId == "frightEffect", "an effect carrying dazed outranks weakened")

--Helpful items are never ended on itself; with nothing harmful it passes.
ok, selections = chooser(one, {{token = demon, items = {ConditionItem("hidden"), EffectItem("blessing")}}}, nil, demon, nil)
check(ok == false, "nothing harmful to end: pass")

--On an enemy, the AI strips buffs rather than debuffs.
local hero = Token("hero", "heroes", 30, 30)
ok, selections = chooser(one, {{token = hero, items = {EffectItem("curse"), EffectItem("blessing")}}}, nil, demon, nil)
check(ok and selections.hero[1].effectId == "blessing", "an enemy's blessing is stripped, not its curse")

--A "chosen" purge takes the best items across targets, capped by the purge.
local ally = Token("ally", "monsters", 30, 30)
ok, selections = chooser({purgeType = "chosen"}, {
    {token = demon, items = {ConditionItem("prone"), ConditionItem("slowed")}},
    {token = ally, items = {ConditionItem("dazed")}},
}, nil, demon, 2)
check(ok and #selections.ally == 1 and #selections.demon == 1 and selections.demon[1].conditionId == "slowed",
    "chosen purge keeps the two worst: dazed and slowed")

--End Effect decision.
local function EndEffectOn(token, items, cost)
    local behavior = {
        typeName = "ActivatedAbilityPurgeEffectsBehavior",
        EvalDamageToSelf = function() return tostring(cost) end,
        CollectPurgeItems = function(self, target) if #items == 0 then return nil end return {token = target, items = items} end,
    }
    token.properties.triggered = {{ability = {name = "End Effect", guid = "end-effect", behaviors = {behavior}, try_get = try_get}}}
    return {abilityGuid = "end-effect", abilityName = "End Effect"}
end

local trigger = EndEffectOn(demon, {ConditionItem("weakened")}, 5)
check(decide(demon, trigger).activate, "healthy and weakened: pay 5 to end it")

trigger = EndEffectOn(demon, {ConditionItem("judged")}, 5)
check(decide(demon, trigger).dismiss, "an unremarkable debuff is not worth Stamina")

demon.properties.hp = 22
trigger = EndEffectOn(demon, {ConditionItem("dazed")}, 5)
check(decide(demon, trigger).dismiss, "22 Stamina cannot spare 5 with an 18 reserve")

demon.properties.hp = 24
check(decide(demon, trigger).activate, "24 Stamina can spare 5")

local bloodlord = Token("bloodlord", "monsters", 19, 40)
trigger = EndEffectOn(bloodlord, {ConditionItem("dazed")}, 10)
check(decide(bloodlord, trigger).dismiss, "10 damage needs at least 10 left after paying")

demon.properties.triggered = {}
check(decide(demon, {abilityGuid = "x", abilityName = "End Effect"}) == nil,
    "no purge behind the trigger: left to the Director")

check(registeredTriggers["End Effect"] ~= nil and registeredTriggers["End Effect"].monsters == nil,
    "End Effect is registered for every monster")

print(string.format("ai_end_effect_test: %d checks passed", checks))
