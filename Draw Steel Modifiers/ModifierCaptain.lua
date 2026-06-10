local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("modcaptain", "Modify Squad Captain")

CharacterModifier.TypeInfo.modcaptain = {
    init = function(modifier)
        modifier.feature = CharacterFeature.Create{
            name = "Mount Captain",
            description = "Modify the captain of the squad this is a member of",
            source = "Squad",
        }
    end,

    modifyCaptain = function(modifier, creature, captain, targetModifiers)
        for _,modifier in ipairs(modifier.feature.modifiers) do
            targetModifiers[#targetModifiers+1] = {
                mod = modifier,
            }
        end
    end,

	createEditor = function(modifier, element)
        local children = {}

		children[#children+1] = modifier:FilterConditionEditor()

        children[#children+1] = gui.Button{
            classes = {"sizeL"},
			width = 200,
			text = "Edit Modifiers",
			click = function(element)
				element.root:AddChild(modifier.feature:PopupEditor())
			end,
        }


        element.children = children
    end,
}

function CharacterModifier:FillSquadCaptainModifiers(context, creature, captain, modifiers)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.modifyCaptain ~= nil then
		self:InstallSymbolsFromContext(context)
		typeInfo.modifyCaptain(self, creature, captain, modifiers)
	end
end