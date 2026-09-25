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

--Candidate portraits on a trigger card. A merged prompt can offer half the
--party at once, so these are sized to fit three per row across the card
--rather than to show a single target large.
local g_triggerPortraitSize = 34
local g_triggerPortraitImageSize = 28
local g_triggerPortraitMargin = 1

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
                    reasons[potential.charid] = ActivatedAbility.FormatFilterReason(reasonedFilter, symbols)
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
-- made so a stale snapshot can never be dispatched. targetId is the target
-- being redirected away from.
local function RunTriggerRetargetChoice(element, triggerToken, trigger, targetId)
    targetId = targetId or trigger:GetTargetId()
    local targetToken = nil
    if targetId ~= nil then
        targetToken = dmhub.GetTokenById(targetId)
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
    RuleUtils.RemoveRetargetStrikeTargets(targets, trigger, targetId)
    local allowOriginal = RuleUtils.RetargetAllowsOriginal(trigger)

    local sourceToken = triggerToken
    local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, triggerToken.properties:LookupSymbol(symbols), 10))
    local rangeType = powerMod:try_get("changeTargetRange", "none")
    if rangeType == "ability" then
        sourceToken = casterToken
        range = trigger.originalAbilityRange
    elseif rangeType == "distance" then
        range = powerMod:try_get("changeTargetDistance", 10)
    end
    --the new target must be one the striking creature could actually
    --hit: inside the strike's distance and in its line of effect.
    if rangeType == "ability" then
        RuleUtils.AddRetargetRangeReasons(targets, retargetReasons, sourceToken, range)
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
        prompt = RuleUtils.RetargetPromptText(sourceToken, range, rangeType, allowOriginal),
        autoPickSole = true,
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
                    --resolution is now complete; release the caster's roll hold.
                    t.resolving = false
                    triggerToken.properties:DispatchAvailableTrigger(t)
                end,
            }
        end,

        cancel = function()
            --the choice was abandoned: withdraw the resolving hold so the
            --caster's roll doesn't keep waiting on a picker nobody is using.
            if triggerToken == nil or not triggerToken.valid then
                return
            end
            triggerToken:ModifyProperties{
                undoable = false,
                description = "Trigger",
                execute = function()
                    local live = triggerToken.properties:GetAvailableTriggers() or {}
                    local t = live[trigid]
                    if t ~= nil and t.resolving then
                        t.resolving = false
                        triggerToken.properties:DispatchAvailableTrigger(t)
                    end
                end,
            }
        end,
    })
end

-- A triggered action offered against several targets of one roll (Parry when a
-- strike damages three allies) is a single prompt. Pressing it first asks, on
-- the map, which target it is for; the card's press then runs again with the
-- picked charid as its second argument.
-- candidateIds narrows the offer to part of the prompt's targets: a merged
-- card's modes can each apply to a different set of subjects.
local function ChooseTriggerTarget(element, triggerToken, trigger, candidateIds)
    local candidates = {}
    for _,targetid in ipairs(candidateIds or trigger.targets) do
        local tok = dmhub.GetTokenById(targetid)
        if tok ~= nil and tok.valid then
            candidates[#candidates+1] = tok
        end
    end

    local controller = element:Get("abilityController")
    if #candidates == 0 or controller == nil then
        return
    end

    controller:FireEventTree("chooseTarget", {
        sourceToken = triggerToken,
        targets = candidates,
        prompt = string.format("Choose a target for %s", tostring(trigger:GetText())),
        choose = function(targetToken)
            --The picker now tears itself down before handing the pick on, so the
            --press runs straight away; a card rebuilt in the meantime is gone and
            --there is nothing to press.
            if mod.unloaded or not element.valid then
                return
            end
            element:FireEvent("press", targetToken.charid)
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
                        --a hostile prompt under strict action economy must be accepted, not dismissed.
                        if trigger:CanDismiss() then
                            trigger.dismissed = true
                            g_token.properties:DispatchAvailableTrigger(trigger)
                        end
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

				--the Dismiss Triggers bar only shows while something on the list
				--can actually be dismissed (hostile prompts under strict action
				--economy cannot be).
				local anyDismissable = false

				local newTriggerPanels = {}
				for key,trigger in pairs(availableTriggers) do
					--mergedInto marks a prompt folded into another one's card, so the
					--group draws once. Should that card be gone, show this one anyway:
					--an uncollapsed group beats a prompt nobody can reach.
					local hidden = false
					if trigger.mergedInto ~= false then
						local front = availableTriggers[trigger.mergedInto]
						hidden = front ~= nil and (not front.dismissed)
					end

					if not trigger.dismissed and not hidden then
						if trigger:CanDismiss() then
							anyDismissable = true
						end
						local panel = m_activeTriggerPanels[key]

						--A shared prompt's candidate targets can change mid-roll (a
						--target's roll stops meeting the trigger's requirement), so
						--rebuild its card to keep the portraits and the picker current.
						local targetsKey = table.concat(trigger.targets, ",")
						if panel ~= nil and panel.data.targetsKey ~= targetsKey then
							panel = nil
						end

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
								--a candidate that has despawned draws an empty cell in the grid, and
								--the picker refuses it anyway, so leave it out entirely.
								if token ~= nil and token.valid then
									targetPanels[#targetPanels+1] = gui.Panel{
										width = g_triggerPortraitSize,
										height = g_triggerPortraitSize,
										hmargin = g_triggerPortraitMargin,
										--of several candidates, only the one picked stays shown; one that
										--dies while the card is up drops out as well.
										refresh = function(element)
											local live = availableTriggers ~= nil and availableTriggers[key] or nil
											local tok = dmhub.GetTokenById(target)
											local hide = tok == nil or (not tok.valid)
											if (not hide) and live ~= nil then
												hide = live.chosenTargetId ~= false and live.chosenTargetId ~= target
											end

											element:SetClass("collapsed", hide)
										end,
										gui.CreateTokenImage(token, {
											width = g_triggerPortraitImageSize,
											height = g_triggerPortraitImageSize,
											halign = "center",
											valign = "center",
										}),
									}
								end
							end

                            if #targetPanels > 0 then
                                targetPanels[#targetPanels+1] = gui.Panel{
                                    --only shown once a retarget is picked, so it must start hidden:
                                    --until refresh first runs it would hold a cell in the grid.
                                    classes = {"collapsed"},
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
                                    width = g_triggerPortraitSize,
                                    height = g_triggerPortraitSize,
                                    hmargin = g_triggerPortraitMargin,
                                    --the wrapper has to collapse too, not just the image inside it:
                                    --a hidden image still leaves its cell in the portrait grid.
                                    classes = {"collapsed"},
                                    refresh = function(element)
                                        local live = availableTriggers ~= nil and availableTriggers[key] or nil
                                        element:SetClass("collapsed", live == nil or (not live.retargetid))
                                    end,
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
                                        width = g_triggerPortraitImageSize,
                                        height = g_triggerPortraitImageSize,
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
                                        RuleUtils.RemoveRetargetStrikeTargets(targets, trigger, trigger.targets[1])
                                        local allowOriginal = RuleUtils.RetargetAllowsOriginal(trigger)

                                        local sourceToken = g_token
                                        local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
                                        local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                        if rangeType == "ability" then
                                            sourceToken = dmhub.GetTokenById(trigger.casterid)
                                            range = trigger.originalAbilityRange
                                        elseif rangeType == "distance" then
                                            range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                        end
                                        --the new target must be one the striking creature could actually
                                        --hit: inside the strike's distance and in its line of effect.
                                        if rangeType == "ability" then
                                            RuleUtils.AddRetargetRangeReasons(targets, retargetReasons, sourceToken, range)
                                        end

                                        element:Get("abilityController"):FireEventTree("chooseTarget", {
                                            sourceToken = sourceToken,
                                            radius = range,
                                            targets = targets,
                                            reasons = retargetReasons,
                                            prompt = RuleUtils.RetargetPromptText(sourceToken, range, rangeType, allowOriginal),
                                            autoPickSole = true,
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
                                                        --choosing the new target commits the trigger, so the card leaves the drawer.
                                                        trigger.dismissed = true

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

                                    --set when we start a trigger-before action below: the accept then
                                    --flags the record as resolving, holding the caster's roll until
                                    --the complete callback clears it.
                                    local waitingOnTriggerBefore = false

                                    if (not trigger.triggered) and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
                                        --if we trigger some action before the trigger.
                                        local triggerBefore = trigger.powerRollModifier.powerRollModifier:try_get("triggerBefore")
                                        local triggerToken = g_token

                                        --we commit to it if we use the trigger so we disappear the trigger.
                                        dismiss = true
                                        waitingOnTriggerBefore = true

                                        triggerBefore:Trigger(trigger.powerRollModifier.powerRollModifier, g_token.properties, trigger.powerRollModifier.powerRollModifier:AppendSymbols{}, nil, { mod = trigger.powerRollModifier }, {
                                            complete = function()
                                                --set when resolution continues in the retarget picker,
                                                --which then owns clearing the resolving flag.
                                                local handedOffToRetarget = false
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
                                                            handedOffToRetarget = true
                                                            RunTriggerRetargetChoice(parentElement, triggerToken, freshTrigger)
                                                        end
                                                    end
                                                end

                                                --The caster's roll dialog holds its roll while the record's
                                                --resolving flag is set, so the trigger-before action (e.g.
                                                --Parry's shift) lands before damage and forced movement.
                                                --Clear it now that the action has fully resolved -- even if
                                                --the panel has since closed. When resolution was handed off
                                                --to the retarget picker, that flow clears it instead.
                                                if (not handedOffToRetarget) and triggerToken.valid then
                                                    local live = triggerToken.properties:GetAvailableTriggers() or {}
                                                    local liveTrigger = live[key]
                                                    if liveTrigger ~= nil and liveTrigger.resolving then
                                                        triggerToken:ModifyProperties{
                                                            undoable = false,
                                                            description = "Trigger",
                                                            execute = function()
                                                                liveTrigger.resolving = false
                                                                triggerToken.properties:DispatchAvailableTrigger(liveTrigger)
                                                            end,
                                                        }
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

                                            --the trigger-before action (e.g. Parry's shift) is still
                                            --running: mark the record so the caster's roll dialog holds
                                            --the roll until the complete callback clears this.
                                            if waitingOnTriggerBefore then
                                                trigger.resolving = true
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
                                            RuleUtils.RemoveRetargetStrikeTargets(targets, trigger, trigger.targets[1])
                                            local allowOriginal = RuleUtils.RetargetAllowsOriginal(trigger)

                                            local sourceToken = g_token
                                            local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
                                            local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                            if rangeType == "ability" then
                                                sourceToken = dmhub.GetTokenById(trigger.casterid)
                                                range = trigger.originalAbilityRange
                                            elseif rangeType == "distance" then
                                                range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                            end
                                            --the new target must be one the striking creature could actually
                                            --hit: inside the strike's distance and in its line of effect.
                                            if rangeType == "ability" then
                                                RuleUtils.AddRetargetRangeReasons(targets, retargetReasons, sourceToken, range)
                                            end

                                            element:Get("abilityController"):FireEventTree("chooseTarget", {
                                                sourceToken = sourceToken,
                                                radius = range,
                                                targets = targets,
                                                reasons = retargetReasons,
                                                prompt = RuleUtils.RetargetPromptText(sourceToken, range, rangeType, allowOriginal),
                                                autoPickSole = true,
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
                                                            --choosing the new target commits the trigger, so the card leaves the drawer.
                                                            trigger.dismissed = true

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
									element:SetClass("collapsed", trigger ~= nil and (trigger.triggered ~= false or not trigger:CanDismiss()))
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

                            --Whichever card the mouse is over owns the target highlighting the mode
                            --cards share with the main one. Entering fires before leaving, so a bare
                            --flag could not tell an arriving card from the departing one.
                            local pseudoHoverOwner = nil

                            --Drops the line-of-sight rays a card drew. Separate from the dehover event
                            --so hover can always clear before redrawing, even while a mode card owns the
                            --highlighting and dehover itself has to leave the rays alone.
                            local function ClearTriggerRays(panel)
                                for _,ray in ipairs(panel.data.rays) do
                                    ray:Destroy()
                                end
                                panel.data.rays = {}
                            end

                            local triggerPanel
							triggerPanel = gui.Panel{
                                data = {
                                    ord = trigger.timestamp,
                                    rays = {},
                                },
								classes = {"triggerPanel"},
                                blurBackground = true,

                                --targetids narrows the rays to one mode's subjects: a mode card fires
                                --this event itself, since it shares the main card's highlighting.
                                hover = function(element, targetids)
                                    ClearTriggerRays(element)

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

                                    for _,targetid in ipairs(targetids or trigger.targets or {}) do
                                        local target = dmhub.GetTokenById(targetid)
                                        if target ~= nil then
                                            local ray = dmhub.MarkLineOfSight(g_token, target, g_token.properties:GetPierceWalls())
                                            element.data.rays[#element.data.rays+1] = ray
                                        end
                                    end
                                end,

                                dehover = function(element)
                                    --a mode card has taken the highlighting over, so its rays are the
                                    --live ones now; only its own dehover may clear them.
                                    if pseudoHoverOwner ~= nil then
                                        return
                                    end

                                    ClearTriggerRays(element)

                                    local menu = element:FindParentWithClass("customActionBar")
                                    if menu ~= nil and not element:HasClass("pseudohover") then
                                        menu:FireEventTree("hideability", trigger)
                                    end
                                end,

                                --chosenTargetId is only passed when ChooseTriggerTarget re-runs
                                --this press with the target picked on the map.
                                press = function(element, chosenTargetId)
                                    if chosenTargetId == nil and (not trigger.triggered) then
                                        local live = availableTriggers ~= nil and availableTriggers[key] or trigger
                                        if live:NeedsTargetChoice() then
                                            ChooseTriggerTarget(element, g_token, live)
                                            return
                                        end
                                    end
                                    local targetId = chosenTargetId or trigger:GetTargetId()

                                    print("TRIGGER:: PRESS")

                                    audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                    if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") and not trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
                                        --this changes the target of the trigger.
								        local targetToken = dmhub.GetTokenById(targetId)
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
                                        RuleUtils.RemoveRetargetStrikeTargets(targets, trigger, targetId)
                                        local allowOriginal = RuleUtils.RetargetAllowsOriginal(trigger)

                                        local sourceToken = g_token
                                        local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
                                        local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                        if rangeType == "ability" then
                                            sourceToken = dmhub.GetTokenById(trigger.casterid)
                                            range = trigger.originalAbilityRange
                                        elseif rangeType == "distance" then
                                            range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                        end
                                        --the new target must be one the striking creature could actually
                                        --hit: inside the strike's distance and in its line of effect.
                                        if rangeType == "ability" then
                                            RuleUtils.AddRetargetRangeReasons(targets, retargetReasons, sourceToken, range)
                                        end

                                        element:Get("abilityController"):FireEventTree("chooseTarget", {
                                            sourceToken = sourceToken,
                                            radius = range,
                                            targets = targets,
                                            reasons = retargetReasons,
                                            prompt = RuleUtils.RetargetPromptText(sourceToken, range, rangeType, allowOriginal),
                                            autoPickSole = true,
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
                                                        if chosenTargetId ~= nil then
                                                            trigger.chosenTargetId = chosenTargetId
                                                        end
                                                        --choosing the new target commits the trigger, so the card leaves the drawer.
                                                        trigger.dismissed = true

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

                                    --set when we start a trigger-before action below: the accept then
                                    --flags the record as resolving, holding the caster's roll until
                                    --the complete callback clears it.
                                    local waitingOnTriggerBefore = false

                                    if (not trigger.triggered) and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
                                        --if we trigger some action before the trigger.
                                        local triggerBefore = trigger.powerRollModifier.powerRollModifier:try_get("triggerBefore")
                                        local triggerToken = g_token

                                        --we commit to it if we use the trigger so we disappear the trigger.
                                        dismiss = true
                                        waitingOnTriggerBefore = true

                                        triggerBefore:Trigger(trigger.powerRollModifier.powerRollModifier, g_token.properties, trigger.powerRollModifier.powerRollModifier:AppendSymbols{}, nil, { mod = trigger.powerRollModifier }, {
                                            complete = function()
                                                --set when resolution continues in the retarget picker,
                                                --which then owns clearing the resolving flag.
                                                local handedOffToRetarget = false
                                                if parentElement ~= nil and parentElement.valid then
                                                    if availableTriggers == nil then
                                                        return
                                                    end
                                                    local trigger = availableTriggers[key]
                                                    if trigger == nil then
                                                        return
                                                    end

                                                    --e.g. Parry: did the shift end adjacent to the target it was used for?
                                                    local condition = trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("triggerBeforeCondition", "")
                                                    if trim(condition) ~= "" and triggerToken.valid then
                                                        local target = nil
                                                        if targetId ~= nil then
                                                            target = dmhub.GetTokenById(targetId)
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
                                                            handedOffToRetarget = true
                                                            RunTriggerRetargetChoice(parentElement, triggerToken, freshTrigger, targetId)
                                                        end
                                                    end
                                                end

                                                --The caster's roll dialog holds its roll while the record's
                                                --resolving flag is set, so the trigger-before action (e.g.
                                                --Parry's shift) lands before damage and forced movement.
                                                --Clear it now that the action has fully resolved -- even if
                                                --the panel has since closed. When resolution was handed off
                                                --to the retarget picker, that flow clears it instead.
                                                if (not handedOffToRetarget) and triggerToken.valid then
                                                    local live = triggerToken.properties:GetAvailableTriggers() or {}
                                                    local liveTrigger = live[key]
                                                    if liveTrigger ~= nil and liveTrigger.resolving then
                                                        triggerToken:ModifyProperties{
                                                            undoable = false,
                                                            description = "Trigger",
                                                            execute = function()
                                                                liveTrigger.resolving = false
                                                                triggerToken.properties:DispatchAvailableTrigger(liveTrigger)
                                                            end,
                                                        }
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
                                                trigger.chosenTargetId = false
                                            else
                                                trigger.triggered = true
                                                --the pick tells the roll dialog which target's roll this changes.
                                                if chosenTargetId ~= nil then
                                                    trigger.chosenTargetId = chosenTargetId
                                                end
                                            end

                                            --the trigger-before action (e.g. Parry's shift) is still
                                            --running: mark the record so the caster's roll dialog holds
                                            --the roll until the complete callback clears this.
                                            if waitingOnTriggerBefore then
                                                trigger.resolving = true
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
                                    --a hostile prompt under strict action economy must be accepted:
                                    --the close button is withdrawn (re-evaluated each refresh so a
                                    --setting change takes effect on the live card).
                                    refresh = function(element)
                                        element:SetClass("collapsed", not trigger:CanDismiss())
                                    end,
                                    press = function(element)
                                        if not trigger:CanDismiss() then
                                            return
                                        end
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

								--On a merged card each mode carries the subjects whose own
								--prompt offers it, since a mode's condition is tested against
								--each subject. Unmerged prompts have none and show no row.
								local modeTargets = option.targets
								local modeTargetPanels = {}
								for _,targetid in ipairs(modeTargets or {}) do
									local modeToken = dmhub.GetTokenById(targetid)
									if modeToken ~= nil then
										modeTargetPanels[#modeTargetPanels+1] = gui.Panel{
											width = g_triggerPortraitSize,
											height = g_triggerPortraitSize,
											hmargin = g_triggerPortraitMargin,
											gui.CreateTokenImage(modeToken, {
												width = g_triggerPortraitImageSize,
												height = g_triggerPortraitImageSize,
												halign = "center",
												valign = "center",
											}),
										}
									end
								end

								children[#children+1] = gui.Panel{
									classes = {"triggerPanel", cond(unavailable, "unavailableMode")},

                                    hover = function(element)
                                        pseudoHoverOwner = element
                                        triggerPanel:SetClass("pseudohover", true)
                                        triggerPanel:FireEvent("hover", modeTargets)
                                    end,
                                    dehover = function(element)
                                        --another mode card already owns the highlighting, so this is just the
                                        --tail of moving onto it: leave its rays up.
                                        if pseudoHoverOwner ~= element then
                                            return
                                        end

                                        pseudoHoverOwner = nil
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
                                        gui.Panel{
                                            classes = {cond(#modeTargetPanels == 0, "collapsed")},
                                            width = "100%",
                                            height = "auto",
                                            flow = "horizontal",
                                            wrap = true,
                                            vmargin = 2,
                                            children = modeTargetPanels,
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



									--chosenTargetId is only passed when ChooseTriggerTarget re-runs
									--this press with the target picked on the map.
									press = function(element, chosenTargetId)

                                        --Strict action economy makes an unavailable mode truly
                                        --unavailable: players cannot press it to override.
                                        --Directors bypass this so they can still allow it,
                                        --matching the action bar's strict:resources handling.
                                        if unavailable and (not dmhub.isDM) and dmhub.GetSettingValue("strict:resources") then
                                            return
                                        end

                                        if chosenTargetId == nil and (not trigger.triggered) then
                                            local live = availableTriggers ~= nil and availableTriggers[key] or trigger
                                            if live:NeedsTargetChoice() then
                                                --a mode only one subject qualifies for needs no picker.
                                                if modeTargets ~= nil and #modeTargets == 1 then
                                                    chosenTargetId = modeTargets[1]
                                                else
                                                    ChooseTriggerTarget(element, g_token, live, modeTargets)
                                                    return
                                                end
                                            end
                                        end
                                        local targetId = chosenTargetId or trigger:GetTargetId()

                                        audio.DispatchSoundEvent("Notify.TriggerUse", {})

                                        if (not trigger.triggered) and #trigger.targets > 0 and trigger.powerRollModifier and trigger.powerRollModifier.powerRollModifier:try_get("changeTarget") and not trigger.powerRollModifier.powerRollModifier:try_get("hasTriggerBefore") then
                                            --this changes the target of the trigger.
                                            local targetToken = dmhub.GetTokenById(targetId)
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
                                            RuleUtils.RemoveRetargetStrikeTargets(targets, trigger, targetId)
                                            local allowOriginal = RuleUtils.RetargetAllowsOriginal(trigger)

                                            local sourceToken = g_token
                                            local range = tonumber(ExecuteGoblinScript(trigger.powerRollModifier.range, g_token.properties:LookupSymbol(symbols), 10))
                                            local rangeType = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetRange", "none")
                                            if rangeType == "ability" then
                                                sourceToken = dmhub.GetTokenById(trigger.casterid)
                                                range = trigger.originalAbilityRange
                                            elseif rangeType == "distance" then
                                                range = trigger.powerRollModifier.powerRollModifier:try_get("changeTargetDistance", 10)
                                            end
                                            --the new target must be one the striking creature could actually
                                            --hit: inside the strike's distance and in its line of effect.
                                            if rangeType == "ability" then
                                                RuleUtils.AddRetargetRangeReasons(targets, retargetReasons, sourceToken, range)
                                            end

                                            element:Get("abilityController"):FireEventTree("chooseTarget", {
                                                sourceToken = sourceToken,
                                                radius = range,
                                                targets = targets,
                                                reasons = retargetReasons,
                                                prompt = RuleUtils.RetargetPromptText(sourceToken, range, rangeType, allowOriginal),
                                                autoPickSole = true,
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
                                                            if chosenTargetId ~= nil then
                                                                trigger.chosenTargetId = chosenTargetId
                                                            end
                                                            --choosing the new target commits the trigger, so the card leaves the drawer.
                                                            trigger.dismissed = true

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

                                                --the pick tells the roll dialog which target's roll this changes.
                                                if chosenTargetId ~= nil then
                                                    trigger.chosenTargetId = chosenTargetId
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
                                data = {
                                    targetsKey = targetsKey,
                                },
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
                dismissAllPanel:SetClass("collapsed", not anyDismissable)
				element.children = {triggerListPanel, dismissAllPanel}
				m_activeTriggerPanels = newTriggerPanels
			end,
		}
	}

    return activeTriggersPanel
end