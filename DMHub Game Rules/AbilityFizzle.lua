local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityFizzleBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityFizzleBehavior
--- @field summary string Short label shown in behavior lists.
ActivatedAbilityFizzleBehavior = RegisterGameType("ActivatedAbilityFizzleBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityFizzleBehavior.summary = 'Fizzle'

ActivatedAbility.RegisterType
{
    id = "fizzle",
    text = "Fizzle",
    canHaveDC = false,
    createBehavior = function()
        return ActivatedAbilityFizzleBehavior.new{
        }
    end,
}

function ActivatedAbilityFizzleBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Fizzle"
end

function ActivatedAbilityFizzleBehavior:Cast(ability, casterToken, targets, options)
    if targets == options.targets then
        for i=#targets,1,-1 do
            table.remove(targets, i)
        end
        return
    end

    for _,target in ipairs(targets) do
        for i,t in ipairs(options.targets) do
            if t == target or (target.token ~= nil and t.token ~= nil and target.token.charid == t.token.charid) then
                table.remove(options.targets, i)
                break
            end
        end
    end
end

function ActivatedAbilityFizzleBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	return result
end
