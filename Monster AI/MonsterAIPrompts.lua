local mod = dmhub.GetModLoading()

MonsterAI:RegisterPrompt{
    prompts = {"Shift"},
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local planned = MonsterAI.plannedShiftDestinations[casterToken.charid]
        if planned ~= nil then
            MonsterAI.plannedShiftDestinations[casterToken.charid] = nil
            --Already standing on its square: the shift moves nowhere.
            if ai:MovementTokenIsAtLoc(casterToken, planned) then
                return {targets = {}}
            end
            return {targets = {{loc = planned}}}
        end

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
--allowedTargets (optional, charid -> true) limits it to the creatures a
--prompt_inherit invoke offers: the targets of the ability granting the strike.
local function FindBestImmediateFreeStrike(ai, actor, abilities, onlyTarget, allowedTargets)
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
                    and (allowedTargets == nil or allowedTargets[targetInfo.token.charid])
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

    --A grant that inherits its targets ("a free strike against one of the
    --targets") sets allowedtargets; without this the ally could strike anyone.
    local allowedTargets = symbols ~= nil and symbols.allowedtargets or nil
    local plan = FindBestImmediateFreeStrike(ai, casterToken, synthesized, nil, allowedTargets)
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

--A free strike a monster must aim at one creature (To the Death!'s target
--striking the hero, SASGFH6V). The invoke writes that creature into each
--synthesized strike's target filter, which the planner honors. With no strike
--that reaches it, nil lets HandlePrompt skip the strike in directorless play;
--an empty target list would still cast the chooser and prompt a person.
MonsterAI:RegisterPrompt{
    id = "Generic Free Strike Against Specific Target",
    prompts = {"Free Strike Against Specific Target"},
    --The monster makes this strike itself (To the Death! has it strike the hero),
    --so the AI answers it even though a hero's ability raised the prompt.
    answersForCaster = true,
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local result = HandleFreeStrikePrompt(ai, invokerToken, casterToken, abilityClone, symbols, options)
        if result ~= nil and result.abilityOverride == nil then
            return nil
        end
        return result
    end,
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

--Options for the forced-move preview arrow. Pass the mover and the ability so the
--preview takes the same path the cast will (AbilityRelocateCreature): through
--creatures, straight up, and the mover's rebounds all change where it lands and
--what it hits.
local function ForcedMovementArrowOptions(forcedMovement, range, moverToken, abilityClone)
    local options = {
        straightline = true,
        ignorecreatures = false,
        forcedMovementDistance = range,
        slide = forcedMovement == "vertical_slide",
    }
    if abilityClone ~= nil then
        options.ignorecreatures = abilityClone.targetType == "line"
            or abilityClone:try_get("forcedMovementThroughCreatures", false) == true
        if abilityClone:try_get("forcedMovementStraightUp", false) then
            options.slide = true
        end
    end
    if moverToken ~= nil and moverToken.properties ~= nil and not moverToken.isObject then
        local pushOptions = moverToken.properties:GetForcedPushOptions()
        options.rebound = pushOptions.rebound
        options.maxBounces = pushOptions.maxBounces
    end
    return options
end

--A vertical push/pull target carries an absolute altitude (the ability's own
--calculator), and stays that way as the prompt's answer. Only the arrow probes
--need it as height above the destination ground, which the engine expects.
--moverToken is the creature being moved (the one the arrow is drawn for).
local function ArrowLoc(moverToken, forcedMovement, loc)
    if verticalForcedMovementTypes[forcedMovement] then
        return ActivatedAbility.VerticalForcedMovementEngineLoc(loc, moverToken.loc.altitude)
    end
    return loc
end

--Damage one creature takes from one collision, per the Collision global rule:
--1 per square of movement left, +2 against an object (plus the pusher's bonus on
--a push), less its Forced Movement Damage Reduction.
local function ForcedCollisionDamage(invokerToken, token, speed, withobject, isPush)
    local props = token.properties
    if props:CalculateNamedCustomAttribute("No Damage From Forced Movement") >= 1 then
        return 0
    end
    if withobject and props:CalculateNamedCustomAttribute("NoDamageFromForcedMovementWithObjects") >= 1 then
        return 0
    end
    local damage = speed
    if withobject then
        damage = damage + 2
        if isPush and invokerToken ~= nil and invokerToken.properties ~= nil then
            damage = damage + invokerToken.properties:CalculateNamedCustomAttribute("BonusPushDamageIntoObjects")
        end
    end
    return damage - props:CalculateNamedCustomAttribute("Forced Movement Damage Reduction")
end

--True when everything in collideWith is an object that runs its own collision
--behavior ("No Collision Damage"), so nobody takes collision damage. A wall
--(empty list) or a mixed pile still deals it.
local function CollisionDamageSuppressed(collideWith)
    if #collideWith == 0 then
        return false
    end
    for _,tok in ipairs(collideWith) do
        if not TargetableObject.TokenSuppressesCollisionDamage(tok) then
            return false
        end
    end
    return true
end

local function CollisionIsWithObject(collideWith)
    if #collideWith == 0 then
        return true
    end
    for _,tok in ipairs(collideWith) do
        if tok.isObject then
            return true
        end
    end
    return false
end

--The damage a forced move would deal, read from its preview arrow (movementInfo,
--aimed at targetLoc) the way the cast reads it (AbilityRelocateCreature): the
--collision at the end, creatures passed through, rebound bounces, and a fall.
--Returns net damage (to the invoker's enemies, minus to its friends) and the total.
--The AI picks forced moves by net damage first, so it shoves heroes into walls,
--into each other and off ledges, and avoids slamming them into its own allies.
local function PredictForcedMoveDamage(invokerToken, moverToken, abilityClone, targetLoc, movementInfo, range, forcedMovement)
    local path = movementInfo.path
    local isPush = forcedMovement == "push"
    local net = 0
    local total = 0
    local function Deal(token, amount)
        if amount <= 0 or token == nil or token.isObject or token.properties == nil or token.properties:IsDead() then
            return
        end
        total = total + amount
        if token:IsFriend(invokerToken) then
            net = net - amount
        else
            net = net + amount
        end
    end

    --The collision at the end of the move: the force left when it stopped.
    local requestDist = math.min(targetLoc:DistanceInTiles(path.origin), range)
    if path.hasCollision and requestDist < range then
        requestDist = range
    end
    local speed = requestDist - path.freeMovementSteps
    local hasCollision = speed > 0
    local collisionForce = path.collisionForce
    if collisionForce ~= nil then
        if collisionForce >= 0 then
            hasCollision = true
            speed = collisionForce
        elseif not path.hasCollision then
            hasCollision = false
        end
    end

    local collideWith = {}
    local hadCollideTokens = false
    for _,tok in ipairs(movementInfo.collideWith or {}) do
        hadCollideTokens = true
        if tok.properties == nil or tok.properties:CalculateNamedCustomAttribute("Passthrough") == 0 then
            collideWith[#collideWith+1] = tok
        end
    end
    if hadCollideTokens and #collideWith == 0 then
        --only creatures it passes through were in the way.
        hasCollision = false
    end

    if hasCollision and speed >= 0 and not CollisionDamageSuppressed(collideWith) then
        Deal(moverToken, ForcedCollisionDamage(invokerToken, moverToken, speed, CollisionIsWithObject(collideWith), isPush))
        for _,tok in ipairs(collideWith) do
            if not tok.isObject then
                Deal(tok, ForcedCollisionDamage(invokerToken, tok, speed, moverToken.isObject, isPush))
            end
        end
    end

    --Creatures passed through each take 1, and so does the mover.
    if abilityClone:try_get("forcedMovementThroughCreatures", false) and path.steps ~= nil then
        local hit = {}
        for _,step in ipairs(path.steps) do
            for _,tok in ipairs(game.GetTokensAtLoc(step) or {}) do
                if tok.charid ~= moverToken.charid and not hit[tok.charid] then
                    hit[tok.charid] = true
                    if not TargetableObject.TokenSuppressesCollisionDamage(tok) then
                        Deal(tok, ForcedCollisionDamage(invokerToken, tok, 1, false, isPush))
                        Deal(moverToken, ForcedCollisionDamage(invokerToken, moverToken, 1, false, isPush))
                    end
                end
            end
        end
    end

    --Each rebound bounce is another collision.
    for _,bounce in ipairs(movementInfo.bounceCollisions or {}) do
        local bounceWith = bounce.collideWith or {}
        if not CollisionDamageSuppressed(bounceWith) then
            local withobject = CollisionIsWithObject(bounceWith)
            Deal(moverToken, ForcedCollisionDamage(invokerToken, moverToken, bounce.speed, withobject, isPush))
            for _,tok in ipairs(bounceWith) do
                if not tok.isObject then
                    Deal(tok, ForcedCollisionDamage(invokerToken, tok, bounce.speed, withobject, isPush))
                end
            end
        end
    end

    --A fall at the end (pushed off a ledge, or lifted and dropped).
    local fallDist = path.fallDistance or 0
    if fallDist > 0 and not moverToken.isObject and not moverToken.properties:CanFly() then
        Deal(moverToken, moverToken.properties:PredictedFallDamage(fallDist, path.landsInWater))
    end

    return net, total
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

--Most net damage wins; equal damage falls back to altitude, then the caller's
--positioning score. best is nil or {damage, altitude, score}.
local function BetterForcedMoveCandidate(damage, altitude, score, best, higherScoreIsBetter)
    if best == nil then
        return true
    end
    if damage ~= best.damage then
        return damage > best.damage
    end
    return PreferForcedMovementCandidate(altitude, score, best.altitude, best.score, higherScoreIsBetter)
end

--The standard "Forced Movement: push" (or pull/slide) ability as the Push!
--prompt would cast it, kept per type and distance until the tables change.
local g_forcedMoveAbilityCache = {}
local function ForcedMoveAbility(invokerToken, forcedMovement, distance)
    local key = string.format("%s:%d:%s", forcedMovement, distance, tostring(dmhub.tablesUpdateId))
    local ability = g_forcedMoveAbilityCache[key]
    if ability == nil then
        local standard = MCDMUtils.GetStandardAbility("Forced Movement: " .. forcedMovement)
        if standard == nil then
            return nil
        end
        ability = DeepCopy(standard)
        MCDMUtils.DeepReplace(ability, "<<range>>", string.format("%d", distance))
        ability.name = string.gsub(forcedMovement, "^%l", string.upper) .. "!"
        ability.range = distance
        g_forcedMoveAbilityCache[key] = ability
    end
    ability.invoker = invokerToken.properties
    return ability
end

--- The most net damage (see PredictForcedMoveDamage) a horizontal push, pull or
--- slide of moverToken by `distance` squares could deal, with invokerToken
--- standing at originLoc (where it stands now when nil). For planning: which
--- target to knock back, and from which square. Returns damage, landing loc;
--- 0 when no line moves the target at all.
--- @param invokerToken CharacterToken
--- @param moverToken CharacterToken
--- @param forcedMovement string "push", "pull" or "slide"
--- @param distance number
--- @param originLoc? Loc
--- @return number damage, Loc|nil loc
function MonsterAI.BestForcedMoveDamage(invokerToken, moverToken, forcedMovement, distance, originLoc)
    if distance <= 0 or moverToken.properties == nil then
        return 0, nil
    end
    local abilityClone = ForcedMoveAbility(invokerToken, forcedMovement, distance)
    if abilityClone == nil then
        return 0, nil
    end
    local symbols = {
        invoker = invokerToken.properties,
        forcedmovement = forcedMovement,
        forcedMovementOrigin = originLoc or invokerToken.loc,
        forcedMovementOriginTokenId = invokerToken.charid,
    }
    ---@type fun(loc: Loc): boolean
    local filter = abilityClone:TargetLocPassesFilterPredicate(moverToken, symbols)
        or function() return true end

    --aim at the ring `distance` away (every square within it for a pull, which
    --stops short of the puller); the arrow stops where the move really ends.
    local origin = moverToken.loc
    local best = nil
    local bestLoc = nil
    for dx = -distance,distance do
        for dy = -distance,distance do
            local onRing = math.max(math.abs(dx), math.abs(dy)) == distance
            if (dx ~= 0 or dy ~= 0) and (onRing or forcedMovement == "pull") then
                local testLoc = origin:dir(dx, dy):WithAltitude(0)
                if filter(testLoc) then
                    local movementInfo = moverToken:MarkMovementArrow(testLoc,
                        ForcedMovementArrowOptions(forcedMovement, distance, moverToken, abilityClone))
                    --a bump against something already adjacent still counts.
                    if movementInfo ~= nil and (movementInfo.path.destination:DistanceInTiles(origin) > 0
                        or movementInfo.path.hasCollision) then
                        local damage = PredictForcedMoveDamage(invokerToken, moverToken, abilityClone,
                            testLoc, movementInfo, distance, forcedMovement)
                        if best == nil or damage > best then
                            best = damage
                            bestLoc = testLoc
                        end
                    end
                end
            end
        end
    end
    moverToken:ClearMovementArrow()
    return best or 0, bestLoc
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
    local best = nil

    for _,testLoc in ipairs(shape.locations) do
        if filterTargetPredicate(testLoc) then
            testLoc = preferAltitude(testLoc)
            local movementInfo = casterToken:MarkMovementArrow(ArrowLoc(casterToken, forcedMovement, testLoc),
                ForcedMovementArrowOptions(forcedMovement, range, casterToken, abilityClone))
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

                    -- Damage decides first (PredictForcedMoveDamage). Among equal
                    -- damage, prefer using as much of the pull as the board
                    -- permits, then an end position threatened by the puller's
                    -- allies. Avoid colliding with those allies.
                    local damage = PredictForcedMoveDamage(invokerToken, casterToken, abilityClone,
                        testLoc, movementInfo, range, forcedMovement)
                    local score = dist*10
                        + collideWithEnemies*3
                        + cond(collideWithObject, 4, 0)
                        + fallDistance*2
                        + adjacentAllies
                        - collideWithAllies*4
                        - invokerToken:Distance(path.destination)*0.01
                    local altitude = cond(verticalForcedMovementTypes[forcedMovement], testLoc.altitude, nil)
                    if BetterForcedMoveCandidate(damage, altitude, score, best, true) then
                        best = {damage = damage, altitude = altitude, score = score, loc = testLoc}
                    end
                end
            end
        end
    end

    casterToken:ClearMovementArrow()
    if best == nil then
        return nil, nil
    end
    return best.loc, best.damage
end

--Zone directive "Force Into": when an enemy can be moved so it ends inside a
--Force Into zone, that landing beats every other consideration. Tested
--against the real forced-movement path, so walls and creatures that would
--stop it short are respected. Deeper landings (more of the zone around them)
--are preferred, since they are harder to step out of. nil when none works.
local function FindForceIntoLocation(invokerToken, casterToken, abilityClone, symbols, range, forcedMovement)
    if verticalForcedMovementTypes[forcedMovement] or casterToken:IsFriend(invokerToken)
        or not MonsterAI.AnyDirectiveZones("forceInto", invokerToken)
        or MonsterAI.InDirectiveZone("forceInto", casterToken, nil, invokerToken) then
        return nil
    end
    ---@type fun(loc: Loc): boolean
    local filterTargetPredicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols)
        or function() return true end

    local bestLoc = nil
    local bestScore = nil
    local origin = casterToken.loc
    for dx = -range,range do
        for dy = -range,range do
            local testLoc = origin:dir(dx, dy)
            --cheap zone test first; the arrow is the expensive part.
            if (dx ~= 0 or dy ~= 0) and MonsterAI.InDirectiveZone("forceInto", casterToken, testLoc, invokerToken)
                and filterTargetPredicate(testLoc) then
                --aim on the ground: a target altitude means "this high above it".
                testLoc = testLoc:WithAltitude(0)
                local movementInfo = casterToken:MarkMovementArrow(testLoc,
                    ForcedMovementArrowOptions(forcedMovement, range))
                local destination = movementInfo ~= nil and movementInfo.path.destination or nil
                if destination ~= nil and destination:DistanceInTiles(origin) > 0
                    and MonsterAI.InDirectiveZone("forceInto", casterToken, destination, invokerToken) then
                    local depth = 0
                    for ny = -1,1 do
                        for nx = -1,1 do
                            if MonsterAI.InDirectiveZone("forceInto", casterToken, destination:dir(nx, ny), invokerToken) then
                                depth = depth + 1
                            end
                        end
                    end
                    local collideWithAllies = 0
                    for _,collideToken in ipairs(movementInfo.collideWith or {}) do
                        if not collideToken.isObject and collideToken:IsFriend(invokerToken) then
                            collideWithAllies = collideWithAllies + 1
                        end
                    end
                    local score = depth - collideWithAllies*4
                    if bestScore == nil or score > bestScore then
                        bestScore = score
                        bestLoc = testLoc
                    end
                end
            end
        end
    end

    casterToken:ClearMovementArrow()
    return bestLoc
end

--Answer a forced-move prompt with loc, showing the AI's arrow for a moment first.
local function AnswerForcedMoveLoc(moverToken, loc, forcedMovement, range, abilityClone)
    moverToken:MarkMovementArrow(ArrowLoc(moverToken, forcedMovement, loc),
        ForcedMovementArrowOptions(forcedMovement, range, moverToken, abilityClone))
    MonsterAI.Sleep(1)
    moverToken:ClearMovementArrow()
    return {
        targets = {{loc = loc}},
    }
end

--The undead object throws (Paranormal Fling, Paranormal Activity) aim at the
--nearest enemy within 3 squares of the object.
local objectMissileReach = 3

--A slid object is a missile (Paranormal Fling, AME33M5U): aim it to hit an enemy
--within reach, nearest first. The victim scoring below would rate a wall hit higher.
--Returns the square to slide it at, or nil when no line hits an enemy without also
--hitting one of friendToken's allies. The second result is true when some enemy is
--in reach at all. The undead Malice choice uses this too, so it only pays for
--objects that will hit.
---@param friendToken CharacterToken the side doing the throwing
---@param candidateEnemies CharacterToken[]
---@param objectToken CharacterToken
---@param range number
---@param filterTargetPredicate nil|fun(loc: any): boolean
---@return any|nil loc
---@return boolean enemyInReach
function MonsterAI.FindObjectMissileHit(friendToken, candidateEnemies, objectToken, range, filterTargetPredicate)
    local enemies = {}
    for _,enemy in ipairs(candidateEnemies or {}) do
        if MonsterAI.TokenIsLiveCombatant(enemy) and not enemy.isObject
            and enemy:Distance(objectToken.loc) <= objectMissileReach then
            enemies[#enemies+1] = enemy
        end
    end
    if #enemies == 0 then
        return nil, false
    end
    table.sort(enemies, function(a, b)
        return a:Distance(objectToken.loc) < b:Distance(objectToken.loc)
    end)
    local enemyRank = {}
    for i,enemy in ipairs(enemies) do
        enemyRank[enemy.charid] = i
    end

    --Aim at every square of each enemy and its border; the arrow stops at the
    --first creature in the way, so each line is scored by what it actually hits.
    local candidates = {}
    local seen = {}
    for _,enemy in ipairs(enemies) do
        for _,occupied in ipairs(enemy.locsOccupying) do
            for dx = -1,1 do
                for dy = -1,1 do
                    local loc = occupied:dir(dx, dy):WithAltitude(0)
                    if not seen[loc.str] and (filterTargetPredicate == nil or filterTargetPredicate(loc)) then
                        seen[loc.str] = true
                        candidates[#candidates+1] = loc
                    end
                end
            end
        end
    end

    local bestLoc = nil
    local bestRank = nil
    for _,testLoc in ipairs(candidates) do
        local movementInfo = objectToken:MarkMovementArrow(testLoc, ForcedMovementArrowOptions("slide", range))
        if movementInfo ~= nil then
            local destination = movementInfo.path.destination
            if destination:DistanceInTiles(movementInfo.path.origin) > 0 then
                local hitAlly = false
                local hitRank = nil
                for _,collideToken in ipairs(movementInfo.collideWith or {}) do
                    local rank = enemyRank[collideToken.charid]
                    if rank ~= nil then
                        hitRank = math.min(hitRank or rank, rank)
                    elseif not collideToken.isObject and collideToken:IsFriend(friendToken) then
                        hitAlly = true
                    end
                end
                --Never throw into an ally, and never settle for a line that hits no one
                --(the object would only land beside the enemy). The nearest enemy first.
                if not hitAlly and hitRank ~= nil then
                    if bestRank == nil or hitRank < bestRank then
                        bestRank = hitRank
                        bestLoc = testLoc
                    end
                end
            end
        end
    end

    objectToken:ClearMovementArrow()
    return bestLoc, true
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
        --The engine reads a forced-move target's altitude as height above the
        --ground there, so a sideways move must aim at altitude 0. Candidate
        --squares are built from the target's own loc, which carries its
        --absolute altitude: on raised ground that turned a push into a lift
        --and a fall.
        local preferAltitude = function(loc)
            if not isVertical then
                return loc:WithAltitude(0)
            end
            if altitudeCalculator == nil then
                return loc
            end
            local _,maxAltitude = altitudeCalculator(loc)
            if maxAltitude == nil then
                return loc
            end
            return loc:WithAltitude(maxAltitude)
        end

        local filterTargetPredicate = abilityClone:TargetLocPassesFilterPredicate(casterToken, movementSymbols) or function(loc) return true end

        --Before Force Into: that zone is for creatures, and would take a thrown object off its enemy.
        --With an enemy in reach but no clean hit, leave the object where it is: the
        --victim scoring below once sent it into a wall or an ally instead.
        if forcedMovement == "slide" and casterToken.isObject then
            local missileLoc, enemyInReach = MonsterAI.FindObjectMissileHit(ai.token, ai.enemyTokens,
                casterToken, range, filterTargetPredicate)
            if missileLoc ~= nil then
                return AnswerForcedMoveLoc(casterToken, missileLoc, forcedMovement, range)
            end
            if enemyInReach then
                return {decline = true, reason = "no line hits an enemy without hitting an ally"}
            end
        end

        local forceIntoLoc = FindForceIntoLocation(invokerToken, casterToken, abilityClone,
            movementSymbols, range, forcedMovement)
        if forceIntoLoc ~= nil then
            ai:LogDecision("FORCE INTO ZONE", {
                targets = ai.TargetsLogName({{token = casterToken}}),
                to = ai.LocLogName(forceIntoLoc),
                plan = forcedMovement,
            })
            return AnswerForcedMoveLoc(casterToken, forceIntoLoc, forcedMovement, range)
        end

        if forcedMovement == "pull" or forcedMovement == "vertical_pull" then
            local bestLoc, bestDamage = FindBestPullLocation(invokerToken, casterToken, abilityClone,
                movementSymbols, range, forcedMovement, preferAltitude)
            if bestLoc ~= nil then
                ai:LogDecision("FORCED MOVE", {
                    targets = ai.TargetsLogName({{token = casterToken}}),
                    to = ai.LocLogName(bestLoc),
                    plan = forcedMovement,
                    damage = bestDamage,
                })
                return AnswerForcedMoveLoc(casterToken, bestLoc, forcedMovement, range, abilityClone)
            end
            return nil
        end

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

        local best = nil
        for _,testLoc in ipairs(possibleLocs) do
            testLoc = preferAltitude(testLoc)
            local movementInfo = casterToken:MarkMovementArrow(ArrowLoc(casterToken, forcedMovement, testLoc),
                ForcedMovementArrowOptions(forcedMovement, range, casterToken, abilityClone))
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

                --Damage decides first; this positioning score only breaks ties.
                --lower score is better.
                local damage = PredictForcedMoveDamage(invokerToken, casterToken, abilityClone,
                    testLoc, movementInfo, range, forcedMovement)
                local score = dist + 2*collideWithAllies - 2*collideWithEnemies - 2*fallDistance
                if collideWithObjects then
                    score = score - 4
                end

                local altitude = cond(isVertical, testLoc.altitude, nil)
                if BetterForcedMoveCandidate(damage, altitude, score, best, false) then
                    best = {damage = damage, altitude = altitude, score = score, loc = testLoc}
                end
            end
        end
        casterToken:ClearMovementArrow()

        if best ~= nil then
            ai:LogDecision("FORCED MOVE", {
                targets = ai.TargetsLogName({{token = casterToken}}),
                to = ai.LocLogName(best.loc),
                plan = forcedMovement,
                damage = best.damage,
            })
            return AnswerForcedMoveLoc(casterToken, best.loc, forcedMovement, range, abilityClone)
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

--Where a hurled creature lands (Ogre Goon's People Bowling). When several free
--squares tie for nearest to the line's end they arrive in _tmp_restrictLocs,
--and any of them follows the rule, so take the first.
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

        --No legal second target: answer with no targets so the follow-up is
        --skipped. HandlePrompt only accepts a table (or nil to ask the Director).
        if #possibleTokens == 0 then
            return {targets = {}}
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

--- How bad the worst effect an End Effect trigger could end is (0-5, see
--- MonsterAI.conditionSeverity), and the purge behind it with its Stamina cost.
--- Both nil when the trigger is not shaped like an End Effect.
--- @param token CharacterToken
--- @param triggerInfo ActiveTrigger
--- @return number|nil worst
--- @return nil|{behavior: ActivatedAbilityPurgeEffectsBehavior, cost: number} purge
function MonsterAI.EndEffectSeverity(token, triggerInfo)
    local purge = EndEffectPurge(token, triggerInfo)
    if purge == nil then
        return nil, nil
    end
    local data = purge.behavior:CollectPurgeItems(token, nil)
    local worst = 0
    for _,item in ipairs(data ~= nil and data.items or {}) do
        worst = math.max(worst, MonsterAI.PurgeItemValue(item, token, token))
    end
    return worst, purge
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
    local worst, purge = MonsterAI.EndEffectSeverity(token, triggerInfo)
    if purge == nil then
        return nil, "no purge behind this End Effect; left to the Director"
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

--A Beastheart's Covering Fire puts Taking Fire on each target that is not
--prone: a free triggered action to fall prone, or take extra damage equal to
--twice the Beastheart's Intuition. It is offered to any creature the hero
--shoots, so it is registered by its prompt text for every monster. The trigger
--costs nothing, and prone is the very thing the shot is meant to force, so the
--monster always ducks.
MonsterAI:RegisterTrigger{
    id = "Covering Fire: Fall Prone",
    triggers = {"Taking Fire"},
    description = "Fall prone when targeted by a Beastheart's Covering Fire, rather than take the extra damage.",
    handler = function(ai, token, triggerInfo)
        ai:LogDecision("TAKING FIRE", {
            ability = triggerInfo:GetText(),
            result = "activate",
            reason = "falling prone avoids twice the Beastheart's Intuition in extra damage",
        })
        return {activate = true}
    end,
}
