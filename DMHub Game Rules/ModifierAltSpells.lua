local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('altspells', "Custom Spellcasting")

CharacterModifier.TypeInfo.altspells = {
    init = function(modifier)
        modifier.resourceType = "none"
        modifier.spellList = "all"
        modifier.maxLevel = "1"
        modifier.costFormula = "1"
        modifier.methodid = "all" --method/class of the spellcasting feature that this applies to.
    end,

    altSpellcasting = function(self, creature, spell, resultTable)
        if self.resourceType == "none" then
            return
        end

        if self:has_key("methodid") and spell:has_key("spellcastingFeature") and self.methodid ~= "all" and self.methodid ~= spell.spellcastingFeature.id then
            return
        end

        if self.spellList ~= "all" then
            local spellListTable = dmhub.GetTable(SpellList.tableName) or {}
            --check that this spell is in the spell list.
            if spellListTable[self.spellList] == nil or (not spellListTable[self.spellList].spells[spell.id]) then
                return
            end
        end

        local maxLevel = ExecuteGoblinScript(self.maxLevel, creature:LookupSymbol(), 10, "Maximum level alternate spells")
        if spell.level > maxLevel then
            return
        end

        local cost = ExecuteGoblinScript(self.costFormula, creature:LookupSymbol{ spelllevel = spell.level, spell = GenerateSymbols(spell) }, 1, "Alternative spell cost")
        cost = max(cost, 1)


        resultTable[#resultTable+1] = {
            resourceid = self.resourceType,
            quantity = cost,
            level = spell.level,
            upcast = 0,
        }

        --now see about upcasting.
        for i=spell.level+1,min(GameSystem.maxSpellLevel, maxLevel) do
            cost = ExecuteGoblinScript(self.costFormula, creature:LookupSymbol{ spelllevel = i, spell = GenerateSymbols(spell) }, 1, "Alternative spell cost")
            cost = max(cost, 1)

            resultTable[#resultTable+1] = {
                resourceid = self.resourceType,
                quantity = cost,
                level = i,
                upcast = i - spell.level,
            }
        end
    end,

	createEditor = function(modifier, element)

        local domains = {}

        local spellListOptions = DeepCopy(SpellList.GetOptions())
        table.insert(spellListOptions, 1, {
            id = "all",
            text = "All Spells",
        })

		local resourceChoices = {}

        if modifier.resourceType == "none" then
            resourceChoices[#resourceChoices+1] =
			{
				id = 'none',
				text = 'Choose Resource...',
			}
        end

		local resourceTable = dmhub.GetTable("characterResources") or {}
		for k,v in pairs(resourceTable) do
			if (not v:try_get("hidden")) and (v.levelsFrom == "none" and v.spellSlot == "none") then
				resourceChoices[#resourceChoices+1] = {
					id = k,
					text = v.name,
				}
			end
		end

        table.sort(resourceChoices, function(a,b) return a.text < b.text end)


		local Refresh
		Refresh = function()
            local children = {}

            --spell method.
            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Type:",
                    valign = "center",
                    minWidth = 160,
                },
                gui.Dropdown{
                    options = CharacterModifier.GetSpellcastingClassOptions(),
                    idChosen = modifier:try_get("methodid"),
                    width = 280,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.methodid = element.idChosen
                    end,
                }
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
                    idChosen = modifier.spellList,
                    width = 280,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.spellList = element.idChosen
                    end,
                }
            }

            --resource type used to cast the spell.
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Resource:',
						classes = {'formLabel'},
                        minWidth = 160,
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 280,
							fontSize = 16,
						},
						options = resourceChoices,
						idChosen = modifier.resourceType,

						events = {
							change = function(element)
								---@cast element Dropdown
								modifier.resourceType = element.idChosen
								Refresh()
							end,
						},
					},
				}
			}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = 'Max Spell Level:',
                    valign = 'center',
                    minWidth = 160,
                },
                gui.GoblinScriptInput{
                    value = modifier.maxLevel,
                    placeholderText = "e.g. Level * 2",
                    multiline = false,

                    change = function(element)
                        modifier.maxLevel = element.value
                    end,
                    documentation = {
                        domains = domains,
                        help = "This GoblinScript is used to determine the maximum level spell that can be cast using this feature.",
                        output = "number",
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature that is casting spells.",
                        examples = {
                            {
                                script = "Level / 2",
                                text = "The maximum level spell that can be cast using this feature is equal to half the character's level.",
                            },
                        },
                        symbols = {},
                    },
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = 'Resources Used',
                    valign = 'center',
                    minWidth = 160,
                },
                gui.GoblinScriptInput{
                    value = modifier.costFormula,
                    placeholderText = "e.g. Spell Level * 2",
                    multiline = false,

                    change = function(element)
                        modifier.costFormula = element.value
                    end,

                    displayTypes = {
                        {
                            id = "spelllevel",
                            text = "Table by Spell Level",
                            value = GoblinScriptTable.new{
                                id = "spelllevel",
                                field = "SpellLevel",
                                valueLabel = "Spell Level",
                                entries = {
                                    {
                                        threshold = 1,
                                        script = "1",
                                    },
                                    {
                                        threshold = 2,
                                        script = "2",
                                    },
                                    {
                                        threshold = 3,
                                        script = "3",
                                    },
                                    {
                                        threshold = 4,
                                        script = "4",
                                    },
                                    {
                                        threshold = 5,
                                        script = "5",
                                    },
                                    {
                                        threshold = 6,
                                        script = "6",
                                    },
                                    {
                                        threshold = 7,
                                        script = "7",
                                    },
                                    {
                                        threshold = 8,
                                        script = "8",
                                    },
                                    {
                                        threshold = 9,
                                        script = "9",
                                    },
                                }
                            }
                        },

                    },



                    documentation = {
                        domains = domains,
                        help = "This GoblinScript is used to determine the number of resources consumed when a spell is cast using this feature.",
                        output = "number",
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature that is casting spells.",
                        examples = {
                            {
                                script = "Spell Level * 2",
                                text = "Two resources will be consumed for each level of the spell.",
                            },
                        },

                        symbols = {
                            spelllevel = {
                                name = "Spell Level",
                                type = "number",
                                desc = "The level of the spell being cast",
                            },
                            spell = {
                                name = "Spell",
                                type = "ability",
                                desc = "The spell being cast",
                            },
                        },
                    },
                }
            }


            element.children = children
        end

        Refresh()
    end,
}

function CharacterModifier:AlternativeSpellcastingCosts(modInfo, creature, spell, resultTable)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}

	if typeInfo.altSpellcasting ~= nil then
		typeInfo.altSpellcasting(self, creature, spell, resultTable)
    end

end