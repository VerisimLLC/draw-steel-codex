-- Run from codex root: ../dependencies/lua/bin/lua.exe tests/ai_plan_preview_test.lua
-- The plan preview of a dual melee/ranged strike (EW6UP8BY): it must show the
-- targets the move planned with its ranged variation, and the card must be the
-- variation the cast will use, not the creature's melee/ranged stance.
local f = assert(io.open("Monster AI/MonsterAI.lua"))
local source = f:read("*a"):gsub("\r\n", "\n"); f:close()
local function section(first, last)
    local start = assert(source:find(first, 1, true))
    return source:sub(start, assert(source:find(last, start + #first, true)) - 1)
end
local function noop() end

MonsterAI = {TokenIsLiveCombatant = function(t) return t ~= nil and t.valid end}
dmhub = {TokensAreFriendly = function() return false end, screenDimensionsBelowTitlebar = {y = 1000}}
PREVIEW_CARD_WIDTH = 346
local shownCard = nil
CreateAbilityTooltip = function(ability)
    shownCard = ability
    return {MakeNonInteractiveRecursive = noop}
end
--PreviewName and PreviewTargets are file locals, so they load in the same chunk.
local PreviewAbilityCard = assert(load(section("local function PreviewName(token)", "--Answer the preview on screen")
    .. section("local function PreviewAbilityCard(abilityInfo)", "local function BuildPlanPreviewPanel")
    .. section("--- Which half of a dual melee/ranged ability", "--Area target types the preview can rebuild")
    .. "return PreviewAbilityCard"))()

--Tokens are engine userdata; PreviewTargets checks for that, so fake tokens report it.
local realType = type
type = function(value)
    if realType(value) == "table" and rawget(value, "fakeToken") then
        return "userdata"
    end
    return realType(value)
end
local function loc(x) return {x = x, str = tostring(x)} end
local function token(name, x)
    return {fakeToken = true, valid = true, name = name, charid = name, loc = loc(x), properties = {}}
end
local function ability(fields)
    function fields:try_get(k, default) if self[k] == nil then return default end return self[k] end
    function fields:GetRange() return self.range end
    function fields:GetNumTargets() return 1 end
    return fields
end

local melee = ability{name = "Death Scythe", range = 1, isMeleeVariation = true, targetType = "target"}
local ranged = ability{name = "Death Scythe", range = 10, isRangedVariation = true, targetType = "target"}
local scythe = ability{name = "Death Scythe", range = 10, targetType = "target",
    meleeAndRanged = true, meleeVariation = melee, rangedVariation = ranged}
function scythe:GetActiveVariation() return melee end

local cultist = token("Cultist", 0)
local ulivesh = token("Ulivesh", 1)
local hector = token("Hector", 9)

local ai = setmetatable({}, {__index = MonsterAI})
function ai:GetMovementToken(t) return t end
function ai:MovementTokenIsAtLoc(t, l) return t.loc.str == l.str end
function ai:TargetDistanceFromLoc(_, target, from) return math.abs(target.loc.x - from.x) end
function ai:BuildPlanArea() return nil end
--the old guess, which picked a different target from the move's own plan.
function ai:FindValidTargetsOfStrike() return {{token = hector, edges = 0}, {token = ulivesh, edges = 0}} end
function ai:SelectChargeTargets(_, _, candidates) return candidates end

--The move planned with its ranged variation and chose Ulivesh, from where it stands.
local plan = {loc = cultist.loc, strikePlans = {[ranged] = {[cultist.loc.str] = {{token = ulivesh, edges = -1}}}}}
local preview = ai:BuildPlanPreview(cultist, {scythe}, plan)
assert(#preview.targets == 1 and preview.targets[1] == ulivesh, "preview shows the target the ranged plan chose")
assert(preview.variation == "melee", "adjacent target: the cast picks melee")

plan = {loc = cultist.loc, strikePlans = {[ranged] = {[cultist.loc.str] = {{token = hector, edges = 0}}}}}
preview = ai:BuildPlanPreview(cultist, {scythe}, plan)
assert(preview.targets[1] == hector, "distant planned target")
assert(preview.variation == "ranged", "distant target: the cast picks ranged")

--a variation passed directly names itself; an ordinary ability has none.
assert(ai:PreviewCastVariation(cultist, ranged, {{token = ulivesh}}, cultist.loc) == "ranged")
assert(ai:PreviewCastVariation(cultist, ability{name = "Sword"}, {{token = ulivesh}}, cultist.loc) == nil)
assert(ai:PreviewCastVariation(cultist, scythe, {}, cultist.loc) == nil, "no targets: leave it to the stance")

--The card every client draws follows the variation in the preview document.
cultist.properties.GetActivatedAbilities = function() return {scythe} end
dmhub.GetTokenById = function() return cultist end
PreviewAbilityCard({charid = "Cultist", name = "Death Scythe", variation = "ranged"})
assert(shownCard == ranged, "card shows the ranged variation the AI casts")
PreviewAbilityCard({charid = "Cultist", name = "Death Scythe", variation = "melee"})
assert(shownCard == melee, "card shows the melee variation")
PreviewAbilityCard({charid = "Cultist", name = "Death Scythe"})
assert(shownCard == melee, "an old document without a variation uses the stance")

print("ai_plan_preview_test: all passed")
