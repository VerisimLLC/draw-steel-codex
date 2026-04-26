local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityDelayBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field delay number|string|table Delay in seconds before the next behavior fires.
ActivatedAbilityDelayBehavior = RegisterGameType("ActivatedAbilityDelayBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityDelayBehavior.summary = 'Delay'
ActivatedAbilityDelayBehavior.delay = 1

ActivatedAbility.RegisterType
{
	id = 'delay',
	text = 'Delay',
	createBehavior = function()
		return ActivatedAbilityDelayBehavior.new{
		}
	end
}

function ActivatedAbilityDelayBehavior:Cast(ability, casterToken, targets, options)
    local delay = ExecuteGoblinScript(self.delay, casterToken.properties:LookupSymbol(options.symbols), string.format("Delay for %s", ability.name))
    print("DELAY:: EXECUTE DELAY:", delay, "for ability", ability.name, "by", dmhub.DescribeToken(casterToken)) --- IGNORE ---
    if delay > 60 then
        delay = 60
    end

    local endTime = dmhub.Time() + delay
    while dmhub.Time() < endTime do
        print("DELAY:: WAITING...")
        coroutine.yield(0.1)
    end

        print("DELAY:: PROCEED...")
    if self:try_get("proceedCondition", "") ~= "" then
        while not GoblinScriptTrue(ExecuteGoblinScript(self.proceedCondition, casterToken.properties:LookupSymbol(options.symbols), "Proceed condition")) do
            coroutine.yield(0.1)
        end
    end
end

function ActivatedAbilityDelayBehavior:EditorItems(parentPanel)
    local result = {}

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Delay:",
        },

        gui.GoblinScriptInput{
            value = self.delay,
            events = {
                change = function(element)
                    self.delay = element.value
                end,
            },
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Proceed Condition:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("proceedCondition", ""),
            events = {
                change = function(element)
                    self.proceedCondition = element.value
                end,
            },
        }
    }

    return result
end
