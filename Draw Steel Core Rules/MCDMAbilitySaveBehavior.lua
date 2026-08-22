local mod = dmhub.GetModLoading()

--- @class ActivatedAbilitySaveBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field conditionsMode string Which conditions to attempt to save against: "all" or a specific condition id.
--- @field rollMode string How the save is resolved: "roll" (make a die roll) or "purge" (auto-succeed without rolling).
--- @field durationScope string Which durations this behavior covers: "all", "eot" (end-of-turn expiry only), or "save" (save-ends only).
--- Draw Steel end-of-turn save behavior: rolls to remove conditions from the target creature.
ActivatedAbilitySaveBehavior = RegisterGameType("ActivatedAbilitySaveBehavior", "ActivatedAbilityBehavior")

ActivatedAbilitySaveBehavior.summary = 'Draw Steel Save'
ActivatedAbilitySaveBehavior.conditionsMode = 'all'
ActivatedAbilitySaveBehavior.rollMode = 'roll' --roll or purge with no roll

--Which items this behavior is responsible for. The End Turn Save global rule
--mod splits its two jobs across two triggered abilities: a mandatory one
--scoped to "eot" that silently expires end-of-turn conditions, and a prompted
--(hostile) one scoped to "save" that raises a trigger card for the actual
--saving throw. "all" keeps the original combined behavior and is what the
--player-facing Remove Condition abilities use.
ActivatedAbilitySaveBehavior.durationScope = 'all'

--When set, this behavior does not roll anything. Instead it posts one
--invocation prompt card per in-scope item, each naming its own effect, and the
--save is rolled only when the player accepts a card. Accepting casts
--promptAbility with the effect's name passed through as the "effectname"
--symbol, which narrows that cast to the single item the card was raised for.
ActivatedAbilitySaveBehavior.promptEach = false
ActivatedAbilitySaveBehavior.promptAbility = 'End Turn Saving Throw'

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

    --Apply the duration scope. An "eot" condition is expired outright by Cast
    --with no roll; everything else in this list is a save-ends item that needs
    --one. Splitting the two lets the expiry stay mandatory while the save is
    --raised as a prompt the player resolves in their own time.
    local scope = self:try_get("durationScope", "all")
    if scope ~= "all" then
        local filtered = {}
        for _, item in ipairs(items) do
            local isEot = (item.type == "condition" and item.duration == "eot")
            if (scope == "eot") == isEot then
                filtered[#filtered+1] = item
            end
        end
        items = filtered
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

    -- Per-condition save modifier: a custom attribute named "Save Bonus vs <name>"
    -- (e.g. "Save Bonus vs Frightened") adjusts saves against that one condition or
    -- ongoing effect only. The attribute may not exist for most conditions, and
    -- CalculateNamedCustomAttribute raises on unknown names, so probe under pcall.
    local vsBonus = nil
    pcall(function()
        vsBonus = targetCreature:CalculateNamedCustomAttribute("Save Bonus vs " .. item.name)
    end)
    if type(vsBonus) == "number" and vsBonus ~= 0 then
        if vsBonus > 0 then
            rollStr = string.format("%s + %d", rollStr, vsBonus)
        else
            rollStr = string.format("%s - %d", rollStr, -vsBonus)
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

-- Post one prompt card per save item, so each effect is named on its own card
-- and can be resolved independently, and sweep away cards left from earlier
-- turns whose effect is gone.
--
-- Invocation prompt cards have no watcher coroutine (unlike TriggeredAbility
-- prompts), so nothing else would ever clear a stale one -- and because they
-- are posted hostile they do not age out either. This sweep is what keeps them
-- honest: it runs on every end of turn, drops cards whose effect has since been
-- removed, and skips posting a duplicate for an effect that already has a card
-- waiting.
function ActivatedAbilitySaveBehavior:PromptSaveItems(targetToken, items)
    local abilityName = self:try_get("promptAbility", "End Turn Saving Throw")

    local wanted = {}
    for _, item in ipairs(items) do
        wanted[item.name] = true
    end

    local pending = {}
    local stale = {}
    for guid, trigger in pairs(targetToken.properties:GetAvailableTriggers() or {}) do
        local invocation = trigger.invocation
        if invocation ~= nil and invocation ~= false and invocation:try_get("standardAbility") == abilityName then
            local effectName = invocation:try_get("symbols", {}).effectname
            if type(effectName) == "string" then
                if wanted[effectName] then
                    pending[effectName] = true
                else
                    stale[#stale+1] = guid
                end
            end
        end
    end

    if #stale > 0 then
        targetToken:ModifyProperties{
            description = "Clear stale save prompts",
            undoable = false,
            execute = function()
                for _, guid in ipairs(stale) do
                    targetToken.properties:ClearAvailableTrigger({id = guid})
                end
            end,
        }
    end

    for _, item in ipairs(items) do
        if not pending[item.name] then
            pending[item.name] = true
            AbilityInvocation.PromptStandardAbility{
                token = targetToken,
                standardAbility = abilityName,
                targeting = "self",
                --Hostile so the card waits indefinitely instead of ageing out:
                --the whole point is that the save is taken at the player's
                --leisure, not in the seconds after their turn ends.
                hostile = true,
                prompt = string.format("Saving Throw vs %s", item.name),
                rules = string.format("Roll a saving throw to end **%s**.", item.name),
                activateText = "Roll Save",
                symbols = { effectname = item.name },
            }
        end
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

    --Acquire the embedded roll dialog, queuing behind any other ability roll
    --in progress. The helper installs the cast-aware HideAbility OnFinishCast
    --handler. See CharacterPanel.AcquireAbilityRollDialog.
    local dialog = CharacterPanel.AcquireAbilityRollDialog(casterToken, ability, options.symbols, {lock = true}, options)

    -- The dialog reference can go stale across the init yields inside the
    -- helper: the ability sidebar may be rebuilt or the embedded dialog
    -- destroyed, leaving an invalid panel whose .data is nil. If we no longer
    -- have a usable dialog, bail out (treated as a canceled roll) rather than
    -- indexing nil.
    if dialog == nil or (not dialog.valid) or dialog.data == nil then
        return false
    end

    dialog.data.ShowDialog{
        title = string.format("Saving Throw vs %s", item.name),
        description = string.format("Saving Throw vs %s", item.name),
        roll = rollStr,
        creature = targetCreature,
        skipDeterministic = true,
        type = "save",
        --Keep the dialog up after the dice settle so the roll ends with an
        --Accept Result / Re-roll step, consistent with power rolls.
        showDialogDuringRoll = true,
        amendable = true,
        cancelRoll = function()
            rollCanceled = true
        end,
        completeRoll = function(rollInfo)
            rollComplete = true

            local saveEnds = ExecuteGoblinScript("Save Ends", targetCreature:LookupSymbol(options.symbols or {}), 6, "Save Ends threshold")
            local passed = rollInfo.total >= saveEnds
            if passed then
                self:PurgeSaveItem(targetToken, item)
            elseif item.type == "ongoingEffect" or item.type == "condition" then
                -- Failed save against an ongoing effect OR condition that
                -- did NOT end (it persists). Fire the savefail trigger so
                -- handlers inside the effect's / condition's modifiers[]
                -- can react (e.g. Stoned inflicts corruption damage on each
                -- failed save).
                --
                -- Resolve Caster from the source's casterInfo (ongoing
                -- effect instance OR inflictedConditions entry, both store
                -- the same {tokenid=...} shape when caster tracking is on).
                -- If caster-tracking is not enabled or the original caster
                -- token is gone, fall back to the bearer (targetCreature)
                -- so Caster.X formulas still evaluate to something safe
                -- rather than 0.
                local casterSymbol = targetCreature
                local casterInfo = nil
                if item.type == "ongoingEffect" then
                    for _, inst in ipairs(targetCreature:ActiveOngoingEffects()) do
                        if inst.id == item.instanceId then
                            casterInfo = inst:try_get("casterInfo")
                            break
                        end
                    end
                else
                    -- Conditions: caster tracking (when enabled on the
                    -- CharacterCondition via trackCaster=true) writes a
                    -- casterInfo table onto the per-condition entry inside
                    -- targetCreature.inflictedConditions[<conditionid>].
                    -- See creature:InflictCondition in Creature.lua.
                    local entry = targetCreature:try_get("inflictedConditions", {})[item.id]
                    if entry ~= nil then
                        casterInfo = entry.casterInfo
                    end
                end
                if casterInfo ~= nil and type(casterInfo.tokenid) == "string" then
                    local casterTok = dmhub.GetTokenById(casterInfo.tokenid)
                    if casterTok ~= nil and casterTok.valid and casterTok.properties ~= nil then
                        casterSymbol = casterTok.properties
                    end
                end

                targetCreature:DispatchEvent("savefail", {
                    effectname = item.name,
                    caster = casterSymbol,
                    saveroll = rollInfo.total,
                })
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

        --A cast raised from a per-effect prompt card carries the effect's name
        --as the "effectname" symbol (see PromptSaveItems). Narrow to that one
        --item so accepting a card saves against the effect it named and nothing
        --else. An effect that has since been removed narrows to nothing, which
        --is the correct no-op for a card clicked late.
        local effectName = nil
        if options ~= nil and options.symbols ~= nil then
            effectName = options.symbols.effectname
        end
        if type(effectName) == "string" and effectName ~= "" then
            local narrowed = {}
            for _, item in ipairs(allItems) do
                if item.name == effectName then
                    narrowed[#narrowed+1] = item
                end
            end
            allItems = narrowed
        end

        if self:try_get("promptEach", false) then
            self:PromptSaveItems(target.token, allItems)
            goto continue_target
        end

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

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Durations:",
        },

        gui.Dropdown{
            classes = "formDropdown",
            halign = "left",
            idChosen = self:try_get("durationScope", "all"),
            options = {
                { id = "all", text = "All Durations" },
                { id = "save", text = "Save Ends Only" },
                { id = "eot", text = "End of Turn Only" },
            },
            change = function(element)
                self.durationScope = element.idChosen
            end,
        },
    }

    result[#result+1] = gui.Check{
        text = "Prompt For Each Effect",
        value = self:try_get("promptEach", false),
        change = function(element)
            self.promptEach = element.value
        end,
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