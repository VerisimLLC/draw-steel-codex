local mod = dmhub.GetModLoading()

--This file implements the Grant Proficiency character modifier.

local addAllDropdownOption = function(options)
	local op = {
		id = 'all',
		text = 'All',
	}

	local result = DeepCopy(options)
	table.insert(result, 1, op)
	return result
end

local g_recursion = 0

CharacterModifier.RegisterType('proficiency', "Grant Skill or Language")

--a 'proficiency' modifier has the following properties:
--  - subtype (string): Type of thing to offer proficiency in -- 'skill' means character skill (athletics, acrobatics, etc), 'save' for saving throw, 'equipment' for specific equipment or an equipment category., 'language' for languages.
--  - skills (table of string -> bool): the skill to offer proficiency in.
--  - proficiency (string): the level of proficiency which keys creature.proficiencyKeyToValue.

CharacterModifier.TypeInfo.proficiency = {
	Deserialize = function(modifier)
		modifier:get_or_add("skills", {})
		modifier:get_or_add("equate", false)
		modifier:get_or_add("proficiency", "proficient")
		modifier:get_or_add("subtype", "skill")
	end,

	init = function(modifier)
		modifier.subtype = 'skill'
		modifier.skills = {}
		modifier.proficiency = 'proficient'
		modifier.equate = false
	end,

	autoDescribe = function(modifier)
		if modifier.subtype == "skill" then
            local skillsTable = dmhub.GetTable(Skill.tableName) or {}
			local skills = {}
			if modifier.skills.all then
				skills = {"all skills"}
			else
				for k,_ in pairs(modifier.skills) do
					if skillsTable[k] == nil then
						dmhub.CloudError(string.format("Could not find skill: %s", k))
					else
						skills[#skills+1] = skillsTable[k].name
					end
				end
			end

			if #skills == 0 then
				return nil
			end

			local skillDesc = pretty_join_list(skills)
			return string.format(creature.proficiencyKeyToValue[modifier.proficiency].verboseDescription, skillDesc)

		elseif modifier.subtype == "language" then
			local langs = {}
			if modifier.skills.all then
				langs = {"all languages"}
			else
				local dataTable = dmhub.GetTable("languages") or {}
				for k,_ in pairs(modifier.skills) do
					if dataTable[k] then
						langs[#langs+1] = dataTable[k].name
					end
				end
			end

			if #langs == 0 then
				return nil
			end

			local langDesc = pretty_join_list(langs)

			return string.format("You know how to speak and read %s.", langDesc)
		end

		return nil
	end,

	
	grantProficiency = function(modifier, creature, subtype, skillid, currentProficiency, log)
		--print("Skills", modifier)
		local newProficiency = modifier.proficiency
		if modifier:try_get("equate", false) then
			if g_recursion > 10 then
				return currentProficiency
			end
			--equating means looking this up in the proficiency table.
			local skillInfo = dmhub.GetTable(Skill.tableName)[newProficiency]
			if skillInfo == nil then
				return currentProficiency
			end
			g_recursion = g_recursion+1
			newProficiency = creature:SkillProficiencyLevel(skillInfo).id
			g_recursion = g_recursion-1
		end
		if modifier.subtype == subtype and (modifier.skills[skillid] or modifier.skills.all) and creature.proficiencyKeyToValue[currentProficiency].multiplier < creature.proficiencyKeyToValue[newProficiency].multiplier then
			if log ~= nil then
				log[#log+1] = {
					modifier = modifier,
					proficiency = newProficiency,
				}
			end
			return newProficiency
		end

		return currentProficiency
	end,

	equipmentProficiency = function(modifier, creature, proficiencyTable, pass)
		if cond(modifier:try_get("equate", false), 2, 1) ~= pass then
			--we do normal evaluation on the first pass, then equate on the second pass.
			return
		end
		if modifier.subtype == 'equipment' then
			local newProficiency = modifier.proficiency
			if modifier:try_get("equate", false) then
				--equating means looking this up in the proficiency table.
				local entry = proficiencyTable[newProficiency]
				if entry == nil then
					--we don't have proficiency in this skill so doing nothing.
					return
				end
				newProficiency = entry.proficiency
			end

			for k,_ in pairs(modifier.skills) do

				local use = true
				if proficiencyTable[k] then
					local currentLevel = creature.proficiencyKeyToValue[proficiencyTable[k].proficiency].multiplier
					if currentLevel >= creature.proficiencyKeyToValue[newProficiency].multiplier then
						use = false
					end
				end

				if use then
					proficiencyTable[k] = { proficiency = newProficiency }
				end
			end

		end
	end,

	languageProficiency = function(modifier, creature, proficiencyTable)
		if modifier.subtype == 'language' then
			for k,_ in pairs(modifier.skills) do
				proficiencyTable[k] = true
			end
		end
	end,
	
	accumulateDuplicateProficiencies = function(modifier, skills, tools)
		if modifier.proficiency ~= 'proficient' then
			return
		end

		if modifier.subtype == 'equipment' then
			local equipmentTable = dmhub.GetTable('tbl_Gear')
			local catTable = dmhub.GetTable('equipmentCategories')
			for k,_ in pairs(modifier.skills) do
				local item = equipmentTable[k]
				if item ~= nil and catTable[item:try_get("equipmentCategory", "")] ~= nil then
					local cat = catTable[item.equipmentCategory]
					if cat.isTool then
						tools[k] = (tools[k] or 0) + 1
					end
				end
			end
		elseif modifier.subtype == 'skill' then
			for k,_ in pairs(modifier.skills) do
				skills[k] = (skills[k] or 0) + 1
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
						options = {
							{
								id = "skill",
								text = "Skill",
							},
							{
								id = "save",
								text = "Save",
							},
							{
								id = "equipment",
								text = "Equipment",
							},
							{
								id = "language",
								text = "Language",
							},
						},
						idChosen = modifier.subtype,

						events = {
							change = function(element)
								if modifier.subtype ~= element.idChosen then
									modifier.subtype = element.idChosen
									if element.idChosen == 'skill' then
										modifier.skill = 'athletics'
									elseif element.idChosen == 'save' then
										modifier.skill = 'str'
									end
									modifier.proficiency = 'proficient'
									Refresh()
								end
							end,
						},
					},
					gui.Check{
						text = "Equate",
						hover = gui.Tooltip("If checked, this modifier will grant proficiency equal to the character's proficiency in another skill."),
						classes = {cond(modifier.subtype ~= "skill" and modifier.subtype ~= "equipment", "hidden")},
						value = modifier:try_get("equate", false),
						change = function(element)
							modifier.equate = element.value
							Refresh()
						end,
					},
				}
			}

			local skillOptions
			if modifier.subtype == 'skill' then
				skillOptions = addAllDropdownOption(Skill.skillsDropdownOptions)
			elseif modifier.subtype == 'save' then
				skillOptions = addAllDropdownOption(creature.savingThrowDropdownOptions)
			elseif modifier.subtype == 'equipment' then
				skillOptions = EquipmentCategory.GetEquipmentProficiencyDropdownOptions()

			elseif modifier.subtype == 'language' then
				skillOptions = {}
				local langs = dmhub.GetTable("languages") or {}
				for k,lang in unhidden_pairs(langs) do
					skillOptions[#skillOptions+1] = {
						id = k,
						text = lang.name,
					}
				end
				table.sort(skillOptions, function(a,b) 
					return a.text < b.text
				end)

			end

			local itemChildren = {}
			for skill,_ in pairs(modifier.skills) do
				local index = 0
				for i,option in ipairs(skillOptions) do
					if option.id == skill then
						index = i
					end
				end

				if index ~= 0 then

					itemChildren[#itemChildren+1] = gui.Panel{
						width = 300,
						height = 20,
						flow = 'horizontal',

						data = {
							text = skillOptions[index].text,
						},

						gui.Label{
							text = skillOptions[index].text,
							width = 'auto',
							height = 'auto',
							halign = 'left',
							valign = 'center',
							fontSize = 18,
							color = 'white',
						},

						gui.DeleteItemButton{
							width = 16,
							height = 16,
							valign = 'center',
							halign = 'right',
							click = function(element)
								modifier.skills[skill] = nil
								Refresh()
							end,
						}
					}
					table.remove(skillOptions, index)
				end
			end

			table.sort(itemChildren, function(a,b) return a.data.text < b.data.text end)

			for i,itemChild in ipairs(itemChildren) do
				children[#children+1] = itemChild
			end

			table.insert(skillOptions, 1, { id = 'none', text = 'Choose...' })

			local skillText = 'Skill:'
			if modifier.subtype == 'language' then
				skillText = 'Language:'
			end

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = skillText,
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 260,
							fontSize = 16,
						},
						hasSearch = true,
						options = skillOptions,

						idChosen = 'none',

						events = {
							change = function(element)
								if element.idChosen ~= 'none' then
									modifier.skills[element.idChosen] = true
									Refresh()
								end
							end,
						},
					},
				}
			}
						

			if modifier.subtype ~= 'language' then
				local proficiencyOptions
				printf("PROFICIENCY:: LEVELED %s -> %s FROM %s", json(modifier.subtype), json(GameSystem.IsProficiencyTypeLeveled(modifier.subtype)), json(GameSystem.leveledProficiencyTypes))

				if GameSystem.IsProficiencyTypeLeveled(modifier.subtype) then
					proficiencyOptions = creature.GetProficiencyDropdownOptions()
				else
					proficiencyOptions = {
						{
							id = 'none',
							text = 'None',
						},
						{
							id = 'proficient',
							text = 'Proficient',
						},
					}
				end
				
				table.insert(proficiencyOptions, 1, { id = 'none', text = 'Choose...' })
				
				if modifier:try_get("equate", false) then
					proficiencyOptions = skillOptions
				end

				children[#children+1] = gui.Panel{
					classes = {'formPanel'},
					children = {
						gui.Label{
							text = 'Proficiency:',
							classes = {'formLabel'},
						},
						gui.Dropdown{
							selfStyle = {
								height = 30,
								width = 260,
								fontSize = 16,
							},
							hasSearch = true,
							options = proficiencyOptions,

							idChosen = modifier.proficiency,

							events = {
								change = function(element)
									if modifier.proficiency ~= element.idChosen then
										modifier.proficiency = element.idChosen
										Refresh()
									end
								end,
							},
						},
					}
				}
			end

			element.children = children
		end

		Refresh()
	end,
}
