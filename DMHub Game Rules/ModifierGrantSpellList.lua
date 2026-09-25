local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('grantSpellList', "Grant Spell List")

--listid = id of spell list to add.
--applyto = ID of the class to whose spellcasting this applies, or "all" for all classes.
CharacterModifier.TypeInfo.grantSpellList = {
	init = function(modifier)
		modifier.listid ="none" 
		modifier.applyto = CharacterModifier.GuessIDOfSpellcasting(modifier)
	end,

    ModifySpellcastingFeatures = function(modifier, creature, spellcastingFeatures)
        for _,feature in ipairs(spellcastingFeatures) do
            if modifier.applyto == "all" or modifier.applyto == feature.id then
		feature.spellLists = DeepCopy(feature.spellLists)
		if modifier.listid ~= "none" then
			feature.spellLists[#feature.spellLists+1] = modifier.listid
		end
            end
        end
    end,

	createEditor = function(modifier, element)
		local spellListTable = dmhub.GetTable(SpellList.tableName)

		local Refresh

		local options = {}
		for k,spellList in pairs(spellListTable) do
			options[#options+1] = {
				id = k,
				text = spellList.name,
			}
		end

		table.sort(options, function(a,b) return a.text < b.text end)

        options[#options+1] = {
            id = "none",
            text = "Choose Spell List...",
        }

        local spellListDropdown = gui.Dropdown{
            options = options,
            idChosen = modifier.listid,
            change = function(element)
                ---@cast element Dropdown
		modifier.listid = element.idChosen
            end,
        }

		Refresh = function()
			local children = {}

			children[#children+1] = modifier:FilterConditionEditor()

		local spellcastingTypesDropdown = gui.Dropdown{
		    options = CharacterModifier.GetSpellcastingClassOptions(),
		    idChosen = modifier.applyto,
		    change = function(element)
		    	---@cast element Dropdown
			modifier.applyto = element.idChosen
		    end,
		}


            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Apply to:",
                },
                spellcastingTypesDropdown,
            }

            children[#children+1] = spellListDropdown

            element.children = children
        end

        Refresh()
    end,
}

