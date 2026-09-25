local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityDebugBehavior: ActivatedAbilityBehavior
ActivatedAbilityDebugBehavior = RegisterGameType("ActivatedAbilityDebugBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'debug_behavior',
	text = 'Debug',
	createBehavior = function()
		return ActivatedAbilityDebugBehavior.new{
		}
	end
}


function ActivatedAbilityDebugBehavior:Cast(ability, casterToken, targets, options)
    print("CAST:: DEBUG BEHAVIOR: CASTING ABILITY", ability.name, "FROM", casterToken.name)
    for i,target in ipairs(targets) do
        if target.token ~= nil then
            print("CAST:: DEBUG BEHAVIOR: TARGET", i, target.token.name)
        else
            print("CAST:: DEBUG BEHAVIOR: TARGET", i, "<no token>")
        end
    end
    return true
end