local mod = dmhub.GetModLoading()


--- @class ActivatedAbilityMacroBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityMacroBehavior
ActivatedAbilityMacroBehavior = RegisterGameType("ActivatedAbilityMacroBehavior", "ActivatedAbilityBehavior")


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

--- Opens the caster's character sheet on a chosen tab (e.g. a monster's Builder).
--- @class ActivatedAbilityOpenSheetBehavior: ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityOpenSheetBehavior
--- @field tab string Character sheet tab id (see CharSheet.TabOptions).
ActivatedAbilityOpenSheetBehavior = RegisterGameType("ActivatedAbilityOpenSheetBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'open_sheet',
	text = 'Open Character Sheet',
	createBehavior = function()
		return ActivatedAbilityOpenSheetBehavior.new{
            tab = "Builder",
		}
	end
}

ActivatedAbilityOpenSheetBehavior.summary = 'Open Character Sheet'
ActivatedAbilityOpenSheetBehavior.tab = "Builder"

function ActivatedAbilityOpenSheetBehavior:Cast(ability, casterToken, targets, options)
    if casterToken ~= nil and casterToken.valid then
        casterToken:ShowSheet(self.tab)
    end
end

function ActivatedAbilityOpenSheetBehavior:EditorItems(parentPanel)
    local result = {}

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    local tabOptions = {}
    for _,tabOption in ipairs(rawget(_G, "CharSheet") and CharSheet.TabOptions or {}) do
        tabOptions[#tabOptions+1] = { id = tabOption.id, text = tabOption.text or tabOption.id }
    end

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Tab:",
        },
        gui.Dropdown{
            options = tabOptions,
            idChosen = self.tab,
            change = function(element)
                ---@cast element Dropdown
                self.tab = element.idChosen --[[@as string]] -- option ids are CharSheet tab ids
            end,
        },
    }
    return result
end
