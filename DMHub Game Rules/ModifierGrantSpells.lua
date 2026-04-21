local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType('grantSpells', "Grant Spells")


CharacterModifier.GetSpellcastingClassOptions = function()
    local result = {}

    result[#result+1] = {
        id = "all",
        text = "All",
    }

    for _,option in ipairs(GameSystem.CalculateSpellcastingMethods()) do
        result[#result+1] = option
    end

    table.sort(result, function(a,b) return a.text < b.text end)
    
    return result
end

CharacterModifier.GuessClassOfSpellcasting = function(modifier)
    local spellcastingMethods = GameSystem.CalculateSpellcastingMethods()
    local classesTable = dmhub.GetTable("classes")
    local domains = modifier:Domains()
    for domain,_ in pairs(domains) do
        if string.starts_with(domain, "class:") then
            local key = string.sub(domain, 7)
            local classInfo = classesTable[key]
            if classInfo ~= nil then
                for _,method in ipairs(spellcastingMethods) do
                    if method.id == key then
                        return classInfo
                    end
                end
            end
        end
    end

    return nil
end

CharacterModifier.GuessIDOfSpellcasting = function(modifier)
    local classInfo = CharacterModifier.GuessClassOfSpellcasting(modifier)
    if classInfo == nil then
        return "all"
    end

    return classInfo.id
end

--spells = list of spells
--applyto = ID of the class to whose spellcasting this applies, or "all" for all classes.
CharacterModifier.TypeInfo.grantSpells = {
	init = function(modifier)
        modifier.spells = {}
        modifier.applyto = CharacterModifier.GuessIDOfSpellcasting(modifier)
    end,

    ModifySpellcastingFeatures = function(modifier, creature, spellcastingFeatures)
        for _,feature in ipairs(spellcastingFeatures) do
            if modifier.applyto == "all" or modifier.applyto == feature.id then
                local grant = feature.grantedSpells
                for _,spell in ipairs(modifier.spells) do
                    grant[#grant+1] = { spellid = spell, source = modifier.name }
                end
            end
        end
    end,

	createEditor = function(modifier, element)
		local spellsTable = dmhub.GetTable("Spells")

		local Refresh

		local options = {}
		for k,spell in pairs(spellsTable) do
			options[#options+1] = {
				id = k,
				text = spell.name,
			}
		end

		table.sort(options, function(a,b) return a.text < b.text end)

        options[#options+1] = {
            id = "add",
            text = "Add Spell...",
        }

        local spellsDropdown = gui.Dropdown{
            options = options,
            idChosen = "add",
            hasSearch = true,
            change = function(element)
                if element.idChosen ~= "add" then
                    modifier.spells[#modifier.spells+1] = element.idChosen
                    Refresh()
                end
            end,
        }

        local spellcastingTypesDropdown = gui.Dropdown{
            options = CharacterModifier.GetSpellcastingClassOptions(),
            idChosen = modifier.applyto,
            change = function(element)
                modifier.applyto = element.idChosen
            end,
        }

		Refresh = function()
			local children = {}

			children[#children+1] = modifier:FilterConditionEditor()

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Apply to:",
                },
                spellcastingTypesDropdown,
            }

            for i,spellid in ipairs(modifier.spells) do
                local index = i
                local spellInfo = spellsTable[spellid]
                if spellInfo ~= nil then
                    children[#children+1] = gui.Panel{
                        classes = {"formPanel", "formPanel-inline"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = spellInfo.name,
                        },

                        gui.DeleteItemButton{
                            width = 16,
                            height = 16,
                            valign = "center",
                            halign = "right",
                            click = function(element)
                                table.remove(modifier.spells, index)
                                Refresh()
                            end,
                        }
                    }
                end
            end

            spellsDropdown.idChosen = "add"
            children[#children+1] = spellsDropdown

            element.children = children
        end

        Refresh()
    end,
}

function CharacterModifier:ModifySpellcastingFeatures(creature, spellcastingFeatures)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.ModifySpellcastingFeatures ~= nil then
        printf("MODIFY:: MODIFYING FEATURES: %d", #spellcastingFeatures)
		typeInfo.ModifySpellcastingFeatures(self, creature, spellcastingFeatures)
	end
end