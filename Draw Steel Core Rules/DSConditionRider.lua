local mod = dmhub.GetModLoading()

--- @class ConditionRider:CharacterOngoingEffect
--- @field allowEditingDisplayInfo boolean If true, the display info can be edited in the UI.
--- @field removeThisInsteadOfCondition boolean If true, effects that remove the condition instead remove this rider.
--- @field showAsMenuOption boolean If true, this rider is shown as a menu option alongside its parent condition.
--- @field powerTableText string Text displayed in the power table for this rider.
--- A condition rider is an additional ongoing effect attached to a condition, granting extra modifiers or behaviors.
ConditionRider = RegisterGameType("ConditionRider", "CharacterOngoingEffect")

ConditionRider.allowEditingDisplayInfo = false
ConditionRider.removeThisInsteadOfCondition = false
ConditionRider.showAsMenuOption = false
ConditionRider.powerTableText = ""

function ConditionRider.Create(options)
	local args = {
		id = dmhub.GenerateGuid(),
		iconid = "ui-icons/skills/1.png",
		name = 'New Ongoing Effect',
		source = 'Ongoing Effect',
		description = '',
		modifiers = {},
		display = {
			bgcolor = '#ffffffff',
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		}
	}

	--we need guid to be valid since CharacterFeatures are expected to come with them. While objects in tables have ids.
	args.guid = args.id

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return ConditionRider.new(args)
end

function ConditionRider:FillEditingFields(result)
    result[#result+1] = gui.Check{
        text = "Remove Rider Instead of Condition",
        hover = gui.Tooltip("If checked, effects that would remove the condition just remove this rider instead."),
        value = self.removeThisInsteadOfCondition,
        change = function(element)
            self.removeThisInsteadOfCondition = element.value
        end,
    }

    result[#result+1] = gui.Check{
        text = "Show As Menu Option",
        hover = gui.Tooltip("If checked, menus will offer this rider alongside the condition."),
        value = self.showAsMenuOption,
        change = function(element)
            self.showAsMenuOption = element.value
        end,
    }

    result[#result+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Power Table Text:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = self.powerTableText,
            characterLimit = 120,
            placeholderText = "Enter power table text...",
            change = function(element)
                self.powerTableText = element.text
            end,
        }
    }
end