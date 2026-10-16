local mod = dmhub.GetModLoading()

--- @class ActivatedAbilitySaveBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilitySaveBehavior
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
--               bondid = <ongoing effect instance bond id or false>,
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
                    bondid = effectInstance.bondid,
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

-- After a passed save against a bonded ongoing effect whose definition has
-- bondSaveEndsAll set (e.g. Net Trap: "any creature who makes their save ends
-- that effect for all targets"), remove the same bond from every other creature.
-- item.bondid is captured by GetSaveItems, since the saver's own instance is
-- already gone by the time this runs.
function ActivatedAbilitySaveBehavior:EndBondedSaveItem(targetToken, item)
    if item.type ~= "ongoingEffect" or not item.bondid then
        return
    end

    local ongoingEffect = (dmhub.GetTable(CharacterOngoingEffect.tableName) or {})[item.id]
    if ongoingEffect == nil or ongoingEffect.casterTracking ~= "bond" or not ongoingEffect:try_get("bondSaveEndsAll", false) then
        return
    end

    for _, tok in ipairs(dmhub.allTokens) do
        if tok.charid ~= targetToken.charid and tok.properties:HasBondForOngoingEffect(item.id, item.bondid) then
            tok:ModifyProperties{
                description = string.format("%s ends for all bonded creatures", item.name),
                execute = function()
                    local kept = {}
                    for _, inst in ipairs(tok.properties:try_get("ongoingEffects", {})) do
                        if inst.ongoingEffectid ~= item.id or inst.bondid ~= item.bondid then
                            kept[#kept+1] = inst
                        end
                    end
                    tok.properties.ongoingEffects = kept
                end,
            }
        end
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
                aiActivityId = "end-turn-save",
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

-- One line per thing changing this save, for the roll dialog: bonuses to the
-- roll (Save Bonus, Save Bonus vs <name>), a changed success threshold (Save
-- Ends), and the Coward complication's keep-lowest roll.
function ActivatedAbilitySaveBehavior:DescribeSaveModifiers(targetCreature, item, rollFormula)
    local lines = {}

    local function describe(attrName)
        local entries = nil
        pcall(function()
            entries = targetCreature:DescribeModificationsToNamedCustomAttribute(attrName)
        end)
        return entries or {}
    end

    for _, e in ipairs(describe("Save Bonus")) do
        lines[#lines+1] = string.format("%s to saves: %s", tostring(e.value), tostring(e.key))
    end
    for _, e in ipairs(describe("Save Bonus vs " .. item.name)) do
        lines[#lines+1] = string.format("%s vs %s: %s", tostring(e.value), item.name, tostring(e.key))
    end
    for _, e in ipairs(describe("Save Ends")) do
        lines[#lines+1] = string.format("Save on %s+: %s", tostring(e.current), tostring(e.key))
    end
    if string.find(rollFormula, "2d10kl1", 1, true) ~= nil then
        lines[#lines+1] = "Coward: roll 2d10 and keep the lowest"
    end

    return lines
end

--"a-b" for a range of totals, a single number when a == b, nil when empty.
local function SaveRangeText(a, b)
    if a > b then
        return nil
    end
    if a == b then
        return tostring(a)
    end
    return string.format("%d-%d", a, b)
end

-- The roll dialog's Results panel for a save: a Fail row and a Save row with
-- the totals that land on each, highlighted live as the dice tumble and
-- settled once they land, a verdict line, and the modifiers in play.
-- args: item, threshold (Save Ends), rollStr (evaluated roll), modifiers
-- (lines from DescribeSaveModifiers), saveState (shared with the Hero Token
-- rule; saveState.forced = the save was bought with a Hero Token).
function ActivatedAbilitySaveBehavior.SaveResultsPopulateCustom(args)
    return function(parentPanel)
        local threshold = args.threshold

        --The totals the roll can reach. RollMinValue ignores keep-lowest, so a
        --Coward's 2d10kl1 is measured as the single d10 it behaves like.
        local plainRoll = string.gsub(args.rollStr, "(%d+)d(%d+)k[lh]%d+", "1d%2")
        local lo = dmhub.RollMinValue(plainRoll) or 1
        local hi = dmhub.RollMaxValue(plainRoll) or 10

        local failRange = SaveRangeText(lo, math.min(hi, threshold - 1)) or "-"
        local saveRange = SaveRangeText(math.max(lo, threshold), hi) or "-"

        local function OutcomeRow(isSave)
            local rowClass = cond(isSave, "saveRowSuccess", "saveRowFail")
            return gui.Panel{
                classes = {"saveRow", rowClass},
                bgimage = true,
                width = "100%",
                height = "auto",
                flow = "horizontal",
                vpad = 4,
                borderBox = true,
                saveResult = function(element, passed, final)
                    element:SetClassTree("highlight", passed == isSave)
                    element:SetClassTree("preview", not final)
                end,
                gui.Label{
                    classes = {rowClass},
                    text = cond(isSave, saveRange, failRange),
                    width = "22%",
                    height = "auto",
                    fontSize = 20,
                    bold = true,
                    textAlignment = "center",
                    valign = "center",
                },
                gui.Label{
                    classes = {rowClass},
                    text = string.format(cond(isSave, "<b>Save</b>\n<size=13>%s ends.</size>", "<b>Fail</b>\n<size=13>%s continues.</size>"), args.item.name),
                    width = "78%",
                    height = "auto",
                    fontSize = 16,
                    valign = "center",
                },
            }
        end

        local verdict = gui.Label{
            classes = {"saveVerdict", "collapsed"},
            width = "100%",
            height = "auto",
            textAlignment = "center",
            fontSize = 20,
            bold = true,
            vmargin = 4,
            saveResult = function(element, passed, final)
                element:SetClass("collapsed", not final)
                element:SetClass("passed", passed)
                if args.saveState.forced then
                    element.text = "SAVED with a Hero Token!"
                elseif passed then
                    element.text = "SAVED!"
                else
                    element.text = "FAILED"
                end
            end,
        }

        local modifierLabels = {}
        for _, line in ipairs(args.modifiers or {}) do
            modifierLabels[#modifierLabels+1] = gui.Label{
                classes = {"saveModifier"},
                text = line,
                width = "100%",
                height = "auto",
                fontSize = 13,
                hmargin = 6,
            }
        end

        local tbl
        tbl = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                { selectors = {"saveRow"}, bgcolor = "@bg" },
                { selectors = {"saveRow", "highlight", "saveRowFail"}, bgcolor = "@danger" },
                { selectors = {"saveRow", "highlight", "saveRowSuccess"}, bgcolor = "@success" },
                --While the dice are still tumbling the highlight is only a preview.
                { selectors = {"saveRow", "highlight", "preview"}, opacity = 0.55 },
                { selectors = {"label", "highlight", "saveRowFail"}, color = "#ffffff" },
                { selectors = {"label", "highlight", "saveRowSuccess"}, color = "#000000" },
                { selectors = {"saveVerdict"}, color = "@danger" },
                { selectors = {"saveVerdict", "passed"}, color = "@success" },
                { selectors = {"saveModifier"}, color = "@fgMuted" },
            },

            data = {
                faces = {},
                numDice = 0,
                mod = nil,
                endTime = nil,
                final = false,
                rollInfo = nil,
            },

            --Re-rolls fire this again. The non-dice part of the total is taken
            --from the first roll only: a re-roll's rollInfo.total is stale.
            beginRoll = function(element, rollInfo, rollid)
                local d = element.data
                d.faces = {}
                d.numDice = 0
                d.endTime = nil
                d.final = false
                d.rollInfo = rollInfo
                local mod = rollInfo.total
                for _, roll in ipairs(rollInfo.rolls) do
                    mod = mod - roll.result
                    local events = chat.DiceEvents(roll.guid)
                    if events ~= nil then
                        events:Listen(element)
                        d.numDice = d.numDice + 1
                    end
                end
                if d.mod == nil then
                    d.mod = mod
                end
                element:FireEventTree("saveResult", false, false)
                element.thinkTime = 0.1
            end,

            diceface = function(element, diceguid, num, timeRemaining)
                local d = element.data
                if d.final then
                    return
                end
                d.faces[diceguid] = num
                local endTime = dmhub.Time() + timeRemaining
                if d.endTime == nil or endTime > d.endTime then
                    d.endTime = endTime
                end
                local total = d.mod or 0
                for _, value in pairs(d.faces) do
                    total = total + value
                end
                element:FireEventTree("saveResult", total >= threshold, false)
            end,

            --Settle once the dice have stopped; a roll with no dice to watch
            --settles as soon as the dialog reports it finished.
            think = function(element)
                local d = element.data
                if d.final or d.rollInfo == nil then
                    element.thinkTime = nil
                    return
                end
                local settled = (d.endTime ~= nil and dmhub.Time() > d.endTime)
                    or (d.numDice == 0 and element:HasClass("finishedRolling"))
                if not settled then
                    return
                end
                d.final = true
                element.thinkTime = nil
                local total = d.rollInfo.total or 0
                if d.numDice > 0 then
                    total = d.mod or 0
                    for _, value in pairs(d.faces) do
                        total = total + value
                    end
                end
                element:FireEventTree("saveResult", total >= threshold, true)
            end,

            OutcomeRow(false),
            OutcomeRow(true),
            verdict,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                children = modifierLabels,
            },
        }

        parentPanel.children = {tbl}
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

    --Worked out once, so the Results panel and the outcome agree.
    local saveEnds = ExecuteGoblinScript("Save Ends", targetCreature:LookupSymbol(options.symbols or {}), 6, "Save Ends threshold")

    --forced: a hero spent a Hero Token to succeed instead (see below).
    local saveState = { forced = false }

    --A hero who fails may spend a Hero Token to succeed instead. The rule takes
    --over the Re-roll button only while the save on screen is a failure.
    local isHero = targetCreature:IsHero()
    if not isHero then
        pcall(function() isHero = targetCreature:IsCompanion() end)
    end
    local rerollRule = nil
    if isHero then
        rerollRule = CharacterResource.HeroTokenSaveSucceedRule{
            IsFailed = function(state)
                return state.finished and (not saveState.forced) and state.total ~= nil and state.total < saveEnds
            end,
            Succeed = function(state)
                saveState.forced = true
                state.accept()
            end,
        }
    end

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
        rerollRule = rerollRule,
        PopulateCustom = ActivatedAbilitySaveBehavior.SaveResultsPopulateCustom{
            item = item,
            threshold = saveEnds,
            rollStr = rollStr,
            modifiers = self:DescribeSaveModifiers(targetCreature, item, rollFormula),
            saveState = saveState,
        },
        cancelRoll = function()
            rollCanceled = true
        end,
        completeRoll = function(rollInfo)
            rollComplete = true

            local passed = saveState.forced or rollInfo.total >= saveEnds
            if passed then
                self:PurgeSaveItem(targetToken, item)
                self:EndBondedSaveItem(targetToken, item)
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
        --If the roll dialog is destroyed while we wait here (another cast can
        --tear it down), neither callback ever fires and this loop would spin
        --forever, quietly breaking every later triggered ability. Treat it as
        --a canceled roll instead. (report NQMSECG3)
        if dialog == nil or (not dialog.valid) or dialog.data == nil then
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
                ---@cast element Dropdown
                self.conditionsMode = element.idChosen --[[@as string]]
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
                ---@cast element Dropdown
                self.durationScope = element.idChosen --[[@as string]]
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
                ---@cast element Dropdown
                self.rollMode = element.idChosen --[[@as string]]
                --parentPanel:FireEvent("refreshBehavior")
            end,

        },
    }

    return result
end

--- @class ActivatedAbilitySaveEndsToEotChatMessage: GameType
--- @field new fun(o?: table): ActivatedAbilitySaveEndsToEotChatMessage
--- Action log card for ActivatedAbilitySaveEndsToEotBehavior: names the
--- ability (e.g. Otherworldly Grace) and the effect that now ends at end of turn.
ActivatedAbilitySaveEndsToEotChatMessage = RegisterGameType("ActivatedAbilitySaveEndsToEotChatMessage")
ActivatedAbilitySaveEndsToEotChatMessage.casterid = ""
ActivatedAbilitySaveEndsToEotChatMessage.abilityName = ""
ActivatedAbilitySaveEndsToEotChatMessage.effectName = ""

function ActivatedAbilitySaveEndsToEotChatMessage:Render(message)
    local token = dmhub.GetCharacterById(self.casterid)
    if token == nil or not token.valid then
        return gui.Panel{ width = 0, height = 0 }
    end

    return gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        refreshMessage = function(element, message)
        end,
        CreateActionLogCard{
            token = token,
            content = {
                gui.Label{
                    classes = {"action-log-detail", "sizeXs", "fg"},
                    text = self.abilityName,
                },
                gui.Label{
                    classes = {"action-log-subtext", "sizeXxs", "fgMuted"},
                    text = string.format("%s: changed from Save Ends to End of Turn", self.effectName),
                },
            },
        },
    }
end

--- @class ActivatedAbilitySaveEndsToEotBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilitySaveEndsToEotBehavior
--- @field allowMultiple boolean
--- Changes one save-ends condition or ongoing effect on each target so it ends
--- at the end of the target's turn instead (High/Wode Elf Otherworldly Grace).
--- The duration is changed in place, so caster, riders and stacks are kept and
--- no "condition applied" triggers or immunities fire a second time.
ActivatedAbilitySaveEndsToEotBehavior = RegisterGameType("ActivatedAbilitySaveEndsToEotBehavior", "ActivatedAbilityBehavior")
ActivatedAbilitySaveEndsToEotBehavior.summary = 'Save Ends To End Of Turn'
--When true the player may pick several effects at once (Ordinator's Otherworldly Blessing).
ActivatedAbilitySaveEndsToEotBehavior.allowMultiple = false

ActivatedAbility.RegisterType
{
    id = 'save_ends_to_eot',
    text = 'Save Ends To End Of Turn',
    createBehavior = function()
        return ActivatedAbilitySaveEndsToEotBehavior.new{
        }
    end
}

function ActivatedAbilitySaveEndsToEotBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Save ends effect ends at end of turn"
end

--- Lists the target's save-ends items in the same shape GetSaveItems uses.
--- @param targetCreature creature
--- @return table[]
function ActivatedAbilitySaveEndsToEotBehavior.GetSaveEndsItems(targetCreature)
    local items = {}
    for _, item in ipairs(ActivatedAbilitySaveBehavior.new{durationScope = "save"}:GetSaveItems(targetCreature)) do
        if item.type == "ongoingEffect" or item.duration == "save" then
            items[#items+1] = item
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

--- Small modal listing the save-ends items. Returns the chosen items, or nil if canceled.
--- With allowMultiple the buttons toggle and a Confirm button commits the selection.
local function ChooseSaveEndsItems(title, targetToken, items, allowMultiple)
    local chosen = nil
    local finished = false
    local selected = {}

    local confirmButton = nil
    if allowMultiple then
        confirmButton = gui.Button{
            classes = {"sizeM", "disabled"},
            halign = "center",
            rmargin = 8,
            text = "Confirm",
            click = function(element)
                if element:HasClass("disabled") then
                    return
                end
                chosen = {}
                for _, item in ipairs(items) do
                    if selected[item] then
                        chosen[#chosen+1] = item
                    end
                end
                finished = true
                gui.CloseModal()
            end,
        }
    end

    local buttons = {}
    for _, item in ipairs(items) do
        buttons[#buttons+1] = gui.Button{
            classes = {"sizeL"},
            width = "100%",
            halign = "center",
            vmargin = 3,
            text = item.name,
            click = function(element)
                if not allowMultiple then
                    chosen = {item}
                    finished = true
                    gui.CloseModal()
                    return
                end
                selected[item] = (not selected[item]) or nil
                element:SetClass("selected", selected[item] == true)
                confirmButton:SetClass("disabled", next(selected) == nil)
            end,
        }
    end

    local prompt = cond(allowMultiple,
        "Choose any number of save ends effects on %s. They will end at the end of this turn instead.",
        "Choose a save ends effect on %s. It will end at the end of this turn instead.")

    gui.ShowModal(gui.Panel{
        classes = {"framedPanel"},
        --Modals sit outside the HUD's style cascade, so pull the theme in here.
        styles = ThemeEngine.GetStyles(),
        width = 420,
        height = "auto",
        pad = 16,
        borderBox = true,
        flow = "vertical",
        destroy = function()
            finished = true
        end,

        gui.Label{
            classes = {"dialogTitle"},
            width = "100%",
            height = "auto",
            text = title,
        },
        gui.Label{
            classes = {"sizeS"},
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 8,
            text = string.format(prompt, targetToken.name or "this creature"),
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            children = buttons,
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            tmargin = 10,
            confirmButton,
            gui.Button{
                classes = {"sizeM"},
                halign = "center",
                text = "Cancel",
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    finished = true
                    gui.CloseModal()
                end,
            },
        },
    })

    while not finished do
        coroutine.yield(0.1)
    end

    return chosen
end

--- Flips one save-ends item to end-of-turn in place. Call inside ModifyProperties.
local function ConvertItemToEot(props, item)
    if item.type == "condition" then
        local entry = props:try_get("inflictedConditions", {})[item.id]
        if entry ~= nil then
            --"eot" conditions are expired by the End Turn Save rule at this turn's end.
            entry.duration = "eot"
        end
    else
        for _, effectInstance in ipairs(props:try_get("ongoingEffects", {})) do
            if effectInstance.id == item.instanceId then
                --removeAtNextTurnEnd=true expires at the next EndTurn of this
                --creature, which is the end of the turn this runs at the start of.
                effectInstance.removeOnSave = false
                effectInstance.removeAtNextTurnEnd = true
            end
        end
    end
end

function ActivatedAbilitySaveEndsToEotBehavior:Cast(ability, casterToken, targets, options)
    for _, target in ipairs(targets) do
        local targetToken = target.token
        if targetToken ~= nil and targetToken.valid then
            local items = ActivatedAbilitySaveEndsToEotBehavior.GetSaveEndsItems(targetToken.properties)

            local chosen = items
            if #items > 1 then
                local picked = ChooseSaveEndsItems(ability.name, targetToken, items, self.allowMultiple)
                if picked == nil then
                    --Declining the menu cancels the whole cast, so nothing is spent.
                    options.abort = true
                    options.stopProcessing = true
                    return
                end
                chosen = picked
            end

            if #chosen > 0 then
                ability:CommitToPaying(casterToken, options)

                local names = {}
                for _, item in ipairs(chosen) do
                    names[#names+1] = item.name
                end
                local effectNames = table.concat(names, ", ")

                targetToken:ModifyProperties{
                    description = string.format("%s: %s ends at end of turn", ability.name, effectNames),
                    execute = function()
                        for _, item in ipairs(chosen) do
                            ConvertItemToEot(targetToken.properties, item)
                        end
                    end,
                }

                chat.SendCustom(ActivatedAbilitySaveEndsToEotChatMessage.new{
                    casterid = ActivatedAbility.GetLogActorId(targetToken, options),
                    abilityName = ability.name,
                    effectName = effectNames,
                })
            end
        end
    end
end

function ActivatedAbilitySaveEndsToEotBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Check{
        text = "Choose Any Number",
        value = self.allowMultiple,
        change = function(element)
            self.allowMultiple = element.value
        end,
    }

    return result
end