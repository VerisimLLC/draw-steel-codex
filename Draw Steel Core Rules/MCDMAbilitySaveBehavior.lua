local mod = dmhub.GetModLoading()

--- @class ActivatedAbilitySaveBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field conditionsMode string Which conditions to attempt to save against: "all" or a specific condition id.
--- @field rollMode string How the save is resolved: "roll" (make a die roll) or "purge" (auto-succeed without rolling).
--- Draw Steel end-of-turn save behavior: rolls to remove conditions from the target creature.
ActivatedAbilitySaveBehavior = RegisterGameType("ActivatedAbilitySaveBehavior", "ActivatedAbilityBehavior")

ActivatedAbilitySaveBehavior.summary = 'Draw Steel Save'
ActivatedAbilitySaveBehavior.conditionsMode = 'all'
ActivatedAbilitySaveBehavior.rollMode = 'roll' --roll or purge with no roll

ActivatedAbility.RegisterType
{
    id = 'draw_steel_save',
    text = 'Draw Steel Save',
    createBehavior = function()
        return ActivatedAbilitySaveBehavior.new{
        }
    end
}

function ActivatedAbilitySaveBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Save"
end

-- Build the list of conditions/effects a target can save against.
-- Each entry: { type = "condition"|"ongoingEffect", id = <conditionid or effectTypeid>,
--               instanceId = <ongoing effect instance id>, name = <display name>,
--               duration = <duration string or nil> }
function ActivatedAbilitySaveBehavior:GetSaveItems(targetCreature)
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
    local ongoingEffectsTable = dmhub.GetTable(CharacterOngoingEffect.tableName) or {}
    local items = {}

    for conditionid, entry in pairs(targetCreature:try_get("inflictedConditions", {})) do
        local conditionInfo = conditionsTable[conditionid]
        if conditionInfo ~= nil and ((entry.duration ~= nil and entry.duration ~= "eoe") or (self:try_get("includeProne") and string.lower(conditionInfo.name) == "prone")) then
            items[#items+1] = {
                type = "condition",
                id = conditionid,
                name = conditionInfo.name,
                duration = entry.duration,
            }
        end
    end

    for _, effectInstance in ipairs(targetCreature:ActiveOngoingEffects()) do
        if effectInstance.removeOnSave then
            local ongoingEffectEntry = ongoingEffectsTable[effectInstance.ongoingEffectid]
            if ongoingEffectEntry ~= nil then
                items[#items+1] = {
                    type = "ongoingEffect",
                    id = effectInstance.ongoingEffectid,
                    instanceId = effectInstance.id,
                    name = ongoingEffectEntry.name,
                }
            end
        end
    end

    return items
end

-- Determine the save roll formula for a given save item and creature.
-- Handles the Coward complication (roll 2d10kl1 for Frightened saves).
function ActivatedAbilitySaveBehavior:GetSaveRollFormula(targetCreature, item)
    local rollStr = "1d10 + Save Bonus"
    if item.type == "condition" and item.name == "Frightened" then
        local complications = targetCreature:Complications()
        for _, complication in ipairs(complications) do
            if complication.name == "Coward" then
                rollStr = "2d10kl1 + Save Bonus"
                break
            end
        end
    end
    return rollStr
end

-- Purge a condition or ongoing effect from a target without rolling.
function ActivatedAbilitySaveBehavior:PurgeSaveItem(targetToken, item)
    if item.type == "condition" then
        targetToken:ModifyProperties{
            description = "Purge condition",
            execute = function()
                targetToken.properties:InflictCondition(item.id, { purge = true })
            end,
        }
    else
        targetToken:ModifyProperties{
            description = "Purge ongoing effect",
            execute = function()
                targetToken.properties:RemoveOngoingEffect(item.id)
            end,
        }
    end
end

-- Roll a save for a single item using the timeline roll dialog.
-- Returns true if the save was rolled (not canceled).
function ActivatedAbilitySaveBehavior:RollSaveInTimeline(ability, casterToken, targetToken, item, options)
    local targetCreature = targetToken.properties

    local rollFormula = self:GetSaveRollFormula(targetCreature, item)
    local rollStr = dmhub.EvalGoblinScript(rollFormula, targetCreature:LookupSymbol(options.symbols or {}), string.format("Save vs %s", item.name))

    local rollCanceled = false
    local rollComplete = false

    local dialog
    local existingEmbedded = CharacterPanel.FindEmbeddedRollDialog()
    if existingEmbedded ~= nil then
        dialog = existingEmbedded
    else
        local displayed = CharacterPanel.DisplayAbility(casterToken, ability, options.symbols, {lock = true})
        if displayed then
            options.OnFinishCastHandlers = options.OnFinishCastHandlers or {}
            options.OnFinishCastHandlers[#options.OnFinishCastHandlers+1] = function()
                CharacterPanel.HideAbility(ability)
            end
        end

        local embeddedDialog = CharacterPanel.EmbedDialogInAbility()
        if embeddedDialog ~= nil then
            dialog = embeddedDialog
            for j = 1, 4 do
                coroutine.yield(0.01)
            end
        else
            dialog = GameHud.instance.rollDialog
        end
    end

    dialog.data.ShowDialog{
        title = string.format("Saving Throw vs %s", item.name),
        description = string.format("Saving Throw vs %s", item.name),
        roll = rollStr,
        creature = targetCreature,
        skipDeterministic = true,
        type = "save",
        cancelRoll = function()
            rollCanceled = true
        end,
        completeRoll = function(rollInfo)
            rollComplete = true

            local saveEnds = ExecuteGoblinScript("Save Ends", targetCreature:LookupSymbol(options.symbols or {}), 6, "Save Ends threshold")
            if rollInfo.total >= saveEnds then
                self:PurgeSaveItem(targetToken, item)
            end

            -- Fire custom triggers matching the standard save ability behavior.
            targetCreature:DispatchEvent("custom", {
                triggername = "madesave",
                triggervalue = rollInfo.total,
            })
            targetCreature:DispatchEvent("custom", {
                triggername = "madesave" .. item.name,
                triggervalue = rollInfo.total,
            })
        end,
    }

    while not rollComplete do
        if rollCanceled then
            return false
        end
        coroutine.yield(0.1)
    end

    return true
end

function ActivatedAbilitySaveBehavior:Cast(ability, casterToken, targets, options)
    for _, target in ipairs(targets) do
        if target.token == nil then
            goto continue_target
        end

        local targetCreature = target.token.properties
        local allItems = self:GetSaveItems(targetCreature)

        local saveItems = {}

        if self.conditionsMode == "one" then
            -- Let user choose which condition to save against.
            local conditionChoices = {}
            local chosenIndex = nil

            for i, item in ipairs(allItems) do
                conditionChoices[#conditionChoices+1] = {
                    text = item.name,
                    click = function()
                        chosenIndex = i
                    end,
                }
            end

            if #conditionChoices > 0 then
                local dialog = GameHud.instance:ModalChoice{
                    title = "Choose Condition",
                    options = conditionChoices,
                }

                while chosenIndex == nil and dialog ~= nil and dialog.valid do
                    coroutine.yield()
                end

                if chosenIndex ~= nil then
                    saveItems[1] = allItems[chosenIndex]
                end
            end
        else
            saveItems = allItems
        end

        for _, item in ipairs(saveItems) do
            -- End-of-turn conditions are auto-purged without a roll.
            if item.type == "condition" and item.duration == "eot" then
                self:PurgeSaveItem(target.token, item)
            elseif self.rollMode == "purge" then
                self:PurgeSaveItem(target.token, item)
            else
                local rolled = self:RollSaveInTimeline(ability, casterToken, target.token, item, options)
                if not rolled then
                    return
                end
            end

            ability:CommitToPaying(casterToken, options)
        end

        ::continue_target::
    end
end

function ActivatedAbilitySaveBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Conditions:",
        },

        gui.Dropdown{
            classes = "formDropdown",
            halign = "left",
            idChosen = self.conditionsMode,
            options = {
                { id = "all", text = "All Conditions" },
                { id = "one", text = "One Chosen Condition" },
            },
            change = function(element)
                self.conditionsMode = element.idChosen
                --parentPanel:FireEvent("refreshBehavior")
            end,

        },
    }

    --do prone.
    result[#result+1] = gui.Check{
        text = "Include Prone",
        value = self:try_get("includeProne", false),
        change = function(element)
            self.includeProne = element.value
        end,
    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Roll Mode:",
        },

        gui.Dropdown{
            classes = "formDropdown",
            halign = "left",
            idChosen = self.rollMode,
            options = {
                { id = "roll", text = "Roll" },
                { id = "purge", text = "Remove Without Roll" },
            },
            change = function(element)
                self.rollMode = element.idChosen
                --parentPanel:FireEvent("refreshBehavior")
            end,

        },
    }

    return result
end