local mod = dmhub.GetModLoading()

-- Ooze band AI: every monster in the Ooze group (Sludgestorm, Creeping Sludge,
-- Imit Putty, Stunslopper, Gummy Ball, Gummy Brick, Oz the Oozemaster and the
-- ichors), plus the group's Malice (Gush, Liquefy). Oozes are mindless, so
-- nothing here speaks.

local sludgestormMonsters = {"Sludgestorm"}
local creepingSludgeMonsters = {"Creeping Sludge"}
local stunslopperMonsters = {"Stunslopper"}
local gummyBallMonsters = {"Gummy Ball"}
local gummyBrickMonsters = {"Gummy Brick"}
local ozMonsters = {"Oz the Oozemaster"}
local ichorMonsters = {"Red Ichor", "Black Ichor", "White Ichor"}
local splitMonsters = {"Sludgestorm", "Creeping Sludge", "Imit Putty", "Stunslopper", "Gummy Ball", "Gummy Brick"}

local movementPause = 0.6
local abilityPause = 1.0

-- The shared "Tier 3 on next power roll" effect Storm Surge applies.
local stormSurgeEffectId = "45233f5a-56ac-488a-bb64-9b2b45382316"

-- Storm Strike's 5 Malice mode is a 3 cube that hits only enemies.
local stormCubeMode = 2
local stormCubeMinimumEnemies = 2

-- Split's data only allows it above 1 Stamina (Imit Putty's lacks the check);
-- match that so the AI dismisses instead of trying.
local splitMinimumStamina = 2

-- The ichors' "Malice Emitted" effect: this round's extra Malice is already claimed.
local maliceEmittedEffectId = "8148e1e8-224b-4b15-8424-b281f9d319d9"

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject and token.properties ~= nil
        and not token.properties:IsDead()
end

local function MonsterType(token)
    if token == nil or token.properties == nil then
        return ""
    end
    return MonsterAI.AIMonsterType(token.properties)
end

local function HasOngoingEffect(token, effectid)
    if not LiveCreature(token) then
        return false
    end
    for _,effect in ipairs(token.properties:ActiveOngoingEffects()) do
        if effect.ongoingEffectid == effectid then
            return true
        end
    end
    return false
end

local function HasBehavior(ability, typeName)
    for _,behavior in ipairs(ability.behaviors or {}) do
        if behavior.typeName == typeName then
            return true
        end
    end
    return false
end

local function Enemies(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and not other:IsFriend(token) then
            result[#result+1] = other
        end
    end
    return result
end

-- The enemies in the fight; falls back to every hostile token on the map when
-- no list is given.
local function CombatEnemies(token, enemyTokens)
    if enemyTokens == nil then
        return Enemies(token)
    end
    local result = {}
    for _,enemy in ipairs(enemyTokens) do
        if LiveCreature(enemy) then
            result[#result+1] = enemy
        end
    end
    return result
end

local function NearestEnemyDistance(token, loc)
    local best = nil
    for _,enemy in ipairs(Enemies(token)) do
        local distance = enemy:Distance(loc)
        if best == nil or distance < best then
            best = distance
        end
    end
    return best or 1000
end

local function EmptyLoc(loc)
    if loc == nil or not loc.valid or not loc.isOnMap then
        return false
    end
    for _,other in ipairs(dmhub.GetTokensAtLoc(loc) or {}) do
        if other.valid then
            return false
        end
    end
    return true
end

local function MoveCinematically(ai, token, loc)
    if loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc) then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(movementPause)
    end
end

--------------------------------------------------------------------------------
-- Shared helpers: cube areas and strikes.
--------------------------------------------------------------------------------

-- The engine pulls a cube back to within `range` of where the caster stands
-- now. Planning passes a range just long enough to reach the center, so a cube
-- around enemies the caster must move toward is counted where it will be.
local function BuildCubeArea(token, ability, center, rangeOverride)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = rangeOverride or ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        checklos = false,
        altitude = center.altitude * dmhub.unitsPerSquare,
    }
end

local function EnemiesInArea(token, ability, area, symbols)
    local result = {}
    local areaSymbols = table.shallow_copy(symbols)
    areaSymbols.targetArea = area
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if LiveCreature(target) and not target:IsFriend(token)
            and ability:TargetPassesFilter(token, target, areaSymbols) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

-- Try every cube center that could cover an enemy and keep those catching at
-- least minimumEnemies, so enemies a few squares apart can share one cube. Then
-- pick the reachable square with a center in range and line of effect,
-- preferring more targets, then less movement.
local function FindCubePlan(ai, token, cubeAbility, symbols, minimumEnemies)
    local range = cubeAbility:GetRange(token.properties)
    local radius = cubeAbility:GetRadius(token.properties)
    local reach = math.floor((radius - 1)/2)
    local pierceWalls = token.properties:GetPierceWalls()
    local centers = {}
    local seen = {}
    for _,enemy in ipairs(CombatEnemies(token, ai:try_get("enemyTokens"))) do
        for dx=-reach,reach do
            for dy=-reach,reach do
                local center = enemy.loc:dir(dx, dy)
                if center.valid and center.isOnMap and not seen[center.str] then
                    seen[center.str] = true
                    local unclampedRange = token:Distance(center) + radius + 1
                    local area = BuildCubeArea(token, cubeAbility, center, unclampedRange)
                    local targets = EnemiesInArea(token, cubeAbility, area, symbols)
                    if #targets >= minimumEnemies then
                        centers[#centers+1] = {loc = center, numTargets = #targets}
                    end
                end
            end
        end
    end
    if #centers == 0 then
        return nil
    end
    -- Most targets first: from any one square, the first center in range with
    -- line of effect is that square's best, so the rest need no checks.
    table.sort(centers, function(first, second)
        return first.numTargets > second.numTargets
    end)

    local best = nil
    for _,info in pairs(ai.paths or {}) do
        ai:ExecuteWithTheoreticalMovementLoc(token, info.loc, function()
            for _,center in ipairs(centers) do
                if token:Distance(center.loc) <= range
                    and token:GetLineOfSight(center.loc, pierceWalls) > 0 then
                    local value = center.numTargets - (info.cost or 0)*0.001
                    if best == nil or value > best.value then
                        best = {
                            value = value,
                            loc = info.loc,
                            center = center.loc,
                            numTargets = center.numTargets,
                        }
                    end
                    break
                end
            end
        end)
    end
    return best
end

-- Cast a planned cube from where the caster now stands. Returns nil (casting
-- nothing) when the Malice is no longer there or fewer than minimumEnemies are
-- left in the cube, since enemies can move or die between planning and casting.
local function ExecuteCubePlan(ai, token, cubeAbility, center, symbols, minimumEnemies)
    if not cubeAbility:CanAfford(token) then
        return nil
    end
    local area = BuildCubeArea(token, cubeAbility, center)
    local targets = EnemiesInArea(token, cubeAbility, area, symbols)
    if #targets < minimumEnemies then
        return nil
    end
    local castSymbols = table.shallow_copy(symbols)
    castSymbols.targetArea = area
    local result = ai:ExecuteAbility(token, cubeAbility, targets, {
        sleep = abilityPause,
        symbols = castSymbols,
        targetArea = area,
    })
    return result ~= false
end

-- Default target score: favor targets the strike has edges against, then
-- healthier enemies.
local function DefaultTargetValue(target, edges)
    return 1 + (edges or 0)*0.1 + MonsterAI.TargetStaminaBias(target)
end

-- The strike's targets from where the token stands, best first, cut to the
-- ability's target count.
local function StrikeTargetsHere(ai, token, ability, valueOf)
    local targets = ai:FindValidTargetsOfStrike(token, ability, token.loc)
    table.sort(targets, function(first, second)
        return valueOf(first.token, first.edges) > valueOf(second.token, second.edges)
    end)
    table.resize_array(targets, ability:GetNumTargets(token))
    return targets
end

-- Move to the planned square and strike. Returns false when no target is left,
-- which tells the move loop the action is unspent so it tries something else.
local function MoveAndStrike(ai, token, loc, ability, valueOf)
    MoveCinematically(ai, token, loc)
    local targets = StrikeTargetsHere(ai, token, ability, valueOf)
    if #targets == 0 then
        return false
    end
    return ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause, symbols = {mode = 1}})
end

--------------------------------------------------------------------------------
-- Sludgestorm: Storm Strike and Storm Surge.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Sludgestorm: Storm Strike",
    category = "Main Actions",
    monsters = sludgestormMonsters,
    abilities = {"Storm Strike"},
    description = "Spend 5 Malice on the Storm Strike cube when it catches two or more enemies, otherwise make the normal ranged strike.",
    score = function(self, ai, token, ability)
        -- CanAfford(token, {mode = 2}) does not see a variation's own Malice
        -- cost; only the switched ability carries it.
        local cubeAbility = ability:SwitchModes(stormCubeMode)
        if cubeAbility:CanAfford(token) then
            local plan = FindCubePlan(ai, token, cubeAbility, {mode = stormCubeMode}, stormCubeMinimumEnemies)
            if plan ~= nil then
                return {
                    score = 1.3 + math.min(0.3, (plan.numTargets - stormCubeMinimumEnemies)*0.1),
                    mode = stormCubeMode,
                    loc = plan.loc,
                    center = plan.center,
                }
            end
        end

        local loc = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetValue)
        if loc == nil then
            return nil, "no reachable square has a Storm Strike target"
        end
        return {score = 1, mode = 1, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        if scoringInfo.mode == stormCubeMode then
            MoveCinematically(ai, token, scoringInfo.loc)
            -- If the Malice is gone or under two enemies are left in the cube,
            -- make the normal strike from here instead.
            local cast = ExecuteCubePlan(ai, token, ability:SwitchModes(stormCubeMode),
                scoringInfo.center, {mode = stormCubeMode}, stormCubeMinimumEnemies)
            if cast ~= nil then
                return cast
            end
        end
        return MoveAndStrike(ai, token, scoringInfo.loc, ability, DefaultTargetValue)
    end,
}

MonsterAI:RegisterMove{
    id = "Sludgestorm: Storm Surge",
    category = "Maneuvers",
    monsters = sludgestormMonsters,
    abilities = {"Storm Surge"},
    description = "Give an ally within reach an automatic tier 3 on its next power roll, preferring full monsters over minions.",
    score = function(self, ai, token, ability)
        local best = nil
        for _,ally in ipairs(dmhub.allTokens) do
            -- StrikePairIsLegal is the cast's own range, filter and line of sight
            -- test; an ally the cast would reject would be picked every cycle.
            if LiveCreature(ally) and ally.charid ~= token.charid and ally:IsFriend(token)
                and not HasOngoingEffect(ally, stormSurgeEffectId)
                and ai:StrikePairIsLegal(ability, token, ally, {}) then
                -- A full monster gets more out of an automatic tier 3 than one
                -- minion's share of a squad strike.
                local value = ally.properties.minion and 0.5 or 1
                if best == nil or value > best.value then
                    best = {value = value, target = ally}
                end
            end
        end
        if best == nil then
            return nil, "no ally in reach without Storm Surge"
        end
        return {score = 0.55 + best.value*0.1, targetid = best.target.charid}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local ally = dmhub.GetTokenById(scoringInfo.targetid)
        if ally == nil or not LiveCreature(ally) then
            return false
        end
        return ai:ExecuteAbility(token, ability, {{token = ally}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Creeping Sludge: Oozen Grasp.
--------------------------------------------------------------------------------

-- The grab is A<0 / A<1 / A<2 by tier, so an enemy with Agility 2 or more can
-- never be grabbed, one with Agility 1 only on a tier 3, and one with Agility 0
-- on a tier 2 or 3 (counted as a sure grab, since tier 1 is the rarest roll).
-- An enemy that is already grabbed is held anyway, so grabbing it again isn't
-- worth Malice.
local function OozenGraspValue(target)
    if target.properties:HasNamedCondition("Grabbed") then
        return 0
    end
    local agility = target.properties:GetAttribute("agl"):Value()
    if agility >= 2 then
        return 0
    elseif agility == 1 then
        return 0.5
    end
    return 1
end

-- Worth 2 Malice once the burst can expect to hold two enemies.
local oozenGraspMinimumValue = 2

MonsterAI:RegisterMove{
    id = "Creeping Sludge: Oozen Grasp",
    category = "Maneuvers",
    monsters = creepingSludgeMonsters,
    abilities = {"Oozen Grasp"},
    description = "Spend 2 Malice on Oozen Grasp when the burst can grab two or more enemies weak enough in Agility to fail it, before striking with Corrode.",
    score = function(self, ai, token, ability)
        local loc, value = ai:FindBestMoveToUseBurst(token, ability, function(target)
            if LiveCreature(target) and not target:IsFriend(token) then
                return OozenGraspValue(target)
            end
            return 0
        end)
        if loc == nil or value < oozenGraspMinimumValue then
            return nil, "the burst would not hold two enemies who can fail its Agility potency"
        end
        -- Score 1 or more: the generic AI never scores Corrode this high, so the
        -- grab comes before the strike.
        return {score = 1 + math.min(0.2, (value - oozenGraspMinimumValue)*0.1), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        return ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Ooze Malice. Congeal is left out: merging two oozes trades a body's worth of
-- actions for temporary Stamina, which is rarely worth 5 Malice.
--------------------------------------------------------------------------------

local oozeGroups = {"Ooze"}

-- The Liquefy effect: invisible and hidden until the ooze's next turn.
local liquefyEffectId = "bb1a1ef8-339c-4d69-9b9a-bfc21c64ee94"

local function AdjacentEnemyCount(token, enemies)
    local count = 0
    for _,enemy in ipairs(enemies) do
        if MonsterAI.TargetDistance(token, enemy) <= 1 then
            count = count + 1
        end
    end
    return count
end

local function IsOoze(token)
    return LiveCreature(token) and token.properties:Keywords()["Ooze"] == true
end

-- Gush picks any ooze on the map; the one with the most enemies around it
-- gets the most free strikes and acid ground out of the 5 Malice.
local gushMinimumEnemies = 2

-- Where each ooze last gushed, per initiative queue: a second Gush from the
-- same square would only pile acid ground onto ground that already has it.
local g_gushedFrom = {}

local function GushedFromHere(context, ooze)
    local queue = context.initiativeQueue
    if queue == nil then
        return false
    end
    local gushed = g_gushedFrom[queue.guid]
    return gushed ~= nil and gushed[ooze.charid] == ooze.loc.str
end

local function RecordGush(context, charid, locStr)
    local queue = context.initiativeQueue
    if queue == nil then
        return
    end
    g_gushedFrom[queue.guid] = g_gushedFrom[queue.guid] or {}
    g_gushedFrom[queue.guid][charid] = locStr
end

MonsterAI:RegisterMaliceAbility{
    id = "Ooze Malice: Gush",
    monsterGroups = oozeGroups,
    abilities = {"Gush"},
    description = "Spend 5 Malice to make the ooze with the most adjacent enemies gush, when it has two or more.",
    score = function(self, ai, token, ability, context)
        local enemies = CombatEnemies(token, context.enemyTokens)
        local best = nil
        for _,ooze in ipairs(dmhub.allTokens) do
            -- The caster may gush itself; any other ooze must pass the cast's
            -- own range, filter and line of sight test, or the cast is rejected.
            if IsOoze(ooze) and ooze:IsFriend(token)
                and not GushedFromHere(context, ooze)
                and (ooze.charid == token.charid or ai:StrikePairIsLegal(ability, token, ooze, {})) then
                local count = AdjacentEnemyCount(ooze, enemies)
                if best == nil or count > best.count then
                    best = {count = count, ooze = ooze}
                end
            end
        end
        if best == nil or best.count < gushMinimumEnemies then
            return nil, "no ooze that hasn't already gushed from its square has two or more adjacent enemies"
        end
        return {
            score = math.min(0.95, 0.75 + (best.count - gushMinimumEnemies)*0.1),
            targetid = best.ooze.charid,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local ooze = dmhub.GetTokenById(scoringInfo.targetid)
        if ooze == nil or not LiveCreature(ooze) then
            return false
        end
        local gushFrom = ooze.loc.str
        local result = ai:ExecuteAbility(token, ability, {{token = ooze}}, {sleep = abilityPause})
        if result ~= false then
            RecordGush(context, ooze.charid, gushFrom)
        end
        return result
    end,
}

-- Gush runs two invoked steps, each a burst around the gushing ooze. A burst
-- prompt wants every creature its filter accepts in range; the acid ground also
-- needs the burst's shape, or no aura is placed.
local function BurstPromptTargets(casterToken, abilityClone, symbols)
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local targets = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and MonsterAI.TargetDistance(other, casterToken) <= range
            and abilityClone:TargetPassesFilter(casterToken, other, symbols or {}) then
            targets[#targets+1] = {token = other}
        end
    end
    return targets, range
end

local function GushStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if not LiveCreature(casterToken) then
        return nil
    end
    local targets = BurstPromptTargets(casterToken, abilityClone, symbols)
    return {targets = targets}
end

local function GushAuraPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if not LiveCreature(casterToken) then
        return nil
    end
    local targets, range = BurstPromptTargets(casterToken, abilityClone, symbols)
    local area = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = casterToken,
        radius = range,
    }
    return {targets = targets, targetArea = area}
end

-- Unqualified: only Gush uses these names, and any ooze in the group can gush.
MonsterAI:RegisterPrompt{
    prompts = {"Gush Melee Strike Damage"},
    handler = GushStrikePrompt,
}

MonsterAI:RegisterPrompt{
    prompts = {"Gush Aura"},
    handler = GushAuraPrompt,
}

-- Liquefy hides an ooze until its next turn, and the hiding ends when it uses an
-- ability. So it goes on a hurt ooze beside the caster that isn't about to act.
-- Only worth it when an enemy is close enough to reach that ooze next turn.
local liquefyThreatDistance = 5

MonsterAI:RegisterMaliceAbility{
    id = "Ooze Malice: Liquefy",
    monsterGroups = oozeGroups,
    abilities = {"Liquefy"},
    description = "Spend 3 Malice to hide a winded ooze that enemies can reach and that is not acting this turn.",
    score = function(self, ai, token, ability, context)
        local acting = {}
        for _,actor in ipairs(context.actingTokens or {}) do
            acting[actor.charid] = true
        end
        local best = nil
        for _,ooze in ipairs(dmhub.allTokens) do
            if IsOoze(ooze) and ooze:IsFriend(token) and not acting[ooze.charid]
                and not ooze.properties.minion
                and ooze.properties:IsWinded()
                and not HasOngoingEffect(ooze, liquefyEffectId)
                and ai:StrikePairIsLegal(ability, token, ooze, {})
                and ai:DistanceFromNearestEnemy(ooze) <= liquefyThreatDistance then
                local stamina = ooze.properties:CurrentHitpoints()
                if best == nil or stamina < best.stamina then
                    best = {stamina = stamina, ooze = ooze}
                end
            end
        end
        if best == nil then
            return nil, "no winded ooze beside the caster needs hiding"
        end
        -- Just over the lowest score at which the AI uses a Malice ability. A
        -- first Gush outscores this; once Gush has been used, its repeat
        -- penalty can let the cheaper Liquefy win.
        return {score = MonsterAI.maliceAbilityMinimumScore + 0.03, targetid = best.ooze.charid}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local ooze = dmhub.GetTokenById(scoringInfo.targetid)
        if ooze == nil or not LiveCreature(ooze) then
            return false
        end
        return ai:ExecuteAbility(token, ability, {{token = ooze}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Stunslopper: Psychic Stun and Psychic Slop.
--------------------------------------------------------------------------------

-- Psychic Stun is only partly automated (Silver), which the generic AI never
-- casts, so it needs its own move.
MonsterAI:RegisterMove{
    id = "Stunslopper: Psychic Stun",
    category = "Main Actions",
    monsters = stunslopperMonsters,
    abilities = {"Psychic Stun"},
    description = "Signature melee strike on up to two enemies.",
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetValue)
        if loc == nil then
            return nil, "no reachable square has a Psychic Stun target"
        end
        return {score = 1, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        return MoveAndStrike(ai, token, scoringInfo.loc, ability, DefaultTargetValue)
    end,
}

-- Psychic Slop takes the main action instead of the stun's two targets and
-- costs 2 Malice, so it needs a bigger crowd to be worth it.
local psychicSlopMinimumEnemies = 3

MonsterAI:RegisterMove{
    id = "Stunslopper: Psychic Slop",
    category = "Main Actions",
    monsters = stunslopperMonsters,
    abilities = {"Psychic Slop"},
    description = "Spend 2 Malice on the psychic burst when it catches three or more enemies.",
    score = function(self, ai, token, ability)
        local loc, count = ai:FindBestMoveToUseBurst(token, ability, function(target)
            if LiveCreature(target) and not target:IsFriend(token) then
                return 1
            end
            return 0
        end)
        if loc == nil or count < psychicSlopMinimumEnemies then
            return nil, "the burst would catch fewer than three enemies"
        end
        return {score = 1.2 + math.min(0.2, (count - psychicSlopMinimumEnemies)*0.1), loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        -- The move can stop short or enemies can move away: recount before
        -- paying the 2 Malice, and leave the action unspent if the crowd is gone.
        if not ability:CanAfford(token) then
            return false
        end
        local range = ability:GetRange(token.properties)
        local count = 0
        for _,enemy in ipairs(Enemies(token)) do
            if MonsterAI.TargetDistance(enemy, token) <= range and ability:TargetPassesFilter(token, enemy, {}) then
                count = count + 1
            end
        end
        if count < psychicSlopMinimumEnemies then
            return false
        end
        return ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Gummy Ball: Bowl. Rolling is left to a Director: the forced-movement event
-- doesn't say which way the ball was pushed, so the AI can't roll it on.
--------------------------------------------------------------------------------

-- Bowl's 2 Malice mode restrains a target of size 1L or smaller (the data's
-- "Target.Size < 5") with Agility below 1, instead of sliding it.
local bowlRestrainMode = 2
local bowlRestrainSizeLimit = 5

local function BowlRestrains(target)
    return target.properties:GetCalculatedCreatureSizeAsNumber() < bowlRestrainSizeLimit
        and target.properties:GetAttribute("agl"):Value() < 1
        and not target.properties:HasNamedCondition("Restrained")
end

-- Targets Bowl can restrain count for more, when the 2 Malice mode is affordable.
local function BowlTargetValue(canRestrain)
    return function(target, edges)
        return DefaultTargetValue(target, edges) + ((canRestrain and BowlRestrains(target)) and 1 or 0)
    end
end

-- Bowl is only partly automated (Silver), so the generic AI never casts it.
MonsterAI:RegisterMove{
    id = "Gummy Ball: Bowl",
    category = "Main Actions",
    monsters = gummyBallMonsters,
    abilities = {"Bowl"},
    description = "Signature charge strike; spends 2 Malice to restrain a small, clumsy target instead of sliding it.",
    score = function(self, ai, token, ability)
        local restrainAbility = ability:SwitchModes(bowlRestrainMode)
        local canRestrain = restrainAbility ~= ability and restrainAbility:CanAfford(token)
        local loc = ai:FindBestMoveToUseStrike(token, ability, BowlTargetValue(canRestrain))
        if loc == nil then
            return nil, "no reachable square has a Bowl target"
        end
        return {score = 1, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local restrainAbility = ability:SwitchModes(bowlRestrainMode)
        local canRestrain = restrainAbility ~= ability and restrainAbility:CanAfford(token)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = StrikeTargetsHere(ai, token, ability, BowlTargetValue(canRestrain))
        if #targets == 0 then
            return false
        end
        if canRestrain and BowlRestrains(targets[1].token) then
            return ai:ExecuteAbility(token, restrainAbility, targets, {sleep = abilityPause, symbols = {mode = bowlRestrainMode}})
        end
        return ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause, symbols = {mode = 1}})
    end,
}

--------------------------------------------------------------------------------
-- Gummy Brick: Engulf and The Brick Consumes.
--------------------------------------------------------------------------------

local engulfHiddenMode = 2

-- The AI reveals hidden monsters as their turn starts, so IsHidden alone is
-- false here; also accept "was hidden earlier this turn", as the
-- `hiddenthisturn` symbol does.
local function WasHiddenThisTurn(token)
    if token.properties:IsHidden() then
        return true
    end
    local queue = dmhub.initiativeQueue
    return queue ~= nil and not queue.hidden
        and token.properties:try_get("_tmp_hiddenTurnId") == queue:GetTurnId()
end

-- The 2 Malice mode tests Intuition at one higher potency instead of Agility,
-- so it is the better roll unless the target's Intuition beats its Agility.
local function EngulfPrefersIntuition(target)
    return target.properties:GetAttribute("inu"):Value() <= target.properties:GetAttribute("agl"):Value()
end

-- Engulf is only partly automated (Silver), so the generic AI never casts it.
MonsterAI:RegisterMove{
    id = "Gummy Brick: Engulf",
    category = "Main Actions",
    monsters = gummyBrickMonsters,
    abilities = {"Engulf"},
    description = "Signature charge strike; spends 2 Malice to test Intuition when the brick was hidden from the target.",
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetValue)
        if loc == nil then
            return nil, "no reachable square has an Engulf target"
        end
        return {score = 1, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = StrikeTargetsHere(ai, token, ability, DefaultTargetValue)
        if #targets == 0 then
            return false
        end
        local hiddenAbility = ability:SwitchModes(engulfHiddenMode)
        if hiddenAbility ~= ability and WasHiddenThisTurn(token) and hiddenAbility:CanAfford(token)
            and EngulfPrefersIntuition(targets[1].token) then
            return ai:ExecuteAbility(token, hiddenAbility, targets, {sleep = abilityPause, symbols = {mode = engulfHiddenMode}})
        end
        return ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause, symbols = {mode = 1}})
    end,
}

-- Who set the trigger off: the card keeps the event's `subject` (the creature
-- that moved) in its saved symbols, as "charid:<id>" or "tokenid:<id>".
local function TriggerSubjectId(triggerInfo)
    local saved = triggerInfo:try_get("execSymbols")
    local subject = type(saved) == "table" and saved.subject or nil
    if type(subject) ~= "string" then
        return nil
    end
    return string.match(subject, "^charid:(.+)$") or string.match(subject, "^tokenid:(.+)$")
end

local function AdjacentEnemy(brick, charid)
    local other = charid ~= nil and dmhub.GetTokenById(charid) or nil
    if other ~= nil and LiveCreature(other) and not other:IsFriend(brick)
        and MonsterAI.TargetDistance(brick, other) <= 1 then
        return other
    end
    return nil
end

-- The creature each brick will Engulf, from its trigger to its Engulf prompt.
local g_brickVictim = {}

-- Only the creature that stepped in may be engulfed, and only if it is an enemy:
-- an ally ooze moving next to the brick sets the trigger off too.
MonsterAI:RegisterTrigger{
    id = "Gummy Brick: The Brick Consumes",
    monsters = gummyBrickMonsters,
    abilities = {"The Brick Consumes"},
    description = "Engulf an enemy that steps next to the brick.",
    handler = function(ai, token, triggerInfo)
        local victim = LiveCreature(token) and AdjacentEnemy(token, TriggerSubjectId(triggerInfo)) or nil
        if victim == nil then
            return {dismiss = true}
        end
        g_brickVictim[token.charid] = victim.charid
        return {activate = true}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Gummy Brick:Engulf (The Brick Consumes)"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if not LiveCreature(casterToken) then
            return nil
        end
        local victim = AdjacentEnemy(casterToken, g_brickVictim[casterToken.charid])
        g_brickVictim[casterToken.charid] = nil
        if victim == nil then
            return nil
        end
        return {targets = {{token = victim}}}
    end,
}

--------------------------------------------------------------------------------
-- Oz the Oozemaster: Oozen Sling, Slimy Pit, Determination and Ichor Flicker.
--------------------------------------------------------------------------------

-- Oozen Sling is only partly automated (Silver), so the generic AI never casts it.
MonsterAI:RegisterMove{
    id = "Oz the Oozemaster: Oozen Sling",
    category = "Main Actions",
    monsters = ozMonsters,
    abilities = {"Oozen Sling"},
    description = "Signature strike on up to two enemies within 10.",
    score = function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability, DefaultTargetValue)
        if loc == nil then
            return nil, "no reachable square has an Oozen Sling target"
        end
        return {score = 1, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        return MoveAndStrike(ai, token, scoringInfo.loc, ability, DefaultTargetValue)
    end,
}

local slimyPitMinimumEnemies = 2

MonsterAI:RegisterMove{
    id = "Oz the Oozemaster: Slimy Pit",
    category = "Main Actions",
    monsters = ozMonsters,
    abilities = {"Slimy Pit"},
    description = "Spend 3 Malice on the slimy pit when the cube catches two or more enemies.",
    score = function(self, ai, token, ability)
        local plan = FindCubePlan(ai, token, ability, {mode = 1}, slimyPitMinimumEnemies)
        if plan == nil then
            return nil, "no cube in reach catches two enemies"
        end
        return {
            score = 1.3 + math.min(0.3, (plan.numTargets - slimyPitMinimumEnemies)*0.1),
            loc = plan.loc,
            center = plan.center,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        return ExecuteCubePlan(ai, token, ability, scoringInfo.center, {mode = 1}, slimyPitMinimumEnemies) == true
    end,
}

-- The conditions Determination can end.
local determinationConditions = {"Frightened", "Slowed", "Weakened"}

MonsterAI:RegisterMove{
    id = "Oz the Oozemaster: Determination",
    category = "Maneuvers",
    monsters = ozMonsters,
    abilities = {"Determination"},
    description = "End frightened, slowed or weakened on Oz.",
    score = function(self, ai, token, ability)
        for _,name in ipairs(determinationConditions) do
            if token.properties:HasNamedCondition(name) then
                return {score = 0.8}
            end
        end
        return nil, "Oz is not frightened, slowed or weakened"
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        return ai:ExecuteAbility(token, ability, {{token = token}}, {sleep = abilityPause})
    end,
}

-- Ichor Flicker: when Oz is struck, an ally ooze within 5 squares takes the
-- strike instead. A minion is the cheapest body to give up; otherwise the
-- healthiest ooze.
local ichorFlickerRange = 5

local function IchorFlickerTarget(oz)
    local best = nil
    for _,ooze in ipairs(dmhub.allTokens) do
        if IsOoze(ooze) and ooze.charid ~= oz.charid and ooze:IsFriend(oz)
            and MonsterAI.TargetDistance(oz, ooze) <= ichorFlickerRange then
            local stamina = ooze.properties:CurrentHitpoints() / math.max(1, ooze.properties:MaxHitpoints())
            local value = (ooze.properties.minion and 2 or 0) + stamina
            if best == nil or value > best.value then
                best = {value = value, token = ooze}
            end
        end
    end
    return best ~= nil and best.token or nil
end

local ichorFlickerText = "Ichor Flicker"

-- The Malice a card asks for: the 2 Malice version (a free triggered action)
-- carries its cost here; the ordinary one, which spends the triggered action, has 0.
local function TriggerMaliceCost(triggerInfo)
    return tonumber(triggerInfo:try_get("heroicResourceCost")) or 0
end

-- Both versions show the same text, so one handler takes both. The paid one is
-- only worth it when the ordinary one isn't on offer (the triggered action is
-- spent) and the Malice is there.
MonsterAI:RegisterTrigger{
    id = "Oz the Oozemaster: Ichor Flicker",
    monsters = ozMonsters,
    triggers = {ichorFlickerText},
    description = "Hand a strike aimed at Oz to an ally ooze within 5 squares, a minion first; pay 2 Malice only when the triggered action is spent.",
    handler = function(ai, token, triggerInfo)
        local cost = TriggerMaliceCost(triggerInfo)
        if cost > 0 then
            if (CharacterResource.GetMalice() or 0) < cost then
                return {dismiss = true}
            end
            for _,other in pairs(token.properties:GetAvailableTriggers() or {}) do
                if other.id ~= triggerInfo.id and not other.dismissed
                    and other:GetText() == ichorFlickerText and TriggerMaliceCost(other) == 0 then
                    return {dismiss = true}
                end
            end
        end
        local ooze = IchorFlickerTarget(token)
        if ooze == nil then
            return {dismiss = true}
        end
        return {activate = true, retargetid = ooze.charid}
    end,
}

--------------------------------------------------------------------------------
-- Split: always worth a second body while there is room for it.
--------------------------------------------------------------------------------

-- Where the copy can stand: its whole footprint (it is the ooze's size, 3x3 for
-- a Sludgestorm) is free, touches the ooze, and is in the ooze's line of effect.
local function SplitLocations(token)
    local own = token:LocsOccupyingWhenAt(token.loc)
    local side = math.max(1, math.floor(math.sqrt(#own) + 0.5))
    local result = {}
    for _,loc in ipairs(token:GetLocsWithinRadius(side)) do
        local fits = true
        local touches = false
        for _,square in ipairs(token:LocsOccupyingWhenAt(loc)) do
            if not EmptyLoc(square) then
                fits = false
                break
            end
            for _,ownSquare in ipairs(own) do
                if square:DistanceInTiles(ownSquare) <= 1 then
                    touches = true
                end
            end
        end
        if fits and touches and token:GetLineOfSightToSpace(loc) > 0 then
            result[#result+1] = loc
        end
    end
    return result
end

MonsterAI:RegisterTrigger{
    id = "Ooze: Split",
    monsters = splitMonsters,
    abilities = {"Split"},
    description = "Split whenever the ooze has the Stamina for two halves and room beside it for the copy.",
    handler = function(ai, token, triggerInfo)
        if not LiveCreature(token)
            or token.properties:CurrentHitpoints() < splitMinimumStamina
            or #SplitLocations(token) == 0 then
            return {dismiss = true}
        end
        return {activate = true}
    end,
}

-- Split's copy is summoned into an empty square beside the ooze; the one
-- nearest the enemies keeps the copy in the fight.
local function SplitPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if not HasBehavior(abilityClone, "ActivatedAbilitySummonBehavior") or not LiveCreature(casterToken) then
        return nil
    end
    local best = nil
    for _,loc in ipairs(SplitLocations(casterToken)) do
        local value = -NearestEnemyDistance(casterToken, loc)
        if best == nil or value > best.value then
            best = {value = value, loc = loc}
        end
    end
    if best == nil then
        return nil
    end
    return {targets = {{loc = best.loc}}}
end

--------------------------------------------------------------------------------
-- Ichors: Malice Emitter. The data makes it an optional trigger, so without a
-- Director it never fires unless the AI takes it.
--------------------------------------------------------------------------------

-- One claim per round per ichor kind: {charid, triggerid} of the ichor whose
-- card was accepted. The "Malice Emitted" mark lands only when the cast runs,
-- and that cast can queue behind another one (a hero's open dialog), so this
-- stops a second ichor's card being accepted in the meantime.
local g_emitterClaimed = {}

local function EmitterClaimKey(token)
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        return nil
    end
    return string.format("%s:%s:%s", tostring(queue.guid), tostring(queue.round), MonsterType(token))
end

-- An accepted card vanishes at once and its cast runs later, so a claim holds
-- while the card is up or any cast is still running. Once casts settle with no
-- mark (the ichor died, the cast never ran), the next card may claim instead.
local function EmitterClaimPending(claim)
    local claimant = dmhub.GetTokenById(claim.charid)
    if claimant == nil or not LiveCreature(claimant) then
        return false
    end
    local triggers = claimant.properties:GetAvailableTriggers() or {}
    return triggers[claim.triggerid] ~= nil or ActivatedAbility.CountActiveCasts() > 0
end

MonsterAI:RegisterTrigger{
    id = "Ichor: Malice Emitter",
    monsters = ichorMonsters,
    abilities = {"Malice Emitter"},
    description = "Claim the extra Malice at the start of the round, unless an ichor of the same kind already has this round.",
    handler = function(ai, token, triggerInfo)
        if HasOngoingEffect(token, maliceEmittedEffectId) then
            return {dismiss = true}
        end
        local key = EmitterClaimKey(token)
        if key ~= nil then
            local claim = g_emitterClaimed[key]
            if claim ~= nil and claim.charid ~= token.charid and EmitterClaimPending(claim) then
                return {dismiss = true}
            end
            g_emitterClaimed[key] = {charid = token.charid, triggerid = triggerInfo.id}
        end
        return {activate = true}
    end,
}

-- The first step marks every ichor of this kind as having emitted this round,
-- so only one of them pays out. Unqualified: only the ichors use this name.
MonsterAI:RegisterPrompt{
    prompts = {"Malice Emitted"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targets = {}
        for _,other in ipairs(dmhub.allTokens) do
            if LiveCreature(other) and MonsterType(other) == MonsterType(casterToken)
                and abilityClone:TargetPassesFilter(casterToken, other, symbols or {}) then
                targets[#targets+1] = {token = other}
            end
        end
        -- The data's filter can match nobody (a renamed token). Mark at least
        -- the caster so the cast has a target; other unmarked ichors still pay.
        if #targets == 0 then
            targets[1] = {token = casterToken}
        end
        return {targets = targets}
    end,
}

-- The Malice Emitter's second step pays the Malice to the ichor itself.
local function MaliceEmitterPayoutPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if HasBehavior(abilityClone, "ActivatedAbilityReplenishBehavior") and LiveCreature(casterToken) then
        return {targets = {{token = casterToken}}}
    end
    return nil
end

-- Split and the Malice Emitter's payout both arrive as "Invoked Ability", so one
-- handler per monster type tries each and answers only the one it recognizes.
local invokedAbilityPrompts = {}
for _,monsterType in ipairs(splitMonsters) do
    invokedAbilityPrompts[#invokedAbilityPrompts+1] = monsterType .. ":Invoked Ability"
end
for _,monsterType in ipairs(ichorMonsters) do
    invokedAbilityPrompts[#invokedAbilityPrompts+1] = monsterType .. ":Invoked Ability"
end

MonsterAI:RegisterPrompt{
    prompts = invokedAbilityPrompts,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return SplitPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
            or MaliceEmitterPayoutPrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    end,
}
