--Run from C:/dev/dmhub with dependencies/lua/bin/lua.exe draw-steel-codex/tests/charge_jump_roll_test.lua.
--Exercise the real charge executor and Jump dialog flow with deterministic engine/UI stand-ins.
dmhub = {GetModLoading = function() return {} end, unitsPerSquare = 5}
ActivatedAbility = {RegisterType = function() end}
ActivatedAbilityBehavior = {}
function RegisterGameType(name)
    local t = {typeName = name}
    t.__index = t
    function t.new(v) return setmetatable(v or {}, t) end
    function t:try_get(k, default) if self[k] == nil then return default end return self[k] end
    return t
end
function round(n) return math.floor(n + 0.5) end
function tr(s) return s end
function cond(v, a, b) if v then return a end return b end
function ExecuteGoblinScript(s, lookup)
    return (tonumber(s:match("^(%d) %+")) or 0) + lookup[s:find("Height") and "height" or "distance"]
end
dofile("draw-steel-codex/Draw Steel Ability Behaviors/AbilityJump.lua")
dofile("draw-steel-codex/DMHub Game Rules/AbilityRelocateCreature.lua")
local checks = 0
local function check(v, name) assert(v, name); checks = checks + 1 end
local function loc(x)
    return {x = x, str = tostring(x), DistanceInTiles = function(self, other) return math.abs(self.x - other.x) end}
end
local props = {attrs = {["Charge Allows Jump"] = 1}}
function props:CalculateNamedCustomAttribute(name) return self.attrs[name] or 0 end
function props:try_get(k, default) if self[k] == nil then return default end return self[k] end
function props:LookupSymbol() return {distance = 3, height = 1} end
function props:IsOurTurn() return true end
function props:DistanceMovedThisTurn() return 7 end
function props:CurrentMovementSpeed() return 7 end
function props:IsDead() return self.dead end
function props:GetPierceWalls() return 0 end
function props:GetModifiersForPowerRoll(_, kind, options)
    assert(kind == "test_power_roll" and options.skills[1] == "jump-skill")
    if self.guaranteed then
        return {{modifier = {try_get = function() return "nottierone" end}, hint = {result = true}}}
    end
    return {}
end
local behavior = ActivatedAbilityJumpBehavior.new{skillid = "jump-skill"}
local jump = setmetatable({name = "Jump", behaviors = {behavior}}, {__index = ActivatedAbility})
function props:GetActivatedAbilities() return {jump} end
local charge = setmetatable({name = "Charge"}, {__index = ActivatedAbility})
function charge:GetRange() return props.chargeRange end
local payments, jumpPayments, rolls, previews, moves, reaction, rollReaction
function charge:CommitToPaying(_, options) payments = payments + 1; options.pay = true end
function jump:CommitToPaying(_, options) jumpPayments = jumpPayments + 1; options.pay = true end
local tok = {properties = props, valid = true, isMoving = false, altitude = 0, id = "caster"}
function tok:ClearMovementArrow() end
function tok:MarkMovementArrow(_, options) previews[#previews + 1] = options end
function tok:Distance(target) return math.abs(self.loc.x - target.loc.x) * 5 end
function tok:GetLineOfSight() return 1 end
local guaranteedPlan, failHeight, mismatch, selectedTier, cancelRoll, legalTarget
function tok:PlanCharge()
    return {validCharge = true, requiresRoll = not guaranteedPlan, requiredTier = 3,
        chargeSegments = {
            {loc = loc(1), expectedLoc = loc(1), jump = false},
            {loc = loc(6), expectedLoc = loc(6), jump = true, jumpHeight = guaranteedPlan and 2 or 3},
            {loc = loc(7), expectedLoc = loc(7), jump = false},
        }}
end
function tok:PlanChargeJumpOutcome(source, target, distance, height)
    local reaches = distance >= target.x - source.x and not failHeight
    return {loc = target, jumpDistance = distance, jumpHeight = height,
        expectedLoc = loc(reaches and target.x or math.min(target.x - 1, source.x + distance)),
        reachesJumpEnd = reaches}
end
function tok:Move(target, options)
    moves[#moves + 1] = options
    local destination = target
    if options.chargeJumpOutcome then
        destination = self:PlanChargeJumpOutcome(self.loc, target, options.chargeJumpDistance, options.jumpHeight).expectedLoc
    end
    local distance = destination.x - self.loc.x
    self.loc = mismatch and loc(destination.x - 1) or destination
    if reaction then reaction(#moves) end
    return {numSteps = distance}
end
RollPropertiesPowerTable = RegisterGameType("RollPropertiesPowerTable")
RollUtils = {DiceResultToTier = function() return selectedTier end}
Skill = {tableName = "skills"}
function dmhub.EvalGoblinScript() return "2d10+3" end
function dmhub.GetSettingValue() return false end
local attack = {}
function attack:HasKeyword(keyword) return keyword == "Strike" end
function attack:try_get() return nil end
function attack:AbilityFilterFailureMessage() return nil end
function attack:GetCost() return {canAfford = true} end
function attack:GetRange() return 5 end
function attack:TargetPassesFilter(_, target, symbols)
    assert(symbols.targetArea == nil and symbols.cast == nil, "fresh attack symbols")
    return legalTarget and target.id == "enemy"
end
function dmhub.GetTable(name)
    if name == "standardAbilities" then
        return {["923bf32c-4233-4fec-8895-7ce18da28744"] = {SynthesizeAbilities = function() return {attack} end}}
    end
    return {}
end
local enemyProperties = {hidden = false}
function enemyProperties:HasNamedCondition(name) return name == "Hidden" and self.hidden end
dmhub.allTokens = {{id = "enemy", valid = true, loc = loc(6), altitude = 0, properties = enemyProperties}}
CharacterPanel = {
    AcquireAbilityRollDialog = function(_, rolledAbility)
        assert(rolledAbility == jump, "roll uses actual Jump action")
        return {valid = true, data = {ShowDialog = function(args)
            rolls = rolls + 1
            if rollReaction then rollReaction() end
            if cancelRoll then args.cancelRoll() else args.completeRoll{total = 15, naturalRoll = 12} end
        end}}, nil, "jump-lock"
    end,
    UnlockDisplayAbility = function() end,
}
local function reset()
    payments, jumpPayments, rolls = 0, 0, 0
    previews, moves = {}, {}
    reaction, rollReaction = nil, nil
    guaranteedPlan, failHeight, mismatch, cancelRoll = false, false, false, false
    selectedTier, legalTarget = 3, true
    props.chargeRange, props.guaranteed, props._tmp_prone, props.dead = 35, true, nil, false
    props._tmp_triggeredOpportunityAttacks = 0
    props.attrs["Charge Allows Jump"], props.attrs["Charge Uses Jump"] = 1, 0
    props.attrs["Ignore Hidden Within Range"] = 0
    enemyProperties.hidden = false
    tok.loc = loc(0)
end
local function execute()
    local options = {symbols = {cast = {spacesMoved = 0}}}
    ActivatedAbilityRelocateCreatureBehavior:ExecuteGuaranteedCharge(tok, loc(7), charge:GetChargeJumpOptions(tok), options, charge)
    return options
end
reset()
local options = charge:GetChargeJumpOptions(tok)
check(options.chargeJumpDistance == 4 and options.chargeJumpTierDistances[3] == 5, "tier limits")
check(behavior:GetTierDistances(jump, tok)[2] == 0, "charge independent of exhausted move action")
props._tmp_prone = true
check(charge:GetChargeJumpOptions(tok).chargeJumpDistance == 0, "prone cannot jump")
reset(); local oldPlanner = tok.PlanChargeJumpOutcome; tok.PlanChargeJumpOutcome = nil
check(charge:GetChargeJumpOptions(tok).chargeJumpTierDistances == nil, "old engine guaranteed-only fallback")
tok.PlanChargeJumpOutcome = oldPlanner
reset(); props.attrs["Charge Uses Jump"] = 1
check(charge:GetChargeJumpOptions(tok) == nil, "Panther unchanged")
reset(); options = execute()
check(#moves == 3 and rolls == 1 and tok.loc.x == 7 and not options.abort, "tier3 succeeds then finishes charge")
check(payments == 1 and jumpPayments == 0 and options.pay, "charge payment once, no Jump payment")
check(moves[2].chargeJumpOutcome and not moves[2].chargeJumpLanding, "native fixed-direction jump outcome")
reset(); selectedTier = 2; options = execute()
check(#moves == 2 and tok.loc.x == 5 and not options.abort, "tier2 falls short and can attack nearby")
check(previews[1].chargeJumpOutcome and previews[1].chargeJumpDistance == 4, "roll preview uses native tier outcome")
reset(); selectedTier = 2; legalTarget = false; options = execute()
check(options.abort and options.stopProcessing and #moves == 2, "no legal shortfall attack stops pipeline")
reset(); selectedTier = 2; enemyProperties.hidden = true; options = execute()
check(options.abort and options.stopProcessing, "only hidden target does not open charge attack selector")
reset(); selectedTier = 2; enemyProperties.hidden = true; props.attrs["Ignore Hidden Within Range"] = 5; options = execute()
check(not options.abort, "ignore-hidden range allows a nearby hidden charge target")
reset(); selectedTier = 2; enemyProperties.hidden = true; props.attrs["Ignore Hidden Within Range"] = 4; options = execute()
check(options.abort, "hidden target beyond ignore-hidden range remains illegal")
reset(); selectedTier = 2; reaction = function(n) if n == 2 then props._tmp_prone = true end end; options = execute()
check(not options.abort and #moves == 2, "prone landing may attack with ordinary bane")
reset(); cancelRoll = true; options = execute()
check(options.abort and options.stopProcessing and #moves == 1 and options.pay and payments == 1, "cancel at takeoff keeps approach and charge cost")
reset(); reaction = function() props._tmp_prone = true end; options = execute()
check(options.abort and #moves == 1 and rolls == 0, "prone approach reaction prevents roll and jump")
reset(); reaction = function() props.chargeRange = 0 end; options = execute()
check(options.abort and #moves == 1 and rolls == 0, "restraint approach reaction prevents jump")
reset(); rollReaction = function() props._tmp_prone = true end; options = execute()
check(options.abort and #moves == 1 and rolls == 1, "reaction during roll prevents jump")
reset(); rollReaction = function() tok.loc = loc(2) end; options = execute()
check(options.abort and options.stopProcessing and #moves == 1 and tok.loc.x == 2,
    "forced displacement during roll cannot relocate the planned takeoff")
reset(); mismatch = true; options = execute()
check(options.abort and options.stopProcessing and #moves == 1, "actual landing mismatch aborts")
reset(); guaranteedPlan = true
--Use a four-square guaranteed leap with a one-square approach and walk afterward.
local riskyPlanner = tok.PlanCharge
function tok:PlanCharge()
    local p = riskyPlanner(self)
    p.chargeSegments[2].loc, p.chargeSegments[2].expectedLoc = loc(5), loc(5)
    return p
end
options = execute()
check(not options.abort and rolls == 0 and #moves == 3, "guaranteed charge still skips roll")
tok.PlanCharge = riskyPlanner
reset(); local savedPlanner = tok.PlanCharge; tok.PlanCharge = nil
check(charge:GetChargeJumpOptions(tok) == nil, "engine without charge planner preserves ordinary Charge")
tok.PlanCharge = savedPlanner
reset(); reaction = function() props.dead = true end; options = execute()
check(options.abort and #moves == 1 and rolls == 0, "fatal approach reaction stops charge")
reset(); local savedCost = attack.GetCost
function attack:GetCost() return {canAfford = false} end
check(not ActivatedAbilityRelocateCreatureBehavior:HasChargeAttackTarget(tok), "unaffordable charge attack is not offered")
attack.GetCost = savedCost
local purges = 0
charge.targetType = "emptyspace"
charge.behaviors = {{
    typeName = "ActivatedAbilityPurgeEffectsBehavior",
    ApplyToTargets = function(_, _, _, targets) return targets end,
    Cast = function() purges = purges + 1 end,
}}
local relocation = ActivatedAbilityRelocateCreatureBehavior.new{movementType = "move"}
local function cast()
    local result = {symbols = {cast = {spacesMoved = 0, opportunityAttacksTriggered = 0}}}
    relocation:Cast(charge, tok, {{loc = loc(7)}}, result)
    return result
end
reset(); tok.PlanCharge = function() return nil end; options = cast()
check(options.abort and payments == 0 and purges == 1, "invalid preapproach cast purges without paying")
tok.PlanCharge = savedPlanner
reset(); cancelRoll = true; options = cast()
check(options.abort and payments == 1 and purges == 2 and options.pay, "canceling full cast purges and pays exactly once")
reset(); options = {symbols = {cast = {}}}
behavior:RollForTier(jump, tok, options, {3, 4, 5}, {1, 2, 3}, 3, nil)
check(jumpPayments == 1, "ordinary Jump retains payment behavior")
print(checks .. " charge jump roll checks passed")
