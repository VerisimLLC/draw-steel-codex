local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRecoverySelectionBehavior:ActivatedAbilityBehavior
ActivatedAbilityRecoverySelectionBehavior = RegisterGameType("ActivatedAbilityRecoverySelectionBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityRecoverySelectionBehavior.summary = "Recovery Selection"

ActivatedAbility.RegisterType
{
	id = 'recoverySelection',
	text = 'Recovery Selection',
	createBehavior = function()
		return ActivatedAbilityRecoverySelectionBehavior.new{
		}
	end
}

function ActivatedAbilityRecoverySelectionBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	return result
end

function ActivatedAbilityRecoverySelectionBehavior:Cast(ability, casterToken, targets, options)

    ability:CommitToPaying(casterToken, options)

    local targetTokenids = ActivatedAbility.GetTokenIds(targets) or {}

    local finished = false
    local canceled = false

    local effectTargets = {}
    local recoveryTargets = {}
    local firstTargetId = nil

    for _, tok in pairs(targetTokenids) do
        local token = dmhub.GetTokenById(tok)
        if token.valid then
            effectTargets[token.id] = {}
            if firstTargetId == nil then
                firstTargetId = token.id
                recoveryTargets[token.id] = 1
            else
                recoveryTargets[token.id] = 0
            end
        end
    end

    local calcCost = function()
        local numEffects = 0
        local numRecovery = 0
        for token, recoveries in pairs(recoveryTargets) do
            numRecovery = numRecovery + recoveries
        end

        for _, effects in pairs(effectTargets) do
            for _, value in pairs(effects) do
                if value then
                    numEffects = numEffects + 1
                end
            end
        end

        return max(0, numEffects + numRecovery - 1)
    end

    local recoveryid = nil
    local recoveryInfo = nil
    local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
    for k,v in unhidden_pairs(resourcesTable) do
        if v.name == "Recovery" then
            recoveryid = k
            recoveryInfo = v
        end
    end

    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
    local ongoingEffectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName)

    -- Reference to the cost label element for refreshing.
    local costLabelElement = nil

    local function refreshCostLabel()
        if costLabelElement == nil then
            return
        end
        local cost = calcCost()
        costLabelElement.text = string.format("%s Cost: %s", casterToken.properties:GetHeroicResourceName(), cost)
        costLabelElement:SetClass("recovery-cannot-afford", cost > casterToken.properties:GetHeroicOrMaliceResourcesAvailableToSpend())
    end

    --- @param token CharacterToken
    local CreateTokenPanel = function(token)

        local targetCurrentEffects = token.properties:ActiveOngoingEffects()
        local targetCurrentConditions = token.properties:try_get("inflictedConditions", {})

        -- Build effect/condition chips for this token.
        local effectChips = {}

        for _, effect in ipairs(targetCurrentEffects) do
            if effect.removeAtNextTurnEnd or effect.removeOnSave then
                local capturedEffect = effect
                local effectName = ongoingEffectsTable[effect.ongoingEffectid].name

                local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                local effectDesc = ""
                if effectInfo.condition ~= nil and effectInfo.condition ~= "none" and conditionsTable[effectInfo.condition] ~= nil then
                    effectDesc = conditionsTable[effectInfo.condition].description or ""
                end

                effectChips[#effectChips+1] = gui.Panel{
                    classes = {"recovery-chip"},
                    flow = "horizontal",

                    press = function(element)
                        if effectTargets[token.id][capturedEffect.ongoingEffectid] then
                            effectTargets[token.id][capturedEffect.ongoingEffectid] = nil
                            element:SetClass("recovery-chip-selected", false)
                        else
                            effectTargets[token.id][capturedEffect.ongoingEffectid] = true
                            element:SetClass("recovery-chip-selected", true)
                        end
                        refreshCostLabel()
                    end,

                    hover = function(element)
                        if effectDesc ~= "" then
                            gui.Tooltip(effectDesc)(element)
                        end
                    end,

                    gui.Label{
                        classes = {"recovery-chip-label"},
                        text = string.format("End: %s", effectName),
                    },
                }
            end
        end

        for id, details in pairs(targetCurrentConditions) do
            if details.duration == "save" or details.duration == "eot" or conditionsTable[id].indefiniteDuration then
                local capturedId = id
                local condName = conditionsTable[id].name

                local condDesc = conditionsTable[id].description or ""

                effectChips[#effectChips+1] = gui.Panel{
                    classes = {"recovery-chip"},
                    flow = "horizontal",

                    press = function(element)
                        if effectTargets[token.id][capturedId] then
                            effectTargets[token.id][capturedId] = nil
                            element:SetClass("recovery-chip-selected", false)
                        else
                            effectTargets[token.id][capturedId] = true
                            element:SetClass("recovery-chip-selected", true)
                        end
                        refreshCostLabel()
                    end,

                    hover = function(element)
                        if condDesc ~= "" then
                            gui.Tooltip(condDesc)(element)
                        end
                    end,

                    gui.Label{
                        classes = {"recovery-chip-label"},
                        text = string.format("End: %s", condName),
                    },
                }
            end
        end

        -- Build numbered recovery chips (1 through available recoveries).
        local availableRecoveries = math.tointeger(max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0)))
        local recoveryNumChips = {}
        local recoveryChipElements = {}

        for i = 1, availableRecoveries do
            local num = i
            recoveryNumChips[#recoveryNumChips+1] = gui.Panel{
                classes = {"recovery-num-chip"},
                flow = "horizontal",

                press = function(element)
                    local minRecoveries = cond(token.id == firstTargetId, 1, 0)
                    -- Clicking the currently highest selected chip deselects to minimum.
                    if recoveryTargets[token.id] == num then
                        recoveryTargets[token.id] = minRecoveries
                    else
                        recoveryTargets[token.id] = num
                    end
                    local selected = recoveryTargets[token.id]
                    for j, el in ipairs(recoveryChipElements) do
                        el:SetClass("recovery-num-chip-selected", j <= selected)
                    end
                    refreshCostLabel()
                end,

                create = function(element)
                    recoveryChipElements[#recoveryChipElements+1] = element
                    if num <= (recoveryTargets[token.id] or 0) then
                        element:SetClass("recovery-num-chip-selected", true)
                    end
                end,

                gui.Label{
                    classes = {"recovery-num-chip-label"},
                    text = tostring(num),
                },
            }
        end

        local tokenPanel = gui.Panel{
            classes = {"recovery-token-row"},

            -- Token portrait with hover tooltip.
            gui.Panel{
                classes = {"recovery-token-portrait"},
                bgimage = "panels/square.png",

                gui.CreateTokenImage(token),

                hover = function(element)
                    local staminaString = string.format("Current Stamina: %d / %d", math.tointeger(token.properties:CurrentHitpoints()), math.tointeger(token.properties:MaxHitpoints()))
                    local recoveryString = string.format("Recoveries Available: %d", math.tointeger(availableRecoveries))
                    local tooltip = string.format("%s\n%s\n%s", token.name, staminaString, recoveryString)
                    gui.Tooltip(tooltip)(element)
                end,
            },

            -- Token name, recovery chips, and effect chips.
            gui.Panel{
                classes = {"recovery-token-info"},

                gui.Label{
                    classes = {"recovery-token-name"},
                    text = token.name,
                },

                gui.Panel{
                    classes = {"recovery-count-row"},

                    gui.Label{
                        classes = {"recovery-count-label-text"},
                        text = "Recoveries:",
                    },

                    gui.Panel{
                        classes = {"recovery-num-chips-wrap"},
                        children = recoveryNumChips,
                    },
                },

                -- Condition/effect chips.
                gui.Panel{
                    classes = {"recovery-chips-wrap"},
                    children = effectChips,
                },
            },
        }

        return tokenPanel
    end

    -- Build the list of token panels.
    local tokenPanels = {}
    for _, tok in pairs(targetTokenids) do
        local token = dmhub.GetTokenById(tok)
        if token.valid then
            tokenPanels[#tokenPanels+1] = CreateTokenPanel(token)
        end
    end

    -- Assemble main content.
    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"recovery-title"},
        text = ability.name or "Select Recovery Options",
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"recovery-cost-label"},

        create = function(element)
            costLabelElement = element
            refreshCostLabel()
        end,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"recovery-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"recovery-tokens-list"},
        children = tokenPanels,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"recovery-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"recovery-button-row"},
        gui.Panel{
            classes = {"recovery-submit"},
            press = function(element)
                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"recovery-button-label"},
                text = "Submit",
            },
        },
        gui.Panel{
            classes = {"recovery-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"recovery-button-label"},
                text = "Cancel",
            },
        },
    }

    local resultPanel = gui.Panel{
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#040807",
        border = 1,
        borderColor = "#5C3D10",
        cornerRadius = 6,
        width = 520,
        height = "auto",
        pad = 12,

        styles = {
            {
                selectors = {"label", "recovery-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "recovery-cost-label"},
                fontFace = "Berling",
                fontSize = 14,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
                bold = true,
            },
            {
                selectors = {"label", "recovery-cost-label", "recovery-cannot-afford"},
                color = "#D53031",
            },
            {
                selectors = {"panel", "recovery-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "recovery-tokens-list"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                bmargin = 2,
            },
            {
                selectors = {"panel", "recovery-token-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vmargin = 6,
            },
            {
                selectors = {"panel", "recovery-token-portrait"},
                width = 56,
                height = 56,
                bgcolor = "black",
                cornerRadius = 6,
                halign = "left",
                valign = "top",
                rmargin = 10,
            },
            {
                selectors = {"panel", "recovery-token-info"},
                width = "100% -70",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
            },
            {
                selectors = {"label", "recovery-token-name"},
                fontFace = "Berling",
                fontSize = 15,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "left",
                bold = true,
                bmargin = 2,
            },
            {
                selectors = {"panel", "recovery-count-row"},
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                bmargin = 4,
            },
            {
                selectors = {"label", "recovery-count-label-text"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#C49A5A",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 6,
            },
            {
                selectors = {"panel", "recovery-num-chips-wrap"},
                width = "auto",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                valign = "center",
            },
            {
                selectors = {"panel", "recovery-num-chip"},
                width = 26,
                height = 22,
                halign = "left",
                valign = "center",
                hmargin = 2,
                flow = "horizontal",
                bgimage = "panels/square.png",
                border = 1,
                borderColor = "#5C6860",
                bgcolor = "clear",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "recovery-num-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "recovery-num-chip", "recovery-num-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"label", "recovery-num-chip-label"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
            {
                selectors = {"panel", "recovery-chips-wrap"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
            },
            {
                selectors = {"panel", "recovery-chip"},
                height = "auto",
                minHeight = 22,
                width = "auto",
                halign = "left",
                valign = "top",
                hpad = 8,
                vpad = 4,
                margin = 3,
                flow = "horizontal",
                bgimage = "panels/square.png",
                border = 1,
                borderColor = "#5C6860",
                bgcolor = "clear",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "recovery-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "recovery-chip", "recovery-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"label", "recovery-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "recovery-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "recovery-submit"},
                width = 130,
                height = 30,
                halign = "right",
                rmargin = 8,
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#966D4B",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "recovery-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "recovery-cancel"},
                width = 130,
                height = 30,
                halign = "right",
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#5C6860",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "recovery-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "recovery-button-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        },

        children = mainChildren,
    }

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    -- Canceling stops the ability from executing
    if canceled then
        return
    end

    for _, tok in pairs(targetTokenids) do
        local token = dmhub.GetTokenById(tok)
        local targetCreature = token:GetCreature()
        if token.valid then
            local numRecoveries = recoveryTargets[token.id] or 0
            if numRecoveries > 0 then
                local maySpendRecovery = DeepCopy(MCDMUtils.GetStandardAbility("May Spend Recovery"))
                AbilityUtils.DeepReplaceAbility(maySpendRecovery, "<<numrecoveries>>", string.format("%d", numRecoveries))
                ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(token, maySpendRecovery, token, "self", options.symbols, options)
            end

            for effectId, value in pairs(effectTargets[token.id] or {}) do
                if value then
                    if conditionsTable[effectId] then
                        token:ModifyProperties{
                            description = "Remove Condition",
                            execute = function()
                                targetCreature:InflictCondition(effectId, {purge = true})
                            end,
                        }
                    elseif ongoingEffectsTable[effectId] then
                        token:ModifyProperties{
                            description = "Purge Effects",
                            execute = function()
                                targetCreature:RemoveOngoingEffect(effectId)
                            end,
                        }
                    end
                end
            end
        end
    end

    casterToken:ModifyProperties{
        description = "Change Heroic Resource",
        execute = function()
            local cost = calcCost()
            casterToken.properties:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", cost)
        end,
    }

end
