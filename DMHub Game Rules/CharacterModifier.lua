local mod = dmhub.GetModLoading()

--This file implements character modifiers. A character modifier is placed on a creature, most often
--by a Character Feature or an Ongoing Effect and modifies the character's rules in some way.

--- @class CharacterModifier
--- @field name string
--- @field description string
--- @field StandardModifiers CharacterModifier[]
--- @field resourceCost string
--- @field valueTypes {id: string, text: string, get: (fun(c:Creature): number)}

RegisterGameType("CharacterModifier")

CharacterModifier.name = "UNKNOWN"
CharacterModifier.description = ""
CharacterModifier.StandardModifiers = {}

CharacterModifier.resourceCost = "none"

CharacterModifier.valueTypes = {
	{ id = 'number', text = 'Number', get = function(creature) return 1 end },
}

for k,v in pairs(creature.attributesInfo) do
	local attrKey = k
	CharacterModifier.valueTypes[#CharacterModifier.valueTypes+1] =
	{
		id = k,
		text = string.format("%s Modifier", v.description),
		get = function(creature)
			return creature:GetAttribute(attrKey):Modifier()
		end,
	}
end

local valueTypesById = {}
for i,valueType in ipairs(CharacterModifier.valueTypes) do
	valueTypesById[valueType.id] = valueType
end

CharacterModifier.Types = {
	{
		id = 'none',
		text = 'None',
	},
}

CharacterModifier.TypesById = {}

--- @param id string
--- @param text string
function CharacterModifier.RegisterType(id, text)
	CharacterModifier.DeregisterType(id) --remove any existing entry.
	CharacterModifier.Types[#CharacterModifier.Types+1] = {
		id = id,
		text = text,
	}

	CharacterModifier.TypesById[id] = CharacterModifier.Types[#CharacterModifier.Types]

	printf("Register Modifier: %s / %s", id, text)
end

--- @param id string
function CharacterModifier.DeregisterType(id)
	local entry = CharacterModifier.TypesById[id]
	if entry == nil then
		--try to remove by name instead.
		for _,t in ipairs(CharacterModifier.Types) do
			if t.text == id then
				id = t.id
				entry = t
				break
			end
		end

		if entry == nil then
			return
		end
	end

	for i,t in ipairs(CharacterModifier.Types) do
		if t == entry then
			table.remove(CharacterModifier.Types, i)
			break
		end
	end
	CharacterModifier.TypesById[id] = nil
end

function CharacterModifier:GetNumberOfCharges(creature)
	return ExecuteGoblinScript(self:try_get("numCharges", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 0, string.format("Number of charges for %s", self.name))
end

function CharacterModifier:GetResourceRefreshType()
	return self:try_get('resourceRefreshType', 'none')
end

function CharacterModifier:GetResourceRefreshId()
    return self:try_get("resourceCostId", self.guid)
end

function CharacterModifier:SetSymbols(symbols)
	self._tmp_symbols = symbols
end

function CharacterModifier:AppendSymbols(result)
	for k,sym in pairs(self:try_get("_tmp_symbols", {})) do
		if result[k] == nil then
			result[k] = sym
		end
	end

	return result
end

function CharacterModifier.DuplicateAndAddContext(modifier, context)
	if modifier == nil then
		return nil
	end

	local result = dmhub.DeepCopy(modifier)
	result:InstallSymbolsFromContext(context)
	return result
end

function CharacterModifier:InstallSymbolsFromContext(context)
	if context == nil then
		return
	end

	local symbols = self:get_or_add("_tmp_symbols", {})
	for k,v in pairs(context) do
		if k ~= "mod" then
			symbols[string.lower(k)] = v
		end
	end
end

function CharacterModifier:ResourceCostEditor(options)
	options = options or {}

	local resourceOptions = {}
	local resourceTable = dmhub.GetTable("characterResources")
	for k,resource in pairs(resourceTable) do
		if resource.grouping ~= "Actions" and not resource:try_get("hidden", false) then
			resourceOptions[#resourceOptions+1] = {
				id = k,
				text = resource.name,
			}
		end
	end

	table.sort(resourceOptions, function(a,b) return a.text < b.text end)
	table.insert(resourceOptions, 1, {
		id = "none",
		text = "No resource cost",
	})

	local resultPanel
	local upcastableCheck = nil

	local resourceid = self:try_get("resourceCost")
	if resourceid ~= nil and options.allowUpcast then
		local resourceInfo = resourceTable[resourceid]
		if resourceInfo ~= nil and resourceInfo:GetSpellSlot() ~= nil then
			upcastableCheck = gui.Check{
				value = self:try_get("resourceCostUpcastable", false),
				width = 140,
				valign = "center",
				fontSize = 12,
				text = "Upcastable",
				change = function(element)
					self.resourceCostUpcastable = element.value
					resultPanel:FireEvent("change")
				end,
			}
		end
	end

	options.allowUpcast = nil


	local args = {
		classes = "formPanel",
	
		gui.Dropdown{
			classes = "formDropdown",
			idChosen = self:try_get("resourceCost", "none"),
			options = resourceOptions,
			change = function(element)
				self.resourceCost = element.idChosen
				resultPanel:FireEvent("change")
			end,
		},

		upcastableCheck,
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

function CharacterModifier:UsageLimitEditor(options)

	local resultPanel
	options = dmhub.DeepCopy(options or {})

	local multicharge = false
	if options.multicharge then
		multicharge = true
	end
	options.multicharge = nil

	local perspell = false
	if options.perspell then
		perspell = true
	end
	options.perspell = nil

	local args = {
		classes = {'formPanel'},
		children = {
			gui.Dropdown{
				selfStyle = {
					height = 30,
					width = 160,
					fontSize = 16,
				},

				options = cond(perspell, CharacterResource.usageLimitOptionsWithPerSpell, CharacterResource.usageLimitOptions),
				idChosen = self:GetResourceRefreshType(),

				events = {
					change = function(element)
						self.resourceRefreshType = element.idChosen
						resultPanel:FireEvent("change")
						element.parent:FireEventTree('create')
					end,
				},
			},
			gui.Label{
				classes = {'formLabel'},
                minWidth = 80,
                width = "auto",
				margin = 8,
				text = 'Uses:',
				events = {
					create = function(element)
						element:SetClass('hidden', self:GetResourceRefreshType() == 'none')
					end,
				},
			},
			gui.GoblinScriptInput{
				multiline = false,
                width = 140,
				create = function(element)
					element:SetClass('hidden', self:GetResourceRefreshType() == 'none')
					element.value = self:try_get("numCharges", "1")
				end,
				change = function(element)
					self.numCharges = element.value
					element.parent:FireEventTree('create')
					resultPanel:FireEvent("change")
				end,

				documentation = {
					domains = self:Domains(),
					help = string.format("This GoblinScript is used to determine the number of times this feature can be used before it must be refreshed."),
					output = "number",
					examples = {
						{
							script = "1",
							text = "The feature can be used once before it has to be refreshed.",
						},
						{
							script = "3 + 1 when level > 10",
							text = "The feature can be used 3 times, or 4 times for creatures above level 10.",
						},
					},
					subject = creature.helpSymbols,
					subjectDescription = "The creature that possesses this feature",
					symbols = self:HelpAdditionalSymbols(),
				},
			},

            gui.Label{
                text = "ID:",
                classes = {"formLabel"},
                minWidth = 0,
                width = "auto",
                hover = function(element)
                    gui.Tooltip("Set a unique ID to make multiple features share the same usage limit.")(element)
                end,
				create = function(element)
					element:SetClass('hidden', self:GetResourceRefreshType() == 'none')
				end,
            },
            gui.Input{
                width = 100,
                halign = "left",
                valign = "center",
                text = self:try_get("resourceCostId", ""),
				create = function(element)
					element:SetClass('hidden', self:GetResourceRefreshType() == 'none')
				end,
                change = function(element)
                    local text = trim(element.text)
                    element.text = text
                    if text == "" then
                        text = nil
                    end

                    self.resourceCostId = text
                end,
            }
		}
	}

	if multicharge then
		args = {
			flow = "vertical",
			width = "auto",
			height = "auto",
			gui.Panel(args),
			gui.Check{
				classes = {cond(self:GetResourceRefreshType() == "none" and self:try_get("multicharge", false) == false, "collapsed")},
				text = "Can use multiple charges",
				value = self:try_get("multicharge", false),
				change = function(element)
					self.multicharge = element.value
					resultPanel:FireEvent("change")
				end,
			},
		}
	end

	for k,v in pairs(options) do
		args[k] = v
	end

	resultPanel = gui.Panel(args)
	return resultPanel
end

CharacterModifier.TypeInfo = {}

CharacterModifier.TypeInfo.none = {
	createEditor = function(modifier, element)
		element.children = {}
	end
}

local DescribeAttrModifier = function(modifier)

	local attrText = ""
	local attrid = modifier:try_get("attribute", "armorClass")
	for i,option in ipairs(CustomAttribute.modifiableAttributes) do
		if option.id == attrid then
			attrText = option.text
		end
	end

	local text
	local op = modifier:try_get("operation", "add")
	if op == "add" then
		text = string.format("%s is added to your %s", GoblinScriptTable.tostring(modifier.value), attrText)
	elseif op == "set" then
		text = string.format("Your %s is %s.", attrText, GoblinScriptTable.tostring(modifier.value))
	elseif op == "max" then
		text = string.format("Your %s is %s. No effect if your %s is already this value or higher.", attrText, GoblinScriptTable.tostring(modifier.value), attrText)
	elseif op == "min" then
		text = string.format("Your %s is %s. No effect if your %s is already this value or lower.", attrText, GoblinScriptTable.tostring(modifier.value), attrText)
	end

	return text
end

CharacterModifier.RegisterType('icon', 'Status Icon')

CharacterModifier.TypeInfo.icon = {
	init = function(modifier)
		modifier.statusIcon = "none"
		modifier.iconColor = '#ffffffff'
	end,

	fillStatusIcons = function(self, creature, result)
		result[#result+1] = {
			id = self.name,
			icon = self.statusIcon,
			hoverText = self.name,
			style = {
				bgcolor = self:try_get("iconColor", "#ffffffff"),
			},
			statusIcon = true,
		}
	end,

	createEditor = function(modifier, element)

		local firstRefresh = true
		local Refresh
		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local children = {}


			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = gui.Panel{
				width = "auto",
				height = "auto",
				flow = "horizontal",
				gui.IconEditor{
					library = "ongoingEffects",
					bgcolor = modifier:try_get("iconColor", "#ffffffff"),
					margin = 10,
					width = 48,
					height = 48,
					halign = "left",
					value = modifier:try_get("statusIcon", "none"),
					change = function(element)
						modifier.statusIcon = element.value
						Refresh()
					end,
					iconcolor = function(element, color)
						element.selfStyle.bgcolor = color
					end,
				},
				gui.ColorPicker{
					value = modifier:try_get("iconColor", "#ffffffff"),
					hmargin = 8,
					width = 24,
					height = 24,
					halign = "left",
					valign = "center",
					borderWidth = 2,
					borderColor = '#999999ff',

					confirm = function(element)
						modifier.iconColor = element.value
						Refresh()
					end,
					change = function(element)
						element.parent.parent:FireEventTree("iconcolor", element.value)
					end,
				},
			}

			element.children = children
		end

		Refresh()
	end,

}

CharacterModifier.RegisterType('attribute', 'Modify Attribute')

--an 'attribute' modifier has the following properties:
--  - operation (default = 'add') -- 'add', 'set', 'max', 'min'
--  - attribute (default = 'armorClass') -- the attribute to modify.
--  - value (default = 1) -- a number or GoblinScript string describing the modification.
CharacterModifier.TypeInfo.attribute = {
	init = function(modifier)
		modifier.attribute = "armorClass"
		modifier.value = 1
	end,


	fillStatusIcons = function(self, creature, result)
		if self:try_get("displayIcon", false) and self:has_key("statusIcon") then
			result[#result+1] = {
				id = self.name,
				icon = self.statusIcon,
				hoverText = self.name,
				style = {
					bgcolor = self:try_get("iconColor", "#ffffffff"),
				},
				statusIcon = true,
			}
		end
	end,

	autoDescribe = function(modifier)
		return DescribeAttrModifier(modifier)
	end,

	modify = function(self, creature, attribute, currentValue)
		if attribute ~= self:try_get('attribute', 'armorClass') then
			return currentValue
		end

		local attributeType = CustomAttribute.GetAttributeType(self.attribute)
		local mod

		if attributeType == nil then
			printf("Invalid attribute: %s", attribute)
			return currentValue
		end


		if attributeType.enum then
			mod = self.value
		else
			mod = ExecuteGoblinScript(self.value, GenerateSymbols(creature, self:try_get("_tmp_symbols")), 0, string.format("%s modifier for %s", self.name, attribute))
		end
		
		local op = self:try_get("operation", "add")

		return attributeType:ApplyOperation(currentValue, mod, op)

	end,

	describe = function(self, creature, attribute, currentValue)
		if attribute ~= self:try_get('attribute', 'armorClass') then
			return nil
		end
		
		local mod = ExecuteGoblinScript(self.value, GenerateSymbols(creature, self:try_get("_tmp_symbols")), 0, string.format("%s modifier for %s", self.name, attribute))
		local op = self:try_get("operation", "add")
		if op == "add" then
			return { key = self.name, value = ModifierStr(mod), modifier = self }
		elseif op == "set" then
			return { key = self.name, value = string.format("Set to %d", mod), modifier = self }
		elseif op == "max" then
			return { key = self.name, value = string.format("Increase to %d", mod), modifier = self }
		else
			return { key = self.name, value = string.format("Decrease to %d", mod), modifier = self }
		end
	end,

	createEditor = function(modifier, element)
		local m_options = CustomAttribute.ModifiableAttributesForDomains(modifier:Domains())
		local m_categoryOverride = nil

		local firstRefresh = true
		local Refresh
		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local attrInfo = CustomAttribute.attributeInfoById[modifier.attribute]
			local attributeType = CustomAttribute.GetAttributeType(modifier.attribute)

            if attributeType == nil then
                print("Invalid attribute:", modifier.attribute, attrInfo)
            end


			local children = {}

			local options = {}

			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Modification:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 300,
							fontSize = 16,
						},

						options = attributeType.operationOptions,

						idChosen = modifier:try_get('operation', 'add'),
						events = {
							change = function(element)
								modifier.operation = element.idChosen
								Refresh()
							end,
							linger = function(element)
								local tooltip = "The value will be added to the attribute"
								if element.idChosen == "max" then
									tooltip = "The attribute will be set to be equal to the value. It won't change if it's already higher than the value."
								elseif element.idChosen == "min" then
									tooltip = "The attribute will be set to be equal to the value. It won't change if it's already lower than the value."
								elseif element.idChosen == "set" then
									tooltip = "The attribute will be set to be equal to the value."
								end
								gui.Tooltip(tooltip)(element)
							end,
						},
					},
				}
			}

			local categoriesSeen = {}
			local availableCategories = {}

			local idChosen = modifier:try_get("attribute", "armorClass")
			local optionChosen = nil
			local catChosen = "All"
			for _,option in ipairs(m_options) do
				if categoriesSeen[option.category] == nil then
					categoriesSeen[option.category] = true
					availableCategories[#availableCategories+1] = option.category
				end
			end

			table.sort(availableCategories, function(a,b) return a < b end)
            table.insert(availableCategories, 1, "All")

			if m_categoryOverride ~= nil then
				catChosen = m_categoryOverride
			end

			local haveOption = false
			local currentOptions = {}
			for _,option in ipairs(m_options) do
				if (catChosen == nil or catChosen == "All" or catChosen == option.category) and (not option.hidden) then
					currentOptions[#currentOptions+1] = option
					if option.id == idChosen then
						haveOption = true
					end
				end
			end

			table.sort(currentOptions, function(a,b) return a.text < b.text end)
			if not haveOption then
				table.insert(currentOptions, 1, { id = "none", text = "Choose..." })
			end


			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Category:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 300,
							fontSize = 16,
						},
						options = availableCategories,
						optionChosen = catChosen,
						events = {
							change = function(element)
								m_categoryOverride = element.optionChosen
								Refresh()
							end,
						},
					},
				}
			}



			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Attribute:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 300,
							fontSize = 16,
						},
                        hasSearch = true,
                        sort = true,
						options = currentOptions,
						idChosen = cond(haveOption, idChosen, "none"),
						events = {
							change = function(element)
								if element.idChosen ~= "none" then
									modifier.attribute = element.idChosen
									local newAttributeType = CustomAttribute.GetAttributeType(modifier.attribute)
									if newAttributeType ~= attributeType then
										modifier.value = newAttributeType:DefaultModifierValue()
									end
								end

								Refresh()
							end,
						},
					},
				}
			}

			if attributeType.enum then
				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Value:',
							classes = {'formLabel'},
						},
						gui.Dropdown{
							height = 30,
							width = 240,
							fontSize = 16,
							options = attributeType:GetDropdownOptions(attrInfo),
							idChosen = modifier.value,
							change = function(element)
								modifier.value = element.idChosen
								Refresh()
							end,
						},
					}
				}
			else

				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Value:',
							classes = {'formLabel'},
						},
						gui.GoblinScriptInput{
							value = modifier.value,
							change = function(element)
								modifier.value = element.value
								if tostring(tonumber(modifier.value)) == modifier.value then
									modifier.value = tonumber(modifier.value)
								end
								Refresh()
							end,

							documentation = {
								domains = modifier:Domains(),
								help = string.format("This GoblinScript is used to determine how much to modify the modified attribute by. It is calculated every time the game state is changed."),
								output = "number",
								examples = {
									{
										script = "1",
										text = "The attribute is modified by 1.",
									},
									{
										script = "3 + level",
										text = "The attribute is modified by 3, plus 1 for each level of the affected creature.",
									},
								},
								subject = creature.helpSymbols,
								subjectDescription = "The creature affected by this modifier.",
								symbols = modifier:HelpAdditionalSymbols(),
							},
						},
					}
				}
			end

			local attrText = ""
			for i,option in ipairs(CustomAttribute.modifiableAttributes) do
				if option.id == modifier:try_get("attribute", "armorClass") then
					attrText = option.text
				end
			end

			local text = DescribeAttrModifier(modifier)

			children[#children+1] = gui.Label{
				fontSize = 16,
				width = '100%',
				height = 'auto',
				maxWidth = 560,
				text = text,
			}

			children[#children+1] = gui.Check{
				text = "Display Icon When Active",
				value = modifier:try_get("displayIcon", false),
				change = function(element)
					modifier.displayIcon = element.value
					Refresh()
				end,
			}

			if modifier:try_get("displayIcon", false) then
				children[#children+1] = gui.Panel{
					width = "auto",
					height = "auto",
					flow = "horizontal",
					gui.IconEditor{
						library = "ongoingEffects",
						bgcolor = modifier:try_get("iconColor", "#ffffffff"),
						margin = 10,
						width = 48,
						height = 48,
						halign = "left",
						value = modifier:try_get("statusIcon", "none"),
						change = function(element)
							modifier.statusIcon = element.value
							Refresh()
						end,
						iconcolor = function(element, color)
							element.selfStyle.bgcolor = color
						end,
					},
					gui.ColorPicker{
						value = modifier:try_get("iconColor", "#ffffffff"),
						hmargin = 8,
						width = 24,
						height = 24,
						halign = "left",
						valign = "center",
						borderWidth = 2,
						borderColor = '#999999ff',

						confirm = function(element)
							modifier.iconColor = element.value
							Refresh()
						end,
						change = function(element)
							element.parent.parent:FireEventTree("iconcolor", element.value)
						end,


					},
				}

			end

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('resistance', "Damage Immunity")

--a 'resistance' modifier has the following properties:
--  - resistances: a list of ResistanceEntry entries. These entries will always have the same values for nonmagic and apply.
--  - filterCondition (optional): additional filter condition that will control whether this shows up at all.
CharacterModifier.TypeInfo.resistance = {
	init = function(modifier)
		modifier.resistances = {
			ResistanceEntry.new{
				apply = ResistanceEntry.types[1],
				damageType = 'all',
				dr = cond(ResistanceEntry.types[1] == "Damage Reduction", 1),
			}
		}
	end,

	autoDescribe = function(modifier)
		if #modifier.resistances == 0 then
			return nil
		end

		local nonmagic = modifier.resistances[1]:try_get("nonmagic", false)
		local nonmagicText = cond(nonmagic, "non-magical ", "")
		local items = {}
		for i,entry in ipairs(modifier.resistances) do
			items[#items+1] = entry.damageType
		end

		local itemsDesc = string.format("%s%s", nonmagicText, pretty_join_list(items))

		if modifier.resistances[1].apply == 'Damage Reduction' then
			return string.format("Damage from %s attacks is reduced by %s.", itemsDesc, modifier.resistances[1].dr)
		elseif modifier.resistances[1].apply == 'Percent Reduction' then
			return string.format("Damage from %s attacks is reduced by %d%%.", itemsDesc, math.floor(modifier.resistances[1].dr*100))

		else
			return string.format("You are %s to %s damage.", modifier.resistances[1].apply, itemsDesc)
		end
		
	end,

	getResistances = function(modifier, creature, resistanceList)
		for i,entry in ipairs(modifier.resistances) do
			local e = table.shallow_copy_with_meta(entry)
			if type(e:try_get("dr")) == "string" then
				e.dr = ExecuteGoblinScript(e.dr, GenerateSymbols(creature, modifier:try_get("_tmp_symbols")), 0, "Damage Resistance")
			end

            e.source = modifier.name

            if e.dr ~= 0 then
			    resistanceList[#resistanceList+1] = e
            end
		end
	end,

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

			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = gui.Panel{
				id = 'resistance-apply-container',
				classes = {'formPanel', cond(#ResistanceEntry.types <= 1, "collapsed")},
				children = {
					gui.Dropdown{
						id = 'resistance-apply-dropdown',
						selfStyle = {
							height = 30,
							width = 160,
							fontSize = 16,
						},
						options = ResistanceEntry.types,
						idChosen = modifier.resistances[1].apply,
						events = {
							change = function(element)
								for i,entry in ipairs(modifier.resistances) do
									entry.apply = element.idChosen
									if entry.apply == 'Damage Reduction' then
										entry.dr = entry:try_get("dr", 1)
									elseif entry.apply == 'Percent Reduction' then
										entry.dr = entry:try_get("dr", 0.5)
									end
								end
								Refresh()
							end,
						},
					},
					gui.Label{
						text = ' to',
						classes = {'formLabel'},
					},
				}
			}

			if #modifier.resistances > 0 and modifier.resistances[1].apply == 'Damage Reduction' then
				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					gui.Label{
						text = 'Damage Immunity:',
						classes = {'formLabel'},
						width = 180,
						valign = "center",

					},

					gui.GoblinScriptInput{
						value = tostring(modifier.resistances[1].dr),
						change = function(element)
							for _,entry in ipairs(modifier.resistances) do
								entry.dr = element.value
							end
							Refresh()
						end,

						documentation = {
							domains = modifier:Domains(),
							help = string.format("This GoblinScript is used to determine the amount of damage reduction this modifier applies."),
							output = "number",
							examples = {
								{
									script = "1",
									text = "Damage is Reduced by 1 by this modifier.",
								},
								{
									script = "1 when level < 10 else 2",
									text = "Damage is reduced by 1 for creatures with a level lower than 10, otherwise by 2.",
								},
							},
							subject = creature.helpSymbols,
							subjectDescription = "The creature that possesses this feature",
							symbols = modifier:HelpAdditionalSymbols(),
						},

					},
				}

                children[#children+1] = gui.Check{
                    text = "Stacks with other Damage Reduction",
                    value = modifier.resistances[1].stacks,
                    change = function(element)
                        for _,entry in ipairs(modifier.resistances) do
                            entry.stacks = element.value
                        end
                        Refresh()
                    end,
                }
			end

			if #modifier.resistances > 0 and modifier.resistances[1].apply == 'Percent Reduction' then
				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					halign = "left",
					gui.Label{
						text = 'Percent Reduction:',
						classes = {'formLabel'},
					},

					gui.Input{
						height = 22,
						width = 100,
						fontSize = 16,
						text = string.format("%d", math.floor(modifier.resistances[1].dr*100)),
						change = function(element)
							local num = tonumber(element.text)
							if num == nil then
								element.text = string.format("%d", math.floor(modifier.resistances[1].dr*100))
								return
							end

							num = math.floor(num)

							element.text = string.format("%d", num)
							for _,entry in ipairs(modifier.resistances) do
								entry.dr = num*0.01
							end
							Refresh()
						end,
					},

				}
			end

			--if this game system uses damage type keywords then have them here.

			if GameSystem.hasAbilityKeywords then
                local keywordsFound = {}
                for keyword,val in sorted_pairs(modifier.resistances[1]:try_get("keywords", {})) do
                    if val == true then
                        keywordsFound[keyword] = true
                        children[#children+1] = gui.Panel{
                            classes = {"formPanel"},
                            data = {ord = keyword},
                            width = 200,
                            height = 14,
                            minHeight = 14,
                            gui.Label{
                                text = keyword,
                                width = "auto",
                                height = 14,
                                fontSize = 14,
                                color = Styles.textColor,
                            },
                            gui.DeleteItemButton{
                                width = 12,
                                height = 12,
                                halign = "right",
                                click = function(element)
                                    modifier.resistances[1].keywords[keyword] = nil
                                    Refresh()
                                end,
                            },
                        }
                    end
                end

                local dropdownOptions = {}
				for keyword,_ in pairs(GameSystem.abilityKeywords) do
                    if not keywordsFound[keyword] then
                        dropdownOptions[#dropdownOptions+1] = {
                            id = keyword,
                            text = keyword,
                        }
                    end
                end

                children[#children+1] = gui.Dropdown{
                    selfStyle = {
                        height = 30,
                        width = 240,
                        fontSize = 16,
                        halign = "left",
                    },
                    sort = true,
                    options = dropdownOptions,
                    textDefault = "Add Keyword...",
                    change = function(element)
                        if element.idChosen ~= nil and GameSystem.abilityKeywords[element.idChosen] then
                            modifier.resistances[1]:get_or_add("keywords", {})[element.idChosen] = true
                        end
                        Refresh()
                    end,
                }

			else
				children[#children+1] = gui.Check{
					id = 'non-magical-checkbox',
					text = 'Non-Magical',
					style = {
						height = 30,
						width = 240,
						fontSize = 18,
						halign = "left",
					},

					value = modifier.resistances[1]:try_get('nonmagic', false),

					change = function(element)
						for i,entry in ipairs(modifier.resistances) do
							entry.nonmagic = element.value
						end

						Refresh()
					end,
				}
			end

			local optionsTable = {}

			local options = {}
			if #modifier.resistances > 1 then
				options = { {id = '(Remove)', text = '(Remove)'} }
			else
				options = { {id = 'all', text = "all damage"} }
			end

            local damageTable = dmhub.GetTable(DamageType.tableName) or {}
            for k,v in unhidden_pairs(damageTable) do
                local name = string.lower(v.name)
                local alreadyHave = false
                for i,r in ipairs(modifier.resistances) do
                    if r.damageType == v.name then
                        alreadyHave = true
                    end
                end

                if not alreadyHave then
                    optionsTable[name] = true
                    options[#options+1] = {
                        id = name,
                        text = string.format("%s damage", name),
                    }
                end
            end

			for i,r in ipairs(modifier.resistances) do
				children[#children+1] = gui.Dropdown{
					selfStyle = {
						height = 30,
						width = 240,
						fontSize = 16,
						vmargin = 2,
						halign = "left",
					},
					options = options,
					idChosen = r.damageType,
                    textDefault = string.format("%s damage", r.damageType),
                    sort = true,
					change = function(element)
						if element.idChosen == '(Remove)' then
							table.remove(modifier.resistances, i)
						else
							modifier.resistances[i].damageType = element.idChosen
						end
						Refresh()
					end,
				}
			end

			if options[1] == '(Remove)' then
                options = DeepCopy(options)
				table.remove(options, 1)
			end


			if #options > 0 and (#modifier.resistances == 0 or modifier.resistances[1].damageType ~= 'all') then
				children[#children+1] = gui.Dropdown{
					selfStyle = {
						height = 30,
						width = 240,
						fontSize = 16,
						vmargin = 2,
					},
					options = options,
                    textDefault = "Add...",
                    sort = true,
					change = function(element)
						if optionsTable[element.idChosen] then
							local newEntry = dmhub.DeepCopy(modifier.resistances[1])
							newEntry.damageType = element.idChosen
							modifier.resistances[#modifier.resistances+1] = newEntry
							Refresh()
						end
					end
				}
			end

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('conditionimmunity', "Condition Immunity")

--a 'conditionimmunity' modifier has the following properties:
--  - conditions: a list of condition id's which we are immune to.
CharacterModifier.TypeInfo.conditionimmunity = {
	init = function(modifier)
		modifier.conditions = {}
	end,

	fillConditionImmunities = function(modifier, result)
		for i,condid in ipairs(modifier.conditions) do
			result[condid] = true
		end
	end,

	autoDescribe = function(modifier)
		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

		local items = {}
		for i,condid in ipairs(modifier.conditions) do
			local condition = conditionsTable[condid]
			if condition ~= nil then
				items[#items+1] = condition.name
			end
		end

		if #items == 0 then
			return nil
		end

		return string.format("Immune to %s.", pretty_join_list(items))
	end,

	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true
		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end


			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

			local children = {}

			children[#children+1] = modifier:FilterConditionEditor()

			for i,condid in ipairs(modifier.conditions) do
				local condition = conditionsTable[condid]

				if condition ~= nil then
					children[#children+1] = gui.Label{
						text = condition.name,
						classes = {'formLabel'},
						width = 200,
						height = 30,
						gui.DeleteItemButton{
							width = 16,
							height = 16,
							valign = 'center',
							halign = 'right',
							click = function(element)
								table.remove(modifier.conditions, i)
								Refresh()
							end,
						},
					}
				end
			end

			local options = {}

			for j,cond in unhidden_pairs(conditionsTable) do
				local alreadyHave = false
				for i,condid in ipairs(modifier.conditions) do
					if condid == j then
						alreadyHave = true
					end
				end

				if alreadyHave == false then
					options[#options+1] = {
						id = j,
						text = cond.name,
					}
				end
			end

			table.sort(options, function(a,b) return a.text < b.text end)
			table.insert(options, 1, {
				id = "none",
				text = cond(#modifier.conditions == 0, "Choose Condition...", "Add Condition..."),
			})



			children[#children+1] = gui.Panel{
				id = 'resistance-apply-container',
				classes = {'formPanel'},
				children = {
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 160,
							fontSize = 16,
						},
						options = options,
						idChosen = 'none',
						change = function(element)
							if element.idChosen ~= "none" then
								modifier.conditions[#modifier.conditions+1] = element.idChosen
							end
							Refresh()
						end,
					},
				}
			}

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('rollsattacking', "Rolls Attacking Us")

--a 'rollsattacking' modifier has the following properties:
--  - modifyRoll: text to be added to damage rolls.
--  - filterRoll (optional): GoblinScript used to determine if this should be used.
CharacterModifier.TypeInfo.rollsattacking = {
	init = function(modifier)
		modifier.modifyRoll = ''
	end,

	filterAttackAgainstUs = function(self, defenderCreature, attackerCreature, attack)
		if self:try_get("rollType", "attack") ~= "attack" then
			return false
		end

		if (not self:has_key("filterRoll")) or self.filterRoll == "" then
			return true
		end
		local symbols = self:AppendSymbols{
			attack = GenerateSymbols(attack),
			target = GenerateSymbols(defenderCreature),
		}
		local lookupFunction = attackerCreature:LookupSymbol(symbols)
		local result = ExecuteGoblinScript(self.filterRoll, lookupFunction, 0, string.format("Should %s apply to rolls attacking.", self.name))
		return GoblinScriptTrue(result)
	end,

	modifyAttackAgainstUs = function(self, defenderCreature, attackerCreature, roll)
		print("AGAINSTUS:: ADDING", self.modifyRoll)
		return dmhub.NormalizeRoll(roll .. ' ' .. self.modifyRoll)
	end,

	filterDamageAgainstUs = function(self, defenderCreature, attackerCreature, attack)
		print("AGAINSTUS:: ROLL TYPE = ", self:try_get("rollType", "attack"))
		if self:try_get("rollType", "attack") ~= "damage" then
			return false
		end

		if (not self:has_key("filterRoll")) or self.filterRoll == "" then
			return true
		end
		local symbols = self:AppendSymbols{
			attack = GenerateSymbols(attack),
			target = GenerateSymbols(defenderCreature),
		}
		local lookupFunction = attackerCreature:LookupSymbol(symbols)
		local result = ExecuteGoblinScript(self.filterRoll, lookupFunction, 0, string.format("Should %s apply to rolls damaging.", self.name))
		local res = GoblinScriptTrue(result)
		return res
	end,

	modifyDamageAgainstUs = function(self, defenderCreature, attackerCreature, roll)
		local result = dmhub.NormalizeRoll(roll .. ' ' .. self.modifyRoll)
		return result
	end,



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

			documentation = {
				domains = modifier:Domains(),
				help = string.format("This GoblinScript is used to determine whether or not this modifier will be used. If this GoblinScript produces a False result, this modifier will not even appear as an option in dialogs in which this modifier might be used."),
				output = "boolean",
				examples = {
					{
						script = "",
						text = "This modifier will not be applied to undead creatures.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature that is attacking.",
				symbols = {
					target = {
						name = "Target",
						type = "creature",
						desc = "The creature targeted with the attack.",
					},
					attack = {
						name = "Attack",
						type = "attack",
						desc = "The attack being used.",
					},
				},
			}

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Roll Type:",
				},
				gui.Dropdown{
					options = {
						{
							id = "attack",
							text = "Attack Rolls",
						},
						{
							id = "damage",
							text = "Damage Rolls",
						},
					},
					idChosen = modifier:try_get("rollType", "attack"),
					change = function(element)
						modifier.rollType = element.idChosen
					end,
				},
			}

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Condition:",
				},
				gui.GoblinScriptInput{
					value = modifier:try_get("filterRoll", ""),
					change = function(element)
						if trim(element.value) == '' then
							modifier.filterRoll = nil
						else
							modifier.filterRoll = element.value
						end
					end,

					documentation = documentation,
				},
			}

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Modify Roll:',
						classes = {'formLabel'},
					},
					gui.Input{
						selfStyle = {
							height = 22,
							width = 160,
							fontSize = 16,
						},
						text = modifier.modifyRoll,

						events = {
							change = function(element)
								modifier.modifyRoll = element.text
							end,
						},
					},
				}
			}

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('armorclasscalculation', "Armor Class Calculation")

--A 'armorclasscalculation' modifier provides an alternative armor class calculation.
--creatures will use the highest armor class calculation they can.
--  - calculation: goblinscript to calculate armor class.
CharacterModifier.TypeInfo.armorclasscalculation = {
	init = function(modifier)
		modifier.calculation = '10'
	end,

	alterBaseArmorClass = function(modifier, creature, armorClass)

		local symbols = GenerateSymbols(creature, modifier:try_get("_tmp_symbols"))

		if modifier:has_key("filterCondition") then
			local cond = ExecuteGoblinScript(modifier.filterCondition, symbols, 1, string.format("Should %s modifier apply armor class calculation.", modifier.name)) ~= 0
			if cond == 0 then
				return armorClass
			end
		end
		


		local result = ExecuteGoblinScript(modifier.calculation, symbols, 0, "Calculate alternative armor class")
		if result > armorClass then
			return result
		end

		return armorClass
	end,

	autoDescribe = function(modifier)
		return "You may calculate your Armor Class using the formula " .. modifier.calculation
	end,

	createEditor = function(modifier, element)
		local Refresh
		Refresh = function()
			
			local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Calculation:",
				},
				gui.GoblinScriptInput{
					value = modifier.calculation,
					change = function(element, text)
						modifier.calculation = text
						Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to calculate the affected creature's armor class. The result will be used if it is higher than other ways the creature can calculate its Armor Class."),
						output = "number",
						examples = {
							{
								script = "10 + Dexterity Modifier + Constitution Modifier",
								text = "The creature's Armor Class will be 10 plus its Dexterity and Constitution modifiers.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that is affected by this modifier",
						symbols = modifier:HelpAdditionalSymbols(),
					},

				},
			}

			local text = CharacterModifier.TypeInfo.armorclasscalculation.autoDescribe(modifier)

			children[#children+1] = gui.Label{
				fontSize = 16,
				width = '100%',
				height = 'auto',
				maxWidth = 560,
				text = text,
			}

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('attackattribute', "Attack Attribute")

--A 'attackattribute' modifier provides an alternative attribute to strength to use for attacks.
--creatures will use the highest attack attribute they can.
--  - attribute: the attribute that can be used.
--  - weaponFilterCondition: goblinscript filter which inspects the character along with a specific weapon to determine if it should apply.
CharacterModifier.TypeInfo.attackattribute = {
	init = function(modifier)
		modifier.attribute = 'dex'
		modifier.weaponFilterCondition = ""
	end,

	attackAttribute = function(modifier, creature, weapon)

		if modifier.weaponFilterCondition == "" then
			return modifier.attribute
		end

		local lookupFunction = creature:LookupSymbol{
			weapon = GenerateSymbols(weapon),
		}

		local result = ExecuteGoblinScript(modifier.weaponFilterCondition, lookupFunction, 0, string.format("Should use attribute %s for attack with %s", modifier.attribute, weapon:try_get("description", "unknown weapon")))
		if result ~= 0 then
			return modifier.attribute
		end

		return nil
	end,

	createEditor = function(modifier, element)
		local Refresh
		Refresh = function()
			
			local children = {}
			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Attribute:",
				},
				gui.Dropdown{
					options = creature.attributeDropdownOptions,
					idChosen = modifier:try_get("attribute", "dex"),
					change = function(element)
						modifier.attribute = element.idChosen
					end,
				},
			}

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Condition:",
				},
				gui.GoblinScriptInput{
					value = modifier.weaponFilterCondition,
					change = function(element, text)
						modifier.weaponFilterCondition = text
						Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine whether the alternative attribute should be allowed when using the provided weapon."),
						output = "boolean",
						examples = {
							{
								script = "weapon.melee and weapon.simple and (not weapon.heavy)",
								text = "The alternative attribute will be used when using a simple melee weapon that isn't heavy.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature that is affected by this modifier",
						symbols = {
							weapon = {
								name = "Weapon",
								type = "weapon",
								desc = "The weapon used in the attack",
								examples = {
									"weapon.finesse",
									"weapon.twohanded and weapon.heavy",
								},
							}
						},
					},
				},
			}

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('trigger', "Triggered Ability")

--a 'trigger' modifier has the following properties:
--  - triggeredAbility: a TriggeredAbility
CharacterModifier.TypeInfo.trigger = {
	init = function(modifier)
		modifier.triggeredAbility = TriggeredAbility.Create()
		modifier.triggeredAbility.name = modifier.name
	end,

	UpdateDomains = function(modifier)
		modifier.triggeredAbility:SetDomains(modifier:Domains())
	end,

	autoDescribe = function(modifier)
		return modifier.triggeredAbility.description
	end,

	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true
		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			if modifier.triggeredAbility.name == "" then
				modifier.triggeredAbility.name = modifier.name
			end

			local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = modifier:UsageLimitEditor{
				perspell = true,
				change = function(element)
					modifier.triggeredAbility.usageLimitOptions = {
						resourceRefreshType = modifier:GetResourceRefreshType(),
						charges = modifier:try_get("numCharges", "1"),
						resourceid = modifier.guid,
					}
				end,
			}
            children[#children+1] = gui.Label{
                classes = {'formLabel'},
                halign = "left",
                textAlignment = "left",
                create = function(element)
                    element:FireEvent("think")
                end,

                thinkTime = 0.5,
                think = function(element)
					local options = TriggeredAbility.GetTriggerDropdownOptions()
                    for i,option in ipairs(options) do
                        if option.id == modifier.triggeredAbility.trigger then
                            element.text = option.text
                            break
                        end
                    end

                end,
            }
			children[#children+1] = gui.PrettyButton{
				width = 200,
				height = 50,
				text = "Edit Ability",
				click = function(element)
					local fn = function(element, modifier, savefn)
						element.root:AddChild(modifier.triggeredAbility:ShowEditActivatedAbilityDialog{
                            destroy = savefn,
                        })
					end
	
					element.root:FireEventTree("editCompendiumFeature", modifier, fn)
	
					fn(element, modifier)
				end,
			}
			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('activated', "Activated Ability")

--a 'activated' modifier has the following properties:
--  - activatedAbility: an ActivatedAbility
--  - multicharge (optional): multiple charges can be used for this ability.
CharacterModifier.TypeInfo.activated = {
	init = function(modifier)
		modifier.activatedAbility = ActivatedAbility.Create()
		modifier.activatedAbility.name = modifier.name
		modifier.activatedAbility:SetDomains(modifier:Domains())
	end,

	UpdateDomains = function(modifier)
		modifier.activatedAbility:SetDomains(modifier:Domains())
	end,

	fillActivatedAbilities = function(modifier, creature, result)
		result[#result+1] = modifier.activatedAbility
	end,

    modifyAbility = function(modifier, creature, ability)
        local suppresses = modifier:try_get("suppressOthers", false)
        if suppresses and ability.name == modifier.activatedAbility.name and ability.guid ~= modifier.activatedAbility.guid then
            return nil
        end

        return ability
    end,

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

            local ability = modifier.activatedAbility
            if ability ~= nil then
                local text = string.format("<b>%s</b>", ability.name)
                local resourceInfo = dmhub.GetTable(CharacterResource.tableName)[ability.actionResourceId]
                if resourceInfo ~= nil then
                    text = string.format("%s (%s)", text, resourceInfo.name)
                end
                children[#children+1] = gui.Label{
                    classes = {"formLabel"},
                    halign = "left",
                    text = text,
                    width = "auto",
                }
            end


			children[#children+1] = modifier:FilterConditionEditor()
			children[#children+1] = modifier:UsageLimitEditor{
				multicharge = true,
				change = function(element)
					modifier.activatedAbility.usageLimitOptions = {
						resourceRefreshType = modifier:GetResourceRefreshType(),
						charges = modifier:try_get("numCharges", "1"),
						resourceid = modifier.guid,
						multicharge = modifier:try_get("multicharge", false),
					}
					Refresh()
				end,
			}

            children[#children+1] = gui.Check{
                value = modifier:try_get("suppressOthers", false),
                text = "Suppress Other Abilities With Same Name",
                change = function(element)
                    modifier.suppressOthers = element.value
                end,
            }
			children[#children+1] = gui.PrettyButton{
				width = 200,
				height = 50,
				text = "Edit Ability",
				click = function(element)
					local fn = function(element, modifier, savefn)
						element.root:AddChild(modifier.activatedAbility:ShowEditActivatedAbilityDialog{
                            destroy = savefn,
                        })
					end

					element.root:FireEventTree("editCompendiumFeature", modifier, fn)
					fn(element, modifier)
				end,
			}
			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('spell', "Innate Spellcasting")

--a 'spell' modifier has the following properties:
-- spell: id of the spell it allows us to cast.
-- attribute: id of the attribute to use for casting.
-- level (optional): the level to force-cast this spell at.
-- usageLimitOptions (optional): resource cost that can be set directly on a spell.
CharacterModifier.TypeInfo.spell = {
	init = function(modifier)
		local spellsTable = dmhub.GetTable("Spells")
		for k,spell in pairs(spellsTable) do
			if modifier:has_key("spell") == false then
				modifier.spell = k
			end
		end

		modifier.attribute = 'int'
	end,

	fillActivatedAbilities = function(modifier, creature, result)
		local spellsTable = dmhub.GetTable("Spells")
		local spell = spellsTable[modifier.spell]
		if spell ~= nil then
			local spellClone = dmhub.DeepCopy(spell)
			spellClone.usesSpellSlots = false
			spellClone.attributeOverride = modifier:try_get("attribute")

			

			if modifier:has_key("level") and modifier.level ~= "" and spellClone.level ~= 0 then
				--forced upcasting of this spell.
				local level = ExecuteGoblinScript(modifier.level, creature:LookupSymbol(modifier:try_get("_tmp_symbols", {})), 1, string.format("Calculate level to cast innate spell %s at", spellClone.name))					
				if type(level) == "number" and level >= spellClone.level then
					spellClone.castingLevel = level
				end
			end

			if modifier:has_key("usageLimitOptions") then
				spellClone.usageLimitOptions = modifier.usageLimitOptions
			end

			result[#result+1] = spellClone
		end
	end,

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
			children[#children+1] = modifier:FilterConditionEditor()
			children[#children+1] = modifier:UsageLimitEditor{
				change = function(element)
					modifier.usageLimitOptions = {
						resourceRefreshType = modifier:GetResourceRefreshType(),
						charges = modifier:try_get("numCharges", "1"),
						resourceid = modifier.guid,
					}
				end,
			}

			local options = {}
			local spellsTable = dmhub.GetTable("Spells")
			for k,spell in pairs(spellsTable) do
				options[#options+1] = {
					id = k,
					text = spell.name,
				}
			end

			table.sort(options, function(a,b) return a.text < b.text end)

			local levelPanel = nil

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Spell:",
				},
				gui.Dropdown{
					options = options,
					idChosen = modifier.spell,
					hasSearch = true,
					change = function(element)
						modifier.spell = element.idChosen
						levelPanel:FireEventTree("create")
					end,
				},
			}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				create = function(element)
					local spellInfo = spellsTable[modifier.spell]
					element:SetClass("hidden", spellInfo == nil or spellInfo.level == 0)
				end,
				gui.Label{
					classes = {'formLabel'},
					text = "Casting Level:",
				},
				gui.GoblinScriptInput{
					value = modifier:try_get("level", ""),
					change = function(element)
						modifier.level = element.value
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine the level which this spell is cast at. If left empty, the default level of the spell will be used."),
						output = "number",
						examples = {
							{
								script = "4",
								text = "The spell will be cast at level 4.",
							},
							{
								script = "3 + 2 when level >= 5",
								text = "The spell will be cast at level 5 when the caster is level 5 or higher, otherwise it will be cast at level 3.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature using the spell.",
						symbols = modifier:HelpAdditionalSymbols(),
					},

				},
			}

			levelPanel = children[#children]

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					classes = {'formLabel'},
					text = "Attribute:",
				},
				gui.Dropdown{
					options = creature.attributeDropdownOptions,
					idChosen = modifier:try_get("attribute", "int"),
					change = function(element)
						modifier.attribute = element.idChosen
					end,
				},
			}

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('multiattack', "Multiple Attacks")

CharacterModifier.TypeInfo.multiattack = {

	createEditor = function(modifier, element)
		local Refresh
		Refresh = function()
			local children = {}

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.RegisterType('transform', "Transformation")


CharacterModifier.TypeInfo.transform = {
	RefreshGameState = function(creature, self)
		if creature:has_key("transformInfo") then
			local monsterInfo = assets.monsters[creature.transformInfo.transformid]
			creature._tmp_appearance = monsterInfo.appearance
			creature._tmp_creaturesize = monsterInfo.info.creatureSize
		end
	end,

	addModifiers = function(modifier, creature, result)
		if creature:has_key("transformInfo") then
			local monsterInfo = assets.monsters[creature.transformInfo.transformid]
			local beast = monsterInfo.properties
			for _,feature in ipairs(beast:try_get("characterFeatures", {})) do
				for _,mod in ipairs(feature.modifiers) do
					result[#result+1] = mod
				end
			end
		end
	end,

	--if we modify hitpoints then we also overwrite hit dice here.
	getNamedResources = function(modifier, creature, resourceTable)
		local attributes = modifier:try_get("attributes")
		if attributes == nil or not attributes["hitpoints"] then
			return
		end

		local deletes = {}

		for k,_ in pairs(resourceTable) do
			if string.starts_with(k, "hitDie") then
				deletes[#deletes+1] = k
			end
		end

		for _,k in ipairs(deletes) do
			resourceTable[k] = nil
		end

	end,

	getResistances = function(modifier, creature, resistanceList)
		if modifier:try_get("inheritResistances") and creature:has_key("transformInfo") then
			local monsterInfo = assets.monsters[creature.transformInfo.transformid]
			local beast = monsterInfo.properties
			local resistances = beast:try_get("resistances", {})
			for _,resist in ipairs(resistances) do
				resistanceList[#resistanceList+1] = resist
			end
		end
	end,

	skillProficiencyBonus = function(modifier, creature, skillInfo, bonus, descriptionTable)
		if modifier:try_get("inheritSkills") then
			if creature:has_key("transformInfo") then
				local monsterInfo = assets.monsters[creature.transformInfo.transformid]
				local beast = monsterInfo.properties
				local beastProficiency = beast:SkillProficiencyBonus(skillInfo)

				if beastProficiency > bonus then
					bonus = beastProficiency
					if descriptionTable ~= nil then
						descriptionTable[#descriptionTable+1] = string.format("%s proficiency: %d", beast:try_get("monster_type", "Transformation"), bonus)
					end
				end
			end
		end

		return bonus
	end,

	modify = function(self, creature, attribute, currentValue)
		local attributes = self:try_get("attributes")
		if attributes == nil or ((not attributes[attribute]) and attribute ~= "speed" and (not creature.movementTypesTable[attribute])) then
			return currentValue
		end

		if creature:has_key("transformInfo") then
			local monsterInfo = assets.monsters[creature.transformInfo.transformid]
			local beast = monsterInfo.properties

			if creature.movementTypesTable[attribute] then
				if self:try_get("overrideMovement") then
					return beast:GetSpeed(attribute)
				end

			elseif attribute == "speed" then
				if self:try_get("overrideMovement") then
					return beast:WalkingSpeed()
				end
			elseif attribute == "hitpoints" then
				return beast:MaxHitpoints()
			elseif attribute == "armorClass" then
				return beast:ArmorClass()
			elseif attribute == "darkvision" then
				return 0 --later when monsters get dark vision we can fill this in.
			else
				return beast:GetAttribute(attribute):Value()
			end
		end
		
		return currentValue
	end,

	describe = function(self, creature, attribute, currentValue)

		local attributes = self:try_get("attributes")
		if attributes == nil or not attributes[attribute] then
			return nil
		end

		if creature:has_key("transformInfo") then
			local monsterInfo = assets.monsters[creature.transformInfo.transformid]
			local beast = monsterInfo.properties
			local val = nil
			if attribute == "hitpoints" then
				val = string.format("%d", beast:MaxHitpoints())
			elseif attribute == "armorClass" then
				val = string.format("%d", beast:ArmorClass())
			elseif attribute == "darkvision" then
				val = "0"
			else
				val = string.format("%d", beast:GetAttribute(attribute):Value())
			end
			return {
				key = string.format("%s", beast:try_get("monster_type", "Creature")),
				value = val,
			}

		end

		return nil
	end,

	fillActivatedAbilities = function(modifier, creature, abilities)
		if modifier:try_get("inheritAbilities") and creature:has_key("transformInfo") then
			local monsterInfo = assets.monsters[creature.transformInfo.transformid]
			local beast = monsterInfo.properties
			for _,ability in ipairs(beast.innateActivatedAbilities) do
				abilities[#abilities+1] = ability
			end
		end
	end,

	preventsSpells = function(self, creature)
		return self:try_get("banspells")
	end,

	preventsEquipment = function(self, creature)
		return self:try_get("banequipment")
	end,

	createEditor = function(modifier, element)
		local Refresh
		Refresh = function()
			local children = {}

			modifier:get_or_add("attributes", {})

			local attributes = {
				{
					id = "hitpoints",
					name = "Maximum Hitpoints",
				},
				{
					id = "armorClass",
					name = "Armor Class",
				},
				{
					id = "darkvision",
					name = "Dark Vision",
				},
			}
			for i,attrid in ipairs(creature.attributeIds) do
				local attr = creature.attributesInfo[attrid]
				attributes[#attributes+1] = {
					id = attr.id,
					name = attr.description,
				}
			end


			for i,attr in ipairs(attributes) do
				children[#children+1] = gui.Check{
					halign = "left",
					text = string.format("Transform %s", attr.name),

					value = modifier.attributes[attr.id] == true,
					change = function(element)
						modifier.attributes[attr.id] = cond(element.value, true)
					end,
				}
			end

			local capabilities = {
				{
					id = "overrideMovement",
					text = "Override Movement",
				},
				{
					id = "banspells",
					text = "Cannot cast spells",
				},
				{
					id = "banequipment",
					text = "Cannot use equipment",
				},
				{
					id = "inheritAbilities",
					text = "Gain Abilities",
				},
				{
					id = "inheritResistances",
					text = "Gain Resistances",
				},
				{
					id = "inheritSkills",
					text = "Gain Skill Proficiencies",
				},
			}

			for i,capability in ipairs(capabilities) do
				children[#children+1] = gui.Check{
					halign = "left",
					text = capability.text,

					value = modifier:try_get(capability.id) == true,
					change = function(element)
						modifier[capability.id] = element.value
					end,
				}
			end

			element.children = children
		end

		Refresh()
	end,

}


CharacterModifier.StandardModifiers.TransformIntoBeast = CharacterModifier.new{
	behavior = 'transform',
	guid = dmhub.GenerateGuid(),
	name = "Transformation",
	source = "Transformation",
	description = "You are transformed into a different creature",
	attributes = {
		str = true,
		dex = true,
		con = true,
	},

}

CharacterModifier.RegisterType('resource', "Grant Resource")

--resourceType: id of the resource granted.
--num: the quantity granted
--level: the level of the resource (goblin script). Used for resources that have leveling.
CharacterModifier.TypeInfo.resource = {
	init = function(modifier)
		modifier.resourceType = 'none'
		modifier.num = 1 --can be a number, or a string in which case it is interpreted as goblinscript
	end,

	getNamedResources = function(modifier, creature, resourceTable)
		if modifier.resourceType ~= 'none' then
			local resourceType = modifier.resourceType
			if CharacterResource.levelingMap[resourceType] ~= nil and modifier:has_key("level") then
				local level = ExecuteGoblinScript(modifier.level, creature:LookupSymbol(modifier:try_get("_tmp_symbols", {})), 1, string.format("Calculate resource level for %s", modifier.name))					

				while level < 1000 and level > 1 and CharacterResource.levelingMap[resourceType] ~= nil do
					resourceType = CharacterResource.levelingMap[resourceType]
					level = level-1
				end
			end
			resourceTable[resourceType] = (resourceTable[resourceType] or 0) + ExecuteGoblinScript(modifier:try_get("num", 1), creature:LookupSymbol(modifier:try_get("_tmp_symbols", {})), 0, string.format("Calculate resource %s", modifier.name))
		end
	end,

	createEditor = function(modifier, element)
		local Refresh
		Refresh = function()

			modifier:get_or_add("num", 1)
			local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

			local resourceChoices = {
				{
					id = 'none',
					text = 'Choose Resource...',
				}
			}

			local resourceTable = dmhub.GetTable("characterResources") or {}
			for k,v in pairs(resourceTable) do
				if (not v:try_get("hidden")) and (v.levelsFrom == "none" or v.spellSlot ~= "none") then
					resourceChoices[#resourceChoices+1] = {
						id = k,
						text = v.name,
					}
				end
			end

			table.sort(resourceChoices, function(a,b)
				if a.id == 'none' then
					return true
				end
				if b.id == 'none' then
					return false
				end

				return a.text < b.text
			end)

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Resource:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 250,
							fontSize = 16,
						},
						options = resourceChoices,
						idChosen = modifier.resourceType,

						events = {
							change = function(element)
								modifier.resourceType = element.idChosen
								Refresh()
							end,
						},
					},
				}
			}

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Quantity:',
						classes = {'formLabel'},
					},
					gui.GoblinScriptInput{
						value = modifier.num,

						events = {
							change = function(element)
								modifier.num = element.value
								if tonumber(modifier.num) ~= nil and tostring(tonumber(modifier.num)) == modifier.num then
									modifier.num = tonumber(modifier.num)
								end
							end,
						},

						documentation = {
							domains = modifier:Domains(),
							help = string.format("This GoblinScript is used to determine the number of resources this modifier grants."),
							output = "number",
							examples = {
								{
									script = "1",
									text = "The modifier gives the creature 1 resource.",
								},
								{
									script = "3 + level",
									text = "The modifier gives the creature 3 resources, plus 1 for each of the creature's levels.",
								},
							},
							subject = creature.helpSymbols,
							subjectDescription = "The creature affected by this modifier",
							symbols = modifier:HelpAdditionalSymbols(),
						},

					},
				}
			}

			local resourceInfo = resourceTable[modifier.resourceType]
			if resourceInfo ~= nil and CharacterResource.levelingMap[modifier.resourceType] ~= nil then
				--see how far this resource levels up.
				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Resource Level:',
							classes = {'formLabel'},
						},
						gui.GoblinScriptInput{
							value = modifier:try_get("level", "1"),

							events = {
								change = function(element)
									modifier.level = element.value
									if tonumber(modifier.level) ~= nil and tostring(tonumber(modifier.level)) == modifier.level then
										modifier.level = tonumber(modifier.level)
									end
								end,
							},

							documentation = {
								domains = modifier:Domains(),
								help = string.format("This GoblinScript is used to determine the level of resources that this modifier grants."),
								output = "number",
								examples = {
									{
										script = "1",
										text = "The modifier sets the level of the resource to level 1.",
									},
									{
										script = "1 when Character Level < 6 else 2 when Character Level < 14 else 3",
										text = "The modifier grants a level 1 resource when the character is level 1-5, 2 when the character is level 6-13, otherwise a level 3 resource.",
									},
								},
								subject = creature.helpSymbols,
								subjectDescription = "The creature affected by this modifier",
								symbols = modifier:HelpAdditionalSymbols(),
							},
						},
					}
				}

				local resourceLevels = CharacterResource.GetLevelProgression(modifier.resourceType)

				
				for i,level in ipairs(resourceLevels) do
					children[#children+1] = gui.Label{
						width = "auto",
						height = "auto",
						maxWidth = 400,
						fontSize = 14,
						text = string.format("Resource Level %d = %s", i, resourceTable[level].name),
					}
				end

			end

			element.children = children
		end

		Refresh()
	end,
}

CharacterModifier.priority = 10

function CharacterModifier:PriorityEditor()
	return gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			classes = {'formLabel'},
			text = "Priority:",
		},

        gui.Input{
            width = 100,
            characterLimit = 8,
            text = tostring(self.priority),
            change = function(element)
                self.priority = tonumber(element.text) or self.priority
                element.text = tostring(self.priority)
            end,
        }
    }

end

function CharacterModifier:FilterConditionEditor(fieldName)
	fieldName = fieldName or "filterCondition"

	local documentation = nil
	if fieldName == "filterAbility" then
		local symbols = DeepCopy(self:HelpAdditionalSymbols())
		symbols["ability"] = {
			name = "Ability",
			type = "ability",
			desc = "The ability that this modifier may affect.",
		}
		documentation = {
			domains = self:Domains(),
			help = "This GoblinScript is used to determine whether this modifier will affect a given ability. It should produce a result of True if the ability is to be modified, and False otherwise. This GoblinScript is calculated when the game state changes, but it is not recalculated when the ability is used and does not have any usage-dependent criteria for deciding whether to apply the modifier.",
			output = "boolean",
			examples = {
				{
					script = "Ability.Has Attack and not Ability.Spell",
					text = "This modifier only affects regular attacks that are not spells.",
				},
				{
					script = "Ability.Cantrip and Ability.School is Necromancy and Ability.Number of Targets = 1",
					text = "This modifier only affects Necromancy Cantrips that always target exactly one creature.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature affected by this modifier",
			symbols = symbols,
		}
	else
		documentation = {
			domains = self:Domains(),
			help = string.format("This GoblinScript is used to determine whether or not this modifier will be used. If this GoblinScript produces a False result, this modifier will not even appear as an option in dialogs in which this modifier might be used."),
			output = "boolean",
			examples = {
				{
					script = "Type is not undead",
					text = "This modifier will not be applied to undead creatures.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature potentially affected by this modifier",
			symbols = self:HelpAdditionalSymbols(),
		}
	end

	return gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			classes = {'formLabel'},
			text = "Condition:",
		},
		gui.GoblinScriptInput{
			value = self:try_get(fieldName, ""),
			change = function(element)
				if type(element.value) == 'string' and trim(element.value) == '' then
					self[fieldName] = nil
				else
					self[fieldName] = element.value
				end
			end,

			documentation = documentation,
		},
	}
end

function CharacterModifier:PopupEditor()
	local resultPanel

	local behaviorPanel = gui.Panel{
		classes = {'behavior-panel'},

		events = {
			create = function(element)
				local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
				local createEditor = typeInfo.createEditor
				if createEditor ~= nil then
					createEditor(self, element)
				end
			end,
		}
	}

	resultPanel = gui.Panel{
		id = "characterModifierResultPanel",
		classes = {'popup-editor', 'framedPanel'},
		
		styles = {
			Styles.Panel,
			Styles.Default,

			{
				selectors = {'popup-editor'},
				width = 600,
				height = 400,
				bgcolor = 'white',
				halign = 'center',
				valign = 'center',
			},
			{
				selectors = {'content-panel'},
				width = "90%",
				height = "90%",
				halign = 'center',
				valign = 'center',
				flow = "vertical",
			},
			{
				selectors = {'formPanel'},
				width = "auto",
				height = "auto",
				flow = "horizontal",
				pad = 4,
			},
			{
				selectors = {'formLabel'},
				fontSize = 16,
				color = 'white',
				width = 100,
				height = 'auto',
				valign = 'center',
			},
			{
				selectors = {'form-heading'},
				fontSize = 18,
				color = 'white',
				width = 'auto',
				height = 'auto',
				valign = 'center',
			},
			{
				selectors = {'formInput'},
				bgcolor = 'black',
				priority = 10,
				fontSize = 16,
				width = 300,
				valign = 'center',
				height = 22,
				textAlignment = "topLeft",
			},
			{
				selectors = {'dropdown-option'},
				fontSize = 16,
				priority = 20,
			},
			{
				selectors = {'behavior-panel'},
				width = 'auto',
				height = 'auto',
				halign = "left",
				flow = 'vertical',
			},
			{
				selectors = {'form-usage-level-editor'},
				width = 'auto',
				height = 'auto',
				flow = 'vertical',
			},
		},

		data = {
			--notifies this element of 'refreshModifier' on change.
			notifyElement = nil,
		},

		children = {
			gui.Panel{
				classes = {'content-panel'},
				vscroll = true,
				children = {

					gui.Panel{
						classes = {'formPanel'},
						children = {
							gui.Label{
								text = 'Name:',
								classes = {'formLabel'},
							},

							gui.Input{
								text = self.name,
								classes = {'input', 'formInput'},
								events = {
									change = function(element)
										self.name = element.text
										if resultPanel.data.notifyElement then
											resultPanel.data.notifyElement:FireEvent('refreshModifier')
										end
									end,
								},
							},

						}
					},

					gui.Panel{
						classes = {'formPanel'},
						children = {
							gui.Label{
								text = 'Source:',
								classes = {'formLabel'},
							},
							gui.Input{
								text = self.source,
								classes = {'input', 'formInput'},
								events = {
									change = function(element)
										self.source = element.text
										if resultPanel.data.notifyElement then
											resultPanel.data.notifyElement:FireEvent('refreshModifier')
										end
									end,
								},
							},
						}
					},

					gui.Panel{
						classes = {'formPanel'},
						children = {
							gui.Label{
								text = 'Description:',
								classes = {'formLabel'},
							},
							gui.Input{
								text = self.description,
								multiline = true,
								classes = {'input', 'formInput'},
								selfStyle = {
									height = 'auto',
								},
								events = {
									change = function(element)
										self.description = element.text
										if resultPanel.data.notifyElement then
											resultPanel.data.notifyElement:FireEvent('refreshModifier')
										end
									end,
								},
							},
						}
					},

					gui.Panel{
						classes = {'formPanel'},
						children = {
							gui.Label{
								text = 'Behavior:',
								classes = {'formLabel'},
							},
							gui.Dropdown{
								selfStyle = {
									height = 30,
									width = 160,
									fontSize = 16,
								},
								options = CharacterModifier.Types,
								idChosen = self.behavior,
								events = {
									change = function(element)
										self.behavior = element.idChosen
										local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
										if typeInfo.init then
											--initialize our new behavior type.
											typeInfo.init(self)
										end
										behaviorPanel:FireEvent('create')
									end,
								},
							},
						},
					},

					behaviorPanel,

				},

			},
		}
	}

	return resultPanel
end

function CharacterModifier:CreateEditorDialog()
	return gui.Panel{
		
	}
end

function CharacterModifier:Domains()
	return self:try_get("domains", {})
end

function CharacterModifier:SetDomain(domainid)
	self:get_or_add("domains", {})[domainid] = true
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local UpdateDomains = typeInfo.UpdateDomains
	if UpdateDomains then
		UpdateDomains(self)
	end
end

function CharacterModifier:ForceDomains(domains)
	self.domains = dmhub.DeepCopy(domains)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local UpdateDomains = typeInfo.UpdateDomains
	if UpdateDomains then
		UpdateDomains(self)
	end
end

function CharacterModifier:GetSummaryText()
	return string.format("<b>%s</b>--%s", self.name, self.description)
end

--Below here we have functions that can be called on any modifier to see
--how it behaves in various circumstances.


--Have the character modifier modify a creature's attribute.
--   - creature: the creature whose attribute is being modified.
--   - attribute (string): name of the attribute being modified
--   - currentValue (number): current value.
--
--returns a number representing the new value.
function CharacterModifier:Modify(modContext, creature, attribute, currentValue)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior]
	if typeInfo == nil then
		print("No modify function for behavior: " .. self.behavior .. " in behavior " .. json(self))
            return
	end
	local modify = typeInfo.modify
	if modify then
		self:InstallSymbolsFromContext(modContext)
		return modify(self, creature, attribute, currentValue)
	end
	
	return currentValue
end

--Describe a modification. Returns e.g. { key = "Ring of Strength", value = "+1" }
function CharacterModifier:DescribeModification(creature, attribute, currentValue)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior]
	local describe = typeInfo.describe
	if describe then
		return describe(self, creature, attribute, currentValue)
	end
	
	return nil
end

function CharacterModifier:ModifySkillProficiencyBonus(modContext, creature, skillInfo, currentValue, descriptionTable)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior]
	local skillProficiencyBonus = typeInfo.skillProficiencyBonus
	if skillProficiencyBonus then
		self:InstallSymbolsFromContext(modContext)
		return skillProficiencyBonus(self, creature, skillInfo, currentValue, descriptionTable)
	end

	return currentValue
end

--modifies a damage roll. Accepts the damage roll as a string and returns
--a modified string, or the string unchanged if this modification doesn't
--modify the damage roll.
function CharacterModifier:ModifyDamageRoll(modContext, creature, targetCreature, damageRoll)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyDamageRoll = typeInfo.modifyDamageRoll
	if modifyDamageRoll then
		self:InstallSymbolsFromContext(modContext)
		return modifyDamageRoll(self, creature, targetCreature, damageRoll)
	end
	
	return damageRoll
end

--returns information about modification to a damage roll. Returns result
--in the format of { modifier = (CharacterModifier), context = { mod = (CharacterModifier)} } or nil if this modifier isn't relevant
--to the damage roll.
function CharacterModifier:DescribeModifyDamageRoll(modContext, creature, attack, targetCreature, hitOptions)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyDamageRoll = typeInfo.modifyDamageRoll
	if modifyDamageRoll then
		local subtype = self:try_get("subtype", "attacks")

		if subtype == "attacks" then
			if attack == nil then
				return nil
			end
		elseif subtype == "spells" then
			local ability = hitOptions.ability
			if ability == nil or not ability.isSpell then
				return nil
			end
		elseif subtype == "abilities" then
			local ability = hitOptions.ability
			if ability == nil then
				return nil
			end
		end

		self:InstallSymbolsFromContext(modContext)
		return {
			modifier = self,
			context = modContext,
		}
	end

	return nil
end

function CharacterModifier:ShouldApplyDamageModifier(modContext, creature, attack, target, attackOptions)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local hintDamageRoll = typeInfo.hintDamageRoll
	if hintDamageRoll then
		self:InstallSymbolsFromContext(modContext)
		return hintDamageRoll(self, creature, attack, target, attackOptions)
	end

	return nil
end

--hinting comes in the form { result = true/false, justification = {string} }
function CharacterModifier:ShouldApplyD20Modifier(modContext, creature, rollType, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local hintD20Roll = typeInfo.hintD20Roll
	if hintD20Roll then
		self:InstallSymbolsFromContext(modContext)
		return hintD20Roll(self, creature, rollType, options)
	end
	
	return nil
end

--returns information about modification to a D20 roll. Returns result
--in the format of { modifier = (CharacterModifier) } or nil if this modifier isn't relevant
--to the D20 roll.
function CharacterModifier:DescribeModifyD20Roll(modContext, creature, rollType, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local canModifyD20Roll = typeInfo.canModifyD20Roll
	if canModifyD20Roll == nil then
		return nil
	end

	self:InstallSymbolsFromContext(modContext)
	self:InstallSymbolsFromContext(options)

	if canModifyD20Roll(self, creature, rollType, options) then
		return {
			modifier = self,
			context = modContext,
		}
	end

	return nil
end

--modifies a D20 roll using this modifier, this gets the roll as a raw GoblinScript formula.
function CharacterModifier:ModifyD20RollEarly(modContext, creature, rollType, roll, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyD20RollEarly = typeInfo.modifyD20RollEarly
	if modifyD20RollEarly then
		self:InstallSymbolsFromContext(modContext)
		return modifyD20RollEarly(self, creature, rollType, roll, options)
	end
	
	return roll
end

--modifies a D20 roll using this modifier, if it can apply.
function CharacterModifier:ModifyD20Roll(modContext, creature, rollType, roll, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyD20Roll = typeInfo.modifyD20Roll
	if modifyD20Roll then
		self:InstallSymbolsFromContext(modContext)
		return modifyD20Roll(self, creature, rollType, roll, options)
	end
	
	return roll
end

--modifies a D20 roll using this modifier, if it can apply and if it does apply by default.
function CharacterModifier:ModifyD20RollDefaultBehavior(modContext, creature, rollType, roll, options)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyD20Roll = typeInfo.modifyD20Roll
	if modifyD20Roll then
		self:InstallSymbolsFromContext(modContext)
		local hint = self:ShouldApplyD20Modifier(modContext, creature, rollType, options)
		if hint == nil or not hint.result then
			return roll
		end
		return modifyD20Roll(self, creature, rollType, roll, options)
	end
	
	return roll
end


--returns information about modification to an attack roll against us. Returns result
--in the format of { modifier = (CharacterModifier) } or nil if this modifier isn't relevant
--to the D20 roll.
function CharacterModifier:DescribeModifyAttackAgainstUs(modContext, creature, attackerCreature, attack)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyAttackAgainstUs = typeInfo.modifyAttackAgainstUs
	if modifyAttackAgainstUs then
		if typeInfo.filterAttackAgainstUs and not typeInfo.filterAttackAgainstUs(self, creature, attackerCreature, attack) then
			return nil
		end

		return {
			modifier = self,
			context = modContext,
			modFromTarget = true,
		}
	end

	return nil
end

function CharacterModifier:ModifyAttackAgainstUs(modContext, creature, attackerCreature, roll)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyAttackAgainstUs = typeInfo.modifyAttackAgainstUs
	if modifyAttackAgainstUs then
		self:InstallSymbolsFromContext(modContext)
		return modifyAttackAgainstUs(self, creature, attackerCreature, roll)
	end

	return roll
end

--returns information about modification to an attack roll against us. Returns result
--in the format of { modifier = (CharacterModifier) } or nil if this modifier isn't relevant
--to the D20 roll.
function CharacterModifier:DescribeModifyDamageAgainstUs(modContext, creature, attackerCreature, attack)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyDamageAgainstUs = typeInfo.modifyDamageAgainstUs
	if modifyDamageAgainstUs then
		if typeInfo.filterDamageAgainstUs and not typeInfo.filterDamageAgainstUs(self, creature, attackerCreature, attack) then
			return nil
		end

		return {
			modifier = self,
			context = modContext,
			modFromTarget = true,
		}
	end

	return nil
end

function CharacterModifier:ModifyDamageAgainstUs(modContext, creature, attackerCreature, roll)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local modifyDamageAgainstUs = typeInfo.modifyDamageAgainstUs
	if modifyDamageAgainstUs then
		self:InstallSymbolsFromContext(modContext)
		return modifyDamageAgainstUs(self, creature, attackerCreature, roll)
	end

	return roll
end



function CharacterModifier:DoesConsumeResources()
    local costType = self:try_get("resourceCostType", "none")
    if costType ~= "none" then
        return true
    end

	if self:GetResourceRefreshType() == 'none' then
		return false
	end

	return true
end

--the modifier consumes any resource relevant to the modifier, used to trigger its ability
--returns true if a resource was consumed.
--
--respects a consumeResourceOverride which can be set on the modifier to override the kind of resource it consumes. Used in upcasting.
--
--this also triggers events that are associated with the modifier being used.
function CharacterModifier:ConsumeResource(creature, modContext)
	local result = self:ConsumeResourceInternal(creature, modContext)

	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.triggerOnUse ~= nil then
		typeInfo.triggerOnUse(self, creature, modContext)
	end

	return result
end

function CharacterModifier:ConsumeResourceInternal(creature, modContext)

    local costType = self:try_get("resourceCostType", "none")
    print("CONSUME:: IN INTERNAL CONSUME", costType, self:try_get("overrideCost", false))
    if costType == "surges" then
        local resourcesAvailable = creature:GetAvailableSurges()
        local charges = self:try_get("_tmp_symbols", {}).charges or 1
        local cost = ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 0)*charges
        local note = nil
        if modContext ~= nil and modContext.modifier ~= nil then
            note = modContext.modifier.name
        end
        creature:ConsumeSurges(cost, note)
    elseif costType ~= "none" and not self:try_get("overrideCost", false) then
        local charges = self:try_get("_tmp_symbols", {}).charges or 1
        local cost = ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 0)*charges
        print("CONSUME:: EVAL", json(self), self:try_get("resourceCostAmount", "1"), "charges =", charges)
		local resourcesTable = dmhub.GetTable("characterResources")
        print("CONSUME:: ConsumeResources:", creature.resourceid, cost, creature.resourceRefresh)
        creature:ConsumeResource(creature.resourceid, creature.resourceRefresh, cost, string.format("%s", self.name))
    end


	local result = false
	local resourceCost = creature:ResourceToConsume(self.resourceCost)
	if resourceCost ~= nil then
		local resourcesTable = dmhub.GetTable("characterResources")
		local resourceInfo = resourcesTable[resourceCost]
		creature:ConsumeResource(self:try_get("consumeResourceOverride", resourceCost), resourceInfo.usageLimit)
		result = true
	end

	local refreshType = self:GetResourceRefreshType()
	if refreshType == 'none' then
		return result
	elseif refreshType == 'perspell' then
		if modContext ~= nil and modContext.ongoingEffect ~= nil then
			modContext.ongoingEffect:CountdownResource(self.guid, self:GetNumberOfCharges(creature))
			return true
		end
		
		return result
	end

	creature:ConsumeResource(self:GetResourceRefreshId(), refreshType)
	return true
end

function CharacterModifier:HasResourcesAvailable(creature)

    local costType = self:try_get("resourceCostType", "none")
    if costType == "surges" then
        local resourcesAvailable = creature:GetAvailableSurges()
        local cost = ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 0)
        return cost <= resourcesAvailable
    elseif costType ~= "none" then
        local resourcesAvailable = creature:GetHeroicOrMaliceResources()
        local cost = ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 0)
        return cost <= resourcesAvailable
    end


	if self:try_get("resourceCost", "none") ~= "none" then
		local resourceCost = creature:ResourceToConsume(self.resourceCost)
		if resourceCost ~= nil then
			local resourcesTable = dmhub.GetTable("characterResources")
			local resourceInfo = resourcesTable[resourceCost]
			local resourcesAvailable = creature:GetResources()
			local max = resourcesAvailable[resourceCost] or 0
			local usage = creature:GetResourceUsage(resourceCost, resourceInfo.usageLimit)
			local available = max - usage

			if available < 1 then
				return false
			end
		end
	end

	local refreshType = self:GetResourceRefreshType()
	if refreshType == 'none' or refreshType == 'perspell' then
		return true
	end

	return creature:GetResourceUsage(self:GetResourceRefreshId(), refreshType) < self:GetNumberOfCharges(creature)
end

function CharacterModifier:DescribeResourceAvailability(creature, charges, expectedCostOfCurrentCast)
    charges = charges or 1

    local costType = self:try_get("resourceCostType", "none")
    if costType ~= "none" then
        local resourcesAvailable
        local resourceName
        if costType == "surges" then
            resourcesAvailable = creature:GetAvailableSurges()
            resourceName = tr("Surges")
        else
            resourcesAvailable = creature:GetHeroicOrMaliceResources()
            resourceName = creature:GetHeroicResourceName()

            if expectedCostOfCurrentCast ~= nil and not self:try_get("overrideCost", false) then
                resourcesAvailable = resourcesAvailable - (expectedCostOfCurrentCast[creature:GetHeroicOrMaliceId()] or 0)
            end
        end
        local cost = ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 0)*charges
        local result = string.format("%d/%d %s", cost, resourcesAvailable, resourceName)
        return result
    end



	local refreshType = self:GetResourceRefreshType()
	if refreshType == 'none' or refreshType == 'perspell' then
		local resourceCost = creature:ResourceToConsume(self.resourceCost)
		if resourceCost ~= nil then
			local resourcesTable = dmhub.GetTable("characterResources")
			local resourceInfo = resourcesTable[resourceCost]
			local resourcesAvailable = creature:GetResources()
			local max = resourcesAvailable[resourceCost] or 0
			local usage = creature:GetResourceUsage(resourceCost, resourceInfo.usageLimit)
			local available = max - usage

			return string.format("%d/%d %s", available, max, resourceInfo.name)
		end

		return nil
	end

	if refreshType == 'round' and self:GetNumberOfCharges(creature) == 1 then
		if self:HasResourcesAvailable(creature) then
			return "Once per round"
		else
			return "Already used this round"
		end
	end

	local used = creature:GetResourceUsage(self:GetResourceRefreshId(), refreshType)
	local available = self:GetNumberOfCharges(creature)
	return string.format("%d/%d available, refreshes %s", available - used, available, CharacterResource.usageLimitMap[refreshType].refreshDescription)
end

function CharacterModifier:IsResourceCostUpcastable()
	if self:try_get("resourceCostUpcastable", false) == false then
		return false
	end

	local resourceTable = dmhub.GetTable("characterResources")
	local resourceid = self:try_get("resourceCost")
	if resourceid == nil then
		return false
	end

	local resourceInfo = resourceTable[resourceid]
	if resourceInfo == nil or resourceInfo:GetSpellSlot() == nil then
		return false
	end

	return true
end

function CharacterModifier:CalculateResourceDiceFaces(creature)
	local resourceid = creature:ResourceToConsume(self.resourceCost)
	if resourceid == nil then
		return nil
	end

	local resourceTable = dmhub.GetTable("characterResources")
	local resourceInfo = resourceTable[resourceid]
	if resourceInfo == nil or resourceInfo.diceType == "none" then
		return nil
	end

	return tonumber(resourceInfo.diceType)
end

function CharacterModifier:IsResourceCostDice()
	local resourceid = self:try_get("resourceCost")
	if resourceid == nil then
		return false
	end

	local resourceTable = dmhub.GetTable("characterResources")
	local resourceInfo = resourceTable[resourceid]
	if resourceInfo == nil or resourceInfo.diceType == "none" then
		return false
	end

	return true
end

function CharacterModifier:GetNamedResources(modContext, creature, resourceTable)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local getNamedResources = typeInfo.getNamedResources
	if getNamedResources ~= nil then
		self:InstallSymbolsFromContext(modContext)
		getNamedResources(self, creature, resourceTable)
	end
end

function CharacterModifier:GetResistance(modContext, creature, resistanceList)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local getResistances = typeInfo.getResistances
	if getResistances ~= nil then
		self:InstallSymbolsFromContext(modContext)
		getResistances(self, creature, resistanceList)
	end
end

--returns a list of { ongoingEffect = string, duration = number } representing ongoingEffects to apply.
function CharacterModifier:ApplyOngoingEffectsToSelfOnRoll(creature)
	if self:has_key('applyOngoingEffects') and #self.applyOngoingEffects > 0 then
		local result = {}
		for i,cond in ipairs(self.applyOngoingEffects) do
			result[#result+1] = cond
		end
		return result
	end

	return nil
end

function CharacterModifier:HasTriggeredEvent(creature, eventName, targetsOther)
	if self:has_key('triggeredAbility') and self.triggeredAbility.trigger == eventName then

        local subject = self.triggeredAbility:try_get("subject", "self")
        if subject == "self" and targetsOther then
            return false
        end

        if subject ~= "self" and subject ~= "any" and subject ~= "selfandallies" and subject ~= "selfandheroes" and not targetsOther then
            return false
        end

        if self.triggeredAbility:try_get("whenActive", "always") == "combat" and (dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden) then
            return false
        end

        local token = dmhub.LookupToken(creature)
        if token == nil or (self.triggeredAbility:try_get("whenActive", "combat") == "combat" and dmhub.initiativeQueue:HasInitiative(InitiativeQueue.GetInitiativeId(token)) == false) then
            return false
        end

        if not self.triggeredAbility:subjectHasRequiredCondition(creature, creature) and not targetsOther then
            return false
        end
        
		if self:HasResourcesAvailable(creature) == false or (not self.triggeredAbility:CanAfford(dmhub.LookupToken(creature))) then
			return false
		end
		return true
	else
		return false
	end
end

--modContext is a 'mod context' as returned by creature.GetActiveModifiers(). We use it to affect the ongoing effect or other context.
function CharacterModifier:TriggerEvent(creature, eventName, info, modContext, debugLog)
	if self:has_key('triggeredAbility') and self.triggeredAbility.trigger == eventName then
        if self.triggeredAbility:try_get("whenActive", "always") == "combat" and (dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden) then
            return false
        end

		local creatureToken = dmhub.LookupToken(creature)
        if creatureToken == nil then
            if debugLog ~= nil then
                debugLog[#debugLog+1] = {
                    name = self.triggeredAbility.name,
                    success = false,
                    reason = "Token not found",
                }
            end
            return false
        end

        if self.triggeredAbility:try_get("whenActive", "always") == "combat" and dmhub.initiativeQueue:HasInitiative(InitiativeQueue.GetInitiativeId(creatureToken)) == false then
            if debugLog ~= nil then
                debugLog[#debugLog+1] = {
                    name = self.triggeredAbility.name,
                    success = false,
                    reason = "Not in combat",
                }
            end
            return false
        end

		if self:HasResourcesAvailable(creature) == false or (not self.triggeredAbility:CanAfford(creatureToken)) then
            if debugLog ~= nil then
                debugLog[#debugLog+1] = {
                    name = self.triggeredAbility.name,
                    success = false,
                    reason = "Not enough resources",
                }
            end
			return false
		end

        if  ((not self.triggeredAbility:IsMandatory()) and (not creature:TriggeredAbilityEnabled(self.triggeredAbility))) then
            if debugLog ~= nil then
                debugLog[#debugLog+1] = {
                    name = self.triggeredAbility.name,
                    success = false,
                    reason = "Trigger disabled by user",
                }
            end
            return false
        end

		--copy over any symbols tied to the mod to the info symbols the trigger will use.
		if info ~= nil then
			self:InstallSymbolsFromContext(modContext)
			for k,v in pairs(self._tmp_symbols or {}) do
				info[k] = v
			end
		end
		self.triggeredAbility:Trigger(self, creature, info, nil, modContext, {debugLog = debugLog})
		return true
	end

	return false
end

function CharacterModifier:FillTriggeredAbilities(modContext, creature, result)
	if self:has_key("triggeredAbility") then
		result[#result+1] = {
			modifier = self,
			available = self:HasResourcesAvailable(creature),
			resources = self:DescribeResourceAvailability(creature),
			ability = self.triggeredAbility,
		}
	end
end

--log is an optional list which gets populated with modifiers that affects the proficiency.
function CharacterModifier:SkillProficiency(modContext, creature, skillid, currentProficiency, log)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local grantProficiency = typeInfo.grantProficiency
	if grantProficiency ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return grantProficiency(self, creature, 'skill', skillid, currentProficiency, log)
	end

	return currentProficiency
end

--log is an optional list which gets populated with modifiers that affects the proficiency.
function CharacterModifier:SavingThrowProficiency(modContext, creature, attrid, currentProficiency, log)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local grantProficiency = typeInfo.grantProficiency
	if grantProficiency ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return grantProficiency(self, creature, 'save', attrid, currentProficiency, log)
	end

	return currentProficiency
end

function CharacterModifier:CriticalHitsOnly()
	return self:try_get("crit", false)
end

--this is run in two passes.
function CharacterModifier:AccumulateEquipmentProficiencies(modContext, creature, proficiencyTable, pass)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local equipmentProficiency = typeInfo.equipmentProficiency
	if equipmentProficiency ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return equipmentProficiency(self, creature, proficiencyTable, pass)
	end
end

function CharacterModifier:AccumulateLanguages(modContext, creature, languageTable)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local languageProficiency = typeInfo.languageProficiency
	if languageProficiency ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return languageProficiency(self, creature, languageTable)
	end
end

--DEPRECATED
function CharacterModifier:AccumulateDuplicateProficiencies(skills, tools)
end

function CharacterModifier:FillActivatedAbilities(modContext, creature, abilities)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local fillActivatedAbilities = typeInfo.fillActivatedAbilities
	if fillActivatedAbilities ~= nil then
		self:InstallSymbolsFromContext(modContext)
		fillActivatedAbilities(self, creature, abilities)
	end
end

function CharacterModifier:HasFilter()
	if not self:has_key("filterCondition") or self.filterCondition == "" then
        return false
    end

    return true
end

function CharacterModifier:PassesFilter(creature, modContext)
	if not self:has_key("filterCondition") or self.filterCondition == "" then
		return true
	end

	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.filterRequiresRoll then
		--we need roll information to be able to decide whether to filter.
		return true
	end

	-- Install symbols from context if provided
	if modContext ~= nil then
		self:InstallSymbolsFromContext(modContext)
	end

	if ExecuteGoblinScript(self.filterCondition, creature:LookupSymbol(self:try_get("_tmp_symbols", {})), 1, string.format("Should apply modifier %s", self.name)) ~= 0 then
		return true
	else
		return false
	end
end

function CharacterModifier:AutoDescribe()
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local fn = typeInfo.autoDescribe
	if fn ~= nil then
		return fn(self)
	end

	return nil
end

function CharacterModifier:FillConditionImmunities(modContext, creature, result)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local fn = typeInfo.fillConditionImmunities
	if fn ~= nil then
		self:InstallSymbolsFromContext(modContext)
		fn(self, result)
	end
end

function CharacterModifier:ModifyAbility(modContext, creature, ability)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local fn = typeInfo.modifyAbility
	if fn ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return fn(self, creature, ability)
	end

	return ability
end

function CharacterModifier:AlterBaseArmorClass(modContext, creature, armorClass)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local fn = typeInfo.alterBaseArmorClass
	if fn ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return fn(self, creature, armorClass)
	end

	return armorClass
end

function CharacterModifier:FillAuras(modContext, creature, result)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local fn = typeInfo.generateAura
	if fn ~= nil then
		self:InstallSymbolsFromContext(modContext)
		fn(self, creature, result)
	end
end

function CharacterModifier:FillStatusIcons(modContext, creature, result)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior]
	if typeInfo == nil then
		return
	end
	local fn = typeInfo.fillStatusIcons
	if fn ~= nil then
		fn(self, creature, result)
	end
end

local defaultHelpSymbols = {
	aura = {
		name = "Aura",
		type = "aura",
		desc = "The aura that is generating this modifier.\n\n<color=#ffaaaa><i>This field is only available for modifiers that are generated by an aura.</i></color>"
	},
	ongoingeffect = {
		name = "Ongoing Effect",
		type = "ongoingeffect",
		desc = "The Ongoing Effect that is generating this modifier.\n\n<color=#ffaaaa><i>This field is only available for modifiers that are generated by an ongoing effect.</i></color>"
	},
	stacks = {
		name = "Stacks",
		type = "number",
		desc = "The number of stacks of the ongoing effect that is generating this modifier.\n\n<color=#ffaaaa><i>This field is only available for modifiers that are generated by an ongoing effect.</i></color>"
	},
}

CharacterModifier.defaultHelpSymbols = defaultHelpSymbols

function CharacterModifier:HelpAdditionalSymbols(symbols)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	local result = typeInfo.helpSymbols or defaultHelpSymbols
	if type(result) == "function" then
		result = result(self, defaultHelpSymbols)
	end

	if symbols ~= nil then
		result = dmhub.DeepCopy(result)
		for k,sym in pairs(symbols) do
			result[k] = sym
		end
	end

	return result
end

function CharacterModifier:RefreshGameState(modContext, creature)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.RefreshGameState ~= nil then
		self:InstallSymbolsFromContext(modContext)
		typeInfo.RefreshGameState(creature, self)
	end
end

function CharacterModifier:PreventsSpells(modContext, creature)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.preventsSpells ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return typeInfo.preventsSpells(self, creature)
	end
end

function CharacterModifier:PreventsEquipment(modContext, creature)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.preventsEquipment ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return typeInfo.preventsEquipment(self, creature)
	end
end

function CharacterModifier:ModifyAttackAttribute(modContext, creature, weapon)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.attackAttribute ~= nil then
		self:InstallSymbolsFromContext(modContext)
		return typeInfo.attackAttribute(self, creature, weapon)
	end

	return nil
end

function CharacterModifier:CanBestowConditions()
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	return typeInfo.bestowConditions ~= nil
end

function CharacterModifier:BestowConditions(modContext, creature, conditionsRecorded, conditionExplanations)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.bestowConditions ~= nil then
		self:InstallSymbolsFromContext(modContext)
		typeInfo.bestowConditions(self, creature, conditionsRecorded, conditionExplanations)
	end
end

function CharacterModifier:FillModifiers(modContext, creature, result)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.fillModifiers ~= nil then
		self:InstallSymbolsFromContext(modContext)
		typeInfo.fillModifiers(self, creature, result)
	end
end

function CharacterModifier:AddModifiers(creature, result)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.addModifiers ~= nil then
		return typeInfo.addModifiers(self, creature, result)
	end
end

function CharacterModifier.OnDeserialize(self)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.Deserialize ~= nil then
		typeInfo.Deserialize(self)
	end
end

function CharacterModifier:ApplyToRoll(context, casterCreature, targetCreature, rollType, roll)
	return roll
end

function CharacterModifier:ModifyRollProperties(context, creature, rollProperties, targetCreature)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.modifyRollProperties ~= nil then
		self:InstallSymbolsFromContext(context)
		typeInfo.modifyRollProperties(self, creature, rollProperties, targetCreature)
	end
end

function CharacterModifier:OnTokenRefresh(context, creature, token)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.onTokenRefresh ~= nil then
        typeInfo.onTokenRefresh(self, creature, token)
    end
end