local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityPurgeEffectsBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'purge_effects',
	text = 'Purge Ongoing Effects',
	createBehavior = function()
		return ActivatedAbilityPurgeEffectsBehavior.new{
            conditions = {},
		}
	end
}


--- @class ActivatedAbilityPurgeEffectsChatMessage
--- @field ability ActivatedAbility
ActivatedAbilityPurgeEffectsChatMessage = RegisterGameType("ActivatedAbilityPurgeEffectsChatMessage")
ActivatedAbilityPurgeEffectsChatMessage.conditions = {}
ActivatedAbilityPurgeEffectsChatMessage.casterid = ""
ActivatedAbilityPurgeEffectsChatMessage.chatMessage = ""
ActivatedAbilityPurgeEffectsChatMessage.targetids = {}

function ActivatedAbilityPurgeEffectsChatMessage:Render(message)
    local resultPanel

    local token = self:GetCasterToken()
    local targets = self:GetTargetTokens()


    if token == nil or (not token.valid) then
        return gui.Panel{
            width = 0, height = 0,
        }
    end

    local resultPanel

    local tokenPanel = gui.CreateTokenImage(token,{
        scale = 0.9,
        valign = "center",
        halign = "left",

        interactable = true,
        hover = gui.Tooltip(token.name),
    })

    local targetTokenPanels = {}
    for _,tok in ipairs(self:GetTargetTokens()) do
        if tok.valid then
            targetTokenPanels[#targetTokenPanels+1] = gui.CreateTokenImage(tok, {
                width = 32,
                height = 32,
                valign = "center",
                halign = "left",

                interactable = true,
                hover = gui.Tooltip(tok.name),
            })
        end
    end

    local conditionTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

    local conditionNames = {}

    for _,conditionid in ipairs(self.conditions) do
        local conditionInfo = conditionTable[conditionid] or ongoingEffectsTable[conditionid]
        if conditionInfo ~= nil then
            conditionNames[#conditionNames+1] = conditionInfo.name
        else
            conditionNames[#conditionNames+1] = "Unknown Effect"
        end
    end

    local effectName = table.concat(conditionNames, ", ")

    local messageText = string.format("Removed %s", effectName)

    resultPanel = gui.Panel{
        classes = {"chat-message-panel"},

 
        flow = "vertical",
        width = "100%",
        height = "auto",

        refreshMessage = function(element, message)
        end,

        gui.Panel{
			classes = {'separator'},
		},

        gui.Panel{

            width = "100%",
            height = "auto",
            flow = "horizontal",

            tokenPanel,

            gui.Panel{
                flow = "vertical",
                width = "100%-80",
                height = "auto",
                halign = "right",
                valign = "top",

                gui.Label{
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                    maxWidth = 420,
                    halign = "left",
                    valign = "top",
                    text = string.format("<b>%s</b>\n%s", self.chatMessage, messageText),
                    hover = function(element)
                        local token = self:GetCasterToken()
                        if token == nil then
                            return
                        end
	                    local dock = element:FindParentWithClass("dock")
	                    element.tooltipParent = dock

                        --TODO: show a more detailed breakdown of damage messaging.
                    end,
                },

                gui.Panel{
                    width = "50%",
                    height = "auto",
                    halign = "left",
                    flow = "horizontal",
                    wrap = true,
                    children = targetTokenPanels,
                }
            },
        },
    }

    return resultPanel
end

function ActivatedAbilityPurgeEffectsChatMessage:GetCasterToken()
    return dmhub.GetCharacterById(self.casterid)
end

--- @return CharacterToken[]
function ActivatedAbilityPurgeEffectsChatMessage:GetTargetTokens()
    local result = {}
    for i,tokenid in ipairs(self.targetids) do
        result[#result+1] = dmhub.GetCharacterById(tokenid)
    end
    return result
end

ActivatedAbilityPurgeEffectsBehavior.summary = 'Purge Ongoing Effects'
ActivatedAbilityPurgeEffectsBehavior.mode = 'conditions'
ActivatedAbilityPurgeEffectsBehavior.ongoingEffect = 'none'
ActivatedAbilityPurgeEffectsBehavior.purgeType = 'all'
ActivatedAbilityPurgeEffectsBehavior.useStacks = false
ActivatedAbilityPurgeEffectsBehavior.stacksFormula = "1"
ActivatedAbilityPurgeEffectsBehavior.damageToSelf = ""
ActivatedAbilityPurgeEffectsBehavior.chatMessage = ""

ActivatedAbilityPurgeEffectsBehavior.modeOptions = {
    {
        id = "conditions",
        text = "Underlying Condition",
    },
    {
        id = "effect",
        text = "Specific Ongoing Effect",
    },
}


ActivatedAbilityPurgeEffectsBehavior.purgeTypeOptions = {
    {
        id = "all",
        text = "All Effects",
    },
    {
        id = "chosen",
        text = "Chosen Effects",
    },
    {
        id = "one",
        text = "One Chosen Effect",
    },
}



function ActivatedAbilityPurgeEffectsBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 then
        return
    end

    local messages = {}

    for _,target in ipairs(targets) do
        if target.token ~= nil then
            self:CastOnTarget(casterToken, target.token, ability, options)

            if self.chatMessage ~= "" then
                local existingMessage = messages[#messages]
                if existingMessage ~= nil and dmhub.DeepEqual(existingMessage.conditions, self.conditions) then
                    existingMessage.targetids[#existingMessage.targetids+1] = target.token.charid
                else
                    local msg = ActivatedAbilityPurgeEffectsChatMessage.new{
                        ability = ability,
                        casterid = casterToken.charid,
                        chatMessage = self.chatMessage,
                        conditions = self.conditions,
                        targetids = { target.token.charid },
                    }
                    messages[#messages+1] = msg
                end
            end
        end
    end

    for _,message in ipairs(messages) do
        chat.SendCustom(message)
    end

    ability:CommitToPaying(casterToken, options)
end

function ActivatedAbilityPurgeEffectsBehavior:CastOnTarget(casterToken, targetToken, ability, options)
    local targetCreature = targetToken.properties
    local effects = targetCreature:ActiveOngoingEffects()
    local filteredEffects = {}
    for _,effect in ipairs(effects) do
        if self:AppliesToEffect(effect) then
            filteredEffects[#filteredEffects+1] = effect
        end
    end

    local result = {}

    if self.mode == "conditions" and targetCreature:has_key("inflictedConditions") then
        local conditions = {}
        local targetDuration = self:try_get("targetDuration", "all")
        local durationTable = string.split(targetDuration, "|")
        for key,conditionInfo in pairs(targetCreature.inflictedConditions) do
            if #self.conditions == 0 or table.contains(self.conditions, key) then
                for _,durationEntry in ipairs(durationTable) do
                    if durationEntry == "all" or string.lower(durationEntry) == string.lower(conditionInfo.duration) then
                        conditions[#conditions+1] = key
                        break
                    end
                end
            end
        end

        if #conditions == 0 then
            return result
        end

        local conditionsToPurge = {}

        if self.purgeType == "all" then
            conditionsToPurge = conditions
        else
            table.insert(conditions, 1, "none")
            conditionsToPurge = self:ShowConditionsSelection(casterToken, targetToken, ability, conditions, options)
        end

        print("Purge:: Purging =", conditionsToPurge)

        if #conditionsToPurge > 0 then
            options.symbols.cast.purgedConditions = #conditionsToPurge

            targetToken:ModifyProperties{
                description = "Purge Conditions",
                execute = function()
                    for _,condid in ipairs(conditionsToPurge) do
                        targetCreature:InflictCondition(condid, {purge = true})
                        result[#result+1] = condid
                    end

                    local damage = tonumber(self.damageToSelf)
                    if damage ~= nil and damage > 0 then
                        targetCreature:TakeDamage(damage, "Purged condition")
                    end
                end,
            }
        end
    end

    if #filteredEffects == 0 then
        return result
    end

    local numStacks = nil
    if self.useStacks then
        numStacks = ExecuteGoblinScript(self.stacksFormula, GenerateSymbols(casterToken.properties), 0, "Number of stacks of effect to remove")
    end

    if self.purgeType == "all" then
        targetToken:ModifyProperties{
            description = "Purge Effects",
            execute = function()
                for _,effect in ipairs(filteredEffects) do
                    numStacks = targetCreature:RemoveOngoingEffect(effect.ongoingEffectid, numStacks)
                    result[#result+1] = effect.ongoingEffectid
                end
            end,
        }

        ability:CommitToPaying(casterToken, options)
    else
        self:ShowSelectionDialog(casterToken, targetToken, ability, filteredEffects, options, numStacks)
    end

    return result
end

function ActivatedAbilityPurgeEffectsBehavior:AppliesToEffect(effect)
	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    if self.mode == "conditions" then
        local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
        if effectInfo == nil or effectInfo.condition == "none" then
            return false
        end

        for _,condid in ipairs(self.conditions) do
            if condid == effectInfo.condition then
                return true
            end
        end

        return #self.conditions == 0
    else
        return effect.ongoingEffectid == self.ongoingEffect
    end
end

--options: {
--  title: string,
--  multiselect: boolean,
--  options: [{
--    id: (optional) string,
--    iconid: (optional) string,
--    text: (optional) string,
--    panels: (optional) [Panel],
--    selected: (in/out) boolean,
--}]
--}
function ActivatedAbilityBehavior:ShowOptionsDialog(options)
    local finished = false
    local canceled = false

    local optionPanels = {}

    for i,option in ipairs(options.options) do
        local panels = {}

        if option.iconid ~= nil then
            local display = option.display
            if display == nil then
                display = {
                    bgcolor = "white",
                }
            end

            panels[#panels+1] = gui.Panel{
                classes = {"optionIcon"},
                bgimage = option.iconid,
                selfStyle = display,
            }
        end

        if option.text ~= nil then
            panels[#panels+1] = gui.Label{
                classes = {"optionLabel"},
                text = option.text,
            }
        end

        if option.panels ~= nil then
            for _,p in ipairs(option.panels) do
                panels[#panels+1] = p
            end
        end

        optionPanels[#optionPanels+1] = gui.Panel{
            data = {
                option = option,
            },
            classes = {"option", cond(option.selected, "selected")},
            press = function(element)
                element:SetClass("selected", not element:HasClass("selected"))

                if not options.multiselect then
                    for _,el in ipairs(element.parent.children) do
                        if el ~= element then
                            el:SetClass("selected", false)
                        end
                    end
                end

                for i,panel in ipairs(optionPanels) do
                    if panel.valid and panel.data.option ~= nil then
                        panel.data.option.selected = panel:HasClass("selected")
                    end
                end
            end,

            children = panels,
        }

    end

    gamehud:ModalDialog{
        title = options.title,
        buttons = {
            {
                text = "Confirm",
                click = function()
                    finished = true
                end,
            },
            {
                text = "Cancel",
                escapeActivates = true,
                click = function()
                    finished = true
                    canceled = true
                end,
            }
        },

        styles = {
			{
				selectors = {"option"},
				height = 24,
				width = 500,
				halign = "center",
				valign = "top",
				hmargin = 20,
				vmargin = 0,
				vpad = 4,
				bgcolor = "#00000000",
                bgimage = "panels/square.png",
			},
			{
				selectors = {"option","hover"},
				bgcolor = "#ffff0088",
			},
			{
				selectors = {"option","selected"},
				bgcolor = "#ff000088",
			},
            {
                selectors = {"optionIcon"},
                width = 32,
                height = 32,
                halign = "left",
                valign = "center",
                hmargin = 16,
            },
            {
                selectors = {"optionLabel"},
                fontSize = 14,
                color = "white",
                width = 200,
                height = "auto",
                halign = "right",
                textAlignment = "left",
            },
        },

		width = 810,
		height = 768,

		flow = "vertical",

        gui.Panel{
            flow = "vertical",
            vscroll = true,
            width = 600,
            height = 500,
            halign = "center",
            valign = "center",
            children = optionPanels,
        }
    }

    while finished == false do
        coroutine.yield(0.1)
    end

    print("Purge:: Finishing canceled =", canceled, "/", #optionPanels)

    return not canceled
end

function ActivatedAbilityPurgeEffectsBehavior:ShowConditionsSelection(casterToken, targetToken, ability, conditionsList, options)

    local args = {
        title = "Purge Effects",
        multiselect = self.purgeType ~= "one",
        options = {},
    }

	local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}

    for i,condid in ipairs(conditionsList) do
        local conditionInfo = conditionsTable[condid]
        if conditionInfo ~= nil then
            local option = {
                id = condid,
                selected = self.purgeType ~= "one" or i == 1,
                iconid = conditionInfo.iconid,
                display = conditionInfo.display,
                text = conditionInfo.name,
            }

            if self.damageToSelf ~= "" then
                option.text = option.text .. " <color=#ff0000>(Receive " .. self.damageToSelf .. " damage)"
            end

            args.options[#args.options+1] = option
        else
            local option = {
                id = "none",
                selected = self.purgeType ~= "one" or i == 1,
                text = "Don't Remove",
            }

            args.options[#args.options+1] = option
        end
    end

    local complete = self:ShowOptionsDialog(args)
    print("Purge:: complete =", complete)
    if complete then
        ability:CommitToPaying(casterToken, options)
        local result = {}
        for i,option in ipairs(args.options) do
            print("Purge:: id =", option.id, "selected =", option.selected)
            if option.selected and option.id ~= "none" then
                result[#result+1] = option.id
            end
        end
    print("Purge:: result =", result)

        return result
    end

    return {}
end



function ActivatedAbilityPurgeEffectsBehavior:ShowSelectionDialog(casterToken, targetToken, ability, effectsList, options, numStacks)

    local args = {
        title = "Purge Effects",
        multiselect = self.purgeType ~= "one",
        options = {},
    }

	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

    for i,effect in ipairs(effectsList) do
        local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]

        local option = {
            id = effect.ongoingEffectid,
            selected = self.purgeType ~= "one" or i == 1,
            iconid = effectInfo.iconid,
            display = effectInfo.display,
            text = effectInfo.name,
        }

        args.options[#args.options+1] = option
    end

    local complete = self:ShowOptionsDialog(args)
    if complete then
        ability:CommitToPaying(casterToken, options)

        targetToken:ModifyProperties{
            description = "Purge Effects",
            execute = function()
                for i,option in ipairs(args.options) do
                    if option.selected then
                        numStacks = targetToken.properties:RemoveOngoingEffect(option.id, numStacks)
                    end
                end
            end,
        }

    end
end

function ActivatedAbilityPurgeEffectsBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Mode:",
        },

        gui.Dropdown{
            idChosen = self.mode,
            options = ActivatedAbilityPurgeEffectsBehavior.modeOptions,
            change = function(element)
                self.mode = element.idChosen
                parentPanel:FireEvent("refreshBehavior")
            end,

        },
    }

    if self.mode == "effect" then
        local effectOptions = {}
		local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
        for k,v in pairs(ongoingEffectsTable) do
            if not rawget(v, "hidden") then
                effectOptions[#effectOptions+1] = {
                    id = k,
                    text = v.name,
                }
            end
        end

        table.sort(effectOptions, function(a,b) return a.text < b.text end)

        if self.ongoingEffect == "none" then
            table.insert(effectOptions, 1, {
                id = "none",
                text = "Choose Ongoing Effect...",
            })
        end

        result[#result+1] = gui.Panel{
            classes = "formPanel",
            gui.Label{
                classes = "formLabel",
                text = "Ongoing Effect:",
            },

            gui.Dropdown{
                idChosen = self.ongoingEffect,
                options = effectOptions,
                hasSearch = true,
                change = function(element)
                    self.ongoingEffect = element.idChosen
                    parentPanel:FireEvent("refreshBehavior")
                end,

            },
        }

    end

    if self.mode == "conditions" then
        local conditionOptions = {}
        local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
        for k,v in unhidden_pairs(conditionsTable) do
            conditionOptions[#conditionOptions+1] = {
                id = k,
                text = v.name,
            }
        end

        table.sort(conditionOptions, function(a,b) return a.text < b.text end)
        table.insert(conditionOptions, 1, {
            id = "none",
            text = "All Conditions",
        })

        result[#result+1] = gui.Panel{
            classes = "formPanel",
            gui.Label{
                classes = "formLabel",
                text = "Conditions:",
            },

            gui.Panel{
                flow = "vertical",
                width = 300,
                height = "auto",

                gui.Panel{
                    flow = "vertical",
                    width = "100%",
                    height = "auto",
                    create = function(element)
                        element:FireEvent("refreshPurge")
                    end,
                    refreshPurge = function(element)

                        local children = {}
                        for i,cond in ipairs(self.conditions) do
                            children[#children+1] = gui.Label{
                                width = 240,
                                height = "auto",
                                fontSize = 14,
                                color = "white",
                                text = conditionsTable[cond].name,
                                vmargin = 4,

                                gui.DeleteItemButton{
                                    width = 16,
                                    height = 16,
                                    floating = true,
                                    halign = 'right',
                                    valign = 'center',
                                    click = function(element)
                                        table.remove(self.conditions, i)
                                        parentPanel:FireEventTree("refreshPurge")
                                    end,
                                },
                            }
                        end

                        element.children = children
                    end,
                },

                gui.Dropdown{
                    options = conditionOptions,
                    idChosen = "none",
                    halign = "left",
                    create = function(element)
                        element:FireEvent("refreshPurge")
                    end,
                    refreshPurge = function(element)
                        if #self.conditions == 0 then
                            conditionOptions[1].text = "All Conditions"
                        else
                            conditionOptions[1].text = "Add Condition..."
                        end
                        element.options = conditionOptions
                        element.idChosen = "none"
                    end,
                    change = function(element)
                        if element.idChosen ~= "none" then
                            self.conditions[#self.conditions+1] = element.idChosen
                        end
                        parentPanel:FireEventTree("refreshPurge")
                    end,
                },
            },
        }
    end

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Purge:",
        },

        gui.Dropdown{
            idChosen = self.purgeType,
            options = ActivatedAbilityPurgeEffectsBehavior.purgeTypeOptions,
            change = function(element)
                self.purgeType = element.idChosen
            end,

        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel", cond(self.mode ~= "conditions", "collapsed")},
        refreshPurge = function(element)
            element:SetClass("collapsed", self.mode ~= "conditions")
        end,
        gui.Label{
            classes = "formLabel",
            text = "Target Duration:",
        },

        gui.Dropdown{
            idChosen = self:try_get("targetDuration", "all"),
            options = {
                {
                    id = "all",
                    text = "All Effects",
                },
                {
                    id = "save",
                    text = "Save Ends",
                },
                {
                    id = "save|eot",
                    text = "Save or EoT",
                },
            },
            change = function(element)
                self.targetDuration = element.idChosen
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Log Message:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.chatMessage,
            events = {
                change = function(element)
                    self.chatMessage = element.text
                end
            }
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Damage to Self:",
        },
        gui.Input{
            classes = {"formInput"},
            placeholderText = "Enter Damage...",
            text = self:try_get("damageToSelf", ""),
            characterLimit = 3,
            change = function(element)
                self.damageToSelf = element.text
            end,
        },
    }

    result[#result+1] = gui.Check{
        text = "Number of Stacks",
        value = self.useStacks,
        change = function(element)
            self.useStacks = element.value
            parentPanel:FireEventTree("refreshPurge")
        end,
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        create = function(element)
            element:FireEvent("refreshPurge")
        end,
        refreshPurge = function(element)
            element:SetClass("collapsed", self.useStacks == false)
        end,
        gui.Label{
            classes = "formLabel",
            text = "Stacks:",
        },
        gui.GoblinScriptInput{
            value = self.stacksFormula,
            events = {
                change = function(element)
                    self.stacksFormula = element.value
                end,
            },

			documentation = {
				help = string.format("This GoblinScript determines the number of stacks to purge."),
				output = "roll",
				examples = {
					{
						script = "1",
						text = "1 stack is purged.",
					},
					{
						script = "Wisdom Modifier",
						text = "Stacks equal to the caster's wisdom modifier are purged.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature that is casting the spell.",
				symbols = ActivatedAbility.helpCasting,
			},
        }
    }

	return result
end
