--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/power_roll_text_tiers_test.lua
--A power modifier's addText / replaceText is split into 3 tiers, but an
--Encounter of the Week montage test has 4 (the 4th is the critical line).
--Tiers past the third must reuse the tier 3 text instead of passing nil
--into AppendTieredText / string.replace_insensitive.
--Loads the real BreakTextIntoTiers, AppendTieredText and the addText /
--replaceText block of modifyRollProperties, plus the real string.split and
--string.replace_insensitive from Utils.
local function stub(name, value)
    rawset(_G, name, value)
end

local function readSource(path)
    local f = assert(io.open(path, "rb"))
    local source = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return source
end

local function between(source, startText, stopText, label)
    local start = assert(source:find(startText, 1, true), label .. ": start not found")
    local stop = assert(source:find(stopText, start, true), label .. ": stop not found")
    return source:sub(start, stop - 1)
end

local utils = readSource("DMHub Utils/Utils.lua")
assert(load(between(utils, "function string.replace_insensitive(", "function string.upper_first(", "replace_insensitive"), "Utils replace_insensitive"))()
assert(load(between(utils, "function string.split (", "function string.split_allow_duplicates(", "split"), "Utils split"))()

--Engine trim returns non-strings unchanged (Definitions/lua-core.lua).
stub("trim", function(s) if type(s) ~= "string" then return s end return (s:match("^%s*(.-)%s*$")) end)
stub("StringInterpolateGoblinScript", function(s) return s end)

--Only the "a // b // c" form is used by this test; the numeric and damage
--patterns never match plain rider text.
local function matchGroups(text, pattern)
    if pattern:find("tier1>.*?)(\\s*//", 1, true) then
        local a, b, c = text:match("^(.-)%s*//%s*(.-)%s*//%s*(.*)$")
        if a ~= nil then
            return { tier1 = a, tier2 = b, tier3 = c }
        end
    end
    return nil
end
stub("regex", { MatchGroups = matchGroups })

local source = readSource("Draw Steel Core Rules/MCDModifyPowerRolls.lua")
local helpers = between(source, "local function BreakTextIntoTiers(text)", "local g_powerRollsAbilityAdditionalSymbols", "helpers")
local block = between(source, "        local addTextValue = self:try_get(\"addText\", \"\")", "    end,\n\n    modifyPowerRollCasting", "text block")

local CharacterModifierStub = { ResolveAddTextChoice = function() return "" end }
local chunk = helpers .. "\nreturn function(self, rollProperties, lookupFunction, CharacterModifier)\n" .. block .. "\nend\n"
local applyText = assert(load(chunk, "modifyRollProperties text block"))()

local function modifier(t)
    t.try_get = function(self, k, d) if self[k] == nil then return d end return self[k] end
    t.has_key = function(self, k) return self[k] ~= nil end
    return t
end

local passed = 0
local function check(condition, message)
    if not condition then
        error("FAILED: " .. tostring(message), 2)
    end
    passed = passed + 1
end

local function run(mod, tiers)
    local props = { tiers = tiers }
    local ok, err = pcall(applyText, mod, props, nil, CharacterModifierStub)
    check(ok, "applying the modifier text must not error: " .. tostring(err))
    return props.tiers
end

--addText, single text, 4-tier montage roll.
local tiers = run(modifier{ addText = "rider" }, { "Fail", "Partial", "Success", "Critical" })
check(tiers[1] == "Fail; rider", "tier 1 addText: " .. tostring(tiers[1]))
check(tiers[3] == "Success; rider", "tier 3 addText: " .. tostring(tiers[3]))
check(tiers[4] == "Critical; rider", "tier 4 must get the tier 3 addText: " .. tostring(tiers[4]))

--addText, per-tier text, 4-tier montage roll.
tiers = run(modifier{ addText = "one // two // three" }, { "A", "B", "C", "D" })
check(tiers[2] == "B; two", "tier 2 tiered addText: " .. tostring(tiers[2]))
check(tiers[4] == "D; three", "tier 4 must get the tier 3 tiered addText: " .. tostring(tiers[4]))

--addText on a normal 3-tier roll is unchanged.
tiers = run(modifier{ addText = "one // two // three" }, { "A", "B", "C" })
check(#tiers == 3 and tiers[1] == "A; one" and tiers[3] == "C; three", "3-tier addText unchanged")

--replaceText, per-tier text, 4-tier montage roll.
tiers = run(modifier{ replacePattern = "push", replaceText = "slide 1 // slide 2 // slide 3" },
    { "push", "push", "push", "push" })
check(tiers[1] == "slide 1", "tier 1 replaceText: " .. tostring(tiers[1]))
check(tiers[4] == "slide 3", "tier 4 must get the tier 3 replaceText: " .. tostring(tiers[4]))

print(string.format("power_roll_text_tiers: %d checks passed", passed))
