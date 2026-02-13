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

    local resultPanel = nil
    local finished = false
    local canceled = false

    local effectTargets = {}
    local recoveryTargets = {}

    for _, tok in pairs(targetTokenids) do
        local token = dmhub.GetTokenById(tok)
        if token.valid then
            effectTargets[token.id] = {}
            recoveryTargets[token.id] = 1
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
        
        return numEffects + numRecovery - 1
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

    --- @param token CharacterToken
	local CreateTokenPanel = function(token)

        local effectsPanel = nil
        local targetCurrentEffects = token.properties:ActiveOngoingEffects()
        local targetCurrentConditions = token.properties:try_get("inflictedConditions", {})
        
        effectsPanel = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            flow = "horizontal",

            create = function(element)
                local children = {}
                for _, effect in ipairs(targetCurrentEffects) do
                    if effect.removeAtNextTurnEnd or effect.removeOnSave then
                        children[#children + 1] = gui.Button{
                            classes = "effect-button",
                            text = string.format("End: %s", ongoingEffectsTable[effect.ongoingEffectid].name),
                            
                            click = function(element)
                                element:SetClass('selected', not element:HasClass('selected'))

                                if element:HasClass('selected') then
                                    effectTargets[token.id][effect.ongoingEffectid] = true
                                else
                                    effectTargets[token.id][effect.ongoingEffectid] = nil
                                end
                                element:Get("recoveryCost"):FireEvent("refreshCost")
                            end,
                        }
                    end
                end

                for id, details in pairs(targetCurrentConditions) do
                    if details.duration == "save" or details.duration == "eot" or conditionsTable[id].indefiniteDuration then
                        children[#children + 1] = gui.Button{
                            classes = "effect-button",
                            text = string.format("End: %s", conditionsTable[id].name),

                            click = function(element)
                                element:SetClass('selected', not element:HasClass('selected'))

                                if element:HasClass('selected') then
                                    effectTargets[token.id][id] = true
                                else
                                    effectTargets[token.id][id] = nil
                                end
                                element:Get("recoveryCost"):FireEvent("refreshCost")
                            end,
                        }
                    end
                end

                element.children = children
            end,
        }
       
        local tokenPanel = nil

        tokenPanel = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            flow = "horizontal",
                gui.Panel{
                bgimage = 'panels/square.png',
                classes = 'token-panel',
                data = {
                    token = token,
                },

                gui.CreateTokenImage(token),

                hover = function(element)
                    local staminaString = string.format("Current Stamina: %d / %d", math.tointeger(token.properties:CurrentHitpoints()), math.tointeger(token.properties:MaxHitpoints()))
                    local availableRecoveries = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                    local recoveryString = string.format("Recoveries Available: %d", math.tointeger(availableRecoveries))
                    local tooltip = string.format("%s\n%s\n%s", token.name, staminaString, recoveryString)

                    gui.Tooltip(tooltip)(element)
                end,
            },
            
            
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "left",
                flow = "horizontal",

                gui.Label{
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    fontSize = 16,
                    margin = 5,

                    refreshRecoveries = function(element)
                        local recoveries = recoveryTargets[token.id] or 1
                        element.text = tostring(recoveries)
                    end,

                    create = function(element)
                        element:FireEvent("refreshRecoveries")
                    end,
                },
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    flow = "vertical",

                    gui.Panel{
                        classes = "clickableIcon",
                        lmargin = 10,
                        bgimage = "panels/hud/down-arrow.png",
                        bgcolor = "white",
                        height = "75% width",
                        scale = {x = 1, y = -1},
                        valign = "center",
                        click = function(element)
                            local recoveries = recoveryTargets[token.id] or 1
                            local availableRecoveries = max(0, (token.properties:GetResources()[recoveryid] or 0) - (token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                            recoveries = math.min(recoveries + 1, math.tointeger(availableRecoveries))
                            recoveryTargets[token.id] = recoveries
                            element.parent.parent.children[1]:FireEvent("refreshRecoveries")
                            element:Get("recoveryCost"):FireEvent("refreshCost")
                        end,

                    },
                    gui.Panel{
                        classes = "clickableIcon",
                        bgimage = "panels/hud/down-arrow.png",
                        bgcolor = "white",
                        height = "75% width",
                        valign = "center",

                        click = function(element)
                            local recoveries = recoveryTargets[token.id] or 1
                            recoveries = math.max(1, recoveries - 1)
                            recoveryTargets[token.id] = recoveries
                            element.parent.parent.children[1]:FireEvent("refreshRecoveries")
                            element:Get("recoveryCost"):FireEvent("refreshCost")
                        end,
                    },
                },
            },
            
            effectsPanel,
        }

		return tokenPanel

	end

    local mainTargetsPanel = nil
    mainTargetsPanel = gui.Panel{
        id = "recoveryTargets",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",

        create = function(element)
            local children = {}
            for _, tok in pairs(targetTokenids) do
                local token = dmhub.GetTokenById(tok)
                if token.valid then
                    children[#children + 1] = CreateTokenPanel(token)
                end
            end
            element.children = children
        end,
    }

    resultPanel = gui.Panel{
        classes = {"formPanel"},
        bgimage = 'panels/square.png',
        bgcolor = 'black',
        borderColor = "white",
        borderWidth = 2,
        width = 550,
        height = 550,

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
                classes = {'effect-button'},
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 14,
                margin = 4,
                pad = 2,
            },
            {
                classes = {'effect-button' , 'selected'},
                borderColor = 'white',
				borderWidth = 2,
				bgcolor = '#882222',
            },
            {
                classes = {"recovery-label"},
                valign = "top",
                width = "auto",
                fontSize = 20,
                bold = true,
            },
            {
                classes = {"recovery-label",  "cannot-afford"},
                color = "red",
            },
		},

        gui.Panel{
            flow = "vertical",
            width = "90%",
            height = "90%",
            valign = "top",
            halign = "center",
            gui.Label{
                text = ability.name or "Select Recovery Options",
                bold = true,
                width = "auto",
                valign = "top",
                fontSize = 20,
            },
            gui.Label{
                id = "recoveryCost",
                classes = "recovery-label",
                refreshCost = function(element)
                    element.text = string.format("%s Cost: %s", casterToken.properties:GetHeroicResourceName(), calcCost())
                    element:SetClass('cannot-afford', calcCost() > casterToken.properties:GetHeroicOrMaliceResourcesAvailableToSpend())
                end,

                create = function(element)
                    element:FireEvent("refreshCost")
                end,
            },
            mainTargetsPanel,
            gui.Button{
                halign = 'right',
                valign = 'bottom',
                text = 'Submit',
                height = 30,
                width = 160,
                click = function(element)
                    finished = true
                    gui.CloseModal()
                end,
            },
            gui.Button{
                halign = 'right',
                valign = 'bottom',
                text = 'Cancel',
                width = 160,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function(element)
                    finished = true
                    canceled = true
                    gui.CloseModal()
                end,
            },

        }
    }

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    --Canceling stops the ability from executing
    if canceled then
        return
    end

    for _, tok in pairs(targetTokenids) do
        local token = dmhub.GetTokenById(tok)
        local targetCreature = token:GetCreature()
        if token.valid then
            local maySpendRecovery = DeepCopy(MCDMUtils.GetStandardAbility("May Spend Recovery"))
            AbilityUtils.DeepReplaceAbility(maySpendRecovery, "<<numrecoveries>>", string.format("%d", recoveryTargets[token.id] or 1))
            ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(token, maySpendRecovery, token, "self", options.symbols, options)

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