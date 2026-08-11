local mod = dmhub.GetModLoading()

local chimeraMonster = {"Chimera"}
local chimeraGroup = {"Chimera"}

local movementPause = 0.6
local abilityPause = 1.0

local defensiveSnappingEffectId = "7b7e5aff-4aa2-43de-aad8-f38e1507ceb5"
local defensiveSnappingFreeStrikePrompt =
    "The chimera makes a free strike against each enemy who comes within 2 squares of them."

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject and token.properties ~= nil
        and not token.properties:IsDead()
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

local function FindAbility(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

local function FindTokenByCharid(charid)
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.charid == charid then
            return token
        end
    end
end

local function EnemyTokens(token)
    local result = {}
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and not other:IsFriend(token) then
            result[#result+1] = other
        end
    end
    return result
end

local function EnemiesWithin(token, range, ability)
    local result = {}
    for _,enemy in ipairs(EnemyTokens(token)) do
        if token:Distance(enemy) <= range
            and (ability == nil or ability:TargetPassesFilter(token, enemy, {})) then
            result[#result+1] = enemy
        end
    end
    return result
end

local function MoveCinematically(ai, token, loc)
    if loc ~= nil and loc.str ~= token.loc.str then
        token:Move(loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(movementPause)
    end
end

local function BiteTargetScore(target, edges)
    if target.isObject then
        return 0.1
    end

    local stamina = target.properties:CurrentHitpoints()
        / math.max(1, target.properties.max_hitpoints)
    return 1 + (edges or 0)*0.25 + (1 - stamina)*0.15
end

local function TossTargetScore(target, edges)
    if target.isObject then
        return 0.1
    end
    return 1 + (edges or 0)*0.1
end

local function SortedStrikeTargets(ai, token, ability, loc, scorefn)
    local targets = ai:FindValidTargetsOfStrike(token, ability, loc)
    if scorefn ~= nil then
        table.sort(targets, function(a, b)
            return scorefn(a.token, a.edges) > scorefn(b.token, b.edges)
        end)
    end
    table.resize_array(targets, ability:GetNumTargets(token))
    return targets
end

local function ExecuteStrike(ai, token, scoringInfo, ability, scorefn)
    MoveCinematically(ai, token, scoringInfo.loc)
    local targets = SortedStrikeTargets(ai, token, ability, scoringInfo.loc, scorefn)
    ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
end

local function TokensInArea(casterToken, ability, area, symbols)
    local result = {}
    symbols = symbols or {}
    symbols.targetArea = area
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if target.valid and ability:TargetPassesFilter(casterToken, target, symbols) then
            result[#result+1] = {token = target}
        end
    end
    return result
end

local function CountCreaturesByAllegiance(casterToken, targets)
    local enemies = 0
    local allies = 0
    for _,targetInfo in ipairs(targets) do
        local target = targetInfo.token
        if LiveCreature(target) then
            if target:IsFriend(casterToken) then
                allies = allies + 1
            else
                enemies = enemies + 1
            end
        end
    end
    return enemies, allies
end

local function BuildCubeArea(token, ability, center)
    return dmhub.CalculateShape{
        shape = "cube",
        targetPoint = token:PosAtLoc(center),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        checklos = false,
        altitude = center.altitude * dmhub.unitsPerSquare,
    }
end

local function ExecuteAreaAbility(ai, token, ability, area, targets)
    local options = {
        sleep = abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
    }
    local abilityClone = DeepCopy(ability)
    abilityClone.targetType = "target"
    abilityClone.numTargets = math.max(1, #targets)
    ai:ExecuteAbility(token, abilityClone, targets, options)
    if type(area.Destroy) == "function" then
        area:Destroy()
    end
end

local function FindBestCubePlan(token, ability, enemies)
    local best = nil
    local checked = {}
    for _,enemy in ipairs(enemies) do
        if LiveCreature(enemy) and token:Distance(enemy) <= ability:GetRange(token.properties)
            and not checked[enemy.loc.str] then
            checked[enemy.loc.str] = true
            local area = BuildCubeArea(token, ability, enemy.loc)
            local targets = TokensInArea(token, ability, area, {})
            local numEnemies, numAllies = CountCreaturesByAllegiance(token, targets)
            local value = numEnemies - numAllies*2
            if best == nil or value > best.value then
                best = {
                    center = enemy.loc,
                    numEnemies = numEnemies,
                    numAllies = numAllies,
                    value = value,
                }
            end
            if type(area.Destroy) == "function" then
                area:Destroy()
            end
        end
    end
    return best
end

local function NearestEnemyDistance(token, loc)
    local result = 10000
    for _,enemy in ipairs(EnemyTokens(token)) do
        result = math.min(result, enemy:Distance(loc))
    end
    return result
end

local function FindVolantDestination(token)
    local currentDistance = NearestEnemyDistance(token, token.loc)
    local paths = token:CalculatePathfindingArea(
        token.properties:CurrentMovementSpeed()*10,
        {})
    local best = nil
    for _,info in pairs(paths) do
        local distance = NearestEnemyDistance(token, info.loc)
        local value = -distance - (info.cost or 0)*0.001
        if distance < currentDistance and (best == nil or value > best.value) then
            best = {loc = info.loc, value = value}
        end
    end
    return best
end

local function FindRamDefianceDestination(token, target)
    local paths = token:CalculatePathfindingArea(50, {"shift"})
    local best = nil
    for _,info in pairs(paths) do
        local distance = target ~= nil and target:Distance(info.loc)
            or NearestEnemyDistance(token, info.loc)
        local inStrikeRange = target ~= nil and distance <= 2
        local value = cond(inStrikeRange, 100, 0) - distance - (info.cost or 0)*0.001
        if best == nil or value > best.value then
            best = {loc = info.loc, value = value}
        end
    end
    return best
end

local function FindChorusDestination(token)
    local paths = token:CalculatePathfindingArea(
        token.properties:CurrentMovementSpeed()*10,
        {"shift"})
    local enemies = EnemyTokens(token)
    local best = nil
    for _,info in pairs(paths) do
        local adjacent = 0
        local nearest = 10000
        for _,enemy in ipairs(enemies) do
            local distance = enemy:Distance(info.loc)
            nearest = math.min(nearest, distance)
            if distance <= 1 then
                adjacent = adjacent + 1
            end
        end
        local value = adjacent*3 - nearest*0.1 - (info.cost or 0)*0.001
        if best == nil or value > best.value then
            best = {loc = info.loc, value = value}
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- Main actions and maneuver.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Chimera: Bite",
    category = "Main Actions",
    monsters = chimeraMonster,
    abilities = {"Bite"},
    description = "Bite up to two enemies, preferring targets that grant an edge and wounded enemies.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, BiteTargetScore)
        if loc ~= nil then
            return {score = 1.2 + math.min(0.15, targetScore*0.04), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteStrike(ai, token, scoringInfo, ability, BiteTargetScore)
    end,
}

MonsterAI:RegisterMove{
    id = "Chimera: Dragon's Eruption",
    category = "Main Actions",
    monsters = chimeraMonster,
    abilities = {"Dragon's Eruption"},
    description = "Spend 5 Malice on Dragon's Eruption when its cube catches at least two enemies without catching allies.",
    score = function(self, ai, token, ability)
        local plan = FindBestCubePlan(token, ability, ai.enemyTokens)
        if plan ~= nil and plan.value >= 2 then
            return {
                score = 1.65 + math.min(0.25, (plan.value - 2)*0.1),
                center = plan.center,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local area = BuildCubeArea(token, ability, scoringInfo.center)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Chimera: Roar",
    category = "Main Actions",
    monsters = chimeraMonster,
    abilities = {"Roar"},
    description = "Spend 5 Malice on Roar when the chimera can catch at least two enemies in its burst.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseBurst(token, ability, function(target)
            return cond(target:IsFriend(token), -2, 1)
        end)
        if loc ~= nil and targetScore ~= nil and targetScore >= 2 then
            return {
                score = 1.6 + math.min(0.25, (targetScore - 2)*0.1),
                loc = loc,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Chimera: Lion's Toss",
    category = "Maneuvers",
    monsters = chimeraMonster,
    abilities = {"Lion's Toss "},
    description = "Use Lion's Toss after the main action to hurl the best available nearby enemy vertically.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, TossTargetScore)
        if loc ~= nil then
            return {score = 0.9 + math.min(0.1, targetScore*0.03), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteStrike(ai, token, scoringInfo, ability, TossTargetScore)
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Malice abilities.
--------------------------------------------------------------------------------

MonsterAI:RegisterMaliceAbility{
    id = "Chimera Malice: Defensive Snapping",
    monsterGroups = chimeraGroup,
    abilities = {"Defensive Snapping"},
    description = "Spend 3 Malice on Defensive Snapping when enemies are close enough to threaten its reaction area.",
    score = function(self, ai, token, ability, context)
        if HasOngoingEffect(token, defensiveSnappingEffectId) then
            return nil
        end
        local nearbyEnemies = #EnemiesWithin(token, 4)
        if nearbyEnemies > 0 then
            return {score = math.min(0.77, 0.67 + nearbyEnemies*0.04)}
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Chimera Malice: Solo Action",
    monsterGroups = chimeraGroup,
    abilities = {"Solo Action"},
    description = "Spend 5 Malice for an additional main action while at least one enemy remains.",
    score = function(self, ai, token, ability, context)
        if #context.enemyTokens > 0 then
            return {score = 0.78}
        end
    end,
}

--------------------------------------------------------------------------------
-- Trigger and nested prompt decisions.
--------------------------------------------------------------------------------

MonsterAI:RegisterTrigger{
    id = "Chimera: Volant",
    monsters = chimeraMonster,
    abilities = {"Volant"},
    triggers = {"Volant"},
    description = "Use Volant after winding or defeating an enemy to move toward the next enemy.",
    handler = function(ai, token, triggerInfo)
        local plan = FindVolantDestination(token)
        if plan == nil then
            return {dismiss = true}
        end
        return {
            activate = true,
            expectedPrompt = {
                casterid = token.charid,
                targets = {{loc = plan.loc}},
                sleep = movementPause,
            },
        }
    end,
}

MonsterAI:RegisterTrigger{
    id = "Chimera: Ram's Defiance",
    monsters = chimeraMonster,
    abilities = {"Ram's Defiance"},
    triggers = {"Ram's Defiance"},
    description = "Use Ram's Defiance on a tier-1 strike and shift into range of the triggering creature when possible.",
    handler = function(ai, token, triggerInfo)
        local target = nil
        for _,charid in ipairs(triggerInfo.targets or {}) do
            local candidate = FindTokenByCharid(charid)
            if LiveCreature(candidate) and not candidate:IsFriend(token) then
                target = candidate
                break
            end
        end

        local plan = FindRamDefianceDestination(token, target)
        if plan == nil then
            return {activate = true}
        end
        return {
            activate = true,
            expectedPrompt = {
                casterid = token.charid,
                targets = {{loc = plan.loc}},
                sleep = movementPause,
            },
        }
    end,
}

MonsterAI:RegisterTrigger{
    id = "Chimera: End Effect",
    monsters = chimeraMonster,
    abilities = {"End Effect"},
    triggers = {"End effect for 5"},
    description = "Take 5 damage to end a save-ends effect unless doing so would reduce the chimera to 0 Stamina.",
    handler = function(ai, token, triggerInfo)
        if token.properties:CurrentHitpoints() > 5 then
            return {activate = true}
        end
        return {dismiss = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Chimera: Defensive Snapping",
    monsters = chimeraMonster,
    abilities = {"Defensive Snapping"},
    triggers = {"Defensive Snapping"},
    description = "Accept Defensive Snapping when an enemy enters its reaction area.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Chimera: Defensive Snapping Free Strike",
    monsters = chimeraMonster,
    triggers = {defensiveSnappingFreeStrikePrompt},
    description = "Resolve Defensive Snapping's authored follow-up free-strike invocation.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Chimera:Ranged Free Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targets = {}
        local range = abilityClone:GetRange(casterToken.properties)
        for _,enemy in ipairs(EnemyTokens(casterToken)) do
            if casterToken:Distance(enemy) <= range
                and abilityClone:TargetPassesFilter(casterToken, enemy, symbols) then
                targets[#targets+1] = {token = enemy}
            end
        end
        table.resize_array(targets, abilityClone:GetNumTargets(casterToken))
        if #targets > 0 then
            return {targets = targets}
        end
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Chimera:Dragon's Eruption - No Malice"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = FindBestCubePlan(casterToken, abilityClone, EnemyTokens(casterToken))
        if plan ~= nil then
            return {targets = {{loc = plan.center}}}
        end
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Chimera:Chorus of Destruction "},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = FindChorusDestination(casterToken)
        if plan ~= nil then
            return {targets = {{loc = plan.loc}}}
        end
    end,
}

--------------------------------------------------------------------------------
-- Villain actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterVillainAction{
    id = "Chimera: Overture of Destruction",
    monsters = chimeraMonster,
    abilities = {"Overture of Destruction "},
    description = "Use Overture of Destruction when one or more enemies are adjacent, with greater urgency for a crowd.",
    score = function(self, ai, token, ability, context)
        local enemies = #EnemiesWithin(token, ability:GetRange(token.properties), ability)
        if enemies > 0 then
            return {score = math.min(1, 0.55 + enemies*0.12), enemies = enemies}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Chimera: Fire Solo",
    monsters = chimeraMonster,
    abilities = {"Fire Solo "},
    description = "Use Fire Solo when Dragon's Eruption or Roar can catch useful enemy targets.",
    score = function(self, ai, token, ability, context)
        local eruption = FindAbility(token, "Dragon's Eruption")
        local plan = eruption ~= nil and FindBestCubePlan(token, eruption, ai.enemyTokens) or nil
        local roar = FindAbility(token, "Roar")
        local roarTargets = roar ~= nil and #EnemiesWithin(token, roar:GetRange(token.properties), roar) or 0
        local eruptionTargets = plan ~= nil and plan.numEnemies or 0
        if eruptionTargets > 0 or roarTargets > 0 then
            return {
                score = math.min(1, 0.5 + eruptionTargets*0.1 + roarTargets*0.08),
                center = plan ~= nil and plan.center or nil,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        if scoringInfo.center ~= nil then
            ai:SetTargetsForExpectedPrompt{
                casterid = token.charid,
                targets = {{loc = scoringInfo.center}},
                sleep = movementPause,
            }
        end
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Chimera: Chorus of Destruction",
    monsters = chimeraMonster,
    abilities = {"Chorus of Destruction "},
    description = "Use Chorus of Destruction while enemies remain, choosing a shift that passes through the fight and sets up its follow-up attacks.",
    score = function(self, ai, token, ability, context)
        local enemies = #ai.enemyTokens
        if enemies > 0 then
            local nearby = #EnemiesWithin(token, 5)
            return {score = math.min(1, 0.55 + nearby*0.1 + enemies*0.03)}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local plan = FindChorusDestination(token)
        if plan ~= nil then
            ai:SetTargetsForExpectedPrompt{
                casterid = token.charid,
                targets = {{loc = plan.loc}},
                sleep = movementPause,
            }
        end
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}
