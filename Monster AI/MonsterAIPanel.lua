local mod = dmhub.GetModLoading()

local MonsterAIPanel

DockablePanel.Register{
    name = "Monster AI",
    minHeight = 60,
    dmonly = true,
    content = function()
        return MonsterAIPanel()
    end,
}

local g_thread = nil
local g_terminate = false
local g_status = nil

local function MonsterAIThread()
    g_status = nil
    while true do
        g_thread = coroutine.running()
        coroutine.yield(0.1)
        if mod.unloaded or g_terminate then
            return
        end

        local queue = dmhub.initiativeQueue


        --check for opportunity attacks.
        if queue ~= nil and (not queue.hidden) then
            for _,token in ipairs(dmhub.allTokens) do
                if not token.playerControlled then
                    local triggers = token.properties:GetAvailableTriggers()
                    if triggers ~= nil then
                        for _,trigger in pairs(triggers) do
                            if trigger.text == "Opportunity Attack" and (not trigger.triggered) then
                                print("AI:: DISPATCH OPPORTUNITY ATTACK")
                                trigger.triggered = true
                                token.properties:DispatchAvailableTrigger(trigger)
                                break
                            end
                        end
                    end
                end
            end
        end


        if queue ~= nil and (not queue.hidden) and (not queue:IsPlayersTurn()) then
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
                        if bestScore == nil or distance < bestScore then
                            bestScore = distance
                            initiativeid = k
                        end
                    end
                end

                if initiativeid ~= nil then
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
                end
            end
        end
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
                        element.text = g_status or "Active"
                    end
                else
                    m_running = false
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
                    g_terminate = true
                else
                    g_terminate = false
                    dmhub.Coroutine(MonsterAIThread)
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
                            movePanels = {}
                        },
                        setanalysis = function(element, entry)
                            local children = element.children
                            local changed = false

                            for j,moveEntry in ipairs(entry.moves) do
                                local movePanel = element.data.movePanels[j+1]
                                if movePanel == nil then
                                    movePanel = gui.Panel{
                                        width = "100%",
                                        height = "auto",
                                        flow = "vertical",
                                        gui.Label{
                                            fontSize = 16,
                                            lmargin=8,
                                            width = "100%-16",
                                            height = "auto",
                                            setmove = function(element, moveEntry)
                                                local name = moveEntry.id
                                                local abilities = moveEntry.abilities
                                                if #abilities == 1 and abilities[1] == name then
                                                    element.text = string.format("<b>%s</b>", name)
                                                else
                                                    element.text = string.format("<b>%s</b> (%s)", name, table.concat(abilities,","))
                                                end
                                            end,
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
                                    element.data.movePanels[j+1] = movePanel
                                    changed = true
                                end

                                movePanel:FireEventTree("setmove", moveEntry)
                                children[j+1] = movePanel
                            end

                            while #element.data.movePanels > #entry.moves do
                                element.data.movePanels[#element.data.movePanels] = nil
                                changed = true
                            end

                            if changed then
                                element.children = children
                            end
                        end,

                        gui.Label{
                            fontSize = 16,
                            bold = true,
                            width = "100%",
                            height = "auto",
                            setanalysis = function(element, entry)
                                element.text = entry.monsterType
                            end,
                        },
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