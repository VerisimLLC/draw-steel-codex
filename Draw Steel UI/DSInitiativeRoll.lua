local mod = dmhub.GetModLoading()

local g_selectedTokensOpenInitiative = nil
local g_playerTokensOpenInitiative = nil
local g_monsterTokensOpenInitiative = nil
--The Encounter chosen in the combat setup dialog's encounter dropdown, carried to
--the controller's queue creation. nil means "Custom" (no live encounter).
local g_selectedEncounterOpenInitiative = nil

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

    local m_initiativeThreshold = 6
    local surprisedConditionForThreshold = CharacterCondition.conditionsByName["surprised"]
    for charid,_ in pairs(g_playerTokensOpenInitiative or {}) do
        local tok = dmhub.GetCharacterById(charid)
        if tok ~= nil and tok.valid then
            local isSurprised = surprisedConditionForThreshold ~= nil and tok.properties:HasCondition(surprisedConditionForThreshold.id)
            if not isSurprised then
                local t = tok.properties:CalculateNamedCustomAttribute("Initiative Threshold")
                if type(t) == "number" and t > 0 and t < m_initiativeThreshold then
                    m_initiativeThreshold = t
                end
            end
        end
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
                    if options.controller and options.reroll then
                        --Per-round "who goes first" reroll (Crows): combat already
                        --exists, so do NOT create a queue. Just record which side
                        --goes first this round and refresh the initiative bar.
                        --(See showDrawSteelRerollBanner.)
                        local q = dmhub.initiativeQueue
                        if q ~= nil and not q.hidden and m_heroesWin ~= nil then
                            q.playersGoFirst = m_heroesWin
                            q.playersTurn = m_heroesWin
                            dmhub:UploadInitiativeQueue()
                            if GameHud.instance ~= nil and GameHud.instance:has_key("choiceInitiativeBar") then
                                GameHud.instance.choiceInitiativeBar:FireEvent("refresh")
                            end
                        end
                    elseif options.controller then
                        local info = GameHud.instance.initiativeInterface
                        info.initiativeQueue = InitiativeQueue.Create()
                        info.initiativeQueue.playersGoFirst = m_heroesWin
                        info.initiativeQueue.playersTurn = m_heroesWin

                        --If an encounter was chosen (not "Custom"), attach a live encounter
                        --built from a deep copy of it. For a Custom combat there is no authored
                        --encounter, but we still create a basic live encounter so victory can be
                        --tracked and awarded -- it uses the Encounter defaults (1 Victory reward
                        --and the "all monsters defeated" victory condition).
                        if g_selectedEncounterOpenInitiative ~= nil then
                            info.initiativeQueue.liveEncounter = LiveEncounter.Create(g_selectedEncounterOpenInitiative)
                        else
                            local live = LiveEncounter.Create(Encounter.new())
                            --CountNonMinionMonsters (called in Create) reads the authored monster
                            --list, which is empty for Custom, so seed onsetMonsterCount from the
                            --actual non-minion monster tokens entering combat. Without this,
                            --CheckVictory short-circuits ("no monsters -> nothing to win").
                            local onsetMonsters = 0
                            for charid,_ in pairs(g_monsterTokensOpenInitiative or {}) do
                                local tok = dmhub.GetCharacterById(charid)
                                if tok ~= nil and tok.valid and tok.properties ~= nil
                                    and tok.properties:IsMonster() and not tok.properties.minion then
                                    onsetMonsters = onsetMonsters + 1
                                end
                            end
                            live.onsetMonsterCount = onsetMonsters
                            info.initiativeQueue.liveEncounter = live
                        end
                        --Snapshot the heroes' Recoveries at the onset of combat so the
                        --victory screen can show how they changed over the fight.
                        info.initiativeQueue.liveEncounter:RecordOnsetHeroes(g_playerTokensOpenInitiative)
                        g_selectedEncounterOpenInitiative = nil

                        --Combat has started: the readied encounter is consumed.
                        Encounter.ClearReadiedEncounter()

                        Commands.rollinitiative()

                        -- Track encounter_start event
                        local heroCount = 0
                        local monsterCount = 0
                        local monsterTypes = {}
                        local monsterRoles = {}
                        for charid,_ in pairs(g_playerTokensOpenInitiative or {}) do
                            heroCount = heroCount + 1
                        end
                        for charid,_ in pairs(g_monsterTokensOpenInitiative or {}) do
                            monsterCount = monsterCount + 1
                            local tok = dmhub.GetCharacterById(charid)
                            if tok ~= nil and tok.valid then
                                local monsterType = tok.properties:try_get("monster_type", "unknown")
                                monsterTypes[#monsterTypes+1] = monsterType
                                local role = tok.properties:try_get("role", "")
                                if role ~= "" then
                                    monsterRoles[#monsterRoles+1] = role
                                end
                            end
                        end
                        track("encounter_start", {
                            heroCount = heroCount,
                            monsterCount = monsterCount,
                            monsterTypes = table.concat(monsterTypes, ","),
                            monsterRoles = table.concat(monsterRoles, ","),
                            roundNumber = 1,
                            mapId = game.currentMapId,
                            mapName = (game.currentMap and game.currentMap.description) or "unknown",
                            dailyLimit = 10,
                        })
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
            local heroesWin = (num >= m_initiativeThreshold)
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

--Show the per-round "who goes first" reroll banner (used by Crows, which rolls
--for turn order at the start of every round). Reuses the Draw Steel banner, but
--in reroll mode it sets playersGoFirst on the EXISTING initiative queue when the
--roll resolves rather than starting a new combat (see the reroll branch in
--createDrawSteelBanner). Call this on a single client (the one advancing the
--round); it broadcasts the banner to the other users itself.
function showDrawSteelRerollBanner()
    if GameHud.instance == nil or GameHud.instance.parentPanel == nil then
        return
    end
    local banner = createDrawSteelBanner{ controller = true, reroll = true }
    GameHud.instance.parentPanel:AddChild(banner)
end

RegisterGameType("Encounter") --make sure we have it registered.

--Journal "Draw Steel!" button entry point. Opens the combat setup dialog scoped to
--the given authored encounter so the DM can confirm/adjust sides before rolling turn
--order. The dialog pre-selects this encounter in its dropdown (which routes the
--encounter's placed monsters into the participating "Monsters" pool) and sets up the
--heroes automatically. spawnedCharids is no longer needed -- the dialog derives the
--participating monsters from the encounter's spawns via the dropdown selection.
function Encounter.DrawSteelWithEncounter(encounter, spawnedCharids)
    local q = dmhub.initiativeQueue
    if q ~= nil and not q.hidden then
        --already in combat.
        return
    end

    Encounter.ShowCombatSetupDialog(nil, encounter)
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
    local winnerText
    if selfInput.winner == "players" then
        winnerText = "Heroes win turn order!"
    else
        winnerText = "Monsters win turn order!"
    end

    -- Collect all tokens and sort by playerControlled
    local playerTokenPanels = {}
    local monsterTokenPanels = {}

    local allTokens = {}
    for _,tok in ipairs(selfInput:GetPlayerTokens()) do
        if tok ~= nil and tok.valid then
            allTokens[#allTokens+1] = tok
        end
    end
    for _,tok in ipairs(selfInput:GetMonsterTokens()) do
        if tok ~= nil and tok.valid then
            allTokens[#allTokens+1] = tok
        end
    end

    local portraitHeight = 44
    local portraitAspect = 0.75
    local portraitWidth = math.floor(portraitHeight * portraitAspect)

    local function CreatePortraitPanel(tok, quantity)
        local portrait = tok.offTokenPortrait
        local imageRect = nil
        if portrait == tok.portrait or tok.popoutPortrait then
            imageRect = tok:GetPortraitRectForAspect(portraitAspect, portrait)
        end

        local quantityLabel = nil
        if quantity ~= nil and quantity > 1 then
            quantityLabel = gui.Label{
                floating = true,
                halign = "right",
                valign = "bottom",
                width = "auto",
                height = "auto",
                fontSize = 10,
                bold = true,
                color = "white",
                text = string.format("x%d", quantity),
                textOutlineWidth = 1,
                textOutlineColor = "black",
            }
        end

        return gui.Panel{
            width = portraitWidth,
            height = portraitHeight,
            bgimage = portrait,
            bgcolor = "white",
            cornerRadius = 4,
            imageRect = imageRect,
            hmargin = 1,
            vmargin = 1,
            interactable = true,
            hover = gui.Tooltip(tok.name),
            quantityLabel,
        }
    end

    -- Group monsters by portrait + monster_type to collapse duplicates
    local monsterGroups = {} -- key -> {tok, count}
    local monsterGroupOrder = {}

    local q = dmhub.initiativeQueue

    for _,tok in ipairs(allTokens) do
        print("INIT:: TOKEN:", tok.charid)
        if table.contains(selfInput.playerTokenIds, tok.charid) then
            print("INIT:: IS CHAR")
            playerTokenPanels[#playerTokenPanels+1] = CreatePortraitPanel(tok)
        elseif table.contains(selfInput.monsterTokenIds, tok.charid) then
            print("INIT:: IS MONSTER")
            local monsterType = tok.properties:try_get("monster_type", "")
            local groupKey = tostring(tok.portrait) .. "|" .. monsterType
            if monsterGroups[groupKey] == nil then
                monsterGroups[groupKey] = {tok = tok, count = 1}
                monsterGroupOrder[#monsterGroupOrder+1] = groupKey
            else
                monsterGroups[groupKey].count = monsterGroups[groupKey].count + 1
            end
        else
            print("INIT:: IS NEUTRAL")
        end
    end

    for _,groupKey in ipairs(monsterGroupOrder) do
        local group = monsterGroups[groupKey]
        monsterTokenPanels[#monsterTokenPanels+1] = CreatePortraitPanel(group.tok, group.count)
    end

    -- Balance items into rows so each row has roughly equal count
    local function BalancedGrid(panels, maxPerRow, gridHalign)
        local n = #panels
        if n == 0 then
            return gui.Panel{width = 0, height = 0}
        end
        local cols = math.min(n, maxPerRow)
        if n > maxPerRow then
            cols = math.ceil(math.sqrt(n))
            if cols > maxPerRow then cols = maxPerRow end
        end
        return gui.Panel{
            width = "auto",
            height = "auto",
            halign = gridHalign,
            flow = "horizontal",
            wrap = true,
            maxWidth = cols * (portraitWidth + 2),
            children = panels,
        }
    end

    local playersPanel = gui.Panel{
        width = "45%",
        height = "auto",
        halign = "left",
        valign = "center",
        BalancedGrid(playerTokenPanels, 4, "right"),
    }

    local vsLabel = gui.Label{
        text = "vs",
        fontSize = 11,
        color = "#999999",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        hmargin = 4,
        italics = true,
    }

    local monstersPanel = gui.Panel{
        width = "45%",
        height = "auto",
        halign = "right",
        valign = "center",
        BalancedGrid(monsterTokenPanels, 4, "left"),
    }

    local resultPanel = gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        vmargin = 6,

        styles = {
            {
                selectors = {"leftSword", "animate-in"},
                x = 80,
                opacity = 0,
                transitionTime = 0.6,
                easing = "easeOutCubic",
            },
            {
                selectors = {"rightSword", "animate-in"},
                x = -80,
                opacity = 0,
                transitionTime = 0.6,
                easing = "easeOutCubic",
            },
            {
                selectors = {"drawsteel-text", "animate-in"},
                opacity = 0,
                scale = 0.5,
                transitionTime = 0.4,
            },
        },

        refreshMessage = function(element, message)
        end,

        gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            halign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111111",
            cornerRadius = 4,
            vpad = 8,

            -- Swords + Draw Steel image
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "center",

                gui.Panel{
                    classes = {"leftSword"},
                    bgimage = "panels/initiative/drawsteel-sword.png",
                    bgcolor = "white",
                    width = 50,
                    height = "50% width",
                    valign = "center",
                    halign = "center",
                },

                gui.Panel{
                    classes = {"drawsteel-text"},
                    bgimage = "panels/initiative/drawsteel-text.png",
                    bgcolor = "white",
                    width = 160,
                    height = 22,
                    valign = "center",
                    halign = "center",
                    hmargin = 4,
                },

                gui.Panel{
                    classes = {"rightSword"},
                    bgimage = "panels/initiative/drawsteel-sword.png",
                    bgcolor = "white",
                    width = 50,
                    height = "50% width",
                    valign = "center",
                    halign = "center",
                    scale = {x = -1, y = 1},
                },
            },

            -- Winner text
            gui.Label{
                text = winnerText,
                fontSize = 12,
                color = "#cccccc",
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 4,
            },

            -- Players vs Monsters
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "center",
                tmargin = 4,
                bmargin = 2,

                playersPanel,
                vsLabel,
                monstersPanel,
            },
        },

        create = function(element)
            element:SetClassTree("animate-in", true)
            element:ScheduleEvent("animate-done", 0.05)
        end,

        ["animate-done"] = function(element)
            element:SetClassTree("animate-in", false)
        end,
    }

    return resultPanel
end

--- @param initiativeQueue InitiativeQueue
--- @param tokens CharacterToken[]
--- @return RollInitiativeChatMessage
function RollInitiativeChatMessage.Create(initiativeQueue, tokens, playerids, monsterids)
    local tokensByInitiative = {}
    for _,tok in ipairs(tokens) do
        local initiativeid = InitiativeQueue.GetInitiativeId(tok)
        if initiativeid ~= nil then
            if tokensByInitiative[initiativeid] == nil then
                tokensByInitiative[initiativeid] = tok
            else
                tokensByInitiative[initiativeid] = creature.GetSeniorToken{tokensByInitiative[initiativeid], tok}
            end
        end
    end

    return RollInitiativeChatMessage.new{
        playerTokenIds = playerids,
        monsterTokenIds = monsterids,
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

--selectedTokens: optional list of tokens to pre-mark as participating (else inferred).
--preselectEncounter: optional Encounter object to force-select in the dropdown; takes
--priority over the readied/open-journal inference. Used by the journal RichEncounter
--"Draw Steel!" button so the dialog opens scoped to that encounter.
local function ShowCombatSetupDialog(selectedTokens, preselectEncounter)
    --The party strength computed from the hero pool (see Encounter.PartyStrengthFromTokens),
    --or nil while the pool is empty. Shared between the hero and monster status labels so
    --the monster EV readout can classify against the current party.
    local m_partyStrength = nil
    local surprisedCondition = CharacterCondition.conditionsByName["surprised"]

    --Forward-declared so the per-group "Ungroup" button and "Group With" right-click
    --menu (built in CreateGroupPanel, below) can call back into the group/ungroup
    --logic. They are assigned later, once the pools and monsterGroups state they need
    --are in scope. BuildGroupWithSubmenu(group, panel) returns the context-menu
    --submenu entries listing the other groups on the same side.
    local UngroupGroup
    local BuildGroupWithSubmenu

    local CreateTokenPoolPanel = function(args)
        local sideline = args.sideline or false
        args.sideline = nil
        local pool
        pool = {
            classes = {"tokenPool", "bordered"},
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
                refreshSurprise = function(element)
                    local tokens = {}
                    for i,child in ipairs(args.pool.children) do
                        local group = child.data.group
                        for _,tok in ipairs(group.tokens) do
                            tokens[#tokens+1] = tok
                        end
                    end

                    local strength = Encounter.PartyStrengthFromTokens(tokens)
                    m_partyStrength = strength
                    if strength == nil then
                        element.text = ""
                        element.data.tooltip = nil
                        return
                    end

                    element.text = string.format("Encounter Strength: %d", strength.total)

                    local tooltip = string.format("%d Heroes", strength.numHeroes)
                    local numAllies = strength.numTokens - strength.numHeroes
                    if numAllies > 0 then
                        tooltip = string.format("%s, %d %s", tooltip, numAllies, cond(numAllies == 1, "Ally", "Allies"))
                    end

                    if strength.minLevel == strength.maxLevel then
                        tooltip = string.format("%s, Level %d", tooltip, strength.minLevel)
                    else
                        tooltip = string.format("%s, Levels %d-%d", tooltip, strength.minLevel, strength.maxLevel)
                    end

                    tooltip = string.format("%s\nBase Encounter Strength: %d", tooltip, strength.base)

                    tooltip = string.format("%s\nAverage Victories: %d", tooltip, strength.averageVictories)
                    tooltip = string.format("%s\nExtra Heroes from Victories: %d", tooltip, strength.victoryHeroes)
                    tooltip = string.format("%s\nEncounter Strength of a Single Hero: %d", tooltip, strength.singleHero)
                    tooltip = string.format("%s\nTotal Encounter Strength: %d", tooltip, strength.total)

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

                    local description = Encounter.DifficultyTier(ev, m_partyStrength)

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
                classes = {"sizeL", "bold"},
                text = args.title,
                width = "auto",
                height = "auto",
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
                    styles = {
                        {
                            selectors = {"surprised"},
                            color = "@warning",
                        },
                        {
                            selectors = {"sideline"},
                            hidden = 1,
                        },
                    },
                },
            }
        }

        --A grouping of more than one non-minion creature (as opposed to a minion
        --squad, or a captain leading a squad of minions) can be split back apart.
        --Offer an "Ungroup" button that gives each creature its own initiative slot
        --and rebuilds the list in place.
        local nonMinionCount = 0
        for _,tok in ipairs(group.tokens) do
            if not tok.properties.minion then
                nonMinionCount = nonMinionCount + 1
            end
        end

        if nonMinionCount > 1 then
            resultPanel:AddChild(gui.Button{
                classes = {"sizeS"},
                floating = true,
                text = "Ungroup",
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "bottom",
                margin = 4,
                press = function(element)
                    UngroupGroup(group, resultPanel)
                end,
            })
        end

        --Right-click a group row to fold it together with another group on the same
        --side ("Group With" -> pick a creature/group). The submenu is built fresh on
        --each right-click so it reflects the current pools after any earlier
        --group/ungroup edits.
        resultPanel.events.rightClick = function(element)
            local entries = BuildGroupWithSubmenu(group, resultPanel)
            if #entries == 0 then
                return
            end

            element.popup = gui.ContextMenu{
                entries = {
                    {
                        text = "Group With",
                        submenu = entries,
                    },
                },
            }
        end

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
    selectedTokens = selectedTokens or dmhub.selectedTokens
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
            if not playerSide and tok.playerControlled then
                playerSide = true
            end

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

            if partyid ~= nil then
                local partyTable = dmhub.GetTable(Party.tableName)
                local party = partyTable[partyid]
                --if the party is non-combatant then they are non-combatants.
                if party ~= nil then
                    selected = not party.noncombatant
                end
            end

            group.selected = selected
        end
    end

    --Heroes are placed into the participating / non-combatant pools immediately based
    --on the generic selected logic. Monster placement is deferred: which monsters
    --participate is driven by the chosen encounter (see ApplyEncounterToMonsters), so
    --we collect the monster groups and assign them once the default encounter is known.
    local monsterGroups = {}
    for key,group in pairs(groupings) do
        local panel = CreateGroupPanel(group)
        group.panel = panel
        if group.playerSide then
            local pool = cond(group.selected, heroesSelectedPool, heroesAvailablePool)
            pool:FireEventTree("add", panel)
        else
            --Park monsters in the non-combatant pool initially; ApplyEncounterToMonsters
            --moves the ones matching the chosen encounter into the participating pool.
            monstersAvailablePool:FireEventTree("add", panel)
            monsterGroups[#monsterGroups + 1] = group
        end
    end

    --Split a multi-creature (non-minion) initiative group back into individual
    --creatures. Assigned here (not at its forward declaration) so it closes over
    --monsterGroups and CreateGroupPanel, which do not exist yet where the per-group
    --"Ungroup" button that calls it is built.
    UngroupGroup = function(group, panel)
        local pool = panel.parent

        --Give each creature its own initiative id so GetInitiativeId stops returning
        --the shared grouping id. A fresh guid per token matches the "Ungroup
        --Initiative" button on the character panel.
        for _,tok in ipairs(group.tokens) do
            tok:ModifyProperties{
                description = "Ungroup Initiative",
                execute = function()
                    tok.properties.initiativeGrouping = dmhub.GenerateGuid()
                end,
            }
        end

        panel:DestroySelf()

        --Drop the combined group from monsterGroups so a later encounter-dropdown
        --change (ApplyEncounterToMonsters) does not try to reparent the dead panel.
        for i,g in ipairs(monsterGroups) do
            if g == group then
                table.remove(monsterGroups, i)
                break
            end
        end

        --Rebuild one panel per creature in the same pool, keeping monsterGroups in
        --sync so the new panels continue to route on encounter changes.
        for _,tok in ipairs(group.tokens) do
            local newGroup = { playerSide = group.playerSide, selected = group.selected, tokens = { tok } }
            local newPanel = CreateGroupPanel(newGroup)
            newGroup.panel = newPanel
            if pool ~= nil then
                pool:FireEvent("add", newPanel)
            end
            if not group.playerSide then
                monsterGroups[#monsterGroups + 1] = newGroup
            end
        end
    end

    local function RemoveFromMonsterGroups(g)
        for i,mg in ipairs(monsterGroups) do
            if mg == g then
                table.remove(monsterGroups, i)
                break
            end
        end
    end

    --Fold otherGroup into targetGroup: put every token of both on a single shared
    --initiative id, then replace both rows with one combined row in targetGroup's
    --pool. Reuses an existing grouping id if either side already has one so we do not
    --churn ids needlessly (matches GetInitiativeId, where initiativeGrouping wins).
    local function MergeGroups(targetGroup, targetPanel, otherGroup, otherPanel)
        local groupingId = nil
        for _,tok in ipairs(targetGroup.tokens) do
            if tok.properties.initiativeGrouping then
                groupingId = tok.properties.initiativeGrouping
                break
            end
        end
        if groupingId == nil then
            for _,tok in ipairs(otherGroup.tokens) do
                if tok.properties.initiativeGrouping then
                    groupingId = tok.properties.initiativeGrouping
                    break
                end
            end
        end
        if groupingId == nil then
            groupingId = dmhub.GenerateGuid()
        end

        local allTokens = {}
        for _,tok in ipairs(targetGroup.tokens) do
            allTokens[#allTokens + 1] = tok
        end
        for _,tok in ipairs(otherGroup.tokens) do
            allTokens[#allTokens + 1] = tok
        end

        for _,tok in ipairs(allTokens) do
            tok:ModifyProperties{
                description = "Group Initiative",
                execute = function()
                    tok.properties.initiativeGrouping = groupingId
                end,
            }
        end

        --The combined row lands in the right-clicked row's pool (its participation
        --state wins over the group it absorbs).
        local pool = targetPanel.parent

        targetPanel:DestroySelf()
        otherPanel:DestroySelf()
        RemoveFromMonsterGroups(targetGroup)
        RemoveFromMonsterGroups(otherGroup)

        local combined = { playerSide = targetGroup.playerSide, selected = targetGroup.selected, tokens = allTokens }
        local combinedPanel = CreateGroupPanel(combined)
        combined.panel = combinedPanel
        if pool ~= nil then
            pool:FireEvent("add", combinedPanel)
        end
        if not combined.playerSide then
            monsterGroups[#monsterGroups + 1] = combined
        end
    end

    --Build the "Group With" submenu for a group: one entry per other group on the
    --same side (heroes vs monsters), across both the participating and non-combatant
    --pools. Read live from the pools so it reflects any earlier group/ungroup edits.
    BuildGroupWithSubmenu = function(group, panel)
        local pools
        if group.playerSide then
            pools = { heroesSelectedPool, heroesAvailablePool }
        else
            pools = { monstersSelectedPool, monstersAvailablePool }
        end

        local entries = {}
        for _,pool in ipairs(pools) do
            for _,child in ipairs(pool.children) do
                local otherGroup = child.data ~= nil and child.data.group or nil
                if otherGroup ~= nil and otherGroup ~= group then
                    entries[#entries + 1] = {
                        text = otherGroup.name,
                        click = function()
                            panel.popup = nil
                            MergeGroups(group, panel, otherGroup, child)
                        end,
                    }
                end
            end
        end

        return entries
    end

    local m_initiativeResult = "roll"
    local m_initiativeLocked = false

    --Scour the current map's journal info bubbles plus game-wide journal documents
    --for authored encounters and build the encounter dropdown options: a "Custom"
    --choice plus one entry per encounter found.
    local m_encountersOnMap = Encounter.GetEncountersOnCurrentMap()
    local m_encounterOptions = { { id = "custom", text = "Custom" } }
    for i, info in ipairs(m_encountersOnMap) do
        m_encounterOptions[#m_encounterOptions + 1] = {
            id = string.format("encounter-%d", i),
            text = info.name,
        }
    end

    --Infer the default encounter for the dropdown: a readied encounter (set by an
    --encounter's "Place on Map" button) wins; otherwise the first encounter in the
    --journal document currently open in the tabbed viewer; otherwise Custom.
    local m_selectedEncounterId = "custom"
    local defaultEncounterIndex = nil

    --An explicitly requested encounter (e.g. the journal "Draw Steel!" button) wins
    --over every inferred default below.
    if preselectEncounter ~= nil then
        for i, info in ipairs(m_encountersOnMap) do
            if info.encounter == preselectEncounter or info.name == preselectEncounter.name then
                defaultEncounterIndex = i
                break
            end
        end
    end

    local readiedEncounter = Encounter.GetReadiedEncounter()
    if defaultEncounterIndex == nil and readiedEncounter ~= nil then
        for i, info in ipairs(m_encountersOnMap) do
            if info.encounter == readiedEncounter or info.name == readiedEncounter.name then
                defaultEncounterIndex = i
                break
            end
        end
    end

    if defaultEncounterIndex == nil then
        local openDocId = CustomDocument.GetCurrentJournalDocId()
        if openDocId ~= nil then
            for i, info in ipairs(m_encountersOnMap) do
                if info.docid == openDocId then
                    defaultEncounterIndex = i
                    break
                end
            end
        end
    end

    if defaultEncounterIndex ~= nil then
        m_selectedEncounterId = string.format("encounter-%d", defaultEncounterIndex)
    end

    --Map a dropdown option id ("custom" or "encounter-N") back to its entry in
    --m_encountersOnMap, or nil for Custom.
    local function ResolveEncounterEntry(encounterId)
        if encounterId == nil or encounterId == "custom" then
            return nil
        end
        local idx = tonumber(string.match(encounterId, "encounter%-(%d+)"))
        return idx ~= nil and m_encountersOnMap[idx] or nil
    end

    --Assign each monster group to the participating "Monsters" pool or to "Non-Combatant
    --Monsters". When an encounter is chosen, a group participates if it belongs to that
    --encounter (i.e. it was placed on the map by that encounter, tracked in the
    --RichEncounter's spawns). With no encounter chosen ("Custom") we fall back to the
    --generic selected logic, which participates all monsters by default (unless specific
    --tokens were pre-selected, or their party is flagged non-combatant).
    local function ApplyEncounterToMonsters(encounterEntry)
        local matching = nil
        if encounterEntry ~= nil and encounterEntry.richEncounter ~= nil then
            matching = {}
            for _,charid in ipairs(encounterEntry.richEncounter:try_get("spawns", {})) do
                matching[charid] = true
            end
        end

        for _,group in ipairs(monsterGroups) do
            local participates
            if matching == nil then
                participates = group.selected
            else
                participates = false
                for _,tok in ipairs(group.tokens) do
                    if matching[tok.charid] then
                        participates = true
                        break
                    end
                end
            end

            local pool = cond(participates, monstersSelectedPool, monstersAvailablePool)
            group.panel:Unparent()
            pool:FireEvent("add", group.panel)
        end
    end

    --Initial population using the inferred default encounter.
    ApplyEncounterToMonsters(ResolveEncounterEntry(m_selectedEncounterId))

    local m_reminderPanel = gui.ReminderTextPanel{
        halign = "center",
        valign = "center",
        tokens = dmhub.allTokens,
        domain = "initiative",
    }

    local dialog
    dialog = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.MergeStyles({
            {
                selectors = {"tokenPool"},
                width = 340,
                height = 360,
                pad = 4,
                borderBox = true,
            },
            {
                selectors = {"tokenPool", "drag-target"},
                borderColor = "@accent",
            },
            {
                selectors = {"tokenPool", "drag-target-hover"},
                borderColor = "@accentHover",
            },
            {
                selectors = {"tokenGroup", "hover"},
                bgcolor = "@accent",
            },
        }),

        width = 1024,
        height = 968,

        gui.Panel{
            halign = "center",
            valign = "center",
            width = 800,
            height = 800,
            flow = "vertical",

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                valign = "top",
                vmargin = 8,
                gui.Label{
                    text = "Encounter:",
                    valign = "center",
                    hmargin = 8,
                },
                gui.Dropdown{
                    width = 240,
                    options = m_encounterOptions,
                    idChosen = m_selectedEncounterId,
                    change = function(element)
                        m_selectedEncounterId = element.idChosen
                        ApplyEncounterToMonsters(ResolveEncounterEntry(m_selectedEncounterId))
                        element.root:FireEventTree("refreshSurprise")
                    end,
                },
            },

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
                    classes = {"sizeL", "bold"},
                    width = 22,
                    valign = "center",
                    halign = "center",
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

            m_reminderPanel,

            gui.EnumeratedSliderControl{
                width = 600,
                options = {
                    { id = "heroes", text = "Heroes Win Turn Order"},
                    { id = "roll", text = "Roll for Turn Order"},
                    { id = "monsters", text = "Monsters Win Turn Order"},
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
            classes = {"modalTitle"},
            text = "Prepare Combat",
        },

        gui.Panel{
            width = "100%",
            valign = "bottom",
            halign = "center",
            flow = "horizontal",
            gui.Button{
                classes = {"sizeL"},
                text = "Draw Steel!",
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

                    --Resolve the chosen encounter (nil for "Custom") and carry it to the
                    --queue creation that happens once the Draw Steel banner resolves.
                    local chosenEntry = ResolveEncounterEntry(m_selectedEncounterId)
                    g_selectedEncounterOpenInitiative = chosenEntry and chosenEntry.encounter or nil

                    g_selectedTokensOpenInitiative = tokens
                    if m_initiativeResult == "roll" then
                        m_initiativeResult = nil
                    end
                    showDrawSteelBanner(m_initiativeResult)
                end,
            },
        },

        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            press = function()
                GameHud.instance:CloseModal(dialog)
            end,
        }
    }

    GameHud.instance:ShowModal(dialog)
end

--Public handle so callers earlier in the file (Encounter.DrawSteelWithEncounter) and
--other modules can open the combat setup dialog, optionally scoped to an encounter.
Encounter.ShowCombatSetupDialog = ShowCombatSetupDialog

Commands.RegisterMacro{
    name = "rollinitiative",
    summary = "start combat",
    doc = "Usage: /rollinitiative [x1 y1 x2 y2]\nStarts combat with selected tokens, or tokens in a rectangular area if coordinates are given.",
    command = function(str)
    local args = string.split(str or "", " ")

    local tokens = dmhub.selectedTokens

    print("ARGS::", #args)
    if #args == 4 then
        local x1 = tonumber(args[1]) or 0
        local y1 = tonumber(args[2]) or 0
        local x2 = tonumber(args[3]) or 0
        local y2 = tonumber(args[4]) or 0

        if x1 > x2 then
            local temp = x1
            x1 = x2
            x2 = temp
        end

        if y1 > y2 then
            local temp = y1
            y1 = y2
            y2 = temp
        end

        tokens = {}

        for _,token in ipairs(dmhub.allTokens) do
            if token.loc.x >= x1 and token.loc.x <= x2 and token.loc.y >= y1 and token.loc.y <= y2 then
                tokens[#tokens+1] = token
            end
        end

        print("ARGS:: GOT TOKENS", #tokens, "/", #dmhub.allTokens)
    end


    local info = GameHud.instance.initiativeInterface
    if info.initiativeQueue == nil or info.initiativeQueue.hidden then
        ShowCombatSetupDialog(tokens)

        --g_selectedTokensOpenInitiative = tokens
        --showDrawSteelBanner()
        return
    end

    if g_selectedTokensOpenInitiative ~= nil then
        tokens = g_selectedTokensOpenInitiative
        g_selectedTokensOpenInitiative = nil
    end

    local isNewCombat = next(info.initiativeQueue.entries) == nil

    local playerids = {}
    local monsterids = {}

    local playerPartyId = GetDefaultPartyID()
    local playerParty = GetParty(GetDefaultPartyID())
    local heroVictories = {}
    for _,tok in ipairs(tokens) do
        if tok ~= nil and tok.valid then
            local partyid = tok.partyId
            local playerSide = partyid ~= nil and ((partyid == playerPartyId) or (playerParty ~= nil and playerParty:GetAllyParties()[partyid] ~= nil))
            if not playerSide and tok.playerControlled then
                playerSide = true
            end

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

            if playerSide then
                playerids[#playerids+1] = tok.charid
            else
                monsterids[#monsterids+1] = tok.charid
            end

            tok.properties:DispatchEvent("rollinitiative", {})
            tok.properties:DispatchEvent("beginround")
        end
    end

    if isNewCombat then
        local message = RollInitiativeChatMessage.Create(info.initiativeQueue, tokens, playerids, monsterids)
        chat.SendCustom(message)
    end


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

    if isNewCombat then
        CharacterResource.SetMalice(CharacterResource.GetMalice() + averageVictories + info.initiativeQueue:CalculateMaliceGain(), "Start of Combat Malice")
        CharacterResource.SetVillainActions(1)
    end

    info.UploadInitiative()
    end,
}

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