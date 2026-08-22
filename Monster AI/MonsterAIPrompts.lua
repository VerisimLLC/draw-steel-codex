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
    if type(shape.Destroy) == "function" then
        shape:Destroy()
    end
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
            print("AI:: best pull loc =", bestLoc)
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

        print("AI:: bestLoc =", bestLoc)
        if bestLoc ~= nil then
        print("AI:: Mark arrow to", bestLoc.x, bestLoc.y)
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
            if tok.valid and (not tok:IsFriend(monsterToken)) and (not tok.properties:IsDead()) and casterToken:Distance(tok) <= range then
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

MonsterAI:RegisterPrompt{
    prompts = {"Decrepit Skeleton:Invoked Ability"},

    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        local range = abilityClone:GetRange(casterToken.properties)

        local forbiddenTokens = {}
        for _,p in ipairs(symbols.targetPairs or {}) do
            if p.a == invokerToken.charid then
                forbiddenTokens[p.b] = true
            end
        end

        local possibleTokens = {}
        for _,tok in ipairs(dmhub.allTokens) do
            if (not forbiddenTokens[tok.charid]) and (not tok:IsFriend(invokerToken)) and invokerToken:Distance(tok) <= range then
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
