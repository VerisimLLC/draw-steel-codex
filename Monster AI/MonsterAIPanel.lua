local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local MonsterAIPanel

DockablePanel.Register{
    name = "Monster AI",
    icon = "phosphor/cpu-light.png",
    minHeight = 60,
    dmonly = true,
    content = function()
        track("panel_open", {
            panel = "Monster AI",
            dailyLimit = 30,
        })
        return MonsterAIPanel()
    end,
}

local g_thread = nil
local g_terminate = false
local g_status = nil

--Save cards disappear on acceptance, but their shared reaction markers remain
--until the roll finishes on the accepting client. Neither state has a timer.
local function FindPendingPlayerSave(queue)
    for _,token in ipairs(dmhub.allTokens) do
        if MonsterAI.TokenIsLiveCombatant(token) and token.playerControlled then
            local initiativeid = InitiativeQueue.GetInitiativeId(token)
            if initiativeid ~= nil and queue.entries[initiativeid] ~= nil then
                --The second return is the save prompt's key in availableTriggers.
                for reactionId,entry in pairs(token.properties:try_get("pendingAIActivityReactions", {})) do
                    if type(entry) == "table" and entry.activityId == "end-turn-save" and entry.state ~= "completed" then
                        return token, reactionId
                    end
                end
                --Also recognize cards posted before these clients were updated.
                for key,trigger in pairs(token.properties:GetAvailableTriggers(true) or {}) do
                    local invocation = trigger.invocation
                    if not trigger.dismissed and invocation ~= nil and invocation ~= false
                        and invocation:try_get("standardAbility") == "End Turn Saving Throw" then
                        return token, key
                    end
                end
            end
        end
    end
    return nil
end

--Seconds a relayed trigger event may hold the monsters while the hero's client
--evaluates it. Normally gone in a fraction of a second; an offline recipient
--must not hold the table longer than this.
local g_relayedTriggerWaitSeconds = 10

--Whether this hero prompt makes the monsters wait before taking a turn. Any
--prompt the player has not answered counts (Showdown at the start of a round,
--Hesitation Is Weakness, a custom class's trigger), except harm forced on the
--hero, roll modifiers (they belong to a roll in progress) and the hidden
--members of a merged prompt. Dismissing the prompt releases the wait.
---@param trigger ActiveTrigger
---@return boolean
local function PromptHoldsMonsterTurn(trigger)
    return not trigger.dismissed
        and not trigger:try_get("hostile", false)
        and trigger:try_get("powerRollModifier", false) == false
        and trigger:try_get("mergedInto", false) == false
end

--A trigger event the host relayed to the hero's player (Begin Round for
--Showdown) that their client has not evaluated yet. Their prompt does not
--exist until it has, so without this the monsters could take the turn first.
local function HasRelayedTriggerInFlight(token)
    for key,event in pairs(token.properties:try_get("triggeredEvents", {})) do
        if key ~= "version" and type(event) == "table" and type(event.userid) == "string"
            and TimestampAgeInSeconds(event.timestamp) < g_relayedTriggerWaitSeconds then
            return true
        end
    end
    return false
end

--A start-of-round reaction (see creature:DispatchBeginRound) the hero has not
--finished. Accepting the prompt clears its card while the cast it starts --
--Showdown's target pick -- is still running; the marker on the hero's token
--covers that gap on whichever machine runs the cast. A marker that can no
--longer be confirmed releases the wait, so a lost reaction cannot stall the table.
---@param token CharacterToken
---@param activityId string|nil
---@return string|nil description
local function PendingRoundStartReaction(token, activityId)
    if activityId == nil then
        return nil
    end
    local ok, pending, description, failure = pcall(token.properties.GetAIActivityReactionStatus, token.properties, activityId)
    if not ok or failure ~= nil or pending == 0 then
        return nil
    end
    return description or "reaction"
end

--A hero's trigger the monsters wait for before choosing their next turn: a
--hero may use it to claim the turn or to act before the monsters do. Returns
--the token and its prompt; the token, nil and a description while a
--start-of-round reaction is still resolving; or the token and nil while a
--relayed event is still being evaluated on its player's client. Data-driven,
--so custom classes work.
---@return CharacterToken|nil, ActiveTrigger|nil, string|nil
local function FindPendingPlayerTrigger(queue)
    local relayToken = nil
    local reactionToken, reactionText = nil, nil
    local roundActivityId = creature.RoundStartAIActivityId(queue)
    for _,token in ipairs(dmhub.allTokens) do
        if MonsterAI.TokenIsLiveCombatant(token) and token.playerControlled then
            local initiativeid = InitiativeQueue.GetInitiativeId(token)
            if initiativeid ~= nil and queue:IsEntryPlayer(initiativeid) then
                for _,trigger in pairs(token.properties:GetAvailableTriggers(true) or {}) do
                    if PromptHoldsMonsterTurn(trigger) then
                        return token, trigger
                    end
                end
                if reactionToken == nil then
                    local description = PendingRoundStartReaction(token, roundActivityId)
                    if description ~= nil then
                        reactionToken, reactionText = token, description
                    end
                end
                if relayToken == nil and HasRelayedTriggerInFlight(token) then
                    relayToken = token
                end
            end
        end
    end

    if reactionToken ~= nil then
        return reactionToken, nil, reactionText
    end
    return relayToken, nil, nil
end

--The banner text for a FindPendingPlayerTrigger result.
---@param token CharacterToken
---@param trigger ActiveTrigger|nil
---@param reactionText string|nil
local function PendingPlayerTriggerText(token, trigger, reactionText)
    if trigger == nil then
        if reactionText ~= nil then
            return string.format("Waiting for %s's %s", token.name or "a hero", reactionText)
        end
        return string.format("Waiting for %s's triggers", token.name or "a hero")
    end
    local name = trigger.abilityName
    if type(name) ~= "string" or name == "" then
        local ok, text = pcall(function() return trigger:GetText() end)
        name = (ok and type(text) == "string" and text ~= "") and text or "trigger"
    end
    return string.format("Waiting for %s's %s", token.name or "a hero", name)
end

MonsterAI:RegisterTrigger{
    id = "Opportunity Attack",
    triggers = {"Opportunity Attack"},
    description = "Automatically use opportunity attacks offered to non-player creatures.",
    handler = function(ai, token, triggerInfo)
        return {activate = true}
    end,
}

GameHud.RegisterBetweenTurnHandler{
    id = "Monster AI Villain Actions",
    priority = 50,
    run = function(context)
        if MonsterAI.active and MonsterAI.IsAIRunning() then
            local ai = MonsterAI.new{}
            local ok, err = ai:RunYieldingFunction(function()
                ai:HandleVillainActionWindow(context)
            end)
            if not ok then
                pcall(function()
                    ai:LogDecision("VILLAIN ACTION ERROR", {
                        reason = tostring(err),
                        result = "between-turn handler continuing",
                    })
                end)
            end
        end
    end,
}

--Runs as a DockablePanel background process (see "Panel background
--processes" in DockablePanel.lua): registered from the Start AI button,
--it keeps taking monster turns even if the Monster AI panel is closed,
--and the panel's icon-rail button spins its gear while this runs. The
--process handle's stopRequested is the systemic stop signal (StopProcess
--or a replacing StartProcess); g_terminate remains the panel's own local
--stop flag, and both routes end the thread here.
local function MonsterAIThread(process)
    --The AI thread acts for the machine HOSTING the game, never for its user:
    --it drives monsters, takes their turns and answers their triggers. Elevating
    --the whole thread means every engine call it makes reports real hosting
    --status, so player rules enforcement does not bind it on a player host
    --(Encounter of the Week). The elevation is parked whenever this coroutine
    --yields -- which is most of the time -- so the user keeps player vision and
    --player UI, and it is discarded outright when the thread ends.
    --Turns run in their OWN coroutine (MonsterAI:PlayTurn), which elevates itself.
    ElevateToHostPermissions()

    local lifecycleAI = MonsterAI.new{}
    lifecycleAI:LogDecision("AI STARTED", {
        result = "background process is active",
    })
    MonsterAI.active = true
    g_status = nil
    local failedTriggers = {}
    --Set while the watcher holds initiative open for a hero's pending trigger
    --(FindPendingPlayerTrigger); lets the loop clear the notice once without a
    --document read per iteration.
    local turnClaimWaiting = false
    local saveWaiting = false
    --The monster turn this process last began. The turn is not played until its
    --start-of-turn triggers have finished. nil for turns begun by anyone else.
    local turnStart = nil
    MonsterAI.ClearWaiting()
    pcall(MonsterAI.ClearPlanPreview)
    creature.SetAIActivityInProgress(nil)
    creature.ClearAIControl()
    while true do
        g_thread = coroutine.running()
        coroutine.yield(0.1)
        if mod.unloaded or g_terminate or (process ~= nil and process.stopRequested) then
            MonsterAI.active = false
            lifecycleAI:LogDecision("AI STOPPED", {
                reason = mod.unloaded and "Monster AI module unloaded"
                    or g_terminate and "stop requested from the Monster AI panel"
                    or "background process stop requested",
            })
            pcall(MonsterAI.ClearWaiting)
            pcall(MonsterAI.ClearPlanPreview)
            pcall(creature.SetAIActivityInProgress, nil)
            --a turn abandoned mid-action never reaches its EndTokenControl.
            pcall(creature.ClearAIControl)
            return
        end

        --Keep an unexpected selection, trigger, or camera error from killing the
        --background process. Turn execution has its own narrower recovery guard.
        local iterationOk, iterationErr = lifecycleAI:RunYieldingFunction(function()

        local queue = dmhub.initiativeQueue

        local saveProf = MonsterAI.ProfBegin("thread: pending save check")
        local pendingSave, saveTriggerId = nil, nil
        if queue ~= nil and not queue.hidden then
            pendingSave, saveTriggerId = FindPendingPlayerSave(queue)
        end
        MonsterAI.ProfEnd(saveProf)
        if pendingSave ~= nil then
            MonsterAI.SetWaiting("save", string.format("Waiting for %s's saving throw", pendingSave.name),
                {charid = pendingSave.charid, triggerid = saveTriggerId})
            saveWaiting = true
        elseif saveWaiting then
            saveWaiting = false
            MonsterAI.ClearWaiting()
        end

        --Drop the notice the moment the hero's trigger stops being pending:
        --the hero used it (a turn claim makes their turn live, so the selection
        --block below is skipped), dismissed it, or the queue moved on. Checked
        --here, ahead of every early exit, so the banner never outlives the
        --wait; only paid while a wait is on.
        if turnClaimWaiting then
            local stillPending = queue ~= nil and (not queue.hidden)
                and (not queue:IsPlayersTurn()) and queue:CurrentInitiativeId() == nil
                and FindPendingPlayerTrigger(queue) ~= nil
            if not stillPending then
                turnClaimWaiting = false
                MonsterAI.ClearWaiting()
            end
        end

        --check for registered triggered abilities.
        local handledTrigger = false
        if queue ~= nil and (not queue.hidden) then
            for _,token in ipairs(dmhub.allTokens) do
                if MonsterAI.TokenIsLiveCombatant(token) and not token.playerControlled then
                    local pollProf = MonsterAI.ProfBegin("thread: trigger poll")
                    local triggers = token.properties:GetAvailableTriggers()
                    MonsterAI.ProfEnd(pollProf)
                    if triggers ~= nil then
                        local ai = MonsterAI.new{token = token}
                        for _,trigger in pairs(triggers) do
                            local triggerKey = string.format("%s:%s",
                                tostring(token.charid), tostring(trigger.id))
                            local triggerHandled = false
                            local ok = true
                            local err = nil
                            if not failedTriggers[triggerKey] then
                                ok, err = ai:RunYieldingFunction(function()
                                    triggerHandled = ai:HandleAvailableTrigger(token, trigger)
                                end)
                            end
                            if not ok then
                                failedTriggers[triggerKey] = true
                                pcall(function()
                                    if MonsterAI.TokenIsLiveCombatant(token) then
                                        token:ModifyProperties{
                                            description = "AI Trigger Recovery",
                                            undoable = false,
                                            execute = function()
                                                local liveTriggers = token.properties:GetAvailableTriggers() or {}
                                                local liveTrigger = liveTriggers[trigger.id]
                                                if liveTrigger ~= nil and not liveTrigger.triggered
                                                    and not liveTrigger.dismissed then
                                                    liveTrigger.dismissed = true
                                                    token.properties:DispatchAvailableTrigger(liveTrigger)
                                                end
                                            end,
                                        }
                                    end
                                end)
                                pcall(function()
                                    ai:LogDecision("TRIGGER ERROR", {
                                        category = "Triggered Action",
                                        ability = trigger.abilityName,
                                        reason = tostring(err),
                                        result = "trigger dismissed and quarantined for this AI run",
                                    })
                                end)
                            elseif triggerHandled then
                                handledTrigger = true
                                break
                            end
                        end
                    end
                end

                if handledTrigger then
                    break
                end
            end
        end


        if pendingSave ~= nil then return end

        if (not handledTrigger) and queue ~= nil and (not queue.hidden)
            and not GameHud.BetweenTurnTransitionInProgress() and (not queue:IsPlayersTurn()) then
            local initiativeid = queue:CurrentInitiativeId()
            if initiativeid == nil then
                local claimToken, claimTrigger, claimReaction = FindPendingPlayerTrigger(queue)
                if claimToken ~= nil then
                    --Tell the table why the monsters are not moving. The banner's
                    --Dismiss (offered when there is a prompt) releases the wait.
                    local text = PendingPlayerTriggerText(claimToken, claimTrigger, claimReaction)
                    if not turnClaimWaiting then
                        lifecycleAI:LogDecision("INITIATIVE WAITING", {
                            actor = MonsterAI.TokenLogName(claimToken),
                            reason = text,
                        })
                    end
                    MonsterAI.SetWaiting("turnclaim", text,
                        {charid = claimToken.charid, triggerid = claimTrigger ~= nil and claimTrigger.id or nil})
                    turnClaimWaiting = true
                    return
                end
            end

            if initiativeid == nil then
                local entriesUnmoved = queue:EntriesUnmoved()
                local choicePhase = MonsterAI.ProfPhaseBegin("initiative choice")

                --The waiting monster groups with someone alive in them.
                local groups = {}
                for k,_ in pairs(entriesUnmoved) do
                    if not queue:IsEntryPlayer(k) then
                        local members = {}
                        for _,tok in ipairs(GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, k)) do
                            if MonsterAI.TokenIsLiveCombatant(tok) then
                                members[#members+1] = tok
                            end
                        end
                        if #members > 0 then
                            groups[#groups+1] = {initiativeid = k, members = members}
                        end
                    end
                end

                --See "Initiative choice" in MonsterAI.lua for the rule.
                local bestScore = nil
                local bestInitiativeId = nil
                if #groups == 1 then
                    --nothing to choose between.
                    bestInitiativeId = groups[1].initiativeid
                end
                for groupIndex,group in ipairs(#groups > 1 and groups or {}) do
                    local k = group.initiativeid
                    --Each member's bid with its random factor, highest first. The
                    --first member that can strike sets the group's score: any bid
                    --that can strike beats any bid that cannot.
                    local bids = {}
                    for _,tok in ipairs(group.members) do
                        local priority = MonsterAI.TurnPriority(tok)
                        local heat = 1 + math.random()*0.5
                        bids[#bids+1] = {token = tok, priority = priority, heat = heat, bid = priority*heat}
                    end
                    table.sort(bids, function(a, b)
                        if a.bid ~= b.bid then
                            return a.bid > b.bid
                        end
                        return tostring(a.token.charid) < tostring(b.token.charid)
                    end)

                    local groupScore = nil
                    ---@type CharacterToken?
                    local groupActor = nil
                    for _,bid in ipairs(bids) do
                        local candidateAI = MonsterAI.new{}
                        candidateAI:SetLogContext(bid.token, {
                            turn = k,
                            round = queue.round,
                        })
                        local candidatePhase = MonsterAI.ProfPhaseBegin("can strike: " .. MonsterAI.TokenLogName(bid.token))
                        candidateAI:SetupCombatants(bid.token, queue)
                        local canStrike, reason = candidateAI:CanStrikeThisTurn(bid.token)
                        MonsterAI.ProfPhaseEnd(candidatePhase, reason)
                        local score = canStrike and bid.bid or bid.bid*MonsterAI.initiativeCannotStrikeFactor
                        candidateAI:LogDecision("INITIATIVE ACTOR CANDIDATE", {
                            priority = bid.priority,
                            heat = bid.heat,
                            score = score,
                            canStrike = canStrike,
                            reason = reason,
                        })
                        if groupScore == nil or score > groupScore then
                            groupScore = score
                            groupActor = bid.token
                        end
                        if canStrike then
                            break
                        end
                    end

                    if groupActor ~= nil then
                        lifecycleAI:SetLogContext(groupActor, {
                            turn = k,
                            round = queue.round,
                        })
                        lifecycleAI:LogDecision("INITIATIVE CANDIDATE", {
                            score = groupScore,
                            reason = "highest bid in the initiative group",
                        })
                        if bestScore == nil or groupScore > bestScore
                            or (groupScore == bestScore and tostring(k) < tostring(bestInitiativeId)) then
                            bestScore = groupScore
                            bestInitiativeId = k
                        end
                    end

                    --A check can need a pathfinding area; keep each frame short.
                    if groupIndex < #groups then
                        coroutine.yield(0.01)
                    end
                end
                initiativeid = bestInitiativeId
                MonsterAI.ProfPhaseEnd(choicePhase, string.format("picked %s", tostring(initiativeid)))

                if initiativeid ~= nil and dmhub.initiativeQueue == queue
                    and queue:ChoosingTurn() and not queue:IsPlayersTurn()
                    and FindPendingPlayerSave(queue) == nil
                    and FindPendingPlayerTrigger(queue) == nil
                    and queue:EntriesUnmoved()[initiativeid] ~= nil then
                    lifecycleAI:SetLogContext(nil, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    lifecycleAI:LogDecision("INITIATIVE SELECTED", {
                        score = bestScore,
                        result = "beginning non-player initiative entry",
                    })
                    dmhub.initiativeQueue:SelectTurn(initiativeid)
                    dmhub:UploadInitiativeQueue()

                    local tokens = GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, initiativeid)
                    local pending = {count = 0}
                    turnStart = {initiativeid = initiativeid, activityId = "turn-start:" .. dmhub.GenerateGuid(), pending = pending}
                    for i,tok in ipairs(tokens) do
                        if tok.properties ~= nil then
                            pending.count = pending.count + 1
                            tok.properties:BeginTurn{
                                aiActivityId = turnStart.activityId,
                                onComplete = function()
                                    pending.count = pending.count - 1
                                end,
                            }
                        end
                    end
                end
            else
                local ai = MonsterAI.new{}
                if turnStart ~= nil and turnStart.initiativeid == initiativeid then
                    ai:SetLogContext(nil, {turn = initiativeid, round = queue.round})
                    if not ai:WaitForTurnStart(turnStart) then
                        return
                    end
                end
                turnStart = nil
                g_status = "Playing Turn"
                ai:PlayTurnSafely(initiativeid)
                g_status = nil

                --center back on a player.
                local centerOn = nil
                local entriesUnmoved = queue:EntriesUnmoved()
                for k,_ in pairs(entriesUnmoved) do
                    if queue:IsEntryPlayer(k) then
                        local tokens = GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, k)
                        for i,tok in ipairs(tokens) do
                            if centerOn == nil or not tok.properties.minion then
                                centerOn = tok
                            end
                        end
                    end
                end

                if centerOn ~= nil then
                    dmhub.CenterOnToken(centerOn.charid, {smooth = true})
                    dmhub.SyncCamera{
                        speed = 1,
                    }
                end
            end
        end
        end)

        if not iterationOk then
            g_status = nil
            pcall(function()
                lifecycleAI:LogDecision("AI ITERATION ERROR", {
                    reason = tostring(iterationErr),
                    result = "background process continuing",
                })
            end)
            coroutine.yield(0.5)
        end
    end
end

--Programmatic start/stop for the AI background process -- the same calls the
--panel's Start AI button makes, exported so automated game modes (Encounter
--of the Week) can run the AI with no Director UI. The process is registered
--under the Monster AI panel but is independent of the panel being openable,
--so this works on a client whose dmonly panels are hidden.
function MonsterAI.StartAI()
    g_terminate = false
    MonsterAI.reactionStatus = false
    MonsterAI.reactionFailure = false
    MonsterAI.active = true
    DockablePanel.StartProcess{
        panel = "Monster AI",
        id = "monster-ai",
        coroutine = MonsterAIThread,
    }
end

function MonsterAI.StopAI()
    g_terminate = true
    MonsterAI.active = false
    DockablePanel.StopProcess("Monster AI", "monster-ai")
end

--True while the AI thread is running (it may take a beat to wind down after
--StopAI; MonsterAI.active flips false as soon as a stop is requested).
function MonsterAI.IsAIRunning()
    return DockablePanel.HasActiveProcess("Monster AI")
end

--- True when the running AI plays this creature's rolls: the AI runs on this
--- client, this client hosts the game, and no player controls the creature's
--- token. Such rolls happen outside the AI's own actions too (a War Dog's
--- Loyalty Collar exploding on a hero's turn), and the roll dialog rolls and
--- accepts them itself instead of waiting for the Director.
--- @param subject creature|nil
--- @return boolean
function MonsterAI.RollsForCreature(subject)
    if subject == nil or MonsterAI.active ~= true or not MonsterAI.IsAIRunning() or not IsDMOrPlayerHost() then
        return false
    end
    --pcall: the token may be one that has left the map.
    local ok, directorRun = pcall(function()
        local token = nil
        local tokenid = dmhub.LookupTokenId(subject)
        if tokenid ~= nil then
            token = dmhub.GetCharacterById(tokenid)
        else
            --A dying minion can already be off the map when its own roll comes
            --up (its Loyalty Collar), and then nothing finds its token by
            --creature. The roll runs inside that creature's cast, which still
            --holds it.
            local castInfo = ActivatedAbility.CurrentCastInfo()
            if castInfo ~= nil and castInfo.casterToken ~= nil and castInfo.casterToken.properties == subject then
                token = castInfo.casterToken
            end
        end
        return token ~= nil and token.playerControlled == false
    end)
    return ok and directorRun == true
end

--- The prompt handler for an invoke raised by a creature the AI plays but is
--- not driving at this moment, such as a dying Abyssal Hyena's Death Snap on a
--- hero's turn: mandatory triggers fire with no AI control installed. Same rule
--- as RollsForCreature. A prompt with no registered handler still goes to the
--- Director. nil when the AI does not play this creature.
--- @param token CharacterToken
--- @return nil|fun(invokerToken: CharacterToken, casterToken: CharacterToken, abilityClone: ActivatedAbility, symbols: table, options: table): string
function MonsterAI.PromptCallbackForCreature(token)
    if token == nil or token.properties == nil or not MonsterAI.RollsForCreature(token.properties) then
        return nil
    end
    return function(invokerToken, casterToken, abilityClone, symbols, options)
        local ai = MonsterAI.new{token = invokerToken}
        return ai:HandlePrompt(invokerToken, casterToken, abilityClone, symbols, options)
    end
end

MonsterAIPanel = function()
    local resultPanel
    local m_status
    local m_running = false
    local m_analysisUpdate = nil

    local m_analysisPanels = {}

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            fontSize = 16,
            width = "auto",
            height = "auto",
            thinkTime = 0.1,
            think = function(element)
                if MonsterAI.log.updatedAnalysis ~= nil and MonsterAI.log.updatedAnalysis ~= m_analysisUpdate then
                    m_analysisUpdate = MonsterAI.log.updatedAnalysis
                    resultPanel:FireEventTree("analysis")
                end

                m_status = g_thread ~= nil and coroutine.status(g_thread)
                if m_status == "suspended" or m_status == "running" then
                    m_running = true
                    if g_terminate then
                        element.text = "Stopping..."
                    else
                        element.text = MonsterAI.reactionFailure or MonsterAI.reactionStatus or g_status or "Active"
                    end
                else
                    m_running = false
                    MonsterAI.active = false
                    element.text = MonsterAI.reactionFailure or "Not Running"
                end
                resultPanel:FireEventTree("refreshai")
            end,

            hover = function(element)
                m_status = g_thread ~= nil and coroutine.status(g_thread)
                if m_status == "suspended" or m_status == "running" then
                    gui.Tooltip(debug.traceback(g_thread))(element)
                end
            end,
        },

        gui.Button{
            text = "Start AI",
            width = 100,
            height = 30,
            fontSize = 14,
            refreshai = function(element)
                element.text = m_running and "Stop AI" or "Start AI"
            end,
            click = function()
                if m_running then
                    MonsterAI.StopAI()
                else
                    --a background process rather than a bare coroutine:
                    --the AI keeps playing turns if this panel closes, and
                    --the rail button's gear spins while it runs.
                    MonsterAI.StartAI()
                end
            end,
        },

        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            analysis = function(element)
                element:FireEvent("think")
            end,
            thinkTime = 3,
            think = function(element)
                local analysis = MonsterAI.log.analysis
                if analysis == nil then
                    local ai = MonsterAI.new{}
                    analysis = ai:Analysis()
                end
                for i,entry in ipairs(analysis) do
                    m_analysisPanels[i] = m_analysisPanels[i] or gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "vertical",
                        data = {
                            movePanels = {},
                            categoryHeadings = {},
                        },
                        setanalysis = function(element, entry)
                            local children = {}
                            local currentCategory = ""
                            local newCategoryHeadings = {}

                            for j,moveEntry in ipairs(entry.moves) do

                                if moveEntry.category ~= currentCategory then
                                    currentCategory = moveEntry.category or "Main Actions"
                                    local headingPanel = element.data.categoryHeadings[currentCategory] or gui.Label{
                                        fontSize = 16,
                                        width = "100%",
                                        height = "auto",
                                        bold = true,
                                        text = string.format("<u>%s</u>", currentCategory),
                                    }
                                    children[#children+1] = headingPanel
                                    newCategoryHeadings[currentCategory] = headingPanel
                                end

                                local movePanel = element.data.movePanels[j]
                                if movePanel == nil then
                                    movePanel = gui.Panel{
                                        width = "100%",
                                        height = "auto",
                                        flow = "vertical",

                                        gui.Panel{
                                            flow = "horizontal",
                                            width = "100%-16",
                                            height = "auto",
                                            lmargin = 8,
                                            gui.Check{
                                                text = "",
                                                width = 12,
                                                height = 16,
                                                minWidth = 12,
                                                valign = "center",
                                                value = true,
                                                setmove = function(element, moveEntry)
                                                    element:SetClass("hidden", moveEntry.id == "Minion Signature Ability" or moveEntry.synthesized)
                                                    element.value = MonsterAI:IsMoveEnabledForMonster(moveEntry.monsterType, moveEntry.id)
                                                    element.data.moveEntry = moveEntry
                                                end,
                                                change = function(element)
                                                    if element.data.moveEntry ~= nil then
                                                        MonsterAI:SetMoveEnabledForMonster(element.data.moveEntry.monsterType, element.data.moveEntry.id, element.value)
                                                    end
                                                end,
                                            },
                                            gui.Label{
                                                fontSize = 16,
                                                hmargin = 4,
                                                halign = "left",
                                                width = "100%-32",
                                                height = "auto",
                                                hover = function(element)
                                                    if element.data.tooltip ~= nil then
                                                        gui.Tooltip(element.data.tooltip)(element)
                                                    end
                                                end,
                                                setmove = function(element, moveEntry)
                                                    element.data.tooltip = moveEntry.description
                                                    local name = moveEntry.id
                                                    local abilities = moveEntry.abilities
                                                    if #abilities == 0 or (#abilities == 1 and abilities[1] == name) then
                                                        element.text = string.format("<b>%s</b>", name)
                                                    else
                                                        element.text = string.format("<b>%s</b> (%s)", name, table.concat(abilities,","))
                                                    end
                                                end,
                                            },
                                        },
                                        gui.Label{
                                            fontSize = 14,
                                            lmargin = 8,
                                            width = "100%-16",
                                            height = "auto",
                                            setmove = function(element, moveEntry)
                                                if moveEntry.log then
                                                    element.text = table.concat(moveEntry.log or {}, "\n")
                                                else
                                                    element.text = ""
                                                end
                                            end,
                                        }
                                    }
                                    element.data.movePanels[j] = movePanel
                                end

                                movePanel:FireEventTree("setmove", moveEntry)
                                children[#children+1] = movePanel
                            end

                            while #element.data.movePanels > #entry.moves do
                                element.data.movePanels[#element.data.movePanels] = nil
                            end

                            element.children[2].children = children
                            element.data.categoryHeadings = newCategoryHeadings
                        end,

                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            gui.Panel{
                                classes = {"expanded"},
                                styles = gui.TriangleStyles,
                                bgimage = "panels/triangle.png",
                                bgcolor = "white",
                                width = 8,
                                height = 8,
                                valign = "top",
                                press = function(element)
                                    element:SetClass("expanded", not element:HasClass("expanded"))
                                    local parent = element.parent.parent
                                    parent.children[2]:SetClass("collapsed", not element:HasClass("expanded"))
                                end,
                            },
                            gui.Label{
                                fontSize = 16,
                                width = "100%",
                                height = "auto",
                                setanalysis = function(element, entry)
                                    local text = entry.monsterType
                                    if entry.language ~= nil then
                                        text = string.format("<b><u>%s</u></b>\nCommunicates in %s", text, entry.language.name)
                                    else
                                        text = string.format("<b><u>%s</u></b>\nNo language", text)
                                    end
                                    element.text = text
                                end,
                            },
                        },

                        gui.Panel{
                            width = "100%-16",
                            height = "auto",
                            flow = "vertical",
                            halign = "right",
                        }
                    }

                    m_analysisPanels[i]:FireEventTree("setanalysis", entry)
                end

                while #m_analysisPanels > #analysis do
                    m_analysisPanels[#m_analysisPanels] = nil
                end

                element.children = m_analysisPanels
            end,
        },
    }


    return resultPanel
end
