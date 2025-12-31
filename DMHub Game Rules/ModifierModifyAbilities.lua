local mod = dmhub.GetModLoading()

--This file implements the "Modify Abilities" modifier that allows a modifier to affect
--abilities that a creature has.

CharacterModifier.RegisterType('modifyability', "Modify Abilities")

--------------------------------------------------------------------
--modify ability modifiers can modify the abilities a creature has.
--------------------------------------------------------------------

local abilityModifierOptionsById = {}
local abilityModifierOptions = {}

function CharacterModifier.RegisterAbilityModifier(options)
	abilityModifierOptionsById[options.id] = options

	if options.index == nil then
		options.index = #abilityModifierOptions+1
	end

	abilityModifierOptions[options.index] = options
end

CharacterModifier.RegisterAbilityModifier
	{
		id = "none",
		text = "Add Attribute...",
	}

--[[ CharacterModifier.RegisterAbilityModifier
	{
		id = "numactions",
		text = "Number of Actions",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if operation == "Set" then
				ability.actionNumber = value
				return true
			end

			if type(ability.actionNumber) ~= "number" and type(ability.actionNumber) ~= "string" then
				--Not implemented to modify tables!
				return true
			end

			if operation == "Multiply" then
				ability.actionNumber = string.format("(%s) * (%s)", tostring(ability.actionNumber), value)
			else
				ability.actionNumber = string.format("(%s) + (%s)", tostring(ability.actionNumber), value)
			end
		end,
	} ]]

CharacterModifier.RegisterAbilityModifier
	{
		id = "cost",
		text = "Heroic Resource Cost",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if not ability:has_key("resourceCost") then
				if creature:IsHero() then
					ability.resourceCost = "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca" --Heroic Resource
				else
					ability.resourceCost = "101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8" --Malice Resource
				end
				--When we add a resourceCost, a value of 1 is implied.
				value = value -1
			end

			if operation == "Set" then
				ability.resourceNumber = value
			elseif operation == "Multiply" then
				ability.resourceNumber = string.format("(%s) * (%s)", ability.resourceNumber, value)
			else
				ability.resourceNumber = string.format("(%s) + (%s)", ability.resourceNumber, value)
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
{
	id = "targettype",
	text = "Target Type",
	operations = { "targeting" },
	set = function(modifier, creature, ability, attributes)
		ability.targetType = attributes.targeting
		if attributes.allegiance == "all" then
			ability.objectTarget = false
			ability.targetAllegiance = nil
		elseif attributes.allegiance == "all_and_objects" then
			ability.objectTarget = true
			ability.targetAllegiance = nil
		elseif attributes.allegiance == "ally" then
			ability.objectTarget = false
			ability.targetAllegiance = "ally"
		elseif attributes.allegiance == "enemy" then
			ability.objectTarget = false
			ability.targetAllegiance = "enemy"
		else
			ability.objectTarget = false
			ability.targetAllegiance = nil
		end
		ability.radius = attributes.radius
		return true
	end,
}

CharacterModifier.RegisterAbilityModifier
	{
		id = "numtargets",
		text = "Number of Targets",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if operation == "Set" then
				ability.numTargets = value
			elseif operation == "Multiply" then
				ability.numTargets = string.format("(%s) * (%s)", ability.numTargets, value)
			else
				ability.numTargets = string.format("(%s) + (%s)", ability.numTargets, value)
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "range",
		text = "Range",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			local val = nil
			if operation == "Set" then
				val = tonumber(value)
			elseif operation == "Multiply" then
				val = tonum(ability.range) * tonum(value)
			else
                if type(ability.range) == "string" and tonumber(ability.range) == nil then
                    val = string.format("(%s) + (%s)", ability.range, value)
                else
				    val = tonum(ability.range) + tonum(value)
                end
			end

			if val ~= nil then
				ability.range = val
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "proximitytargeting",
		text = "Set Proximity Targeting",
		operations = { "Bool" },
		set = function(modifier, creature, ability, operation, value)
			ability.proximityTargeting = true
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "proximityrange",
		text = "Proximity Range",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if operation == "Set" then
				ability.proximityRange = value
			elseif operation == "Multiply" then
				ability.proximityRange = string.format("%s * (%s)", ability.proximityRange, value)
			else
				ability.proximityRange = string.format("%s + (%s)", ability.proximityRange, value)
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "healroll",
		text = "Healing Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityHealBehavior" then
					behavior.roll = string.format("%s+(%s)", behavior.roll, value)
				end
			end
		end,
	}

--[[ CharacterModifier.RegisterAbilityModifier
	{
		id = "attackroll",
		text = "Attack Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityAttackBehavior" then
					behavior:AppendHitModification(ability, tostring(value), modifier:try_get("_tmp_symbols"))
				end
			end
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to attack rolls for attacks this modifier affects."),
			output = "roll",
			examples = {
				{
					script = "1",
					text = "1 is added to the attack roll.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the attack roll, or 4 when the attacking creature is above level 10.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with damage.",
					examples = {
						"2 when Target.Hitpoints < Target.Maximum Hitpoints",
						"5 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	} ]]


--[[ CharacterModifier.RegisterAbilityModifier
	{
		id = "attackdamageroll",
		text = "Attack Damage Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityAttackBehavior" then
					if type(value) == "table" then
						value = value:ToText()
					end
					behavior:AppendDamageModification(ability, tostring(value), modifier:try_get("_tmp_symbols"), {
						name = modifier.name,
						description = modifier:try_get("modifyDescription", ""),
					})
				end
			end
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to attack damage rolls for attacks this modifier affects."),
			output = "roll",
			examples = {
				{
					script = "1",
					text = "1 is added to the damage.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the damage, or 4 when the attacking creature is above level 10.",
				},
				{
					script = "1d6 [fire]",
					text = "1d6 Fire damage is added to the damage.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with damage.",
					examples = {
						"1d6 + 1d6 when Target.Hitpoints < Target.Maximum Hitpoints",
						"1d8 + 2d8 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	} ]]

CharacterModifier.RegisterAbilityModifier
	{
		id = "directdamageroll",
		text = "Direct Damage Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityDamageBehavior" then
					behavior.roll = string.format("%s+(%s)", behavior.roll, value)
				end
			end
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to direct damage rolls for abilities this modifier affects."),
			output = "roll",
			examples = {
				{
					script = "1",
					text = "1 is added to the damage.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the damage, or 4 when the attacking creature is above level 10.",
				},
				{
					script = "1d6 [fire]",
					text = "1d6 Fire damage is added to the damage.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with damage.",
					examples = {
						"1d6 + 1d6 when Target.Hitpoints < Target.Maximum Hitpoints",
						"1d8 + 2d8 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	}

--The "replaceBehavior" used to be false (default) for placing new behaviors at the end, and true for replacing behaviors.
--Now it has three modes, "after", "before", and "replace". This converts an old modifier to the new mode.
local function ReplaceBehaviorToEnum(mode)
	if mode == false then
		return "after"
	end

	if mode == true then
		return "before"
	end

	return mode
end

--a 'modifyability' modifier has the following properties:
--modifyDescription (string): a string to add to the ability's description describing what was changed.
--filterAbility (string) optional: GoblinScript to determine if an ability gets modified.
--attributes (list of { id = string, operation = string|nil, value = string}): List of attributes we modify
--ability: ActivatedAbility -- we use it for the behaviors.
--actionResourceId: (optional) -- if set, this overrides the action resource id.
--cannotModifyAction: (optional) -- if set this modifier can't override actions. Used in ActivatedAbilityAugmentAbilityBehavior
--unconditional: (optional) -- if set then filter condition won't be shown. This is for when the modification always applies, e.g. for ammo.
CharacterModifier.TypeInfo.modifyability = {
	init = function(modifier)
		modifier.attributes = {}
		modifier.ability = ActivatedAbility.Create{
			abilityModification = true,
		}
	end,

	willModifyAbility = function(modifier, creature, ability)
        local keywords = modifier:try_get("keywords", {})

        for keyword,_ in pairs(keywords) do
            if not ability:HasKeyword(keyword) then
                return false
            end
        end
		if modifier:try_get("filterAbility", "") ~= '' then
			modifier._tmp_symbols = modifier:get_or_add("_tmp_symbols", {})
			modifier._tmp_symbols.ability = GenerateSymbols(ability)
			local result = ExecuteGoblinScript(modifier.filterAbility, GenerateSymbols(creature, modifier._tmp_symbols), 0, string.format("Should modify ability: %s", ability.name))
			if result == 0 then
				return false
			end
		end

		return true
	end,

	modifyAbility = function(modifier, creature, ability)
        local keywords = modifier:try_get("keywords", {})
        for keyword,_ in pairs(keywords) do
            if not ability:HasKeyword(keyword) then
                return ability
            end
        end
		if modifier:try_get("filterAbility", "") ~= '' then
			modifier._tmp_symbols = modifier:get_or_add("_tmp_symbols", {})
			modifier._tmp_symbols.ability = GenerateSymbols(ability)
			local result = ExecuteGoblinScript(modifier.filterAbility, GenerateSymbols(creature, modifier._tmp_symbols), 0, string.format("Should modify ability: %s", ability.name))
			if result == 0 then
				return ability
			end
		end

		ability = ability:MakeTemporaryClone()

		if modifier:has_key("actionResourceId") then
			ability.actionResourceId = modifier.actionResourceId
		end

		for i,attr in ipairs(modifier.attributes) do
			local info = abilityModifierOptionsById[attr.id]
			if info ~= nil then
				if attr.id == "targettype" then
					info.set(modifier, creature, ability, attr)
				else
					info.set(modifier, creature, ability, attr.operation, attr.value, attr.condition)
				end
			end
		end

		if modifier:has_key("ability") then
			local replacementMode = ReplaceBehaviorToEnum(modifier:try_get("replaceBehaviors", false))

			local atend = {}
			if replacementMode == "before" then
				atend = ability.behaviors
				ability.behaviors = {}
			elseif replacementMode == "replaceAll" then
				ability.behaviors = {}
			end

			local nstarting = #ability.behaviors
			for i,behavior in ipairs(modifier.ability.behaviors) do
				local replaced = false
				if replacementMode == "replace" then
					for j=1,nstarting do
						if ability.behaviors[j].typeName == behavior.typeName then
							ability.behaviors[j] = dmhub.DeepCopy(behavior)
							replaced = true
							break
						end
					end
				end

				if not replaced then
					ability.behaviors[#ability.behaviors+1] = dmhub.DeepCopy(behavior)
				end
			end

			for _,b in ipairs(atend) do
				ability.behaviors[#ability.behaviors+1] = b
			end
		end

		if modifier:try_get("modifyDescription", "") ~= "" then
			local modifyDescriptions = ability:get_or_add("modifyDescriptions", {})
			modifyDescriptions[#modifyDescriptions+1] = modifier.modifyDescription
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

			if not modifier:try_get("unconditional") then
				children[#children+1] = modifier:FilterConditionEditor("filterAbility")
			end

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Modify Description:",
				},
				gui.Input{
					width = 300,
					fontSize = 16,
					height = "auto",
					minHeight = 22,
					maxHeight = 60,
					multiline = true,
					placeholderText = "Enter text to add to ability...",
					text = modifier:try_get("modifyDescription"),
					change = function(element)
						modifier.modifyDescription = element.text
						Refresh()
					end,
				}
			}

            children[#children+1] = gui.Check{
                text = "Must Pay Resource Cost",
                value = modifier:try_get("mustPayResourceCost", false),
                change = function(element)
                    modifier.mustPayResourceCost = element.value
                    Refresh()
                end,
            }

			local actions = DeepCopy(CharacterResource.GetActionOptions())
			actions[#actions+1] = {
				id = "nochange",
				text = "(Unchanged)",
			}

            local keywords = modifier:try_get("keywords", {})
            children[#children+1] = gui.KeywordSelector{
                keywords = keywords,
                change = function()
                    modifier.keywords = keywords
                    Refresh()
                end,
            }

			if modifier:try_get("cannotModifyAction", false) == false then
				children[#children+1] = gui.Panel{
					classes = "formPanel",
					gui.Label{
						classes = "formLabel",
						text = "Change Action:",
					},
					gui.Dropdown{
						classes = "formDropdown",
						idChosen = modifier:try_get("actionResourceId", "nochange"),
						options = actions,
						change = function(element)
							if element.idChosen == "nochange" then
								modifier.actionResourceId = nil
							else
								modifier.actionResourceId = element.idChosen
							end
							Refresh()
						end,
					},
				}
			end
			

			for i,attr in ipairs(modifier.attributes) do
				local info = abilityModifierOptionsById[attr.id]
				if info ~= nil then
					children[#children+1] = gui.Panel{
						classes = {"formPanel"},
						gui.Label{
							classes = {"formLabel"},
							width = 400,
							text = info.text,
						},
						gui.DeleteItemButton{
							width = 16,
							height = 16,
							valign = 'center',
							halign = 'right',
							click = function(element)
								table.remove(modifier.attributes, i)
								Refresh()
							end,
						},
					}

					if info.operations ~= nil then
						if #info.operations > 1 then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"formLabel"},
									text = "Operation:",
								},
								gui.Dropdown{
									height = 30,
									width = 260,
									fontSize = 16,
									optionChosen = attr.operation,
									options = info.operations,
									change = function(element)
										modifier.attributes[i].operation = element.optionChosen
										Refresh()
									end,
								},
							}
						end

						if attr.operation == "Bool" then
							children[#children+1] = gui.Check{
								text = info.text,
								style = {
									height = 30,
									width = 260,
									fontSize = 18,
								},

								value = cond(tonumber(attr.value), true, false),
								change = function(element)
									attr.value = cond(element.value, "1", "0")
									Refresh()
								end,
							}
						elseif attr.operation == "targeting" then
							local dummyAbility = ActivatedAbility.Create{}
							local radiusItems = {sphere = true, cylinder = true, line = true, cube = true}
							children[#children+1] = gui.Panel{
								classes = "formPanel",
								gui.Label{
									classes = "formLabel",
									text = "Target Type:",
								},
								gui.Dropdown{
									classes = "formDropdown",
									options = dummyAbility:GetDisplayedTargetTypeOptions(),
									idChosen = attr.targeting or "self",
									change = function(element)
										attr.targeting = element.idChosen
										Refresh()
									end,
								},
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = "formLabel",
									text = "Affects:",
								},
								gui.Dropdown{
									classes = "formDropdown",
									options = {
										{
											id = "all",
											text = "Creatures",
										},
										{
											id = "all_and_objects",
											text = "Creatures and Objects",
										},
										{
											id = "ally",
											text = "Allied Creatures",
										},
										{
											id = "enemy",
											text = "Enemy Creatures",
										},
									},
									idChosen = attr.allegiance or "all",
									change = function(element)
										attr.allegiance = element.idChosen
										Refresh()
									end,
								},
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel", cond(not radiusItems[attr.targeting], 'collapsed-anim')},
								gui.Label{
									classes = "formLabel",
									text = "Radius:",
									create = function(element)
										if attr.targeting == 'line' then
											element.text = 'Width:'
										elseif attr.targeting == 'cube' then
											element.text = 'Edge:'
										else
											element.text = 'Radius:'
										end
									end,
								},

								gui.GoblinScriptInput{
									classes = "formInput",
									value = attr.radius or "",
									change = function(element)
										attr.radius = element.value
										Refresh()
									end,
									documentation = {
										domains = modifier:Domains(),
										help = " This GoblinScript is used to determine the radius of this <color=#00FFFF><link=ability>ability</link></color>. It produces a number which is used as the range of the ability, given in feet. If left empty, the ability will have a range of 5.",
										output = "number",
										examples = {
											{
												script = "2",
												text = "The ability will have a radius of 2 squares.",
											},
											{
												script = "2 + level",
												text = "The ability will have a range of 2 squares plus 1 for each level of the caster.",
											},
										},

										subject = creature.helpSymbols,
										subjectDescription = "The creature using the ability",
										symbols = table.union({
											ability = {
												name = "Ability",
												type = "ability",
												desc = "The ability being used.",
											},
										}, ActivatedAbility.helpCasting),
									}
								},
							}
						-- This creates both a condition and value input, both goblin script values
						elseif attr.operation == "Condition" then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"formLabel"},
									text = "Condition:",
								},
								gui.GoblinScriptInput{
									height = 22,
									width = 360,
									fontSize = 16,
									value = attr.condition,

									change = function(element)
										modifier.attributes[i].condition = element.value
										Refresh()
									end,
									documentation = info.conditionDocumentation,
								}
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Value:",
								},
								gui.GoblinScriptInput{
									height = "auto",
									width = 360,
									fontSize = 16,
									value = attr.value,

									change = function(element)
										modifier.attributes[i].value = element.value
										Refresh()
									end,
									documentation = info.documentation,
								},
							}
						elseif info.documentation ~= nil then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Value:",
								},
								gui.GoblinScriptInput{
									height = "auto",
									width = 360,
									fontSize = 16,
									value = attr.value,

									change = function(element)
										modifier.attributes[i].value = element.value
										Refresh()
									end,
									documentation = info.documentation,
								},
							}
						else
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Value:",
								},
								gui.Input{
									height = 22,
									width = 360,
									fontSize = 16,
									text = attr.value,

									change = function(element)
										modifier.attributes[i].value = element.text
										Refresh()
									end,
								},
							}
						end
					end
				end
			end

			children[#children+1] = gui.Dropdown{
				options = abilityModifierOptions,
				idChosen = "none",
				height = 30,
				width = 260,
				fontSize = 16,

				change = function(element)
					if element.idChosen == "none" then
						return
					end

					local op = nil
					local info = abilityModifierOptionsById[element.idChosen]
					if info.operations ~= nil then
						op = info.operations[1]
					end

					modifier.attributes[#modifier.attributes+1] = {
						id = element.idChosen,
						operation = op,
						value = "",
					}
					Refresh()
				end,
			}

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
								text = "Replace All Behaviors"
							}
						},
						idChosen = ReplaceBehaviorToEnum(modifier:try_get("replaceBehaviors", false)),
						change = function(element)
							modifier.replaceBehaviors = element.idChosen
						end,
					}
				}

			end

			element.children = children
		end

		Refresh()
	end,

}
