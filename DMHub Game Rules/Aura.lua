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
--- @field creatureFilter string GoblinScript filter evaluated against each creature to determine whether it is affected.
--- @field modifiers CharacterModifier[] Modifiers applied to creatures inside the aura.
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
Aura.iconid = "ui-icons/skills/1.png"
Aura.canrelocate = false
Aura.relocateResource = "standardAction"
Aura.relocateRange = 30
Aura.triggers = {}
Aura.name = "Aura"
Aura.source = "Aura"
Aura.description = ""
Aura.applyto = "all"

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

    local casterToken = dmhub.GetTokenById(auraInstance.casterid)
    local caster = nil
    if casterToken ~= nil and casterToken.properties ~= nil then
        caster = casterToken.properties
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
                        gui.DeleteItemButton {
                            width = 16,
                            height = 16,
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
                        text = "Destroy Aura After Trigger",
                        value = (trigger.destroyaura or false),
                        change = function(element)
                            trigger.destroyaura = element.value
                            resultPanel:FireEventTree("refreshAura")
                        end,
                    },

                    trigger.ability:GenerateEditor {
                        --the triggers don't have a trigger condition set because that is implied
                        --by the way the creature interacts with the aura. They don't have activation
                        --saving throws either, since that is for 'good' triggers to see if they are activated.
                        --The normal saving throws are controlled by the behavior which will be added to the trigger.
                        excludeTriggerCondition = true,
                        excludeActivationSavingThrows = true,
                        excludeAppearance = true,
                    }
                }
            end

            abilityChildren[#abilityChildren + 1] = gui.Dropdown {
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

            ActivatedAbility.IconEditorPanel(self),

            gui.Panel {
                classes = "formPanel",
                gui.Label {
                    classes = "formLabel",
                    text = "Object:",
                },
                gui.Dropdown {
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

            gui.Check{
                halign = "left",
                text = "Avoid Damage When Shifting",
                value = self:try_get("shiftAvoidsDamage", false),
                change = function(element)
                    self.shiftAvoidsDamage = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
                create = function(element)
                    element:FireEvent("refreshAura")
                end,
                refreshAura = function(element)
                    element:SetClass("collapsed", self:try_get("movedamage", "none") == "none")
                end,
            },

            gui.SetEditor {
                halign = "left",
                value = self:try_get("flags"),
                addItemText = "Add Flag...",
                options = Aura.Flags,

                change = function(element, val)
                    self.flags = val
                end,
            },

            gui.Check {
                halign = "left",
                text = "Offers Concealment",
                value = self:try_get("concealment", false),
                change = function(element)
                    self.concealment = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                halign = "left",
                text = "Makes Terrain Difficult",
                value = self:try_get("difficult_terrain", false),
                change = function(element)
                    self.difficult_terrain = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
                halign = "left",
                text = "Blocks Line of Effect",
                value = self:try_get("blocks_line_of_effect", false),
                change = function(element)
                    self.blocks_line_of_effect = element.value
                    resultPanel:FireEventTree("refreshAura")
                end,
            },

            gui.Check {
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
                fontSize = '60%',
                vmargin = 0,
            },

            children = {
                gui.PrettyButton {
                    text = 'Close',
                    style = {
                        height = 60,
                        width = 160,
                        fontSize = 44,
                        bgcolor = 'white',
                    },
                    events = {
                        click = function(element)
                            resultPanel.data.close()
                        end,
                    },
                },
            },
        }

    local titleLabel = gui.Label {
        text = "Edit Aura",
        valign = 'top',
        halign = 'center',
        width = 'auto',
        height = 'auto',
        color = 'white',
        fontSize = 28,
    }

    resultPanel = gui.Panel {
        style = {
            bgcolor = 'white',
            width = dialogWidth,
            height = dialogHeight,
            halign = 'center',
            valign = 'center',
        },

        classes = { "framedPanel" },
        styles = Styles.Panel,

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
    local result = DeepCopy(self.symbols or {})
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

function AuraInstance:GetDamageInfo()
    local movedamage = self.aura:try_get("movedamage", "none")
    if movedamage == "none" then
        return nil
    end

    local result = {
        damage = self.aura:try_get("damage", 0),
        type = movedamage,
    }

    if self.aura:try_get("shiftAvoidsDamage", false) then
        result.shiftAvoidsDamage = true
    end

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
    if options.targetArea ~= nil then
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
                if persistence ~= nil and persistence.enabled and obj ~= nil then
                    local persistenceInfo = casterToken.properties:MostRecentPersistentAbility()
                    local objects = persistenceInfo:get_or_add("objects", {})
                    objects[#objects + 1] = {
                        floorid = obj.floorid,
                        objid = obj.objid,
                    }
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
        end
    end


    for i = #auras, 1, -1 do
        if auras[i].duration == eventname then
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

    local targetLoc = options.targetArea.origin

    dmhub.BeginTransaction()

    local destx = targetLoc.x - 0.5
    local desty = targetLoc.y - 0.5

    local objAura = obj:GetComponent("Aura")
    if objAura ~= nil then
        objAura:SetAndUploadProperties {
            moveTimestamp = dmhub.serverTime,
            movex = destx - obj.x,
            movey = desty - obj.y,
        }
    end

    obj:SetAndUploadPos(targetLoc.x - 0.5, targetLoc.y - 0.5)

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
        bgimage = "panels/square.png",
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