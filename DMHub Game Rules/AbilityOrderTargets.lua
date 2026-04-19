local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityOrderTargetsBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field orderFormula string|number|table GoblinScript formula returning a sort key for each target.
ActivatedAbilityOrderTargetsBehavior = RegisterGameType("ActivatedAbilityOrderTargetsBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityOrderTargetsBehavior.summary = 'Order Targets'
ActivatedAbilityOrderTargetsBehavior.orderFormula = ""

ActivatedAbility.RegisterType
{
	id = 'ordertargets',
	text = 'Order Targets',
	createBehavior = function()
		return ActivatedAbilityOrderTargetsBehavior.new{
		}
	end
}

function ActivatedAbilityOrderTargetsBehavior:Cast(ability, casterToken, targets, options)
    local ordValues = {}
    local symbols = table.shallow_copy(options.symbols)
    for _,target in ipairs(targets) do
        if target.token ~= nil then
            symbols.target = target.token.properties
            local ordValue = ExecuteGoblinScript(self.orderFormula, casterToken.properties:LookupSymbol(symbols), string.format("Order value for %s", ability.name))
            ordValues[target] = ordValue
        else
            ordValues[target] = 0
        end
    end

    table.sort(targets, function(a, b)
        return ordValues[a] < ordValues[b]
    end)
end

function ActivatedAbilityOrderTargetsBehavior:EditorItems(parentPanel)
    local result = {}

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Order Formula:",
        },

        gui.GoblinScriptInput{
            value = self.orderFormula,
            events = {
                change = function(element)
                    self.orderFormula = element.value
                end,
            },

			documentation = {
				help = "This GoblinScript determines the order of the targets.",
				output = "number",
				examples = {
					{
						script = "Stamina",
						text = "The targets will be ordered by their Stamina score.",
					},
					{
						script = "Distance(target, self)",
						text = "The targets will be ordered by their distance to the caster.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature casting the ability.",

				symbols = ActivatedAbility.CatHelpSymbols(ActivatedAbility.helpCasting, {
					target = {
						name = "Target",
						type = "creature",
						desc = "The target of this ability.",
					},
				}),
			},


        }
    }

    return result
end