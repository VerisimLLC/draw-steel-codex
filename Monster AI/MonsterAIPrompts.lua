local mod = dmhub.GetModLoading()

MonsterAI:RegisterPrompt{
    prompts = {"Shift"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)
        local paths = casterToken:CalculatePathfindingArea(range*10, {"shift"})
        local bestLoc = nil
        local bestScore = nil
        for _,info in pairs(paths) do
            local score = math.random()
            if bestScore == nil or score > bestScore then
                bestScore = score
                bestLoc = info.loc
            end
        end

        if bestLoc ~= nil then
            casterToken:MarkMovementArrow(bestLoc, {straightline = true, ignorecreatures = false})
            MonsterAI.Sleep(1)
            casterToken:ClearMovementArrow()

            return {
                targets = { {loc = bestLoc } }
            }
        end
    end,
}

--Granted free strikes arrive through augmented-ability wrappers. A creature
--can have both melee and ranged synthesized choices, so resolution requires a
--concrete ability as well as a target. The shared handler recognizes both the
--standard Free Strike wrapper and generic Invoked Ability wrappers.
local function AIControlledCreature(token)
    return token ~= nil and token.valid and not token.isObject
        and token.properties ~= nil and not token.playerControlled
end

local function LiveAIControlledCreature(token)
    return AIControlledCreature(token) and not token.properties:IsDead()
end

local function IsActiveCombatant(token)
    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden or queue.entries == nil then
        return true
    end

    local initiativeid = InitiativeQueue.GetInitiativeId(token)
    return initiativeid ~= nil and queue.entries[initiativeid] ~= nil
end

local function FreeStrikeCombatants(actor)
    local enemies = {}
    local allies = {}
    for _,token in ipairs(dmhub.allTokens) do
        if token.valid and not token.isObject and token.properties ~= nil
            and not token.properties:IsDead() and IsActiveCombatant(token) then
            if dmhub.TokensAreFriendly(actor, token) then
                allies[#allies+1] = token
            else
                enemies[#enemies+1] = token
            end
        end
    end
    return enemies, allies
end

local function TacticsForFreeStriker(actor)
    local result = {}
    for id,tactic in pairs(MonsterAI.tactics) do
        if MonsterAI.MoveMatchesMonster(actor, tactic) then
            result[id] = tactic
        end
    end
    return result
end

local function CreatureFreeStrikeAbilities(token)
    local result = {}
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization == "Basic Attack" then
            if ability.meleeAndRanged then
                result[#result+1] = ability.meleeVariation
                result[#result+1] = ability.rangedVariation
            else
                result[#result+1] = ability
            end
        end
    end
    return result
end

local function FreeStrikeTargetScore(targetInfo)
    return 1 + (targetInfo.edges or 0)*0.1 + MonsterAI.TargetStaminaBias(targetInfo.token)
end

--onlyTarget (optional) limits the plan to strikes against that one creature.
local function FindBestImmediateFreeStrike(ai, actor, abilities, onlyTarget)
    --Death-triggered grants resolve before the creature is removed, so the
    --caster can already report dead while still being allowed this strike.
    if not AIControlledCreature(actor) then
        return nil
    end

    abilities = abilities or CreatureFreeStrikeAbilities(actor)
    if #abilities == 0 then
        return nil
    end

    -- FindValidTargetsOfStrike uses the AI's cached combatants and tactics.
    -- Temporarily center those caches on the creature receiving the free strike;
    -- it can be an ally other than the monster whose turn is being automated.
    local enemies, allies = FreeStrikeCombatants(actor)
    local priorEnemies = ai:try_get("enemyTokens", {})
    local priorAllies = ai:try_get("allyTokens", {})
    local priorTactics = ai:try_get("activeTactics", {})
    ai.enemyTokens = enemies
    ai.allyTokens = allies
    ai.activeTactics = TacticsForFreeStriker(actor)

    local ok, plan = pcall(function()
        local best = nil
        for _,ability in ipairs(abilities) do
            local scoringAbility = DeepCopy(ability)
            -- Melee Free Strike is treated as charge-capable by the normal turn
            -- planner. A granted free strike is immediate and cannot add movement.
            scoringAbility.name = "Granted Free Strike"
            scoringAbility.disableSquadCoordination = true
            if scoringAbility.keywords ~= nil then
                scoringAbility.keywords.Charge = nil
            end

            local range = scoringAbility:GetRange(actor.properties)
            for _,targetInfo in ipairs(ai:FindValidTargetsOfStrike(
                actor, scoringAbility, actor.loc, range)) do
                local utility = FreeStrikeTargetScore(targetInfo)
                if (onlyTarget == nil or targetInfo.token.charid == onlyTarget.charid)
                    and (best == nil or utility > best.utility) then
                    local activation = DeepCopy(ability)
                    activation.disableSquadCoordination = true
                    best = {
                        ability = activation,
                        target = targetInfo,
                        utility = utility,
                    }
                end
            end
        end
        return best
    end)

    ai.enemyTokens = priorEnemies
    ai.allyTokens = priorAllies
    ai.activeTactics = priorTactics

    if not ok then
        ai:LogDecision("PROMPT ERROR", {
            ability = "Granted Free Strike",
            reason = "target planning failed: " .. tostring(plan),
        })
        return nil
    end
    return plan
end

local freeStrikeSpeech = {
    "Take This!",
    "Die!",
    "I'll take a swing!",
}

local dyingFreeStrikeSpeech = {
    "I'll take you with me!",
    "We die together!",
    "I won't go easily!",
}

local function SpeakBeforeFreeStrike(ai, token)
    local lines = freeStrikeSpeech
    local dying = token.properties:CurrentHitpoints() <= 0
        or token.properties:try_get("_tmp_minionDeathPending") ~= nil
    if dying then
        lines = dyingFreeStrikeSpeech
    end
    ai:Speech(token, lines)
    MonsterAI.Sleep(0.5)
end

MonsterAI:RegisterPrompt{
    prompts = {"Adjacent Ally Makes Free Strike"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local rangeOrigin = abilityClone:GetRangeSource(casterToken)
        local range = abilityClone:GetRange(casterToken.properties)
        local best = nil

        for _,ally in ipairs(dmhub.allTokens) do
            if LiveAIControlledCreature(ally) and IsActiveCombatant(ally)
                and ally.charid ~= casterToken.charid
                and dmhub.TokensAreFriendly(casterToken, ally)
                and MonsterAI.TargetDistance(rangeOrigin, ally) <= range
                and abilityClone:TargetPassesFilter(casterToken, ally, symbols or {})
                and rangeOrigin:GetLineOfSight(
                    ally, casterToken.properties:GetPierceWalls()) > 0 then
                local plan = FindBestImmediateFreeStrike(ai, ally)
                if plan ~= nil and (best == nil or plan.utility > best.utility) then
                    best = {
                        token = ally,
                        utility = plan.utility,
                    }
                end
            end
        end

        if best == nil then
            --An answered prompt with no targets skips the optional grant without
            --opening an action-bar prompt that an AI turn cannot answer.
            return {targets = {}}
        end
        return {targets = {{token = best.token}}}
    end,
}

--The melee free strikes a creature can make (the melee half of a melee-and-
--ranged basic attack counts).
local function CreatureMeleeFreeStrikeAbilities(token)
    local result = {}
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.categorization == "Basic Attack" then
            if ability.meleeAndRanged then
                result[#result+1] = ability.meleeVariation
            elseif ability.name == "Melee Free Strike" or ability:HasKeyword("Melee") then
                result[#result+1] = ability
            end
        end
    end
    return result
end

--"One ally adjacent to the target can make a free strike against them"
--(Swordplay, the Bandit Chief's longsword). The struck hero casts this
--standard ability and so would also own the ally's Melee Free Strike prompt,
--which the AI could never answer. Instead the handler picks the ally, drives
--its free strike against the hero itself, and skips the rest of the chain.
MonsterAI:RegisterPrompt{
    id = "Adjacent Enemy Free Strike Me",
    prompts = {"Adjacent Enemy Free Strike Me"},
    resolvesInvokedAbility = true,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local victim = casterToken
        if victim == nil or not victim.valid or victim.properties == nil
            or victim.properties:IsDead() then
            return {targets = {}}
        end

        local range = abilityClone:GetRange(victim.properties)
        local best = nil
        for _,ally in ipairs(dmhub.allTokens) do
            if LiveAIControlledCreature(ally) and IsActiveCombatant(ally)
                and ally.charid ~= invokerToken.charid
                and dmhub.TokensAreFriendly(invokerToken, ally)
                and MonsterAI.TargetDistance(victim, ally) <= range
                and abilityClone:TargetPassesFilter(victim, ally, symbols or {}) then
                local plan = FindBestImmediateFreeStrike(ai, ally,
                    CreatureMeleeFreeStrikeAbilities(ally), victim)
                if plan ~= nil then
                    --A minion's free strike hits for less, so a full monster goes first.
                    local utility = plan.utility + cond(ally.properties.minion, 0, 0.5)
                    if best == nil or utility > best.utility then
                        best = {token = ally, plan = plan, utility = utility}
                    end
                end
            end
        end

        if best == nil then
            ai:LogDecision("GRANTED FREE STRIKE SKIPPED", {
                ability = abilityClone.name,
                reason = "no ally adjacent to the target can free strike it",
            })
            return {targets = {}}
        end

        --The strike is outside the ally's action economy and cannot charge.
        local activation = best.plan.ability
        activation.actionResourceId = "none"
        if activation.keywords ~= nil then
            activation.keywords.Charge = nil
        end

        --RunWithTokenControl clears the expected prompt; keep the outer move's.
        local expected = ai:try_get("_tmp_expectedPromptTarget")
        local ok, err = ai:RunWithTokenControl(best.token, function()
            SpeakBeforeFreeStrike(ai, best.token)
            ai:ExecuteAbility(best.token, activation, {{token = victim}}, {sleep = 0.5})
        end)
        ai._tmp_expectedPromptTarget = expected
        if not ok then
            ai:LogDecision("PROMPT ERROR", {
                ability = abilityClone.name,
                reason = "granted free strike failed: " .. tostring(err),
            })
        end
        return {targets = {}}
    end,
}

local function HandleFreeStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
    if not AIControlledCreature(casterToken) then
        return nil
    end

    local synthesized = abilityClone:SynthesizeAbilities(casterToken.properties) or {}
    if abilityClone.name ~= "Free Strike" then
        if #synthesized == 0 then
            return nil
        end
        for _,ability in ipairs(synthesized) do
            if ability.categorization ~= "Basic Attack" then
                return nil
            end
        end
    end

    local plan = FindBestImmediateFreeStrike(ai, casterToken, synthesized)
    if plan == nil then
        return {targets = {}}
    end

    SpeakBeforeFreeStrike(ai, casterToken)
    return {
        targets = {{token = plan.target.token}},
        abilityOverride = plan.ability,
    }
end

MonsterAI:RegisterPrompt{
    id = "Generic Free Strike",
    prompts = {"Free Strike", "Invoked Ability"},
    handler = HandleFreeStrikePrompt,
}

local verticalForcedMovementTypes = {
    vertical_push = true,
    vertical_pull = true,
    vertical_slide = true,
}

local function CopyForcedMovementSymbols(symbols, invokerToken, range)
    local result = {}
    for key,value in pairs(symbols or {}) do
        result[key] = value
    end
    result.range = result.range or range
    if result.invoker == nil and invokerToken ~= nil then
        result.invoker = invokerToken.properties
    end
    return result
end

local function ForcedMovementArrowOptions(forcedMovement, range)
    return {
        straightline = true,
        ignorecreatures = false,
        forcedMovementDistance = range,
        slide = forcedMovement == "vertical_slide",
    }
end

local function PreferForcedMovementCandidate(candidateAltitude, candidateScore, bestAltitude, bestScore, higherScoreIsBetter)
    if candidateAltitude ~= nil then
        if bestAltitude == nil or candidateAltitude > bestAltitude then
            return true
        elseif candidateAltitude < bestAltitude then
            return false
        end
    end

    if bestScore == nil then
        return true
    end
    if higherScoreIsBetter then
        return candidateScore > bestScore
    end
    return candidateScore < bestScore
end

local function FindBestPullLocation(invokerToken, casterToken, abilityClone, symbols, range, forcedMovement, preferAltitude)
    ---@type fun(loc: Loc): boolean
    local filterTargetPredicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols)
        or function() return true end
    local shape = dmhub.CalculateShape{
        shape = "RadiusFromCreature",
        token = casterToken,
        radius = range,
        checklos = false,
    }
    local bestLoc = nil
    local bestScore = nil
    local bestAltitude = nil

    for _,testLoc in ipairs(shape.locations) do
        if filterTargetPredicate(testLoc) then
            testLoc = preferAltitude(testLoc)
            local movementInfo = casterToken:MarkMovementArrow(testLoc,
                ForcedMovementArrowOptions(forcedMovement, range))
            if movementInfo ~= nil then
                local path = movementInfo.path
                local dist = path.destination:DistanceInTiles(path.origin)
                if dist > 0 then
                    local collideWithAllies = 0
                    local collideWithEnemies = 0
                    local collideWithObject = false
                    for _,collideToken in ipairs(movementInfo.collideWith or {}) do
                        if collideToken.isObject then
                            collideWithObject = true
                        elseif collideToken:IsFriend(invokerToken) then
                            collideWithAllies = collideWithAllies + 1
                        else
                            collideWithEnemies = collideWithEnemies + 1
                        end
                    end

                    local adjacentAllies = 0
                    for _,other in ipairs(dmhub.allTokens) do
                        if other.valid and other.properties ~= nil
                            and other.charid ~= casterToken.charid
                            and not other.properties:IsDead()
                            and other:IsFriend(invokerToken)
                            and other:Distance(path.destination) <= 1 then
                            adjacentAllies = adjacentAllies + 1
                        end
                    end

                    local fallDistance = path.destination.altitude
                        - game.currentFloor:GetAltitudeAtLoc(path.destination)
                    if fallDistance <= 1 then
                        fallDistance = 0
                    end

                    -- Prefer using as much of the available pull as the board
                    -- permits. Then value hazardous collisions/falls and an end
                    -- position threatened by the puller's allies. Avoid colliding
                    -- with those allies.
                    local score = dist*10
                        + collideWithEnemies*3
                        + cond(collideWithObject, 4, 0)
                        + fallDistance*2
                        + adjacentAllies
                        - collideWithAllies*4
                        - invokerToken:Distance(path.destination)*0.01
                    local altitude = cond(verticalForcedMovementTypes[forcedMovement], testLoc.altitude, nil)
                    if PreferForcedMovementCandidate(altitude, score, bestAltitude, bestScore, true) then
                        bestScore = score
                        bestAltitude = altitude
                        bestLoc = testLoc
                    end
                end
            end
        end
    end

    casterToken:ClearMovementArrow()
    return bestLoc
end

MonsterAI:RegisterPrompt{
    prompts = {"Push!", "Pull!", "Slide!"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)
        local movementSymbols = CopyForcedMovementSymbols(symbols, invokerToken, range)
        local forcedMovement = movementSymbols.forcedmovement or abilityClone:try_get("forcedMovement", "slide")
        local isVertical = verticalForcedMovementTypes[forcedMovement] == true
        local altitudeCalculator = nil
        if isVertical then
            altitudeCalculator = abilityClone:TargetLocMaxElevationChangeFunction(casterToken, movementSymbols)
        end
        local preferAltitude = function(loc)
            if altitudeCalculator == nil then
                return loc
            end
            local _,maxAltitude = altitudeCalculator(loc)
            if maxAltitude == nil then
                return loc
            end
            return loc:WithAltitude(maxAltitude)
        end

        if forcedMovement == "pull" or forcedMovement == "vertical_pull" then
            local bestLoc = FindBestPullLocation(invokerToken, casterToken, abilityClone,
                movementSymbols, range, forcedMovement, preferAltitude)
            if bestLoc ~= nil then
                casterToken:MarkMovementArrow(bestLoc, ForcedMovementArrowOptions(forcedMovement, range))
                MonsterAI.Sleep(1)
                casterToken:ClearMovementArrow()
                return {
                    targets = {{loc = bestLoc}},
                }
            end
            return nil
        end

        local filterTargetPredicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, movementSymbols) or function(loc) return true end


        --TODO: implement custom target shape for ai
        --local customLocs = abilityClone:CustomTargetShape(casterToken, range, symbols, {})


        local loc = casterToken.loc
        for i=1,range do
            loc = loc.north.west
        end

        local possibleLocs = {}
        if isVertical and filterTargetPredicate(casterToken.loc) then
            possibleLocs[#possibleLocs+1] = casterToken.loc
        end
        for i=1,range*2 do
            if filterTargetPredicate(loc) then
                possibleLocs[#possibleLocs+1] = loc
            end
            loc = loc.east
        end

        for i=1,range*2 do
            if filterTargetPredicate(loc) then
                possibleLocs[#possibleLocs+1] = loc
            end
            loc = loc.south
        end

        for i=1,range*2 do
            if filterTargetPredicate(loc) then
                possibleLocs[#possibleLocs+1] = loc
            end
            loc = loc.west
        end

        for i=1,range*2 do
            if filterTargetPredicate(loc) then
                possibleLocs[#possibleLocs+1] = loc
            end
            loc = loc.north
        end

        local bestLoc = nil
        local bestScore = nil
        local bestAltitude = nil
        for _,testLoc in ipairs(possibleLocs) do
            testLoc = preferAltitude(testLoc)
            local movementInfo = casterToken:MarkMovementArrow(testLoc,
                ForcedMovementArrowOptions(forcedMovement, range))
            if movementInfo ~= nil then
                local path = movementInfo.path
                local dist = path.destination:DistanceInTiles(path.origin)

                local collideWith = movementInfo.collideWith

                local fallDistance = path.destination.altitude - game.currentFloor:GetAltitudeAtLoc(path.destination)
                if fallDistance <= 1 then
                    --only consider a decent size fall.
                    fallDistance = 0
                end

                local collideWithAllies = 0
                local collideWithEnemies = 0
                local collideWithObjects = collideWith ~= nil and #collideWith == 0
                for _,collideToken in ipairs(collideWith or {}) do
                    if collideToken.isObject then
                        collideWithObjects = true
                    elseif collideToken:IsFriend(invokerToken) then
                        collideWithAllies = collideWithAllies + 1
                    else
                        collideWithEnemies = collideWithEnemies + 1
                    end
                end

                --lower score is better.
                local score = dist + 2*collideWithAllies - 2*collideWithEnemies - 2*fallDistance
                if collideWithObjects then
                    score = score - 4
                end

                local altitude = cond(isVertical, testLoc.altitude, nil)
                if PreferForcedMovementCandidate(altitude, score, bestAltitude, bestScore, false) then
                    bestScore = score
                    bestAltitude = altitude
                    bestLoc = testLoc
                end
            end
        end

        if bestLoc ~= nil then
            casterToken:MarkMovementArrow(bestLoc, ForcedMovementArrowOptions(forcedMovement, range))
            MonsterAI.Sleep(1)
            casterToken:ClearMovementArrow()

            return {
                targets = { {loc = bestLoc } }
            }
        end
    end,
}

--Wallmaster: the per-wall-square victim picks for Wall Slam and Dead End. The
--invoker/caster is the WALL SQUARE object token (targeting is re-centered on
--it); the wallmaster itself is ai.token. Registered unqualified because object
--tokens have no monster_type to qualify with.
MonsterAI:RegisterPrompt{
    prompts = {"Wall Slam Topple", "Dead End Victim"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local monsterToken = ai.token
        if monsterToken == nil or not monsterToken.valid then
            return nil
        end

        local range = abilityClone:GetRange(casterToken.properties)

        local best = nil
        local bestFrac = nil
        for _,tok in ipairs(dmhub.allTokens) do
            if tok.valid and (not tok:IsFriend(monsterToken)) and (not tok.properties:IsDead()) and MonsterAI.TargetDistance(casterToken, tok) <= range then
                local frac = tok.properties:CurrentHitpoints() / math.max(1, tok.properties.max_hitpoints)
                if bestFrac == nil or frac < bestFrac then
                    bestFrac = frac
                    best = tok
                end
            end
        end

        if best == nil then
            --no enemy in reach; fall back to manual prompting.
            return nil
        end

        return {
            targets = { {token = best} }
        }
    end,
}

--Wallmaster: Dead End's wall-shift destination. The pick ability carries the
--whitelist of vacated squares in _tmp_restrictLocs (ordered from the push's
--start square toward the creature's final position); take the last one so the
--wall stays pressed up against the pushed creature.
MonsterAI:RegisterPrompt{
    prompts = {"Wall Shift"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local locs = abilityClone:try_get("_tmp_restrictLocs")
        if locs == nil or #locs == 0 then
            return nil
        end

        return {
            targets = { {loc = locs[#locs]} }
        }
    end,
}

--Hurl Grabbed Creature (Ogre Goon "People Bowling", AbilityRelocateAura.lua):
--two picks. The creature pick carries its candidates in _tmp_hurlCandidates;
--throw the first (the goon normally grabs only one creature anyway). The
--landing pick carries the equally-near free squares in _tmp_restrictLocs;
--any of them satisfies the rule, so take the first.
MonsterAI:RegisterPrompt{
    prompts = {"Hurl Grabbed Creature"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local candidates = abilityClone:try_get("_tmp_hurlCandidates")
        if candidates == nil or #candidates == 0 then
            return nil
        end
        return {
            targets = { {token = candidates[1]} }
        }
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Hurl Landing Square"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local locs = abilityClone:try_get("_tmp_restrictLocs")
        if locs == nil or #locs == 0 then
            return nil
        end
        return {
            targets = { {loc = locs[1]} }
        }
    end,
}

MonsterAI:RegisterPrompt{
    prompts = {"Decrepit Skeleton:Invoked Ability"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        --For Bone Bow's per-minion invoke, casterToken is the squad member making
        --this follow-up choice; invokerToken is the parent effect's source.
        local actingToken = casterToken
        local range = abilityClone:GetRange(casterToken.properties)

        local forbiddenTokens = {}
        for _,p in ipairs(symbols.targetPairs or {}) do
            if p.a == actingToken.charid then
                forbiddenTokens[p.b] = true
            end
        end

        local possibleTokens = {}
        for _,tok in ipairs(dmhub.allTokens) do
            if (not forbiddenTokens[tok.charid])
                and (not tok:IsFriend(actingToken))
                and MonsterAI.TargetDistance(actingToken, tok) <= range
                and abilityClone:TargetPassesFilter(actingToken, tok, symbols or {}) then
                possibleTokens[#possibleTokens+1] = tok
            end
        end

        if #possibleTokens == 0 then
            return "skip"
        end

        return {
            targets = { {token = possibleTokens[math.random(#possibleTokens)] } }
        }
    end,
}

--------------------------------------------------------------------------------
-- Ending effects: End Effect and other "choose an effect to end" purges.
--------------------------------------------------------------------------------

--How much a condition hurts the creature carrying it, from 0 (harmless) to 5,
--by lower-case condition name. A harmful condition missing from this table
--counts as defaultHarmSeverity.
MonsterAI.conditionSeverity = {
    dazed = 5,
    restrained = 5,
    stoned = 5,
    frightened = 4,
    weakened = 4,
    ["on fire"] = 4,
    slowed = 3,
    bleeding = 3,
    taunted = 3,
    grabbed = 3,
    dazzled = 3,
    prone = 1,
}
MonsterAI.defaultHarmSeverity = 2
--End Effect is only worth its Stamina for a condition at least this bad...
MonsterAI.endEffectMinimumSeverity = 3
--...and only while the creature keeps this share of its Stamina (and at
--least the cost again) after paying.
MonsterAI.endEffectStaminaReserve = 0.15

local function ConditionHarm(conditionid)
    local condition = (dmhub.GetTable(CharacterCondition.tableName) or {})[conditionid]
    if condition == nil then
        return MonsterAI.defaultHarmSeverity
    end
    if condition:try_get("buffType", "debuff") == "buff" then
        return 0
    end
    return MonsterAI.conditionSeverity[string.lower(condition.name or "")] or MonsterAI.defaultHarmSeverity
end

--How much ending this purge item helps the side choosing it: the harm taken
--off a friend, or the benefit stripped from an enemy. Items come from
--ActivatedAbilityPurgeEffectsBehavior:CollectPurgeItems.
--- @param item table
--- @param targetToken CharacterToken
--- @param casterToken CharacterToken
--- @return number
function MonsterAI.PurgeItemValue(item, targetToken, casterToken)
    local harm
    if item.type == "condition" or item.type == "conditionOnly" then
        harm = ConditionHarm(item.conditionId)
    else
        local effectInfo = (dmhub.GetTable("characterOngoingEffects") or {})[item.effectId]
        if effectInfo == nil then
            harm = MonsterAI.defaultHarmSeverity
        elseif effectInfo:try_get("condition", "none") ~= "none" then
            harm = ConditionHarm(effectInfo.condition)
        elseif effectInfo:try_get("buffType", "debuff") == "buff" then
            harm = -MonsterAI.defaultHarmSeverity
        else
            harm = MonsterAI.defaultHarmSeverity
        end
    end
    if targetToken.charid == casterToken.charid or targetToken:IsFriend(casterToken) then
        return harm
    end
    return -harm
end

--True when the AI makes this creature's choices right now: it is driving
--the token, or it plays the creature while the AI runs.
local function AIChoosesFor(token)
    if token == nil or not token.valid or token.properties == nil then
        return false
    end
    return creature.IsTokenAIControlled(token.charid) or MonsterAI.RollsForCreature(token.properties)
end

--Answers the purge selection dialog for an AI-driven caster: the worst
--effects on friends (the best on enemies), one per creature for a "one"
--purge, never more than the purge allows, and nothing of no value. With
--nothing worth ending it passes, which also skips any Stamina cost.
ActivatedAbilityPurgeEffectsBehavior.aiChooser = function(behavior, targetDataList, ability, casterToken, maxSelections)
    if not AIChoosesFor(casterToken) then
        return nil
    end
    local candidates = {}
    for _,data in ipairs(targetDataList) do
        local perTarget = {}
        for _,item in ipairs(data.items or {}) do
            local value = MonsterAI.PurgeItemValue(item, data.token, casterToken)
            if value > 0 then
                perTarget[#perTarget+1] = {data = data, item = item, value = value}
            end
        end
        table.sort(perTarget, function(a, b) return a.value > b.value end)
        if behavior.purgeType == "one" then
            table.resize_array(perTarget, 1)
        end
        for _,entry in ipairs(perTarget) do
            candidates[#candidates+1] = entry
        end
    end
    table.sort(candidates, function(a, b) return a.value > b.value end)
    if maxSelections ~= nil then
        table.resize_array(candidates, math.max(0, maxSelections))
    end

    local selections = {}
    local chosen = {}
    for _,data in ipairs(targetDataList) do
        selections[data.token.id] = {}
    end
    for _,entry in ipairs(candidates) do
        local list = selections[entry.data.token.id]
        list[#list+1] = entry.item
        chosen[#chosen+1] = string.format("%s (%s)", tostring(entry.item.displayName), MonsterAI.TokenLogName(entry.data.token))
    end

    print(string.format("AI:: PURGE CHOSEN | ability=%q | caster=%q | chosen=%q",
        tostring(ability ~= nil and ability.name or "?"), MonsterAI.TokenLogName(casterToken),
        #chosen > 0 and table.concat(chosen, ", ") or "nothing worth ending"))
    if #chosen == 0 then
        return false
    end
    return true, selections
end

--The purge behind an End Effect trigger and its Stamina cost, or nil when the
--trigger is not shaped like one.
local function EndEffectPurge(token, triggerInfo)
    local fallback = nil
    for _,entry in ipairs(token.properties:GetTriggeredAbilities() or {}) do
        local triggered = entry.ability
        if triggered ~= nil then
            local matches = triggered:try_get("guid") == triggerInfo.abilityGuid
            if matches or (fallback == nil and triggered.name == triggerInfo.abilityName) then
                for _,behavior in ipairs(triggered:try_get("behaviors", {})) do
                    if behavior.typeName == "ActivatedAbilityPurgeEffectsBehavior" then
                        local found = {
                            behavior = behavior,
                            cost = tonumber(behavior:EvalDamageToSelf(token.properties)) or 0,
                        }
                        if matches then
                            return found
                        end
                        fallback = found
                    end
                end
            end
        end
    end
    return fallback
end

--Whether a monster should take its End Effect: only to end something nasty
--(endEffectMinimumSeverity or worse), and only when it can afford the
--Stamina with endEffectStaminaReserve to spare. Accepting it lets the purge
--chooser above pick the worst effect.
--- @param token CharacterToken
--- @param triggerInfo ActiveTrigger
--- @return nil|table decision {activate = true}, {dismiss = true}, or nil for the Director
--- @return string reason
function MonsterAI.EndEffectDecision(token, triggerInfo)
    local purge = EndEffectPurge(token, triggerInfo)
    if purge == nil then
        return nil, "no purge behind this End Effect; left to the Director"
    end
    local data = purge.behavior:CollectPurgeItems(token, nil)
    local worst = 0
    for _,item in ipairs(data ~= nil and data.items or {}) do
        worst = math.max(worst, MonsterAI.PurgeItemValue(item, token, token))
    end
    if worst < MonsterAI.endEffectMinimumSeverity then
        return {dismiss = true}, string.format("worst effect is only severity %d", worst)
    end
    local stamina = token.properties:CurrentHitpoints()
    local reserve = math.max(purge.cost, token.properties:MaxHitpoints()*MonsterAI.endEffectStaminaReserve)
    if stamina - purge.cost < reserve then
        return {dismiss = true}, string.format("%d Stamina cannot spare %d", stamina, purge.cost)
    end
    return {activate = true}, string.format("ending severity %d for %d Stamina", worst, purge.cost)
end

MonsterAI:RegisterTrigger{
    id = "End Effect",
    abilities = {"End Effect"},
    description = "Take End Effect's Stamina cost to end the nastiest save-ends effect, when it is bad enough and the monster can afford it.",
    handler = function(ai, token, triggerInfo)
        local decision, reason = MonsterAI.EndEffectDecision(token, triggerInfo)
        local result = "Director decision"
        if decision ~= nil then
            result = cond(decision.activate, "activate", "dismiss")
        end
        ai:LogDecision("END EFFECT", {
            ability = triggerInfo.abilityName,
            result = result,
            reason = reason,
        })
        return decision
    end,
}
