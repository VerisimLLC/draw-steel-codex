local mod = dmhub.GetModLoading()

local movementPause = 0.6
local stationaryPause = 0.35
local abilityPause = 0.9

local waterWolfMonsters = {
    "Flow of the River",
    "Essence of Change",
    "Sudden Downpour",
}

local waterWolfNonMinions = {
    "Essence of Change",
    "Sudden Downpour",
}

local waterWolfMonsterSet = {
    ["Flow of the River"] = true,
    ["Essence of Change"] = true,
    ["Sudden Downpour"] = true,
}

local stepOfTheMistAbilityId = "db9e44aa-ca11-4ad3-a987-ddd217424b54"

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

local function IsWaterWolf(token)
    return LiveCreature(token) and waterWolfMonsterSet[MonsterType(token)] == true
end

local function LocKey(loc)
    return loc.xyfloorOnly.str
end

local function MoveCinematically(ai, token, loc)
    local moving = loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc)
    if moving then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    end
    ai.Sleep(moving and movementPause or stationaryPause)
end

local function StandardStrikeScore(score)
    return function(self, ai, token, ability)
        local loc = ai:FindBestMoveToUseStrike(token, ability)
        if loc ~= nil then
            return {score = score, loc = loc}
        end
    end
end

local function StandardStrikeExecute()
    return function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
        ai:ExecuteAbility(token, ability, targets, {sleep = abilityPause})
    end
end

local function ActivateWithoutBehaviors(ai, token, ability, targets)
    local activation = DeepCopy(ability)
    activation.behaviors = {}
    ai:ExecuteAbility(token, activation, targets or {}, {sleep = stationaryPause})
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

local function ExecuteAreaAbility(ai, token, ability, area, targets)
    local abilityClone = DeepCopy(ability)
    ai:ExecuteAbility(token, abilityClone, targets, {
        sleep = abilityPause,
        symbols = {targetArea = area},
        targetArea = area,
    })
    if type(area.Destroy) == "function" then
        area:Destroy()
    end
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

local function StrikeTargetScore(target, edges)
    if target.isObject then
        return 0.1 + (edges or 0)*0.1
    end
    local stamina = target.properties:CurrentHitpoints()
        / math.max(1, target.properties.max_hitpoints)
    return 1 + (edges or 0)*0.1 + (1 - stamina)*0.08
end

local function NearestEnemyDistance(ai, actor, loc)
    local result = 999
    for _,enemy in ipairs(ai.enemyTokens or {}) do
        if LiveCreature(enemy) then
            result = math.min(result, enemy:Distance(loc or actor.loc))
        end
    end
    return result
end

local function AdjacentAlliesAt(token, loc)
    local result = 0
    for _,other in ipairs(dmhub.allTokens) do
        if LiveCreature(other) and other.charid ~= token.charid
            and other:IsFriend(token) and other:Distance(loc) <= 1 then
            result = result + 1
        end
    end
    return result
end

local function PositionUtility(ai, token, loc)
    local distance = NearestEnemyDistance(ai, token, loc)
    local adjacentAllies = AdjacentAlliesAt(token, loc)
    return -math.min(20, distance) + math.min(2, adjacentAllies)*0.8
end

local function FindBestLinePlanFromPaths(ai, token, ability)
    local best = nil
    for _,pathInfo in pairs(ai.paths or {}) do
        local candidates = {}
        for _,enemy in ipairs(ai.enemyTokens or {}) do
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
                return target:IsFriend(token) and -3 or 1
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

local function FindLeapPlan(ai, token, ability)
    local strike = nil
    for _,behavior in ipairs(ability.behaviors or {}) do
        local candidate = behavior:try_get("customAbility")
        if candidate ~= nil and candidate.name == "Leap Upon"
            and candidate:HasKeyword("Strike") then
            strike = candidate
            break
        end
    end
    if strike == nil then
        return nil
    end

    local planningStrike = DeepCopy(strike)
    planningStrike:AddKeyword("Charge")
    planningStrike.chargeDistanceOverride = 3

    local moveLoc, targetScore = ai:FindBestMoveToUseStrike(token, planningStrike,
        function(target, edges)
            return StrikeTargetScore(target, edges)
        end)
    if moveLoc == nil or targetScore == nil or targetScore <= 0 then
        return nil
    end

    local targets = ai:FindValidTargetsOfStrike(token, planningStrike, moveLoc)
    table.sort(targets, function(a, b)
        return StrikeTargetScore(a.token, a.edges) > StrikeTargetScore(b.token, b.edges)
    end)
    if #targets == 0 then
        return nil
    end

    return {
        loc = moveLoc,
        jumpLoc = targets[1].charge,
        score = targetScore,
        target = targets[1].token,
    }
end

local function ExecuteLeapPlan(ai, token, ability, plan)
    MoveCinematically(ai, token, plan.loc)
    if not LiveCreature(plan.target) then
        return
    end

    ai._tmp_waterWolfLeapPlan = {
        actorid = token.charid,
        jumpLoc = plan.jumpLoc,
        targetid = plan.target.charid,
    }
    ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    ai._tmp_waterWolfLeapPlan = nil
end

local function CasterTouchesWater(token)
    local result = false
    pcall(function()
        result = GoblinScriptTrue(dmhub.EvalGoblinScript(
            "Self.AdjacentToWater", token.properties:LookupSymbol{},
            "Water Wolf AI Water Weird source gate"))
    end)
    return result
end

local function WaterWeirdDestinationAbility(token, ability)
    if ability.targetType == "emptyspace" or ability.targetType == "anyspace" then
        return ability
    end

    local teleport = MCDMUtils.GetStandardAbility("Teleport"):MakeTemporaryClone()
    teleport.range = ability:GetRange(token.properties)
    teleport.targetFilter = "target.AdjacentToWater"
    return teleport
end

local function FindWaterWeirdPlan(ai, token, ability)
    if not CasterTouchesWater(token) then
        return nil
    end

    local destinationAbility = WaterWeirdDestinationAbility(token, ability)
    local range = destinationAbility:GetRange(token.properties)
    local targetPredicate = destinationAbility:TargetLocPassesFilterPredicate(token, {})
    local currentUtility = PositionUtility(ai, token, token.loc)
    local best = nil
    local paths = token:CalculatePathfindingArea(range*10,
        {"IgnoreWalls", "IgnoreMovementType", "IgnoreOtherCreatures"})

    for _,info in pairs(paths) do
        local loc = info.loc
        if LocKey(loc) ~= LocKey(token.loc) and targetPredicate(loc) then
            local utility = PositionUtility(ai, token, loc)
            local benefit = utility - currentUtility
            if benefit >= 0.75 and (best == nil or benefit > best.benefit
                or (benefit == best.benefit and (info.cost or 0) < best.cost)) then
                best = {
                    benefit = benefit,
                    cost = info.cost or 0,
                    loc = loc,
                }
            end
        end
    end
    return best
end

local function ExecuteWaterWeird(ai, token, ability, loc)
    if ability.targetType == "emptyspace" or ability.targetType == "anyspace" then
        ai:ExecuteAbility(token, ability, {{loc = loc}}, {sleep = movementPause})
        return
    end

    ai._tmp_waterWolfTeleportPlan = {
        actorid = token.charid,
        loc = loc,
    }
    ai:ExecuteAbility(token, ability, nil, {sleep = movementPause})
    ai._tmp_waterWolfTeleportPlan = nil
end

local function WaterWolfTokens(tokens)
    local result = {}
    for _,token in ipairs(tokens or {}) do
        if IsWaterWolf(token) then
            result[#result+1] = token
        end
    end
    return result
end

local function LocationReserved(token, loc, reserved)
    for _,occupied in ipairs(token:LocsOccupyingWhenAt(loc)) do
        if reserved[LocKey(occupied)] then
            return true
        end
    end
    return false
end

local function ReserveLocation(token, loc, reserved)
    for _,occupied in ipairs(token:LocsOccupyingWhenAt(loc)) do
        reserved[LocKey(occupied)] = true
    end
end

local function FindFormationPlan(ai, token, reserved)
    local range = token.properties:CurrentMovementSpeed()
    local currentUtility = PositionUtility(ai, token, token.loc)
    local best = nil
    for _,info in pairs(token:CalculatePathfindingArea(range*10, {"shift"})) do
        local loc = info.loc
        if not LocationReserved(token, loc, reserved or {}) then
            local utility = PositionUtility(ai, token, loc) - (info.cost or 0)*0.001
            local benefit = utility - currentUtility
            if LocKey(loc) ~= LocKey(token.loc) and benefit >= 0.35
                and (best == nil or benefit > best.benefit) then
                best = {
                    benefit = benefit,
                    loc = loc,
                }
            end
        end
    end
    return best
end

local function ExecuteGrantedShift(ai, actor, loc)
    local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
    shift.range = actor.properties:CurrentMovementSpeed()
    shift.actionResourceId = "none"
    shift.targetFilter = ""
    local ok, err = ai:RunWithTokenControl(actor, function()
        ai:ExecuteAbility(actor, shift, {{loc = loc}}, {sleep = movementPause})
    end)
    if not ok then
        print(string.format("AI:: Water Wolf Pack Formation shift failed: %s", tostring(err)))
    end
end

local function AbilityHasPotency(ability)
    for _,behavior in ipairs(ability.behaviors or {}) do
        for _,tier in ipairs(behavior:try_get("tiers", {})) do
            if type(tier) == "string" and string.find(tier, "[AMIRP]%s*<") then
                return true
            end
        end
    end
    return false
end

local function WaterWolfHasPotencyStrike(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability:HasKeyword("Strike") and AbilityHasPotency(ability) then
            return true
        end
    end
    return false
end

local function FirstLocOutsideArea(path, area)
    if area == nil or area.locations == nil then
        return path.destination
    end

    local inside = {}
    for _,loc in ipairs(area.locations) do
        inside[LocKey(loc)] = true
    end
    for _,step in ipairs(path.steps or {}) do
        if not inside[LocKey(step)] then
            return step
        end
    end
    return path.destination
end

local function FindChangeCourseSlide(ai, invokerToken, casterToken, abilityClone, symbols)
    local range = abilityClone:GetRange(casterToken.properties, symbols)
    local predicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols)
        or function() return true end
    local arrowOptions = {
        straightline = true,
        ignorecreatures = false,
        forcedMovementDistance = range,
    }
    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = casterToken,
        radius = range,
        checklos = false,
    }
    local startDistance = invokerToken:Distance(casterToken.loc)
    local best = nil

    for _,testLoc in ipairs(shape.locations) do
        local moveDistance = casterToken.loc:DistanceInTiles(testLoc)
        local endDistance = invokerToken:Distance(testLoc)
        if moveDistance > 0 and endDistance >= startDistance + moveDistance
            and predicate(testLoc) then
            local movementInfo = casterToken:MarkMovementArrow(testLoc, arrowOptions)
            if movementInfo ~= nil then
                local destination = FirstLocOutsideArea(
                    movementInfo.path, symbols ~= nil and symbols.targetArea or nil)
                local actualDistance = casterToken.loc:DistanceInTiles(destination)
                local actualEndDistance = invokerToken:Distance(destination)
                if actualDistance > 0 and actualEndDistance >= startDistance + actualDistance then
                    local score = actualDistance*10 + actualEndDistance*0.01
                    if best == nil or score > best.score then
                        best = {loc = destination, score = score}
                    end
                end
            end
        end
    end

    casterToken:ClearMovementArrow()
    if type(shape.Destroy) == "function" then
        shape:Destroy()
    end

    if best ~= nil then
        casterToken:MarkMovementArrow(best.loc, arrowOptions)
        ai.Sleep(movementPause)
        casterToken:ClearMovementArrow()
        return best.loc
    end
end

--------------------------------------------------------------------------------
-- Passive formation preference.
--------------------------------------------------------------------------------

MonsterAI:RegisterTactic{
    id = "Water Wolf: Pack Strong Formation",
    monsters = waterWolfMonsters,
    description = "Prefer strike positions adjacent to an ally so Pack Strong remains active.",
    score = function(self, token, tokenLoc, enemy, ability)
        if AdjacentAlliesAt(token, tokenLoc) > 0 then
            return 0.5
        end
    end,
}

--------------------------------------------------------------------------------
-- Essence of Change.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Essence of Change: Bite and Throw",
    category = "Main Actions",
    monsters = {"Essence of Change"},
    abilities = {"Bite and Throw"},
    description = "Use Bite and Throw against the best reachable pair of enemies.",
    score = StandardStrikeScore(1),
    execute = StandardStrikeExecute(),
}

MonsterAI:RegisterMove{
    id = "Essence of Change: Wolf Stream",
    category = "Main Actions",
    monsters = {"Essence of Change"},
    abilities = {"Wolf Stream"},
    description = "Spend 3 Malice on a line that catches at least two enemies and no allies.",
    score = function(self, ai, token, ability)
        local plan = FindBestLinePlanFromPaths(ai, token, ability)
        if plan ~= nil and plan.enemies >= 2 then
            plan.score = 1.55 + math.min(0.25, (plan.enemies - 2)*0.1)
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local area = BuildLineArea(token, ability, scoringInfo.targetLoc)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

MonsterAI:RegisterMove{
    id = "Essence of Change: Rally Howl",
    category = "Maneuvers",
    monsters = {"Essence of Change"},
    abilities = {"Rally Howl"},
    description = "Grant an edge on the next strike when at least two allies are in the howl.",
    score = function(self, ai, token, ability)
        local beneficiaries = 0
        local range = ability:GetRange(token.properties)
        for _,ally in ipairs(ai.allyTokens or {}) do
            if LiveCreature(ally) and token:Distance(ally) <= range
                and ability:TargetPassesFilter(token, ally, {}) then
                beneficiaries = beneficiaries + 1
            end
        end
        if beneficiaries >= 2 then
            return {
                score = 0.78 + math.min(0.12, (beneficiaries - 2)*0.03),
                beneficiaries = beneficiaries,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Sudden Downpour.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Sudden Downpour: Leap Upon",
    category = "Main Actions",
    monsters = {"Sudden Downpour"},
    abilities = {"Leap Upon"},
    description = "Move and jump up to 3 squares to use Leap Upon against the best reachable enemy.",
    score = function(self, ai, token, ability)
        local plan = FindLeapPlan(ai, token, ability)
        if plan ~= nil then
            plan.score = 1.05
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteLeapPlan(ai, token, ability, scoringInfo)
    end,
}

MonsterAI:RegisterMove{
    id = "Sudden Downpour: See Through and Leap Upon",
    category = "Main Actions",
    monsters = {"Sudden Downpour"},
    abilities = {"See Through", "Leap Upon"},
    description = "Spend 1 Malice to turn invisible immediately before using Leap Upon.",
    score = function(self, ai, token, seeThrough, leapUpon)
        local plan = FindLeapPlan(ai, token, leapUpon)
        if plan ~= nil then
            plan.score = 1.3
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, seeThrough, leapUpon)
        ai:ExecuteAbility(token, seeThrough, nil, {sleep = stationaryPause})
        ExecuteLeapPlan(ai, token, leapUpon, scoringInfo)
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Sudden Downpour:Jump"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = ai:try_get("_tmp_waterWolfLeapPlan")
        if plan == nil or plan.actorid ~= invokerToken.charid then
            return nil
        end
        if plan.jumpLoc == nil or LocKey(plan.jumpLoc) == LocKey(casterToken.loc) then
            return {targets = {}}
        end
        return {targets = {{loc = plan.jumpLoc}}}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Sudden Downpour:Leap Upon"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = ai:try_get("_tmp_waterWolfLeapPlan")
        if plan == nil or plan.actorid ~= invokerToken.charid then
            return nil
        end
        local target = dmhub.GetTokenById(plan.targetid)
        ai._tmp_waterWolfLeapPlan = nil
        if LiveCreature(target) and not target:IsFriend(casterToken)
            and casterToken:Distance(target) <= abilityClone:GetRange(casterToken.properties)
            and abilityClone:TargetPassesFilter(casterToken, target, symbols) then
            return {targets = {{token = target}}}
        end
        return {targets = {}}
    end,
}

--------------------------------------------------------------------------------
-- Shared Water Weird positioning for non-minions.
--------------------------------------------------------------------------------

MonsterAI:RegisterMove{
    id = "Water Wolf: Water Weird",
    category = "Maneuvers",
    monsters = waterWolfNonMinions,
    abilities = {"Water Weird"},
    description = "Use Water Weird when a legal water-linked destination materially improves position.",
    score = function(self, ai, token, ability)
        local plan = FindWaterWeirdPlan(ai, token, ability)
        if plan ~= nil then
            plan.score = 0.72 + math.min(0.16, plan.benefit*0.04)
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ExecuteWaterWeird(ai, token, ability, scoringInfo.loc)
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {
        "Flow of the River:Teleport",
        "Essence of Change:Teleport",
        "Sudden Downpour:Teleport",
    },
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local plan = ai:try_get("_tmp_waterWolfTeleportPlan")
        if plan == nil or plan.actorid ~= invokerToken.charid then
            return nil
        end
        ai._tmp_waterWolfTeleportPlan = nil
        return {targets = {{loc = plan.loc}}}
    end,
}

--------------------------------------------------------------------------------
-- Start-of-turn Water Wolf Malice abilities.
--------------------------------------------------------------------------------

MonsterAI:RegisterMaliceAbility{
    id = "Water Wolf Malice: Change Course",
    monsterGroups = {"Water Wolf"},
    abilities = {"Change Course"},
    description = "Spend 3 Malice when the river line can slide at least two enemies without catching an ally.",
    score = function(self, ai, token, ability, context)
        local plan = ai:FindBestLinePlan(token, ability, {
            candidates = context.enemyTokens,
            scorefn = function(target)
                return target:IsFriend(token) and -3 or 1
            end,
        })
        local enemies, allies = 0, 0
        if plan ~= nil then
            enemies, allies = CountByAllegiance(token, plan.targets)
        end
        if plan ~= nil and enemies >= 2 and allies == 0 then
            return {
                score = math.min(1, 0.66 + (enemies - 2)*0.06),
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

MonsterAI:RegisterPrompt{
    prompts = {
        "Flow of the River:Slide Creature",
        "Essence of Change:Slide Creature",
        "Sudden Downpour:Slide Creature",
    },
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local loc = FindChangeCourseSlide(
            ai, invokerToken, casterToken, abilityClone, symbols)
        if loc ~= nil then
            return {targets = {{loc = loc}}}
        end
        return {targets = {}}
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Water Wolf Malice: Pack Formation",
    monsterGroups = {"Water Wolf"},
    abilities = {"Pack Formation"},
    description = "Spend 5 Malice when multiple Water Wolves can improve their attack position or restore Pack Strong.",
    score = function(self, ai, token, ability, context)
        local plans = 0
        for _,wolf in ipairs(WaterWolfTokens(context.allyTokens)) do
            if FindFormationPlan(ai, wolf, {}) ~= nil then
                plans = plans + 1
            end
        end
        if plans >= 2 then
            return {
                score = math.min(1, 0.62 + math.min(5, plans)*0.035),
                plans = plans,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        ActivateWithoutBehaviors(ai, token, ability, {})
        local reserved = {}
        for _,wolf in ipairs(WaterWolfTokens(context.allyTokens)) do
            local plan = FindFormationPlan(ai, wolf, reserved)
            if plan ~= nil then
                ExecuteGrantedShift(ai, wolf, plan.loc)
                ReserveLocation(wolf, plan.loc, reserved)
            else
                ReserveLocation(wolf, wolf.loc, reserved)
            end
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Water Wolf Malice: Step of the Mist",
    monsterGroups = {"Water Wolf"},
    abilities = {"Step of the Mist"},
    description = "Spend 7 Malice when a sizeable pack can exploit flight and stronger forced movement.",
    score = function(self, ai, token, ability, context)
        if HasAuraFromAbility(stepOfTheMistAbilityId) then
            return nil
        end

        local wolves = WaterWolfTokens(context.allyTokens)
        local forceMovers = 0
        for _,wolf in ipairs(wolves) do
            local monsterType = MonsterType(wolf)
            if monsterType == "Flow of the River" or monsterType == "Essence of Change" then
                forceMovers = forceMovers + 1
            end
        end
        if #wolves >= 3 and forceMovers >= 2 and #context.enemyTokens >= 2 then
            return {
                score = math.min(1, 0.64 + math.min(5, #wolves)*0.025
                    + math.min(4, forceMovers)*0.02),
                wolves = #wolves,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildMapArea(token)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Water Wolf Malice: Brutal Effectiveness",
    monsterGroups = {"Water Wolf"},
    abilities = {"Brutal Effectiveness"},
    description = "Spend 3 Malice before a non-minion Water Wolf uses a potency-bearing strike.",
    score = function(self, ai, token, ability, context)
        if not token.properties.minion and WaterWolfHasPotencyStrike(token)
            and #context.enemyTokens > 0 then
            return {score = 0.68}
        end
    end,
}
