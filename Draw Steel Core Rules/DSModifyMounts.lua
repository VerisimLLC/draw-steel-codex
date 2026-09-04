local mod = dmhub.GetModLoading()

CharacterModifier.RegisterType("modrider", "Modify Mount Riders")

CharacterModifier.TypeInfo.modrider = {
    init = function(modifier)
        modifier.feature = CharacterFeature.Create{
            name = "Mount Riders",
            description = "Modify the riders of a mount",
            source = "Mount",
        }
    end,

    modifyRider = function(modifier, creature, rider, targetModifiers)
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

function CharacterModifier:FillRiderModifiers(context, creature, rider, modifiers)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
	if typeInfo.modifyRider ~= nil then
		self:InstallSymbolsFromContext(context)
		typeInfo.modifyRider(self, creature, rider, modifiers)
	end
end