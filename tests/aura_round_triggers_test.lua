--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/aura_round_triggers_test.lua.
--Load the production methods without initializing the engine-dependent module.
local f = assert(io.open("DMHub Game Rules/Creature.lua", "r"))
local source = f:read("*a")
f:close()
local first = assert(source:find("function creature:GetTurnId()", 1, true))
local last = assert(source:find("--Remove ongoing effects that expire on a rest", first, true))
creature = {}
local roundId, turnId = "combat-1", "turn-1"
dmhub = {
    initiativeQueue = {GetRoundId = function() return roundId end},
    LookupToken = function(c) return c.token end,
}
GameHud = {instance = {tokenInfo = {initiativeQueue = {GetTurnId = function() return turnId end}}}}
assert(load(source:sub(first, last - 1), "@Creature-aura-methods"))()

local function subject()
    local c = setmetatable({}, {__index = creature})
    function c:try_get(key, default)
        local value = rawget(self, key)
        if value == nil then return default end
        return value
    end
    c.token = {valid = true, uploadable = true, ModifyProperties = function(_, args) args.execute() end}
    return c
end
local function area(id, triggers)
    local aura = {triggers = {}}
    for _, event in ipairs(triggers) do
        aura.triggers[#aura.triggers + 1] = {trigger = event, ability = {event = event}}
    end
    function aura:try_get(key, default)
        local value = rawget(self, key)
        if value == nil then return default end
        return value
    end
    function aura:CreaturePassesFilter() return true end
    function aura:GetSimplePowerRollTrigger() return nil end
    local info = {auraInstance = {guid = id, aura = aura}, counts = {}}
    function info.auraInstance:FireTriggeredAbility(ability, c)
        local key = ability.event
        info.counts[key] = (info.counts[key] or 0) + 1
        info.lastTarget = c
    end
    return info
end
local function eq(a, b, message) assert(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local c = subject()
local a = area("line-a", {"onfirstenterround", "targetstartturnaura"})
a.token = c.token
eq(c:EnterAura(a, false, true), true, "start turn fires")
eq(c:EnterAuraHaltsMovement(a), true, "start turn leaves entry available")
eq(c:EnterAura(a), true, "first entry after turn start")
eq(c:EnterAura(a), false, "reentry suppressed")
turnId = "turn-2"
eq(c:EnterAura(a), false, "another creature's turn does not reset round")
eq(c:EnterAura(a, false, true), true, "start turn after entry still fires")
eq(a.counts.targetstartturnaura, 2, "both starts resolved")
eq(a.counts.onfirstenterround, 1, "one entry this round")
eq(c:EnterAuraHaltsMovement(a), false, "consumed entry does not halt")
local b = area("line-b", {"onfirstenterround", "targetstartturnaura"})
eq(c:EnterAura(b), true, "independent overlapping line")
local other = subject()
eq(other:EnterAura(a), true, "independent target")
roundId = "combat-2"
eq(c:EnterAura(a), true, "new round resets entry")
eq(c:EnterAura(a, true, true), false, "adjacency is not inside")
local noStart = area("entry-only", {"onfirstenterround"})
eq(c:EnterAura(noStart, false, true), false, "entry trigger excludes turn start")
eq(c:EnterAura(noStart), true, "excluded turn start leaves entry")
roundId = nil
eq(c:EnterAura(a), true, "outside combat entry")
eq(c:EnterAura(a), true, "outside combat has no round gate")
roundId = "combat-3"
local legacy = area("legacy", {"onenter"})
legacy.token = c.token
eq(c:EnterAura(legacy), true, "legacy entry")
eq(c:EnterAura(legacy, false, true), false, "legacy shared turn gate preserved")
turnId = "turn-3"
eq(c:EnterAura(legacy, false, true), true, "legacy new turn")
local mixed = area("mixed", {"onenter", "onfirstenterround", "targetstartturnaura"})
mixed.token = c.token
eq(c:EnterAura(mixed, false, true), true, "mixed turn start")
eq(c:EnterAura(mixed), true, "mixed entry bypasses legacy consumed gate")
eq(mixed.counts.onenter, 1, "mixed preserves legacy frequency")
eq(mixed.counts.onfirstenterround, 1, "mixed first entry")
print("Aura round trigger regressions passed (24 assertions).")
