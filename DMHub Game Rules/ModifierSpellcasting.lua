local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('spellcasting', "Spellcasting")

CharacterModifier.TypeInfo.spellcasting = {
	init = function(modifier)
        modifier.leveling = "full" --matches Class.spellcastingLevelOptions
        modifier.customLevelingFormula = ""
        modifier.spellcasting = SpellcastingFeature.new{
        }

        --classid, is a unique identifier which is the 'type' of the spellcasting. Often an id of a class, but can
        --be anything from GameSystem.CalculateSpellcastingMethods()
        modifier.classid = "none"

        local classInfo = CharacterModifier.GuessClassOfSpellcasting(modifier)
        if classInfo ~= nil then
            modifier.classid = classInfo.id
            modifier.spellcasting.name = string.format("%s Spellcasting", classInfo.name)

            --try to initialize a spell list, preferring one which matches our classname.
            local key = nil
            local spellListTable = dmhub.GetTable(SpellList.tableName) or {}
            for k,v in pairs(spellListTable) do
                if key == nil or string.lower(v.name) == string.lower(classInfo.name) then
                    key = k
                end
            end

            if key ~= nil then
                modifier.spellcasting.spellLists = {key}
            end

        end
    end,

	modify = function(self, creature, attribute, currentValue)
        if attribute ~= "spellLevel" then
            return currentValue
        end

        if self:has_key("spellcastingLevel") then
            return self.spellcastingLevel
        end

        if self.classid == "none" or self.leveling == "custom" then
            return currentValue
        end

        --we have to count the number of spellcasting modifiers to see if this
        --is considered multiclass.
        local modifiers = creature:GetActiveModifiers()
        local spellcastingModifiers = 0

        for _,modifier in ipairs(modifiers) do
            if modifier.mod.behavior == "spellcasting" and modifier.mod.classid ~= "none" and modifier.mod.leveling ~= "custom" then
                spellcastingModifiers = spellcastingModifiers+1
            end
        end

        printf("MULTICLASS: %d", spellcastingModifiers)


        local classesEntries = creature:try_get("classes")
        if classesEntries == nil then
            return currentValue
        end

        for _,entry in ipairs(classesEntries) do
            if entry.classid == self.classid then
                local lvl = entry.level
                if self.leveling == "half" then
                    lvl = lvl/2
                elseif self.leveling == "third" then
                    lvl = lvl/3
                end

                if lvl < 1 then
                    return currentValue
                end

                if spellcastingModifiers <= 1 then
                    --monoclass
                    return currentValue + math.ceil(lvl)
                else
                    --multiclass
                    return currentValue + math.floor(lvl)
                end
            end
        end

        return currentValue
    end,

    spellcasting = function(modifier, creature, spellcastingEntries)
        local source = modifier.spellcasting
        local proficiencyBonus = creature:ProficiencyBonus()
        local attrBonus = creature:GetAttribute(source.attr):Modifier()
        local spellcastingFeature = SpellcastingFeature.new{
            id = modifier.classid,
            name = source.name,
            attr = source.attr,
            spellbook = source.spellbook,
            dc = creature:CalculateAttribute("spellsavedc", 8 + attrBonus + proficiencyBonus),
            attackBonus = creature:CalculateAttribute("spellattackmod", attrBonus + proficiencyBonus),
            refreshType = source.refreshType,

            spellLists = source.spellLists,
            grantedSpells = {},
            numKnownCantrips = ExecuteGoblinScript(source.numKnownCantrips, creature:LookupSymbol(), 0, "Spellcasting known cantrips"),
            numKnownSpells = ExecuteGoblinScript(source.numKnownSpells, creature:LookupSymbol(), 0, "Spellcasting known spells"),

            upcastingType = source.upcastingType,

            canUseSpellSlots = source.canUseSpellSlots,

        }

        if modifier.leveling == "custom" then
            spellcastingFeature.level = ExecuteGoblinScript(modifier:try_get("customLevelingFormula", ""), creature:LookupSymbol(), 0, "Custom spellcasting level")
            spellcastingFeature.maxSpellLevel = spellcastingFeature.level
        else
            spellcastingFeature.level = creature:SpellLevel()
            local spellSlots = GameSystem.spellSlotsTable[spellcastingFeature.level]
            if spellSlots == nil then
                spellcastingFeature.maxSpellLevel = 0
            else
                spellcastingFeature.maxSpellLevel = #spellSlots
            end
        end


        if source.spellbook then
            spellcastingFeature.spellbookSize = ExecuteGoblinScript(source.spellbookSize, creature:LookupSymbol(), 0, "Spellcasting spellbook size")
        end

        spellcastingEntries[#spellcastingEntries+1] = spellcastingFeature

    end,

	createEditor = function(modifier, element)

	    local ismonster = modifier:try_get("domains", {})["monster"]

        local spellListOptions = DeepCopy(SpellList.GetOptions())
        table.insert(spellListOptions, 1, {
            id = "none",
            text = "Choose Spell List...",
        })

        local classesTable = dmhub.GetTable("classes")
        local classOptions = GameSystem.CalculateSpellcastingMethods()

        table.sort(classOptions, function(a,b) return a.text < b.text end)

        local classNames = {}
        for _,option in ipairs(classOptions) do
            classNames[option.id] = option.text
        end


		local Refresh
		Refresh = function()
            local domains = {}

            local classInfo = classesTable[modifier.classid]
            local className = "Wizard"
            local classLevel = "Level"
            if classInfo ~= nil then
                className = classInfo.name
                classLevel = string.format("%s Level", className)

                domains[classInfo:Domain()] = true
                if classInfo:Subdomain() ~= nil then
                    domains[classInfo:Subdomain()] = true
                end
            end

            local children = {}

            if not ismonster then
                children[#children+1] = modifier:FilterConditionEditor()

                --class this pertains to.
                children[#children+1] = gui.Panel{
                    classes = {'formPanel'},
                    gui.Label{
                        classes = {"formLabel"},
                        text = 'Type:',
                        valign = 'center',
                        minWidth = 160,
                    },
                    gui.Dropdown{
                        textDefault = "Choose...",
                        options = classOptions,
                        idChosen = modifier.classid,
                        width = 200,
                        height = 40,
                        fontSize = 20,
                        change = function(element)
                            ---@cast element Dropdown
                            modifier.classid = element.idChosen

                            local classInfo = classesTable[modifier.classid]
                            if classInfo ~= nil then
                                modifier.spellcasting.name = string.format("%s Spellcasting", classInfo.name)
                            else
                                modifier.spellcasting.name = classNames[element.idChosen]
                            end

                            Refresh()
                        end,
                    },
                }
            end

            --spellcasting attribute
            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    classes = {"formLabel"},
                    text = 'Attribute:',
                    valign = 'center',
                    minWidth = 160,
                },
                gui.Dropdown{
                    options = creature.attributeDropdownOptions,
                    idChosen = modifier.spellcasting.attr,
                    width = 200,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.spellcasting.attr = element.idChosen
                    end,
                },
            }


            --spell list.
            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Spell List:",
                    valign = "center",
                    minWidth = 160,
                },
                gui.Dropdown{
                    options = spellListOptions,
                    idChosen = modifier.spellcasting.spellLists[1] or "none",
                    width = 200,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ---@cast element Dropdown
                        if element.idChosen == "none" then
                            modifier.spellcasting.spellLists = {}
                        else
                            modifier.spellcasting.spellLists = {element.idChosen}
                        end
                    end,
                }
            }

            --spellcasting leveling
            if ismonster then
                children[#children+1] = gui.Panel{
                    classes = {'formPanel'},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Spellcasting Level:",
                        valign = "center",
                        minWidth = 160,
                    },

                    gui.Input{
                        classes = {"formInput"},
                        halign = "left",
                        text = modifier:try_get("spellcastingLevel", 1),
                        change = function(element)
                            local num = math.floor(tonumber(element.text))
                            if num == nil then
                                num = modifier:try_get("spellcastingLevel", 1)
                            end
                            modifier.spellcastingLevel = num
                            element.text = tostring(num)
                        end,
                    }

                }

            else --character not monster.
                children[#children+1] = gui.Panel{
                    classes = {'formPanel'},
                    gui.Label{
                        classes = {"formLabel"},
                        text = 'Spell Leveling:',
                        valign = 'center',
                        minWidth = 160,
                    },
                    gui.Dropdown{
                        options = Class.spellcastingLevelOptions,
                        idChosen = modifier.leveling,
                        width = 200,
                        height = 40,
                        fontSize = 20,
                        change = function(element)
                            ---@cast element Dropdown
                            modifier.leveling = element.idChosen
                            Refresh()
                        end,
                    },
                }

                children[#children+1] = gui.Check{
                    value = modifier.spellcasting.canUseSpellSlots,
                    text = "Uses Spell Slots to Cast",
                    hover = gui.Tooltip("If the spellcasting feature doesn't use spell slots to cast, you will have to provide a Custom Spellcasting feature which specifies another way to cast spells."),
                    change = function(element)
                        modifier.spellcasting.canUseSpellSlots = element.value
                        Refresh()
                    end,
                }
            end

            --spellcasting level custom script for e.g. warlocks.
            if modifier.leveling == "custom" then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = 'Spell Level:',
                        valign = 'center',
                        minWidth = 160,
                    },
                    gui.GoblinScriptInput{
                        value = modifier.customLevelingFormula,
                        placeholderText = string.format("e.g. %s / 2", classLevel),
                        multiline = false,

                        displayTypes = {
                            {
                                id = "level",
                                text = string.format("Table by %s", classLevel),
                                value = GoblinScriptTable.new{
                                    id = "level",
                                    field = string.format("%s", classLevel),
                                    valueLabel = "Spell Level",
                                    entries = {
                                        {
                                            threshold = 1,
                                            script = "",
                                        }
                                    }
                                }
                            },

                        },

                        change = function(element)
                            modifier.customLevelingFormula = element.value
                        end,
                        documentation = {
                            domains = domains,
                            help = "This GoblinScript is used to determine the spellcasting level for this class's spells.",
                            output = "number",
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature that is using this class.",
                            examples = {
                                {
                                    script = string.format("%s / 2", classLevel),
                                    text = string.format("The spellcasting level will be equal to half of the character's %s.", classLevel),
                                },
                            },
                            symbols = {},
                        },
                    }

                }
            end


            --spellcasting preparation
            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    classes = {"formLabel"},
                    text = 'Preparation:',
                    valign = 'center',
                    minWidth = 160,
                },
                gui.Dropdown{
                    options = SpellcastingFeature.RefreshTypeOptions,
                    idChosen = modifier.spellcasting.refreshType,
                    width = 200,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.spellcasting.refreshType = element.idChosen
                        Refresh()
                    end,
                },
            }

            --upcasting
            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    classes = {"formLabel"},
                    text = 'Upcasting:',
                    valign = 'center',
                    minWidth = 160,
                },
                gui.Dropdown{
                    options = SpellcastingFeature.UpcastingOptions,
                    idChosen = modifier.spellcasting.upcastingType,
                    width = 200,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.spellcasting.upcastingType = element.idChosen
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",

                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = 'Cantrips Known:',
                        valign = 'center',
                        minWidth = 160,
                    },
                    gui.GoblinScriptInput{
                        value = modifier.spellcasting.numKnownCantrips,
                        placeholderText = string.format("e.g. %s / 2", classLevel),
                        multiline = false,
                        change = function(element)
                            modifier.spellcasting.numKnownCantrips = element.value
                        end,

                        fieldName = "Cantrips Known",

                        displayTypes = {
                            {
                                id = "level",
                                text = string.format("Table by %s", classLevel),
                                value = GoblinScriptTable.new{
                                    id = "level",
                                    field = string.format("%s", classLevel),
                                    entries = {
                                        {
                                            threshold = 1,
                                            script = "",
                                        }
                                    }
                                }
                            },
                        },


                        documentation = {
                            domains = domains,
                            help = "This GoblinScript is used to determine the number of cantrips known for this class's spells.",
                            output = "number",
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature that is using this class.",
                            examples = {
                                {
                                    script = string.format("%s / 2", classLevel),
                                    text = string.format("The cantrips known will be equal to half of the character's %s.", classLevel),
                                },
                            },
                            symbols = {},
                        },
                    }
                },

                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = string.format('Spells %s:', string.upper_first(modifier.spellcasting.refreshType)),
                        valign = 'center',
                        minWidth = 160,
                    },
                    gui.GoblinScriptInput{
                        value = modifier.spellcasting.numKnownSpells,
                        placeholderText = string.format("e.g. %s / 2", classLevel),
                        multiline = false,
                        change = function(element)
                            modifier.spellcasting.numKnownSpells = element.value
                        end,

                        fieldName = string.format("Spells %s", string.upper_first(modifier.spellcasting.refreshType)),

                        displayTypes = {
                            {
                                id = "level",
                                text = string.format("Table by %s", classLevel),
                                value = GoblinScriptTable.new{
                                    id = "level",
                                    field = string.format("%s", classLevel),
                                    entries = {
                                        {
                                            threshold = 1,
                                            script = "",
                                        }
                                    }
                                }
                            },
                        },


                        documentation = {
                            domains = domains,
                            help = "This GoblinScript is used to determine the number of spells known for this class's spells.",
                            output = "number",
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature that is using this class.",
                            examples = {
                                {
                                    script = string.format("%s / 2", classLevel),
                                    text = string.format("The cantrips known will be equal to half of the character's %s.", classLevel),
                                },
                            },
                            symbols = {},
                        },
                    }
                },

            }

            children[#children+1] = gui.Check{
                text = "Ritual Casting",
                value = modifier.spellcasting.ritualCasting,
                change = function(element)
                    modifier.spellcasting.ritualCasting = element.value
                    Refresh()
                end,
            }

            children[#children+1] = gui.Check{
                text = "Has Spellbook",
                value = modifier.spellcasting.spellbook,
                change = function(element)
                    modifier.spellcasting.spellbook = element.value
                    Refresh()
                end,
            }

            --goblin script for size of spellbook.
            if modifier.spellcasting.spellbook then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = 'Spellbook Entries:',
                        valign = 'center',
                        minWidth = 160,
                    },
                    gui.GoblinScriptInput{
                        value = modifier.spellcasting.spellbookSize,
                        placeholderText = string.format("e.g. %s / 2", classLevel),
                        multiline = false,
                        change = function(element)
                            modifier.spellcasting.spellbookSize = element.value
                        end,

                        fieldName = "Spellbook Entries",

                        displayTypes = {
                            {
                                id = "level",
                                text = string.format("Table by %s", classLevel),
                                value = GoblinScriptTable.new{
                                    id = "level",
                                    field = string.format("%s", classLevel),
                                    entries = {
                                        {
                                            threshold = 1,
                                            script = "",
                                        }
                                    }
                                }
                            },
                        },


                        documentation = {
                            domains = domains,
                            help = "This GoblinScript is used to determine the number of entries in this class's spellbook.",
                            output = "number",
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature that is using this class.",
                            examples = {
                                {
                                    script = string.format("%s / 2", classLevel),
                                    text = string.format("The number of spell book entries will be equal to half of the character's %s.", classLevel),
                                },
                            },
                            symbols = {},
                        },
                    }
                }
            end

            element.children = children
        end

        Refresh()
    end,

}

function CharacterModifier.CreateMonsterSpellcastingModifier()
    local result = CharacterModifier.new{
        behavior = 'spellcasting',
        guid = dmhub.GenerateGuid(),
        name = "Monster Spellcasting",
        source = "Monster Spellcasting",
        description = "",
        spellcastingLevel = 1,
    }

    result:SetDomain("monster")

    CharacterModifier.TypeInfo.spellcasting.init(result)
    result.classid = "monster"
    return result

end


function CharacterModifier:AccumulateSpellcastingFeatures(creature, spellcastingFeatures)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.spellcasting ~= nil then
		typeInfo.spellcasting(self, creature, spellcastingFeatures)
    end
end
