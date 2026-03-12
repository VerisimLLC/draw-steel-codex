local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityPurgeEffectsBehavior:ActivatedAbilityBehavior
--- @field conditions string[] List of condition ids to purge; empty means purge all ongoing effects.
ActivatedAbilityPurgeEffectsBehavior = RegisterGameType("ActivatedAbilityPurgeEffectsBehavior", "ActivatedAbilityBehavior")


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
ActivatedAbilityPurgeEffectsBehavior.reminderText = ""
ActivatedAbilityPurgeEffectsBehavior.includeOngoingEffects = false

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

    --Check if there is a caster to limit effects to.
    local limitToCasterid
    if self:try_get("fromCaster", "") ~= "" then
        if options.symbols == nil then
            options.symbols = {}
        end
        local effectCaster = dmhub.EvalGoblinScriptToObject(self.fromCaster, casterToken.properties:LookupSymbol(options.symbols), "Determine source of purge")
        if effectCaster ~= nil and type(effectCaster) == "table" and (effectCaster.typeName == "creature" or effectCaster.typeName == "character" or effectCaster.typeName == "monster" or effectCaster.typeName == "follower") then
            limitToCasterid = dmhub.LookupTokenId(effectCaster)
        end
    end

    local messages = {}

    for _,target in ipairs(targets) do
        if target.token ~= nil then
            self:CastOnTarget(casterToken, target.token, ability, options, limitToCasterid)

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

-- limitToCasterid: optional charid string; when set, only effects/conditions from that caster are purged.
function ActivatedAbilityPurgeEffectsBehavior:CastOnTarget(casterToken, targetToken, ability, options, limitToCasterid)
    local targetCreature = targetToken.properties

    local effects = targetCreature:ActiveOngoingEffects()
    local filteredEffects = {}
    for _,effect in ipairs(effects) do
        if self:AppliesToEffect(effect) then
            if limitToCasterid == nil then
                filteredEffects[#filteredEffects+1] = effect
            else
                local effectCasterInfo = effect:try_get("casterInfo")
                if effectCasterInfo ~= nil and effectCasterInfo.tokenid == limitToCasterid then
                    filteredEffects[#filteredEffects+1] = effect
                end
            end
        end
    end

    local result = {}

    -- Combined mode: merge conditions from inflictedConditions into filteredEffects so a
    -- single ShowSelectionDialog handles both.  Conditions already represented by an ongoing
    -- effect instance in filteredEffects are skipped to avoid duplicates.
    if self.mode == "conditions" and self:try_get("includeOngoingEffects", false) and targetCreature:has_key("inflictedConditions") then
        local targetDuration = self:try_get("targetDuration", "all")
        local durationTable = string.split(targetDuration, "|")
        local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
        local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

        -- Build set of condition IDs already covered by a filteredEffects entry
        local coveredConditions = {}
        for _, effect in ipairs(filteredEffects) do
            local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
            if effectInfo ~= nil and effectInfo:try_get("condition", "none") ~= "none" then
                coveredConditions[effectInfo.condition] = true
            end
        end

        for key, conditionInfo in pairs(targetCreature.inflictedConditions) do
            if not coveredConditions[key] then
                if #self.conditions == 0 or table.contains(self.conditions, key) then
                    local passFilter = false
                    for _, durationEntry in ipairs(durationTable) do
                        if durationEntry == "all" or string.lower(durationEntry) == string.lower(conditionInfo.duration or "") then
                            passFilter = true
                            break
                        end
                    end

                    if passFilter then
                        local casterOk = limitToCasterid == nil
                        if not casterOk then
                            local ci = conditionInfo.casterInfo
                            casterOk = (ci ~= nil and ci.tokenid == limitToCasterid)
                        end

                        if casterOk then
                            -- Find an ongoing effect definition that wraps this condition so the
                            -- apply step (CastFromFormula) can use ApplyOngoingEffect with its ID.
                            local defId = nil
                            local defIconid = conditionsTable[key] and conditionsTable[key].iconid or nil
                            local defDisplay = conditionsTable[key] and conditionsTable[key].display or nil
                            local defName = conditionsTable[key] and conditionsTable[key].name or key

                            for k, def in pairs(ongoingEffectsTable) do
                                if def:try_get("condition", "none") == key then
                                    defId = k
                                    break
                                end
                            end

                            filteredEffects[#filteredEffects+1] = {
                                ongoingEffectid = defId,
                                seq = nil,
                                _condid = key,
                                _isConditionOnly = true,
                                _iconid = defIconid,
                                _display = defDisplay,
                                _name = defName,
                                _limitToCasterid = limitToCasterid,
                                _conditionDuration = conditionInfo.duration,
                            }
                        end
                    end
                end
            end
        end
    end

    if self.mode == "conditions" and not self:try_get("includeOngoingEffects", false) and targetCreature:has_key("inflictedConditions") then
        local conditions = {}
        local targetDuration = self:try_get("targetDuration", "all")
        local durationTable = string.split(targetDuration, "|")
        for key,conditionInfo in pairs(targetCreature.inflictedConditions) do
            if #self.conditions == 0 or table.contains(self.conditions, key) then
                for _,durationEntry in ipairs(durationTable) do
                    if durationEntry == "all" or string.lower(durationEntry) == string.lower(conditionInfo.duration) then
                        local shouldAdd = true
                        
                        -- Check caster filter if specified
                        if limitToCasterid ~= nil and conditionInfo.casterInfo ~= nil then
                            if limitToCasterid ~= conditionInfo.casterInfo.tokenid then
                                shouldAdd = false
                            end
                        end
                        
                        if shouldAdd then
                            conditions[#conditions+1] = key
                            break
                        end
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
                    local purgeArgs = {purge = true}
                    if limitToCasterid ~= nil then
                        purgeArgs.casterInfo = {tokenid = limitToCasterid}
                    end
                    for _,condid in ipairs(conditionsToPurge) do
                        targetCreature:InflictCondition(condid, purgeArgs)
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
                    if rawget(effect, "_isConditionOnly") then
                        local purgeArgs = {purge = true}
                        if rawget(effect, "_limitToCasterid") ~= nil then
                            purgeArgs.casterInfo = {tokenid = rawget(effect, "_limitToCasterid")}
                        end
                        targetCreature:InflictCondition(rawget(effect, "_condid"), purgeArgs)
                    else
                        targetCreature:RemoveOngoingEffectBySeq(effect.seq)
                        result[#result+1] = effect.ongoingEffectid
                    end
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
        if self:try_get("includeOngoingEffects", false) then
            -- Filter ongoing effects by targetDuration using the effect definition
            local targetDuration = self:try_get("targetDuration", "all")
            if targetDuration == "all" then
                return true
            end
            local durationTable = string.split(targetDuration, "|")
            for _, durationEntry in ipairs(durationTable) do
                if durationEntry == "all" then
                    return true
                elseif durationEntry == "save" then
                    if effect:try_get("removeOnSave", false) then
                        return true
                    end
                elseif durationEntry == "eot" then
                    if effect:try_get("removeAtNextTurnEnd", false) then
                        return true
                    end
                end
            end
            return false
        end

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

    local dialogContent = {}
    if options.reminderText and options.reminderText ~= "" then
        dialogContent[#dialogContent+1] = gui.Label{
            text = options.reminderText,
            fontSize = 14,
            color = "white",
            textWrap = true,
            width = 600,
            height = "auto",
            halign = "center",
            textAlignment = "center",
            vmargin = 8,
        }
    end
    dialogContent[#dialogContent+1] = gui.Panel{
        flow = "vertical",
        vscroll = true,
        width = 600,
        height = 500,
        halign = "center",
        valign = "center",
        children = optionPanels,
    }

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

        children = dialogContent,
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
        reminderText = self:try_get("reminderText", ""),
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
        reminderText = self:try_get("reminderText", ""),
        options = {},
    }

	local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

    for i,effect in ipairs(effectsList) do
        -- Use rawget for underscore-prefixed fields: plain-table synthetic entries have them,
        -- but CharacterOngoingEffectInstance is a strict game type that throws on unknown fields.
        local isConditionOnly = rawget(effect, "_isConditionOnly") or false
        local iconid, display, text
        if isConditionOnly then
            iconid = rawget(effect, "_iconid")
            display = rawget(effect, "_display")
            text = rawget(effect, "_name")
        else
            local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
            iconid = effectInfo.iconid
            display = effectInfo.display
            text = effectInfo.name
        end

        local inheritedDuration = nil
        if isConditionOnly then
            local d = string.lower(rawget(effect, "_conditionDuration") or "")
            if d == "eot" then
                inheritedDuration = "end_of_next_turn"
            elseif d == "save" then
                inheritedDuration = "save_ends"
            end
        else
            if effect:try_get("removeOnSave", false) then
                inheritedDuration = "save_ends"
            elseif effect:try_get("removeAtNextTurnEnd", false) then
                inheritedDuration = "end_of_next_turn"
            end
        end

        local option = {
            id = effect.ongoingEffectid,
            seq = effect.seq,
            condid = rawget(effect, "_condid"),
            isConditionOnly = isConditionOnly,
            limitToCasterid = rawget(effect, "_limitToCasterid"),
            inheritedDuration = inheritedDuration,
            selected = self.purgeType ~= "one" or i == 1,
            iconid = iconid,
            display = display,
            text = text,
        }

        args.options[#args.options+1] = option
    end

    local complete = self:ShowOptionsDialog(args)
    if complete then
        ability:CommitToPaying(casterToken, options)

        -- Track purged IDs and durations outside ModifyProperties (correct pattern)
        local purgedList = options.symbols.cast:get_or_add("purgedOngoingEffectsChosen", {})
        local durationsMap = options.symbols.cast:get_or_add("purgedOngoingEffectDurations", {})
        local selectedOptions = {}
        for i, option in ipairs(args.options) do
            if option.selected then
                if option.id ~= nil then
                    purgedList[#purgedList+1] = option.id
                    if option.inheritedDuration ~= nil then
                        durationsMap[option.id] = {duration = option.inheritedDuration, untilEndOfTurn = false}
                    end
                end
                selectedOptions[#selectedOptions+1] = option
            end
        end

        -- Only token property mutation belongs inside ModifyProperties
        targetToken:ModifyProperties{
            description = "Purge Effects",
            execute = function()
                for _, option in ipairs(selectedOptions) do
                    if option.isConditionOnly then
                        local purgeArgs = {purge = true}
                        if option.limitToCasterid ~= nil then
                            purgeArgs.casterInfo = {tokenid = option.limitToCasterid}
                        end
                        targetToken.properties:InflictCondition(option.condid, purgeArgs)
                    else
                        targetToken.properties:RemoveOngoingEffectBySeq(option.seq)
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

    if self.mode == "conditions" then
        result[#result+1] = gui.Check{
            text = "Include Ongoing Effects",
            value = self:try_get("includeOngoingEffects", false),
            change = function(element)
                self.includeOngoingEffects = element.value
                parentPanel:FireEvent("refreshBehavior")
            end,
        }
    end

    --Future support Shwayguy
    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Limit to Caster:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("fromCaster", ""),
            events = {
                change = function(element)
                    self.fromCaster = element.value
                end,
            },

			documentation = {
				help = string.format("When given a creature, the purged effects are limited to conditions or effects inflicted by the creature."),
				output = "creature",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is casting the spell.",
				examples = {
					{
						script = "Caster",
						text = "Purged effects are limited to those inflicted by the caster of this ability.",
					},
					{
						script = "Target",
						text = "Purged effects are limited to those inflicted by the target of this ability.",
					},
				},
				symbols = ActivatedAbility.CatHelpSymbols(ActivatedAbility.helpCasting, {
                    caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The creature that is casting the ability.",
                    },
                    target = {
                        name = "Target",
                        type = "creature",
                        desc = "The target creature of the ability.",
                    },
                    subject = {
						name = "Subject",
						type = "creature",
						desc = "The subject of the triggered ability. Only valid within a triggered ability.",
					},
                })
			},
        }
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
            text = "Reminder Text:",
        },
        gui.Input{
            classes = {"formInput"},
            placeholderText = "Enter text...",
            text = self:try_get("reminderText", ""),
            change = function(element)
                self.reminderText = element.text
            end,
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
