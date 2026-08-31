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

--Geometry shared by a trigger's card and the heading boxes stacked on top of
--it, so the two line up exactly. triggerPanel declares its width without
--borderBox, so its padding sits outside the declared width and its outer width
--is the sum; the heading boxes use borderBox and declare that outer width
--directly.
local g_triggerCardWidth = 178
local g_triggerCardHPad = 6
local g_triggerCardOuterWidth = g_triggerCardWidth + g_triggerCardHPad*2

--How tall the card list may grow before it scrolls. An ability that offers one
--trigger per damaged target -- Parry against a multi-target hit, or a minion
--squad -- can produce a dozen at once, and without a bound they push the
--Dismiss bar off the bottom of the screen and paint over each other.
local g_triggerListMaxHeight = 520

--The scroller alone is wider than the cards, so its bar overhangs to the right
--of the stack rather than sitting over the card edge -- which is where the
--heroic resource cost diamond is. The container keeps the card width, so the
--cards stay put relative to the trigger button below them.
local g_triggerScrollbarWidth = 20
local g_triggerListWidth = g_triggerCardOuterWidth + g_triggerScrollbarWidth

-- Build the candidate retarget list for a triggered ability that changes its
-- target. Every token passing the all-inclusive changeTargetFilter is returned
-- in `targets`. A token that additionally fails one of the "reasoned" filters is
-- still returned (so the player can see it) but gets an entry in `reasons` keyed
-- by charid -- surfaced to the user as a tooltip explaining why it cannot be
-- chosen. This mirrors ActivatedAbility:TargetPassesFilter's reasonedFilters.
local function BuildRetargetCandidates(powerMod, symbols)
    local filterFormula = powerMod:try_get("changeTargetFilter")
    local reasonedFilters = powerMod:try_get("changeTargetReasonedFilters", {})
    local targets = {}
    local reasons = {}
    for _,potential in ipairs(dmhub.allTokens) do
        symbols.target = potential.properties:LookupSymbol{}
        if trim(filterFormula or "") == "" or GoblinScriptTrue(ExecuteGoblinScript(filterFormula, potential.properties:LookupSymbol(symbols), 1)) then
            targets[#targets+1] = potential
            for _,reasonedFilter in ipairs(reasonedFilters) do
                if trim(reasonedFilter.formula or "") ~= "" and not GoblinScriptTrue(ExecuteGoblinScript(reasonedFilter.formula, potential.properties:LookupSymbol(symbols), 1)) then
                    reasons[potential.charid] = StringInterpolateGoblinScript(reasonedFilter.reason, symbols)
                    break
                end
            end
        end
    end
    return targets, reasons
end

-- Opens the retarget picker for a trigger whose triggerBefore flow has
-- completed and marked the trigger as needing a new-target choice (the
-- serialized triggerBeforeRetarget flag, set by the trigger's own nested
-- ability -- e.g. Devilish Charm tier 1). Mirrors the immediate changeTarget
-- press flow below, but re-fetches the live trigger by id when the choice is
-- made so a stale snapshot can never be dispatched.
local function RunTriggerRetargetChoice(element, triggerToken, trigger)
    local targetToken = nil
    if #trigger.targets > 0 then
        targetToken = dmhub.GetTokenById(trigger.targets[1])
    end
    local casterToken = nil
    if trigger.casterid then
        casterToken = dmhub.GetTokenById(trigger.casterid)
    end
    if targetToken == nil or casterToken == nil then
        return
    end

    local symbols = {
        current = targetToken.properties:LookupSymbol{},
        triggerer = triggerToken.properties:LookupSymbol{},
        caster = casterToken.properties:LookupSymbol{},
    }
    local powerMod = trigger.powerRollModifier.powerRollModifier
    local targets, retargetReasons = BuildRetargetCandidates(powerMod, symbols)

    local sourceToken = triggerToken
    local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, triggerToken.properties:LookupSymbol(symbols), 10))
    local rangeType = powerMod:try_get("changeTargetRange", "none")
    if rangeType == "ability" then
        sourceToken = casterToken
        range = trigger.originalAbilityRange
    elseif rangeType == "distance" then
        range = powerMod:try_get("changeTargetDistance", 10)
    end

    local controller = element:Get("abilityController")
    if controller == nil then
        return
    end

    local trigid = trigger.id
    controller:FireEventTree("chooseTarget", {
        sourceToken = sourceToken,
        radius = range,
        targets = targets,
        reasons = retargetReasons,
        choose = function(newTargetToken)
            if triggerToken == nil or not triggerToken.valid then
                return
            end

            triggerToken:ModifyProperties{
                undoable = false,
                description = "Trigger",
                execute = function()
                    local live = triggerToken.properties:GetAvailableTriggers() or {}
                    local t = live[trigid]
                    if t == nil then
                        return
                    end
                    t.triggered = true
                    t.retargetid = newTargetToken.charid
                    t.triggerBeforeRetarget = false
                    triggerToken.properties:DispatchAvailableTrigger(t)
                end,
            }
        end,

        cancel = function()
        end,
    })
end

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

mod.shared.hostileTriggerGradient = gui.Gradient{
    type = "radial",
    point_a = {x = 0.5, y = 0.5},
    point_b = {x = 1, y = 0.5},
    stops = {
        {
            position = 0,
            color = "srgb:#570808",
        },
        {
            position = 1,
            color = "srgb:#2D0C0C",
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

    --The cards scroll in here rather than in the panel that also holds the
    --Dismiss bar, so a long list never pushes that bar out of reach.
    local triggerListPanel = gui.Panel{
        width = g_triggerListWidth,
        height = "auto",
        maxHeight = g_triggerListMaxHeight,
        flow = "vertical",
        valign = "bottom",
        vscroll = true,
    }

	local activeTriggersPanel

	activeTriggersPanel = gui.Panel{
		floating = true,
		width = g_triggerCardOuterWidth,
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
                    width = g_triggerCardOuterWidth,
                    height = 24,
                    halign = "left",
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
                    width = g_triggerCardWidth,
                    minHeight = 44,
                    height = "auto",
                    vpad = 6,
                    hpad = g_triggerCardHPad,
                    vmargin = 0,
                    halign = "left",
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
                --pseudohover deliberately has no highlight of its own. An option
                --card sets it on the trigger's first card so that card's hover
                --handler runs (ability preview + line-of-sight rays) and so its
                --dehover knows an option is still hovered -- but the first card
                --is a mode card like any other, so highlighting it while the
                --pointer is on a sibling made two cards look hovered at once.
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
                --The heading boxes above a multi-mode trigger's cards: one for
                --the trigger's own name and one for its prompt, both of which
                --would otherwise displace the name and rules of the first
                --mode's card. They read as the top of the stack of cards rather
                --than as separate floating boxes, so they take the card's outer
                --width and no bottom margin -- the boxes and the first card butt
                --together exactly as the cards do against each other.
                {
                    selectors = {"triggerHeadingPanel"},
                    width = g_triggerCardOuterWidth,
                    height = "auto",
                    halign = "center",
                    valign = "bottom",
                    vpad = 4,
                    hpad = g_triggerCardHPad,
                    vmargin = 0,
                    borderBox = true,
                    flow = "vertical",
                    bgimage = true,
                    bgcolor = "#1D1D1D",
                    borderColor = "#606060",
                    --per-edge widths only, no borderWidth: a blanket borderWidth
                    --overrides them and re-draws all four edges.
                    border = {x1 = 2, y1 = 2, x2 = 2, y2 = 2},
                },
                --The title and prompt are one header block, so a hairline
                --divides them instead of the doubled 2px seam that separates one
                --mode card from the next.
                {
                    selectors = {"triggerHeadingPanel", "triggerHeadingJoined"},
                    border = {x1 = 2, y1 = 1, x2 = 2, y2 = 2},
                },
                {
                    selectors = {"triggerHeadingPanel", "triggerPromptBox"},
                    border = {x1 = 2, y1 = 2, x2 = 2, y2 = 0},
                },
                {
                    selectors = {"triggerHeadingLabel"},
                    width = "100%",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",
                    fontSize = 14,
                    bold = true,
                    color = Styles.textColor,
                    textWrap = true,
                },
                {
                    selectors = {"triggerPromptLabel"},
                    width = "100%",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    textAlignment = "center",
                    fontSize = 12,
                    color = Styles.textColor,
                    textWrap = true,
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
                --A mode whose condition is not currently met is still offered:
                --it is dimmed and carries a note saying so, but remains
                --pressable so the player can override it.
                {
                    selectors = {"triggerPanel", "unavailableMode"},
                    bgcolor = "#141414",
                    borderColor = "#4A4A4A",
                },
                {
                    selectors = {"triggerTitle", "unavailableMode"},
                    color = "#8C8C8C",
                },
                {
                    selectors = {"triggerRules", "unavailableMode"},
                    color = "#8C8C8C",
                },
                {
                    selectors = {"triggerUnavailableNote"},
                    width = "auto",
                    height = "auto",
                    maxWidth = 140,
                    hmargin = 0,
                    tmargin = 0,
                    bmargin = 4,
                    fontSize = 11,
                    italics = true,
                    color = g_forbiddenColor,
                    textWrap = true,
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
					selectors = {"triggerButton", "unavailableMode"},
					color = "#8C8C8C",
					borderColor = "#4A4A4A",
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

            --Both declared here so they are parented from construction; refresh
            --only ever re-fills the scroller's children.
            triggerListPanel,
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
							--A trigger with several modes draws one card per mode. The
							--trigger's own name and prompt then move to heading boxes
							--above the group, so that this first card can carry the
							--first mode's name and rules rather than being anonymised
							--by the trigger's.
							local usesModeHeading = trigger:UsesModeHeading()
							local cardTitle = trigger:GetText()
							local cardRules = trigger:GetRulesText()
							if usesModeHeading then
								cardTitle = trigger.activateText
								cardRules = trigger.activateRules
							end

							--The trigger's own resource cost, shown in the diamond on
							--the edge of its card.
							local resourceCost = trigger.heroicResourceCost ~= 0 and trigger.heroicResourceCost or trigger.epicResourceCost

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


                                    if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") and not trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
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
                                        local targets, retargetReasons = BuildRetargetCandidates(trigger.powerRollModifier.powerRollModifier, symbols)

                                        local sourceToken = g_token
                                        local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
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
                                            reasons = retargetReasons,
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

                                                    --If the trigger-before flow marked this trigger as needing a
                                                    --new-target choice (the serialized triggerBeforeRetarget flag,
                                                    --set by the nested ability's own logic -- e.g. Devilish Charm
                                                    --tier 1), open the retarget picker now. Read the live trigger
                                                    --from the token: the panel's availableTriggers snapshot may
                                                    --predate the nested ability's dispatch.
                                                    if triggerToken.valid then
                                                        local live = triggerToken.properties:GetAvailableTriggers() or {}
                                                        local freshTrigger = live[key]
                                                        if freshTrigger ~= nil and freshTrigger:try_get("triggerBeforeRetarget", false)
                                                                and freshTrigger.powerRollModifier
                                                                and freshTrigger.powerRollModifier.powerRollModifier:try_get("changeTarget")
                                                                and not freshTrigger.retargetid then
                                                            RunTriggerRetargetChoice(parentElement, triggerToken, freshTrigger)
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

							--hideEnhancementOptions (on the powertabletrigger modifier) is an
							--opt-in for triggers whose outcome is decided by a nested
							--trigger-before ability (e.g. Devilish Charm's Presence test):
							--the additional cost modifiers still exist as outcome data, but
							--they are not offered as manually pressable options.
							local enhancementOptions = {}
							if not (trigger.powerRollModifier and trigger.powerRollModifier:try_get("hideEnhancementOptions", false)) then
								enhancementOptions = trigger:EnhancementOptions(g_token)
							end
							for index,option in ipairs(enhancementOptions) do
								buttons[#buttons+1] = gui.Label{
									classes = {"triggerButton", cond(option.unavailable == true, "unavailableMode")},
									text = option.text,
									hover = gui.Tooltip(cond(option.unavailable == true, tostring(option.conditionReason or "") .. "\n\n" .. tostring(option.rules), option.rules)),
									press = function(element)

                                        --Strict action economy makes an unavailable mode truly
                                        --unavailable: players cannot press it to override.
                                        --Directors bypass this so they can still allow it,
                                        --matching the action bar's strict:resources handling.
                                        if option.unavailable == true and (not dmhub.isDM) and dmhub.GetSettingValue("strict:resources") then
                                            return
                                        end

                                        audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                        if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") and not trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
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
                                            local targets, retargetReasons = BuildRetargetCandidates(trigger.powerRollModifier.powerRollModifier, symbols)

                                            local sourceToken = g_token
                                            local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
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
                                                reasons = retargetReasons,
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
                            local isHostile = trigger.hostile

                            --A trigger prompt ages out after a fixed window (which
                            --resets whenever the user interacts with any trigger --
                            --see ActiveTrigger.RefreshAllTimers). Once a prompt is
                            --inside the warning window this drains a thin bar across
                            --the top of it so it is obvious the prompt is about to
                            --disappear. The bar itself is never collapsed, since a
                            --collapsed panel gets no think events -- only the fill is.
                            local expiryBarFill = gui.Panel{
                                classes = {"collapsed"},
                                interactable = false,
                                bgimage = true,
                                halign = "left",
                                valign = "center",
                                width = "100%",
                                height = "100%",
                                bgcolor = g_accentColor,
                            }

                            local expiryBar = gui.Panel{
                                floating = true,
                                interactable = false,
                                bgimage = true,
                                halign = "center",
                                valign = "top",
                                --the panel has vpad = 6; pull the bar back up so it
                                --sits just inside the top border rather than adrift
                                --in the padding.
                                vmargin = -4,
                                width = "100%",
                                height = 3,
                                bgcolor = "clear",
                                thinkTime = 0.1,
                                think = function(element)
                                    local fraction = nil
                                    if availableTriggers ~= nil then
                                        local trigger = availableTriggers[key]
                                        if trigger ~= nil then
                                            fraction = trigger:ExpiryWarningFraction()
                                        end
                                    end

                                    if fraction == nil then
                                        if not expiryBarFill:HasClass("collapsed") then
                                            expiryBarFill:SetClass("collapsed", true)
                                            element.selfStyle.bgcolor = "clear"
                                        end
                                        return
                                    end

                                    expiryBarFill:SetClass("collapsed", false)
                                    element.selfStyle.bgcolor = "#00000060"
                                    expiryBarFill.selfStyle.width = string.format("%.2f%%", fraction*100)
                                    expiryBarFill.selfStyle.bgcolor = cond(fraction < 0.25, g_forbiddenColor, g_accentColor)
                                end,

                                expiryBarFill,
                            }

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

                                    if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") and not trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
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
                                        local targets, retargetReasons = BuildRetargetCandidates(trigger.powerRollModifier.powerRollModifier, symbols)

                                        local sourceToken = g_token
                                        local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
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
                                            reasons = retargetReasons,
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

                                                    --If the trigger-before flow marked this trigger as needing a
                                                    --new-target choice (the serialized triggerBeforeRetarget flag,
                                                    --set by the nested ability's own logic -- e.g. Devilish Charm
                                                    --tier 1), open the retarget picker now. Read the live trigger
                                                    --from the token: the panel's availableTriggers snapshot may
                                                    --predate the nested ability's dispatch.
                                                    if triggerToken.valid then
                                                        local live = triggerToken.properties:GetAvailableTriggers() or {}
                                                        local freshTrigger = live[key]
                                                        if freshTrigger ~= nil and freshTrigger:try_get("triggerBeforeRetarget", false)
                                                                and freshTrigger.powerRollModifier
                                                                and freshTrigger.powerRollModifier.powerRollModifier:try_get("changeTarget")
                                                                and not freshTrigger.retargetid then
                                                            RunTriggerRetargetChoice(parentElement, triggerToken, freshTrigger)
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

                                    if dismiss then
                                        triggerPanel:SetClass("collapsed", true)
                                    end

                                    local menu = element:FindParentWithClass("customActionBar")
                                    if menu ~= nil then
                                        menu:FireEventTree("hideability", trigger)
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

                                expiryBar,

                                gui.Button{
                                    classes = {"closeButton", "sizeS", "triggerCloseButton"},
                                    floating = true,
                                    halign = "right",
                                    valign = "top",
                                    hmargin = -3,
                                    vmargin = -3,
                                    --the reveal rule must name triggerCloseButton: styles cascade to
                                    --descendants, and the themed closeButton is an iconButton chrome
                                    --panel wrapping a buttonIcon child that owns the X glyph. Without
                                    --the marker class the rule also matches that child, whose "parent"
                                    --is the button rather than the trigger panel -- so the glyph stayed
                                    --hidden unless the mouse was directly on the button.
                                    styles = {
                                        {
                                            selectors = {"triggerCloseButton", "~parent:hover", "~hover"},
                                            hidden = 1,
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

        gui.Panel{
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
        },

        --icon panel.
        gui.Label{
            textAlignment = "center",
            color = cond(isHostile, "srgb:#FF4040", cond(isPassive, "srgb:#00a300", cond(trigger.free, "srgb:3097FF", "srgb:#FF9730"))),
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
            gradient = cond(isHostile, mod.shared.hostileTriggerGradient, cond(isPassive, mod.shared.passiveTriggerGradient, cond(trigger.free, mod.shared.freeTriggerGradient, mod.shared.triggerGradient))),

        },


        --main layout panel.
        gui.Panel{
            flow = "vertical",
            height = "auto",
            width = "100%-36",
								gui.Label{
									classes = {"triggerTitle"},
                                    interactable = false,
									text = cardTitle,
								},
								gui.Label{
									classes = {"triggerRules"},
                                    markdown = true,
									text = StringInterpolateGoblinScript(cardRules, g_token.properties:LookupSymbol{}),
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

                            local children = {}

                            if usesModeHeading then
                                local promptText = StringInterpolateGoblinScript(trigger:GetRulesText(), g_token.properties:LookupSymbol{})
                                local hasPrompt = trim(promptText or "") ~= ""

                                --The title only gives up its full bottom edge to a
                                --prompt box below it; standing alone it meets the
                                --first mode card and keeps the card seam.
                                children[#children+1] = gui.Panel{
                                    classes = {"triggerHeadingPanel", cond(hasPrompt, "triggerHeadingJoined")},
                                    blurBackground = true,
                                    interactable = false,
                                    gui.Label{
                                        classes = {"triggerHeadingLabel"},
                                        text = trigger:GetText(),
                                    },
                                }

                                if hasPrompt then
                                    children[#children+1] = gui.Panel{
                                        classes = {"triggerHeadingPanel", "triggerPromptBox"},
                                        blurBackground = true,
                                        interactable = false,
                                        gui.Label{
                                            classes = {"triggerPromptLabel"},
                                            markdown = true,
                                            text = promptText,
                                        },
                                    }
                                end
                            end

                            children[#children+1] = triggerPanel

							--hideEnhancementOptions (on the powertabletrigger modifier) is an
							--opt-in for triggers whose outcome is decided by a nested
							--trigger-before ability (e.g. Devilish Charm's Presence test):
							--the additional cost modifiers still exist as outcome data, but
							--they are not offered as manually pressable options.
							local enhancementOptions = {}
							if not (trigger.powerRollModifier and trigger.powerRollModifier:try_get("hideEnhancementOptions", false)) then
								enhancementOptions = trigger:EnhancementOptions(g_token)
							end
							for index,option in ipairs(enhancementOptions) do
								--A mode whose condition is not met is offered anyway,
								--dimmed and annotated, and stays pressable: the table
								--can always agree to allow it.
								local unavailable = option.unavailable == true

								children[#children+1] = gui.Panel{
									classes = {"triggerPanel", cond(unavailable, "unavailableMode")},

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
                                        color = cond(isHostile, "srgb:#FF4040", cond(isPassive, "srgb:#00a300", cond(trigger.free, "srgb:3097FF", "srgb:#FF9730"))),
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
                                        gradient = cond(isHostile, mod.shared.hostileTriggerGradient, cond(isPassive, mod.shared.passiveTriggerGradient, cond(trigger.free, mod.shared.freeTriggerGradient, mod.shared.triggerGradient))),
                                    },

                                    gui.Panel{
                                        flow = "vertical",
                                        height = "auto",
                                        width = "100%-36",
                                        gui.Label{
                                            classes = {"triggerTitle", cond(unavailable, "unavailableMode")},
                                            text = option.text,
                                        },
                                        gui.Label{
                                            classes = {"triggerRules", cond(unavailable, "unavailableMode")},
                                            markdown = true,
                                            text = StringInterpolateGoblinScript(option.rules, g_token.properties:LookupSymbol{}),
                                        },
                                        gui.Label{
                                            classes = {"triggerUnavailableNote", cond(not unavailable, "collapsed")},
                                            interactable = false,
                                            markdown = true,
                                            text = tostring(option.conditionReason or ""),
                                        },
                                    },

        --A mode-driven trigger's options carry no cost of their own: choosing any
        --one of the modes costs the trigger's own resource cost, so every card
        --shows the same diamond as the first one. A powerRollModifier trigger's
        --options are extra resource spends, so they price themselves.
        (function()
            local optionCost = option.cost
            local optionIsEpic = false
            if optionCost == nil then
                optionCost = resourceCost
                optionIsEpic = trigger.epicResourceCost ~= 0
            end
            return gui.Panel{
            classes = {"costDiamond", cond(optionCost == 0, "hidden")},
            floating = true,
            rotate = 135,
            gui.Panel{
                classes = {"costInnerDiamond", cond(optionIsEpic, "epicCost")},
                gui.Label{
                    classes = {"abilityCostLabel"},
                    rotate = -135,
                    text = optionCost,

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



									press = function(element)

                                        --Strict action economy makes an unavailable mode truly
                                        --unavailable: players cannot press it to override.
                                        --Directors bypass this so they can still allow it,
                                        --matching the action bar's strict:resources handling.
                                        if unavailable and (not dmhub.isDM) and dmhub.GetSettingValue("strict:resources") then
                                            return
                                        end

                                        audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                        if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") and not trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
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
                                            local targets, retargetReasons = BuildRetargetCandidates(trigger.powerRollModifier.powerRollModifier, symbols)

                                            local sourceToken = g_token
                                            local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
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
                                                reasons = retargetReasons,
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

                --Cards into the scroller, Dismiss bar outside it so it stays put.
                triggerListPanel.children = children
				element.children = {triggerListPanel, dismissAllPanel}
				m_activeTriggerPanels = newTriggerPanels
			end,
		}
	}

    return activeTriggersPanel
end