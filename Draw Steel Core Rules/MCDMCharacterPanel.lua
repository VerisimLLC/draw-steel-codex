local mod = dmhub.GetModLoading()

CharacterPanel.CreateConditionsPanel = function(token)
    return nil
end

function CharacterPanel.AddConditionMenu(args)
    local m_tokens = args.tokens
    local m_button = args.button

    local options = {}
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}

    for k, effect in unhidden_pairs(conditionsTable) do
        if effect.showInMenus then
            local children = {}
            if effect.indefiniteDuration then

                local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                local riders = {}
                for riderid,rider in unhidden_pairs(ridersTable) do
                    if rider.condition == k and rider.showAsMenuOption then
                        children[#children+1] = gui.Label{
                            halign = "right",
                            swallowPress = true,
                            classes = { "conditionSuboption" },
                            bgimage = true,
                            text = rider.name,
                            press = function(element)
                                element.parent:FireEvent("press", "eoe", riderid)
                            end,
                        }
                    end
                end

            else
                children = {
                    gui.Label {
                        halign = "right",
                        swallowPress = true,
                        classes = { "conditionSuboption" },
                        bgimage = true,
                        text = "EoT",
                        press = function(element)
                            element.parent:FireEvent("press", "eot")
                        end,
                    },

                    gui.Label {
                        halign = "right",
                        swallowPress = true,
                        classes = { "conditionSuboption" },
                        bgimage = true,
                        text = "Save",
                        press = function(element)
                            element.parent:FireEvent("press", "save")
                        end,
                    },
                    gui.Label {
                        halign = "right",
                        swallowPress = true,
                        classes = { "conditionSuboption" },
                        bgimage = true,
                        text = "EoE",
                        press = function(element)
                            element.parent:FireEvent("press", "eoe")
                        end,
                    },
                }
            end

            options[#options + 1] = gui.Label {
                classes = { "conditionOption" },
                bgimage = "panels/square.png",
                text = effect.name,
                flow = "horizontal",
                searchText = function(element, searchText)
                    if string.starts_with(string.lower(element.text), searchText) then
                        element:SetClass("collapsed", false)
                    else
                        element:SetClass("collapsed", true)
                    end
                end,
                press = function(element, durationOverride, riderid)
                    if (not durationOverride) and effect.indefiniteDuration then
                        durationOverride = "eoe"
                    end
                    for _,tok in ipairs(m_tokens) do
                        tok:BeginChanges()
                        tok.properties:InflictCondition(k, { riders = {riderid}, duration = (durationOverride or "eot") })
                        tok:CompleteChanges("Apply Condition")
                    end
                    m_button.popup = nil
                end,

                children = children,
            }
        end
    end

    table.sort(options, function(a, b) return a.text < b.text end)

    local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    local statusEffectOptions = {}
    for k, effect in unhidden_pairs(ongoingEffectsTable) do
        if effect.statusEffect then
            statusEffectOptions[#statusEffectOptions + 1] = gui.Label {
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
                    for _,tok in ipairs(m_tokens) do
                        tok:ModifyProperties{
                            description = tr("Apply Status Effect"),
                            combine = true,
                            execute = function()
                                if tok == nil or not tok.valid then
                                    return
                                end
                                tok.properties:ApplyOngoingEffect(k)
                            end,
                        }
                    end
                    m_button.popup = nil
                end,
            }
        end
    end

    table.sort(statusEffectOptions, function(a, b) return a.text < b.text end)

    m_button.popup = gui.TooltipFrame(
        gui.Panel {
            styles = {
                Styles.Default,

                {
                    selectors = {"conditionSuboption"},
                    textAlignment = "center",
                    fontSize = 12,
                    bgcolor = Styles.backgroundColor,
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    height = 18,
                    minWidth = 40,
                    width = "auto",
                },
                {
                    selectors = {"conditionSuboption", "hover"},
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor,
                },
                {
                    selectors = {"conditionSuboption", "press"},
                    brightness = 1.2,
                },

                {
                    selectors = { "conditionOption" },
                    width = "95%",
                    height = 20,
                    fontSize = 14,
                    color = Styles.textColor,
                    bgcolor = "clear",
                    halign = "center",
                },
                {
                    selectors = { "conditionOption", "searched" },
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor
                },
                {
                    selectors = { "conditionOption", "hover" },
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor
                },
                {
                    selectors = { "conditionOption", "press" },
                    brightness = 1.2,
                },

                {
                    selectors = { "title" },
                    fontSize = 16,
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "left",
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

            gui.Label {
                classes = { "title" },
                text = "Conditions",
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",

                children = options,
            },

            gui.Label {
                classes = { "title" },
                text = "Status Effects",
            },

            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",

                children = statusEffectOptions,
            },
        },

        {
            halign = "left",
            valign = "bottom",
        }
    )
end

local function PersistencePanel(m_token)


    local persistenceLabel = gui.Label{
        text = "Persistent Abilities",
        width = "100%",
        height = "auto",
        fontSize = 16,
        halign = "left",
        valign = "center",
        hpad = 4,
        color = Styles.textColor,
    }

    local errorLabel = gui.Label{
        classes = {"collapsed"},
        text = "Too many persistent abilities. You must end some.",
        width = "100%",
        height = "auto",
        fontSize = 14,
        halign = "left",
        hpad = 4,
        color = "Red",
    }


    local m_panelsCache = {}

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            gui.Style{
                selectors = {"persistentPanel"},

                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
                hmargin = 4,
                hpad = 4,

                width = "100%",
                height = "auto",
                fontSize = 14,
                flow = "horizontal",
            },
            gui.Style{
                selectors = {"button"},

                priority = 100,
                halign = "right",
                fontSize = 12,
                height = "100%",
                width = 50,
                height = 18,
                rmargin = 12,
                lmargin = 0,
                vmargin = 0,
            },

            gui.Style{
                selectors = {"button", "pulse"},
                transitionTime = 0.4,
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
            },
            gui.Style{
                selectors = {"activateButton", "~parent:active"},
                hidden = 1,
            },
        },

        persistenceLabel,
        errorLabel,

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end

            local persistentAbilities = m_token.properties:try_get("persistentAbilities")
            if persistentAbilities == nil or #persistentAbilities == 0 then
                element:SetClass("collapsed", true)
                return
            end

            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                element:SetClass("collapsed", true)
                return
            end

            local totalCost = 0

            local newPanelsCache = {}
            local children = {persistenceLabel}

            for i,entry in ipairs(persistentAbilities) do
                local guid = entry.guid
                if entry.combatid == q.guid then
                    totalCost = totalCost + entry.cost

                    local panel = m_panelsCache[entry.guid] or gui.Label{
                        classes = {"persistentPanel"},
                        bgimage = true,
                        text = string.format("%s--%d", entry.abilityName, entry.cost),

                        data = {
                            targetingMarkers = nil,
                        },

                        think = function(element)
                            element:FireEventTree("pulsePersist")
                        end,

                        refresh = function(element)
                            local q = dmhub.initiativeQueue
                            if q == nil or q.hidden then
                                element.thinkTime = nil
                                return
                            end

                            if m_token == nil or (not m_token.valid) then
                                return
                            end

                            local active = false
                            if m_token.properties:IsOurTurn() and (q.round ~= entry.round or q.turn ~= entry.turn) then
                                --we need to activate this entry since it's a new turn and it hasn't been used.
                                active = true
                                element.thinkTime = 1
                            else
                                element.thinkTime = nil
                            end

                            element:SetClass("active", active)
                        end,

                        hover = function(element)
                            element:FireEvent("clearTargetingMarkers")

                            local abilities = m_token.properties:GetActivatedAbilities{excludeGlobal = true}
                            for _,ability in ipairs(abilities) do
                                if ability.name == entry.abilityName then
                                    local panel = CreateAbilityTooltip(ability, {width = 540, token = m_token})
                                    element.tooltip = panel

                                    if ability:Persistence().mode == "recast_target" then
                                        for _,targetid in ipairs(entry.targets or {}) do
                                            local targetToken = dmhub.GetTokenById(targetid)
                                            if targetToken ~= nil then
                                                element.data.targetingMarkers = element.data.targetingMarkers or {}
                                                element.data.targetingMarkers[#element.data.targetingMarkers+1] = dmhub.MarkLineOfSight(m_token, targetToken)
                                            end
                                        end
                                    end

                                    break
                                end
                            end
                        end,

                        dehover = function(element)
                            element:FireEvent("clearTargetingMarkers")
                        end,

                        destroy = function(element)
                            element:FireEvent("clearTargetingMarkers")
                        end,

                        clearTargetingMarkers = function(element)
                            if element.data.targetingMarkers ~= nil then
                                for _,m in ipairs(element.data.targetingMarkers) do
                                    m:Destroy()
                                end
                                element.data.targetingMarkers = nil
                            end
                        end,

                        --[[ gui.Button{
                            classes = {"activateButton", "button"},
                            text = "Persist",
                            pulsePersist = function(element)
                                element:PulseClass("pulse")
                            end,
                            click = function(element)
                                local abilities = m_token.properties:GetActivatedAbilities{excludeGlobal = true, bindCaster = true}
                                for _,ability in ipairs(abilities) do
                                    if ability.name == entry.abilityName then
                                        ability.OnFinishCast = function(ability)
                                            local q = dmhub.initiativeQueue
                                            if q == nil or q.hidden then
                                                return
                                            end
                                            local persistentAbilities = m_token.properties:try_get("persistentAbilities", {})
                                            for _,entry in ipairs(persistentAbilities) do
                                                if entry.guid == guid then
                                                    m_token:ModifyProperties{
                                                        description = "Update Persistent Ability",
                                                        undoable = false,
                                                        execute = function()
                                                            entry.turn = q.turn
                                                            entry.round = q.round
                                                        end,
                                                    }
                                                end
                                            end
                                        end

                                        local persistenceMode = ability:Persistence().mode
                                        ability.persistence = nil
                                        ability.resourceNumber = entry.cost
                                        ability.actionResourceId = cond(persistenceMode == "recast_maneuver", CharacterResource.maneuverResourceId, "none")
                                        ability.promptOverride = string.format(tr("Persistence: Recast %s"), ability.name)

                                        local targeting = "prompt"

                                        local targets = nil

                                        if persistenceMode == "recast_target" then
                                            targeting = "inherit"
                                            targets = {}
                                            for _,targetid in ipairs(entry.targets or {}) do
                                                local targetToken = dmhub.GetTokenById(targetid)
                                                if targetToken ~= nil then
                                                    targets[#targets+1] = {
                                                        token = targetToken,
                                                    }
                                                end
                                            end
                                        elseif persistenceMode == "recast_with_one_target" then
                                            ability.numTargets = 1
                                        end

                                        ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(m_token, ability, m_token, targeting, {}, { targets = targets })
                                        return
                                    end
                                end
                            end,
                        }, ]]

                        gui.Button{
                            classes = {"deleteButton", "button"},
                            text = "Stop",
                            --[[ pulsePersist = function(element)
                                element:PulseClass("pulse")
                            end, ]]
                            click = function(element)
                                m_token.properties:EndPersistentAbilityById(guid)
                            end,
                        },
                    }

                    newPanelsCache[guid] = panel
                    children[#children+1] = panel
                end
            end

            children[#children+1] = errorLabel

            errorLabel:SetClass("collapsed", totalCost <= 2)

            element.children = children
            m_panelsCache = newPanelsCache

            if #children <= 2 then
                element:SetClass("collapsed", true)
            else
                element:SetClass("collapsed", false)
            end
        end,

    }

    return resultPanel
end


local function RoutinesPanel(m_token)

    local m_routinePanels = {}

    local startDiv = gui.Divider{}
    local endDiv = gui.Divider{}

    local routinesLabel = gui.Label{
        text = "Routines",
        width = "100%",
        height = "auto",
        fontSize = 16,
        halign = "left",
        valign = "center",
        hpad = 4,
        color = Styles.textColor,
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        minHeight = 20,
        styles = {
            {
                selectors = {"routine"},
                color = Styles.textColor,
                bgcolor = Styles.backgroundColor,
                hmargin = 4,
                hpad = 4,
            },
            {
                selectors = {"routine", "hover"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
                brightness = 1.2,
            },
            {
                selectors = {"routine", "selected"},
                bgcolor = Styles.textColor,
                color = Styles.backgroundColor,
                brightness = 1,
            },
        },

        startDiv,
        routinesLabel,
        endDiv,

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end
            local routines = m_token.properties:GetRoutines()
            if routines == nil or #routines == 0 then
                element:SetClass("collapsed", true)
                return
            end

            local initiative = dmhub.initiativeQueue

            local routinesSelected = m_token.properties:try_get("routinesSelected")

            element:SetClass("collapsed", false)

            local newPanels = {}

            local nonePanel = gui.Label{
                text = "None",
                classes = {"routine"},
                bgimage = true,
                width = "100%",
                height = "auto",
                fontSize = 14,
                flow = "horizontal",
                press = function(element)
                    m_token:ModifyProperties{
                        description = tr("Select Routine"),
                        execute = function()
                            m_token.properties.routinesSelected = nil
                        end,
                    }
                end,
                refresh = function(element)
                    if m_token == nil or not m_token.valid then
                        return
                    end

                    local routinesSelected = m_token.properties:try_get("routinesSelected")
                    element:FireEvent("selected", routinesSelected == nil)
                end,
            }

            local routinesSelected = m_token.properties:try_get("routinesSelected") or {}

            local children = {startDiv, routinesLabel, nonePanel}

            for routineIndex,routine in ipairs(routines) do
                local panel = m_routinePanels[routine.guid] or gui.Panel{
                    data = {
                        selected = false,
                    },
                    classes = {"routine"},
                    bgimage = true,
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",

                    gui.Label{
                        classes = {"routine"},
                        text = routine.name,
                        inherit_selectors = true,
                        bgimage = true,
                        width = "50%",
                        height = "auto",
                        fontSize = 14,
                        hover = function(element)
                            element.tooltip = gui.TooltipFrame(routine:Render{})
                        end,
                        press = function(element)
                            m_token:ModifyProperties{
                                description = tr("Select Routine"),
                                execute = function()
                                    local selected = m_token.properties:get_or_add("routinesSelected", {})
                                    if selected[routine.guid] then
                                        selected[routine.guid] = nil
                                    else
                                        selected[routine.guid] = ServerTimestamp()
                                    end
                                    m_token.properties.routinesSelected = selected
                                end,
                            }
                        end,
                    },

                    selectionChanged = function(element, selected)
                        element:SetClass("selected", selected)
                        local labelChild = element.children[1]
                        labelChild:SetClass("selected", selected)
                        
                        if not selected then
                            element.children = {labelChild}
                            return
                        end

                        element.children = {
                            labelChild,
                            gui.VisibilityPanel{
                                valign = "center",
                                halign = "right",
                                opacity = 1,
                                visible = true,
                                bgcolor = "black",
                                press = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(routine.name))
                                    settings.hide = not settings.hide

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            m_token.properties:SetAuraDisplaySetting(routine.name, settings)
                                        end,
                                    }
                                end,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element:FireEvent("visible", not m_token.properties:GetAuraDisplaySetting(routine.name).hide)
                                end,
                            },
                            gui.PercentSlider{
                                valign = "center",
                                halign = "right",
                                hmargin = 6,
                                value = m_token.properties:GetAuraDisplaySetting(routine.name).opacity,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element.value = m_token.properties:GetAuraDisplaySetting(routine.name).opacity
                                end,
                                preview = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(routine.name))
                                    settings.opacity = element.value
                                    m_token.properties:SetAuraDisplaySetting(routine.name, settings)
                                    m_token:UpdateAuras()
                                end,
                                confirm = function(element)
                                    --set it to off to force upload.
                                    m_token.properties:SetAuraDisplaySetting(routine.name, nil)

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(routine.name))
                                            settings.opacity = element.value
                                            m_token.properties:SetAuraDisplaySetting(routine.name, settings)
                                        end,
                                    }
                                end,
                            }
                        }
                    end,
                }

                local selected = (routinesSelected ~= nil and routinesSelected[routine.guid])
                if selected ~= panel.data.selected then
                    panel.data.selected = selected
                    panel:FireEvent("selectionChanged", selected)
                end

                children[#children+1] = panel
                newPanels[routine.guid] = panel
            end

            children[#children+1] = endDiv
            m_routinePanels = newPanels

            element.children = children
        end,
    }

    return resultPanel
end

local function AurasAffectingPanel(m_token)
    local resultPanel

    local m_panelsCache = {}

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            local newPanelsCache = {}
            local children = {}
			local aurasTouching = m_token.properties:GetAurasAffecting(m_token) or {}
            for i,info in ipairs(aurasTouching) do
                local auraInstance = info.auraInstance

                local panel = m_panelsCache[auraInstance.guid] or gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 4,
                    bgimage = "panels/square.png",
                    bgcolor = "black",
                    opacity = 0.8,

                    hover = function(element)
						local tooltip = CreateAuraTooltip(auraInstance)
                        element.tooltip = gui.TooltipFrame(tooltip)

						local area = auraInstance:GetArea()
						if area ~= nil then
							element.data.mark = {
								area:Mark{
									color = "white",
									video = "divinationline.webm",
								}
							}
						end
                    end,

					dehover = function(element)
						if element.data.mark ~= nil then
							for _,mark in ipairs(element.data.mark) do
								mark:Destroy()
							end
							element.data.mark = nil
						end
					end,



                    gui.DiamondButton{
                        bgimage = 'panels/square.png',
                        halign = "left",
                        width = 24,
                        height = 24,
                        hmargin = 6,
                        valign = "center",
                        icon = auraInstance.aura.iconid,
                        create = function(element)
                            element:FireEvent("display", auraInstance.aura.display)
                        end,
                    },

                    gui.Label{
                        height = "auto",
                        width = 120,
                        textWrap = false,
                        halign = "left",
                        valign = "center",
                        rmargin = 4,
                        fontSize = 14,
                        minFontSize = 8,
                        color = Styles.textColor,
                        text = string.format("%s (Aura)", auraInstance.aura.name),
                    },
                }

                newPanelsCache[auraInstance.guid] = panel

                children[#children+1] = panel
            end

            m_panelsCache = newPanelsCache
            element.children = children
        end,
    }

    return resultPanel
end

local function AurasEmittingPanel(m_token)

    local m_auraPanels = {}

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                element:SetClass("collapsed", true)
                return
            end

            local creature = m_token.properties
            if creature == nil then
                element:SetClass("collapsed", true)
                return
            end

            local newChildren = {}
            local newPanels = {}
            local auras = creature:try_get("auras", {})
            for _,aura in ipairs(auras) do
                local auraid = aura.guid
                local panel = m_auraPanels[auraid] or gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    vmargin = 4,
                    bgimage = "panels/square.png",
                    bgcolor = "clear",

                    gui.DiamondButton{
                        bgimage = 'panels/square.png',
                        halign = "left",
                        width = 24,
                        height = 24,
                        hmargin = 6,
                        valign = "center",
                        icon = aura.aura.iconid,
                        create = function(element)
                            element:FireEvent("display", aura.aura.display)
                        end,
                    },

                    gui.Label{
                        height = "auto",
                        width = 120,
                        textWrap = false,
                        halign = "left",
                        valign = "center",
                        rmargin = 4,
                        fontSize = 14,
                        minFontSize = 8,
                        color = Styles.textColor,
                        text = string.format("%s (Aura)", aura.aura.name),
                    },

                    gui.DeleteItemButton{
                        width = 12,
                        height = 12,

                        lmargin = 24,
                        halign = "left",
                        valign = "center",
                        data = {
                            entry = nil,
                        },
                        press = function(element)
                            m_token:BeginChanges()
                            m_token.properties:RemoveAura(auraid)
                            m_token:CompleteChanges("Remove Aura")
                        end,
                    },
                }

                newPanels[aura.guid] = panel
                newChildren[#newChildren+1] = panel
            end

            local ongoingEffectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName)
            local ongoingeffects = creature:try_get("ongoingEffects", {})
            for _, effect in ipairs(ongoingeffects) do
                local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                for _, mod in ipairs(effectInfo.modifiers) do
                    if mod:has_key("aura") then
                        local auraid = mod.aura.guid
                        local panel = m_auraPanels[auraid] or gui.Panel{
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            vmargin = 4,
                            bgimage = "panels/square.png",
                            bgcolor = "clear",

                            gui.DiamondButton{
                                bgimage = 'panels/square.png',
                                halign = "left",
                                width = 24,
                                height = 24,
                                hmargin = 6,
                                valign = "center",
                                icon = mod.aura.iconid,
                                create = function(element)
                                    element:FireEvent("display", mod.aura.display)
                                end,
                            },

                            gui.Label{
                                height = "auto",
                                width = 120,
                                textWrap = false,
                                halign = "left",
                                valign = "center",
                                rmargin = 4,
                                fontSize = 14,
                                minFontSize = 8,
                                color = Styles.textColor,
                                text = string.format("%s (Aura)", mod.aura.name),
                            },

                            gui.VisibilityPanel{
                                valign = "center",
                                halign = "left",
                                opacity = 1,
                                visible = true,
                                bgcolor = "white",
                                margin = 3,
                                press = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(mod.aura.name))
                                    settings.hide = not settings.hide

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            m_token.properties:SetAuraDisplaySetting(mod.aura.name, settings)
                                        end,
                                    }
                                end,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element:FireEvent("visible", not m_token.properties:GetAuraDisplaySetting(mod.aura.name).hide)
                                end,
                            },

                            gui.PercentSlider{
                                valign = "center",
                                halign = "left",
                                hmargin = 6,
                                value = m_token.properties:GetAuraDisplaySetting(mod.aura.name).opacity,
                                refresh = function(element)
                                    if m_token == nil or not m_token.valid then
                                        return
                                    end

                                    element.value = m_token.properties:GetAuraDisplaySetting(mod.aura.name).opacity
                                end,
                                preview = function(element)
                                    local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(mod.aura.name))
                                    settings.opacity = element.value
                                    m_token.properties:SetAuraDisplaySetting(mod.aura.name, settings)
                                    m_token:UpdateAuras()
                                end,
                                confirm = function(element)
                                    --set it to off to force upload.
                                    m_token.properties:SetAuraDisplaySetting(mod.aura.name, nil)

                                    m_token:ModifyProperties{
                                        description = tr("Set Aura Display Settings"),
                                        undoable = false,
                                        execute = function()
                                            local settings = DeepCopy(m_token.properties:GetAuraDisplaySetting(mod.aura.name))
                                            settings.opacity = element.value
                                            m_token.properties:SetAuraDisplaySetting(mod.aura.name, settings)
                                        end,
                                    }
                                end,
                            },
                        }

                        newPanels[mod.aura.guid] = panel
                        newChildren[#newChildren+1] = panel
                    end
                end
            end

            m_auraPanels = newPanels
            element.children = newChildren
        end,
    }

    return resultPanel
end

local function InflictedConditionsPanel(m_token)

	local m_conditions
	local addConditionButton = nil
	local ongoingEffectPanels = {}

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshToken = function(element, tok)
            m_token = tok
        end,

        refresh = function(element)
            if m_token == nil or not m_token.valid then
                for _,p in ipairs(ongoingEffectPanels) do
                    p:SetClass("collapsed", true)
                end
                return
            end

            local creature = m_token.properties
            if creature == nil then
                for _,p in ipairs(ongoingEffectPanels) do
                    p:SetClass("collapsed", true)
                end
                return
            end

            m_conditions = creature:try_get("inflictedConditions", {})
            local count = 0

            local newPanels = false

            for key,cond in pairs(m_conditions) do
                count = count+1
                local panel = ongoingEffectPanels[count]
    
                if panel == nil then

                    newPanels = true

                    local button = gui.DiamondButton{
                        bgimage = 'panels/square.png',
                        halign = "left",
                        width = 24,
                        height = 24,
                        hmargin = 6,
                        valign = "center",

                        click = function(element)

                            local items = {}

                            local duration = m_token.properties:ConditionDuration(element.parent.data.condid)
                            if duration and duration ~= "eot" and duration ~= "eoe" then
                                items[#items+1] = {
                                    text = "Roll Save",
                                    click = function()
                                        m_token.properties:RollConditionSave(element.parent.data.condid)
                                        element.popup = nil
                                    end,
                                }
                            end

                            local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                            local riders = {}
                            for key,rider in unhidden_pairs(ridersTable) do
                                if rider.condition == element.parent.data.condid then
                                    riders[#riders+1] = key
                                end
                            end

                            table.sort(riders, function(a,b) return ridersTable[a].name < ridersTable[b].name end)

                            for _,rider in ipairs(riders) do
                                local text
                                local alreadyHas = m_token.properties:ConditionHasRider(element.parent.data.condid, rider)
                                if alreadyHas then
                                    text = string.format("Remove %s", ridersTable[rider].name)
                                else
                                    text = string.format("Add %s", ridersTable[rider].name)
                                end

                                items[#items+1] = {
                                    text = text,
                                    click = function()
                                        m_token:BeginChanges()
                                        m_token.properties:SetConditionRider(element.parent.data.condid, rider, not alreadyHas)
                                        m_token:CompleteChanges("Apply Condition Rider")
                                        element.popup = nil
                                    end,
                                }
                            end

                            items[#items+1] = {
                                text = "Remove Condition",
                                click = function()
                                    m_token:BeginChanges()
                                    m_token.properties:InflictCondition(element.parent.data.condid, {purge = true})
                                    m_token:CompleteChanges("Apply Condition")
                                    element.popup = nil
                                end,
                            }

                            element.popup = gui.ContextMenu{
                                entries = items,
                            }
                            
                        end,
                    }

                    local descriptionLabel = gui.Label{
                        height = "auto",
                        width = 140,
                        textWrap = false,
                        halign = "left",
                        valign = "center",
                        rmargin = 4,
                        fontSize = 14,
                        minFontSize = 8,
                        color = Styles.textColor,
                    }

                    local quantityLabel = gui.Label{
                        width = "auto",
                        height = "auto",
                        minWidth = 80,
                        fontSize = 14,
                        bold = true,
                        halign = "left",
                        valign = "center",
                        color = Styles.textColor,
                        characterLimit = 2,
                        textAlignment = "left",

                        press = function(element)
                            if element.popup ~= nil then
                                element.popup = nil
                                return
                            end

                            local SetDuration = function(duration)
                                m_token:BeginChanges()
                                m_token.properties:InflictCondition(element.parent.data.condid, {force = true, duration = duration})
                                m_token:CompleteChanges("Set Condition Duration")
                            end

                            local entries = {}

                            entries[#entries+1] = {
                                text = "Save Ends",
                                click = function()
                                    SetDuration("save")
                                    element.popup = nil
                                end,
                            }

                            entries[#entries+1] = {
                                text = "EoT",
                                click = function()
                                    SetDuration("eot")
                                    element.popup = nil
                                end,
                            }
                            entries[#entries+1] = {
                                text = "EoE",
                                click = function()
                                    SetDuration("eoe")
                                    element.popup = nil
                                end,
                            }
                            element.popup = gui.ContextMenu{
                                halign = "center",
                                entries = entries,
                            }
                        end,

                        change = function(element)
                            local cond = m_conditions[element.parent.data.condid]
                            local stacks = tonumber(element.text)
                            if stacks == nil then
                                element.text = tostring(cond.stacks)
                                return
                            end

                            m_token:BeginChanges()
                            m_token.properties:InflictCondition(element.parent.data.condid, {stacks = stacks - cond.stacks})
                            m_token:CompleteChanges("Apply Condition")
                        end,
                    }

                    local trackCasterButton = gui.Button{
                        fontSize = 12,
                        width = 62,
                        height = "auto",
                        text = "Set Caster",
                        halign = "left",
                        press = function(element)
                            local ability = DeepCopy(MCDMUtils.GetStandardAbility("SetConditionCaster"))
                            ability.behaviors[1].condid = key
                            ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(m_token, ability, m_token, "prompt", {}, {})
                        end,
                        refresh = function(element)
                            if m_token == nil or not m_token.valid then
                                return
                            end

                            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = conditionsTable[key]

                            if ongoingEffectInfo == nil or not ongoingEffectInfo.trackCaster then
                                element:SetClass("collapsed", true)
                                return
                            end

                            local conditions = m_token.properties:try_get("inflictedConditions", {})
                            local cond = conditions[key]
                            if cond == nil or cond.casterInfo ~= nil then
                                element:SetClass("collapsed", true)
                            else
                                element:SetClass("collapsed", false)
                            end
                        end,
                    }

                    panel = gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        vmargin = 4,
                        bgimage = "panels/square.png",
                        bgcolor = "black",
                        opacity = 0.8,
                        data = {
                            targetingMarkers = {},
                        },

                        clearTargetingMarkers = function(element)
                            if #element.data.targetingMarkers == 0 then
                                return
                            end
                            for _, marker in ipairs(element.data.targetingMarkers) do
                                marker:Destroy()
                            end
                            element.data.targetingMarkers = {}
                        end,

                        button,

                        descriptionLabel,

                        quantityLabel,
                        trackCasterButton,

                        gui.DeleteItemButton{
                            width = 12,
                            height = 12,

                            lmargin = 8,
                            halign = "left",
                            valign = "center",
                            data = {
                                entry = nil,
                            },
                            press = function(element)
                                m_token:BeginChanges()
                                m_token.properties:InflictCondition(element.parent.data.condid, {purge = true})
                                m_token:CompleteChanges("Remove Condition")
                            end,
                        },


                        refresh = function(element)
                            if m_token == nil or not m_token.valid then
                                return
                            end

                            local cond = m_conditions[element.data.condid]
                            if cond == nil then
                                return
                            end

                            local ongoingEffectsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = ongoingEffectsTable[element.data.condid]

                            local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                            local text = ongoingEffectInfo.name
                            local riderDuration = false
                            for _,riderid in ipairs(m_token.properties:GetConditionRiders(element.data.condid) or {}) do
                                if ridersTable[riderid] then
                                    text = string.format("%s %s", text, ridersTable[riderid].name)
                                    if ridersTable[riderid].removeThisInsteadOfCondition then
                                        riderDuration = true
                                    end
                                end
                            end

                            descriptionLabel.text = text

                            local ongoingEffectsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = ongoingEffectsTable[element.data.condid]
                            button:FireEvent("icon", ongoingEffectInfo.iconid)
                            button:FireEvent("display", ongoingEffectInfo.display)

                            local duration = cond.duration
                            if duration == "eot" then
                                duration = "EoT"
                            elseif duration == "eoe" then
                                duration = "EoE"
                            else
                                duration = "Save"
                            end

                            quantityLabel.text = duration

                            quantityLabel:SetClass("hidden", ongoingEffectInfo.indefiniteDuration and (not riderDuration))
                        end,

                        dehover = function(element)
                            element:FireEvent("clearTargetingMarkers")
                        end,

                        linger = function(element)
                            element:FireEvent("clearTargetingMarkers")
                            local cond = m_conditions[element.data.condid]
                            if cond == nil then
                                return
                            end
                            local ongoingEffectsTable = dmhub.GetTable(CharacterCondition.tableName)
                            local ongoingEffectInfo = ongoingEffectsTable[element.data.condid]

                            local caster = cond.casterInfo
                            if caster ~= nil and type(caster.tokenid) == "string" then
                                local casterToken = dmhub.GetTokenById(caster.tokenid)
                                if casterToken ~= nil then

									element.data.targetingMarkers[#element.data.targetingMarkers+1] = dmhub.HighlightLine{
										color = "red",
										a = casterToken.pos,
										b = m_token.pos,
									}
                                end
                            end


                            local duration = cond.duration
                            if duration == "eot" then
                                duration = "EoT"
                            elseif duration == "eoe" then
                                duration = "EoE"
                            elseif type(duration) == "string" then
                                duration = string.upper(duration) .. " ends"
                            else
                                duration = "EoT"
                            end

                            local durationText = string.format(" (%s)", duration)
                            if ongoingEffectInfo.indefiniteDuration then
                                durationText = ""
                            end

                            local ridersText = ""
                            local riderids = m_token.properties:GetConditionRiders(element.data.condid)
                            if riderids ~= nil then
                                local ridersTable = dmhub.GetTable(CharacterCondition.ridersTableName)
                                for _,riderid in ipairs(riderids) do
                                    local riderInfo = ridersTable[riderid]
                                    if riderInfo ~= nil then
                                        ridersText = string.format("%s\n\n<b>%s</b>: %s", ridersText, riderInfo.name, riderInfo.description)
                                    end
                                end
                            end

                            element.popupPositioning = "panel"
                            gui.Tooltip{halign = "left", valign = "center", text = string.format('<b>%s</b>%s: %s%s\n\n%s', ongoingEffectInfo.name, durationText, ongoingEffectInfo.description, ridersText, cond.sourceDescription or "")}(element)
                        end,
                    }

                    ongoingEffectPanels[count] = panel
                end

                panel.data.condid = key
            end

            for i,p in ipairs(ongoingEffectPanels) do
                p:SetClass("collapsed", i > count)
            end

            if addConditionButton == nil then
                newPanels = true

                addConditionButton = gui.DiamondButton{
                    width = 24,
                    height = 24,
                    halign = "left",
                    valign = "top",
                    hmargin = 6,
                    vmargin = 4,
                    valign = "center",
                    color = Styles.textColor,

                    hover = gui.Tooltip("Add a condition"),
                    press = function(element)
                        CharacterPanel.AddConditionMenu{
                            tokens = {m_token},
                            button = element,
                        }
                    end,
                }

            end

            if newPanels then
                local children = {}
                for _,child in ipairs(ongoingEffectPanels) do
                    children[#children+1] = child
                end
                children[#children+1] = addConditionButton
                element.children = children
            end


        end,



    }

    return resultPanel
end

local g_refreshChecklistName = {
    encounter = "encounter",
    round = "round",
}

CharacterPanel.CreateCharacterDetailsPanel = function(m_token)

    local m_effectEntryPanels = {}
    local m_customConditionPanels = {}

    local resultPanel = nil

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            {
                selectors = {"deleteItemButton"},
                opacity = 0,
            },
            {
                selectors = {"deleteItemButton", "parent:hover"},
                opacity = 1,
            },
        },

        refreshToken = function(element, tok)
            m_token = tok
        end,

        --add to combat button.
        gui.Button{
            classes = {"collapsed"},
            width = 320,
            height = 30,
            text = "Add to Combat",
            refreshToken = function(element, tok)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then
                    element:SetClass("collapsed", true)
                    return
                end

                element:SetClass("collapsed", tok.properties:try_get("_tmp_initiativeStatus") ~= "NonCombatant")
            end,

            click = function(element)
                Commands.rollinitiative()
            end,
        },

        gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",

            refreshToken = function(element)
                local creature = m_token.properties
                if creature == nil then
                    if m_token == nil then
                        if CharacterSheet.instance and CharacterSheet.instance.data and CharacterSheet.instance.data.info then
                            m_token = CharacterSheet.instance.data.info.token
                        end
                    end
                    if m_token then creature = m_token.properties end
                end
                if creature and creature:IsCompanion() then
                    creature:DisplayCharacterPanel(m_token, element)
                else
                    element:SetClass("collapsed", true)
                end
            end,
        },

        --heroic resource panel.
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            styles = {
                {
                    classes = {"label"},
                    color = "white",
                },
                {
                    classes = {"label", "parent:consumed"},
                    transitionTime = 0.5,
                    color = "grey",
                },
                {
                    classes = {"strikethrough"},
                    bgimage = "panels/square.png",
                    bgcolor = "white",
                    halign = "left",
                    valign = "center",
                    height = 1,
                    width = "0%",
                },
                {
                    classes = {"strikethrough", "parent:consumed"},
                    transitionTime = 0.5,
                    width = "60%",
                    bgcolor = "grey",
                },
            },
            data = {
                panels = {},
                headingPanel = nil,
            },
            refreshToken = function(element)
                if element.data.headingPanel == nil then
                    element.data.headingPanel = element.children[1]
                end
                local creature = m_token.properties
                local checklist = creature:GetHeroicResourceChecklist()
                if checklist == nil or #checklist == 0 then
                    element:SetClass("collapsed", true)
                    element.children = {element.data.headingPanel}
                    element.data.panels = {}
                    return
                end

                element:SetClass("collapsed", false)

                local panels = element.data.panels
                local newPanels = {}

                local children = {element.data.headingPanel}
                for _,entry in ipairs(checklist) do

                    local consumed
                    local q = dmhub.initiativeQueue
                    local record = creature:try_get("heroicResourceRecord")
                    if q == nil or q.hidden or entry.mode == "recurring" or record == nil or record[entry.guid] == nil or record[entry.guid] ~= creature:GetResourceRefreshId(entry.mode or "encounter") then
                        consumed = false
                    else
                        consumed = true
                    end

                    local panel = panels[entry.guid] or gui.Panel{
                        classes = {cond(consumed, "consumed")},
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        linger = gui.Tooltip(entry.details),
                        rightClick = function(element)
                            local q = dmhub.initiativeQueue
                            if q == nil or q.hidden then
                                return
                            end

                            local resourceName = m_token.properties:GetHeroicResourceName()

                            local entries = {}
                            if element:HasClass("consumed") then

                            else
                                entries[#entries+1] = {
                                    text = "Trigger Manually",
                                    click = function()
                                        element.popup = nil
                                        if m_token == nil or not m_token.valid then
                                            return
                                        end


                                        m_token:ModifyProperties{
                                            description = tr("Trigger resource gain"),
                                            execute = function()


                                                local updateid = m_token.properties:GetHeroicResourceChecklistRefreshId(entry.guid)
                                                if updateid == nil then
                                                    return
                                                end

                                                local record = m_token.properties:get_or_add("heroicResourceRecord", {})
                                                local checklistBefore = {}
                                                checklistBefore[entry.guid] = {record[entry.guid], updateid}
                                                record[entry.guid] = updateid

                                                local quantity = ExecuteGoblinScript(entry.quantity, GenerateSymbols(m_token.properties), 0, "Heroic Resource Amount")
                                                local amount = m_token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", quantity, entry.name)
                                                if amount > 0 then
                                                    chat.SendCustom(
                                                        ResourceChatMessage.new{
                                                            tokenid = m_token.charid,
                                                            resourceid = CharacterResource.heroicResourceId,
                                                            quantity = amount,
                                                            mode = "replenish",
                                                            checklistBefore = checklistBefore,
                                                            reason = entry.name,
                                                        }
                                                    )
                                                end


                                            end,
                                        }
                                    end,
                                }
                            end

                            if #entries > 0 then
                                element.popup = gui.ContextMenu{
                                    entries = entries
                                }
                            end
                        end,
                        gui.Panel{
                            classes = {"strikethrough"},
                            floating = true,
                        },
                        gui.Label{
                            height = "auto",
                            width = 160,
                            halign = "left",
                            lmargin = 6,
                            fontSize = 12,
                            minFontSize = 6,
                            text = entry.name,
                            textWrap = false,
                        },
                        gui.Label{
                            width = "auto",
                            height = "auto",
                            halign = "left",
                            lmargin = 12,
                            fontSize = 12,
                            text = string.format("+%d", tonumber(entry.quantity) or 1),
                            refreshToken = function(element)
                                if safe_toint(entry.quantity) then
                                    return
                                end
                                local creature = m_token.properties
                                local text = dmhub.EvalGoblinScript(entry.quantity, creature:LookupSymbol())
                                element.text = string.format("+%s", text)
                            end,
                        },
                        gui.Panel{
                            width = 10,
                            height = 10,
                            valign = "center",
                            halign = "right",
                            bgcolor = "white",
                            bgimage = "game-icons/clockwise-rotation.png",
                            rmargin = 4,
                        },
                        gui.Label{
                            width = 60,
                            height = "auto",
                            halign = "right",
                            fontSize = 12,
                            color = "white",
                            text = g_refreshChecklistName[entry.mode or "encounter"] or "always",
                        }
                    }

                    if consumed then
                        panel:SetClass("consumed", true)
                    else
                        panel:SetClassImmediate("consumed", false)
                    end

                    newPanels[entry.guid] = panel
                    children[#children+1] = panel
                end

                element.data.panels = newPanels
                element.children = children
            end,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                hover = function(element)
                    local desc = m_token.properties:GetHeroicResourceName()
                    local negativeValue = m_token.properties:CalculateNamedCustomAttribute("Negative Heroic Resource")
                    local text = nil
                    if negativeValue > 0 then
                        text = string.format("%s may go as low as -%d", desc, negativeValue)
                    end
                    element.tooltip = gui.StatsHistoryTooltip{ text = text, description = desc, entries = m_token.properties:GetStatHistory(CharacterResource.heroicResourceId):GetHistory() }
                end,


                gui.Label{
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    fontSize = 16,
                    color = Styles.textColor,
                    text = "Heroic Resource",
                    refreshToken = function(element)
                        local creature = m_token.properties
                        if not creature:IsHero() then
                            return
                        end

                        element.text = string.format("<b>%s</b>:", creature:GetHeroicResourceName())
                    end,

                },

                gui.Label{
                    editable = true,
                    numeric = true,
                    lmargin = 8,
                    width = 40,
                    characterLimit = 3,
                    fontSize = 16,
                    height = "auto",

                    refreshToken = function(element)
                        local creature = m_token.properties
                        if not creature:IsHero() then
                            return
                        end

                        local resources = creature:GetHeroicOrMaliceResources()
                        element.text = tostring(resources)
                    end,

                    change = function(element)
                        local amount = tonumber(element.text)
                        if amount == nil then
                            element:FireEvent("refreshToken")
                            return
                        end
                        local diff = amount - m_token.properties:GetHeroicOrMaliceResources()
                        if diff == 0 then
                            return
                        end
                        m_token:ModifyProperties{
                            description = "Change Heroic Resource",
                            execute = function()
                                if diff > 0 then
                                    m_token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
                                else
                                    m_token.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
                                end
                            end,
                        }
                    end,

                }
            },
        },

        --growing resource table, only relevant for characters that have growing resources.
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = true,
            vmargin = 4,

            --title label.
            gui.Label{
                bold = true,
                width = "auto",
                height = "auto",
                fontSize = 16,
                color = Styles.textColor,
            },
            data = {
                children = {},
                title = nil,
            },
            styles = {
                {
                    selectors = {"label"},
                    fontSize = 12,
                    color = Styles.textColor,
                },
                {
                    selectors = {"label", "filled"},
                    color = "black",
                    bold = true,
                },
                {
                    selectors = {"label", "expiring"},
                    color = "black",
                    bold = true,
                },
                {
                    selectors = {"row"},
                    width = "100%",
                    height = "auto",
                    vpad = 2,
                },
                {
                    selectors = {"row", "even"},
                    bgcolor = "black",
                },
                {
                    selectors = {"row", "odd"},
                    bgcolor = "#222222",
                },
                {
                    selectors = {"row", "filled"},
                    bgcolor = "#ffaaaa",
                },
                {
                    selectors = {"row", "expiring"},
                    bgcolor = "#aa9999",
                },
            },
            refreshToken = function(element)
                local creature = m_token.properties
                if (not creature:IsHero()) and (not creature:IsCompanion()) then
                    element:SetClass("collapsed", true)
                    return
                end

                local growingResources = creature:GetGrowingResourcesTable()
                if growingResources == nil then
                    element:SetClass("collapsed", true)
                    return
                end

                if element.data.title == nil then
                    element.data.title = element.children[1]
                end

                element.data.title.text = growingResources.name

                local progression = growingResources.progression

                element:SetClass("collapsed", false)

                local characterLevel = creature:CharacterLevel()
                local characterResources = creature:GetProgressionResource()
                local resourcesHigh = creature:GetProgressionResourceHighWaterMark()


                local children = element.data.children
                local startingChildren = #children

                local index = 1

                for i,entry in ipairs(progression) do
                    if (tonumber(entry.level) or 0) <= characterLevel then
                        local row = children[index] or gui.Panel{
                            classes = {"row", cond(i%2 == 0, "even", "odd")},
                            bgimage = true,
                            flow = "horizontal",
                            data = {
                                entry = nil,
                            },
                            update = function(element, entry)
                                element.data.entry = entry
                            end,
                            hover = function(element)
                                if element.data.entry.tooltip ~= nil then
                                    gui.Tooltip(element.data.entry.tooltip)(element)
                                end
                            end,
                            gui.Label{
                                width = 16,
                                height = 16,
                                lmargin = 4,
                                update = function(element, entry)
                                    element.text = entry.resources
                                end,
                            },
                            gui.Label{
                                halign = "right",
                                width = "100%-24",
                                height = "auto",
                                update = function(element, entry)
                                    element.text = StringInterpolateGoblinScript(entry.description, creature)
                                end,
                            }
                        }

                        children[index] = row

                        index = index + 1

                        row:FireEventTree("update", entry)
                        row:SetClassTree("filled", entry.resources <= characterResources)
                        row:SetClassTree("expiring", entry.resources > characterResources and entry.resources <= resourcesHigh)
                    end
                end

                for i=1,#children do
                    children[i]:SetClass("collapsed", i >= index)
                end

                if #children > startingChildren then
                    local newChildren = {element.data.title}
                    for _,child in ipairs(children) do
                        newChildren[#newChildren+1] = child
                    end
                    element.children = newChildren
                end
            end,
        },



        RoutinesPanel(m_token),
        PersistencePanel(m_token),


        --custom effects.
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",


            gui.Input{
                width = "80%",
                height = "auto",
                halign = "left",
                fontSize = 12,
                characterLimit = 60,
                placeholderText = "Add Custom Condition...",
                change = function(element)
                    local text = trim(element.text)
                    if text ~= "" then

                        m_token:BeginChanges()
                        local customConditions = m_token.properties:get_or_add("customConditions", {})
                        local key = dmhub.GenerateGuid()
                        customConditions[key] = {
                            text = text,
                            timestamp = dmhub.serverTimeMilliseconds,
                        }
                        m_token:CompleteChanges("Add Custom Condition")
                    end

                    element.text = ""

                    --instantly refresh.
                    resultPanel:FireEventTree("refreshToken", m_token)
                end,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                refreshToken = function(element)
                    local children = {}
                    local customConditionPanels = {}
                    for key,entry in pairs(m_token.properties:try_get("customConditions", {})) do
                        local panel
                        panel = m_customConditionPanels[key] or gui.Panel{
                            data = {
                                ord = entry.timestamp,
                            },
                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            valign = "center",
                            halign = "center",
                            vmargin = 4,
                            hmargin = 4,

                            gui.Label{
                                width = 280,
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                characterLimit = 60,
                                editable = true,
                                fontSize = 14,
                                minFontSize = 8,
                                textWrap = false,
                                rmargin = 4,
                                color = Styles.textColor,
                                text = entry.text,
                                change = function(element)
                                    m_token:BeginChanges()
                                    local customConditions = m_token.properties:get_or_add("customConditions", {})
                                    local newKey = dmhub.GenerateGuid()
                                    local newEntry = DeepCopy(entry)
                                    newEntry.text = trim(element.text)
                                    customConditions[key] = nil
                                    if newEntry.text ~= "" then
                                        customConditions[newKey] = newEntry
                                    end
                                    m_token:CompleteChanges("Change Custom Condition")

                                    --instantly refresh.
                                    resultPanel:FireEventTree("refreshToken", m_token)
                                end,
                            },

                            gui.DeleteItemButton{
                                width = 12,
                                height = 12,

                                lmargin = 24,
                                halign = "left",
                                valign = "center",
                                press = function(element)
                                    m_token:BeginChanges()
                                    m_token.properties:get_or_add("customConditions", {})[key] = nil
                                    m_token:CompleteChanges("Remove Custom Condition")
                                    panel:DestroySelf() --update change immediately.
                                end,
                            },
                        }

                        children[#children+1] = panel
                        customConditionPanels[key] = panel
                    end

                    table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

                    m_customConditionPanels = customConditionPanels
                    element.children = children
                end,
            }
        },

        --auras.
        AurasEmittingPanel(m_token),

        --ongoing effects.
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",

            refreshToken = function(element)
                local creature = m_token.properties
				local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects")
				local activeOngoingEffects = creature:ActiveOngoingEffects()

                local index = 1
                for _,effectEntry in ipairs(activeOngoingEffects) do
                    local effectInfo = ongoingEffectsTable[effectEntry.ongoingEffectid]
                    if effectInfo ~= nil and effectInfo.statusEffect then

                        m_effectEntryPanels[index] = m_effectEntryPanels[index] or gui.Panel{
                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            width = "100%",
                            height = "auto",
                            flow = "horizontal",
                            valign = "center",
                            halign = "center",
                            vmargin = 4,
                            hmargin = 4,

                            data = {
                                info = nil,
                                entry = nil,
                            },

                            refreshStatus = function(element, info, entry)
                                element.data.info = info
                                element.data.entry = entry
                            end,

                            clearHighlights = function(element)
                                if element.data.highlights ~= nil then
                                    for i,highlight in ipairs(element.data.highlights) do
                                        highlight:Destroy()
                                    end
                                    element.data.highlights = nil
                                end
                            end,

                            destroy = function(element)
                                element:FireEvent("clearHighlights")
                            end,

                            dehover = function(element)
                                element:FireEvent("clearHighlights")
                            end,

                            linger = function(element)
                                local stacksText = ""
                                if element.data.info.stackable then
                                    stacksText = string.format(" (%d stacks)", element.data.entry.stacks)
                                end
                                local casterText = ""
                                local caster = element.data.entry:DescribeCaster()
                                if caster ~= nil then
                                    casterText = string.format("\nInflicted by %s", caster)
                                end
								gui.Tooltip(string.format('%s%s: %s%s\n%s', element.data.info.name, stacksText, StringInterpolateGoblinScript(element.data.info.description, m_token.properties), casterText, element.data.entry:DescribeTimeRemaining()))(element)

                                element:FireEvent("clearHighlights")

                                if element.data.entry.bondid then
                                    local tokens = creature.GetTokensWithBoundOngoingEffect(element.data.entry.bondid)
                                    element.data.highlights = {}
                                    for i,tok in ipairs(tokens) do
                                        for j=i+1,#tokens do
                                            element.data.highlights[#element.data.highlights+1] = dmhub.HighlightLine{
                                                color = "red",
                                                a = tokens[i].pos,
                                                b = tokens[j].pos,
                                            }
                                        end
                                    end
                                end
                            end,

                            children = {
                                gui.DiamondButton{
                                    width = 24,
                                    height = 24,
                                    hmargin = 6,
                                    valign = "center",
                                    halign = "left",

                                    refreshStatus = function(element, info, entry)
                                        element:FireEvent("icon", info.iconid)
                                        element:FireEvent("display", info.display)
                                    end,

                                },

                                gui.Label{
                                    width = 120,
                                    height = "auto",
                                    halign = "left",
                                    valign = "center",
                                    fontSize = 14,
                                    minFontSize = 8,
                                    textWrap = false,
                                    rmargin = 4,
                                    color = Styles.textColor,
                                    refreshStatus = function(element, info, entry)
                                        local stacksText = ""
                                        if entry.stacks ~= nil and entry.stacks > 1 then
                                            stacksText = string.format(" x %d", entry.stacks)
                                        end
                                        element.text = info.name .. stacksText
                                    end,
                                },

                                --duration label
                                gui.Label{
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 100,
                                    maxWidth = 160,
                                    fontSize = 14,
                                    bold = true,
                                    halign = "left",
                                    valign = "center",
                                    color = Styles.textColor,
                                    characterLimit = 2,
                                    textAlignment = "left",

                                    refreshStatus = function(element, info, entry)
                                        element.text = entry:DescribeTimeRemaining()
                                    end,
                                },

                                gui.DeleteItemButton{
                                    width = 12,
                                    height = 12,

                                    lmargin = 24,
                                    halign = "left",
                                    valign = "center",
                                    data = {
                                        entry = nil,
                                    },
                                    refreshStatus = function(element, info, entry)
                                        element.data.entry = entry
                                    end,
                                    press = function(element)
                                        m_token:BeginChanges()
                                        m_token.properties:RemoveOngoingEffect(element.data.entry.ongoingEffectid)
                                        m_token:CompleteChanges("Remove Ongoing Effect")
                                    end,
                                },

                            },
                        }

                        m_effectEntryPanels[index]:FireEventTree("refreshStatus", effectInfo, effectEntry)

                        index = index+1
                    end
                end

                while #m_effectEntryPanels >= index do
                    m_effectEntryPanels[#m_effectEntryPanels] = nil
                end

                element.children = m_effectEntryPanels

            end,

        },

        AurasAffectingPanel(m_token),

        --inflicted conditions.
        InflictedConditionsPanel(m_token),

		CharacterPanel.CharacteristicsPanel(m_token),
		CharacterPanel.ImportantAttributesPanel(m_token),

		gui.Panel{
			width = "100%",
			height = "auto",
            flow = "vertical",
            data = {
                children = {},
            },
			bmargin = 4,
            refreshToken = function(element)
                local children = element.data.children
                local creature = m_token.properties
				local entries = creature:ResistanceEntries()

                for i=1,#entries do
                    local label = children[i] or gui.Label{
                        data = {},
                        width = "auto",
                        height = "auto",
                        fontSize = 14,
                        bold = true,
			            color = Styles.textColor,
                        hover = function(element)
                            gui.Tooltip{text = element.data.tooltip, fontSize = 14}(element)
                        end,
                    }

                    label.data.tooltip = entries[i].entry.source
                    label.text = entries[i].text

                    children[i] = label
                end

                for i,child in ipairs(children) do
                    child:SetClass("collapsed", i > #entries)
                end

                element.children = children
			end,
		},

		CharacterPanel.SkillsPanel(m_token),
		CharacterPanel.LanguagesPanel(m_token),
        CharacterPanel.AbilitiesPanel(m_token),
        CharacterPanel.NotesPanel(m_token),
    }

    return resultPanel
end

function CharacterPanel.DecorateHitpointsPanel()
	local recoveryid = nil
	local recoveryInfo = nil
	local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
	for k,v in pairs(resourcesTable) do
		if not v:try_get("hidden", false) and v.name == "Recovery" then
			recoveryid = k
			recoveryInfo = v
		end
	end

	local m_token = nil
	local m_hidden = false
	return gui.Panel{
		floating = true,
		width = "100%",
		height = "100%",
		refreshCharacter = function(element, token)
			m_token = token
			m_hidden = recoveryid == nil or token == nil or (not token.valid) or token.properties == nil or ((not token.properties:IsHero()) and (not token.properties:IsRetainer()) and (not token.properties:IsCompanion()))
			element:SetClass("hidden", m_hidden)
		end,

		gui.Panel{
			halign = "center",
			valign = "bottom",
			cornerRadius = 16,
			y = 8,
			width = 32,
			height = 32,
			bgimage = "panels/square.png",
			borderWidth = 1,
			borderColor = Styles.textColor,
			gradient = Styles.healthGradient,
			bgcolor = "white",

			styles = {
				{
					selectors = {"hover", "~expended"},
					brightness = 2,
					transitionTime = 0.2,
				},
				{
					selectors = {"press", "~expended"},
					brightness = 0.5,
				},
				{
					selectors = {"expended"},
					saturation = 0,
				},
			},

			hover = function(element)
				local usage = m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
				local max = m_token.properties:GetResources()[recoveryid] or 0
				local quantity = max - usage


                local usageNote = "Click to use"

                if m_token.properties:CurrentHitpoints() >= m_token.properties:MaxHitpoints() then
                    usageNote = "Already at maximum stamina"
                elseif quantity <= 0 then
                    if m_token.properties:IsHero() and m_token.properties:GetHeroTokens() >= 2 then
                        usageNote = "Click to spend 2 hero tokens as a Recovery"
                    else
                        usageNote = "No Recoveries left"
                    end
                end

				local tooltip = string.format("Recoveries: %d/%d\nRecovery Value: %d\n%s.", quantity, max, m_token.properties:RecoveryAmount(), usageNote)
                local recoverySharing = m_token.properties:ShareRecoveriesWith()
                if recoverySharing ~= nil then
                    tooltip = tooltip .. "\nCan Share Recoveries With:\n"
                    for i,token in ipairs(recoverySharing) do
                        if token.charid ~= m_token.charid then
                            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                            local max = token.properties:GetResources()[recoveryid] or 0
                            local quantity = max - usage
                            tooltip = tooltip .. string.format("%s (%d/%d)\n", token.name, quantity, max)
                        end
                    end
                end
				gui.Tooltip(tooltip)(element)
			end,

			click = function(element)
				if m_token == nil then
					return
				end

                local useHeroTokens = false

				local quantity = max(0, (m_token.properties:GetResources()[recoveryid] or 0) - (m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
				if quantity <= 0 then
                    if (not m_token.properties:IsHero()) or m_token.properties:GetHeroTokens() < 2 then 
					    return
                    end

                    --can spend hero tokens instead.
                    useHeroTokens = true
				end

				if m_token.properties:CurrentHitpoints() >= m_token.properties:MaxHitpoints() then
					return
				end

				m_token:BeginChanges()
				m_token.properties:Heal(m_token.properties:RecoveryAmount(), "Use Recovery")
                if not useHeroTokens then
				    m_token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                end

				m_token:CompleteChanges("Use Recovery")

                if useHeroTokens then
                    m_token.properties:SetHeroTokens(m_token.properties:GetHeroTokens()-2, "Used to Recover")
                end
			end,

			rightClick = function(element)
                local entries = {
					{
						text = "Edit Recoveries",
						click = function()
							element.popup = nil
							element:FireEventTree("editRecoveries")
						end,
					}
                }


                local recoverySharing = m_token.properties:ShareRecoveriesWith()
                if recoverySharing ~= nil then
                    for i,token in ipairs(recoverySharing) do
                        if token.charid ~= m_token.charid then
                            local usage = token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0
                            local max = token.properties:GetResources()[recoveryid] or 0
                            local quantity = max - usage
                            if quantity > 0 then
                                local casterToken = m_token
                                entries[#entries+1] = {
                                    text = string.format("Spend %s's Recovery (%d/%d)", token.name, quantity, max),
                                    click = function()
                                        element.popup = nil

                                        local groupid = dmhub.GenerateGuid()

                                        casterToken:ModifyProperties{
                                            description = string.format("Use %s's Recovery", token.name),
                                            groupid = groupid,
                                            execute = function()
                                                casterToken.properties:Heal(casterToken.properties:RecoveryAmount(), "Use Recovery")
                                            end,
                                        }

                                        token:ModifyProperties{
                                            description = string.format("%s's Recovery used by %s", token.name, casterToken.name),
                                            groupid = groupid,
                                            execute = function()
                                                token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, 1, "Used Recovery")
                                            end,
                                        }
                                    end,
                                }
                            end
                        end
                    end
                end

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
			end,


			gui.Label{
				width = "100%",
				height = "auto",
				halign = "center",
				valign = "center",
				textAlignment = "center",
				color = "white",
				fontSize = 20,
				characterLimit = 2,
				editRecoveries = function(element)
					element:BeginEditing()
				end,
				change = function(element)
					local n = tonumber(element.text)
					if n == nil then
						element:FireEvent("refreshCharacters", m_token)
						return
					end

					local nresources = m_token.properties:GetResources()[recoveryid] or 0
					local usage = m_token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0

					local current = nresources - usage
					local delta = n - current

					m_token:BeginChanges()
					if delta > 0 then
						m_token.properties:RefreshResource(recoveryid, recoveryInfo.usageLimit, delta, "Used Recovery")
					else
						m_token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, -delta, "Used Recovery")
					end
					m_token:CompleteChanges("Set Recoveries")
				end,

				refreshCharacter = function(element, token)
					if m_hidden then
						return
					end

					local quantity = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
					element.text = string.format("%d", quantity)

					element.parent:SetClass("expended", quantity <= 0)
				end,
			},
		}

	}
end

function CharacterPanel.DecoratePortraitPanel(token)
	local m_token = token
	return gui.Panel{
		width = "100%",
		height = "100%",

        gui.Panel{
            classes = {"hidden"},
            floating = true,
            halign = "left",
            valign = "top",
            width = 40,
            height = 16,
            flow = "horizontal",
            linger = function(element)
                local minHeroes = m_token.properties:try_get("minHeroes")
                if minHeroes == nil then
                    return
                end
                gui.Tooltip(string.format("This monster is used when there are %d or more heroes.", minHeroes))(element)
            end,
            gui.Panel{
                bgimage = "icons/icon_app/icon_app_18.png",
                bgcolor = Styles.textColor,
                width = 16,
                height = 16,
            },
            gui.Label{
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 12,
                color = Styles.textColor,
                refreshCharacter = function(element, token)
                    if not token.properties:IsMonster() or token.properties:try_get("minHeroes") == nil then
                        element.parent:SetClass("hidden", true)
                        return
                    end

                    element.text = string.format("%d+", token.properties.minHeroes)
                    element.parent:SetClass("hidden", false)
                end,
            },
        },

        gui.Panel{
            floating = true,
            halign = "right",
            x = 15,
            width = 30,
            height = "100%",
            flow = "vertical",

            gui.Panel{
                valign = "top",
                vmargin = 8,
                width = 30,
                height = 30,
                flow = "none",

                refreshCharacter = function(element, token)
                    m_token = token
                    element:SetClass("hidden", token == nil or (not token.valid) or token.properties == nil or (token.properties.typeName ~= "character" and token.properties.typeName ~= "AnimalCompanion"))
                end,

                gui.Label{
                    fontSize = 22,
                    textWrap = false,
                    bold = true,
                    color = Styles.textColor,
                    halign = "center",
                    valign = "center",
                    characterLimit = 2,
                    editable = true,
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    cornerRadius = 15,
                    bgcolor = "black",
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    bgimage = true,
                    numeric = true,
                    flow = "none",

                    gui.Label{
                        bgimage = true,
                        bgcolor = "black",
                        bold = true,
                        hpad = 1,
                        vpad = 1,
                        fontSize = 9,
                        borderWidth = 0.5,
                        borderColor = Styles.textColor,
                        halign = "center",
                        valign = "bottom",
                        width = "auto",
                        height = "auto",
                        text = "Tokens",
                        y = 7,
                        press = function(element)

                            local n = dmhub.GetSettingValue("numheroes")

                            local items = {}
                            items[#items+1] = {
                                text = string.format("Reset Hero Tokens For Session (%d heroes)", n),
                                click = function()
                                    m_token.properties:SetHeroTokens(n, "Session Reset")
                                    element.popup = nil
                                end,
                            }


                            element.popup = gui.ContextMenu{
                                entries = items,
                            }

                        end,
                    },

                    --if the global resources change we want to refresh.
                    monitorGame = CharacterResource.GlobalResourcePath(),
                    refreshGame = function(element)
                        element:FireEvent("refreshCharacter", m_token)
                    end,

                    hover = function(element)

                        local text = [[<b>Hero Tokens</b>
* You can spend a hero token to gain two surges. Surges allow you to increase the damage or potency of an ability.
* You can spend a hero token when you fail a saving throw to succeed on it instead.
* You can reroll the result of a test. You must use the new result and can't use more than 1 Hero token on a test.
* You can spend 2 hero tokens on your turn or whenever you take damage (no action required) to regain Stamina equal to your Recovery value without spending a Recovery.
]]
                        
                        local history = m_token.properties:GetHeroTokenHistory()
                        if history ~= nil and #history > 0 then
                            text = text .. "\n<b>Recent Changes:</b>"
                            for _,entry in ipairs(history) do
                                text = string.format("%s\n%s: %d by %s %s", text, entry.note, entry.value, entry.who, entry.when)
                            end
                        end

                        gui.Tooltip(text)(element)
                    end,

                    refreshCharacter = function(element, token)
                        if element.parent:HasClass("hidden") then
                            return
                        end

                        if m_token == nil or not m_token.valid then
                            return
                        end

                        element.text = tostring(token.properties:GetHeroTokens())
                    end,

                    change = function(element)
                        if m_token == nil or not m_token.valid then
                            return
                        end

                        local n = tonumber(element.text)
                        if n ~= nil and round(n) == n then
                            n = math.max(0, n)
                            m_token.properties:SetHeroTokens(n, "Set manually")
                        end
                        element.text = string.format("%d", m_token.properties:GetHeroTokens())
                    end,
                },

                gui.Label{
                    fontSize = 22,
                    textWrap = false,
                    bold = true,
                    color = Styles.textColor,
                    halign = "center",
                    valign = "center",
                    characterLimit = 2,
                    editable = true,
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    cornerRadius = 15,
                    bgcolor = "black",
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    bgimage = true,
                    numeric = true,
                    flow = "none",
                    y = 45,

                    hover = function(element)
                        if m_token == nil or not m_token.valid then
                            return
                        end
                        local q = dmhub.initiativeQueue
                        if q == nil or q.hidden then
                            element.tooltip = string.format("No %s while not in combat.", m_token.properties:GetHeroicResourceName())
                            return
                        end
                        local desc = m_token.properties:GetHeroicResourceName()
                        local negativeValue = m_token.properties:CalculateNamedCustomAttribute("Negative Heroic Resource")
                        local text = nil
                        if negativeValue > 0 then
                            text = string.format("%s may go as low as -%d", desc, negativeValue)
                        end
                        element.tooltip = gui.StatsHistoryTooltip{ text = text, description = desc, entries = m_token.properties:GetStatHistory(CharacterResource.heroicResourceId):GetHistory() }
                    end,

                    gui.Label{
                        bgimage = true,
                        bgcolor = "black",
                        bold = true,
                        hpad = 1,
                        vpad = 1,
                        fontSize = 9,
                        borderWidth = 1,
                        borderColor = Styles.textColor,
                        halign = "center",
                        valign = "bottom",
                        width = "auto",
                        height = "auto",
                        text = "xx",
                        y = 7,

                        refreshCharacter = function(element, token)
                            local creature = token.properties
                            element.text = string.format("%s", creature:GetHeroicResourceName())
                        end,
                    },


                    refreshCharacter = function(element, token)
                        local q = dmhub.initiativeQueue
                        if q == nil or q.hidden then
                            element.text = "-"
                            return
                        end
                        local creature = token.properties
                        local resources = creature:GetHeroicOrMaliceResources()
                        element.text = tostring(resources)
                    end,

                    change = function(element)
                        local amount = tonumber(element.text)
                        if amount == nil then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end

                        local creature = m_token.properties
                        if not creature:IsHero() and not creature:IsCompanion() then
                            CharacterResource.SetMalice(math.max(0, amount), "Manually set")
                            return
                        end

                        local resource = dmhub.GetTable(CharacterResource.tableName)[CharacterResource.heroicResourceId]

                        amount = resource:ClampQuantity(m_token.properties, amount)

                        local diff = amount - m_token.properties:GetHeroicOrMaliceResources()
                        if diff == 0 then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end
                        m_token:ModifyProperties{
                            description = "Change Heroic Resource",
                            execute = function()
                                if diff > 0 then
                                    print("RESOURCE:: CALLING REFRESH...")
                                    m_token.properties:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
                                else
                                    print("RESOURCE:: CALLING CONSUME...")
                                    m_token.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
                                end
                            end,
                        }

                    end,
                },

                gui.Label{
                    fontSize = 22,
                    textWrap = false,
                    bold = true,
                    color = Styles.textColor,
                    halign = "center",
                    valign = "center",
                    characterLimit = 2,
                    editable = true,
                    width = "100%",
                    height = "100%",
                    textAlignment = "center",
                    cornerRadius = 15,
                    bgcolor = "black",
                    borderColor = Styles.textColor,
                    borderWidth = 2,
                    bgimage = true,
                    numeric = true,
                    flow = "none",
                    y = 90,

                    hover = function(element)
                        local desc = "Surges"
                        element.tooltip = gui.StatsHistoryTooltip{ description = desc, entries = m_token.properties:GetStatHistory(CharacterResource.surgeResourceId):GetHistory() }
                    end,

                    gui.Label{
                        bgimage = true,
                        bgcolor = "black",
                        bold = true,
                        fontSize = 9,
                        hpad = 1,
                        vpad = 1,
                        borderWidth = 1,
                        borderColor = Styles.textColor,
                        halign = "center",
                        valign = "bottom",
                        width = "auto",
                        height = "auto",
                        text = "Surges",
                        y = 7,
                    },


                    refreshCharacter = function(element, token)
                        local creature = token.properties
                        local resources = creature:GetAvailableSurges()
                        element.text = tostring(resources)
                    end,

                    change = function(element)
                        local amount = tonumber(element.text)
                        if amount == nil then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end

                        amount = math.max(0, round(amount))

                        local diff = amount - m_token.properties:GetAvailableSurges()
                        if diff == 0 then
                            element:FireEvent("refreshCharacter", m_token)
                            return
                        end
                        m_token:ModifyProperties{
                            description = "Change Surges",
                            execute = function()
                                m_token.properties:ConsumeSurges(-diff, "Manually Set")
                            end,
                        }

                        element:FireEvent("refreshCharacter", m_token)
                    end,
                },

            }
        },

		gui.Panel{
			y = 19,
			width = 34,
			height = 34,
			halign = "center",
			valign = "bottom",
			flow = "none",

			refreshCharacter = function(element, token)
				m_token = token
				element:SetClass("hidden", token == nil or (not token.valid) or token.properties == nil or token.properties.typeName ~= "character")
			end,

			gui.Panel{
				rotate = 45,
				width = "100%",
				height = "100%",
				bgimage = "panels/square.png",
				bgcolor = "black",
				x = -3,
				borderColor = Styles.textColor,
				borderWidth = 2,
			},

			gui.Label{
				fontSize = 22,
                textWrap = false,
				bold = true,
				color = Styles.textColor,
				halign = "center",
				valign = "center",
				characterLimit = 2,
				editable = true,
				width = "100%",
				height = "auto",
				textAlignment = "center",

				hover = gui.Tooltip("Victories"),

				refreshCharacter = function(element, token)
					if element.parent:HasClass("hidden") then
						return
					end

                    element.text = tostring(token.properties:GetVictories())
				end,

                change = function(element)
                    local n = tonumber(element.text)
					if n ~= nil and round(n) == n then
						m_token:BeginChanges()
						m_token.properties:SetVictories(n)
						m_token:CompleteChanges("Set Victories")
					end
					element.text = string.format("%d", m_token.properties:GetVictories())
				end,
			}

		}
	}
end

local g_edsSetting = setting{
	id = "eds",
	default = 50,
	min = 10,
	max = 1000,
	storage = "game",
}

local multiEditBaseFunction = CharacterPanel.CreateMultiEdit

local g_nseq = 0

CharacterPanel.CreateMultiEdit = function()
	if mod.unloaded then
		return multiEditBaseFunction()
	end

	g_nseq = g_nseq + 1
	local m_nseq = g_nseq


	local m_tokens
	local resultPanel

	local monsterSquadInput = gui.Input{
		fontSize = 16,
		placeholderText = "Enter name...",
		characterLimit = 24,
		selectAllOnFocus = true,
		width = 200,
		height = "auto",
		valign = "center",
		change = function(element)
			local squadid = trim(element.text)
			if squadid ~= "" then
				for _,tok in ipairs(m_tokens) do
					tok:ModifyProperties{
						description = "Set Squad",
						execute = function()
							tok.properties.minionSquad = squadid
						end,
					}
				end
			end
		end,
	}

	local m_selectedSquadId = nil
	local monsterSquadColorPicker = gui.ColorPicker{
		width = 24,
		height = 24,
		halign = "center",
		valign = "center",
		color = "white",
		confirm = function(element)
			local color = element.value.tostring
			for _,tok in ipairs(m_tokens) do
				tok:ModifyProperties{
					description = "Set Color",
					execute = function()
						DrawSteelMinion.SetSquadColor(m_selectedSquadId, color)
					end,
				}
			end

			--notify the game to update to show the new color.
			local monsterTokens = dmhub.GetTokens{
				unaffiliated = true,
			}

			local squadTokens = {}
			for _,tok in ipairs(monsterTokens) do
				if tok.properties.minion and tok.properties:MinionSquad() == m_selectedSquadId then
					squadTokens[#squadTokens+1] = tok.id
				end
			end

			if #squadTokens > 0 then
				game.Refresh{
					tokens = squadTokens,
				}
			end
		end,
	}

    local addToInitiativeButton = gui.Button{
        classes = {"collapsed"},
        width = 320,
        height = 30,
        text = "Add to Combat",
        tokens = function(element)
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                element:SetClass("collapsed", true)
                return
            end

            local hasNonCombatant = false
            for _,tok in ipairs(m_tokens) do
                if tok.properties:try_get("_tmp_initiativeStatus") == "NonCombatant" then
                    hasNonCombatant = true
                end
            end

            element:SetClass("collapsed", hasNonCombatant == false)
        end,

        click = function(element)
            Commands.rollinitiative()
        end,
    }

    local groupInitiativeButton = gui.Button{
        width = 320,
        height = 30,
        text = "Group Initiative",
        tokens = function(element)
            --don't show if tokens all share the same initiative already.
            local initiativeid = false
            for _,tok in ipairs(m_tokens) do
                if tok.properties.initiativeGrouping == false or (initiativeid ~= false and tok.properties.initiativeGrouping ~= initiativeid) then
                    element:SetClass("collapsed", false)
                    return
                end
                initiativeid = tok.properties.initiativeGrouping
            end

            element:SetClass("collapsed", true)
        end,

        click = function(element)
            local guid = dmhub.GenerateGuid()

            local hasPlayers = false
            local existingInitiative = {}
            local info = gamehud.initiativeInterface

            for _,tok in ipairs(m_tokens) do
                if tok.playerControlled then
                    hasPlayers = true
                end
            end

            if hasPlayers then
                --mark this initiativeid as being on the players side.
                guid = "PLAYERS-" .. guid
            end

            local tokens = DrawSteelMinion.GrowTokensToIncludeSquads(m_tokens)

            for _,tok in ipairs(tokens) do
                local initiativeid = InitiativeQueue.GetInitiativeId(tok)
                existingInitiative[initiativeid] = true
                tok:ModifyProperties{
                    description = "Set Initiative",
                    execute = function()
                        tok.properties.initiativeGrouping = guid
                    end,
                }
            end

            if info.initiativeQueue ~= nil and not info.initiativeQueue.hidden then

                for initiativeid,_ in pairs(existingInitiative) do
                    info.initiativeQueue:RemoveInitiative(initiativeid)
                end

                info.initiativeQueue:SetInitiative(guid, 0, 0)
                if hasPlayers then
			        local entry = info.initiativeQueue.entries[guid]
			        if entry ~= nil and entry:try_get("player") ~= true then
				        entry.player = true
			        end
                end

                info.UploadInitiative()
                
            end
        end,
    }

    local ungroupInitiativeButton = gui.Button{
        width = 320,
        height = 30,
        text = "Ungroup Initiative",
        tokens = function(element)
            local tokens = dmhub.allTokens
            local haveInitiativeGrouping = false

            --only allow ungrouping of initiative if there are multiple tokens sharing the
            --same id that are from different squads.
            for _,tok in ipairs(m_tokens) do
                if tok.properties.initiativeGrouping then
                    local squadsSeen = {}
                    local count = 0
                    for _,token in ipairs(tokens) do
                        if token.properties.initiativeGrouping == tok.properties.initiativeGrouping and (token.properties:MinionSquad() == nil or squadsSeen[token.properties:MinionSquad()] == nil) then
                            count = count+1

                            if token.properties:MinionSquad() ~= nil then
                                squadsSeen[token.properties:MinionSquad()] = true
                            end
                        end
                    end

                    if count > 1 then
                        haveInitiativeGrouping = true
                    end
                end
            end

            element:SetClass("collapsed", not haveInitiativeGrouping)
        end,

        click = function(element)
            local guid = dmhub.GenerateGuid()
            local q = dmhub.initiativeQueue

            local needsInitiativeRefresh = false
            for _,tok in ipairs(m_tokens) do
                tok:ModifyProperties{
                    description = "Set Initiative",
                    execute = function()
                        local haveInitiative = q ~= nil and (not q.hidden) and q:HasInitiative(InitiativeQueue.GetInitiativeId(tok))
                        tok.properties.initiativeGrouping = dmhub.GenerateGuid()
                        if haveInitiative then
                            needsInitiativeRefresh = true
                        end
                    end,
                }
            end

            if needsInitiativeRefresh then
                Commands.rollinitiative()
            end
        end,
    }



	local makeCaptainButton = gui.Button{
		width = 320,
		height = 30,
		text = "Make Captain",
		click = function(element)
            local initiativeGrouping = nil
            local allTokens =dmhub.allTokens

            local charids = {}
            for _,tok in ipairs(m_tokens) do
                charids[tok.charid] = true
            end
            local initiativeGroupingsSeen = {}

            --find an initiativeid that is available
			for _,tok in ipairs(m_tokens) do
                if tok.properties.initiativeGrouping and not initiativeGroupingsSeen[tok.properties.initiativeGrouping] then
                    local grouping = tok.properties.initiativeGrouping
                    local used = false
                    for _,otherTok in ipairs(allTokens) do
                        if otherTok.properties.initiativeGrouping == grouping and (not charids[otherTok.charid]) then
                            used = true
                            break
                        end
                    end

                    if not used then
                        initiativeGrouping = grouping
                        break
                    end
                end
            end

            if initiativeGrouping == false or element.text ~= "Make Captain" then
                initiativeGrouping = dmhub.GenerateGuid()
            end


            local groupid = dmhub.GenerateGuid()
			local captainid = nil
			for _,tok in ipairs(m_tokens) do
				if (not tok.properties.minion) then
					captainid = tok.id
					tok:ModifyProperties{
                        groupid = groupid,
						description = "Set Squad",
						execute = function()
                            tok.properties.initiativeGrouping = initiativeGrouping
							if element.text == "Make Captain" then
								tok.properties.minionSquad = m_selectedSquadId
							else
								tok.properties.minionSquad = nil
							end
						end,
					}
                elseif tok.properties.initiativeGrouping ~= initiativeGrouping and element.text == "Make Captain" then
                    tok:ModifyProperties{
                        groupid = groupid,
                        description = "Set Squad",
                        execute = function()
                            tok.properties.initiativeGrouping = initiativeGrouping
                        end,
                    }
				end
			end

			if captainid ~= nil then
				--search the map for any other captain and remove it.
				local monsterTokens = dmhub.GetTokens{}
				for _,tok in ipairs(monsterTokens) do
					if tok.id ~= captainid and (not tok.properties.minion) and tok.properties:MinionSquad() == m_selectedSquadId then
						tok:ModifyProperties{
							description = "Set Squad",
							execute = function()
								tok.properties.minionSquad = nil
							end,
						}
					end
				end
			end
		end,
	}

	local formSquadButton = gui.Button{
        classes = {"collapsed"},
		width = 320,
		height = 30,
		text = "Form Squad",
		click = function(element)
            DrawSteelMinion.FormSquad(dmhub.selectedOrPrimaryTokens)
		end,
	}


	local monsterSquadPanel = gui.Panel{
		height = 30,
		width = "100%",
		flow = "horizontal",
		tokens = function(element, tokens)
			local nminions = 0
			local monsterType = nil
			local squadid = nil
			local minionParty = nil
			local potentialCaptain = nil
			for _,tok in ipairs(tokens) do
				if (not tok.properties.minion) then
					potentialCaptain = tok
				end
				if tok.properties.minion and tok.properties:has_key("monster_type") and (monsterType == nil or tok.properties.monster_type == monsterType) then
					nminions = nminions + 1
					monsterType = tok.properties.monster_type
					if squadid == nil then
						squadid = tok.properties:MinionSquad()
					elseif squadid ~= tok.properties:MinionSquad() then
						squadid = false
					end

					if minionParty == nil then
						minionParty = tok.ownerId
					elseif minionParty ~= tok.ownerId then
						minionParty = false
					end
				end
			end

			local showCaptainButton = false

			if nminions == #tokens-1 and potentialCaptain ~= nil and potentialCaptain.ownerId == minionParty then
				showCaptainButton = true
				if squadid ~= false and squadid ~= nil and potentialCaptain.properties:MinionSquad() == squadid then
					--this is already the captain. Can edit this squad.
					nminions = nminions + 1
					makeCaptainButton.text = "Remove Captain"
				else
					makeCaptainButton.text = "Make Captain"
					m_selectedSquadId = squadid
				end
			end

			makeCaptainButton:SetClass("collapsed", not showCaptainButton)

            local shouldCollapse = nminions < #tokens
            local haveFormSquad = false

			if nminions == #tokens and squadid ~= nil then
				if squadid == false then
                    haveFormSquad = true
                    shouldCollapse = true
				else
					monsterSquadInput.text = squadid
					monsterSquadColorPicker:SetClass("hidden", false)
					monsterSquadColorPicker.value = DrawSteelMinion.GetSquadColor(squadid)
					m_selectedSquadId = squadid
				end
			end

			element:SetClass("collapsed", shouldCollapse)
            formSquadButton:SetClass("collapsed", not haveFormSquad)
		end,
		gui.Label{
			width = 60,
			height = "auto",
			text = "Squad:",
			fontSize = 14,
			valign = "center",
		},

		monsterSquadInput,

		monsterSquadColorPicker,
	}

	local monsterEVPanel = gui.Panel{
		height = "auto",
		width = "100%",
		flow = "horizontal",
		gui.Label{
			width = "auto",
			height = "auto",
			text = "",
			fontSize = 14,

			multimonitor = "eds",
			monitor = function(element)
				if m_tokens ~= nil then
					element:FireEvent("tokens", m_tokens)
				end
			end,

			tokens = function(element, tokens)
				local monsterTokens = {}
				for _,tok in ipairs(tokens) do
					if tok.properties:IsMonster() then
						monsterTokens[#monsterTokens+1] = tok
					end
				end

				if #monsterTokens == 0 then
					element.text = ""
					return
				end

				local ev = 0
				for _,tok in ipairs(monsterTokens) do
                    if tok.properties.minion then
					    ev = ev + tok.properties.ev/GameSystem.minionsPerSquad
                    else
					    ev = ev + tok.properties.ev
                    end
				end

                ev = round(ev)

				local edsDescription
				local eds = g_edsSetting:Get()

				if ev <= eds/2 then
					edsDescription = "<color=#66ff66>Trivial</color>"
				elseif ev <= eds then
					local val = ev
					while val % 5 ~= 0 do
						val = val + 1
					end

					if val - eds/2 >= eds - val then
						edsDescription = "<color=#ffff66>Standard</color>"
					else
						edsDescription = "<color=#66ff66>Easy</color>"
					end
				elseif ev <= eds + 10 then
					edsDescription = "<color=#ff6666>Hard</color>"
				else
					edsDescription = "<color=#990000>Extreme</color>"
				end

				element.text = string.format("%d monsters selected, EV: %d (<b>%s</b>)", #monsterTokens, ev, edsDescription)
			end,
		},
	}

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		tokens = function(element, tokens)
			m_tokens = tokens
			if #tokens <= 1 then
				element:SetClass("collapsed", true)
			else
				element:SetClass("collapsed", false)
                for _,child in ipairs(element.children) do
                    child:FireEventTree("tokens", tokens)
                end
			end
		end,

		multiEditBaseFunction(),

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

            addToInitiativeButton,
            groupInitiativeButton,
            ungroupInitiativeButton,
			makeCaptainButton,
            formSquadButton,
			monsterSquadPanel,

			gui.Panel{
				flow = "horizontal",
				width = "auto",
				height = "auto",
				gui.Label{
					width = "auto",
					height = "auto",
					text = "EDS:",
					fontSize = 14,
				},
				gui.Label{
					editable = true,
					width = 100,
					height = "auto",
					fontSize = 14,
					text = g_edsSetting:Get(),
					characterLimit = 3,
					multimonitor = "eds",
					monitor = function(element)
						element.text = tostring(g_edsSetting:Get())
					end,
					change = function(element)
						local n = tonumber(element.text)
						if n == nil or n < 10 or n > 1000 then
							element.text = tostring(g_edsSetting:Get())
							return
						end

						g_edsSetting:Set(n)
					end,
				}

			},
			monsterEVPanel,


		}
	}


	return resultPanel
end

CharacterPanel.PopulatePartyMembers = function(element, party, partyMembers, memberPanes)

	local m_folderPanels = element.data.folderPanels or {}
	element.data.folderPanels = m_folderPanels

	local newFolderPanels = {}

	local children = {}
	local newMemberPanes = {}

	for _,charid in ipairs(partyMembers) do

		local token = dmhub.GetCharacterById(charid)
		local creature = token.properties

		if creature ~= nil then
			local key = charid

			local folder = nil
			local squadid = creature:MinionSquad()

			if squadid ~= nil then
				key = squadid .. '-' .. charid

				folder = newFolderPanels[squadid]

				if folder == nil then

					folder = m_folderPanels[squadid]
					if folder == nil then
						local contentPanel = gui.Panel{
							width = "100%",
							height = "auto",
							flow = "vertical",
							halign = "center",
							vmargin = 4,
							hmargin = 4,
						}

						folder = gui.TreeNode{
							text = squadid,
							contentPanel = contentPanel,
							width = "100%-10",
							halign = "left",
							lmargin = 8,
							expanded = true,
							clickHeader = function(element)
								element:FireEventOnParents("ClearCharacterPanelSelection")
								local setFocus = false
								for _,p in ipairs(folder.data.children) do
									if not setFocus then
										gui.SetFocus(p)
										setFocus = true
									else
										element:FireEventOnParents("AddCharacterPanelToSelection", p)
									end
								end
							end,
						}

						local labels = folder:GetChildrenWithClassRecursive("folderLabel")
						for _,label in ipairs(labels) do
							label:SetClass("folderLabel", false)
							label:SetClass("bestiaryLabel", true)
						end

						folder.data.contentPanel = contentPanel
					end

					newFolderPanels[squadid] = folder

					--first time seeing this folder this refresh so re-init children.
					folder.data.children = {}
				end


			end

			local child = memberPanes[key] or CharacterPanel.CreateCharacterEntry(charid)
			newMemberPanes[key] = child
			child:FireEventTree("prepareRefresh")

			if folder ~= nil then
				folder.data.children[#folder.data.children+1] = child
			else
				children[#children+1] = child
			end
		end
	end

	table.sort(children, function(a,b)
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

	local folderChildren = {}
	for squadid,folder in pairs(newFolderPanels) do
		local newChildren = folder.data.children
		table.sort(newChildren, function(a,b)
			return a.data.token.description < b.data.token.description
		end)

		folder.data.contentPanel.children = newChildren
		folder.data.ord = squadid

		folderChildren[#folderChildren+1] = folder
	end

	for _,folder in ipairs(folderChildren) do
		children[#children+1] = folder
	end

	element.children = children

	element.data.folderPanels = newFolderPanels

	return newMemberPanes
end

function CharacterPanel.NotesPanel(token)
    local m_cache = nil
    local resultPanel
    resultPanel = gui.Label{
        width = "100%",
        height = "auto",
        fontSize = 12,
        tmargin = 8,
        markdown = true,
        links = true,
        press = function(element)
            if element.linkHovered ~= nil then
                dmhub.OpenTutorialVideo(element.linkHovered)
            end
        end,
        refreshToken = function(element, token)
            local creature = token.properties
            local notes = creature:try_get("notes")
            if dmhub.DeepEqual(m_cache, notes) then
                return
            end

            local text = ""
            m_cache = DeepCopy(notes)
            if notes ~= nil then
                for _,note in ipairs(notes) do
                    if note.text ~= nil and note.text ~= "" then
                        local s = ""
                        if text ~= "" then
                            s = "\n\n"
                        end

                        text = string.format("%s%s##### %s\n%s", s, text, note.title, note.text)
                    end
                end
            end

            element.text = text
        end,
    }

    return resultPanel
end

function CharacterPanel.AbilitiesPanel(token)
    local resultPanel

    local m_panels = {}

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		vmargin = 6,
		styles = {
			{
                selectors = {"notesLabel"},
				fontSize = 14,
                color = Styles.textColor,
                width = "90%",
                height = "auto",
                halign = "center",
			},
		},

        refreshToken = function(element, token)
            local creature = token.properties
            local features = creature:try_get("characterFeatures")
            if features == nil or #features == 0 then
                element:SetClass("collapsed", true)
            else
                element:SetClass("collapsed", false)

                local panelIndex = 1

                if creature.withCaptain and creature.minion then
                    local squad = creature:try_get("_tmp_minionSquad")
                    local hasCaptain = squad ~= nil and squad.hasCaptain
                    local panel = m_panels[panelIndex] or gui.Label{
                        classes = {"notesLabel"},
                        markdown = true,
                    }

                    local hasCaptainColor = cond(hasCaptain, "#ff", "#55")

                    local implemented = DrawSteelMinion.GetWithCaptainEffect(creature.withCaptain) ~= nil
                    local implementedColor = cond(implemented, "#ff", "#55")

                    panel.text = string.format("<b><alpha=%s>With Captain</b> <alpha=%s>%s<alpha=#ff>", hasCaptainColor, implementedColor, creature.withCaptain)

                    
                    panel:SetClass("collapsed", false)
                    m_panels[panelIndex] = panel
                    panelIndex = panelIndex + 1
                end

                for i,feature in ipairs(features) do
                    if feature.description ~= "" then
                        local panel = m_panels[panelIndex] or gui.Label{
                            classes = {"notesLabel"},
                            markdown = true,
                        }

                        local implemented = feature:try_get("implementation", 1) ~= 1
                        local implementedColor = cond(implemented, "#ff", "#55")

                        panel.text = string.format("<b>%s:</b> <alpha=%s>%s<alpha=#ff>", feature.name, implementedColor, feature.description)

                        panel:SetClass("collapsed", false)
                        m_panels[panelIndex] = panel
                        panelIndex = panelIndex + 1
                    end
                end

                for i=panelIndex,#m_panels do
                    m_panels[i]:SetClass("collapsed", true)
                end

                element.children = m_panels
            end
        end,
	}

    return resultPanel
end

function CharacterPanel.LanguagesPanel(token)
	local resultPanel

    resultPanel = gui.Label{
        width = "100%",
        height = "auto",
        textAlignment = "left",
        fontSize = 14,
		create = function(element)
			element:FireEvent("refreshToken", token)
		end,
		refreshToken = function(element, token)
            local text = "<b>Languages:</b> "
			local languagesTable = dmhub.GetTable(Language.tableName) or {}
            local first = true
            local languages = {}
            for langid,_ in pairs(token.properties:LanguagesKnown()) do
                local language = languagesTable[langid]
                if language then
                    languages[#languages+1] = language
                end
            end

            table.sort(languages, function(a,b)
                return a.name < b.name
            end)

            for _,language in ipairs(languages) do
                if not first then
                    text = text .. ", "
                end
                text = text .. language.name
                first = false
            end

            if first then
                text = text .. "None"
            end

            element.text = text
        end,
    }

    return resultPanel
end

function CharacterPanel.SkillsPanel(token)
	local resultPanel

	local panels = {}

	for _,cat in ipairs(Skill.categories) do
		local panel = gui.Label{
			width = "100%",
			height = "auto",
			textAlignment = "left",

			create = function(element)
				element:FireEvent("refreshToken", token)
			end,
			refreshToken = function(element, token)
				local proficiencyList = nil
				for i,skill in ipairs(Skill.SkillsInfo) do
					if skill.category == cat.id and token.properties:ProficientInSkill(skill) then
						if proficiencyList == nil then
							proficiencyList = skill.name
						else
							proficiencyList = proficiencyList .. ", " .. skill.name
						end
					end
				end
				
				if proficiencyList == nil then
					element:SetClass("collapsed", true)
				else
					element:SetClass("collapsed", false)
					element.text = string.format("<b>%s:</b> %s", cat.text, proficiencyList)
				end
			end,
		}

		panels[#panels+1] = panel
	end

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		vmargin = 6,
		styles = {
			{
				fontSize = 14,
			}
		},
		children = panels,
	}

	return resultPanel
end

local function GenerateAttributeCalculationTooltip(tokenInfo, name, GetBaseFunction, DescribeModificationsFunction)
    return function(element)
        local m_token = tokenInfo.token
        if m_token == nil or (not m_token.valid) then
            return
        end
        local baseValue = GetBaseFunction(m_token.properties)
        local modifications = DescribeModificationsFunction(m_token.properties)

        local panels = {}
        panels[#panels+1] = gui.Label{
            text = string.format("Base %s: %d", name, baseValue),
            width = "auto",
            height = "auto",
            fontSize = 14,
        }
        for _,modification in ipairs(modifications) do
            local text = string.format("%s: %s", modification.key, modification.value)
            panels[#panels+1] = gui.Label{
                text = text,
                width = "auto",
                height = "auto",
                fontSize = 14,
            }
        end

        local container = gui.Panel{
            width = "auto",
            height = "auto",
            flow = "vertical",
            children = panels,
        }

        element.tooltip = gui.TooltipFrame(container)
    end
end

local function GenerateCustomAttributeCalculationTooltip(tokenInfo, name)
    return GenerateAttributeCalculationTooltip(tokenInfo, name,
        function(c) return c:BaseNamedCustomAttribute(name) end,
        function(c) return c:DescribeModificationsToNamedCustomAttribute(name) end)
end

--important attributes beyond characteristics
--e.g. things like stability etc.
function CharacterPanel.ImportantAttributesPanel(token)
    local m_tokenInfo = {
        token = token,
    }
	local m_token = token

    local resultPanel

    local movementPanel = gui.Label{
        text = "Speed",
        hover = GenerateAttributeCalculationTooltip(m_tokenInfo, "Speed", creature.GetBaseSpeed, creature.DescribeSpeedModifications),
       
		refreshToken = function(element)
            local movementSpeed = m_token.properties:CurrentMovementSpeed()
			local info = m_token.properties.movementTypeById[m_token.properties:CurrentMoveType()]
            local movementTypeInfo = ""
            if info ~= nil and info.id ~= "walk" then
                movementTypeInfo = string.format(" (%s)", info.name)
            end
            element.text = string.format("<b>Movement:</b> %d%s", movementSpeed, movementTypeInfo)
        end,
        press = function(element)
            gui.PopupOverrideAttribute {
                parentElement = element,
                token = m_token,
                attributeName = "Speed",
                baseValue = m_token.properties:GetBaseSpeed(),
                modifications = m_token.properties:DescribeSpeedModifications(),
            }
        end,
    }

    local disengageSpeedPanel = gui.Label{
        bgimage = true,
        bgcolor = "clear",
        text = "Disengage",
        hover = GenerateCustomAttributeCalculationTooltip(m_tokenInfo, "Disengage Speed"),
		refreshToken = function(element)
            local customAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
            if customAttr ~= nil then
                local result = m_token.properties:GetCustomAttribute(customAttr)
                element.text = string.format("<b>Disengage:</b> %s", tostring(result))
            else
                element.text = ""
            end
        end,
        press = function(element)
            gui.PopupOverrideAttribute {
                parentElement = element,
                token = m_token,
                attributeName = "Disengage Speed",
            }
        end,
    }


    local stabilityPanel = gui.Label{
        hover = GenerateAttributeCalculationTooltip(m_tokenInfo, "Stability",
        creature.BaseForcedMoveResistance,
        function(c)
            return c:DescribeModifications("forcedmoveresistance", c:BaseForcedMoveResistance())
        end),

        press = function(element)
            local baseStability = m_token.properties:BaseForcedMoveResistance()
            gui.PopupOverrideAttribute {
                parentElement = element,
                token = m_token,
                attributeName = "Stability",
                baseValue = baseStability,
                modifications = m_token.properties:DescribeModifications("forcedmoveresistance", baseStability),
            }
        end,
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",

        styles = {
            {
                selectors = {"label"},
                fontSize = 14,
                width = "auto",
                height = "auto",
            },
        },

        movementPanel,
        disengageSpeedPanel,
        stabilityPanel,

		refreshToken = function(element, newToken)
            m_tokenInfo.token = newToken
            token = newToken
			m_token = newToken

            local stability = token.properties:Stability()
            stabilityPanel.text = string.format("<b>Stability:</b> %d", stability)
		end,
    }

    return resultPanel
end

function CharacterPanel.CharacteristicsPanel(token)

	local m_token = token

	local resultPanel

	local panels = {}

	for index,attrid in ipairs(creature.attributeIds) do
		local attrInfo = creature.attributesInfo[attrid]
		--local width = string.format("%.2f%%", (100/#creature.attributeIds))
		local halign = "center"
		if index == 1 then
			halign = "left"
		elseif index == #creature.attributeIds then
			halign = "right"
		end
		local panel = gui.Panel{
			width = "auto",
			height = "auto",
			halign = halign,
			flow = "vertical",
			bgimage = "panels/square.png",
			bgcolor = "clear",

			press = function(element)
				m_token.properties:ShowCharacteristicRollDialog(attrid)
			end,

            hover = function(element)
                if m_token == nil or (not m_token.valid) then
                    return
                end
                local text = ""
                local potency = m_token.properties:AttributeForPotencyResistance(attrid)
                if m_token.properties:GetAttribute(attrid):Modifier() ~= potency then
                    local attrName = creature.attributesInfo[attrid].description
                    text = string.format("Your %s counts as %s for resisting potencies.\nBasic Might Score: %d", attrName, ModifierStr(potency), m_token.properties:GetAttribute(attrid):Value())
                    local modifications = m_token.properties:AttributeForPotencyResistanceDescription(attrid)
                    for _,modification in ipairs(modifications) do
                        text = string.format("%s\n%s: %s", text, modification.key, modification.value)
                    end
                end

                if text ~= "" then
                    gui.Tooltip(text)(element)
                end
            end,

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                gui.Label{
                    text = attrInfo.description,
                    height = 14,
                    width = "auto",
                    halign = "center",
                },
                gui.Label{
                    classes = {"asterisk"},
                    text = "*",
                    valign = "top",
                    width = "auto",
                    height = "auto",
                    create = function(element)
                        element:FireEvent("refreshToken", token)
                    end,
                    refreshToken = function(element, token)
                        element:SetClass("collapsed", token.properties:GetAttribute(attrid):Modifier() == token.properties:AttributeForPotencyResistance(attrid))
                    end,
                },
            },
			gui.Label{
				text = "0",
				width = "auto",
				height = 14,
				halign = "center",
				valign = "center",
				minWidth = 20,
				lmargin = 4,
				textAlignment = "left",
				create = function(element)
					element:FireEvent("refreshToken", token)
				end,
				refreshToken = function(element, token)
					element.text = ModifierStr(token.properties:GetAttribute(attrid):Modifier())
				end,

			},
		}

		panels[#panels+1] = panel
	end

	resultPanel = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = "auto",

		styles = {
			{
				height = 18,
				fontSize = 11,
				bold = true,
				uppercase = true,
			},
			{
				selectors = {"label"},
				color = "#dddddd",
			},
            {
                selectors = {"asterisk"},
                color = "#ff00ff",
            },
			{
				selectors = {"label", "parent:hover"},
				color = "#ffffff",
			},
		},

		children = panels,
		refreshToken = function(element, newToken)
            token = newToken
			m_token = newToken
		end,
	}

	return resultPanel

end

function CharacterPanel.SingleCharacterDisplaySidePanel(token)

	local characterDisplaySidebar

	local conditionsPanel = CharacterPanel.CreateConditionsPanel(token)

	local summaryPanel = gui.Panel{
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

		gui.Panel{
			id = "LeftPanel",
			valign = "top",
			width = string.format("%f%% height", Styles.portraitWidthPercentOfHeight),
			height = 140,
			bgimage = "panels/square.png",
			bgcolor = "white",
            borderWidth = 0,
			lmargin = 16,

			refreshCharacter = function(element, token)
                local bg = token.portraitBackground
                if bg == nil or bg == "" then
                    element.selfStyle.bgcolor = "clear"
                else
                    element.bgimage = bg
                    element.selfStyle.bgcolor = "white"
                end
			end,

            gui.Panel{
                floating = true,
                width = "100%",
                height = "100%",
                bgcolor = "white",
			    borderWidth = 2,
			    borderColor = Styles.textColor,

                refreshCharacter = function(element, token)
                    local portrait = token.offTokenPortrait
                    element.bgimage = portrait

                    if portrait ~= token.portrait and not token.popoutPortrait then
                        element.selfStyle.imageRect = nil
                    else
                        element.selfStyle.imageRect = token:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight*0.01, portrait)
                    end
                end,
            },

			CharacterPanel.DecoratePortraitPanel(token),

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
                gui.Panel {

                    bgimage = true,
                    bgcolor = "clear",
                    height = 20,
                    width = "80%",
                    borderWidth = 0,
                    tmargin = 4,

                    flow = "horizontal",

                    refresh = function(element)
                        local tok = dmhub.currentToken
                        if tok ~= nil then
                            if (not tok.properties:CanFly()) and (not tok.canCurrentlyClimb) then
                                element:SetClass("collapsed", true)
                            else
                                element:SetClass("collapsed", false)
                            end
                        end
                    end,


                    gui.Label {

                        text = "Flying: ",
                        color = "white",
                        fontSize = 20,
                        fontFace = "newzald",
                        width = 80,

                        refresh = function(element)
                            local tok = dmhub.currentToken
                            if tok ~= nil then
                                if tok.properties:CanFly() then
                                    element.text = string.format("Flying: " .. tostring(tok.floorAltitude))
                                elseif tok.canCurrentlyClimb then
                                    element.text = string.format("Climb: " .. tostring(tok.floorAltitude))
                                end
                            end
                        end


                    },

                    gui.Button {
                        text = "-",
                        width = 16,
                        height = 16,


                        click = function()
                            local tok = dmhub.currentToken
                            if tok ~= nil then
                                if tok.properties:CanFly() then
                                    tok.properties:SetAndUploadCurrentMoveType("fly")
                                elseif tok.properties:CanClimb() then
                                    tok.properties:SetAndUploadCurrentMoveType("climb")
                                end

                                tok:MoveVertical(tok.floorAltitude - 1)
                            end
                        end

                    },

                    gui.Button {
                        text = "+",
                        width = 16,
                        height = 16,

                        click = function()
                            local tok = dmhub.currentToken
                            if tok ~= nil then
                                if tok.properties:CanFly() then
                                    tok.properties:SetAndUploadCurrentMoveType("fly")
                                elseif tok.properties:CanClimb() then
                                    tok.properties:SetAndUploadCurrentMoveType("climb")
                                end

                                tok:MoveVertical(tok.floorAltitude + 1)
                            end
                        end

                    }


                },

                gui.Button {
                    text = "Light",
                    width = 50,
                    height = "auto",
                    tmargin = 10,


                    refresh = function(element)
                        local tok = dmhub.currentToken

                        if tok == nil then
                            return
                        end

                        if tok.properties.selectedLoadout == 1 then
                            element.selfStyle.bgcolor = "white"
                            element.selfStyle.color = "black"
                        else
                            element.selfStyle.bgcolor = "clear"
                            element.selfStyle.color = "white"
                        end
                    end,

                    click = function()
                        Commands.light()
                    end

                },
			},
		}),

	}

	characterDisplaySidebar = gui.Panel{
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

        gui.Label{
            width = "100%",
            height = "auto",
            textAlignment = "center",
            fontSize = 16,
            minFontSize = 8,
            bold = true,
            halign = "center",
            vmargin = 4,

			refreshCharacter = function(element, token)
                local name = token:GetNameMaxLength(64)
                if name == nil or name == "" then
                    if token.properties:IsMonster() then
                        name = rawget(token.properties, "monster_type") or "Unknown Monster"
                    else
                        name = token.properties:RaceOrMonsterType()
                    end
                end
                element.text = name
            end,
        },
		summaryPanel,
	}

	return characterDisplaySidebar
end