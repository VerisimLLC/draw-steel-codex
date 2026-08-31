local mod = dmhub.GetModLoading()

local arixxMonster = {"Arixx"}
local arixxGroup = {"Arixx"}

local movementPause = 0.6
local abilityPause = 1.0

local burningMawEffectId = "76d21112-ebb3-4818-ad73-baa43fdc919f"
local earthSinkEffectId = "163c875b-20ff-4846-bdb2-3a11ed0f058a"
local startedTurnUndergroundEffectId = "4982ddf6-975b-44a6-aede-9a6ca2ea3fd9"

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

local function MoveCinematically(ai, token, loc)
    if loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc) then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
        ai.Sleep(movementPause)
    end
end

local function IsGrabbed(token)
    return token.properties:HasNamedCondition("Grabbed")
end

local function BiteTargetScore(token)
    if token.isObject then
        return 0.1
    end
    local score = 1
    if token.properties:CreatureSizeWhenBeingForceMoved() <= 1 then
        score = score + 0.3
    end
    if not IsGrabbed(token) then
        score = score + 0.15
    end
    local stamina = token.properties:CurrentHitpoints()
        / math.max(1, token.properties.max_hitpoints)
    return score + (1 - stamina)*0.1
end

local function ClawTargetScore(token)
    if token.isObject then
        return 0.1
    end
    return 1 + cond(IsGrabbed(token), 0, 0.2)
end

local function SpitfireTargetScore(token)
    if token.isObject then
        return 0.1
    end
    local stamina = token.properties:CurrentHitpoints()
        / math.max(1, token.properties.max_hitpoints)
    return 1 + stamina*0.15
end

local function SortedStrikeTargets(ai, token, ability, loc, scorefn)
    local targets = ai:FindValidTargetsOfStrike(token, ability, loc)
    if scorefn ~= nil then
        table.sort(targets, function(a, b)
            return scorefn(a.token) > scorefn(b.token)
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

local function BuildLineArea(token, ability, targetLoc)
    return dmhub.CalculateShape{
        shape = "line",
        targetPoint = token:PosAtLoc(targetLoc),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        checklos = true,
        altitude = token.loc.altitude * dmhub.unitsPerSquare,
    }
end

local function ExecuteAreaAbility(ai, token, ability, area, targets)
    local options = {
        sleep = abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
    }
    local abilityClone = DeepCopy(ability)
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

local function EnemiesWithin(token, range, ability)
    local result = {}
    for _,target in ipairs(dmhub.allTokens) do
        if LiveCreature(target) and not target:IsFriend(token)
            and token:Distance(target) <= range
            and (ability == nil or ability:TargetPassesFilter(token, target, {})) then
            result[#result+1] = target
        end
    end
    return result
end

local function FindDustCloudDestination(ai, token)
    local plans = {
        {ability = FindAbility(token, "Claw Swing"), scorefn = ClawTargetScore},
        {ability = FindAbility(token, "Bite"), scorefn = BiteTargetScore},
        {ability = FindAbility(token, "Spitfire"), scorefn = SpitfireTargetScore},
    }
    local best = nil
    for _,plan in ipairs(plans) do
        if plan.ability ~= nil and plan.ability:CanAfford(token) then
            local loc, score = ai:FindBestMoveToUseStrike(token, plan.ability, plan.scorefn)
            if loc ~= nil and (best == nil or score > best.score) then
                best = {loc = loc, score = score}
            end
        end
    end
    return best
end

local function FindSinkholePlan(ai, token)
    local bite = FindAbility(token, "Bite")
    if bite == nil then
        return nil
    end

    local paths = token:CalculatePathfindingArea(
        token.properties:CurrentMovementSpeed()*10,
        {"shift"})
    local best = nil
    for _,info in pairs(paths) do
        local targets = SortedStrikeTargets(ai, token, bite, info.loc, BiteTargetScore)
        if #targets > 0 then
            local target = targets[1].token
            local value = BiteTargetScore(target) - (info.cost or 0)*0.001
            if best == nil or value > best.value then
                best = {loc = info.loc, target = target, value = value}
            end
        end
    end
    return best
end

local function FindSkitterDestination(token)
    local paths = token:CalculatePathfindingArea(30, {"shift"})
    local best = nil
    for _,info in pairs(paths) do
        local nearestEnemy = 1000
        for _,other in ipairs(dmhub.allTokens) do
            if LiveCreature(other) and not other:IsFriend(token) then
                nearestEnemy = math.min(nearestEnemy, other:Distance(info.loc))
            end
        end
        local value = nearestEnemy - (info.cost or 0)*0.001
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
    id = "Arixx: Bite",
    category = "Main Actions",
    monsters = arixxMonster,
    abilities = {"Bite"},
    description = "Bite a vulnerable nearby enemy, preferring size 1 targets that are not already grabbed.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, BiteTargetScore)
        if loc ~= nil then
            return {score = 1.2 + math.min(0.15, targetScore*0.05), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteStrike(ai, token, scoringInfo, ability, BiteTargetScore)
    end,
}

MonsterAI:RegisterMove{
    id = "Arixx: Claw Swing",
    category = "Main Actions",
    monsters = arixxMonster,
    abilities = {"Claw Swing"},
    description = "Use Claw Swing when the arixx can catch two enemies, preferring creatures not already grabbed.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, ClawTargetScore)
        if loc ~= nil and targetScore >= 1.8 then
            return {score = 1.45 + math.min(0.15, (targetScore - 1.8)*0.1), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteStrike(ai, token, scoringInfo, ability, ClawTargetScore)
    end,
}

MonsterAI:RegisterMove{
    id = "Arixx: Spitfire",
    category = "Main Actions",
    monsters = arixxMonster,
    abilities = {"Spitfire"},
    description = "Use Spitfire at range, with a preference for catching two healthy enemies in persistent burning acid.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseStrike(token, ability, SpitfireTargetScore)
        if loc == nil then
            return nil
        end
        if targetScore >= 1.8 then
            return {score = 1.3 + math.min(0.15, (targetScore - 1.8)*0.1), loc = loc}
        end
        return {score = 0.95, loc = loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteStrike(ai, token, scoringInfo, ability, SpitfireTargetScore)
    end,
}

MonsterAI:RegisterMove{
    id = "Arixx: Dirt Devil",
    category = "Main Actions",
    monsters = arixxMonster,
    abilities = {"Dirt Devil"},
    description = "Spend 3 Malice on Dirt Devil when its burst can catch at least two enemies without endangering allies.",
    score = function(self, ai, token, ability)
        local loc, targetScore = ai:FindBestMoveToUseBurst(token, ability, function(target)
            return cond(target:IsFriend(token), -2, 1)
        end)
        if loc ~= nil and targetScore >= 2 then
            local undergroundBonus = cond(HasOngoingEffect(token, startedTurnUndergroundEffectId), 0.2, 0)
            return {
                score = 1.65 + undergroundBonus + math.min(0.2, (targetScore - 2)*0.1),
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
    id = "Arixx: Dust Cloud",
    category = "Maneuvers",
    monsters = arixxMonster,
    abilities = {"Dust Cloud"},
    description = "Kick up a defensive dust cloud when an enemy is adjacent, then use the granted move to set up the next strike.",
    score = function(self, ai, token, ability)
        if #EnemiesWithin(token, ability:GetRange(token.properties), ability) == 0 then
            return nil
        end
        local plan = FindDustCloudDestination(ai, token)
        if plan ~= nil then
            return {score = 1.6, loc = plan.loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:SetTargetsForExpectedPrompt{
            casterid = token.charid,
            targets = {{loc = scoringInfo.loc}},
            sleep = movementPause,
        }
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Malice abilities.
--------------------------------------------------------------------------------

MonsterAI:RegisterMaliceAbility{
    id = "Arixx Malice: Burning Maw",
    monsterGroups = arixxGroup,
    abilities = {"Burning Maw"},
    description = "Spend 3 Malice when the arixx has an enemy to strike and Burning Maw is not already active.",
    score = function(self, ai, token, ability, context)
        if HasOngoingEffect(token, burningMawEffectId) or #context.enemyTokens == 0 then
            return nil
        end
        return {score = 0.7}
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Arixx Malice: Geyser",
    monsterGroups = arixxGroup,
    abilities = {"Geyser"},
    description = "Spend 5 Malice to erupt a geyser beneath a cluster of at least two enemies.",
    score = function(self, ai, token, ability, context)
        local plan = FindBestCubePlan(token, ability, context.enemyTokens)
        if plan ~= nil and plan.value >= 2 then
            return {
                score = math.min(1, 0.7 + plan.numEnemies*0.08 - plan.numAllies*0.15),
                center = plan.center,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.center)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Arixx Malice: Solo Action",
    monsterGroups = arixxGroup,
    abilities = {"Solo Action"},
    description = "Spend 5 Malice for an additional main action when at least one enemy remains.",
    score = function(self, ai, token, ability, context)
        if #context.enemyTokens > 0 then
            return {score = 0.78}
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Arixx Malice: Earth Sink",
    monsterGroups = arixxGroup,
    abilities = {"Earth Sink"},
    description = "Spend 7 Malice early to hinder multiple enemies with the encounter-long Earth Sink effect.",
    minimumScore = 0.8,
    score = function(self, ai, token, ability, context)
        if context.round ~= nil and context.round > 2 then
            return nil
        end
        for _,other in ipairs(dmhub.allTokens) do
            if HasOngoingEffect(other, earthSinkEffectId) then
                return nil
            end
        end

        local affectedEnemies = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if LiveCreature(enemy) and ability:TargetPassesFilter(token, enemy, {}) then
                affectedEnemies = affectedEnemies + 1
            end
        end
        if affectedEnemies >= 2 then
            return {score = math.min(1, 0.77 + affectedEnemies*0.06)}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,target in ipairs(dmhub.allTokens) do
            if LiveCreature(target) and ability:TargetPassesFilter(token, target, {}) then
                targets[#targets+1] = {token = target}
            end
        end

        local abilityClone = DeepCopy(ability)
        abilityClone.targetType = "target"
        abilityClone.numTargets = math.max(1, #targets)
        ai:ExecuteAbility(token, abilityClone, targets, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Trigger and nested prompt decisions.
--------------------------------------------------------------------------------

MonsterAI:RegisterTrigger{
    id = "Arixx: Skitter",
    monsters = arixxMonster,
    abilities = {"Skitter"},
    triggers = {"Skitter"},
    description = "Use Skitter to halve incoming damage, then shift away from the nearest enemies.",
    handler = function(ai, token, triggerInfo)
        local plan = FindSkitterDestination(token)
        if plan ~= nil then
            return {
                activate = true,
                expectedPrompt = {
                    targets = {{loc = plan.loc}},
                    sleep = movementPause,
                },
            }
        end
        return {activate = true}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Arixx:Bite"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targets = {}
        local range = abilityClone:GetRange(casterToken.properties)
        for _,target in ipairs(dmhub.allTokens) do
            if LiveCreature(target) and not target:IsFriend(casterToken)
                and casterToken:Distance(target) <= range
                and abilityClone:TargetPassesFilter(casterToken, target, symbols) then
                targets[#targets+1] = {token = target}
            end
        end
        table.sort(targets, function(a, b)
            return BiteTargetScore(a.token) > BiteTargetScore(b.token)
        end)
        if #targets > 0 then
            return {targets = {targets[1]}}
        end
        return "skip"
    end,
}

--------------------------------------------------------------------------------
-- Villain actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterVillainAction{
    id = "Arixx: Acid Spew",
    monsters = arixxMonster,
    abilities = {"Acid Spew"},
    description = "Aim Acid Spew along the line that catches the most enemies while avoiding allies.",
    score = function(self, ai, token, ability, context)
        local plan = ai:FindBestLinePlan(token, ability, {
            candidates = ai.enemyTokens,
            scorefn = function(target)
                if not LiveCreature(target) then
                    return 0
                end
                return cond(target:IsFriend(token), -1.5, 1)
            end,
        })
        local numEnemies, numAllies = 0, 0
        if plan ~= nil then
            numEnemies, numAllies = CountCreaturesByAllegiance(token, plan.targets)
        end
        if plan ~= nil and numEnemies > 0 and plan.score > 0 then
            return {
                score = math.min(1, 0.5 + numEnemies*0.13 - numAllies*0.15),
                targetLoc = plan.targetLoc,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildLineArea(token, ability, scoringInfo.targetLoc)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Arixx: Sinkhole",
    monsters = arixxMonster,
    abilities = {"Sinkhole "},
    description = "Shift into Bite range, attack the best target, then use Dig through the authored Sinkhole sequence.",
    score = function(self, ai, token, ability, context)
        local plan = FindSinkholePlan(ai, token)
        if plan ~= nil then
            return {score = 0.78, loc = plan.loc, target = plan.target}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ai:SetTargetsForExpectedPrompt{
            casterid = token.charid,
            targets = {{loc = scoringInfo.loc}},
            sleep = movementPause,
        }
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Arixx: Acid and Claws",
    monsters = arixxMonster,
    abilities = {"Acid and Claws"},
    description = "Use Acid and Claws when its burst catches one or more enemies, with greater urgency for a crowd.",
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
