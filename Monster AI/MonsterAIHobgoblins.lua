local mod = dmhub.GetModLoading()

local movementPause = 0.6
local stationaryPause = 0.35
local speechPause = 0.45
local abilityPause = 0.9

local hobgoblinSpeech = {
    ["Hobgoblin Burning Witch: Burning Legion"] = {
        "Burn in formation!",
        "Take your places in the fire!",
        "The legion marches in flame!",
    },
    ["Hobgoblin Grandguard: Thunder Rush"] = {
        "Break their line!",
        "Shields forward!",
        "Trample them!",
    },
    ["Hobgoblin Bloodlord: Advance!"] = {
        "Advance! Leave none standing.",
        "Forward! Burn through them.",
        "The line moves as one.",
    },
    ["Hobgoblin Bloodlord: Skulls Abound"] = {
        "The fallen still serve.",
        "Skulls, attend your lord.",
        "Death circles close.",
    },
    ["Hobgoblin Bloodlord: I am Fire! I am Death!"] = {
        "I am fire! I am death!",
        "Kneel before the black flame.",
        "Burn with me.",
    },
}

local burningEffectId = "420d80fa-3784-4b7e-9b6c-586deed49d4e"
local flameslingerWeaknessEffectId = "8a04f32a-f942-4d30-9c28-69c997a190a2"
local enchantmentsEdgeEffectId = "f02a12ec-b938-4798-86b3-ddddd7fe0eb3"
local skullsAboundEffectId = "1b04405a-fd3a-407c-9a59-583e17105a3d"
local operationGoblinModeEffectId = "82d4fbb9-2640-41bf-be1d-ac65adc6b948"
local goblinModeEffectId = "5646898c-0c0e-4973-823e-13172eaaaba2"
local defendEffectId = "5ca9517b-ddbf-4f61-bd59-68e3a62708eb"
local operationEarthSearAbilityId = "1602821e-4616-4ce0-af52-250c8f6620cb"
local swampStinkAbilityId = "2b213b4b-43cd-4c08-bc17-d047e84765f4"

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject
        and token.properties ~= nil and not token.properties:IsDead()
end

local function MonsterType(token)
    if token == nil or token.properties == nil then
        return ""
    end
    return token.properties:try_get("monster_type", "")
end

local function FindTokenByCharid(charid)
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.charid == charid then
            return token
        end
    end
end

local function FindAbility(token, name)
    if not LiveCreature(token) then
        return nil
    end
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name then
            return ability
        end
    end
end

local function HasOngoingEffect(token, effectid)
    if not LiveCreature(token) then
        return false
    end

    local effects = nil
    pcall(function()
        effects = token.properties:ActiveOngoingEffects(true)
    end)
    for _,effect in ipairs(effects or {}) do
        if effect.ongoingEffectid == effectid then
            return true
        end
    end
    return false
end

local function HasCondition(token, conditionName)
    local result = false
    if LiveCreature(token) then
        pcall(function()
            result = token.properties:HasNamedCondition(conditionName)
        end)
    end
    return result
end

local function AttributeValue(token, attributeName, fallback)
    local result = fallback
    if LiveCreature(token) then
        pcall(function()
            result = token.properties:GetAttribute(attributeName):Value()
        end)
    end
    return result
end

local function CanSpendMalice(amount)
    return (CharacterResource.GetMalice() or 0) >= amount
end

local function OnGround(token)
    local moveType = nil
    if LiveCreature(token) then
        pcall(function()
            moveType = token.properties:CurrentMoveType()
        end)
    end
    return moveType == nil
        or (moveType ~= "fly" and moveType ~= "burrow" and moveType ~= "climb")
end

local function HasAuraFromAbility(abilityid)
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil then
            for _,aura in ipairs(token.properties:try_get("auras", {})) do
                if aura:try_get("sourceAbilityId") == abilityid then
                    return true
                end
            end
        end
    end
    return false
end

local function MatchingCombatTargets(caster, ability, context)
    local targets = {}
    local allies = {}
    local enemies = {}
    local seen = {}

    local function AddTargets(tokens, output)
        for _,target in ipairs(tokens or {}) do
            if LiveCreature(target) and not seen[target.charid]
                and ability:TargetPassesFilter(caster, target, {}) then
                seen[target.charid] = true
                targets[#targets+1] = target
                output[#output+1] = target
            end
        end
    end

    AddTargets(context.allyTokens, allies)
    AddTargets(context.enemyTokens, enemies)
    return targets, allies, enemies
end

local function HasCreatureKeyword(token, keyword)
    local keywords = nil
    if LiveCreature(token) then
        pcall(function()
            keywords = token.properties:Keywords()
        end)
    end
    if type(keywords) ~= "table" then
        return false
    end

    keyword = string.lower(keyword)
    for name,value in pairs(keywords) do
        if value and string.lower(tostring(name)) == keyword then
            return true
        end
    end
    return false
end

local function Speak(ai, token, moveid)
    local lines = hobgoblinSpeech[moveid]
    if lines ~= nil then
        ai:Speech(token, lines)
        ai.Sleep(speechPause)
    end
end

local function MoveCinematically(ai, token, loc)
    local moving = loc ~= nil and loc.str ~= token.loc.str
    if moving then
        token:Move(loc, {maxCost = 10000, ignoreFalling = false})
    end
    ai.Sleep(cond(moving, movementPause, stationaryPause))
end

local function EmptyLoc(loc, reserved)
    if loc == nil or not loc.valid or not loc.isOnMap
        or (reserved ~= nil and reserved[loc.str]) then
        return false
    end
    for _,token in ipairs(dmhub.GetTokensAtLoc(loc) or {}) do
        if token.valid then
            return false
        end
    end
    return true
end

local function DefaultTargetScore(targetInfo)
    if targetInfo.token.isObject then
        return 0.1
    end
    local stamina = targetInfo.token.properties:CurrentHitpoints()
        / math.max(1, targetInfo.token.properties.max_hitpoints)
    return 1 + (targetInfo.edges or 0)*0.1 + (1 - stamina)*0.08
end

-- Build a full movement-and-target plan so scoring and execution use the same
-- targets. The core helper only returns the destination.
local function FindBestStrikePlan(ai, token, ability, targetScore, paths)
    targetScore = targetScore or DefaultTargetScore
    paths = paths or ai.paths
    local range = ability:GetRange(token.properties)
    local numTargets = ability:GetNumTargets(token)
    local best = nil

    for _,pathInfo in pairs(paths or {}) do
        local candidates = {}
        for _,targetInfo in ipairs(ai:FindValidTargetsOfStrike(
            token, ability, pathInfo.loc, range)) do
            local score = targetScore(targetInfo)
            if score ~= nil then
                candidates[#candidates+1] = {info = targetInfo, score = score}
            end
        end

        table.sort(candidates, function(a, b)
            return a.score > b.score
        end)

        local targets = {}
        local utility = 0
        for i=1,math.min(numTargets, #candidates) do
            targets[#targets+1] = candidates[i].info
            utility = utility + candidates[i].score
        end

        if #targets > 0 then
            utility = utility - (pathInfo.cost or 0)*0.001
            if best == nil or utility > best.utility then
                best = {
                    loc = pathInfo.loc,
                    targets = targets,
                    utility = utility,
                }
            end
        end
    end

    return best
end

local function ExecuteStrikePlan(ai, token, scoringInfo, ability, options)
    options = options or {}
    MoveCinematically(ai, token, scoringInfo.loc)
    local executingAbility = options.ability or ability
    ai:ExecuteAbility(token, executingAbility, scoringInfo.targets, {
        sleep = options.sleep or abilityPause,
        symbols = options.symbols,
    })
end

local function RegisterStrike(args)
    MonsterAI:RegisterMove{
        id = args.id,
        category = args.category or "Main Actions",
        monsters = args.monsters,
        abilities = {args.ability},
        description = args.description,
        score = function(self, ai, token, ability)
            local plan = FindBestStrikePlan(ai, token, ability, args.targetScore)
            if plan ~= nil then
                plan.score = type(args.score) == "function"
                    and args.score(token, ability, plan) or (args.score or 1)
                return plan
            end
        end,
        execute = function(self, ai, token, scoringInfo, ability)
            if args.execute ~= nil then
                args.execute(self, ai, token, scoringInfo, ability)
            else
                ExecuteStrikePlan(ai, token, scoringInfo, ability)
            end
        end,
    }
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

local function BuildMapArea(token)
    return dmhub.CalculateShape{
        shape = "map",
        token = token,
    }
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

local function CountByAllegiance(casterToken, targets)
    local enemies = 0
    local allies = 0
    for _,targetInfo in ipairs(targets or {}) do
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

local function ExecuteAreaAbility(ai, token, ability, area, targets, options)
    options = options or {}
    local abilityClone = options.ability or DeepCopy(ability)
    abilityClone.targetType = "target"
    abilityClone.numTargets = math.max(1, #targets)
    ai:ExecuteAbility(token, abilityClone, targets, {
        sleep = options.sleep or abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
    })
    if type(area.Destroy) == "function" then
        area:Destroy()
    end
end

local function FindBestCubePlan(token, ability, candidates, allyPenalty)
    allyPenalty = allyPenalty or 2
    local best = nil
    local checked = {}
    for _,candidate in ipairs(candidates or {}) do
        if LiveCreature(candidate)
            and token:Distance(candidate) <= ability:GetRange(token.properties)
            and not checked[candidate.loc.str] then
            checked[candidate.loc.str] = true
            local area = BuildCubeArea(token, ability, candidate.loc)
            local targets = TokensInArea(token, ability, area, {})
            local enemies, allies = CountByAllegiance(token, targets)
            local utility = enemies - allies*allyPenalty
            if best == nil or utility > best.utility then
                best = {
                    center = candidate.loc,
                    enemies = enemies,
                    allies = allies,
                    targets = targets,
                    utility = utility,
                }
            end
            if type(area.Destroy) == "function" then
                area:Destroy()
            end
        end
    end
    return best
end

local function FindBestLinePlanFromPaths(ai, token, ability)
    local best = nil
    for _,pathInfo in pairs(ai.paths or {}) do
        local candidates = {}
        for _,enemy in ipairs(ai.enemyTokens) do
            if LiveCreature(enemy) then
                candidates[#candidates+1] = {
                    targetLoc = enemy.loc,
                    locOverride = pathInfo.loc,
                }
            end
        end

        local plan = ai:FindBestLinePlan(token, ability, {
            candidates = candidates,
            scorefn = function(target)
                return cond(target:IsFriend(token), -3, 1)
            end,
        })
        if plan ~= nil then
            local enemies, allies = CountByAllegiance(token, plan.targets)
            local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
            if enemies > 0 and allies == 0
                and (best == nil or utility > best.utility) then
                best = {
                    loc = pathInfo.loc,
                    targetLoc = plan.targetLoc,
                    targets = plan.targets,
                    enemies = enemies,
                    utility = utility,
                }
            end
        end
    end
    return best
end

local function FindNearestEnemyDistance(ai, loc)
    local result = 10000
    local enemies = ai:try_get("enemyTokens")
    if enemies == nil then
        enemies = {}
        local actingToken = ai:try_get("token")
        for _,other in ipairs(dmhub.allTokens) do
            if LiveCreature(other) and LiveCreature(actingToken)
                and not other:IsFriend(actingToken) then
                enemies[#enemies+1] = other
            end
        end
    end
    for _,enemy in ipairs(enemies) do
        if LiveCreature(enemy) then
            result = math.min(result, enemy:Distance(loc))
        end
    end
    return result
end

local function FindRepositionLoc(ai, token, range, retreat)
    local best = nil
    for _,info in pairs(token:CalculatePathfindingArea(range*10, {})) do
        local distance = FindNearestEnemyDistance(ai, info.loc)
        local utility = cond(retreat, distance, -distance)
            - (info.cost or 0)*0.001
        if best == nil or utility > best.utility then
            best = {loc = info.loc, utility = utility}
        end
    end
    return best ~= nil and best.loc or nil
end

local function GrantedAbilityClone(ability)
    local result = DeepCopy(ability)
    result.actionResourceId = "none"
    if result.keywords ~= nil then
        result.keywords.Charge = nil
    end
    if result.multipleModes then
        result = result:SwitchModes(1)
        result.actionResourceId = "none"
    end
    return result
end

local function FindGrantedAttackPlan(ai, actor, kind, movementRange, preferredTarget)
    local paths = actor:CalculatePathfindingArea(movementRange*10, {})
    local oldTactics = ai.activeTactics
    ai.activeTactics = {}
    local best = nil

    for _,ability in ipairs(actor.properties:GetActivatedAbilities()) do
        local matches = false
        if kind == "signature" then
            matches = ability.categorization == "Signature Ability"
                and ability.targetType == "target" and ability:HasKeyword("Strike")
        else
            matches = ability.name == "Melee Free Strike"
                or ability.name == "Ranged Free Strike"
        end

        if matches then
            local scoringAbility = GrantedAbilityClone(ability)
            if scoringAbility:CanAfford(actor) then
                local plan = FindBestStrikePlan(ai, actor, scoringAbility, function(targetInfo)
                    local score = DefaultTargetScore(targetInfo)
                    if preferredTarget ~= nil
                        and targetInfo.token.charid == preferredTarget.charid then
                        score = score + 1
                    end
                    return score
                end, paths)
                if plan ~= nil and (best == nil or plan.utility > best.utility) then
                    plan.ability = scoringAbility
                    best = plan
                end
            end
        end
    end

    ai.activeTactics = oldTactics
    return best
end

local function ExecuteGrantedAttack(ai, actor, plan)
    if plan == nil or not LiveCreature(actor) then
        return false
    end

    local ok, err = ai:RunWithTokenControl(actor, function()
        MoveCinematically(ai, actor, plan.loc)
        for _,target in ipairs(plan.targets) do
            target.charge = nil
        end
        ai:ExecuteAbility(actor, plan.ability, plan.targets, {sleep = abilityPause})
    end)
    if not ok then
        print(string.format("AI:: Hobgoblin granted attack failed: %s", tostring(err)))
        return false
    end
    return true
end

local function FindBestGrantedAlly(ai, caster, commandAbility, kind)
    local best = nil
    local range = commandAbility:GetRange(caster.properties)
    for _,ally in ipairs(ai.allyTokens) do
        if LiveCreature(ally) and ally.charid ~= caster.charid
            and not ally.properties.minion and caster:Distance(ally) <= range
            and commandAbility:TargetPassesFilter(caster, ally, {}) then
            local plan = FindGrantedAttackPlan(
                ai, ally, kind, ally.properties:CurrentMovementSpeed())
            if plan ~= nil then
                local stamina = ally.properties:CurrentHitpoints()
                    / math.max(1, ally.properties.max_hitpoints)
                local utility = plan.utility + stamina*0.05
                if best == nil or utility > best.utility then
                    best = {ally = ally, attack = plan, utility = utility}
                end
            end
        end
    end
    return best
end

local function ActivateWithoutBehaviors(ai, caster, ability, targets, options)
    local activation = DeepCopy(ability)
    activation.behaviors = {}
    ai:ExecuteAbility(caster, activation, targets or {}, options or {sleep = stationaryPause})
end

local function ExecuteOptionalAbility(ai, caster, optionalAbility, targets)
    local abilityClone = DeepCopy(optionalAbility)
    abilityClone.actionResourceId = "none"
    abilityClone.targetFilter = ""
    abilityClone.targetAllegiance = nil
    ai:ExecuteAbility(caster, abilityClone, targets, {sleep = abilityPause})
end

local function FindBurningLegionDestination(ai, movingToken, reserved)
    local best = nil
    for _,enemy in ipairs(ai.enemyTokens) do
        if LiveCreature(enemy) then
            for _,loc in ipairs(MCDMLocUtils.GetTokenAdjacentLocsInOpposingPairs(enemy)) do
                if movingToken:Distance(loc) <= 5 and EmptyLoc(loc, reserved) then
                    local nearbyEnemies = 0
                    local nearbyAllies = 0
                    for _,other in ipairs(ai.enemyTokens) do
                        if LiveCreature(other) and other:Distance(loc) <= 1 then
                            nearbyEnemies = nearbyEnemies + 1
                        end
                    end
                    for _,other in ipairs(ai.allyTokens) do
                        if LiveCreature(other) and other.charid ~= movingToken.charid
                            and other:Distance(loc) <= 1 then
                            nearbyAllies = nearbyAllies + 1
                        end
                    end
                    local utility = nearbyEnemies*2 - nearbyAllies*0.5
                        - movingToken:Distance(loc)*0.01
                    if best == nil or utility > best.utility then
                        best = {
                            loc = loc,
                            enemies = nearbyEnemies,
                            utility = utility,
                        }
                    end
                end
            end
        end
    end
    return best
end

local function FindBurningLegionPlan(ai, token, ability)
    local candidates = {}
    local range = ability:GetRange(token.properties)
    for _,ally in ipairs(ai.allyTokens) do
        if LiveCreature(ally) and ally.tileSize <= 1
            and token:Distance(ally) <= range
            and ability:TargetPassesFilter(token, ally, {}) then
            candidates[#candidates+1] = ally
        end
    end

    local reserved = {}
    local used = {}
    local plans = {}
    local totalEnemies = 0
    for i=1,math.min(3, #candidates) do
        local best = nil
        for _,candidate in ipairs(candidates) do
            if not used[candidate.charid] then
                local destination = FindBurningLegionDestination(ai, candidate, reserved)
                if destination ~= nil and destination.enemies > 0
                    and (best == nil or destination.utility > best.destination.utility) then
                    best = {token = candidate, destination = destination}
                end
            end
        end
        if best == nil then
            break
        end
        used[best.token.charid] = true
        reserved[best.destination.loc.str] = true
        totalEnemies = totalEnemies + best.destination.enemies
        plans[#plans+1] = best
    end

    if #plans > 0 then
        return {plans = plans, totalEnemies = totalEnemies}
    end
end

local function FindEnchantmentsTargets(ai, token, ability)
    local result = {}
    local range = ability:GetRange(token.properties)
    for _,ally in ipairs(ai.allyTokens) do
        if LiveCreature(ally) and ally.charid ~= token.charid
            and token:Distance(ally) <= range
            and ability:TargetPassesFilter(token, ally, {})
            and not HasOngoingEffect(ally, enchantmentsEdgeEffectId) then
            local stamina = ally.properties:CurrentHitpoints()
                / math.max(1, ally.properties.max_hitpoints)
            result[#result+1] = {token = ally, score = 2 - stamina}
        end
    end
    table.sort(result, function(a, b)
        return a.score > b.score
    end)
    table.resize_array(result, ability:GetNumTargets(token))
    return result
end

local function FindHellfireTeleport(ai, token, area)
    local targetsInArea = {}
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if target.valid then
            targetsInArea[target.charid] = true
        end
    end

    local best = nil
    for _,enemy in ipairs(ai.enemyTokens) do
        if LiveCreature(enemy) and not targetsInArea[enemy.charid]
            and token:Distance(enemy) <= 10 then
            for _,loc in ipairs(area.locations or {}) do
                if enemy:Distance(loc) <= 2 and EmptyLoc(loc) then
                    local stamina = enemy.properties:CurrentHitpoints()
                        / math.max(1, enemy.properties.max_hitpoints)
                    local score = 2 - stamina - enemy:Distance(loc)*0.01
                    if best == nil or score > best.score then
                        best = {token = enemy, loc = loc, score = score}
                    end
                end
            end
        end
    end
    return best
end

local function TeleportCreature(ai, token, loc, distance)
    local teleport = MCDMUtils.GetStandardAbility("Teleport"):MakeTemporaryClone()
    teleport.range = distance
    teleport.actionResourceId = "none"
    teleport.targetFilter = ""
    local ok, err = ai:RunWithTokenControl(token, function()
        ai:ExecuteAbility(token, teleport, {{loc = loc}}, {sleep = movementPause})
    end)
    if not ok then
        print(string.format("AI:: Hobgoblin teleport failed: %s", tostring(err)))
    end
end

local function PrefersRangedPosition(token)
    local hasMeleeSignature = false
    local hasRangedSignature = false
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization == "Signature Ability" and ability:HasKeyword("Strike") then
            hasMeleeSignature = hasMeleeSignature or ability:HasKeyword("Melee")
            hasRangedSignature = hasRangedSignature or ability:HasKeyword("Ranged")
        end
    end
    return hasRangedSignature and not hasMeleeSignature
end

local function FormationBonus(ai, actor, loc)
    local bonus = 0
    for _,ally in ipairs(ai.allyTokens) do
        if LiveCreature(ally) and ally.charid ~= actor.charid
            and string.sub(MonsterType(ally), 1, 10) == "Hobgoblin"
            and ally:Distance(loc) <= 2 then
            bonus = bonus + 0.08
        end
    end
    return math.min(0.24, bonus)
end

local function FindTacticalSwarmDestination(ai, actor, reserved)
    if #ai.enemyTokens == 0 then
        return nil
    end

    local range = actor.properties:CurrentMovementSpeed()
    if range == nil or range <= 0 then
        return nil
    end

    local retreat = PrefersRangedPosition(actor)
    local currentDistance = FindNearestEnemyDistance(ai, actor.loc)
    local currentUtility = cond(retreat, currentDistance, -currentDistance)
        + FormationBonus(ai, actor, actor.loc)
    local best = nil

    for _,info in pairs(actor:CalculatePathfindingArea(range*10, {})) do
        local loc = info.loc
        if loc ~= nil and loc.str ~= actor.loc.str and EmptyLoc(loc, reserved) then
            local distance = FindNearestEnemyDistance(ai, loc)
            local utility = cond(retreat, distance, -distance)
                + FormationBonus(ai, actor, loc) - (info.cost or 0)*0.001
            if best == nil or utility > best.utility then
                best = {loc = loc, utility = utility}
            end
        end
    end

    if best ~= nil and best.utility > currentUtility + 0.05 then
        return best.loc
    end
end

local function BuildTacticalSwarmPlans(ai, actors)
    local result = {}
    local reserved = {}
    for _,actor in ipairs(actors) do
        local loc = FindTacticalSwarmDestination(ai, actor, reserved)
        if loc ~= nil then
            result[#result+1] = {actor = actor, loc = loc}
            reserved[loc.str] = true
        end
    end
    return result
end

local function ExecuteGrantedShift(ai, actor, loc)
    if not LiveCreature(actor) or loc == nil or not loc.valid then
        return false
    end

    local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
    shift.range = actor.properties:CurrentMovementSpeed()
    shift.actionResourceId = "none"
    shift.targetFilter = ""
    local ok, err = ai:RunWithTokenControl(actor, function()
        ai:ExecuteAbility(actor, shift, {{loc = loc}}, {sleep = movementPause})
    end)
    if not ok then
        print(string.format("AI:: Hobgoblin Tactical Swarm shift failed: %s", tostring(err)))
        return false
    end
    return true
end

--------------------------------------------------------------------------------
-- Start-of-turn Hobgoblin Malice abilities.
--------------------------------------------------------------------------------

MonsterAI:RegisterMaliceAbility{
    id = "Hobgoblin Inherited Goblin Malice: Goblin Mode",
    monsterGroups = {"Hobgoblin"},
    abilities = {"Goblin Mode"},
    description = "Spend 3 Malice to increase allied goblin speed when the inherited bonus helps more allies than enemies.",
    score = function(self, ai, token, ability, context)
        local targets, allies, enemies = MatchingCombatTargets(token, ability, context)
        local beneficiaries = 0
        for _,ally in ipairs(allies) do
            if not HasOngoingEffect(ally, goblinModeEffectId) then
                beneficiaries = beneficiaries + 1
            end
        end

        if beneficiaries < 2 or beneficiaries <= #enemies then
            return nil
        end

        return {
            score = math.min(1, 0.54 + math.min(5, beneficiaries)*0.065
                - math.min(3, #enemies)*0.1),
            targets = targets,
            beneficiaries = beneficiaries,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,target in ipairs(scoringInfo.targets or {}) do
            if LiveCreature(target) then
                targets[#targets+1] = {token = target}
            end
        end
        if #targets == 0 then
            return
        end

        local activation = DeepCopy(ability)
        activation.targetType = "target"
        activation.numTargets = #targets
        ai:ExecuteAbility(token, activation, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Hobgoblin Inherited Goblin Malice: Tiny Stabs",
    monsterGroups = {"Hobgoblin"},
    abilities = {"Tiny Stabs"},
    description = "Spend 5 Malice when adjacent goblins produce at least three total damage across enemy targets.",
    score = function(self, ai, token, ability, context)
        local targets = {}
        local totalDamage = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if LiveCreature(enemy) then
                local damage = 0
                for _,ally in ipairs(context.allyTokens) do
                    if LiveCreature(ally) and HasCreatureKeyword(ally, "Goblin")
                        and ally:Distance(enemy) <= 1 then
                        damage = damage + 1
                    end
                end
                if damage > 0 then
                    targets[#targets+1] = enemy
                    totalDamage = totalDamage + damage
                end
            end
        end

        if totalDamage < 3 then
            return nil
        end

        return {
            score = math.min(1, 0.58 + math.min(8, totalDamage)*0.05
                + math.min(3, #targets)*0.03),
            targets = targets,
            totalDamage = totalDamage,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,target in ipairs(scoringInfo.targets or {}) do
            if LiveCreature(target) then
                targets[#targets+1] = {token = target}
            end
        end
        if #targets == 0 then
            return
        end

        local activation = DeepCopy(ability)
        activation.targetType = "target"
        activation.numTargets = #targets
        ai:ExecuteAbility(token, activation, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Hobgoblin Inherited Goblin Malice: Swamp Stink",
    monsterGroups = {"Hobgoblin"},
    abilities = {"Swamp Stink"},
    description = "Spend 7 Malice to cover the map in weakening mist when non-goblin enemies substantially outnumber vulnerable allies.",
    score = function(self, ai, token, ability, context)
        if HasAuraFromAbility(swampStinkAbilityId) then
            return nil
        end

        local enemies = 0
        local allies = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if LiveCreature(enemy) and ability:TargetPassesFilter(token, enemy, {}) then
                enemies = enemies + 1
            end
        end
        for _,ally in ipairs(context.allyTokens) do
            if LiveCreature(ally) and ability:TargetPassesFilter(token, ally, {}) then
                allies = allies + 1
            end
        end

        if enemies < 2 or enemies <= allies then
            return nil
        end

        return {
            score = math.min(1, 0.7 + math.min(5, enemies)*0.05
                - math.min(4, allies)*0.08),
            enemies = enemies,
            allies = allies,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildMapArea(token)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Hobgoblin Malice: Operation Goblin Mode",
    monsterGroups = {"Hobgoblin"},
    abilities = {"Operation Goblin Mode"},
    description = "Spend 3 Malice to increase allied goblin speed when the bonus helps more allies than enemies.",
    score = function(self, ai, token, ability, context)
        local targets, allies, enemies = MatchingCombatTargets(token, ability, context)
        local beneficiaries = 0
        for _,ally in ipairs(allies) do
            if not HasOngoingEffect(ally, operationGoblinModeEffectId) then
                beneficiaries = beneficiaries + 1
            end
        end

        if beneficiaries < 2 or beneficiaries <= #enemies then
            return nil
        end

        return {
            score = math.min(1, 0.58 + math.min(5, beneficiaries)*0.07
                - math.min(3, #enemies)*0.1),
            targets = targets,
            beneficiaries = beneficiaries,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,target in ipairs(scoringInfo.targets or {}) do
            if LiveCreature(target) then
                targets[#targets+1] = {token = target}
            end
        end
        if #targets == 0 then
            return
        end

        local activation = DeepCopy(ability)
        activation.targetType = "target"
        activation.numTargets = #targets
        ai:ExecuteAbility(token, activation, targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Hobgoblin Malice: Operation Tactical Swarm",
    monsterGroups = {"Hobgoblin"},
    abilities = {"Operation Tactical Swarm"},
    description = "Spend 5 Malice when multiple hobgoblins can improve their formation and gain Defend.",
    score = function(self, ai, token, ability, context)
        local targets, allies, enemies = MatchingCombatTargets(token, ability, context)
        if #allies < 2 or #enemies > 0 then
            return nil
        end

        local newDefenders = 0
        local threatened = 0
        local wounded = 0
        for _,ally in ipairs(allies) do
            if not HasOngoingEffect(ally, defendEffectId) then
                newDefenders = newDefenders + 1
            end
            if FindNearestEnemyDistance(ai, ally.loc) <= 2 then
                threatened = threatened + 1
            end
            if ally.properties:CurrentHitpoints()
                <= ally.properties.max_hitpoints*0.5 then
                wounded = wounded + 1
            end
        end

        local plans = BuildTacticalSwarmPlans(ai, allies)
        if newDefenders + #plans*0.5 < 2 then
            return nil
        end

        return {
            score = math.min(1, 0.5 + math.min(5, newDefenders)*0.06
                + math.min(4, #plans)*0.035
                + math.min(4, threatened)*0.025
                + math.min(4, wounded)*0.025),
            targets = targets,
            plans = plans,
            newDefenders = newDefenders,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,target in ipairs(scoringInfo.targets or {}) do
            if LiveCreature(target) then
                targets[#targets+1] = {token = target}
            end
        end
        if #targets == 0 then
            return
        end

        local activation = DeepCopy(ability)
        activation.targetType = "target"
        activation.numTargets = #targets
        activation.behaviors = {DeepCopy(ability.behaviors[2])}
        ai:ExecuteAbility(token, activation, targets, {sleep = stationaryPause})

        for _,plan in ipairs(scoringInfo.plans or {}) do
            ExecuteGrantedShift(ai, plan.actor, plan.loc)
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Hobgoblin Malice: Operation Earth Sear",
    monsterGroups = {"Hobgoblin"},
    abilities = {"Operation Earth Sear"},
    description = "Spend 7 Malice to sear the encounter map when multiple grounded enemies must move through it.",
    score = function(self, ai, token, ability, context)
        if HasAuraFromAbility(operationEarthSearAbilityId) then
            return nil
        end

        local grounded = 0
        local mobile = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if LiveCreature(enemy) and ability:TargetPassesFilter(token, enemy, {}) then
                if OnGround(enemy) then
                    grounded = grounded + 1
                end
                if enemy.properties:CurrentMovementSpeed() > 0 then
                    mobile = mobile + 1
                end
            end
        end
        if grounded < 2 then
            return nil
        end

        return {
            score = math.min(1, 0.64 + math.min(5, grounded)*0.06
                + math.min(5, mobile)*0.02),
            grounded = grounded,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildMapArea(token)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

--------------------------------------------------------------------------------
-- Main actions and maneuvers.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Hobgoblin Bloodlord: Soul Sword",
    monsters = {"Hobgoblin Bloodlord"},
    ability = "Soul Sword",
    description = "Strike up to two enemies and spend 2 Malice to mark both when the battle is still developing.",
    score = 1.1,
    execute = function(self, ai, token, scoringInfo, ability)
        local strike = DeepCopy(ability)
        strike.behaviors = {DeepCopy(ability.behaviors[1])}
        ExecuteStrikePlan(ai, token, scoringInfo, strike)

        if CanSpendMalice(2) and #scoringInfo.targets > 0 then
            local optionalAbility = ability.behaviors[2].customAbility
            ExecuteOptionalAbility(ai, token, optionalAbility, scoringInfo.targets)
        end
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin Bloodlord: Take Point!",
    category = "Maneuvers",
    monsters = {"Hobgoblin Bloodlord"},
    abilities = {"Take Point!"},
    description = "Order the ally with the best reachable signature strike to move and use it.",
    score = function(self, ai, token, ability)
        local plan = FindBestGrantedAlly(ai, token, ability, "signature")
        if plan ~= nil then
            plan.score = 1.25
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ActivateWithoutBehaviors(ai, token, ability, {{token = scoringInfo.ally}})
        ExecuteGrantedAttack(ai, scoringInfo.ally, scoringInfo.attack)
    end,
}

RegisterStrike{
    id = "Hobgoblin Burning Witch: Soul Burn",
    monsters = {"Hobgoblin Burning Witch"},
    ability = "Soul Burn",
    description = "Use corruption damage against up to two enemies and spend 2 Malice to spread weakening when two targets are available.",
    score = 1.1,
    execute = function(self, ai, token, scoringInfo, ability)
        local strike = DeepCopy(ability:SwitchModes(1))
        local optionalAbility = ability.behaviors[3].customAbility
        strike.behaviors = {DeepCopy(strike.behaviors[1])}
        ExecuteStrikePlan(ai, token, scoringInfo, strike, {
            symbols = {mode = 1},
        })

        if CanSpendMalice(2) and #scoringInfo.targets >= 2 then
            ExecuteOptionalAbility(ai, token, optionalAbility, scoringInfo.targets)
        end
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin Burning Witch: Burning Legion",
    category = "Maneuvers",
    monsters = {"Hobgoblin Burning Witch"},
    abilities = {"Burning Legion"},
    description = "Spend 1 Malice to teleport up to three fire-resistant allies into enemy formations.",
    score = function(self, ai, token, ability)
        local plan = FindBurningLegionPlan(ai, token, ability)
        if plan ~= nil then
            plan.score = 1.15 + math.min(0.25, plan.totalEnemies*0.04)
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        Speak(ai, token, self.id)
        local targets = {}
        for _,plan in ipairs(scoringInfo.plans) do
            targets[#targets+1] = {token = plan.token}
        end
        ActivateWithoutBehaviors(ai, token, ability, targets)

        local teleportAbility = ability.behaviors[1].customAbility
        for _,plan in ipairs(scoringInfo.plans) do
            if LiveCreature(plan.token) then
                local ok, err = ai:RunWithTokenControl(plan.token, function()
                    ai:ExecuteAbility(plan.token, teleportAbility,
                        {{loc = plan.destination.loc}}, {sleep = movementPause})
                end)
                if not ok then
                    print(string.format("AI:: Burning Legion teleport failed: %s", tostring(err)))
                end
            end
        end
    end,
}

RegisterStrike{
    id = "Hobgoblin Death Captain: Blightblade",
    monsters = {"Hobgoblin Death Captain"},
    ability = "Blightblade",
    description = "Strike an enemy, set up the next attack, and spend 3 Malice for an adjacent ally's signature strike when useful.",
    score = 1.05,
    execute = function(self, ai, token, scoringInfo, ability)
        local strike = DeepCopy(ability)
        strike.behaviors = {
            DeepCopy(ability.behaviors[1]),
            DeepCopy(ability.behaviors[2]),
        }
        ExecuteStrikePlan(ai, token, scoringInfo, strike)

        local originalTarget = scoringInfo.targets[1] ~= nil
            and scoringInfo.targets[1].token or nil
        if not CanSpendMalice(3) or not LiveCreature(originalTarget) then
            return
        end

        local best = nil
        for _,ally in ipairs(ai.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and not ally.properties.minion and ally:Distance(originalTarget) <= 1 then
                local plan = FindGrantedAttackPlan(ai, ally, "signature", 0, originalTarget)
                if plan ~= nil and (best == nil or plan.utility > best.plan.utility) then
                    best = {ally = ally, plan = plan}
                end
            end
        end

        if best ~= nil then
            local costAbility = DeepCopy(ability.behaviors[4].customAbility)
            costAbility.behaviors = {}
            costAbility.targetFilter = ""
            costAbility.targetAllegiance = nil
            ExecuteOptionalAbility(ai, token, costAbility, {{token = best.ally}})
            ExecuteGrantedAttack(ai, best.ally, best.plan)
        end
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin Death Captain: On My Mark!",
    category = "Maneuvers",
    monsters = {"Hobgoblin Death Captain"},
    abilities = {"On My Mark!"},
    description = "Order the ally with the best reachable free strike to move and make it.",
    score = function(self, ai, token, ability)
        local plan = FindBestGrantedAlly(ai, token, ability, "free")
        if plan ~= nil then
            plan.score = 1.2
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ActivateWithoutBehaviors(ai, token, ability, {{token = scoringInfo.ally}})
        ExecuteGrantedAttack(ai, scoringInfo.ally, scoringInfo.attack)
    end,
}

RegisterStrike{
    id = "Hobgoblin Firerunner: Flaming Kick",
    monsters = {"Hobgoblin Firerunner"},
    ability = "Flaming Kick",
    description = "Charge the best reachable enemy with Flaming Kick.",
    score = 1.1,
}

RegisterStrike{
    id = "Hobgoblin Flameslinger: Fire Curse",
    monsters = {"Hobgoblin Flameslinger"},
    ability = "Fire Curse",
    description = "Use Fire Curse as the flameslinger's normal ranged attack.",
    score = 1,
}

RegisterStrike{
    id = "Hobgoblin Flameslinger: Fuel for the Fire",
    monsters = {"Hobgoblin Flameslinger"},
    ability = "Fuel for the Fire",
    description = "Expose a healthy enemy to fire weakness when several allies can exploit it.",
    score = function(token, ability, plan)
        local allies = 0
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and ally:IsFriend(token)
                and ally.charid ~= token.charid then
                allies = allies + 1
            end
        end
        return cond(allies >= 2, 1.15, 0.85)
    end,
    targetScore = function(targetInfo)
        if HasOngoingEffect(targetInfo.token, flameslingerWeaknessEffectId) then
            return nil
        end
        local stamina = targetInfo.token.properties:CurrentHitpoints()
            / math.max(1, targetInfo.token.properties.max_hitpoints)
        return 1 + stamina
    end,
}

RegisterStrike{
    id = "Hobgoblin Grandguard: Tower Shield Smash",
    monsters = {"Hobgoblin Grandguard"},
    ability = "Tower Shield Smash",
    description = "Smash the best reachable enemy and use the authored tier-3 Malice follow-up when available.",
    score = 1,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin Grandguard: Thunder Rush",
    category = "Main Actions",
    monsters = {"Hobgoblin Grandguard"},
    abilities = {"Thunder Rush"},
    description = "Spend 3 Malice to rush a safe line through one or more enemies, push them, and shift into vacated ground.",
    score = function(self, ai, token, ability)
        local plan = FindBestLinePlanFromPaths(ai, token, ability)
        if plan ~= nil then
            plan.score = 1.55 + math.min(0.25, (plan.enemies - 1)*0.12)
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        Speak(ai, token, self.id)
        local originalLocs = {}
        for _,target in ipairs(scoringInfo.targets) do
            originalLocs[#originalLocs+1] = target.token.loc
        end

        local area = BuildLineArea(token, ability, scoringInfo.targetLoc)
        local targets = TokensInArea(token, ability, area, {})
        local rush = DeepCopy(ability)
        rush.behaviors = {DeepCopy(ability.behaviors[1])}
        ExecuteAreaAbility(ai, token, rush, area, targets)

        for _,loc in ipairs(originalLocs) do
            if EmptyLoc(loc) then
                local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
                shift.range = 10
                shift.actionResourceId = "none"
                ai:ExecuteAbility(token, shift, {{loc = loc}}, {sleep = movementPause})
                break
            end
        end
    end,
}

RegisterStrike{
    id = "Hobgoblin Incendiarist: Fire Crossbow",
    monsters = {"Hobgoblin Incendiarist"},
    ability = "Fire Crossbow",
    description = "Use Fire Crossbow as the incendiarist's normal ranged attack.",
    score = 1,
    targetScore = function(targetInfo)
        return DefaultTargetScore(targetInfo)
            + cond(HasOngoingEffect(targetInfo.token, burningEffectId), 0, 0.25)
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin Incendiarist: Fireball Volley",
    monsters = {"Hobgoblin Incendiarist"},
    abilities = {"Fireball Volley"},
    description = "Spend 3 Malice when Fireball Volley can catch at least two enemies.",
    score = function(self, ai, token, ability)
        local plan = FindBestCubePlan(token, ability, ai.enemyTokens, 0)
        if plan ~= nil and plan.enemies >= 2 then
            return {
                score = 1.6 + math.min(0.25, (plan.enemies - 2)*0.1),
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

RegisterStrike{
    id = "Hobgoblin Redglare: Eye Flash",
    monsters = {"Hobgoblin Redglare"},
    ability = "Eye Flash",
    description = "Use Eye Flash as the redglare's normal ranged strike.",
    score = 1,
}

RegisterStrike{
    id = "Hobgoblin Redglare: Glare of the Old Judgements",
    monsters = {"Hobgoblin Redglare"},
    ability = "Glare of the Old Judgements",
    description = "Spend 5 Malice to judge a healthy low-Presence enemy.",
    score = 1.75,
    targetScore = function(targetInfo)
        local stamina = targetInfo.token.properties:CurrentHitpoints()
            / math.max(1, targetInfo.token.properties.max_hitpoints)
        local presence = AttributeValue(targetInfo.token, "prs", 4)
        return 1 + stamina*0.4 + math.max(0, 3 - presence)*0.2
    end,
}

RegisterStrike{
    id = "Hobgoblin Smokebinder: Choking Bolt",
    monsters = {"Hobgoblin Smokebinder"},
    ability = "Choking Bolt",
    description = "Attack from range with Choking Bolt, preferring positions that grant an edge.",
    score = 1,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin Smokebinder: Smoke Bomb",
    category = "Maneuvers",
    monsters = {"Hobgoblin Smokebinder"},
    abilities = {"Smoke Bomb"},
    description = "Spend 3 Malice when Smoke Bomb can catch at least two enemies.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability, function(target)
            return cond(target:IsFriend(token), -2, 1)
        end)
        if loc ~= nil and score ~= nil and score >= 2 then
            return {
                score = 1.35 + math.min(0.2, (score - 2)*0.1),
                loc = loc,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

RegisterStrike{
    id = "Hobgoblin Hell Trooper: Fire Flail",
    monsters = {"Hobgoblin Hell Trooper"},
    ability = "Fire Flail",
    description = "Engage up to two enemies with Fire Flail.",
    score = 1,
}

RegisterStrike{
    id = "Hobgoblin Hell Trooper: Fight Me, Coward!",
    category = "Maneuvers",
    monsters = {"Hobgoblin Hell Trooper"},
    ability = "Fight Me, Coward!",
    description = "Taunt a healthy low-Presence enemy that is not already taunted.",
    score = 0.8,
    targetScore = function(targetInfo)
        if HasCondition(targetInfo.token, "Taunted") then
            return nil
        end
        local stamina = targetInfo.token.properties:CurrentHitpoints()
            / math.max(1, targetInfo.token.properties.max_hitpoints)
        local presence = AttributeValue(targetInfo.token, "prs", 4)
        return 1 + stamina + math.max(0, 2 - presence)*0.25
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin War Mage: Hellfire",
    monsters = {"Hobgoblin War Mage"},
    abilities = {"Hellfire"},
    description = "Teleport an extra enemy into the best Hellfire cube when possible, then burn the cluster.",
    score = function(self, ai, token, ability)
        local hellfire = ability.behaviors[2].customAbility
        local plan = FindBestCubePlan(token, hellfire, ai.enemyTokens, 0)
        if plan ~= nil and plan.enemies > 0 then
            return {
                score = 1.1 + math.min(0.35, plan.enemies*0.1),
                center = plan.center,
                enemies = plan.enemies,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ActivateWithoutBehaviors(ai, token, ability, {})
        local hellfire = ability.behaviors[2].customAbility
        local area = BuildCubeArea(token, hellfire, scoringInfo.center)
        local teleport = FindHellfireTeleport(ai, token, area)
        if teleport ~= nil then
            TeleportCreature(ai, teleport.token, teleport.loc, 2)
        end
        if type(area.Destroy) == "function" then
            area:Destroy()
        end

        area = BuildCubeArea(token, hellfire, scoringInfo.center)
        local targets = TokensInArea(token, hellfire, area, {})
        ExecuteAreaAbility(ai, token, hellfire, area, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin War Mage: Enchantments of War",
    monsters = {"Hobgoblin War Mage"},
    abilities = {"Enchantments of War"},
    description = "Grant 10 temporary Stamina and a double edge to two wounded allies.",
    score = function(self, ai, token, ability)
        local targets = FindEnchantmentsTargets(ai, token, ability)
        if #targets >= 2 then
            return {score = 1.35, targets = targets, loc = token.loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local enchantment = DeepCopy(ability)
        enchantment.behaviors = {
            DeepCopy(ability.behaviors[2]),
            DeepCopy(ability.behaviors[3]),
        }
        ai:ExecuteAbility(token, enchantment, scoringInfo.targets, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterMove{
    id = "Hobgoblin War Mage: Unhallowed Ground",
    category = "Maneuvers",
    monsters = {"Hobgoblin War Mage"},
    abilities = {"Unhallowed Ground"},
    description = "Spend 3 Malice to place encounter-long difficult terrain and fire weakness under at least two enemies.",
    score = function(self, ai, token, ability)
        local plan = FindBestCubePlan(token, ability, ai.enemyTokens, 0)
        if plan ~= nil and plan.enemies >= 2 then
            return {
                score = 1.25 + math.min(0.2, (plan.enemies - 2)*0.08),
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

--------------------------------------------------------------------------------
-- Hobgoblin positioning tactics.
--------------------------------------------------------------------------------

MonsterAI:RegisterTactic{
    id = "Hobgoblin Recruit: Tactical Positioning",
    monsters = {"Hobgoblin Recruit"},
    description = "Recruits prefer attacking from a square adjacent to a non-minion ally.",
    score = function(self, token, tokenLoc, enemy, ability)
        for _,ally in ipairs(self.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and not ally.properties.minion and ally:Distance(tokenLoc) <= 1 then
                return 1
            end
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "Hobgoblin Brandbearer: Open Furnace",
    monsters = {"Hobgoblin Brandbearer"},
    description = "Brandbearers prefer enemies already adjacent to another brandbearer.",
    score = function(self, token, tokenLoc, enemy, ability)
        for _,ally in ipairs(self.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and MonsterType(ally) == "Hobgoblin Brandbearer"
                and ally:Distance(enemy) <= 1 then
                return 1
            end
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "Hobgoblin Formation Guard",
    monsters = {"Hobgoblin Death Captain", "Hobgoblin Grandguard"},
    description = "Formation guards prefer strike positions that keep allies inside their defensive aura.",
    score = function(self, token, tokenLoc, enemy, ability)
        for _,ally in ipairs(self.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and ally:Distance(tokenLoc) <= 2 then
                return 1
            end
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "Hobgoblin Incendiarist: Raining Cinders",
    monsters = {"Hobgoblin Incendiarist"},
    description = "Incendiarists prefer firing positions that keep allies inside Raining Cinders.",
    score = function(self, token, tokenLoc, enemy, ability)
        for _,ally in ipairs(self.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and ally:Distance(tokenLoc) <= 3 then
                return 0.5
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Bloodlord triggers and nested prompt decisions.
--------------------------------------------------------------------------------

local function RecruitSummonLocations(subject)
    local result = {}
    for _,loc in ipairs(MCDMLocUtils.GetTokenAdjacentLocsInOpposingPairs(subject)) do
        if EmptyLoc(loc) then
            result[#result+1] = loc
        end
    end
    return result
end

local function ArmyFromBloodSubject(triggerInfo)
    for _,charid in ipairs(triggerInfo.targets or {}) do
        local target = FindTokenByCharid(charid)
        if LiveCreature(target) and not target.properties.minion
            and string.find(string.lower(MonsterType(target)), "hobgoblin", 1, true) then
            return target
        end
    end
end

MonsterAI:RegisterTrigger{
    id = "Hobgoblin Brandbearer: Open Furnace",
    monsters = {"Hobgoblin Brandbearer"},
    abilityGuids = {"572736c8-4f78-4ba5-b13f-d4aead9dd213"},
    description = "Always apply Open Furnace's mandatory extra fire damage when its authored optional trigger appears.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Hobgoblin Bloodlord: An Army From Blood",
    monsters = {"Hobgoblin Bloodlord"},
    abilityGuids = {"0a387d9e-ddf6-469b-acbd-304a2afb6f76"},
    abilities = {"An Army From Blood"},
    description = "Spend 3 Malice to summon three recruits when a damaged non-minion hobgoblin has three adjacent spaces.",
    handler = function(ai, token, triggerInfo)
        local subject = ArmyFromBloodSubject(triggerInfo)
        if subject == nil or not CanSpendMalice(3)
            or #RecruitSummonLocations(subject) < 3 then
            return {dismiss = true}
        end
        ai._tmp_hobgoblinArmySubject = subject.charid
        ai._tmp_hobgoblinArmyReserved = {}
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Hobgoblin Bloodlord: End Effect",
    monsters = {"Hobgoblin Bloodlord"},
    abilityGuids = {"f8cbfa6d-efa6-4668-b41b-a3d2b4621202"},
    abilities = {"End Effect"},
    description = "Take 10 damage to end a save-ends effect unless doing so would reduce the bloodlord to 0 Stamina.",
    handler = function(ai, token, triggerInfo)
        return cond(token.properties:CurrentHitpoints() > 10,
            {activate = true}, {dismiss = true})
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {
        "Summon 1st Hobgoblin Recruit",
        "Summon 2nd Hobgoblin Recruit",
        "Summon 3rd Hobgoblin Recruit",
    },
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local subject = FindTokenByCharid(ai:try_get("_tmp_hobgoblinArmySubject", ""))
        if not LiveCreature(subject) then
            return nil
        end

        local reserved = ai:try_get("_tmp_hobgoblinArmyReserved", {})
        local best = nil
        for _,loc in ipairs(RecruitSummonLocations(subject)) do
            if not reserved[loc.str] then
                local score = -FindNearestEnemyDistance(ai, loc)
                if best == nil or score > best.score then
                    best = {loc = loc, score = score}
                end
            end
        end
        if best == nil then
            return nil
        end

        reserved[best.loc.str] = true
        ai._tmp_hobgoblinArmyReserved = reserved
        if abilityClone.name == "Summon 3rd Hobgoblin Recruit" then
            ai._tmp_hobgoblinArmySubject = nil
            ai._tmp_hobgoblinArmyReserved = nil
        end
        return {targets = {{loc = best.loc}}}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Hobgoblin Grandguard:Allies Free Strike Against Prone"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return {targets = {{token = casterToken}}}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Hobgoblin Grandguard:Ally Makes Free Strike Against Specific Target"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targets = {}
        local range = abilityClone:GetRange(casterToken.properties, symbols)
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveCreature(ally) and ally.charid ~= casterToken.charid
                and not ally.properties.minion and ally:IsFriend(casterToken)
                and casterToken:Distance(ally) <= range
                and abilityClone:TargetPassesFilter(casterToken, ally, symbols) then
                targets[#targets+1] = {token = ally}
            end
        end
        table.resize_array(targets, abilityClone:GetNumTargets(casterToken, symbols))
        if #targets > 0 then
            return {targets = targets}
        end
    end,
}

--------------------------------------------------------------------------------
-- Bloodlord villain actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterVillainAction{
    id = "Hobgoblin Bloodlord: Advance!",
    monsters = {"Hobgoblin Bloodlord"},
    abilities = {"Advance!"},
    description = "Grant nearby allies temporary Stamina, move them, and give each non-minion a free strike.",
    score = function(self, ai, token, ability, context)
        local participants = 0
        local attackers = 0
        local range = ability:GetRange(token.properties)
        for _,ally in ipairs(ai.allyTokens) do
            if LiveCreature(ally) and token:Distance(ally) <= range
                and ability:TargetPassesFilter(token, ally, {}) then
                participants = participants + 1
                if not ally.properties.minion then
                    attackers = attackers + 1
                end
            end
        end
        if participants > 0 then
            return {
                score = math.min(1, 0.45 + participants*0.04 + attackers*0.06),
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, self.id)
        local participants = {}
        local range = ability:GetRange(token.properties)
        for _,ally in ipairs(ai.allyTokens) do
            if LiveCreature(ally) and token:Distance(ally) <= range
                and ability:TargetPassesFilter(token, ally, {}) then
                participants[#participants+1] = ally
            end
        end

        local activation = DeepCopy(ability)
        activation.behaviors = {DeepCopy(ability.behaviors[1])}
        ai:ExecuteAbility(token, activation, nil, {sleep = abilityPause})

        for _,ally in ipairs(participants) do
            if LiveCreature(ally) then
                if ally.properties.minion then
                    local loc = FindRepositionLoc(
                        ai, ally, ally.properties:CurrentMovementSpeed(), false)
                    if loc ~= nil then
                        local ok, err = ai:RunWithTokenControl(ally, function()
                            MoveCinematically(ai, ally, loc)
                        end)
                        if not ok then
                            print(string.format("AI:: Advance minion movement failed: %s", tostring(err)))
                        end
                    end
                else
                    local plan = FindGrantedAttackPlan(
                        ai, ally, "free", ally.properties:CurrentMovementSpeed())
                    ExecuteGrantedAttack(ai, ally, plan)
                end
            end
        end
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Hobgoblin Bloodlord: Skulls Abound",
    monsters = {"Hobgoblin Bloodlord"},
    abilities = {"Skulls Abound "},
    description = "Raise the encounter-long skull aura while enemies remain and it is not already active.",
    score = function(self, ai, token, ability, context)
        if HasOngoingEffect(token, skullsAboundEffectId) or #ai.enemyTokens == 0 then
            return nil
        end
        local nearby = 0
        for _,enemy in ipairs(ai.enemyTokens) do
            if LiveCreature(enemy) and token:Distance(enemy) <= 6 then
                nearby = nearby + 1
            end
        end
        return {score = math.min(0.9, 0.62 + nearby*0.07)}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Hobgoblin Bloodlord: I am Fire! I am Death!",
    monsters = {"Hobgoblin Bloodlord"},
    abilities = {"I am Fire! I am Death!"},
    description = "Detonate black flame when one or more enemies are caught in the burst.",
    score = function(self, ai, token, ability, context)
        local enemies = 0
        local range = ability:GetRange(token.properties)
        for _,enemy in ipairs(ai.enemyTokens) do
            if LiveCreature(enemy) and token:Distance(enemy) <= range
                and ability:TargetPassesFilter(token, enemy, {}) then
                enemies = enemies + 1
            end
        end
        if enemies > 0 then
            return {score = math.min(1, 0.5 + enemies*0.13)}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}
