local mod = dmhub.GetModLoading()

local damageModifierTypes = {
	{
		id = "attacks",
		text = "Attack Damage",
	},
	{
		id = "spells",
		text = "Spell Damage",
	},
	{
		id = "abilities",
		text = "Ability Damage",
	},
	{
		id = "all",
		text = "All Damage",
	},
}

CharacterModifier.RegisterType('damage', "Modify Damage")

--a 'damage' modifier has the following properties:
--  - modifyRoll: formula to be added to damage rolls.
--  - subtype (optional): the types of damage this applies to. 
--  - crit (optional): this will only apply to critical hits.
--  - damageFilterCondition (optional): the filter condition under which this will activate.
CharacterModifier.TypeInfo.damage = {
	filterRequiresRoll = true,

	init = function(modifier)
		modifier.modifyRoll = '1'
		modifier.damageFilterCondition = false
	end,

	triggerOnUse = function(modifier, creature, modContext)
		print("Trigger:: on use...", traceback())
		if modifier:try_get("hasCustomTrigger", false) and modifier:has_key("customTrigger") then
			print("Trigger:: Triggering custom trigger", modifier.customTrigger)
			modifier.customTrigger:Trigger(modifier, creature, modifier:AppendSymbols{}, nil, modContext)
		end
	end,

	--actually modify the damage roll if hinting the damage roll was successful. Right now we don't expose so many symbols here, do we need more?
	modifyDamageRoll = function(self, creature, targetCreature, damageRoll)

		local symbols = self:try_get("_tmp_symbols")
		
		if targetCreature ~= nil then
			symbols = self:AppendSymbols{
				target = targetCreature:LookupSymbol(),
				dicefaces = self:CalculateResourceDiceFaces(creature),
			}
		end

		symbols = creature:LookupSymbol(symbols)

		local modifyRoll = self.modifyRoll
		if type(modifyRoll) == "table" then
			--convert to dmhub.ParseGoblinScriptToText() once it's available from the engine?
			modifyRoll = dmhub.EvalGoblinScript(modifyRoll, symbols, string.format("Modify damage roll: %s", self.name))
		end

		
		local result = dmhub.NormalizeRoll(damageRoll .. ' ' .. modifyRoll, symbols, string.format("Modify damage roll: %s", self.name))
		return result

	end,


	--returns e.g. { result = true, justification = {"Because you rolled a 20", "Because you're an assassin and it's the first round of combat" } }
	--as to whether this modifier should be activated or not.
	hintDamageRoll = function(self, creature, attack, target, attackOptions)
		local justification = {}

		if self:HasResourcesAvailable(creature) == false then
			return {
				result = false,
				justification = {"You have expended all uses of this ability."},
			}
		end

		local lookupFunction
		if self:try_get("damageFilterCondition", false) ~= false or self:try_get("filterCondition", false) ~= false then
			attackOptions = attackOptions or {}
			local rollInfo = attackOptions.roll or {}

			local damageTypes = attackOptions.damageTypes

			local abilitySymbols = nil
			if attackOptions.ability ~= nil then
				abilitySymbols = GenerateSymbols(attackOptions.ability)
			end

			local attackSymbols = nil
			if attack ~= nil then
				attackSymbols = GenerateSymbols(attack)

				if damageTypes == nil then
					damageTypes = attack:GetDamageTypesSet()
				end
			end

			local targetSymbols = nil
			if target ~= nil then
				targetSymbols = GenerateSymbols(target.properties)
			end

			local symbols = self:AppendSymbols{
				attack = attackSymbols,
				ability = abilitySymbols,
				damagetypes = damageTypes,
				target = targetSymbols,
				haveadvantage = rollInfo.advantage,
				havedisadvantage = rollInfo.disadvantage,
				dicefaces = self:CalculateResourceDiceFaces(creature),
			}

			lookupFunction = creature:LookupSymbol(symbols)
		end

		if self:try_get("filterCondition", false) ~= false then
			local result = ExecuteGoblinScript(self.filterCondition, lookupFunction, 0, string.format("Is %s valid for damage", self.name))
			if result == 0 then
				return nil
			end
		end

		if self:try_get("damageFilterCondition", false) ~= false then
			if self.damageFilterCondition == true then
				return {
					result = true,
					justification = {cond(self:try_get("crit", false), "Activates on critical hits.", "This ability is set to always activate.")},
				}
			end

			local result = ExecuteGoblinScript(self.damageFilterCondition, lookupFunction, 0, string.format("Should %s apply to damage", self.name))

			local explanation = dmhub.ExplainDeterministicGoblinScript(self.damageFilterCondition, lookupFunction, GoblinScriptSymbolDocument)
			return {
				result = (result ~= 0),
				justification = explanation,
			}
		else
			return {
				result = false,
				justification = {},
			}
		end

		return {
			result = false,
			justification = justification,
		}
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

			local upcastDoc = nil
			if modifier:IsResourceCostUpcastable() then
				upcastDoc = {
					name = "Upcast",
					type = "number",
					desc = "The number of spell slots above the minimum that this feature is being used with.",
					examples = {
						"2d6 + upcast d6",
					},
				}
			end

			local dicefacesDoc = nil
			if modifier:IsResourceCostDice() then
				dicefacesDoc = GoblinScriptDocs.dicefaces
			end

			local children = {}

			local options = {}

            children[#children+1] = modifier:PriorityEditor()

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = "Type:",
					classes = {"formLabel"},
				},

				gui.Dropdown{
					options = damageModifierTypes,
					idChosen = modifier:try_get("subtype", "attacks"),
					change = function(element)
						modifier.subtype = element.idChosen
						Refresh()
					end,
				},
			}

			children[#children+1] = modifier:FilterConditionEditor()

			children[#children+1] = gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 12,
				text = "The condition determines whether this modifier will be offered as an option for damage rolls",
			}

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
							help = string.format("This GoblinScript is appended to damage rolls that this modifier affects."),
							output = "roll",
							examples = {
								{
									script = "1",
									text = "1 is added to the damage.",
								},
								{
									script = "3 + 1 when level > 10",
									text = "3 is added to the damage, or 4 when the creature is above level 10.",
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
									desc = "The ability (or spell) used to inflict damage.",
								},
								attack = {
									name = "Attack",
									type = "attack",
									desc = "The attack used to inflict damage. You can access all of its fields, for instance <b>Attack.Finesse</b> to determine if the attack is with a Finesse weapon.\n\n<color=#ffaaaa><i>This field is only available for damage inflicted by an attack.</i></color>",
								},
								cast = {
									name = "Cast",
									type = "spellcast",
									desc = "Information about what has happened during the spell or ability used to generate the damage instance.",
								},
								upcast = upcastDoc,
								dicefaces = dicefacesDoc,
							},
						},

					},

				}
			}

			children[#children+1] = modifier:UsageLimitEditor()
			children[#children+1] = modifier:ResourceCostEditor{
				allowUpcast = true,
				change = function(element)
					Refresh()
				end,
			}

			children[#children+1] = gui.Check{
				id = 'criticalCheckbox',
				text = 'Critical Hits Only',
				style = {
					height = 30,
					width = 260,
					fontSize = 18,
				},

				value = modifier:try_get('crit', false),

				change = function(element)
					modifier.crit = element.value
					Refresh()
				end,
			}

			local damageFilterCondition = modifier:try_get("damageFilterCondition", false)

			local idChosen = cond(damageFilterCondition == false, "never", cond(damageFilterCondition == true, "always", "condition"))

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				gui.Label{
					text = "Auto-activates:",
					classes = {"formLabel"},
				},
				gui.Dropdown{
					height = 30,
					width = 260,
					fontSize = 16,
					idChosen = idChosen,
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
							text = "Conditional",
						},
					},
					change = function(element)
						if element.idChosen == idChosen then
							return
						end
						if element.idChosen == "never" then
							modifier.damageFilterCondition = false
						elseif element.idChosen == "always" then
							modifier.damageFilterCondition = true
						else
							modifier.damageFilterCondition = ""
						end

						Refresh()
					end,
				},
			}

			if type(damageFilterCondition) == "string" then
				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					gui.Label{
						text = "Condition:",
						classes = {"formLabel"},
					},
					gui.GoblinScriptInput{
						value = modifier:try_get("damageFilterCondition", ""),
						change = function(element)
							modifier.damageFilterCondition = element.value
						end,

						documentation = {
							domains = modifier:Domains(),
							help = string.format("This GoblinScript is used to determine whether this modifier should apply to a specific damage roll. Whenever the creature the modifier is applied to damages another creature with an attack, this script is evaluated to determine if the modifier should be applied to the damage roll. If it results in true, it will be applied, otherwise it will not be applied."),
							output = "boolean",
							examples = {
								{
									script = "Dexterity > Target.Dexterity",
									text = "The modifier will only be applied if the attacking creature has higher dexterity than its target.",
								},
								{
									script = "Attack.Finesse and Have Advantage",
									text = "The modifier will only be applied if the attack is made with a finesse weapon and the attacker has advantage on the attack.",
								},
								{
									script = "Target.Next to Another Enemy",
									text = "The modifier will only be applied if the target of the attack is next to another enemy (in addition to the attacker).",
								},
							},
							subject = creature.helpSymbols,
							subjectDescription = "The creature that possesses this feature",
							symbols = {
								damagetypes = {
									name = "Damage Types",
									type = "set",
									desc = "The damage types involved.",
									examples = {
										'Damage Types has "Fire"'
									},
								},
								ability = {
									name = "Ability",
									type = "ability",
									desc = "The ability (or spell) used to inflict damage",
								},
								attack = {
									name = "Attack",
									type = "attack",
									desc = "The attack used to inflict damage. You can access all of its fields, for instance <b>Attack.Finesse</b> to determine if the attack is with a Finesse weapon.\n\n<color=#ffaaaa><i>This field is only available for damage inflicted by an attack.</i></color>",
								},
								target = {
									name = "Target",
									type = "creature",
									desc = "The creature targeted with damage. You can access all of its fields, for instance <b>Target.Hitpoints</b> to access its hitpoints.",
									examples = {
										"1d6 + 1d6 when Target.Hitpoints < Target.Maximum Hitpoints\n\n<color=#ffaaaa><i>This field is only available for damage inflicted by an attack.</i></color>",
									},
								},
								haveadvantage = {
									name = "Have Advantage",
									type = "boolean",
									desc = "If the attack was made with advantage then this is True. Otherwise, it is False.",
								},
								havedisadvantage = {
									name = "Have Disadvantage",
									type = "boolean",
									desc = "If the attack was made with disadvantage then this is True. Otherwise, it is False.",
								},
								cast = {
									name = "Cast",
									type = "spellcast",
									desc = "Information about what has happened during the spell or ability used to generate the damage instance.",
								},
							},
						},
					},
				}
			end

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
							trigger = "damage",
							targetType = "target",
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

