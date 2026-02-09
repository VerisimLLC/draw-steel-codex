local mod = dmhub.GetModLoading()

local ActionMenu
local CreateAbilityController

---  @type function
local CalculateSpellTargeting

--- @type nil|Panel
local g_abilityController = nil

--- @type nil|Panel
local g_triggerPanel = nil

--- @type nil|Panel
local g_actionBar = nil

--- @type string[]
local g_targetsChosen = {}

--- @type nil|string The first target chosen by the player, the charid of this token.
local g_firstTarget = nil

--- @type Loc[]
local m_positionTargetsChosen = {} --list of Locs for targets. Used on emptyspace targeting.

--- @type nil|ActivatedAbility
local g_currentAbility

--- @type number
local g_range = 0

--- @type table
local g_currentSymbols = {}

--- @type nil|CharacterToken
local g_token

--- @type nil|Creature
local g_creature

--- @type nil|Panel
local g_channeledResourcePanel

local g_casterTokenStack = {}

--- @type {shapePathEnd: nil|LuaShape[], labelsAtPathEnd: nil|LuaObjectReference[], pathEndOvershoot: nil|number, fallingShape: nil|LuaObjectReference, shapeRequiresConfirm: nil|boolean, shapeConfirmedLoc: nil|Loc, shape: nil|LuaShape, label: nil|LuaObjectReference, radius: nil|LuaObjectReference, showingMovementArrow: nil|boolean}
local g_pointTargeting = {}

--- @type nil|{oncast=nil|function, oncancel=nil|function}
local g_invokerInfo = nil

--tokens we are force targeting based on them being in a radius. A mapping of tokenid -> token
--- @type table<string, CharacterToken>
local g_pointForceTargets = {}

--- @type function[] a list of functions we will call when we cancel casting.
local g_castingDestructors = {}

function IsCurrentlyUsingAbility()
    return g_currentAbility ~= nil
end

local function GetHeroicResourceOrMaliceCost(ability, symbols)
    symbols = symbols or g_currentSymbols

    local cost = ability:GetCost(g_token, symbols)
    if cost == nil or cost.details == nil then
        return nil
    end

    local heroicResourceEntry = nil
    for _, entry in ipairs(cost.details) do
        if entry.cost == CharacterResource.heroicResourceId or entry.cost == CharacterResource.maliceResourceId then
            heroicResourceEntry = entry
            break
        end
    end

    if heroicResourceEntry == nil then
        return nil
    end

    return heroicResourceEntry.quantity
end

local function ClearPointTargeting()
    if g_pointTargeting.labelsAtPathEnd ~= nil then
        for _, label in ipairs(g_pointTargeting.labelsAtPathEnd) do
            label:Destroy()
        end
    end

    if g_pointTargeting.fallingShape ~= nil then
        g_pointTargeting.fallingShape:Destroy()
    end

    if g_pointTargeting.label ~= nil then
        g_pointTargeting.label:Destroy()
    end

    if g_pointTargeting.radius ~= nil then
        g_pointTargeting.radius:Destroy()
    end

    g_pointTargeting = {}
end

local function PushCasterToken(token)
    if token == nil then
        return
    end

    dmhub.tokenInfo:PushSelectedTokenOverride(token)

    g_casterTokenStack[#g_casterTokenStack + 1] = token
    g_token = token
    print("ActionBar:: push g_token =", g_token)
    g_creature = g_token.properties
end

local function TryPopCasterToken()
    if #g_casterTokenStack == 0 then
        return false
    end

    dmhub.tokenInfo:PopSelectedTokenOverride(g_casterTokenStack[#g_casterTokenStack])
    g_token = dmhub.selectedOrPrimaryTokens[1]
    print("ActionBar:: pop g_token =", g_token)
    g_creature = g_token and g_token.properties or nil

    g_casterTokenStack[#g_casterTokenStack] = nil
    return true
end

--- @type nil|string
local g_prevCharid

--- @type table<string, number>
local g_resources

--- @type ActivatedAbility[]
local g_abilities
local g_initiative

local g_newActionBar = setting {
    id = "newactionbar",
    description = "Use New Action Bar",
    storage = "preference",
    section = "General",
    default = true,
    editor = "check",
}

local g_preferredForcedMovementType = setting {
    id = "preferredforcedmovementtype",
    storage = "preference",
    default = "none",
}


local function ActionBarDrawer(args)
    local m_resourceid
    local m_resourceInfo

    local m_moveBar
    local m_rightInfoText

    local m_costDiamond

    local m_glow


    if args.type == "malice" then
        m_glow = gui.Panel {
            blend = "add",
            floating = true,
            bgimage = true,
            width = "90%",
            height = 80,
            halign = "center",
            valign = "top",
            bgcolor = "white",
            y = -80,
            interactable = false,
            gradient = Styles.Ability.maliceGlowGradient,

            refresh = function(element)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden or q:ChoosingTurn() then
                    element:SetClass("off", true)
                    return
                end

                local malice = CharacterResource.GetMalice()
                local canAfford = false

                for _, ability in ipairs(g_abilities) do
                    if ability.categorization == "Malice" then
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })
                        if cost ~= nil and cost <= malice then
                            canAfford = true
                            break
                        end
                    end
                end

                if not canAfford then
                    element:SetClass("off", true)
                    return
                end

                local currentInitiativeId = dmhub.initiativeQueue.currentTurn
                local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface,
                currentInitiativeId) or {}
                for _, token in ipairs(tokens) do
                    local usage = token.properties:GetResourceUsage(CharacterResource.actionResourceId, "round")
                    if usage ~= nil and usage > 0 then
                        element:SetClass("off", true)
                        return
                    end

                    local usage = token.properties:GetResourceUsage(CharacterResource.maneuverResourceId, "round")
                    if usage ~= nil and usage > 0 then
                        element:SetClass("off", true)
                        return
                    end
                end

                element:SetClass("off", false)
            end,

            styles = {
                {
                    brightness = 3,
                },
                {
                    selectors = { "on" },
                    brightness = 5,
                    transitionTime = 0.6,
                    easing = "easeInOutSine",
                },
                {
                    selectors = { "off" },
                    transitionTime = 0.5,
                    brightness = 0,
                },
            },

            thinkTime = 0.6,
            think = function(element)
                element:SetClass("on", not element:HasClass("on"))
            end,
        }

        m_rightInfoText = gui.Label {
            maxWidth = 100,
            fontSize = 10,
            minFontSize = 6,
            bold = true,
            color = "white",
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            rotate = -135,
            events = {},
        }

        m_costDiamond = gui.Panel {
            styles = { Styles.ActionMenu,

                gui.Style {
                    classes = { "costDiamond" },
                    brightness = 1,
                    borderColor = "grey",
                    priority = 5,
                },

                gui.Style {
                    classes = { "costDiamond", "parent:hover" },
                    brightness = 1.5,
                    borderColor = "grey",
                    priority = 5,
                },

            },
            classes = { "costDiamond", "malice" },
            floating = true,
            rotate = 135,

            halign = "center",
            valign = "top",
            vmargin = -13.5,
            bgcolor = "white",

            border = { x1 = 0, y1 = 2, x2 = 2, y2 = 0 },
            --bgcolor = "#10110F",
            gradient = Styles.Ability.maliceDiamondGradient,



            --vback

            gui.Panel {
                classes = { "costInnerDiamond", "malice" },

                --bgcolor = "#e9b86f",
                --borderWidth = 1,
                --borderColor = "white",

                m_rightInfoText,

            },



        }





        m_rightInfoText.editable = true
        m_rightInfoText.numeric = true
        m_rightInfoText.characterLimit = 2
        m_rightInfoText.swallowPress = true
        m_rightInfoText.selfStyle.minWidth = 30
        m_rightInfoText.selfStyle.textAlignment = "center"
        m_rightInfoText.selfStyle.fontSize = 14
        m_rightInfoText.selfStyle.bold = true
        m_rightInfoText.events.change = function(element)
            local value = tonumber(element.text) or 0
            if value < 0 then
                value = 0
            end
            CharacterResource.SetMalice(value, "Manually set")
        end
        m_rightInfoText.events.hover = function(element)
            local history = CharacterResource.GetGlobalResourceHistory(CharacterResource.maliceResourceId)
            element.tooltip = gui.StatsHistoryTooltip { description = "Malice", entries = history }
        end
        m_rightInfoText.events.refresh = function(element)
            element.text = string.format("%d", CharacterResource.GetMalice())
        end
    end

    if args.type == "trigger" then
        m_rightInfoText = gui.Label {
            floating = true,
            maxWidth = 100,
            fontSize = 10,
            minFontSize = 6,
            margin = 6,
            bold = true,
            color = Styles.Ability.accentColor,
            halign = "right",
            valign = "top",
            width = "auto",
            height = "auto",
            events = {},
        }
    end

    if args.type == "trigger" then
        m_resourceid = CharacterResource.triggerResourceId
    elseif args.type == "action" then
        m_resourceid = CharacterResource.actionResourceId
    elseif args.type == "maneuver" then
        m_resourceid = CharacterResource.maneuverResourceId
    elseif args.type == "malice" then
        m_resourceid = CharacterResource.maliceResourceId
    elseif args.type == "free" then
        --pass.
    else
        local m_segments = {}
        local m_margin = 2
        m_moveBar = gui.Panel {
            floating = true,
            width = "auto",
            height = 6,
            halign = "center",
            valign = "bottom",
            bmargin = 5,
            flow = "horizontal",
            styles = {
                {
                    selectors = { "segment" },
                    bgcolor = Styles.Ability.accentColor,
                },
                {
                    selectors = { "segment", "otherturn" },
                    bgcolor = "#666666",
                },
                {
                    selectors = { "segment", "expended" },
                    bgcolor = "#333333",
                    borderColor = "#666666",
                    borderWidth = 1,
                },
                {
                    selectors = { "segment", "temporarilyBonused" },
                    bgcolor = "#00ffff",
                },
                {
                    selectors = { "segment", "temporarilyBonused", "expended" },
                    bgcolor = "#00ffff",
                    brightness = 0.4,
                    saturation = 0.5,
                },
                {
                    selectors = { "segment", "temporarilyBonused", "otherturn" },
                    bgcolor = "#00ffff",
                    brightness = 0.4,
                    saturation = 0.5,
                },
                {
                    selectors = { "segment", "temporarilyNegated" },
                    bgcolor = "#666666",
                    borderWidth = 1,
                    borderColor = Styles.Ability.forbiddenColor,
                },
            },

            refresh = function(element)
                local movementSpeed = math.max(0, g_creature:CurrentMovementSpeed())
                local moved = g_creature:DistanceMovedThisTurn()

                --find the movement speed base, without temporary modifiers.
                local movementModifications = g_creature:DescribeSpeedModifications()
                local movementSpeedBeforeTemporary = movementSpeed
                for _, info in ipairs(movementModifications) do
                    if info.temporal then
                        movementSpeedBeforeTemporary = info.previous
                    end
                end


                if movementSpeed > 16 then
                    moved = max(0, moved - (movementSpeed - 16))
                    movementSpeed = 16
                end

                local wantedSegments = math.max(movementSpeed, movementSpeedBeforeTemporary)

                if wantedSegments > #m_segments then
                    for i = #m_segments + 1, wantedSegments do
                        m_segments[i] = gui.Panel {
                            classes = { "segment" },
                            width = 6,
                            height = "100%",
                            hmargin = 1,
                            bgimage = true,
                            halign = "center",
                            valign = "center",
                        }
                    end

                    element.children = m_segments
                end

                for i = 1, movementSpeed do
                    m_segments[i]:SetClass("collapsed", false)
                    m_segments[i]:SetClass("temporarilyNegated", false)
                    m_segments[i]:SetClass("temporarilyBonused", i > movementSpeedBeforeTemporary)
                    m_segments[i]:SetClass("otherturn", not g_creature:IsOurTurn())
                    if i <= movementSpeed - moved then
                        m_segments[i]:SetClass("expended", false)
                    else
                        m_segments[i]:SetClass("expended", true)
                    end
                end

                for i = movementSpeed + 1, movementSpeedBeforeTemporary do
                    m_segments[i]:SetClass("collapsed", false)
                    m_segments[i]:SetClass("temporarilyNegated", true)
                end

                for i = wantedSegments + 1, #m_segments do
                    m_segments[i]:SetClass("collapsed", true)
                end
            end,
        }
    end

    if m_resourceid ~= nil then
        m_resourceInfo = dmhub.GetTable(CharacterResource.tableName)[m_resourceid]
        if m_resourceInfo == nil then
            m_resourceid = nil
        end
    end

    args.resourceid = m_resourceid
    args.resourceInfo = m_resourceInfo

    local m_usedAbilityIcon


    if args.type == "trigger" then
        m_usedAbilityIcon = gui.TriggerPanel {
            styles = Styles.TriggerStyles,
            classes = { "hidden" },
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
        }
    else
        m_usedAbilityIcon = gui.Panel {
            classes = { "hidden" },
            width = 24,
            height = 24,
            halign = "center",
            valign = "center",
        }
    end

    local m_diamond = gui.Panel {
        classes = { "diamond" },
        rotate = 45,
        width = 12,
        height = 12,
        tmargin = -5,
        floating = true,
        halign = "center",
        valign = "top",
        bgcolor = Styles.Ability.borderColor,
        bgimage = true,
    }

    local m_diamondAccent = gui.Panel {
        classes = { "diamondAccent" },
        width = "100%-20",
        height = 6,
        floating = true,
        tmargin = 5,
        halign = "center",
        valign = "top",

        gui.Panel {
            width = "50%-6",
            halign = "left",
            valign = "top",
            height = 1,
            bgcolor = Styles.Ability.goldColor,
            bgimage = true,
        },

        gui.Panel {
            width = "50%-6",
            halign = "right",
            valign = "top",
            height = 1,
            bgcolor = Styles.Ability.goldColor,
            bgimage = true,
        },


        gui.Panel {
            halign = "center",
            valign = "top",
            y = -4,
            width = 10,
            height = 10,
            rotate = 45,
            border = { x1 = 1, y1 = 1, x2 = 0, y2 = 0 },
            borderColor = Styles.Ability.goldColor,
            bgimage = true,
            bgcolor = "clear",
        },
    }

    local resultPanel

    local resultPanelArgs = {
        classes = { "actionBarDrawer" },

        press = function(element)

            args.drawer = resultPanel
            element:FindParentWithClass("actionBar"):FireEventTree("menu", args)
        end,

        menuStatus = function(element, menuInfo)
            local active = menuInfo ~= nil and menuInfo.type == args.type
            element:SetClass("active", active)
            element.captureEscape = active
            element.mapfocus = active
        end,

        mappress = function(element, loc, pos)
            element:FireEvent("escape")
        end,

        closemenu = function(element)
            if element:HasClass("active") then
                element:FireEvent("press")
            end
        end,

        escapePriority = EscapePriority.CANCEL_ACTION_BAR,
        escape = function(element)
            element:FireEvent("press")
        end,


        refresh = function(element)
            local newToken = g_token.charid ~= element.data.lastcharid

            element.data.lastcharid = g_token.charid

            if args.type == "free" then
                local haveFree = false
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == "none" and ability.categorization ~= "Malice" and ability.categorization ~= "Move" and ability.categorization ~= "Hidden" then
                        haveFree = true
                        break
                    end
                end

                resultPanel:SetClass("collapsed", not haveFree)
                if not haveFree then
                    return
                end

                --element.text = "Free actions available"
                if newToken then
                    resultPanel:SetClassTreeImmediate("available", true)
                else
                    resultPanel:SetClassTree("available", true)
                end
            end

            if args.type == "malice" then
                local isMonster = g_creature:IsMonster()
                local isFollower = g_creature:IsFollower()
                resultPanel:SetClass("collapsed", not isMonster or isFollower)
                if not isMonster or isFollower then
                    return
                end
            end

            if g_initiative == nil then
                if newToken then
                    resultPanel:SetClassTreeImmediate("available", false)
                else
                    resultPanel:SetClassTree("available", false)
                end

                return
            end

            if args.type ~= "trigger" and (not g_token.properties:IsOurTurn()) then
                if newToken then
                    resultPanel:SetClassTreeImmediate("available", false)
                else
                    resultPanel:SetClassTree("available", false)
                end

                return
            end

            if args.type == "move" then
                local movementSpeed = g_creature:CurrentMovementSpeed()
                local moved = g_creature:DistanceMovedThisTurn()

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", moved < movementSpeed)
                else
                    resultPanel:SetClassTree("available", moved < movementSpeed)
                end

                return
            end

            if args.type == "trigger" then
                local triggersDisabled = g_token.properties:CalculateNamedCustomAttribute(
                    "Cannot Use Triggered Abilities")
                if triggersDisabled > 0 then
                    local reason = "Cannot use triggers"
                    local modifications = g_token.properties:DescribeModificationsToNamedCustomAttribute(
                        "Cannot Use Triggered Abilities")
                    if modifications and #modifications > 0 then
                        reason = string.format("%s: Cannot use triggers", modifications[1].key)
                    end

                    --TODO: find way to show why we can't use triggers.
                    --element.text = reason

                    if newToken then
                        resultPanel:SetClassTreeImmediate("available", false)
                    else
                        resultPanel:SetClassTree("available", false)
                    end

                    return
                end

                local triggers = g_token.properties:GetAvailableTriggers()
                local count = 0
                local freecount = 0
                if triggers ~= nil then
                    for key, trigger in pairs(triggers) do
                        count = count + 1
                        if trigger.free then
                            freecount = freecount + 1
                        end
                    end
                end

                local isAvailable = true
                if m_resourceid ~= nil then
                    local usage = g_creature:GetResourceUsage(m_resourceid, m_resourceInfo.usageLimit)
                    local available = (g_resources[m_resourceid] or 0) - usage
                    isAvailable = count > 0 or available > 0
                end

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", isAvailable)
                else
                    resultPanel:SetClassTree("available", isAvailable)
                end



                --m_usedAbilityIcon:SetClass("free", freecount == count)

                --[[
                if count == 1 then
                    m_usedAbilityIcon:SetClass("hidden", false)
                    m_usedAbilityIcon.text = "!"
                    for key, trigger in pairs(triggers) do
                        if trigger.free then
                            element.text = "Free triggered action available"
                        else
                            element.text = "Triggered action available"
                        end
                        m_rightInfoText.text = trigger.text
                    end
                elseif count > 1 then
                    m_usedAbilityIcon:SetClass("hidden", false)
                    m_usedAbilityIcon.text = "!"
                    m_rightInfoText.text = string.format("%d available", count)

                    if freecount == count then
                        element.text = "Free triggered actions available"
                    else
                        element.text = "Triggered actions available"
                    end
                else
                    m_rightInfoText.text = ""
                    if available > 0 then
                        element.text = "Triggered action available"
                        m_usedAbilityIcon:SetClass("hidden", true)
                    else
                        element.text = "Triggered action used"
                        m_usedAbilityIcon.text = ""
                        m_usedAbilityIcon:SetClass("hidden", false)
                        m_usedAbilityIcon.bgimage = "ui-icons/close.png"
                        m_usedAbilityIcon.selfStyle = {
                            bgcolor = "grey",
                        }
                    end
                end
                --]]
                return
            end

            local hideAbilityIcon = true

            if m_resourceid ~= nil then
                local usage = g_creature:GetResourceUsage(m_resourceid, m_resourceInfo.usageLimit)
                local available = (g_resources[m_resourceid] or 0) - usage

                if newToken then
                    resultPanel:SetClassTreeImmediate("available", available > 0)
                else
                    resultPanel:SetClassTree("available", available > 0)
                end


                --[[
                if args.type == "malice" then
                    element.text = "Use at start of a monster's turn"
                elseif available == 0 then
                    local setIcon = false
                    hideAbilityIcon = false
                    local text = nil
                    local history = g_creature:GetStatHistory(m_resourceid)
                    if history ~= nil then
                        local timestamp = 0
                        local refreshid = g_creature:GetResourceRefreshId("round")
                        local abilityid = nil
                        for key, entry in pairs(history.entries) do
                            local ts = entry.timestamp or 0
                            if type(ts) == "string" then
                                ts = math.huge
                            end
                            if entry.refreshid == refreshid and ts > timestamp and entry.abilityid ~= nil then
                                timestamp = ts
                                abilityid = entry.abilityid
                            end
                        end

                        if abilityid ~= nil then
                            for _, ability in ipairs(g_abilities) do
                                if ability.guid == abilityid then
                                    text = string.format("Used on <b>%s</b>", ability.name)

                                    m_usedAbilityIcon.bgimage = ability.iconid
                                    m_usedAbilityIcon.selfStyle = ability.display
                                    setIcon = true
                                    break
                                end
                            end
                        end
                    end

                    if setIcon == false then
                        --we couldn't find a specific icon to set so just
                        --use a generic one.
                        m_usedAbilityIcon.bgimage = "ui-icons/close.png"
                        m_usedAbilityIcon.selfStyle = {
                            bgcolor = "grey",
                        }
                    end


                    text = text or string.format("Your %s has been used", args.type)
                    element.text = text
                elseif available == 1 then
                    element.text = string.format("You have one %s available", args.type)
                elseif available == 2 then
                    element.text = string.format("You have two %ss available", args.type)
                else
                    element.text = string.format("You have %d %ss available", available, args.type)
                end
                --]]
            end

            --m_usedAbilityIcon:SetClass("hidden", hideAbilityIcon)
        end,

        gui.Panel {
            classes = { "drawerTopPanel", "collapsed" },
            gui.Panel {
                classes = { "drawerIconPanel", "collapsed" },
                m_usedAbilityIcon,
                swallowPress = true,
                press = function(element)
                    if m_resourceid ~= nil then
                        local usage = g_creature:GetResourceUsage(m_resourceid, m_resourceInfo.usageLimit)
                        local available = (g_resources[m_resourceid] or 0) - usage

                        local target = available - 1
                        if target < 0 then
                            target = g_resources[m_resourceid]
                        end

                        local diff = target - available
                        if diff == 0 then
                            return
                        end

                        g_token:ModifyProperties {
                            description = "Manually Update Resource",
                            execute = function()
                                if diff > 0 then
                                    g_token.properties:RefreshResource(m_resourceid, m_resourceInfo.usageLimit, diff)
                                else
                                    g_token.properties:ConsumeResource(m_resourceid, m_resourceInfo.usageLimit, -diff)
                                end
                            end,
                        }
                    end
                end,
            },

        },

        m_glow,

        m_diamond,
        m_diamondAccent,

        gui.Label {
            classes = { "drawerTitle" },
            text = args.name,
        },

        m_moveBar,

        cond(args.type ~= "malice", m_rightInfoText),

        m_costDiamond,


    }

    if args.panel ~= nil then
        for key, value in pairs(args.panel) do
            resultPanelArgs[key] = value
        end
    end

    resultPanel = gui.Panel(resultPanelArgs)

    resultPanel:SetClassTree("available", true)

    return resultPanel
end

local g_triggerReactionPanel

function UpdateTriggerReactionPanel(options)
    if g_triggerReactionPanel == nil or not g_triggerReactionPanel.valid then
        return
    end

    g_triggerReactionPanel:FireEventTree("refreshTriggerReactions", options)
end

local function CreateTriggerReactionPanel()
    local m_stateBaseline = nil
    local m_state = nil
    return gui.Panel{
        classes = {"collapsed"},
        halign = "center",
        valign = "bottom",
        flow = "vertical",
        height = 96,
        width = 400,
        y = -16,
        refreshTriggerReactions = function(element, options)
            m_state = options
            if options == nil then
                element:SetClass("collapsed", true)
                element.thinkTime = nil
                return
            end

            m_stateBaseline = dmhub.Time()
            element:SetClass("collapsed", false)
            element.thinkTime = 0.01
            element:FireEvent("think")
        end,
        think = function(element)
            local time = dmhub.Time()
            local elapsed = time - m_stateBaseline
            local r = ((m_state.current + elapsed) - m_state.start)/(m_state.expire - m_state.start)
            if m_state.paused then
                r = 0
            end

            if r >= 1 then
                m_state = nil
                element:SetClass("collapsed", true)
                return
            end
            element:FireEventTree("progress", 1 - r)
        end,
        gui.ProgressDice{
            width = 92,
            height = 92,
            halign = "center",
            thinkTime = 0.01,
            press = function(element)
                if m_state ~= nil then
                    m_state.callback()
                end
            end,
        },
        gui.Label{
            tmargin = 4,
            fontSize = 16,
            width = "100%",
            height = 18,
            textAlignment = "center",
            bgimage = true,
            bgcolor = "black",
            opacity = 0.7,
            refreshTriggerReactions = function(element, options)
                if options == nil then
                    element.text = ""
                    return
                end

                element.text = options.text
            end,
        }
    }
end


local function CreateActionBar()
    local resultPanel

    local m_triggerPanel = ActionBarDrawer { name = "Trigger", type = "trigger" }
    local m_actionPanel = ActionBarDrawer { name = "Main Action", type = "action" }
    local m_maneuverPanel = ActionBarDrawer { name = "Maneuver", type = "maneuver" }
    local m_movementPanel = ActionBarDrawer { name = "Move", type = "move" }
    local m_freeActionsPanel = nil --[[ActionBarDrawer { name = "Free Action", type = "free", panel = {
        floating = true,
        halign = "left",
        valign = "bottom",
        y = -70,
        lmargin = 19,
    } }]]

    local m_malicePanel


    if dmhub.isDM then
        m_malicePanel = ActionBarDrawer { name = "Malice", type = "malice", panel = {
        } }
    end

    local m_actionMenu = ActionMenu()

    g_abilityController = CreateAbilityController()

    g_triggerPanel = mod.shared.CreateTriggerPanel()

    --make the permanent triggers panel appear above the drawer.

    local m_triggerDrawerContainer = gui.Panel {
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",

        g_triggerPanel,
        m_triggerPanel,
    }

    resultPanel = gui.Panel {
        classes = { "actionBar" },
        styles = Styles.ActionBar,
        width = "100%",
        height = 50,
        halign = "center",
        valign = "bottom",
        flow = "horizontal",
        bmargin = 8,

        refresh = function(element)
            if #g_casterTokenStack == 0 then
                g_token = dmhub.selectedOrPrimaryTokens[1]
            end

            if g_token == nil or not g_token.valid then
                g_abilities = {}
                g_prevCharid = nil
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FireEventTree("closemenu")
                return
            end

            g_creature = g_token.properties

            element:SetClass("hidden", false)

            if g_prevCharid ~= g_token.charid then
                g_prevCharid = g_token.charid
                element:FireEventTree("closemenu")
            end

            g_resources = g_token.properties:GetResources()
            g_abilities = g_token.properties:GetActivatedAbilities { bindCaster = true, manualTriggers = true }

            --break out melee and ranged.
            local abilities = {}
            for _, ability in ipairs(g_abilities) do
                if ability.meleeAndRanged then
                    abilities[#abilities + 1] = ability.meleeVariation
                    abilities[#abilities + 1] = ability.rangedVariation
                else
                    abilities[#abilities + 1] = ability
                end
            end

            g_abilities = abilities

            g_initiative = dmhub.initiativeQueue
            if g_initiative ~= nil and g_initiative.hidden then
                g_initiative = nil
            end
        end,

        gui.Panel {
            floating = true,
            width = "100%",
            height = "100%+8",
            valign = "top",
            bgimage = true,
            --bgcolor = Styles.Ability.blurColor,
            --blurBackground = true,

            bgcolor = "white",
            gradient = Styles.Ability.gradientBar,



        },

        m_triggerDrawerContainer,
        m_actionPanel,
        m_maneuverPanel,
        m_movementPanel,
        m_freeActionsPanel,
        m_malicePanel,

        m_actionMenu,

        g_abilityController,
    }

    g_actionBar = resultPanel

    resultPanel:FireEventTree("refresh")

    g_triggerReactionPanel = CreateTriggerReactionPanel()

    local m_containerPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "bottom",
        g_triggerReactionPanel,
        resultPanel,
    }

    return m_containerPanel
end

local function AbilityHeading(args)
    local args = args or {}

    local m_ability = nil
    local m_cannotAfford = false
    local m_expended = false

    local resultPanel

    local SetCannotAfford = function(cannotAffordResourceCost, expended)
        if cannotAffordResourceCost ~= m_cannotAfford then
            m_cannotAfford = cannotAffordResourceCost
            resultPanel:SetClassTree("cannotAfford", m_cannotAfford)
        end

        if expended ~= m_expended then
            m_expended = expended
            resultPanel:SetClassTree("expended", m_expended)
        end
    end

    --we only show an ability from here if we aren't parented by an action menu.
    local m_showingAbility = false

    resultPanel = gui.Panel {
        classes = { "abilityHeading" },

        ability = function(element, ability)
            local suppressMessage = ability:try_get("suppressExplanation") or
                ability:AbilityFilterFailureMessage(g_token.properties)
            element:SetClassTree("suppressed", suppressMessage ~= nil)
        end,

        rightClick = function(element)
            local entries = {}
            entries[#entries + 1] = {
                text = 'Share to Chat',
                click = function()
                    element.popup = nil
                    chat.ShareObjectInfo(nil, nil, { charid = g_token.charid, ability = m_ability })
                end,
            }

            if m_ability:has_key("sourceReference") then
                if m_ability.sourceReference:url() ~= nil then
                    entries[#entries + 1] = {
                        text = 'View Source',
                        click = function()
                            element.popup = nil
                            dmhub.OpenDocument(m_ability.sourceReference:url())
                        end,
                    }
                end
            end

            if dmhub.isDM then
                for domain, _ in pairs(m_ability.domains or {}) do
                            if domain ~= "_luaTable" then
                                --parse domain information
                                local tableType, guid = string.match(domain, "^([^:]+):(.+)$")
                                if tableType and guid then
                                    -- Find the parent object (class/feat/etc) that contains this ability
                                    local obj, tableid = FindAbilityParentByGuid(guid)
                                    if obj and tableid then
                                        local path = {}
                                        --Find the path to the ability within the parent object
                                        local found = FindObjectPathByGuid(m_ability.guid, obj, path)
                                        --if a path is found create an edit option
                                        if found then
                                            entries[#entries + 1] = {
                                                text = 'Edit Ability',
                                                click = function()
                                                    element.popup = nil

                                                    element.root:AddChild(m_ability:ShowEditActivatedAbilityDialog{
                                                        close = function()
                                                            --Use found path to locate ability in parent object
                                                            SetObjectAtPath(obj, path, m_ability)
                        
                                                            -- Upload the parent object
                                                            dmhub.SetAndUploadTableItem(tableid, obj)
                                                        end
                                                    })
                                                end,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                        
                        --[[ element.root:AddChild(m_ability:ShowEditActivatedAbilityDialog{
                            close = function()
                                print("Ability Info::", g_token.properties:IsActivatedAbilityInnate(m_ability))
                                for _, ability in ipairs(g_token.properties.innateActivatedAbilities or {}) do
                                    
                                end
                                g_token:ModifyProperties {
                                    description = "Update Ability",
                                    execute = function()
                                        -- This is a bit hacky, but we need to trigger a properties update so that any changes to the ability are reflected in the UI.
                                        local props = g_token.properties
                                        g_token.properties = nil
                                        g_token.properties = props
                                    end,
                                }
                            end
                        })
                    end
                } ]]
            end

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        hover = function(element)
            if dmhub.modKeys['ctrl'] then
                --do not show ability if ctrl is held.
                return
            end
            local menu = element:FindParentWithClass("actionMenu")
            if menu ~= nil then
                menu:FireEvent("showability", m_ability)
            else
                m_showingAbility = CharacterPanel.DisplayAbility(g_token, m_ability)
            end
        end,

        dehover = function(element)
            if m_showingAbility then
                CharacterPanel.HideAbility(m_ability)
            end
        end,

        press = function(element)
            audio.FireSoundEvent("Mouse.Click")
            --this will be adopted by the ability controller
            assert(g_abilityController ~= nil)
            local menu = element:FindParentWithClass("actionMenu")
            if menu ~= nil then
                menu:FireEvent("oncast")
            elseif m_showingAbility then
                element:FireEvent("dehover")
            end

            if m_ability == nil then
                return
            end

            if args.instantCast then
                m_ability = m_ability:MakeTemporaryClone()
                m_ability.castImmediately = true
            end

            CharacterPanel.HighlightAbilitySection{
                ability = m_ability,
                section = "target",
            }

            g_abilityController:FireEventTree("beginCasting", m_ability, { targets = args.targets, cast = args.cast, fromui = true })
        end,

        gui.Label {
            classes = { "abilityIconPanel" },
            ability = function(element, ability)
                m_ability = ability

                if ability:try_get("manualVersionOfTrigger") or ability.categorization == "Trigger" then
                    element.text = "!"
                    element.bgimage = "panels/square.png"
                    element.selfStyle.gradient = cond(ability.actionResourceId == CharacterResource.triggerResourceId,
                        mod.shared.triggerGradient, mod.shared.freeTriggerGradient)
                    element.selfStyle.gradientMapping = false
                    element.selfStyle.bgcolor = "white"
                    element.selfStyle.hueshift = 0
                    element.selfStyle.saturation = 1
                    element.selfStyle.brightness = 1
                else
                    element.text = ""
                    element.bgimage = ability.iconid
                    element.selfStyle = ability.display
                    element.selfStyle.gradient = DisplayGradients.GetGradient(rawget(ability, "iconGradient"))
                    element.selfStyle.gradientMapping = true
                end
            end,
        },

        gui.Panel {
            classes = { "costDiamond", "collapsed" },
            floating = true,
            rotate = 135,
            gui.Panel {
                --vback
                classes = { "costInnerDiamond" },
                gui.Label {
                    classes = { "abilityCostLabel" },
                    rotate = -135,


                    ability = function(element, ability)
                        local resource = ability:ActionResource()
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element.parent.parent:SetClass("collapsed", true)
                            SetCannotAfford(false, false)
                            return
                        end

                        element.parent.parent:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                    end,
                },
            },
        },


        gui.Panel {
            classes = { "abilityInfoPanel" },

            gui.Label {
                classes = { "abilityTitle" },
                text = "Ability Name",
                ability = function(element, ability)
                    local text = ability.name
                    --rely on keywords to show melee/ranged.
                    --if ability:try_get("isMeleeVariation") then
                    --    text = text .. " <size=8>(Melee)"
                    --elseif ability:try_get("isRangedVariation") then
                    --    text = text .. " <size=8>(Ranged)"
                    --end
                    element.text = text
                end,
            },


            --[[
            gui.Panel {
                classes = { "abilityTitleArea" },

                gui.Label {
                    classes = { "abilityCostLabel" },
                    text = "",

                    ability = function(element, ability)
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element:SetClass("collapsed", true)
                            SetCannotAfford(false)
                            return
                        end

                        element:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                    end,

                },
            },
--]]
            gui.Label {
                classes = { "abilityInfoLabel" },
                text = "Ability Info",
                ability = function(element, ability)
                    local costInfo = ability:GetCost(g_token)

                    --look for heroic resource or malice cost and see if we can afford it.
                    local cannotAfford = false
                    for _, entry in ipairs(costInfo.details or {}) do
                        if entry.cost == CharacterResource.heroicResourceId or entry.cost == CharacterResource.maliceResourceId then
                            cannotAfford = not entry.canAfford
                            break
                        end
                    end

                    SetCannotAfford(cannotAfford, not costInfo.canAfford)
                    for _, entry in ipairs(costInfo.details) do
                        if entry.description ~= nil and (not entry.canAfford) then
                            --this means there is an 'anonymous' cost, e.g. number of times they can use per round.
                            if entry.refreshType == "long" then
                                element.text = "Already used since respite"
                            else
                                element.text = string.format("Already used this %s", entry.refreshType)
                            end
                            return
                        end
                    end

                    if ability.categorization == "Villain Action" then
                        element.text = ability:try_get("villainAction")
                        return
                    end

                    local keywords = table.keys(ability.keywords)
                    table.sort(keywords)
                    element.text = string.join(keywords, ", ")
                end,
            },
        },
    }

    if args.ability ~= nil then
        resultPanel:FireEventTree("ability", args.ability)
    end

    return resultPanel
end

local function TriggerPreviewPanel()
    local m_trigger = nil
    local resultPanel

    resultPanel = gui.Panel{
        classes = {"abilityHeading", "nonselectable"},
        hover = function(element)
            if m_trigger ~= nil then
                CharacterPanel.DisplayAbility(g_token, m_trigger, {})
            end
        end,
        dehover = function(element)
            if m_trigger ~= nil then
                CharacterPanel.HideAbility(m_trigger)
            end
        end,

        rightClick = function(element)
            local entries = {}
            entries[#entries + 1] = {
                text = 'Share to Chat',
                click = function()
                    element.popup = nil
                    chat.ShareObjectInfo(nil, nil, { charid = g_token.charid, ability = m_trigger })
                end,
            }

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        gui.Label{
            classes = {"abilityIconPanel"},
            trigger = function(element, trigger)
                m_trigger = trigger
                element.selfStyle.gradient = cond(trigger.type ~= "free",
                    mod.shared.triggerGradient, mod.shared.freeTriggerGradient)
            end,

            text = "!",
            bgimage = "panels/square.png",
            bgcolor = "white",
            hueshift = 0,
            saturation = 1,
            brightness = 1,
        },
        gui.Panel{
            classes = {"abilityInfoPanel"},
            gui.Label{
                classes = {"abilityTitle", "expended"},
                hmargin = 6,
                vmargin = 0,
                tmargin = 0,
                trigger = function(element, trigger)
                    element.text = trigger.name
                end,
            },
            gui.Label{
                classes = {"abilityInfoLabel", "expended"},
                hmargin = 6,
                vmargin = 0,
                tmargin = 0,
                trigger = function(element, trigger)
                    if trigger.type == "free" then
                        element.text = "Free Triggered Action"
                    else
                        element.text = "Triggered Action"
                    end
                end,
            },
        }
    }

    return resultPanel
end

local function PowerRollTriggersSubmenu(args)
    local m_children = {
        gui.Label {
            classes = { "submenuHeading" },
            text = "All Triggers",
        }
    }

    local resultPanel

    resultPanel = gui.Panel {
        vpad = -4,

        classes = { "abilitySubMenu" },
        floating = true,
        halign = "right",
        hmargin = -200,
        blurBackground = true,
        triggers = function(element, triggers)
            if #triggers == 0 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            local heading = m_children[#m_children]
            m_children[#m_children] = nil

            table.sort(triggers, function(a, b)
                return (a.type .. a.name) < (b.type .. b.name)
            end)

            for i,trigger in ipairs(triggers) do
                m_children[i] = m_children[i] or TriggerPreviewPanel()
                m_children[i]:FireEventTree("trigger", trigger)
                m_children[i]:SetClass("collapsed", false)
            end

            for i = #triggers + 1, #m_children do
                m_children[i]:SetClass("collapsed", true)
            end

            m_children[#m_children+1] = heading
            element.children = m_children
        end,

        children = m_children,
    }

    return resultPanel
end

local function ActionSubMenu(args)
    local m_children = {
        gui.Label {
            classes = { "submenuHeading" },
            abilities = function(element, abilities, grouping)
                if g_token.properties.typeName == "monster" and grouping == "Heroic Abilities" then
                    grouping = "Villain Actions"
                elseif grouping == "Triggers" then
                    grouping = "Manual Use Triggers"
                end
                element.text = grouping
            end,
        }
    }

    local resultPanel

    resultPanel = gui.Panel {

        vpad = -4,

        classes = { "abilitySubMenu" },
        blurBackground = true,
        abilities = function(element, abilities)
            if abilities == nil or #abilities == 0 then
                element:SetClass("collapsed", true)
                element:HaltEventPropagation()
                return
            end

            element:SetClass("collapsed", false)

            if abilities[1].categorization == "Malice" then
                table.sort(abilities, function(a, b)
                    return (GetHeroicResourceOrMaliceCost(a) or 0) < (GetHeroicResourceOrMaliceCost(b) or 0)
                end)
            elseif abilities[1].categorization == "Villain Action" then
                table.sort(abilities, function(a,b) return a:try_get("villainAction","") < b:try_get("villainAction","") end)
            else
                table.sort(abilities, function(a, b)
                    return a.name < b.name
                end)
            end

            local startChildCount = #m_children

            local heading = m_children[#m_children]
            m_children[#m_children] = nil

            for i = 1, #abilities do
                m_children[i] = m_children[i] or AbilityHeading()
                m_children[i]:FireEventTree("ability", abilities[i])
                m_children[i]:SetClass("collapsed", false)
            end

            for i = #abilities + 1, #m_children do
                m_children[i]:SetClass("collapsed", true)
            end

            m_children[#m_children + 1] = heading

            if #m_children ~= startChildCount then
                element.children = m_children
            end
        end,
    }

    return resultPanel
end



local g_categorizationMapping = {
    ["Basic Attack"] = "Skill",
}

ActionMenu = function()
    local m_submenus = {}
    local m_args
    local resultPanel
    local m_showingAbility = false

    local g_manualSetResourcePanel = gui.Label {
        classes = { "abilityHeading" },
        width = 205,
        height = 20,
        tmargin = 12,
        text = "Set Trigger",
        textAlignment = "center",
        fontSize = 14,
        bold = true,

        press = function(element)
            g_token:ModifyProperties {
                description = "Manually Set Trigger Resource",
                execute = function()
                    local resources = g_token.properties:GetResources()[CharacterResource.triggerResourceId] or 0
                    local resourcesAvailable = resources -
                        g_token.properties:GetResourceUsage(CharacterResource.triggerResourceId, "round")
                    if resourcesAvailable > 0 then
                        g_token.properties:ConsumeResource(CharacterResource.triggerResourceId, "round", 1)
                    else
                        g_token.properties:RefreshResource(CharacterResource.triggerResourceId, "round", 1)
                    end
                end,
            }
        end,
    }

    local m_containerPanel = gui.Panel {
        width = "auto",
        height = "auto",
        minHeight = 200,
        maxHeight = 900,
        flow = "horizontal",
    }


    resultPanel = gui.Panel {
        styles = Styles.ActionMenu,
        classes = { "actionMenu", "hidden" },
        floating = true,
        flow = "vertical",
        width = "auto",
        height = "auto",
        --wrap = true,
        halign = "center",
        valign = "bottom",
        y = -50,
        bgimage = true,
        bgcolor = "clear",

        g_manualSetResourcePanel,

        showability = function(element, ability)
            element:FireEvent("dehover")
            local result = CharacterPanel.DisplayAbility(g_token, ability)
            if result then
                m_showingAbility = ability
            end
        end,

        hideability = function(element, ability)
            if m_showingAbility == ability then
                CharacterPanel.HideAbility(m_showingAbility)
                m_showingAbility = false
            end
        end,

        oncast = function(element)
            m_showingAbility = false
        end,

        hover = function(element)
        end,

        dehover = function(element)
            if m_showingAbility then
                CharacterPanel.HideAbility(m_showingAbility)
                m_showingAbility = false
            end
        end,

        destroy = function(element)
            element:FireEvent("dehover")
        end,

        closemenu = function(element)
            g_triggerPanel:SetClass("hidden", false)
        end,

        menu = function(element, args)
            if element.data.shownMenuTime == dmhub.Time() or g_token == nil then
                return
            end

            if args.type ~= "trigger" then
                g_manualSetResourcePanel:SetClass("collapsed", true)
            else
                g_manualSetResourcePanel:SetClass("collapsed", false)

                local resources = g_token.properties:GetResources()[CharacterResource.triggerResourceId] or 0
                local resourcesAvailable = resources -
                    g_token.properties:GetResourceUsage(CharacterResource.triggerResourceId, "round")
                if resourcesAvailable > 0 then
                    g_manualSetResourcePanel.text = "Mark Trigger as Used"
                else
                    g_manualSetResourcePanel.text = "Mark Trigger as Unused"
                end
            end

            element.data.shownMenuTime = dmhub.Time()

            if (not element:HasClass("hidden")) and m_args ~= nil and m_args.drawer == args.drawer then
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FindParentWithClass("actionBar"):FireEventTree("menuStatus")
                g_triggerPanel:SetClass("hidden", false)
                return
            end

            g_triggerPanel:SetClass("hidden", true)

            g_abilityController:FireEvent("cancelCasting")

            --parent to the drawer firing us.
            element:Unparent()
            args.drawer:AddChild(element)

            m_args = args
            local abilities = {}
            if args.type == "malice" then
                for _, ability in ipairs(g_abilities) do
                    if ability.categorization == "Malice" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "free" then
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == "none" and ability.categorization ~= "Malice" and ability.categorization ~= "Move" and ability.categorization ~= "Hidden" and ability.categorization ~= "Trigger" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "move" then
                for _, ability in ipairs(g_abilities) do
                    if ability.actionResourceId == "none" and ability.categorization == "Move" then
                        abilities[#abilities + 1] = ability
                    end
                end
            elseif args.type == "trigger" then
                for _, ability in ipairs(g_abilities) do
                    if ability.categorization == "Trigger" or ability.categorization == "Villain Action" then
                        abilities[#abilities + 1] = ability
                    end
                end
            else
                for _, ability in ipairs(g_abilities) do
                    if (ability.actionResourceId == args.resourceid or (args.type == "maneuver" and (ability.actionResourceId == "none" or ability.actionResourceId == CharacterResource.respiteActivityId or ability.actionResourceId == CharacterResource.freeManeuverResourceId) and ability.categorization ~= "Malice" and ability.categorization ~= "Move" and ability.categorization ~= "Trigger")) and ability.categorization ~= "Hidden" then
                        abilities[#abilities + 1] = ability
                    end
                end
            end

            local triggers = {}
            if args.type == "trigger" then
                triggers = g_token.properties:GetTriggeredActions()
            end

            if #abilities == 0 and #triggers == 0 then
                element:SetClass("hidden", true)
                element:HaltEventPropagation()
                element:FindParentWithClass("actionBar"):FireEventTree("menuStatus")
                return
            end

            element:SetClass("hidden", false)

            local abilitiesByGrouping = {}

            for _, ability in ipairs(abilities) do
                local grouping = GameSystem.GetAbilityCategoryInfo(ability.categorization).grouping or "Common Abilities"
                if grouping == "Common Abilities" and ability.actionResourceId == CharacterResource.freeManeuverResourceId then
                    grouping = "Free Maneuvers"
                end
                if grouping == "Common Abilities" and ability.actionResourceId == "none" then
                    grouping = "No Action Required"
                end
                if ability.actionResourceId == CharacterResource.respiteActivityId then
                    grouping = "Respite Activities"
                end
                abilitiesByGrouping[grouping] = abilitiesByGrouping[grouping] or {}
                abilitiesByGrouping[grouping][#abilitiesByGrouping[grouping] + 1] = ability
            end

            for catid, abilities in pairs(abilitiesByGrouping) do
                m_submenus[catid] = m_submenus[catid] or ActionSubMenu {}
            end

            local children = {}
            for grouping, submenu in pairs(m_submenus) do
                submenu:FireEventTree("abilities", abilitiesByGrouping[grouping], grouping)
                submenu.data.ord = GameSystem.ActionBarGroupings[grouping] or 1000
                children[#children + 1] = submenu
            end

            table.sort(children, function(a, b)
                return a.data.ord < b.data.ord
            end)

            if element.data.triggerPanel == nil then
                element.data.triggerPanel = PowerRollTriggersSubmenu()
            end
            children[#children+1] = element.data.triggerPanel

            if args.type == "trigger" then
                element.data.triggerPanel:FireEventTree("triggers", triggers)
            else
                element.data.triggerPanel:SetClass("collapsed", true)
            end

            m_containerPanel.children = children

            element:FindParentWithClass("actionBar"):FireEventTree("menuStatus", args)

            if g_token.properties:IsMonster() then
                element:SetClassTree("malice", true)
            else
                element:SetClassTree("malice", false)
            end
        end,

        m_containerPanel,
        g_manualSetResourcePanel,
    }

    return resultPanel
end

local m_targetLineOfSightRays = {}

local function FreeTargetLineOfSightRays()
    for key, ray in pairs(m_targetLineOfSightRays) do
        ray:DestroyLineOfSight()
    end

    m_targetLineOfSightRays = {}
end

local function SetTargetLineOfSightRayForKey(key, ray)
    if m_targetLineOfSightRays[key] ~= nil then
        m_targetLineOfSightRays[key]:DestroyLineOfSight()
    end

    m_targetLineOfSightRays[key] = ray
end

---@param rays table<{a: Token, b: Token}>[]
local function ReplaceTargetLineOfSightRays(rays)
    local t = {}
    for i, ray in ipairs(rays) do
        local key = string.format("%s-%s", ray.a.id, ray.b.id)
        t[key] = m_targetLineOfSightRays[key] or dmhub.MarkLineOfSight(ray.a, ray.b)
        m_targetLineOfSightRays[key] = nil
    end

    FreeTargetLineOfSightRays()
    m_targetLineOfSightRays = t
end

local function RemoveLineOfSightRaysTargetingToken(tokenid)
    local destroyKeys = {}
    for key, ray in pairs(m_targetLineOfSightRays) do
        if string.ends_with(key, tokenid) then
            ray:DestroyLineOfSight()
            destroyKeys[#destroyKeys + 1] = key
        end
    end

    for _, key in ipairs(destroyKeys) do
        m_targetLineOfSightRays[key] = nil
    end
end

--objects to mark line of sight.

--- @type nil|LuaTargetingMarkers
local m_markLineOfSight = nil

--- @type nil|CharacterToken
local m_markLineOfSightSourceToken = nil

--- @type nil|CharacterToken
local m_markLineOfSightToken = nil

--if m_markLineOfSight is set, it will be adopted as a persistent marking.
local function AdoptLineOfSightMark()
    if m_markLineOfSight == nil then
        return
    end
    SetTargetLineOfSightRayForKey(string.format("%s-%s", m_markLineOfSightSourceToken.id, m_markLineOfSightToken.id),
        m_markLineOfSight)
    m_markLineOfSight = nil
    m_markLineOfSightToken = nil
    m_markLineOfSightSourceToken = nil
end

local function ClearLineOfSightMark()
    if m_markLineOfSight == nil then
        return
    end

    m_markLineOfSight:Destroy()
    m_markLineOfSight = nil
    m_markLineOfSightToken = nil
    m_markLineOfSightSourceToken = nil
end

-- Casting Triggers.
local m_castingTriggersCache = nil
local m_castingTriggers = nil
local m_castingTriggersOwnerPanel = nil

local ClearCastingTriggers = function()
    if m_castingTriggersOwnerPanel ~= nil and m_castingTriggersOwnerPanel.valid then
        m_castingTriggersOwnerPanel:FireEvent("clearCastingTriggers")
    end
    if m_castingTriggers == nil then
        return
    end

    for _, trigger in ipairs(m_castingTriggers) do
        local controllingToken = dmhub.GetTokenById(trigger.charid)
        if controllingToken ~= nil then
            controllingToken:ModifyProperties {
                description = "Clear casting trigger",
                undoable = false,
                execute = function()
                    controllingToken.properties:ClearAvailableTrigger(trigger)
                end,
            }
        end
    end

    m_castingTriggers = nil
end




local function CreateTargetInfo(spell)
    local targetInfo = {
        type = string.lower(spell.typeName),
        guid = dmhub.GenerateGuid(),
        action = spell,
        execute = function(targetToken, info) --info has {targetEffects = {list of effect panels}}
            local exists = list_contains(g_targetsChosen, targetToken.id)

            for i, effect in ipairs(info.targetEffect) do
                effect:SetClass('target-selected', true)
                effect:SetClass('two', false)
                effect:SetClass('three', false)
            end
            if not exists then
                g_targetsChosen[#g_targetsChosen + 1] = targetToken.id
                if g_firstTarget == nil then
                    g_firstTarget = targetToken.id
                end

                AdoptLineOfSightMark()
            else
                if spell:CanTargetAdditionalTimes(g_token, g_currentSymbols, g_targetsChosen, targetToken) then
                    g_targetsChosen[#g_targetsChosen + 1] = targetToken.id
                    local ntargets = 0
                    for _, tokenid in ipairs(g_targetsChosen) do
                        if tokenid == targetToken.id then
                            ntargets = ntargets + 1
                        end
                    end

                    for i, effect in ipairs(info.targetEffect) do
                        effect:SetClass('two', ntargets >= 2)
                        effect:SetClass('three', ntargets >= 3)
                    end
                else
                    RemoveLineOfSightRaysTargetingToken(targetToken.id)
                    local newTargetsChosen = {}
                    for _, tokenid in ipairs(g_targetsChosen) do
                        if tokenid ~= targetToken.id then
                            newTargetsChosen[#newTargetsChosen + 1] = tokenid
                        end
                    end
                    g_targetsChosen = newTargetsChosen

                    if g_firstTarget == targetToken.id then
                        g_firstTarget = g_targetsChosen[1]
                    end
                    for i, effect in ipairs(info.targetEffect) do
                        effect:SetClass('target-selected', false)
                    end
                end
            end

            CalculateSpellTargeting()
        end,
    }

    return targetInfo
end

--functionality to mark radiuses.
local g_radiusMarkers = {}

local AddCustomAreaMarker = function(locs, color)
    g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs {
        locs = locs,
        color = color,
    }
end

local AddRadiusMarker = function(locOverride, radius, color, filterFunction)
    local tokenCasting = g_token
    if g_currentAbility ~= nil then
        tokenCasting = g_currentAbility:GetRangeSource(g_token)
    end


    local locs = tokenCasting.locsOccupying

    if locOverride ~= nil then
        if type(locOverride) == "table" then
            locs = locOverride
        else
            locs = { locOverride }
        end
    end


    local shape = dmhub.CalculateShape {
        shape = "radiusfromcreature",
        token = tokenCasting,
        radius = radius,
        locOverride = locs,
    }

    local locs = shape.locations
    if filterFunction ~= nil then
        local newLocs = {}
        for _, loc in ipairs(locs) do
            if filterFunction(loc) then
                newLocs[#newLocs + 1] = loc
            end
        end

        locs = newLocs
    end

    g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs {
        locs = locs,
        color = color,
    }
end

local function ClearRadiusMarkers()
    for i, marker in ipairs(g_radiusMarkers) do
        marker:Destroy()
    end

    g_radiusMarkers = {}
end


local g_currentCostProposal = nil

local g_targetInfo = nil

local function RemoveTokenTargeting()
    if g_targetInfo == nil then
        return
    end

    for _, token in ipairs(dmhub.allTokensIncludingObjects) do
        if token.valid and token.sheet ~= nil and token.sheet.data.targetInfo == g_targetInfo then
            token.sheet:FireEvent("untarget")
            token.sheet.data.targetInfo = nil
        end
    end

    g_targetInfo = nil
end


local g_castingEmoteSet = nil

local g_castButton
local g_skipButton
local g_castMessage
local g_castMessageContainer
local g_tokenSelectionContainer

local g_castModesPanel
local g_forcedMovementTypePanel


--- @type nil|function
local m_allowedAltitudeCalculator

local m_altitudeController
local m_shiftController

local g_ammoChoicePanel = nil
local g_synthesizedSpellsPanel = nil
local g_castChargesInput = nil

local g_shifting = true

local function CreateShiftController()
    local resultPanel
    local slider = gui.EnumeratedSliderControl {
        halign = "center",
        width = 180,
        vmargin = 2,
        options = {
            { id = true,  text = "Shifting" },
            { id = false, text = "Not Shifting" },
        },
        value = g_shifting,
        beginCasting = function(element)
            element.value = true
        end,
        change = function(element)
            g_shifting = element.value
            g_currentSymbols.shiftingOverride = g_shifting
            CalculateSpellTargeting()
        end,
    }

    resultPanel = gui.Panel {
        halign = "center",
        width = "auto",
        height = "auto",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = Styles.Ability.blurColor,
        blurBackground = true,
        pad = 4,

        gui.Label {
            fontSize = 14,
            width = "auto",
            height = "auto",
            text = "You are shifting. You can choose to move normally instead.",
            vmargin = 2,
        },
        slider,
    }
    return resultPanel
end

local function CreateAltitudeController()
    local resultPanel
    resultPanel = gui.Panel {
        classes = { "collapsed" },
        styles = {
            {
                selectors = { "altitudeArrow" },
                bgcolor = "#999999",
                bgimage = "panels/InventoryArrow.png",
            },
            {
                selectors = { "altitudeArrow", "parent:hover" },
                bgcolor = "white",
            },
        },
        data = {
            target = "max",
            currentLocInfo = {},
        },
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = true,
        bgcolor = "black",
        opacity = 0.9,
        pad = 4,

        enable = function(element)
            element.thinkTime = 0.01
        end,

        disable = function(element)
            element.thinkTime = nil
        end,

        think = function(element)
            if dmhub.modKeys["alt"] then
                local wheel = dmhub.mouseWheel

                if wheel ~= 0 then
                    local alt = element.data.target
                    if type(alt) ~= "number" then
                        alt = 0
                    end

                    if wheel > 0 then
                        alt = alt + 1
                    else
                        alt = alt - 1
                    end

                    if element.data.currentLocInfo.loc ~= nil then
                        assert(m_allowedAltitudeCalculator ~= nil, "Allowed altitude calculator is not set.")
                        local minAltitude, maxAltitude = m_allowedAltitudeCalculator(element.data.currentLocInfo.loc)
                        alt = math.clamp(alt, minAltitude, maxAltitude)
                    end

                    m_altitudeController:FireEventTree("setAltitude", alt)
                end

                if element.data.currentLocInfo.loc ~= nil and element.data.currentLocInfo.panel.valid then
                    --update the altitude.
                    element.data.currentLocInfo.panel:FireEvent("maphover", element.data.currentLocInfo.loc,
                        element.data.currentLocInfo.point)
                end
            end
        end,

        loc = function(element, info)
            element.data.currentLocInfo = info
        end,

        setAltitude = function(element, val)
            element.data.target = val
        end,

        gui.Label {
            width = "auto",
            height = "auto",
            color = Styles.textColor,
            hmargin = 4,
            text = "Vertical:",
            fontSize = 18,
        },
        gui.Label {
            width = 80,
            height = 20,
            fontSize = 14,
            valign = "center",
            textAlignment = "center",
            bold = true,
            color = Styles.textColor,
            text = "max",
            setAltitude = function(element, val)
                element.text = val
            end,
            loc = function(element, info)
                if info.loc == nil then
                    return
                end
                assert(m_allowedAltitudeCalculator ~= nil, "Allowed altitude calculator is not set.")
                local minAltitude, maxAltitude = m_allowedAltitudeCalculator(info.loc)
                local target = m_altitudeController.data.target
                local alt = info.loc.altitude
                if target == "max" then
                    alt = maxAltitude
                    element.text = string.format("max (%d)", alt)
                elseif target == "min" then
                    alt = minAltitude
                    element.text = string.format("min (%d)", alt)
                elseif type(target) == "number" then
                    alt = math.clamp(target, minAltitude, maxAltitude)
                    if alt == target then
                        element.text = string.format("%d", alt)
                    else
                        element.text = string.format("%d (%d)", alt, target)
                    end
                end

                info.loc = info.loc:WithAltitude(alt)
            end,
        },

        --up/down container
        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",

            --up button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,
                press = function(element)
                    local alt = m_altitudeController.data.target
                    if type(alt) ~= "number" then
                        alt = 0
                    end
                    m_altitudeController:FireEventTree("setAltitude", alt + 1)
                end,
                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = -90,
                },
            },

            --down button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,

                press = function(element)
                    local alt = m_altitudeController.data.target
                    if type(alt) ~= "number" then
                        alt = 0
                    end
                    m_altitudeController:FireEventTree("setAltitude", alt - 1)
                end,

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = 90,
                },
            },
        },

        --max/min container.
        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",

            --max button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,

                press = function(element)
                    m_altitudeController:FireEventTree("setAltitude",
                        cond(m_altitudeController.data.target == "max", 0, "max"))
                end,

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = -90,
                    y = -4,
                },

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = -90,
                },
            },

            --min button.
            gui.Panel {
                bgimage = true,
                bgcolor = "clear",
                width = 20,
                height = 10,

                press = function(element)
                    m_altitudeController:FireEventTree("setAltitude",
                        cond(m_altitudeController.data.target == "min", 0, "min"))
                end,

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = 90,
                    y = 4,
                },

                gui.Panel {
                    classes = { "altitudeArrow" },
                    interactable = false,
                    halign = "center",
                    valign = "center",
                    width = 10,
                    height = 20,
                    rotate = 90,
                },
            },

        },


    }

    return resultPanel
end

---@return table<{loc: table, token: Token}>[]
local function BuildTargetsList()
    --accumulate our target list based on what is selected.
    local targets = {}

    for _, tokenid in ipairs(g_targetsChosen) do
        local token = dmhub.GetTokenById(tokenid)
        if token ~= nil then
            targets[#targets + 1] = { loc = token.loc, token = token }
        end
    end

    return targets
end

local function CreateSynthesizedSpellsPanel()
    local resultPanel

    resultPanel = gui.Panel {
        idprefix = "synthesizeSpellsPanel",
        styles = Styles.ActionMenu,
        classes = { 'collapsed' },
        width = "auto",
        height = "auto",
        maxWidth = 800,
        halign = "center",
        valign = "bottom",
        flow = "horizontal",
        wrap = true,

        data = {
            synthesized = nil
        },

        refreshSpell = function(element, addedSpellOptions)
            if g_currentAbility == nil then
                element:SetClass("collapsed", true)
                return
            end

            local synth = g_currentAbility:SynthesizeAbilities(g_creature)
            element.data.synthesized = synth
            if synth == nil then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            local children = {}
            for _, a in ipairs(synth) do
                local cast = nil
                if g_currentSymbols ~= nil then
                    cast = g_currentSymbols.cast
                end

                local spellOptions = {
                    synthesized = true,
                    cast = cast,
                    ability = a,
                }
                for k, v in pairs(addedSpellOptions or {}) do
                    spellOptions[k] = v
                end
                local panel = AbilityHeading(spellOptions)

                children[#children + 1] = panel
            end

            element.children = children
        end,
    }

    return resultPanel
end

local SetTargetsInRadius = function(tokens)
    for k, tok in pairs(tokens) do
        if tok.valid and tok.sheet ~= nil and g_pointForceTargets[tok.id] == nil then
            tok.sheet:FireEvent("targetnoninteractive", {})
        end
    end

    for k, tok in pairs(g_pointForceTargets) do
        if tok.valid and tok.sheet ~= nil and tokens[k] == nil then
            tok.sheet:FireEvent("untarget")
        end
    end

    g_pointForceTargets = tokens
end

local function CreateTokenSelectionContainer()
    local resultPanel
    
    resultPanel = gui.Panel {
        styles = {
            {
                selectors = {"selectable"},
                opacity = 0,
            },
            {
                selectors = {"selectable", "hover"},
                opacity = 1,
            }
        },
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        flow = "horizontal",
        bgimage = true,
		cornerRadius = 10,
		bgcolor = "#000000fa",
		borderColor = "#000000fa",
		borderWidth = 10,
		borderFade = true,
        pad = 10,

        maxWidth = 800,
        wrap = true,
        disable = function(element)
            element.mapfocus = false
        end,
        settokens = function(element, tokens)
            if tokens == nil then
                element.mapfocus = false
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            local children = {}

            for _,token in ipairs(tokens) do
                local image = gui.CreateTokenImage(token, {
                    width = 64,
                    height = 64,
                    halign = "center",
                    valign = "center",
                })

                local tok = token


                local child = gui.Panel{
                    classes = {"selectable"},
                    width = "auto",
                    height = "auto",
                    bgimage = true,
                    bgcolor = "#ffffff22",
                    borderWidth = 1,
                    borderColor = "white",
                    image,
                    press = function(element)
                        if tok.valid then
                            dmhub.CenterOnToken(tok.charid)
                        end
                    end,
                    linger = function(element)
                        gui.Tooltip(creature.GetTokenDescription(tok))(element)
                    end,
                }


                children[#children + 1] = child
            end

            element.children = children
            element:SetClass("collapsed", #children == 0)
            element.mapfocus = #children > 0
        end,
    }

    return resultPanel
end

CreateAbilityController = function()
    local resultPanel

    m_altitudeController = CreateAltitudeController()
    m_shiftController = CreateShiftController()

    g_castButton = gui.PrettyButton {
        halign = "center",
        width = 140,
        height = 50,
        fontSize = 24,
        bold = true,
        text = "Confirm",
        classes = { 'collapsed' },
        press = function(element)
            assert(g_currentAbility ~= nil)
            assert(g_abilityController ~= nil)

            if g_currentAbility.targetType == 'all' or g_currentAbility.targetType == 'map' or g_currentAbility.targetType == 'areatemplate' then
                --for 'all' types we have a fake map press. The map parameters don't matter.
                g_abilityController:FireEvent("mappress")
            else
                CalculateSpellTargeting(true)
            end
        end,
    }

    g_castMessage = gui.Label {
        data = {
            promptText = '',
        },
        halign = "center",
        width = "auto",
        minWidth = 200,
        textAlignment = "center",
        height = "auto",
        bold = true,
        fontSize = 16,
        refresh = function(element)
            if element.data.promptText == nil or element.data.promptText == "" then
                g_castMessageContainer:SetClass("collapsed", true)
                return
            end

            element.text = element.data.promptText
            g_castMessageContainer:SetClass("collapsed", false)
        end,
    }

    g_tokenSelectionContainer = CreateTokenSelectionContainer()

    g_castMessageContainer = gui.TooltipFrame(g_castMessage, {
    })

    g_castModesPanel = gui.Panel {
        styles = Styles.AdvantageBar,
        classes = { 'advantage-bar', 'collapsed' },
        width = "auto",
        maxWidth = 800,
        height = "auto",
        bgimage = "panels/square.png",
        bgcolor = "#000000bb",
        wrap = true,
        vmargin = 8,

        refreshModes = function(element)
            if g_currentAbility == nil or g_currentAbility.multipleModes == false or g_currentAbility:try_get("modeList") == nil then
                element:SetClass("collapsed", true)
                return
            end

            local changeMode = false
            local children = {}

            for i, mode in ipairs(g_currentAbility.modeList) do
                local available = true
                if mode.condition ~= nil and mode.condition ~= "" then
                    available = ExecuteGoblinScript(mode.condition, g_token.properties:LookupSymbol(), 1,
                        "Mode condition")
                    available = type(available) == "number" and available > 0
                end

                if available then
                    children[#children + 1] = gui.Label {
                        classes = { "advantage-element", cond(i == g_currentSymbols.mode, "selected") },
                        text = mode.text,
                        fontSize = 14,
                        textWrap = true,
                        pad = 1,
                        width = "auto",
                        minWidth = 120,
                        maxWidth = 140,
                        height = 35,

                        hover = function(element)
                            if mode.rules ~= nil and mode.rules ~= "" then
                                gui.Tooltip{valign = "top", text = StringInterpolateGoblinScript(mode.rules, g_token.properties)}(element)
                            end
                        end,

                        press = function(element)
                            g_currentSymbols.mode = i

                            g_currentAbility = g_currentAbility:SwitchModes(i)

                            g_targetInfo = CreateTargetInfo(g_currentAbility)

                            if g_currentAbility.targetType ~= 'self' and g_currentAbility.targetType ~= 'target' and g_currentAbility.targetType ~= 'all' and g_currentAbility.targetType ~= 'areatemplate' then
                                --make this get map events.
                                g_abilityController.mapfocus = true
                            else
                                g_abilityController.mapfocus = false
                            end

                            if g_currentAbility ~= nil and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                                local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                                local shifting = (movementType == "shift")
                                if shifting then
                                    m_shiftController:FireEventTree("beginCasting")
                                    m_shiftController:SetClass("collapsed", false)
                                else
                                    m_shiftController:SetClass("collapsed", true)
                                end
                            else
                                m_shiftController:SetClass("collapsed", true)
                            end



                            g_currentCostProposal = g_currentAbility:GetCost(g_token, g_currentSymbols)
                            CalculateSpellTargeting()
                            --TODO: resourcesBar
                            --resourcesBar:FireEventTree("cost", g_currentCostProposal)
                            g_castMessage:FireEvent("refresh")
                            g_castModesPanel:FireEvent("refreshModes")
                            g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")
                            g_channeledResourcePanel:FireEventTree("focusspell")

                            --If the spell's tooltip varies depending on the mode, then refresh it.
                            if g_currentAbility ~= nil and g_currentAbility:RenderVariesWithDifferentModes() then
                                --TODO: refresh tooltip.
                                --m_currentSpellPanel.data.tooltipSource:FireEvent("showtooltip")
                            end
                        end,
                    }
                elseif i == g_currentSymbols.mode then
                    changeMode = true
                end
            end

            if changeMode and #children > 0 then
                --need to force a mode change to an available mode.
                children[1]:ScheduleEvent("press", 0.05)
            end


            element.children = children

            element:SetClass("collapsed", false)
        end,
    }

    g_forcedMovementTypePanel = gui.Panel {
        styles = Styles.AdvantageBar,
        classes = { 'advantage-bar', 'collapsed' },
        width = "auto",
        maxWidth = 800,
        height = "auto",
        bgimage = "panels/square.png",
        bgcolor = Styles.Ability.blurColor,
        blurBackground = true,
        wrap = true,

        data = {
            possibleForcedMovementTypes = {},
        },

        refreshForcedMovement = function(element)
            local forcedMovementType = g_currentAbility ~= nil and g_currentAbility:ForcedMovementType()
            if forcedMovementType == nil or g_currentSymbols == nil or g_currentSymbols.invoker == nil then
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            local invoker = Utils.ResolveGoblinScriptObject(g_currentSymbols.invoker)

            --see if the invoker is capable of modifying the forced movement type.
            local movementTypes = invoker:CanModifyForcedMovementTypes(forcedMovementType)
            if #movementTypes == 0 then
                element.children = {}
                element:SetClass("collapsed", true)
                return
            end

            local possibleForcedMovementTypes = movementTypes
            table.insert(possibleForcedMovementTypes, 1, forcedMovementType)

            local preferred = g_preferredForcedMovementType:Get()
            if table.contains(possibleForcedMovementTypes, preferred) then
                g_currentSymbols.forcedmovement = preferred
            else
                g_currentSymbols.forcedmovement = possibleForcedMovementTypes[1]
            end

            local children = {}
            for i, moveType in ipairs(possibleForcedMovementTypes) do
                children[#children + 1] = gui.Label {
                    classes = { "advantage-element", cond(moveType == g_currentSymbols.forcedmovement, "selected") },
                    text = moveType,

                    press = function(element)
                        g_preferredForcedMovementType:Set(moveType)
                        g_currentSymbols.forcedmovement = moveType

                        CalculateSpellTargeting()

                        g_castMessage:FireEvent("refresh")
                        g_castModesPanel:FireEvent("refreshModes")
                        g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")
                    end,
                }
            end

            element.children = children
            element:SetClass("collapsed", false)
        end,
    }

    g_skipButton = gui.PrettyButton {
        width = 80,
        height = 30,
        fontSize = 14,
        text = "Skip",
        halign = "center",
        classes = { 'collapsed' },
        press = function(element)
            assert(g_abilityController ~= nil)
            g_abilityController:FireEvent("cancelCasting")
        end,
    }

    g_ammoChoicePanel = gui.Panel {
        width = 1,
        height = 1,
    }

    g_synthesizedSpellsPanel = CreateSynthesizedSpellsPanel()

    g_castChargesInput = gui.Panel {
        width = 1,
        height = 1,
    }

    --- @type Label
    local channeledResourceTitle = gui.Label {
        text = "Channeled Resource",
        fontSize = 24,
        bold = true,
        markdown = true,
        bmargin = 5,
        color = Styles.textColor,
        halign = "center",
        valign = "top",
        width = "auto",
        maxWidth = 800,
        height = 28,
    }

    --- @type Panel
    local channeledResourceContainer = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
    }

    g_channeledResourcePanel = gui.Panel {
        classes = { "collapsed" },
        width = "auto",
        height = "auto",
        vpad = 8,
        hpad = 16,
        borderFade = true,
        borderWidth = 12,
        tmargin = 2,
        bmargin = 2,
        flow = "vertical",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#00000088",
        borderColor = "#00000088",

        channeledResourceTitle,
        channeledResourceContainer,

        data = {
            children = {},
        },

        styles = {
            {
                selectors = { "levelPanel" },
                width = 22,
                height = 22,
                hmargin = 2,
                valign = "center",
                fontSize = 18,
                color = Styles.textColor,
                textAlignment = "center",
                borderWidth = 1,
                bgimage = "panels/square.png",
                borderWidth = 1,
                borderColor = "#ffffff55",
                bgcolor = "#ffffff22",
            },
            {
                selectors = { "levelPanel", "invalid" },
                color = "red",
                borderColor = "#99999955",
                bgcolor = "#99999922",
            },
            {
                selectors = { "levelPanel", "~invalid", "hover" },
                borderColor = "#ffffffaa",
            },
            {
                selectors = { "levelPanel", "selected" },
                borderColor = "#ffffffff",
                borderWidth = 2,
            },
        },

        focusspell = function(element)
            assert(g_token ~= nil)
            if g_currentAbility == nil or g_currentAbility.channeledResource == "none" then
                element:SetClass("collapsed", true)
                return
            end

            local resourcesTable = dmhub.GetTable(CharacterResource.tableName) or {}
            local resource = resourcesTable[g_currentAbility.channeledResource]
            if resource == nil then
                element:SetClass("collapsed", true)
                return
            end

            local resources = g_token.properties:GetResources()[resource.id] or 0
            local resourcesAvailable = resources - g_token.properties:GetResourceUsage(resource.id, resource.usageLimit)
            local baseCost = 0
            if g_currentAbility.resourceCost == g_currentAbility.channeledResource then
                --what we are channeling is also the base cost of the spell, so factor that in.
                resourcesAvailable = resourcesAvailable - ExecuteGoblinScript(g_currentAbility.resourceNumber, g_token.properties:LookupSymbol(g_currentSymbols), 0, "Determine resource number for " .. g_currentAbility.name)
                baseCost = ExecuteGoblinScript(g_currentAbility.resourceNumber, g_token.properties:LookupSymbol(g_currentSymbols), 0, "Determine resource number for " .. g_currentAbility.name)
            end

            if resourcesAvailable <= 0 then
                element:SetClass("collapsed", true)
                return
            end

            channeledResourceTitle.text = StringInterpolateGoblinScript(g_currentAbility.channelDescription,
                g_token.properties) or ""
            local channelIncrement = g_currentAbility:ChannelIncrement()
            local maxChannel = g_currentAbility:MaxChannel(g_token.properties, g_currentSymbols)

            local added = false
            local children = element.data.children
            while #children * channelIncrement <= resourcesAvailable and #children * channelIncrement <= maxChannel do
                local ncharges = #children
                local nresources = ncharges * channelIncrement
                local panel = gui.Label {
                    classes = { "levelPanel" },
                    text = tostring(ncharges * channelIncrement),
                    data = {
                        nresources = nresources,
                        ncharges = ncharges,
                    },
                    press = function(element)
                        if element:HasClass("invalid") == false then
                            g_channeledResourcePanel:FireEventTree("select", element.data.ncharges)
                        end
                    end,
                }

                children[#children + 1] = panel
                added = true
            end

            for i = 1, #children do
                children[i].text = tostring(baseCost + (i - 1) * channelIncrement)
                children[i].data.nresources = (i - 1) * channelIncrement
                children[i]:SetClass("collapsed", (i - 1) * channelIncrement > resourcesAvailable)
                children[i]:SetClass("selected", (i - 1) == g_currentSymbols.charges)
            end

            if added then
                element.data.children = children

                channeledResourceContainer.children = children
            end

            element:SetClass("collapsed", false)
        end,
        defocusspell = function(element)
            element:SetClass("collapsed", true)
        end,

        select = function(element, charges)
            assert(g_channeledResourcePanel ~= nil)
            assert(g_currentAbility ~= nil)

            --recalculate with the new cost proposal.
            g_currentCostProposal = g_currentAbility:GetCost(g_token, { charges = charges, mode = g_currentSymbols.mode })
            g_currentSymbols.charges = charges

            CalculateSpellTargeting()
            g_castMessage:FireEvent("refresh")
            g_castModesPanel:FireEvent("refreshModes")
            g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")

            g_channeledResourcePanel:FireEventTree("focusspell")
        end,
    }


    resultPanel = gui.Panel {
        id = "abilityController",
        classes = { "collapsed" },
        floating = true,
        width = "auto",
        height = "auto",
        valign = "bottom",
        halign = "center",
        flow = "vertical",
        y = -70,

        g_triggerReactionPanel,

        g_castMessageContainer,
        g_tokenSelectionContainer,


        g_forcedMovementTypePanel,

        m_altitudeController,
        m_shiftController,

        g_ammoChoicePanel,
        g_synthesizedSpellsPanel,
        g_castChargesInput,

        g_channeledResourcePanel,

        g_castModesPanel,

        gui.Panel {
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            g_castButton,
            g_skipButton,
        },




        create = function(element)
            element.data.oldIsCasting = gamehud.actionBarPanel.data.IsCastingSpell
            gamehud.actionBarPanel.data.IsCastingSpell = function()
                return g_currentAbility
            end
        end,

        destroy = function(element)
            if gamehud and gamehud.actionBarPanel and gamehud.actionBarPanel.valid then
                gamehud.actionBarPanel.data.IsCastingSpell = element.data.oldIsCasting
            end
        end,

        enable = function(element)
        end,

        disable = function(element)
            element:FireEvent("cancelCasting")
        end,

        beginCasting = function(element, ability, args)
            if g_invokerInfo ~= nil and g_invokerInfo.oncast ~= nil then
                g_invokerInfo.oncast()
            end

            args = args or {}

            assert(g_actionBar ~= nil)
            g_actionBar:FireEventTree("closemenu")

            ability = ability:SwitchModes(1)

            --[[ --code to make a 'charge' ability a charge.
            if args.fromui and ability:HasKeyword("Charge") then
                --find the charge ability and use it instead.
                local chargeAbility = nil
                for _,ability in ipairs(g_abilities) do
                    if ability.name == "Charge" and ability:HasKeyword("Melee") then
                        chargeAbility = DeepCopy(ability:MakeTemporaryClone())
                    end
                end

                if chargeAbility ~= nil then
                    --cook up a special version of the charge ability that always
                    --uses the current ability as the attack at the end of the charge.
                    local invoke = nil
                    for i=#chargeAbility.behaviors, 1, -1 do
                        if chargeAbility.behaviors[i].typeName == "ActivatedAbilityInvokeAbilityBehavior" then
                            invoke = chargeAbility.behaviors[i]
                            break
                        end
                    end

                    if invoke ~= nil then
                        invoke.abilityType = "named"
                        invoke.namedAbility = ability.name
                        invoke.promptText = "Choose target of " .. ability.name
                        ability = chargeAbility
                    end
                end
            end
            ]]

            g_currentAbility = ability
            g_targetsChosen = {}
            g_firstTarget = nil

            --transfer any packaged targets over. TODO: Work out how to pass in non-token targets.
            if args.targets ~= nil then
                for _,target in ipairs(args.targets) do
                    if target.token ~= nil then
                        g_targetsChosen[#g_targetsChosen + 1] = target.token.charid
                    end
                end
            end
            
            if g_targetsChosen ~= nil then
                g_firstTarget = g_targetsChosen[1]
            end
            m_positionTargetsChosen = {}
            g_pointTargeting = {}

            --if we have a 'duration effect' on this ability we apply it while casting,
            --so that we can get its effects during casting. E.g. if their movement increases
            --for pathfinding. TODO: Make this more general than just looking for a specific
            --behavior as the first behavior.
            if #g_currentAbility.behaviors > 0 and g_currentAbility.behaviors[1].typeName == "ActivatedAbilityApplyAbilityDurationEffect" then
                g_castingDestructors[#g_castingDestructors + 1] = g_currentAbility.behaviors[1]:ApplyOnCasting(g_token)
            end

            gui.SetFocus(element)

            g_synthesizedSpellsPanel:SetClass("collapsed", true)
            m_altitudeController:SetClass("collapsed", true)

            g_currentSymbols = table.union(
                { cast = args.cast, mode = 1, charges = ability:DefaultCharges(), spellname = ability.name },
                args.symbols or {})

            local compelToward = g_token.properties:CalculateNamedCustomAttribute("Compel Movement Toward")
            if compelToward ~= 0 then
                local tokens = dmhub.allTokens
                for _,tok in ipairs(tokens) do
                    if Utils.HashGuidToNumber(tok.charid) == compelToward then
                        g_currentSymbols.compeltoward = tok.properties
                        break
                    end
                end
            end

            local compeladjacent = g_token.properties:CalculateNamedCustomAttribute("Compel Movement Adjacent")
            if compeladjacent ~= 0 then
                local tokens = dmhub.allTokens
                for _,tok in ipairs(tokens) do
                    if Utils.HashGuidToNumber(tok.charid) == compeladjacent then
                        g_currentSymbols.compeladjacent = tok.properties
                        break
                    end
                end
            end

            g_currentCostProposal = ability:GetCost(g_token, g_currentSymbols)

            g_targetInfo = CreateTargetInfo(g_currentAbility)

            g_castMessageContainer:SetClass("collapsed", true)
            g_tokenSelectionContainer:SetClass("collapsed", true)
            g_castButton:SetClass("collapsed", true)

            if ability.targetType ~= 'self' and ability.targetType ~= 'target' and ability.targetType ~= 'all' and ability.targetType ~= 'areatemplate' then
                --make this get map events.
                g_abilityController.mapfocus = true
            else
                g_abilityController.mapfocus = false
            end

            element.captureEscape = true

            element:SetClass("collapsed", false)

            if ability:GetCastingEmote() ~= nil then
                g_castingEmoteSet = ability:GetCastingEmote()
                g_token.properties:Emote(g_castingEmoteSet, { start = true, ttl = 20 })
            end

            dmhub.blockTokenSelection = true

            --Don't force cast when beginning casting
            --Abilities with prompts need to wait for user input
            CalculateSpellTargeting(false, true)

            g_channeledResourcePanel:FireEventTree("focusspell")

            if g_currentAbility ~= nil and g_currentAbility.castImmediately and (not g_castButton:HasClass("collapsed")) then
                g_castButton:FireEvent("press")
            end


            if g_currentAbility ~= nil and (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") then
                local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                local shifting = (movementType == "shift")
                if shifting then
                    m_shiftController:FireEventTree("beginCasting")
                    m_shiftController:SetClass("collapsed", false)
                else
                    m_shiftController:SetClass("collapsed", true)
                end
            else
                m_shiftController:SetClass("collapsed", true)
            end

            --see if there are any triggers that can apply to this cast.
            ClearCastingTriggers()
            if g_currentAbility ~= nil then
                local triggers = {}
                local triggerSymbols = table.shallow_copy(g_currentSymbols)
                triggerSymbols.ability = GenerateSymbols(g_currentAbility)
                triggerSymbols.caster = g_token.properties:LookupSymbol()
                triggerSymbols.targetcount = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                for _, triggerToken in ipairs(dmhub.allTokens) do
                    for _, mod in ipairs(triggerToken.properties:GetActiveModifiers()) do
                        mod.mod:TriggerModsCastingAbility(mod, triggerToken, g_token, g_currentAbility, triggerSymbols,
                            triggers)
                    end
                end

                if #triggers > 0 then
                    m_castingTriggers = {}
                    for _, trigger in ipairs(triggers) do
                        local token = dmhub.GetTokenById(trigger.charid)
                        if token ~= nil then
                            token:ModifyProperties {
                                description = "Trigger Casting",
                                undoable = false,
                                execute = function()
                                    token.properties:DispatchAvailableTrigger(trigger)
                                end,
                            }
                            m_castingTriggers[#m_castingTriggers + 1] = trigger
                        end
                    end
                    m_castingTriggers = triggers
                    m_castingTriggersOwnerPanel = element
                    m_castingTriggersCache = {}
                    element.monitorGame = "/characters"
                end
            end
        end,

        monitorGameEvent = "refreshCharacters",
        refreshCharacters = function(element)
            if m_castingTriggers == nil or #m_castingTriggers == 0 then
                return
            end

            for i = 1, #m_castingTriggers do
                local triggerToken = dmhub.GetTokenById(m_castingTriggers[i].charid)
                if triggerToken ~= nil and triggerToken.valid then
                    local availableTriggers = triggerToken.properties:GetAvailableTriggers() or {}
                    local availableTrigger = availableTriggers[m_castingTriggers[i].id]
                    if availableTrigger == nil then
                        table.remove(m_castingTriggers, i)
                    else
                        m_castingTriggers[i] = availableTrigger

                        if availableTrigger.triggered and (not m_castingTriggersCache[availableTrigger.id]) then
                            m_castingTriggersCache[availableTrigger.id] = true

                            if availableTrigger.params.targetcount ~= nil then
                                g_currentSymbols.targetcount = availableTrigger.params.targetcount
                                g_currentSymbols.numtargetsoverride = availableTrigger.params.targetcount
                                CalculateSpellTargeting()
                            end
                        end
                    end
                end
            end
        end,
        clearCastingTriggers = function(element)
            element.monitorGame = nil
        end,



        finishCasting = function(element)
            element:FireEvent("cancelCasting")
        end,

        cancelCasting = function(element)
            ClearCastingTriggers()

            for _, destructor in ipairs(g_castingDestructors) do
                destructor()
            end

            g_castingDestructors = {}

            if g_invokerInfo ~= nil and g_invokerInfo.oncancel ~= nil then
                g_invokerInfo.oncancel()
            end

            g_invokerInfo = nil

            for k, token in pairs(dmhub.tokenInfo.tokens) do
                if token.valid and token.sheet ~= nil and token.sheet.data.targetInfo ~= g_targetInfo then
                    token.sheet:FireEvent("untarget")
                    token.sheet.data.targetInfo = nil
                end
            end

            if g_token ~= nil and g_token.valid then
                g_token:ClearMovementArrow()
            end

            dmhub.blockTokenSelection = false

            TryPopCasterToken()

            if gui.GetFocus() == element then
                gui.SetFocus(nil)
            end

            CharacterPanel.HideAbility(g_currentAbility)

            RemoveTokenTargeting()

            ClearPointTargeting()

            SetTargetsInRadius({})

            g_currentAbility = nil
            g_currentSymbols = {}
            FreeTargetLineOfSightRays()
            element.mapfocus = false
            element.captureEscape = false

            g_channeledResourcePanel:SetClass("collapsed", true)
            m_altitudeController:SetClass("collapsed", true)
            m_allowedAltitudeCalculator = nil

            g_actionBar:SetClassTree("invokingAbility", false)
            g_abilityController.mapfocus = false

            ClearLineOfSightMark()
            ClearRadiusMarkers()

            if g_token ~= nil and g_token.valid and g_castingEmoteSet ~= nil then
                local emote = g_castingEmoteSet
                g_token.properties:Emote(emote, { start = false, ttl = 20 })

                g_castingEmoteSet = nil
            end

            element:SetClass("collapsed", true)
        end,

        chooseTargetToken = function(element, options)
            element:FireEvent("chooseTarget", options)
        end,

        chooseTarget = function(element, options)
            assert(g_actionBar ~= nil)
            ClearRadiusMarkers()

            if options.sourceToken ~= nil and options.radius ~= nil then
                print("MovementRadius:: MARK", options.radius)
                AddRadiusMarker(options.sourceToken.locsOccupying, options.radius)
            end

            local targets = options.targets or {}
            local promptText = options.prompt or "Choose a target"
            local choose = options.choose or function(target) end
            local cancel = options.cancel or function() end

            gui.SetFocus(nil)
            g_actionBar:FireEvent("refresh")

            g_actionBar:SetClassTree("choosingTarget", true)

            g_tokenSelectionContainer:FireEvent("settokens", targets)

            g_castMessage.data.promptText = promptText
            g_castMessage:FireEvent("refresh")
            g_abilityController:SetClass("collapsed", false)
            g_castButton:SetClass("collapsed", true)

            local targetChooser = gui.Panel {
                width = 1,
                height = 1,
                escapeActivates = true,
                escapePriority = EscapePriority.CANCEL_ACTION_BAR,
                captureEscape = true,
                escape = function(element)
                    element:DestroySelf()
                end,
                defocus = function(element)
                    element:DestroySelf()
                end,
                destroy = function()
                    g_castMessage.data.promptText = ''
                    g_castMessage:FireEvent("refresh")
                    g_abilityController:SetClass("collapsed", true)
                    ClearRadiusMarkers()
                    cancel()
                    for _, tok in ipairs(targets) do
                        if tok ~= nil and tok.valid and tok.sheet ~= nil then
                            tok.sheet.data.targetInfo = nil
                            tok.sheet:FireEvent("untarget")
                        end
                    end
                    gui.SetFocus(nil)
                    g_actionBar:SetClassTree("choosingTarget", false)
                end,
            }


            local targetInfo = {
                type = "ActivatedAbility",
                guid = dmhub.GenerateGuid(),
                execute = function(targetToken, info) --info has {targetEffects = {list of effect panels}}
                    choose(targetToken)
                    cancel = function() end
                    gui.SetFocus(nil)
                end,
            }

            for _, tok in ipairs(targets) do
                if tok.valid and tok.sheet ~= nil then
                    if tok.sheet.data.targetInfo ~= nil then
                        tok.sheet.data.targetInfo = nil
                        tok.sheet:FireEvent("untarget")
                    end
                    tok.sheet.data.targetInfo = targetInfo
                    tok.sheet:FireEvent("target", {})
                end
            end

            g_actionBar:AddChild(targetChooser)
            gui.SetFocus(targetChooser)
        end,

        --- @param invokerInfo nil|{oncast=nil|function, oncancel=nil|function}
        invokeAbility = function(element, casterToken, ability, symbols, invokerInfo, options)
            options = options or {}
            gui.SetFocus(nil)

            g_invokerInfo = invokerInfo
            symbols.invoked = true

            PushCasterToken(casterToken)
            g_actionBar:FireEvent("refresh")

            g_actionBar:SetClassTree("invokingAbility", true)

            ability = DeepCopy(ability)
            element:FireEvent("beginCasting", ability, { symbols = symbols })

            --[[
            local spellPanel = GetSpellPanel(nil, nil, ability,
                { destroyOnDefocus = true, invoking = true, forceCasterToken = casterToken, adoptCasterToken = true })
            element:AddChild(spellPanel)
            --spellPanel:SetClass("collapsed", true)
            gui.SetFocus(spellPanel)
            spellPanel.data.stickyFocus = true
            spellPanel.data.blockFocus = true
            --]]

            g_synthesizedSpellsPanel:FireEvent("refreshSpell", { forceCasterToken = casterToken, instantCast = options.instantCast, targets = options.targets })
        end,

        highlightTargetToken = function(element, targetToken)
            if g_token == nil or not g_token.valid then
                return
            end
            element:FireEvent("unhighlightTargetToken")

            local targets = BuildTargetsList()
            targets[#targets + 1] = {
                token = targetToken,
                loc = targetToken.loc,
            }

            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
            g_currentSymbols.range = range
            local rays = g_currentAbility:GetTargetingRays(g_token, range, g_currentSymbols, targets)
            if rays ~= nil then
                --the ability specifies the rays, we try to fish out the
                --new one to highlight and maintain any existing ones.
                for _, ray in ipairs(rays) do
                    if ray.b.id == targetToken.id and m_targetLineOfSightRays[string.format("%s-%s", ray.a.id, ray.b.id)] == nil then
                        m_markLineOfSight = dmhub.MarkLineOfSight(ray.a, ray.b)
                        m_markLineOfSightToken = targetToken
                        m_markLineOfSightSourceToken = g_token
                        break
                    end
                end
            else
                --we just target from the source to the target.
                m_markLineOfSight = dmhub.MarkLineOfSight(g_token, targetToken)
                if m_markLineOfSight ~= nil then
                    m_markLineOfSightToken = targetToken
                    m_markLineOfSightSourceToken = g_token
                end
            end
        end,

        unhighlightTargetToken = function(element, targetToken)
            if m_markLineOfSight ~= nil and (targetToken == nil or targetToken == m_markLineOfSightToken) then
                m_markLineOfSight:Destroy()
                m_markLineOfSight = nil
                m_markLineOfSightToken = nil
                m_markLineOfSightSourceToken = nil
            end
        end,

        --map events that we get when in point targeting mode.
        --- @param element Panel
        --- @param loc Loc
        --- @param point table
        maphover = function(element, loc, point)
            element.data.lastHoverLoc = loc
            element.data.lastHoverPoint = point

            assert(g_abilityController ~= nil)
            if g_token == nil or (not g_token.valid) then
                g_abilityController:FireEvent("cancelCasting")
                return
            end

            assert(g_currentAbility ~= nil, "Current ability is not set.")

            if g_pointTargeting == nil then
                return
            end

            local startingLoc = loc

            if g_pointTargeting.shapeConfirmedLoc ~= nil and (loc == nil or loc.str ~= g_pointTargeting.shapeConfirmedLoc.str) then
                g_pointTargeting.shapeConfirmedLoc = nil
            end

            if loc ~= nil and m_allowedAltitudeCalculator ~= nil then
                local info = { loc = loc, point = point, panel = element }
                m_altitudeController:FireEventTree("loc", info)
                loc = info.loc
            end

            --a list of targets we'll highlight.
            local filteredTargets = {}

            local targetColor = "white"
            local clearMovementArrow = g_pointTargeting.showingMovementArrow
            local prevShape = g_pointTargeting.shape
            if g_pointTargeting.fallingShape ~= nil then
                g_pointTargeting.fallingShape:Destroy()
                g_pointTargeting.fallingShape = nil
            end
            local destroyLabelsBeforeReturning = g_pointTargeting.labelsAtPathEnd ~= nil
            local pathfinding = false
            if point ~= nil and g_currentAbility.targetType ~= "areatemplate" then
                local radius = g_currentAbility:GetRadius(g_token.properties, g_currentSymbols)
                local shape = g_currentAbility.targetType
                local requireEmpty = false

                local locOverride = g_currentAbility:try_get("casterLocOverride")

                local targetingType = g_currentAbility:try_get("targeting", "direct")

                if (shape == 'emptyspace' or shape == 'anyspace') and (targetingType == "pathfind" or targetingType == "vacated" or targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures") then
                    if g_token.creatureDimensions.x > 1 and g_token.creatureDimensions.x % 2 == 1 then
                        for i = 3, g_token.creatureDimensions.x, 2 do
                            loc = loc.west.south
                        end
                    end
                end

                if shape == "line" and #m_positionTargetsChosen == 0 then
                    local lineDistance = g_currentAbility:GetLineDistance(g_token.properties, g_currentSymbols)
                    --still choosing the starting point of the line.
                    g_pointTargeting.shape = dmhub.CalculateShape {
                        shape = "cylinder",
                        targetPoint = point,
                        token = g_token,
                        range = lineDistance,
                        radius = 1,
                        locOverride = g_currentAbility:try_get("casterLocOverride"),
                        requireEmpty = requireEmpty,
                        emptyMayIncludeSelf = true,
                    }
                    
                elseif (shape == "emptyspace" or shape == "anyspace") and (targetingType == "pathfind" or targetingType == "vacated") then
                    pathfinding = true

                    local waypoints = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        waypoints[#waypoints + 1] = pos.loc
                    end

                    local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                    local shifting = (movementType == "shift")

                    local movementInfo = g_token:MarkMovementArrow(loc, { shifting = shifting, waypoints = waypoints })
                    if movementInfo ~= nil then
                        local targets = g_currentAbility:FindTargetsInMovementVicinity(g_token, movementInfo.path) or
                            filteredTargets
                        for _, target in ipairs(targets) do
                            filteredTargets[target.id] = target
                        end
                    end
                    g_pointTargeting.showingMovementArrow = true
                    clearMovementArrow = false
                elseif shape == "emptyspace" and targetingType == "direct" then
                    g_token:MarkMovementArrow(loc, { teleport = true })
                    g_pointTargeting.showingMovementArrow = true
                    clearMovementArrow = false
                elseif (shape == 'emptyspace' or shape == 'anyspace') and (targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures") then
                    local waypoints = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        waypoints[#waypoints + 1] = pos.loc
                    end

                    g_currentSymbols.waypoints = waypoints

                    local movementInfo = g_token:MarkMovementArrow(loc, {
                        straightline = true,
                        ignorecreatures = (targetingType == "straightpathignorecreatures"),
                    })
                    
                    if movementInfo ~= nil then
                        local targets = g_currentAbility:FindTargetsInMovementVicinity(g_token, movementInfo.path) or
                            filteredTargets
                        for _, target in ipairs(targets) do
                            filteredTargets[target.id] = target
                        end
                    end
                    g_pointTargeting.showingMovementArrow = true
                    clearMovementArrow = false

                    if movementInfo ~= nil then
                        local path = movementInfo.path
                        local abilityDist = g_currentAbility:GetRange(g_token.properties, g_currentSymbols) /
                            dmhub.unitsPerSquare
                        g_currentSymbols.range = abilityDist
                        local requestDist = math.min(loc:DistanceInTiles(path.origin), abilityDist)
                        local pathDist = path.destination:DistanceInTiles(path.origin)

                        if pathDist < requestDist and (g_currentAbility:try_get("targeting", "direct") == "straightline") and g_token.properties:CalculateNamedCustomAttribute("No Damage From Forced Movement") == 0 then
                            local prevOvershoot = g_pointTargeting.pathEndOvershoot
                            g_pointTargeting.pathEndOvershoot = abilityDist - pathDist

                            local prevPathEnd = g_pointTargeting.shapePathEnd
                            destroyLabelsBeforeReturning = false

                            local destPoint = path.destination.point3
                            if g_token.creatureDimensions.x % 2 == 0 then
                                local offset = (g_token.creatureDimensions.x - 1) * 0.5
                                destPoint = core.Vector3(destPoint.x + offset, destPoint.y + offset, destPoint.z)
                            end

                            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                            g_currentSymbols.range = range

                            g_pointTargeting.shapePathEnd = {
                                dmhub.CalculateShape {
                                    shape = cond(g_token.creatureDimensions.x % 2 == 1, "radius", "cylinder"),
                                    token = g_currentAbility:GetRangeSource(g_token),
                                    targetPoint = destPoint,
                                    range = range,
                                    radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                }
                            }

                            local collideWith = movementInfo.collideWith or {}

                            --implement increase of collide damage if we collide into an object.
                            local collideDamage = g_pointTargeting.pathEndOvershoot

                            local isObject = true
                            for _, collideToken in ipairs(collideWith) do
                                if not collideToken.isObject then
                                    isObject = false
                                    break
                                end
                            end

                            if isObject then
                                collideDamage = collideDamage + 2
                            end

                            local textLabels = {}
                            textLabels[#textLabels + 1] = {
                                point = destPoint,
                                text = string.format("-%d<color=#00000000>-</color>", collideDamage),
                            }

                            for _, collideToken in ipairs(collideWith) do
                                local targetPoint = collideToken:PosAtLoc()
                                g_pointTargeting.shapePathEnd[#g_pointTargeting.shapePathEnd + 1] = dmhub.CalculateShape {
                                    shape = cond(collideToken.creatureDimensions.x % 2 == 1, "radius", "radiusfromintersection"),
                                    token = collideToken,
                                    targetPoint = collideToken:PosAtLoc(),
                                    range = 0,
                                    radius = collideToken.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                                }

                                textLabels[#textLabels + 1] = {
                                    point = collideToken:PosAtLoc(),
                                    text = string.format("-%d<color=#00000000>-</color>", collideDamage),
                                }
                            end

                            local needRedraw = prevPathEnd == nil or #prevPathEnd ~= #g_pointTargeting.shapePathEnd or
                                prevOvershoot ~= g_pointTargeting.pathEndOvershoot
                            if not needRedraw then
                                for i, loc in ipairs(prevPathEnd) do
                                    if not loc.str == g_pointTargeting.shapePathEnd[i].str then
                                        needRedraw = true
                                        break
                                    end
                                end
                            end

                            if needRedraw then
                                if g_pointTargeting.labelsAtPathEnd ~= nil then
                                    for _, marker in ipairs(g_pointTargeting.labelsAtPathEnd) do
                                        marker:Destroy()
                                    end
                                    g_pointTargeting.labelsAtPathEnd = nil
                                    destroyLabelsBeforeReturning = false
                                end

                                g_pointTargeting.labelsAtPathEnd = {}
                                for i, loc in ipairs(g_pointTargeting.shapePathEnd) do
                                    g_pointTargeting.labelsAtPathEnd[#g_pointTargeting.labelsAtPathEnd + 1] =
                                        g_pointTargeting.shapePathEnd
                                        [i]:Mark { color = "red", video = "divinationline.webm", showLocs = false }
                            print("MARK:: MARK SHAPE")
                                end

                                for i, info in ipairs(textLabels) do
                                    g_pointTargeting.labelsAtPathEnd[#g_pointTargeting.labelsAtPathEnd + 1] = dmhub
                                        .CreateCanvasOnMap {
                                            point = info.point,
                                            sheet = gui.Label {
                                                interactable = false,
                                                halign = "center",
                                                valign = "center",
                                                color = "red",
                                                width = "auto",
                                                height = "auto",
                                                fontSize = 0.5,
                                                text = info.text,
                                            }
                                        }
                                end
                            end
                        end

                        --falling.
                        local fallInfo = g_token:GetFallInfoFromLoc(loc)
                        if fallInfo ~= nil then
                            local fallShape = dmhub.CalculateShape {
                                shape = "radius",
                                token = g_token,
                                locOverride = fallInfo.loc,
                                targetPoint = g_token:PosAtLoc(fallInfo.loc),
                                radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5,
                            }

                            g_pointTargeting.fallingShape = fallShape:Mark { color = "red", video = "divinationline.webm" }
                            print("MARK:: MARK SHAPE")
                        end
                    end
                end

                if point == 'all' then
                    --this is for the 'all' target type, targeting within the caster.
                    radius = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                    g_currentSymbols.range = radius
                    point = nil
                    shape = "RadiusFromCreature"
                end
                if shape == 'emptyspace' or shape == 'emptyspacefriend' or shape == 'anyspace' then
                    radius = dmhub.unitsPerSquare * 0.5
                    requireEmpty = (shape == 'emptyspace')

                    if (shape == "emptyspace" or shape == "anyspace") then
                        radius = g_token.creatureDimensions.x * dmhub.unitsPerSquare * 0.5
                        if g_token.creatureDimensions.x % 2 == 1 then
                            shape = "radius"
                        else
                            --if we are an even number of tiles wide, we want to target a tile intersection
                            --we offset the target point to match creature movement behavior.
                            shape = "cylinder"
                            local offset = (g_token.creatureDimensions.x - 1) * 0.5
                            point = core.Vector3(point.x + offset, point.y + offset, point.z)
                        end
                    else
                        shape = "radius"
                    end

                    if #m_positionTargetsChosen > 0 and (g_currentAbility.targeting == "contiguous" or g_currentAbility.targeting == "contiguous_wall") then
                        shape = "locations"
                    end
                end

                local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
                g_currentSymbols.range = range
                if shape == "line" and g_currentAbility.canChooseLowerRange then
                    local pos = g_token:PosAtLoc(g_token.loc)
                    local dist = math.ceil(math.max(math.abs(point.x - pos.x), math.abs(point.y - pos.y)))
                    range = math.min(range, dist)
                end

                local numTargets = 1
                if g_currentAbility ~= nil then
                    numTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                end

                if numTargets > 1 or targetingType == "pathfind" or (g_pointTargeting.shapeConfirmedLoc ~= nil and g_pointTargeting.shapeConfirmedLoc.str == startingLoc.str) then
                    g_pointTargeting.shapeRequiresConfirm = false
                else
                    g_pointTargeting.shapeRequiresConfirm = true
                end

                local locOverride = nil
                if shape == "line" and #m_positionTargetsChosen == 0 then
                    shape = "radius"
                    radius = 0
                elseif shape == "line" then
                    locOverride = m_positionTargetsChosen[1]
                end

                local locations = nil
                if shape == "locations" then
                    locations = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        locations[#locations + 1] = pos.loc
                    end
                    --add the current location in too, provisionally.
                    locations[#locations+1] = loc
                end

                g_pointTargeting.shape = dmhub.CalculateShape {
                    shape = shape,
                    targetPoint = point,
                    token = g_token,
                    range = range,
                    radius = radius,
                    checklos = true,
                    locOverride = locOverride or g_currentAbility:try_get("casterLocOverride"),
                    requireEmpty = requireEmpty,
                    emptyMayIncludeSelf = requireEmpty and (targetingType == "pathfind" or targetingType == "vacated" or targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures"),
                    locations = locations,
                }
            elseif g_currentAbility.targetType == "map" then
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shape = dmhub.CalculateShape {
                    shape = "map",
                    token = g_token,
                }
            elseif g_currentAbility.targetType == "areatemplate" then
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shape = dmhub.CalculateShape {
                    shape = "areatemplate",
                    token = g_token,
                    objectTemplate = g_currentAbility:try_get("areaTemplateObjectId"),
                }
            else
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shape = nil
            end

            g_currentSymbols.targetArea = g_pointTargeting.shape

            local selfTarget = g_currentAbility.selfTarget
            local targetTokens = dmhub.tokenInfo.TokensInShape(g_pointTargeting.shape)

            --if we target the entire map, do not target creatures not in initiative.
            if g_currentAbility.targetType == "map" and dmhub.initiativeQueue ~= nil and (not dmhub.initiativeQueue.hidden) then
                for tokenid,targetToken in pairs(targetTokens) do
                    if not targetToken.isObject then

                        local initiativeid = InitiativeQueue.GetInitiativeId(targetToken)
                        if not dmhub.initiativeQueue:HasInitiative(initiativeid) then
                            targetTokens[tokenid] = nil
                        end
                    end
                end
            end



            if not pathfinding then
                for k, tok in pairs(targetTokens) do
                    if (selfTarget or tok.charid ~= g_token.charid) and g_currentAbility:TargetPassesFilter(g_token, tok, g_currentSymbols) then
                        filteredTargets[k] = tok
                    end
                end
            end
            SetTargetsInRadius(filteredTargets)

            if g_pointTargeting.radius ~= nil then
                if g_pointTargeting.shape ~= nil and g_pointTargeting.shape:Equal(prevShape) then
                    --shape unchanged.
                    --return
                end

                g_pointTargeting.radius:Destroy()
                g_pointTargeting.radius = nil
            end

            if g_pointTargeting.label ~= nil then
                g_pointTargeting.label:Destroy()
                g_pointTargeting.label = nil
            end

            if g_pointTargeting.shape ~= nil then
                local video = "divinationline.webm"
                local school = string.lower(g_currentAbility:try_get("school", ""))
                if school == "Evocation" then
                    video = "fire-radius.webm"
                elseif school == "Illusion" then
                    video = "illusionline.webm"
                end

                if g_pointTargeting.shapeRequiresConfirm then
                    targetColor = "#444444"
                end

                g_pointTargeting.radius = g_pointTargeting.shape:Mark { color = targetColor, video = video }

                if g_currentAbility ~= nil and loc ~= nil and g_pointTargeting.shape ~= nil then
                    local numTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                    local clickText = cond(numTargets == 1, "Click to Confirm", "")
                    local targetingType = g_currentAbility:try_get("targeting", "direct")
                    if g_currentAbility.targetType == "line" and #m_positionTargetsChosen == 0 then
                        clickText = "Select Line Start"
                    elseif targetingType == "pathfind" then
                        local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                        clickText = string.upper_first(movementType or "Move")

                        if m_positionTargetsChosen ~= nil and #m_positionTargetsChosen > 0 then
                            local lastPos = m_positionTargetsChosen[#m_positionTargetsChosen].loc
                            if lastPos.x == loc.x and lastPos.y == loc.y then
                                clickText = "Click to Confirm"
                            end
                        end
                    elseif g_pointTargeting.shapeRequiresConfirm then
                        clickText = g_currentAbility:DescribeTargetText(g_currentSymbols)
                    end

                    local locs = g_pointTargeting.shape.locations
                    local point = locs[1].withGroundAltitude.point3
                    local minx = point.x
                    local miny = point.y
                    local maxx = point.x
                    local maxy = point.y
                    for i = 2, #locs do
                        point.x = point.x + locs[i].withGroundAltitude.point3.x
                        point.y = point.y + locs[i].withGroundAltitude.point3.y
                        point.z = point.z + locs[i].withGroundAltitude.point3.z

                        minx = math.min(minx, locs[i].withGroundAltitude.point3.x)
                        miny = math.min(miny, locs[i].withGroundAltitude.point3.y)
                        maxx = math.max(maxx, locs[i].withGroundAltitude.point3.x)
                        maxy = math.max(maxy, locs[i].withGroundAltitude.point3.y)
                    end

                    local w = 1 + maxx - minx
                    local h = 1 + maxy - miny

                    point.x = point.x / #locs
                    point.y = point.y / #locs
                    point.z = point.z / #locs

                    g_pointTargeting.label = dmhub.CreateCanvasOnMap {
                        point = point, --loc.point3,
                        sheet = gui.Panel {
                            interactable = false,
                            halign = "center",
                            valign = "center",
                            width = w,
                            height = h,
                            gui.Label {
                                interactable = false,
                                floating = true,
                                valign = "center",
                                halign = "center",
                                width = "80%",
                                height = "auto",
                                fontSize = 0.15,
                                color = "white",
                                text = clickText,
                                textAlignment = "center",
                            },
                            gui.Label {
                                interactable = false,
                                floating = true,
                                valign = "bottom",
                                halign = "center",
                                width = "auto",
                                height = 0.1,
                                y = 0.15,
                                fontSize = 0.15,
                                color = "white",
                                text = g_currentSymbols.spellname or g_currentAbility.name,
                            },
                        }
                    }
                end
            end

            if clearMovementArrow and g_token ~= nil then
                g_token:ClearMovementArrow()
                g_pointTargeting.showingMovementArrow = false
            end

            if destroyLabelsBeforeReturning then
                for _, marker in ipairs(g_pointTargeting.labelsAtPathEnd) do
                    marker:Destroy()
                end


                if g_pointTargeting.fallingShape ~= nil then
                    g_pointTargeting.fallingShape:Destroy()
                end

                g_pointTargeting.fallingShape = nil
                g_pointTargeting.labelsAtPathEnd = nil
                g_pointTargeting.shapePathEnd = nil
            end
        end,

        mappress = function(element, loc, point)
            if g_pointTargeting == nil then
                return
            end

            assert(g_token ~= nil)
            assert(g_currentAbility ~= nil, "Current ability is not set.")

            local shape = g_currentAbility.targetType

            --set the starting point of the line.
            if shape == "line" and #m_positionTargetsChosen == 0 then
                m_positionTargetsChosen[#m_positionTargetsChosen + 1] = loc
                return
            end

            if loc ~= nil and (g_pointTargeting.shapeRequiresConfirm) and g_pointTargeting.shape ~= nil then
                g_pointTargeting.shapeRequiresConfirm = false
                g_pointTargeting.shapeConfirmedLoc = loc
                return
            end

            if m_allowedAltitudeCalculator ~= nil and loc ~= nil then
                local info = { loc = loc, point = point, panel = element }
                m_altitudeController:FireEventTree("loc", info)
                loc = info.loc
            end

            local locOverride = g_currentAbility:try_get("casterLocOverride")
            local targetingType = g_currentAbility:try_get("targeting", "direct")

            if (shape == 'emptyspace' or shape == 'anyspace') and (targetingType == "direct" or targetingType == "pathfind" or targetingType == "vacated" or targetingType == "straightline" or targetingType == "straightpath" or targetingType == "straightpathignorecreatures") then
                --adjust the position of the location if we are moving with a large creature.
                if g_token.creatureDimensions.x > 1 and g_token.creatureDimensions.x % 2 == 1 then
                    for i = 3, g_token.creatureDimensions.x, 2 do
                        loc = loc.west.south
                    end
                end
            end

            print("WAYPOINT:: PRESS SHAPE:", g_pointTargeting.shape)
            if g_pointTargeting.shape ~= nil then
                local targets = m_positionTargetsChosen
                if g_currentAbility.targetType == "line" then
                    --line doesn't include the starting point as a target.
                    targets = {}
                end

                if g_currentAbility.targetType == 'emptyspace' or g_currentAbility.targetType == 'emptyspacefriend' or g_currentAbility.targetType == 'anyspace' then
                    targets[#targets + 1] = { loc = loc }
                else
                    for k, target in pairs(g_pointForceTargets) do
                        if g_currentAbility.targetType ~= 'all' or target ~= g_token or g_currentAbility.selfTarget then
                            targets[#targets + 1] = { loc = target.loc, token = target }
                        end
                    end
                end
                if g_castingEmoteSet and g_token.valid then
                    g_token.properties:Emote(g_castingEmoteSet .. 'cast', { start = true, ttl = 20 })
                end

                if g_currentAbility.sequentialTargeting and g_currentSymbols.targetnumber == nil then
                    g_currentSymbols.targetnumber = 1
                end

                local numTargets = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
                if (g_currentAbility.targetType == 'emptyspace' or g_currentAbility.targetType == 'anyspace') and #targets < numTargets then
                    --allow selection of more targets.
                    AddCustomAreaMarker({ loc }, 'white')

                    if g_currentAbility.targeting == "Contiguous" or g_currentAbility.targeting == "contiguous_wall" then
                        --targeting must be contiguous of current targets.
                        ClearRadiusMarkers()

                        if g_currentAbility.targeting == "contiguous" then
                            local duplicates = false
                            for i=#targets,2,-1 do
                                for j=1,i-1 do
                                    local a = targets[i].loc
                                    local b = targets[j].loc
                                    if a.str == b.str then
                                        --no duplicates.
                                        table.remove(targets, i)
                                        table.remove(targets, j)
                                        duplicates = true
                                        break
                                    end
                                end
                                if duplicates then
                                    break
                                end
                            end
                        end

                        local locs = {}

                        for _,target in ipairs(targets) do
                            if target.loc ~= nil then
                                locs[#locs + 1] = target.loc
                                locs[#locs+1] = target.loc.north
                                locs[#locs+1] = target.loc.south
                                locs[#locs+1] = target.loc.east
                                locs[#locs+1] = target.loc.west
                            end
                        end


                        print("MARK:: MARK LOCS")
                        g_radiusMarkers[#g_radiusMarkers + 1] = dmhub.MarkLocs{
                            locs = locs,
                            color = "#444444",
                        }
                    end

                    local promptText = g_currentAbility:PromptText(g_token, targets, g_currentSymbols)
                    g_castMessage.data.promptText = promptText
                    g_castMessage:FireEvent("refresh")
                    return
                end

                if targetingType == "pathfind" or targetingType == "vacated" then
                    --allow waypoint selection.

                    ClearRadiusMarkers()

                    local waypoints = {}
                    for _, pos in ipairs(m_positionTargetsChosen) do
                        waypoints[#waypoints + 1] = pos.loc
                    end

                    if #waypoints < 2 or waypoints[#waypoints].x ~= waypoints[#waypoints - 1].x or waypoints[#waypoints].y ~= waypoints[#waypoints - 1].y then
                        local mask = nil
                        if targetingType == "vacated" and g_currentSymbols.cast then
                            mask = g_currentSymbols.cast:GetVacatedSpaces()
                        end


                        local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                        local shifting = (movementType == "shift")
                        local moveFlags = {}
                        if shifting then
                            moveFlags[#moveFlags + 1] = "shifting"
                        end

                        local filterTargetPredicate = g_currentAbility:TargetLocPassesFilterPredicate(g_token, g_currentSymbols)
                        local radiusMarker = g_token:MarkMovementRadius(g_range,
                            { moveFlags = moveFlags, waypoints = waypoints, mask = mask, filter = filterTargetPredicate})

                        if radiusMarker ~= nil then
                        print("MARK:: MARK LOCS")
                            g_radiusMarkers[#g_radiusMarkers + 1] = radiusMarker
                            return
                        end
                    end

                    if #waypoints >= 2 and waypoints[#waypoints].x == waypoints[#waypoints - 1].x and waypoints[#waypoints].y == waypoints[#waypoints - 1].y then
                        --last waypoint is the same as the previous one, so remove it.
                        waypoints[#waypoints] = nil
                        targets[#targets] = nil
                    end

                    while #waypoints > 0 and waypoints[#waypoints].x == targets[#targets].loc.x and waypoints[#waypoints].y == targets[#targets].loc.y do
                        waypoints[#waypoints] = nil
                    end

                    g_currentSymbols.waypoints = waypoints

                    --we don't have any movement left, so cast.
                end

                g_token.lookAtMouse = false

                targets = g_currentAbility:PrepareTargets(g_token, g_currentSymbols, targets)

                if m_markLineOfSight ~= nil then
                    SetTargetLineOfSightRayForKey(
                        string.format("%s-%s", m_markLineOfSightSourceToken.id, m_markLineOfSightToken.id),
                        m_markLineOfSight)
                    m_markLineOfSight = nil
                    m_markLineOfSightToken = nil
                    m_markLineOfSightSourceToken = nil
                end

                CharacterPanel.HighlightAbilitySection{
                    ability = g_currentAbility,
                    section = "main",
                }

                local clearAbility = g_currentAbility
                g_currentAbility:Cast(g_token, targets, {
                    targetArea = g_pointTargeting.shape,
                    costOverride = g_currentCostProposal,
                    symbols = g_currentSymbols,
                    markLineOfSight = m_targetLineOfSightRays,
                    OnFinishCastHandlers = {
                        function()
                            CharacterPanel.HideAbility(clearAbility)
                        end
                    }
                })

                g_currentAbility = nil

                m_targetLineOfSightRays = {}

                m_markLineOfSight = nil
                m_markLineOfSightToken = nil
                m_markLineOfSightSourceToken = nil
                g_abilityController:FireEvent("finishCasting")
            end
        end,

        escapePriority = EscapePriority.CANCEL_ACTION_BAR,
        escape = function(element)
            if g_currentAbility ~= nil and g_currentAbility.targetType == "line" and #m_positionTargetsChosen > 0 then
                local loc = m_positionTargetsChosen[#m_positionTargetsChosen]
                --clear the line start point.
                m_positionTargetsChosen = {}
                CalculateSpellTargeting()
                element:FireEvent("maphover", element.data.lastHoverLoc, element.data.lastHoverPoint)
                return
            end
            
            element:FireEvent("cancelCasting")
        end,
    }

    return resultPanel
end

local g_potentialTargetTokens = {}

local function CalculateSpellTargetFocusing(symbols)

    local range = symbols.range

    local potentialTargetTokens = {}
    assert(g_currentAbility ~= nil)
    local spell = g_currentAbility
    if (spell.targetType == 'self' or spell.targetType == 'target' or spell.targetType == 'all' or spell.targetType == 'areatemplate') and g_synthesizedSpellsPanel:HasClass("collapsed") then

        local locs = nil
        if spell.targetType == "areatemplate" then

            local shape = dmhub.CalculateShape {
                shape = "areatemplate",
                token = g_token,
                objectTemplate = g_currentAbility:try_get("areaTemplateObjectId"),
            }

            if shape ~= nil and shape.locations ~= nil then
                locs = shape.locations
            end
        end

        for _, targetToken in ipairs(dmhub.allTokensIncludingObjects) do
            if targetToken.valid and targetToken.sheet ~= nil then
                if targetToken.sheet.data.targetInfo ~= nil then
                    targetToken.sheet:FireEvent("untarget")
                end

                local canTarget = true
                if (spell.targetType == 'self' or spell.targetType == 'all') and targetToken.charid ~= g_token.charid then
                    canTarget = false
                end

                if g_creature == targetToken.properties and (spell.targetType == 'target' or spell.targetType == 'all') and spell.selfTarget == false then
                    canTarget = false
                end

                if symbols ~= nil and symbols.forbiddentargets ~= nil and symbols.forbiddentargets[targetToken.charid] then
                    canTarget = false
                end

                if locs ~= nil and canTarget then
                    canTarget = false
                    local locsOccupying = targetToken.locsOccupying
                    for _,loc in ipairs(locsOccupying) do
                        for _,shapeLoc in ipairs(locs) do
                            if loc.x == shapeLoc.x and loc.y == shapeLoc.y then
                                canTarget = true
                                break
                            end
                        end
                        if canTarget then
                            break
                        end
                    end
                end

                local failReason = nil

                if canTarget then
                    canTarget, failReason = spell:TargetPassesFilter(g_token, targetToken, symbols)
                    if failReason ~= nil then
                        canTarget = true
                    end
                end

                if canTarget and targetToken.properties:HasNamedCondition("Hidden") and g_currentAbility:HasKeyword("Strike") then
                    failReason = "Cannot target a hidden creature with a strike"
                end

                if targetToken.properties:CalculateNamedCustomAttribute("Untargetable") > 0 then
                    failReason = "Target is untargetable"
                end

                local casterLocOverride = g_currentAbility:try_get("casterLocOverride")

                if canTarget then
                    --give us an extra square of range to account for diagonals.
                    if failReason == nil and spell.targetType ~= "areatemplate" and (not g_token.properties.minion) and not (range + dmhub.unitsPerSquare > targetToken:Distance(casterLocOverride or g_token)) then
                        failReason = "Out of range"
                    end
                    local valid = failReason == nil

                    if targetToken.valid and targetToken.sheet ~= nil then
                        if targetToken.sheet.data.targetInfo ~= nil then
                            targetToken.sheet.data.targetInfo = nil
                            targetToken.sheet:FireEvent("untarget")
                        end

                        --count if there are multiple rays for this target.
                        local raycount = 0
                        for key, ray in pairs(m_targetLineOfSightRays) do
                            if string.ends_with(key, targetToken.charid) then
                                raycount = raycount + 1
                            end
                        end

                        local classes = cond(valid, {}, { 'invalid' })
                        if raycount >= 2 then
                            classes[#classes + 1] = "two"
                            if raycount >= 3 then
                                classes[#classes + 1] = "three"
                            end
                        end

                        targetToken.sheet.data.targetInfo = g_targetInfo
                        targetToken.sheet:FireEvent('target', { valid = valid, classes = classes, reason = failReason })

                        potentialTargetTokens[#potentialTargetTokens + 1] = targetToken
                    end
                end
            end
        end
    end

    return potentialTargetTokens
end

CalculateSpellTargeting = function(forceCast, initialSetup)
    assert(g_currentAbility ~= nil, "CalculateSpellTargeting called with nil g_currentAbility")
    assert(g_skipButton ~= nil)

    if g_token == nil then
        dmhub.CloudError("nil token: " .. traceback())
        return
    end

    if g_currentAbility.targetType == 'point' then

    else
        local targets = BuildTargetsList()

        local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
        g_currentSymbols.range = range

        --if this spell dictates specific targeting rays to use.
        local rays = g_currentAbility:GetTargetingRays(g_token, range, g_currentSymbols, targets)
        if rays ~= nil then
            ReplaceTargetLineOfSightRays(rays)

            --record the targeting as symbols.
            local targetPairs = {}
            for i, ray in ipairs(rays) do
                targetPairs[#targetPairs + 1] = { a = ray.a.id, b = ray.b.id }
            end

            g_currentSymbols.targetPairs = targetPairs
        else
            g_currentSymbols.targetPairs = nil
        end

        g_skipButton:SetClass("collapsed", not g_currentAbility:try_get("skippable", false))

        -- Don't auto-cast on initial setup unless requested
        if ((not g_currentAbility:CanSelectMoreTargets(g_token, targets, g_currentSymbols)) or forceCast) then --temporarily disabled -David -- and not initialSetup then
            --we can't select more targets, so cast the spell in here.
            g_token.lookAtMouse = false
            if g_castingEmoteSet and g_token.valid then
                g_token.properties:Emote(g_castingEmoteSet .. 'cast', { start = true, ttl = 20 })
            end

            if g_currentAbility.sequentialTargeting and g_currentSymbols.targetnumber == nil then
                g_currentSymbols.targetnumber = 1
                g_currentSymbols.targetcount = g_currentAbility:GetNumTargets(g_token, g_currentSymbols)
            end

            --make any active targeted tokens keep their targeting until the spell is done.
            local adoptedTargets = {}
            for k, token in pairs(dmhub.allTokensIncludingObjects) do
                if token.valid and token.sheet ~= nil and token.sheet.data.targetInfo == g_targetInfo then
                    token.sheet:FireEvent('adoptSelectedTargets', adoptedTargets)
                end
            end

            targets = g_currentAbility:PrepareTargets(g_token, g_currentSymbols, targets)

            AdoptLineOfSightMark()

            --any triggers created while casting are attached to the spell.
            local attachedTriggers = nil
            if m_castingTriggers ~= nil then
                for _, trigger in ipairs(m_castingTriggers) do
                    if trigger.triggered then
                        attachedTriggers = attachedTriggers or {}
                        attachedTriggers[#attachedTriggers + 1] = DeepCopy(trigger)
                    end
                end
            end

            CharacterPanel.HighlightAbilitySection{
                ability = g_currentAbility,
                section = "main",
            }

            local clearAbility = g_currentAbility
            g_currentAbility:Cast(g_token, targets, {
                attachedTriggers = attachedTriggers,
                costOverride = g_currentCostProposal,
                symbols = g_currentSymbols,
                markLineOfSight = m_targetLineOfSightRays,
                OnFinishCastHandlers = {
                    function()
                        CharacterPanel.HideAbility(clearAbility)
                        for _, panel in ipairs(adoptedTargets) do
                            if panel ~= nil and panel.valid then
                                panel:FireEvent("destroy")
                            end
                        end
                    end,
                },
            })
            m_targetLineOfSightRays = {}

            g_currentAbility = nil

            assert(g_abilityController ~= nil)
            g_abilityController:FireEvent("finishCasting")
        else
            assert(g_ammoChoicePanel ~= nil and g_synthesizedSpellsPanel ~= nil and g_castChargesInput ~= nil)
            g_ammoChoicePanel:FireEvent("refreshSpell")
            g_synthesizedSpellsPanel:FireEvent("refreshSpell")
            g_castChargesInput:FireEvent("refreshSpell")

            local synthesizedSpells = g_synthesizedSpellsPanel.data.synthesized
            g_castButton:SetClass('collapsed',
                (not g_currentAbility:CanCastAsIs(g_token, targets, g_currentSymbols)) or
                (synthesizedSpells ~= nil and #synthesizedSpells > 0))


            local promptText = g_currentAbility:PromptText(g_token, targets, g_currentSymbols, synthesizedSpells)
            g_castMessage.data.promptText = promptText
            g_castMessage:FireEvent("refresh")

            g_castModesPanel:FireEvent("refreshModes")
            g_forcedMovementTypePanel:FireEvent("refreshForcedMovement")

            local range = g_currentAbility:GetRange(g_token.properties, g_currentSymbols)
            print("MovementRadius:: RANGE", range)
            g_currentSymbols.numberoftargets = #targets
            g_currentSymbols.range = range
            g_range = range

            g_potentialTargetTokens = CalculateSpellTargetFocusing(g_currentSymbols)

            --refresh the radius marker.
            if g_currentAbility.targetType == "line" then
                ClearRadiusMarkers()

                if #m_positionTargetsChosen == 0 then
                    local loc = g_currentAbility:try_get("casterLocOverride")
                    local lineDistance = g_currentAbility:GetLineDistance(g_token.properties, g_currentSymbols)
                    AddRadiusMarker(loc, lineDistance, 'white')
                end
                
            elseif (g_currentAbility.targetType == "emptyspace" or g_currentAbility.targetType == "anyspace") and (g_currentAbility:try_get("targeting", "direct") == "pathfind" or g_currentAbility:try_get("targeting", "direct") == "vacated" or g_currentAbility:try_get("targeting", "direct") == "vacated") then
                ClearRadiusMarkers()

                local waypoints = {}
                for _, pos in ipairs(m_positionTargetsChosen) do
                    waypoints[#waypoints + 1] = pos.loc
                end

                local mask = nil
                if g_currentAbility:try_get("targeting", "direct") == "vacated" and g_currentSymbols.cast then
                    mask = g_currentSymbols.cast:GetVacatedSpaces()
                end

                local movementType = g_currentAbility:GetMovementType(g_token, g_currentSymbols)
                local shifting = (movementType == "shift")
                local moveFlags = {}
                if shifting then
                    moveFlags[#moveFlags + 1] = "shifting"
                end

                local filterTargetPredicate = g_currentAbility:TargetLocPassesFilterPredicate(g_token, g_currentSymbols)

                print("MARK:: MovementRadius:: MARK", range)
                g_radiusMarkers[#g_radiusMarkers + 1] = g_token:MarkMovementRadius(range,
                    { moveFlags = moveFlags, waypoints = waypoints, mask = mask, filter = filterTargetPredicate })
            elseif (g_currentAbility.targetType ~= 'line' or g_currentAbility.canChooseLowerRange) and g_currentAbility.targetType ~= 'cone' and g_currentAbility.targetType ~= 'self' and g_currentAbility.targetType ~= 'all' and g_currentAbility.targetType ~= 'map' and g_currentAbility.targetType ~= 'areatemplate' then
                local loc = g_currentAbility:try_get("casterLocOverride")

                if g_currentAbility.proximityTargeting and g_firstTarget ~= nil then
                    local firstTargetToken = dmhub.GetTokenById(g_firstTarget)
                    if firstTargetToken ~= nil then
                        loc = firstTargetToken.locsOccupying
                        range = ExecuteGoblinScript(g_currentAbility.proximityRange,
                            g_token.properties:LookupSymbol(), dmhub.unitsPerSquare,
                            "Calculate proximity")
                    end
                end

                ClearRadiusMarkers()

                m_allowedAltitudeCalculator = nil
                local customLocs = g_currentAbility:CustomTargetShape(g_token, range, g_currentSymbols, targets)

                if customLocs == nil then
                    local filterTargetPredicate = g_currentAbility:TargetLocPassesFilterPredicate(g_token,
                        g_currentSymbols)

                print("MovementRadius:: MARK", range)
                    AddRadiusMarker(loc, range, 'white', filterTargetPredicate)

                    m_allowedAltitudeCalculator = g_currentAbility:TargetLocMaxElevationChangeFunction(g_token,
                        g_currentSymbols)
                    m_altitudeController:SetClass("collapsed", m_allowedAltitudeCalculator == nil)
                else
                    AddCustomAreaMarker(customLocs, 'white')
                end
            elseif g_currentAbility.targetType == 'all' or g_currentAbility.targetType == 'areatemplate' then
                --synthesize a map hover event to highlight the area.
                assert(g_abilityController ~= nil)
                g_abilityController:FireEvent("maphover", nil, 'all')
            end
        end
    end
end

RegisterCustomActionBar(CreateActionBar)
--RegisterCustomActionBar(nil)
