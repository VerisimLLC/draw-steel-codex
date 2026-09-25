local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('modifydamageaftersave', "Damage Multiplier After Save")



CharacterModifier.TypeInfo.modifydamageaftersave = {

	init = function(modifier)
        modifier.attrid = creature.savingThrowDropdownOptions[1].id
        modifier.affect = "half"
        modifier.onsuccess = "none"
        modifier.onfail = "half"
    end,

    modifyDamageAfterSave = function(modifier, symbols, info)
        printf("ATTRIBUTE: %s vs %s", modifier.attrid, symbols.attrid)
        if (modifier.attrid == "all" or modifier.attrid == symbols.attrid) and symbols.damageonsuccess == modifier.affect then
            local damageStr = cond(symbols.success, modifier.onsuccess, modifier.onfail)
            local damageMultiplier = 0
            local desc = "No Damage"
            if damageStr == "full" then
                damageMultiplier = 1
                desc = "Full Damage"
            elseif damageStr == "half" then
                damageMultiplier = 0.5
                desc = "Half Damage"
            end

            if damageMultiplier ~= info.damageMultiplier then
                info.damageMultiplier = damageMultiplier
                info.saveText = string.format("%s; Modified to %s by %s", info.saveText, desc, modifier.name)
            end
        end
    end,

	createEditor = function(modifier, element)
		local Refresh
		Refresh = function()
			local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

            local attributeOptions = DeepCopy(creature.savingThrowDropdownOptions)
            table.insert(attributeOptions, 1, {
                text = "All",
                id = "all",
            })

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				children = {
					gui.Label{
						text = 'Save Type:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 250,
							fontSize = 16,
						},
						options = attributeOptions,
						idChosen = modifier.attrid,

						events = {
							change = function(element)
								---@cast element Dropdown
								modifier.attrid = element.idChosen
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
						text = 'Affect When:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 250,
							fontSize = 16,
						},
						options = {
                            {
                                id = "none",
                                text = "Success = No Damage",
                            },
                            {
                                id = "half",
                                text = "Success = Half Damage",
                            },
                        },
						idChosen = modifier.affect,

						events = {
							change = function(element)
								---@cast element Dropdown
								modifier.affect = element.idChosen
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
						text = 'On Success:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 250,
							fontSize = 16,
						},
						options = {
                            {
                                id = "none",
                                text = "No Damage",
                            },
                            {
                                id = "half",
                                text = "Half Damage",
                            },
                            {
                                id = "full",
                                text = "Full Damage",

                            },
                        },
						idChosen = modifier.onsuccess,

						events = {
							change = function(element)
								---@cast element Dropdown
								modifier.onsuccess = element.idChosen
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
						text = 'On Failure:',
						classes = {'formLabel'},
					},
					gui.Dropdown{
						selfStyle = {
							height = 30,
							width = 250,
							fontSize = 16,
						},
						options = {
                            {
                                id = "none",
                                text = "No Damage",
                            },
                            {
                                id = "half",
                                text = "Half Damage",
                            },
                            {
                                id = "full",
                                text = "Full Damage",

                            },
                        },
						idChosen = modifier.onfail,

						events = {
							change = function(element)
								---@cast element Dropdown
								modifier.onfail = element.idChosen
								Refresh()
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

function CharacterModifier:ModifyDamageAfterSave(modInfo, symbols, info)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.modifyDamageAfterSave ~= nil then
        typeInfo.modifyDamageAfterSave(self, symbols, info)
    end
end