local mod = dmhub.GetModLoading()

CharacterPanel = {}

local CreateCharacterPanel
local CreateBestiaryPanel

local g_panelStyles = {
    {
        selectors = { "triangle", "empty" },
        priority = 5,
        bgcolor = 'grey',
    },
    {
        selectors = { "triangle", 'parent:hover' },
        priority = 5,
        transitionTime = 0.1,
        bgcolor = "black",
    },
    {
        selectors = { "iconButton", "settingsButton", "parent:hover" },
    }
}

DockablePanel.Register {
    name = "Character",
	icon = "icons/standard/Icon_App_Character.png",
    minHeight = 140,
    vscroll = true,
    hideObjectsOutOfScroll = false,
    content = function()
        return CreateCharacterPanel()
    end,
    hasNewContent = function()
        return module.HasNovelContent("character")
    end,
}

DockablePanel.Register {
    name = "Bestiary",
	icon = "icons/standard/Icon_App_Bestiary.png",
    minHeight = 140,
    dmonly = true,
    vscroll = true,
    hideObjectsOutOfScroll = false,
    content = function()
        return CreateBestiaryPanel()
    end,
    hasNewContent = function()
        return module.HasNovelContent("monsters")
    end,
}

local CreateBestiaryNode

--character panels selected beyond the focused one.
local characterPanelsSelected = {}

dmhub.GetSelectedMonster = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.monsterid) then
        return nil
    end

    local monsterid = gui.GetFocus().data.monsterid
    local monster = assets.monsters[monsterid]
    local quantity = 1
    if monster.properties.minion then
        quantity = 4
    end

    return {
        monsterid = monsterid,
        quantity = quantity,
    }
end

dmhub.GetSelectedCharacters = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.charid) then
        return {}
    end

    local result = {}
    result[#result + 1] = gui.GetFocus().data.charid

    for _, p in ipairs(characterPanelsSelected) do
        if p.valid and p.data.charid then
            result[#result + 1] = p.data.charid
        end
    end

    return result
end

local AddCharacterPanelToSelection = function(panel)
    for _, p in ipairs(characterPanelsSelected) do
        if p == panel then
            return
        end
    end

    characterPanelsSelected[#characterPanelsSelected + 1] = panel
    panel:SetClass("selected", true)
end

local RemoveCharacterPanelSelection = function(panel)
    panel:SetClass("selected", false)
    for i, p in ipairs(characterPanelsSelected) do
        if p == panel then
            table.remove(characterPanelsSelected, i)
            return
        end
    end
end

local ClearCharacterPanelSelection = function()
    for _, p in ipairs(characterPanelsSelected) do
        if p.valid then
            p:SetClass("selected", false)
        end
    end

    characterPanelsSelected = {}
end


local BestiaryPanelHeight = 24

local IsMonsterNodeSelfOrChildOf
IsMonsterNodeSelfOrChildOf = function(nodeid, childid)
    if nodeid == childid then
        return true
    end

    if childid == '' or childid == nil then
        return false
    end

    local node = assets:GetMonsterNode(childid)
    if node == nil then
        return false
    end

    return IsMonsterNodeSelfOrChildOf(nodeid, node.parentNode)
end

--function which is used when we drag monsters around the bestiary.
mod.shared.CreateDragTargetFunction = function(node, getNodeFunction, refreshType)
    return function(element, target)
        if target ~= nil then
            if target:HasClass("ignoreDrag") then
                return
            end
            target:FireEvent('monsterDraggedOnto', node)
        end
        if target == nil or target.data.nodeid == nil then
            return
        end

        local targetNode = getNodeFunction(target.data.nodeid)
        if targetNode == nil then
            return
        end

        local targetOrd = target.data.ord

        if targetOrd == nil then
            local maxOrd = 0
            for i, v in ipairs(targetNode.children) do
                if v ~= node and v.ord > maxOrd then
                    maxOrd = v.ord
                end
            end

            targetOrd = maxOrd + 1
        end

        for i, v in ipairs(targetNode.children) do
            local newOrd = v.ord
            if newOrd >= targetOrd then
                newOrd = newOrd + 1
            end

            if v ~= node and v.ord ~= newOrd then
                v.ord = newOrd
                v:Upload()
            end
        end

        node.parentNode = target.data.nodeid
        node.ord = targetOrd
        node:Upload()
        assets:RefreshAssets(refreshType)
    end
end

CharacterPanel.CreateCharacterDetailsPanel = function(token)
    return gui.Panel {
        width = "100%",
        height = 1,
    }
end

local g_characterDetailsPanel = nil
local g_displayedAbility = nil

function CharacterPanel.DisplayAbility(token, ability, symbols)
    DockablePanel.LaunchPanelByName("Character", "show")
    if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid then
        g_displayedAbility = ability
        g_characterDetailsPanel:FireEventTree("showAbility", token, ability, symbols)
        return true
    end

    return false
end

function CharacterPanel.HighlightAbilitySection(options)
    if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid then
        g_characterDetailsPanel:FireEventTree("showAbilitySection", options)
    end
end

function CharacterPanel.HideAbility(ability)
    local ctrl = dmhub.modKeys['ctrl'] or false
    if ctrl then
        dmhub.Coroutine(function()
            while dmhub.modKeys['ctrl'] do
                coroutine.yield(0.1)
            end
            if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid and ability == g_displayedAbility then
                g_characterDetailsPanel:FireEvent("hideAbility")
            end
        end)
        return true
    end
    if g_characterDetailsPanel ~= nil and g_characterDetailsPanel.valid and ability == g_displayedAbility then
        g_characterDetailsPanel:FireEvent("hideAbility")
        return true
    end

    return false
end

local function AbilityDisplayPanel()
    local resultPanel
    resultPanel = gui.Panel {
        classes = { "collapsed" },
        width = "100%",
        height = "auto",
        showAbility = function(element, token, ability, symbols)
            local panel = nil

                print("ABILITY:: RENDER TRIGGER START", ability.typeName)
            if ability.typeName == "ActiveTrigger" then
                local triggerInfo = token.properties:GetTriggeredActionInfo(ability:GetText())
                print("ABILITY:: RENDER TRIGGER", ability:GetText(), json(triggerInfo))
                if triggerInfo ~= nil then
                    panel = triggerInfo:Render { width = 340 }
                    panel:SetClass("hidden", false)
                    panel:SetClass("collapsed", false)
                end
            elseif ability.typeName == "TriggeredAbilityDisplay" then
                panel = ability:Render { width = 340 }
            else

                if ability.categorization == "Trigger" then
                    local triggerInfo = token.properties:GetTriggeredActionInfo(ability.name)
                    if triggerInfo ~= nil then
                        panel = triggerInfo:Render { width = 340, token = token, ability = ability, symbols = symbols }
                    end
                end

                if panel == nil then
                    panel = CreateAbilityTooltip(ability:GetActiveVariation(token),
                        { token = token, symbols = symbols, width = 346 })
                end
            end

            if panel ~= nil then
                element.children = { panel }
            end
        end,
    }
    return resultPanel
end

local function CharacterDetailsPanel(token)
    local m_token = token

    local m_abilityDisplay = AbilityDisplayPanel()


    local m_characterPanel = CharacterPanel.CreateCharacterDetailsPanel(token)

    resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 26,
        styles = {
            gui.Style {
                selectors = { "collapsedByAbility" },
                collapsed = 1,
            }
        },
        data = {
            dirty = false,
        },

        create = function(element)
            g_characterDetailsPanel = element
        end,

        destroy = function(element)
            if g_characterDetailsPanel == element then
                g_characterDetailsPanel = nil
            end
        end,

        showAbility = function(element, token, ability, symbols)
            m_characterPanel:SetClass("collapsedByAbility", true)
            m_abilityDisplay:SetClass("collapsed", false)
        end,

        hideAbility = function(element)
            m_characterPanel:SetClass("collapsedByAbility", false)
            m_abilityDisplay:SetClass("collapsed", true)
        end,

        refreshTokenTree = function(element)
            if element.data.dirty == false then
                return
            end

            element.data.dirty = false

            if m_token ~= nil and m_token.valid then
                element:FireEventTree("refreshToken", m_token)
            end
        end,

        dirtyToken = function(element, tok, skipMonitor)
            local delay = 0.3
            if m_token ~= tok then
                delay = 0
            end

            m_token = tok

            if skipMonitor ~= true then
                element.monitorGame = m_token.monitorPath
            end

            if element.data.dirty == false or delay <= 0 then
                element.data.dirty = true
                element:ScheduleEvent("refreshTokenTree", delay)
            end
        end,

        refreshGame = function(element)
            if m_token ~= nil and m_token.properties ~= nil then
                element:FireEvent("dirtyToken", m_token, true)
            end
        end,

        m_characterPanel,
        m_abilityDisplay,

    }

    return resultPanel
end


CharacterPanel.ShowMovement = function()
    local creature = nil
    return gui.Panel {
        id = 'MovementPanel',
        bgimage = "panels/character-sheet/PartyFrame_Avatar_Frame.png",
        bgcolor = "white",
        valign = "bottom",
        width = "100% height",
        height = 40,
        flow = "none",

        --icon showing the current movement type.
        gui.Panel {
            width = "50%",
            height = "50%",
            halign = "center",
            valign = "center",
            bgcolor = "#d4d1ba",
            brightness = 0.2,
            border = 0,
            refreshCharacter = function(element, token)
                if token.properties == nil then
                    return
                end
                local info = token.properties.movementTypeById[token.properties:CurrentMoveType()]
                if info ~= nil then
                    element.bgimage = info.icon
                end
            end,
        },

        gui.Label {
            text = "MV",
            fontSize = 18,
            editable = false,
            halign = "center",
            valign = "center",

            events = {
                refresh = function(element)
                end,

                refreshCharacter = function(element, token)
                    if token.properties ~= nil then
                        element.text = MeasurementSystem.NativeToDisplayString(token.properties:CurrentMovementSpeed())
                    end
                end
            },

            style = {
                valign = "center",
                halign = "center",
                textAlignment = "center",
                pad = 0,
                bold = true,

                width = 30,
                height = 14,
            },
        },
    }
end


CharacterPanel.ShowArmorClass = function()
    local creature = nil
    return gui.Panel({
        id = 'ArmorClassPanel',
        bgimage = "panels/character-sheet/bg_01.png",
        border = 0,

        width = "90% height",
        height = 38,
        vmargin = 0,
        hmargin = 4,
        pad = 0,
        bgcolor = 'white',
        valign = 'top',
        halign = 'left',

        events = {
            refreshCharacter = function(element, token)
                creature = token.properties
                if token.properties == nil then
                    element:AddClass('hidden')
                else
                    element:RemoveClass('hidden')
                end
            end,
            linger = function(element)
                if creature ~= nil then
                    gui.Tooltip { text = creature:ResistanceDescription(), textAlignment = 'center', valign = 'top' } (
                    element)
                end
            end,
        },

        children = {
            gui.Label({
                text = "AC",
                fontSize = 18,
                editable = false,
                halign = "center",
                valign = "center",

                events = {
                    refresh = function(element)
                    end,

                    refreshCharacter = function(element, token)
                        if token.properties ~= nil then
                            local newValue = token.properties:ArmorClass()
                            element.text = string.format("%d", math.tointeger(newValue))
                        end
                    end
                },

                style = {
                    valign = "center",
                    halign = "center",
                    textAlignment = "center",
                    pad = 0,
                    bold = true,

                    width = 30,
                    height = 14,
                },
            }),
        },
    })
end

function CharacterPanel.ShowHitpoints()
    local currentToken = nil

    --temporary hitpoints
    local temporaryHitpointsPanel

    if GameSystem.haveTemporaryHitpoints then
        temporaryHitpointsPanel = gui.Label({
            id = 'TemporaryHitpoints',
            text = 'TMP',
            editable = true,
            style = {
                color = '#ccccff',
                halign = "center",
                valign = "center",
                width = "20%",
            },

            valign = "top",
            tmargin = 6,

            data = {
                token = nil
            },

            events = {
                change = function(element)
                    if element.data.token.properties ~= nil then
                        local token = element.data.token
                        local before = tonumber(token.properties:TemporaryHitpointsStr()) or 0
                        local after = tonumber(element.text) or 0
                        element.data.token.properties:SetTemporaryHitpoints(element.text)

                        if after > before then
                            element.data.token.properties:DispatchEvent("gaintempstamina", {})
                        end

                        element.data.token:Upload('Change Temporary Hitpoints')
                    end
                end,

                refreshCharacter = function(element, token)
                    element.data.token = token
                    if token.properties ~= nil then
                        local temphp = token.properties:TemporaryHitpointsStr()
                        element.text = temphp
                    end
                end,
            },

        })
    end



    return gui.Panel({
        id = 'HitpointsPanel',
        bgimage = 'panels/square.png',
        borderWidth = 2,
        borderColor = Styles.textColor,
        halign = "center",
        style = {
            bgcolor = 'black',
            width = 172,
            height = 80,
            flow = 'none',
            valign = 'top',
            halign = 'center',
            fontSize = "70%",
            textAlignment = "center",
            hmargin = 0,
        },

        events = {
            refreshCharacter = function(element, token)
                currentToken = token
                element:SetClass('hidden', token.properties == nil)
            end
        },

        children = {
            --main hitpoints display hp / maxhp --temp hp--
            gui.Panel({
                events = {
                    refreshCharacter = function(element, token)
                        if token.properties ~= nil then
                            element:RemoveClass('hidden')
                        else
                            element:AddClass('hidden')
                        end
                    end
                },

                style = {
                    width = "100%",
                    height = "50%",
                    halign = "center",
                    valign = "top",
                    flow = 'horizontal',
                    textOverflow = 'overflow',
                    textWrap = false,
                },

                children = {
                    gui.Panel {
                        valign = "top",
                        tmargin = 4,
                        halign = "center",
                        width = "auto",
                        flow = "horizontal",

                        gui.Label({
                            text = 'HP',
                            editable = true,
                            numeric = true,
                            halign = "center",
                            valign = "center",
                            height = "100%",
                            width = "auto",
                            minWidth = 30,

                            data = {
                                token = nil,
                            },

                            events = {

                                linger = function(element)
                                    if currentToken ~= nil and currentToken.properties ~= nil then
                                        element.tooltip = gui.StatsHistoryTooltip { description = "stamina", entries = currentToken.properties:GetStatHistory("stamina"):GetHistory() }
                                    end
                                end,

                                change = function(element)
                                    if element.data.token.properties ~= nil then
                                        element:SetClass("pending", true)
                                        element.data.token:ModifyProperties {
                                            description = "Set Stamina",
                                            execute = function()
                                                element.data.token.properties:SetCurrentHitpoints(element.text)
                                            end,
                                        }
                                    end
                                end,

                                refreshCharacter = function(element, token)
                                    if token.properties ~= nil then
                                        local hp = token.properties:CurrentHitpoints()
                                        element.text = string.format("%d", math.tointeger(hp))
                                    end

                                    element:SetClass("pending", false)

                                    element.data.token = token
                                end,
                            },

                        }),

                        gui.Label({
                            text = '/',
                            editable = false,
                            style = {
                                halign = "center",
                                valign = "center",
                                width = "10%",
                            },
                        }),


                        gui.Label({
                            id = 'MaxHitpoints',
                            text = 'MAXHP',
                            editable = false,
                            height = "100%",
                            style = {
                                halign = "center",
                                valign = "center",
                                width = "20%",
                            },

                            events = {
                                refreshCharacter = function(element, token)
                                    if token.properties ~= nil then
                                        local maxhp = token.properties:MaxHitpoints()
                                        element.text = string.format("%d", math.tointeger(maxhp))
                                    end
                                end,

                                --allow modification of max stamina with a complex to add custom modifiers.
                                press = function(element)
                                    local baseValue = currentToken.properties:BaseHitpoints()
                                    gui.PopupOverrideAttribute{
                                        parentElement = element,
                                        token = currentToken,
                                        attributeName = "Stamina",
                                        baseValue = baseValue,
                                        modifications = currentToken.properties:DescribeModifications("hitpoints", baseValue),
                                    }
                                end,

                                linger = function(element)
                                    if currentToken ~= nil and currentToken.properties ~= nil and element.popup == nil then
                                        local baseValue = currentToken.properties:BaseHitpoints()
                                        local modifications = currentToken.properties:DescribeModifications("hitpoints",
                                            baseValue)
                                        print("Modifications:", modifications)

                                        local panels = {}
                                        panels[#panels + 1] = gui.Label {
                                            text = string.format("Base Stamina: %d", baseValue),
                                            width = "auto",
                                            height = "auto",
                                            fontSize = 14,
                                        }
                                        for _, modification in ipairs(modifications) do
                                            local text = string.format("%s: %s", modification.key, modification.value)
                                            panels[#panels + 1] = gui.Label {
                                                text = text,
                                                width = "auto",
                                                height = "auto",
                                                fontSize = 14,
                                            }
                                        end

                                        local container = gui.Panel {
                                            width = "auto",
                                            height = "auto",
                                            flow = "vertical",
                                            children = panels,
                                        }

                                        element.tooltip = gui.TooltipFrame(container)


                                        --		--element.tooltip = gui.StatsHistoryTooltip{ description = "maximum stamina", entries = currentToken.properties:GetStatHistory("max_stamina"):GetHistory()}
                                    end
                                end,
                            },

                        }),
                    },

                    temporaryHitpointsPanel,

                },
            }),

            --bottom hitpoints panel
            gui.Panel({

                style = {
                    pad = 0,
                    width = "100%",
                    height = "40%",
                    fontSize = '100%',
                    halign = 'center',
                    valign = 'bottom',
                    vmargin = 0,
                    textAlignment = 'center',
                    flow = 'none',
                },

                children = {
                    gui.Input({
                        id = 'heal',
                        classes = { "inputFaded" },
                        text = '',
                        characterLimit = 8,
                        placeholderText = 'HEAL',
                        bgcolor = "white",
                        gradient = Styles.healthGradient,
                        events = {
                            change = function(element)
                                if element.data.token.properties ~= nil then
                                    element.data.token:ModifyProperties {
                                        description = "Apply Healing",
                                        execute = function()
                                            local num = tonumber(element.text)
                                            if num ~= nil then
                                                element.data.token.properties:Heal(round(num))
                                                element.text = ''
                                            end
                                        end,
                                    }
                                end
                            end,

                            refreshCharacter = function(element, token)
                                element.data.token = token
                            end,
                        },
                        selfStyle = {
                            bgcolor = '#007700',
                            pad = 0,
                            margin = 0,
                            width = "38%",
                            height = "100%",
                            fontSize = '70%',
                            halign = 'left',
                            valign = 'bottom',
                            textAlignment = 'center',
                        }
                    }),

                    gui.Input({
                        text = '',
                        classes = { "inputFaded" },
                        characterLimit = 8,
                        placeholderText = 'DAMAGE',
                        gradient = Styles.damagedGradient,
                        events = {
                            change = function(element)
                                if element.data.token.properties ~= nil then
                                    element.data.token:ModifyProperties {
                                        description = "Apply Damage",
                                        execute = function()
                                            element.data.token.properties:TakeDamage(element.text)
                                            element.text = ''
                                        end,
                                    }
                                end
                            end,

                            refreshCharacter = function(element, token)
                                element.data.token = token
                            end,

                        },
                        selfStyle = {
                            bgcolor = 'white',
                            pad = 0,
                            margin = 0,
                            width = "38%",
                            height = "100%",
                            fontSize = '70%',
                            halign = 'right',
                            valign = 'bottom',
                            textAlignment = 'center',
                        }
                    }),
                }
            }),

            --lifebar.
            gui.Panel {

                flow = "horizontal",
                valign = "bottom",
                vmargin = 36,
                hmargin = 0,

                width = "100%",
                pad = 0,
                hpad = 0,
                vpad = 0,

                borderWidth = 1,
                borderColor = Styles.textColor,
                height = 10,
                bgimage = "panels/square.png",
                bgcolor = "#444444ff",

                --stamina fill.
                gui.Panel {
                    data = {
                        charid = nil,
                        animating = false,
                        targetPercent = nil,
                        currentPercent = 1,
                        windedPercent = 0.5,
                        tempPercent = 0,
                        tempFill = nil,
                    },

                    styles = {
                        {
                            gradient = Styles.healthGradient,
                        },
                        {
                            selectors = { "winded" },
                            transitionTime = 0.2,
                            gradient = Styles.damagedGradient,
                        },
                    },

                    width = "100%-4",
                    height = 8,
                    bgimage = "panels/square.png",
                    bgcolor = "white",
                    borderWidth = 0,
                    lmargin = 1,
                    rmargin = 0,
                    vmargin = 1,
                    pad = 0,
                    hpad = 0,
                    vpad = 0,
                    halign = "left",
                    valign = "center",
                    create = function(element)
                        element.data.tempFill = element.parent.children[2]
                    end,
                    refreshCharacter = function(element, token)
                        if element.data.tempFill == nil then
                            element:FireEvent("create")
                        end

                        local newToken = element.data.charid ~= token.charid
                        element.data.charid = token.charid

                        local temphp = token.properties:TemporaryHitpoints()
                        local hp = token.properties:CurrentHitpoints()
                        local maxhp = token.properties:MaxHitpoints()

                        hp = clamp(hp, 0, maxhp)

                        local percent = hp / (maxhp + temphp)
                        local tempPercent = temphp / (maxhp + temphp)
                        local windedPercent = math.ceil(maxhp / 2) / (maxhp + temphp)

                        if percent ~= element.data.targetPercent or tempPercent ~= element.data.tempPercent or windedPercent ~= element.data.windedPercent then
                            element.data.targetPercent = percent
                            element.data.tempPercent = tempPercent
                            element.data.windedPercent = windedPercent

                            if newToken then
                                element:FireEvent("setwidth", percent, tempPercent, element.data.windedPercent)
                            elseif element.data.animating == false then
                                element.data.animating = true
                                element:ScheduleEvent("animatefill", 0.01)
                            end
                        end
                    end,

                    animatefill = function(element)
                        local seekSpeed = 0.02

                        if element.data.targetPercent == nil then
                            element.data.animating = false
                            return
                        end

                        local delta = element.data.targetPercent - element.data.currentPercent
                        if math.abs(delta) <= seekSpeed then
                            element.data.animating = false
                            element:FireEvent("setwidth", element.data.targetPercent, element.data.tempPercent,
                                element.data.windedPercent)
                            return
                        end

                        if delta > 0 then
                            element:FireEvent("setwidth", element.data.currentPercent + seekSpeed,
                                element.data.tempPercent, element.data.windedPercent)
                        else
                            element:FireEvent("setwidth", element.data.currentPercent - seekSpeed,
                                element.data.tempPercent, element.data.windedPercent)
                        end

                        element:ScheduleEvent("animatefill", 0.01)
                    end,

                    setwidth = function(element, percent, tempPercent, windedPercent)
                        element.selfStyle.width = string.format("%.2f%%-4", percent * 100)
                        element.data.tempFill.selfStyle.width = string.format("%.2f%%-4", tempPercent * 100)
                        element.data.currentPercent = percent

                        element:SetClass("winded", percent <= windedPercent)
                    end,
                },

                --temporary stamina fill.
                gui.Panel {

                    styles = {
                        {
                            gradient = Styles.tempGradient,
                        },
                    },

                    width = "0%",
                    height = 8,
                    bgimage = "panels/square.png",
                    bgcolor = "white",
                    borderWidth = 0,
                    hmargin = 0,
                    vmargin = 1,
                    pad = 0,
                    hpad = 0,
                    vpad = 0,
                    halign = "left",
                    valign = "center",

                    setwidth = function(element, percent)
                        element.selfStyle.width = string.format("%.2f%%-4", percent * 100)
                        element.data.currentPercent = percent
                    end,
                },

            },


            CharacterPanel.DecorateHitpointsPanel(),
        },
    })
end

CharacterPanel.CreateConditionsPanel = function(token)
    local activeOngoingEffects
    local addConditionButton = nil
    local ongoingEffectPanels = {}

    return gui.Panel {
        flow = "vertical",
        width = 172,
        height = "auto",
        halign = "right",
        valign = "top",

        refreshCharacter = function(element, tok)
            token = tok
        end,

        gui.Label {
            fontSize = 12,
            text = "Conditions",
            halign = "center",
            width = "auto",
            height = "auto",
            vmargin = 0,
            vpad = 0,
        },

        gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            wrap = true,
            refresh = function(element)
                if token == nil or not token.valid then
                    for _, p in ipairs(ongoingEffectPanels) do
                        p:SetClass("collapsed", true)
                    end
                    return
                end

                local creature = token.properties
                if creature == nil then
                    for _, p in ipairs(ongoingEffectPanels) do
                        p:SetClass("collapsed", true)
                    end
                    return
                end

                activeOngoingEffects = creature:ActiveOngoingEffects()

                element.selfStyle.maxWidth = (#activeOngoingEffects + 1) * 40

                local newPanels = false


                for i, cond in ipairs(activeOngoingEffects) do
                    local panel = ongoingEffectPanels[i]

                    if panel == nil then
                        local index = i

                        newPanels = true

                        panel = gui.DiamondButton {
                            bgimage = 'panels/square.png',
                            halign = "center",
                            width = 24,
                            height = 24,
                            refresh = function(element)
                                local cond = activeOngoingEffects[index]
                                if cond == nil then
                                    return
                                end

                                local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects")
                                local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]
                                element:FireEvent("icon", ongoingEffectInfo.iconid)
                                element:FireEvent("display", ongoingEffectInfo.display)
                            end,

                            linger = function(element)
                                local cond = activeOngoingEffects[index]
                                if cond == nil then
                                    return
                                end
                                local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects")
                                local ongoingEffectInfo = ongoingEffectsTable[cond.ongoingEffectid]

                                local stacksText = ""
                                if ongoingEffectInfo.stackable and cond.stacks > 1 then
                                    stacksText = string.format(" (%d stacks)", cond.stacks)
                                end

                                gui.Tooltip(string.format('%s%s: %s\n%s', ongoingEffectInfo.name, stacksText,
                                    ongoingEffectInfo.description, cond:DescribeTimeRemaining()))(element)
                            end,

                            press = function(element)
                                local cond = activeOngoingEffects[index]
                                token:ModifyProperties {
                                    description = "Remove Condition",
                                    execute = function()
                                        token.properties:RemoveOngoingEffect(cond.ongoingEffectid)
                                    end,
                                }
                            end,
                        }
                        ongoingEffectPanels[i] = panel
                    end
                end

                for i, p in ipairs(ongoingEffectPanels) do
                    p:SetClass("collapsed", i > #activeOngoingEffects)
                end

                if addConditionButton == nil then
                    newPanels = true

                    addConditionButton = gui.DiamondButton {
                        width = 24,
                        height = 24,
                        halign = "center",
                        color = Styles.textColor,

                        hover = gui.Tooltip("Add a condition"),
                        press = function(element)
                            local options = {}
                            local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

                            for k, effect in pairs(ongoingEffectsTable) do
                                --we only do effects that are the same name as their base conditions.
                                if effect.statusEffect and not effect:try_get("hidden", false) then
                                    options[#options + 1] = gui.Label {
                                        classes = { "conditionOption" },
                                        bgimage = "panels/square.png",
                                        text = effect.name,
                                        searchText = function(element, searchText)
                                            if string.starts_with(string.lower(element.text), searchText) then
                                                element:SetClass("collapsed", false)
                                            else
                                                element:SetClass("collapsed", true)
                                            end
                                        end,
                                        press = function(element)
                                            token:ModifyProperties {
                                                description = "Apply Condition",
                                                execute = function()
                                                    token.properties:ApplyOngoingEffect(k)
                                                end,
                                            }
                                            addConditionButton.popup = nil
                                        end,
                                    }
                                end
                            end

                            table.sort(options, function(a, b) return a.text < b.text end)

                            element.popup = gui.TooltipFrame(
                                gui.Panel {
                                    styles = {
                                        Styles.Default,

                                        {
                                            selectors = { "conditionOption" },
                                            width = "95%",
                                            height = 20,
                                            fontSize = 14,
                                            bgcolor = "clear",
                                            halign = "center",
                                        },
                                        {
                                            selectors = { "conditionOption", "searched" },
                                            bgcolor = "#ff444466",
                                        },
                                        {
                                            selectors = { "conditionOption", "hover" },
                                            bgcolor = "#ff444466",
                                        },
                                        {
                                            selectors = { "conditionOption", "press" },
                                            bgcolor = "#aaaaaa66",
                                        },

                                    },
                                    vscroll = true,
                                    flow = "vertical",
                                    width = 300,
                                    height = 800,

                                    gui.Label {
                                        fontSize = 18,
                                        bold = true,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        text = "Add Condition",
                                    },

                                    gui.Panel {
                                        bgimage = "panels/square.png",
                                        width = "90%",
                                        height = 1,
                                        bgcolor = Styles.textColor,
                                        halign = "center",
                                        vmargin = 8,
                                        gradient = Styles.horizontalGradient,
                                    },

                                    gui.Input {
                                        placeholderText = "Search...",
                                        hasFocus = true,
                                        width = "70%",
                                        hpad = 8,
                                        height = 20,
                                        fontSize = 14,
                                        data = {
                                            searchedOption = nil

                                        },
                                        edit = function(element)
                                            element.parent:FireEventTree("searchText", string.lower(element.text))

                                            element.data.searchedOption = nil

                                            local found = element.text == ""
                                            for i, option in ipairs(options) do
                                                if found == false and option:HasClass("collapsed") == false then
                                                    found = true
                                                    option:SetClass("searched", true)
                                                    element.data.searchedOption = option
                                                else
                                                    option:SetClass("searched", false)
                                                end
                                            end
                                        end,
                                        submit = function(element)
                                            if element.data.searchedOption ~= nil then
                                                element.data.searchedOption:FireEvent("press")
                                            end
                                        end,
                                    },

                                    gui.Panel {
                                        width = "100%",
                                        height = "auto",
                                        flow = "vertical",

                                        children = options,
                                    },
                                },

                                {
                                    halign = "left",
                                    valign = "bottom",
                                }
                            )
                        end,
                    }
                end

                if newPanels then
                    local children = {}
                    for _, child in ipairs(ongoingEffectPanels) do
                        children[#children + 1] = child
                    end
                    children[#children + 1] = addConditionButton
                    element.children = children
                end


            end,
        },
    }
end

function CharacterPanel.DecorateHitpointsPanel()
    return nil
end

function CharacterPanel.DecoratePortraitPanel(token)
    return nil
end

function CharacterPanel.SingleCharacterDisplaySidePanel(token)

    local characterDisplaySidebar

    local conditionsPanel = CharacterPanel.CreateConditionsPanel(token)

    local summaryPanel = gui.Panel {
        bgimage = "panels/square.png",
        flow = "horizontal",
        styles = {
            {
                halign = "left",
                valign = "center",
                pad = 2,
                height = "auto",
                width = "100%",
                bgcolor = '#000000aa',
                borderColor = '#000000ff',
                borderWidth = 2,
                flow = 'horizontal',
            },
        },

        --	gui.Panel({
        --		id = 'LeftPanel',
        --		style = {
        --			width = '40%',
        --			height = 'auto',
        --			halign = 'center',
        --			valign = "top",
        --			flow = 'none',
        --		},

        --		children = {

        --			gui.CreateTokenImage(nil, {
        --				width = 60,
        --				height = 60,
        --				valign = 'top',
        --				halign = 'center',

        --				refresh = function(element)
        --					if token == nil or not token.valid then
        --						return
        --					end

        --					element:FireEventTree("token", token)
        --				end,

        --			}),

        --			gui.Panel({
        --				id = 'CharacterSheetButton',
        --				bgimage = 'fantasy-icons/Enchantment_34_summoning_scroll.png',
        --				x = 16,
        --				y = 30,
        --				events = {
        --					refreshCharacter = function(element, token)
        --						element.data.token = token
        --					end,

        --					press = function(element)
        --						element.data.token:ShowSheet()
        --					end,
        --				},
        --				styles = {
        --				{
        --					bgcolor = 'white',
        --					borderWidth = 0,
        --					width = 24,
        --					height = 24,
        --				},
        --				{
        --					selectors = { 'hover' },
        --					transitionTime = 0.1,
        --					brightness = 1.5,
        --					scale = 1.1,
        --				}
        --				},
        --			}),

        --			gui.Panel({
        --				id = 'CharacterSheetButton',
        --				bgimage = 'fantasy-icons/Tailoring_44_little_bag.png',
        --				x = 0,
        --				y = 30,
        --				events = {
        --					refreshCharacter = function(element, token)
        --						element.data.token = token
        --					end,

        --					press = function(element)
        --						gamehud:ShowInventory(element.data.token)
        --					end,
        --				},
        --				styles = {
        --					{
        --						bgcolor = 'white',
        --						borderWidth = 0,
        --						width = 24,
        --						height = 24,
        --						halign = 'left',
        --					},
        --					{
        --						selectors = { 'hover' },
        --						transitionTime = 0.1,
        --						brightness = 1.5,
        --						scale = 1.1,
        --					}
        --				},
        --			}),

        --		},
        --	}),

        gui.Panel {
            id = "LeftPanel",
            valign = "top",
            width = "78% height",
            height = 140,
            bgimage = "panels/square.png",
            bgcolor = "white",
            lmargin = 16,
            borderWidth = 2,
            borderColor = Styles.textColor,

            refreshCharacter = function(element, token)
                element.bgimage = token.portrait
                element.selfStyle.imageRect = token:GetPortraitRectForAspect(78 * 0.01)
            end,

            CharacterPanel.DecoratePortraitPanel(token),

            gui.Panel {
                id = "ArmorClassMovementPanel",
                flow = "vertical",
                floating = true,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "top",
                rmargin = -22,
                CharacterPanel.ShowArmorClass(),
                CharacterPanel.ShowMovement(),
            },
        },

        gui.Panel({
            id = 'RightPanel',
            valign = "top",
            style = {
                width = '60%',
                height = 'auto',
                halign = 'center',
                flow = 'vertical',
                vmargin = 0,
            },

            children = {

                CharacterPanel.ShowHitpoints(),
                conditionsPanel,
            },
        }),

    }

    characterDisplaySidebar = gui.Panel {
        id = 'sidebar',

        width = "auto",
        height = "auto",
        halign = "left",
        flow = "vertical",

        events = {
            refresh = function(element)
                if token == nil or not token.valid then
                    return
                end

                element.data.displayedProperties = token.properties
                element.data.hasInit = true

                characterDisplaySidebar:FireEventTree('refreshCharacter', token)

            end,

            setToken = function(element, tok)
                token = tok
                element.data.token = token
            end,
        },

        data = {
            token = token,
            hasInit = false,
            displayedProperties = nil,
        },

        summaryPanel,
    }


    return characterDisplaySidebar
end

local CreateMonsterEntry = function(nodeid)
    local node = assets:GetMonsterNode(nodeid)
    local monster = node.monster.info

    local searchActive = false
    local matchesSearch = true
    local parentCollapsed = false

    local resultPanel = nil

    resultPanel = gui.Panel({
        classes = { "monsterEntry" },
        id = nodeid,
        bgimage = 'panels/square.png',
        draggable = nodeid ~= '',
        canDragOnto = function(element, target)
            if target:HasClass("ignoreDrag") then
                return true
            end

            return target:HasClass('monster-drag-target') and
                   not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,
        styles = {
            {
                valign = 'top',
                bgcolor = '#ffffff00',
                width = 300,
                height = BestiaryPanelHeight,
                borderWidth = 0,
                borderColor = 'black',
                flow = 'horizontal',
            },

            {
                selectors = { 'focus' },
                borderWidth = 2,
                borderColor = 'white',
            },

            {
                selectors = { 'focus' },
                inherit_selectors = true,
                bgcolor = Styles.textColor,
                brightness = 1.2,
                color = 'black',
            },

            {
                selectors = { "monsterEntry", 'hover' },
                bgcolor = Styles.textColor,
            },

        },

        events = {

            --render a tooltip of the monster.
            linger = function(element)
                local dock = element:FindParentWithClass("dock")

                local monsterEntry = assets.monsters[nodeid]
                if monsterEntry == nil then
                    return
                end

                local panel = monsterEntry:Render { width = 800 }

                if panel ~= nil then
                    element.tooltip = gui.TooltipFrame(
                        panel,
                        {
                            halign = dock.data.TooltipAlignment(),
                            valign = "center",
                            vscroll = true,
                            maxHeight = dmhub.screenDimensionsBelowTitlebar.y - 20,
                        }
                    )
                end
            end,

            beginDrag = function(element)
                --element:FireEvent('click')
            end,
            drag = mod.shared.CreateDragTargetFunction(node, function(nodeid) return assets:GetMonsterNode(nodeid) end,
                "Monsters"),

            dragging = function(element, target)
                if target == nil then
                    element.dragging = false
                    dmhub.SetDraggingMonster()
                    dmhub.Debug("DRAG:: DRAGGING MONSTER")
                end
            end,

            refreshAssets = function(element)
                monster = assets:GetMonsterNode(nodeid).monster.info

                if element:HasClass('focus') then
                    element:FireEvent('focus')
                end

                element.x = element.data.depth * 10
            end,

            press = function(element)
                if gui.GetFocus() == element then
                    gui.SetFocus(nil)
                else
                    gui.SetFocus(element)
                end
                element.popup = nil
            end,

            rightClick = function(element)
                if gui.GetFocus() ~= element then
                    gui.SetFocus(element)
                end

                --create the context menu for this folder.
                local menuItems = {}
                local parentElement = element

                --Delete and duplicate bestiary entries.
                if nodeid ~= '' then
                    menuItems[#menuItems + 1] = {
                        text = 'Edit Monster',
                        click = function(element)
                            local monster = node.monster

                            local token = monster:GetLocalGameBestiaryToken()
                            if token == nil then
                                monster:Upload()
                                dmhub.Coroutine(function()
                                    while token == nil do
                                        coroutine.yield(0.1)
                                        token = monster:GetLocalGameBestiaryToken()
                                    end
                                    token:ShowSheet()
                                end)
                            else
                                token:ShowSheet()
                            end

                            parentElement.popup = nil
                        end,
                    }


                    menuItems[#menuItems + 1] = {
                        text = 'Duplicate Monster',
                        click = function(element)
                            node:Duplicate()
                            parentElement.popup = nil
                        end,
                    }

                    menuItems[#menuItems + 1] = {
                        text = 'Delete Monster',

                        click = function(element)
                            node:Delete()
                            parentElement.popup = nil
                        end,
                    }

                    if devmode() then
                        local monster = node.monster
                        if monster.properties:has_key("import") then
                            menuItems[#menuItems + 1] = {
                                text = cond(monster.properties.import.override, 'Revert Override', 'Override Import'),
                                click = function(element)
                                    monster.properties.import.override = not monster.properties.import.override
                                    monster:Upload()
                                    parentElement.popup = nil
                                end,
                            }
                        end
                    end
                end

                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,
        },

        data = {
            ord = function()
                return "b" .. creature.GetTokenDescription(monster)
            end,

            nodeid = nodeid, --storing the nodeid with the panel for drag and drop.
            monsterid = nodeid, --makes it so this reports the monster id to GetSelectedMonster()

            search = function(text, matchedParent)
                searchActive = text ~= ''
                matchesSearch = matchedParent or text == '' or node:MatchesSearch(text)

                resultPanel:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))

                return matchesSearch
            end,

            --recursively turn search status off, for when we collapse a searched node. This doesn't globally disable
            --the search but makes us stop respecting it on this node.
            setSearchInactive = function(element)
                searchActive = false
            end,

            setParentCollapsed = function(element, newValue)
                parentCollapsed = newValue
                element:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))
            end,

            SetDepth = function(element, depth)
                element.data.depth = depth
            end,

            depth = 0,
        },

        children = {
            gui.Panel({
                bgimageStreamed = monster.portrait,
                bgimageTokenMask = monster.portraitFrame,

                selfStyle = {
                    imageRect = monster.portraitRect,
                },

                style = {
                    bgcolor = 'white',
                    halign = 'left',
                    valign = 'center',
                    width = BestiaryPanelHeight,
                    height = BestiaryPanelHeight,
                },

                events = {
                    refreshAssets = function(element)
                        element.bgimageStreamed = monster.portrait
                        element.bgimageTokenMask = monster.portraitFrame
                        element.selfStyle.imageRect = monster.portraitRect
                    end,
                },

                children = {
                    gui.Panel({
                        bgimage = monster.portraitFrame,
                        selfStyle = {
                            bgcolor = 'white',
                            hueshift = monster.portraitFrameHueShift,
                            width = BestiaryPanelHeight,
                            height = BestiaryPanelHeight,
                        }
                    })
                },
            }),

            gui.Label({
                classes = { "bestiaryLabel" },
                text = creature.GetTokenDescription(monster),
                gui.NewContentAlertConditional("monsters", nodeid),
                refreshAssets = function(element)
                    local desc = creature.GetTokenDescription(monster)
                    if devmode() then
                        if monster.properties:has_key("import") then
                            local postfix = " <size=60%><color=#bbbbff>(imported)"
                            if monster.properties.import.override then
                                postfix = " <size=60%><color=#ffbbbb>(overridden)"
                            end
                            element.text = desc .. postfix
                        else
                            element.text = desc
                        end
                    else
                        element.text = desc
                    end
                end
            })
        }
    })

    return resultPanel
end

local CreateBestiaryFolder = function(nodeid)
    local matchesSearch = true
    local searchActive = false
    local isCollapsed = true
    local parentCollapsed = false

    local node = assets:GetMonsterNode(nodeid)

    local folderPane = nil

    --the root folder gets additional UI, such as a search and ways to add objects.
    local clearSearchButton = nil
    local rootPanel = nil
    if nodeid == '' then
        isCollapsed = false

        local updateSearch = function(element)
            clearSearchButton:SetClass('collapsed', element.text == '')
            folderPane.data.search(element.text)
        end

        local searchInput = gui.Input {
            id = 'MonsterSearch',
            placeholderText = 'Search for Monsters...',
            editlag = 0.25,
            style = {
                fontSize = '50%',
                width = '80%',
                height = '80%',
                halign = 'left',
                valign = 'center',
            },

            events = {
                edit = updateSearch,
                change = updateSearch,
            }
        }

        clearSearchButton = gui.Button {
            icon = 'ui-icons/close.png',
            classes = { 'collapsed' },
            halign = 'left',
            valign = 'center',
            height = '75%',
            pad = 4,
            width = '100% height',

            events = {
                press = function(element)
                    searchInput.text = ''
                    updateSearch(searchInput)
                end,
            }
        }


        local addBestiaryEntryButton = gui.AddButton {
            id = "AddBestiaryEntryButton",
            halign = "right",
            width = 24,
            height = 24,
            hover = gui.Tooltip("Create a bestiary entry"),
            press = function(element)
                local menuItems = {}
                local parentElement = element

                menuItems[#menuItems + 1] = {
                    text = 'Create Monster',
                    click = function(element)
                        local guid = assets:CreateBestiaryEntry()

                        local newMonster = assets.monsters[guid]
                        newMonster.properties = monster.CreateNew()

                        newMonster:Upload()

                        local token = newMonster:GetLocalGameBestiaryToken()
                        if token == nil then
                            dmhub.Coroutine(function()
                                while token == nil do
                                    coroutine.yield(0.1)
                                    token = newMonster:GetLocalGameBestiaryToken()
                                end
                                token:ShowSheet()
                            end)
                        else
                            token:ShowSheet()
                        end

                        parentElement.popup = nil
                    end,
                }
                menuItems[#menuItems + 1] = {
                    text = "Create Follower",
                    click = function(element)
                        local guid = assets:CreateBestiaryEntry()

                        local newFollower = assets.monsters[guid]
                        newFollower.properties = follower.CreateNew()

                        newFollower:Upload()

                        local token = newFollower:GetLocalGameBestiaryToken()
                        if token == nil then
                            dmhub.Coroutine(function()
                                while token == nil do
                                    coroutine.yield(0.1)
                                    token = newFollower:GetLocalGameBestiaryToken()
                                end
                                token:ShowSheet()
                            end)
                        else
                            token:ShowSheet()
                        end

                        parentElement.popup = nil
                    end,
                }

                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,
        }


        rootPanel =
            gui.Panel {
                id = 'RootUIPanel',
                x = 10,
                style = {
                    height = 'auto',
                    width = '90%',
                    flow = 'vertical',
                },

                children = {
                    gui.Panel {
                        id = 'ObjectSearchPanel',
                        style = {
                            height = 30,
                            width = '100%',
                            flow = 'horizontal',
                        },
                        children = {
                            searchInput,
                            clearSearchButton,
                        },
                    },

                    addBestiaryEntryButton,
                },
            }
    end

    local triangle = nil
    triangle = gui.Panel({
        bgimage = 'panels/triangle.png',
        classes = { "triangle", cond(nodeid == "", "collapsed") },
        styles =
        {
            {
                bgcolor = Styles.textColor,
                width = 8,
                height = 8,
                halign = 'left',
                margin = 5,
                rotate = 90,
                valign = "center",
            },

            {
                selectors = { 'expanded' },
                transitionTime = 0.2,
                rotate = 0,
            },
            {
                selectors = { 'search' },
                transitionTime = 0,
                rotate = 0,
            },
        },

        swallowPress = true,

        events = {
            create = function(element)
                element:SetClass('expanded', not isCollapsed)
                element:SetClass('empty', #node.children < 1)
            end,
            refreshAssets = function(element)
                element:SetClass('empty', #node.children < 1)
            end,
            press = function(element)
                if element:HasClass("collapsed") then
                    --the triangle itself isn't usable.
                    return
                end

                isCollapsed = not isCollapsed

                if searchActive then
                    isCollapsed = true
                    folderPane.data.setSearchInactive(folderPane)
                    element:SetClass('search', false)
                    searchActive = false

                    if clearSearchButton ~= nil then --is root panel, clear search.
                        clearSearchButton:FireEvent('press')
                    end
                end

                triangle:SetClass('expanded', not isCollapsed)
                folderPane.data.refreshCollapsed(folderPane)

                if not isCollapsed then
                    folderPane:FireEvent('expand')
                end
            end,
        },
    })


    local headerPanel = gui.Panel({

        bgimage = 'panels/square.png',
        classes = { 'headerPanel', 'monster-drag-target' },
        dragTarget = true,

        draggable = nodeid ~= '',
        canDragOnto = function(element, target)
            return target:HasClass('monster-drag-target') and
            not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,

        selfStyle = {
            valign = 'top',
            halign = 'left',
            width = "100%",
            height = BestiaryPanelHeight,
            flow = 'horizontal',
        },

        styles = {
            {
                borderWidth = 0,
                bgcolor = '#ffffff00',
            },
            {
                selectors = { 'hover', 'headerPanel' },
                bgcolor = Styles.textColor,
            },
            {
                selectors = { 'drag-target' },
                bgcolor = '#ffffaa66',
                transitionTime = 0.2,
            },
            {
                selectors = { 'drag-target-hover' },
                borderWidth = 2,
                borderColor = 'white',
                bgcolor = '#ffffaaaa',
                transitionTime = 0.2,
            },
        },

        data = {
            nodeid = nodeid, --store the node id here so it can be conveniently accessed when dragging.
        },

        events = {
            refreshAssets = function(element)
            end,

            drag = mod.shared.CreateDragTargetFunction(node, function(nodeid) return assets:GetMonsterNode(nodeid) end,
                "Monsters"),
        },

        children = {
            triangle,

            gui.Label({
                text = 'Bestiary',
                classes = { "bestiaryLabel" },
                editableOnDoubleClick = (nodeid ~= ''), --all folders except the root Bestiary folder can be renamed.
                characterLimit = 24,
                events = {
                    change = function(element)
                        node.description = element.text
                        node:Upload()
                    end,
                    refreshAssets = function(element)
                        element.text = node.description
                    end,
                    press = function()
                        triangle:FireEvent('press')
                    end,
                    editname = function(element)
                        element:BeginEditing()
                    end,
                },
            }),
        },
    })

    local dragPanels = {}

    local elements = {}

    folderPane = gui.Panel({
        selfStyle = {
            pivot = { x = 0, y = 1 },
            pad = 0,
            margin = 0,
            width = "100%",
            height = 'auto',
            valign = 'top',
            flow = 'vertical',
        },

        classes = { cond(isCollapsed, "collapsed-anim"), "bestiaryPanel", "ignoreDrag" },
        dragTarget = true,

        data = {
            ord = function()
                return "a" .. node.description
            end,

            toggleCollapsed = function(element)
                triangle.events.press(triangle)
            end,
            isCollapsed = function()
                return isCollapsed
            end,

            setParentCollapsed = function(element, newValue)
                parentCollapsed = newValue
                element:SetClass('collapsed-anim', (parentCollapsed and not searchActive) or (not matchesSearch))
            end,

            --recursively turn search status off, for when we collapse a searched node. This doesn't globally disable
            --the search but makes us stop respecting it on this node.
            setSearchInactive = function(element)
                searchActive = false
                for k, v in pairs(elements) do
                    v.data.setSearchInactive(v)
                end
            end,

            refreshCollapsed = function(element)
                if rootPanel ~= nil then
                    rootPanel:SetClass('collapsed-anim', isCollapsed)
                end

                for k, v in pairs(elements) do
                    v.data.setParentCollapsed(v, isCollapsed)
                end

                for i, v in ipairs(dragPanels) do
                    v:SetClass('collapsed-anim', isCollapsed or searchActive)
                end

                --element.selfStyle.height = (BestiaryPanelHeight+4) * numElements
            end,

            search = function(text, matchedParent)
                local selfMatches = matchedParent or node:MatchesSearch(text)
                matchesSearch = selfMatches or (nodeid == '') --root node always matches searches.
                for k, el in pairs(elements) do
                    if el.data.search(text, selfMatches) then
                        matchesSearch = true
                    end
                end

                searchActive = text ~= ''

                folderPane:SetClass('collapsed-anim', (parentCollapsed and not searchActive) or (not matchesSearch))

                triangle:SetClass('search', searchActive)

                for i, v in ipairs(dragPanels) do
                    v:SetClass('collapsed-anim', isCollapsed or searchActive)
                end

                return matchesSearch
            end,

            SetDepth = function(element, depth)
                element.data.depth = depth
            end,

            depth = 0,
        },

        events = {
            press = function(element)
                element.popup = nil --clear any context menu on click.
            end,
            rightClick = function(element)
                --create the context menu for this folder.
                local menuItems = {}
                local parentElement = element

                if nodeid ~= "" then
                    --Create a new folder as a child of this one.
                    menuItems[#menuItems + 1] = {
                        text = 'Rename Folder',
                        click = function(element)
                            headerPanel:FireEventTree("editname")
                            parentElement.popup = nil
                        end,
                    }
                end

                --Create a new folder as a child of this one.
                menuItems[#menuItems + 1] = {
                    text = 'Create Folder',

                    click = function(element)
                        local maxOrd = 0
                        for i, entry in ipairs(node.children) do
                            if entry.ord > maxOrd then
                                maxOrd = entry.ord
                            end
                        end

                        assets:UploadNewMonsterFolder({
                            description = 'New Folder',
                            parentFolder = nodeid,
                            ord = maxOrd + 1,
                        })

                        parentElement.popup = nil
                    end,
                }

                --Delete folder option.
                if nodeid ~= '' then
                    menuItems[#menuItems + 1] = {
                        text = 'Delete Folder',

                        click = function(element)
                            local CountMonsterEntries = nil
                            CountMonsterEntries = function(n)
                                local result = 0
                                for i, v in ipairs(n.children) do
                                    if v.folder ~= nil then
                                        result = result + CountMonsterEntries(v)
                                    else
                                        result = result + 1
                                    end
                                end

                                return result
                            end

                            local numChildren = CountMonsterEntries(node)

                            if numChildren == 0 then
                                --delete an empty folder without prompting.
                                node:Delete()
                            else
                                local msg = string.format(
                                'Do you really want to delete %s and the %d monster entries within?', node.description,
                                    numChildren)
                                if numChildren == 1 then
                                    msg = string.format('Do you really want to delete %s and the monster entry within?',
                                        node.description)
                                end

                                gamehud:ModalMessage({
                                    title = 'Delete Folder',
                                    message = msg,
                                    options = {
                                        {
                                            text = 'Okay',
                                            execute = function()
                                                node:Delete()
                                            end,
                                        },
                                        {
                                            text = 'Cancel',
                                        },
                                    }
                                })
                            end

                            parentElement.popup = nil
                        end,
                    }
                end


                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,

            refreshAssets = function(element)
                node = assets:GetMonsterNode(nodeid)


                local newElements = {}
                for i, v in ipairs(node.children) do
                    if not v.hidden then
                        if elements[v.id] == nil then
                            newElements[v.id] = CreateBestiaryNode(v)
                        else
                            newElements[v.id] = elements[v.id]
                        end

                        newElements[v.id].data.SetDepth(newElements[v.id], element.data.depth + 1)
                    end
                end

                local newChildren = { headerPanel, rootPanel }

                local newNodes = {}
                for i, v in ipairs(node.children) do
                    if not v.hidden then
                        newNodes[#newNodes + 1] = newElements[v.id]
                    end
                end

                table.sort(newNodes, function(a, b) return a.data.ord() < b.data.ord() end)

                for _, c in ipairs(newNodes) do
                    newChildren[#newChildren + 1] = c
                end

                elements = newElements

                element.children = newChildren

                element.x = element.data.depth * 10

                element.data.refreshCollapsed(element)
            end,
        },

        children = {
            headerPanel,
            rootPanel,
        }
    })

    return folderPane
end

CreateBestiaryNode = function(node)
    if node.folder ~= nil then
        return CreateBestiaryFolder(node.id)
    else
        return CreateMonsterEntry(node.id)
    end
end

--similar to a bestiary entry but is an entry for a live character.
CharacterPanel.CreateCharacterEntry = function(charid)
    local token = dmhub.GetCharacterById(charid)
    local creature = token.properties

    if creature == nil then
        return
    end

    local resultPanel = nil

    local novelContentAlert = nil
    if module.HasNovelContent("character", charid) then
        novelContentAlert = gui.NewContentAlert { x = -14 }
    end

    local playerStar = gui.Panel {
        width = 16,
        height = 16,
        valign = "center",
        bgimage = "icons/icon_simpleshape/icon_simpleshape_31.png",
        bgcolor = "#ffffaaff",
        prepareRefresh = function(element)
            resultPanel.data.primaryCharacter = token.playerControlledAndPrimary
            element:SetClass("hidden", not resultPanel.data.primaryCharacter)
        end,
    }

    local clickTime = nil


    resultPanel = gui.Panel {
        bgimage = 'panels/square.png',
        draggable = true,
        canDragOnto = function(element, target)
            return false --target:HasClass('monster-drag-target') and not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,
        styles = {
            {
                color = '#ccccccff',
                valign = 'top',
                bgcolor = '#ffffff00',
                width = 300,
                height = BestiaryPanelHeight,
                borderWidth = 0,
                borderColor = 'black',
                flow = 'horizontal',
            },

            {
                selectors = { 'selected' },
                inherit_selectors = true,
                bgcolor = Styles.textColor,
                color = 'black',
            },

            {
                selectors = { 'focus' },
                borderWidth = 2,
                borderColor = 'white',
            },

            {
                selectors = { 'focus' },
                inherit_selectors = true,
                bgcolor = Styles.textColor,
                color = 'black',
            },

            {
                selectors = { 'hover' },
                bgcolor = Styles.textColor,
            },

        },

        events = {

            dragging = function(element, target)
                element.dragging = false
                dmhub.SetDraggingMonster()
                dmhub.Debug("DRAG:: DRAGGING MONSTER")
            end,

            --render a tooltip of the character.
            hover = function(element)
                local dock = element:FindParentWithClass("dock")

                local panel = token:Render {}
                if panel ~= nil then
                    element.tooltip = gui.TooltipFrame(
                        panel,
                        {
                            halign = dock.data.TooltipAlignment(),
                            valign = "center",
                        }
                    )
                end
            end,

            refresh = function(element)

            end,

            moduleInstalled = function(element)
                local hasNovel = module.HasNovelContent("character", charid)
                if hasNovel and novelContentAlert == nil then
                    novelContentAlert = gui.NewContentAlert { x = -14 }
                    resultPanel:AddChild(novelContentAlert)
                elseif (not hasNovel) and novelContentAlert ~= nil then
                    novelContentAlert:DestroySelf()
                    novelContentAlert = nil
                end
            end,

            --fired by the 'sheet' command (i.e. 'c button')
            command = function(element, cmd)
                if cmd == "sheet" then
                    local tok = dmhub.GetCharacterById(charid)
                    if tok ~= nil then
                        tok:ShowSheet()
                    end
                end
            end,

            press = function(element)
                if clickTime ~= nil and clickTime > dmhub.Time() - 0.4 then
                    --double-click
                    clickTime = nil
                    dmhub.CenterOnToken(charid, function()
                        dmhub.SelectToken(charid)
                    end)
                    gui.SetFocus(nil)
                    return
                end

                clickTime = dmhub.Time()

                local addSelection = dmhub.modKeys['ctrl'] or dmhub.modKeys['shift']
                if addSelection and element:HasClass("selected") then
                    RemoveCharacterPanelSelection(element)
                elseif gui.GetFocus() == element then
                    if addSelection and #characterPanelsSelected > 0 then
                        gui.SetFocus(characterPanelsSelected[#characterPanelsSelected])
                        RemoveCharacterPanelSelection(gui.GetFocus())
                    else
                        ClearCharacterPanelSelection()
                        gui.SetFocus(nil)
                    end
                else
                    if addSelection then
                        if gui.GetFocus() ~= nil and gui.GetFocus().data.charid then
                            AddCharacterPanelToSelection(gui.GetFocus())

                            --if shift is held, then select all characters between.
                            if dmhub.modKeys['shift'] and gui.GetFocus().parent == element.parent then
                                local selecting = false
                                for _, child in ipairs(gui.GetFocus().parent.children) do
                                    if child == gui.GetFocus() or child == element then
                                        selecting = not selecting
                                    elseif selecting then
                                        AddCharacterPanelToSelection(child)
                                    end
                                end
                            end
                        end
                    else
                        ClearCharacterPanelSelection()
                    end

                    gui.SetFocus(element)
                end
                element.popup = nil
            end,

            rightClick = function(element)
                if gui.GetFocus() ~= element and not element:HasClass("selected") then
                    --if this isn't selected, then treat it as a selection click.
                    element:FireEvent("press")
                end

                --create the context menu for this folder.
                local menuItems = {}
                local parentElement = element

                --go to the token's character sheet.
                menuItems[#menuItems + 1] = {
                    text = "Character Sheet",

                    click = function(element)
                        local tok = dmhub.GetCharacterById(charid)
                        if tok ~= nil then
                            tok:ShowSheet()
                        end
                        parentElement.popup = nil
                    end,
                }

                --Teleport to token, same as double click.
                local tok = dmhub.GetCharacterById(charid)
                if tok ~= nil and tok.valid and tok.hasTokenOnAnyMap then
                    menuItems[#menuItems + 1] = {
                        text = "Select Token",

                        click = function(element)
                            local canCenter = dmhub.CenterOnToken(charid, function()
                                dmhub.SelectToken(charid)
                            end)
                            gui.SetFocus(nil)
                            parentElement.popup = nil
                        end,
                    }
                end

                menuItems[#menuItems + 1] = {
                    text = cond(token.invisibleToPlayers, 'Make Visible to Players', 'Make Invisible to Players'),

                    click = function(element)
                        local invisible = not token.invisibleToPlayers

                        --make this operate on all selected characters.
                        for _, charid in ipairs(dmhub.GetSelectedCharacters()) do
                            local tok = dmhub.GetCharacterById(charid)
                            if tok ~= nil then
                                tok.invisibleToPlayers = invisible
                            end
                        end

                        parentElement.popup = nil
                    end,
                }


                --delete the token.
                menuItems[#menuItems + 1] = {
                    text = "Delete Character",

                    click = function(element)
                        local charids = {charid}
                        for _, c in ipairs(characterPanelsSelected) do
                            if c.data.charid ~= charid then
                                charids[#charids + 1] = c.data.charid
                            end
                        end
                        gamehud:ModalMessage {
                            title = cond(#charids == 1, "Delete Character?", "Delete Characters?"),
                            message = cond(#charids == 1, "Are you sure you want to delete this character? They will be gone forever.",
                              string.format("Are you sure you want to delete these %d characters? They will be gone forever.", #charids)),
                            options = {
                                {
                                    text = "Delete",
                                    execute = function()
                                        game.DeleteCharacters(charids)
                                        gui.SetFocus(nil)
                                    end,
                                },
                                {
                                    text = "Cancel",
                                    execute = function()
                                    end,
                                },
                            }
                        }
                        parentElement.popup = nil
                    end,
                }


                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,

            focus = function(element)
            end,

            defocus = function(element, newFocus)
                if (not newFocus) or not newFocus.data.charid then
                    --if we aren't transferring focus to another character panel then clear the selection.
                    ClearCharacterPanelSelection()
                end
            end,
        },

        data = {
            charid = charid,
            token = token,
            primaryCharacter = false,
        },

        children = {

            playerStar,
            novelContentAlert,

            gui.CreateTokenImage(token, {
                width = BestiaryPanelHeight,
                height = BestiaryPanelHeight,
                halign = "left",

                refresh = function(element)
                    if token == nil or not token.valid then
                        return
                    end

                    element:FireEventTree("token", token)
                end,
            }),

            gui.Label({
                classes = { "bestiaryLabel" },
                halign = "left",
                text = creature.GetTokenDescription(token),
                refresh = function(element)
                    local desc = creature.GetTokenDescription(token)
                    local playerName = token.playerNameOrNil
                    if playerName ~= nil then
                        local color = token.playerColor.tostring
                        desc = string.format("%s (<color=%s>%s</color>)", desc, color, playerName)
                    end
                    element.text = desc
                    element:SetClass("invisible", token.invisibleToPlayers)
                end,
            })
        }
    }

    return resultPanel
end

CharacterPanel.PopulatePartyMembers = function(element, party, partyMembers, memberPanes)

    local children = {}
    local newMemberPanes = {}

    for _, charid in ipairs(partyMembers) do
        local child = memberPanes[charid] or CharacterPanel.CreateCharacterEntry(charid)
        newMemberPanes[charid] = child
        child:FireEventTree("prepareRefresh")
        children[#children + 1] = child
    end

    table.sort(children, function(a, b)
        local aname = a.data.token.playerNameOrNil
        local bname = b.data.token.playerNameOrNil
        if aname == nil and bname == nil then
            return a.data.token.description < b.data.token.description
        end

        if aname == nil then
            return false
        end

        if bname == nil then
            return true
        end

        if aname == bname then
            return cond(a.data.primaryCharacter, 0, 1) < cond(b.data.primaryCharacter, 0, 1)
        end

        return aname < bname
    end)

    element.children = children

    return newMemberPanes
end

--create a folder with character entries for all characters in a party.
--If partyid is nil it will create a 'party' for all monsters on the map.
CharacterPanel.CreatePartyCharacters = function(partyid)
    local resultPanel

    local isCollapsed = partyid == nil or partyid == "graveyard"

    local party
    local partyMembers
    local partyName = ""

    local RefreshParty = function()
        if partyid == nil then
            party = nil
            local tokens = dmhub.GetTokens {
                unaffiliated = true,
            }
            partyMembers = {}
            for _, tok in ipairs(tokens) do
                partyMembers[#partyMembers + 1] = tok.charid
            end

            partyName = "Director Controlled (This map)"
        elseif partyid == "graveyard" then
            party = nil
            local tokens = dmhub.despawnedTokens
            partyMembers = {}
            for _, tok in ipairs(tokens) do
                partyMembers[#partyMembers + 1] = tok.charid
            end

            partyName = "Dead Monsters"
        else
            party = dmhub.GetTable(Party.tableName)[partyid]
            partyMembers = dmhub.GetCharacterIdsInParty(partyid)
            partyName = party.name
        end
    end

    RefreshParty()

    local folderPane

    local triangle = nil
    triangle = gui.Panel({
        classes = { "triangle" },
        bgimage = 'panels/triangle.png',
        styles =
        {
            {
                bgcolor = 'white',
                width = 8,
                height = 8,
                halign = 'left',
                margin = 5,
                rotate = 90,
                valign = "center",
            },
            {
                selectors = { 'expanded' },
                transitionTime = 0.2,
                rotate = 0,
            },
        },

        swallowPress = true,

        events = {
            create = function(element)
                element:SetClass('expanded', not isCollapsed)
                element:SetClass('empty', #partyMembers < 1)
            end,
            refresh = function(element)
                element:SetClass('empty', #partyMembers < 1)
            end,
            press = function(element)
                if element:HasClass("collapsed") then
                    --the triangle itself isn't usable.
                    return
                end

                isCollapsed = not isCollapsed

                triangle:SetClass('expanded', not isCollapsed)
                folderPane:FireEvent("refreshCollapsed")

                if not isCollapsed then
                    folderPane:FireEvent('expand')
                end
            end,
        },
    })

    local memberPanes = {}

    local headerPanel = gui.Panel {

        bgimage = 'panels/square.png',
        classes = { 'monster-drag-target', 'headerPanel' },
        dragTarget = true,

        draggable = false,
        canDragOnto = function(element, target)
            return false --target:HasClass('monster-drag-target') and not IsMonsterNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
        end,

        selfStyle = {
            valign = 'top',
            halign = 'left',
            width = "100%",
            height = BestiaryPanelHeight,
            flow = 'horizontal',
        },

        styles = {
            {
                borderWidth = 0,
                bgcolor = '#ffffff00',
            },
            {
                selectors = { 'hover', 'headerPanel' },
                bgcolor = Styles.textColor,
            },
            {
                selectors = { 'drag-target' },
                bgcolor = '#ffffaa44',
                transitionTime = 0.2,
            },
            {
                selectors = { 'drag-target-hover' },
                borderWidth = 2,
                borderColor = 'white',
                bgcolor = Styles.textColor,
                brightness = 1.4,
                transitionTime = 0.2,
            },
        },

        events = {
            refreshAssets = function(element)
            end,

            press = function(element)
                if partyid == nil then
                    return
                end

                local setFocus = false
                element:FireEventOnParents("ClearCharacterPanelSelection")
                for k, p in pairs(memberPanes) do
                    if not setFocus then
                        gui.SetFocus(p)
                        setFocus = true
                    else
                        element:FireEventOnParents("AddCharacterPanelToSelection", p)
                    end
                end

                if isCollapsed then
                    triangle:FireEvent("press")
                end
            end,

            rightClick = function(element)
                if #memberPanes == 0 and party ~= nil then
                    element.popup = gui.ContextMenu {
                        entries = {
                            {
                                text = "Delete Party",
                                click = function()
                                    party.hidden = true
                                    dmhub.SetAndUploadTableItem(Party.tableName, party)
                                    element.popup = nil
                                end,

                            }
                        },
                    }
                elseif partyid == "graveyard" then
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Clear Dead Monsters",
                                click = function()
                                    local tokens = dmhub.despawnedTokens
                                    local charids = {}
                                    local objectTokens = dmhub.allObjectTokens
                                    for _,tok in ipairs(tokens) do
                                        charids[#charids+1] = tok.charid

                                        local corpse = tok:FindCorpse()
                                        if corpse ~= nil then
                                            corpse.objectInstance:Destroy()
                                        end
                                    end
                                    game.DeleteCharacters(charids)
                                    element.popup = nil
                                end,
                            }
                        }
                    }
                end
            end,

        },

        children = {
            triangle,

            gui.Label {
                text = partyName,
                classes = { "bestiaryLabel" },
                editableOnDoubleClick = party ~= nil,
                characterLimit = 24,
                events = {
                    change = function(element)
                        party.name = element.text
                        dmhub.SetAndUploadTableItem(Party.tableName, party)
                    end,
                    refresh = function(element)
                        element.text = partyName
                    end,
                },
            },

            gui.SettingsButton {
                classes = { cond(party == nil, "hidden") },
                width = 16,
                height = 16,
                swallowPress = true,
                press = function(element)
                    Compendium.ShowModalEditDialog(Party, party.id)
                end,
            }
        },
    }


    folderPane = gui.Panel {
        classes = { cond(isCollapsed, "collapsed") },
        flow = "vertical",
        width = "auto",
        height = "auto",

        refreshCollapsed = function(element)
            element:SetClass("collapsed", isCollapsed)
        end,

        create = function(element)
            element:FireEvent("refresh")
        end,

        refresh = function(element)
            if isCollapsed or resultPanel.data.parentCollapsed then
                return
            end

            memberPanes = CharacterPanel.PopulatePartyMembers(element, party, partyMembers, memberPanes)
        end,

        expand = function(element)
            element:FireEvent("refresh")
        end,

    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "auto",
        height = "auto",

        data = {
            parentCollapsed = false,
            ord = function()
                if party == nil then
                    return 999999
                end
                return party.ord
            end,
        },


        --events accepted to change selection of characters.
        AddCharacterPanelToSelection = function(element, panel)
            AddCharacterPanelToSelection(panel)
        end,

        ClearCharacterPanelSelection = function(element)
            ClearCharacterPanelSelection()
        end,

        refresh = function(element)
            RefreshParty()
        end,

        headerPanel,
        folderPane,

    }

    return resultPanel
end


local CreateBestiaryAndPartyPanel = function(noBestiary)
    local partyPanels = {}

    local bestiaryPanel = nil
    if not noBestiary then
        bestiaryPanel = CreateBestiaryFolder('')
    end
    local resultPanel
    resultPanel = gui.Panel {
        flow = "vertical",
        width = "auto",
        height = "auto",

        refresh = function(element)
            if element:HasClass("collapsed") then
                --we don't allow refresh events through if we are collapsed.
                element:HaltEventPropagation()
            end
        end,

        refreshAssets = function(element)
            local newPartyPanels = {}
            local allParties = GetAllParties()
            local children = {}
            for _, k in ipairs(allParties) do
                newPartyPanels[k] = partyPanels[k] or CharacterPanel.CreatePartyCharacters(k)

                children[#children + 1] = newPartyPanels[k]
            end

            newPartyPanels['unaffiliated'] = partyPanels['unaffiliated'] or CharacterPanel.CreatePartyCharacters(nil)
            newPartyPanels['graveyard'] = partyPanels['graveyard'] or CharacterPanel.CreatePartyCharacters('graveyard')
            children[#children + 1] = newPartyPanels['unaffiliated']
            children[#children + 1] = newPartyPanels['graveyard']

            table.sort(children, function(a, b) return a.data.ord() < b.data.ord() end)


            children[#children + 1] = gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",

                gui.AddButton {
                    bgimage = "icons/icon_app/icon_app_18.png",
                    halign = "right",
                    width = 24,
                    height = 24,
                    hover = gui.Tooltip("Create a party"),
                    press = function(element)
                        local newParty = Party.CreateNew()
                        dmhub.SetAndUploadTableItem(Party.tableName, newParty)
                        Compendium.ShowModalEditDialog(Party, newParty.id)
                        resultPanel:FireEventTree("refreshAssets")
                    end,
                },

                gui.AddButton {
                    id = "AddCharacterButton",
                    halign = "right",
                    width = 24,
                    height = 24,
                    hover = gui.Tooltip("Create a character"),

                    data = {
                        newchar = "",
                        newcharTime = 0,
                    },
                    press = function(element)
                        local createChar = function(chartype)
                            local charid = game.CreateCharacter("character", chartype)
                            element.data.newchar = charid
                            element.data.newcharTime = dmhub.Time()
                            element.monitorGame = string.format("/characters/%s", charid)
                            mod.shared.CompleteTutorial("Create a Character")
                        end

                        local menuItems = {}

                        local characterTypes = dmhub.GetTable(CharacterType.tableName)
                        for k, v in pairs(characterTypes) do
                            if not v:try_get("hidden", false) then
                                local chartype = k
                                menuItems[#menuItems + 1] = {
                                    text = string.format("Create %s", v.name),
                                    click = function()
                                        element.popup = nil
                                        createChar(chartype)
                                    end,
                                }
                            end
                        end

                        if #menuItems == 0 then
                            createChar()
                        elseif #menuItems == 1 then
                            menuItems[1].click()
                        else
                            element.popup = gui.ContextMenu {
                                entries = menuItems,
                            }
                        end
                    end,
                    refreshGame = function(element)
                        if element.data.newchar ~= "" and element.data.newcharTime > dmhub.Time() - 2 then
                            local tok = dmhub.GetCharacterById(element.data.newchar)
                            if tok ~= nil then
                                tok:ShowSheet("Appearance")
                            end
                        end

                        element.data.newchar = ""
                        element.monitorGame = nil
                    end,
                },
            }


            children[#children + 1] = bestiaryPanel
            partyPanels = newPartyPanels

            element.children = children
        end,

        bestiaryPanel,
    }

    return resultPanel
end

CharacterPanel.CreateMultiEdit = function()
    local resultPanel
    local m_tokens = {}

    resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tokens = function(element, tokens)
            m_tokens = tokens
            if #tokens <= 1 then
                element:SetClass("collapsed", true)
            else
                element:SetClass("collapsed", false)
            end
        end,

        gui.Panel {
            width = "30%",
            height = 28,
            pad = 0,
            bgimage = "panels/square.png",
            bgcolor = 'white',
            gradient = Styles.healthGradient,
            borderWidth = 2,
            borderColor = Styles.textColor,
            halign = "center",
            valign = "center",

            gui.Input {
                bgcolor = 'clear',
                color = Styles.textColor,
                bold = true,
                pad = 0,
                margin = 0,
                borderWidth = 0,
                borderColor = "clear",
                width = "100%",
                height = "100%",
                fontSize = 14,
                placeholderAlpha = 1,
                placeholderText = "Heal All",
                textAlignment = 'center',
                change = function(element)
                    for _, tok in ipairs(m_tokens) do
                        tok:ModifyProperties {
                            description = "Heal",
                            execute = function()
                                tok.properties:Heal(element.text)
                            end,
                        }
                    end
                    element.text = ''
                end,
            },
        },

        gui.Panel {
            width = "30%",
            height = 28,
            pad = 0,
            bgimage = "panels/square.png",
            bgcolor = 'white',
            gradient = Styles.damagedGradient,
            borderWidth = 2,
            borderColor = Styles.textColor,
            halign = "center",
            valign = "center",

            gui.Input {
                bgcolor = 'clear',
                color = Styles.textColor,
                bold = true,
                borderWidth = 0,
                borderColor = "clear",
                pad = 0,
                margin = 0,
                width = "100%",
                height = "100%",
                fontSize = 14,
                placeholderAlpha = 1,
                placeholderText = "Damage All",
                textAlignment = 'center',
                change = function(element)
                    for _, tok in ipairs(m_tokens) do
                        tok:ModifyProperties {
                            description = "Damage",
                            execute = function()
                                tok.properties:TakeDamage(element.text)
                            end,
                        }
                    end
                    element.text = ''
                end,
            },
        },

        gui.Button {
            width = "30%",
            height = 28,
            fontSize = 14,
            styles = {
                {
                    selectors = { "~hover" },
                    priority = 10,
                    bgcolor = "#aaaaaa",
                    gradient = Styles.conditionGradient,
                },
            },
            text = "Add Condition",
            press = function(element)
                CharacterPanel.AddConditionMenu {
                    tokens = m_tokens,
                    button = element,
                }
            end,
        }



    }

    return resultPanel
end

CreateCharacterPanel = function()
    local multiEditPanel = nil
    local tokenPanels = {}
    local singleTokenDetailsPanel = nil
    local bestiaryPanel = nil
    if dmhub.isDM then
        bestiaryPanel = CreateBestiaryAndPartyPanel(true) --no actual bestiary
        bestiaryPanel:FireEventTree("refreshAssets")
        bestiaryPanel:FireEventTree("refresh")
    end
    local resultPanel = gui.Panel {
        styles = {
            g_panelStyles,
            {
                selectors = { "bestiaryLabel" },
                color = Styles.textColor,
                fontFace = "dubai",
                fontSize = 14,
                bold = true,
                height = 'auto',
                width = 'auto',
                minWidth = 200,
                halign = 'left',
                valign = 'center',
            },
            {
                selectors = { "bestiaryLabel", "focus" },
                color = "black",
            },
            {
                selectors = { "bestiaryLabel", "parent:hover" },
                color = "black",
            },
            {
                selectors = { "bestiaryLabel", "invisible" },
                italics = true,
            },
        },

        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorAssets = cond(bestiaryPanel ~= nil, "Monsters"),
        refreshAssets = function(element)
            if bestiaryPanel ~= nil then
                bestiaryPanel:FireEventTree("refreshAssets")
            end
        end,
        refresh = function(element)
            local hasVisible = false
            local newChildren = {}
            local createdNew = false
            local tokens = dmhub.tokenInfo.selectedOrPrimaryTokens
            if #tokens > 1 then
                if multiEditPanel == nil then
                    createdNew = true
                    multiEditPanel = CharacterPanel.CreateMultiEdit()
                end
            end

            if multiEditPanel ~= nil then
                newChildren[#newChildren + 1] = multiEditPanel
                multiEditPanel:FireEvent("tokens", tokens)
            end

            table.sort(tokens, function(a,b)
                return creature.GetTokenDescription(a) < creature.GetTokenDescription(b)
            end)

            for i, token in ipairs(tokens) do
                local panel = tokenPanels[i]
                if panel == nil then
                    panel = CharacterPanel.SingleCharacterDisplaySidePanel(token)
                    tokenPanels[i] = panel
                    createdNew = true
                end

                panel:SetClass("collapsed", not token.valid)

                if token.valid then
                    hasVisible = true
                    panel:FireEvent("setToken", token)
                end
            end

            for i = 1, #tokenPanels do
                if i > #tokens then
                    tokenPanels[i]:SetClass("collapsed", true)
                end
                newChildren[#newChildren + 1] = tokenPanels[i]
            end

            local panelTitle = nil

            if #tokens == 1 then
                if singleTokenDetailsPanel == nil then
                    singleTokenDetailsPanel = CharacterDetailsPanel(tokens[1])
                    createdNew = true
                end

                singleTokenDetailsPanel:SetClass("collapsed", false)
                if tokens[1] ~= nil and tokens[1].properties ~= nil then
                    singleTokenDetailsPanel:FireEvent("dirtyToken", tokens[1])
                end

                panelTitle = creature.GetTokenDescription(tokens[1])
            elseif singleTokenDetailsPanel ~= nil then
                singleTokenDetailsPanel:SetClass("collapsed", true)
            end

            element:FireEventOnParents("title", panelTitle)

            if singleTokenDetailsPanel ~= nil then
                newChildren[#newChildren + 1] = singleTokenDetailsPanel
            end

            if bestiaryPanel ~= nil then
                bestiaryPanel:SetClass("collapsed", hasVisible)
                newChildren[#newChildren + 1] = bestiaryPanel
            end

            --if createdNew or #newChildren ~= #element.children then
            element.children = newChildren
            --end

        end,

        bestiaryPanel,
    }

    return resultPanel
end

CreateBestiaryPanel = function()
    local tokenPanels = {}
    local singleTokenDetailsPanel = nil
    local bestiaryPanel = nil
    bestiaryPanel = CreateBestiaryFolder('')
    bestiaryPanel:FireEventTree("refreshAssets")
    bestiaryPanel:FireEventTree("refresh")
    local resultPanel = gui.Panel {
        styles = {
            g_panelStyles,
            {
                selectors = { "bestiaryLabel" },
                color = Styles.textColor,
                fontFace = "dubai",
                uppercase = true,
                fontSize = 14,
                bold = true,
                height = 'auto',
                width = 'auto',
                minWidth = 200,
                halign = 'left',
                valign = 'center',
            },
            {
                selectors = { "bestiaryLabel", "parent:hover" },
                color = "black",
            },
            {
                selectors = { "bestiaryLabel", "invisible" },
                color = "#d4d1bacc",
                italics = true,
            },
        },

        flow = "vertical",
        width = "100%",
        height = "auto",
        monitorAssets = cond(bestiaryPanel ~= nil, "Monsters"),
        refreshAssets = function(element)
            if bestiaryPanel ~= nil then
                bestiaryPanel:FireEventTree("refreshAssets")
            end
        end,
        refresh = function(element)

        end,

        bestiaryPanel,
    }

    return resultPanel
end
