local mod = dmhub.GetModLoading()

---@class MonsterAI
MonsterAI = RegisterGameType("MonsterAI")
MonsterAI.moves = {} --a table of registered moves the ai can choose from.
MonsterAI.prompts = {} --a table of prompted abilities the ai knows how to use.
MonsterAI.token = false
MonsterAI.squadMembers = {}
MonsterAI.squadCaptain = false
MonsterAI.abilities = {}
MonsterAI.tactics = {}
MonsterAI.paths = false
MonsterAI.log = {}

MonsterAI.activeTactics = {}

creature._tmp_ai_aidAttack = false

Commands.playai = function(str)

    local queue = dmhub.initiativeQueue
    if queue == nil or queue.hidden then
        print("AI:: No initiative queue active.")
        return
    end

    local initiativeid = dmhub.initiativeQueue:CurrentInitiativeId()
    if not initiativeid then
        print("AI:: No current initiative ID.")
        return
    end

    local ai = MonsterAI.new{}

    ai:PlayTurn(initiativeid)
end

function MonsterAI.Sleep(seconds)
    if seconds <= 0 then
        return
    end
    local endTime = dmhub.Time() + seconds
    while dmhub.Time() < endTime do
        coroutine.yield(0.1)
    end
end

function MonsterAI:PlayTurn(initiativeid)
    dmhub.Coroutine(function()
        self:PlayTurnCoroutine(initiativeid)
    end)
end

function MonsterAI:PlayTurnCoroutine(initiativeid)
    local queue = dmhub.initiativeQueue

    self.log.analysis = self:Analysis()

    if queue ~= nil and (not queue.hidden) and initiativeid == queue:CurrentInitiativeId() then

        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        tokens = tokens or {}

        for i=1,#tokens do
            local token = tokens[i]
            local alreadyProcessed = false
            local squadMembers = {}
            local squadid = nil
            self.squadCaptain = false
            self.squadMembers = squadMembers
            self.activeTactics = {}
            if token.valid and token.properties.minion then
                squadid = token.properties:MinionSquad()
                for j=1,i-1 do
                    local otherToken = tokens[j]
                    if otherToken.properties.minion and otherToken.properties:MinionSquad() == squadid then
                        print("AI:: Already processed minion squad")
                        alreadyProcessed = true
                        break
                    end
                end

                for j=i,#tokens do
                    local otherToken = tokens[j]
                    if otherToken.valid and otherToken.properties.minion and otherToken.properties:MinionSquad() == squadid then
                        squadMembers[#squadMembers+1] = {token = otherToken}
                    end
                end
            end

            if #squadMembers > 0 then
                for j=1,#tokens do
                    if tokens[j].valid and not tokens[j].properties.minion then
                        local minionSquad = tokens[j].properties:MinionSquad()
                        if minionSquad == squadid then
                            self.squadCaptain = tokens[j]
                            break
                        end
                    end
                end
            end

            if token.valid and (not alreadyProcessed) and (not token.properties:IsDead()) then
                self.token = token
                self.squad = squadMembers

                if token.properties.minion then
                    self.squad = {}
                else
                    self.squad = false
                end

                local promptCallback = function(invokerToken, casterToken, abilityClone, symbols, options)
                    --the ability directly inserted the expected targets.
                    local expectedEntry = self:try_get("_tmp_expectedPromptTarget")
                    if expectedEntry ~= nil and expectedEntry.casterid == invokerToken.charid then
                        if expectedEntry.sleep then
                            self.Sleep(expectedEntry.sleep)
                        end
                        options.targets = expectedEntry.targets
                        return "inherit"
                    end

                    local handler = self.prompts[abilityClone.name] or self.prompts[string.format("%s:%s", invokerToken.properties.monster_type, abilityClone.name)]
                    if handler ~= nil then
                        local result = handler.handler(self, invokerToken, casterToken, abilityClone, symbols, options)
                        if result ~= nil then
                            for k,v in pairs(result) do
                                options[k] = v
                            end

                            return "inherit"
                        end
                    else
                        print("AI:: No handler for prompt ability:", string.format("%s:%s", invokerToken.properties.monster_type, abilityClone.name))
                    end

                    return "prompt"
                end

                if #self.squadMembers > 0 then
                    for _,member in ipairs(self.squadMembers) do
                        member.token.properties._tmp_aicontrol = member.token.properties._tmp_aicontrol + 1
                        member.token.properties._tmp_aipromptCallback = promptCallback
                    end
                else
                    token.properties._tmp_aicontrol = token.properties._tmp_aicontrol + 1
                    token.properties._tmp_aipromptCallback = promptCallback
                end

                self.activeTactics = {}
                for id,tactic in pairs(self.tactics) do
                    if self.MoveMatchesMonster(token, tactic) then
                        self.activeTactics[id] = tactic
                    end
                end

                local tokens = dmhub.allTokens

                local aidAttackGuid = "e234f1f4-9953-43bd-894c-d96adbb63f84"
                self.enemyTokens = {}
                self.allyTokens = {}

                for _,tok in ipairs(tokens) do
                    local tokenInitiativeId = InitiativeQueue.GetInitiativeId(tok)
                    if tokenInitiativeId ~= nil and queue.entries[tokenInitiativeId] ~= nil and not tok.properties:IsDead() then
                        if not dmhub.TokensAreFriendly(token, tok) then
                            self.enemyTokens[#self.enemyTokens+1] = tok

                            local hasAidAttack = false
                            for _,effect in ipairs(tok.properties:ActiveOngoingEffects()) do
                                if effect.ongoingEffectid == aidAttackGuid then
                                    hasAidAttack = true
                                    break
                                end
                            end
                            tok.properties._tmp_ai_aidAttack = hasAidAttack
                        else
                            self.allyTokens[#self.allyTokens+1] = tok
                        end
                    end
                end

                self.abilities = token.properties:GetActivatedAbilities()

                for i=1,6 do
                    self.paths = token:CalculatePathfindingArea((token.properties:CurrentMovementSpeed() - token.properties:DistanceMovedThisTurn())*10, {})

                    local result = self:FindAndExecuteMove()
                    print("AI:: Execute move:", i, "result =", result)
                    if not result then
                        break
                    end
                end

                token.properties._tmp_aicontrol = token.properties._tmp_aicontrol - 1
                token.properties._tmp_aipromptCallback = nil
            else
                print("AI:: Token no longer valid for initiative ID", initiativeid)
            end
        end

        GameHud.instance:NextInitiative(function()
            dmhub:UploadInitiativeQueue()
        end)
        
        coroutine.yield(0.5)
    end
end

local function FindAbilityByName(abilities, name)
    for _,ability in ipairs(abilities) do
        if ability.name == name then
            return ability
        end
    end

    return nil
end 

function MonsterAI:FindClosestEnemy()
    local closestEnemy = nil
    local closestDistance = nil
    for _,enemy in ipairs(self.enemyTokens) do
        local dist = self.token:Distance(enemy)
        if closestDistance == nil or dist < closestDistance then
            closestDistance = dist
            closestEnemy = enemy
        end
    end

    return closestEnemy
end

function MonsterAI:FindValidTargetsOfStrike(token, ability, loc, range)

    local meleeAbility = ability:HasKeyword("Melee")
    local rangedAbility = ability:HasKeyword("Ranged")

    local filteredTokens = {}
    for i=1,#self.enemyTokens do
        local enemy = self.enemyTokens[i]
        local canTarget = ability:TargetPassesFilter(token, enemy, {})
        if canTarget and enemy.properties:HasNamedCondition("Hidden") and ability:HasKeyword("Strike") then
            canTarget = false
        end
        if canTarget then
            filteredTokens[#filteredTokens+1] = enemy
        end
    end

    local hasCharge = ability:HasKeyword("Charge") or ability.name == "Melee Free Strike"
    range = range or ability:GetRange(token.properties)
    local result = {}
    token:ExecuteWithTheoreticalLoc(loc, function()
        for i=1,#filteredTokens do
            local enemy = filteredTokens[i]
            local dist = token:Distance(enemy)

            local chargeLoc = nil
            if hasCharge then
                local movementInfo = token:MarkMovementArrow(enemy.loc, {straightline = true, ignorecreatures = false, moveThroughFriends = true})
                --check that the move doesn't make us fall down.
                if movementInfo ~= nil then
                    local path = movementInfo.path
                    local altitude = game.currentFloor:GetAltitudeAtLoc(path.origin)
                    for _,step in ipairs(path.steps) do
                        local fallDistance = altitude - game.currentFloor:GetAltitudeAtLoc(step)
                        if fallDistance > 1 then
                            movementInfo = nil
                            break
                        end
                    end
                end

                if movementInfo ~= nil then
                    local chargeDist = movementInfo.path.destination:DistanceInTiles(movementInfo.path.origin)
                    if chargeDist <= ability:try_get("chargeDistanceOverride", token.properties:CurrentMovementSpeed()) then
                        local dest = movementInfo.path.destination
                        dist = enemy:Distance(dest)
                        chargeLoc = dest
                    end
                end
            end

            if dist <= range then
                local los = token:GetLineOfSight(enemy)
                if los > 0 then

                    local edges = 0

                    --obstruction.
                    if los < 1 then
                        edges = edges - 1
                    end

                    local tokenLoc = chargeLoc or loc

                    for _,tactic in pairs(self.activeTactics) do
                        local score = tactic.score(self, token, tokenLoc, enemy, ability) or 0
                        edges = edges + score
                    end

                    --nearby enemies with ranged penalty
                    if rangedAbility and not meleeAbility then
                        local hasNearbyEnemies = false
                        for _,enemyToken in ipairs(self.enemyTokens) do
                            if enemyToken:Distance(tokenLoc) <= 1 then
                                hasNearbyEnemies = true
                                break
                            end
                        end

                        if hasNearbyEnemies then
                            edges = edges - 1
                        end
                    end

                    result[#result+1] = { token = enemy, loc = enemy.loc, charge = chargeLoc, edges = edges }
                end
            end
        end

    end)

    if hasCharge then
        token:ClearMovementArrow()
    end

    table.sort(result, function(a,b) return a.edges > b.edges end)

    return result
end

function MonsterAI:FindSquadMemberStrikeOptions(squadMember, ability)
    squadMember.possibleTargets = {}
    local range = ability:GetRange(squadMember.token.properties)
    local numTargets = ability:GetNumTargets(squadMember.token)
    for _,info in pairs(squadMember.paths) do
        local destLoc = info.loc

        local targets = self:FindValidTargetsOfStrike(squadMember.token, ability, destLoc, range)
        for _,target in ipairs(targets) do
            local cost = info.cost
            cost = cost - target.edges * 5 --we love to get edges
            if target.charge ~= nil then
                --if charging, prefer to move in line with the charge
                local deltaMove = {x = target.charge.x - squadMember.token.loc.x, y = target.charge.y - squadMember.token.loc.y}
                local deltaCharge = {x = target.token.loc.x - target.charge.x, y = target.token.loc.y - target.charge.y}
                local dotProduct = deltaMove.x * deltaCharge.x + deltaMove.y * deltaCharge.y
                cost = cost - dotProduct*0.5
                print("AI:: Charge dot product for", squadMember.token.loc.x, squadMember.token.loc.y, "to", target.token.loc.x, target.token.loc.y, "via", target.charge.x, target.charge.y, "is", dotProduct, "adjusted cost =", cost)
            end
            local existing = squadMember.possibleTargets[target.token.charid]
            if existing == nil then
                squadMember.possibleTargets[target.token.charid] = {
                    token = target.token,
                    charge = target.charge,
                    loc = destLoc,
                    cost = cost,
                }
            elseif existing.cost > cost then
                existing.loc = destLoc
                existing.cost = cost
                existing.charge = target.charge
            end
        end
    end

    print("AI:: SQUAD MEMBER HAS POSSIBLE TARGETS:", table.keys(squadMember.possibleTargets))

    return squadMember.possibleTargets
end

function MonsterAI:ExecuteSquadStrike(ability)
    local logMessage = nil
    local rays = {}
    local targetPairs = {}
    local assignedTargets = {}
    for _,squadMember in ipairs(self.squadMembers) do

        squadMember.paths = squadMember.token:CalculatePathfindingArea(squadMember.token.properties:CurrentMovementSpeed()*10, {})

        local options = self:FindSquadMemberStrikeOptions(squadMember, ability)
        local bestOption = nil
        local bestScore = nil
        for _,option in pairs(options) do
            local score = option.cost
            if assignedTargets[option.token.charid] ~= nil then
                score = score + 10000*assignedTargets[option.token.charid]
            end

            if bestOption == nil or score < bestScore then
                bestOption = option
                bestScore = score
            end
        end

        if bestOption ~= nil then
            assignedTargets[bestOption.token.charid] = (assignedTargets[bestOption.token.charid] or 0) + 1
            local path = squadMember.token:Move(bestOption.loc, {maxCost = 10000, ignoreFalling = false})
            self.Sleep(0.6)


            if bestOption.charge ~= nil then
                self:Speech(squadMember.token, "Charge!")
                self.Sleep(0.3)
                print("AI:: CHARGE TO", bestOption.charge.x, bestOption.charge.y)
                local path = squadMember.token:Move(bestOption.charge, {maxCost = 10000, ignoreFalling = false})
                self.Sleep(1)
            end

            local toka = squadMember.token
            local tokb = bestOption.token

            if toka ~= nil and toka.valid and (not toka.properties:IsDead()) and tokb ~= nil and tokb.valid then
                dmhub.Schedule(0.8, function()
                    rays[#rays+1] = dmhub.MarkLineOfSight(toka, tokb)
                end)
                targetPairs[#targetPairs+1] = {a = squadMember.token.charid, b = bestOption.token.charid}
            end
        end
    end

    if #targetPairs > 0 then
        if self.squadCaptain and self.squadCaptain.valid then
            if ability:HasKeyword("Melee") then
                self:Speech(self.squadCaptain, {"Attack together!", "Strike as one!", "Get 'em, boys!"})
            else
                self:Speech(self.squadCaptain, {"Fire at will!", "Take them down!", "Shoot them down like dogs!"})
            end
            
        end

        local symbols = {
            targetPairs = targetPairs,
        }

        self.Sleep(1)

        local targetsAdded = {}
        local targets = {}
        for _,pair in ipairs(targetPairs) do
            if not targetsAdded[pair.b] then
                local targetToken = dmhub.GetTokenById(pair.b)
                targets[#targets+1] = { token = targetToken }
                targetsAdded[pair.b] = true
            end
        end

        self:ExecuteAbility(self.token, ability, targets, {symbols = symbols, sleep = 2.0})
        logMessage = string.format("Executed on %d targets", #targets)
    else
        logMessage = "Could not find any targets"
    end

    for _,ray in ipairs(rays) do
        ray:DestroyLineOfSight()
    end

    if logMessage then
        self:LogMove(self.token.properties.monster_type, "Minion Signature Ability", logMessage)
    end

    return #targetPairs > 0
end

function MonsterAI:FindBestMoveToUseStrike(token, ability, scorefn)
    if scorefn ~= nil then
        local scoreCache = {}
        local scoreInternal = scorefn
        scorefn = function(tok)
            local score = scoreCache[tok.charid]
            if score == nil then
                score = scoreInternal(tok)
                scoreCache[tok.charid] = score
            end
            return score
        end
    end
    local range = ability:GetRange(token.properties)
    local numTargets = ability:GetNumTargets(token)
    local bestScore = 0
    local bestMove = nil
    for _,info in pairs(self.paths) do
        local destLoc = info.loc

        local targets = self:FindValidTargetsOfStrike(token, ability, destLoc, range)

        local score = math.min(numTargets, #targets)
        if scorefn ~= nil then
            score = 0
            table.sort(targets, function(a,b)
                return scorefn(a.token, a.edges) > scorefn(b.token, b.edges)
            end)
            for i=1,math.min(numTargets, #targets) do
                score = score + scorefn(targets[i].token, targets[i].edges)
            end
        else
            local maxEdges = nil
            for _,target in ipairs(targets) do
                if maxEdges == nil or target.edges > maxEdges then
                    maxEdges = target.edges
                end
            end

            print("AI:: Max Edges for loc", destLoc.x, destLoc.y, "is", maxEdges)

            score = score + (maxEdges or 0)*0.1
        end

        score = score - info.cost*0.001

        if score > bestScore then
            bestScore = score
            bestMove = destLoc
        end
    end

    return bestMove, bestScore
end

function MonsterAI:FindBestMoveToUseBurst(token, ability, scorefn)
    scorefn = scorefn or function() return 1 end
    local range = ability:GetRange(token.properties)
    local bestScore = nil
    local bestMove = nil
    local allTokens = dmhub.allTokens
    for _,info in pairs(self.paths) do
        local score = 0
        local destLoc = info.loc
        for _,targetToken in ipairs(allTokens) do
            if targetToken ~= token and targetToken:Distance(destLoc) <= range then
                score = score + scorefn(targetToken)
            end
        end

        if bestScore == nil or score > bestScore then
            bestScore = score
            bestMove = destLoc
        end
    end

    return bestMove, bestScore
end

function MonsterAI.MoveMatchesMonster(token, move, includeDisabled)
    if move.id == "Minion Signature Ability" then
        --minion signatures cannot be disabled.
        includeDisabled = true
    end
    local monster_type = token.properties:try_get("monster_type", "")
    if not includeDisabled then
        if move.disabledForMonsters ~= nil and move.disabledForMonsters[monster_type] then
            return false
        end
    end
    if move.monsters ~= nil then
        for i=1,#move.monsters do
            if move.monsters[i] == monster_type then
                return true
            end
        end
    else
        return true
    end

    return false
end

function MonsterAI:FindAndExecuteMove()
    local token = self.token

    if not token.valid then
        print("AI:: Token no longer valid.")
        return false
    end

    local abilities = self.abilities
    local bestScore = {score = 0}
    local bestMove = nil
    local c = token.properties


    if token.properties.minion then
        for _,ability in ipairs(abilities) do
            if ability.categorization == "Signature Ability" and ability:CanAfford(token) then
                print("AI:: Minions executing squad strike:", ability.name)
                return self:ExecuteSquadStrike(ability)
            end
        end

        print("AI: No signature ability found")
        return 
    end

    for moveid,move in pairs(self.moves) do
        local matchesMonster = self.MoveMatchesMonster(token, move)

        local usingAbilities = {}
        if matchesMonster and move.abilities ~= nil then
            for i=1,#move.abilities do
                local ability = FindAbilityByName(abilities, move.abilities[i])
                if ability == nil then
                    matchesMonster = false
                    break
                end

                if not ability:CanAfford(token) then
                    print("AI:: Cannot afford ability:", ability.name)
                    self:LogMove(self.token.properties.monster_type, moveid, "Could not afford", {onlyIfEmpty = true})
                    matchesMonster = false
                    break
                end

                print("AI:: Can afford ability:", ability.name)

                usingAbilities[#usingAbilities+1] = ability
            end
        end
        
        if matchesMonster then
            local score = move.score(move, self, token, usingAbilities[1], usingAbilities[2], usingAbilities[3])
            if score ~= nil then
                self:LogMove(self.token.properties.monster_type, moveid, string.format("Score: %.2f", score.score))
            else
                self:LogMove(self.token.properties.monster_type, moveid, "Could not make move", {onlyIfEmpty = true})
            end
            if score ~= nil and score.score > bestScore.score then
                score.usingAbilities = usingAbilities
                bestScore = score
                bestMove = move
            end
        end
    end

    if bestMove ~= nil then
        bestMove.execute(bestMove, self, token, bestScore, bestScore.usingAbilities[1], bestScore.usingAbilities[2], bestScore.usingAbilities[3])
        self:LogMove(self.token.properties.monster_type, bestMove.id, "Executed move")
        return true
    end

    return false
end

function MonsterAI:DistanceFromNearestEnemy(token)
    local result = 999
    for _,enemy in ipairs(self.enemyTokens) do
        local dist = token:Distance(enemy)
        result = math.min(result, dist)
    end
    return result
end

function MonsterAI:ExecuteAbility(casterToken, ability, targets, options)

    if not ability:CanAfford(casterToken) then
        print("AI:: Cannot afford ability:", ability.name)
        return
    end

    options = options or {}
    local symbols = options.symbols or {}
    symbols.mode = symbols.mode or 1

    if targets == nil then
        targets = {}

        if ability.targetType == "all" then
            local range = ability:GetRange(casterToken.properties)
            --a burst ability.
            for _,token in ipairs(dmhub.allTokens) do
                if ability:TargetPassesFilter(casterToken, token, symbols) and token:Distance(casterToken) <= range then
                    targets[#targets+1] = { token = token }
                end
            end
        end
    else
        local numTargets = ability:GetNumTargets(casterToken)
        table.resize_array(targets, numTargets)
    end

    --if this is a melee and ranged ability, choose the appropriate variation.
    if ability.meleeAndRanged then
        local meleeRange = ability.meleeVariation:GetRange(casterToken.properties)
        local inMeleeRange = true
        for _,target in ipairs(targets) do
            if target.token ~= nil and casterToken:Distance(target.token) > meleeRange then
                inMeleeRange = false
                break
            end
        end

        if inMeleeRange then
            ability = ability.meleeVariation
        else
            ability = ability.rangedVariation
        end
    end

    for _,target in ipairs(targets) do
        if target.charge ~= nil then
            local token = casterToken
            if symbols.targetPairs ~= nil then
                for _,p in ipairs(symbols.targetPairs) do
                    token = dmhub.GetTokenById(p.a)
                end
            end

            self.Sleep(1)
            self:Speech(token, "Charge!")
            self.Sleep(0.5)

            local path = token:Move(target.charge, {maxCost = 10000, ignoreFalling = false})
            self.Sleep(1)
            target.charge = nil
        end
    end

    local rays = {}
    if symbols.targetPairs == nil then
        for _,target in ipairs(targets) do
            if target.token ~= nil then
                rays[#rays+1] = dmhub.MarkLineOfSight(casterToken, target.token)
            end
        end
    end

    ability = ability:MakeTemporaryClone()
    print("AI:: USING ABILITY:", ability.name, "on", #targets)
    options.symbols = symbols
    options.targets = targets
    options.countsAsCast = true

    local finished = false

	local OnFinishCast = ability:try_get("OnFinishCast")
    ability.OnFinishCast = function (ability, options)
        if OnFinishCast then
            OnFinishCast(ability, options)
        end
        
        finished = true
    end


    print("AI:: Execute invoke with targets =", targets)
    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, ability, casterToken, "inherit", symbols, options)


    print("AI:: RUNNING...")
    while not finished do
        coroutine.yield(0.1)
    end

    print("AI:: FINISHED ABILITY")
    self.Sleep(options.sleep or 1.0)

    for _,ray in ipairs(rays) do
        ray:DestroyLineOfSight()
    end
end

function MonsterAI:FindReachableConcealment()
    local bestLoc = nil
    local bestScore = nil
    for _,info in pairs(self.paths) do
        local destLoc = info.loc

        if bestScore == nil or info.cost < bestScore then
            self.token:ExecuteWithTheoreticalLoc(destLoc, function()
                if self.token.properties:IsConcealed() then
                    bestLoc = info.loc
                    bestScore = info.cost
                end
            end)
        end
    end

    return bestLoc
end

function MonsterAI:Speech(token, text, options)
    if not token.valid then
        return
    end
    if type(text) == "table" then
        text = text[math.random(1, #text)]
    end
    local ability = MCDMImporter.GetStandardAbility("Speech")
    ability = ability:MakeTemporaryClone()

    MCDMUtils.DeepReplace(ability, "<<text>>", text)
    self:ExecuteAbility(token, ability, {}, options)
end

function MonsterAI:LogMove(monsterType, moveid, message, options)
    options = options or {}
    if self.log.analysis == nil then
        self.log.analysis = self:Analysis()
        self.log.updatedAnalysis = dmhub.GenerateGuid()
    end

    for _,entry in ipairs(self.log.analysis) do
        if entry.monsterType == monsterType then
            for _,move in ipairs(entry.moves) do
                if move.id == moveid then
                    move.log = move.log or {}
                    if #move.log > 0 and options.onlyIfEmpty then
                        return
                    end
                    move.log[#move.log+1] = message
                    return
                end
            end
        end
    end
end

MonsterAI.AbilityCategories = {
    "Main Actions",
    "Basic Strikes",
    "Maneuvers",
    "Tactics",
}

local g_abilityCategoryOrder = {}
for i,cat in ipairs(MonsterAI.AbilityCategories) do
    g_abilityCategoryOrder[cat] = i
end

--- @return {monsterType: string, moves: {id: string, category: string, abilities: string[]}[] }[]
function MonsterAI:Analysis()
    local result = {}
    local monstersSeen = {}
    local tokens = dmhub.allTokens
    local queue = dmhub.initiativeQueue
    if queue ~= nil and (not queue.hidden) then
        for _,tok in ipairs(tokens) do
            local monsterType = tok.properties:try_get("monster_type", nil)
            local initiativeid = InitiativeQueue.GetInitiativeId(tok)
            if initiativeid ~= nil and queue.entries[initiativeid] ~= nil and (not queue:IsEntryPlayer(initiativeid)) and (not monstersSeen[monsterType]) then
                monstersSeen[monsterType] = true

                local languageid = tok.properties:CurrentlySpokenLanguage()
                if languageid then
                    languageid = dmhub.GetTable(Language.tableName)[languageid]
                end

                local resultEntry = {
                    monsterType = monsterType,
                    language = languageid,
                    moves = {},
                }
                result[#result+1] = resultEntry

                for moveid,move in pairs(self.moves) do
                    if self.MoveMatchesMonster(tok, move, true) then
                        resultEntry.moves[#resultEntry.moves+1] = {
                            monsterType = monsterType,
                            id = moveid,
                            description = move.description,
                            category = move.category,
                            abilities = move.abilities,
                            enabled = move.enabled ~= false,
                        }
                    end
                end

                for moveid,move in pairs(self.tactics) do
                    if self.MoveMatchesMonster(tok, move, true) then
                        resultEntry.moves[#resultEntry.moves+1] = {
                            monsterType = monsterType,
                            id = moveid,
                            description = move.description,
                            category = move.category,
                            abilities = {},
                            enabled = move.enabled ~= false,
                        }
                    end
                end

                table.sort(resultEntry.moves, function(a,b)
                    return (g_abilityCategoryOrder[a.category or "Maneuvers"] or 0) < (g_abilityCategoryOrder[b.category or "Maneuvers"] or 0)
                end)

                if tok.properties.minion then
                    local abilities = tok.properties:GetActivatedAbilities()
                    for _,ability in ipairs(abilities) do
                        if ability.categorization == "Signature Ability" then
                            resultEntry.moves[#resultEntry.moves+1] = {
                                id = "Minion Signature Ability",
                                category = "Main Actions",
                                description = "The Squad will move into a position that can maximize their number of targets and then use this ability.",
                                abilities = {ability.name},
                            }
                        end
                    end
                end
            end
        end
    end

    return result
end


--- @param {casterid: string, targets: {casterid: nil|Token, loc: nil|Loc}[], sleep: nil|number} options
function MonsterAI:SetTargetsForExpectedPrompt(options)
   self._tmp_expectedPromptTarget = options
end

function MonsterAI:IsMoveEnabledForMonster(monsterType, id)
    local move = self.moves[id] or self.tactics[id]
    if move ~= nil then
        if move.disabledForMonsters ~= nil and move.disabledForMonsters[monsterType] then
            return false
        end
        return true
    end
    return false
end

function MonsterAI:SetMoveEnabledForMonster(monsterType, id, enabled)
    local move = self.moves[id] or self.tactics[id]
    if move ~= nil then
        move.disabledForMonsters = move.disabledForMonsters or {}
        move.disabledForMonsters[monsterType] = not enabled
    end
end

function MonsterAI:RegisterMove(args)
    if args.category == nil then
        args.category = "Main Actions"
    end
    self.moves[args.id] = args
end

function MonsterAI:RegisterPrompt(args)
    for _,prompt in ipairs(args.prompts) do
        self.prompts[prompt] = args
    end
end

function MonsterAI:RegisterTactic(args)
    args.category = "Tactics"
    self.tactics[args.id] = args
end