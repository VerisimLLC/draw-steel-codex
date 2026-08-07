local mod = dmhub.GetModLoading()

---@class MonsterAI
MonsterAI = RegisterGameType("MonsterAI")
MonsterAI.moves = {} --a table of registered moves the ai can choose from.
MonsterAI.prompts = {} --a table of prompted abilities the ai knows how to use.
MonsterAI.triggerHandlersByGuid = {}
MonsterAI.triggerHandlersByMonsterAbility = {}
MonsterAI.triggerHandlersByAbility = {}
MonsterAI.triggerHandlersByMonsterText = {}
MonsterAI.triggerHandlersByText = {}
MonsterAI.token = false
MonsterAI.squadMembers = {}
MonsterAI.squadCaptain = false
MonsterAI.abilities = {}
MonsterAI.tactics = {}
MonsterAI.maliceAbilities = {}
MonsterAI.villainActions = {}
MonsterAI.paths = false
MonsterAI.log = {}
MonsterAI.active = false
MonsterAI.maliceAbilityMinimumScore = 0.65

MonsterAI.activeTactics = {}

creature._tmp_ai_aidAttack = false

Commands.RegisterMacro{
    name = "playai",
    summary = "play AI turn",
    doc = "Usage: /playai\nPlays an AI turn for the current initiative entry. Requires an active initiative queue.",
    command = function(str)

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
    end,
}

function MonsterAI.Sleep(seconds)
    if seconds <= 0 then
        return
    end
    local endTime = dmhub.Time() + seconds
    while dmhub.Time() < endTime do
        coroutine.yield(0.1)
    end
end

function MonsterAI:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
    --the ability directly inserted the expected targets.
    local expectedEntry = self:try_get("_tmp_expectedPromptTarget")
    if expectedEntry ~= nil and expectedEntry.casterid == invokerToken.charid then
        self._tmp_expectedPromptTarget = nil
        if expectedEntry.sleep then
            self.Sleep(expectedEntry.sleep)
        end
        options.targets = expectedEntry.targets
        return "inherit"
    end

    --try_get: the invoker can be an object token (e.g. a wall voxel
    --prompting for a target near it), whose TargetableObject
    --properties have no monster_type field.
    local invokerMonsterType = invokerToken.properties:try_get("monster_type", "")
    local handler = self.prompts[abilityClone.name] or self.prompts[string.format("%s:%s", invokerMonsterType, abilityClone.name)]
    if handler ~= nil then
        local result = handler.handler(self, invokerToken, casterToken, abilityClone, symbols, options)
        if result ~= nil then
            for k,v in pairs(result) do
                options[k] = v
            end

            return "inherit"
        end
    else
        print("AI:: No handler for prompt ability:", string.format("%s:%s", invokerMonsterType, abilityClone.name))
    end

    return "prompt"
end

function MonsterAI:BeginTokenControl(token)
    local previousCallback = token.properties._tmp_aipromptCallback
    local promptCallback = function(invokerToken, casterToken, abilityClone, symbols, options)
        return self:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
    end

    token.properties._tmp_aicontrol = token.properties._tmp_aicontrol + 1
    token.properties._tmp_aipromptCallback = promptCallback

    return {
        promptCallback = promptCallback,
        previousCallback = previousCallback,
    }
end

function MonsterAI:EndTokenControl(token, controlInfo)
    if token == nil or not token.valid or token.properties == nil then
        return
    end

    token.properties._tmp_aicontrol = math.max(0, token.properties._tmp_aicontrol - 1)
    if token.properties._tmp_aipromptCallback == controlInfo.promptCallback then
        token.properties._tmp_aipromptCallback = controlInfo.previousCallback
    end
end

function MonsterAI:FindTriggerHandler(token, triggerInfo)
    local function MatchingHandler(handler)
        if handler ~= nil and self.MoveMatchesMonster(token, handler, true) then
            return handler
        end
    end

    if type(triggerInfo.abilityGuid) == "string" then
        local handler = MatchingHandler(self.triggerHandlersByGuid[triggerInfo.abilityGuid])
        if handler ~= nil then
            return handler
        end
    end

    if type(triggerInfo.abilityName) == "string" then
        local monsterType = token.properties:try_get("monster_type", "")
        local qualifiedName = string.format("%s:%s", monsterType, triggerInfo.abilityName)
        local handler = MatchingHandler(self.triggerHandlersByMonsterAbility[qualifiedName])
        if handler ~= nil then
            return handler
        end

        handler = MatchingHandler(self.triggerHandlersByAbility[triggerInfo.abilityName])
        if handler ~= nil then
            return handler
        end
    end

    local triggerText = triggerInfo:GetText()
    if type(triggerText) == "string" then
        local monsterType = token.properties:try_get("monster_type", "")
        local qualifiedText = string.format("%s:%s", monsterType, triggerText)
        local handler = MatchingHandler(self.triggerHandlersByMonsterText[qualifiedText])
        if handler ~= nil then
            return handler
        end

        return MatchingHandler(self.triggerHandlersByText[triggerText])
    end
end

function MonsterAI:HandleAvailableTrigger(token, triggerInfo)
    if triggerInfo == nil or triggerInfo.triggered or triggerInfo.dismissed then
        return false
    end

    local registeredTrigger = self:FindTriggerHandler(token, triggerInfo)
    if registeredTrigger == nil then
        return false
    end

    self.token = token
    local decision = registeredTrigger.handler(self, token, triggerInfo)
    if decision == true then
        decision = {activate = true}
    end

    if type(decision) ~= "table" or (not decision.activate and not decision.dismiss) then
        return false
    end

    if decision.expectedPrompt ~= nil then
        local expectedPrompt = table.shallow_copy(decision.expectedPrompt)
        expectedPrompt.casterid = expectedPrompt.casterid or token.charid
        self:SetTargetsForExpectedPrompt(expectedPrompt)
    end

    local controlInfo = self:BeginTokenControl(token)

    token:ModifyProperties{
        description = string.format("AI Trigger: %s", registeredTrigger.id),
        undoable = false,
        execute = function()
            if decision.dismiss then
                triggerInfo.dismissed = true
            elseif type(decision.mode) == "number" and decision.mode > 1 then
                --ActiveTrigger stores alternate modes zero-based relative to the
                --ability's mode list: true selects mode 1, 1 selects mode 2, etc.
                triggerInfo.triggered = decision.mode - 1
            else
                triggerInfo.triggered = true
            end

            token.properties:DispatchAvailableTrigger(triggerInfo)
        end,
    }

    --An accepted trigger may wait for the cast that caused it to finish before
    --starting its own cast. Keep AI prompt control installed until the prompt is
    --gone and all casts have been idle for a short grace period.
    local deadline = dmhub.Time() + 45
    local idleSince = nil
    while token.valid and dmhub.Time() < deadline do
        local availableTriggers = token.properties:GetAvailableTriggers() or {}
        local triggerPending = availableTriggers[triggerInfo.id] ~= nil
        local castPending = ActivatedAbility.CountActiveCasts() > 0
        if not triggerPending and not castPending then
            idleSince = idleSince or dmhub.Time()
            if dmhub.Time() - idleSince >= 0.3 then
                break
            end
        else
            idleSince = nil
        end

        coroutine.yield(0.1)
    end

    self:EndTokenControl(token, controlInfo)
    self._tmp_expectedPromptTarget = nil
    return true
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

        self:HandleMaliceAbilityStartOfTurn(initiativeid, tokens, queue)

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
                    return self:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
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

                if #self.squadMembers > 0 then
                    for _,member in ipairs(self.squadMembers) do
                        member.token.properties._tmp_aicontrol = member.token.properties._tmp_aicontrol - 1
                        member.token.properties._tmp_aipromptCallback = nil
                    end
                else
                    token.properties._tmp_aicontrol = token.properties._tmp_aicontrol - 1
                    token.properties._tmp_aipromptCallback = nil
                end
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

local function FindMaliceAbilityByName(token, name)
    for _,ability in ipairs(token.properties:GetActivatedAbilities()) do
        if ability.name == name and ability.categorization == "Malice" then
            return ability
        end
    end
end

function MonsterAI:SetupCombatants(token, queue)
    self.token = token
    self.abilities = token.properties:GetActivatedAbilities()
    self.enemyTokens = {}
    self.allyTokens = {}
    self.activeTactics = {}

    for id,tactic in pairs(self.tactics) do
        if self.MoveMatchesMonster(token, tactic) then
            self.activeTactics[id] = tactic
        end
    end

    for _,other in ipairs(dmhub.allTokens) do
        local initiativeid = InitiativeQueue.GetInitiativeId(other)
        if other.valid and other.properties ~= nil and initiativeid ~= nil
            and queue.entries[initiativeid] ~= nil and not other.properties:IsDead() then
            if dmhub.TokensAreFriendly(token, other) then
                self.allyTokens[#self.allyTokens+1] = other
            else
                self.enemyTokens[#self.enemyTokens+1] = other
            end
        end
    end
end

local function InitiativeEntryHasLiveToken(initiativeid)
    for _,token in ipairs(InitiativeQueue.GetTokensForInitiativeId(initiativeid) or {}) do
        if token.valid and token.properties ~= nil and not token.properties:IsDead() then
            return true
        end
    end
    return false
end

local function CountFutureVillainActionWindows(queue, endedInitiativeId, ownerInitiativeId)
    local result = 0
    for initiativeid,entry in pairs(queue.entries) do
        if initiativeid ~= endedInitiativeId and initiativeid ~= ownerInitiativeId
            and entry.round <= queue.round and InitiativeEntryHasLiveToken(initiativeid) then
            result = result + 1
        end
    end
    return result
end

local function RunYieldingFunction(fn)
    local thread = coroutine.create(fn)
    while coroutine.status(thread) ~= "dead" do
        local ok, delay = coroutine.resume(thread)
        if not ok then
            return false, delay
        end
        if coroutine.status(thread) ~= "dead" then
            coroutine.yield(type(delay) == "number" and delay or 0.1)
        end
    end
    return true
end

function MonsterAI:RunWithTokenControl(token, fn)
    local controlInfo = self:BeginTokenControl(token)
    local ok, err = RunYieldingFunction(fn)
    self:EndTokenControl(token, controlInfo)
    self._tmp_expectedPromptTarget = nil
    return ok, err
end

function MonsterAI:WaitForAbilityIdle(timeout)
    local deadline = dmhub.Time() + (timeout or 45)
    local idleSince = nil
    while dmhub.Time() < deadline do
        if ActivatedAbility.CountActiveCasts() <= 0 then
            idleSince = idleSince or dmhub.Time()
            if dmhub.Time() - idleSince >= 0.3 then
                return
            end
        else
            idleSince = nil
        end
        coroutine.yield(0.1)
    end
end

function MonsterAI.MaliceAbilityMatchesMonster(token, maliceAbility, includeDisabled)
    if token == nil or not token.valid or token.properties == nil then
        return false
    end

    local monsterType = token.properties:try_get("monster_type", "")
    if not includeDisabled and maliceAbility.disabledForMonsters ~= nil
        and maliceAbility.disabledForMonsters[monsterType] then
        return false
    end

    if maliceAbility.monsterGroups ~= nil then
        local group = token.properties:MonsterGroup()
        if group == nil then
            return false
        end

        for _,groupNameOrId in ipairs(maliceAbility.monsterGroups) do
            if group.name == groupNameOrId or group.id == groupNameOrId then
                return true
            end
        end
        return false
    end

    return MonsterAI.MoveMatchesMonster(token, maliceAbility, includeDisabled)
end

function MonsterAI:HandleMaliceAbilityStartOfTurn(initiativeid, actingTokens, queue)
    if queue == nil or queue.hidden or initiativeid ~= queue:CurrentInitiativeId() then
        return false
    end

    local bestCandidate = nil
    for _,registration in pairs(self.maliceAbilities) do
        local groupTokens = {}
        local eligibleCasters = {}
        for _,token in ipairs(actingTokens) do
            if token.valid and token.properties ~= nil and not token.properties:IsDead()
                and self.MaliceAbilityMatchesMonster(token, registration, true) then
                groupTokens[#groupTokens+1] = token
                if self.MaliceAbilityMatchesMonster(token, registration) then
                    eligibleCasters[#eligibleCasters+1] = token
                end
            end
        end

        if #eligibleCasters > 0 and registration.abilities ~= nil and registration.abilities[1] ~= nil then
            local caster = nil
            local ability = nil
            for pass=1,2 do
                for _,token in ipairs(eligibleCasters) do
                    if pass == 2 or not token.properties.minion then
                        local candidateAbility = FindMaliceAbilityByName(token, registration.abilities[1])
                        if candidateAbility ~= nil and candidateAbility:CanAfford(token) then
                            caster = token
                            ability = candidateAbility
                            break
                        end
                    end
                end
                if caster ~= nil then
                    break
                end
            end

            if caster ~= nil then
                self:SetupCombatants(caster, queue)
                local context = {
                    actingTokens = actingTokens,
                    allyTokens = self.allyTokens,
                    enemyTokens = self.enemyTokens,
                    groupTokens = groupTokens,
                    initiativeId = initiativeid,
                    initiativeQueue = queue,
                    malice = CharacterResource.GetMalice(),
                    round = queue.round,
                }

                local ok, scoringInfo = pcall(registration.score, registration, self, caster, ability, context)
                if not ok then
                    print(string.format("AI:: Malice ability scoring failed [%s]: %s", registration.id, tostring(scoringInfo)))
                    self:LogMove(caster.properties.monster_type, registration.id, "Scoring failed: " .. tostring(scoringInfo))
                else
                    if type(scoringInfo) == "number" then
                        scoringInfo = {score = scoringInfo}
                    end

                    if type(scoringInfo) == "table" and type(scoringInfo.score) == "number" then
                        local score = math.max(0, math.min(1, scoringInfo.score))
                        local minimumScore = tonumber(registration.minimumScore) or self.maliceAbilityMinimumScore
                        self:LogMove(caster.properties.monster_type, registration.id,
                            string.format("Score %.2f; threshold %.2f", score, minimumScore))

                        if score >= minimumScore and (bestCandidate == nil or score > bestCandidate.score
                            or (score == bestCandidate.score and registration.id < bestCandidate.registration.id)) then
                            bestCandidate = {
                                ability = ability,
                                caster = caster,
                                context = context,
                                registration = registration,
                                score = score,
                                scoringInfo = scoringInfo,
                            }
                        end
                    else
                        self:LogMove(caster.properties.monster_type, registration.id,
                            "Could not use at the start of this turn", {onlyIfEmpty = true})
                    end
                end
            end
        end
    end

    if bestCandidate == nil then
        return false
    end

    local registration = bestCandidate.registration
    local caster = bestCandidate.caster
    self:SetupCombatants(caster, queue)
    local execute = registration.execute or function(_, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability)
    end
    local ok, err = self:RunWithTokenControl(caster, function()
        execute(registration, self, caster, bestCandidate.scoringInfo, bestCandidate.ability, bestCandidate.context)
    end)

    if not ok then
        print(string.format("AI:: Malice ability execution failed [%s]: %s", registration.id, tostring(err)))
        self:LogMove(caster.properties.monster_type, registration.id, "Execution failed: " .. tostring(err))
        return false
    end

    self:WaitForAbilityIdle()
    self:LogMove(caster.properties.monster_type, registration.id, "Executed at the start of the turn")
    return true
end

function MonsterAI:ExecuteVillainActionCandidate(candidate)
    local token = candidate.token
    local ability = candidate.ability
    local action = candidate.action
    if not self.active or token == nil or not token.valid or token.properties:IsDead() then
        return false
    end
    if CharacterResource.GetVillainActions() <= 0
        or VillainActionState.HasUsed(token.charid, candidate.slot)
        or not ability:CanAfford(token) then
        return false
    end

    dmhub.CenterOnToken(token.charid, {smooth = true})
    local subtitle = string.gsub(candidate.slot, "3", "III")
    subtitle = string.gsub(subtitle, "2", "II")
    subtitle = string.gsub(subtitle, "1", "I")
    DramaticBanner.Show{
        tokenid = token.charid,
        text = ability.name or "",
        subtitle = subtitle,
    }
    self.Sleep(DramaticBanner.TimeUntilDone() + 0.2)

    if not self.active or not token.valid or CharacterResource.GetVillainActions() <= 0 then
        return false
    end

    self:SetupCombatants(token, candidate.context.initiativeQueue)
    local ok, err = self:RunWithTokenControl(token, function()
        action.execute(action, self, token, candidate.scoringInfo, ability, candidate.context)
    end)

    if not ok then
        print(string.format("AI:: Villain Action execution failed [%s]: %s", action.id, tostring(err)))
        self:LogMove(token.properties.monster_type, action.id, "Execution failed: " .. tostring(err))
        return false
    end

    self:WaitForAbilityIdle()
    self:LogMove(token.properties.monster_type, action.id, "Executed villain action")
    return true
end

function MonsterAI:HandleVillainActionWindow(context)
    if not self.active or context == nil or context.initiativeQueue ~= dmhub.initiativeQueue then
        return
    end
    if CharacterResource.GetVillainActions() <= 0 then
        return
    end

    local round = context.round
    if type(round) ~= "number" or round < 1 or round > 3 then
        return
    end
    local slot = string.format("Villain Action %d", round)

    -- End-turn triggers get a short grace period to start and finish before a
    -- villain action is scored in the same between-turn window.
    self:WaitForAbilityIdle()
    if not self.active or CharacterResource.GetVillainActions() <= 0 then
        return
    end

    self.log.analysis = self:Analysis()
    local candidates = {}
    for _,token in ipairs(dmhub.allTokens) do
        local ownerInitiativeId = InitiativeQueue.GetInitiativeId(token)
        if token.valid and token.properties ~= nil and not token.properties:IsDead()
            and ownerInitiativeId ~= nil and ownerInitiativeId ~= context.endedInitiativeId
            and context.initiativeQueue.entries[ownerInitiativeId] ~= nil
            and context.initiativeQueue:IsEntryPlayer(ownerInitiativeId) == false then
            local abilities = token.properties:GetActivatedAbilities()
            for _,action in pairs(self.villainActions) do
                if self.MoveMatchesMonster(token, action) then
                    local ability = FindAbilityByName(abilities, action.abilities[1])
                    if ability ~= nil and ability:try_get("villainAction") == slot
                        and not VillainActionState.HasUsed(token.charid, slot)
                        and ability:CanAfford(token) then
                        self:SetupCombatants(token, context.initiativeQueue)
                        local ok, scoringInfo = pcall(action.score, action, self, token, ability, context)
                        if ok and type(scoringInfo) == "number" then
                            scoringInfo = {score = scoringInfo}
                        elseif not ok then
                            print(string.format("AI:: Villain Action scoring failed [%s]: %s", action.id, tostring(scoringInfo)))
                            scoringInfo = nil
                        end

                        if type(scoringInfo) == "table" and type(scoringInfo.score) == "number" then
                            local score = math.max(0, math.min(1, scoringInfo.score))
                            local futureWindows = CountFutureVillainActionWindows(
                                context.initiativeQueue,
                                context.endedInitiativeId,
                                ownerInitiativeId)
                            local windowsIncludingNow = futureWindows + 1
                            local chance = 1 - math.pow(1 - score, 1 / windowsIncludingNow)
                            local roll = math.random()
                            local candidate = {
                                action = action,
                                ability = ability,
                                context = context,
                                forced = futureWindows == 0,
                                ownerInitiativeId = ownerInitiativeId,
                                roll = roll,
                                score = score,
                                scoringInfo = scoringInfo,
                                slot = slot,
                                token = token,
                                chance = chance,
                            }
                            candidates[#candidates+1] = candidate
                            self:LogMove(token.properties.monster_type, action.id, string.format(
                                "Score %.2f; chance %.2f; roll %.2f; %d window(s) including now%s",
                                score, chance, roll, windowsIncludingNow, cond(candidate.forced, "; forced", "")))
                        end
                    end
                end
            end
        end
    end

    local bestCandidate = nil
    local haveForcedCandidate = false
    for _,candidate in ipairs(candidates) do
        if candidate.forced then
            if not haveForcedCandidate or bestCandidate == nil or candidate.score > bestCandidate.score then
                bestCandidate = candidate
            end
            haveForcedCandidate = true
        elseif not haveForcedCandidate and candidate.roll <= candidate.chance then
            local candidateValue = candidate.score + math.random() * 0.05
            if bestCandidate == nil or candidateValue > bestCandidate.selectionValue then
                candidate.selectionValue = candidateValue
                bestCandidate = candidate
            end
        end
    end

    if bestCandidate ~= nil then
        self:ExecuteVillainActionCandidate(bestCandidate)
    end
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
            local ignoreRange = token.properties:CalculateNamedCustomAttribute("Ignore Hidden Within Range") or 0
            if ignoreRange <= 0 or token:Distance(enemy) > ignoreRange then
                canTarget = false
            end
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
                local los = token:GetLineOfSight(enemy, token.properties:GetPierceWalls())
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
                    rays[#rays+1] = dmhub.MarkLineOfSight(toka, tokb, toka.properties:GetPierceWalls())
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
    local bestCost = nil
    local bestMove = nil
    local allTokens = dmhub.allTokens
    local symbols = {mode = 1}
    for _,info in pairs(self.paths) do
        local score = 0
        local destLoc = info.loc

        token:ExecuteWithTheoreticalLoc(destLoc, function()
            for _,targetToken in ipairs(allTokens) do
                if targetToken.valid and targetToken:Distance(token) <= range and ability:TargetPassesFilter(token, targetToken, symbols) then
                    score = score + scorefn(targetToken)
                end
            end
        end)

        local cost = info.cost or 0
        if bestScore == nil or score > bestScore or (score == bestScore and cost < bestCost) then
            bestScore = score
            bestCost = cost
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

    if not token.properties:has_key("monster_type") then
        print("AI:: Not a monster")
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
                rays[#rays+1] = dmhub.MarkLineOfSight(casterToken, target.token, casterToken.properties:GetPierceWalls())
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
    "Malice Abilities",
    "Main Actions",
    "Basic Strikes",
    "Maneuvers",
    "Villain Actions",
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
            if monsterType ~= nil and initiativeid ~= nil and queue.entries[initiativeid] ~= nil and (not queue:IsEntryPlayer(initiativeid)) and (not monstersSeen[monsterType]) then
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

                for moveid,move in pairs(self.maliceAbilities) do
                    if self.MaliceAbilityMatchesMonster(tok, move, true) then
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

                for moveid,move in pairs(self.villainActions) do
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
    local move = self.moves[id] or self.tactics[id] or self.maliceAbilities[id] or self.villainActions[id]
    if move ~= nil then
        if move.disabledForMonsters ~= nil and move.disabledForMonsters[monsterType] then
            return false
        end
        return true
    end
    return false
end

function MonsterAI:SetMoveEnabledForMonster(monsterType, id, enabled)
    local move = self.moves[id] or self.tactics[id] or self.maliceAbilities[id] or self.villainActions[id]
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

function MonsterAI:RegisterMaliceAbility(args)
    args.category = "Malice Abilities"
    args.minimumScore = args.minimumScore or self.maliceAbilityMinimumScore
    self.maliceAbilities[args.id] = args
end

function MonsterAI:RegisterVillainAction(args)
    args.category = "Villain Actions"
    self.villainActions[args.id] = args
end

function MonsterAI:RegisterPrompt(args)
    for _,prompt in ipairs(args.prompts) do
        self.prompts[prompt] = args
    end
end

function MonsterAI:RegisterTrigger(args)
    for _,guid in ipairs(args.abilityGuids or {}) do
        self.triggerHandlersByGuid[guid] = args
    end

    for _,abilityName in ipairs(args.abilities or {}) do
        if args.monsters ~= nil then
            for _,monsterType in ipairs(args.monsters) do
                local qualifiedName = string.format("%s:%s", monsterType, abilityName)
                self.triggerHandlersByMonsterAbility[qualifiedName] = args
            end
        else
            self.triggerHandlersByAbility[abilityName] = args
        end
    end

    for _,triggerText in ipairs(args.triggers or {}) do
        if args.monsters ~= nil then
            for _,monsterType in ipairs(args.monsters) do
                local qualifiedText = string.format("%s:%s", monsterType, triggerText)
                self.triggerHandlersByMonsterText[qualifiedText] = args
            end
        else
            self.triggerHandlersByText[triggerText] = args
        end
    end
end

function MonsterAI:RegisterTactic(args)
    args.category = "Tactics"
    self.tactics[args.id] = args
end

--- /testai support: drive the AI machinery for a single named ability on the
--- selected token, without needing an active combat or the AI thread running.

local function TestAIMessage(message)
    print("AI TEST::", message)
    chat.Send("/testai: " .. message)
end

--grant whatever the token is missing to pay for the ability: malice or other
--global pools, action/maneuver/triggered action usage, per-ability charges.
--Returns a list of human readable descriptions of what was granted.
local function TestAIGrantResources(token, ability)
    local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
    local grantedQuantities = {}
    local grantedNames = {}

    for attempt=1,3 do
        local cost = ability:GetCost(token)
        if cost.canAfford then
            break
        end

        local resourcesAvailable = token.properties:GetResources()
        local globalGrants = {}
        local creatureGrants = {}

        for _,detail in ipairs(cost.details or {}) do
            if detail.canAfford == false and detail.cost ~= nil then
                local resourceInfo = resourcesTable[detail.cost]
                local refreshType = detail.refreshType
                if refreshType == nil and resourceInfo ~= nil then
                    refreshType = resourceInfo.usageLimit
                end

                if refreshType ~= nil and refreshType ~= "none" then
                    local max
                    if refreshType == "global" then
                        max = CharacterResource.GetGlobalResource(detail.cost)
                    else
                        max = resourcesAvailable[detail.cost] or 0
                    end
                    if detail.maxCharges ~= nil then
                        max = detail.maxCharges
                    end

                    local usage = token.properties:GetResourceUsage(detail.cost, refreshType)
                    local needed = (detail.quantity or 1) - (max - usage)
                    if needed > 0 then
                        local grant = {
                            resourceid = detail.cost,
                            refreshType = refreshType,
                            quantity = needed,
                        }
                        if resourceInfo ~= nil then
                            grant.name = resourceInfo.name
                        else
                            grant.name = "charges of " .. ability.name
                        end
                        if refreshType == "global" then
                            globalGrants[#globalGrants+1] = grant
                        else
                            creatureGrants[#creatureGrants+1] = grant
                        end
                    end
                end
            end
        end

        if #globalGrants == 0 and #creatureGrants == 0 then
            break
        end

        local function RecordGrant(grant)
            if grantedQuantities[grant.name] == nil then
                grantedNames[#grantedNames+1] = grant.name
            end
            grantedQuantities[grant.name] = (grantedQuantities[grant.name] or 0) + grant.quantity
        end

        for _,grant in ipairs(globalGrants) do
            CharacterResource.SetGlobalResource(grant.resourceid, CharacterResource.GetGlobalResource(grant.resourceid) + grant.quantity, "/testai grant")
            RecordGrant(grant)
        end

        if #creatureGrants > 0 then
            token:ModifyProperties{
                description = "Grant resources for /testai",
                undoable = false,
                execute = function()
                    for _,grant in ipairs(creatureGrants) do
                        token.properties:RefreshResource(grant.resourceid, grant.refreshType, grant.quantity, "/testai grant")
                    end
                end,
            }
            for _,grant in ipairs(creatureGrants) do
                RecordGrant(grant)
            end
        end

        --GetResources() is cached per game-update tick, so a same-frame
        --re-check of GetCost would not see grants that raised a pool
        --(e.g. the villain action budget). Bust the cache before re-checking.
        token.properties:InvalidateResources()
    end

    local granted = {}
    for _,name in ipairs(grantedNames) do
        granted[#granted+1] = string.format("%d %s", grantedQuantities[name], name)
    end
    return granted
end

--out of combat there is no initiative queue to enumerate combatants from, so
--treat every live token on the map as a combatant instead.
local function TestAISetupOutOfCombat(ai, token)
    ai.token = token
    ai.abilities = token.properties:GetActivatedAbilities()
    ai.enemyTokens = {}
    ai.allyTokens = {}
    ai.activeTactics = {}

    for id,tactic in pairs(ai.tactics) do
        if MonsterAI.MoveMatchesMonster(token, tactic) then
            ai.activeTactics[id] = tactic
        end
    end

    for _,other in ipairs(dmhub.allTokens) do
        if other.valid and other.properties ~= nil and not other.properties:IsDead() then
            if dmhub.TokensAreFriendly(token, other) then
                ai.allyTokens[#ai.allyTokens+1] = other
            else
                ai.enemyTokens[#ai.enemyTokens+1] = other
            end
        end
    end
end

local function TestAIExecuteSquadStrike(ai, token, ability)
    local squadid = token.properties:MinionSquad()
    ai.squadMembers = {}
    ai.squadCaptain = false
    if squadid == nil then
        ai.squadMembers[1] = {token = token}
    else
        for _,other in ipairs(dmhub.allTokens) do
            if other.valid and other.properties ~= nil and (not other.properties:IsDead())
                and other.properties:MinionSquad() == squadid then
                if other.properties.minion then
                    ai.squadMembers[#ai.squadMembers+1] = {token = other}
                elseif not ai.squadCaptain then
                    ai.squadCaptain = other
                end
            end
        end
    end

    local controls = {}
    for _,member in ipairs(ai.squadMembers) do
        controls[#controls+1] = {token = member.token, info = ai:BeginTokenControl(member.token)}
    end

    local struck = false
    local ok, err = RunYieldingFunction(function()
        struck = ai:ExecuteSquadStrike(ability)
    end)

    for _,control in ipairs(controls) do
        ai:EndTokenControl(control.token, control.info)
    end
    ai._tmp_expectedPromptTarget = nil

    if not ok then
        TestAIMessage(string.format("squad strike with \"%s\" failed: %s", ability.name, tostring(err)))
    elseif not struck then
        TestAIMessage(string.format("the squad could not find any targets for \"%s\".", ability.name))
    end
end

--used when no registered AI move covers the ability: position with the
--generic strike/burst logic and cast, mirroring the generic fallback moves.
local function TestAIExecuteGeneric(ai, token, ability)
    local ok, err = ai:RunWithTokenControl(token, function()
        if ability.targetType == "all" then
            local loc, score = ai:FindBestMoveToUseBurst(token, ability, function(targetToken)
                if targetToken:IsFriend(token) then
                    return -1
                end
                return 1
            end)
            if loc ~= nil and (score or 0) > 0 then
                token:Move(loc, {maxCost = 10000, ignoreFalling = false})
                ai.Sleep(0.5)
            end
            ai:ExecuteAbility(token, ability)
        elseif ability.targetType == "target" then
            local loc = ai:FindBestMoveToUseStrike(token, ability)
            if loc == nil then
                TestAIMessage(string.format("could not find any position to use \"%s\" from.", ability.name))
                return
            end

            token:Move(loc, {maxCost = 10000, ignoreFalling = false})
            ai.Sleep(0.5)

            local targets = ai:FindValidTargetsOfStrike(token, ability, loc)
            ai:ExecuteAbility(token, ability, targets)
        else
            --self, map, line, cube, emptyspace, etc: cast in place and let
            --any location prompts fall through to the DM to resolve.
            ai:ExecuteAbility(token, ability)
        end
    end)

    if not ok then
        TestAIMessage(string.format("generic execution of \"%s\" failed: %s", ability.name, tostring(err)))
    end
end

Commands.RegisterMacro{
    name = "testai",
    summary = "test the AI with one ability",
    doc = "Usage: /testai <ability name>\nMakes the Monster AI use the named ability, maneuver, or villain action with the selected token. Works in or out of combat and whether or not the AI is running. Grants any resources needed to execute (malice, actions, maneuvers, the villain action budget and used state, ability charges). Uses the registered AI move for the ability when one exists (even if disabled in the panel); otherwise falls back to a generic strike/burst execution. Minion signature abilities execute as a squad strike. Note: a villain action cast this way is marked used for the encounter by the normal cast pipeline.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        local tokens = dmhub.selectedTokens
        if tokens == nil or #tokens == 0 then
            return result
        end
        local token = tokens[1]
        if token.properties == nil then
            return result
        end
        local abilities = nil
        pcall(function() abilities = token.properties:GetActivatedAbilities() end)
        for _,ability in ipairs(abilities or {}) do
            local summary = ability:try_get("villainAction")
            if summary == nil then
                summary = cond(ability.categorization ~= "none", ability.categorization, "ability")
            end
            result[#result+1] = {text = ability.name, summary = summary}
        end
        table.sort(result, function(a, b) return a.text < b.text end)
        return result
    end,
    command = function(str)
        if not dmhub.isDM then
            print("/testai: DM only.")
            return
        end

        local name = trim(str or "")
        if string.sub(name, 1, 1) == "\"" and string.sub(name, -1) == "\"" and #name >= 2 then
            name = trim(string.sub(name, 2, #name - 1))
        end
        if name == "" then
            TestAIMessage("usage: /testai <ability name>")
            return
        end

        local tokens = dmhub.selectedTokens
        if tokens == nil or #tokens == 0 then
            TestAIMessage("select a token first.")
            return
        end

        local token = tokens[1]
        if token.properties == nil then
            TestAIMessage("the selected token has no creature properties.")
            return
        end

        local tokenName = token.name
        if tokenName == nil or tokenName == "" then
            tokenName = token.properties:try_get("monster_type", "The selected token")
        end

        local abilities = nil
        pcall(function() abilities = token.properties:GetActivatedAbilities() end)
        abilities = abilities or {}

        local ability = nil
        for _,a in ipairs(abilities) do
            if string.lower(a.name) == string.lower(name) then
                ability = a
                break
            end
        end

        if ability == nil then
            TestAIMessage(string.format("%s has no ability, maneuver, or villain action named \"%s\".", tokenName, name))
            return
        end

        local granted = TestAIGrantResources(token, ability)
        if #granted > 0 then
            TestAIMessage(string.format("granted %s to %s.", table.concat(granted, ", "), tokenName))
        end

        if not ability:CanAfford(token) then
            --diagnose exactly which cost components are still short.
            local cost = ability:GetCost(token)
            local missing = {}
            local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
            for _,detail in ipairs(cost.details or {}) do
                if detail.canAfford == false and detail.cost ~= nil then
                    local rname = detail.cost
                    local rinfo = resourcesTable[detail.cost]
                    if rinfo ~= nil then
                        rname = rinfo.name
                    end
                    missing[#missing+1] = string.format("%s x%s", rname, tostring(detail.quantity or 1))
                end
            end
            if cost.cannotMove then
                missing[#missing+1] = "movement"
            end
            if cost.outOfAmmo then
                missing[#missing+1] = "ammo"
            end
            local missingText = ""
            if #missing > 0 then
                missingText = " Missing: " .. table.concat(missing, ", ") .. "."
            end
            TestAIMessage(string.format("%s still cannot afford \"%s\" even after granting resources; aborting.%s", tokenName, ability.name, missingText))
            return
        end

        local ai = MonsterAI.new{}
        --instance-level flag: this one-shot run is active even when the AI thread is not.
        ai.active = true

        dmhub.Coroutine(function()
            local queue = dmhub.initiativeQueue
            if queue ~= nil and queue.hidden then
                queue = nil
            end

            if queue ~= nil then
                ai:SetupCombatants(token, queue)
            else
                TestAISetupOutOfCombat(ai, token)
            end

            ai.log.analysis = ai:Analysis()
            ai.log.updatedAnalysis = dmhub.GenerateGuid()

            ai.paths = token:CalculatePathfindingArea((token.properties:CurrentMovementSpeed() - token.properties:DistanceMovedThisTurn())*10, {})

            --minion signature abilities execute as a squad strike, like the AI turn loop does.
            if token.properties.minion and ability.categorization == "Signature Ability" then
                TestAIMessage(string.format("%s: executing \"%s\" as a squad strike.", tokenName, ability.name))
                TestAIExecuteSquadStrike(ai, token, ability)
                ai:WaitForAbilityIdle()
                return
            end

            local villainSlot = ability:try_get("villainAction")
            local context = nil
            if villainSlot ~= nil then
                local round = nil
                if queue ~= nil then
                    round = queue.round
                end
                round = round or tonumber(string.match(villainSlot, "%d+")) or 1
                context = {
                    initiativeQueue = queue,
                    endedInitiativeId = nil,
                    round = round,
                }

                --clear the used flag and make sure the shared villain action
                --budget is available so the cast pipeline can consume it normally.
                pcall(function()
                    VillainActionState.ClearUsed(token.charid, villainSlot)
                    if CharacterResource.GetVillainActions() <= 0 then
                        CharacterResource.SetVillainActions(1, "/testai grant")
                    end
                end)
            end

            local candidates = {}
            local lowerName = string.lower(ability.name)

            if villainSlot ~= nil then
                for _,action in pairs(ai.villainActions) do
                    if MonsterAI.MoveMatchesMonster(token, action, true) and action.abilities ~= nil
                        and action.abilities[1] ~= nil and string.lower(action.abilities[1]) == lowerName then
                        candidates[#candidates+1] = {move = action, usingAbilities = {ability}, isVillainAction = true}
                    end
                end
            else
                for _,move in pairs(ai.moves) do
                    local usesAbility = false
                    if MonsterAI.MoveMatchesMonster(token, move, true) and move.abilities ~= nil then
                        for i=1,#move.abilities do
                            if string.lower(move.abilities[i]) == lowerName then
                                usesAbility = true
                                break
                            end
                        end
                    end

                    if usesAbility then
                        --like FindAndExecuteMove, every ability the move lists must be
                        --present and affordable -- but grant resources to any that fall short.
                        local usingAbilities = {}
                        for i=1,#move.abilities do
                            local moveAbility = FindAbilityByName(ai.abilities, move.abilities[i])
                            if moveAbility ~= nil and not moveAbility:CanAfford(token) then
                                local comboGranted = TestAIGrantResources(token, moveAbility)
                                if #comboGranted > 0 then
                                    TestAIMessage(string.format("granted %s to %s for \"%s\".", table.concat(comboGranted, ", "), tokenName, moveAbility.name))
                                end
                            end
                            if moveAbility == nil or not moveAbility:CanAfford(token) then
                                usingAbilities = nil
                                break
                            end
                            usingAbilities[#usingAbilities+1] = moveAbility
                        end

                        if usingAbilities ~= nil then
                            candidates[#candidates+1] = {move = move, usingAbilities = usingAbilities}
                        end
                    end
                end
            end

            local best = nil
            for _,candidate in ipairs(candidates) do
                local move = candidate.move
                local ok, scoringInfo
                if candidate.isVillainAction then
                    ok, scoringInfo = pcall(move.score, move, ai, token, candidate.usingAbilities[1], context)
                else
                    ok, scoringInfo = pcall(move.score, move, ai, token, candidate.usingAbilities[1], candidate.usingAbilities[2], candidate.usingAbilities[3])
                end

                if not ok then
                    TestAIMessage(string.format("scoring of AI move \"%s\" failed: %s", move.id, tostring(scoringInfo)))
                elseif scoringInfo ~= nil then
                    if type(scoringInfo) == "number" then
                        scoringInfo = {score = scoringInfo}
                    end
                    if type(scoringInfo) == "table" and type(scoringInfo.score) == "number" then
                        candidate.scoringInfo = scoringInfo
                        if best == nil or scoringInfo.score > best.scoringInfo.score then
                            best = candidate
                        end
                    end
                end
            end

            if best ~= nil then
                local move = best.move
                TestAIMessage(string.format("%s: executing AI move \"%s\" (score %.2f).", tokenName, move.id, best.scoringInfo.score))
                local ok, err = ai:RunWithTokenControl(token, function()
                    if best.isVillainAction then
                        move.execute(move, ai, token, best.scoringInfo, best.usingAbilities[1], context)
                    else
                        move.execute(move, ai, token, best.scoringInfo, best.usingAbilities[1], best.usingAbilities[2], best.usingAbilities[3])
                    end
                end)
                ai:WaitForAbilityIdle()
                if not ok then
                    TestAIMessage(string.format("execution of AI move \"%s\" failed: %s", move.id, tostring(err)))
                end
                return
            end

            if #candidates > 0 then
                TestAIMessage(string.format("the AI declined to use \"%s\" right now (no registered move found a valid opportunity).", ability.name))
                return
            end

            TestAIMessage(string.format("%s: no AI move is registered for \"%s\"; using generic execution.", tokenName, ability.name))
            TestAIExecuteGeneric(ai, token, ability)
            ai:WaitForAbilityIdle()
        end)
    end,
}
