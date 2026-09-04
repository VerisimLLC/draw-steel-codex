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

--Evaluate this behavior's filterTarget (a per-behavior condition gate) against the
--caster, with the supplied symbols (e.g. the selected `mode`) in scope. Returns true
--if there is no gate, or the gate currently evaluates truthy. Used by the instant
--"apply on casting" path so the effect is mode-aware.
function ActivatedAbilityApplyAbilityDurationEffect:CastingFilterPasses(casterToken, symbols)
    local filterTarget = self:try_get("filterTarget", "")
    if type(filterTarget) ~= "string" then
        filterTarget = tostring(filterTarget)
    end
    if trim(filterTarget) == "" then
        return true
    end

    --the gate is normally written against a `target`; for the caster-applied
    --instant effect the caster is both caster and target.
    local syms = {}
    for k,v in pairs(symbols or {}) do
        syms[k] = v
    end
    syms.target = casterToken.properties

    return GoblinScriptTrue(ExecuteGoblinScript(filterTarget, casterToken.properties:LookupSymbol(syms), 1, "Ability Duration Effect filter"))
end

--If this effect applies to the caster then this is a way to out-of-line apply it, so
--we can apply it while still preparing to cast and get the effect.
--`symbols` (optional) carries the current casting symbols, notably `mode`, so the
--filterTarget gate can be mode-aware.
function ActivatedAbilityApplyAbilityDurationEffect:ApplyOnCasting(casterToken, symbols)
    if self.applyto == "caster" or self.applyto == "caster_including_squad" then
        if not self:CastingFilterPasses(casterToken, symbols) then
            return nil
        end
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