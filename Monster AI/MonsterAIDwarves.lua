local mod = dmhub.GetModLoading()

local movementPause = 0.6
local stationaryPause = 0.35
local abilityPause = 0.9

local portableBallistaCollisionAbilityId = "a6aad248-cafc-4e5f-803a-6a64b4b566a1"

local servitorMonsters = {
    "Servitor War Walker",
    "Servitor Battle Walker",
}

local reelWinchMonsters = {
    "Dwarf Reel Winch",
    "Dwarf Engineer",
}

local function LiveCreature(token)
    return token ~= nil and token.valid and not token.isObject
        and token.properties ~= nil and not token.properties:IsDead()
end

local function FindTokenByCharid(charid)
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and token.charid == charid then
            return token
        end
    end
end

local function PortableBallistaForAI(ability)
    local result = DeepCopy(ability)
    for _,behavior in ipairs(result.behaviors or {}) do
        if behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            local customAbility = behavior:try_get("customAbility")
            if customAbility ~= nil
                and customAbility:try_get("guid", "") == portableBallistaCollisionAbilityId then
                -- The authored formula targeting presents a yes/no confirmation
                -- directly through the action bar. Route the AI's private clone
                -- through its prompt handler so it can make that decision.
                behavior.targeting = "prompt"
            end
        end
    end
    return result
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

local function HasCondition(token, conditionName)
    local result = false
    if LiveCreature(token) then
        pcall(function()
            result = token.properties:HasNamedCondition(conditionName)
        end)
    end
    return result
end

local function CanSpendMalice(amount)
    return (CharacterResource.GetMalice() or 0) >= amount
end

local function MoveCinematically(ai, token, loc)
    local moving = loc ~= nil and not ai:MovementTokenIsAtLoc(token, loc)
    if moving then
        ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    end
    ai.Sleep(cond(moving, movementPause, stationaryPause))
end

local function Speak(ai, token, lines)
    if lines ~= nil then
        ai:Speech(token, lines)
        ai.Sleep(stationaryPause)
    end
end

local function EmptyLoc(loc)
    if loc == nil or not loc.valid or not loc.isOnMap then
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
    if targetInfo.token.isObject or targetInfo.token.properties == nil then
        return 0.1
    end
    local stamina = targetInfo.token.properties:CurrentHitpoints()
        / math.max(1, targetInfo.token.properties.max_hitpoints)
    return 1 + (targetInfo.edges or 0)*0.1 + (1 - stamina)*0.08
end

-- Keep the chosen targets with the movement plan so execution does not make a
-- different tactical choice after scoring.
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
    Speak(ai, token, options.speech)
    ai:ExecuteAbility(token, options.ability or ability, scoringInfo.targets, {
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
                ExecuteStrikePlan(ai, token, scoringInfo, ability, {
                    speech = args.speech,
                })
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
    ai:ExecuteAbility(token, abilityClone, targets, {
        sleep = options.sleep or abilityPause,
        symbols = options.symbols or {targetArea = area},
        targetArea = area,
    })
    if type(area.Destroy) == "function" then
        area:Destroy()
    end
end

local function FindBestCubePlanAtCurrentLoc(token, ability, candidates)
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
            local utility = enemies - allies*3
            if enemies > 0 and allies == 0
                and (best == nil or utility > best.utility) then
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

local function ExecuteCubePlan(ai, token, scoringInfo, ability, options)
    options = options or {}
    MoveCinematically(ai, token, scoringInfo.loc)
    Speak(ai, token, options.speech)
    local area = BuildCubeArea(token, ability, scoringInfo.center)
    local targets = TokensInArea(token, ability, area, {})
    ExecuteAreaAbility(ai, token, ability, area, targets)
end

local function RegisterCube(args)
    MonsterAI:RegisterMove{
        id = args.id,
        category = args.category or "Main Actions",
        monsters = args.monsters,
        abilities = {args.ability},
        description = args.description,
        score = function(self, ai, token, ability)
            local plan = ai:FindSynthesizedCubePlan(token, ability)
            if plan ~= nil and plan.allies == 0
                and plan.enemies >= (args.minimumEnemies or 1) then
                plan.score = (args.score or 1)
                    + math.min(0.3, math.max(0, plan.enemies - 1)*0.1)
                return plan
            end
        end,
        execute = function(self, ai, token, scoringInfo, ability)
            ExecuteCubePlan(ai, token, scoringInfo, ability, {
                speech = args.speech,
            })
        end,
    }
end

local function RegisterBurst(args)
    MonsterAI:RegisterMove{
        id = args.id,
        category = args.category or "Maneuvers",
        monsters = args.monsters,
        abilities = {args.ability},
        description = args.description,
        score = function(self, ai, token, ability)
            local loc, targetScore = ai:FindBestMoveToUseBurst(token, ability, function(target)
                return cond(target:IsFriend(token), -3, 1)
            end)
            if loc ~= nil and targetScore ~= nil
                and targetScore >= (args.minimumEnemies or 1) then
                return {
                    score = (args.score or 1)
                        + math.min(0.25, math.max(0, targetScore - 1)*0.1),
                    loc = loc,
                    targets = targetScore,
                }
            end
        end,
        execute = function(self, ai, token, scoringInfo, ability)
            MoveCinematically(ai, token, scoringInfo.loc)
            ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
        end,
    }
end

local function ClearAbilityCosts(ability)
    ability.actionResourceId = "none"
    ability.resourceCost = nil
    ability.resourceNumber = nil
end

local function AbilityWithoutInvoke(ability, invokedName)
    local result = DeepCopy(ability)
    result.behaviors = {}
    for _,behavior in ipairs(ability.behaviors or {}) do
        local customAbility = behavior:try_get("customAbility")
        local remove = behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior"
            and (invokedName == nil
                or (customAbility ~= nil and customAbility.name == invokedName))
        if not remove then
            result.behaviors[#result.behaviors+1] = DeepCopy(behavior)
        end
    end
    return result
end

local function FindDirectFreeStrike(token, target)
    local best = nil
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike" then
            local clone = DeepCopy(ability)
            ClearAbilityCosts(clone)
            if clone:TargetPassesFilter(token, target, {})
                and token:Distance(target) <= clone:GetRange(token.properties) then
                if best == nil or clone:GetRange(token.properties) > best:GetRange(token.properties) then
                    best = clone
                end
            end
        end
    end
    return best
end

local function ExecuteGrantedFreeStrike(ai, token, target)
    local ability = FindDirectFreeStrike(token, target)
    if ability == nil or not LiveCreature(target) then
        return false
    end
    ai:ExecuteAbility(token, ability, {{token = target}}, {sleep = abilityPause})
    return true
end

--------------------------------------------------------------------------------
-- Minion tactics. Their signature attacks themselves are handled by the core
-- squad-strike path.
--------------------------------------------------------------------------------

MonsterAI:RegisterTactic{
    id = "Dwarves: Maul Restrained Targets",
    monsters = {"Dwarf Catchpole", "Dwarf Securer"},
    description = "Catchpoles and securers prefer restrained targets for Maul's extra damage.",
    score = function(self, token, tokenLoc, enemy, ability)
        if ability.name == "Maul" and HasCondition(enemy, "Restrained") then
            return 2
        end
    end,
}

MonsterAI:RegisterTactic{
    id = "Dwarves: Servitor Prison Harness",
    monsters = servitorMonsters,
    description = "Servitor walkers prefer positions adjacent to slowed or restrained enemies.",
    score = function(self, token, tokenLoc, enemy, ability)
        for _,candidate in ipairs(self.enemyTokens) do
            if LiveCreature(candidate) and candidate:Distance(tokenLoc) <= 1
                and (HasCondition(candidate, "Slowed")
                    or HasCondition(candidate, "Restrained")) then
                return 1.5
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Gunner.
--------------------------------------------------------------------------------

local dwarfGunnerSpeech = {
    portableBallista = {
        "Let's line up this shot...",
        "Now where's a wall I can nail you to?",
        "You're on the wrong end of a Dwarvish Ballista",
    },
    newlyRestrained = {
        "Huh, got you all tied up!",
        "All fun and games until you get nailed to something.",
        "Won't be getting out of that easily.",
    },
}

RegisterStrike{
    id = "Dwarf Gunner: Portable Ballista",
    monsters = {"Dwarf Gunner"},
    ability = "Portable Ballista",
    description = "Fire the ballista from range and let the forced-movement handler seek a restraining collision.",
    score = 1.05,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local target = scoringInfo.targets[1].token
        local wasRestrained = HasCondition(target, "Restrained")
        Speak(ai, token, dwarfGunnerSpeech.portableBallista)
        ai:ExecuteAbility(token, PortableBallistaForAI(ability), scoringInfo.targets, {
            sleep = abilityPause,
        })
        if not wasRestrained and HasCondition(target, "Restrained") then
            Speak(ai, token, dwarfGunnerSpeech.newlyRestrained)
        end
    end,
}

MonsterAI:RegisterMove{
    id = "Dwarf Gunner: Ensnaring Chains",
    category = "Maneuvers",
    monsters = {"Dwarf Gunner"},
    abilities = {"Ensnaring Chains"},
    description = "Upgrade a prone, slowed, or restrained enemy to restrained (save ends) after a free strike.",
    score = function(self, ai, token, ability)
        local plan = FindBestStrikePlan(ai, token, ability, function(targetInfo)
            return DefaultTargetScore(targetInfo)
                + cond(HasCondition(targetInfo.token, "Restrained"), 0.15, 0.35)
        end)
        if plan ~= nil then
            plan.score = 1.4
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local target = scoringInfo.targets[1].token

        -- Pay for Ensnaring Chains before its granted strike. The effects are
        -- applied afterward without paying a second time.
        local payment = DeepCopy(ability)
        payment.behaviors = {}
        ai:ExecuteAbility(token, payment, scoringInfo.targets, {sleep = stationaryPause})

        ExecuteGrantedFreeStrike(ai, token, target)

        if LiveCreature(target) then
            local effects = AbilityWithoutInvoke(ability)
            ClearAbilityCosts(effects)
            ai:ExecuteAbility(token, effects, {{token = target}}, {sleep = abilityPause})
        end
    end,
}

--------------------------------------------------------------------------------
-- Launcher and grenadier.
--------------------------------------------------------------------------------

RegisterCube{
    id = "Dwarf Launcher: Concussive Grenade",
    monsters = {"Dwarf Launcher"},
    ability = "Concussive Grenade",
    description = "Place a concussive grenade to catch as many enemies as possible without friendly fire.",
    score = 1.05,
}

RegisterCube{
    id = "Dwarf Grenadier: Concussive Grenade",
    monsters = {"Dwarf Grenadier"},
    ability = "Concussive Grenade",
    description = "Place a concussive grenade to catch as many enemies as possible without friendly fire.",
    score = 1.05,
}

RegisterCube{
    id = "Dwarf Launcher: Sleep Grenade",
    monsters = {"Dwarf Launcher"},
    ability = "Sleep Grenade",
    description = "Spend 3 Malice when a sleep grenade can catch at least two enemies without friendly fire.",
    category = "Main Actions",
    minimumEnemies = 2,
    score = 1.55,
}

--------------------------------------------------------------------------------
-- Reel winch and engineer.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Dwarf Reel Winch: Snaring Crossbow",
    monsters = {"Dwarf Reel Winch"},
    ability = "Snaring Crossbow",
    description = "Slow and pull an enemy, preferring a target that We Have a Quota can restrain.",
    targetScore = function(targetInfo)
        return DefaultTargetScore(targetInfo)
            + cond(HasCondition(targetInfo.token, "Slowed")
                or HasCondition(targetInfo.token, "Grabbed"), 0.5, 0)
    end,
    score = 1.05,
}

MonsterAI:RegisterMove{
    id = "Dwarf Engineer: Snaring Crossbow",
    monsters = {"Dwarf Engineer"},
    abilities = {"Snaring Crossbow"},
    description = "Slow or restrain an enemy, then spend 5 Malice to pull a useful conditioned target.",
    score = function(self, ai, token, ability)
        local plan = FindBestStrikePlan(ai, token, ability, function(targetInfo)
            return DefaultTargetScore(targetInfo)
                + cond(HasCondition(targetInfo.token, "Slowed")
                    or HasCondition(targetInfo.token, "Grabbed"), 0.5, 0)
        end)
        if plan ~= nil then
            plan.score = 1.05
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local target = scoringInfo.targets[1].token
        local strike = AbilityWithoutInvoke(ability, "Snaring Crossbow - 5 Malice Pull")
        ai:ExecuteAbility(token, strike, scoringInfo.targets, {sleep = abilityPause})

        if LiveCreature(target) and CanSpendMalice(5)
            and (HasCondition(target, "Slowed")
                or HasCondition(target, "Restrained")
                or HasCondition(target, "Grabbed")) then
            for _,behavior in ipairs(ability.behaviors or {}) do
                local customAbility = behavior:try_get("customAbility")
                if customAbility ~= nil
                    and customAbility.name == "Snaring Crossbow - 5 Malice Pull" then
                    ai:ExecuteAbility(token, DeepCopy(customAbility), {{token = target}}, {
                        sleep = abilityPause,
                    })
                    break
                end
            end
        end
    end,
}

RegisterStrike{
    id = "Dwarf Reel Winch: Reel Them In",
    category = "Maneuvers",
    monsters = {"Dwarf Reel Winch"},
    ability = "Reel Them In",
    description = "Spend 3 Malice to pull up to three enemies toward the dwarf line.",
    score = function(token, ability, plan)
        return 1.25 + math.min(0.25, (#plan.targets - 1)*0.1)
    end,
}

RegisterStrike{
    id = "Dwarf Engineer: Reel them In",
    category = "Maneuvers",
    monsters = {"Dwarf Engineer"},
    ability = "Reel them In",
    description = "Spend 5 Malice to pull up to three enemies toward the dwarf line.",
    score = function(token, ability, plan)
        return 1.3 + math.min(0.25, (#plan.targets - 1)*0.1)
    end,
}

--------------------------------------------------------------------------------
-- Shieldwall.
--------------------------------------------------------------------------------

local function FindShieldwallFollowLoc(ai, token, target)
    if not LiveCreature(target) or token:Distance(target) <= 1 then
        return nil
    end
    local best = nil
    for _,loc in ipairs(MCDMLocUtils.GetTokenAdjacentLocsInOpposingPairs(target)) do
        if EmptyLoc(loc) and token:Distance(loc) <= 1 then
            local adjacentAllies = 0
            for _,ally in ipairs(ai.allyTokens) do
                if LiveCreature(ally) and ally.charid ~= token.charid
                    and ally:Distance(loc) <= 1 then
                    adjacentAllies = adjacentAllies + 1
                end
            end
            if best == nil or adjacentAllies > best.adjacentAllies then
                best = {loc = loc, adjacentAllies = adjacentAllies}
            end
        end
    end
    return best ~= nil and best.loc or nil
end

MonsterAI:RegisterMove{
    id = "Dwarf Shieldwall: Wide Axe",
    monsters = {"Dwarf Shieldwall"},
    abilities = {"Wide Axe"},
    description = "Slide enemies, spend 3 Malice for a second target when worthwhile, and follow the target to hold the line.",
    score = function(self, ai, token, ability)
        local selectedAbility = ability:SwitchModes(1)
        local plan = FindBestStrikePlan(ai, token, selectedAbility)
        if ability:CanAfford(token, {mode = 2}) then
            local modeTwoAbility = ability:SwitchModes(2)
            local modeTwoPlan = FindBestStrikePlan(ai, token, modeTwoAbility)
            if modeTwoPlan ~= nil and #modeTwoPlan.targets >= 2 then
                selectedAbility = modeTwoAbility
                plan = modeTwoPlan
                plan.mode = 2
            end
        end
        if plan ~= nil then
            plan.mode = plan.mode or 1
            plan.selectedAbility = selectedAbility
            plan.score = cond(plan.mode == 2, 1.35, 1.05)
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        local strike = AbilityWithoutInvoke(scoringInfo.selectedAbility)
        ai:ExecuteAbility(token, strike, scoringInfo.targets, {
            sleep = abilityPause,
            symbols = {mode = scoringInfo.mode},
        })

        local target = scoringInfo.targets[1].token
        local loc = FindShieldwallFollowLoc(ai, token, target)
        if loc ~= nil then
            local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
            shift.range = 1
            ClearAbilityCosts(shift)
            ai:ExecuteAbility(token, shift, {{loc = loc}}, {sleep = movementPause})
        end
    end,
}

--------------------------------------------------------------------------------
-- Stone whisperer.
--------------------------------------------------------------------------------

RegisterCube{
    id = "Dwarf Stone Whisperer: Tile Slide",
    monsters = {"Dwarf Stone Whisperer"},
    ability = "Tile Slide",
    description = "Move into the safest adjacent position that catches enemies without catching allies.",
    score = 1.05,
}

RegisterCube{
    id = "Dwarf Stone Whisperer: Stone Wave",
    category = "Maneuvers",
    monsters = {"Dwarf Stone Whisperer"},
    ability = "Stone Wave",
    description = "Spend 3 Malice when Stone Wave can catch at least two enemies and leave difficult terrain.",
    minimumEnemies = 2,
    score = 1.45,
}

--------------------------------------------------------------------------------
-- Trapper.
--------------------------------------------------------------------------------

local dwarfTrapperSpeech = {
    concussiveBolts = {
        "I'll knock you into next week!",
        "You won't see this coming!",
        "Everyone has a plan until a Dwarf nails them to a wall!",
    },
    steamPoweredSnare = {
        "Now, I'll ensnare you!",
        "Let's see you escape from this!",
        "You won't get away!",
    },
}

RegisterStrike{
    id = "Dwarf Trapper: Concussive Bolts",
    monsters = {"Dwarf Trapper"},
    ability = "Concussive Bolts",
    description = "Use the trapper's long-range signature strike and push enemies into hazards.",
    score = 1.05,
    speech = dwarfTrapperSpeech.concussiveBolts,
}

RegisterCube{
    id = "Dwarf Trapper: Steam Powered Snare",
    category = "Maneuvers",
    monsters = {"Dwarf Trapper"},
    ability = "Steam Powered Snare",
    description = "Spend 3 Malice to place a persistent snare under at least two enemies without catching allies.",
    minimumEnemies = 2,
    score = 1.5,
    speech = dwarfTrapperSpeech.steamPoweredSnare,
}

--------------------------------------------------------------------------------
-- Warden.
--------------------------------------------------------------------------------

local function FindWardenEscortTarget(ai, token, ability)
    local carried = token.properties:try_get("_tmp_numberOfCreaturesGrabbed", 0)
    local capacity = token.properties:CalculateNamedCustomAttribute("Maximum Grabbed Creatures")
    if carried >= capacity then
        return nil
    end

    local best = nil
    local bestStamina = nil
    for _,target in ipairs(ai.enemyTokens or {}) do
        if LiveCreature(target) and token:Distance(target) <= ability:GetRange(token.properties)
            and HasCondition(target, "Restrained")
            and ability:TargetPassesFilter(token, target, {}) then
            local stamina = target.properties:CurrentHitpoints()
            if best == nil or stamina > bestStamina then
                best = target
                bestStamina = stamina
            end
        end
    end
    return best
end

MonsterAI:RegisterMove{
    id = "Dwarf Warden: Escort the Prisoners",
    category = "Maneuvers",
    monsters = {"Dwarf Warden"},
    abilities = {"Escort the Prisoners"},
    description = "Secure an adjacent restrained enemy before moving, then carry them using the normal grab limits.",
    score = function(self, ai, token, ability)
        local target = FindWardenEscortTarget(ai, token, ability)
        if target ~= nil then
            return {score = 1.75, target = target}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability, {{token = scoringInfo.target}}, {
            sleep = stationaryPause,
        })
    end,
}

RegisterStrike{
    id = "Dwarf Warden: Concussive Maul",
    monsters = {"Dwarf Warden"},
    ability = "Concussive Maul",
    description = "Close to melee and drive an enemy into hazards or the dwarf line.",
    score = 1.05,
}

RegisterCube{
    id = "Dwarf Warden: Concussive Shockwave",
    monsters = {"Dwarf Warden"},
    ability = "Concussive Shockwave",
    description = "Spend 5 Malice when the shockwave can catch at least two enemies without friendly fire.",
    minimumEnemies = 2,
    score = 1.6,
}

--------------------------------------------------------------------------------
-- Mortar retainer.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Dwarf Mortar: Armor-Piercing Shell",
    monsters = {"Dwarf Mortar"},
    ability = "Armor-Piercing Shell",
    description = "Fire the armor-piercing shell from long range, preferring wounded targets.",
    score = 1.05,
}

--------------------------------------------------------------------------------
-- Servitor walkers.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Dwarf Servitor: Grasping Claws",
    monsters = servitorMonsters,
    ability = "Grasping Claws",
    description = "Strike up to two enemies and prefer slowed or restrained prisoners for the follow-up pull.",
    targetScore = function(targetInfo)
        return DefaultTargetScore(targetInfo)
            + cond(HasCondition(targetInfo.token, "Slowed")
                or HasCondition(targetInfo.token, "Restrained"), 0.45, 0)
    end,
    score = 1.1,
}

RegisterBurst{
    id = "Dwarf Servitor: Stunning Blast",
    category = "Maneuvers",
    monsters = servitorMonsters,
    ability = "Stunning Blast",
    description = "Spend 3 Malice when Stunning Blast can catch at least two enemies.",
    minimumEnemies = 2,
    score = 1.45,
}

--------------------------------------------------------------------------------
-- Marauder lord actions and maneuvers.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Dwarf Marauder Lord: Levitating Axes",
    monsters = {"Dwarf Marauder Lord"},
    ability = "Levitating Axes",
    description = "Strike up to two enemies and slide them toward dwarf allies for optional restraints.",
    score = 1.15,
}

RegisterStrike{
    id = "Dwarf Marauder Lord: Magnetomancy",
    category = "Maneuvers",
    monsters = {"Dwarf Marauder Lord"},
    ability = "Magnetomancy (Ranged)",
    description = "Vertically slide one enemy or object, favoring already restrained enemies.",
    targetScore = function(targetInfo)
        return DefaultTargetScore(targetInfo)
            + cond(HasCondition(targetInfo.token, "Restrained"), 0.35, 0)
    end,
    score = 0.8,
}

MonsterAI:RegisterMove{
    id = "Dwarf Marauder Lord: Magnetomancy Burst",
    category = "Maneuvers",
    monsters = {"Dwarf Marauder Lord"},
    abilities = {"Magnetomancy", "Magnetomancy (AoE)"},
    description = "Spend 5 Malice to vertically slide at least two restrained enemies in the 10 burst.",
    score = function(self, ai, token, ability, areaAbility)
        if not ability:CanAfford(token, {mode = 2}) then
            return nil
        end
        local loc, targetScore = ai:FindBestMoveToUseBurst(token, areaAbility, function(target)
            return cond(target:IsFriend(token), -3, 1)
        end)
        if loc ~= nil and targetScore ~= nil and targetScore >= 2 then
            return {
                score = 1.25 + math.min(0.2, (targetScore - 2)*0.1),
                loc = loc,
                targets = targetScore,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, areaAbility)
        MoveCinematically(ai, token, scoringInfo.loc)

        local payment = DeepCopy(ability:SwitchModes(2))
        payment.behaviors = {}
        ai:ExecuteAbility(token, payment, {{token = token}}, {
            sleep = stationaryPause,
            symbols = {mode = 2},
        })

        local activation = DeepCopy(areaAbility)
        ClearAbilityCosts(activation)
        ai:ExecuteAbility(token, activation, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Dwarf start-of-turn Malice abilities.
--------------------------------------------------------------------------------

local rappellingBarrageSpeech = {
    "Rappelling Barrage!",
    "Come Dwarves, let them have it!",
    "Dwarves, forward!!!",
    "All of you, attack!",
}

local function TacticsForToken(token)
    local result = {}
    for id,tactic in pairs(MonsterAI.tactics) do
        if MonsterAI.MoveMatchesMonster(token, tactic) then
            result[id] = tactic
        end
    end
    return result
end

local function FindGrantedFreeStrikePlan(ai, actor)
    if not LiveCreature(actor) then
        return nil
    end
    local paths = ai:CalculateRemainingMovementPaths(actor)
    local oldTactics = ai.activeTactics
    ai.activeTactics = TacticsForToken(actor)
    local best = nil

    for _,ability in ipairs(actor.properties:GetActivatedAbilities()) do
        if ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike" then
            local granted = DeepCopy(ability)
            ClearAbilityCosts(granted)
            granted.disableSquadCoordination = true
            granted.name = "Rappelling Free Strike"
            if granted.keywords ~= nil then
                granted.keywords.Charge = nil
            end
            local plan = FindBestStrikePlan(ai, actor, granted, nil, paths)
            if plan ~= nil and (best == nil or plan.utility > best.utility) then
                plan.actor = actor
                plan.ability = granted
                best = plan
            end
        end
    end

    ai.activeTactics = oldTactics
    return best
end

MonsterAI:RegisterMaliceAbility{
    id = "Dwarf Malice: Rappelling Barrage",
    monsterGroups = {"Dwarf"},
    abilities = {"Rappelling Barrage"},
    description = "Grant the acting dwarves climb speed, movement, and a free strike when at least one useful strike is available.",
    score = function(self, ai, token, ability, context)
        local plans = {}
        for _,actor in ipairs(context.groupTokens) do
            local plan = FindGrantedFreeStrikePlan(ai, actor)
            if plan ~= nil then
                plans[#plans+1] = plan
            end
        end
        if #plans > 0 then
            return {
                score = math.min(0.9, 0.66 + (#plans - 1)*0.09),
                plans = plans,
            }
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local climbBehavior = nil
        for _,behavior in ipairs(ability.behaviors or {}) do
            if behavior.typeName == "ActivatedAbilityApplyAbilityDurationEffect" then
                climbBehavior = behavior
                break
            end
        end
        if climbBehavior == nil then
            return
        end

        local leader = ai:FindMostSeniorInitiativeGroupMember(context.actingTokens)
        if leader ~= nil then
            Speak(ai, leader, rappellingBarrageSpeech)
        end

        local targets = {}
        for _,actor in ipairs(context.groupTokens) do
            if LiveCreature(actor) then
                targets[#targets+1] = {token = actor}
            end
        end
        local activation = DeepCopy(ability)
        activation.targetType = "target"
        activation.numTargets = math.max(1, #targets)
        activation.behaviors = {DeepCopy(climbBehavior)}
        ai:ExecuteAbility(token, activation, targets, {sleep = abilityPause})

        for _,plan in ipairs(scoringInfo.plans or {}) do
            if LiveCreature(plan.actor) then
                local ok, err = ai:RunWithTokenControl(plan.actor, function()
                    MoveCinematically(ai, plan.actor, plan.loc)
                    for _,target in ipairs(plan.targets) do
                        target.charge = nil
                    end
                    ai:ExecuteAbility(plan.actor, plan.ability, plan.targets, {
                        sleep = abilityPause,
                    })
                end)
                if not ok then
                    print(string.format("AI:: Dwarf rappelling strike failed: %s", tostring(err)))
                end
            end
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Dwarf Malice: Snaring Line",
    monsterGroups = {"Dwarf"},
    abilities = {"Snaring Line"},
    description = "Place a persistent snaring line through at least two enemies without catching allies.",
    score = function(self, ai, token, ability, context)
        local plan = ai:FindBestLinePlan(token, ability, {
            candidates = context.enemyTokens,
            scorefn = function(target)
                return cond(target:IsFriend(token), -4, 1)
            end,
        })
        if plan ~= nil then
            local enemies, allies = CountByAllegiance(token, plan.targets)
            if enemies >= 2 and allies == 0 then
                plan.enemies = enemies
                plan.score = math.min(0.95, 0.78 + (enemies - 2)*0.07)
                return plan
            end
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildLineArea(token, ability, scoringInfo.targetLoc)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

--------------------------------------------------------------------------------
-- Marauder lord villain actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterVillainAction{
    id = "Dwarf Marauder Lord: Ajax Will Pay Well for These Specimens",
    monsters = {"Dwarf Marauder Lord"},
    abilities = {"Ajax Will Pay Well for These Specimens "},
    description = "Use Levitating Axes across the cube that catches the most enemies.",
    score = function(self, ai, token, ability, context)
        local plan = FindBestCubePlanAtCurrentLoc(token, ability, ai.enemyTokens)
        if plan ~= nil then
            plan.score = math.min(0.95, 0.55 + plan.enemies*0.12)
            return plan
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local area = BuildCubeArea(token, ability, scoringInfo.center)
        local targets = TokensInArea(token, ability, area, {})
        ExecuteAreaAbility(ai, token, ability, area, targets)
    end,
}

local function FindShiftTowardEnemy(ai, actor)
    if not LiveCreature(actor) then
        return nil
    end
    local range = actor.properties:CurrentMovementSpeed()
    local paths = actor:CalculatePathfindingArea(range*10, {"shift"})
    local best = nil
    for _,pathInfo in pairs(paths or {}) do
        local distance = 999
        actor:ExecuteWithTheoreticalLoc(pathInfo.loc, function()
            for _,enemy in ipairs(ai.enemyTokens) do
                if LiveCreature(enemy) then
                    distance = math.min(distance, actor:Distance(enemy))
                end
            end
        end)
        local score = -distance - (pathInfo.cost or 0)*0.001
        if best == nil or score > best.score then
            best = {loc = pathInfo.loc, score = score}
        end
    end
    return best ~= nil and best.loc or nil
end

MonsterAI:RegisterVillainAction{
    id = "Dwarf Marauder Lord: Don't Let Them Escape!",
    monsters = {"Dwarf Marauder Lord"},
    abilities = {"Don't Let Them Escape!"},
    description = "Shift nearby allies toward the enemy, then make the granted Levitating Axes strike.",
    score = function(self, ai, token, ability, context)
        local allies = 0
        for _,ally in ipairs(ai.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and token:Distance(ally) <= ability:GetRange(token.properties)
                and ability:TargetPassesFilter(token, ally, {}) then
                allies = allies + 1
            end
        end
        if #ai.enemyTokens > 0 then
            return {score = math.min(0.9, 0.58 + allies*0.07), allies = allies}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local targets = {}
        for _,ally in ipairs(ai.allyTokens) do
            if LiveCreature(ally) and ally.charid ~= token.charid
                and token:Distance(ally) <= ability:GetRange(token.properties)
                and ability:TargetPassesFilter(token, ally, {}) then
                targets[#targets+1] = {token = ally}
            end
        end

        local activation = DeepCopy(ability)
        activation.targetType = "self"
        activation.targetFilter = ""
        activation.targetAllegiance = nil
        activation.numTargets = 1
        activation.behaviors = {}
        ai:ExecuteAbility(token, activation, {{token = token}}, {sleep = stationaryPause})

        for _,targetInfo in ipairs(targets) do
            local ally = targetInfo.token
            local loc = FindShiftTowardEnemy(ai, ally)
            if loc ~= nil and loc.str ~= ally.loc.str then
                local shift = MCDMUtils.GetStandardAbility("Shift"):MakeTemporaryClone()
                shift.range = ally.properties:CurrentMovementSpeed()
                ClearAbilityCosts(shift)
                local ok, err = ai:RunWithTokenControl(ally, function()
                    ai:ExecuteAbility(ally, shift, {{loc = loc}}, {sleep = movementPause})
                end)
                if not ok then
                    print(string.format("AI:: Dwarf villain shift failed: %s", tostring(err)))
                end
            end
        end

        local axes = FindAbility(token, "Levitating Axes")
        if axes ~= nil then
            local grantedAxes = DeepCopy(axes)
            ClearAbilityCosts(grantedAxes)
            local plan = FindBestStrikePlan(ai, token, grantedAxes, nil, {
                {loc = token.loc, cost = 0},
            })
            if plan ~= nil then
                ExecuteStrikePlan(ai, token, plan, grantedAxes)
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- Trigger decisions.
--------------------------------------------------------------------------------

local function TriggerEnemy(token, triggerInfo)
    for _,charid in ipairs(triggerInfo.targets or {}) do
        local target = FindTokenByCharid(charid)
        if LiveCreature(target) and not target:IsFriend(token) then
            return target
        end
    end
end

local function FindAdjacentSplitShotTarget(gunner, anchor)
    if not LiveCreature(anchor) then
        return nil
    end
    local best = nil
    local bestStamina = nil
    for _,target in ipairs(dmhub.allTokens) do
        if LiveCreature(target) and not target:IsFriend(gunner)
            and target.charid ~= anchor.charid and target:Distance(anchor) <= 1 then
            local stamina = target.properties:CurrentHitpoints()
            if best == nil or stamina < bestStamina then
                best = target
                bestStamina = stamina
            end
        end
    end
    return best
end

MonsterAI:RegisterTrigger{
    id = "Dwarf Gunner: Split Shot",
    monsters = {"Dwarf Gunner"},
    abilityGuids = {"edb16676-2402-4969-9992-137ad87dfcde"},
    abilities = {"Split Shot"},
    description = "Deal Split Shot's extra damage to a safe enemy adjacent to the original target.",
    handler = function(ai, token, triggerInfo)
        local anchor = TriggerEnemy(token, triggerInfo)
        local target = FindAdjacentSplitShotTarget(token, anchor)
        if target == nil then
            return {dismiss = true}
        end
        ai._tmp_dwarfSplitShotTarget = target.charid
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarves: We Have a Quota!",
    monsters = reelWinchMonsters,
    abilityGuids = {
        "4d298727-ba25-40d9-a743-9f10c0052ca6",
        "e3ee06c8-5a53-4aea-83cb-ae4a379cdd6b",
    },
    abilities = {"We Have a Quota!"},
    description = "Always upgrade a qualifying slowed or grabbed target to restrained.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarf Shieldwall: Call to the Wall",
    monsters = {"Dwarf Shieldwall"},
    abilityGuids = {
        "84311db1-67c3-47a3-ad69-6a214452e3d6",
        "2b3c4d5e-6f7a-8b9c-0d1e-2f3a4b5c6d7f",
    },
    abilities = {" Call to the Wall", "Call to the Wall (Deal Damage)"},
    description = "Taunt creatures that damage the shieldwall or are damaged by it.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarf Trapper: Steam Powered Snare Damage",
    abilityGuids = {"96e47cd2-7bf5-40e8-9023-cd81cae266a8"},
    description = "Resolve the persistent snare when an enemy enters it.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarf Servitor: Mobile Prison Harness",
    monsters = {"Servitor War Walker"},
    abilityGuids = {"e5e80edd-0a5d-4f1b-ab05-9bd2646ca5b1"},
    abilities = {"Mobile Prison Harness"},
    description = "Automatically secure slowed or restrained creatures adjacent to the war walker.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarf Marauder Lord: Your Weapon Is Useless",
    monsters = {"Dwarf Marauder Lord"},
    triggers = {"Your Weapon Is Useless"},
    description = "Halve an eligible melee strike and retaliate against its attacker.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarf Marauder Lord: Your Weapon Is Useless Retaliation",
    monsters = {"Dwarf Marauder Lord"},
    abilityGuids = {"565d7a89-1c18-4463-9ca4-970aa0100b70"},
    abilities = {"New Ability"},
    description = "Apply the triggered 4 damage to the melee attacker.",
    handler = function(ai, token, triggerInfo)
        local target = TriggerEnemy(token, triggerInfo)
        if target == nil then
            return {dismiss = true}
        end
        return {
            activate = true,
            expectedPrompt = {
                casterid = token.charid,
                targets = {{token = target}},
                sleep = stationaryPause,
            },
        }
    end,
}

MonsterAI:RegisterTrigger{
    id = "Dwarf Marauder Lord: End Effect",
    monsters = {"Dwarf Marauder Lord"},
    abilityGuids = {"fc4a5c00-3e82-43d1-9492-0f5583fa4f58"},
    abilities = {"End Effect"},
    description = "Take 5 damage to end a save-ends effect unless it would reduce the marauder lord to 0 Stamina.",
    handler = function(ai, token, triggerInfo)
        if token.properties:CurrentHitpoints() > 5 then
            return {activate = true}
        end
        return {dismiss = true}
    end,
}

--------------------------------------------------------------------------------
-- Secondary prompts.
--------------------------------------------------------------------------------

local genericPullPrompt = MonsterAI.prompts["Pull!"]
local genericSlidePrompt = MonsterAI.prompts["Slide!"]

MonsterAI:RegisterPrompt{
    prompts = {"Dwarf Gunner:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if abilityClone:try_get("guid", "") ~= portableBallistaCollisionAbilityId then
            return nil
        end

        local cast = symbols.cast
        if type(cast) == "function" then
            cast = cast("self")
        end
        if cast == nil or not CanSpendMalice(5) then
            return {targets = {}}
        end

        local targets = {}
        local collisionIds = cast:try_get("forcedMovementCreatureCollisionIds", {})
        for charid in pairs(collisionIds) do
            local target = FindTokenByCharid(charid)
            if not LiveCreature(target) then
                return {targets = {}}
            end
            targets[#targets+1] = {token = target}
        end

        if #targets < 2 then
            return {targets = {}}
        end

        -- ExecuteInvoke's AI-resolved path bypasses the action bar, so stamp
        -- payment only on the accepted custom ability. A rejected prompt casts
        -- no targets and cannot spend Malice.
        abilityClone._tmp_payInvokedCost = true
        return {targets = targets}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {
        "Dwarf Reel Winch:Forced Movement: Pull",
        "Dwarf Engineer:Forced Movement: Pull",
        "Servitor War Walker:Forced Movement: Pull",
        "Servitor Battle Walker:Forced Movement: Pull",
    },
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if genericPullPrompt ~= nil then
            return genericPullPrompt.handler(
                ai, invokerToken, casterToken, abilityClone, symbols, options)
        end
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Dwarf Marauder Lord:Forced Movement: Vertical Slide"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if genericSlidePrompt ~= nil then
            return genericSlidePrompt.handler(
                ai, invokerToken, casterToken, abilityClone, symbols, options)
        end
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Dwarf Gunner:Split Shot Damage"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local target = FindTokenByCharid(ai:try_get("_tmp_dwarfSplitShotTarget", ""))
        ai._tmp_dwarfSplitShotTarget = nil
        if LiveCreature(target) and casterToken:Distance(target) <= 1
            and abilityClone:TargetPassesFilter(invokerToken, target, symbols) then
            return {targets = {{token = target}}}
        end
        return {targets = {}}
    end,
}

local function FindMarauderRestraintTarget(invokerToken, abilityClone, symbols)
    local best = nil
    local bestStamina = nil
    for _,target in ipairs(dmhub.allTokens) do
        if LiveCreature(target) and not target:IsFriend(invokerToken)
            and invokerToken:Distance(target) <= abilityClone:GetRange(invokerToken.properties)
            and abilityClone:TargetPassesFilter(invokerToken, target, symbols) then
            local stamina = target.properties:CurrentHitpoints()
            if best == nil or stamina > bestStamina then
                best = target
                bestStamina = stamina
            end
        end
    end
    return best
end

MonsterAI:RegisterPrompt{
    prompts = {"Dwarf Marauder Lord:Levitating Axes - 3 Malice Restrain"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if not CanSpendMalice(3) then
            return {targets = {}}
        end
        local target = FindMarauderRestraintTarget(invokerToken, abilityClone, symbols)
        return {targets = cond(target ~= nil, {{token = target}}, {})}
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Dwarf Marauder Lord:Invoked Ability"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local guid = abilityClone:try_get("guid", "")
        if guid == "88c0bc57-8dfe-4b1f-a56c-86636e57a576" then
            if not CanSpendMalice(3) then
                return {targets = {}}
            end
            local target = FindMarauderRestraintTarget(invokerToken, abilityClone, symbols)
            return {targets = cond(target ~= nil, {{token = target}}, {})}
        elseif guid == "f99c39fe-8c43-4035-9d2b-520f81bfc295" then
            local target = nil
            for _,candidate in ipairs(dmhub.allTokens) do
                if LiveCreature(candidate) and not candidate:IsFriend(invokerToken)
                    and invokerToken:Distance(candidate) <= abilityClone:GetRange(invokerToken.properties) then
                    target = candidate
                    break
                end
            end
            return {targets = cond(target ~= nil, {{token = target}}, {})}
        end
    end,
}
