local mod = dmhub.GetModLoading()

--- @class Aura:CharacterFeature
--- @field objectid string Id of the object placed to represent this aura ("none" if unset).
--- @field iconid string Icon asset path.
--- @field canrelocate boolean If true, the caster can spend an action to move the aura.
--- @field relocateResource string Action resource id used to relocate the aura.
--- @field relocateRange number Maximum range in world units for relocating the aura.
--- @field triggers table[] List of trigger definitions {trigger: string, ability: TriggeredAbility, destroyaura: boolean, movementFilter: string}.
--- movementFilter ("all" or "forced", default "all") restricts an onenter trigger to entries made
--- by forced movement; see Aura.TriggerMovementFilters and the stash helpers further down.
--- @field name string Display name.
--- @field source string Source description string.
--- @field description string Rules text.
--- @field applyto string Target filter id: "all", "allother", "selfandfriends", "friends", "enemies", "sametype", "othertype".
--- @field creatureFilter nil|string|number|table GoblinScript filter evaluated against each creature to determine whether it is affected. Honoured on both sides of the engine boundary: Lua checks it in Aura:CreaturePassesFilter (modifiers, triggers, enter/start-of-turn), and the engine reads it through AuraInstance:GetCreatureFilter so Aura.ApplyTo can consult it too -- which is what keeps a filtered aura out of the per-tile terrain rules (FloorController.GetTileRulesAtLoc) and decides it per creature instead.
--- @field modifiers CharacterModifier[] Modifiers applied to creatures inside the aura.
--- @field subauras nil|Aura[] Optional child aura payloads. Each shares this aura's area, caster,
--- duration, and removal, but has its own applyto/creatureFilter/modifiers/triggers/terrain flags/
--- move damage. Child defs never use objectid, icon/display, relocate fields, or nested subauras.
--- @field powerRollEnabled boolean If true, a 2d10 + powerRollBonus power roll is made against any creature entering the aura or starting its turn there (fires through the onenter trigger path as a free triggered action on the creature; see Aura:GetSimplePowerRollTrigger).
--- @field powerRollBonus number The X in the 2d10 + X power roll.
--- @field powerRollTiers string[]|nil The three power table tier texts (tier 1 = 11 or less, tier 2 = 12-16, tier 3 = 17+), executed by the Draw Steel command parser.
--- @field powerRollShiftEntryMode "normal"|"bane"|"ignore" How the simple power roll handles entry during a Shift: normal rolls normally, bane adds one non-stacking bane, and ignore suppresses only the simple power roll for that entry.
--- @field includeAdjacent boolean If true, the engine extends the aura's area one tile outward (8-way) and marks the extension tiles as adjacent-only. Creatures on those tiles count as touching the aura for enter/start-of-turn trigger contact (the simple power roll fires for them at the start of their turn, with a bane), but the tiles do not take the aura's terrain rules, move damage, or modifiers.
--- @field damaging boolean Explicitly marks the aura as damaging terrain for movement advisories (the red "moving into damaging terrain" line on the drag tooltip). Only needed for auras whose damage comes from custom triggers: an entry power roll or per-tile move damage already implies it (see Aura:IsDamaging).
--- @field environmentalKeywordId string|nil Id in the environmentalKeywords table of the Environmental Keyword this aura is marked with. Set on map-markup zone auras (see MapMarkup BuildZoneAuraInstance) and settable on any hand-authored aura definition. When an aura is created, EnvironmentalKeyword.ApplyToAura folds the keyword's effects (terrain flags, modifiers, move damage, entry power roll) into the definition; the id is also read by the creature and Loc "Environment" GoblinScript symbols and by creature:HasConcealmentIgnoringDarkness.
Aura = RegisterGameType("Aura", "CharacterFeature")

Aura.TriggerConditions = {
    {
        id = "none",
        text = "Add a trigger...",
    },
    {
        id = "onenter",
        text = "When entering the aura",
    },
    {
        id = "casterstartturnaura",
        text = "Start of Caster's Turn",
    },
    {
        id = "casterendturnaura",
        text = "End of Caster's Turn",
    },
}

Aura.ApplyOptions = {
    {
        id = "all",
        text = "All Creatures",
    },
    {
        id = "allother",
        text = "All Other Creatures",
    },
    {
        id = "selfandfriends",
        text = "Friends, Including Self",
    },
    {
        id = "friends",
        text = "Friends, Excluding Self",
    },
    {
        id = "enemies",
        text = "Enemies",
    },
    {
        id = "sametype",
        text = "Same Type Creatures",
    },
    {
        id = "othertype",
        text = "Other Type Creatures",
    },
}

--Which kind of movement into the aura may fire an "onenter" trigger. Deliberately
--offers fewer options than movementDamageFilter: move damage is filtered by the
--engine, which sees the movement type, whereas creature:EnterAura is called
--identically for a shove and for a walk-in, so "forced" is the only distinction
--Lua can honour (see the stash helpers below).
Aura.TriggerMovementFilters = {
    {
        id = "all",
        text = "Any Movement",
    },
    {
        id = "forced",
        text = "Forced Movement Only",
    },
}

Aura.TriggerIdToCondition = {}
for i, cond in ipairs(Aura.TriggerConditions) do
    Aura.TriggerIdToCondition[cond.id] = cond
end

Aura.objectid = "none"
Aura.iconid = "drawsteel/ability/aura_burst_icon.png"
Aura.hasCustomIcon = true
Aura.canrelocate = false
Aura.relocateResource = "standardAction"
Aura.relocateRange = 30
Aura.triggers = {}
Aura.name = "Aura"
Aura.source = "Aura"
Aura.description = ""
Aura.applyto = "all"
Aura.hasCustomIcon = false
Aura.includeAdjacent = false
Aura.powerRollShiftEntryMode = "normal"

Aura.PowerRollShiftEntryModeOptions = {
    {
        id = "normal",
        text = "Normal",
    },
    {
        id = "bane",
        text = "One Bane",
    },
    {
        id = "ignore",
        text = "Ignore Power Roll",
    },
}

function Aura.OnDeserialize(self)
    --we had to change id -> guid to match CharacterFeature.
    if self:has_key("guid") == false then
        self.guid = self:try_get("id")
    end

    self:get_or_add("display", { hueshift = 0, saturation = 1, brightness = 1, bgcolor = "#ffffffff" })
end

--- Creates a new Aura instance with default display settings.
--- @param options nil|table Optional initial field values.
--- @return Aura
function Aura.Create(options)
    local args = {
        guid = dmhub.GenerateGuid(),
        modifiers = {},
        display = {
            hueshift = 0,
            saturation = 1,
            brightness = 1,
            bgcolor = "#ffffffff",
        },
    }

    for k, v in pairs(options or {}) do
        args[k] = v
    end

    local result = Aura.new(args)

    return result
end

--- @class AuraInstance
--- @field aura Aura The Aura definition this instance belongs to.
--- @field casterid string Token id of the creature that cast/owns this aura.
--- @field guid string Unique identifier.
--- @field name string Display name (copied from the Aura definition).
--- @field iconid string Icon asset path.
--- @field display table Display settings {hueshift, saturation, brightness, bgcolor}.
--- @field area table|nil Shape object describing the aura's area, or nil if not yet placed.
--- @field symbols table|nil GoblinScript symbols attached to this instance.
--- @field duration number|string|nil Duration value: rounds as number, "eoe" (end of encounter), "endround", or nil for permanent.
--- @field durationRound number|nil Initiative round at which the aura expires.
--- @field time table|nil Time-stamp object used to compute rounds elapsed.
--- @field object table|nil Reference to the placed object {floorid, objid}.
AuraInstance = RegisterGameType("AuraInstance")

Aura.Flags = {
    {
        id = "zerocost",
        text = "Zero Movement Cost",
    }
}

--- Returns true if this aura has the given flag set.
--- @param id string Flag id (e.g. "zerocost").
--- @return boolean
function Aura:HasFlag(id)
    return self:try_get("flags", {})[id]
end

--- Returns true if the creature passes this aura's GoblinScript creatureFilter.
--- @param c creature The creature to evaluate.
--- @param auraInstance AuraInstance The live aura instance (provides caster context).
--- @return boolean
function Aura:CreaturePassesFilter(c, auraInstance)
    if self:try_get("creatureFilter", "") == "" then
        return true
    end

    local casterToken
    local caster

    if rawget(auraInstance, "casterid") ~= nil then
        casterToken = dmhub.GetTokenById(auraInstance.casterid)
        caster = nil
        if casterToken ~= nil and casterToken.properties ~= nil then
            caster = casterToken.properties
        end
    end

    --The default is the 3rd argument and the context message the 4th. This used to pass
    --the context in the default's slot, which made a filter that failed to compile or
    --threw default to the truthy string "Aura Creature Filter" -- and swallowed the real
    --error text in the log. Default to true deliberately: an unevaluable filter should
    --leave the aura working as if unfiltered rather than make it silently affect nobody.
    local result = ExecuteGoblinScript(self.creatureFilter, c:LookupSymbol { caster = caster, target = c, aura = auraInstance },
        true, "Aura Creature Filter")
    return GoblinScriptTrue(result)
end

--- Builds the synthesized enter/start-of-turn power roll trigger from the simple
--- power roll fields (powerRollEnabled/powerRollBonus/powerRollTiers), or nil when
--- disabled, empty, or the power roll behavior type is not loaded. The returned
--- table is shaped like an entry of Aura.triggers ({trigger, ability}) and the
--- ability is a free (no action resource), non-mandatory triggered action: it
--- comes up as a trigger prompt on the creature, and the roll is flagged as an
--- environment roll so it counts as a roll made AGAINST the creature for power
--- roll modifiers (their own modifiers do not apply to it). The prompt is
--- hostile: environment rolls are never beneficial offers, so it renders red
--- and never expires.
--- @param options nil|{adjacentOnly: boolean, enteredViaShift: boolean} adjacentOnly =
--- the creature touches the aura only via its adjacent extension (includeAdjacent),
--- not any true aura tile; enteredViaShift = the creature entered during a Shift.
--- Adjacent-only always rolls with one bane. A shifted entry follows
--- powerRollShiftEntryMode, with unknown values treated as normal.
--- @return nil|{trigger: string, ability: TriggeredAbility}
function Aura:GetSimplePowerRollTrigger(options)
    if not self:try_get("powerRollEnabled", false) then
        return nil
    end

    local shiftedEntry = options ~= nil and options.enteredViaShift == true
    local shiftEntryMode = self:try_get("powerRollShiftEntryMode", "normal")
    if shiftedEntry and shiftEntryMode == "ignore" and not options.adjacentOnly then
        return nil
    end

    local rollBehaviorType = rawget(_G, "ActivatedAbilityPowerRollBehavior")
    if rollBehaviorType == nil then
        return nil
    end

    local tiers = self:try_get("powerRollTiers")
    if tiers == nil then
        return nil
    end

    local hasText = false
    for i = 1, 3 do
        if trim(tiers[i] or "") ~= "" then
            hasText = true
            break
        end
    end
    if not hasText then
        return nil
    end

    local bonus = math.floor(tonumber(self:try_get("powerRollBonus", 0)) or 0)
    local roll
    if bonus < 0 then
        roll = string.format("2d10 - %d", -bonus)
    else
        roll = string.format("2d10 + %d", bonus)
    end

    local behaviorFields = {
        roll = roll,
        tiers = {tiers[1] or "", tiers[2] or "", tiers[3] or ""},
    }

    --Adjacent-only contact rolls with a bane (e.g. Lava: "If the target is
    --adjacent to lava but not in it, this ability takes a bane"). Some auras
    --also apply a bane when entered by shifting (e.g. Quicksand). Adjacent-only
    --takes precedence, so the two built-in reasons can never stack. The entry
    --shape matches the behavior's built-in modifiers list ({type, condition,
    --text}, see MCDMAbilityRollBehavior's "our behavior-builtin modifiers").
    local baneText = nil
    local baneDetails = nil
    if options ~= nil and options.adjacentOnly then
        baneText = string.format("Adjacent to %s", self.name)
        baneDetails = string.format("This roll takes a bane against a creature that is adjacent to the %s but not in it. You started your turn next to the area rather than inside it.", self.name)
    elseif shiftedEntry and shiftEntryMode == "bane" then
        baneText = string.format("Shifted into %s", self.name)
        baneDetails = string.format("This roll takes a bane because the triggering creature shifted into the %s.", self.name)
    end

    if baneText ~= nil then
        behaviorFields.modifiers = {
            {
                type = "bane",
                condition = true,
                text = baneText,
                details = baneDetails,
            },
        }
    end

    return {
        trigger = "onenter",
        ability = TriggeredAbility.Create{
            name = self.name,
            trigger = "onenter",
            targetType = "self",
            range = 0,
            radius = 0,
            silent = true,
            mandatory = false,
            hostile = true,
            environmentRoll = true,
            iconid = self.iconid,
            behaviors = {
                rollBehaviorType.new(behaviorFields),
            },
        },
    }
end

--- Whether this aura is "damaging terrain" for movement advisories: it hurts
--- creatures that enter it or move through it. True when the aura has an entry
--- power roll (Lava), per-tile move damage, or the explicit `damaging` flag
--- (for hand-authored auras whose damage comes from custom triggers).
--- @return boolean
function Aura:IsDamaging()
    if self:try_get("damaging", false) == true then
        return true
    end

    if self:try_get("movedamage", "none") ~= "none" then
        return true
    end

    if not self:try_get("powerRollEnabled", false) then
        return false
    end

    local tiers = self:try_get("powerRollTiers")
    if tiers == nil then
        return false
    end

    for i = 1, 3 do
        if trim(tiers[i] or "") ~= "" then
            return true
        end
    end

    return false
end

local g_powerRollTierLabels = {"11 or less", "12 - 16", "17 +"}

--Composes a short human-readable summary of tier text validator findings
--(ActivatedAbilityDrawSteelCommandBehavior.DiagnoseTierText). Copy mirrors the
--ability editor's diagnostics chips, compressed for an inline label.
local function ComposePowerRollFindingSummary(findings)
    local parts = {}
    for _,finding in ipairs(findings) do
        if #parts >= 2 then
            parts[#parts+1] = "..."
            break
        end
        if finding.kind == "damageType_unknown" and finding.token ~= nil then
            if finding.suggestion ~= nil and finding.suggestion ~= "" then
                parts[#parts+1] = string.format("Damage type '%s' isn't recognized - did you mean '%s'?", finding.token, finding.suggestion)
            else
                parts[#parts+1] = string.format("Damage type '%s' isn't recognized.", finding.token)
            end
        elseif finding.kind == "duration_missing" and finding.condition ~= nil then
            parts[#parts+1] = string.format("Condition '%s' needs a duration - try (save ends), (EoT), or (EoE).", finding.condition)
        elseif finding.kind == "near_miss" and finding.suggestion ~= nil and finding.segment ~= nil then
            parts[#parts+1] = string.format("Did you mean '%s' in '%s'?", finding.suggestion, finding.segment)
        elseif finding.kind == "unknown_segment" and finding.segment ~= nil then
            parts[#parts+1] = string.format("'%s' isn't read as a rule.", finding.segment)
        end
    end
    return table.concat(parts, " ")
end

--- Shared editor section for the simple enter/start-of-turn power roll fields.
--- Used by both the Aura editor (Aura:GenerateEditor) and the Environmental
--- Keywords compendium editor. Reads/writes powerRollEnabled, powerRollBonus and
--- powerRollTiers directly on options.obj; options.change (optional) is invoked
--- after every mutation so the host editor can persist/refresh.
--- Returns an empty collapsed panel when the Draw Steel power roll machinery is
--- not loaded (non-DS game systems).
--- @param options {obj: table, change: nil|fun()}
--- @return Panel
function Aura.CreateSimplePowerRollEditor(options)
    local obj = options.obj
    local onchange = options.change or function() end

    if rawget(_G, "ActivatedAbilityPowerRollBehavior") == nil then
        return gui.Panel{ classes = {"collapsed"}, width = 1, height = 1 }
    end

    local tierPanels = {}
    for i = 1, 3 do
        local index = i

        --forward-declare: the input's change handler refreshes this label.
        local validationLabel

        local UpdateValidation = function()
            local tiers = obj:try_get("powerRollTiers")
            local text = ""
            if tiers ~= nil then
                text = tiers[index] or ""
            end

            if trim(text) == "" then
                validationLabel:SetClass("collapsed", true)
                return
            end

            local cmdType = rawget(_G, "ActivatedAbilityDrawSteelCommandBehavior")
            if cmdType == nil then
                validationLabel:SetClass("collapsed", true)
                return
            end

            local preview = text
            pcall(function()
                preview = cmdType.FormatRuleValidation(text)
            end)

            local findings = {}
            pcall(function()
                findings = cmdType.DiagnoseTierText(text) or {}
            end)

            validationLabel:SetClass("collapsed", false)
            if #findings == 0 then
                validationLabel.text = string.format("<color=#79b877>Recognized:</color> %s", preview)
            else
                validationLabel.text = string.format("<color=#e0b050>%s</color>\n%s", ComposePowerRollFindingSummary(findings), preview)
            end
        end

        validationLabel = gui.Label{
            classes = {"collapsed"},
            width = "100%-100",
            height = "auto",
            halign = "right",
            fontSize = 13,
            textWrap = true,
            bmargin = 4,
        }

        tierPanels[#tierPanels+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Label{
                    text = g_powerRollTierLabels[index],
                    width = 90,
                    height = "auto",
                    fontSize = 16,
                    valign = "center",
                },

                gui.Input{
                    text = (obj:try_get("powerRollTiers") or {})[index] or "",
                    width = "100%-100",
                    height = 26,
                    fontSize = 16,
                    valign = "center",
                    change = function(element)
                        local tiers = obj:get_or_add("powerRollTiers", {"", "", ""})
                        tiers[index] = element.text
                        UpdateValidation()
                        onchange()
                    end,
                },
            },

            validationLabel,

            create = function(element)
                UpdateValidation()
            end,
        }
    end

    local detailsChildren = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 4,

            gui.Label{
                text = "Power Roll: 2d10 +",
                width = "auto",
                height = "auto",
                fontSize = 16,
                valign = "center",
            },

            gui.Input{
                text = tostring(math.floor(tonumber(obj:try_get("powerRollBonus", 0)) or 0)),
                width = 40,
                height = 22,
                fontSize = 16,
                hmargin = 8,
                valign = "center",
                characterLimit = 4,
                change = function(element)
                    local num = tonumber(element.text)
                    if num == nil then
                        element.text = tostring(math.floor(tonumber(obj:try_get("powerRollBonus", 0)) or 0))
                    else
                        obj.powerRollBonus = math.floor(num)
                        onchange()
                    end
                end,
            },
        },

        gui.Label{
            text = "A power roll made against any creature that enters the area or starts its turn there. It appears as a free triggered action on the creature.",
            width = "100%",
            height = "auto",
            fontSize = 13,
            bmargin = 4,
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            hover = gui.Tooltip("Controls only the simple power roll when a creature enters during an actual Shift. Normal movement, forced movement, and start-of-turn rolls are unaffected. Adjacent-only rolls still take their existing single bane."),

            gui.Label{
                text = "When Entered by Shifting:",
                width = 220,
                height = 22,
                fontSize = 16,
                valign = "center",
            },

            gui.Dropdown{
                width = 180,
                height = 22,
                fontSize = 16,
                options = Aura.PowerRollShiftEntryModeOptions,
                idChosen = obj:try_get("powerRollShiftEntryMode", "normal"),
                change = function(element)
                    obj.powerRollShiftEntryMode = element.idChosen
                    onchange()
                end,
            },
        },
    }

    for _,tierPanel in ipairs(tierPanels) do
        detailsChildren[#detailsChildren+1] = tierPanel
    end

    local detailsPanel = gui.Panel{
        classes = {cond(obj:try_get("powerRollEnabled", false), nil, "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",
        lmargin = 20,
        children = detailsChildren,
    }

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",

        gui.Check{
            halign = "left",
            text = "Power Roll on Enter / Start of Turn",
            value = obj:try_get("powerRollEnabled", false),
            change = function(element)
                obj.powerRollEnabled = element.value
                detailsPanel:SetClass("collapsed", not element.value)
                onchange()
            end,
        },

        detailsPanel,
    }
end

function Aura:GenerateEditor(options)
    options = options or {}

    local resultPanel

    local objectChoices = {
        {
            id = "none",
            text = "Choose Object...",
        }
    }

    local objectAuraFolder = assets:GetObjectNode("auras");
    for i, auraObject in ipairs(objectAuraFolder.children) do
        if not auraObject.isfolder then
            objectChoices[#objectChoices + 1] = {
                id = auraObject.id,
                text = auraObject.description,
            }
        end
    end

    local abilitiesPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshAura = function(element)
            local abilityChildren = {}
            for i, trigger in ipairs(self.triggers) do
                abilityChildren[#abilityChildren + 1] = gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    gui.Panel {
                        height = 20,
                        width = "100%",
                        flow = "horizontal",
                        halign = "left",
                        gui.Label {
                            halign = "left",
                            text = Aura.TriggerIdToCondition[trigger.trigger].text,
                            fontSize = 18,
                            bold = true,
                            width = "auto",
                            height = "auto",
                        },
                        gui.Button {
                            classes = {"deleteButton", "sizeXxs"},
                            hmargin = 20,
                            halign = "left",
                            valign = "center",
                            click = function(element)
                                table.remove(self.triggers, i)
                                resultPanel:FireEventTree("refreshAura")
                            end,
                        },
                    },

                    gui.Check {
                        styles = ThemeEngine.GetStyles(),
                        text = "Destroy Aura After Trigger",
                        value = (trigger.destroyaura or false),
                        change = function(element)
                            trigger.destroyaura = element.value
                            resultPanel:FireEventTree("refreshAura")
                        end,
                    },

                    --Only entering the aura can be attributed to a kind of movement;
                    --the end-of-turn trigger has no movement to filter.
                    gui.Dropdown {
                        styles = ThemeEngine.GetStyles(),
                        classes = { "formDropdown", cond(trigger.trigger ~= "onenter", "collapsed") },
                        halign = "left",
                        options = Aura.TriggerMovementFilters,
                        idChosen = trigger.movementFilter or "all",
                        change = function(element)
                            trigger.movementFilter = element.idChosen
                            resultPanel:FireEventTree("refreshAura")
                        end,
                    },

                    --the triggers don't have a trigger condition set because that is implied
                    --by the way the creature interacts with the aura. They don't have activation
                    --saving throws either, since that is for 'good' triggers to see if they are activated.
                    --The normal saving throws are controlled by the behavior which will be added to the trigger.
                    trigger.ability:GenerateEmbeddedEditor()
                }
            end

            abilityChildren[#abilityChildren + 1] = gui.Dropdown {
                styles = ThemeEngine.GetStyles(),
                classes = "formDropdown",
                idChosen = "none",
                options = Aura.TriggerConditions,
                halign = "left",
                valign = "top",
                change = function(element)
                    if #self.triggers == 0 then
                        --make sure we have unique triggers.
                        self.triggers = {}
                    end

                    local targetType = "self"
                    if element.idChosen == "casterendturnaura" or element.idChosen == "casterstartturnaura" then
                        targetType = "aura"
                    end

                    self.triggers[#self.triggers + 1] = {
                        trigger = element.idChosen,
                        ability = TriggeredAbility.Create {
                            name = "Aura Trigger",
                            targetType = targetType,
                            trigger = element.idChosen,
                            range = 5,
                            radius = 0,
                            silent = true,
                        },
                    }
                    resultPanel:FireEventTree("refreshAura")
                end,
            }

            element.children = abilityChildren
        end,

    }

    local iconEditorPanel = ActivatedAbility.IconEditorPanel(self)
    if options.childAura then
        --sub-auras have no icon or object of their own; the parent provides the visuals.
        iconEditorPanel:SetClass("collapsed", true)
    end

    --Sub-aura editing. Only on top-level auras: sub-auras cannot nest.
    local subAurasPanel = nil
    if not options.childAura then
        subAurasPanel = gui.Panel {
            width = "100%",
            height = "auto",
            flow = "vertical",

            refreshAura = function(element)
                local subChildren = {}
                for i, subaura in ipairs(self:try_get("subauras", {})) do
                    subChildren[#subChildren + 1] = gui.Panel {
                        width = "100%",
                        height = "auto",
                        flow = "vertical",

                        gui.Panel {
                            height = 20,
                            width = "100%",
                            flow = "horizontal",
                            halign = "left",
                            gui.Label {
                                halign = "left",
                                text = string.format("Sub-Aura %d", i),
                                fontSize = 18,
                                bold = true,
                                width = "auto",
                                height = "auto",
                            },
                            gui.Button {
                                classes = {"deleteButton", "sizeXxs"},
                                hmargin = 20,
                                halign = "left",
                                valign = "center",
                                click = function(element)
                                    table.remove(self.subauras, i)
                                    resultPanel:FireEventTree("refreshAura")
                                end,
                            },
                        },

                        subaura:GenerateEditor{ norelocate = true, childAura = true },
                    }
                end

                subChildren[#subChildren + 1] = gui.Button {
                    text = "Add Sub-Aura",
                    halign = "left",
                    fontSize = 16,
                    vmargin = 4,
                    click = function(element)
                        local subs = self:get_or_add("subauras", {})
                        subs[#subs + 1] = Aura.Create{ name = "Sub-Aura" }
                        resultPanel:FireEventTree("refreshAura")
                    end,
                }

                element.children = subChildren
            end,
        }
    end

    resultPanel = gui.Panel {
        classes = "abilityEditor",
        styles = {
            Styles.Form,

            {
                classes = { "formPanel" },
                halign = "left",
                width = 340,
            },
            {
                classes = { "formLabel" },
                halign = "left",
            },
            {
                classes = { "abilityEditor" },
                width = '100%',
                height = 'auto',
                flow = "horizontal",
                valign = "top",
            },
            {
                classes = "mainPanel",
                width = "90%",
                height = "auto",
                flow = "vertical",
                valign = "top",
            },

        },

        gui.Panel {
            id = "leftPanel",
            classes = "mainPanel",

            iconEditorPanel,

            gui.Panel {
                classes = { "formPanel", cond(options.childAura, 'collapsed') },
                gui.Label {
                    classes = "formLabel",
                    text = "Object:",
                },
                gui.Dropdown {
                    styles = ThemeEngine.GetStyles(),
                    classes = "formDropdown",
                    options = objectChoices,
                    sort = true,
                    hasSearch = true,
                    idChosen = self.objectid,
                    change = function(element)
                        self.objectid = element.idChosen
                    end,
                },
            },

            gui.Panel {
                classes = "formPanel",
                gui.Label {
                    classes = "formLabel",
                    text = "Apply To:",
                },
                gui.Dropdown {
                    styles = ThemeEngine.GetStyles(),
                    classes = "formDropdown",
                    options = Aura.ApplyOptions,
                    idChosen = self.applyto,
                    change = function(element)
                        self.applyto = element.idChosen
                    end,
                },
            },

            gui.Panel {
                classes = { "formPanel" },
                gui.Label {
                    text = 'Filter:',
                    classes = { 'formLabel' },
                },
                gui.GoblinScriptInput {
                    value = self:try_get("creatureFilter", ""),
                    change = function(element)
                        self.creatureFilter = element.value
                        resultPanel:FireEventTree("refreshAura")
                    end,
                    documentation = {
                        help = "This GoblinScript is used to determine which creatures are affected by this aura. It is run for each creature that enters the aura, and if it returns true, the creature is affected by the aura.",
                        output = "boolean",
                        examples = {
                            {
                                script = 'Self has "*phasing*"',
                                text = "Only creature which have a feature with phasing in the name are affected by this aura.",
                            }
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "Creature that is entering the aura.",
                        symbols = {
                            caster = {
                                name = "Caster",
                                type = "creature",
                                desc = "The creature that cast the aura.",
                            },
                            target = {
                                name = "Target",
                                type = "creature",
                                desc = "The creature being evaluated for inclusion in the aura. This is a synonym for 'Self' for this script.",
                            },
                            aura = {
                                name = "Aura",
                                type = "aura",
                                desc = "The aura being applied.",
                            },
                        }

                    }
                },
            },

            gui.Panel {
                classes = { 'formPanel', 'namePanel' },
                gui.Label {
                    text = 'Move Damage:',
                    classes = { 'formLabel' },
                },
                gui.Dropdown {
                    styles = ThemeEngine.GetStyles(),
                    classes = { "formDropdown" },
                    idChosen = self:try_get("movedamage", "none"),
                    options = table.append_arrays({ { id = "none", text = "none" } }, map(rules.damageTypesAvailable, function(
                        a) return { id = a, text = a } end)),
                    change = function(element)
                        self.movedamage = element.idChosen
                        resultPanel:FireEventTree("refreshAura")
                    end,

                },
                gui.Input {
                    text = self:try_get("damage", 0),
                    classes = { 'input', 'form-input' },
                    width = 40,
                    height = 22,
                    halign = "left",
                    hmargin = 10,
                    characterLimit = 4,
                    events = {
                        refreshAura = function(element)
                            element:SetClass("hidden", self:try_get("movedamage", "none") == "none")
                        end,
                        change = function(element)
                            local num = tonumber(element.text)
                            if num == nil then
                                element.text = self:try_get("damage", 0)
                            else
                                self.damage = num
                            end
                            resultPanel:FireEventTree("refreshAura")
                        end,
                    },
                },
            },

            gui.Dropdown{
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                classes = "formDropdown",
                options = {
                    {id = "all", text = "All Movement"},
                    {id = "nonshift", text = "Non-Shifting Movement"},
                    {id = "forced", text = "Forced Movement Only"},
                },
                idChosen = self:try_get("movementDamageFilter") or (self:try_get("shiftAvoidsDamage", false) and "nonshift" or "all"),
                change = function(element)
                    self.movementDamageFilter = element.idChosen
                    resultPanel:FireEventTree("refreshAura")
                end,
                create = function(element)
                    element:FireEvent("refreshAura")
                end,
                refreshAura = function(element)
                    element:SetClass("collapsed", self:try_get("movedamage", "none") == "none")
                end,
            },

            Aura.CreateSimplePowerRollEditor{
                obj = self,
                change = function()
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Multiselect {
                halign = "left",
                value = self:try_get("flags"),
                addItemText = "Add Flag...",
                options = Aura.Flags,

                change = function(element, val)
                    self.flags = val
                end,
            },

            gui.Check {
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                text = "Offers Concealment",
                value = self:try_get("concealment", false),
                change = function(element)
                    self.concealment = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                text = "Makes Terrain Difficult",
                value = self:try_get("difficult_terrain", false),
                change = function(element)
                    self.difficult_terrain = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                text = "Affects Adjacent Squares",
                tooltip = "The aura's area extends one square outward. Creatures adjacent to the aura count as touching it for enter/start-of-turn triggers -- the entry power roll fires for them at the start of their turn, with a bane -- but adjacent squares do not take the aura's terrain rules, move damage, or modifiers.",
                value = self:try_get("includeAdjacent", false),
                change = function(element)
                    self.includeAdjacent = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                text = "Blocks Line of Effect",
                value = self:try_get("blocks_line_of_effect", false),
                change = function(element)
                    self.blocks_line_of_effect = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                text = "Blocks Movement",
                value = self:try_get("blocks_movement", false),
                change = function(element)
                    self.blocks_movement = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                styles = ThemeEngine.GetStyles(),
                halign = "left",
                text = "Unlimited Height",
                tooltip = "By default an aura reaches as far above and below its source as it does laterally. Check this to have it instead reach any distance up and down.",
                value = self:try_get("unlimitedHeight", false),
                change = function(element)
                    self.unlimitedHeight = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            CharacterFeature.EditorPanel(self, {
                halign = "left",
                noscroll = true,
                height = "auto",
            }),


            gui.Check {
                styles = ThemeEngine.GetStyles(),
                classes = { cond(options.norelocate, 'collapsed') },
                text = "Can relocate",
                value = self.canrelocate,
                change = function(element)
                    self.canrelocate = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Panel {
                classes = { "formPanel", cond(self.canrelocate, nil, 'hidden'), cond(options.norelocate, 'collapsed') },
                refreshAura = function(element)
                    element:SetClass("hidden", not self.canrelocate)
                end,
                gui.Label {
                    classes = "formLabel",
                    text = "Relocate Action:",
                },
                gui.Dropdown {
                    styles = ThemeEngine.GetStyles(),
                    classes = "formDropdown",
                    options = CharacterResource.GetActionOptions(),
                    idChosen = self.relocateResource,
                    change = function(element)
                        self.relocateResource = element.idChosen
                    end,
                },
            },

            gui.Panel {
                classes = { "formPanel", cond(self.canrelocate, nil, 'hidden'), cond(options.norelocate, 'collapsed') },
                refreshAura = function(element)
                    element:SetClass("hidden", not self.canrelocate)
                end,
                gui.Label {
                    classes = "formLabel",
                    text = "Relocate Range:",
                },
                gui.Input {
                    classes = "formInput",
                    text = tostring(self.relocateRange or 0),
                    change = function(element)
                        self.relocateRange = tonumber(element.text) or self.relocateRange
                    end,
                },
            },

            abilitiesPanel,

            subAurasPanel,
        },


    }

    resultPanel:FireEventTree("refreshAura")

    return resultPanel
end

function Aura:ShowEditDialog(options)
    options = options or {}
    local onclose = options.close
    options.close = nil
    local aura = self

    local dialogWidth = 1200
    local dialogHeight = 980

    local resultPanel = nil

    local mainFormPanel = gui.Panel {
        style = {
            bgcolor = 'white',
            pad = 0,
            margin = 0,
            width = 1060,
            height = 840,
        },
        vscroll = true,
    }

    local newItem = nil

    local closePanel =
        gui.Panel {
            style = {
                valign = 'bottom',
                flow = 'horizontal',
                height = 60,
                width = '100%',
                vmargin = 0,
            },

            children = {
                gui.Button {
                    classes = {"sizeM"},
                    text = 'Close',
                    events = {
                        click = function(element)
                            resultPanel.data.close()
                        end,
                    },
                },
            },
        }

    local titleLabel = gui.Label {
        classes = { "modalTitle" },
        text = "Edit Aura",
        valign = "top",
        halign = "center",
        width = "auto",
        height = "auto",
    }

    resultPanel = gui.Panel {
        classes = { "framedPanel" },
        styles = ThemeEngine.GetStyles(),

        width = dialogWidth,
        height = dialogHeight,
        halign = "center",
        valign = "center",

        floating = true,

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element.data.close()
        end,

        data = {
            show = function(editItem)
                newItem = nil

                mainFormPanel.children = {
                    editItem:GenerateEditor(options),
                }
            end,
            close = function()
                if onclose ~= nil then
                    onclose()
                end
                resultPanel:DestroySelf()
            end,
        },

        children = {

            gui.Panel {
                id = 'content',
                style = {
                    halign = 'center',
                    valign = 'center',
                    width = '94%',
                    height = '94%',
                    flow = 'vertical',
                },
                children = {
                    titleLabel,
                    mainFormPanel,
                    closePanel,

                },
            },
        },
    }

    resultPanel.data.show(aura)

    return resultPanel
end

AuraInstance.lookupSymbols = {
    datatype = function(c)
        return "aura"
    end,
    debuginfo = function(c)
        return "aura"
    end,
    caster = function(c)
        local token = dmhub.GetTokenById(c.casterid)
        if token == nil then
            return nil
        end

        return token.properties
    end,
}

AuraInstance.helpSymbols = {
    __name = "aura",
    __sampleFields = { "caster" },
    caster = {
        name = "Caster",
        type = "creature",
        desc = "The creature that controls this aura.",
        seealso = {},
    },
}


--get symbols for a triggered event. Includes this aura as the 'aura' key.
--- Builds a GoblinScript symbols table for a triggered event, including this aura as "aura".
--- @param targetCreature nil|creature The creature that triggered the event, added as "target" if provided.
--- @return table
function AuraInstance:GetSymbolsForTrigger(targetCreature)
    local result = DeepCopy(self:try_get("symbols") or {})
    result.aura = GenerateSymbols(self)

    if targetCreature ~= nil then
        result.target = GenerateSymbols(targetCreature)
    end
    return result
end

--- Fires a triggered ability from this aura instance.
--- @param ability TriggeredAbility The triggered ability to fire.
--- @param castingCreature creature The creature that owns the aura.
--- @param targetToken table|nil Token that entered/exited and triggered the event.
--- @param addedSymbols nil|table Extra GoblinScript symbols to inject.
function AuraInstance:FireTriggeredAbility(ability, castingCreature, targetToken, addedSymbols)
    ability = self:PopulateTriggeredAbility(ability)
    local temporaryModifier = self:CreateTemporaryModifier(castingCreature)
    local symbols = self:GetSymbolsForTrigger(castingCreature)

    if addedSymbols then
        for k, v in pairs(addedSymbols) do
            symbols[k] = v
        end
    end

    local options = {
        debugLog = {}
    }
    ability:Trigger(temporaryModifier, castingCreature, symbols, targetToken, nil, options)
end

--"Forced Movement Only" aura triggers are resolved from the engine's own move
--notification (creature:OnMove), NOT from creature:EnterAura. Three findings from tracing
--real movement forced this:
--
-- 1. EnterAura runs BEFORE a relocate behavior's Cast. The engine walks the prospective
--    path while planning the move (that is what EnterAuraHaltsMovement answers), so
--    anything hooked around the Cast is out of step with it.
--
-- 2. EnterAura is gated to once per aura per turn, and -- worse -- the PLANNING pass is
--    what consumes the gate, so the real movement's entries are reported with the gate
--    already closed. "Force moved into the area" has no such limit: a creature shoved in,
--    cleared, and shoved in again on the same turn takes the effect both times.
--
-- 3. Hooking the forced-movement ABILITY path only covers scripted pushes. A Director
--    ALT-dragging a token is forced movement that casts no ability at all, and was
--    silently missed. OnMove is the one place every kind of movement arrives.
--
--OnMove hands over the real LuaPath, so the squares entered are the engine's own steps
--rather than a reconstructed straight line -- rebounds and collision-shortened pushes
--come out right for free.

--- Index every object-hosted aura carrying a "forced" trigger, keyed by "floor,x,y".
--- Object auras are positioned by their object (their stored area shape is authored data
--- and does not track the spawn location), which is also how the engine places them.
--- @return table<string, AuraInstance[]>
local function CollectForcedTriggerAurasByLoc()
    local result = {}

    for _, floor in ipairs(game.currentMap.floors) do
        for _, obj in pairs(floor.objects) do
            if obj.valid then
                local component = obj:GetComponent("Aura")
                local auraInstance = nil
                if component ~= nil and component.properties ~= nil then
                    auraInstance = component.properties:try_get("aura")
                end

                if auraInstance ~= nil then
                    local key = string.format("%d,%d,%d",
                        obj.floorIndex, math.floor(obj.x + 0.5), math.floor(obj.y + 0.5))
                    local list = result[key]
                    if list == nil then
                        list = {}
                        result[key] = list
                    end
                    list[#list + 1] = auraInstance
                end
            end
        end
    end

    return result
end

--- Call fn(instance, triggerInfo) for each "forced" onenter trigger on this aura,
--- including those carried by its sub-auras (a split aura normally keeps its triggers on
--- the child payload). Child triggers fire through the child view so the trigger sees the
--- child's own payload.
local function ForEachForcedTrigger(auraInstance, fn)
    for _, triggerInfo in ipairs(auraInstance.aura:try_get("triggers", {})) do
        if triggerInfo.trigger == "onenter" and triggerInfo.movementFilter == "forced" then
            fn(auraInstance, triggerInfo)
        end
    end

    for _, child in ipairs(auraInstance:GetChildInstances() or {}) do
        for _, triggerInfo in ipairs(child.aura:try_get("triggers", {})) do
            if triggerInfo.trigger == "onenter" and triggerInfo.movementFilter == "forced" then
                fn(child, triggerInfo)
            end
        end
    end
end

--- Fire the "Forced Movement Only" triggers of every aura whose squares a creature entered
--- during a forced move. Fires every time, with no per-turn dedupe -- see the note above.
--- Called from creature:OnMove for any path flagged `forced`, whatever produced it.
--- @param c nil|creature The creature that was force moved.
--- @param token nil|CharacterToken That creature's token.
--- @param path nil|LuaPath The path the engine actually moved it along.
--- @return nil
function Aura.FireForcedMovementTriggersForPath(c, token, path)
    if c == nil or token == nil or (not token.valid) or path == nil then
        return
    end

    --steps[1] is where the move STARTED; a square is only "entered" from steps[2] on.
    --A shove that went nowhere therefore has nothing to fire.
    local steps = path.steps
    if steps == nil or #steps < 2 then
        return
    end

    local aurasByLoc = CollectForcedTriggerAurasByLoc()

    --Mirrors the caster-token fallback in creature:EnterAura: a non-uploadable token
    --cannot own the triggered cast, so fall back to the creature's own token.
    local auraCasterToken = token
    if auraCasterToken.valid == false or (not auraCasterToken.uploadable) then
        auraCasterToken = dmhub.LookupToken(c)
    end

    --One firing per aura instance per move: a path can re-enter a square it already
    --crossed (a rebound), and a creature larger than one square reports overlaps.
    local fired = {}

    for i = 2, #steps do
        local loc = steps[i]
        local key = string.format("%d,%d,%d", loc.floor, loc.x, loc.y)
        for _, auraInstance in ipairs(aurasByLoc[key] or {}) do
            ForEachForcedTrigger(auraInstance, function(instance, triggerInfo)
                if fired[instance.guid] then
                    return
                end
                if instance.aura:CreaturePassesFilter(c, instance) == false then
                    return
                end

                fired[instance.guid] = true
                instance:FireTriggeredAbility(triggerInfo.ability, c, auraCasterToken)
                if triggerInfo.destroyaura then
                    instance:DestroyAura(c)
                end
            end)
        end
    end
end

--creates a temporary triggered ability copy and populates it with our spellcasting feature making it ready to use.
function AuraInstance:PopulateTriggeredAbility(triggeredAbility)
    triggeredAbility = DeepCopy(triggeredAbility)

    if self:has_key("spellcastingFeature") then
        triggeredAbility.spellcastingFeature = self.spellcastingFeature
    end

    return triggeredAbility
end

--create a character modifier from this aura instance, used for triggers.
function AuraInstance:CreateTemporaryModifier(creature)
    return CharacterModifier.new {
        guid = dmhub.GenerateGuid(),
        behavior = "none",
        name = self.name,
        source = self.name,
        description = "",
    }
end

function AuraInstance:DestroyAura(creature)
    if self:has_key("object") then
        local objectInstance = game.LookupObject(self.object.floorid, self.object.objid)
        if objectInstance ~= nil then
            objectInstance:DestroyWithBehavior {
                ttl = 3,
            }
        end
    end
end

--- Returns true if the aura should be removed at end-of-round (also includes HasExpired check).
--- @return boolean
function AuraInstance:HasExpiredEndOfRound()
    if self:try_get("duration") == "endround" then
        return true
    end

    return self:HasExpired()
end

--- Returns true if this aura instance's duration has elapsed.
--- @return boolean
function AuraInstance:HasExpired()
    --Auras tied to a persistent ability never expire on their own schedule. Their
    --lifetime is controlled by the persistence entry: they are removed when persistence
    --ends (see creature:EndPersistentAbilityById). The "persistence" duration check also
    --covers the misconfigured case where "While Persisting" was chosen on a non-persistent
    --ability (persistenceId never got stamped) -- treat it like "eoe" and never expire.
    if self:try_get("persistenceId") ~= nil or self:try_get("duration") == "persistence" then
        return false
    end

    if self:has_key("duration") then
        local initiative = dmhub.initiativeQueue
        if initiative == nil or initiative.hidden == true then
            return true
        end

        if self.duration == "eoe" then
            --only expires when encounter is over.
            return false
        end

        if self:has_key("durationRound") then
            local q = dmhub.initiativeQueue
            if q ~= nil and q.hidden == false and q.round <= self.durationRound then
                return false
            end
        end

        if type(self.duration) == "number" and (tonumber(self.time:RoundsSince()) or 0) >= self.duration then
            return true
        end
    end

    return false
end

--this is called by DMHub to get the locs an aura fills.
--- Returns the Shape object describing the aura's area, or nil if not yet placed.
--- @return table|nil
function AuraInstance:GetArea()
    return self:try_get("area")
end

--- Returns the applyto filter id from the Aura definition.
--- @return string
function AuraInstance:GetApplyTo()
    return self.aura.applyto
end

function AuraInstance:GetFlags()
    return self.aura:try_get("flags")
end

function AuraInstance:GetDifficultTerrain()
    return self.aura:try_get("difficult_terrain", false)
end

function AuraInstance:GetConcealment()
    return self.aura:try_get("concealment", false)
end

--The aura definition's GoblinScript creature filter, or "" when it has none.
--Read once by the engine when it builds the C# Aura (Aura.cs AddAuraFromLua):
--an aura that reports a filter here is no longer treated as a property of the
--tiles it covers, because it applies to some creatures standing there and not
--others. The engine then asks CreaturePassesFilterForToken per creature.
function AuraInstance:GetCreatureFilter()
    local filter = self.aura:try_get("creatureFilter", "")
    if type(filter) ~= "string" then
        return ""
    end
    return filter
end

--Engine entry point for the creature filter: called from Aura.ApplyTo and from
--FloorController.GetTileRulesAtLoc with the token being tested. The engine
--caches the answer per creature per game update, so this runs at most once per
--pair per update even though its callers are per-tile pathfinding loops.
--Returns true (affected) for anything it cannot evaluate, matching
--Aura:CreaturePassesFilter: an unevaluable filter should leave the aura working
--as if unfiltered rather than silently affect nobody.
function AuraInstance:CreaturePassesFilterForToken(token)
    if token == nil or token.properties == nil then
        return true
    end
    return self.aura:CreaturePassesFilter(token.properties, self)
end

function AuraInstance:GetCover()
    if self.aura:try_get("blocks_line_of_effect", false) then
        return 1
    end

    return 0
end

function AuraInstance:GetBlockMovement()
    return self.aura:try_get("blocks_movement", false)
end

--Additive tile-rule contributions read by the engine (AuraManager.AddAuraFromLua).
--These are optional fields on the Aura definition; abilities normally leave them
--unset, map markup zones set them from their Environmental Keyword.
function AuraInstance:GetWater()
    return self.aura:try_get("water", false)
end

--The footstep sound family (AudioSurfaceTypes index) tiles in this aura use,
--or nil for no override.
function AuraInstance:GetSurfaceType()
    return self.aura:try_get("surfaceType")
end

--Whether the aura's tiles can be climbed, like a climbable wall: creatures in
--the area may climb up to the ceiling of the floor. Returns nil (not climbable)
--or {climbersOnly = boolean}, where climbersOnly restricts the surface to
--natural climbers (climb speed >= walk speed), matching walls'
--"Climbable (Climbers Only)".
function AuraInstance:GetClimbable()
    if self.aura:try_get("climbable", false) ~= true then
        return nil
    end
    return { climbersOnly = self.aura:try_get("climbersOnly", false) == true }
end

--Whether the aura's tiles are a HOLE in the map, like the excavate hole
--object: the engine (AuraManager.AddAuraFromLua) turns this into
--forceGameRules.hole -- no floor at those tiles, creatures fall through --
--registers fall-through map geometry from the aura's area, and renders the
--excavation visual from GetHolePolygons(). Map markup "Hole" zones set it.
function AuraInstance:GetHole()
    return self.aura:try_get("hole", false) == true
end

--The polygon outlines a hole aura was drawn with, in floor coordinates,
--stored on the AuraInstance by the markup panel. Each entry is either a flat
--{x1,y1,x2,y2,...} ring or a structured {points = ring, holes = {ring,...}}
--table (the zone eraser clips holes, so an erased middle leaves a donut).
--Shapes the smooth visual cut; gameplay uses the area tiles.
function AuraInstance:GetHolePolygons()
    return self:try_get("holePolygons")
end

--Optional visual representation of a markup zone, stored on the INSTANCE by
--the markup panel (like holePolygons -- it is presentational, not part of the
--aura definition). The engine (AuraManager.AddAuraFromLua) copies it onto
--Aura.markupAppearance and MarkupZoneVisuals renders it: mode "floor" fills
--the zone's tiles with a floor tilesheet ({mode="floor", tileid, edgeWallId,
--alpha}, the optional edgeWallId drawing a decorative wall ring around the
--boundary), mode "sprites" stamps one hash-picked square sprite per tile
--({mode="sprites", sprites={imageids}, spriteScale, spriteAlpha, seed}).
--Gameplay never reads it.
function AuraInstance:GetAppearance()
    return self:try_get("appearance")
end

--Whether the engine should extend this aura's area one tile outward (8-way),
--marking the extension tiles as adjacent-only (AuraManager.AddAuraFromLua).
--Adjacent tiles count as touching the aura for enter/start-of-turn trigger
--contact, but do not take the aura's terrain rules, move damage, or modifiers.
function AuraInstance:GetIncludeAdjacent()
    return self.aura:try_get("includeAdjacent", false) == true
end

--Optional vertical extent in tiles: the aura only affects creatures whose
--altitude overlaps [GetAltitude(), GetAltitude() + GetHeight()]. nil means
--unlimited height (the engine skips the vertical test entirely).
function AuraInstance:GetHeight()
    return self.aura:try_get("auraHeight")
end

--The altitude the aura's vertical range starts at (only meaningful together
--with auraHeight). nil leaves the engine default of 0.
function AuraInstance:GetAltitude()
    return self.aura:try_get("auraAltitude")
end

--When true, the vertical band is measured from the GROUND under each tile
--tested rather than from the floor's zero altitude, and GetAltitude() becomes
--an offset above that ground. Markup zones set this so a height-limited zone
--follows the terrain: a "ground only" (auraHeight 0) lava pool affects a
--creature standing in it whether the pool is on flat ground, in a pit, or on a
--raised ledge. Auras anchored in absolute space (object auras, ability areas)
--leave it false.
function AuraInstance:GetGroundRelative()
    return self.aura:try_get("auraGroundRelative", false) == true
end

--Optional caster-relative vertical half-extent in tiles, set on the INSTANCE
--by token-attached aura generators (ModifierAura's generateAura) to the aura's
--lateral radius: by default an aura reaches as far above and below its caster
--as it does laterally. The engine computes the affected band live as
--[casterBottom - r, casterTop + r] at test time (Aura.TryGetCasterBand), so it
--follows a flying caster with no re-registration. nil means no caster-relative
--band (the aura uses the absolute auraHeight band, or is unlimited). The aura
--payload's unlimitedHeight flag is the author's opt-out back to the legacy
--infinite column.
function AuraInstance:GetVerticalRadius()
    if self.aura:try_get("unlimitedHeight", false) == true then
        return nil
    end
    return self:try_get("verticalRadius")
end

function AuraInstance:GetDamageInfo()
    local movedamage = self.aura:try_get("movedamage", "none")
    if movedamage == "none" then
        return nil
    end

    local result = {
        damage = self.aura:try_get("damage", 0),
        type = movedamage,
    }

    -- migrate legacy shiftAvoidsDamage boolean to movementDamageFilter string
    local filter = self.aura:try_get("movementDamageFilter")
    if filter == nil then
        if self.aura:try_get("shiftAvoidsDamage", false) then
            filter = "nonshift"
        else
            filter = "all"
        end
    end
    result.movementDamageFilter = filter

    return result
end

function AuraInstance:FillActivatedAbilities(creature, resultAbilities)
    if self.aura.canrelocate and self:GetArea() ~= nil then
        local area = self:GetArea()

        --A relocated aura's stored area is an explicit-locations shape (see
        --ActivatedAbilityMoveAuraBehavior.SetCasterAuraArea), whose shape
        --type ("Locations") is not a placeable target type. Fall back to the
        --targeting shape recorded at relocation time.
        local targetType = area.shape
        if string.lower(tostring(targetType)) == "locations" then
            targetType = self:try_get("moveTargetType", "cube")
        end

        resultAbilities[#resultAbilities + 1] = ActivatedAbility.Create {
            name = string.format("Move %s", self.name),
            auraid = self.guid,
            iconid = self.iconid,
            casterLocOverride = self.area.origin,
            display = self.display,
            targetType = targetType,
            range = self.aura.relocateRange,
            radius = area.radius,
            actionResourceId = self.aura.relocateResource,
            behaviors = {
                ActivatedAbilityMoveAuraBehavior.new {
                    object = self:try_get("object")
                },
            },
        }
    end
end

--- Returns the list of modifiers from the Aura definition, with GoblinScript symbols populated.
--- @return CharacterModifier[]
function AuraInstance:GetModifiers()
    if self:try_get("_tmp_refresh") ~= dmhub.ngameupdate then
        self._tmp_refresh = dmhub.ngameupdate
        local caster = nil
        local tok = self:has_key("casterid") and dmhub.GetTokenById(self.casterid)
        if tok then
            caster = tok.properties
        end
        for _, mod in ipairs(self.aura.modifiers) do
            mod:SetSymbols {
                aura = self,
                caster = caster,
            }
        end
    end

    return self.aura.modifiers
end

--- @class ChildAuraInstance:AuraInstance
--- A transient view over a parent AuraInstance for one entry in aura.subauras. Child views are
--- built on demand by AuraInstance:GetChildInstances and are NEVER stored or serialized: they do
--- not live in creature.auras or in the aura object's component properties. The engine registers
--- them as separate entries in its aura index so each child payload gets its own audience filter,
--- while area/caster/duration/removal all derive from the parent.
ChildAuraInstance = RegisterGameType("ChildAuraInstance", "AuraInstance")

ChildAuraInstance.isChildAura = true

function ChildAuraInstance:GetArea()
    return self._tmp_parent:GetArea()
end

--Children have no lifecycle of their own: they exist only while the parent is registered.
function ChildAuraInstance:HasExpired()
    return false
end

function ChildAuraInstance:HasExpiredEndOfRound()
    return false
end

--Relocation abilities come from the parent only.
function ChildAuraInstance:FillActivatedAbilities(creature, resultAbilities)
end

--The vertical band is a property of the shared area, so children always use
--the parent's: a sub-aura payload never carries its own auraHeight/altitude,
--and without this delegation the engine would read nil from the child def and
--register the child as an infinite column inside a banded parent.
function ChildAuraInstance:GetHeight()
    return self._tmp_parent:GetHeight()
end

function ChildAuraInstance:GetAltitude()
    return self._tmp_parent:GetAltitude()
end

function ChildAuraInstance:GetGroundRelative()
    return self._tmp_parent:GetGroundRelative()
end

function ChildAuraInstance:GetVerticalRadius()
    return self._tmp_parent:GetVerticalRadius()
end

--- Builds transient ChildAuraInstance views for each entry in this instance's aura.subauras.
--- Cached per game update so C# sees stable object identity within a frame. The guid formula
--- (parent guid .. "-sub-" .. child def guid) is deterministic across clients and rebuilds --
--- creature.aurasEntered trigger dedupe persists these guids, so the formula must never change.
--- @return ChildAuraInstance[]
function AuraInstance:GetChildInstances()
    if self:try_get("_tmp_childRefresh") == dmhub.ngameupdate then
        return self._tmp_childInstances
    end

    local result = {}
    local subs = self.aura:try_get("subauras")
    if subs ~= nil then
        for _, childDef in ipairs(subs) do
            local child = ChildAuraInstance.new {
                guid = self.guid .. "-sub-" .. childDef.guid,
                aura = childDef,
                name = self:try_get("name", childDef.name),
                --set explicitly (not just via the class field) so C#-side raw Get() sees it.
                isChildAura = true,
                _tmp_parent = self,
            }

            if rawget(self, "tokenAttached") ~= nil then
                child.tokenAttached = self.tokenAttached
            end
            if rawget(self, "casterid") ~= nil then
                child.casterid = self.casterid
            end
            if rawget(self, "casterPartyId") ~= nil then
                child.casterPartyId = self.casterPartyId
            end
            if self:has_key("symbols") then
                child.symbols = self.symbols
            end
            if self:has_key("spellcastingFeature") then
                child.spellcastingFeature = self.spellcastingFeature
            end

            result[#result + 1] = child
        end
    end

    self._tmp_childInstances = result
    self._tmp_childRefresh = dmhub.ngameupdate
    return result
end

--- @class AuraComponent
--- @field casterid string Token id of the creature that owns the aura.
--- @field auraid string Guid of the AuraInstance on the caster.
--- The object component attached to the placed map object representing an aura.
AuraComponent = RegisterGameType("AuraComponent")

function AuraComponent:Destroy()
    if self:has_key("casterid") then
        local tok = dmhub.GetTokenById(self.casterid)
        if tok ~= nil and tok.properties ~= nil then
            tok:ModifyProperties {
                description = "Remove Aura",
                execute = function()
                    tok.properties:RemoveAura(self.auraid)
                end,
            }
        end
    end
end

function AuraComponent.CreatePropertiesEditor(component)
    local self = component.properties
    if self:has_key("aura") == false then
        return nil
    end

    local casterid = self.aura:try_get("casterid")
    local tokenImagePanel = nil
    if casterid then
        tokenImagePanel = gui.CreateTokenImage(dmhub.GetTokenById(casterid), {
            styles = {
                {
                    flow = "none",
                }
            },
            width = 64,
            height = 64,
            halign = "left",
            valign = "top",
        })
    end
    return gui.Panel {
        width = "auto",
        height = "auto",
        flow = "vertical",

        tokenImagePanel,

        gui.Panel {
            classes = { "field-editor-panel" },
            gui.Label {
                text = "Radius:",
                valign = "center",
                classes = { "field-description-label" },
                hmargin = 4,
            },

            gui.Input {
                width = 40,
                characterLimit = 4,
                halign = "left",
                valign = "center",
                text = tostring(component.properties.aura.area.radius),
                thinkTime = 0.2,
                think = function(element)
                    if element.hasInputFocus then
                        return
                    end

                    local text = tostring(component.properties.aura.area.radius)
                    if text ~= element.text then
                        element.text = text
                    end
                end,

                change = function(element)
                    component:BeginChanges()
                    component.properties.aura.area.radius = tonumber(element.text)
                    print("WRITE::", element.text, "->", tonumber(element.text), "->", component.properties.aura.area.radius)
                    element.text = tostring(component.properties.aura.area.radius)
                    component:CompleteChanges("Change radius")
                end,
            },
        },

        gui.Button {
            width = 100,
            height = 24,
            fontSize = 16,
            text = "Edit Aura",
            click = function(element)
                element.root:AddChild(component.properties.aura.aura:ShowEditDialog {
                    close = function()
                        print("COMPONENT:: UPLOAD")
                        component:Upload()
                    end,
                })
            end,
        }
    }
end

--Opt-in. When true, casting this ability places its aura in place of any aura the
--same caster previously placed with the same ability, rather than alongside it.
--This is the "...until the end of the encounter or you use this ability again"
--wording. Off by default so no existing ability changes behavior.
ActivatedAbilityAuraBehavior.replacePrevious = false

--- Removes auras this caster previously placed with this same ability.
--- Matches on both the ability guid stamped at placement time and the caster id:
--- the ability guid keeps one aura ability from purging a different one, and the
--- caster id keeps two creatures using the same ability from purging each other.
--- Auras placed before sourceAbilityId existed carry no stamp and are left alone.
--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
function ActivatedAbilityAuraBehavior:RemovePreviousAuras(ability, casterToken)
    if casterToken == nil or casterToken.properties == nil then
        return
    end

    local abilityid = ability:try_get("guid")
    if abilityid == nil then
        return
    end

    --Collect first, mutate second: RemoveAura mutates the list we are walking.
    local doomed = {}
    for _,auraInstance in ipairs(casterToken.properties:try_get("auras", {})) do
        if auraInstance:try_get("sourceAbilityId") == abilityid and auraInstance:try_get("casterid") == casterToken.id then
            doomed[#doomed+1] = auraInstance.guid
        end
    end

    if #doomed == 0 then
        return
    end

    casterToken:ModifyProperties {
        description = "Replace Aura",
        execute = function()
            for _,auraid in ipairs(doomed) do
                casterToken.properties:RemoveAura(auraid)
            end
        end,
    }
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityAuraBehavior:Cast(ability, casterToken, targets, options)
    --Purge before placing anything. This lives here rather than in CastOnArea
    --because one cast can cover several areas (targetAreaList), and purging
    --per-area would make a multi-area cast delete its own earlier areas.
    if self:try_get("replacePrevious", false) then
        self:RemovePreviousAuras(ability, casterToken)
    end

    if options.targetAreaList ~= nil then
        --More than one area was supplied (e.g. a movement trail that diagonal
        --steps split into separate pieces). Create one aura over each area.
        for _, area in ipairs(options.targetAreaList) do
            self:CastOnArea(ability,casterToken, targets, options, area)
        end
    elseif options.targetArea ~= nil then
        self:CastOnArea(ability,casterToken, targets, options, options.targetArea)
    else
        for _,target in ipairs(targets) do
            if target.token ~= nil then
                local shape = dmhub.CalculateShape{
                    token = target.token,
                    shape = "RadiusFromCreature",
                    radius = 0,
                }
                self:CastOnArea(ability,casterToken, targets, options, shape)
            end
        end
    end
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
--- @param targetArea LuaShape
function ActivatedAbilityAuraBehavior:CastOnArea(ability, casterToken, targets, options, targetArea)
    --copy the 'shallow' parts from the symbols to include with the aura.
    local symbols = {}
    for k, v in pairs(options.symbols) do
        if type(v) == "number" or type(v) == "string" then
            symbols[k] = v
        end
    end
    local targetLoc = targetArea.origin
    local targetFloor = game.currentMap:GetFloorFromLoc(targetLoc)
    print("AREA:::", targetArea)
    if targetFloor ~= nil then
        local auraArea = targetArea
        local grow = tonumber(self:try_get("grow", 0)) or 0
        if grow > 0 then
            auraArea = auraArea:Grow(grow)
        end
        local guid = dmhub.GenerateGuid()

        --Fold in the effects of any Environmental Keyword this aura names, so a
        --keyword applied through an ability carries the same mechanics it would
        --as a painted map zone: concealment, difficult terrain, water, move
        --damage, entry power roll, and the keyword's modifiers. The merge is
        --additive, so an aura that already states a flag itself is unchanged.
        --Sub-auras carry their own keyword, matching their own payload.
        --EnvironmentalKeyword lives in a later-loading module, hence the
        --runtime lookup rather than a direct reference.
        local auraDef = DeepCopy(self.aura)
        local environmentalKeywordType = rawget(_G, "EnvironmentalKeyword")
        if environmentalKeywordType ~= nil then
            environmentalKeywordType.ApplyToAuraTree(auraDef)
        end

        local auraInstance = AuraInstance.new {
            guid = guid,
            spellcastingFeature = ability:try_get("spellcastingFeature"),
            --Stamped so a later cast of this same ability by this same caster can
            --find and remove this instance (see RemovePreviousAuras). Only read
            --when the behavior opts in via replacePrevious.
            sourceAbilityId = ability:try_get("guid"),
            casterid = casterToken.id,
            --snapshot the caster's party allegiance so an aura that persists past the
            --caster's death (aliveafterdeath) can still tell friend from foe after the
            --caster token/record is gone. Empty string means no party, which the engine
            --Party.IsFriendly treats as the "MONSTER" side. See Aura.cs ApplyTo fallback.
            casterPartyId = casterToken.partyId or "",
            iconid = ability.iconid,
            name = ability.name,
            display = ability.display,
            area = auraArea,
            time = TimePoint.Create(),
            duration = self:try_get("duration", "none"),
            symbols = symbols,
            aliveafterdeath = self:try_get("aliveafterdeath"),
            aura = auraDef,
        }

        if auraInstance.duration == "endnextturn" then
            local q = dmhub.initiativeQueue
            if q ~= nil and q.hidden == false then
                auraInstance.durationRound = q.round + 1
            end

            auraInstance.duration = "endturn"
        end

        print("AURA:: CREATED")

        --Vertical extent. A cube keeps its legacy behavior: the component-level
        --auraHeight below anchors the band at the spawned object's render altitude
        --(see ObjectComponentAura.GetAuras) with the cube's own height. Every other
        --shape gets the default band: the zone reaches as far above and below the
        --cast altitude as it does laterally, written onto the aura payload so the
        --engine's GetHeight/GetAltitude reads pick it up in both the object and the
        --no-object registration paths. unlimitedHeight on the aura payload is the
        --author's opt-out back to the legacy infinite column, and an explicitly
        --authored auraHeight is respected as-is.
        local auraHeight = 0
        if targetArea ~= nil and targetArea.shape == "Cube" then
            auraHeight = targetArea.radius
        elseif auraDef:try_get("unlimitedHeight", false) ~= true and auraDef:try_get("auraHeight") == nil then
            local lateral = math.floor(tonumber(targetArea ~= nil and targetArea.radius or nil) or -1)
            if lateral >= 0 then
                auraDef.auraHeight = lateral * 2
                auraDef.auraAltitude = (tonumber(targetLoc.altitude) or 0) - lateral
            end
        end

        local obj = nil
        if self.aura.objectid ~= nil then
            obj = targetFloor:SpawnObjectLocal(self.aura.objectid)
            if obj ~= nil then
                auraInstance.object = {
                    floorid = obj.floorid,
                    objid = obj.objid,
                }
                obj:AddComponentFromJson("AURA", {
                    ["@class"] = "ObjectComponentAura",
                    auraHeight = auraHeight,
                    properties = AuraComponent.new {
                        casterid = casterToken.id,
                        auraid = guid,
                        aura = auraInstance,
                    },
                })
                options.symbols.cast.auraObject = obj
                obj.x = targetArea.xpos
                obj.y = targetArea.ypos
                --obj.x = targetLoc.x-0.5
                --obj.y = targetLoc.y-0.5
                obj:Upload()
            end
        end

        ability:CommitToPaying(casterToken, options)
        casterToken:ModifyProperties {
            description = "Add Aura",
            execute = function()
                if ability:RequiresConcentration() and casterToken.properties:HasConcentration() and obj ~= nil then
                    local concentration = casterToken.properties:MostRecentConcentration()
                    local objects = concentration:get_or_add("objects", {})
                    objects[#objects + 1] = {
                        floorid = obj.floorid,
                        objid = obj.objid,
                    }
                end

                local persistence = ability:Persistence()
                if persistence ~= nil and persistence.enabled then
                    --Link this aura to the persistent ability so its lifetime follows the
                    --persistence: it survives as long as persistence is maintained and is
                    --removed when persistence ends (see EndPersistentAbilityById).
                    auraInstance.persistenceId = casterToken.properties:MostRecentPersistentAbilityId()

                    if obj ~= nil then
                        local persistenceInfo = casterToken.properties:MostRecentPersistentAbility()
                        if persistenceInfo ~= nil then
                            local objects = persistenceInfo:get_or_add("objects", {})
                            objects[#objects + 1] = {
                                floorid = obj.floorid,
                                objid = obj.objid,
                            }
                        end
                    end
                end

                casterToken.properties:AddAura(auraInstance)
            end,
        }
    end
end

--- @param auraInstance AuraInstance
function creature:AddAura(auraInstance)
    local auras = self:get_or_add("auras", {})
    auras[#auras + 1] = auraInstance
end

function creature:RemoveAura(auraid)
    local auras = self:try_get("auras", {})
    for i, aura in ipairs(auras) do
        if aura.guid == auraid then
            aura:DestroyAura(self)
            table.remove(auras, i)
            return
        end
    end
end

function creature:OnDelete()
    local auras = self:try_get("auras", {})
    for i = #auras, 1, -1 do
        if auras[i]:try_get("aliveafterdeath", false) == false then
            auras[i]:DestroyAura(self)
        end
    end
end

function creature:RemoveAurasOnDeath()
    local auras = self:try_get("auras", {})
    local removes = {}
    for _, aura in ipairs(auras) do
        if aura:try_get("aliveafterdeath", false) == false then
            removes[#removes + 1] = aura.guid
        end
    end

    if removes then
        local token = dmhub.LookupToken(self)
        if token ~= nil then
            for _, guid in ipairs(removes) do
                token:ModifyProperties {
                    description = "Remove Aura",
                    execute = function()
                        self:RemoveAura(guid)
                    end,
                }
            end
        end
    end
end

function Aura.CheckObjectAuraExpirationEndOfRound()
    for _, floor in ipairs(game.currentMap.floors) do
        for _, obj in pairs(floor.objects) do
            if obj:GetComponent("Aura") then
                local auraComponent = obj:GetComponent("Aura")
                if auraComponent ~= nil then
                    local aura = auraComponent.properties
                    if aura.aura:HasExpiredEndOfRound() then
                        aura.aura:DestroyAura()
                    end
                end
            end
        end
    end
end

--Map-anchored auras: every aura the aura system has on the current map that is
--NOT an emanation of a creature. Two storage shapes feed the list:
--  * ability-placed auras, which live in the CASTER's `auras` list and, when the
--    aura definition names an objectid, also carry a spawned map object for the
--    visual. Goblin Malice's Swamp Stink is one of these -- an aura over the whole
--    map, parked on whichever goblin spent the malice.
--  * auras that exist only as an object's Aura component: placed straight onto an
--    object, or outliving their caster through aliveafterdeath.
--Excluded on purpose: modifier-generated auras and the custom auras added from the
--character panel, which carry tokenAttached and follow their creature (they are
--removed on the creature, not here); child sub-auras, which have no lifetime of
--their own; and markup zone auras, which are authored map content edited in the
--Map Markup panel and never appear in either store above.
--- @param auraInstance nil|AuraInstance
--- @return boolean
local function IsMapAnchoredAura(auraInstance)
    if auraInstance == nil then
        return false
    end

    if auraInstance:try_get("tokenAttached", false) then
        return false
    end

    return auraInstance:try_get("isChildAura", false) == false
end

--The walk below touches every token and every object on every floor, and the UI
--that displays it asks more than once per refresh (the caret, the header and the
--list each need the count). One walk per game state is plenty: the underlying
--data only changes when new data arrives from the cloud, and local removals
--invalidate the cache explicitly.
local g_mapAnchoredAuras = nil
local g_mapAnchoredAurasUpdate = -1

--- Discards the memoized map-anchored aura list so the next call rebuilds it.
--- Call after changing an aura from code that must be reflected before the next
--- game update lands.
function Aura.InvalidateMapAnchoredAuras()
    g_mapAnchoredAuras = nil
    g_mapAnchoredAurasUpdate = -1
end

--- Every aura anchored to the current map rather than to a creature. Sorted by
--- name (then guid) so the display order is stable across refreshes -- object
--- iteration order is not.
--- @return {guid: string, name: string, instance: AuraInstance, casterToken: nil|CharacterToken, casterName: nil|string, object: nil|LuaObjectInstance, floorid: nil|string, x: nil|number, y: nil|number}[]
function Aura.GetMapAnchoredAuras()
    if g_mapAnchoredAuras ~= nil and g_mapAnchoredAurasUpdate == dmhub.ngameupdate then
        return g_mapAnchoredAuras
    end

    local result = {}
    local byGuid = {}

    local AddAura = function(auraInstance, casterToken, obj)
        if not IsMapAnchoredAura(auraInstance) then
            return
        end

        local guid = auraInstance:try_get("guid")
        if guid == nil then
            return
        end

        local entry = byGuid[guid]
        if entry == nil then
            entry = { guid = guid, instance = auraInstance }
            byGuid[guid] = entry
            result[#result + 1] = entry
        end

        --an object-backed aura is stored twice; the caster's copy is the one that
        --removes cleanly (RemoveAura destroys the object too), so prefer it.
        if casterToken ~= nil and entry.casterToken == nil then
            entry.instance = auraInstance
            entry.casterToken = casterToken
            entry.casterName = creature.GetTokenDescription(casterToken)
        end

        if obj ~= nil and entry.object == nil then
            entry.object = obj
            entry.floorid = obj.floorid
        end
    end

    for _, token in ipairs(dmhub.allTokens) do
        if token.valid and token.properties ~= nil then
            for _, auraInstance in ipairs(token.properties:try_get("auras", {})) do
                AddAura(auraInstance, token, nil)
            end
        end
    end

    local map = game.currentMap
    if map ~= nil then
        for _, floor in ipairs(map.floors) do
            for _, obj in pairs(floor.objects) do
                local component = obj:GetComponent("Aura")
                if component ~= nil and component.properties ~= nil then
                    AddAura(component.properties:try_get("aura"), nil, obj)
                end
            end
        end
    end

    for _, entry in ipairs(result) do
        local instance = entry.instance

        local name = instance:try_get("name")
        if name == nil or name == "" then
            local auraDef = instance:try_get("aura")
            name = "Aura"
            if auraDef ~= nil then
                name = auraDef.name
            end
        end
        entry.name = name

        --an aura whose caster has left the map (aliveafterdeath) still names the
        --caster on the instance; look it up so the row can still say who cast it.
        if entry.casterName == nil then
            local casterid = instance:try_get("casterid")
            if casterid ~= nil and casterid ~= "" then
                local casterToken = dmhub.GetTokenById(casterid)
                if casterToken ~= nil and casterToken.valid then
                    entry.casterName = creature.GetTokenDescription(casterToken)
                end
            end
        end

        local area = instance:GetArea()
        if area ~= nil and area.origin ~= nil then
            entry.x = area.origin.x
            entry.y = area.origin.y

            if entry.floorid == nil and map ~= nil then
                local floor = map:GetFloorFromLoc(area.origin)
                if floor ~= nil then
                    entry.floorid = floor.floorid
                end
            end
        end
    end

    table.sort(result, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end

        return a.guid < b.guid
    end)

    g_mapAnchoredAuras = result
    g_mapAnchoredAurasUpdate = dmhub.ngameupdate
    return result
end

--- Removes an aura listed by GetMapAnchoredAuras.
--- @param entry nil|table An entry from Aura.GetMapAnchoredAuras.
function Aura.RemoveMapAnchoredAura(entry)
    if entry == nil then
        return
    end

    local casterToken = entry.casterToken
    if casterToken ~= nil and casterToken.valid and casterToken.properties ~= nil then
        --RemoveAura destroys the aura's map object as well, so this covers both
        --halves of an object-backed aura.
        local guid = entry.guid
        casterToken:ModifyProperties {
            description = "Remove Aura",
            execute = function()
                casterToken.properties:RemoveAura(guid)
            end,
        }
        casterToken:UpdateAuras()
    elseif entry.object ~= nil and entry.object.valid then
        --No caster copy to remove from: destroying the object unregisters the
        --aura, and AuraComponent:Destroy clears any caster entry that does exist.
        entry.object:Destroy()
    end

    Aura.InvalidateMapAnchoredAuras()

    if dmhub.RefreshMapAuras ~= nil then
        dmhub.RefreshMapAuras()
    end
end

--Turn-boundary aura triggers: which aura trigger id each turn event fires.
--"nextturn" is dispatched at the start of the caster's turn, "endturn" at the end.
local g_turnEventToAuraTrigger = {
    nextturn = "casterstartturnaura",
    endturn = "casterendturnaura",
}

function creature:CheckAuraExpiration(eventname)
    local auras = self:try_get("auras", {})
    local removes = nil

    local turnTriggerId = g_turnEventToAuraTrigger[eventname]
    if turnTriggerId ~= nil then
        --fire the auras this creature cast that trigger on this turn boundary.
        local auraCasterToken = dmhub.LookupToken(self)
        for i, aura in ipairs(auras) do
            local destroy = false

            for j, trigger in ipairs(aura.aura.triggers) do
                if trigger.trigger == turnTriggerId then
                    aura:FireTriggeredAbility(trigger.ability, self, auraCasterToken, { aura = aura })
                    if trigger.destroyaura then
                        destroy = true
                    end
                end
            end

            --sub-auras carry their own triggers; fire them through the child view so the
            --trigger sees the child's payload while sharing the parent's caster/area.
            for _, child in ipairs(aura:GetChildInstances()) do
                for _, trigger in ipairs(child.aura:try_get("triggers", {})) do
                    if trigger.trigger == turnTriggerId then
                        child:FireTriggeredAbility(trigger.ability, self, auraCasterToken, { aura = child })
                        if trigger.destroyaura then
                            destroy = true
                        end
                    end
                end
            end

            --a sub-aura has no lifetime of its own, so its destroy flag removes the parent.
            if destroy then
                removes = removes or {}
                removes[#removes + 1] = aura.guid
            end
        end
    end


    for i = #auras, 1, -1 do
        --Persistence-linked auras are removed only when their persistence ends, never by
        --turn/round expiration events.
        if rawget(auras[i], "duration") == eventname and rawget(auras[i], "persistenceId") == nil then
            local doremove = true
            if rawget(auras[i], "durationRound") ~= nil then
                local q = dmhub.initiativeQueue
                if q ~= nil and q.hidden == false and q.round < auras[i].durationRound then
                    doremove = false
                end
            end

            if doremove then
                if removes == nil then
                    removes = {}
                end

                removes[#removes + 1] = auras[i].guid
            end
        end
    end

    if removes then
        local token = dmhub.LookupToken(self)
        if token ~= nil then
            for _, guid in ipairs(removes) do
                token:ModifyProperties {
                    description = "Remove Aura",
                    execute = function()
                        self:RemoveAura(guid)
                    end,
                }
            end
        end
    end
end

function creature:GetAura(auraid)
    local auras = self:try_get("auras", {})
    for i, aura in ipairs(auras) do
        if aura.guid == auraid then
            return aura
        end
    end
end

--Relocating an aura's map object only moves the VISUAL. The mechanical area
--lives in TWO serialized copies of the AuraInstance, and both must be updated:
-- 1. The copy inside the object's Aura component: this is the one the engine
--    actually registers in the aura index, so it decides which tiles the
--    aura's concealment/damage/triggers apply to.
-- 2. The copy in the CASTER's auras list: drives the aura panel outline and
--    caster-side bookkeeping.
--The area is also converted to an explicit-locations shape before assignment.
--A serialized targeted shape is a RECIPE {originCreature, targetPoint, range,
--checklos} that the engine re-evaluates on every aura index rebuild and on
--load, re-clamping the target point by the ORIGINAL cast's range and line of
--sight. For an aura cast at short range (e.g. Shadow Skulk's range-1 "leave
--darkness in your space") that recompute pins the mechanical area near the
--cast location no matter where the object is moved. A locations shape stores
--the exact tiles and recomputes to itself.
--NOTE: assign a whole shape; mutating the existing shape's .locations does not
--persist, because AuraInstance:GetArea materialises a fresh userdata per read.
function ActivatedAbilityMoveAuraBehavior.SetCasterAuraArea(obj, newArea)
    if newArea == nil then
        return
    end

    local component = obj:GetComponent("Aura")
    if component == nil or component.properties == nil then
        return
    end

    --Remember the targeting shape the aura was placed with ("Cube" etc.)
    --before converting: FillActivatedAbilities builds the aura's built-in
    --Move ability from the stored area's shape/radius, and a converted area
    --reports shape "Locations", which is not a placeable target type.
    local moveTargetType = nil
    local locs = newArea.locations
    if locs ~= nil and #locs > 0 then
        local converted = dmhub.CalculateShape{
            shape = "locations",
            locations = locs,
            locOverride = newArea.origin or locs[1],
            radius = tonumber(newArea.radius) or 0,
            range = 0,
            checklos = false,
        }
        if converted ~= nil then
            moveTargetType = newArea.shape
            newArea = converted
        end
    end

    local objInstance = component.properties:try_get("aura")
    if objInstance ~= nil then
        component:BeginChanges()
        objInstance.area = newArea
        if moveTargetType ~= nil then
            objInstance.moveTargetType = moveTargetType
        end
        component:CompleteChanges("Relocate aura area")
    end

    local auraid = component.properties:try_get("auraid")
    local casterid = component.properties:try_get("casterid")
    if auraid == nil or casterid == nil then
        return
    end

    local casterTok = dmhub.GetTokenById(casterid)
    if casterTok == nil or not casterTok.valid then
        return
    end

    casterTok:ModifyProperties {
        description = "Relocate aura area",
        undoable = false,
        execute = function()
            local inst = casterTok.properties:GetAura(auraid)
            if inst ~= nil then
                inst.area = newArea
                if moveTargetType ~= nil then
                    inst.moveTargetType = moveTargetType
                end
            end
        end,
    }
end

function ActivatedAbilityMoveAuraBehavior:Cast(ability, casterToken, targets, options)
    if options.targetArea == nil or self:try_get("object") == nil then
        return
    end

    local obj = game.LookupObject(self.object.floorid, self.object.objid)
    if obj == nil then
        return
    end

    dmhub.BeginTransaction()

    local destx = options.targetArea.xpos
    local desty = options.targetArea.ypos
    local dx = destx - obj.x
    local dy = desty - obj.y

    local objAura = obj:GetComponent("Aura")
    if objAura ~= nil then
        objAura:SetAndUploadProperties {
            moveTimestamp = dmhub.serverTime,
            movex = dx,
            movey = dy,
        }
    end

    obj:SetAndUploadPos(destx, desty)

    dmhub.EndTransaction()

    ActivatedAbilityMoveAuraBehavior.SetCasterAuraArea(obj, options.targetArea)

    ability:ConsumeResources(casterToken, {
        costOverride = options.costOverride,
    })
end

function CreateAuraTooltip(auraInstance)
    local aura = auraInstance.aura
    print("AURA:: SHOW AURA:", json(aura))

    return gui.Panel {
        styles = SpellRenderStyles,

        pad = 12,
        bgimage = true,
        bgcolor = "black",
        borderWidth = 2,
        borderColor = "white",
        width = 400,


        id = "spellInfo",
        gui.Label {
            id = "spellName",
            text = aura.name,
        },

        gui.Panel {
            classes = "divider",
        },

        gui.Panel {
            bgimage = aura.iconid,
            classes = "icon",
            selfStyle = aura.display,
        },

        gui.Label {
            text = aura:GetDescription(),
            classes = "description",
        },
    }
end


dmhub.CreateAuraComponent = function()
    return AuraComponent.new{
        aura = AuraInstance.new{
            guid = dmhub.GenerateGuid(),
            --iconid = ability.iconid,
            --display = ability.display,
            name = "Aura",
            area = dmhub.CalculateShape{
                --locOverride = core.Loc{x = 0, y = 0},
                shape = "cube",
                radius = 1,
                range = 1,
            },
            time = TimePoint.Create(),
            aura = Aura.Create{
                name = "Aura",
            },
        }
    }
end
