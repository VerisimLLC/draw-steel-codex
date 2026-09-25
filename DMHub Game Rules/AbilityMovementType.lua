local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityChangeMovementTypeBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field movementType string Movement type to grant: "fly", "swim", "burrow", etc.
ActivatedAbilityChangeMovementTypeBehavior = RegisterGameType("ActivatedAbilityChangeMovementTypeBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'change_movement_type',
	text = 'Change Movement Type',
	createBehavior = function()
		return ActivatedAbilityChangeMovementTypeBehavior.new{
		}
	end
}


ActivatedAbilityChangeMovementTypeBehavior.summary = 'Change Movement Type'
ActivatedAbilityChangeMovementTypeBehavior.movementType = "fly"

function ActivatedAbilityChangeMovementTypeBehavior:Cast(ability, casterToken, targets, options)
    if #targets > 0 then

		for i=1,#targets do
			local tok = targets[i].token
			if tok ~= nil then
				tok:ModifyProperties{
					description = "Change movement type",
					execute = function()
						tok.properties.currentMoveType = self.movementType
					end,
				}
			end
		end

        ability:CommitToPaying(casterToken, options)
    end
end

function ActivatedAbilityChangeMovementTypeBehavior:EditorItems(parentPanel)

	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = "formLabel",
			text = "Movement:",
		},

		gui.Dropdown{
			classes = "formDropdown",
			options = creature.movementTypeInfo,
			idChosen = self.movementType,
			change = function(element)
				---@cast element Dropdown
				self.movementType = element.idChosen
			end,
		},
	}



	return result
end
