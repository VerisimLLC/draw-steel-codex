local mod = dmhub.GetModLoading()

--This file implements the "Modify D20 Rolls" character modifier.
--it's a good example file for implementing your own character modifier.

local d20ModifierTypes = {
	{
		id = 'all',
		text = 'All D20 Rolls',
	},
	{
		id = 'attack',
		text = 'Attack Rolls',
	},
	{
		id = 'save',
		text = 'Saving Throws',
	},
	{
		id = 'skill',
		text = 'Skill Rolls',
	},
	{
		id = 'initiative',
		text = 'Initiative Rolls',
	},
}


local DoesD20ModifierPassFilter = function(self, cond, creature, rollType, options, explanation)
	local lookupFunction

	if type(cond) == "string" then
		if rollType == "attack" then

			
			lookupFunction = creature:LookupSymbol(self:AppendSymbols{
				attack = GenerateSymbols(options.attack),
				target = GenerateSymbols(options.target),
				dicefaces = self:CalculateResourceDiceFaces(creature),
			})

			if explanation ~= nil then
				--we can generate a full explanation for attacks here.
				local e = dmhub.ExplainDeterministicGoblinScript(cond, lookupFunction, GoblinScriptSymbolDocument)
				for i,entry in ipairs(e) do
					explanation[#explanation+1] = entry
				end
			end
		else

			lookupFunction = creature:LookupSymbol(self:AppendSymbols{
				proficient = options.proficient,
				dicefaces = self:CalculateResourceDiceFaces(creature),
			})
		end

		cond = ExecuteGoblinScript(cond, lookupFunction, 0, string.format("Should %s modifier apply to d20 roll", self.name)) ~= 0
	end

	return cond
end

local ShouldD20ModifierApply = function(self, creature, rollType, options)

	options = options or {}
	local match = self.subtype == 'all' or self.subtype == rollType
	if not match then
		if self.subtype == 'skill' and string.starts_with(rollType, "skill:") then
			local specificSkill = string.sub(rollType, 7)
			if self.skill == 'all' or self.skill == specificSkill or (Skill.SkillsById[specificSkill] ~= nil and Skill.SkillsById[specificSkill].attribute == self.skill) then
				
				match = true
			end
		end

		if not match then
			match = self.subtype == 'save' and string.starts_with(rollType, "save:") and (self.save == 'all' or self.save == string.sub(rollType, 6) or self.save == options.condition)

			--it can also match if it's a save and the damage type matches the save type.
			if not match and self.subtype == 'save' and options.damagetype ~= nil then
				local damageTypesTable = dmhub.GetTable(DamageType.tableName)
				if damageTypesTable[self.save] ~= nil and damageTypesTable[self.save].name == options.damagetype then
					match = true
				end
			end
		end
	end

	return match
end

local d20AdditionalHelpSymbols = {
	proficient = {
		name = "Proficient",
		type = "boolean",
		desc = "True if the character's proficiency bonus is being applied to this roll.",
	}
}

local d20AttackAdditionalHelpSymbols = {
	attack = {
		name = "Attack",
		type = "attack",
		desc = "The attack being used for this roll.",
	},
	target = {
		name = "Target",
		type = "creature",
		desc = "The creature that is being targeted with this attack.",
	},
}

local AppendExplanations = function(resultTable, positiveExplanations, negativeExplanations)
	local append = cond(resultTable.result, positiveExplanations, negativeExplanations)
	for _,item in ipairs(append) do
		resultTable.justification[#resultTable.justification+1] = item
	end

	return resultTable
end

local d20ModifyOptions = {
	{
		id = "roll",
		text = "Custom Formula",
	},
	{
		id = "advantage",
		text = "Advantage",
	},
	{
		id = "disadvantage",
		text = "Disadvantage",
	},
	{
		id = "proficient",
		text = "Proficiency",
	},
	{
		id = "expert",
		text = "Expertise",
	},
}



CharacterModifier.RegisterType('d20', "Modify D20 Rolls")

--a 'd20' modifier has the following properties:
--  - modifyType: (optional) enum of how we are modifying: 'roll' (default -- use modifyRoll), 'advantage', 'disadvantage', 'proficient', 'expert'
--  - modifyRoll: text to be added to the rolls.
--  - subtype: type of rolls to modify, 'all', 'attack', 'skill', 'save', 'initiative'
--  - skill: apply to this specific skill. Valid when subtype = 'skill'
--  - skillSpecialization: apply to this sub-specialization of a skill. Valid when subtype = 'skill'.
--  - save: apply to this specific saving throw. Valid when subtype = 'save'
--  - savevsmagic: (optional) present on saves and true means that it will only apply vs magical effects.
--  - applyOngoingEffects = nil or list of {ongoingEffect = id, duration=nil|number} elements that are applied to self on use.
--  - activationCondition = true = always, false = never, or goblin script which describes when to activate.
--  - filterCondition (optional): additional filter condition that will control whether this shows up at all.
--  - conditions (DEPRECATED): List of conditions under which to activate.
--            - { type: 'always', 'never' }
CharacterModifier.TypeInfo.d20 = {
	filterRequiresRoll = true,

	init = function(modifier)
		modifier.modifyType = 'advantage'
		modifier.modifyRoll = ''
		modifier.subtype = 'all'
		modifier.skill = 'all'
		modifier.save = 'all'
		modifier.activationCondition = true
	end,

	triggerOnUse = function(modifier, creature, modContext)
		if modifier:try_get("hasCustomTrigger", false) and modifier:has_key("customTrigger") then
			modifier.customTrigger:Trigger(modifier, creature, modifier:AppendSymbols{}, nil, modContext)
		end
	end,

	--when constructing the condition filter, will consult this to get symbols.
	helpSymbols = function(modifier, baseSymbols)
		local result = DeepCopy(baseSymbols)

		local additionalSymbols = d20AdditionalHelpSymbols
		if modifier.subtype == "attack" then
			additionalSymbols = d20AttackAdditionalHelpSymbols
		end

		for k,v in pairs(additionalSymbols) do
			result[k] = v
		end

		return result
	end,

	--this will return true if we should check this option by default.
	hintD20Roll = function(self, creature, rollType, options)
		if self:HasResourcesAvailable(creature) == false then
			return {
				result = false,
				justification = {"You have expended all uses of this ability."},
			}
		end

		options = options or {}

		if self.subtype == "skill" and self:try_get("skill", "all") ~= "all" and self:try_get("skillSpecialization", "all") ~= "all" and (options.specializations == nil or options.specializations[self.skillSpecialization] == nil) then
			local skillTable = dmhub.GetTable(Skill.tableName)
			local skillInfo = skillTable[self.skill]
			if skillInfo == nil then
				dmhub.Debug("Could not find skill info for specialization")
			end
			if skillInfo ~= nil then
				local specialization = Skill.GetSpecializationById(skillInfo, self.skillSpecialization)
				if specialization == nil then
					dmhub.Debug("Could not find specialization")
				end
				if specialization ~= nil then
					return {
						result = false,
						justification = {string.format("This check does not involve %s", specialization.text)},
					}
				end
			end
		end

		local positiveExplanation = {}
		local negativeExplanation = {}

		local savevsmagic = self:try_get("savevsmagic", false)

		if savevsmagic and self.subtype == "save" then
			if not options.magic then
				return {
					result = false,
					justification = {"This feature only applies to spells & magic."},
				}
			else
				positiveExplanation[#positiveExplanation+1] = "This feature works against spells & magic"
			end
		end

		local cond = self:try_get("activationCondition")
		if cond ~= nil then

			local explanation = {}
			cond = DoesD20ModifierPassFilter(self, cond, creature, rollType, options, explanation)

			return AppendExplanations({
				result = cond,
				justification = explanation,
			}, positiveExplanation, negativeExplanation)
		end

		for i,cond in ipairs(self:try_get('conditions', {})) do
			if cond.type == 'always' then
				return AppendExplanations({
					result = true,
					justification = {},
				}, positiveExplanation, negativeExplanation)
			end
		end

		return AppendExplanations({
			result = false,
			justification = {},
		}, positiveExplanation, negativeExplanation)
	end,

	--this should return true if the roll should show up at all in the dialog.
	canModifyD20Roll = function(self, creature, rollType, options)
		local result = ShouldD20ModifierApply(self, creature, rollType, options)
		if result and self:try_get("filterCondition") ~= nil and self.filterCondition ~= "" then
			result = DoesD20ModifierPassFilter(self, self.filterCondition, creature, rollType, options)
		end
		return result
	end,

	modifyD20RollEarly = function(self, creature, rollType, roll, options)
		local modifyType = self:try_get("modifyType", "roll")
		if modifyType ~= "proficient" and modifyType ~= "expert" then
			--proficient and expert apply early, everything else doesn't.
			return roll
		end

		local match = ShouldD20ModifierApply(self, creature, rollType, options)

		if match then
			roll = string.format("(%s) where ProficiencyMultiplier = %d", roll, cond(modifyType == "proficient", 1, 2))
		end

		return roll
	end,

    --this code actually modifies the roll.
	modifyD20Roll = function(self, creature, rollType, roll, options)
		local modifyType = self:try_get("modifyType", "roll")
		if modifyType == "proficient" or modifyType == "expert" then
			--proficient and expert are applied as early modifications.
			return roll
		end

		local match = ShouldD20ModifierApply(self, creature, rollType, options)

		if match then
			local appendText = nil

			if modifyType ~= "roll" then
				appendText = modifyType
			else

				local lookupFunction = creature:LookupSymbol(self:AppendSymbols{
					dicefaces = self:CalculateResourceDiceFaces(creature),
				})

				appendText = dmhub.EvalGoblinScript(self.modifyRoll, lookupFunction)
			end

			local result = dmhub.NormalizeRoll(roll .. ' + ' .. appendText)
			return result
		end

		return roll
	end,

    --the implementation of the editor for this kind of modifier.
	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true

		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end
			local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}

			local children = {}

			local options = {}

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Type:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
						options = d20ModifierTypes,
						idChosen = modifier.subtype,

						events = {
							change = function(element)
								modifier.subtype = element.idChosen
								Refresh()
							end,
						},
					},
				}
			}

			if modifier.subtype == 'skill' then

				local skillOptions = {}
				skillOptions[#skillOptions+1] = {
					id = 'all',
					text = 'All',
				}

				for i,attrid in ipairs(creature.attributeIds) do
					skillOptions[#skillOptions+1] = {
						id = attrid,
						text = creature.attributesInfo[attrid].description,
					}
				end

				for i,skillInfo in ipairs(Skill.SkillsInfo) do
					skillOptions[#skillOptions+1] = {
						id = skillInfo.id,
						text = string.format("%s (%s)", skillInfo.name, creature.attributesInfo[skillInfo.attribute].description),
					}
				end


				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Skill:',
							classes = {'formLabel'},
						},
						gui.Dropdown{
							selfStyle = {
								height = 30,
								width = 260,
								fontSize = 16,
							},
							options = skillOptions,
							idChosen = modifier:try_get('skill', 'all'),

							events = {
								change = function(element)
									modifier.skill = element.idChosen
									Refresh()
								end,
							},
						},
					}
				}

				local skillTable = dmhub.GetTable(Skill.tableName)
				local skillInfo = nil
				local skillid = modifier:try_get("skill", "all")

				if skillid ~= "all" then
					skillInfo = skillTable[skillid]
				end

				if skillInfo ~= nil and #Skill.GetSpecializations(skillInfo) > 0 then
					children[#children+1] = gui.Panel{
						classes = {'formPanel'},
						children = {
							gui.Label{
								text = 'Specialty:',
								classes = {'formLabel'},
							},
							gui.Dropdown{
								selfStyle = {
									height = 30,
									width = 260,
									fontSize = 16,
								},
								options = Skill.GetSpecializationDropdownOptions(skillInfo),
								idChosen = modifier:try_get('skillSpecialization', 'all'),

								events = {
									change = function(element)
										modifier.skillSpecialization = element.idChosen
									end,
								},
							},
						}
					}
				end

			elseif modifier.subtype == 'save' then

				local saveOptions = creature.GetSavingThrowDropdownOptions()
				table.insert(saveOptions, 1, {
					id = "all",
					text = "All",
				})


				saveOptions[#saveOptions+1] = {
					id = "concentration",
					text = "Maintain Concentration",
				}


				local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
				local conditionOptions = {}

				conditionOptions[#conditionOptions+1] = {
					id = "death",
					text = "Against Death",
				}

				for k,cond in pairs(conditionsTable) do
					if cond.immunityPossible then
						conditionOptions[#conditionOptions+1] = {
							id = k,
							text = string.format("Against %s", cond.name),
						}
					end
				end


				table.sort(conditionOptions, function(a,b) return a.text < b.text end)

				for _,option in ipairs(conditionOptions) do
					saveOptions[#saveOptions+1] = option
				end


				local upper_case_first_letter = function(str)
					return (string.gsub(str, "^%l", string.upper))
				end
				


				local damageOptions = {}

				local damageTypesTable = dmhub.GetTable(DamageType.tableName)

				for k,damageType in pairs(damageTypesTable) do
					damageOptions[#damageOptions+1] = {
						id = k,
						text = string.format("Against %s Damage", upper_case_first_letter(damageType.name)),
					}
				end


				table.sort(damageOptions, function(a,b) return a.text < b.text end)

				for _,option in ipairs(damageOptions) do
					saveOptions[#saveOptions+1] = option
				end


				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Save:',
							classes = {'formLabel'},
						},
						gui.Dropdown{
							selfStyle = {
								height = 30,
								width = 260,
								fontSize = 16,
							},
							options = saveOptions,
							idChosen = modifier:try_get('save', 'all'),

							events = {
								change = function(element)
									modifier.save = element.idChosen
								end,
							},
						},
					}
				}

				children[#children+1] = gui.Check{
					style = {
						height = 30,
						width = 160,
						fontSize = 18,
						halign = "left",
					},

					text = "vs Magic & Spells Only",
					value = modifier:try_get("savevsmagic", false),
					change = function(element)
						modifier .savevsmagic = cond(element.value, true, nil)
					end,
				}

			end

			children[#children+1] = modifier:UsageLimitEditor()
			children[#children+1] = modifier:ResourceCostEditor()
			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 12,
				text = "The condition determines whether this modifier will be offered as an option for d20 rolls",
			}

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				children = {
					gui.Label{
						text = 'Modification:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
							vmargin = 4,
						},
						options = d20ModifyOptions,
						idChosen = modifier:try_get("modifyType", "roll"),
						change = function(element)
							modifier.modifyType = element.idChosen
							Refresh()
						end,
					},
				},
			}

			if modifier:try_get("modifyType", "roll") == "roll" then

				local helpSymbols = DeepCopy(modifier:HelpAdditionalSymbols())
				helpSymbols.dicefaces = GoblinScriptDocs.dicefaces


				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Modify Roll:',
							classes = {'formLabel'},
						},
						gui.GoblinScriptInput{
							value = modifier.modifyRoll,

							events = {
								change = function(element)
									modifier.modifyRoll = element.value
								end,
							},

							documentation = {
								domains = modifier:Domains(),
								help = string.format("This GoblinScript is appended to d20 rolls that this modifier affects."),
								output = "roll",
								examples = {
									{
										script = "advantage",
										text = "Rolls will be made with advantage",
									},
									{
										script = "3",
										text = "3 will be added to rolls",
									},
									{
										script = "Dexterity Modifier",
										text = "The creature's Dexterity Modifier will be added to rolls",
									},
								},
								subject = creature.helpSymbols,
								subjectDescription = "The creature affected by this modifier",
								symbols = helpSymbols,
							},

						},
					}
				}
			end


			--DEPRECATED: apply ongoing effects. We now use ability triggers instead.
			if #modifier:try_get("applyOngoingEffects", {}) ~= 0 then
				children[#children+1] = gui.Label{
					text = 'Applies Ongoing Effects to you when used:',
					classes = {'form-heading'},
				}

				local ongoingEffectsFound = {}
				for i,cond in ipairs(modifier:try_get('applyOngoingEffects', {})) do
					ongoingEffectsFound[cond.ongoingEffect] = true
					local ongoingEffect = ongoingEffectsTable[cond.ongoingEffect]
					if ongoingEffect ~= nil then

						children[#children+1] = gui.Label{
							text = ongoingEffect.name,
							classes = {'formLabel'},
							width = 200,
							height = 30,
							gui.DeleteItemButton{
								width = 16,
								height = 16,
								valign = 'center',
								halign = 'right',
								click = function(element)
									table.remove(modifier.applyOngoingEffects, i)
									Refresh()
								end,
							},
						}

						local idChosen = 'rounds'
						if cond.duration == 0 then
							idChosen = 'turn'
						elseif not cond.duration then
							idChosen = 'indefinite'
						elseif cond.durationUntilEndOfTurn then
							idChosen = 'rounds_end_turn'
						end
						children[#children+1] = gui.Dropdown{
							selfStyle = {
								height = 30,
								width = 260,
								fontSize = 16,
								vmargin = 4,
							},
							options = CharacterOngoingEffect.durationOptions,
							idChosen = idChosen,
							change = function(element)
								if element.idChosen == 'turn' then
									cond.duration = 0
								elseif element.idChosen == 'rounds' or element.idChosen == 'rounds_end_turn' then
									cond.duration = tonumber(cond.duration) or 1
									if cond.duration <= 0 then
										cond.duration = 1
									end

									cond.durationUntilEndOfTurn = (element.idChosen == 'rounds_end_turn')
								else
									cond.duration = nil
								end
								Refresh()
							end,
						}

						if idChosen == 'rounds' or idChosen == 'rounds_end_turn' then
							children[#children+1] = gui.Input{
								selfStyle = {
									height = 30,
									width = 60,
									fontSize = 16,
									vmargin = 4,
								},
								text = tostring(cond.duration),
								events = {
									change = function(element)
										cond.duration = math.floor(tonumber(element.text)) or 1
										Refresh()
									end,
								},
							}
						end
					end
				end

				local possibleOngoingEffects = {
					{
						id = 'add',
						text = 'Add Ongoing Effect...',
					}
				}
				for k,ongoingEffect in pairs(ongoingEffectsTable) do
					if not ongoingEffectsFound[k] then
						possibleOngoingEffects[#possibleOngoingEffects+1] = {
							id = k,
							text = ongoingEffect.name,
						}
					end
				end
				children[#children+1] = gui.Dropdown{
					selfStyle = {
						height = 30,
						width = 260,
						fontSize = 16,
					},
					
					options = possibleOngoingEffects,
					idChosen = 'add',

					change = function(element)
						if ongoingEffectsTable[element.idChosen] then
							modifier.applyOngoingEffects = modifier:try_get('applyOngoingEffects', {})
							modifier.applyOngoingEffects[#modifier.applyOngoingEffects+1] = { ongoingEffect = element.idChosen }
							Refresh()
						end
					end,
				}
			end

			local cond = modifier:try_get("activationCondition")
			if cond == nil then
				for i,cond in ipairs(modifier:get_or_add('conditions', {})) do
					if cond.type == "always" then
						cond = true
					end
				end
			end

			if cond == nil then
				cond = false
			end

			local conditionType = "condition"
			if cond == true then
				conditionType = "always"
			elseif cond == false then
				conditionType = "never"
			end

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					text = "Activation:",
					classes = {"formLabel"},
				},

				gui.Dropdown{
					height = 30,
					width = 260,
					fontSize = 16,
					idChosen = conditionType,
					options = {
						{
							id = "never",
							text = "Never",
						},
						{
							id = "always",
							text = "Always",
						},
						{
							id = "condition",
							text = "Condition",
						},
					},
					change = function(element)
						if element.idChosen ~= conditionType then
							modifier.conditions = nil --get rid of deprecated condition.
							if element.idChosen == "never" then
								modifier.activationCondition = false
							elseif element.idChosen == "always" then
								modifier.activationCondition = true
							else
								modifier.activationCondition = ""
							end
							Refresh()
						end
					end,
				}
			}

			if type(cond) == "string" then

				local helpSymbols = {}
				if modifier.subtype == "attack" then
					helpSymbols = d20AttackAdditionalHelpSymbols
				end

				helpSymbols = DeepCopy(helpSymbols)
				helpSymbols.dicefaces = GoblinScriptDocs.dicefaces

				children[#children+1] = gui.GoblinScriptInput{
					placeholderText = "Enter condition...",
					value = cond,
					change = function(element)
						modifier.activationCondition = element.value
						Refresh()
					end,

					documentation = {
						domains = modifier:Domains(),
						help = string.format("This GoblinScript is used to determine whether or not this modifier will be applied to a given roll. It determines the default value for the checkbox that appears next to it when the roll occurs. The player can always override the value manually."),
						output = "boolean",
						examples = {
							{
								script = "Proficient",
								text = "The checkbox will be checked by default if proficiency applies to this roll.",
							},
						},
						subject = creature.helpSymbols,
						subjectDescription = "The creature affected by this modifier",
						symbols = modifier:HelpAdditionalSymbols(helpSymbols),
					},

				}
			end

			children[#children+1] = gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 12,
				text = "The activation criteria determines whether the modifier will default to on or off when a roll occurs.",
			}

			children[#children+1] = gui.Check{
				style = {
					height = 30,
					width = 160,
					fontSize = 18,
					halign = "left",
				},

				text = "Has Custom Trigger",
				value = modifier:try_get("hasCustomTrigger", false),
				change = function(element)
					modifier.hasCustomTrigger = element.value
					if element.value and modifier:has_key("customTrigger") == false then
						modifier.customTrigger = TriggeredAbility.Create{
							trigger = "d20roll",
						}
					end
					Refresh()
				end,
			}

			if modifier:try_get("hasCustomTrigger", false) then
				children[#children+1] = gui.Button{
					classes = {"sizeL"},
					halign = "left",
					height = 50,
					text = "Edit Trigger",
					click = function(element)
						if modifier:has_key("customTrigger") then
							element.root:AddChild(modifier.customTrigger:ShowEditActivatedAbilityDialog{
								title = "Edit Trigger",
								hide = {"appearance", "abilityInfo"},
							})
						end
					end,
				}
			end


			element.children = children
		end

		Refresh()
	end,
}
