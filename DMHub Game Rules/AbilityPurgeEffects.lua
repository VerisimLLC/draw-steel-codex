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
ActivatedAbilityPurgeEffectsBehavior.value = ""

ActivatedAbilityPurgeEffectsBehavior.modeOptions = {
    {
        id = "conditions",
        text = "Underlying Condition",
    },
    {
        id = "conditions_and_effects",
        text = "Conditions and Effects",
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
    {
        id = "replace",
        text = "Replace Effects",
    },
}



function ActivatedAbilityPurgeEffectsBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 then
        return
    end

    -- Resolve optional caster limit from GoblinScript (unchanged).
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

    if self.purgeType == "all" then
        -- Unchanged: per-target CastOnTarget handles filtering and mutation.
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

    elseif self.purgeType == "replace" then
        -- "replace": change a condition to another from the pre-defined list,
        -- preserving the original condition's duration and caster info.

        -- Evaluate the optional GoblinScript value formula for a replacement cap.
        local maxReplacements = nil
        local valueFormula = self:try_get("value", "")
        if valueFormula ~= "" then
            if options.symbols == nil then
                options.symbols = {}
            end
            local val = ExecuteGoblinScript(valueFormula, casterToken.properties:LookupSymbol(options.symbols), nil, "Max conditions to replace")
            if type(val) == "number" then
                maxReplacements = math.floor(val)
            end
        end

        -- Phase 1: collect matching conditions per target.
        local targetDataList = {}
        for _, target in ipairs(targets) do
            if target.token ~= nil then
                local data = self:CollectPurgeItems(target.token, limitToCasterid)
                if data ~= nil then
                    targetDataList[#targetDataList+1] = data
                end
            end
        end

        if #targetDataList == 0 then
            ability:CommitToPaying(casterToken, options)
            return
        end

        -- Phase 2: show the replacement dialog.
        local confirmed, replacements = self:ShowReplaceDialog(targetDataList, ability, casterToken, maxReplacements)
        if not confirmed then
            return
        end

        ability:CommitToPaying(casterToken, options)

        -- Phase 3: apply mutations, preserving original duration and caster info.
        local replacementCount = 0
        for _, data in ipairs(targetDataList) do
            local rep = replacements[data.token.id]
            if rep ~= nil and rep.fromConditionId ~= nil and rep.toConditionId ~= nil then
                if maxReplacements == nil or replacementCount < maxReplacements then
                    replacementCount = replacementCount + 1
                    data.token:ModifyProperties{
                        description = "Replace Condition",
                        execute = function()
                            local origEntry = data.token.properties:try_get("inflictedConditions", {})[rep.fromConditionId]
                            local origDuration = origEntry and origEntry.duration or nil
                            local origCasterInfo = (origEntry and origEntry.casterInfo)
                                and {tokenid = origEntry.casterInfo.tokenid} or nil
                            data.token.properties:InflictCondition(rep.fromConditionId, {purge = true})
                            data.token.properties:InflictCondition(rep.toConditionId, {
                                duration = origDuration,
                                casterInfo = origCasterInfo,
                            })
                        end,
                    }

                    if self.chatMessage ~= "" then
                        local existingMessage = messages[#messages]
                        if existingMessage ~= nil and dmhub.DeepEqual(existingMessage.conditions, self.conditions) then
                            existingMessage.targetids[#existingMessage.targetids+1] = data.token.charid
                        else
                            messages[#messages+1] = ActivatedAbilityPurgeEffectsChatMessage.new{
                                ability = ability,
                                casterid = casterToken.charid,
                                chatMessage = self.chatMessage,
                                conditions = self.conditions,
                                targetids = { data.token.charid },
                            }
                        end
                    end
                end
            end
        end

    else
        -- "chosen" / "one": show a single unified dialog for all targets.

        -- numStacks is caster-based, so the same for every target.
        local numStacks = nil
        if self.useStacks then
            numStacks = ExecuteGoblinScript(self.stacksFormula, GenerateSymbols(casterToken.properties), 0, "Number of stacks of effect to remove")
        end

        -- Phase 1: collect purgeable items per target.
        local targetDataList = {}
        for _,target in ipairs(targets) do
            if target.token ~= nil then
                local data = self:CollectPurgeItems(target.token, limitToCasterid)
                if data ~= nil then
                    targetDataList[#targetDataList+1] = data
                end
            end
        end

        if #targetDataList == 0 then
            ability:CommitToPaying(casterToken, options)
            return
        end

        -- Evaluate the optional GoblinScript value formula to cap how many
        -- effects the player may choose (nil = unlimited).
        local maxSelections = nil
        local valueFormula = self:try_get("value", "")
        if valueFormula ~= "" then
            if options.symbols == nil then
                options.symbols = {}
            end
            local val = ExecuteGoblinScript(valueFormula, casterToken.properties:LookupSymbol(options.symbols), nil, "Max effects to purge")
            if type(val) == "number" then
                maxSelections = math.floor(val)
            end
        end

        -- Phase 2: show the new unified selection panel.
        local confirmed, selections = self:ShowPurgeDialog(targetDataList, ability, casterToken, maxSelections)
        if not confirmed then
            return
        end

        -- CommitToPaying after confirm, matching the per-dialog call sites in the old flow.
        ability:CommitToPaying(casterToken, options)

        -- Phase 3: write downstream symbols then apply token mutations.
        -- Symbol tables are obtained outside ModifyProperties (correct pattern, mirrors ShowSelectionDialog).
        local purgedList = options.symbols.cast:get_or_add("purgedOngoingEffectsChosen", {})
        local durationsMap = options.symbols.cast:get_or_add("purgedOngoingEffectDurations", {})

        for _, data in ipairs(targetDataList) do
            local selectedItems = selections[data.token.id] or {}
            if #selectedItems > 0 then

                -- Count purged conditions and populate symbol tables before ModifyProperties.
                local purgedConditionsCount = 0
                for _, item in ipairs(selectedItems) do
                    if item.type == "condition" then
                        purgedConditionsCount = purgedConditionsCount + 1
                    elseif item.type == "conditionOnly" then
                        if item.effectId ~= nil then
                            purgedList[#purgedList+1] = item.effectId
                            if item.inheritedDuration ~= nil then
                                durationsMap[item.effectId] = {duration = item.inheritedDuration, untilEndOfTurn = false}
                            end
                        end
                    else
                        -- type == "effect"
                        purgedList[#purgedList+1] = item.effectId
                        if item.inheritedDuration ~= nil then
                            durationsMap[item.effectId] = {duration = item.inheritedDuration, untilEndOfTurn = false}
                        end
                    end
                end

                -- purgedConditions: overwrite per-target, matching original line 383 behaviour.
                if purgedConditionsCount > 0 then
                    options.symbols.cast.purgedConditions = purgedConditionsCount
                end

                -- Token mutations belong inside ModifyProperties.
                data.token:ModifyProperties{
                    description = "Purge Effects",
                    execute = function()
                        for _, item in ipairs(selectedItems) do
                            if item.type == "condition" then
                                local purgeArgs = {purge = true}
                                if limitToCasterid ~= nil then
                                    purgeArgs.casterInfo = {tokenid = limitToCasterid}
                                end
                                data.token.properties:InflictCondition(item.conditionId, purgeArgs)
                            elseif item.type == "conditionOnly" then
                                local purgeArgs = {purge = true}
                                if item.limitToCasterid ~= nil then
                                    purgeArgs.casterInfo = {tokenid = item.limitToCasterid}
                                end
                                data.token.properties:InflictCondition(item.conditionId, purgeArgs)
                            else
                                -- type == "effect"
                                data.token.properties:RemoveOngoingEffectBySeq(item.seq, numStacks)
                            end
                        end

                        -- damageToSelf: applied once per target when conditions were selected,
                        -- matching original behaviour (lines 397-400 in CastOnTarget).
                        if purgedConditionsCount > 0 and self.damageToSelf ~= "" then
                            local damage = tonumber(self.damageToSelf)
                            if damage ~= nil and damage > 0 then
                                data.token.properties:TakeDamage(damage, "Purged condition")
                            end
                        end
                    end,
                }

                -- Chat message per target.
                if self.chatMessage ~= "" then
                    local existingMessage = messages[#messages]
                    if existingMessage ~= nil and dmhub.DeepEqual(existingMessage.conditions, self.conditions) then
                        existingMessage.targetids[#existingMessage.targetids+1] = data.token.charid
                    else
                        messages[#messages+1] = ActivatedAbilityPurgeEffectsChatMessage.new{
                            ability = ability,
                            casterid = casterToken.charid,
                            chatMessage = self.chatMessage,
                            conditions = self.conditions,
                            targetids = { data.token.charid },
                        }
                    end
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
    if self.mode == "conditions_and_effects" and targetCreature:has_key("inflictedConditions") then
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

    if self.mode == "conditions" and targetCreature:has_key("inflictedConditions") then
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
                        targetCreature:RemoveOngoingEffectBySeq(effect.seq, numStacks)
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
    if self.mode == "conditions" or self.mode == "conditions_and_effects" then
        if self.mode == "conditions_and_effects" then
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

-- Collects all purgeable items for a single target token into a flat list.
-- Each item carries enough metadata for both display (chip) and mutation (apply purge).
-- Mirrors the three filtering paths in CastOnTarget so behaviour is identical.
-- Returns nil when there is nothing to purge for this token.
-- item.type values: "condition" | "conditionOnly" | "effect"
function ActivatedAbilityPurgeEffectsBehavior:CollectPurgeItems(targetToken, limitToCasterid)
    local targetCreature = targetToken.properties
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
    local items = {}

    if self.mode == "conditions" then
        -- Path A: conditions-only mode.
        -- Mirror CastOnTarget lines 341-403: if no conditions found, return nil (early-return preserved).
        if not targetCreature:has_key("inflictedConditions") then
            return nil
        end

        local targetDuration = self:try_get("targetDuration", "all")
        local durationTable = string.split(targetDuration, "|")
        local conditionFound = false

        for key, conditionInfo in pairs(targetCreature.inflictedConditions) do
            if #self.conditions == 0 or table.contains(self.conditions, key) then
                local passFilter = false
                for _, durationEntry in ipairs(durationTable) do
                    if durationEntry == "all" or string.lower(durationEntry) == string.lower(conditionInfo.duration or "") then
                        passFilter = true
                        break
                    end
                end
                local casterOk = limitToCasterid == nil
                if not casterOk and conditionInfo.casterInfo ~= nil then
                    casterOk = conditionInfo.casterInfo.tokenid == limitToCasterid
                end
                if passFilter and casterOk then
                    conditionFound = true
                    local condDef = conditionsTable[key]
                    items[#items+1] = {
                        type = "condition",
                        conditionId = key,
                        displayName = condDef and condDef.name or key,
                        iconid = condDef and condDef.iconid or nil,
                        display = condDef and condDef.display or nil,
                    }
                end
            end
        end

        -- Honour the original early-return: if no matching conditions, nothing to show.
        if not conditionFound then
            return nil
        end

        -- Fall-through path (mirrors CastOnTarget lines 406+): also collect ongoing effects
        -- whose effectInfo.condition matches the filter.
        for _, effect in ipairs(targetCreature:ActiveOngoingEffects()) do
            if self:AppliesToEffect(effect) then
                local shouldAdd = limitToCasterid == nil
                if not shouldAdd then
                    local casterInfo = effect:try_get("casterInfo")
                    shouldAdd = casterInfo ~= nil and casterInfo.tokenid == limitToCasterid
                end
                if shouldAdd then
                    local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                    if effectInfo ~= nil then
                        local inheritedDuration = nil
                        if effect:try_get("removeOnSave", false) then
                            inheritedDuration = "save_ends"
                        elseif effect:try_get("removeAtNextTurnEnd", false) then
                            inheritedDuration = "end_of_next_turn"
                        end
                        items[#items+1] = {
                            type = "effect",
                            effectId = effect.ongoingEffectid,
                            seq = effect.seq,
                            displayName = effectInfo.name,
                            iconid = effectInfo.iconid,
                            display = effectInfo.display,
                            inheritedDuration = inheritedDuration,
                        }
                    end
                end
            end
        end

    elseif self.mode == "conditions_and_effects" then
        -- Path B: combined mode -- mirrors CastOnTarget lines 271-339.
        local targetDuration = self:try_get("targetDuration", "all")
        local durationTable = string.split(targetDuration, "|")
        local coveredConditions = {}

        for _, effect in ipairs(targetCreature:ActiveOngoingEffects()) do
            if self:AppliesToEffect(effect) then
                local shouldAdd = limitToCasterid == nil
                if not shouldAdd then
                    local casterInfo = effect:try_get("casterInfo")
                    shouldAdd = casterInfo ~= nil and casterInfo.tokenid == limitToCasterid
                end
                if shouldAdd then
                    local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                    if effectInfo ~= nil then
                        if effectInfo:try_get("condition", "none") ~= "none" then
                            coveredConditions[effectInfo.condition] = true
                        end
                        local inheritedDuration = nil
                        if effect:try_get("removeOnSave", false) then
                            inheritedDuration = "save_ends"
                        elseif effect:try_get("removeAtNextTurnEnd", false) then
                            inheritedDuration = "end_of_next_turn"
                        end
                        items[#items+1] = {
                            type = "effect",
                            effectId = effect.ongoingEffectid,
                            seq = effect.seq,
                            displayName = effectInfo.name,
                            iconid = effectInfo.iconid,
                            display = effectInfo.display,
                            inheritedDuration = inheritedDuration,
                        }
                    end
                end
            end
        end

        -- Merge inflictedConditions not already covered by an ongoing effect.
        if targetCreature:has_key("inflictedConditions") then
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
                        local casterOk = limitToCasterid == nil
                        if not casterOk and conditionInfo.casterInfo ~= nil then
                            casterOk = conditionInfo.casterInfo.tokenid == limitToCasterid
                        end
                        if passFilter and casterOk then
                            -- Find the wrapping ongoing effect definition ID (may be nil).
                            local defId = nil
                            for k, def in pairs(ongoingEffectsTable) do
                                if def:try_get("condition", "none") == key then
                                    defId = k
                                    break
                                end
                            end
                            local condDef = conditionsTable[key]
                            local d = string.lower(conditionInfo.duration or "")
                            local inheritedDuration = nil
                            if d == "eot" then
                                inheritedDuration = "end_of_next_turn"
                            elseif d == "save" then
                                inheritedDuration = "save_ends"
                            end
                            items[#items+1] = {
                                type = "conditionOnly",
                                conditionId = key,
                                effectId = defId,
                                limitToCasterid = limitToCasterid,
                                inheritedDuration = inheritedDuration,
                                displayName = condDef and condDef.name or key,
                                iconid = condDef and condDef.iconid or nil,
                                display = condDef and condDef.display or nil,
                            }
                        end
                    end
                end
            end
        end

    else
        -- Path C: specific ongoing effect mode -- mirrors CastOnTarget lines 406+.
        for _, effect in ipairs(targetCreature:ActiveOngoingEffects()) do
            if self:AppliesToEffect(effect) then
                local shouldAdd = limitToCasterid == nil
                if not shouldAdd then
                    local casterInfo = effect:try_get("casterInfo")
                    shouldAdd = casterInfo ~= nil and casterInfo.tokenid == limitToCasterid
                end
                if shouldAdd then
                    local effectInfo = ongoingEffectsTable[effect.ongoingEffectid]
                    if effectInfo ~= nil then
                        local inheritedDuration = nil
                        if effect:try_get("removeOnSave", false) then
                            inheritedDuration = "save_ends"
                        elseif effect:try_get("removeAtNextTurnEnd", false) then
                            inheritedDuration = "end_of_next_turn"
                        end
                        items[#items+1] = {
                            type = "effect",
                            effectId = effect.ongoingEffectid,
                            seq = effect.seq,
                            displayName = effectInfo.name,
                            iconid = effectInfo.iconid,
                            display = effectInfo.display,
                            inheritedDuration = inheritedDuration,
                        }
                    end
                end
            end
        end
    end

    if #items == 0 then
        return nil
    end
    return {
        token = targetToken,
        items = items,
    }
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

-- Shows the new styled purge-effects selection panel.
-- targetDataList: list of {token, items} from CollectPurgeItems.
-- Returns confirmed (bool), selections ({[tokenId] = {item, ...}}).
-- Nothing is pre-selected (opt-in UX).  For purgeType "one", only one chip
-- per token row can be selected at a time.
function ActivatedAbilityPurgeEffectsBehavior:ShowPurgeDialog(targetDataList, ability, casterToken, maxSelections)
    local finished = false
    local canceled = false
    local multiSelect = self.purgeType ~= "one"

    -- selections[tokenId] = list of selected item references
    local selections = {}
    for _, data in ipairs(targetDataList) do
        selections[data.token.id] = {}
    end

    -- Build one row per target token.
    local tokenRows = {}
    for _, data in ipairs(targetDataList) do
        local tokenId = data.token.id
        local chipPanels = {}

        for _, item in ipairs(data.items) do
            local capturedItem = item

            local chipChildren = {}
            if item.iconid ~= nil then
                chipChildren[#chipChildren+1] = gui.Panel{
                    classes = {"purge-chip-icon"},
                    bgimage = item.iconid,
                    selfStyle = item.display,
                }
            end
            chipChildren[#chipChildren+1] = gui.Label{
                classes = {"purge-chip-label"},
                text = item.displayName,
            }

            chipPanels[#chipPanels+1] = gui.Panel{
                classes = {"purge-chip"},
                flow = "horizontal",

                press = function(element)
                    local tokenSelections = selections[tokenId]
                    if multiSelect then
                        local isSelected = element:HasClass("purge-chip-selected")
                        if isSelected then
                            -- Always allow deselection.
                            element:SetClass("purge-chip-selected", false)
                            for i, sel in ipairs(tokenSelections) do
                                if sel == capturedItem then
                                    table.remove(tokenSelections, i)
                                    break
                                end
                            end
                        elseif maxSelections == nil or #tokenSelections < maxSelections then
                            -- Only select if under the cap (or no cap).
                            element:SetClass("purge-chip-selected", true)
                            tokenSelections[#tokenSelections+1] = capturedItem
                        end
                    else
                        -- Single-select: clear all sibling chips first.
                        for _, sibling in ipairs(element.parent.children) do
                            sibling:SetClass("purge-chip-selected", false)
                        end
                        element:SetClass("purge-chip-selected", true)
                        selections[tokenId] = {capturedItem}
                    end
                end,

                children = chipChildren,
            }
        end

        tokenRows[#tokenRows+1] = gui.Panel{
            classes = {"purge-token-row"},
            gui.Panel{
                classes = {"purge-token-header"},
                gui.CreateTokenImage(data.token, {
                    classes = {"purge-token-image"},
                    width = 40,
                    height = 40,
                    valign = "center",
                }),
                gui.Label{
                    classes = {"purge-token-name"},
                    text = data.token.name,
                },
            },
            gui.Panel{
                classes = {"purge-chips-wrap"},
                children = chipPanels,
            },
        }
    end

    -- Assemble panel contents.
    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"purge-title"},
        text = "PURGE EFFECTS",
    }

    local reminderText = self:try_get("reminderText", "")
    if reminderText ~= "" then
        mainChildren[#mainChildren+1] = gui.Label{
            classes = {"purge-reminder"},
            text = reminderText,
        }
    end

    -- Instruction label: always shown for "one" and "chosen" purge types.
    local instructionText
    if self.purgeType == "one" then
        instructionText = "Select an effect to end"
    elseif maxSelections ~= nil then
        instructionText = string.format("Select up to %d effects", maxSelections)
    else
        instructionText = "Select effects to end"
    end
    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"purge-count"},
        text = instructionText,
    }

    -- Damage-to-self warning: shown in red when a positive damage value is set.
    local damageNum = tonumber(self:try_get("damageToSelf", ""))
    if damageNum ~= nil and damageNum > 0 then
        local damageText
        if self.purgeType == "one" then
            damageText = string.format("Take %d damage to end an effect", damageNum)
        else
            damageText = string.format("Take %d damage to end effects", damageNum)
        end
        mainChildren[#mainChildren+1] = gui.Label{
            classes = {"purge-damage"},
            text = damageText,
        }
    end

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"purge-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        maxHeight = 420,
        vscroll = true,
        children = tokenRows,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"purge-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"purge-button-row"},
        gui.Panel{
            classes = {"purge-submit"},
            press = function(element)
                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"purge-button-label"},
                text = "Submit",
            },
        },
        gui.Panel{
            classes = {"purge-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"purge-button-label"},
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
        width = 480,
        height = "auto",
        pad = 12,

        styles = {
            {
                selectors = {"label", "purge-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-count"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#C49A5A",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-damage"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#D53031",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-reminder"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#5C6860",
                width = "100%",
                height = "auto",
                halign = "left",
                textWrap = true,
                bmargin = 4,
            },
            {
                selectors = {"panel", "purge-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "purge-token-row"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 4,
            },
            {
                selectors = {"panel", "purge-token-header"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 6,
                halign = "left",
            },
            {
                selectors = {"panel", "purge-token-image"},
                halign = "left",
                valign = "center",
                rmargin = 8,
            },
            {
                selectors = {"label", "purge-token-name"},
                fontFace = "Berling",
                fontSize = 14,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            {
                selectors = {"panel", "purge-chips-wrap"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                lmargin = 48,
                bmargin = 2,
            },
            {
                selectors = {"panel", "purge-chip"},
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
                selectors = {"panel", "purge-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "purge-chip", "purge-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"panel", "purge-chip-icon"},
                width = 16,
                height = 16,
                valign = "center",
                halign = "left",
                rmargin = 4,
            },
            {
                selectors = {"label", "purge-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "purge-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "purge-submit"},
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
                selectors = {"panel", "purge-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "purge-cancel"},
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
                selectors = {"panel", "purge-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "purge-button-label"},
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

    if canceled then
        return false, nil
    end
    return true, selections
end

-- Shows the replace-effects dialog.  The user selects one condition chip per target row
-- and then picks a replacement from the dropdown on the right.
-- targetDataList: list of {token, items} from CollectPurgeItems (conditions mode).
-- Returns confirmed (bool), replacements ({[tokenId] = {fromConditionId, toConditionId}}).
function ActivatedAbilityPurgeEffectsBehavior:ShowReplaceDialog(targetDataList, ability, casterToken, maxReplacements)
    local finished = false
    local canceled = false

    -- replacements[tokenId] = {fromConditionId = string, toConditionId = string} or nil
    local replacements = {}
    for _, data in ipairs(targetDataList) do
        replacements[data.token.id] = nil
    end

    -- Build the ordered list of conditions available as replacements.
    -- Uses self.conditions when set, or all conditions when the list is empty.
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    local replaceOptions = {}
    if #self.conditions == 0 then
        for k, v in unhidden_pairs(conditionsTable) do
            replaceOptions[#replaceOptions+1] = {id = k, text = v.name}
        end
    else
        for _, condId in ipairs(self.conditions) do
            local v = conditionsTable[condId]
            if v ~= nil then
                replaceOptions[#replaceOptions+1] = {id = condId, text = v.name}
            end
        end
    end
    table.sort(replaceOptions, function(a, b) return a.text < b.text end)

    local tokenRows = {}
    for _, data in ipairs(targetDataList) do
        local tokenId = data.token.id
        -- Per-row selection state, closed over by chip press and dest-chip handlers.
        local selectedItem = nil
        local selectedDestItem = nil
        local destWrapPanel = nil  -- set via create event on the dest chips wrap

        local chipPanels = {}
        for _, item in ipairs(data.items) do
            local capturedItem = item
            local chipChildren = {}
            if item.iconid ~= nil then
                chipChildren[#chipChildren+1] = gui.Panel{
                    classes = {"purge-chip-icon"},
                    bgimage = item.iconid,
                    selfStyle = item.display,
                }
            end
            chipChildren[#chipChildren+1] = gui.Label{
                classes = {"purge-chip-label"},
                text = item.displayName,
            }

            chipPanels[#chipPanels+1] = gui.Panel{
                classes = {"purge-chip"},
                flow = "horizontal",
                press = function(element)
                    -- Single-select: deselect all sibling chips first.
                    for _, sibling in ipairs(element.parent.children) do
                        sibling:SetClass("purge-chip-selected", false)
                    end
                    element:SetClass("purge-chip-selected", true)
                    selectedItem = capturedItem
                    replacements[tokenId] = nil
                    -- Rebuild the "With:" dest chips for this row.
                    if destWrapPanel ~= nil and destWrapPanel.valid then
                        destWrapPanel:FireEvent("rebuildOptions")
                    end
                end,
                children = chipChildren,
            }
        end

        tokenRows[#tokenRows+1] = gui.Panel{
            classes = {"purge-token-row"},
            gui.Panel{
                classes = {"purge-token-header"},
                gui.CreateTokenImage(data.token, {
                    classes = {"purge-token-image"},
                    width = 40,
                    height = 40,
                    valign = "center",
                }),
                gui.Label{
                    classes = {"purge-token-name"},
                    text = data.token.name,
                },
            },
            gui.Panel{
                classes = {"purge-replace-section"},
                -- Row 1: "Replace:" label + source condition chips.
                gui.Panel{
                    classes = {"purge-labeled-row"},
                    gui.Label{
                        classes = {"purge-row-label"},
                        text = "Replace:",
                    },
                    gui.Panel{
                        classes = {"purge-chips-wrap"},
                        children = chipPanels,
                    },
                },
                -- Row 2: "With:" label + destination condition chips (rebuilt dynamically).
                gui.Panel{
                    classes = {"purge-labeled-row"},
                    gui.Label{
                        classes = {"purge-row-label"},
                        text = "With:",
                    },
                    gui.Panel{
                        classes = {"purge-chips-wrap"},
                        create = function(element)
                            destWrapPanel = element
                            element.children = {
                                gui.Label{
                                    classes = {"purge-placeholder"},
                                    text = "Select a source condition above...",
                                },
                            }
                        end,
                        rebuildOptions = function(element)
                            replacements[tokenId] = nil
                            selectedDestItem = nil
                            local newChildren = {}
                            if selectedItem == nil then
                                newChildren[#newChildren+1] = gui.Label{
                                    classes = {"purge-placeholder"},
                                    text = "Select a source condition above...",
                                }
                            else
                                -- Filter: exclude the source condition and any condition
                                -- the target token already has (other than the source).
                                local existingConds = data.token.properties:try_get("inflictedConditions", {})
                                for _, opt in ipairs(replaceOptions) do
                                    local isSource = (opt.id == selectedItem.conditionId)
                                    local alreadyPresent = (existingConds[opt.id] ~= nil) and (opt.id ~= selectedItem.conditionId)
                                    if not isSource and not alreadyPresent then
                                        local capturedOpt = opt
                                        newChildren[#newChildren+1] = gui.Panel{
                                            classes = {"purge-chip"},
                                            flow = "horizontal",
                                            press = function(chipEl)
                                                -- Single-select among dest chips.
                                                for _, sib in ipairs(chipEl.parent.children) do
                                                    sib:SetClass("purge-chip-selected", false)
                                                end
                                                chipEl:SetClass("purge-chip-selected", true)
                                                selectedDestItem = capturedOpt
                                                replacements[tokenId] = {
                                                    fromConditionId = selectedItem.conditionId,
                                                    toConditionId   = capturedOpt.id,
                                                }
                                            end,
                                            gui.Label{
                                                classes = {"purge-chip-label"},
                                                text = capturedOpt.text,
                                            },
                                        }
                                    end
                                end
                                if #newChildren == 0 then
                                    newChildren[#newChildren+1] = gui.Label{
                                        classes = {"purge-placeholder"},
                                        text = "No valid replacements available.",
                                    }
                                end
                            end
                            element.children = newChildren
                        end,
                    },
                },
            },
        }
    end

    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"purge-title"},
        text = "REPLACE EFFECTS",
    }

    local reminderText = self:try_get("reminderText", "")
    if reminderText ~= "" then
        mainChildren[#mainChildren+1] = gui.Label{
            classes = {"purge-reminder"},
            text = reminderText,
        }
    end

    local instructionText
    if maxReplacements ~= nil then
        instructionText = string.format("Select up to %d condition(s) to replace", maxReplacements)
    else
        instructionText = "Select a condition to replace, then choose its replacement"
    end
    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"purge-count"},
        text = instructionText,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"purge-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        maxHeight = 420,
        vscroll = true,
        children = tokenRows,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"purge-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"purge-button-row"},
        gui.Panel{
            classes = {"purge-submit"},
            press = function(element)
                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"purge-button-label"},
                text = "Submit",
            },
        },
        gui.Panel{
            classes = {"purge-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"purge-button-label"},
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
        width = 540,
        height = "auto",
        pad = 12,

        styles = {
            {
                selectors = {"label", "purge-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-count"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#C49A5A",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-reminder"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#5C6860",
                width = "100%",
                height = "auto",
                halign = "left",
                textWrap = true,
                bmargin = 4,
            },
            {
                selectors = {"panel", "purge-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "purge-token-row"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 4,
            },
            {
                selectors = {"panel", "purge-token-header"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 6,
                halign = "left",
            },
            {
                selectors = {"panel", "purge-token-image"},
                halign = "left",
                valign = "center",
                rmargin = 8,
            },
            {
                selectors = {"label", "purge-token-name"},
                fontFace = "Berling",
                fontSize = 14,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            -- Stacked layout below the token header: two labeled rows (Replace / With).
            {
                selectors = {"panel", "purge-replace-section"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                lmargin = 48,
            },
            {
                selectors = {"panel", "purge-labeled-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 6,
            },
            {
                selectors = {"label", "purge-row-label"},
                fontFace = "Berling",
                fontSize = 11,
                color = "#5C6860",
                width = 65,
                height = "auto",
                valign = "top",
                tmargin = 4,
            },
            -- Chips area: fills remaining width after the row label (65px).
            {
                selectors = {"panel", "purge-chips-wrap"},
                width = "100%-65",
                height = "auto",
                flow = "horizontal",
                wrap = true,
            },
            {
                selectors = {"label", "purge-placeholder"},
                fontFace = "Berling",
                fontSize = 11,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                valign = "center",
                tmargin = 4,
            },
            {
                selectors = {"panel", "purge-chip"},
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
                selectors = {"panel", "purge-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "purge-chip", "purge-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"panel", "purge-chip-icon"},
                width = 16,
                height = 16,
                valign = "center",
                halign = "left",
                rmargin = 4,
            },
            {
                selectors = {"label", "purge-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "purge-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "purge-submit"},
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
                selectors = {"panel", "purge-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "purge-cancel"},
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
                selectors = {"panel", "purge-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "purge-button-label"},
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

    if canceled then
        return false, nil
    end
    return true, replacements
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
                        targetToken.properties:RemoveOngoingEffectBySeq(option.seq, numStacks)
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

    if self.mode == "conditions" or self.mode == "conditions_and_effects" then
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
                parentPanel:FireEventTree("refreshPurge")
            end,

        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel", cond(self.purgeType ~= "chosen" and self.purgeType ~= "replace", "collapsed")},
        create = function(element)
            element:FireEvent("refreshPurge")
        end,
        refreshPurge = function(element)
            element:SetClass("collapsed", self.purgeType ~= "chosen" and self.purgeType ~= "replace")
        end,
        gui.Label{
            classes = "formLabel",
            text = "Value:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("value", ""),
            events = {
                change = function(element)
                    self.value = element.value
                end,
            },
            documentation = {
                help = "A GoblinScript expression that sets the maximum number of effects the player may choose to purge. Leave blank to allow any number.",
                output = "number",
                subject = creature.helpSymbols,
                subjectDescription = "The creature casting the ability.",
                examples = {
                    {
                        script = "2",
                        text = "Player may choose up to 2 effects to purge.",
                    },
                    {
                        script = "Tier",
                        text = "Player may choose a number of effects equal to the caster's Tier.",
                    },
                },
                symbols = ActivatedAbility.CatHelpSymbols(ActivatedAbility.helpCasting, {
                    caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The creature casting the ability.",
                    },
                    target = {
                        name = "Target",
                        type = "creature",
                        desc = "The target of the ability.",
                    },
                }),
            },
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel", cond(self.mode == "effect", "collapsed")},
        refreshPurge = function(element)
            element:SetClass("collapsed", self.mode == "effect")
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
        classes = {"formPanel", cond(self.purgeType == "replace", "collapsed")},
        create = function(element)
            element:FireEvent("refreshPurge")
        end,
        refreshPurge = function(element)
            element:SetClass("collapsed", self.purgeType == "replace")
        end,
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
        classes = {cond(self.purgeType == "replace", "collapsed")},
        text = "Number of Stacks",
        value = self.useStacks,
        change = function(element)
            self.useStacks = element.value
            parentPanel:FireEventTree("refreshPurge")
        end,
        refreshPurge = function(element)
            element:SetClass("collapsed", self.purgeType == "replace")
        end,
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        create = function(element)
            element:FireEvent("refreshPurge")
        end,
        refreshPurge = function(element)
            element:SetClass("collapsed", self.useStacks == false or self.purgeType == "replace")
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
