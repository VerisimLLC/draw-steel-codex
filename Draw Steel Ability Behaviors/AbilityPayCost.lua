local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityPayAbilityCostBehavior: ActivatedAbilityBehavior
ActivatedAbilityPayAbilityCostBehavior = RegisterGameType("ActivatedAbilityPayAbilityCostBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'pay_ability_cost',
	text = 'Pay Ability Cost',
	createBehavior = function()
		return ActivatedAbilityPayAbilityCostBehavior.new{
		}
	end
}

ActivatedAbilityPayAbilityCostBehavior.summary = 'Pay Ability Cost'

function ActivatedAbilityPayAbilityCostBehavior:Cast(ability, casterToken, targets, options)
	if not options.alreadyPaid then
		ability:ConsumeResources(casterToken, {
			costOverride = options.costOverride,
			meleeAttack = options.meleeAttack,
		})
		options.alreadyPaid = true
	end
end


function ActivatedAbilityPayAbilityCostBehavior:EditorItems(parentPanel)
	local result = {}
    return result
end