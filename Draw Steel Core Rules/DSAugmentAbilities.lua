local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityAugmentedAbilityBehavior:ActivatedAbilityBehavior
--- @field hasCast boolean Internal flag set to true once this behavior has synthesized its augmented cast.
--- @field modifier CharacterModifier The modifier that defines how abilities are augmented.
--- Synthesizes modified copies of the caster's abilities with the augment applied, then presents them for casting.
ActivatedAbilityAugmentedAbilityBehavior = RegisterGameType("ActivatedAbilityAugmentedAbilityBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityAugmentedAbilityBehavior.hasCast = false

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
                synth.OnBeginCast = function()
                    OnBeginCast()
                    if oldBeginCast ~= nil then
                        oldBeginCast()
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

                    local effectiveResourceCost = parentAbility.resourceCost
                    if effectiveResourceCost == CharacterResource.heroicResourceId and casterToken.properties.resourceid ~= CharacterResource.heroicResourceId then
                        effectiveResourceCost = casterToken.properties.resourceid
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