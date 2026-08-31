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
        if MonsterAI.active then
            local ai = MonsterAI.new{}
            ai:HandleVillainActionWindow(context)
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
            return
        end

        local queue = dmhub.initiativeQueue


        --check for registered triggered abilities.
        local handledTrigger = false
        if queue ~= nil and (not queue.hidden) then
            for _,token in ipairs(dmhub.allTokens) do
                if not token.playerControlled then
                    local triggers = token.properties:GetAvailableTriggers()
                    if triggers ~= nil then
                        local ai = MonsterAI.new{token = token}
                        for _,trigger in pairs(triggers) do
                            if ai:HandleAvailableTrigger(token, trigger) then
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


        if (not handledTrigger) and queue ~= nil and (not queue.hidden)
            and not GameHud.BetweenTurnTransitionInProgress() and (not queue:IsPlayersTurn()) then
            local initiativeid = queue:CurrentInitiativeId()

            if initiativeid == nil then
                local entriesUnmoved = queue:EntriesUnmoved()

                local bestScore = nil
                for k,_ in pairs(entriesUnmoved) do
                    if not queue:IsEntryPlayer(k) then

                        local distance = nil
                        local tokens = GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, k)
                        local allTokens = dmhub.allTokens
                        for _,tok in ipairs(allTokens) do
                            if tok.playerControlled then
                                for _,mtok in ipairs(tokens) do
                                    local d = tok:Distance(mtok)
                                    if distance == nil or d < distance then
                                        distance = d
                                    end
                                end
                            end
                        end

                        distance = distance or 0
                        lifecycleAI:SetLogContext(nil, {
                            turn = k,
                            round = queue.round,
                        })
                        lifecycleAI:LogDecision("INITIATIVE CANDIDATE", {
                            distance = distance,
                            reason = "lower nearest-player distance acts first",
                        })
                        if bestScore == nil or distance < bestScore then
                            bestScore = distance
                            initiativeid = k
                        end
                    end
                end

                if initiativeid ~= nil then
                    lifecycleAI:SetLogContext(nil, {
                        turn = initiativeid,
                        round = queue.round,
                    })
                    lifecycleAI:LogDecision("INITIATIVE SELECTED", {
                        distance = bestScore,
                        result = "beginning non-player initiative entry",
                    })
                    dmhub.initiativeQueue:SelectTurn(initiativeid)
                    dmhub:UploadInitiativeQueue()

                    local centerOn = nil
                    local tokens = GameHud.GetTokensForInitiativeId(GameHud.instance, GameHud.instance.initiativeInterface, initiativeid)
                    for i,tok in ipairs(tokens) do
                        if tok.properties ~= nil then
                            tok.properties:BeginTurn()
                            if centerOn == nil or not tok.properties.minion then
                                centerOn = tok
                            end
                        end
                    end

                    if centerOn ~= nil then
                        dmhub.CenterOnToken(centerOn.charid, {smooth = true})

                        dmhub.SyncCamera{
                            speed = 1,
                        }

                        MonsterAI.Sleep(1)
                    end
                end
            else
                local ai = MonsterAI.new{}
                g_status = "Playing Turn"
                ai:PlayTurnCoroutine(initiativeid)
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
    end
end

--Programmatic start/stop for the AI background process -- the same calls the
--panel's Start AI button makes, exported so automated game modes (Encounter
--of the Week) can run the AI with no Director UI. The process is registered
--under the Monster AI panel but is independent of the panel being openable,
--so this works on a client whose dmonly panels are hidden.
function MonsterAI.StartAI()
    g_terminate = false
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
                        element.text = g_status or "Active"
                    end
                else
                    m_running = false
                    MonsterAI.active = false
                    element.text = "Not Running"
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
