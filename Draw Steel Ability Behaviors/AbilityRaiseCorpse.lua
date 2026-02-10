local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityRaiseCorpseBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'raise_corpse',
	text = 'Raise Corpse',
	createBehavior = function()
		return ActivatedAbilityRaiseCorpseBehavior.new{
		}
	end
}

ActivatedAbilityRaiseCorpseBehavior.summary = 'Raise Corpse'
ActivatedAbilityRaiseCorpseBehavior.restoreStamina = true

function ActivatedAbilityRaiseCorpseBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Raise Corpse"
end

function ActivatedAbilityRaiseCorpseBehavior:Cast(ability, casterToken, targets, options)
    local tokenids = {}
    local added = false
    for i,target in ipairs(targets) do
        local creatureToken = nil
        local charid = nil
        if target.token ~= nil and target.token.isCorpse and target.token.objectInstance ~= nil then
            local object = target.token.objectInstance
            local corpse = object:GetComponent("Corpse")
            if corpse ~= nil then
                creatureToken = corpse.properties:DeadCreatureToken()
                charid = corpse.properties.charid
                if creatureToken ~= nil then
                    creatureToken:ModifyProperties{
                        description = "Raised",
                        execute = function()
                            if self.restoreStamina then
                                creatureToken.properties.damage_taken = 0
                                creatureToken.properties.inflictedConditions = {}
                            end
                            creatureToken.properties.activeOngoingEffects = {}
                        end
                    }
                    creatureToken.despawned = false
                    object:Destroy()
                else
                    print("Corpse:: could not find creature token")
                end

            else
                print("Corpse:: no corpse component found on object")
            end
        else
            print("Corpse:: target is not a corpse")
        end

        if creatureToken ~= nil then
            tokenids[i] = charid
            added = true
        end
    end

    if not added then
        print("Corpse:: No corpses found to raise")
        return
    end

    ability:CommitToPaying(casterToken, options)

    game.UpdateCharacterTokens()
    coroutine.yield(0.1)

    for i,target in ipairs(targets) do
        local charid = tokenids[i]
        if charid ~= nil then
            local token = dmhub.GetTokenById(charid)
            if token ~= nil then
                target.token = token
                print("Corpse:: found token", charid)
            else
                print("Corpse:: Could not find token with charid", charid)
            end
        end
    end
end

function ActivatedAbilityRaiseCorpseBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Check{
        text = "Restore Stamina",
        value = self.restoreStamina,
        change = function(element)
            self.restoreStamina = element.value
        end,
    }

    return result
end