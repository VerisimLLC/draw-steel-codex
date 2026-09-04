local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityStealAbilityBehavior:ActivatedAbilityBehavior
ActivatedAbilityStealAbilityBehavior = RegisterGameType("ActivatedAbilityStealAbilityBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityStealAbilityBehavior.summary = "Steal Ability"

ActivatedAbility.RegisterType
{
	id = 'stealAbility',
	text = 'Steal Ability',
	createBehavior = function()
		return ActivatedAbilityStealAbilityBehavior.new{
            stacks = 1,
		}
	end
}

function ActivatedAbilityStealAbilityBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Ability Filter:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("abilityFilter", ""),
            change = function(element)
                self.abilityFilter = element.value
            end,

            documentation = {
                help = "This GoblinScript is used to determine if this modifier filters an ability. If the result is true, the ability will be available, if it is false, the ability will be suppressed.",
                output = "boolean",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is affected by this modifier",
                symbols = {
                    ability = {
                        name = "Ability",
                        type = "ability",
                        desc = "The ability that is being checked for availability.",
                        examples = {
                            "Ability.Name = 'Hide'",
                            "Ability.Keywords has 'Fire'",
                        },
                    },
                    caster = {
                        name = "Caster",
                        type = "caster",
                        desc = "The original caster of the ability.",
                        examples = {
                            "Caster.Name = 'Bob'",
                            "Caster.Level > 5",
                        },
                    },
                    usedability = {
                        name = "Used Ability",
                        type = "ability",
                        desc = "The ability that triggered this steal, if fired from a triggered ability.",
                        examples = {
                            "Ability.Name = Used Ability.Name",
                        },
                    },
                }
            }
        }
    }

    self:OngoingEffectEditor(parentPanel, result)
	return result
end

--Retained as a thin alias: the implementation now lives in ActivatedAbility so the
--invoke behavior's "chooseClassAbility" mode can share it. Existing callers and any
--saved content referencing this name keep working unchanged.
function ActivatedAbilityStealAbilityBehavior.ShowChoiceDialog(choices, dialogOptions, casterToken)
	return ActivatedAbility.ShowAbilityChoiceDialog(choices, dialogOptions, casterToken)
end


--- @param ability ActivatedAbility
--- @param casterToken Token
--- @param targets Token[]
--- @param options table
--- @return 
function ActivatedAbilityStealAbilityBehavior:Cast(ability, casterToken, targets, options)
    if self:try_get("ongoingEffect") == nil then
        printf("STEAL ABILITY:: NO EFFECT")
        return
    end
    
    local results = {}
    local filter = self:try_get("abilityFilter", "")

    for _, target in ipairs(targets) do
        local targetCreature = target.token.properties
        local candidateAbilities = targetCreature:GetActivatedAbilities{ characterSheet = true }
        for _,a in ipairs(candidateAbilities) do
            local passesFilter = true
            if filter ~= "" then
                local symbols = {
                    ability = a,
                    caster = casterToken.properties,
                    usedability = options ~= nil and options.symbols ~= nil and options.symbols.usedability or nil,
                }
                passesFilter = GoblinScriptTrue(ExecuteGoblinScript(filter, targetCreature:LookupSymbol(symbols), 0, "Steal Ability Filter"))
            end

            if passesFilter then
                local synth = DeepCopy(a)
                synth.stolenFrom = target.token.id

                results[#results+1] = synth
            end
        end
    end

    local chosenAbility = nil
    chosenAbility = ActivatedAbilityStealAbilityBehavior.ShowChoiceDialog(results, {
        title = "Steal Ability",
        buttonText = "Steal",
    }, casterToken)
    if chosenAbility == nil then
        return
    end

    local casterInfo = {
        tokenid = casterToken.id
    }

    if casterToken.properties ~= nil then
        casterToken:ModifyProperties{
            description = "Steal Ability",
            execute = function()
                local newEffect = casterToken.properties:ApplyOngoingEffect(self.ongoingEffect, self:try_get("duration"), casterInfo, {
                    stolenAbility = chosenAbility,
                    untilEndOfTurn = self.durationUntilEndOfTurn,
                })
            end
        }
    end

end 