--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/test_riders_damage_test.lua
--Exercises the "you can deal <type> damage" knack requirement in the pure
--half of TestRiders (grammar, facts, verdicts) and its use in Encounter of
--the Week scene conditions. The engine half (reading damage types off a
--real hero's abilities) is checked in the app.
--Stubs go through rawset with a non-literal name so LuaLS does not read
--them as new definitions of the real globals.
local function stub(name, value)
    rawset(_G, name, value)
end
if rawget(_G, "dmhub") == nil then
    stub("dmhub", {
        GetModLoading = function() return {} end,
        Error = function(message) print(message) end,
    })
end
dofile("DMHub Utils/UIText.lua")
dofile("EncounterOfTheWeek/EncounterText.lua")
dofile("EncounterOfTheWeek/EncounterAuthoringText.lua")
dofile("DMHub Game Rules/TestRiders.lua")
dofile("EncounterOfTheWeek/EncounterScript.lua")

local passed = 0
local function check(condition, message)
    if not condition then
        error("FAILED: " .. tostring(message), 2)
    end
    passed = passed + 1
end

--"kind=name|kind=name" for a requirement's alternatives, to compare in one go.
local function Kinds(text)
    local parts = {}
    for _, alt in ipairs(TestRiders.ParseRequirement(text).alternatives) do
        parts[#parts + 1] = string.format("%s=%s", alt.kind, alt.name)
    end
    return table.concat(parts, "|")
end

local function Texts(text)
    local parts = {}
    for _, alt in ipairs(TestRiders.ParseRequirement(text).alternatives) do
        parts[#parts + 1] = alt.text
    end
    return table.concat(parts, "|")
end

local function Met(text, facts)
    return TestRiders.RequirementMet(TestRiders.ParseRequirement(text), facts)
end

--- the grammar --------------------------------------------------------------
check(Kinds("you can deal fire damage") == "damage=fire", "you can deal fire damage")
check(Kinds("You can deal Fire damage.") == "damage=fire", "case and a full stop are ignored")
check(Kinds("you can deal fire damage or deal holy damage") == "damage=fire|damage=holy", "a second 'deal X damage' clause")
check(Texts("you can deal fire damage or deal holy damage") == "you can deal fire damage|you can deal holy damage",
    "the bare clause is spelled out for the chip")
check(Kinds("you can deal fire or holy damage") == "damage=fire|damage=holy", "one 'damage' shared by two types")
check(Texts("you can deal fire or holy damage") == "you can deal fire damage|you can deal holy damage",
    "both shared-damage clauses read as sentences")
check(Kinds("you can deal fire, cold or holy damage") == "damage=fire|damage=cold|damage=holy", "a list of three types")
check(Kinds("you can deal fire damage, cold or holy damage") == "damage=fire|damage=cold|damage=holy",
    "bare names after a damage clause inherit it")
check(Kinds("you can deal fire") == "damage=fire", "'deal fire' with no 'damage' for a real type")
check(Kinds("you can teleport or deal fire damage") == "capability=teleport|damage=fire", "a capability, then damage")
check(Kinds("you can deal fire damage or teleport") == "damage=fire|capability=teleport", "damage, then a bare capability")
check(Kinds("you can deal fire damage or you are a Dwarf") == "damage=fire|kindred=dwarf", "damage, then another kind")
check(Kinds("you can deal with goblins") == "unknowncapability=deal with goblins", "'deal with' is not damage")
check(Kinds("you can deal sonic damage; you speak Caelian") == "damage=sonic|language=caelian", "semicolons separate too")

--- problems -----------------------------------------------------------------
check(#TestRiders.RequirementProblems(TestRiders.ParseRequirement("you can deal holy damage")) == 0, "a real type has no problem")
check(not TestRiders.ParseRequirement("you can deal holy damage").unrecognized, "a real type is recognized")
local bad = TestRiders.ParseRequirement("you can deal fire or radiant damage")
local problems = TestRiders.RequirementProblems(bad)
check(bad.unrecognized, "an unknown damage type marks the requirement unrecognized")
check(#problems == 1 and string.find(problems[1], "'radiant' is not a damage type", 1, true) ~= nil
    and string.find(problems[1], "acid, cold, corruption, fire, holy, lightning, poison, psychic, sonic", 1, true) ~= nil,
    "an unknown damage type is reported with the known ones: " .. tostring(problems[1]))
check(Kinds("you can deal radiant") == "unknowncapability=deal radiant", "'deal <word>' with no 'damage' needs a real type")

--- facts and verdicts ---------------------------------------------------------
local elementalist = { damage = { fire = "Bifurcated Incineration", acid = "Hurl Element" } }
local ok, why = Met("you can deal fire damage", elementalist)
check(ok and why == "you can deal fire damage (Bifurcated Incineration)", "the chip names the ability: " .. tostring(why))
ok, why = Met("you can deal holy damage or deal acid damage", elementalist)
check(ok and why == "you can deal acid damage (Hurl Element)", "the alternative that met it: " .. tostring(why))
check(not Met("you can deal holy damage", elementalist), "a type no ability deals is unmet")
check(not Met("you can deal radiant damage", { damage = { radiant = "Nonsense" } }), "an unknown type is never met")
ok, why = Met("you can deal holy damage", { damage = { holy = true } })
check(ok and why == "you can deal holy damage", "a plain true fact meets it without a source")
check(not Met("you can deal fire damage", {}), "no damage facts at all")
check(not Met("you can deal fire damage", { immunity = { fire = 5 } }), "a fire immunity is not fire damage")

local rider = TestRiders.ParseRider("|Edge: you can deal fire damage or deal holy damage")
local verdict = TestRiders.Evaluate({ rider }, { damage = { holy = "Blessed Light" } })
check(verdict.boons == 1 and verdict.applied[1].why == "you can deal holy damage (Blessed Light)", "an edge rider applies")
local rows = TestRiders.DescribeRows({ rider }, verdict)
check(rows[1].state == "met" and rows[1].text == "you can deal holy damage (Blessed Light)", "the row shows why")
local allow = TestRiders.ParseRider("|Allow: you can deal holy damage")
check(TestRiders.Evaluate({ allow }, elementalist).allowed == false, "a secret option stays hidden")
check(TestRiders.Evaluate({ allow }, { damage = { holy = "Judgment" } }).unlockedBy == "you can deal holy damage (Judgment)",
    "a secret option unlocks")

--- rules text ------------------------------------------------------------------
local function TypesIn(text, patron)
    local found = {}
    TestRiders.DamageTypesInText(text, function(t) found[#found + 1] = t end, patron)
    return table.concat(found, ",")
end
check(TypesIn("2 + R fire damage; push 2") == "fire", "a tier's type")
check(TypesIn("3 corruption damage and 2 Holy damage") == "corruption,holy", "two types in one tier")
check(TypesIn("5 + M damage") == "", "untyped damage counts for nothing")
check(TypesIn("the target has fire weakness 5") == "", "a weakness is not damage")
check(TypesIn("4 patron damage", "Lightning") == "lightning", "patron damage is the patron's type")
check(TypesIn("4 patron damage", nil) == "", "patron damage with no patron")
check(TypesIn(nil) == "", "no text")

--- knack headings and scene conditions ----------------------------------------
check(EncounterScript.ParseKnackHeading("If you can deal fire damage") == "you can deal fire damage", "#### If you can deal fire damage")
check(EncounterScript.ParseKnackHeading("If PC can deal fire damage") == "you can deal fire damage", "#### If PC can deal fire damage")
local c1 = EncounterScript.ParseCondition("PC can deal fire damage")
check(c1 ~= nil and c1.op == "req" and c1.text == "you can deal fire damage", "if PC can deal fire damage then")
check(Met(c1.text, elementalist), "the scene condition is met by the facts")
local c2 = EncounterScript.ParseCondition("PC can deal fire damage or PC can deal holy damage")
check(c2 ~= nil and c2.op == "or" and c2.a.text == "you can deal fire damage" and c2.b.text == "you can deal holy damage",
    "two scene conditions joined by or")

print(string.format("test_riders_damage_test: %d checks passed", passed))
