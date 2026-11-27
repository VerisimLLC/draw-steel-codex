--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/block_tiers_test.lua
--Checks the power roll tier grammar in DMHub Utils/BlockTiers.lua: what each
--kind of tier part reads as, that an unedited tier writes back byte-identical,
--and how an edited segment is written.
--Inside DMHub (no io), send this file's text to execute_lua: it then tests the
--loaded Block and puts the real condition and effect lookups back afterwards.

local inApp = rawget(_G, "Block") ~= nil and Block.ParseTier ~= nil

if not inApp then
    local function readSource(path)
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a"):gsub("\r\n", "\n")
        f:close()
        return source
    end
    local errors = {}
    rawset(_G, "dmhub", {
        GetModLoading = function() return { unloaded = false } end,
        Error = function(message) errors[#errors + 1] = message end,
    })
    assert(load(readSource("DMHub Utils/Block.lua"), "Block.lua"))()
    assert(load(readSource("DMHub Utils/BlockTiers.lua"), "BlockTiers.lua"))()
end

--Small fixed tables, so the test does not depend on the compendium.
local savedLookups = Block.TierLookups
Block.TierLookups = {
    conditions = function()
        return {
            { id = "c-prone", name = "Prone" },
            { id = "c-slowed", name = "Slowed" },
            { id = "c-grabbed", name = "Grabbed" },
            { id = "c-taunted", name = "Taunted" },
            { id = "c-weakened", name = "Weakened" },
        }
    end,
    riders = function()
        return { { id = "r-cannot-stand", condition = "c-prone", words = "and can't stand" } }
    end,
    effects = function()
        return { { id = "e-jaws", name = "Jaws of Death" } }
    end,
}
Block.TierLookupsChanged()

local failures = 0
local function check(label, ok, detail)
    if not ok then
        failures = failures + 1
        print("FAIL " .. label .. (detail and (": " .. detail) or ""))
    end
end

--Each tier, the kinds its parts read as, and nothing else: it must write back unchanged.
local cases = {
    { "3 + M damage; slide 2", { "damage", "forced" } },
    { "2 damage; M < WEAK, slowed (save ends)", { "damage", "potency" } },
    { "9 + R fire damage", { "damage" } },
    { "{2*Reason} damage (added)", { "formulaDamage" } },
    { "5 + M or A damage", { "kitDamage" } },
    { "3 + M, R, I, or P holy damage", { "kitDamage" } },
    { "vertical push straight up 5; vertical pull 3", { "forced", "forced" } },
    { "slide {Might}", { "forced" } },
    { "Each target gains one surge", { "surges" } },
    { "#Director loses 2 Malice", { "note" } },
    { "8 damage; M < average, prone and can't stand (save ends)", { "damage", "potency" } },
    { "taunted (EoT)", { "condition" } },
    { "jaws of death (save ends)", { "effect" } },
    { "15 + M damage; M < Average grabbed and prone", { "damage", "potency" } },
    { "push 4 and prone", { "both" } },
    { "M < {Strong}, grabbed", { "potency" } },
    { "The Director tells you one of an NPC's motivations.", { "todo" } },
    { "10 damage-", { "todo" } },
    { "6 damage;;push 2;", { "damage", "empty", "forced", "empty" } },
    { "  2 damage ;  push 1.  ", { "damage", "forced" } },
    { "", { "empty" } },
}

for _, case in ipairs(cases) do
    local text, kinds = case[1], case[2]
    local segments = Block.ParseTier(text)
    local back = Block.CompileTier(segments)
    check("round trip \"" .. text .. "\"", back == text, "got \"" .. back .. "\"")
    local got = {}
    for i, segment in ipairs(segments) do
        got[i] = segment.kind
    end
    check("kinds of \"" .. text .. "\"", table.concat(got, ",") == table.concat(kinds, ","), table.concat(got, ","))
end

--Values the rules read.
local damage = Block.ParseTier("3 + M fire damage")[1].values
check("damage values", damage.base == "3" and damage.characteristic == "M" and damage.damageType == "fire" and damage.added == false)
local potency = Block.ParseTier("M < WEAK, slowed (save ends)")[1].values
check("potency values", potency.characteristic == "M" and potency.threshold == "weak" and potency.inner.kind == "condition")
check("potency inner condition", potency.inner.values.condition == "c-slowed" and potency.inner.values.duration == "save ends")
local rider = Block.ParseTier("prone and can't stand (EoT)")[1].values
check("rider values", rider.condition == "c-prone" and rider.rider == "r-cannot-stand" and rider.duration == "EoT")
check("todo keeps a potency's words", Block.TierSegmentHasTodo(Block.ParseTier("M < weak, the push is vertical")[1]))

--Edits: a changed segment is written by its rule; unchanged neighbours keep their spelling.
local segments = Block.ParseTier("3 + M damage;  slide 2")
segments[1].values.base = "5"
check("edit damage", Block.CompileTier(segments) == "5 + M damage;  slide 2", Block.CompileTier(segments))

segments = Block.ParseTier("2 damage; M<WEAK, slowed (save ends)")
segments[2].values.inner.values.duration = "EoT"
check("edit inside potency keeps its spelling", Block.CompileTier(segments) == "2 damage; M<WEAK, slowed (EoT)", Block.CompileTier(segments))
segments[2].values.threshold = "strong"
check("edit potency threshold", Block.CompileTier(segments) == "2 damage; M < strong, slowed (EoT)", Block.CompileTier(segments))

segments = Block.ParseTier("push 2.")
segments[1].values.movement = "pull"
check("edit keeps the period", Block.CompileTier(segments) == "pull 2.", Block.CompileTier(segments))

segments = Block.ParseTier("4 damage")
segments[#segments + 1] = { kind = "condition", values = { condition = "c-prone", rider = "r-cannot-stand", duration = "save ends" } }
check("new segment", Block.CompileTier(segments) == "4 damage; prone and cannot stand (save ends)", Block.CompileTier(segments))

--A rule registered again with the same id replaces the old one.
local surges = assert(Block.GetTierRule("surges"))
Block.RegisterTierRule{ id = "surges", order = 60, match = function() return nil end, compile = surges.compile }
check("replaced rule is used", Block.ParseTier("the target gains two surges")[1].kind == "todo")
Block.RegisterTierRule(surges)
check("restored rule", Block.ParseTier("the target gains two surges")[1].kind == "surges")

Block.TierLookups = savedLookups
Block.TierLookupsChanged()

if failures == 0 then
    print("block_tiers_test: all passed")
else
    print("block_tiers_test: " .. failures .. " failed")
end
if not inApp and failures > 0 then
    os.exit(1)
end
