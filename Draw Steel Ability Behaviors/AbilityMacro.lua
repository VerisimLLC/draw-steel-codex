local mod = dmhub.GetModLoading()


RegisterGameType("ActivatedAbilityMacroBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'Macro',
	text = 'Macro Execution',
	createBehavior = function()
		return ActivatedAbilityMacroBehavior.new{
            macro = "",
		}
	end
}

ActivatedAbilityMacroBehavior.summary = 'Macro Execution'

function ActivatedAbilityMacroBehavior:Cast(ability, casterToken, targets, options)
    local macro = StringInterpolateGoblinScript(self.macro, casterToken.properties:LookupSymbol(options.symbols))
    print("MACRO:: EXECUTE:", macro)
    dmhub.Execute(macro)
end

function ActivatedAbilityMacroBehavior:EditorItems(parentPanel)
    local result = {}

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Macro:",
        },
        gui.Input{
            classes = {"formInput"},
            width = 320,
            text = self.macro,
            placeholderText = "Enter macro text here...",
            change = function(element)
                self.macro = element.text
            end,
        },
    }
    return result
end