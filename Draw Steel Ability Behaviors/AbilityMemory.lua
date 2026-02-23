local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRememberBehavior:ActivatedAbilityBehavior
--- @field memoryName string
--- @field calculation string
ActivatedAbilityRememberBehavior = RegisterGameType("ActivatedAbilityRememberBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'remember',
	text = 'Remember',
	createBehavior = function()
		return ActivatedAbilityRememberBehavior.new{
		}
	end
}

ActivatedAbilityRememberBehavior.summary = 'Remember Value'
ActivatedAbilityRememberBehavior.memoryName = 'value'
ActivatedAbilityRememberBehavior.calculation = '0'

function ActivatedAbilityRememberBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Remember Value"
end

function ActivatedAbilityRememberBehavior:Cast(ability, casterToken, targets, options)
    local symbols = table.shallow_copy(options.symbols)
    symbols.caster = casterToken.properties
    local val = 0
    for _, target in ipairs(targets) do
        symbols.target = target.token.properties
        local value = ExecuteGoblinScript(self.calculation, target.token.properties:LookupSymbol(symbols), 0, "Remember Value Calculation")
        print("MEMORY:: CALC", self.calculation, "=", value, "FROM", table.keys(symbols))
        val = val + value
    end

    options.symbols.cast:StoreMemory(self.memoryName, val)
    print("MEMORY:: Store", self.memoryName, "=", val, "FROM", #targets)
end

function ActivatedAbilityRememberBehavior:EditorItems(parentPanel)
    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local Refresh
    Refresh = function()
        local children = {}

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Memory Name:",
            },
            gui.Input{
                classes = {"formInput"},
                text = self.memoryName,
                characterLimit = 32,
                change = function(element)
                    self.memoryName = string.trim(element.text)
                    Refresh()
                end,
            },
        }

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Value:",
            },
            gui.GoblinScriptInput{
                value = self.calculation,
                change = function(element)
                    self.calculation = element.value
                    Refresh()
                end,
                documentation = {
                    help = "This GoblinScript is used to calculate the value to remember.",
                    output = "number",
                    subject = creature.helpSymbols,
                    subjectDescription = "The creature that this behavior is applied to",
                    symbols = {
                        caster = {
                            name = "Caster",
                            type = "creature",
                            desc = "The creature that is casting the ability.",
                        },
                        target = {
                            name = "Target",
                            type = "creature",
                            desc = "The creature that is the target of the ability.",
                        },
                        cast = {
                            name = "Cast",
                            type = "spellcast",
                            desc = "The current ability cast, which can be used to store the memory value."
                        }
                    }
                },
            },
        }

        panel.children = children
    end

    Refresh()

    local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
    result[#result+1] = panel
    return result
end