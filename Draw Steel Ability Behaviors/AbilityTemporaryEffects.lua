local mod = dmhub.GetModLoading()


RegisterGameType("ActivatedAbilityApplyAbilityDurationEffect", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'temporary_effect',
	text = 'Ability Duration Effect',
	createBehavior = function()
		return ActivatedAbilityApplyAbilityDurationEffect.new{
			name = "Ability Duration Effect",
			momentaryEffect = CharacterOngoingEffect.Create{}
		}
	end
}

ActivatedAbilityApplyAbilityDurationEffect.lingerTime = 0
ActivatedAbilityApplyAbilityDurationEffect.instant = true
ActivatedAbilityApplyAbilityDurationEffect.summary = 'Ability Duration Effect'

function ActivatedAbilityApplyAbilityDurationEffect:SummarizeBehavior(ability, creatureLookup)
    return "Apply Ability Duration Effect"
end

--If this effect applies to the caster then this is a way to out-of-line apply it, so
--we can apply it while still preparing to cast and get the effect.
function ActivatedAbilityApplyAbilityDurationEffect:ApplyOnCasting(casterToken)
    if self.applyto == "caster" or self.applyto == "caster_including_squad" then
        print("ApplyTo:: Applying effect")
        local result = casterToken.properties:ApplyTemporaryEffect(self.momentaryEffect)
        if result and result.cancel then
            game.Refresh{
                tokens = {[casterToken.charid] = true},
            }
            return function()
                if self.lingerTime > 0 then
                    dmhub.Schedule(math.min(self.lingerTime, 10), function()
                    print("ApplyTo:: Cancel")
                        result.cancel()
                        game.Refresh{
                            tokens = {[casterToken.charid] = true},
                        }
                    end)
                    return
                end
                    print("ApplyTo:: Cancel")
                result.cancel()
                game.Refresh{
                    tokens = {[casterToken.charid] = true},
                }
            end
        end
    end
end

function ActivatedAbilityApplyAbilityDurationEffect:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)

        print("ApplyTo:: Applying effect to", #targets)
    local tokenids = {}
	for i,target in ipairs(targets) do
		local targetCreature = target.token.properties
        tokenids[target.token.charid] = true
		self.momentaryEffect.iconid = ability.iconid
		self.momentaryEffect.display = ability.display
		local result = targetCreature:ApplyTemporaryEffect(self.momentaryEffect)

        --when the ability ends we remove the temporary effect.
        options.OnFinishCastHandlers = options.OnFinishCastHandlers or {}
        options.OnFinishCastHandlers[#options.OnFinishCastHandlers+1] = function()
            if self.lingerTime > 0 then
                dmhub.Schedule(math.min(self.lingerTime,10), function()
                    print("ApplyTo:: Cancel")
                    result.cancel()
                    game.Refresh{
                        tokens = tokenids,
                    }
                end)
                return
            end
                    print("ApplyTo:: Cancel")
            result.cancel()
        end
	end

    game.Refresh{
        tokens = tokenids,
    }
end

function ActivatedAbilityApplyAbilityDurationEffect:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:MomentaryEffectEditor(parentPanel, result)
	return result
end