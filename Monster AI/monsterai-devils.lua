local mod = dmhub.GetModLoading()

local devilCharmers = {
    "Devil Adjudicator",
    "Devil Jurist",
    "Devil Legate",
    "Devil Magistrate",
}

local devilSpeech = {
    ["Devil Adjudicator: Adjudicator's Interdiction"] = {
        "Objection sustained.",
        "Your motion is denied.",
        "The court forbids it.",
    },
    ["Devil Adjudicator: Quid Pro Quo"] = {
        "Quid pro quo.",
        "A fair exchange.",
        "Let us trade places.",
    },
    ["Devil Jurist: Dismissal with Prejudice"] = {
        "Dismissed with prejudice.",
        "Clear the court.",
        "Your case is thrown out.",
    },
    ["Devil Jurist: Ashes to Ashes"] = {
        "Ashes to ashes.",
        "The sentence is fire.",
        "Your appeal ends in flame.",
    },
    ["Devil Legate: Writ of Execution"] = {
        "The writ is served.",
        "Execution is ordered.",
        "No appeal.",
    },
    ["Devil Legate: Law and Order"] = {
        "Law and order.",
        "You answer to me.",
        "Face your accuser.",
    },
    ["Devil Magistrate: Verdict"] = {
        "The verdict is guilty.",
        "Sentence: death.",
        "Judgment is final.",
    },
    ["Devil Magistrate: Justice Turns Its Gaze"] = {
        "Justice turns its gaze.",
        "You cannot strike what you cannot see.",
        "The law moves unseen.",
    },
    ["Devil High Judge: Compel the Jury"] = {
        "The jury will obey.",
        "You will see reason.",
        "Your will is overruled.",
    },
    ["Devil High Judge: All Rise"] = {
        "All rise.",
        "This court is now in session.",
        "Stand before your judge.",
    },
    ["Devil High Judge: Heed My Decree"] = {
        "Heed my decree.",
        "Take your appointed places.",
        "The court will come to order.",
    },
    ["Devil High Judge: Deceptive Stratagem"] = {
        "A simple change of venue.",
        "You have mistaken the defendant.",
        "Let us rearrange the evidence.",
    },
}

local movementPause = 0.75
local stationaryPause = 0.35
local speechPause = 0.45
local abilityPause = 0.9

local function Speak(ai, token, moveid)
    local lines = devilSpeech[moveid]
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

local function HasOngoingEffect(token, effectid)
    if token == nil or not token.valid or token.properties == nil then
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
    pcall(function()
        result = token.properties:HasNamedCondition(conditionName)
    end)
    return result
end

local function AttributeValue(token, attributeName, fallback)
    local result = fallback
    pcall(function()
        result = token.properties:GetAttribute(attributeName):Value()
    end)
    return result
end

local function MonsterType(token)
    if token == nil or token.properties == nil then
        return ""
    end
    return token.properties:try_get("monster_type", "")
end

local function IsDevil(token)
    local monsterType = MonsterType(token)
    return monsterType == "Archdevil" or string.starts_with(monsterType, "Devil ")
end

local function FindAbility(token, abilityName)
    if token == nil or token.properties == nil then
        return nil
    end
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == abilityName then
            return ability
        end
    end
end

local function LiveToken(token)
    return token ~= nil and token.valid and token.properties ~= nil
        and not token.properties:IsDead()
end

local function DefaultTargetScore(targetInfo)
    return 1 + (targetInfo.edges or 0)*0.1
end

-- Build a full move-and-target plan so custom priorities used during scoring
-- are also honored during execution. The core strike helper only returns a
-- location and otherwise re-sorts targets by edges during execution.
local function FindBestStrikePlan(ai, token, ability, targetScore, groupScore)
    targetScore = targetScore or DefaultTargetScore
    local range = ability:GetRange(token.properties)
    local numTargets = ability:GetNumTargets(token)
    local best = nil

    for _,pathInfo in pairs(ai.paths) do
        local candidates = {}
        for _,targetInfo in ipairs(ai:FindValidTargetsOfStrike(token, ability, pathInfo.loc, range)) do
            local score = targetScore(targetInfo)
            if score ~= nil then
                candidates[#candidates+1] = {
                    info = targetInfo,
                    score = score,
                }
            end
        end

        table.sort(candidates, function(a, b)
            return a.score > b.score
        end)

        local selected = {}
        local score = 0
        for i=1,math.min(numTargets, #candidates) do
            selected[#selected+1] = candidates[i].info
            score = score + candidates[i].score
        end

        if #selected > 0 then
            if groupScore ~= nil then
                local groupTargets = nil
                score, groupTargets = groupScore(selected, score, candidates)
                selected = groupTargets or selected
            end
            score = score - (pathInfo.cost or 0)*0.001
            if best == nil or score > best.utility then
                best = {
                    loc = pathInfo.loc,
                    targets = selected,
                    utility = score,
                }
            end
        end
    end

    return best
end

local function ExecuteStrikePlan(ai, token, scoringInfo, ability, moveid, options)
    MoveCinematically(ai, token, scoringInfo.loc)
    Speak(ai, token, moveid)
    options = options or {}
    local executingAbility = options.ability or ability
    options.ability = nil
    options.sleep = options.sleep or abilityPause
    ai:ExecuteAbility(token, executingAbility, scoringInfo.targets, options)
end

local function RegisterStrike(args)
    MonsterAI:RegisterMove{
        id = args.id,
        category = args.category or "Main Actions",
        monsters = args.monsters,
        abilities = {args.ability},
        description = args.description,
        score = function(self, ai, token, ability)
            local plan = FindBestStrikePlan(ai, token, ability, args.targetScore, args.groupScore)
            if plan ~= nil then
                plan.score = type(args.score) == "function"
                    and args.score(token, ability, plan) or (args.score or 1)
                return plan
            end
        end,
        execute = function(self, ai, token, scoringInfo, ability)
            if args.execute ~= nil then
                args.execute(self, ai, token, scoringInfo, ability)
                return
            end
            local options = nil
            if args.options ~= nil then
                options = args.options(token, ability, scoringInfo)
            end
            ExecuteStrikePlan(ai, token, scoringInfo, ability, args.id, options)
        end,
    }
end

local function DistanceFromNearestEnemy(ai, loc)
    local result = 999
    for _,enemy in ipairs(ai.enemyTokens) do
        if LiveToken(enemy) then
            result = math.min(result, enemy:Distance(loc))
        end
    end
    return result
end

local function FindBestRepositionLoc(ai, movingToken, range, retreat, movementFlags)
    local paths = movingToken:CalculatePathfindingArea(range*10, movementFlags or {"shift"})
    local bestLoc = nil
    local bestScore = nil
    for _,info in pairs(paths) do
        local enemyDistance = DistanceFromNearestEnemy(ai, info.loc)
        local score = cond(retreat, enemyDistance, -enemyDistance)
            - (info.cost or 0)*0.001
        if bestScore == nil or score > bestScore then
            bestScore = score
            bestLoc = info.loc
        end
    end
    return bestLoc
end

local function ExecuteGrantedMovement(ai, movingToken, standardAbilityName, range,
    retreat, movementFlags)
    local loc = FindBestRepositionLoc(ai, movingToken, range, retreat, movementFlags)
    if loc == nil or loc.str == movingToken.loc.str then
        return false
    end

    local movementAbility = MCDMUtils.GetStandardAbility(standardAbilityName):MakeTemporaryClone()
    movementAbility.range = range
    movementAbility.targetFilter = ""
    local ok, err = ai:RunWithTokenControl(movingToken, function()
        ai:ExecuteAbility(movingToken, movementAbility, {{loc = loc}},
            {sleep = movementPause})
    end)
    if not ok then
        print(string.format("AI:: Devil granted movement failed: %s", tostring(err)))
        return false
    end
    return true
end

local function ConfigureFreeStrikeAI(ai, token)
    ai.token = token
    ai.abilities = token.properties:GetActivatedAbilities()
    ai.activeTactics = {}
    for id,tactic in pairs(ai.tactics) do
        if ai.MoveMatchesMonster(token, tactic) then
            ai.activeTactics[id] = tactic
        end
    end
end

local function HasAffordableFreeStrike(token)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if (ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike")
            and ability:CanAfford(token) then
            return true
        end
    end
    return false
end

local function FindFreeStrikePlan(ai, token)
    ConfigureFreeStrikeAI(ai, token)
    local best = nil
    for _,ability in ipairs(ai.abilities) do
        if (ability.name == "Melee Free Strike" or ability.name == "Ranged Free Strike")
            and ability:CanAfford(token) then
            local scoringAbility = ability:MakeTemporaryClone()
            if scoringAbility.keywords ~= nil then
                scoringAbility.keywords.Charge = nil
            end
            local targets = ai:FindValidTargetsOfStrike(token, scoringAbility, token.loc)
            if #targets > 0 then
                table.resize_array(targets, ability:GetNumTargets(token))
                local score = #targets + (targets[1].edges or 0)*0.1
                if best == nil or score > best.score then
                    best = {
                        ability = ability,
                        score = score,
                        targets = targets,
                    }
                end
            end
        end
    end
    return best
end

local function ExecuteFreeStrike(ai, token)
    local plan = FindFreeStrikePlan(ai, token)
    if plan == nil then
        return false
    end

    for _,target in ipairs(plan.targets) do
        target.charge = nil
    end
    local ok, err = ai:RunWithTokenControl(token, function()
        ai:ExecuteAbility(token, plan.ability, plan.targets, {sleep = abilityPause})
    end)
    if not ok then
        print(string.format("AI:: Devil free strike failed: %s", tostring(err)))
        return false
    end
    return true
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

local function AdjacentLocs(loc)
    return {
        loc.north,
        loc.north.east,
        loc.east,
        loc.south.east,
        loc.south,
        loc.south.west,
        loc.west,
        loc.north.west,
    }
end

local function FindUnderhandedPlan(ai, actor, reservedLocs)
    local best = nil
    for _,enemy in ipairs(ai.enemyTokens) do
        if LiveToken(enemy) and not HasCondition(enemy, "Hidden") then
            for _,loc in ipairs(AdjacentLocs(enemy.loc)) do
                if EmptyLoc(loc) and not reservedLocs[loc.str] then
                    local stamina = enemy.properties:CurrentHitpoints()
                        / math.max(1, enemy.properties.max_hitpoints)
                    local score = 2 - stamina
                    if best == nil or score > best.score then
                        best = {
                            loc = loc,
                            score = score,
                            target = enemy,
                        }
                    end
                end
            end
        end
    end
    return best
end

local function FindBestPromptTargets(casterToken, ability, symbols, filter, allTargets)
    local result = {}
    local range = ability:GetRange(casterToken.properties, symbols)
    for _,target in ipairs(dmhub.allTokens) do
        if LiveToken(target) and casterToken:Distance(target) <= range
            and ability:TargetPassesFilter(casterToken, target, symbols)
            and (filter == nil or filter(target)) then
            result[#result+1] = {token = target}
        end
    end

    table.sort(result, function(a, b)
        local ahp = a.token.properties:CurrentHitpoints()
            / math.max(1, a.token.properties.max_hitpoints)
        local bhp = b.token.properties:CurrentHitpoints()
            / math.max(1, b.token.properties.max_hitpoints)
        return ahp < bhp
    end)

    if not allTargets then
        table.resize_array(result, ability:GetNumTargets(casterToken, symbols))
    end
    return result
end

local burningEffectId = "420d80fa-3784-4b7e-9b6c-586deed49d4e"
local interdictionTierOneEffectId = "20b162d6-d80d-4670-8ed1-17af268296ea"
local interdictionTierTwoEffectId = "4725f308-376e-4a3e-a2ae-48b12cb2df49"
local charmedByHighJudgeEffectId = "4a607059-6413-49d4-80f5-c6f2f75619ae"
local cannotHideEffectId = "6c3135e3-73a6-4dbe-bdd6-8c726828bc28"
local cannotHideMaliceEffectId = "35e5153d-24b7-4f57-b514-c5e5a7ba45d8"
local notaryEdgeEffectId = "21827a29-9af8-46ac-86a0-fc74841584a8"
local smallPrintWeaknessEffectId = "a5feff79-ba94-487f-be63-0db2898d05a2"
local smallPrintBaneEffectId = "54455d3b-5abe-46a3-90db-20ada18c4e95"

local function CannotHideFromDecree(token)
    return HasOngoingEffect(token, cannotHideEffectId)
        or HasOngoingEffect(token, cannotHideMaliceEffectId)
end

--------------------------------------------------------------------------------
-- Start-of-turn Devil Malice.
--------------------------------------------------------------------------------

MonsterAI:RegisterMaliceAbility{
    id = "Devil Malice: Bureaucratic Tape",
    monsterGroups = {"Devil"},
    abilities = {"Bureaucratic Tape"},
    description = "When an acting devil is adjacent to an enemy, spend 3 Malice to make a signature strike with the tier-3 double-bane rider.",
    minimumScore = 0.7,
    score = function(self, ai, token, ability, context)
        for _,actor in ipairs(context.actingTokens) do
            if LiveToken(actor) and IsDevil(actor) then
                for _,signature in ipairs(actor.properties:GetActivatedAbilities()) do
                    if signature.categorization == "Signature Ability"
                        and signature:HasKeyword("Strike") then
                        for _,enemy in ipairs(context.enemyTokens) do
                            if LiveToken(enemy) and actor:Distance(enemy) <= 1
                                and signature:TargetPassesFilter(actor, enemy, {}) then
                                return {
                                    score = 0.78,
                                    actor = actor,
                                    signatureName = signature.name,
                                    target = enemy,
                                }
                            end
                        end
                    end
                end
            end
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local actor = scoringInfo.actor
        local actorMaliceAbility = FindAbility(actor, "Bureaucratic Tape") or ability
        local synthesized = actorMaliceAbility.behaviors[1]:SynthesizeAbilities(
            actorMaliceAbility, actor.properties)
        local signature = nil
        for _,candidate in ipairs(synthesized or {}) do
            if candidate.name == scoringInfo.signatureName then
                signature = candidate
                break
            end
        end
        if signature == nil then
            print("AI:: Bureaucratic Tape could not synthesize the selected signature")
            return
        end

        local ok, err = ai:RunWithTokenControl(actor, function()
            ai:ExecuteAbility(actor, signature, {{token = scoringInfo.target}},
                {sleep = abilityPause})
        end)
        if not ok then
            print(string.format("AI:: Bureaucratic Tape signature failed: %s", tostring(err)))
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Devil Malice: Underhanded Tactics",
    monsterGroups = {"Devil"},
    abilities = {"Underhanded Tactics"},
    description = "Spend 5 Malice when two devils can teleport beside visible enemies and immediately make useful free strikes.",
    score = function(self, ai, token, ability, context)
        local plans = {}
        local reservedLocs = {}
        for _,actor in ipairs(context.allyTokens) do
            if LiveToken(actor) and IsDevil(actor) and HasAffordableFreeStrike(actor) then
                local plan = FindUnderhandedPlan(ai, actor, reservedLocs)
                if plan ~= nil then
                    plans[#plans+1] = {actor = actor, plan = plan}
                    reservedLocs[plan.loc.str] = true
                end
            end
        end
        table.sort(plans, function(a, b)
            return a.plan.score > b.plan.score
        end)
        table.resize_array(plans, 2)
        if #plans < 2 then
            return nil
        end
        return {
            score = math.min(1, 0.65 + #plans*0.1),
            plans = plans,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local activation = DeepCopy(ability)
        activation.behaviors = {}
        activation.targetType = "self"
        activation.numTargets = 1
        ai:ExecuteAbility(token, activation, {}, {sleep = abilityPause})

        for _,entry in ipairs(scoringInfo.plans) do
            local actor = entry.actor
            if LiveToken(actor) and EmptyLoc(entry.plan.loc) then
                actor:Teleport(entry.plan.loc, false)
                ai.Sleep(movementPause)
                ExecuteFreeStrike(ai, actor)
            end
        end
    end,
}

MonsterAI:RegisterMaliceAbility{
    id = "Devil Malice: Read the Small Print",
    monsterGroups = {"Devil"},
    abilities = {"Read the Small Print"},
    description = "Spend 7 Malice early in a fight to offer every unaffected enemy the encounter-long bad deal.",
    minimumScore = 0.75,
    score = function(self, ai, token, ability, context)
        if context.round ~= nil and context.round > 2 then
            return nil
        end
        local unaffected = 0
        for _,enemy in ipairs(context.enemyTokens) do
            if LiveToken(enemy) and not HasOngoingEffect(enemy, smallPrintWeaknessEffectId)
                and not HasOngoingEffect(enemy, smallPrintBaneEffectId) then
                unaffected = unaffected + 1
            end
        end
        if unaffected < 2 then
            return nil
        end
        return {
            score = math.min(1, 0.62 + unaffected*0.08),
            unaffected = unaffected,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        local allEnemies = DeepCopy(ability)
        allEnemies.targetType = "all"
        ai:ExecuteAbility(token, allEnemies, nil, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Devil Adjudicator.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Devil Adjudicator: Infernal Injunction",
    monsters = {"Devil Adjudicator"},
    ability = "Infernal Injunction",
    description = "Use Infernal Injunction against up to two enemies, preferring targets not already frightened.",
    score = 1,
    targetScore = function(targetInfo)
        return 1 + (targetInfo.edges or 0)*0.1
            + cond(HasCondition(targetInfo.token, "Frightened"), 0, 0.25)
    end,
    options = function(token, ability, scoringInfo)
        local mode = cond(token.properties:try_get("monsterMode", 1) == 2, 2, 1)
        return {
            ability = ability:SwitchModes(mode),
            symbols = {mode = mode},
        }
    end,
}

RegisterStrike{
    id = "Devil Adjudicator: Adjudicator's Interdiction",
    monsters = {"Devil Adjudicator"},
    ability = "Adjudicator's Interdiction",
    description = "Prefer the interdiction against a healthy enemy not already suffering one of its lasting penalties.",
    score = 1.15,
    targetScore = function(targetInfo)
        local target = targetInfo.token
        if HasOngoingEffect(target, interdictionTierOneEffectId)
            or HasOngoingEffect(target, interdictionTierTwoEffectId) then
            return nil
        end
        local stamina = target.properties:CurrentHitpoints()
            / math.max(1, target.properties.max_hitpoints)
        return 1 + stamina*0.4 + (targetInfo.edges or 0)*0.1
    end,
}

MonsterAI:RegisterMove{
    id = "Devil Adjudicator: Quid Pro Quo",
    category = "Maneuvers",
    monsters = {"Devil Adjudicator"},
    abilities = {"Quid Pro Quo"},
    description = "When threatened in melee, swap with a legal target that puts the adjudicator farther from the nearest enemy.",
    score = function(self, ai, token, ability)
        local currentSafety = DistanceFromNearestEnemy(ai, token.loc)
        if currentSafety > 1 then
            return nil
        end

        local best = nil
        local range = ability:GetRange(token.properties)
        for _,target in ipairs(dmhub.allTokens) do
            if LiveToken(target) and target.charid ~= token.charid
                and token:Distance(target) <= range
                and ability:TargetPassesFilter(token, target, {}) then
                local safety = DistanceFromNearestEnemy(ai, target.loc)
                if safety >= currentSafety + 2 and (best == nil or safety > best.safety) then
                    best = {target = target, safety = safety}
                end
            end
        end

        if best ~= nil then
            return {score = 0.7, target = best.target}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        Speak(ai, token, self.id)
        ai:ExecuteAbility(token, ability, {{token = scoringInfo.target}}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Devil Jurist.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Devil Jurist: Fire and Brimstone",
    monsters = {"Devil Jurist"},
    ability = "Fire and Brimstone",
    description = "Set up burning on as many new targets as possible with Fire and Brimstone.",
    score = 1,
    targetScore = function(targetInfo)
        return 1 + (targetInfo.edges or 0)*0.1
            + cond(HasOngoingEffect(targetInfo.token, burningEffectId), 0, 0.5)
    end,
    options = function(token, ability, scoringInfo)
        local mode = cond(token.properties:try_get("monsterMode", 1) == 2, 2, 1)
        return {
            ability = ability:SwitchModes(mode),
            symbols = {mode = mode},
        }
    end,
}

MonsterAI:RegisterMove{
    id = "Devil Jurist: Dismissal with Prejudice",
    category = "Main Actions",
    monsters = {"Devil Jurist"},
    abilities = {"Dismissal with Prejudice"},
    description = "Move into a useful burst and dismiss at least two enemies with prejudice.",
    score = function(self, ai, token, ability)
        local loc, score = ai:FindBestMoveToUseBurst(token, ability, function(target)
            return cond(target:IsFriend(token), -2, 1)
        end)
        if loc ~= nil and score ~= nil and score >= 2 then
            return {score = 1.35 + math.min(0.3, (score - 2)*0.1), loc = loc}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        MoveCinematically(ai, token, scoringInfo.loc)
        Speak(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

RegisterStrike{
    id = "Devil Jurist: Ashes to Ashes",
    category = "Maneuvers",
    monsters = {"Devil Jurist"},
    ability = "Ashes to Ashes",
    description = "After the main action, deal automatic fire damage to a burning enemy.",
    score = 0.85,
    targetScore = function(targetInfo)
        if not HasOngoingEffect(targetInfo.token, burningEffectId) then
            return nil
        end
        local stamina = targetInfo.token.properties:CurrentHitpoints()
            / math.max(1, targetInfo.token.properties.max_hitpoints)
        return 2 - stamina + (targetInfo.edges or 0)*0.1
    end,
}

--------------------------------------------------------------------------------
-- Devil Legate.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Devil Legate: Infernal Pike",
    monsters = {"Devil Legate"},
    ability = "Infernal Pike",
    description = "Use Infernal Pike against two enemies, strongly preferring an adjacent pair for the bonus damage.",
    score = 1.05,
    groupScore = function(targets, score, candidates)
        for i=1,#candidates do
            for j=i+1,#candidates do
                local first = candidates[i]
                local second = candidates[j]
                if first.info.token:Distance(second.info.token) <= 1 then
                    return first.score + second.score + 1,
                        {first.info, second.info}
                end
            end
        end
        return score
    end,
    options = function(token, ability, scoringInfo)
        local mode = cond(token.properties:try_get("monsterMode", 1) == 2, 2, 1)
        return {
            ability = ability:SwitchModes(mode),
            symbols = {mode = mode},
        }
    end,
}

RegisterStrike{
    id = "Devil Legate: Writ of Execution",
    monsters = {"Devil Legate"},
    ability = "Writ of Execution",
    description = "Use Writ of Execution when its Charge keyword can close the distance and knock enemies down.",
    score = function(token, ability, plan)
        for _,target in ipairs(plan.targets) do
            if target.charge ~= nil then
                return 1.2
            end
        end
        return 0.9
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        local chargeTarget = nil
        for _,target in ipairs(scoringInfo.targets) do
            if target.charge ~= nil then
                chargeTarget = target
                break
            end
        end
        if chargeTarget == nil then
            ExecuteStrikePlan(ai, token, scoringInfo, ability, self.id)
            return
        end

        MoveCinematically(ai, token, scoringInfo.loc)
        Speak(ai, token, self.id)
        local strikeTargets = {}
        for _,target in ipairs(scoringInfo.targets) do
            strikeTargets[#strikeTargets+1] = {token = target.token}
        end
        ai:SetTargetsForExpectedPrompt{
            casterid = token.charid,
            targets = strikeTargets,
            sleep = stationaryPause,
        }
        local chargeAbility = ability:SwitchModes(2)
        ai:ExecuteAbility(token, chargeAbility, {{loc = chargeTarget.charge}}, {
            sleep = abilityPause,
            symbols = {mode = 2},
        })
    end,
}

RegisterStrike{
    id = "Devil Legate: Law and Order",
    category = "Maneuvers",
    monsters = {"Devil Legate"},
    ability = "Law and Order",
    description = "Taunt the healthiest reachable enemy after attacking.",
    score = 0.75,
    targetScore = function(targetInfo)
        if HasCondition(targetInfo.token, "Taunted") then
            return nil
        end
        local stamina = targetInfo.token.properties:CurrentHitpoints()
            / math.max(1, targetInfo.token.properties.max_hitpoints)
        return 1 + stamina + (targetInfo.edges or 0)*0.1
    end,
}

--------------------------------------------------------------------------------
-- Devil Magistrate.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Devil Magistrate: Edge of the Law",
    monsters = {"Devil Magistrate"},
    ability = "Edge of the Law",
    description = "Cut through up to two enemies, then use the post-strike shift to disengage.",
    score = 1,
    execute = function(self, ai, token, scoringInfo, ability)
        local normalMode = token.properties:try_get("monsterMode", 1) == 1
        MoveCinematically(ai, token, scoringInfo.loc)
        if not normalMode then
            ai:ExecuteAbility(token, ability:SwitchModes(3), scoringInfo.targets, {
                sleep = abilityPause,
                symbols = {mode = 3},
            })
            return
        end

        local strikeAbility = DeepCopy(ability)
        strikeAbility.behaviors = {}
        for _,behavior in ipairs(ability.behaviors) do
            if behavior.typeName ~= "ActivatedAbilityInvokeAbilityBehavior" then
                strikeAbility.behaviors[#strikeAbility.behaviors+1] = DeepCopy(behavior)
            end
        end
        ai:ExecuteAbility(token, strikeAbility, scoringInfo.targets, {
            sleep = abilityPause,
            symbols = {mode = 2},
        })
        ExecuteGrantedMovement(ai, token, "Shift", 3, true, {"shift"})
    end,
}

RegisterStrike{
    id = "Devil Magistrate: Verdict",
    monsters = {"Devil Magistrate"},
    ability = "Verdict",
    description = "Deliver the Verdict when hidden or when an enemy is dazed; otherwise prefer Edge of the Law.",
    score = function(token, ability, plan)
        if HasCondition(token, "Hidden") then
            return 1.55
        end
        for _,target in ipairs(plan.targets) do
            if HasCondition(target.token, "Dazed") then
                return 1.35
            end
        end
        return 0.9
    end,
    targetScore = function(targetInfo)
        return 1 + (targetInfo.edges or 0)*0.1
            + cond(HasCondition(targetInfo.token, "Dazed"), 1, 0)
    end,
}

MonsterAI:RegisterMove{
    id = "Devil Magistrate: Justice Turns Its Gaze",
    category = "Maneuvers",
    monsters = {"Devil Magistrate"},
    abilities = {"Justice Turns Its Gaze"},
    description = "Turn invisible and attempt to hide before delivering a Verdict.",
    score = function(self, ai, token, ability)
        if HasCondition(token, "Hidden") or HasCondition(token, "Invisible") then
            return nil
        end
        return {score = 1.25, loc = token.loc}
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        Speak(ai, token, self.id)
        ai:ExecuteAbility(token, ability, {}, {sleep = abilityPause})
    end,
}

--------------------------------------------------------------------------------
-- Devil Defector.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Devil Defector: Black Flame",
    monsters = {"Devil Defector"},
    ability = "Black Flame (Corruption)",
    description = "Use corruption as the safe default Black Flame damage type when target immunities are not known.",
    score = 1,
}

--------------------------------------------------------------------------------
-- Devil High Judge and legacy Archdevil.
--------------------------------------------------------------------------------

RegisterStrike{
    id = "Devil High Judge: Infernal Decree",
    monsters = {"Devil High Judge"},
    ability = "Infernal Decree",
    description = "Issue an Infernal Decree against up to three enemies, preferring targets not already barred from hiding.",
    score = 1,
    targetScore = function(targetInfo)
        return 1 + (targetInfo.edges or 0)*0.1
            + cond(CannotHideFromDecree(targetInfo.token), 0, 0.35)
    end,
    options = function(token, ability, scoringInfo)
        if token.properties:try_get("monsterMode", 1) == 2 then
            return {
                sleep = abilityPause,
                ability = ability:SwitchModes(3),
                symbols = {mode = 3},
            }
        end
        local freshTargets = 0
        for _,target in ipairs(scoringInfo.targets) do
            if not CannotHideFromDecree(target.token) then
                freshTargets = freshTargets + 1
            end
        end
        local mode = 1
        if freshTargets >= 2 and ability:CanAfford(token, {mode = 2}) then
            mode = 2
        end
        return {
            sleep = abilityPause,
            ability = ability:SwitchModes(mode),
            symbols = {mode = mode},
        }
    end,
}

RegisterStrike{
    id = "Devil High Judge: Compel the Jury",
    category = "Maneuvers",
    monsters = {"Devil High Judge"},
    ability = "Compel the Jury",
    description = "Charm up to two enemies, prioritizing low-Intuition targets not already compelled.",
    score = 1.2,
    targetScore = function(targetInfo)
        if HasOngoingEffect(targetInfo.token, charmedByHighJudgeEffectId)
            or HasCondition(targetInfo.token, "Charmed") then
            return nil
        end
        local intuition = AttributeValue(targetInfo.token, "inu", 4)
        return 1 + math.max(0, 4 - intuition)*0.2 + (targetInfo.edges or 0)*0.1
    end,
}

MonsterAI:RegisterMove{
    id = "Devil High Judge: Compelled Movement",
    category = "Maneuvers",
    monsters = {"Devil High Judge"},
    abilities = {"Compelled Movement"},
    description = "Spend 1 Malice after other maneuvers to pull one compelled creature out of position each turn.",
    score = function(self, ai, token, ability)
        if ai:try_get("_tmp_devilsCompelledMovementUsed", false) then
            return nil
        end

        local best = nil
        local range = ability:GetRange(token.properties)
        for _,target in ipairs(dmhub.allTokens) do
            if LiveToken(target) and target.charid ~= token.charid
                and token:Distance(target) <= range
                and HasOngoingEffect(target, charmedByHighJudgeEffectId)
                and ability:TargetPassesFilter(token, target, {}) then
                local stamina = target.properties:CurrentHitpoints()
                    / math.max(1, target.properties.max_hitpoints)
                if best == nil or stamina > best.stamina then
                    best = {target = target, stamina = stamina}
                end
            end
        end
        if best ~= nil then
            return {score = 0.55, target = best.target}
        end
    end,
    execute = function(self, ai, token, scoringInfo, ability)
        ai._tmp_devilsCompelledMovementUsed = true
        local activation = DeepCopy(ability)
        activation.behaviors = {}
        ai:ExecuteAbility(token, activation, {{token = scoringInfo.target}},
            {sleep = stationaryPause})
        ExecuteGrantedMovement(ai, scoringInfo.target, "Move", 3, true, {})
    end,
}

RegisterStrike{
    id = "Archdevil: Infernal Decree",
    monsters = {"Archdevil"},
    ability = "Infernal Decree",
    description = "Use the legacy Archdevil's implemented signature strike against up to three enemies.",
    score = 1,
}

RegisterStrike{
    id = "Archdevil: Compel the Jury",
    category = "Maneuvers",
    monsters = {"Archdevil"},
    ability = "Compel the Jury",
    description = "Use the legacy Archdevil's implemented jury-compulsion maneuver.",
    score = 1.1,
    targetScore = function(targetInfo)
        return 1 + math.max(0, 4 - AttributeValue(targetInfo.token, "inu", 4))*0.2
            + (targetInfo.edges or 0)*0.1
    end,
}

--------------------------------------------------------------------------------
-- Devil High Judge villain actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterVillainAction{
    id = "Devil High Judge: All Rise",
    monsters = {"Devil High Judge"},
    abilities = {"All Rise"},
    description = "Open with All Rise when at least one enemy is caught in the burst, with a strong preference for a full courtroom.",
    score = function(self, ai, token, ability, context)
        local targets = 0
        local range = ability:GetRange(token.properties)
        for _,enemy in ipairs(ai.enemyTokens) do
            if LiveToken(enemy) and token:Distance(enemy) <= range
                and ability:TargetPassesFilter(token, enemy, {}) then
                targets = targets + 1
            end
        end
        if targets == 0 then
            return nil
        end
        return {score = math.min(1, 0.5 + targets*0.13), targets = targets}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, self.id)
        ai:ExecuteAbility(token, ability, nil, {sleep = abilityPause})
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Devil High Judge: Heed My Decree",
    monsters = {"Devil High Judge"},
    abilities = {"Heed My Decree"},
    description = "Reposition nearby allies and any compelled creatures when at least two participants can move.",
    score = function(self, ai, token, ability, context)
        local participants = 1
        local range = ability:GetRange(token.properties)
        for _,ally in ipairs(ai.allyTokens) do
            if LiveToken(ally) and ally.charid ~= token.charid and token:Distance(ally) <= range then
                participants = participants + 1
            end
        end
        for _,other in ipairs(dmhub.allTokens) do
            if LiveToken(other) and other.charid ~= token.charid
                and HasOngoingEffect(other, charmedByHighJudgeEffectId) then
                participants = participants + 1
            end
        end
        if participants < 2 then
            return nil
        end
        return {score = math.min(1, 0.45 + participants*0.1), participants = participants}
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, self.id)
        local activation = DeepCopy(ability)
        activation.behaviors = {}
        activation.targetType = "self"
        activation.numTargets = 1
        ai:ExecuteAbility(token, activation, {}, {sleep = stationaryPause})

        ai:SetupCombatants(token, context.initiativeQueue)
        local moved = {}
        for _,ally in ipairs(ai.allyTokens) do
            if LiveToken(ally) and token:Distance(ally) <= ability:GetRange(token.properties) then
                moved[ally.charid] = true
                ExecuteGrantedMovement(ai, ally, "Shift",
                    ally.properties:CurrentMovementSpeed(), false, {"shift"})
            end
        end
        for _,other in ipairs(dmhub.allTokens) do
            if LiveToken(other) and not moved[other.charid]
                and HasOngoingEffect(other, charmedByHighJudgeEffectId)
                and token:Distance(other) <= 20 then
                ExecuteGrantedMovement(ai, other, "Move",
                    math.floor(other.properties:CurrentMovementSpeed()/2), true, {})
            end
        end
    end,
}

MonsterAI:RegisterVillainAction{
    id = "Devil High Judge: Deceptive Stratagem",
    monsters = {"Devil High Judge"},
    abilities = {"Deceptive Stratagem"},
    description = "Swap into the location that places the most allies within the free-strike command radius.",
    score = function(self, ai, token, ability, context)
        local best = nil
        local range = ability:GetRange(token.properties)
        for _,target in ipairs(dmhub.allTokens) do
            if LiveToken(target) and target.charid ~= token.charid
                and token:Distance(target) <= range
                and ability:TargetPassesFilter(token, target, {}) then
                local allies = 0
                for _,ally in ipairs(ai.allyTokens) do
                    if LiveToken(ally) and ally:Distance(target.loc) <= 12 then
                        allies = allies + 1
                    end
                end
                if best == nil or allies > best.allies then
                    best = {target = target, allies = allies}
                end
            end
        end
        if best == nil then
            return nil
        end
        return {
            score = math.min(1, 0.45 + best.allies*0.1),
            target = best.target,
            allies = best.allies,
        }
    end,
    execute = function(self, ai, token, scoringInfo, ability, context)
        Speak(ai, token, self.id)
        local swapAbility = DeepCopy(ability)
        swapAbility.behaviors = {}
        for _,behavior in ipairs(ability.behaviors) do
            if behavior.typeName == "ActivatedAbilityRelocateCreatureBehavior" then
                swapAbility.behaviors[#swapAbility.behaviors+1] = DeepCopy(behavior)
            end
        end
        if #swapAbility.behaviors == 0 then
            print("AI:: Deceptive Stratagem has no swap behavior")
            return
        end

        ai:ExecuteAbility(token, swapAbility, {{token = scoringInfo.target}},
            {sleep = abilityPause})
        ai:SetupCombatants(token, context.initiativeQueue)

        local participants = {}
        local added = {}
        for _,other in ipairs(dmhub.allTokens) do
            if LiveToken(other) and other.charid ~= token.charid then
                local allied = dmhub.TokensAreFriendly(token, other)
                    and token:Distance(other) <= 12
                local compelled = HasOngoingEffect(other, charmedByHighJudgeEffectId)
                if (allied or compelled) and not added[other.charid] then
                    added[other.charid] = true
                    participants[#participants+1] = other
                end
            end
        end

        for _,participant in ipairs(participants) do
            ExecuteFreeStrike(ai, participant)
        end
    end,
}

--------------------------------------------------------------------------------
-- Secondary prompts.
--------------------------------------------------------------------------------

MonsterAI:RegisterPrompt{
    prompts = {"Devil Notary:Importunity"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local best = nil
        for _,target in ipairs(dmhub.allTokens) do
            if LiveToken(target) and target.charid ~= casterToken.charid
                and casterToken:Distance(target) <= abilityClone:GetRange(casterToken.properties, symbols)
                and abilityClone:TargetPassesFilter(casterToken, target, symbols)
                and not HasOngoingEffect(target, notaryEdgeEffectId) then
                local signature = false
                for _,ability in ipairs(target.properties:GetActivatedAbilities()) do
                    if ability.categorization == "Signature Ability" and ability:CanAfford(target) then
                        signature = true
                        break
                    end
                end
                local score = cond(signature, 2, 0)
                    + target.properties:CurrentHitpoints()
                        / math.max(1, target.properties.max_hitpoints)
                if best == nil or score > best.score then
                    best = {token = target, score = score}
                end
            end
        end
        if best ~= nil then
            return {targets = {{token = best.token}}}
        end
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {
        "Devil Adjudicator:Infernal Injunction",
        "Devil Jurist:Dismissal with Prejudice",
    },
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local targets = FindBestPromptTargets(casterToken, abilityClone, symbols)
        if #targets > 0 then
            return {targets = targets}
        end
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Devil Magistrate:Hide"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        return {targets = {{token = casterToken}}}
    end,
}

--------------------------------------------------------------------------------
-- Optional triggered actions.
--------------------------------------------------------------------------------

MonsterAI:RegisterTrigger{
    id = "Devils: Devilish Charm",
    monsters = devilCharmers,
    abilities = {"Devilish Charm"},
    triggers = {"Devilish Charm"},
    description = "Spend 2 Malice on Devilish Charm whenever an eligible strike targets the devil.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

MonsterAI:RegisterTrigger{
    id = "Devil High Judge: Devilish Suggestion",
    monsters = {"Devil High Judge"},
    abilities = {"Devilish Suggestion"},
    triggers = {"Devilish Suggestion"},
    description = "Spend 2 Malice on Devilish Suggestion whenever an eligible strike targets the high judge.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}
