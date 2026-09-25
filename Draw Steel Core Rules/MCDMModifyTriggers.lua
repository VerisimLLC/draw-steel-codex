local mod = dmhub.GetModLoading()

-- Trigger symbol provider for GoblinScript condition evaluation. Each entry is
-- one symbol an author can write after "Trigger." in a formula. The argument is
-- the symbol object MakeTriggerSymbolObject built for the prompt being tested.
local g_triggerLookupSymbols = {
    datatype = function(trigger)
        return "trigger"
    end,

    debuginfo = function(trigger)
        return string.format("trigger: %s", trigger._name or "")
    end,

    name = function(trigger)
        return trigger._name or ""
    end,

    text = function(trigger)
        return trigger._text or ""
    end,

    rules = function(trigger)
        return trigger._rules or ""
    end,

    free = function(trigger)
        return trigger._free and 1 or 0
    end,

    hostile = function(trigger)
        return trigger._hostile and 1 or 0
    end,

    grantsfreestrike = function(trigger)
        return trigger._grantsFreeStrike and 1 or 0
    end,

    grantssignatureability = function(trigger)
        return trigger._grantsSignature and 1 or 0
    end,
}

local g_triggerHelpSymbols = {
    {
        name = "Name",
        type = "string",
        desc = "The name of the trigger.",
    },
    {
        name = "Text",
        type = "string",
        desc = "The display text of the trigger (may include cost).",
    },
    {
        name = "Rules",
        type = "string",
        desc = "The rules text of the trigger.",
    },
    {
        name = "Free",
        type = "boolean",
        desc = "Whether the trigger is a free triggered action.",
    },
    {
        name = "Hostile",
        type = "boolean",
        desc = "Whether the trigger is a hostile trigger (a harmful prompt that never expires and must be manually resolved).",
    },
    {
        name = "Grants Free Strike",
        type = "boolean",
        desc = "Whether taking this triggered action would have the creature make a free strike. Worked out from what the ability actually does, not from its rules text.",
    },
    {
        name = "Grants Signature Ability",
        type = "boolean",
        desc = "Whether taking this triggered action would have the creature use a signature ability. Worked out from what the ability actually does, not from its rules text.",
    },
}

RegisterGoblinScriptTypeInfo("trigger", g_triggerHelpSymbols)


--Answers "would this triggered action make a free strike or use a signature
--ability?" by inspecting what the ability does. The old test searched the
--prompt's rules text for "free strike", which both missed and over-matched.

--How far to follow Invoke Ability chains. Real grants nest two or three deep
--("Ally Makes Signature Strike" -> "Signature Strike" -> the hero's own
--ability); the cap only exists to stop a cyclic chain looping forever.
local STRIKE_SCAN_DEPTH = 5

--- Whether this ability is itself castable in place of a free strike or a
--- signature ability. Same test as the Ability.Usable As Free Strike /
--- Ability.Usable As Signature Ability GoblinScript symbols.
--- @param ability ActivatedAbility
--- @return boolean freestrike, boolean signature
local function AbilityCountsAsStrike(ability)
    local categorization = nil
    pcall(function() categorization = ability.categorization end)

    local freestrike = categorization == "Basic Attack"
    local signature = categorization == "Signature Ability"

    pcall(function()
        freestrike = freestrike or ability:HasProperty("useasstrike")
        signature = signature or ability:HasProperty("useassignature")
    end)

    return freestrike, signature
end

--- Looks up one of the creature's own abilities by name, for an Invoke Ability
--- behavior set to "named".
--- @param creature creature|nil
--- @param name string
--- @return ActivatedAbility|nil
local function FindNamedAbility(creature, name)
    if creature == nil or name == nil or name == "" then
        return nil
    end

    local abilities = nil
    pcall(function() abilities = creature:GetActivatedAbilities{allLoadouts = true} end)

    local nameLower = string.lower(name)
    for _,ability in ipairs(abilities or {}) do
        if string.lower(ability.name or "") == nameLower then
            return ability
        end
    end

    return nil
end

--- An Augmented Ability behavior (the "Free Strike" and "Signature Strike"
--- standard abilities) names no ability: it offers whichever of the caster's
--- own abilities pass its modifier's filter. Run that filter -- the same one
--- SynthesizeAbilities uses -- and classify what passes, without paying for
--- the ability clones synthesis would make.
--- @param behavior ActivatedAbilityAugmentedAbilityBehavior
--- @param ability ActivatedAbility the ability the behavior belongs to
--- @param creature creature|nil
--- @return boolean freestrike, boolean signature
local function AugmentedBehaviorStrikeGrant(behavior, ability, creature)
    if creature == nil then
        return false, false
    end

    local modifier = behavior:try_get("modifier")
    if modifier == nil then
        return false, false
    end

    local typeInfo = CharacterModifier.TypeInfo[modifier.behavior]
    if typeInfo == nil or typeInfo.willModifyAbility == nil then
        return false, false
    end

    local abilities = nil
    pcall(function() abilities = creature:GetActivatedAbilities() end)

    local freestrike, signature = false, false
    for _,candidateAbility in ipairs(abilities or {}) do
        if candidateAbility ~= ability then
            local passesFilter = false
            pcall(function() passesFilter = typeInfo.willModifyAbility(modifier, creature, candidateAbility) end)
            if passesFilter then
                local candidateFreeStrike, candidateSignature = AbilityCountsAsStrike(candidateAbility)
                freestrike = freestrike or candidateFreeStrike
                signature = signature or candidateSignature
                if freestrike and signature then
                    break
                end
            end
        end
    end

    return freestrike, signature
end

--- What kind of strike, if any, casting this ability would have the creature
--- make. Follows Invoke Ability behaviors down to the ability actually cast
--- (a grant like "Ally Makes Free Strike" is a wrapper around the standard
--- Free Strike ability) and runs an Augmented Ability behavior's filter.
--- @param ability ActivatedAbility|nil
--- @param creature creature|nil the creature who would be casting
--- @param depth number|nil recursion budget; omit at the top level
--- @return boolean freestrike, boolean signature
local function AbilityStrikeGrant(ability, creature, depth)
    if ability == nil then
        return false, false
    end

    depth = depth or STRIKE_SCAN_DEPTH
    if depth <= 0 then
        return false, false
    end

    local freestrike, signature = AbilityCountsAsStrike(ability)
    if freestrike and signature then
        return true, true
    end

    local behaviors = nil
    pcall(function() behaviors = ability.behaviors end)

    for _,behavior in ipairs(behaviors or {}) do
        local behaviorFreeStrike, behaviorSignature = false, false

        if behavior.typeName == "ActivatedAbilityInvokeAbilityBehavior" then
            local abilityType = behavior:try_get("abilityType", "standard")
            local inner = nil
            if abilityType == "standard" then
                inner = MCDMUtils.GetStandardAbility(behavior:try_get("standardAbility", ""))
            elseif abilityType == "custom" then
                inner = behavior:try_get("customAbility")
            elseif abilityType == "named" then
                inner = FindNamedAbility(creature, behavior:try_get("namedAbility", ""))
            end
            behaviorFreeStrike, behaviorSignature = AbilityStrikeGrant(inner, creature, depth - 1)
        elseif behavior.typeName == "ActivatedAbilityAugmentedAbilityBehavior" then
            behaviorFreeStrike, behaviorSignature = AugmentedBehaviorStrikeGrant(behavior, ability, creature)
        end

        freestrike = freestrike or behaviorFreeStrike
        signature = signature or behaviorSignature
        if freestrike and signature then
            break
        end
    end

    return freestrike, signature
end

--Answers for prompt cards this file raised itself (opportunity attacks and
--intercepted grants). Those records carry no ability to read the answer off,
--so it is recorded here when the card goes up. Keyed by trigger id.
local g_interposedStrikeGrant = {}

--Per-prompt memo so several modifiers classifying one card share the walk.
--Entries go when the prompt is dismissed or cleared; a prompt that just ages
--out never gets that call, so the whole memo is dropped past the limit.
local g_triggerStrikeGrant = {}
local g_triggerStrikeGrantCount = 0
local STRIKE_MEMO_LIMIT = 512

--- Finds the TriggeredAbility a prompt came from, preferring the persisted
--- guid with a name fallback (the same lookup ActivateOrphanedTrigger uses,
--- so a compendium re-import changing guids does not break classification).
--- @param creature creature
--- @param abilityGuid string|false
--- @param abilityName string|false
--- @return ActivatedAbility|nil
local function FindTriggeredAbilityForPrompt(creature, abilityGuid, abilityName)
    if creature == nil then
        return nil
    end

    local entries = nil
    pcall(function() entries = creature:GetTriggeredAbilities() end)

    local nameMatch = nil
    for _,entry in ipairs(entries or {}) do
        local ability = entry.ability
        if ability ~= nil then
            if abilityGuid ~= false and abilityGuid ~= nil and ability:try_get("guid") == abilityGuid then
                return ability
            end
            if nameMatch == nil and abilityName ~= false and abilityName ~= nil and ability.name == abilityName then
                nameMatch = ability
            end
        end
    end

    return nameMatch
end

--- What kind of strike, if any, the triggered action behind this prompt would
--- let the creature make. Reads the prompt's own record: an invocation card
--- carries the standard ability it will cast, a triggered-ability card carries
--- the guid of the ability on the creature's modifiers.
--- @param triggerInfo ActiveTrigger
--- @param creature creature|nil
--- @return boolean freestrike, boolean signature
local function TriggerStrikeGrant(triggerInfo, creature)
    local interposed = g_interposedStrikeGrant[triggerInfo.id]
    if interposed ~= nil then
        return interposed[1], interposed[2]
    end

    local cached = g_triggerStrikeGrant[triggerInfo.id]
    if cached ~= nil then
        return cached[1], cached[2]
    end

    local freestrike, signature = false, false

    local invocation = triggerInfo.invocation
    if invocation ~= false and invocation ~= nil then
        local abilityType = invocation:try_get("abilityType", "standard")
        local inner = nil
        if abilityType == "standard" then
            inner = MCDMUtils.GetStandardAbility(invocation:try_get("standardAbility", ""))
        elseif abilityType == "named" then
            inner = FindNamedAbility(creature, invocation:try_get("namedAbility", ""))
        end
        freestrike, signature = AbilityStrikeGrant(inner, creature)
    end

    if not (freestrike or signature) then
        local ability = FindTriggeredAbilityForPrompt(creature, triggerInfo.abilityGuid, triggerInfo.abilityName)
        freestrike, signature = AbilityStrikeGrant(ability, creature)
    end

    if g_triggerStrikeGrantCount >= STRIKE_MEMO_LIMIT then
        g_triggerStrikeGrant = {}
        g_triggerStrikeGrantCount = 0
    end

    g_triggerStrikeGrant[triggerInfo.id] = {freestrike, signature}
    g_triggerStrikeGrantCount = g_triggerStrikeGrantCount + 1
    return freestrike, signature
end

--- Creates a symbol-lookup object for an ActiveTrigger so it can be used in GoblinScript.
--- @param triggerInfo ActiveTrigger
--- @param creature creature|nil the creature the trigger belongs to; needed to
---        classify what the triggered action would actually do.
--- @return table
local function MakeTriggerSymbolObject(triggerInfo, creature)
    local freestrike, signature = TriggerStrikeGrant(triggerInfo, creature)
    return {
        lookupSymbols = g_triggerLookupSymbols,
        _name = triggerInfo:GetText(),
        _text = triggerInfo.text or "",
        _rules = triggerInfo:GetRulesText(),
        _free = triggerInfo:IsFreeTriggeredAbility(),
        _hostile = triggerInfo.hostile,
        _grantsFreeStrike = freestrike,
        _grantsSignature = signature,
    }
end


local function ReplaceBehaviorToEnum(mode)
    if mode == false then return "after" end
    if mode == true then return "before" end
    return mode
end


--Register new trigger modifier types
local triggerModifierOptionsById = {}
local triggerModifierOptions = {}

--- @class TriggerModifierOption
--- @field id string Unique identifier for this param type.
--- @field text string Display name shown in the dropdown.
--- @field init fun(entry: table)|nil Called when a new entry of this type is added.
--- @field createEditor fun(modifier: CharacterModifier, entry: table, index: number, Refresh: fun()): Panel[] Returns editor panels for this entry.
--- @field fillTriggerModes fun(modifier: CharacterModifier, entry: table, triggerInfo: ActiveTrigger, creature: creature, casterSymbols: function, index: number)|nil Called to inject modes into a trigger. index is the entry's position in modifier.attributes; pass it to TriggerModeMarker so the mode is only added once.

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


--What each injected mode does, keyed by "<trigger id>_<mode index>". These are
--session-local and rebuilt on every dispatch, so a prompt answered on a
--different client than the one that raised it still resolves correctly.
local g_modeVariations = {}
local g_modeCostDeltas = {}
local g_modeActionOverrides = {}

--- Drops everything remembered about one trigger prompt. Called when the
--- prompt is dismissed or cleared so these tables do not grow all session.
--- @param triggerid string
local function ForgetTriggerTracking(triggerid)
    g_triggerStrikeGrant[triggerid] = nil
    g_interposedStrikeGrant[triggerid] = nil

    local prefix = triggerid .. "_"
    for _,tracking in ipairs({g_modeVariations, g_modeCostDeltas, g_modeActionOverrides}) do
        for key, _ in pairs(tracking) do
            if string.sub(key, 1, #prefix) == prefix then
                tracking[key] = nil
            end
        end
    end
end

--Evaluates an Add Mode entry's Mode Condition the same way TriggeredAbility
--evaluates a modeList entry's, so a mode injected by a Modify Trigger modifier
--behaves like one authored on the ability itself. Only Add Mode offers the
--player a new mode, so only Add Mode carries a Condition Reason; the other
--entry types modify the trigger and just withdraw when their condition fails.
--
--Returns nil when the mode should not be offered at all. Otherwise returns the
--availability fields to merge into the mode: empty when the condition passed,
--or unavailable/conditionReason when it failed but the author gave a reason.
--A failed condition hides the mode, as it always has, unless that Condition
--Reason is filled in: then the mode is offered anyway, greyed out and annotated
--with the reason, and the player may override it.
--- @param entry table The modifier entry carrying condition/conditionReason.
--- @param casterSymbols function
--- @param errorContext string Label used if the GoblinScript errors.
--- @return table|nil
local function EvaluateModeCondition(entry, casterSymbols, errorContext)
    local formula = entry.condition or ""
    if formula == "" then
        return {}
    end

    local result = ExecuteGoblinScript(formula, casterSymbols, 0, errorContext)
    if GoblinScriptTrue(result) then
        return {}
    end

    local reason = trim(entry.conditionReason or "")
    if reason == "" then
        return nil
    end

    return {
        unavailable = true,
        conditionReason = StringInterpolateGoblinScript(reason, casterSymbols),
    }
end

--- A stable id for one entry of one Modify Trigger modifier, used to recognise
--- a mode this entry already added to a prompt.
--- @param modifier CharacterModifier
--- @param index number the entry's position in modifier.attributes
--- @return string
local function TriggerModeMarker(modifier, index)
    return string.format("%s:%d", tostring(modifier:try_get("guid", modifier.behavior)), index)
end

--- Adds a mode to a trigger prompt, or returns the one this entry already
--- added. Prompt records sync between clients, so the same entry gets
--- processed again on whichever client answers the prompt; matching on the
--- marker keeps that from stacking up duplicate modes, while still
--- registering the mode's index in the local side tables below.
--- @param triggerInfo ActiveTrigger
--- @param marker string from TriggerModeMarker
--- @param mode table the mode fields to add
--- @return number the mode's index in triggerInfo.modes
local function AddTriggerMode(triggerInfo, marker, mode)
    local existingModes = triggerInfo.modes or {}
    for i,existingMode in ipairs(existingModes) do
        if existingMode.injectedBy == marker then
            return i
        end
    end

    --Copy before appending: the class-level default ActiveTrigger.modes is
    --shared by every trigger that never set its own.
    local modes = {}
    for i,existingMode in ipairs(existingModes) do
        modes[i] = existingMode
    end

    mode.injectedBy = marker
    modes[#modes+1] = mode
    triggerInfo.modes = modes
    return #modes
end


CharacterModifier.RegisterTriggerModifier{
    id = "mode",
    text = "Add Mode",

    init = function(entry)
        entry.text = "New Mode"
        entry.rules = ""
        entry.condition = ""
        entry.conditionReason = ""
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

        -- Blank -- the default -- keeps the original hide-when-unavailable
        -- behaviour, which is what the placeholder text says.
        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Condition Reason:",
            },
            gui.Input{
                classes = {"formInput"},
                characterLimit = 200,
                placeholderText = "Blank: hide the mode when unavailable",
                text = entry.conditionReason or "",
                change = function(element)
                    entry.conditionReason = element.text
                    Refresh()
                end,
            },
        }

        -- Variation ability support (like ActivatedAbilityEditor variations).
        children[#children+1] = gui.Panel{
            classes = {"formPanel", "formPanel-inline"},
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

    fillTriggerModes = function(modifier, entry, triggerInfo, creature, casterSymbols, index)
        local availability = EvaluateModeCondition(entry, casterSymbols, "Modify Trigger mode condition")
        if availability == nil then
            return
        end

        local modeIndex = AddTriggerMode(triggerInfo, TriggerModeMarker(modifier, index), {
            text = entry.text or "",
            rules = StringInterpolateGoblinScript(entry.rules or "", casterSymbols),
            unavailable = availability.unavailable,
            conditionReason = availability.conditionReason,
        })

        -- Track variation ability for this mode index so the
        -- DispatchAvailableTrigger hook can intercept activation. This runs
        -- for a mode offered greyed out too, which the player can still choose.
        if entry.hasAbility and entry.variation ~= nil then
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

    fillTriggerModes = function(modifier, entry, triggerInfo, creature, casterSymbols, index)
        -- A cost modification is not a mode the author offers, so it has no
        -- Condition Reason: a failing condition simply withdraws it.
        local formula = entry.condition or ""
        if formula ~= "" then
            local result = ExecuteGoblinScript(formula, casterSymbols, 0, "Modify Trigger cost condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        local costDelta = entry.costDelta or 0
        local costText = ""
        if costDelta ~= 0 then
            local sign = costDelta > 0 and "+" or ""
            costText = string.format(" (%s%d)", sign, costDelta)
        end

        local modeIndex = AddTriggerMode(triggerInfo, TriggerModeMarker(modifier, index), {
            text = (entry.text or "") .. costText,
            rules = StringInterpolateGoblinScript(entry.rules or "", casterSymbols),
            cost = costDelta,
        })

        -- Track cost delta by mode index so the hook can apply it.
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
                styles = ThemeEngine.GetStyles(),
                classes = "formDropdown",
                idChosen = entry.actionResourceId or "none",
                options = CharacterResource.GetActionOptions(),
                change = function(element)
                    ---@cast element Dropdown
                    entry.actionResourceId = element.idChosen
                    Refresh()
                end,
            },
        }

        return children
    end,

    fillTriggerModes = function(modifier, entry, triggerInfo, creature, casterSymbols, index)
        -- An action modification is not a mode the author offers, so it has no
        -- Condition Reason: a failing condition simply withdraws it.
        local formula = entry.condition or ""
        if formula ~= "" then
            local result = ExecuteGoblinScript(formula, casterSymbols, 0, "Modify Trigger action condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        local modeIndex = AddTriggerMode(triggerInfo, TriggerModeMarker(modifier, index), {
            text = entry.text or "",
            rules = StringInterpolateGoblinScript(entry.rules or "", casterSymbols),
        })

        -- Track action resource override by mode index.
        g_modeActionOverrides[triggerInfo.id .. "_" .. modeIndex] = entry.actionResourceId or "none"
    end,
}


CharacterModifier.RegisterType("modifytrigger", "Modify Trigger")

CharacterModifier.TypeInfo.modifytrigger = {
    init = function(modifier)
        modifier.triggerCondition = ""
        modifier.interceptStrikes = false
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
            local triggerObj = MakeTriggerSymbolObject(triggerInfo, creature)
            local symbols = {
                trigger = GenerateSymbols(triggerObj),
            }
            local result = ExecuteGoblinScript(condition, creature:LookupSymbol(symbols), 0, "Modify Trigger condition")
            if not GoblinScriptTrue(result) then
                return
            end
        end

        -- Process each registered attribute entry.
        for index, entry in ipairs(modifier:try_get("attributes", {})) do
            local info = triggerModifierOptionsById[entry.id]
            if info ~= nil and info.fillTriggerModes ~= nil then
                info.fillTriggerModes(modifier, entry, triggerInfo, creature, casterSymbols, index)
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

            -- Opt-in for strikes that arrive with no prompt of their own:
            -- opportunity attacks, and strikes another hero grants you. On,
            -- those raise a card so this modifier's modes reach them.
            children[#children+1] = gui.Panel{
                classes = {"formPanel", "formPanel-inline"},
                flow = "horizontal",
                width = "auto",
                height = "auto",
                gui.Check{
                    text = "Intercept Strikes",
                    tooltip = "Also offer these modes when this creature makes a free strike or signature ability that has no trigger prompt of its own -- an opportunity attack, or a strike granted by another hero.",
                    minWidth = 260,
                    width = 260,
                    value = modifier:try_get("interceptStrikes", false),
                    change = function(element)
                        modifier.interceptStrikes = element.value
                        Refresh()
                    end,
                },
            }

            -- Registered attribute entries with per-type editors and delete buttons.
            for i, entry in ipairs(modifier:try_get("attributes", {})) do
                local info = triggerModifierOptionsById[entry.id]
                if info ~= nil then
                    children[#children+1] = gui.Panel{
                        classes = {"formPanel", "formPanel-inline"},
                        gui.Label{
                            classes = {"formLabel"},
                            width = 400,
                            text = info.text,
                            bold = true,
                        },
                        gui.Button{
                            classes = {"deleteButton", "sizeS"},
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
                styles = ThemeEngine.GetStyles(),
                options = triggerModifierOptions,
                idChosen = "none",
                height = 30,
                width = 260,
                fontSize = 16,
                change = function(element)
                    ---@cast element Dropdown
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
                        styles = ThemeEngine.GetStyles(),
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
                            ---@cast element Dropdown
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

        -- Must run BEFORE the mode is resolved below: the g_mode* tables are
        -- session-local, and the client answering a prompt is often not the one
        -- that raised it, so it has to rebuild them before reading them.
        if not triggerInfo.dismissed then
            local casterSymbols = self:LookupSymbol{}
            local mods = self:GetActiveModifiers()
            local seenMods = {}
            for _, modContext in ipairs(mods) do
                if not seenMods[modContext.mod] then
                    seenMods[modContext.mod] = true
                    local typeInfo = CharacterModifier.TypeInfo[modContext.mod.behavior]
                    if typeInfo ~= nil and typeInfo.fillTriggerModes ~= nil then
                        typeInfo.fillTriggerModes(modContext.mod, triggerInfo, self, casterSymbols)
                    end
                end
            end
        end

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

                ForgetTriggerTracking(triggerInfo.id)
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

        if triggerInfo.dismissed then
            ForgetTriggerTracking(triggerInfo.id)
        end
    end
    g_baseDispatchAvailableTrigger(self, triggerInfo)
end

-- Also clean up when triggers are cleared
local g_baseClearAvailableTrigger = creature.ClearAvailableTrigger
function creature:ClearAvailableTrigger(triggerInfo)
    ForgetTriggerTracking(triggerInfo.id)
    g_baseClearAvailableTrigger(self, triggerInfo)
end

-- Hook TriggeredAbility:Trigger to apply behavior replacements from
-- active modifytrigger modifiers before the trigger executes.
local g_baseTriggerAbilityTrigger = TriggeredAbility.Trigger
function TriggeredAbility:Trigger(characterModifier, creature, symbols, auraControllerToken, modContext, argOptions)
    local triggerSelf = self
    if creature ~= nil then
        local mods = creature:GetActiveModifiers()
        for _, modEntry in ipairs(mods) do
            local modifier = modEntry.mod
            if modifier.behavior == "modifytrigger" and modifier:has_key("ability") and #modifier.ability.behaviors > 0 then
                if modifier:PassesFilter(creature) then
                    -- Evaluate trigger condition if present.
                    local shouldApply = true
                    local condition = modifier:try_get("triggerCondition", "")
                    if condition ~= "" then
                        local grantsFreeStrike, grantsSignature = AbilityStrikeGrant(self, creature)
                        local triggerObj = {
                            lookupSymbols = g_triggerLookupSymbols,
                            _name = self.name or "",
                            _text = self.name or "",
                            _rules = self:try_get("description", ""),
                            _free = self:ActionResource() ~= CharacterResource.triggerResourceId,
                            _grantsFreeStrike = grantsFreeStrike,
                            _grantsSignature = grantsSignature,
                        }
                        local symTable = {
                            trigger = GenerateSymbols(triggerObj),
                        }
                        local result = ExecuteGoblinScript(condition, creature:LookupSymbol(symTable), 0, "Modify Trigger behavior condition")
                        if not GoblinScriptTrue(result) then
                            shouldApply = false
                        end
                    end

                    if shouldApply then
                        -- Clone only once so we don't mutate the original.
                        if triggerSelf == self then
                            triggerSelf = self:MakeTemporaryClone()
                        end

                        local replacementMode = ReplaceBehaviorToEnum(modifier:try_get("replaceBehaviors", "after"))

                        -- Collect modifier behaviors into a plain list first,
                        -- since the ability may come from a data table entry.
                        local modBehaviors = {}
                        for i, behavior in ipairs(modifier.ability.behaviors) do
                            modBehaviors[#modBehaviors + 1] = behavior
                        end

                        printf("MODIFY TRIGGER: mode=%s, modifier behaviors=%d, trigger behaviors=%d, trigger=%s", replacementMode, #modBehaviors, #triggerSelf.behaviors, self.name or "?")

                        local atend = {}
                        if replacementMode == "before" then
                            for i, b in ipairs(triggerSelf.behaviors) do
                                atend[#atend + 1] = b
                            end
                            triggerSelf.behaviors = {}
                        elseif replacementMode == "replaceAll" then
                            triggerSelf.behaviors = {}
                        end

                        local nstarting = #triggerSelf.behaviors
                        for _, behavior in ipairs(modBehaviors) do
                            local replaced = false
                            if replacementMode == "replace" then
                                for j = 1, nstarting do
                                    if triggerSelf.behaviors[j].typeName == behavior.typeName then
                                        triggerSelf.behaviors[j] = DeepCopy(behavior)
                                        replaced = true
                                        break
                                    end
                                end
                            end

                            if not replaced then
                                triggerSelf.behaviors[#triggerSelf.behaviors + 1] = DeepCopy(behavior)
                            end
                        end

                        for _, b in ipairs(atend) do
                            triggerSelf.behaviors[#triggerSelf.behaviors + 1] = b
                        end

                        printf("MODIFY TRIGGER: final behaviors=%d", #triggerSelf.behaviors)
                    end
                end
            end
        end
    end

    return g_baseTriggerAbilityTrigger(triggerSelf, characterModifier, creature, symbols, auraControllerToken, modContext, argOptions)
end


--Strikes with no trigger prompt of their own. An opportunity attack only draws
--a warning arrow, and a hero's grant is cast directly on the recipient, so
--neither makes an ActiveTrigger. Intercept Strikes raises one for both.

--How long to hold a granted strike waiting for an answer. Deliberately long:
--it must never cut off a player who is just taking their time.
local STRIKE_PROMPT_TIMEOUT_SECONDS = 120

--Opportunity-attack cards we have outstanding, keyed "<observer>/<mover>".
--One departure can dispatch leaveadjacent more than once, and these cards are
--noDeduplicate, so without this the same prompt would stack up.
local g_outstandingOpportunityPrompts = {}

--One-shot suppression, keyed by charid: accepting an intercepted strike casts
--it back through the hook that raised the card, which would otherwise raise it
--again. The expiry stops a cast that never arrives swallowing a later one.
local g_suppressInterceptUntil = {}

local function SuppressNextIntercept(charid)
    g_suppressInterceptUntil[charid] = dmhub.Time() + 30
end

local function ConsumeInterceptSuppression(charid)
    local expiry = g_suppressInterceptUntil[charid]
    if expiry == nil then
        return false
    end

    g_suppressInterceptUntil[charid] = nil
    return dmhub.Time() <= expiry
end

--- Whether any active Modify Trigger modifier on this creature asked to see
--- strikes that arrive with no trigger prompt of their own.
--- @param creature creature|nil
--- @return boolean
local function CreatureInterceptsStrikes(creature)
    if creature == nil then
        return false
    end

    local mods = nil
    pcall(function() mods = creature:GetActiveModifiers() end)

    for _,modContext in ipairs(mods or {}) do
        local modifier = modContext.mod
        if modifier.behavior == "modifytrigger" and modifier:try_get("interceptStrikes", false) and modifier:PassesFilter(creature) then
            return true
        end
    end

    return false
end

--- Raises a prompt card for a strike the creature is about to make, records
--- what kind of strike it is so the trigger condition can match on it, and
--- returns the card's id.
--- @param casterToken CharacterToken the creature that would strike
--- @param args {text: string, rules: string, activateText: string|nil, targets: string[]|nil, freestrike: boolean, signature: boolean}
--- @return string triggerid
local function RaiseStrikePrompt(casterToken, args)
    local trigger = ActiveTrigger.new{
        id = dmhub.GenerateGuid(),
        text = args.text,
        rules = args.rules or "",
        activateText = args.activateText or "Activate",
        targets = args.targets or {},
        clearOnDismiss = true,
        noDeduplicate = true,
        --An opportunity attack and a granted strike both cost a triggered
        --action, so the card uses the non-free (gold) styling.
        free = false,
    }

    g_interposedStrikeGrant[trigger.id] = {args.freestrike == true, args.signature == true}

    casterToken:ModifyProperties{
        description = "Strike Prompt",
        undoable = false,
        execute = function()
            casterToken.properties:DispatchAvailableTrigger(trigger)
        end,
    }

    return trigger.id
end

--- Holds the calling cast coroutine until the player answers a strike prompt.
--- Returns true to go ahead with the strike that was about to happen, false
--- when the player declined it or replaced it with one of the modifier's modes
--- (the mode's own ability has already been cast by then).
--- @param casterToken CharacterToken
--- @param triggerid string
--- @return boolean
local function AwaitStrikeDecision(casterToken, triggerid)
    local deadline = dmhub.Time() + STRIKE_PROMPT_TIMEOUT_SECONDS

    --This client only watches the card; the answer arrives as a change to the
    --synced record, so nothing here will call ClearAvailableTrigger for us.
    local function Finish(proceed)
        ForgetTriggerTracking(triggerid)
        return proceed
    end

    while true do
        coroutine.yield(0.1)

        if mod.unloaded then
            return Finish(true)
        end

        if casterToken == nil or (not casterToken.valid) or casterToken.properties == nil then
            return Finish(false)
        end

        local record = casterToken.properties:GetAvailableTriggerRecord(triggerid)

        if record == nil then
            --Cleared or expired out from under us; let the strike through
            --rather than silently swallowing the grant.
            return Finish(true)
        end

        --A chosen mode arrives as a dismissal: the dispatch hook casts the
        --mode's ability then dismisses the card. A player pressing Dismiss
        --looks identical and means the same thing -- do not make the strike.
        if record.dismissed then
            return Finish(false)
        end

        if record.triggered ~= false then
            casterToken:ModifyProperties{
                description = "Clear Strike Prompt",
                undoable = false,
                execute = function()
                    casterToken.properties:ClearAvailableTrigger({id = triggerid})
                end,
            }
            return Finish(true)
        end

        if dmhub.Time() > deadline then
            casterToken:ModifyProperties{
                description = "Clear Strike Prompt",
                undoable = false,
                execute = function()
                    casterToken.properties:ClearAvailableTrigger({id = triggerid})
                end,
            }
            return Finish(true)
        end
    end
end

--Intercept a strike another creature is handing this one. Both Invoke Ability
--paths -- local, and the one shipped to the recipient's client -- meet at
--ExecuteInvoke, so this one hook covers every "an ally lets you strike".
local g_baseExecuteInvoke = ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke
function ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(invokerToken, abilityClone, casterToken, targeting, symbols, options)
    --In Lua 5.4 coroutine.running() also answers on the main thread, so the
    --second return value is what says whether we can actually wait here.
    local _, isMainThread = coroutine.running()

    --Only worth checking when someone else is handing us the ability, we are
    --inside a cast coroutine (the prompt has to be waited on), and the
    --recipient actually asked to intercept.
    if casterToken ~= nil and casterToken.valid and casterToken.properties ~= nil
        and invokerToken ~= nil and invokerToken.charid ~= casterToken.charid
        and (not isMainThread)
        and CreatureInterceptsStrikes(casterToken.properties) then

        if ConsumeInterceptSuppression(casterToken.charid) then
            --This IS the strike an intercept card already offered.
            return g_baseExecuteInvoke(invokerToken, abilityClone, casterToken, targeting, symbols, options)
        end

        local freestrike, signature = AbilityStrikeGrant(abilityClone, casterToken.properties)
        if freestrike or signature then
            local name = abilityClone.name
            if name == nil or name == "" then
                name = "Free Strike"
                if signature and not freestrike then
                    name = "Signature Ability"
                end
            end

            --No targets on the card: the mode's replacement ability picks its
            --own (Strike For Me selects minions), and listing the granting
            --ally here would hand it to them as a target.
            local triggerid = RaiseStrikePrompt(casterToken, {
                text = name,
                rules = abilityClone:try_get("promptOverride") or "",
                freestrike = freestrike,
                signature = signature,
            })

            if not AwaitStrikeDecision(casterToken, triggerid) then
                return false
            end
        end
    end

    return g_baseExecuteInvoke(invokerToken, abilityClone, casterToken, targeting, symbols, options)
end

--Accepting an intercepted card runs its invocation through ExecuteInvoke like
--any other, so flag the caster first to stop the hook above offering the same
--card a second time.
local g_baseActivateInvocationPrompt = AbilityInvocation.ActivateInvocationPrompt
function AbilityInvocation.ActivateInvocationPrompt(casterToken, triggerid)
    if casterToken ~= nil and casterToken.valid and g_interposedStrikeGrant[triggerid] ~= nil then
        SuppressNextIntercept(casterToken.charid)
    end

    return g_baseActivateInvocationPrompt(casterToken, triggerid)
end

--- Puts an opportunity-attack card on an opted-in creature when an enemy
--- leaves its reach. The card offers the standard Free Strike ability, so the
--- classification above reads it as a free strike and the creature's Modify
--- Trigger modes are offered alongside it. Purely additive: dismissing it
--- costs nothing and the action bar still works as before.
--- @param observerCreature creature the creature that may strike
--- @param movingCreature creature the enemy leaving its reach
local function OfferOpportunityAttackPrompt(observerCreature, movingCreature)
    local observerToken = dmhub.LookupToken(observerCreature)
    local movingToken = dmhub.LookupToken(movingCreature)
    if observerToken == nil or (not observerToken.valid) or movingToken == nil or (not movingToken.valid) then
        return
    end

    local key = string.format("%s/%s", observerToken.charid, movingToken.charid)
    local outstanding = g_outstandingOpportunityPrompts[key]
    if outstanding ~= nil then
        if observerToken.properties:GetAvailableTriggerRecord(outstanding) ~= nil then
            --Still on screen unanswered; one departure is one decision.
            return
        end
        g_outstandingOpportunityPrompts[key] = nil
    end

    local moverName = "an enemy"
    if movingToken.canLocalPlayerSeeName and movingToken.name ~= nil then
        moverName = movingToken.name
    end

    local triggerid = AbilityInvocation.PromptStandardAbility{
        token = observerToken,
        invoker = movingToken,
        standardAbility = "Free Strike",
        prompt = "Opportunity Attack",
        rules = string.format("%s left your reach. You can make a free strike against them.", moverName),
        activateText = "Free Strike",
        free = false,
    }

    if triggerid == nil then
        return
    end

    g_outstandingOpportunityPrompts[key] = triggerid
    --Record the answer rather than leaving the classifier to walk the
    --invocation: this also marks the card as one of ours, which is what stops
    --accepting it from raising a second card.
    g_interposedStrikeGrant[triggerid] = {true, false}
end

--Hook the departure event, not DrawSteelTokenHud's preview arrow: that one
--only tracks a move being planned, while leaveadjacent fires once the enemy
--has really left reach, past every opportunity-attack gate.
local g_baseDispatchEvent = creature.DispatchEvent
function creature:DispatchEvent(eventName, info)
    g_baseDispatchEvent(self, eventName, info)

    if eventName ~= "leaveadjacent" or info == nil then
        return
    end

    --DispatchEventOnOthers rebroadcasts every event to all other creatures
    --with info.subject naming who it happened to. Only the creature actually
    --walked away from may strike, and that dispatch is the one with no subject.
    if info.subject ~= nil then
        return
    end

    local movingCreature = info.movingcreature
    if movingCreature == nil or movingCreature == self then
        return
    end

    --OnMove already applied every opportunity-attack gate before dispatching
    --this (banes, line of effect, grabs, "cannot make opportunity attacks")
    --except the one that forbids triggered actions outright.
    if not self:CanUseTriggeredAbilities() then
        return
    end

    if not CreatureInterceptsStrikes(self) then
        return
    end

    OfferOpportunityAttackPrompt(self, movingCreature)
end
