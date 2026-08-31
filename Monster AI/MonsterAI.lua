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
MonsterAI.deferredTriggerLog = {}
MonsterAI.paths = false
MonsterAI.log = {}
MonsterAI.active = false
MonsterAI.maliceAbilityMinimumScore = 0.65
MonsterAI.areaTelegraphBlinks = 3
MonsterAI.areaTelegraphOnTime = 0.35
MonsterAI.areaTelegraphOffTime = 0.15

MonsterAI.activeTactics = {}

local g_aiLogFieldOrder = {
    "turn",
    "round",
    "cycle",
    "actor",
    "actorId",
    "monster",
    "category",
    "move",
    "ability",
    "action",
    "prompt",
    "trigger",
    "score",
    "threshold",
    "reason",
    "plan",
    "from",
    "to",
    "targets",
    "result",
    "duration",
}

local g_aiLogCategoryNames = {
    ["Main Actions"] = "Main Action",
    ["Basic Strikes"] = "Basic Strike",
    ["Maneuvers"] = "Maneuver",
    ["Malice Abilities"] = "Malice Ability",
    ["Villain Actions"] = "Villain Action",
    ["Tactics"] = "Tactic",
}

local function AILogText(value)
    local result = tostring(value or "")
    result = string.gsub(result, "[\r\n\t]+", " ")
    result = string.gsub(result, "|", "/")
    result = string.gsub(result, '"', '\\"')
    return result
end

local function AILogValue(value)
    if type(value) == "number" then
        if value == math.floor(value) then
            return tostring(value)
        end
        return string.format("%.3f", value)
    elseif type(value) == "boolean" then
        return tostring(value)
    end
    return string.format('"%s"', AILogText(value))
end

function MonsterAI.TokenLogName(token)
    if token == nil then
        return "none"
    end

    local result = nil
    pcall(function()
        result = creature.GetTokenDescription(token)
    end)
    if result == nil or result == "" then
        result = token.charid or "unknown token"
    end
    return AILogText(result)
end

function MonsterAI.LocLogName(loc)
    if loc == nil then
        return "none"
    end

    local result = nil
    pcall(function()
        result = string.format("(%d,%d,%d)", loc.x, loc.y, loc.altitude or 0)
    end)
    return result or "unknown location"
end

function MonsterAI.TargetsLogName(targets)
    local result = {}
    for _,targetInfo in ipairs(targets or {}) do
        local token = nil
        local loc = nil
        pcall(function()
            token = targetInfo.token
            loc = targetInfo.loc
        end)
        if token == nil then
            local charid = nil
            pcall(function() charid = targetInfo.charid end)
            if charid ~= nil then
                token = targetInfo
            end
        end

        if token ~= nil and token.charid ~= nil then
            result[#result+1] = string.format("%s [%s]",
                MonsterAI.TokenLogName(token), AILogText(token.charid))
        elseif loc ~= nil then
            result[#result+1] = MonsterAI.LocLogName(loc)
        end
    end
    if #result == 0 then
        return "none"
    end
    return table.concat(result, ", ")
end

function MonsterAI.TargetScoresLogName(targets)
    local result = {}
    for _,targetInfo in ipairs(targets or {}) do
        if targetInfo.token ~= nil then
            local detail = string.format("%s edges=%s",
                MonsterAI.TokenLogName(targetInfo.token), tostring(targetInfo.edges or 0))
            if targetInfo.edgeReasons ~= nil and #targetInfo.edgeReasons > 0 then
                detail = detail .. " [" .. table.concat(targetInfo.edgeReasons, ", ") .. "]"
            end
            result[#result+1] = detail
        end
    end
    if #result == 0 then
        return "none"
    end
    return table.concat(result, "; ")
end

function MonsterAI.AbilitiesLogName(abilities)
    local result = {}
    for _,ability in ipairs(abilities or {}) do
        local abilityName = nil
        if type(ability) == "string" then
            abilityName = ability
        else
            pcall(function() abilityName = ability.name end)
        end
        result[#result+1] = AILogText(abilityName or ability)
    end
    if #result == 0 then
        return "none"
    end
    return table.concat(result, ", ")
end

function MonsterAI.AbilityActionLogName(ability)
    if ability == nil then
        return "Unknown Action"
    end
    if ability:try_get("villainAction") ~= nil or ability.categorization == "Villain Action" then
        return "Villain Action"
    end

    local resourceid = ability:ActionResource()
    if resourceid == CharacterResource.actionResourceId then
        return "Main Action"
    elseif resourceid == CharacterResource.maneuverResourceId then
        return "Maneuver"
    elseif resourceid == CharacterResource.freeManeuverResourceId then
        return "Free Maneuver"
    elseif resourceid == CharacterResource.triggerResourceId then
        return "Triggered Action"
    elseif resourceid == CharacterResource.villainActionId then
        return "Villain Action"
    elseif ability.categorization == "Malice" then
        return "Malice Ability"
    elseif ability.categorization == "Move" then
        return "Move"
    elseif resourceid == nil then
        return "Free Action"
    end

    local resources = dmhub.GetTable(CharacterResource.tableName) or {}
    local resourceInfo = resources[resourceid]
    if resourceInfo ~= nil and resourceInfo.name ~= nil then
        return resourceInfo.name
    end
    return string.format("Other Action (%s)", tostring(resourceid))
end

function MonsterAI.AbilityActionsLogName(abilities)
    local result = {}
    local seen = {}
    for _,ability in ipairs(abilities or {}) do
        local name = MonsterAI.AbilityActionLogName(ability)
        if not seen[name] then
            seen[name] = true
            result[#result+1] = name
        end
    end
    if #result == 0 then
        return "No Ability Action"
    end
    return table.concat(result, ", ")
end

function MonsterAI.MoveCategoryLogName(move)
    if move == nil then
        return "Unknown Move"
    end
    return g_aiLogCategoryNames[move.category] or move.category or "Main Action"
end

function MonsterAI.ScoringPlanLogName(scoringInfo)
    if type(scoringInfo) ~= "table" then
        return "none"
    end

    local result = {}
    if scoringInfo.loc ~= nil then
        result[#result+1] = "move-to " .. MonsterAI.LocLogName(scoringInfo.loc)
    end
    if scoringInfo.targetLoc ~= nil then
        result[#result+1] = "aim-at " .. MonsterAI.LocLogName(scoringInfo.targetLoc)
    elseif scoringInfo.center ~= nil then
        result[#result+1] = "center-on " .. MonsterAI.LocLogName(scoringInfo.center)
    end
    if scoringInfo.targets ~= nil then
        result[#result+1] = "targets " .. MonsterAI.TargetsLogName(scoringInfo.targets)
    end
    if scoringInfo.enemies ~= nil or scoringInfo.allies ~= nil then
        result[#result+1] = string.format("enemies=%s allies=%s",
            tostring(scoringInfo.enemies or 0), tostring(scoringInfo.allies or 0))
    end
    if scoringInfo.mode ~= nil then
        result[#result+1] = "mode=" .. tostring(scoringInfo.mode)
    end
    if scoringInfo.reason ~= nil then
        result[#result+1] = AILogText(scoringInfo.reason)
    end
    if #result == 0 then
        return "no additional plan details"
    end
    return table.concat(result, "; ")
end

function MonsterAI:LogDecision(event, fields)
    fields = fields or {}
    local values = {}
    local context = self:try_get("_tmp_aiLogContext") or {}
    for key,value in pairs(context) do
        values[key] = value
    end
    for key,value in pairs(fields) do
        values[key] = value
    end

    local parts = {"AI:: " .. event}
    local written = {}
    for _,key in ipairs(g_aiLogFieldOrder) do
        if values[key] ~= nil then
            parts[#parts+1] = string.format("%s=%s", key, AILogValue(values[key]))
            written[key] = true
        end
    end

    local remaining = {}
    for key,_ in pairs(values) do
        if not written[key] then
            remaining[#remaining+1] = key
        end
    end
    table.sort(remaining)
    for _,key in ipairs(remaining) do
        parts[#parts+1] = string.format("%s=%s", key, AILogValue(values[key]))
    end

    print(table.concat(parts, " | "))
end

function MonsterAI:SetLogContext(token, fields)
    local context = {}
    for key,value in pairs(fields or {}) do
        context[key] = value
    end
    if token ~= nil then
        context.actor = self.TokenLogName(token)
        context.actorId = token.charid
        if token.properties ~= nil then
            context.monster = token.properties:try_get("monster_type", "")
        end
    end
    self._tmp_aiLogContext = context
end

function MonsterAI:SetMoveLogContext(token, move)
    local context = {}
    for key,value in pairs(self:try_get("_tmp_aiLogContext") or {}) do
        context[key] = value
    end
    context.category = self.MoveCategoryLogName(move)
    context.move = move ~= nil and move.id or nil
    self:SetLogContext(token, context)
end

local function AIAbilityUnavailableReason(token, ability)
    local cost = ability:GetCost(token)
    local unavailable = {}
    local resources = dmhub.GetTable(CharacterResource.tableName) or {}
    for _,detail in ipairs(cost.details or {}) do
        if detail.canAfford == false then
            local resourceInfo = resources[detail.cost]
            local resourceName = resourceInfo ~= nil and resourceInfo.name or detail.cost or "resource"
            unavailable[#unavailable+1] = string.format("%s x%s",
                tostring(resourceName), tostring(detail.quantity or 1))
        end
    end
    if #unavailable > 0 then
        return "cannot afford " .. table.concat(unavailable, ", ")
    end
    return "ability:CanAfford returned false"
end

creature._tmp_ai_aidAttack = false

Commands.RegisterMacro{
    name = "playai",
    summary = "play AI turn",
    doc = "Usage: /playai\nPlays an AI turn for the current initiative entry. Requires an active initiative queue.",
    command = function(str)

        local ai = MonsterAI.new{}
        local queue = dmhub.initiativeQueue
        if queue == nil or queue.hidden then
            ai:LogDecision("TURN ABORTED", {reason = "no initiative queue is active"})
            return
        end

        local initiativeid = dmhub.initiativeQueue:CurrentInitiativeId()
        if not initiativeid then
            ai:LogDecision("TURN ABORTED", {reason = "initiative queue has no current entry"})
            return
        end

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

-- A mounted rider plans and performs ordinary AI movement with the creature
-- carrying it. The rider remains the caster for every ability and target test.
function MonsterAI:GetMovementToken(token)
    if token == nil or not token.valid then
        return token
    end

    local movementToken = token.selfOrMount
    if movementToken ~= nil and movementToken.valid then
        return movementToken
    end

    return token
end

function MonsterAI:CalculateMovementPaths(token, movementAllowanceDecis, flags)
    local movementToken = self:GetMovementToken(token)
    return movementToken:CalculatePathfindingArea(movementAllowanceDecis, flags or {})
end

function MonsterAI:CalculateRemainingMovementPaths(token, flags)
    local movementToken = self:GetMovementToken(token)
    local remainingMovement = math.max(0,
        movementToken.properties:CurrentMovementSpeed()
        - movementToken.properties:DistanceMovedThisTurn())
    return self:CalculateMovementPaths(token, remainingMovement*10, flags)
end

function MonsterAI:MoveToken(token, loc, options)
    local movementToken = self:GetMovementToken(token)
    local fromLoc = movementToken ~= nil and movementToken.loc or nil
    self:LogDecision("MOVEMENT START", {
        actor = self.TokenLogName(token),
        actorId = token ~= nil and token.charid or nil,
        from = self.LocLogName(fromLoc),
        to = self.LocLogName(loc),
        movementToken = movementToken ~= token and self.TokenLogName(movementToken) or nil,
        freeMovement = options ~= nil and options.freeMovement == true or nil,
    })
    local result = movementToken:Move(loc, options)
    self:LogDecision("MOVEMENT ISSUED", {
        actor = self.TokenLogName(token),
        actorId = token ~= nil and token.charid or nil,
        from = self.LocLogName(fromLoc),
        to = self.LocLogName(loc),
        result = result ~= nil and "path accepted" or "no path returned",
    })
    return result
end

function MonsterAI:ExecuteWithTheoreticalMovementLoc(token, loc, fn)
    local movementToken = self:GetMovementToken(token)
    return movementToken:ExecuteWithTheoreticalLoc(loc, fn)
end

function MonsterAI:MovementTokenIsAtLoc(token, loc)
    local movementToken = self:GetMovementToken(token)
    return loc ~= nil and movementToken.loc.str == loc.str
end

local function OrderMountedRidersFirst(tokens)
    local tokensById = {}
    local ridersByMountId = {}
    for _,token in ipairs(tokens) do
        tokensById[token.charid] = token
    end

    for _,token in ipairs(tokens) do
        local mountId = token.mountedOn
        if mountId ~= nil and tokensById[mountId] ~= nil then
            ridersByMountId[mountId] = ridersByMountId[mountId] or {}
            ridersByMountId[mountId][#ridersByMountId[mountId]+1] = token
        end
    end

    local result = {}
    local emitted = {}
    local visiting = {}
    local function EmitToken(token)
        if emitted[token.charid] or visiting[token.charid] then
            return
        end

        visiting[token.charid] = true
        for _,rider in ipairs(ridersByMountId[token.charid] or {}) do
            EmitToken(rider)
        end
        visiting[token.charid] = nil
        emitted[token.charid] = true
        result[#result+1] = token
    end

    for _,token in ipairs(tokens) do
        EmitToken(token)
    end

    return result
end

-- Choose the leader for a shared initiative. Non-minions outrank minions,
-- squad captains outrank other non-minions, and EV breaks remaining ties.
function MonsterAI:FindMostSeniorInitiativeGroupMember(tokens)
    local best = nil
    local bestNonMinion = false
    local bestCaptain = false
    local bestEV = -math.huge

    for _,token in ipairs(tokens or {}) do
        if token ~= nil and token.valid and token.properties ~= nil
            and not token.properties:IsDead() then
            local nonMinion = not token.properties.minion
            local captain = nonMinion and token.properties:MinionSquad() ~= nil
            local ev = token.properties:EV()
            if best == nil
                or (nonMinion and not bestNonMinion)
                or (nonMinion == bestNonMinion and captain and not bestCaptain)
                or (nonMinion == bestNonMinion and captain == bestCaptain and ev > bestEV) then
                best = token
                bestNonMinion = nonMinion
                bestCaptain = captain
                bestEV = ev
            end
        end
    end

    return best
end

function MonsterAI:TelegraphAreaAbility(ability, area, symbols)
    local label = ability.name or "Area Ability"
    if symbols ~= nil and symbols.spellname ~= nil then
        label = symbols.spellname
    end

    for i = 1, self.areaTelegraphBlinks do
        local marker = area:Mark{
            color = "white",
            video = "divinationline.webm",
            label = label,
        }
        self.Sleep(self.areaTelegraphOnTime)
        marker:Destroy()
        self.Sleep(self.areaTelegraphOffTime)
    end
end

function MonsterAI:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
    local invokerMonsterType = invokerToken.properties:try_get("monster_type", "")
    self:LogDecision("PROMPT RECEIVED", {
        actor = self.TokenLogName(casterToken),
        actorId = casterToken ~= nil and casterToken.charid or nil,
        ability = abilityClone.name,
        prompt = string.format("%s:%s", invokerMonsterType, abilityClone.name),
        invoker = self.TokenLogName(invokerToken),
    })

    --the ability directly inserted the expected targets.
    local expectedEntry = self:try_get("_tmp_expectedPromptTarget")
    if expectedEntry ~= nil and expectedEntry.casterid == invokerToken.charid then
        self._tmp_expectedPromptTarget = nil

        --The expected targets were chosen for the position the caster PLANNED
        --to reach; if the preceding movement stopped short (collision, blocked
        --path), some may now be out of range and striking them would violate
        --the rules. Keep only targets legal from the caster's actual position.
        --If none remain, fall through to the registered prompt handler / DM.
        local targets = {}
        local range = abilityClone:GetRange(casterToken.properties)
        for _,target in ipairs(expectedEntry.targets or {}) do
            if target.token == nil or casterToken:Distance(target.token) <= range then
                targets[#targets+1] = target
            else
                self:LogDecision("PROMPT TARGET REJECTED", {
                    ability = abilityClone.name,
                    targets = self.TargetsLogName({target}),
                    reason = "planned target is now out of range",
                })
            end
        end

        if #targets > 0 then
            --line-of-sight rays so viewers can see who is being struck, the
            --same feedback ExecuteAbility draws for direct casts. The prompt
            --path has no cast-finished hook, so clean them up on a timer.
            local rays = {}
            for _,target in ipairs(targets) do
                if target.token ~= nil then
                    rays[#rays+1] = dmhub.MarkLineOfSight(casterToken, target.token, casterToken.properties:GetPierceWalls())
                end
            end
            if #rays > 0 then
                dmhub.Schedule(6, function()
                    for _,ray in ipairs(rays) do
                        ray:DestroyLineOfSight()
                    end
                end)
            end

            if expectedEntry.sleep then
                self.Sleep(expectedEntry.sleep)
            end
            options.targets = targets
            self:LogDecision("PROMPT RESOLVED", {
                ability = abilityClone.name,
                prompt = "expected targets",
                targets = self.TargetsLogName(targets),
                result = "automatic",
            })
            return "inherit"
        end
    end

    --try_get: the invoker can be an object token (e.g. a wall voxel
    --prompting for a target near it), whose TargetableObject
    --properties have no monster_type field.
    local qualifiedPrompt = string.format("%s:%s", invokerMonsterType, abilityClone.name)
    local handler = self.prompts[abilityClone.name] or self.prompts[qualifiedPrompt]
    if handler ~= nil then
        local result = handler.handler(self, invokerToken, casterToken, abilityClone, symbols, options)
        if result ~= nil then
            for k,v in pairs(result) do
                options[k] = v
            end

            self:LogDecision("PROMPT RESOLVED", {
                ability = abilityClone.name,
                prompt = handler.id or qualifiedPrompt,
                targets = self.TargetsLogName(result.targets),
                result = result.abilityOverride ~= nil
                    and string.format("automatic with ability %s", result.abilityOverride.name)
                    or "automatic",
            })
            return "inherit"
        end

        self:LogDecision("PROMPT DEFERRED", {
            ability = abilityClone.name,
            prompt = handler.id or qualifiedPrompt,
            reason = "registered handler returned no automatic choice",
            result = "Director prompt",
        })
    else
        self:LogDecision("PROMPT DEFERRED", {
            ability = abilityClone.name,
            prompt = qualifiedPrompt,
            reason = "no registered AI prompt handler",
            result = "Director prompt",
        })
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
    self:SetLogContext(token)
    local triggerText = triggerInfo:GetText()
    local triggerLogKey = string.format("%s:%s", token.charid, tostring(triggerInfo.id))
    self:LogDecision("TRIGGER CONSIDERED", {
        category = "Triggered Action",
        move = registeredTrigger.id,
        ability = triggerInfo.abilityName,
        trigger = triggerText,
    })
    local decision = registeredTrigger.handler(self, token, triggerInfo)
    if decision == true then
        decision = {activate = true}
    end

    if type(decision) ~= "table" or (not decision.activate and not decision.dismiss) then
        if not self.deferredTriggerLog[triggerLogKey] then
            self.deferredTriggerLog[triggerLogKey] = true
            self:LogDecision("TRIGGER DEFERRED", {
                category = "Triggered Action",
                move = registeredTrigger.id,
                ability = triggerInfo.abilityName,
                trigger = triggerText,
                reason = "handler returned no activate or dismiss decision",
                result = "Director decision",
            })
        end
        return false
    end
    self.deferredTriggerLog[triggerLogKey] = nil

    self:LogDecision("TRIGGER DECIDED", {
        category = "Triggered Action",
        move = registeredTrigger.id,
        ability = triggerInfo.abilityName,
        trigger = triggerText,
        targets = decision.expectedPrompt ~= nil
            and self.TargetsLogName(decision.expectedPrompt.targets) or nil,
        result = decision.dismiss and "dismiss" or "activate",
        mode = decision.mode,
    })

    if decision.expectedPrompt ~= nil then
        local expectedPrompt = table.shallow_copy(decision.expectedPrompt)
        expectedPrompt.casterid = expectedPrompt.casterid or token.charid
        self:SetTargetsForExpectedPrompt(expectedPrompt)
    end

    local controlInfo = self:BeginTokenControl(token)
    local startedAt = dmhub.Time()

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
    self:LogDecision("TRIGGER FINISHED", {
        category = "Triggered Action",
        move = registeredTrigger.id,
        ability = triggerInfo.abilityName,
        trigger = triggerText,
        result = decision.dismiss and "dismissed" or "activated",
        duration = dmhub.Time() - startedAt,
    })
    return true
end

function MonsterAI:PlayTurn(initiativeid)
    dmhub.Coroutine(function()
        --Everything a turn does -- moving monsters, casting their abilities --
        --is the HOST acting, not the user playing, so run the whole turn with
        --host permissions. On a player host (Encounter of the Week) this is
        --what keeps player rules enforcement from binding the AI; the engine
        --parks the elevation whenever this coroutine yields, so the user still
        --sees player vision and player UI throughout.
        ElevateToHostPermissions()
        self:PlayTurnCoroutine(initiativeid)
        DropHostPermissions()
    end)
end

function MonsterAI:PlayTurnCoroutine(initiativeid)
    local queue = dmhub.initiativeQueue

    self.log.analysis = self:Analysis()

    if queue ~= nil and (not queue.hidden) and initiativeid == queue:CurrentInitiativeId() then

        local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
        tokens = OrderMountedRidersFirst(tokens or {})
        local turnTargets = {}
        for _,turnToken in ipairs(tokens) do
            turnTargets[#turnTargets+1] = {token = turnToken}
        end
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })
        self:LogDecision("TURN START", {
            targets = self.TargetsLogName(turnTargets),
            tokenCount = #tokens,
        })

        self:HandleMaliceAbilityStartOfTurn(initiativeid, tokens, queue)
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })

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
                        self:SetLogContext(token, {
                            turn = initiativeid,
                            round = queue.round,
                        })
                        self:LogDecision("ACTOR SKIPPED", {
                            reason = "minion squad was already processed by an earlier member",
                        })
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
                self:SetLogContext(token, {
                    turn = initiativeid,
                    round = queue.round,
                })
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
                self._tmp_synthesizedAbilitiesUsed = {}

                local tacticNames = table.keys(self.activeTactics)
                table.sort(tacticNames)
                self:LogDecision("ACTOR START", {
                    abilities = self.AbilitiesLogName(self.abilities),
                    activeTactics = #tacticNames > 0 and table.concat(tacticNames, ", ") or "none",
                    allies = #self.allyTokens,
                    enemies = #self.enemyTokens,
                    minion = token.properties.minion,
                    squadMembers = #self.squadMembers,
                })

                for i=1,6 do
                    self:SetLogContext(token, {
                        turn = initiativeid,
                        round = queue.round,
                        cycle = i,
                    })
                    self.paths = self:CalculateRemainingMovementPaths(token)
                    self:LogDecision("MOVE CYCLE START", {
                        reachableLocations = #table.values(self.paths),
                    })

                    local result = self:FindAndExecuteMove()
                    self:LogDecision("MOVE CYCLE FINISHED", {
                        result = result and "move executed" or "no legal move",
                    })
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

                self:SetLogContext(token, {
                    turn = initiativeid,
                    round = queue.round,
                })
                self:LogDecision("ACTOR FINISHED", {
                    result = token.valid and "completed" or "token became invalid",
                })
            else
                if not alreadyProcessed then
                    self:SetLogContext(token, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    self:LogDecision("ACTOR SKIPPED", {
                        reason = not token.valid and "token is no longer valid"
                            or "token is dead",
                    })
                end
            end
        end

        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })
        self:LogDecision("TURN FINISHED", {
            result = "advancing initiative",
        })
        GameHud.instance:NextInitiative(function()
            dmhub:UploadInitiativeQueue()
        end)
        
        coroutine.yield(0.5)
    else
        self:SetLogContext(nil, {turn = initiativeid})
        self:LogDecision("TURN ABORTED", {
            reason = queue == nil and "no initiative queue"
                or queue.hidden and "initiative queue is hidden"
                or "initiative entry is no longer current",
        })
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

local g_aiMinionDeathPendingTimeout = 125

local function AIMinionDeathPending(creatureProps)
    local confirmedAt = creatureProps:try_get("_tmp_minionDeathPending")
    return confirmedAt ~= nil and dmhub.Time() - confirmedAt < g_aiMinionDeathPendingTimeout
end

local function GetMinionLastAttacker(creatureProps)
    local attacker = creatureProps:try_get("_tmp_lastattacker")
    if type(attacker) == "function" then
        attacker = attacker("self")
    end
    return attacker
end

local function IsAIControlledAttacker(attacker)
    if attacker == nil then
        return false
    end

    local aiControl = nil
    pcall(function()
        aiControl = attacker._tmp_aicontrol
    end)
    return type(aiControl) == "number" and aiControl > 0
end

local function ConfirmAIMinionDeath(token, attacker)
    if token == nil or not token.valid or token.properties == nil
        or not token.properties.minion or token.properties.minionDead
        or AIMinionDeathPending(token.properties) then
        return false
    end

    token.properties._tmp_minionDeathPending = dmhub.Time()

    attacker = attacker or GetMinionLastAttacker(token.properties)
    if attacker ~= nil then
        --An overflow death can legally choose a squad member that was not the
        --direct damage target. Carry the killing attacker onto that minion so
        --kill triggers and the corpse attribution match the actual cast.
        token.properties._tmp_lastattacker = attacker
    end
    if attacker ~= nil then
        attacker:TriggerEvent("kill", {
            victim = token.properties,
            hasattacker = true,
            attacker = attacker,
        })
    end

    token.properties:TriggerEvent("creaturedeath", {
        hasattacker = attacker ~= nil,
        attacker = attacker,
    })
    token.properties:MinionDeath()
    return true
end

--Minion damage reduces the squad's shared Stamina pool, but the attacker must
--still choose the individual minions that die. Normally the Director does that
--by clicking the skulls created in DrawSteelTokenHud. AI casts have no ability
--prompt for that choice, so mirror the skull's eligibility and confirmation
--rules here while the attacking creatures are still under AI control.
function MonsterAI:ResolvePendingMinionDeaths(timeout)
    local deadline = dmhub.Time() + (timeout or 5)

    while true do
        local squads = {}
        for _,token in ipairs(dmhub.GetTokens{haveProperties = true}) do
            if token.valid and token.properties ~= nil and token.properties.minion
                and not token.properties.minionDead
                and token.properties:has_key("_tmp_minionSquad") then
                local squad = token.properties._tmp_minionSquad
                local entry = squads[squad]
                if entry == nil then
                    entry = {
                        squad = squad,
                        tokens = {},
                        attacker = nil,
                        attackerToken = nil,
                    }
                    squads[squad] = entry
                end

                entry.tokens[#entry.tokens+1] = token
                local attacker = GetMinionLastAttacker(token.properties)
                if IsAIControlledAttacker(attacker) then
                    entry.attacker = attacker
                    entry.attackerToken = dmhub.LookupToken(attacker)
                end
            end
        end

        local choices = {}
        local waiting = false
        for _,entry in pairs(squads) do
            local squad = entry.squad
            local healthSingle = squad.health_single or 0
            local damageTaken = squad.damage_taken or 0
            local deathsOwed = 0
            if healthSingle > 0 then
                deathsOwed = math.min(#entry.tokens, math.floor(damageTaken / healthSingle))
            end

            if entry.attacker ~= nil and deathsOwed > 0 then
                local pendingDeaths = 0
                for _,token in ipairs(entry.tokens) do
                    if AIMinionDeathPending(token.properties) then
                        pendingDeaths = pendingDeaths + 1
                    end
                end

                local deathsToChoose = deathsOwed - pendingDeaths
                if deathsToChoose > 0 then
                    if squad.damage_time_pending then
                        waiting = true
                    else
                        local candidates = {}
                        local numRecentlyDamaged = squad.num_recently_damaged or 0
                        local deathOverflows = damageTaken >= (numRecentlyDamaged + 1) * healthSingle

                        for _,token in ipairs(entry.tokens) do
                            local props = token.properties
                            local isDirectTarget = props.minionDamageTime == squad.damage_time
                            local gated = (props:CalculateNamedCustomAttribute("Gated Minion Deaths") or 0) > 0
                            local triggers = props:GetAvailableTriggers(true)
                            if not AIMinionDeathPending(props) and not gated
                                and (isDirectTarget or deathOverflows) and triggers == nil then
                                local distance = 999999
                                if entry.attackerToken ~= nil and entry.attackerToken.valid then
                                    distance = entry.attackerToken:Distance(token)
                                end
                                candidates[#candidates+1] = {
                                    token = token,
                                    direct = isDirectTarget,
                                    distance = distance,
                                }
                            end
                        end

                        table.sort(candidates, function(a, b)
                            if a.direct ~= b.direct then
                                return a.direct
                            end
                            if a.distance ~= b.distance then
                                return a.distance < b.distance
                            end
                            return a.token.charid < b.token.charid
                        end)

                        for i=1,math.min(deathsToChoose, #candidates) do
                            choices[#choices+1] = {
                                token = candidates[i].token,
                                attacker = entry.attacker,
                            }
                        end

                        if #candidates < deathsToChoose then
                            waiting = true
                        end
                    end
                end
            end
        end

        if #choices > 0 then
            for _,choice in ipairs(choices) do
                if ConfirmAIMinionDeath(choice.token, choice.attacker) then
                    self:LogDecision("MINION DEATH SELECTED", {
                        targets = self.TargetsLogName({{token = choice.token}}),
                        reason = "squad damage requires a minion death",
                    })
                end
            end
            self.Sleep(0.1)
        elseif waiting and dmhub.Time() < deadline then
            coroutine.yield(0.1)
        else
            return
        end
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

    self:SetLogContext(nil, {
        turn = initiativeid,
        round = queue.round,
    })
    self:LogDecision("MALICE WINDOW START", {
        malice = CharacterResource.GetMalice(),
        registrations = #table.values(self.maliceAbilities),
    })

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

        if #groupTokens > 0 and #eligibleCasters == 0 then
            self:LogDecision("MALICE REJECTED", {
                category = self.MoveCategoryLogName(registration),
                move = registration.id,
                ability = registration.abilities ~= nil and registration.abilities[1] or nil,
                reason = "registration is disabled for every matching acting monster",
            })
        elseif #eligibleCasters > 0 and registration.abilities ~= nil and registration.abilities[1] ~= nil then
            local caster = nil
            local ability = nil
            local unavailableReasons = {}
            local unavailableByToken = {}
            local function RecordUnavailable(token, reason)
                if not unavailableByToken[token.charid] then
                    unavailableByToken[token.charid] = true
                    unavailableReasons[#unavailableReasons+1] = string.format("%s %s",
                        self.TokenLogName(token), reason)
                end
            end
            for pass=1,2 do
                for _,token in ipairs(eligibleCasters) do
                    if pass == 2 or not token.properties.minion then
                        local candidateAbility = FindMaliceAbilityByName(token, registration.abilities[1])
                        if candidateAbility == nil then
                            RecordUnavailable(token, "lacks " .. registration.abilities[1])
                        elseif not candidateAbility:CanAfford(token) then
                            RecordUnavailable(token, AIAbilityUnavailableReason(token, candidateAbility))
                        else
                            local filterFailure = candidateAbility:AbilityFilterFailureMessage(token.properties)
                            if filterFailure ~= nil then
                                RecordUnavailable(token, "blocked: " .. tostring(filterFailure))
                            else
                                caster = token
                                ability = candidateAbility
                                break
                            end
                        end
                    end
                end
                if caster ~= nil then
                    break
                end
            end

            if caster ~= nil then
                self:SetLogContext(caster, {
                    turn = initiativeid,
                    round = queue.round,
                })
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

                local ok, scoringInfo, scoringReason = pcall(
                    registration.score, registration, self, caster, ability, context)
                if not ok then
                    self:LogDecision("MALICE ERROR", {
                        category = self.MoveCategoryLogName(registration),
                        move = registration.id,
                        ability = ability.name,
                        reason = "scoring failed: " .. tostring(scoringInfo),
                    })
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
                        self:LogDecision("MALICE CANDIDATE", {
                            category = self.MoveCategoryLogName(registration),
                            move = registration.id,
                            ability = ability.name,
                            action = self.AbilityActionLogName(ability),
                            score = score,
                            threshold = minimumScore,
                            plan = self.ScoringPlanLogName(scoringInfo),
                            result = score >= minimumScore and "eligible" or "below threshold",
                        })

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
                        self:LogDecision("MALICE REJECTED", {
                            category = self.MoveCategoryLogName(registration),
                            move = registration.id,
                            ability = ability.name,
                            reason = scoringReason or "score callback returned no legal plan",
                        })
                    end
                end
            else
                self:LogDecision("MALICE REJECTED", {
                    category = self.MoveCategoryLogName(registration),
                    move = registration.id,
                    ability = registration.abilities[1],
                    reason = #unavailableReasons > 0
                        and table.concat(unavailableReasons, "; ")
                        or "no eligible caster has a legal, affordable ability",
                })
            end
        end
    end

    if bestCandidate == nil then
        self:SetLogContext(nil, {
            turn = initiativeid,
            round = queue.round,
        })
        self:LogDecision("MALICE WINDOW FINISHED", {
            result = "no Malice ability selected",
        })
        return false
    end

    local registration = bestCandidate.registration
    local caster = bestCandidate.caster
    self:SetLogContext(caster, {
        turn = initiativeid,
        round = queue.round,
        category = self.MoveCategoryLogName(registration),
        move = registration.id,
    })
    self:LogDecision("MALICE SELECTED", {
        ability = bestCandidate.ability.name,
        action = self.AbilityActionLogName(bestCandidate.ability),
        score = bestCandidate.score,
        plan = self.ScoringPlanLogName(bestCandidate.scoringInfo),
    })
    self:SetupCombatants(caster, queue)
    local execute = registration.execute or function(_, ai, token, scoringInfo, ability)
        ai:ExecuteAbility(token, ability)
    end
    local ok, err = self:RunWithTokenControl(caster, function()
        execute(registration, self, caster, bestCandidate.scoringInfo, bestCandidate.ability, bestCandidate.context)
    end)

    if not ok then
        self:LogDecision("MALICE ERROR", {
            ability = bestCandidate.ability.name,
            reason = "execution failed: " .. tostring(err),
        })
        self:LogMove(caster.properties.monster_type, registration.id, "Execution failed: " .. tostring(err))
        return false
    end

    self:WaitForAbilityIdle()
    self:LogMove(caster.properties.monster_type, registration.id, "Executed at the start of the turn")
    self:LogDecision("MALICE FINISHED", {
        ability = bestCandidate.ability.name,
        result = "executed",
    })
    return true
end

function MonsterAI:ExecuteVillainActionCandidate(candidate)
    local token = candidate.token
    local ability = candidate.ability
    local action = candidate.action
    self:SetLogContext(token, {
        turn = candidate.context.endedInitiativeId,
        round = candidate.context.round,
        category = self.MoveCategoryLogName(action),
        move = action.id,
    })
    if not self.active or token == nil or not token.valid or token.properties:IsDead() then
        self:LogDecision("VILLAIN ACTION CANCELLED", {
            ability = ability ~= nil and ability.name or nil,
            reason = not self.active and "Monster AI stopped"
                or token == nil and "caster is missing"
                or not token.valid and "caster is invalid"
                or "caster is dead",
        })
        return false
    end
    if CharacterResource.GetVillainActions() <= 0
        or VillainActionState.HasUsed(token.charid, candidate.slot)
        or not ability:CanAfford(token) then
        self:LogDecision("VILLAIN ACTION CANCELLED", {
            ability = ability.name,
            reason = CharacterResource.GetVillainActions() <= 0 and "no villain action budget remains"
                or VillainActionState.HasUsed(token.charid, candidate.slot) and "this villain action was already used"
                or AIAbilityUnavailableReason(token, ability),
        })
        return false
    end

    self:LogDecision("VILLAIN ACTION SELECTED", {
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        score = candidate.score,
        plan = self.ScoringPlanLogName(candidate.scoringInfo),
        slot = candidate.slot,
    })

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
        self:LogDecision("VILLAIN ACTION ERROR", {
            ability = ability.name,
            reason = "execution failed: " .. tostring(err),
        })
        self:LogMove(token.properties.monster_type, action.id, "Execution failed: " .. tostring(err))
        return false
    end

    self:WaitForAbilityIdle()
    self:LogMove(token.properties.monster_type, action.id, "Executed villain action")
    self:LogDecision("VILLAIN ACTION FINISHED", {
        ability = ability.name,
        result = "executed",
    })
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
    self:SetLogContext(nil, {
        turn = context.endedInitiativeId,
        round = round,
    })
    self:LogDecision("VILLAIN ACTION WINDOW START", {
        slot = slot,
        budget = CharacterResource.GetVillainActions(),
    })

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
                        self:SetLogContext(token, {
                            turn = context.endedInitiativeId,
                            round = round,
                        })
                        self:SetupCombatants(token, context.initiativeQueue)
                        local ok, scoringInfo, scoringReason = pcall(
                            action.score, action, self, token, ability, context)
                        if ok and type(scoringInfo) == "number" then
                            scoringInfo = {score = scoringInfo}
                        elseif not ok then
                            self:LogDecision("VILLAIN ACTION ERROR", {
                                category = self.MoveCategoryLogName(action),
                                move = action.id,
                                ability = ability.name,
                                reason = "scoring failed: " .. tostring(scoringInfo),
                            })
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
                            self:LogDecision("VILLAIN ACTION CANDIDATE", {
                                category = self.MoveCategoryLogName(action),
                                move = action.id,
                                ability = ability.name,
                                action = self.AbilityActionLogName(ability),
                                score = score,
                                plan = self.ScoringPlanLogName(scoringInfo),
                                chance = chance,
                                roll = roll,
                                remainingWindows = windowsIncludingNow,
                                result = candidate.forced and "forced in final window"
                                    or roll <= chance and "passed use roll"
                                    or "failed use roll",
                            })
                        elseif ok then
                            self:LogDecision("VILLAIN ACTION REJECTED", {
                                category = self.MoveCategoryLogName(action),
                                move = action.id,
                                ability = ability.name,
                                reason = scoringReason or "score callback returned no legal plan",
                            })
                        end
                    elseif ability ~= nil and ability:try_get("villainAction") == slot then
                        self:SetLogContext(token, {
                            turn = context.endedInitiativeId,
                            round = round,
                        })
                        self:LogDecision("VILLAIN ACTION REJECTED", {
                            category = self.MoveCategoryLogName(action),
                            move = action.id,
                            ability = ability.name,
                            reason = VillainActionState.HasUsed(token.charid, slot)
                                and "this villain action was already used"
                                or AIAbilityUnavailableReason(token, ability),
                        })
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
    else
        self:SetLogContext(nil, {
            turn = context.endedInitiativeId,
            round = round,
        })
        self:LogDecision("VILLAIN ACTION WINDOW FINISHED", {
            result = "no villain action selected",
        })
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
    local movementToken = self:GetMovementToken(token)
    self:ExecuteWithTheoreticalMovementLoc(token, loc, function()
        for i=1,#filteredTokens do
            local enemy = filteredTokens[i]
            local dist = token:Distance(enemy)

            local chargeLoc = nil
            if hasCharge then
                local movementInfo = movementToken:MarkMovementArrow(enemy.loc, {straightline = true, ignorecreatures = false, moveThroughFriends = true})
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
                    if chargeDist <= ability:try_get("chargeDistanceOverride", movementToken.properties:CurrentMovementSpeed()) then
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
                    local edgeReasons = {}

                    --obstruction.
                    if los < 1 then
                        edges = edges - 1
                        edgeReasons[#edgeReasons+1] = "obstruction -1"
                    end

                    local tokenLoc = chargeLoc or loc

                    for tacticid,tactic in pairs(self.activeTactics) do
                        local score = tactic.score(self, token, tokenLoc, enemy, ability) or 0
                        edges = edges + score
                        if score ~= 0 then
                            edgeReasons[#edgeReasons+1] = string.format("%s %+.2f", tacticid, score)
                        end
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
                            edgeReasons[#edgeReasons+1] = "ranged while adjacent -1"
                        end
                    end

                    result[#result+1] = {
                        token = enemy,
                        loc = enemy.loc,
                        charge = chargeLoc,
                        edges = edges,
                        edgeReasons = edgeReasons,
                    }
                end
            end
        end

    end)

    if hasCharge then
        movementToken:ClearMovementArrow()
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

    return squadMember.possibleTargets
end

function MonsterAI:ExecuteSquadStrike(ability)
    self:LogDecision("MOVE SELECTED", {
        category = "Main Action",
        move = "Minion Signature Ability",
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        result = string.format("coordinating %d minion(s)", #self.squadMembers),
    })
    local logMessage = nil
    local rays = {}
    local targetPairs = {}
    local assignedTargets = {}
    for _,squadMember in ipairs(self.squadMembers) do

        local movementToken = self:GetMovementToken(squadMember.token)
        squadMember.paths = self:CalculateMovementPaths(squadMember.token,
            movementToken.properties:CurrentMovementSpeed()*10)

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
            self:LogDecision("MINION ASSIGNMENT", {
                actor = self.TokenLogName(squadMember.token),
                actorId = squadMember.token.charid,
                category = "Main Action",
                move = "Minion Signature Ability",
                ability = ability.name,
                from = self.LocLogName(squadMember.token.loc),
                to = self.LocLogName(bestOption.loc),
                targets = self.TargetsLogName({{token = bestOption.token}}),
                plan = bestOption.charge ~= nil
                    and string.format("charge through %s", self.LocLogName(bestOption.charge))
                    or "strike from destination",
            })
            assignedTargets[bestOption.token.charid] = (assignedTargets[bestOption.token.charid] or 0) + 1
            local path = self:MoveToken(squadMember.token, bestOption.loc, {maxCost = 10000, ignoreFalling = false})
            self.Sleep(0.6)


            if bestOption.charge ~= nil then
                self:Speech(squadMember.token, "Charge!")
                self.Sleep(0.3)
                --freeMovement: a Charge is a main action whose movement belongs to the
                --ability, not to the creature's move action, so it must not be charged
                --against -- or clamped by -- the remaining move budget under
                --strict:movement. Without this the move above eats the budget and the
                --charge silently becomes a no-op, leaving the striker out of range.
                local path = self:MoveToken(squadMember.token, bestOption.charge, {maxCost = 10000, ignoreFalling = false, freeMovement = true})
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
        else
            self:LogDecision("MINION ASSIGNMENT REJECTED", {
                actor = self.TokenLogName(squadMember.token),
                actorId = squadMember.token.charid,
                category = "Main Action",
                move = "Minion Signature Ability",
                ability = ability.name,
                reason = "no legal target can be reached",
            })
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

    local finalTargets = {}
    for _,pair in ipairs(targetPairs) do
        finalTargets[#finalTargets+1] = {token = dmhub.GetTokenById(pair.b)}
    end
    self:LogDecision("MOVE FINISHED", {
        category = "Main Action",
        move = "Minion Signature Ability",
        ability = ability.name,
        targets = self.TargetsLogName(finalTargets),
        result = logMessage,
    })

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
    local bestTargets = nil
    local bestCost = nil
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

            score = score + (maxEdges or 0)*0.1
        end

        score = score - info.cost*0.001

        if score > bestScore then
            bestScore = score
            bestMove = destLoc
            bestTargets = targets
            bestCost = info.cost
        end
    end

    if bestMove ~= nil then
        local selectedTargets = {}
        for i=1,math.min(numTargets, #(bestTargets or {})) do
            selectedTargets[#selectedTargets+1] = bestTargets[i]
        end
        self:LogDecision("TARGET PLAN", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            score = bestScore,
            plan = string.format("move-to %s; movement-cost=%s; %s",
                self.LocLogName(bestMove), tostring(bestCost or 0),
                self.TargetScoresLogName(selectedTargets)),
            targets = self.TargetsLogName(selectedTargets),
            result = "legal strike plan",
        })
    else
        self:LogDecision("TARGET PLAN REJECTED", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = "no reachable location has a legal strike target",
        })
    end

    return bestMove, bestScore
end

function MonsterAI:FindBestMoveToUseBurst(token, ability, scorefn)
    scorefn = scorefn or function() return 1 end
    local range = ability:GetRange(token.properties)
    local bestScore = nil
    local bestCost = nil
    local bestMove = nil
    local bestTargets = nil
    local allTokens = dmhub.allTokens
    local symbols = {mode = 1}
    for _,info in pairs(self.paths) do
        local score = 0
        local destLoc = info.loc
        local targets = {}

        self:ExecuteWithTheoreticalMovementLoc(token, destLoc, function()
            for _,targetToken in ipairs(allTokens) do
                if targetToken.valid and targetToken:Distance(token) <= range and ability:TargetPassesFilter(token, targetToken, symbols) then
                    score = score + scorefn(targetToken)
                    targets[#targets+1] = {token = targetToken}
                end
            end
        end)

        local cost = info.cost or 0
        if bestScore == nil or score > bestScore or (score == bestScore and cost < bestCost) then
            bestScore = score
            bestCost = cost
            bestMove = destLoc
            bestTargets = targets
        end
    end


    if bestMove ~= nil then
        self:LogDecision("TARGET PLAN", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            score = bestScore,
            plan = string.format("move-to %s; movement-cost=%s; burst",
                self.LocLogName(bestMove), tostring(bestCost or 0)),
            targets = self.TargetsLogName(bestTargets),
            result = "best burst plan",
        })
    else
        self:LogDecision("TARGET PLAN REJECTED", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = "no reachable burst location",
        })
    end

    return bestMove, bestScore
end

-- Find the highest-scoring line area from a set of candidate endpoints.
-- Candidates can be tokens, locations, or tables containing targetLoc and an
-- optional locOverride. The latter supports placed lines whose origin differs
-- from the caster without making their candidate-generation rules generic.
function MonsterAI:FindBestLinePlan(token, ability, options)
    options = options or {}
    local candidates = options.candidates or self.enemyTokens or {}
    local scorefn = options.scorefn or function() return 1 end
    local symbols = options.symbols or {}
    local checklos = options.checklos
    if checklos == nil then
        checklos = true
    end

    local range = options.range or ability:GetRange(token.properties, symbols)
    local radius = options.radius or ability:GetRadius(token.properties, symbols)
    local best = nil

    for _,candidate in ipairs(candidates) do
        local targetLoc = candidate.targetLoc or candidate.loc or candidate
        local locOverride = candidate.locOverride or options.locOverride
        if targetLoc ~= nil and targetLoc.valid and targetLoc.isOnMap then
            local originLoc = locOverride or token.loc
            local area = dmhub.CalculateShape{
                shape = "line",
                targetPoint = token:PosAtLoc(targetLoc),
                token = token,
                range = range,
                radius = radius,
                locOverride = locOverride,
                checklos = checklos,
                altitude = originLoc.altitude * dmhub.unitsPerSquare,
            }

            local areaSymbols = {}
            for key,value in pairs(symbols) do
                areaSymbols[key] = value
            end
            areaSymbols.targetArea = area

            local targets = {}
            local score = 0
            for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
                if target.valid and ability:TargetPassesFilter(token, target, areaSymbols) then
                    targets[#targets+1] = {token = target}
                    score = score + (scorefn(target, candidate, areaSymbols) or 0)
                end
            end

            if best == nil or score > best.score then
                best = {
                    targetLoc = targetLoc,
                    locOverride = locOverride,
                    targets = targets,
                    numTargets = #targets,
                    score = score,
                    candidate = candidate,
                }
            end
            if type(area.Destroy) == "function" then
                area:Destroy()
            end
        end
    end

    if options.logPlan ~= false and best ~= nil then
        self:LogDecision("TARGET PLAN", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            score = best.score,
            plan = string.format("line aimed at %s", self.LocLogName(best.targetLoc)),
            targets = self.TargetsLogName(best.targets),
            result = "best line plan",
        })
    elseif options.logPlan ~= false then
        self:LogDecision("TARGET PLAN REJECTED", {
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = "no candidate line produced a legal area",
        })
    end

    return best
end

-- Synthesized moves are intentionally conservative. They are only considered
-- for fully automated offensive abilities whose targeting can be planned by
-- the generic AI without asking a player to make a semantic choice.
local g_synthesizedAbilityMinimumConfidence = 0.90
local g_synthesizedAbilitySupportedTargets = {
    target = true,
    all = true,
    cube = true,
    line = true,
}
local g_synthesizedAbilityExcludedCategories = {
    Malice = true,
    ["Malice Ability"] = true,
    Trigger = true,
    ["Triggered Ability"] = true,
    ["Villain Action"] = true,
}

local function SynthesizedAbilityKey(ability)
    return ability:GetID() or ability.name
end

local function SynthesizedMoveId(ability)
    return string.format("Synthesized: %s", ability.name)
end

local function TextDescribesDamage(text)
    if type(text) ~= "string" then
        return false
    end
    return string.find(string.lower(text), "%f[%a]damage%f[%A]") ~= nil
end

local function ResolveInvokedAbility(behavior)
    local abilityType = behavior:try_get("abilityType", "custom")
    if abilityType == "custom" then
        return behavior:try_get("customAbility")
    elseif abilityType == "standard" then
        local abilities = dmhub.GetTable("standardAbilities") or {}
        return abilities[behavior:try_get("standardAbility", "")]
    end
    return nil
end

local function BehaviorAppliesHarmToTargets(behavior)
    local applyto = behavior:try_get("applyto", "targets")
    return applyto == "targets"
        or applyto == "enemies"
        or applyto == "original_targets"
        or applyto == "hit_targets"
        or applyto == "failed_save_targets"
        or applyto == "passed_save_targets"
end

local function SynthesizedHarmConfidence(ability, visited)
    visited = visited or {}
    if visited[ability] then
        return nil
    end
    visited[ability] = true

    if ability:HasKeyword("Strike") then
        return 0.99, "Strike keyword"
    end

    local bestConfidence = nil
    local bestReason = nil
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        local typeName = behavior.typeName
        local confidence = nil
        local reason = nil
        if typeName == "ActivatedAbilityDamageBehavior"
            and BehaviorAppliesHarmToTargets(behavior) then
            confidence = 0.97
            reason = "damage behavior"
        elseif typeName == "ActivatedAbilityPowerRollBehavior"
            and BehaviorAppliesHarmToTargets(behavior) then
            for _,tier in ipairs(behavior:try_get("tiers", {})) do
                if TextDescribesDamage(tier) then
                    confidence = 0.95
                    reason = "damaging power roll"
                    break
                end
            end
        elseif typeName == "ActivatedAbilityDrawSteelCommandBehavior"
            and BehaviorAppliesHarmToTargets(behavior)
            and TextDescribesDamage(behavior:try_get("rule", "")) then
            confidence = 0.93
            reason = "damage command"
        elseif typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            local invokedAbility = ResolveInvokedAbility(behavior)
            local targeting = behavior:try_get("targeting", "prompt")
            if invokedAbility ~= nil and targeting ~= "self" then
                local invokedConfidence = SynthesizedHarmConfidence(invokedAbility, visited)
                if invokedConfidence ~= nil then
                    confidence = invokedConfidence - 0.03
                    reason = "damaging invoked ability"
                end
            end
        end

        if confidence ~= nil and (bestConfidence == nil or confidence > bestConfidence) then
            bestConfidence = confidence
            bestReason = reason
        end
    end

    return bestConfidence, bestReason
end

function MonsterAI:SynthesizedAbilityPromptsAreHandled(ability, visited)
    visited = visited or {}
    if visited[ability] then
        return true
    end
    visited[ability] = true

    if ability:RequiresPromptWhenCast() then
        return false, "requires a cast-time choice"
    end

    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            if behavior:try_get("promptWhenResolving", false) then
                return false, "requires choosing invocation order"
            end
            if behavior:try_get("runOnController", false) then
                return false, "delegates an invoked ability to another controller"
            end

            local abilityType = behavior:try_get("abilityType", "custom")
            if abilityType == "named" or abilityType == "chooseClassAbility" then
                return false, "selects an invoked ability dynamically"
            end

            local invokedAbility = ResolveInvokedAbility(behavior)
            if invokedAbility == nil then
                return false, "has an unresolved invoked ability"
            end

            local targeting = behavior:try_get("targeting", "prompt")
            if targeting == "prompt" or targeting == "prompt_inherit" then
                local prompt = self.prompts[invokedAbility.name]
                if prompt == nil then
                    return false, string.format("has no AI prompt handler for %s", invokedAbility.name)
                end
            end

            local handled, reason = self:SynthesizedAbilityPromptsAreHandled(invokedAbility, visited)
            if not handled then
                return false, reason
            end
        end
    end

    return true
end


function MonsterAI:GetSynthesizedAbilityProfile(token, ability)
    if ability:try_get("implementation", gui.ImplementationStatus.Unimplemented) < gui.ImplementationStatus.Gold then
        return nil, "is not fully automated"
    end
    if #ability:try_get("behaviors", {}) == 0 then
        return nil, "has no automated behaviors"
    end
    if not ability:IsDirectlyCastable() then
        return nil, "must synthesize its own sub-abilities"
    end
    if not g_synthesizedAbilitySupportedTargets[ability.targetType] then
        return nil, string.format("uses unsupported target type %s", tostring(ability.targetType))
    end
    if g_synthesizedAbilityExcludedCategories[ability.categorization] then
        return nil, string.format("is a %s", ability.categorization)
    end
    if ability:try_get("villainAction") ~= nil then
        return nil, "is a villain action"
    end

    local actionResource = ability:ActionResource()
    if actionResource == CharacterResource.triggerResourceId then
        return nil, "uses the triggered-action resource"
    elseif actionResource == CharacterResource.villainActionId then
        return nil, "uses the villain-action resource"
    end

    local promptsHandled, promptReason = self:SynthesizedAbilityPromptsAreHandled(ability)
    if not promptsHandled then
        return nil, promptReason
    end

    local confidence, reason = SynthesizedHarmConfidence(ability)
    if confidence == nil then
        return nil, "has no confidently harmful effect"
    end
    if ability.targetType ~= "target" then
        confidence = confidence - 0.02
    end
    if confidence < g_synthesizedAbilityMinimumConfidence then
        return nil, string.format("effect confidence %.2f is below threshold", confidence)
    end

    return {
        actionResource = actionResource,
        confidence = confidence,
        reason = reason,
        targetType = ability.targetType,
    }
end


function MonsterAI:GetClaimedAbilityNames(token)
    local result = {}
    for _,move in pairs(self.moves) do
        -- Disabled custom moves still claim their abilities. Otherwise disabling
        -- a handcrafted behavior would unexpectedly turn the ability back on
        -- through the fallback.
        if self.MoveMatchesMonster(token, move, true) then
            for _,abilityName in ipairs(move.abilities or {}) do
                result[abilityName] = true
            end
        end
    end
    return result
end


local function SynthesizedDefaultTargetScore(targetInfo)
    local target = targetInfo.token
    if target.isObject or target.properties == nil then
        return 0.1
    end
    local stamina = target.properties:CurrentHitpoints()
        / math.max(1, target.properties.max_hitpoints)
    return 1 + (targetInfo.edges or 0)*0.1 + (1 - stamina)*0.08
end

function MonsterAI:FindSynthesizedTargetPlan(token, ability)
    local range = ability:GetRange(token.properties)
    local numTargets = ability:GetNumTargets(token)
    local best = nil

    for _,pathInfo in pairs(self.paths or {}) do
        local candidates = {}
        for _,targetInfo in ipairs(self:FindValidTargetsOfStrike(token, ability, pathInfo.loc, range)) do
            candidates[#candidates+1] = {
                info = targetInfo,
                score = SynthesizedDefaultTargetScore(targetInfo),
            }
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
                    enemies = #targets,
                    utility = utility,
                }
            end
        end
    end

    return best
end


local function IsLiveSynthesizedTarget(target)
    return target ~= nil and target.valid and target.properties ~= nil
        and (target.isObject or not target.properties:IsDead())
end

local function CountSynthesizedTargets(token, targets)
    local enemies = 0
    local allies = 0
    for _,targetInfo in ipairs(targets or {}) do
        local target = targetInfo.token
        if IsLiveSynthesizedTarget(target) and not target.isObject then
            if target:IsFriend(token) then
                allies = allies + 1
            else
                enemies = enemies + 1
            end
        end
    end
    return enemies, allies
end

function MonsterAI:FindSynthesizedBurstPlan(token, ability)
    local range = ability:GetRange(token.properties)
    local symbols = {mode = 1}
    local best = nil

    for _,pathInfo in pairs(self.paths or {}) do
        local targets = {}
        self:ExecuteWithTheoreticalMovementLoc(token, pathInfo.loc, function()
            for _,target in ipairs(dmhub.allTokens) do
                if IsLiveSynthesizedTarget(target)
                    and target:Distance(token) <= range
                    and ability:TargetPassesFilter(token, target, symbols) then
                    targets[#targets+1] = {token = target}
                end
            end
        end)

        local enemies, allies = CountSynthesizedTargets(token, targets)
        local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
        if enemies > 0 and allies == 0
            and (best == nil or utility > best.utility) then
            best = {
                loc = pathInfo.loc,
                targets = targets,
                enemies = enemies,
                allies = allies,
                utility = utility,
            }
        end
    end

    return best
end

function MonsterAI:SynthesizedBurstTargetsAtCurrentLoc(token, ability)
    local range = ability:GetRange(token.properties)
    local symbols = {mode = 1}
    local targets = {}
    for _,target in ipairs(dmhub.allTokens) do
        if IsLiveSynthesizedTarget(target)
            and target:Distance(token) <= range
            and ability:TargetPassesFilter(token, target, symbols) then
            targets[#targets+1] = {token = target}
        end
    end
    local enemies, allies = CountSynthesizedTargets(token, targets)
    return targets, enemies, allies
end


local function BuildSynthesizedArea(token, ability, shape, targetLoc, locOverride)
    local originLoc = locOverride or token.loc
    return dmhub.CalculateShape{
        shape = shape,
        targetPoint = token:PosAtLoc(targetLoc),
        token = token,
        range = ability:GetRange(token.properties),
        radius = ability:GetRadius(token.properties),
        locOverride = locOverride,
        checklos = shape == "line",
        altitude = cond(shape == "cube", targetLoc.altitude, originLoc.altitude) * dmhub.unitsPerSquare,
    }
end

function MonsterAI:SynthesizedTargetsInArea(token, ability, area)
    local targets = {}
    local symbols = {mode = 1, targetArea = area}
    for _,target in pairs(dmhub.tokenInfo.TokensInShape(area)) do
        if IsLiveSynthesizedTarget(target)
            and ability:TargetPassesFilter(token, target, symbols) then
            targets[#targets+1] = {token = target}
        end
    end
    local enemies, allies = CountSynthesizedTargets(token, targets)
    return targets, enemies, allies
end

function MonsterAI:FindSynthesizedCubePlan(token, ability)
    local best = nil
    local range = ability:GetRange(token.properties)

    for _,pathInfo in pairs(self.paths or {}) do
        local checked = {}
        self:ExecuteWithTheoreticalMovementLoc(token, pathInfo.loc, function()
            for _,enemy in ipairs(self.enemyTokens or {}) do
                if IsLiveSynthesizedTarget(enemy)
                    and token:Distance(enemy) <= range
                    and not checked[enemy.loc.str] then
                    checked[enemy.loc.str] = true
                    local area = BuildSynthesizedArea(token, ability, "cube", enemy.loc, pathInfo.loc)
                    local targets, enemies, allies = self:SynthesizedTargetsInArea(token, ability, area)
                    local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
                    if enemies > 0 and allies == 0
                        and (best == nil or utility > best.utility) then
                        best = {
                            loc = pathInfo.loc,
                            center = enemy.loc,
                            targets = targets,
                            enemies = enemies,
                            allies = allies,
                            utility = utility,
                        }
                    end
                    if type(area.Destroy) == "function" then
                        area:Destroy()
                    end
                end
            end
        end)
    end

    return best
end


function MonsterAI:FindSynthesizedLinePlan(token, ability)
    local best = nil
    for _,pathInfo in pairs(self.paths or {}) do
        local candidates = {}
        for _,enemy in ipairs(self.enemyTokens or {}) do
            if IsLiveSynthesizedTarget(enemy) then
                candidates[#candidates+1] = {
                    targetLoc = enemy.loc,
                    locOverride = pathInfo.loc,
                }
            end
        end

        local plan = self:FindBestLinePlan(token, ability, {
            candidates = candidates,
            logPlan = false,
            scorefn = function(target)
                if target.isObject then
                    return 0
                end
                return cond(target:IsFriend(token), -3, 1)
            end,
        })
        if plan ~= nil then
            local enemies, allies = CountSynthesizedTargets(token, plan.targets)
            local utility = enemies - allies*3 - (pathInfo.cost or 0)*0.001
            if enemies > 0 and allies == 0
                and (best == nil or utility > best.utility) then
                best = {
                    loc = pathInfo.loc,
                    targetLoc = plan.targetLoc,
                    targets = plan.targets,
                    enemies = enemies,
                    allies = allies,
                    utility = utility,
                }
            end
        end
    end
    return best
end


function MonsterAI:FindSynthesizedAbilityPlan(token, ability, profile)
    if profile.targetType == "target" then
        return self:FindSynthesizedTargetPlan(token, ability)
    elseif profile.targetType == "all" then
        return self:FindSynthesizedBurstPlan(token, ability)
    elseif profile.targetType == "cube" then
        return self:FindSynthesizedCubePlan(token, ability)
    elseif profile.targetType == "line" then
        return self:FindSynthesizedLinePlan(token, ability)
    end
end


local function SynthesizedMaliceCost(token, ability)
    local result = 0
    local cost = ability:GetCost(token)
    for _,detail in ipairs(cost.details or {}) do
        if detail.cost == CharacterResource.maliceResourceId then
            result = result + (tonumber(detail.quantity) or 0)
        else
            for _,payment in ipairs(detail.paymentOptions or {}) do
                if payment.resourceid == CharacterResource.maliceResourceId then
                    result = result + (tonumber(payment.quantity) or 0)
                    break
                end
            end
        end
    end
    return result
end

local function ScoreSynthesizedAbilityPlan(token, ability, profile, plan)
    local score = 0.72
    if profile.actionResource == CharacterResource.actionResourceId then
        score = 0.80
    elseif profile.actionResource == CharacterResource.maneuverResourceId
        or profile.actionResource == CharacterResource.freeManeuverResourceId then
        score = 0.48
    elseif profile.actionResource == nil or profile.actionResource == "none" then
        score = 0.38
    end

    if ability.categorization == "Signature Ability" then
        score = math.max(score, 0.84)
    elseif ability.categorization == "Heroic Ability" then
        score = math.max(score, 0.81)
    end

    score = score + math.min(0.12, math.max(0, (plan.enemies or 1) - 1)*0.05)
    score = score + math.max(0, profile.confidence - g_synthesizedAbilityMinimumConfidence)*0.1
    score = score - math.min(0.18, SynthesizedMaliceCost(token, ability)*0.015)
    -- Handcrafted signature moves conventionally score 1.0. Keep fallback
    -- plans below that while still ranking them above generic free strikes.
    return math.min(0.94, score)
end

function MonsterAI:FindBestSynthesizedAbilityMove(token, abilities, claimedAbilities)
    local best = nil
    local used = self:try_get("_tmp_synthesizedAbilitiesUsed", {})

    for _,ability in ipairs(abilities) do
        local key = SynthesizedAbilityKey(ability)
        if not claimedAbilities[ability.name] and not used[key] then
            local profile, profileReason = self:GetSynthesizedAbilityProfile(token, ability)
            local moveid = SynthesizedMoveId(ability)
            local registration = {
                id = moveid,
                category = "Main Actions",
            }
            self:SetMoveLogContext(token, registration)
            if profile ~= nil then
                if profile.actionResource == CharacterResource.maneuverResourceId
                    or profile.actionResource == CharacterResource.freeManeuverResourceId then
                    registration.category = "Maneuvers"
                    self:SetMoveLogContext(token, registration)
                end
                if not ability:CanAfford(token) then
                    self:LogMove(token.properties.monster_type, moveid, "Could not afford", {onlyIfEmpty = true})
                    self:LogDecision("MOVE REJECTED", {
                        ability = ability.name,
                        action = self.AbilityActionLogName(ability),
                        reason = AIAbilityUnavailableReason(token, ability),
                    })
                else
                    local plan = self:FindSynthesizedAbilityPlan(token, ability, profile)
                    local maliceCost = SynthesizedMaliceCost(token, ability)
                    -- Without effect-specific knowledge, do not spend shared
                    -- Malice on an area ability that only reaches one enemy.
                    if plan ~= nil and not (profile.targetType ~= "target"
                        and maliceCost > 0 and (plan.enemies or 0) < 2) then
                        plan.score = ScoreSynthesizedAbilityPlan(token, ability, profile, plan)
                        plan.ability = ability
                        plan.profile = profile
                        self:LogMove(token.properties.monster_type, moveid, string.format(
                            "Score: %.2f (confidence %.2f; %s)",
                            plan.score, profile.confidence, profile.reason))
                        self:LogDecision("MOVE CANDIDATE", {
                            ability = ability.name,
                            action = self.AbilityActionLogName(ability),
                            score = plan.score,
                            plan = self.ScoringPlanLogName(plan),
                            reason = string.format("synthesized at %.2f confidence from %s",
                                profile.confidence, profile.reason),
                            result = "legal synthesized candidate",
                        })
                        if best == nil or plan.score > best.score then
                            best = plan
                        end
                    else
                        self:LogMove(token.properties.monster_type, moveid,
                            "Could not find a safe, worthwhile target plan", {onlyIfEmpty = true})
                        self:LogDecision("MOVE REJECTED", {
                            ability = ability.name,
                            action = self.AbilityActionLogName(ability),
                            reason = "could not find a safe, worthwhile synthesized target plan",
                        })
                    end
                end
            else
                self:LogDecision("MOVE REJECTED", {
                    ability = ability.name,
                    action = self.AbilityActionLogName(ability),
                    reason = "not eligible for synthesized AI: " .. tostring(profileReason),
                })
            end
        end
    end

    return best
end


local function MoveForSynthesizedPlan(ai, token, loc)
    if loc == nil or ai:MovementTokenIsAtLoc(token, loc) then
        ai.Sleep(0.2)
        return false
    end
    ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
    ai.Sleep(0.6)
    return true
end

function MonsterAI:ExecuteSynthesizedAbilityPlan(token, plan)
    local ability = plan.ability
    self._tmp_synthesizedAbilitiesUsed = self:try_get("_tmp_synthesizedAbilitiesUsed", {})
    self._tmp_synthesizedAbilitiesUsed[SynthesizedAbilityKey(ability)] = true

    local moved = MoveForSynthesizedPlan(self, token, plan.loc)
    if plan.profile.targetType == "target" then
        local candidates = self:FindValidTargetsOfStrike(token, ability, token.loc)
        table.sort(candidates, function(a, b)
            return SynthesizedDefaultTargetScore(a) > SynthesizedDefaultTargetScore(b)
        end)
        local targets = {}
        for i=1,math.min(ability:GetNumTargets(token), #candidates) do
            targets[#targets+1] = candidates[i]
        end
        if #targets == 0 then
            return moved
        end
        self:ExecuteAbility(token, ability, targets)
        return true
    elseif plan.profile.targetType == "all" then
        local _, enemies, allies = self:SynthesizedBurstTargetsAtCurrentLoc(token, ability)
        if enemies == 0 or allies > 0 then
            return moved
        end
        self:ExecuteAbility(token, ability)
        return true
    end

    local targetLoc = cond(plan.profile.targetType == "cube", plan.center, plan.targetLoc)
    local area = BuildSynthesizedArea(token, ability, plan.profile.targetType, targetLoc)
    local targets, enemies, allies = self:SynthesizedTargetsInArea(token, ability, area)
    if enemies == 0 or allies > 0 then
        if type(area.Destroy) == "function" then
            area:Destroy()
        end
        return moved
    end

    local abilityClone = DeepCopy(ability)
    self:ExecuteAbility(token, abilityClone, targets, {
        symbols = {targetArea = area},
        targetArea = area,
    })
    if type(area.Destroy) == "function" then
        area:Destroy()
    end
    return true
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
    local searchContext = {}
    for key,value in pairs(self:try_get("_tmp_aiLogContext") or {}) do
        searchContext[key] = value
    end

    if not token.valid then
        self:LogDecision("MOVE SEARCH ABORTED", {
            reason = "token is no longer valid",
        })
        return false
    end

    if not token.properties:has_key("monster_type") then
        self:LogDecision("MOVE SEARCH ABORTED", {
            reason = "token has no monster type",
        })
        return false
    end

    local abilities = self.abilities
    local bestScore = {score = 0}
    local bestMove = nil

    if token.properties.minion then
        for _,ability in ipairs(abilities) do
            if ability.categorization == "Signature Ability" then
                if not ability:CanAfford(token) then
                    self:LogDecision("MOVE REJECTED", {
                        category = "Main Action",
                        move = "Minion Signature Ability",
                        ability = ability.name,
                        action = self.AbilityActionLogName(ability),
                        reason = AIAbilityUnavailableReason(token, ability),
                    })
                else
                    self:SetMoveLogContext(token, {
                        id = "Minion Signature Ability",
                        category = "Main Actions",
                    })
                    return self:ExecuteSquadStrike(ability)
                end
            end
        end

        self:LogDecision("MOVE SEARCH FINISHED", {
            reason = "minion has no affordable Signature Ability",
            result = "no legal move",
        })
        return false
    end

    for moveid,move in pairs(self.moves) do
        local registeredForMonster = self.MoveMatchesMonster(token, move, true)
        local matchesMonster = registeredForMonster and self.MoveMatchesMonster(token, move)

        local usingAbilities = {}
        if registeredForMonster and not matchesMonster then
            self:SetMoveLogContext(token, move)
            self:LogDecision("MOVE REJECTED", {
                ability = self.AbilitiesLogName(move.abilities),
                reason = "disabled for this monster in the Monster AI panel",
            })
        elseif matchesMonster and move.abilities ~= nil then
            for i=1,#move.abilities do
                local ability = FindAbilityByName(abilities, move.abilities[i])
                if ability == nil then
                    self:SetMoveLogContext(token, move)
                    self:LogDecision("MOVE REJECTED", {
                        ability = move.abilities[i],
                        reason = "required ability is not present on the actor",
                    })
                    matchesMonster = false
                    break
                end

                if not ability:CanAfford(token) then
                    self:SetMoveLogContext(token, move)
                    self:LogDecision("MOVE REJECTED", {
                        ability = ability.name,
                        action = self.AbilityActionLogName(ability),
                        reason = AIAbilityUnavailableReason(token, ability),
                    })
                    self:LogMove(self.token.properties.monster_type, moveid, "Could not afford", {onlyIfEmpty = true})
                    matchesMonster = false
                    break
                end

                usingAbilities[#usingAbilities+1] = ability
            end
        end
        
        if matchesMonster then
            self:SetMoveLogContext(token, move)
            self:LogDecision("MOVE SCORING", {
                ability = self.AbilitiesLogName(usingAbilities),
                action = self.AbilityActionsLogName(usingAbilities),
                result = "all required abilities are present and affordable",
            })
            local ok, score, scoringReason = pcall(
                move.score, move, self, token,
                usingAbilities[1], usingAbilities[2], usingAbilities[3])
            if not ok then
                self:LogDecision("MOVE ERROR", {
                    ability = self.AbilitiesLogName(usingAbilities),
                    reason = "scoring failed: " .. tostring(score),
                })
                error(score)
            elseif type(score) == "table" and type(score.score) == "number" then
                self:LogMove(self.token.properties.monster_type, moveid, string.format("Score: %.2f", score.score))
                self:LogDecision("MOVE CANDIDATE", {
                    ability = self.AbilitiesLogName(usingAbilities),
                    action = self.AbilityActionsLogName(usingAbilities),
                    score = score.score,
                    plan = self.ScoringPlanLogName(score),
                    result = score.score > 0 and "legal candidate" or "non-positive score",
                })
            else
                self:LogMove(self.token.properties.monster_type, moveid, "Could not make move", {onlyIfEmpty = true})
                self:LogDecision("MOVE REJECTED", {
                    ability = self.AbilitiesLogName(usingAbilities),
                    reason = scoringReason or (score == nil
                        and "score callback returned no legal plan"
                        or "score callback returned no numeric score"),
                })
            end
            if type(score) == "table" and type(score.score) == "number"
                and score.score > bestScore.score then
                score.usingAbilities = usingAbilities
                bestScore = score
                bestMove = move
            end
        end
    end

    local synthesizedMove = self:FindBestSynthesizedAbilityMove(
        token, abilities, self:GetClaimedAbilityNames(token))
    if synthesizedMove ~= nil and synthesizedMove.score > bestScore.score then
        local moveid = SynthesizedMoveId(synthesizedMove.ability)
        local synthesizedRegistration = {
            id = moveid,
            category = "Main Actions",
        }
        if synthesizedMove.profile.actionResource == CharacterResource.maneuverResourceId
            or synthesizedMove.profile.actionResource == CharacterResource.freeManeuverResourceId then
            synthesizedRegistration.category = "Maneuvers"
        else
            synthesizedRegistration.category = "Main Actions"
        end
        self:SetMoveLogContext(token, synthesizedRegistration)
        self:LogDecision("MOVE SELECTED", {
            ability = synthesizedMove.ability.name,
            action = self.AbilityActionLogName(synthesizedMove.ability),
            score = synthesizedMove.score,
            plan = self.ScoringPlanLogName(synthesizedMove),
            result = "synthesized fallback outranked registered moves",
        })
        local executed = self:ExecuteSynthesizedAbilityPlan(token, synthesizedMove)
        self:LogMove(self.token.properties.monster_type, moveid,
            cond(executed, "Executed synthesized move", "Synthesized move could not complete"))
        self:LogDecision("MOVE FINISHED", {
            ability = synthesizedMove.ability.name,
            result = executed and "executed" or "could not complete",
        })
        if executed then
            return true
        end
    elseif synthesizedMove ~= nil then
        local moveid = SynthesizedMoveId(synthesizedMove.ability)
        local synthesizedRegistration = {
            id = moveid,
            category = "Main Actions",
        }
        if synthesizedMove.profile.actionResource == CharacterResource.maneuverResourceId
            or synthesizedMove.profile.actionResource == CharacterResource.freeManeuverResourceId then
            synthesizedRegistration.category = "Maneuvers"
        end
        self:SetMoveLogContext(token, synthesizedRegistration)
        self:LogDecision("MOVE NOT SELECTED", {
            ability = synthesizedMove.ability.name,
            score = synthesizedMove.score,
            reason = string.format("score did not exceed selected registered move score %.3f", bestScore.score),
        })
    end

    if bestMove ~= nil then
        self:SetMoveLogContext(token, bestMove)
        self:LogDecision("MOVE SELECTED", {
            ability = self.AbilitiesLogName(bestScore.usingAbilities),
            action = self.AbilityActionsLogName(bestScore.usingAbilities),
            score = bestScore.score,
            plan = self.ScoringPlanLogName(bestScore),
            result = "highest-scoring legal registered move",
        })
        self:LogDecision("MOVE EXECUTION START", {
            ability = self.AbilitiesLogName(bestScore.usingAbilities),
        })
        bestMove.execute(bestMove, self, token, bestScore, bestScore.usingAbilities[1], bestScore.usingAbilities[2], bestScore.usingAbilities[3])
        self:LogMove(self.token.properties.monster_type, bestMove.id, "Executed move")
        self:LogDecision("MOVE FINISHED", {
            ability = self.AbilitiesLogName(bestScore.usingAbilities),
            result = "execution function completed",
        })
        return true
    end

    self:SetLogContext(token, searchContext)
    self:LogDecision("MOVE SEARCH FINISHED", {
        reason = "no move scored above zero",
        result = "no legal move",
    })
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
        self:LogDecision("ABILITY CAST REJECTED", {
            actor = self.TokenLogName(casterToken),
            actorId = casterToken ~= nil and casterToken.charid or nil,
            ability = ability.name,
            action = self.AbilityActionLogName(ability),
            reason = AIAbilityUnavailableReason(casterToken, ability),
        })
        return
    end

    options = options or {}
    local symbols = options.symbols or {}
    symbols.mode = symbols.mode or 1

    --Target filters read the symbols while cast behaviors read the options.
    --Keep both views on the exact area the AI selected.
    local targetArea = options.targetArea or symbols.targetArea
    if targetArea ~= nil then
        options.targetArea = targetArea
        symbols.targetArea = targetArea
    end
    local hasTargetArea = targetArea ~= nil or options.targetAreaList ~= nil

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
    elseif not hasTargetArea then
        --Placed areas already supply every creature inside the shape. Area
        --abilities report one target, so resizing would discard valid targets.
        local numTargets = ability:GetNumTargets(casterToken)
        table.resize_array(targets, numTargets)
    end

    --if this is a melee and ranged ability, choose the appropriate variation.
    if ability.meleeAndRanged then
        local usingCharge = false
        for _,target in ipairs(targets) do
            if target.charge ~= nil then
                usingCharge = true
                break
            end
        end

        if usingCharge then
            --Charge belongs only to the melee half of a dual-mode ability.
            ability = ability.meleeVariation
        else
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

            --freeMovement: the Charge's movement is part of the ability, not the
            --creature's move action (see the matching note in ExecuteSquadStrike).
            local path = self:MoveToken(token, target.charge, {maxCost = 10000, ignoreFalling = false, freeMovement = true})
            self.Sleep(1)
            target.charge = nil
        end
    end

    if targetArea ~= nil and options.telegraphArea ~= false then
        self:TelegraphAreaAbility(ability, targetArea, symbols)
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

    --The AI has already resolved which mode it is casting: callers pass a
    --SwitchModes clone plus a matching symbols.mode (or default to mode 1).
    --SwitchModes deliberately keeps multipleModes/modeList on its result, so
    --RequiresPromptWhenCast() would return true and ExecuteInvoke would route
    --this cast to the action bar's manual mode/target UI -- which, for a cast
    --whose targets are locs, builds an EMPTY symbols.allowedtargets and strands
    --the cast on an unanswerable "Choose Target" prompt. Clearing the flag
    --keeps the cast on the immediate Cast path. Note MakeTemporaryClone above
    --returns the SAME object when the ability is already a temporary clone
    --(e.g. entries in ai.abilities), so this write can land on the run's
    --cached instance -- benign, since AI mode switching works off modeList
    --and nothing else in a run reads multipleModes.
    ability.multipleModes = false

    local startedAt = dmhub.Time()
    self:LogDecision("ABILITY CAST START", {
        actor = self.TokenLogName(casterToken),
        actorId = casterToken ~= nil and casterToken.charid or nil,
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        targets = self.TargetsLogName(targets),
        mode = symbols.mode,
        targetType = ability.targetType,
    })
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

    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, ability, casterToken, "inherit", symbols, options)

    while not finished do
        coroutine.yield(0.1)
    end

    self:LogDecision("ABILITY CAST FINISHED", {
        actor = self.TokenLogName(casterToken),
        actorId = casterToken ~= nil and casterToken.charid or nil,
        ability = ability.name,
        action = self.AbilityActionLogName(ability),
        targets = self.TargetsLogName(targets),
        result = "OnFinishCast received",
        duration = dmhub.Time() - startedAt,
    })
    self.Sleep(options.sleep or 1.0)

    self:ResolvePendingMinionDeaths()

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
            self:ExecuteWithTheoreticalMovementLoc(self.token, destLoc, function()
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

                if not tok.properties.minion then
                    local claimedAbilities = self:GetClaimedAbilityNames(tok)
                    for _,ability in ipairs(tok.properties:GetActivatedAbilities()) do
                        if not claimedAbilities[ability.name] then
                            local profile = self:GetSynthesizedAbilityProfile(tok, ability)
                            if profile ~= nil then
                                resultEntry.moves[#resultEntry.moves+1] = {
                                    monsterType = monsterType,
                                    id = SynthesizedMoveId(ability),
                                    description = string.format(
                                        "Fallback AI generated at %.2f confidence from the ability's %s and targeting metadata.",
                                        profile.confidence, profile.reason),
                                    category = cond(profile.actionResource == CharacterResource.maneuverResourceId
                                        or profile.actionResource == CharacterResource.freeManeuverResourceId,
                                        "Maneuvers", "Main Actions"),
                                    abilities = {ability.name},
                                    enabled = true,
                                    synthesized = true,
                                }
                            end
                        end
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
                ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
                ai.Sleep(0.5)
            end
            ai:ExecuteAbility(token, ability)
        elseif ability.targetType == "target" then
            local loc = ai:FindBestMoveToUseStrike(token, ability)
            if loc == nil then
                TestAIMessage(string.format("could not find any position to use \"%s\" from.", ability.name))
                return
            end

            ai:MoveToken(token, loc, {maxCost = 10000, ignoreFalling = false})
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
    doc = "Usage: /testai <ability name> [tier1|tier2|tier3]\nMakes the Monster AI use the named ability, maneuver, or villain action with the selected token. Works in or out of combat and whether or not the AI is running. Grants any resources needed to execute (malice, actions, maneuvers, the villain action budget and used state, ability charges). Uses the registered AI move for the ability when one exists (even if disabled in the panel); otherwise falls back to a generic strike/burst execution. Minion signature abilities execute as a squad strike. Note: a villain action cast this way is marked used for the encounter by the normal cast pipeline.\n\nAdd tier1, tier2 or tier3 (before or after the ability name) to force every power roll made during the run to that tier -- the same as clicking that row on the power table after the dice land. The dice still roll; the result is overridden.",
    completions = function(args, argIndex)
        local result = {}

        --the tier argument may be given as a second word.
        if argIndex == 2 then
            result[#result+1] = {text = "tier1", summary = "force tier 1"}
            result[#result+1] = {text = "tier2", summary = "force tier 2"}
            result[#result+1] = {text = "tier3", summary = "force tier 3"}
            return result
        end

        if argIndex ~= 1 then return {} end
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
        --hosting capability, not chrome: the machine that runs the AI (a
        --player host included) must be able to drive it by hand.
        if not IsDMOrPlayerHost() then
            print("/testai: DM only.")
            return
        end

        local name = trim(str or "")

        --Optional tier1/tier2/tier3 argument, accepted at either end so both
        --`/testai Bury the Point tier3` and `/testai tier3 Bury the Point` work.
        --Parsed BEFORE the quote strip below, so a quoted ability name followed
        --by the tier word still unquotes. Lua patterns have no case-insensitive
        --classes, hence the spelled-out character sets.
        local forcedTier = nil
        local stripped, tierText = string.match(name, "^(.-)%s+[Tt][Ii][Ee][Rr]([123])$")
        if stripped == nil then
            tierText, stripped = string.match(name, "^[Tt][Ii][Ee][Rr]([123])%s+(.-)$")
        end
        if tierText ~= nil then
            forcedTier = tonumber(tierText)
            name = trim(stripped)
        end

        if string.sub(name, 1, 1) == "\"" and string.sub(name, -1) == "\"" and #name >= 2 then
            name = trim(string.sub(name, 2, #name - 1))
        end
        if name == "" then
            TestAIMessage("usage: /testai <ability name> [tier1|tier2|tier3]")
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

        --The run itself. Named rather than inlined into dmhub.Coroutine so the
        --forced-tier flag below can be cleared on every exit path -- the body has
        --several early returns and can also throw.
        local RunTestAI = function()
            local queue = dmhub.initiativeQueue
            if queue ~= nil and queue.hidden then
                queue = nil
            end

            if queue ~= nil then
                ai:SetupCombatants(token, queue)
            else
                TestAISetupOutOfCombat(ai, token)
            end
            ai:SetLogContext(token, {turn = "/testai"})

            ai.log.analysis = ai:Analysis()
            ai.log.updatedAnalysis = dmhub.GenerateGuid()

            ai.paths = ai:CalculateRemainingMovementPaths(token)

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
                ai:SetMoveLogContext(token, move)
                ai:LogDecision("MOVE SCORING", {
                    ability = ai.AbilitiesLogName(candidate.usingAbilities),
                    action = ai.AbilityActionsLogName(candidate.usingAbilities),
                    result = "/testai candidate",
                })
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
                        ai:LogDecision("MOVE CANDIDATE", {
                            ability = ai.AbilitiesLogName(candidate.usingAbilities),
                            action = ai.AbilityActionsLogName(candidate.usingAbilities),
                            score = scoringInfo.score,
                            plan = ai.ScoringPlanLogName(scoringInfo),
                            result = "legal /testai candidate",
                        })
                        if best == nil or scoringInfo.score > best.scoringInfo.score then
                            best = candidate
                        end
                    end
                else
                    ai:LogDecision("MOVE REJECTED", {
                        ability = ai.AbilitiesLogName(candidate.usingAbilities),
                        reason = "score callback returned no legal plan for /testai",
                    })
                end
            end

            if best ~= nil then
                local move = best.move
                TestAIMessage(string.format("%s: executing AI move \"%s\" (score %.2f).", tokenName, move.id, best.scoringInfo.score))
                ai:SetMoveLogContext(token, move)
                ai:LogDecision("MOVE SELECTED", {
                    ability = ai.AbilitiesLogName(best.usingAbilities),
                    action = ai.AbilityActionsLogName(best.usingAbilities),
                    score = best.scoringInfo.score,
                    plan = ai.ScoringPlanLogName(best.scoringInfo),
                    result = "/testai selected this registered move",
                })
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
                    ai:LogDecision("MOVE ERROR", {
                        reason = "execution failed: " .. tostring(err),
                    })
                else
                    ai:LogDecision("MOVE FINISHED", {
                        ability = ai.AbilitiesLogName(best.usingAbilities),
                        result = "/testai execution completed",
                    })
                end
                return
            end

            if #candidates > 0 then
                TestAIMessage(string.format("the AI declined to use \"%s\" right now (no registered move found a valid opportunity).", ability.name))
                return
            end

            TestAIMessage(string.format("%s: no AI move is registered for \"%s\"; using generic execution.", tokenName, ability.name))
            ai:SetMoveLogContext(token, {
                id = "/testai generic: " .. ability.name,
                category = ability:ActionResource() == CharacterResource.maneuverResourceId
                    and "Maneuvers" or "Main Actions",
            })
            ai:LogDecision("MOVE SELECTED", {
                ability = ability.name,
                action = ai.AbilityActionLogName(ability),
                result = "/testai generic execution",
            })
            TestAIExecuteGeneric(ai, token, ability)
            ai:WaitForAbilityIdle()
        end

        dmhub.Coroutine(function()
            --Same as a real AI turn: this drives monsters as the host, so it runs
            --with host permissions (see MonsterAI:PlayTurn).
            ElevateToHostPermissions()

            --test:aiforcetier is read by ActivatedAbilityPowerRollBehavior:Cast
            --as each power roll resolves; it stamps overrideTier onto the roll,
            --which is exactly what clicking that tier row would have done. It
            --applies to every power roll made while set, so keep it set for the
            --run and no longer.
            if forcedTier ~= nil then
                dmhub.SetSettingValue("test:aiforcetier", forcedTier)
                TestAIMessage(string.format("forcing tier %d for every power roll in this run.", forcedTier))
            end

            --RunYieldingFunction drives the body in a nested coroutine and hands
            --back any error rather than letting it escape, so the clear below
            --always runs.
            local ok, err = RunYieldingFunction(RunTestAI)

            if forcedTier ~= nil then
                dmhub.SetSettingValue("test:aiforcetier", 0)
            end

            if not ok then
                TestAIMessage(string.format("run failed: %s", tostring(err)))
            end

            DropHostPermissions()
        end)
    end,
}
