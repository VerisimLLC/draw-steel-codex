local mod = dmhub.GetModLoading()

local g_token = nil

local g_blurColor = "#000000cc"
local g_blurColorHighlight = "#000000ee"

local g_goldColor = "srgb:#966D4B"
local g_accentColor = "srgb:#e9b86f"
local g_blurColor = "srgb:#000000cc"
local g_blurColorHighlight = "srgb:#000000ee"
local g_borderColor = "srgb:#A48B74"
local g_forbiddenColor = "srgb:#C73131"

mod.shared.triggerGradient = gui.Gradient{
    type = "radial",
    point_a = {x = 0.5, y = 0.5},
    point_b = {x = 1, y = 0.5},
    stops = {
        {
            position = 0,
            color = "srgb:#573108",
        },
        {
            position = 1,
            color = "srgb:#2D140C",
        }
    }
}


mod.shared.freeTriggerGradient = gui.Gradient{
    type = "radial",
    point_a = {x = 0.5, y = 0.5},
    point_b = {x = 1, y = 0.5},
    stops = {
        {
            position = 0,
            color = "srgb:#083157",
        },
        {
            position = 1,
            color = "srgb:#0C142D",
        }
    }
}

mod.shared.passiveTriggerGradient = gui.Gradient{
    type = "radial",
    point_a = {x = 0.5, y = 0.5},
    point_b = {x = 1, y = 0.5},
    stops = {
        {
            position = 0,
            color = "srgb:#085708",
        },
        {
            position = 1,
            color = "srgb:#0C2D0C",
        }
    }
}

mod.shared.CreateTriggerPanel = function()

	local m_activeTriggerPanels = {}
	local availableTriggers = nil

    local dismissAllPanel = gui.Label{
        classes = {"dismissAllPanel"},
        text = "Dismiss Triggers",
        press = function(element)
            if g_token == nil or not g_token.valid then
                return
            end

            g_token:ModifyProperties{
                undoable = false,
                description = "Dismiss All Triggers",
                execute = function()
                    for _,trigger in pairs(g_token.properties:GetAvailableTriggers() or {}) do
                        trigger.dismissed = true
                        g_token.properties:DispatchAvailableTrigger(trigger)
                    end
                end,
            }
        end,
    }

	local activeTriggersPanel

	activeTriggersPanel = gui.Panel{
		floating = true,
		width = 190,
		height = 1,
		vmargin = -20,
		halign = "left",
		valign = "top",
        data = {
            hasTriggers = false,
        },
		gui.Panel{
			width = "100%",
			height = "auto",
            maxHeight = 800,
			valign = "bottom",
            flow = "vertical",
			styles = {
                {
                    selectors = {"dismissAllPanel"},
                    width = 190,
                    height = 24,
                    halign = "center",
                    fontSize = 14,
                    vpad = 4,
                    hpad = 8,

					bgimage = true,
                    bgcolor = "#1D1D1D",
                    borderColor = "#606060",
                    borderWidth = 2,
                },
                {
                    selectors = {"dismissAllPanel", "hover"},
                    borderColor = "white",
                },
				{
					selectors = {"triggerPanel"},
                    width = 178,
                    minHeight = 44,
                    height = "auto",
                    vpad = 6,
                    hpad = 6,
                    vmargin = 0,
                    halign = "center",
                    valign = "bottom",
                    bgimage = true,

                    bgcolor = "#1D1D1D",
                    borderColor = "#606060",
                    borderWidth = 2,
                    flow = "horizontal",
				},
                {
                    selectors = {"triggerPanel", "hover"},
                    borderColor = "white",
                },
                {
                    selectors = {"triggerPanel", "pseudohover"},
                    borderColor = "white",
                },
                {
                    selectors = {"triggerPanel", "press"},
                    brightness = 2,
                },
				{
					selectors = {"triggerPanel", "ping"},
					bgcolor = "#aa00aaaa",
				},
				{
					selectors = {"triggerPanel", "ping", "pong"},
					brightness = 2,
				},
                {
                    selectors = {"triggerTitle"},
                    fontSize = 14,
                    color = Styles.textColor,
                    bold = true,
                    textWrap = true,
                    width = "100%-4",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                },
				{
					selectors = {"triggerLabel"},
					width = "auto",
					height = "auto",
					margin = 2,
					fontSize = 14,
				},
				{
					selectors = {"triggerRules"},
					width = "auto",
					height = "auto",
					hmargin = 0,
					tmargin = 0,
					bmargin = 4,
					fontSize = 12,
					maxWidth = 140,
				},
				{
					selectors = {"triggerButton"},
					halign = "left",
					margin = 4,
					fontSize = 12,
					borderWidth = 1,
					width = "auto",
					height = "auto",
					pad = 2,
					textAlignment = "center",
					bgimage = "panels/square.png",
					color = Styles.textColor,
					borderColor = Styles.textColor,
					bgcolor = Styles.backgroundColor,
				},
				{
					selectors = {"triggerButton", "hover"},
					color = Styles.backgroundColor,
					bgcolor = Styles.textColor,
				},
				{
					selectors = {"triggerButton", "selected"},
					color = Styles.backgroundColor,
					bgcolor = Styles.textColor,
				},

    gui.Style{
        classes = {"costDiamond"},
        width = 30,
        height = "100% width",
        halign = "right",
        valign = "center",
        hmargin = -20,
        bgimage = true,
        borderColor = "#606060",
        bgcolor = "#1D1D1D",
        border = {x1 = 2, y1 = 2, x2 = 0, y2 = 0},
    },
    gui.Style{
        classes = {"costDiamond", "parent:hover"},
        brightness = 1.5,
        borderColor = "white",
    },
    gui.Style{
        classes = {"costInnerDiamond"},
        width = "65%",
        height = "65%",
        bgimage = true,
        halign = "center",
        valign = "center",
        bgcolor = "#e9b86f",
        borderWidth = 1,
        borderColor = "#966D4B",
    },

    gui.Style{
        classes = {"costInnerDiamond", "epicCost"},
        bgcolor = "#6fa8e9",
        borderColor = "#4B6D96",
    },
    gui.Style{
        classes = {"costInnerDiamond", "cannotAfford"},
        bgcolor = g_forbiddenColor,
        borderColor = "white",
    },
        gui.Style{
        classes = {"abilityCostLabel"},
        halign = "center",
        valign = "center",
        textAlignment = "center",
        bold = true,
        color = "white",
        fontSize = 16,
        minFontSize = 6,
        textWrap = false,
        width = "100%",
        height = "100%",
    },




                Styles.TriggerStyles,
			},

            dismissAllPanel,

			refresh = function(element)
                g_token = dmhub.selectedOrPrimaryTokens[1]

                local parentElement = element
				if g_token == nil or not g_token.valid then
					element:SetClass("collapsed", true)
                    activeTriggersPanel.data.hasTriggers = false
					return
				end
				availableTriggers = g_token.properties:GetAvailableTriggers()

				if availableTriggers == nil then
					element:SetClass("collapsed", true)
                    activeTriggersPanel.data.hasTriggers = false
					return
				end


				local children = {}

				local newTriggerPanels = {}
				for key,trigger in pairs(availableTriggers) do
					if not trigger.dismissed then
						local panel = m_activeTriggerPanels[key]
						
						if panel == nil then
							local targetPanels = {}
							for _,target in ipairs(trigger.targets) do
								local token = dmhub.GetTokenById(target)
								targetPanels[#targetPanels+1] = gui.Panel{
									width = 48,
									height = 48,
									hmargin = 2,
									gui.CreateTokenImage(token, {
										width = 40,
										height = 40,
										halign = "center",
										valign = "center",
									}),
								}
							end

                            if #targetPanels > 0 then
                                targetPanels[#targetPanels+1] = gui.Panel{
                                    refresh = function(element)
                                        if availableTriggers == nil then
                                            return
                                        end
                                        local trigger = availableTriggers[key]
                                        if trigger ~= nil and trigger.retargetid then
                                            element:SetClass("collapsed", false)
                                        else
                                            element:SetClass("collapsed", true)
                                        end
                                    end,
                                    bgimage = "panels/triangle.png",
                                    bgcolor = "red",
                                    width = 16,
                                    height = 16,
                                    rotate = 90,
                                    valign = "center",
                                    halign = "left",
                                    hmargin = 8,
                                }

                                targetPanels[#targetPanels+1] = gui.Panel{
                                    width = 48,
                                    height = 48,
                                    hmargin = 2,
                                    gui.CreateTokenImage(nil, {
                                        refresh = function(element)
                                            if availableTriggers == nil then
                                                return
                                            end
                                            local trigger = availableTriggers[key]
                                            if trigger ~= nil and trigger.retargetid then
                                                local token = dmhub.GetTokenById(trigger.retargetid)
                                                element:FireEventTree("token", token)
                                                element:SetClass("collapsed", false)
                                            else
                                                element:SetClass("collapsed", true)
                                            end
                                        end,
                                        width = 40,
                                        height = 40,
                                        halign = "center",
                                        valign = "center",
                                    }),
                                }
                            end

							local buttons = {}
							buttons[#buttons+1] = gui.Label{
								classes = {"triggerButton"},
								text = trigger.activateText,
								press = function(element)

                                    audio.DispatchSoundEvent("Notify.TriggerUse", {})


                                    if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") then
                                        --this changes the target of the trigger.
								        local targetToken = dmhub.GetTokenById(trigger.targets[1])
                                        local casterToken = dmhub.GetTokenById(trigger.casterid)
                                        if targetToken == nil then
                                            return
                                        end
                                        local symbols = {
                                            current = targetToken.properties:LookupSymbol{},
                                            triggerer = g_token.properties:LookupSymbol{},
                                            caster = casterToken.properties:LookupSymbol{},
                                        }
                                        local filterFormula = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetFilter")
                                        local targets = {}
                                        for _,potential in ipairs(dmhub.allTokens) do
                                            symbols.target = potential.properties:LookupSymbol{}
                                            if trim(filterFormula) == "" or GoblinScriptTrue(ExecuteGoblinScript(filterFormula, potential.properties:LookupSymbol(symbols), 1)) then
                                                targets[#targets+1] = potential
                                            end
                                        end

                                        local sourceToken = g_token
                                        local range = tonumber(trigger.powerRollModifier.range)
                                        local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                        if rangeType == "ability" then
                                            sourceToken = dmhub.GetTokenById(trigger.casterid)
                                            range = trigger.originalAbilityRange
                                        elseif rangeType == "distance" then
                                            range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                        end

                                        element:Get("abilityController"):FireEventTree("chooseTarget", {
                                            sourceToken = sourceToken,
                                            radius = range,
                                            targets = targets,
                                            choose = function(newTargetToken)
                                                if g_token == nil then
                                                    return
                                                end

                                                g_token:ModifyProperties{
                                                    undoable = false,
                                                    description = "Trigger",
                                                    execute = function()
                                                        trigger.triggered = true
                                                        trigger.retargetid = newTargetToken.charid

                                                        g_token.properties:DispatchAvailableTrigger(trigger)
                                                    end,
                                                }

                                            end,

                                            cancel = function()
                                            end,
                                        })

                                        return
                                    end --end of changing target of trigger.

                                    local dismiss = trigger:DismissOnTrigger()

                                    if trigger.powerRollModifier and trigger.powerRollModifier:try_get("forceReroll", false) then
                                        dismiss = true
                                    end

                                    if (not trigger.triggered) and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
                                        --if we trigger some action before the trigger.
                                        local triggerBefore = trigger.powerRollModifier.powerRollModifier:try_get("triggerBefore")
                                        local triggerToken = g_token

                                        --we commit to it if we use the trigger so we disappear the trigger.
                                        dismiss = true

                                        triggerBefore:Trigger(trigger.powerRollModifier.powerRollModifier, g_token.properties, trigger.powerRollModifier.powerRollModifier:AppendSymbols{}, nil, { mod = trigger.powerRollModifier }, {
                                            complete = function()
                                                if parentElement ~= nil and parentElement.valid then
                                                    if availableTriggers == nil then
                                                        return
                                                    end
                                                    local trigger = availableTriggers[key]
                                                    if trigger == nil then
                                                        return
                                                    end

                                                    local condition = trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("triggerBeforeCondition", "")
                                                    if trim(condition) ~= "" and triggerToken.valid then
                                                        local target = nil
                                                        if #trigger.targets > 0 then
                                                            target = dmhub.GetTokenById(trigger.targets[1])
                                                        end
                                                        local caster = dmhub.GetTokenById(trigger.casterid)
                                                        if target == nil or caster == nil then
                                                            return
                                                        end
                                                        local symbols = {
                                                            triggerer = triggerToken.properties:LookupSymbol{},
                                                            caster = caster.properties:LookupSymbol{},
                                                            target = target.properties:LookupSymbol{},
                                                        }

                                                        local passed = GoblinScriptTrue(ExecuteGoblinScript(condition, triggerToken.properties:LookupSymbol(symbols), 1))
                                                        if (not passed) and trigger.triggered then
                                                            --after the trigger, we didn't meet the criteria for it to apply so it is canceled.
                                                            triggerToken:ModifyProperties{
                                                                undoable = false,
                                                                description = "Trigger",
                                                                execute = function()
                                                                    trigger.triggered = false
                                                                    trigger.retargetid = nil
                                                                    triggerToken.properties:DispatchAvailableTrigger(trigger)
                                                                end,
                                                            }
                                                        end
                                                    end
                                                end
                                            end,
                                        })
                                    end

									g_token:ModifyProperties{
										undoable = false,
										description = "Trigger",
										execute = function()

                                            trigger.dismissed = dismiss

                                            if trigger.triggered then
                                                trigger.triggered = false
                                                trigger.retargetid = nil
                                            else
                                                trigger.triggered = true
                                            end
											g_token.properties:DispatchAvailableTrigger(trigger)
										end,
									}

								end,
								refresh = function(element)
									if availableTriggers == nil then
										return
									end
									local trigger = availableTriggers[key]
									element:SetClass("selected", trigger ~= nil and trigger.triggered ~= false)
								end,
							}

							local enhancementOptions = trigger:EnhancementOptions(g_token)
							for index,option in ipairs(enhancementOptions) do
								buttons[#buttons+1] = gui.Label{
									classes = {"triggerButton"},
									text = option.text,
									hover = gui.Tooltip(option.rules),
									press = function(element)

                                        audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                        if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") then
                                            --this changes the target of the trigger.
                                            local targetToken = dmhub.GetTokenById(trigger.targets[1])
                                            local casterToken = dmhub.GetTokenById(trigger.casterid)
                                            if targetToken == nil then
                                                return
                                            end
                                            local symbols = {
                                                current = targetToken.properties:LookupSymbol{},
                                                triggerer = g_token.properties:LookupSymbol{},
                                                caster = casterToken.properties:LookupSymbol{},
                                            }
                                            local filterFormula = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetFilter")
                                            local targets = {}
                                            for _,potential in ipairs(dmhub.allTokens) do
                                                symbols.target = potential.properties:LookupSymbol{}
                                                if trim(filterFormula) == "" or GoblinScriptTrue(ExecuteGoblinScript(filterFormula, potential.properties:LookupSymbol(symbols), 1)) then
                                                    targets[#targets+1] = potential
                                                end
                                            end

                                            local sourceToken = g_token
                                            local range = tonumber(trigger.powerRollModifier.range)
                                            local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                            if rangeType == "ability" then
                                                sourceToken = dmhub.GetTokenById(trigger.casterid)
                                                range = trigger.originalAbilityRange
                                            elseif rangeType == "distance" then
                                                range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                            end

                                            element:Get("abilityController"):FireEventTree("chooseTarget", {
                                                sourceToken = sourceToken,
                                                radius = range,
                                                targets = targets,
                                                choose = function(newTargetToken)
                                                    if g_token == nil then
                                                        return
                                                    end

                                                    g_token:ModifyProperties{
                                                        undoable = false,
                                                        description = "Trigger",
                                                        execute = function()

                                                            trigger.triggered = index
                                                            trigger.retargetid = newTargetToken.charid

                                                            g_token.properties:DispatchAvailableTrigger(trigger)
                                                        end,
                                                    }

                                                end,

                                                cancel = function()
                                                end,
                                            })

                                            return
                                        end



										g_token:ModifyProperties{
											undoable = false,
											description = "Trigger",
											execute = function()
                                                if trigger.triggered == index then
                                                    trigger.triggered = true
                                                else
                                                    trigger.triggered = index
                                                end

												g_token.properties:DispatchAvailableTrigger(trigger)
											end,
										}	
									end,
									refresh = function(element)
										if availableTriggers == nil then
											return
										end
										local trigger = availableTriggers[key]	
										element:SetClass("selected", trigger ~= nil and trigger.triggered == index)
									end,	
								}
							end

							buttons[#buttons+1] = gui.Label{
								classes = {"triggerButton"},
								text = "Dismiss",
								press = function(element)
									g_token:ModifyProperties{
										undoable = false,
										description = "Trigger",
										execute = function()
									        trigger.triggered = false
									        trigger.dismissed = true
											g_token.properties:DispatchAvailableTrigger(trigger)
										end,
									}	
								end,
								refresh = function(element)
									if availableTriggers == nil then
										return
									end
									local trigger = availableTriggers[key]	
									element:SetClass("collapsed", trigger ~= nil and trigger.triggered ~= false)
								end,	
							}



							local m_ping = trigger.ping
                            local isPassive = trigger.powerRollModifier and trigger.powerRollModifier.type == "passive"

                            local triggerPanel
							triggerPanel = gui.Panel{
                                data = {
                                    ord = trigger.timestamp,
                                    rays = {},
                                },
								classes = {"triggerPanel"},
                                blurBackground = true,

                                hover = function(element)
                                    element:FireEvent("dehover")

									if availableTriggers == nil then
										return
									end

									local trigger = availableTriggers[key]	
                                    if trigger == nil then
                                        return
                                    end

                                    local menu = element:FindParentWithClass("customActionBar")
                                    if menu ~= nil then
                                        menu:FireEventTree("showability", trigger)
                                    end

                                    for _,targetid in ipairs(trigger.targets or {}) do
                                        local target = dmhub.GetTokenById(targetid)
                                        if target ~= nil then
                                            local ray = dmhub.MarkLineOfSight(g_token, target, g_token.properties:GetPierceWalls())
                                            element.data.rays[#element.data.rays+1] = ray
                                        end
                                    end
                                end,

                                dehover = function(element)
                                    for _,ray in ipairs(element.data.rays) do
                                        ray:Destroy()
                                    end
                                    element.data.rays = {}

                                    local menu = element:FindParentWithClass("customActionBar")
                                    if menu ~= nil and not element:HasClass("pseudohover") then
                                        menu:FireEventTree("hideability", trigger)
                                    end
                                end,

                                press = function(element)
                                    print("TRIGGER:: PRESS")

                                    audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                    if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") then
                                        --this changes the target of the trigger.
								        local targetToken = dmhub.GetTokenById(trigger.targets[1])
                                        local casterToken = dmhub.GetTokenById(trigger.casterid)
                                        if targetToken == nil then
                                            return
                                        end
                                        local symbols = {
                                            current = targetToken.properties:LookupSymbol{},
                                            triggerer = g_token.properties:LookupSymbol{},
                                            caster = casterToken.properties:LookupSymbol{},
                                        }
                                        local filterFormula = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetFilter")
                                        local targets = {}
                                        for _,potential in ipairs(dmhub.allTokens) do
                                            symbols.target = potential.properties:LookupSymbol{}
                                            if trim(filterFormula) == "" or GoblinScriptTrue(ExecuteGoblinScript(filterFormula, potential.properties:LookupSymbol(symbols), 1)) then
                                                targets[#targets+1] = potential
                                            end
                                        end

                                        local sourceToken = g_token
                                        local range = tonumber(trigger.powerRollModifier.range)
                                        local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                        if rangeType == "ability" then
                                            sourceToken = dmhub.GetTokenById(trigger.casterid)
                                            range = trigger.originalAbilityRange
                                        elseif rangeType == "distance" then
                                            range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                        end

                                        element:Get("abilityController"):FireEventTree("chooseTarget", {
                                            sourceToken = sourceToken,
                                            radius = range,
                                            targets = targets,
                                            choose = function(newTargetToken)
                                                if g_token == nil then
                                                    return
                                                end

                                                g_token:ModifyProperties{
                                                    undoable = false,
                                                    description = "Trigger",
                                                    execute = function()
                                                        trigger.triggered = true
                                                        trigger.retargetid = newTargetToken.charid

                                                        g_token.properties:DispatchAvailableTrigger(trigger)
                                                    end,
                                                }

                                            end,

                                            cancel = function()
                                            end,
                                        })

                                        return
                                    end --end of changing target of trigger.

                                    local dismiss = trigger:DismissOnTrigger()

                                    --just always dismiss on click?
                                    if trigger.powerRollModifier then --and trigger.powerRollModifier:try_get("forceReroll", false) then
                                        dismiss = true
                                    end

                                    if (not trigger.triggered) and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
                                        --if we trigger some action before the trigger.
                                        local triggerBefore = trigger.powerRollModifier.powerRollModifier:try_get("triggerBefore")
                                        local triggerToken = g_token

                                        --we commit to it if we use the trigger so we disappear the trigger.
                                        dismiss = true

                                        triggerBefore:Trigger(trigger.powerRollModifier.powerRollModifier, g_token.properties, trigger.powerRollModifier.powerRollModifier:AppendSymbols{}, nil, { mod = trigger.powerRollModifier }, {
                                            complete = function()
                                                if parentElement ~= nil and parentElement.valid then
                                                    if availableTriggers == nil then
                                                        return
                                                    end
                                                    local trigger = availableTriggers[key]
                                                    if trigger == nil then
                                                        return
                                                    end

                                                    local condition = trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("triggerBeforeCondition", "")
                                                    if trim(condition) ~= "" and triggerToken.valid then
                                                        local target = nil
                                                        if #trigger.targets > 0 then
                                                            target = dmhub.GetTokenById(trigger.targets[1])
                                                        end
                                                        local caster = dmhub.GetTokenById(trigger.casterid)
                                                        if target == nil or caster == nil then
                                                            return
                                                        end
                                                        local symbols = {
                                                            triggerer = triggerToken.properties:LookupSymbol{},
                                                            caster = caster.properties:LookupSymbol{},
                                                            target = target.properties:LookupSymbol{},
                                                        }

                                                        local passed = GoblinScriptTrue(ExecuteGoblinScript(condition, triggerToken.properties:LookupSymbol(symbols), 1))
                                                        if (not passed) and trigger.triggered then
                                                            --after the trigger, we didn't meet the criteria for it to apply so it is canceled.
                                                            triggerToken:ModifyProperties{
                                                                undoable = false,
                                                                description = "Trigger",
                                                                execute = function()
                                                                    trigger.triggered = false
                                                                    trigger.retargetid = nil
                                                                    triggerToken.properties:DispatchAvailableTrigger(trigger)
                                                                end,
                                                            }
                                                        end
                                                    end
                                                end
                                            end,
                                        })
                                    end

									g_token:ModifyProperties{
										undoable = false,
										description = "Trigger",
										execute = function()

                                            trigger.dismissed = dismiss

                                            if trigger.triggered then
                                                trigger.triggered = false
                                                trigger.retargetid = nil
                                            else
                                                trigger.triggered = true
                                            end
											g_token.properties:DispatchAvailableTrigger(trigger)
										end,
									}

                                    print("TRIGGER:: DISMISS =", dismiss)
                                    if dismiss then
                                        triggerPanel:SetClass("collapsed", true)
                                        print("TRIGGER:: COLLAPSE")
                                    end
                                end,

								refresh = function(element)
									if availableTriggers == nil then
										return
									end

									local trigger = availableTriggers[key]	
                                    if trigger == nil then
                                        return
                                    end

									if m_ping ~= trigger.ping then
										m_ping = trigger.ping
										element:FireEvent("ping", 12)
									end
								end,

								ping = function(element, count)
									if count > 1 then
										element:SetClass("ping", true)
										element:SetClass("pong", not element:HasClass("pong"))
					
										element:ScheduleEvent("ping", 0.25, count-1)
									else
										element:SetClass("ping", false)
										element:SetClass("pong", false)
									end					
								end,

                                gui.CloseButton{
                                    floating = true,
                                    halign = "right",
                                    valign = "top",
                                    hmargin = -3,
                                    vmargin = -3,
                                    width = 16,
                                    height = 16,
                                    styles = {
                                        {
                                            selectors = {"~parent:hover", "~hover"},
                                            hidden = 1,
                                        },
                                        {
                                            selectors = {"~hover"},
                                            brightness = 0.7,
                                        },
                                    },
                                    swallowPress = true,
                                    press = function(element)
                                        g_token:ModifyProperties{
                                            undoable = false,
                                            description = "Trigger",
                                            execute = function()
                                                trigger.triggered = false
                                                trigger.dismissed = true
                                                g_token.properties:DispatchAvailableTrigger(trigger)
                                            end,
                                        }	
                                    end,
                                },

        (function()
            local resourceCost = trigger.heroicResourceCost ~= 0 and trigger.heroicResourceCost or trigger.epicResourceCost
            return gui.Panel{
            classes = {"costDiamond", cond(resourceCost == 0, "hidden")},
            floating = true,
            rotate = 135,
            gui.Panel{
                classes = {"costInnerDiamond", cond(trigger.epicResourceCost ~= 0, "epicCost")},
                gui.Label{
                    classes = {"abilityCostLabel"},
                    rotate = -135,
                    text = cond(resourceCost == 0, "!", resourceCost),

                    ability = function(element, ability)
--[[
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element.parent.parent:SetClass("collapsed", true)
                            SetCannotAfford(false)
                            return
                        end

                        element.parent.parent:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                        ]]
                    end,
                },
            },
        }
        end)(),

        --icon panel.
        gui.Label{
            textAlignment = "center",
            color = cond(isPassive, "srgb:#00a300", cond(trigger.free, "srgb:3097FF", "srgb:#FF9730")),
            bold = true,
            text = "!",
            fontSize = 24,
            width = 28,
            height = "100% width",
            valign = "center",
            halign = "left",
            hmargin = 4,
            bgimage = true,
            bgcolor = "white",
            borderWidth = 1,
            borderColor = "black",
            gradient = cond(isPassive, mod.shared.passiveTriggerGradient, cond(trigger.free, mod.shared.freeTriggerGradient, mod.shared.triggerGradient)),

        },


        --main layout panel.
        gui.Panel{
            flow = "vertical",
            height = "auto",
            width = "100%-36",
								gui.Label{
									classes = {"triggerTitle"},
                                    interactable = false,
									text = trigger:GetText(),
								},
								gui.Label{
									classes = {"triggerRules"},
                                    markdown = true,
									text = StringInterpolateGoblinScript(trigger:GetRulesText(), g_token.properties:LookupSymbol{}),
								},
								gui.Panel{
									width = "100%",
									height = "auto",
									wrap = true,
									flow = "horizontal",
									children = targetPanels,
								},
								gui.Panel{
                                    classes = {"collapsed"},
									width = "100%",
									height = "auto",
									bmargin = 4,
									flow = "horizontal",
									children = buttons,
								},
                            }
							}

                            local children = {triggerPanel}

							local enhancementOptions = trigger:EnhancementOptions(g_token)
							for index,option in ipairs(enhancementOptions) do
								children[#children+1] = gui.Panel{
									classes = {"triggerPanel"},

                                    hover = function(element)
                                        triggerPanel:SetClass("pseudohover", true)
                                        triggerPanel:FireEvent("hover")
                                    end,
                                    dehover = function(element)
                                        triggerPanel:SetClass("pseudohover", false)
                                        if not triggerPanel:HasClass("hover") then
                                            triggerPanel:FireEvent("dehover")
                                        end
                                    end,

                                    gui.Label{
                                        textAlignment = "center",
                                        color = cond(isPassive, "srgb:#00a300", cond(trigger.free, "srgb:3097FF", "srgb:#FF9730")),
                                        bold = true,
                                        text = "!",
                                        fontSize = 24,
                                        width = 28,
                                        height = "100% width",
                                        valign = "center",
                                        halign = "left",
                                        hmargin = 4,
                                        bgimage = true,
                                        bgcolor = "white",
                                        borderWidth = 1,
                                        borderColor = "black",
                                        gradient = cond(isPassive, mod.shared.passiveTriggerGradient, cond(trigger.free, mod.shared.freeTriggerGradient, mod.shared.triggerGradient)),
                                    },

                                    gui.Panel{
                                        flow = "vertical",
                                        height = "auto",
                                        width = "100%-36",
                                        gui.Label{
                                            classes = {"triggerTitle"},
                                            text = option.text,
                                        },
                                        gui.Label{
                                            classes = {"triggerRules"},
                                            markdown = true,
                                            text = StringInterpolateGoblinScript(option.rules, g_token.properties:LookupSymbol{}),
                                        },
                                    },

        gui.Panel{
            classes = {"costDiamond", cond(option.cost == 0, "hidden")},
            floating = true,
            rotate = 135,
            gui.Panel{
                classes = {"costInnerDiamond"},
                gui.Label{
                    classes = {"abilityCostLabel"},
                    rotate = -135,
                    text = option.cost,
                    create = function(element)
                        print("TARGETS:: OPTION", option)
                    end,

                    ability = function(element, ability)
--[[
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element.parent.parent:SetClass("collapsed", true)
                            SetCannotAfford(false)
                            return
                        end

                        element.parent.parent:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                        ]]
                    end,
                },
            },
        },



									press = function(element)

                                        audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                        if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") then
                                            --this changes the target of the trigger.
                                            local targetToken = dmhub.GetTokenById(trigger.targets[1])
                                            local casterToken = dmhub.GetTokenById(trigger.casterid)
                                            if targetToken == nil then
                                                return
                                            end
                                            local symbols = {
                                                current = targetToken.properties:LookupSymbol{},
                                                triggerer = g_token.properties:LookupSymbol{},
                                                caster = casterToken.properties:LookupSymbol{},
                                            }
                                            local filterFormula = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetFilter")
                                            local targets = {}
                                            for _,potential in ipairs(dmhub.allTokens) do
                                                symbols.target = potential.properties:LookupSymbol{}
                                                if trim(filterFormula) == "" or GoblinScriptTrue(ExecuteGoblinScript(filterFormula, potential.properties:LookupSymbol(symbols), 1)) then
                                                    targets[#targets+1] = potential
                                                end
                                            end

                                            local sourceToken = g_token
                                            local range = tonumber(trigger.powerRollModifier.range)
                                            local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                            if rangeType == "ability" then
                                                sourceToken = dmhub.GetTokenById(trigger.casterid)
                                                range = trigger.originalAbilityRange
                                            elseif rangeType == "distance" then
                                                range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                            end

                                            element:Get("abilityController"):FireEventTree("chooseTarget", {
                                                sourceToken = sourceToken,
                                                radius = range,
                                                targets = targets,
                                                choose = function(newTargetToken)
                                                    if g_token == nil then
                                                        return
                                                    end

                                                    g_token:ModifyProperties{
                                                        undoable = false,
                                                        description = "Trigger",
                                                        execute = function()

                                                            trigger.triggered = index
                                                            trigger.retargetid = newTargetToken.charid

                                                            g_token.properties:DispatchAvailableTrigger(trigger)
                                                        end,
                                                    }

                                                end,

                                                cancel = function()
                                                end,
                                            })

                                            return
                                        end



										g_token:ModifyProperties{
											undoable = false,
											description = "Trigger",
											execute = function()
                                                if trigger.triggered == index then
                                                    trigger.triggered = true
                                                else
                                                    trigger.triggered = index
                                                end

                                                --just always dismiss on click?
                                                if trigger.powerRollModifier then --and trigger.powerRollModifier:try_get("forceReroll", false) then
                                                    trigger.dismissed = true
                                                end

												g_token.properties:DispatchAvailableTrigger(trigger)
											end,
										}	
									end,
									refresh = function(element)
										if availableTriggers == nil then
											return
										end
										local trigger = availableTriggers[key]	
										element:SetClass("selected", trigger ~= nil and trigger.triggered == index)
									end,	
								}
							end


                            panel = gui.Panel{
                                width = "auto",
                                height = "auto",
                                flow = "vertical",
                                vmargin = 4,
                                children = children,
                            }
						end

						newTriggerPanels[key] = panel
						children[#children+1] = panel	
					end
				end

				table.sort(children, function(a,b) return (tonumber(a.data.ord) or 0) < (tonumber(b.data.ord) or 0) end)

				element:SetClass("collapsed", #children == 0)
                activeTriggersPanel.data.hasTriggers = #children > 0

                children[#children+1] = dismissAllPanel

				element.children = children
				m_activeTriggerPanels = newTriggerPanels
			end,
		}
	}

    return activeTriggersPanel
end