local mod = dmhub.GetModLoading()


local function createDrawSteelBanner(options)
    print("BANNER:: CREATE")

    local m_document = mod:GetDocumentSnapshot("drawsteel")

    if options.controller then
        m_document:BeginChange()
        m_document.data.guid = dmhub.GenerateGuid()
        m_document.data.claims = {}
        m_document.data.finished = nil
        m_document.data.delayFinished = nil
        if options.immediateResult then
            m_document.data.finished = true
            m_document.data.delayFinished = 1
        end
        m_document:CompleteChange("Initialize initiative")
    end

    local m_heroesWin = nil

    if options.immediateResult then
        m_heroesWin = cond(options.immediateResult == "heroes", true, false)
    end

    local m_rollInfo = nil
    local m_rollConfirmedStarting = false
    local m_rollConfirmedFinishing = false
    local endAnimationDuration = 1
    local fadeoutDuration = 0.13

    --if we started rolling, this is the guid of the roll.
    local m_rollGuid = nil

    --the user who is currently rolling
    local m_claimUserId = nil
    local m_claim = nil

    --the current roll we are listening to along with the event source.
    local m_rollidListeningTo = nil
    local m_rollEvents = nil

    local scale = 1
    local standardAspect = 16/8
    local actualAspect = dmhub.screenDimensionsBelowTitlebar.x/dmhub.screenDimensionsBelowTitlebar.y
    if actualAspect < standardAspect then
        scale = actualAspect / standardAspect
    end
    print("ASPECT::", actualAspect, "from", dmhub.screenDimensionsBelowTitlebar.x, dmhub.screenDimensionsBelowTitlebar.y, "BECOME", scale)


    local BannerPanel

    BannerPanel = gui.Panel{
        scale = scale,

        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        draggable = false,

        styles = {
            {
                selectors = {"canshine"},
                gradient = gui.Gradient{
                    point_a = {x = 0, y = 0.1},
                    point_b = {x = 1, y = 0},
                    stops = {
                        {
                            position = -0.2,
                            color = "white",
                        },
                        {
                            position = -0.1,
                            color = core.Color{h = 0, s = 0, v = 4},
                        },
                        {
                            position = 0,
                            color = "white",
                        },
                    },

                }
            },
            {
                selectors = {"canshine", "shine"},
                transitionTime = 1,

                gradient = gui.Gradient{
                    point_a = {x = 0, y = 0.1},
                    point_b = {x = 1, y = 0},
                    stops = {
                        {
                            position = 1.0,
                            color = "white",
                        },
                        {
                            position = 1.1,
                            color = core.Color{h = 0, s = 0, v = 4},
                        },
                        {
                            position = 1.2,
                            color = "white",
                        },
                    },
                }
            },
            {
                selectors = {"canshine", "shine", "fadeout"},
                transitionTime = 0.4,
                opacity = 0,
            }
        },

        data = {
            delay = nil,
        },

        --fired very shortly before dying.
        fadeout = function(self)
            self:SetClassTree("fadeout", true)
        end,

        thinkTime = 0.01,
        think = function(self)

            local doc = mod:GetDocumentSnapshot("drawsteel")
            if doc.data.finished then
                if doc.data.delayFinished ~= nil then
                    self.data.delay = self.data.delay or (dmhub.Time() + doc.data.delayFinished)
                    if self.data.delay > dmhub.Time() then
                        return
                    end
                end

                self.thinkTime = nil

                dmhub.Coroutine(function()
                    self:SetClassTree("shine", true)
                    local targetPanel = self:Get(cond(m_heroesWin, "heroesText", "monstersText"))
                    local start = self.aliveTime
                    local t = self.aliveTime - start

                    coroutine.yield(0.8)

                    BannerPanel:SetClassTree("finishing", true)
                    BannerPanel:FireEventTree("finishing")

                    coroutine.yield(1.0)

                    BannerPanel:FireEvent("fadeout")
                    targetPanel:SetClass("fadeout", true)

                    coroutine.yield(0.8)

                    --as the controller who called for this dialog,
                    --create initiative for everyone now.
                    if options.controller then
                        local info = GameHud.instance.initiativeInterface
                        info.initiativeQueue = InitiativeQueue.Create()
                        info.initiativeQueue.playersGoFirst = m_heroesWin
                        info.initiativeQueue.playersTurn = m_heroesWin
                        Commands.rollinitiative()
                    end

                    self:DestroySelf()
                end)

                return
            end


--        if m_rollInfo ~= nil then
--            print("DURATION::", m_rollInfo.timeRemaining)
--            if m_rollConfirmedStarting == false and m_rollInfo.timeRemaining > 0 then
--                m_rollConfirmedStarting = true
--            end

--            if m_rollConfirmedStarting and m_rollConfirmedFinishing == false and m_rollInfo.timeRemaining < endAnimationDuration then
--                m_rollConfirmedFinishing = true
--                BannerPanel:SetClassTree("finishing", true)
--                BannerPanel:FireEventTree("finishing")

--                --also schedule to fire a final fade out with 0.4 seconds left.
--                BannerPanel:ScheduleEvent("fadeout", endAnimationDuration - fadeoutDuration)
--            end
--        end


            if m_claim ~= nil and m_claim.rollid ~= m_rollidListeningTo then

                if m_rollEvents ~= nil then
                    --we were previously listening to this event source, stop listening to it.
                    m_rollEvents:Unlisten(self)
                    m_rollEvents = nil
                    m_rollidListeningTo = nil
                end

                if m_claim.rollid ~= nil then
                    local rollInfo = chat.GetRollInfo(m_claim.rollid)

                    if rollInfo ~= nil then
                        m_rollInfo = rollInfo

                        --there SHOULD only be one roll, but we'll just iterate them all and use
                        --the first we can find.
                        for i,roll in ipairs(rollInfo.rolls) do
                            --we've detected a roll so start listening to it.
                            m_rollEvents = chat.DiceEvents(roll.guid)
                            if m_rollEvents ~= nil then
                                m_rollidListeningTo = m_claim.rollid
                                m_rollEvents:Listen(self)
                                break
                            end
                        end
                    end
                end
            end
        end,

        diceface = function(self, diceguid, num)
            local heroesWin = (num >= 6)
            m_heroesWin = heroesWin
            BannerPanel:SetClassTree("rolling", true)
            BannerPanel:SetClassTree("heroes", heroesWin)
            BannerPanel:SetClassTree("monsters", not heroesWin)
        end,

		monitorGame = m_document.path,

        refreshGame = function(self)

            local bestid = nil
            local bestClaim = nil
            local doc = mod:GetDocumentSnapshot("drawsteel")
            for userid,claim in pairs(doc.data.claims or {}) do
                if bestClaim == nil or claim.priority > bestClaim.priority or (claim.priority == bestClaim.priority and claim.timestamp < bestClaim.timestamp) then
                    bestid = userid
                    bestClaim = claim
                end
            end

            if bestClaim ~= nil then
                if m_rollGuid ~= nil and m_rollGuid == dmhub.currentRollGuid and bestid ~= dmhub.loginUserid then
                    --we are trying to roll but someone else went first, so cancel our roll and cede to them.
                    dmhub.CancelCurrentRoll()
                    m_rollGuid = nil

                    m_document:BeginChange()
                    m_document.data.claims[dmhub.loginUserid] = nil
                    m_document:CompleteChange("Cancel initiative")
                end
            end

            if bestid ~= m_claimUserId then
                BannerPanel:FireEventTree("claim", bestid)
                m_claimUserId = bestid
                m_claim = bestClaim
            end
        end,

        create = function(self)
            audio.FireSoundEvent("UI.DrawSteel")
            if options.controller then
			    GameHud.PresentDialogToUsers(self,"DrawSteel",{ ttl = 10, mapid = game.currentMapId, immediateResult = options.immediateResult })
            end
        end,

        gui.Panel{
            width = 300,
            height = 150,
            bgimage = "panels/initiative/drawsteel-sword.png",
            bgcolor = "white",
            valign = "center",
                
            halign = "right",

            styles = {

                {

                    selectors = {"create"},
                    x = 300,
                    transitionTime = 0.9,
                    easing = "easeInCubic",
                },
                {
                    selectors = {"finishing"},
                    x = 270,
                    transitionTime = endAnimationDuration,
                    easing = "easeInBack",
                },
                {
                    selectors = {"fadeout"},
                    opacity = 0,
                    transitionTime = fadeoutDuration,
                },
            },

        },

        gui.Panel{

            styles = {
                {
                    selectors = {"fadeout"},
                    opacity = 0,
                    transitionTime = fadeoutDuration,
                },
            },

            classes = {"hidden"},

            width = 512,
            height = 70,
            vmargin = 100,
            bgimage = "panels/initiative/drawsteel-text.png",
            bgcolor = "white",

            data = {
                distanceToWall = nil,
                finishTime = nil,
            },

            finishing = function(self)
                self.data.finishTime = self.aliveTime
            end,

            create = function(element)
                element:SetClass("hidden", false)
                element:FireEvent("think")
            end,

            thinkTime = 0.01,
            think = function(self)

                local distanceToWall = math.clamp01(1-(1 - self.aliveTime * 0.8)^3)
                if self.data.finishTime ~= nil then
                    local easeInBack = function(t)
                        local s = 1.70158  -- Default overshoot scale
                        return t * t * ((s + 1) * t - s)
                    end
                    --t will be 0 if we are just starting to finish and 1 if we have completed the finish animation.
                    local t = (self.aliveTime - self.data.finishTime)/(endAnimationDuration*1)
                    t = easeInBack(t)
                    distanceToWall = math.clamp01(1 - t)
                end


                distanceToWall = distanceToWall*0.6

                if distanceToWall ~= self.data.distanceToWall then
                    self.data.distanceToWall = distanceToWall
                    self.selfStyle.gradient = gui.Gradient{

                        point_a = {x = 0, y = 0},
                        point_b = {x = 1, y = 0},
                        stops = {
                            {
                                position = 0.5 - distanceToWall,
                
                                color = "#ffffff00",
                
                            },
                            {
                                position = math.min(0.5, 0.5 - distanceToWall + 0.1),
                
                                color = "#ffffffff",
                
                            },
                            {
                                position = 0.5,
                
                                color = "#ffffffff",
                
                            },
                            {
                                position = math.max(0.5, 0.5 + distanceToWall - 0.1),
                
                                color = "#ffffffff",
                
                            },
                            {
                                position = 0.5 + distanceToWall,
                    
                                color = "#ffffff00",
                    
                            },
                        },

                    }
                end
            end,
        },


        gui.Panel{

            width = 280,
            height = 140,
            bgimage = "panels/initiative/drawsteel-sword.png",
            bgcolor = "white",
            valign = "center",
                
            halign = "right",
            scale = {x = -1, y = 1},

            styles = {

                {

                    selectors = {"create"},
                    x = -300,
                    transitionTime = 0.9,
                    easing = "easeInCubic",

                },

                {
                    selectors = {"finishing"},
                    priority = 20,
                    x = -270,
                    transitionTime = endAnimationDuration,
                    easing = "easeInBack",
                },
                {
                    selectors = {"fadeout"},
                    opacity = 0,
                    transitionTime = fadeoutDuration,
                },

            },


        },

        --the heroes/monsters panel.
        gui.Panel{
            y = -40,
            floating = true,
            width = "auto",
            height = "auto",
            valign = "bottom",
            halign = "center",
            interactable = false,
            gui.Panel{
                id = "monstersText",
                classes = {"canshine"},
                floating = true,
                width = 250,
                height = 39,
                bgimage = "panels/initiative/monsters-text.png",
                halign = "center",
                valign = "bottom",
                interactable = false,
                bgcolor = "white",
                styles = {
                    {
                        opacity = 0,
                    },
                    {
                        selectors = {"monsters"},
                        transitionTime = 0.1,
                        opacity = 1,
                    },
                }
            },
            gui.Panel{
                id = "heroesText",
                classes = {"canshine"},
                floating = true,
                width = 179,
                height = 37,
                bgimage = "panels/initiative/heroes-text.png",
                halign = "center",
                valign = "bottom",
                interactable = false,
                bgcolor = "white",
                styles = {
                    {
                        opacity = 0,
                    },
                    {
                        selectors = {"heroes"},
                        transitionTime = 0.1,
                        opacity = 1,
                    },
                },
            },
        },

        --panel that contains dice along with surrounding initiative text.
        gui.Panel{

            floating = true,
            halign = "center",
            valign = "bottom",
            width = "auto",
            height = "auto",
            y = 110,

            styles = {
                {
                    selectors = {"rolling"},
                    hidden = 1,
                },
            },

            --the clickable dice icon.
            gui.Panel{

                
                bgimage = "panels/initiative/initiative-dice.png",
                bgcolor = "white",
                width = 128,
                height = 128,
                halign = "center",
                valign = "center",
                classes = "dice",

                claim = function(self, userid)
                    if userid == nil then
                        self.selfStyle.bgcolor = "white"
                        self:SetClass("claimed", false)
                        self:SetClass("dragging", false)
                    else
                        local sessionInfo = dmhub.GetSessionInfo(userid)
                        self.selfStyle.bgcolor = sessionInfo.displayColor
                        self:SetClass("claimed", true)
                        self:SetClass("dragging", userid == dmhub.loginUserid)
                    end
                end,

                thinkTime = 0.7,
                think = function(self)

                    if self:HasClass("pulse")
                    then

                        self:SetClass("pulse", false)
                    else
                        
                        self:SetClass("pulse", true)
                    end
                end,

                --we can drag to hurl the dice as long as the dice speed isn't set to instant.
                draggable = dmhub.GetSettingValue("dicespeed") ~= "veryfast",
                beginDrag = function(self)
                    self:FireEvent("click", true)

                end,

                click = function(self, isactuallydrag)
                    if self:HasClass("claimed") then
                        --this is already being dragged by someone else.
                        return
                    end

                    m_rollGuid = dmhub.GenerateGuid()

                    local doc = mod:GetDocumentSnapshot("drawsteel")
                    m_document:BeginChange()
                    m_document.data.claims[dmhub.loginUserid] = {
                        status = cond(isactuallydrag, "drag", "roll"),
                        priority = cond(isactuallydrag, 0, 1),
                        rollid = m_rollGuid,
                        timestamp = dmhub.serverTime,
                    }
                    m_document:CompleteChange("Initialize initiative")

                    dmhub.Roll{
                        roll = "1d10",
                        guid = m_rollGuid,
                        drag = isactuallydrag,
                        description = "Draw Steel",
                        begin = function(rollInfo)

                        end,

                        complete = function(rollInfo)
                            if m_claimUserId == dmhub.loginUserid then
                                --we completed the roll, so close down the dialog.
                                local doc = mod:GetDocumentSnapshot("drawsteel")
                                doc:BeginChange()
                                doc.data.finished = true
                                doc:CompleteChange("Initialize initiative")
                            end
                        end,

                        cancel = function()
                            --this happens if they stop dragging without hurling the dice.
                            --relinquish our claim to the dice.
                            local doc = mod:GetDocumentSnapshot("drawsteel")
                            doc:BeginChange()
                            if doc.data.claims ~= nil then
                                doc.data.claims[dmhub.loginUserid] = nil
                            end
                            doc:CompleteChange("Initialize initiative")
                        end,
                    }
                end,

                styles = {

                    {

                        selectors = {"pulse"},
                        uiscale = 1.05,
                        transitionTime = 0.7,
                        easing = "easeinOutSine",
                    },

                    {
    
                        selectors = {"hover", "dice"},
                        uiscale = 1.1,
                        transitionTime = 0.1,
                        
    
                    },
    
                    {
                        selectors = {"press"},
                        inversion = 1,

    
                    },

                    {
                        --someone else has 'claimed' the dice, don't allow others to interact.
                        selectors = {"claimed"},
                        transitionTime = 0.2,
                        opacity = 0.6,
                        uiscale = 1,
                        inversion = 0,
                    },

                    {
                        --we are dragging the dice, make them disappear.
                        selectors = {"dragging"},
                        opacity = 0,
                    },
    
                },



            },

            gui.Panel{

                width = 600,
                height = 300,
                bgimage = "panels/initiative/initiative-text.png",
                bgcolor = "white",
                halign = "center",
                valign = "center",
                y = -20,
                x = 8,
                interactable = false,

                styles = {

                    {

                        selectors = {"~parent:hover"},
                        opacity = 0,
                        transitionTime = 0.2,

                    },



                },

            



            }
    
    
    
        },

        

    

        close = function()

            BannerPanel:DestroySelf()


        end,

        rightClick = function(self)

            if dmhub.isDM then
                self.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Close",
                            click = function()
                                BannerPanel:DestroySelf()
                                self.popup = nil
                            end,
                        }

                    }
                }
            end
        end
    }

    if options.immediateResult ~= nil then
        BannerPanel:SetClassTree("rolling", true)
        BannerPanel:SetClassTree("heroes", options.immediateResult == "heroes")
        BannerPanel:SetClassTree("monsters", options.immediateResult ~= "heroes")
    end

    return BannerPanel
end

function showDrawSteelBanner(result)
    local banner = createDrawSteelBanner{ controller = true, immediateResult = result }
    GameHud.instance.parentPanel:AddChild(banner)
end

--- @class RollInitiativeChatMessage
--- @field winner "players"|"monsters"
--- @field playerTokenIds string[]
--- @field monsterTokenIds string[]
RollInitiativeChatMessage = RegisterGameType("RollInitiativeChatMessage")

RollInitiativeChatMessage.winner = "players"
RollInitiativeChatMessage.playerTokenIds = {}
RollInitiativeChatMessage.monsterTokenIds = {}

function RollInitiativeChatMessage.Render(selfInput, message)
    return gui.Panel{width = 0, height = 0}
end

--- @param initiativeQueue InitiativeQueue
--- @param tokens CharacterToken[]
--- @return RollInitiativeChatMessage
function RollInitiativeChatMessage.Create(initiativeQueue, tokens)
    local tokensByInitiative = {}
    for _,tok in ipairs(tokens) do
        local initiativeid = InitiativeQueue.GetInitiativeId(tok)
        if tokensByInitiative[initiativeid] == nil then
            tokensByInitiative[initiativeid] = tok
        else
            tokensByInitiative[initiativeid] = creature.GetSeniorToken{tokensByInitiative[initiativeid], tok}
        end
    end

    local playerTokens = {}
    local monsterTokens = {}

    for key,tok in pairs(tokensByInitiative) do
        if initiativeQueue:IsEntryPlayer(key) then
            playerTokens[#playerTokens+1] = tok.charid
        else
            monsterTokens[#monsterTokens+1] = tok.charid
        end
    end

    return RollInitiativeChatMessage.new{
        playerTokenIds = playerTokens,
        monsterTokenIds = monsterTokens,
        winner = initiativeQueue.playersGoFirst and "players" or "monsters",
    }
end

--- @return CharacterToken[]
function RollInitiativeChatMessage:GetPlayerTokens()
    local result = {}
    for _,charid in ipairs(self.playerTokenIds) do
        result[#result+1] = dmhub.GetCharacterById(charid)
    end
    return result
end

--- @return CharacterToken[]
function RollInitiativeChatMessage:GetMonsterTokens()
    local result = {}
    for _,charid in ipairs(self.monsterTokenIds) do
        result[#result+1] = dmhub.GetCharacterById(charid)
    end
    return result
end

local function SetTokenSurprised(tok, surprised)
    local surprisedCondition = CharacterCondition.conditionsByName["surprised"]
    if tok.valid then
        tok:ModifyProperties {
            description = "Toggle Surprise",
            undoable = false,
            execute = function()
                tok.properties:InflictCondition(surprisedCondition.id, {
                    force = true,
                    duration = "eoe",
                    purge = not surprised,
                })
            end,
        }
    end
end

local g_selectedTokensOpenInitiative = nil
local g_playerTokensOpenInitiative = nil
local g_monsterTokensOpenInitiative = nil

local function ShowCombatSetupDialog()
    local m_encounterStrength = 0
    local m_encounterStrengthSingleHero = 0
    local surprisedCondition = CharacterCondition.conditionsByName["surprised"]

    local CreateTokenPoolPanel = function(args)
        local sideline = args.sideline or false
        args.sideline = nil
        local pool
        pool = {
            classes = {"tokenPool"},
            dragTarget = true,
            flow = "vertical",
            vscroll = true,

            add = function(element, tokenPanel)
                tokenPanel:SetClassTree("sideline", sideline or false)
                element:AddChild(tokenPanel)
                local children = element.children
                table.sort(children, function(a,b)
                    return a.data.group.name < b.data.group.name
                end)
                element.children = children
            end,
        }
        for k,v in pairs(args) do
            pool[k] = v
        end

        pool = gui.Panel(pool)
        return pool
    end

    local GetTokenPoolSurprisedCount = function(pool)
        local children = pool.children
        local surprisedCount = 0
        local notSurprisedCount = 0
        for i,child in ipairs(children) do
            local group = child.data.group
            for _,tok in ipairs(group.tokens) do
                if tok.properties:HasCondition(surprisedCondition.id) then
                    surprisedCount = surprisedCount + 1
                else
                    notSurprisedCount = notSurprisedCount + 1
                end
            end
        end

        return surprisedCount, notSurprisedCount
    end


    local CreateTokenPoolContainer = function(args)
        local resultPanel

        local surprisedBar
        
        if args.hasSurprise then
            surprisedBar = gui.EnumeratedSliderControl{
                width = 340,
                tmargin = 6,
                options = {
                    { id = "none", text = "None Surprised"},
                    { id = "all", text = "All Surprised"},
                },
                value = "none",
                change = function(element)
                    local surprised = (element.value == "all")
                    local children = args.pool.children
                    for i,child in ipairs(children) do
                        local group = child.data.group
                        for _,tok in ipairs(group.tokens) do
                            SetTokenSurprised(tok, surprised)
                        end
                    end
                    element.root:FireEventTree("refreshSurprise")
                end,

                refreshSurprise = function(element)

                    local children = args.pool.children
                    local surprisedCount, notSurprisedCount = GetTokenPoolSurprisedCount(args.pool)
                    for i,child in ipairs(children) do
                        local group = child.data.group
                        for _,tok in ipairs(group.tokens) do
                            if tok.properties:HasCondition(surprisedCondition.id) then
                                surprisedCount = surprisedCount + 1
                            else
                                notSurprisedCount = notSurprisedCount + 1
                            end
                        end
                    end

                    if surprisedCount == 0 and notSurprisedCount > 0 then
                        element.value = "none"
                    elseif surprisedCount > 0 and notSurprisedCount == 0 then
                        element.value = "all"
                    else
                        element.value = "mixed"
                    end
                end,

                create = function(element)
                    element:FireEvent("refreshSurprise")
                end,
            }
        end

        local statusLabel = nil

        if args.heroes then

            statusLabel = gui.Label{
                data = {
                    tooltip = nil,
                },
                tmargin = 6,
                text = "",
                width = "auto",
                height = "auto",
                halign = "center",
                maxWidth = 300,
                fontSize = 14,
                color = Styles.textColor,
                refreshSurprise = function(element)
                    local encounterStrength = 0
                    local children = args.pool.children
                    local numTokens = 0
                    local totalVictories = 0
                    local numHeroes = 0
                    local minLevel = nil
                    local maxLevel = nil
                    for i,child in ipairs(children) do
                        local group = child.data.group
                        for _,tok in ipairs(group.tokens) do
                            if minLevel == nil or tok.properties:CharacterLevel() < minLevel then
                                minLevel = tok.properties:CharacterLevel()
                            end
                            if maxLevel == nil or tok.properties:CharacterLevel() > maxLevel then
                                maxLevel = tok.properties:CharacterLevel()
                            end
                            encounterStrength = encounterStrength + 4 + tok.properties:CharacterLevel()*2
                            local victories = tok.properties:GetVictories()
                            totalVictories = totalVictories + victories
                            if tok.properties:IsHero() then
                                numHeroes = numHeroes + 1
                            end
                            numTokens = numTokens + 1
                        end
                    end
                    if numTokens == 0 then
                        element.text = ""
                        m_encounterStrength = 0
                        m_encounterStrengthSingleHero = 0
                        element.data.tooltip = nil
                        return
                    end

                    local averageVictories = math.floor(totalVictories / numTokens)
                    local tokenAverage = math.floor(encounterStrength/numTokens)
                    local baseEncounterStrength = encounterStrength

                    m_encounterStrengthSingleHero = tokenAverage

                    local victoriesAdditionalHeroes = math.floor(averageVictories / 2)

                    encounterStrength = encounterStrength + math.floor(victoriesAdditionalHeroes * tokenAverage)
                    element.text = string.format("Encounter Strength: %d", encounterStrength)
                    m_encounterStrength = encounterStrength

                    local tooltip = string.format("%d Heroes", numHeroes)
                    if numTokens ~= numHeroes then
                        tooltip = string.format("%s, %d %s", tooltip, numTokens - numHeroes, cond(numTokens - numHeroes == 1, "Ally", "Allies"))
                    end

                    if minLevel == maxLevel then
                        tooltip = string.format("%s, Level %d", tooltip, minLevel)
                    else
                        tooltip = string.format("%s, Levels %d-%d", tooltip, minLevel, maxLevel)
                    end

                    tooltip = string.format("%s\nBase Encounter Strength: %d", tooltip, baseEncounterStrength)

                    tooltip = string.format("%s\nAverage Victories: %d", tooltip, averageVictories)
                    tooltip = string.format("%s\nExtra Heroes from Victories: %d", tooltip, victoriesAdditionalHeroes)
                    tooltip = string.format("%s\nEncounter Strength of a Single Hero: %d", tooltip, m_encounterStrengthSingleHero)
                    tooltip = string.format("%s\nTotal Encounter Strength: %d", tooltip, encounterStrength)

                    element.data.tooltip = tooltip
                end,

                create = function(element)
                    element:FireEvent("refreshSurprise")
                end,
                hover = function(element)
                    if element.data.tooltip ~= nil then
                        gui.Tooltip(element.data.tooltip)(element)
                    end
                end,
            }
            
        elseif args.monsters then

            statusLabel = gui.Label{
                data = {
                    tooltip = nil,
                },
                tmargin = 6,
                text = "",
                width = "auto",
                height = "auto",
                halign = "center",
                maxWidth = 300,
                fontSize = 14,
                color = Styles.textColor,
                refreshSurprise = function(element)
                    local ev = 0
                    local evvalid = true

                    local children = args.pool.children
                    for i,child in ipairs(children) do
                        local group = child.data.group
                        for _,tok in ipairs(group.tokens) do
                            local monsterEV = tok.valid and tok.properties:try_get("ev")
                            if monsterEV == nil then
                                evvalid = false
                            elseif tok.properties.minion then
                                ev = ev + monsterEV/GameSystem.minionsPerSquad
                            else
                                ev = ev + monsterEV
                            end
                        end
                    end
                    if evvalid == false or ev <= 0 then
                        element.text = ""
                        element.data.tooltip = nil
                        return
                    end

                    local tooltip = nil

                    local description = "Extreme"
                    if ev < m_encounterStrength - m_encounterStrengthSingleHero then
                        description = "Trivial"
                    elseif ev < m_encounterStrength then
                        description = "Easy"
                    elseif ev < m_encounterStrength + m_encounterStrengthSingleHero then
                        description = "Standard"
                    elseif ev <= m_encounterStrength + m_encounterStrengthSingleHero * 3 then
                        description = "Hard"
                    end

                    element.text = string.format("EV: %s (%s)", round(ev), description)

                    element.data.tooltip = tooltip
                end,

                create = function(element)
                    element:FireEvent("refreshSurprise")
                end,
                hover = function(element)
                    if element.data.tooltip ~= nil then
                        gui.Tooltip(element.data.tooltip)(element)
                    end
                end,
            }
           


        end

        resultPanel = gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "top",
            gui.Label{
                fontSize = 22,
                text = args.title,
                width = "auto",
                height = "auto",
                bold = true,
                halign = "center",
                valign = "top",
            },

            args.pool,
            surprisedBar,
            statusLabel,
        }

        return resultPanel
    end


    local CreateGroupPanel = function(group)
        local tokenStacks = {}

        table.sort(group.tokens, function(a,b)
            return creature.ScoreTokenImportance(a) < creature.ScoreTokenImportance(b)
        end)

        local name = creature.GetTokenDescription(group.tokens[1])

        local pattern = cond(#group.tokens == 1, "mono", "custom")

        for _,tok in ipairs(group.tokens) do
            if #tokenStacks == 0 or tokenStacks[#tokenStacks][1].portrait ~= tok.portrait then
                tokenStacks[#tokenStacks+1] = { tok }
            else
                local list = tokenStacks[#tokenStacks]
                list[#list+1] = tok
            end
        end

        if #group.tokens == 2 then
            pattern = "dual"
            if #tokenStacks == 1 then
                name = name .. " x2"
            else
                name = creature.GetTokenDescription(group.tokens[1]) .. " & " .. creature.GetTokenDescription(group.tokens[2])
            end
        elseif #tokenStacks == 2 and #tokenStacks[1] == 1 and tokenStacks[2][1].properties.minion then
            name = group.tokens[1].properties:MinionSquad() or name
        elseif #tokenStacks == 1 and #group.tokens > 1 and tokenStacks[1][1].properties.minion then
            pattern = "squad"
            name = group.tokens[1].properties:MinionSquad() or name
        end

        local children = {}
        if pattern == "mono" then
            children[#children+1] = gui.CreateTokenImage(tokenStacks[1][1], {
                width = 50,
                height = 50,
                halign = "center",
                valign = "center",
            })
        elseif pattern == "captainedSquad" then
            children[#children+1] = gui.CreateTokenImage(tokenStacks[1][1], {
                width = 50,
                height = 50,
                halign = "center",
                valign = "center",
            })

            for i=1,4 do
                local tok = tokenStacks[2][i]
                if tok then
                    local halign = cond(i%2 == 1, "left", "right")
                    local valign = cond(i <= 2, "top", "bottom")

                    local tokenPanel = gui.CreateTokenImage(tok, {
                        width = 20,
                        height = 20,
                        halign = halign,
                        valign = valign
                    })
                    children[#children+1] = tokenPanel
                end
            end
        elseif pattern == "dual" then
            for i,tok in ipairs(group.tokens) do

                local tokenPanel = gui.CreateTokenImage(tok, {
                    width = 50,
                    height = 50,
                    halign = "center",
                    valign = "center",
                    x = -8*cond(i%2 == 1, 1, -1),
                })
                children[#children+1] = tokenPanel
            end
        elseif pattern == "squad" then
            for i=1,4 do
                local tok = tokenStacks[1][i]
                if tok then
                    local halign = cond(i%2 == 1, "left", "right")
                    local valign = cond(i <= 2, "top", "bottom")

                    local tokenPanel = gui.CreateTokenImage(tok, {
                        width = 26,
                        height = 26,
                        halign = halign,
                        valign = valign
                    })
                    children[#children+1] = tokenPanel
                end
            end
        else
            for i,stack in ipairs(tokenStacks) do
                local dim = 60
                if #tokenStacks > 1 then
                    dim = 30
                    if stack[1].properties.minion then
                        dim = 20
                    end
                end

                for j,tok in ipairs(stack) do
                    local halign = "center"
                    local valign = "center"
                    if #tokenStacks > 1 then
                        halign = cond(i%2 == 1, "left", "right")
                        if #tokenStacks == 2 then
                            valign = "center"
                        else
                            valign = cond(i <= 2, "top", "bottom")
                        end
                    end
                    local tokenPanel = gui.CreateTokenImage(tok, {
                        width = dim,
                        height = dim,
                        halign = halign,
                        valign = valign,
                        x = j*2,
                    })

                    children[#children+1] = tokenPanel
                end
            end
        end

        group.name = name

        local surprisedCondition = CharacterCondition.conditionsByName["surprised"]
        local m_isSurprised = group.tokens[1].properties:HasCondition(surprisedCondition.id)

        local resultPanel
        resultPanel = gui.Panel{
            classes = {"tokenGroup"},
            flow = "horizontal",
            width = 320,
            height = 54,
            halign = "left",
            valign = "top",
            bgimage = true,
            draggable = true,
            drag = function(element, target)
                if target ~= nil then
                    element:Unparent()
                    target:FireEvent("add", element)
                    element.root:FireEventTree("refreshSurprise")
                end
            end,

            canDragOnto = function(element, targetPanel)
                if targetPanel:HasClass("tokenPool") then
                    return true
                end
                return false
            end,

            data = {
                group = group,
            },
            gui.Panel{
                valign = "center",
                halign = "left",
                width = 68,
                height = 54,
                children = children,
                bgimage = true,
            },
            gui.Panel{
                width = 240,
                height = "100%",
                halign = "left",
                flow = "vertical",
                gui.Label{
                    fontSize = 16,
                    minFontSize = 12,
                    bold = true,
                    width = 240,
                    height = "auto",
                    halign = "left",
                    valign ="top",
                    textOverflow = "ellipsis",
                    textWrap = false,
                    margin = 2,
                    color = Styles.textColor,
                    text = name,
                },
                gui.Label{
                    classes = {cond(m_isSurprised, "surprised")},
                    text = cond(m_isSurprised, "Surprised", "Not Surprised"),
                    refreshSurprise = function(element)
                        m_isSurprised = group.tokens[1].properties:HasCondition(surprisedCondition.id)
                        element:SetClass("surprised", m_isSurprised)
                        element.text = cond(m_isSurprised, "Surprised", "Not Surprised")
                    end,
                    click = function(element)
                        m_isSurprised = not m_isSurprised
                        for _,tok in ipairs(group.tokens) do
                            SetTokenSurprised(tok, m_isSurprised)
                        end
                        element.root:FireEventTree("refreshSurprise")
                    end,
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    margin = 2,
                    bgimage = true,
                    bgcolor = "clear",
                    styles = {
                        {
                            color = Styles.textColor,
                        },
                        {
                            selectors = {"surprised"},
                            color = "#ffaaaa",
                        },
                        {
                            selectors = {"hover"},
                            color = "#ffaaff",
                        },
                        {
                            selectors = {"press"},
                            color = "#ccaacc",
                        },
                        {
                            selectors = {"sideline"},
                            hidden = 1,
                        },
                    },
                },
            }
        }

        return resultPanel
    end

    local heroesSelectedPool
    local heroesAvailablePool
    local monstersSelectedPool
    local monstersAvailablePool

    heroesSelectedPool = CreateTokenPoolPanel{
    }

    heroesAvailablePool = CreateTokenPoolPanel{
        height = 140,
        sideline = true,
    }

    monstersSelectedPool = CreateTokenPoolPanel{
    }

    monstersAvailablePool = CreateTokenPoolPanel{
        height = 140,
        sideline = true,
    }

    local tokens = dmhub.allTokens
    local selectedTokens = dmhub.selectedTokens
    if selectedTokens == nil or #selectedTokens < 2 then
        selectedTokens = nil
    end

    local groupings = {}
    local playerPartyId = GetDefaultPartyID()
    local playerParty = GetParty(GetDefaultPartyID())
    local heroVictories = {}
    for _,tok in ipairs(tokens) do
        if tok ~= nil and tok.valid then
            local partyid = tok.partyId
            local playerSide = partyid ~= nil and ((partyid == playerPartyId) or (playerParty ~= nil and playerParty:GetAllyParties()[partyid] ~= nil))

            local initiativeId = InitiativeQueue.GetInitiativeId(tok)
            groupings[initiativeId] = groupings[initiativeId] or { playerSide = playerSide, tokens = {}}
            local group = groupings[initiativeId]
            group.tokens[#group.tokens+1] = tok

            local selected = (selectedTokens == nil or playerSide)
            if not selected then
                for _,item in ipairs(selectedTokens) do
                    if item == tok then
                        selected = true
                        break
                    end
                end
            end

            if selectedTokens == nil and partyid ~= nil then
                local partyTable = dmhub.GetTable(Party.tableName)
                local party = partyTable[partyid]
                --if we don't have selected tokens and the party is non-combatant then they are non-combatants.
                if party ~= nil then
                    selected = not party.noncombatant
                end
            end

            group.selected = selected
        end
    end

    for key,group in pairs(groupings) do
        local panel = CreateGroupPanel(group)
        local pool = cond(group.playerSide, heroesSelectedPool, monstersSelectedPool)
        if not group.selected then
            pool = cond(group.playerSide, heroesAvailablePool, monstersAvailablePool)
        end
        pool:FireEventTree("add", panel)
    end

    local m_initiativeResult = "roll"
    local m_initiativeLocked = false


    local dialog
    dialog = gui.Panel{
        classes = {"framedPanel"},
        styles = {
            Styles.Panel,
            Styles.Default,
            {
                classes = {"tokenPool"},
                bgimage = true,
                bgcolor = "black",
                borderWidth = 2,
                borderColor = "#888888",
                pad = 4,
                width = 340,
                height = 360,
            },
            {
                classes = {"tokenPool", "drag-target"},
                borderColor = "#bbbbbb",
            },
            {
                classes = {"tokenPool", "drag-target-hover"},
                borderColor = "#ffffff",
            },
            {
                classes = {"tokenGroup"},
                bgimage = true,
                bgcolor = "black",
            },
            {
                classes = {"tokenGroup", "hover"},
                bgcolor = "#444444",
            },
        },

        width = 1024,
        height = 868,

        gui.Panel{
            halign = "center",
            valign = "center",
            width = 800,
            height = 700,
            flow = "vertical",

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                CreateTokenPoolContainer{
                    title = "Heroes",
                    pool = heroesSelectedPool,
                    hasSurprise = true,
                    heroes = true,
                },
                gui.Label{
                    width = 22,
                    fontSize = 22,
                    bold = true,
                    valign = "center",
                    halign = "center",
                    color = Styles.textColor,
                    text = "vs",
                },
                CreateTokenPoolContainer{
                    title = "Monsters",
                    pool = monstersSelectedPool,
                    hasSurprise = true,
                    monsters = true,
                },
            },

            gui.Panel{
                tmargin = 20,
                width = "100%",
                height = "auto",
                flow = "horizontal",
                CreateTokenPoolContainer{
                    title = "Non-Combatant Heroes",
                    pool = heroesAvailablePool,
                },
                gui.Panel{
                    width = 22,
                    height = 1,
                },
                CreateTokenPoolContainer{
                    title = "Non-Combatant Monsters",
                    pool = monstersAvailablePool,
                },
            },

            gui.EnumeratedSliderControl{
                width = 600,
                options = {
                    { id = "heroes", text = "Heroes Win Initiative"},
                    { id = "roll", text = "Roll for Initiative"},
                    { id = "monsters", text = "Monsters Win Initiative"},
                },

                refreshSurprise = function(element)
                    if m_initiativeLocked then
                        return
                    end

                    local surprisedCount, notSurprisedCount = GetTokenPoolSurprisedCount(heroesSelectedPool)
                    local allHeroesSurprised = (surprisedCount > 0 and notSurprisedCount == 0)
                    local surprisedCount, notSurprisedCount = GetTokenPoolSurprisedCount(monstersSelectedPool)
                    local allMonstersSurprised = (surprisedCount > 0 and notSurprisedCount == 0)

                    if allHeroesSurprised and not allMonstersSurprised then
                        element.value = "monsters"
                    elseif allMonstersSurprised and not allHeroesSurprised then
                        element.value = "heroes"
                    else
                        element.value = "roll"
                    end
                    m_initiativeResult = element.value
                end,

                create = function(element)
                    element:FireEvent("refreshSurprise")
                end,

                change = function(element)
                    m_initiativeResult = element.value
                    m_initiativeLocked = true
                end,
            },
        },

        gui.Label{
            halign = "center",
            valign = "top",
            classes = {"dialogTitle"},
            text = "Prepare Combat",
        },

        gui.Panel{
            width = "100%",
            valign = "bottom",
            halign = "center",
            flow = "horizontal",
            gui.Button{
                text = "Draw Steel!",
                fontSize = 24,
                halign = "center",
                valign = "bottom",
                vmargin = 12,
                press = function(element)
                    GameHud.instance:CloseModal(dialog)
                    g_playerTokensOpenInitiative = {}
                    g_monsterTokensOpenInitiative = {}

                    local tokens = {}

                    for _,p in ipairs(heroesSelectedPool.children) do
                        for _,token in ipairs(p.data.group.tokens) do
                            if token.valid then
                                tokens[#tokens+1] = token
                                g_playerTokensOpenInitiative[token.charid] = true
                            end
                        end
                    end

                    for _,p in ipairs(monstersSelectedPool.children) do
                        for _,token in ipairs(p.data.group.tokens) do
                            if token.valid then
                                tokens[#tokens+1] = token
                                g_monsterTokensOpenInitiative[token.charid] = true
                            end
                        end
                    end

                    g_selectedTokensOpenInitiative = tokens
                    if m_initiativeResult == "roll" then
                        m_initiativeResult = nil
                    end
                    showDrawSteelBanner(m_initiativeResult)
                end,
            },
        },

        gui.CloseButton{
            halign = "right",
            valign = "top",
            press = function(self)
                GameHud.instance:CloseModal(dialog)
            end,
        }
    }

    GameHud.instance:ShowModal(dialog)
end

Commands.rollinitiative = function(str)
    local tokens = dmhub.selectedTokens
    local info = GameHud.instance.initiativeInterface
    if info.initiativeQueue == nil or info.initiativeQueue.hidden then
        ShowCombatSetupDialog()

        --g_selectedTokensOpenInitiative = tokens
        --showDrawSteelBanner()
        return
    end

    if g_selectedTokensOpenInitiative ~= nil then
        tokens = g_selectedTokensOpenInitiative
        g_selectedTokensOpenInitiative = nil
    end

    local message = RollInitiativeChatMessage.Create(info.initiativeQueue, tokens)
    chat.SendCustom(message)

    local playerPartyId = GetDefaultPartyID()
    local playerParty = GetParty(GetDefaultPartyID())
    local heroVictories = {}
    for _,tok in ipairs(tokens) do
        if tok ~= nil and tok.valid then
            local partyid = tok.partyId
            local playerSide = partyid ~= nil and ((partyid == playerPartyId) or (playerParty ~= nil and playerParty:GetAllyParties()[partyid] ~= nil))

            if g_playerTokensOpenInitiative ~= nil and g_playerTokensOpenInitiative[tok.charid] then
                playerSide = true
            elseif g_monsterTokensOpenInitiative ~= nil and g_monsterTokensOpenInitiative[tok.charid] then
                playerSide = false
            end

            if playerSide and tok.properties:IsHero() then
                heroVictories[#heroVictories+1] = tok.properties:GetVictories()
            end

            local initiativeId = InitiativeQueue.GetInitiativeId(tok)
            local entry = info.initiativeQueue:SetInitiative(initiativeId, 0, 0)
            entry.player = playerSide


            tok.properties:DispatchEvent("rollinitiative", {})
            tok.properties:DispatchEvent("beginround")
        end
    end

    print("DISPATCH:: OBJECT BEGIN ROUND", #dmhub.allObjectTokens)
    for _,tok in ipairs(dmhub.allObjectTokens) do
        tok.properties:DispatchEvent("beginround")
    end

    local averageVictories = 0
    if #heroVictories > 0 then
        for _,victory in ipairs(heroVictories) do
            averageVictories = averageVictories + victory
        end
        averageVictories = averageVictories / #heroVictories
    end

    averageVictories = math.floor(averageVictories)

    CharacterResource.SetMalice(averageVictories + info.initiativeQueue:CalculateMaliceGain(), "Start of Combat Malice")
    CharacterResource.SetVillainActions(1)

    info.UploadInitiative()
end

LaunchablePanel.Register{
	name = "DrawSteel",
	halign = "center",
	valign = "center",
    unframed = true,
    draggable = false,
	filtered = function()
        return true
	end,
	content = function(options)
		return createDrawSteelBanner(options)
	end,
}

local function CreatePreInitiativePanel()
    local dialogPanel

    --- @param token CharacterToken
	local CreateTokenPanel = function(token)

		return gui.Panel{
			bgimage = 'panels/square.png',
			classes = 'token-panel',
			data = {
				token = token,
			},

			gui.CreateTokenImage(token),

            hover = function(element)
                gui.Tooltip(token.description)(element)
            end,

			press = function(element)
				element:SetClass('selected', not element:HasClass('selected'))
				--resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		}
	end


    local CreateTokenPool = function(tokens)
        return gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "black",
            cornerRadius = 8,
            border = 2,
            borderColor = '#888888',
            width = 210,
            height = 210,
            pad = 4,
            vscroll = true,
            vmargin = 8,
            flow = 'horizontal',
            wrap = true,
    
        }
    end

    dialogPanel = gui.Panel{
        width = 900,
        height = 768,

		styles = {
			{
				classes = {'token-panel'},
				bgcolor = 'black',
				cornerRadius = 8,
				width = 64,
				height = 64,
				halign = 'left',
			},
			{
				classes = {'token-panel', 'hover'},
				borderColor = 'grey',
				borderWidth = 2,
				bgcolor = '#441111',
			},
			{
				classes = {'token-panel', 'selected'},
				borderColor = 'white',
				borderWidth = 2,
				bgcolor = '#882222',
			},

		},

        gui.Label{
            halign = "center",
            valign = "top",
            vmargin = 12,
            width = "auto",
            height = "auto",
            bold = true,
            fontSize = 24,
            text = "Prepare Combat",
        },

        gui.Button{
            text = "Proceed",
            fontSize = 24,
            halign = "center",
            valign = "bottom",
            vmargin = 12,
            press = function(element)
            end,
        }
    }

    return dialogPanel
end

--[[
LaunchablePanel.Register{
	name = "Draw Steel!!",
    icon = "panels/initiative/initiative-icon.png",
	halign = "center",
	valign = "center",
    draggable = false,

	hidden = function()
		return not dmhub.isDM
	end,
	content = function(args)
        return CreatePreInitiativePanel()
	end,
}
]]