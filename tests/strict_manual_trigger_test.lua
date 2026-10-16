--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/strict_manual_trigger_test.lua
--Under Strictly Enforce Action Economy, a player's manual copy of a real
--triggered action is refused when the game prompts for it (6TTFJWFP).
local file = assert(io.open("Draw Steel Core Rules/MCDMActivatedAbility.lua", "r"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local first = "--Under Strictly Enforce Action Economy, a player cannot fire"
local start = assert(source:find(first, 1, true))
local finish = assert(source:find("--Tokens on the map with granted abilities", start, true))

local function try_get(self, key, default)
    local value = rawget(self, key)
    if value == nil then return default end
    return value
end

local baseMessage = nil
ActivatedAbility = {}
function ActivatedAbility:AbilityFilterFailureMessage() return baseMessage end
CharacterResource = {triggerResourceId = "trigger", freeTriggeredActionResourceId = "freetrigger"}
local strict = true
function StrictActionEconomyEnforced() return strict end
local playerControlled = true
dmhub = {LookupToken = function() return {playerControlled = playerControlled} end}

assert(load(source:sub(start, finish - 1)))()

local function ability(fields)
    fields.try_get = try_get
    fields.typeName = fields.typeName or "ActivatedAbility"
    fields.AbilityFilterFailureMessage = ActivatedAbility.AbilityFilterFailureMessage
    return fields
end
local triggers = {}
local hero = {GetTriggeredAbilities = function() return triggers end}

local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function blocked(a) return a:AbilityFilterFailureMessage(hero) ~= nil end

--Hesitation is Weakness: an authored Trigger-category copy with an automatic twin.
local hesitation = ability{name = "Hesitation is Weakness", categorization = "Trigger", actionResourceId = "freetrigger"}
check(not blocked(hesitation), "no automatic twin: the manual trigger stays usable")
triggers = {{ability = {typeName = "TriggeredAbility", name = "hesitation is weakness"}}}
check(blocked(hesitation), "automatic twin: the manual copy is refused")

strict = false
check(not blocked(hesitation), "strict rules off: nothing is refused")
strict = true
playerControlled = false
check(not blocked(hesitation), "a token no player controls is not bound")
playerControlled = true

--a generated manual version (hasManualVersion) always has its trigger.
local overwatch = ability{name = "Overwatch", manualVersionOfTrigger = true, actionResourceId = "trigger"}
check(blocked(overwatch), "generated manual copy of a Trigger action is refused")

--manual helper buttons spend no triggered action (Tactician Mark).
local mark = ability{name = "Mark", manualVersionOfTrigger = true, actionResourceId = "none"}
check(not blocked(mark), "manual helper with no triggered action stays usable")

--the prompt's own cast is the TriggeredAbility.
local prompt = ability{name = "Hesitation is Weakness", typeName = "TriggeredAbility", categorization = "Trigger", actionResourceId = "freetrigger"}
check(not blocked(prompt), "the prompt's TriggeredAbility is never refused")

--an ordinary main action is untouched.
local strike = ability{name = "Strike", categorization = "Signature Ability", actionResourceId = "trigger"}
check(not blocked(strike), "a non-trigger ability is untouched")

--an existing filter failure still wins.
baseMessage = "You are grabbed"
check(hesitation:AbilityFilterFailureMessage(hero) == "You are grabbed", "the authored filter message comes first")

print("strict manual trigger: " .. checks .. " checks passed")
