-- Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_free_strike_reach_test.lua
-- The generic free strikes both score 0.2; the one that does not suit the
-- monster's signature reach scores a little less, so a melee monster charges
-- instead of plinking from range (and a ranged one stays at range).
local function read(path)
    local f = assert(io.open(path))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local function section(source, first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end

local moves = {}
MonsterAI = {
    RegisterMove = function(_, entry) moves[entry.id] = entry end,
    TargetStaminaBias = function() return 0 end,
    IsMinionSignatureAbility = function(a) return a.main == true end,
}
dmhub = {GetModLoading = function() return {} end}
assert(load(section(read("Monster AI/MonsterAI.lua"),
    "function MonsterAI.SignatureReach", "--The turn can move to another entry")))()
assert(load(section(read("Monster AI/MonsterAIMonsters.lua"),
    "local mod = dmhub.GetModLoading()", "local function GetKnockbackScoringFunction")))()

local charge = assert(moves["Charge and Free Strike"])
local ranged = assert(moves["Ranged Free Strike"])
local ai = {FindBestMoveToUseStrike = function() return {str = "here"} end}

local function monster(signatureKeywords, main)
    local abilities = {}
    if signatureKeywords ~= nil then
        local signature = {categorization = "Signature Ability", main = main ~= false, keywords = signatureKeywords}
        function signature:HasKeyword(k) return self.keywords[k] == true end
        abilities[1] = signature
    end
    return {properties = {GetActivatedAbilities = function() return abilities end}}
end

local function scores(token)
    return charge.score(charge, ai, token, {}).score, ranged.score(ranged, ai, token, {}).score
end

local c, r = scores(monster({Melee = true}))
assert(c > r, "a melee-signature monster prefers the charge free strike")
assert(c <= charge.maxScore and r <= ranged.maxScore, "scores stay within maxScore")

c, r = scores(monster({Ranged = true}))
assert(r > c, "a ranged-signature monster prefers the ranged free strike")

c, r = scores(monster({Melee = true, Ranged = true}))
assert(c == 0.2 and r == 0.2, "a melee-and-ranged signature leaves both at 0.2")

c, r = scores(monster(nil))
assert(c == 0.2 and r == 0.2, "no signature leaves both at 0.2")

--a main-action signature wins over a maneuver mis-tagged as one.
local token = monster({Ranged = true}, false)
local melee = {categorization = "Signature Ability", main = true, keywords = {Melee = true}}
function melee:HasKeyword(k) return self.keywords[k] == true end
table.insert(token.properties:GetActivatedAbilities(), melee)
assert(MonsterAI.SignatureReach(token) == "melee", "the main-action signature decides")

ai.FindBestMoveToUseStrike = function() return nil end
assert(charge.score(charge, ai, monster({Melee = true}), {}) == nil, "no target, no plan")

print("AI free strike reach tests passed")
