local mod = dmhub.GetModLoading()

-- Trigger symbol provider for GoblinScript condition evaluation.
local g_triggerLookupSymbols = {
    datatype = function(t)
        return "trigger"
    end,

    debuginfo = function(t)
        return string.format("trigger: %s", t._name or "")
    end,

    name = function(t)
        return t._name or ""
    end,

    text = function(t)
        return t._text or ""
    end,

    rules = function(t)
        return t._rules or ""
    end,

    free = function(t)
        return t._free and 1 or 0
    end,
}

local g_triggerHelpSymbols = {
    {
        name = "Name",
        type = "text",
        desc = "The name of the trigger.",
    },
    {
        name = "Text",
        type = "text",
        desc = "The display text of the trigger (may include cost).",
    },
    {
        name = "Rules",
        type = "text",
        desc = "The rules text of the trigger.",
    },
    {
        name = "Free",
        type = "boolean",
        desc = "Whether the trigger is a free triggered action.",
    },
}

--- Creates a symbol-lookup object for an ActiveTrigger so it can be used in GoblinScript.
--- @param triggerInfo ActiveTrigger
--- @return table
local function MakeTriggerSymbolObject(triggerInfo)
    return {
        lookupSymbols = g_triggerLookupSymbols,
        _name = triggerInfo:GetText(),
        _text = triggerInfo.text or "",
        _rules = triggerInfo:GetRulesText(),
        _free = triggerInfo:IsFreeTriggeredAbility(),
    }
end



--Register new trigger modifier types
local triggerModifierOptionsById = {}
local triggerModifierOptions = {}

--- @class TriggerModifierOption
--- @field id string Unique identifier for this param type.
--- @field text string Display name shown in the dropdown.
--- @field init fun(entry: table)|nil Called when a new entry of this type is added.
--- @field createEditor fun(modifier: CharacterModifier, entry: table, index: number, Refresh: fun()): Panel[] Returns editor panels for this entry.
--- @field fillTriggerModes fun(modifier: CharacterModifier, entry: table, triggerInfo: ActiveTrigger, creature: creature, casterSymbols: function)|nil Called to inject modes into a trigger.

--- @param options TriggerModifierOption
function CharacterModifier.RegisterTriggerModifier(options)
    triggerModifierOptionsById[options.id] = options

    if options.index == nil then
        options.index = #triggerModifierOptions + 1
    end

    triggerModifierOptions[options.index] = options
end

-- Placeholder entry for the dropdown.
CharacterModifier.RegisterTriggerModifier{
    id = "none",
    text = "Add Modification...",
}


local g_modeVariations = {}
local g_modeCostDeltas = {}
local g_modeActionOverrides = {}
local g_injectedTriggerIds = {}


CharacterModifier.RegisterTriggerModifier{
    id = "mode",
    text = "Add Mode",

    init = function(entry)
        entry.text = "New Mode"
        entry.rules = ""
        entry.condition = ""
        entry.hasAbility = false
    end,

    createEditor = function(modifier, entry, index, Refresh)
        local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Text:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 60,
                text = entry.text or "",
                change = function(element)
                    entry.text = element.text
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Rules:",
            },
            gui.Input{
                classes = {"formInput"},
                multiline = true,
                fontSize = 14,
                textAlignment = "topleft",
                width = 300,
                height = "auto",
                minHeight = 28,
                characterLimit = 1000,
                text = entry.rules or "",
                change = function(element)
                    entry.rules = element.text
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Mode Condition:",
            },
            gui.GoblinScriptInput{
                value = entry.condition or "",
                change = function(element)
                    entry.condition = element.value
                    Refresh()
                end,
                documentation = {
                    domains = modifier:Domains(),
                    help = "This GoblinScript determines whether this mode is available. Leave blank for always available.",
                    output = "boolean",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature who owns this trigger.",
                },
            },
        }

        -- Variation ability support (like ActivatedAbilityEditor variations).
        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            gui.Check{
                text = "Has Ability",
                minWidth = 130,
                width = 130,
                value = entry.hasAbility or false,
                change = function(element)
                    entry.hasAbility = element.value
                    element.parent.children[2]:SetClass("hidden", not entry.hasAbility)
                    Refresh()
                end,
            },

            gui.Button{
                classes = {"formButton", cond(not entry.hasAbility, "hidden")},
                text = "Edit Ability",
                click = function(element)
                    if entry.variation == nil then
                        entry.variation = ActivatedAbility.Create{
                            name = entry.text or "Mode Ability",
                            description = entry.rules or "",
                        }
                    end

                    element.root:AddChild(entry.variation:ShowEditActivatedAbilityDialog{})
                end,
            },
        }

        return children
    end,

    fillTriggerModes = function(modifier, entry, triggerInfo, creature, casterSymbols)
        local formula = entry.condition or ""
        if formula ~= "" then
            local result = ExecuteGoblinScript(formula, casterSymbols, 0, "Modify Trigger mode condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        -- Copy existing modes into a new table so we never mutate the
        -- class-level default ActiveTrigger.modes shared by all triggers.
        local existingModes = triggerInfo.modes or {}
        local modes = {}
        for i, m in ipairs(existingModes) do
            modes[i] = m
        end
        modes[#modes+1] = {
            text = entry.text or "",
            rules = StringInterpolateGoblinScript(entry.rules or "", casterSymbols),
        }
        triggerInfo.modes = modes

        -- Track variation ability for this mode index so the
        -- DispatchAvailableTrigger hook can intercept activation.
        if entry.hasAbility and entry.variation ~= nil then
            local modeIndex = #modes
            g_modeVariations[triggerInfo.id .. "_" .. modeIndex] = entry.variation
        end
    end,
}

CharacterModifier.RegisterTriggerModifier{
    id = "modifycost",
    text = "Modify Cost",

    init = function(entry)
        entry.text = "Reduced Cost"
        entry.rules = ""
        entry.condition = ""
        entry.costDelta = 0
    end,

    createEditor = function(modifier, entry, index, Refresh)
        local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Text:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 60,
                text = entry.text or "",
                change = function(element)
                    entry.text = element.text
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Rules:",
            },
            gui.Input{
                classes = {"formInput"},
                multiline = true,
                fontSize = 14,
                textAlignment = "topleft",
                width = 300,
                height = "auto",
                minHeight = 28,
                characterLimit = 300,
                text = entry.rules or "",
                change = function(element)
                    entry.rules = element.text
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Mode Condition:",
            },
            gui.GoblinScriptInput{
                value = entry.condition or "",
                change = function(element)
                    entry.condition = element.value
                    Refresh()
                end,
                documentation = {
                    domains = modifier:Domains(),
                    help = "This GoblinScript determines whether this cost modification is available. Leave blank for always available.",
                    output = "boolean",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature who owns this trigger.",
                },
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Cost Change:",
            },
            gui.Input{
                classes = {"formInput"},
                width = 80,
                text = tostring(entry.costDelta or 0),
                change = function(element)
                    entry.costDelta = tonumber(element.text) or 0
                    Refresh()
                end,
            },
        }

        return children
    end,

    fillTriggerModes = function(modifier, entry, triggerInfo, creature, casterSymbols)
        local formula = entry.condition or ""
        if formula ~= "" then
            local result = ExecuteGoblinScript(formula, casterSymbols, 0, "Modify Trigger cost condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        -- Copy existing modes into a new table so we never mutate the
        -- class-level default ActiveTrigger.modes shared by all triggers.
        local existingModes = triggerInfo.modes or {}
        local modes = {}
        for i, m in ipairs(existingModes) do
            modes[i] = m
        end

        local costDelta = entry.costDelta or 0
        local costText = ""
        if costDelta ~= 0 then
            local sign = costDelta > 0 and "+" or ""
            costText = string.format(" (%s%d)", sign, costDelta)
        end

        modes[#modes+1] = {
            text = (entry.text or "") .. costText,
            rules = StringInterpolateGoblinScript(entry.rules or "", casterSymbols),
            cost = costDelta,
        }
        triggerInfo.modes = modes

        -- Track cost delta by mode index so the hook can apply it.
        local modeIndex = #modes
        g_modeCostDeltas[triggerInfo.id .. "_" .. modeIndex] = costDelta
    end,
}


CharacterModifier.RegisterTriggerModifier{
    id = "modifyaction",
    text = "Modify Action",

    init = function(entry)
        entry.text = "Free Triggered Action"
        entry.rules = ""
        entry.condition = ""
        entry.actionResourceId = "none"
    end,

    createEditor = function(modifier, entry, index, Refresh)
        local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Text:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 60,
                text = entry.text or "",
                change = function(element)
                    entry.text = element.text
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Rules:",
            },
            gui.Input{
                classes = {"formInput"},
                multiline = true,
                fontSize = 14,
                textAlignment = "topleft",
                width = 300,
                height = "auto",
                minHeight = 28,
                characterLimit = 300,
                text = entry.rules or "",
                change = function(element)
                    entry.rules = element.text
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Mode Condition:",
            },
            gui.GoblinScriptInput{
                value = entry.condition or "",
                change = function(element)
                    entry.condition = element.value
                    Refresh()
                end,
                documentation = {
                    domains = modifier:Domains(),
                    help = "This GoblinScript determines whether this action modification is available. Leave blank for always available.",
                    output = "boolean",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature who owns this trigger.",
                },
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Action:",
            },
            gui.Dropdown{
                classes = "formDropdown",
                idChosen = entry.actionResourceId or "none",
                options = CharacterResource.GetActionOptions(),
                change = function(element)
                    entry.actionResourceId = element.idChosen
                    Refresh()
                end,
            },
        }

        return children
    end,

    fillTriggerModes = function(modifier, entry, triggerInfo, creature, casterSymbols)
        local formula = entry.condition or ""
        if formula ~= "" then
            local result = ExecuteGoblinScript(formula, casterSymbols, 0, "Modify Trigger action condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        -- Copy existing modes.
        local existingModes = triggerInfo.modes or {}
        local modes = {}
        for i, m in ipairs(existingModes) do
            modes[i] = m
        end
        modes[#modes+1] = {
            text = entry.text or "",
            rules = StringInterpolateGoblinScript(entry.rules or "", casterSymbols),
        }
        triggerInfo.modes = modes

        -- Track action resource override by mode index.
        local modeIndex = #modes
        g_modeActionOverrides[triggerInfo.id .. "_" .. modeIndex] = entry.actionResourceId or "none"
    end,
}


CharacterModifier.RegisterType("modifytrigger", "Modify Trigger")

CharacterModifier.TypeInfo.modifytrigger = {
    init = function(modifier)
        modifier.triggerCondition = ""
        modifier.attributes = {}
        modifier.ability = ActivatedAbility.Create{
            abilityModification = true,
        }
    end,

    --- Injects modes from this modifier into a matching ActiveTrigger.
    --- @param modifier CharacterModifier
    --- @param triggerInfo ActiveTrigger
    --- @param creature creature
    --- @param casterSymbols function
    fillTriggerModes = function(modifier, triggerInfo, creature, casterSymbols)
        if not modifier:PassesFilter(creature) then
            return
        end

        -- Evaluate trigger condition if present.
        local condition = modifier:try_get("triggerCondition", "")
        if condition ~= "" then
            local triggerObj = MakeTriggerSymbolObject(triggerInfo)
            local symbols = {
                trigger = GenerateSymbols(triggerObj),
            }
            local result = ExecuteGoblinScript(condition, creature:LookupSymbol(symbols), 0, "Modify Trigger condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        -- Process each registered attribute entry.
        for _, entry in ipairs(modifier:try_get("attributes", {})) do
            local info = triggerModifierOptionsById[entry.id]
            if info ~= nil and info.fillTriggerModes ~= nil then
                info.fillTriggerModes(modifier, entry, triggerInfo, creature, casterSymbols)
            end
        end
    end,

    --- @param modifier CharacterModifier
    --- @param element Panel
    createEditor = function(modifier, element)
        local Refresh
        local firstRefresh = true
        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local children = {}

            -- Trigger condition: which triggers does this modifier apply to.
            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Condition:",
                },
                gui.GoblinScriptInput{
                    value = modifier:try_get("triggerCondition", ""),
                    change = function(element)
                        modifier.triggerCondition = element.value
                        Refresh()
                    end,
                    documentation = {
                        domains = modifier:Domains(),
                        help = "This GoblinScript determines which triggers this modifier applies to. Leave blank to apply to all triggers on this creature.",
                        output = "boolean",
                        examples = {
                            {
                                script = "Trigger.Name = 'Overwatch'",
                                text = "Only applies to triggers named Overwatch.",
                            },
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature who owns this trigger.",
                        symbols = {
                            {
                                name = "Trigger",
                                type = "trigger",
                                desc = "The trigger being dispatched.",
                                symbols = g_triggerHelpSymbols,
                            },
                        },
                    },
                },
            }

            -- Registered attribute entries with per-type editors and delete buttons.
            for i, entry in ipairs(modifier:try_get("attributes", {})) do
                local info = triggerModifierOptionsById[entry.id]
                if info ~= nil then
                    children[#children+1] = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            width = 400,
                            text = info.text,
                            bold = true,
                        },
                        gui.DeleteItemButton{
                            width = 16,
                            height = 16,
                            valign = "center",
                            halign = "right",
                            click = function(element)
                                table.remove(modifier.attributes, i)
                                Refresh()
                            end,
                        },
                    }

                    if info.createEditor ~= nil then
                        local entryPanels = info.createEditor(modifier, entry, i, Refresh)
                        for _, panel in ipairs(entryPanels) do
                            children[#children+1] = panel
                        end
                    end
                end
            end

            -- Dropdown to add a new modification.
            children[#children+1] = gui.Dropdown{
                options = triggerModifierOptions,
                idChosen = "none",
                height = 30,
                width = 260,
                fontSize = 16,
                change = function(element)
                    if element.idChosen == "none" then
                        return
                    end

                    local info = triggerModifierOptionsById[element.idChosen]
                    local entry = { id = element.idChosen }
                    if info ~= nil and info.init ~= nil then
                        info.init(entry)
                    end

                    modifier.attributes[#modifier.attributes + 1] = entry
                    Refresh()
                end,
            }

            -- Behavior editor
            if modifier:try_get("ability") ~= nil then
                children[#children+1] = modifier.ability:BehaviorEditor{ behaviorOnly = true }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Behaviors Mode:",
                    },
                    gui.Dropdown{
                        options = {
                            {
                                id = "after",
                                text = "Place After",
                            },
                            {
                                id = "before",
                                text = "Place Before",
                            },
                            {
                                id = "replace",
                                text = "Replace Matching Behaviors",
                            },
                            {
                                id = "replaceAll",
                                text = "Replace All Behaviors",
                            },
                        },
                        idChosen = modifier:try_get("replaceBehaviors", "after"),
                        change = function(element)
                            modifier.replaceBehaviors = element.idChosen
                        end,
                    },
                }
            end

            element.children = children
        end

        Refresh()
    end,
}

--- Casts a variation ability in place of the original trigger.
--- @param casterCreature creature
--- @param variation ActivatedAbility
--- @param triggerInfo ActiveTrigger
local function CastVariationAbility(casterCreature, variation, triggerInfo)
    local casterToken = dmhub.LookupToken(casterCreature)
    if casterToken == nil then
        return
    end

    -- Build targets from the trigger's target charids.
    local targets = {}
    for _, targetId in ipairs(triggerInfo.targets or {}) do
        local tok = dmhub.GetTokenById(targetId)
        if tok ~= nil and tok.valid then
            targets[#targets+1] = { token = tok, loc = tok.loc }
        end
    end

    -- If no explicit targets, default to self-targeting.
    if #targets == 0 then
        targets[#targets+1] = { token = casterToken, loc = casterToken.loc }
    end

    -- Schedule the cast so it executes in the main thread,
    -- matching how the original trigger executes.
    dmhub.Schedule(0.01, function()
        if not casterToken.valid then
            return
        end

        local options = {
            symbols = {},
        }

        local needCoroutine = variation:CastInstantPortion(casterToken, targets, options)
        if needCoroutine then
            dmhub.CoroutineSynchronous(function()
                variation:Cast(casterToken, targets, {
                    symbols = {},
                    alreadyInCoroutine = true,
                })
            end)
        end
    end)
end

local g_baseDispatchAvailableTrigger = creature.DispatchAvailableTrigger
function creature:DispatchAvailableTrigger(triggerInfo)
    if triggerInfo ~= nil and triggerInfo.powerRollModifier == false then

        -- Check if this is a re-dispatch with a modifier mode activated.
        if type(triggerInfo.triggered) == "number" then
            local modeKey = triggerInfo.id .. "_" .. triggerInfo.triggered

            -- Variation mode: cast a different ability entirely.
            local variation = g_modeVariations[modeKey]
            if variation ~= nil then
                CastVariationAbility(self, variation, triggerInfo)

                -- Dismiss the original trigger so its coroutine exits
                -- without executing the original ability.
                triggerInfo.triggered = false
                triggerInfo.dismissed = true

                g_baseDispatchAvailableTrigger(self, triggerInfo)
                return
            end

            -- Cost modification mode: adjust the heroicResourceCost
            -- then let the normal trigger flow handle it.
            local costDelta = g_modeCostDeltas[modeKey]
            if costDelta ~= nil then
                triggerInfo.heroicResourceCost = math.max(0, (triggerInfo.heroicResourceCost or 0) + costDelta)
            end

            -- Action resource override mode: change the trigger's free flag
            -- based on the chosen action resource.
            local actionOverride = g_modeActionOverrides[modeKey]
            if actionOverride ~= nil then
                if actionOverride == "none" or actionOverride == CharacterResource.freeManeuverResourceId then
                    -- Free action or no action cost.
                    triggerInfo.free = true
                elseif actionOverride == CharacterResource.triggerResourceId then
                    triggerInfo.free = false
                else
                    -- Other action resources (action, maneuver, etc.)
                    -- still not free -- they consume a different resource.
                    triggerInfo.free = false
                end
            end
        end

        -- Initial dispatch: inject modes from modifytrigger modifiers.
        -- Only inject once per trigger ID to avoid duplicates when the
        -- trigger is re-dispatched (e.g. toggling Activate off/on).
        if not triggerInfo.dismissed and not g_injectedTriggerIds[triggerInfo.id] then
            g_injectedTriggerIds[triggerInfo.id] = true
            local casterSymbols = self:LookupSymbol{}
            local mods = self:GetActiveModifiers()
            for _, modContext in ipairs(mods) do
                local typeInfo = CharacterModifier.TypeInfo[modContext.mod.behavior]
                if typeInfo ~= nil and typeInfo.fillTriggerModes ~= nil then
                    typeInfo.fillTriggerModes(modContext.mod, triggerInfo, self, casterSymbols)
                end
            end
        end
        -- Clean up tracking when a trigger is dismissed.
        if triggerInfo.dismissed then
            g_injectedTriggerIds[triggerInfo.id] = nil
            local prefix = triggerInfo.id .. "_"
            for key, _ in pairs(g_modeVariations) do
                if string.sub(key, 1, #prefix) == prefix then
                    g_modeVariations[key] = nil
                end
            end
            for key, _ in pairs(g_modeCostDeltas) do
                if string.sub(key, 1, #prefix) == prefix then
                    g_modeCostDeltas[key] = nil
                end
            end
            for key, _ in pairs(g_modeActionOverrides) do
                if string.sub(key, 1, #prefix) == prefix then
                    g_modeActionOverrides[key] = nil
                end
            end
        end
    end
    g_baseDispatchAvailableTrigger(self, triggerInfo)
end

-- Also clean up when triggers are cleared
local g_baseClearAvailableTrigger = creature.ClearAvailableTrigger
function creature:ClearAvailableTrigger(triggerInfo)
    g_injectedTriggerIds[triggerInfo.id] = nil
    local prefix = triggerInfo.id .. "_"
    for key, _ in pairs(g_modeVariations) do
        if string.sub(key, 1, #prefix) == prefix then
            g_modeVariations[key] = nil
        end
    end
    for key, _ in pairs(g_modeCostDeltas) do
        if string.sub(key, 1, #prefix) == prefix then
            g_modeCostDeltas[key] = nil
        end
    end
    for key, _ in pairs(g_modeActionOverrides) do
        if string.sub(key, 1, #prefix) == prefix then
            g_modeActionOverrides[key] = nil
        end
    end
    g_baseClearAvailableTrigger(self, triggerInfo)
end
