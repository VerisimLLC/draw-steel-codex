local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityAugmentedAbilityBehavior:ActivatedAbilityBehavior
--- @field new fun(o?: table): ActivatedAbilityAugmentedAbilityBehavior
--- @field hasCast boolean Internal flag set to true once this behavior has synthesized its augmented cast.
--- @field modifier CharacterModifier The modifier that defines how abilities are augmented.
--- @field filterAbilityTargets? string GoblinScript target filter for the augmented abilities ("" for none); read with try_get.
--- Synthesizes modified copies of the caster's abilities with the augment applied, then presents them for casting.
ActivatedAbilityAugmentedAbilityBehavior = RegisterGameType("ActivatedAbilityAugmentedAbilityBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityAugmentedAbilityBehavior.hasCast = false

--- True when this cast is being aimed by a creature hostile to the one making
--- it -- a monster forcing its victim to strike ("the target makes a free
--- strike against a creature of the cackler's choice"). Every "target makes a
--- ..." standard ability routes through this behavior, so the whole family is
--- covered here.
--- An ally directing the cast (the tactician telling a hero to strike) shares
--- the caster's enemies, and a self-invoke ("you may make a free strike") is
--- the caster's own choice, so neither counts: only a hostile director reverses
--- which side the chooser wants to hit.
--- @param ability ActivatedAbility The augmenting ability, carrying the invoker.
--- @param creature any The creature that will make the synthesized cast.
--- @return boolean
local function AimedByOpposingCreature(ability, creature)
    local invoker = ability:try_get("invoker")
    if invoker == nil or invoker == creature then
        return false
    end

    local invokerToken = dmhub.LookupToken(invoker)
    local casterToken = dmhub.LookupToken(creature)
    if invokerToken == nil or (not invokerToken.valid) or casterToken == nil or (not casterToken.valid) then
        return false
    end

    if invokerToken.charid == casterToken.charid then
        return false
    end

    return not invokerToken:IsFriend(casterToken)
end

function ActivatedAbilityAugmentedAbilityBehavior:SynthesizeAbilities(ability, creature)
	local abilities = creature:GetActivatedAbilities()

	local typeInfo = CharacterModifier.TypeInfo[self.modifier.behavior]
	local filterFunction = typeInfo.willModifyAbility
	local modifierFunction = typeInfo.modifyAbility

    local abilitiesWithBifurcations = {}
    for _,a in ipairs(abilities) do
        if a.meleeAndRanged then
            abilitiesWithBifurcations[#abilitiesWithBifurcations+1] = a.meleeVariation
            abilitiesWithBifurcations[#abilitiesWithBifurcations+1] = a.rangedVariation
        else
            abilitiesWithBifurcations[#abilitiesWithBifurcations+1] = a
        end
    end

    abilities = abilitiesWithBifurcations

	local result = {}

	for _,a in ipairs(abilities) do
		if a ~= ability and filterFunction(self.modifier, creature, a) then
			local synth = DeepCopy(a)
			synth._tmp_temporaryClone = true

			-- Apply modifier behaviors before overriding casting properties
			synth = modifierFunction(self.modifier, creature, synth)

	        local OnBeginCast = ability:try_get("OnBeginCast")
	        local OnFinishCast = ability:try_get("OnFinishCast")

            if OnBeginCast ~= nil then
                local oldBeginCast = synth:try_get("OnBeginCast")
                --MUST forward (synthAbility, castOptions): the invoke path's
                --OnBeginCast wrapper (AbilityInvokeAbility ExecuteInvoke) uses
                --castOptions to install its cast-finished handler into
                --options.OnFinishCastHandlers -- the only finish signal that
                --survives the ability's function fields being stripped mid-cast.
                --Dropping the args here silently skipped that install and left
                --the invoke waiting on casting=true forever once the fragile
                --ability.OnFinishCast fallback was destroyed (the "triggered
                --abilities all stop working" strand).
                synth.OnBeginCast = function(synthAbility, castOptions)
                    OnBeginCast(synthAbility, castOptions)
                    if oldBeginCast ~= nil then
                        oldBeginCast(synthAbility, castOptions)
                    end
                end
            end

            if OnFinishCast ~= nil then
                local oldFinishCast = synth:try_get("OnFinishCast")
                synth.OnFinishCast = function(ability, options)
                    OnFinishCast(ability, options)
                    if oldFinishCast ~= nil then
                        oldFinishCast(ability, options)
                    end
                end
            end

			--we copy some casting time and resource usage aspects of the synthesizer into the synthesized
			--ability. Note that we must take care to make sure that it's still a valid instance of
			--the target type.
			synth.actionResourceId = ability:try_get("actionResourceId")
			synth.actionNumber = ability.actionNumber
			synth.castingTime = ability.castingTime
			synth.castingTimeDuration = ability:try_get("castingTimeDuration")

            --The targeting slider's "Enemies" position is evaluated against the
            --creature making the strike, so on a forced strike it withholds
            --exactly the creatures the forcing creature is entitled to name --
            --the victim's own allies -- and reads as a prohibition. Mark the
            --cast so the slider opens on "Creatures" instead; see
            --ActivatedAbility:TargetModeOptions. Report 2P99A7MU.
            synth._tmp_aimedByOpposingCreature = AimedByOpposingCreature(ability, creature)

            --If the invoke overrode targeting, apply it to the ability built here,
            --since that is the one actually cast (e.g. Subvert's signature ability).
            if ability:try_get("_tmp_targetingOverride") ~= nil then
                synth:OverrideTargeting(ability._tmp_targetingOverride)
            end

            if not self.modifier:try_get("mustPayResourceCost", false) then
                --mustPayResourceCost off: the routed ability does not pay its own cost; it
                --inherits (and thus pays) the augmenter ability's cost instead.
    			synth.resourceCost = ability.resourceCost
    			synth.resourceNumber = ability.resourceNumber
            elseif ability:try_get("resourceCost", "none") ~= "none" then
                --Force parent ability to pay their resource cost
                local parentAbility = ability
                local priorBeginCast = synth:try_get("OnBeginCast")
                synth.OnBeginCast = function(synthAbility, castOptions)
                    if priorBeginCast ~= nil then
                        priorBeginCast(synthAbility, castOptions)
                    end

                    local casterProps = castOptions.symbols and castOptions.symbols.caster
                    if casterProps == nil then
                        return
                    end
                    local casterToken = dmhub.LookupToken(casterProps)
                    if casterToken == nil or not casterToken.valid then
                        return
                    end

                    --Same remap as ActivatedAbility:GetCost: GetHeroicOrMaliceId keeps
                    --summoner-shared summons on the heroic resource instead of Malice.
                    local effectiveResourceCost = parentAbility.resourceCost
                    if effectiveResourceCost == CharacterResource.heroicResourceId then
                        effectiveResourceCost = casterToken.properties:GetHeroicOrMaliceId()
                    end

                    local fullCost = parentAbility:GetCost(casterToken)
                    local resourceDetails = {}
                    for _,entry in ipairs(fullCost.details or {}) do
                        if entry.cost == effectiveResourceCost then
                            resourceDetails[#resourceDetails+1] = entry
                        end
                    end

                    if #resourceDetails == 0 then
                        return
                    end

                    castOptions.OnFinishCastHandlers = castOptions.OnFinishCastHandlers or {}
                    castOptions.OnFinishCastHandlers[#castOptions.OnFinishCastHandlers+1] = function(finishedAbility, finishToken, finishOptions)
                        if finishToken == nil or not finishToken.valid or finishToken.properties == nil then
                            return
                        end
                        if finishOptions.abort or finishOptions.atexit then
                            return
                        end
                        parentAbility:ConsumeResources(finishToken, {costOverride = {details = resourceDetails}})
                    end
                end
            end

			synth.usesSpellSlots = ability.usesSpellSlots

            if self:try_get("filterAbilityTargets", "") ~= "" then
                local filter = self:try_get("filterAbilityTargets", "")
                local customFilters = synth:get_or_add("customTargetFilters", {})
                customFilters[#customFilters+1] = filter
            end
			if ability:has_key("level") then
				synth.level = ability.level
			end

			result[#result+1] = synth
		end
	end

	return result
end

function ActivatedAbilityAugmentedAbilityBehavior.AbilityModifierEditor(self, parentPanel, list)
	local element = gui.Panel{
		x = 20,
		width = "auto",
		height = "auto",
		flow = "vertical",
	}

    list[#list+1] = gui.Panel{
        classes = {"formPanel"},
        height = "auto",
        gui.Label{
            classes = {"formLabel"},
            text = "Target Filter:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("filterAbilityTargets", ""),
            change = function(element)
                self.filterAbilityTargets = element.value
            end,
            documentation = {
                help = "This GoblinScript is used to determine if this modifier applies to a target.",
                output = "boolean",
                examples = {
                    {
                        script = "Target.Type is undead",
                        text = "This modifier only applies to undead targets.",
                    },
                    {
                        script = "Target.Hitpoints < Target.Maximum Hitpoints",
                        text = "This modifier only applies to targets that are damaged.",
                    },
                },
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is affected by this modifier",
                symbols = {
                    target = {
                        name = "Target",
                        type = "creature",
                        desc = "The creature targeted with damage.",
                        examples = {
                            "Target.Type is undead",
                            "Target.Hitpoints < Target.Maximum Hitpoints",
                        },
                    },
                    caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The creature that is casting the ability.",
                    },
                },
            }
        },
    }


	local typeInfo = CharacterModifier.TypeInfo[self.modifier.behavior] or {}
	local createEditor = typeInfo.createEditor
	if createEditor ~= nil then
		createEditor(self.modifier, element)
	end

	list[#list+1] = element
end

function ActivatedAbilityAugmentedAbilityBehavior:EditorItems(parentPanel)
	local result = {}
	self:AbilityModifierEditor(parentPanel, result)
	return result
end