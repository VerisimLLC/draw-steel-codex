local mod = dmhub.GetModLoading()

--- @class Aura:CharacterFeature
--- @field objectid string Id of the object placed to represent this aura ("none" if unset).
--- @field iconid string Icon asset path.
--- @field canrelocate boolean If true, the caster can spend an action to move the aura.
--- @field relocateResource string Action resource id used to relocate the aura.
--- @field relocateRange number Maximum range in world units for relocating the aura.
--- @field triggers table[] List of trigger definitions {trigger: string, ability: TriggeredAbility, destroyaura: boolean}.
--- @field name string Display name.
--- @field source string Source description string.
--- @field description string Rules text.
--- @field applyto string Target filter id: "all", "allother", "selfandfriends", "friends", "enemies", "sametype", "othertype".
--- @field creatureFilter nil|string|number|table GoblinScript filter evaluated against each creature to determine whether it is affected.
--- @field modifiers CharacterModifier[] Modifiers applied to creatures inside the aura.
--- @field subauras nil|Aura[] Optional child aura payloads. Each shares this aura's area, caster,
--- duration, and removal, but has its own applyto/creatureFilter/modifiers/triggers/terrain flags/
--- move damage. Child defs never use objectid, icon/display, relocate fields, or nested subauras.
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

    local result = ExecuteGoblinScript(self.creatureFilter, c:LookupSymbol { caster = caster, target = c, aura = auraInstance },
        "Aura Creature Filter")
    return GoblinScriptTrue(result)
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
                    if element.idChosen == "casterendturnaura" then
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


        resultAbilities[#resultAbilities + 1] = ActivatedAbility.Create {
            name = string.format("Move %s", self.name),
            auraid = self.guid,
            iconid = self.iconid,
            casterLocOverride = self.area.origin,
            display = self.display,
            targetType = area.shape,
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

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityAuraBehavior:Cast(ability, casterToken, targets, options)
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
        local auraInstance = AuraInstance.new {
            guid = guid,
            spellcastingFeature = ability:try_get("spellcastingFeature"),
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
            aura = DeepCopy(self.aura),
        }

        if auraInstance.duration == "endnextturn" then
            local q = dmhub.initiativeQueue
            if q ~= nil and q.hidden == false then
                auraInstance.durationRound = q.round + 1
            end

            auraInstance.duration = "endturn"
        end

        print("AURA:: CREATED")

        --If the ability's area is a cube, give the aura a matching finite height (in
        --tiles) so it only affects creatures within the cube's vertical extent rather
        --than extending to infinite height. auraHeight of 0 leaves it unlimited, which
        --is the correct behavior for flat shapes (bursts, cones, lines, etc).
        local auraHeight = 0
        if targetArea ~= nil and targetArea.shape == "Cube" then
            auraHeight = targetArea.radius
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

function creature:CheckAuraExpiration(eventname)
    local auras = self:try_get("auras", {})
    local removes = nil

    if eventname == "endturn" then
        --check for end turn events on auras.
        for i, aura in ipairs(auras) do
            for j, trigger in ipairs(aura.aura.triggers) do
                if trigger.trigger == "casterendturnaura" then
                    local auraCasterToken = dmhub.LookupToken(self)
                    aura:FireTriggeredAbility(trigger.ability, self, auraCasterToken, { aura = aura })
                end
            end

            --sub-auras carry their own triggers; fire them through the child view so the
            --trigger sees the child's payload while sharing the parent's caster/area.
            for _, child in ipairs(aura:GetChildInstances()) do
                for _, trigger in ipairs(child.aura:try_get("triggers", {})) do
                    if trigger.trigger == "casterendturnaura" then
                        local auraCasterToken = dmhub.LookupToken(self)
                        child:FireTriggeredAbility(trigger.ability, self, auraCasterToken, { aura = child })
                    end
                end
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

    local objAura = obj:GetComponent("Aura")
    if objAura ~= nil then
        objAura:SetAndUploadProperties {
            moveTimestamp = dmhub.serverTime,
            movex = destx - obj.x,
            movey = desty - obj.y,
        }
    end

    obj:SetAndUploadPos(destx, desty)

    dmhub.EndTransaction()

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
--=============================================================================
-- Directional lane aura objects (e.g. Time Raider Helix's Kinetic Lane).
--
-- A map object carrying an Aura component whose Aura DEFINITION has
-- directionalLane = true is treated as a "lane": a straight strip of squares,
-- laneLength long and 1 wide, anchored on the object's square and extending
-- in the direction the object is rotated to face (quantized to the 8 compass
-- directions, 45 degree steps). Any token that ENTERS the lane is
-- automatically force-slid laneSlideDistance squares in the lane's direction,
-- with no prompt.
--
-- The engine does not translate or rotate an object-attached aura's area when
-- the object moves, and it never fires aura enter triggers for area-anchored
-- auras (only token-attached radius auras are tracked; verified empirically).
-- So both halves are driven from Lua by a watcher that runs on the DM's
-- client only (single writer):
--   1. Sync: whenever a lane object's position or rotation changes, the
--      watcher rewrites its aura area to the matching list of squares. The
--      aura's displayOutline then renders the player-visible outline in the
--      right place. Freshly placed copies of the asset also get a unique
--      aura guid stamped (placement clones the asset's components verbatim,
--      so every copy starts with the same guid).
--   2. Enter detection: the watcher tracks which tokens stand in each lane.
--      A token that shows up in the lane's squares without having been there
--      the previous tick has entered, and gets slid.
--
-- Aura definition fields:
--   directionalLane (boolean) - marks the aura as a lane.
--   laneLength (number) - length of the lane in squares. Default 4.
--   laneWidth (number) - width of the lane in squares. Default 1.
--   laneSlideDistance (number) - squares to slide entering tokens. Default 3.
--
-- A lane can also be placed by an ability (create_lane_object behavior below):
-- the behavior stamps the aura's area with the EXACT squares of the targeted
-- line and records the object transform it was stamped at (laneSyncX/Y/Rot).
-- The watcher leaves a stamped area alone until the object is moved or
-- rotated, at which point it recomputes the lane from the object transform.
--=============================================================================

Aura.laneLength = 4
Aura.laneWidth = 1
Aura.laneSlideDistance = 3

--Compass directions for rotation quantized to 45 degree steps. Unity rotates
--counterclockwise for positive angles, with rotation 0 facing north (+y).
--Index is round(rotation/45) % 8.
local g_laneDirections = {
    [0] = {x = 0, y = 1},
    [1] = {x = -1, y = 1},
    [2] = {x = -1, y = 0},
    [3] = {x = -1, y = -1},
    [4] = {x = 0, y = -1},
    [5] = {x = 1, y = -1},
    [6] = {x = 1, y = 0},
    [7] = {x = 1, y = 1},
}

--- Quantize an object rotation (degrees) to one of the 8 compass directions.
--- @param rotation number
--- @return {x: number, y: number}
local function LaneDirectionFromRotation(rotation)
    local index = math.floor((rotation or 0)/45 + 0.5) % 8
    if index < 0 then
        index = index + 8
    end
    return g_laneDirections[index]
end

--- Compute the list of squares a lane object should cover. Extra width rows
--- are laid perpendicular to the lane direction (to its right side).
--- @param obj LuaObjectInstance
--- @param laneLength number
--- @param laneWidth number
--- @return Loc[], {x: number, y: number}
local function ComputeLaneLocs(obj, laneLength, laneWidth)
    local dir = LaneDirectionFromRotation(obj.rotation)
    local perp = {x = dir.y, y = -dir.x}
    local anchor = core.Loc{
        x = math.floor(obj.x + 0.5),
        y = math.floor(obj.y + 0.5),
        floorIndex = obj.floorIndex,
    }
    local locs = {}
    for i = 0, laneLength-1 do
        for w = 0, laneWidth-1 do
            locs[#locs+1] = anchor:dir(dir.x*i + perp.x*w, dir.y*i + perp.y*w)
        end
    end
    return locs, dir
end

--Float compare tolerant of serialization round-trips, so the watcher does not
--endlessly rewrite an area because a stored coordinate came back a hair off.
local function LaneNear(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) < 0.001
end

--Transient watcher state, keyed by "floorid/objid". Lives only on the DM's
--client; rebuilt from live positions every tick, so nothing here needs to
--survive a reload.
local g_laneStates = {}

--Tokens currently mid-slide (tokenid -> true). Global across lanes so a
--token being animated by one lane is not re-processed by another until it
--lands.
local g_slidingTokens = {}

--Safety valve against ping-pong loops between facing lanes: recent slide
--timestamps per token. A token slid 3+ times in the last 10 seconds is left
--alone until the window clears.
local g_slideHistory = {}

local function TokenMaySlide(tokenid)
    local now = dmhub.Time()
    local history = g_slideHistory[tokenid] or {}
    local recent = {}
    for _,t in ipairs(history) do
        if now - t < 10 then
            recent[#recent+1] = t
        end
    end
    g_slideHistory[tokenid] = recent
    return #recent < 3
end

--- Force-slide a token dist squares in the given direction, with collision
--- events, mirroring the straightline "move" branch of
--- ActivatedAbilityRelocateCreatureBehavior:Cast.
--- @param tok CharacterToken
--- @param dir {x: number, y: number}
--- @param dist number
--- @param state table The lane's watcher state entry.
local function SlideLaneToken(tok, dir, dist, state)
    g_slidingTokens[tok.id] = true
    local history = g_slideHistory[tok.id] or {}
    history[#history+1] = dmhub.Time()
    g_slideHistory[tok.id] = history

    dmhub.Coroutine(function()
        local ok, err = pcall(function()
            local destLoc = tok.loc:dir(dir.x*dist, dir.y*dist)

            --GetForcedPushOptions is defined by the Draw Steel rules layer;
            --guard with pcall so this generic-layer code still works if a
            --game system does not define it.
            local forcedPushOptions = { rebound = false, maxBounces = 0 }
            pcall(function()
                forcedPushOptions = tok.properties:GetForcedPushOptions()
            end)

            --Measure the slide first so we know whether it collides and with
            --what, then perform the actual move.
            local collisionInfo = nil
            local movementInfo = tok:MarkMovementArrow(destLoc, {
                straightline = true,
                forcedMovementDistance = dist,
                rebound = forcedPushOptions.rebound,
                maxBounces = forcedPushOptions.maxBounces,
            })
            if movementInfo ~= nil then
                local path = movementInfo.path
                local requestDist = math.min(destLoc:DistanceInTiles(path.origin), dist)
                local freeMovement = path.freeMovementSteps
                if path.hasCollision and requestDist < dist then
                    requestDist = dist
                end
                local hasCollision = freeMovement < requestDist
                local collisionSpeed = requestDist - freeMovement

                --The engine reports the true force remaining at the moment of
                --collision (see the same logic in AbilityRelocateCreature).
                local collisionForce = path.collisionForce
                if collisionForce ~= nil then
                    if collisionForce >= 0 then
                        hasCollision = true
                        collisionSpeed = collisionForce
                    elseif not path.hasCollision then
                        hasCollision = false
                        collisionSpeed = 0
                    end
                end

                if hasCollision then
                    collisionInfo = {
                        speed = collisionSpeed,
                        collideWith = movementInfo.collideWith,
                    }
                end
            end
            tok:ClearMovementArrow()

            local path = tok:Move(destLoc, {
                straightline = true,
                maxCost = 30000,
                movementType = "move",
                forcedMovementDistance = dist,
                rebound = forcedPushOptions.rebound,
                maxBounces = forcedPushOptions.maxBounces,
            })

            --filter out passthrough creatures from collision.
            if collisionInfo ~= nil and collisionInfo.collideWith ~= nil and #collisionInfo.collideWith > 0 then
                local filtered = {}
                for _,other in ipairs(collisionInfo.collideWith) do
                    if other.properties:CalculateNamedCustomAttribute("Passthrough") == 0 then
                        filtered[#filtered+1] = other
                    end
                end
                collisionInfo.collideWith = filtered
                if #filtered == 0 then
                    collisionInfo = nil
                end
            end

            local withobject = false
            if collisionInfo ~= nil then
                withobject = #(collisionInfo.collideWith or {}) == 0
                if not withobject then
                    for _,other in ipairs(collisionInfo.collideWith or {}) do
                        if other.isObject then
                            withobject = true
                            break
                        end
                    end
                end
            end

            --Let "when force moved" triggered abilities react to the slide.
            tok.properties:DispatchEvent("forcemove", {
                hasattacker = false,
                type = "slide",
                vertical = false,
                collision = (collisionInfo ~= nil) and collisionInfo.speed or 0,
                collidewithobject = withobject,
                distance = math.floor((path ~= nil and path.numSteps) or 0),
                melee = false,
            })

            if collisionInfo ~= nil then
                if tok.properties:CalculateNamedCustomAttribute("No Damage From Forced Movement") == 0 then
                    tok.properties:TriggerEvent("collide", {
                        speed = collisionInfo.speed,
                        withobject = withobject,
                        withcreature = not withobject,
                        haspusher = false,
                        movementtype = "slide",
                    })
                end

                for _,other in ipairs(collisionInfo.collideWith or {}) do
                    other.properties:TriggerEvent("collide", {
                        speed = collisionInfo.speed,
                        withobject = withobject,
                        withcreature = not withobject,
                        haspusher = false,
                        movementtype = "slide",
                    })
                end
            end
        end)

        if not ok then
            printf("LANE:: error sliding token: %s", tostring(err))
        end

        g_slidingTokens[tok.id] = nil

        --Mark the token as inside so the landing position does not read as a
        --fresh entry on the next tick. The tick after that recomputes true
        --membership from live positions.
        if tok.valid then
            state.insideTokens[tok.id] = true
        end
    end)
end

--- Process one lane object: sync its aura area to the object transform,
--- slide any tokens that entered since the previous tick, and when a new
--- initiative turn just started (turnStartInitiativeId not nil) slide tokens
--- inside the lane whose turn it now is.
--- @param obj LuaObjectInstance
--- @param comp LuaObjectComponentAura
--- @param turnStartInitiativeId nil|string
local function ProcessLaneObject(obj, comp, turnStartInitiativeId)
    local inst = comp.properties.aura
    local auraDef = inst.aura

    local laneLength = tonumber(auraDef:try_get("laneLength", Aura.laneLength)) or Aura.laneLength
    local laneWidth = tonumber(auraDef:try_get("laneWidth", Aura.laneWidth)) or Aura.laneWidth
    local slideDist = tonumber(auraDef:try_get("laneSlideDistance", Aura.laneSlideDistance)) or Aura.laneSlideDistance

    --If the aura's area was stamped at the object's current transform (either
    --by us on a previous tick or by the create_lane_object behavior placing
    --the exact squares of a targeted line), leave it untouched. Otherwise the
    --object was newly placed, moved, or rotated: recompute the lane from the
    --object transform.
    local locs
    local dir
    local stamped = inst:try_get("laneObjId") == obj.objid
        and LaneNear(inst:try_get("laneSyncX"), obj.x)
        and LaneNear(inst:try_get("laneSyncY"), obj.y)
        and LaneNear(inst:try_get("laneSyncRot"), obj.rotation)
        and inst:try_get("area") ~= nil

    if stamped then
        locs = inst.area.locations or {}
        local storedDir = inst:try_get("laneDirection")
        if storedDir ~= nil and storedDir.x ~= nil then
            dir = {x = storedDir.x, y = storedDir.y}
        else
            dir = LaneDirectionFromRotation(obj.rotation)
        end
    else
        locs, dir = ComputeLaneLocs(obj, laneLength, laneWidth)
        comp:BeginChanges()
        if inst:try_get("laneObjId") ~= obj.objid then
            --Newly placed (or copied) lane: placement clones the asset's
            --components verbatim, so stamp a unique guid.
            inst.guid = dmhub.GenerateGuid()
            inst.laneObjId = obj.objid
        end
        inst.laneDirection = {x = dir.x, y = dir.y}
        inst.laneSyncX = obj.x
        inst.laneSyncY = obj.y
        inst.laneSyncRot = obj.rotation
        inst.area = dmhub.CalculateShape{
            shape = "locations",
            locOverride = locs[1],
            targetPoint = core.Vector3(locs[1].x + 0.5, locs[1].y + 0.5, 0),
            range = (laneLength + laneWidth)*2,
            radius = 0,
            checklos = false,
            locations = locs,
        }
        comp:CompleteChanges("Sync lane area")
    end

    --Entry detection.
    local key = obj.floorid .. "/" .. obj.objid
    local state = g_laneStates[key]
    if state == nil then
        state = { insideTokens = nil }
        g_laneStates[key] = state
    end

    local inside = {}
    for _,loc in ipairs(locs) do
        for _,tok in ipairs(game.GetTokensAtLoc(loc) or {}) do
            if tok.valid and (not tok.isObject) then
                inside[tok.id] = tok
            end
        end
    end

    local prev = state.insideTokens
    state.insideTokens = {}
    for id,_ in pairs(inside) do
        state.insideTokens[id] = true
    end

    --On the very first tick for this lane (including right after a reload)
    --just record membership without sliding anyone.
    if prev == nil then
        return
    end

    for id,tok in pairs(inside) do
        if g_slidingTokens[id] then
            --Mid-animation states are not entries; keep the previous
            --membership for this token.
            state.insideTokens[id] = prev[id] or nil
        elseif not prev[id] then
            if tok.properties ~= nil and (not tok.properties:IsDead()) and TokenMaySlide(id) then
                SlideLaneToken(tok, dir, slideDist, state)
            end
        end
    end

    --"Starts their turn there": when a new turn just began, slide tokens
    --standing in the lane whose initiative entry now has the turn.
    if turnStartInitiativeId ~= nil then
        for id,tok in pairs(inside) do
            if (not g_slidingTokens[id]) and tok.properties ~= nil and (not tok.properties:IsDead()) then
                local ok, initid = pcall(function() return InitiativeQueue.GetInitiativeId(tok) end)
                if ok and initid == turnStartInitiativeId and TokenMaySlide(id) then
                    SlideLaneToken(tok, dir, slideDist, state)
                end
            end
        end
    end
end

local LANE_THINK_INTERVAL = 0.25

--Last initiative turn id seen by the watcher, for start-of-turn slides.
local g_laneLastTurnId = nil

local function LaneThink()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(LANE_THINK_INTERVAL, LaneThink)

    if not dmhub.isDM then
        return
    end

    local map = game.currentMap
    if map == nil then
        return
    end

    local ok, err = pcall(function()
        --Detect the start of a new initiative turn. On the tick where the
        --turn changes, pass the initiative id whose turn began so lanes can
        --slide tokens that start their turn standing in them. The first
        --observation after a reload (or when initiative is hidden) only
        --records state.
        local turnStartInitiativeId = nil
        local q = dmhub.initiativeQueue
        if q ~= nil and q.hidden == false then
            local turnid = q:GetTurnId()
            if turnid ~= g_laneLastTurnId then
                local firstObservation = (g_laneLastTurnId == nil)
                g_laneLastTurnId = turnid
                if not firstObservation then
                    turnStartInitiativeId = q:CurrentInitiativeId()
                end
            end
        else
            g_laneLastTurnId = nil
        end

        for _,floor in ipairs(map.floors or {}) do
            --floor.objects can be transiently nil for floors that are not
            --currently loaded, and the objects getter itself raises on a
            --floor that is tearing down, so gate on floor.valid first.
            for _,obj in pairs((floor.valid and floor.objects) or {}) do
                local comp = obj:GetComponent("Aura")
                if comp ~= nil and comp.properties ~= nil and comp.properties:has_key("aura") then
                    local inst = comp.properties.aura
                    if inst:has_key("aura") and inst.aura:try_get("directionalLane", false) then
                        ProcessLaneObject(obj, comp, turnStartInitiativeId)
                    end
                end
            end
        end
    end)

    if not ok then
        printf("LANE:: watcher error: %s", tostring(err))
    end
end

dmhub.Schedule(LANE_THINK_INTERVAL, LaneThink)

--Internal lane API for later-loading files. This file loads BEFORE
--ActivatedAbility.lua, so the create_lane_object ability behavior cannot be
--registered here; it lives in Draw Steel Ability Behaviors/AbilityCreateObject.lua
--and reaches the lane internals through this table.
Aura.laneInternal = {
    directions = g_laneDirections,
    SlideToken = SlideLaneToken,
    TokenMaySlide = TokenMaySlide,
    GetOrCreateLaneState = function(key)
        local state = g_laneStates[key]
        if state == nil then
            state = { insideTokens = {} }
            g_laneStates[key] = state
        end
        state.insideTokens = state.insideTokens or {}
        return state
    end,
}