local mod = dmhub.GetModLoading()

local g_triggerResourceId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c";

local g_abilityTypeChoices = {
    {
        id = "trigger",
        text = "Triggered Action",
    },
    {
        id = "free",
        text = "Free Triggered Action",
    },
    {
        id = "passive",
        text = "Passive",
    }
}

local g_targetChoices = {
    {
        id = "self",
        text = "Self",
    },
    {
        id = "selforally",
        text = "Self or Ally",
    },
    {
        id = "ally",
        text = "Ally",
    },
    {
        id = "enemy",
        text = "Enemy",
    },
    {
        id = "anycreature",
        text = "Any Creature",
    },
}

local g_triggerChoices = {
    {
        id = "powerroll",
        text = "Makes a Power Roll",
        triggeroncaster = true,
    },
    {
        id = "takedamage",
        text = "Target Takes Damage",
        triggerontarget = true,
    },
    {
        id = "dealdamage",
        text = "Target Deals Damage",
        triggeroncaster = true,
    },
    {
        id = "strike",
        text = "Targeted by Strike",
        triggerontarget = true,
    },
    {
        id = "forcemove",
        text = "Target Force Moves Another",
        triggeroncaster = true,
    },
    {
        id = "forcemoved",
        text = "Target is Force Moved",
        triggerontarget = true,
    },
    {
        id = "casting",
        text = "Target is Casting",
        triggerwhilecasting = true,
    },
}

local g_idToTriggerChoice = {}

for _,choice in ipairs(g_triggerChoices) do
    g_idToTriggerChoice[choice.id] = choice
end

--Apply the controlling creature's Modify Abilities modifiers to the trigger's
--effective range. Only the "range" attribute flows through (other Modify
--Abilities aspects don't apply to triggers, by design).
--
--Keyword filter: the Modify Abilities mod's keyword set must be a subset of the
--trigger's powerRollModifier.keywords (the keywords describing what abilities
--the trigger reacts to). Empty keyword filter matches every trigger.
--
--filterAbility GoblinScript: if set on the Modify Abilities mod, the mod is
--skipped -- triggers aren't abilities, so the filter can't be evaluated.
local function ComputeTriggerRange(modifier, creature)
    local range = modifier.range
    if range == nil or range == "" then
        return range
    end

    local triggerKeywords = modifier.powerRollModifier:try_get("keywords", {})

    local modifiers = creature:GetActiveModifiers()
    for _, modContext in ipairs(modifiers) do
        local m = modContext.mod
        if m.behavior == "modifyability"
            and m:try_get("filterAbility", "") == ""
            and m:try_get("applyToPowerRollTriggers", false) then
            local pass = true
            for kw, _ in pairs(m:try_get("keywords", {})) do
                if not triggerKeywords[kw] then
                    pass = false
                    break
                end
            end

            if pass then
                for _, attr in ipairs(m:try_get("attributes", {})) do
                    if attr.id == "range" then
                        local value = dmhub.EvalGoblinScript(attr.value,
                            GenerateSymbols(creature), "Calculate Trigger Range Modifier")
                        local val = nil
                        if attr.operation == "Set" then
                            val = tonumber(value)
                        elseif attr.operation == "Multiply" then
                            val = tonum(range) * tonum(value)
                        else
                            if type(range) == "string" and tonumber(range) == nil then
                                val = string.format("(%s) + (%s)", range, value)
                            else
                                val = tonum(range) + tonum(value)
                            end
                        end
                        if val ~= nil then
                            range = val
                        end
                    end
                end
            end
        end
    end

    return range
end

CharacterModifier.RegisterType("powertabletrigger", "Power Roll Trigger")

CharacterModifier.TypeInfo.powertabletrigger = {
    init = function(modifier)
        modifier.type = "trigger"
        modifier.targetType = "self"
        modifier.trigger = "takedamage"
        modifier.range = 10
        modifier.rules = ""

        modifier.powerRollModifier = CharacterModifier.new{
            behavior = 'power',
            guid = dmhub.GenerateGuid(),
            name = "Triggered Modifier",
            rules = "",
            source = "Trigger",
            rollType = "ability_power_roll",
            modtype = "none",
            activationCondition = false,
            keywords = {}
        }

    end,


    applyTriggerToCast = function(self, token, casterToken, ability, symbols, output)
        if self.trigger ~= "casting" then
            return
        end

        local triggerInfo = g_idToTriggerChoice[self.trigger]
        local triggerTarget = casterToken

        --Triggered and free triggered actions are both forbidden by effects
        --like "Can't use triggered actions"; passive entries are not actions.
        if self.type ~= "passive" and (not token.properties:CanUseTriggeredAbilities()) then
            return false
        end

        if self.type == "trigger" then
            local resources = token.properties:GetResources()
            local usage = token.properties:GetResourceUsage(g_triggerResourceId, "round")
            local available = (resources[g_triggerResourceId] or 0) - usage
            if available <= 0 then
                return false
            end
        end

        if not self.powerRollModifier:HasResourcesAvailable(token.properties) then
            return false
        end

        local selfIsTarget = (token.charid == triggerTarget.charid)
        if self.targetType == "self" then
            if not selfIsTarget then
                return
            end
        
        elseif self.targetType == "selforally" or self.targetType == "ally" then
            if selfIsTarget then
                if self.targetType == "ally" then
                    return
                end
            else
                local friends = token:IsFriend(triggerTarget)
                if not friends then
                    return
                end
            end
        elseif self.targetType == "enemy" then
            if selfIsTarget then
                return
            end
            local friends = token:IsFriend(triggerTarget)
            if friends then
                return
            end
        end

        if not selfIsTarget and self.range ~= "" then
            --range check (with Modify Abilities range mods applied).
            local effectiveRange = ComputeTriggerRange(self, token.properties)
            local distance = token:Distance(triggerTarget)
            if tonumber(distance) > ExecuteGoblinScript(effectiveRange, token.properties:LookupSymbol{}, 0) then
                return
            end
        end


        if self:try_get("castingFilter", "") ~= "" then
            local filter = ExecuteGoblinScript(self.castingFilter, token.properties:LookupSymbol(symbols), 0)
            if not GoblinScriptTrue(filter) then
                return
            end
        end

        local selfClone = DeepCopy(self)
        selfClone.powerRollModifier.casterCharid = token.charid

        if self:try_get("castingCostOverride","") ~= "" then
            local cost = ExecuteGoblinScript(self.castingCostOverride, token.properties:LookupSymbol(symbols), 0)
            selfClone.powerRollModifier.resourceCostType = "cost"
            selfClone.powerRollModifier.resourceCostAmount = cost
        end

        if self.type == "trigger" then
            selfClone.powerRollModifier.resourceCost = g_triggerResourceId
        end

        if selfClone.powerRollModifier:try_get("resourceCostType") == "cost" then
            if token.properties:GetHeroicOrMaliceResourcesAvailableToSpend() < ExecuteGoblinScript(selfClone.powerRollModifier:try_get("resourceCostAmount", "1"), token.properties:LookupSymbol(symbols), 1) then
                return false
            end
        elseif selfClone.powerRollModifier:try_get("resourceCostType") == "epic" then
            if token.properties:GetEpicResources() < ExecuteGoblinScript(selfClone.powerRollModifier:try_get("resourceCostAmount", "1"), token.properties:LookupSymbol(symbols), 1) then
                return false
            end
        end

        local entry = ActiveTrigger.new{
            id = dmhub.GenerateGuid(),
            powerRollModifier = selfClone,
            charid = token.charid,
            casterid = casterToken.charid,
            dismissOnTrigger = true,
        }

        if selfClone.powerRollModifier:try_get("resourceCostType") == "cost" then
            entry.heroicResourceCost = tonumber(selfClone.powerRollModifier:try_get("resourceCostAmount", 1))
        elseif selfClone.powerRollModifier:try_get("resourceCostType") == "epic" then
            entry.epicResourceCost = tonumber(selfClone.powerRollModifier:try_get("resourceCostAmount", 1))
        end

        if self:try_get("abilityTargets", "") ~= "" then
            local targets = ExecuteGoblinScript(self.abilityTargets, token.properties:LookupSymbol(symbols), 0)
            entry.params.targetcount = targets
        end

        output[#output+1] = entry
    end,

    --- @param token CharacterToken The token controlling the trigger.
    --- @param casterToken CharacterToken The token casting the ability
    --- @param targetToken CharacterToken The target of the ability
    --- @param ability ActivatedAbility
    --- @param rollProperties RollProperties
    --- @param castOptions table A table of options that go to an ability cast.
    applyTriggerToPowerRoll = function(self, token, casterToken, targetToken, ability, rollProperties, castOptions)
        local triggerInfo = g_idToTriggerChoice[self.trigger]
        print("TRIGGER::", self.trigger, "->", triggerInfo)
        local triggerTarget = casterToken
        castOptions = castOptions or {}
        local symbols = castOptions.symbols or {}

        if triggerInfo.triggerwhilecasting then
            return false
        end

        --Triggered and free triggered actions are both forbidden by effects
        --like "Can't use triggered actions"; passive entries are not actions.
        if self.type ~= "passive" and (not token.properties:CanUseTriggeredAbilities()) then
            return false
        end

        if self.type == "trigger" then
            local resources = token.properties:GetResources()
            local usage = token.properties:GetResourceUsage(g_triggerResourceId, "round")
            local available = (resources[g_triggerResourceId] or 0) - usage
            if available <= 0 then
                return false
            end
        end

        if not self.powerRollModifier:HasResourcesAvailable(token.properties) then
            return false
        end

        if self.powerRollModifier:try_get("resourceCostType") == "cost" then
            if (tonumber(token.properties:GetHeroicOrMaliceResourcesAvailableToSpend()) or 0) < (tonumber(self.powerRollModifier:try_get("resourceCostAmount", 1)) or 0) then
                return false
            end
        elseif self.powerRollModifier:try_get("resourceCostType") == "epic" then
            if (tonumber(token.properties:GetEpicResources()) or 0) < (tonumber(self.powerRollModifier:try_get("resourceCostAmount", 1)) or 0) then
                return false
            end
        end

        if triggerInfo.id == "strike" then
            if not ability:HasKeyword("Strike") then
                return false
            end
        end
        
        if triggerInfo.triggerontarget then
            triggerTarget = targetToken
        end

        local selfIsTarget = (token.charid == triggerTarget.charid)
        if self.targetType == "self" then
            if not selfIsTarget then
                return false
            end
        
        elseif self.targetType == "selforally" or self.targetType == "ally" then
            if selfIsTarget then
                if self.targetType == "ally" then
                    return false
                end
            else
                local friends = token:IsFriend(triggerTarget)
                if not friends then
                    return false
                end
            end
        elseif self.targetType == "enemy" then
            if selfIsTarget then
                return false
            end
            local friends = token:IsFriend(triggerTarget)
            if friends then
                return false
            end
        end

        if not selfIsTarget and self.range ~= "" then
            --range check (with Modify Abilities range mods applied).
            local effectiveRange = ComputeTriggerRange(self, token.properties)
            local distance = token:Distance(triggerTarget)
            if tonumber(distance) > ExecuteGoblinScript(effectiveRange, token.properties:LookupSymbol{}, 0) then
                return false
            end
        end

        if self.trigger == "dealdamage" or self.trigger == "takedamage" then
            --check that the roll does damage.
            if not rollProperties:HasDamage() then
                return false
            end

            local damageType = self:try_get("damageType", "all")
            if damageType ~= "all" then
                local damageTypes = rollProperties:GetDamageTypes()
                for _,t in ipairs(damageTypes or {}) do
                    if t == "untyped" and damageType == "typed" then
                        return false
                    end

                    if t ~= "untyped" and damageType == "untyped" then
                        return false
                    end
                end
                
            end
        end

        if self.trigger == "forcemove" or self.trigger == "forcemoved" then
            --check that the roll does some kind of forced movement.
            if not rollProperties:HasForcedMovement() then
                return false
            end
        end

        local abilityFilter = self:try_get("abilityFilter", "")
        if abilityFilter ~= "" then
            local filter = ExecuteGoblinScript(abilityFilter, token.properties:LookupSymbol{
                caster = casterToken.properties,
                target = targetToken.properties,
                triggerer = token.properties,
                ability = ability,
                cast = symbols.cast,
            }, 0)
            if not GoblinScriptTrue(filter) then
                return false
            end
        end

        local targetFilter = self:try_get("targetFilter", "")
        if targetFilter ~= "" then
            local filter = ExecuteGoblinScript(targetFilter, token.properties:LookupSymbol{
                caster = casterToken.properties,
                target = targetToken.properties,
                triggerer = token.properties,
                ability = ability,
                cast = symbols.cast,
            }, 0)
            if not GoblinScriptTrue(filter) then
                return false
            end
        end

        return true
    end,

    --- @param modifier CharacterModifier
    --- @param element Panel
	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true
		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local children = {}

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formInput"},
                    characterLimit = 30,
                    text = modifier.powerRollModifier.name,
                    change = function(element)
                        modifier.name = element.text
                        modifier.powerRollModifier.name = element.text
                        Refresh()
                    end,
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Rules:",
                },
                gui.Input{
                    classes = {"formInput"},
                    multiline = true,
                    fontSize = 14,
                    textAlignment = "topleft",
                    width = 300,
                    height = "auto",
                    minHeight = 28,
                    characterLimit = 300,
                    text = modifier.rules,
                    change = function(element)
                        modifier.rules = element.text
                        Refresh()
                    end,
                }
            }


			children[#children+1] = modifier:FilterConditionEditor()

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Action:",
                },
                gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
                    options = g_abilityTypeChoices,
                    idChosen = modifier.type,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.type = element.idChosen
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Target:",
                },
                gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
                    options = g_targetChoices,
                    idChosen = modifier.targetType,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.targetType = element.idChosen
                        Refresh()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Multi-target:",
                },
                gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
                    options = {
                        {
                            id = "one",
                            text = "One Target",
                        },
                        {
                            id = "all",
                            text = "All Targets",
                        }
                    },
                    idChosen = modifier:try_get("multitarget", "one"),
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.multitarget = element.idChosen
                        Refresh()
                    end,
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    classes = {"formLabel"},
                    text = "Trigger:",
                },
                gui.Dropdown{
                    styles = ThemeEngine.GetStyles(),
                    options = g_triggerChoices,
                    idChosen = modifier.trigger,
                    change = function(element)
                        ---@cast element Dropdown
                        modifier.trigger = element.idChosen
                        Refresh()
                    end,
                },
            }

            print("Modifier::", modifier.trigger)
            if modifier.trigger == "takedamage" or modifier.trigger == "dealdamage" then
                print("Modifier:: Damage type")
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Damage Type:",
                    },
                    gui.Dropdown{
                        styles = ThemeEngine.GetStyles(),
                        options = {
                            {
                                id = "all",
                                text = "All Damage Types",
                            },
                            {
                                id = "typed",
                                text = "Typed Damage",
                            },
                            {
                                id = "untyped",
                                text = "Untyped Damage",
                            },
                        },
                        idChosen = modifier:try_get("damageType", "all"),
                        change = function(element)
                            ---@cast element Dropdown
                            modifier.damageType = element.idChosen
                            Refresh()
                        end,
                    }
                }
            end

            if modifier.trigger == "casting" then

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Filter:",
                    },
                    gui.GoblinScriptInput{
                        value = modifier:try_get("castingFilter", ""),
                        change = function(element)
                            modifier.castingFilter = element.value
                            Refresh()
                        end,

                        documentation = {
                            domains = modifier:Domains(),
                            help = "This GoblinScript is used to determine whether the modifier applies to the ability being cast.",
                            output = "boolean",
                            examples = {
                                {
                                    script = "TargetCount = 1",
                                    text = "The modifier will only apply if the ability has exactly 1 target.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature who the modifying trigger comes from.",
                            symbols = {
                                {
                                    name = "Caster",
                                    type = "creature",
                                    desc = "The creature who is casting the ability.",
                                },
                                {
                                    name = "Ability",
                                    type = "ability",
                                    desc = "The ability being cast.",
                                },
                                {
                                    name = "Target",
                                    type = "creature",
                                    desc = "The creature being targeted by this ability. Only valid for single target abilities.",
                                },
                                {
                                    name = "TargetCount",
                                    type = "number",
                                    desc = "The number of targets the ability has.",
                                },
                            }
                        }

                    },
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Cost Override:",
                    },
                    gui.GoblinScriptInput{
                        value = modifier:try_get("castingCostOverride", ""),
                        change = function(element)
                            modifier.castingCostOverride = element.value
                            Refresh()
                        end,
                        documentation = {
                            domains = modifier:Domains(),
                            help = "This GoblinScript is used to determine the Heroic Resource cost of the ability. If present, the formula will replace the normal cost of the modifier.",
                            output = "boolean",
                            examples = {
                                {
                                    script = "Ability.HeroicResourceCost",
                                    text = "The trigger will have the same cost as the ability being cast.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature who the modifying trigger comes from.",
                            symbols = {
                                {
                                    name = "Caster",
                                    type = "creature",
                                    desc = "The creature who is casting the ability.",
                                },
                                {
                                    name = "Ability",
                                    type = "ability",
                                    desc = "The ability being cast.",
                                },
                                {
                                    name = "Target",
                                    type = "creature",
                                    desc = "The creature being targeted by this ability. Only valid for single target abilities.",
                                },
                                {
                                    name = "TargetCount",
                                    type = "number",
                                    desc = "The number of targets the ability has.",
                                },
                            }
                        }
                    },
                }



                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Targets:",
                    },
                    gui.GoblinScriptInput{
                        value = modifier:try_get("abilityTargets", ""),
                        change = function(element)
                            modifier.abilityTargets = element.value
                            Refresh()
                        end,
                        documentation = {
                            domains = modifier:Domains(),
                            help = "This GoblinScript is used to calculate the number of targets we modify the casting ability to have. If left blank it will not modify the number of targets.",
                            output = "number",
                            examples = {
                                {
                                    script = "Targets+1",
                                    text = "The ability will have one additional target.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature who the modifying trigger comes from.",
                            symbols = {
                                {
                                    name = "Caster",
                                    type = "creature",
                                    desc = "The creature who is casting the ability.",
                                },
                                {
                                    name = "Ability",
                                    type = "ability",
                                    desc = "The ability being cast.",
                                },
                                {
                                    name = "Target",
                                    type = "creature",
                                    desc = "The creature being targeted by this ability. Only valid for single target abilities.",
                                },
                                {
                                    name = "TargetCount",
                                    type = "number",
                                    desc = "The number of targets the ability has.",
                                },
                            }
                        }
                    },
                }

            end

            if modifier.trigger ~= "casting" then
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Ability Filter:",
                    },
                    gui.GoblinScriptInput{
                        value = modifier:try_get("abilityFilter", ""),
                        change = function(element)
                            modifier.abilityFilter = element.value
                            Refresh()
                        end,
                        documentation = {
                            domains = modifier:Domains(),
                            help = "This GoblinScript is used to filter which abilities can fire this trigger. Leave blank to allow all abilities.",
                            output = "boolean",
                            examples = {
                                {
                                    script = 'Ability.Keywords has "Melee"',
                                    text = "Only melee abilities can fire this trigger.",
                                },
                                {
                                    script = 'Ability.Keywords has "Strike"',
                                    text = "Only strikes can fire this trigger.",
                                },
                            },
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature who the modifying trigger comes from.",
                            symbols = {
                                {
                                    name = "Caster",
                                    type = "creature",
                                    desc = "The creature who is casting the ability.",
                                },
                                {
                                    name = "Target",
                                    type = "creature",
                                    desc = "The target of the ability.",
                                },
                                {
                                    name = "Triggerer",
                                    type = "creature",
                                    desc = "The creature who triggered the ability.",
                                },
                                {
                                    name = "Ability",
                                    type = "ability",
                                    desc = "The ability being cast.",
                                },
                                {
                                    name = "Cast",
                                    type = "spellcast",
                                    desc = "The cast context of the ability being cast.",
                                },
                            }
                        }
                    },
                }
            end

            if modifier.targetType ~= "self" then

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Target Filter:",
                    },
                    gui.GoblinScriptInput{
                        value = modifier:try_get("targetFilter", ""),
                        change = function(element)
                            modifier.targetFilter = element.value
                            Refresh()
                        end,

                        documentation = {
                            domains = modifier:Domains(),
                            help = "This GoblinScript is used to determine whether the modifier applies to a target.",
                            output = "boolean",
                            subject = creature.helpSymbols,
                            subjectDescription = "The creature who the modifying trigger comes from.",

                            examples = {
                                {
                                    script = "Caster has 'mark' and Caster.ConditionCaster('mark') = Triggerer",
                                    text = "This trigger can only be used if the caster (attacker) has been marked by the trigger's controller.",
                                },
                            },

                            symbols = {
                                {
                                    name = "Caster",
                                    type = "creature",
                                    desc = "The creature who is casting the ability.",
                                },
                                {
                                    name = "Target",
                                    type = "creature",
                                    desc = "The target of the attack.",
                                },
                                {
                                    name = "Triggerer",
                                    type = "creature",
                                    desc = "The creature who triggered the ability.",
                                },
                                {
                                    name = "Ability",
                                    type = "ability",
                                    desc = "The ability being cast.",
                                },
                                {
                                    name = "Cast",
                                    type = "spellcast",
                                    desc = "The cast context of the ability being cast.",
                                },
                            }
                        }
                    },
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Range:",
                    },
                    gui.GoblinScriptInput{
                        value = modifier.range,
                        change = function(element)
                            modifier.range = element.value
                            Refresh()
                        end,
                    }
                }

            end

            children[#children+1] = gui.Check{
                styles = ThemeEngine.GetStyles(),
                text = "Force Re-roll",
                value = modifier:try_get("forceReroll", false),
                change = function(element)
                    modifier.forceReroll = element.value
                    Refresh()
                end,
            }

            local rollModifierEditor = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
            }

            children[#children+1] = rollModifierEditor

        	local rollModifierTypeInfo = CharacterModifier.TypeInfo[modifier.powerRollModifier.behavior]
            rollModifierTypeInfo.createEditor(modifier.powerRollModifier, rollModifierEditor, {triggered = true})

            for index,powerRollModifier in ipairs(modifier:try_get("additionalCostModifiers", {})) do
                children[#children+1] = gui.Label{
                    fontSize = 18,
                    bold = true,
                    text = "Additional Cost Modifier",
                    tmargin = 16,
                    width = "auto",
                    height = "auto",
                    gui.Button{
                        classes = {"deleteButton", "sizeXs"},
                        halign = "right",
                        valign = "center",
                        x = 30,
                        requireConfirm = true,
                        press = function()
                            local items = modifier:try_get("additionalCostModifiers", {})
                            table.remove(items, index)
                            Refresh()
                        end,
                    }
                }

                children[#children+1] = gui.Check{
                    styles = ThemeEngine.GetStyles(),
                    text = "Override Base",
                    value = powerRollModifier:try_get("overrideBase", false),
                    change = function(element)
                        powerRollModifier.overrideBase = element.value
                        Refresh()
                    end,
                }

                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Name:",
                    },
                    gui.Input{
                        classes = {"formInput"},
                        characterLimit = 30,
                        text = powerRollModifier.name,
                        change = function(element)
                            powerRollModifier.name = element.text
                            Refresh()
                        end,
                    }
                }    
                
                children[#children+1] = gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Rules:",
                    },
                    gui.Input{
                        classes = {"formInput"},
                        multiline = true,
                        fontSize = 14,
                        textAlignment = "topleft",
                        width = 300,
                        height = "auto",
                        minHeight = 28,
                        characterLimit = 300,
                        text = powerRollModifier:try_get("rulesText", ""),
                        change = function(element)
                            powerRollModifier.rulesText = element.text
                            Refresh()
                        end,
                    }
                }

                local rollModifierEditor = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                }

                children[#children+1] = rollModifierEditor

                local rollModifierTypeInfo = CharacterModifier.TypeInfo.power
                rollModifierTypeInfo.createEditor(powerRollModifier, rollModifierEditor)


            end

            children[#children+1] = gui.Button{
                width = "auto",
                height = "auto",
                minWidth = 260,
                hpad = 16,
                vpad = 6,
                borderBox = true,
                fontSize = 16,
                text = "Add Additional Cost Modifier",
                click = function(element)

                    modifier.additionalCostModifiers = modifier:try_get("additionalCostModifiers", {})

                    modifier.additionalCostModifiers[#modifier.additionalCostModifiers+1] = CharacterModifier.new{
                        behavior = 'power',
                        guid = dmhub.GenerateGuid(),
                        name = "Triggered Modifier",
                        rules = "",
                        source = "Trigger",
                        rollType = "ability_power_roll",
                        modtype = "none",
                        activationCondition = false,
                        keywords = {}
                    }

                    Refresh()
                end,
            }

			element.children = children
        end

        Refresh()
    end,

}

--- @param modContext table
--- @param token CharacterToken
--- @param casterToken CharacterToken
--- @param targetToken CharacterToken
--- @param ability ActivatedAbility
--- @param rollProperties RollProperties
--- @param output table
function CharacterModifier:TriggerModsPowerRoll(modContext, token, casterToken, targetToken, ability, rollProperties, output, castOptions)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.applyTriggerToPowerRoll ~= nil then 
        self:InstallSymbolsFromContext(modContext)
        if typeInfo.applyTriggerToPowerRoll(self, token, casterToken, targetToken, ability, rollProperties, castOptions) then
            output[#output+1] = {
                modifier = self,
                charid = token.charid,
                targetid = targetToken.charid,
                hostile = not token:IsFriend(casterToken),
                originalAbilityRange = ability:GetRange(casterToken.properties),
                --set when the trigger comes from a carried consumable (see FillEquipmentModifiers).
                consumeItemId = modContext ~= nil and modContext.consumeItemId or nil,
            }
        end
    end
end

function CharacterModifier:TriggerModsCastingAbility(modContext, token, casterToken, ability, symbols, output)
	local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.applyTriggerToCast ~= nil then
        self:InstallSymbolsFromContext(modContext)
        typeInfo.applyTriggerToCast(self, token, casterToken, ability, symbols, output)
    end
end

--- consumeItemId is set when the trigger comes from a carried consumable
--- (Mirror Token, G'Allios Visiting Card): using the trigger spends one of it.
--- @param info {modifier: CharacterModifier, charid: string, targetid: string, consumeItemId: nil|string}
function CharacterModifier:TriggerPayCost(info)
    local casterToken = dmhub.GetTokenById(info.charid)
    if casterToken == nil then
        return
    end

    local costTrigger = self.type == "trigger"
    local consumeItemId = info.consumeItemId

    local hasCost = costTrigger or consumeItemId ~= nil

    if hasCost then
        casterToken:ModifyProperties{
            description = "Pay Trigger Cost",
            execute = function()
                if self.type == "trigger" then
                    local resourcesTable = dmhub.GetTable("characterResources")
                    local resourceInfo = resourcesTable[g_triggerResourceId]
                    casterToken.properties:ConsumeResource(g_triggerResourceId, resourceInfo.usageLimit, 1, string.format("Used triggered ability: %s", self.name))
                end

                if consumeItemId ~= nil then
                    --GiveItem falls back to unequipping, which covers a copy
                    --equipped back when the item was categorized as a trinket.
                    local props = casterToken.properties
                    local carried = props:GetItemQuantity(consumeItemId) > 0
                    if not carried then
                        for _,equipid in pairs(props:Equipment()) do
                            if equipid == consumeItemId then
                                carried = true
                                break
                            end
                        end
                    end
                    if carried then
                        props:GiveItem(consumeItemId, -1)
                        props:QueueLoseItemAnimation(consumeItemId)
                    end
                end
            end,
        }
    end
end

--- Whether a power-roll trigger is offered once per roll, with the reactor
--- picking which target it applies to, rather than once per target. Only "One
--- Target" triggered actions work this way: they spend the reactor's one
--- triggered action, so they can only ever apply to one target (Parry against a
--- strike that damages three allies is one Parry, not three). Free and passive
--- triggers can legally fire for every target, so they keep a prompt per target.
--- @param modifier CharacterModifier The powertabletrigger modifier.
--- @return boolean
function CharacterModifier.PowerRollTriggerChoosesTarget(modifier)
    return modifier:try_get("multitarget", "one") == "one" and modifier:try_get("type", "trigger") == "trigger"
end

--- The roll dialog's key for the prompt a trigger row feeds; rows with the same
--- key share one ActiveTrigger. "All Targets" triggers and target-choosing
--- triggered actions get one prompt per reactor, anything else one per target.
--- @param row table A roll dialog trigger row, as built by TriggerModsPowerRoll.
--- @param targetCharid string The charid of the roll target the row belongs to.
--- @return string
function ActiveTrigger.PowerRollRecordKey(row, targetCharid)
    local key = row.modifier.guid .. (row.charid or "")
    if row.modifier:try_get("multitarget", "one") == "all" or CharacterModifier.PowerRollTriggerChoosesTarget(row.modifier) then
        return key
    end
    return key .. targetCharid
end

--- The ActiveTrigger.triggered value a roll dialog trigger row stands for:
--- false, true, or the index of the additional-cost option picked on it.
--- @param row table A roll dialog trigger row.
--- @return boolean|number
function ActiveTrigger.PowerRollRowTriggered(row)
    local triggered = row.triggered
    if triggered then
        for k, val in pairs(row.augmentations or {}) do
            if val and type(k) == "number" then
                triggered = k
            end
        end
    end
    return triggered or false
end

--- Folds the roll dialog rows behind one prompt into the prompt's state. A
--- prompt shared across several targets counts as activated when any of its
--- rows is, and that row's target becomes the chosen target.
--- @param record ActiveTrigger The roll dialog's copy, carrying _tmp_triggerIndexes.
--- @param multitargets table The roll dialog's per-target entries.
--- @return boolean|number triggered
--- @return false|string chosenTargetId
--- @return false|string ping
function ActiveTrigger.PowerRollRowsState(record, multitargets)
    local triggered = false
    local chosenTargetId = false
    local ping = false
    for _, entry in ipairs(record:try_get("_tmp_triggerIndexes", {})) do
        local target = multitargets[entry.targetIndex]
        local row = target ~= nil and target.triggers[entry.triggerIndex] or nil
        if row ~= nil then
            local rowTriggered = ActiveTrigger.PowerRollRowTriggered(row)
            if rowTriggered and not triggered then
                triggered = rowTriggered
                chosenTargetId = entry.targetid or false
            end
            if row.ping and not ping then
                ping = row.ping
            end
        end
    end
    return triggered, chosenTargetId, ping
end

--- Pushes a prompt's state onto the roll dialog rows behind it: the reverse of
--- PowerRollRowsState. A prompt shared across several targets activates only
--- the row of the target it was used on and clears the others.
--- @param record ActiveTrigger The roll dialog's copy, carrying _tmp_triggerIndexes.
--- @param multitargets table The roll dialog's per-target entries.
--- @param onRow nil|fun(target: table, row: table) Called after each row is updated.
function ActiveTrigger.ApplyPowerRollStateToRows(record, multitargets, onRow)
    local appliedTargetId = nil
    if record.candidateTargets then
        appliedTargetId = record:GetTargetId()
    end
    for _, entry in ipairs(record:try_get("_tmp_triggerIndexes", {})) do
        local target = multitargets[entry.targetIndex]
        local row = target ~= nil and target.triggers[entry.triggerIndex] or nil
        if row ~= nil then
            local applies = appliedTargetId == nil or entry.targetid == appliedTargetId
            row.augmentations = {}
            row.triggered = (record.triggered and applies) and true or false
            row.retargetid = applies and record.retargetid or false
            if applies and type(record.triggered) == "number" then
                row.augmentations[record.triggered] = true
            end
            if onRow ~= nil then
                onRow(target, row)
            end
        end
    end
end

--- Refreshes a shared prompt's candidate targets from the roll dialog rows that
--- currently offer it; a target drops out while its roll fails the trigger's
--- requirement and comes back when it passes again.
--- @param record ActiveTrigger The roll dialog's copy, carrying _tmp_triggerIndexes.
--- @param entries {targetIndex: number, triggerIndex: number, targetid: string}[] The rows offering it now.
--- @return boolean changed True if the caller needs to re-dispatch the prompt.
function ActiveTrigger.SyncPowerRollCandidates(record, entries)
    local current = record:try_get("_tmp_triggerIndexes", {})
    local changed = #current ~= #entries
    if not changed then
        for i, entry in ipairs(entries) do
            local old = current[i]
            if old.targetIndex ~= entry.targetIndex or old.triggerIndex ~= entry.triggerIndex or old.targetid ~= entry.targetid then
                changed = true
                break
            end
        end
    end

    if not changed then
        return false
    end

    local targets = {}
    for _, entry in ipairs(entries) do
        targets[#targets + 1] = entry.targetid
    end
    record._tmp_triggerIndexes = entries
    record.targets = targets
    if record.chosenTargetId and not table.contains(targets, record.chosenTargetId) then
        record.chosenTargetId = false
    end
    return true
end

--- After a roll dialog activates one row of a shared prompt, clears the
--- prompt's other rows: a target-choosing triggered action applies to one target.
--- @param multitargets table The roll dialog's per-target entries.
--- @param row table The row just changed.
function ActiveTrigger.ClearOtherSharedPowerRollRows(multitargets, row)
    if (not row.triggered) or (not CharacterModifier.PowerRollTriggerChoosesTarget(row.modifier)) then
        return
    end

    for _, target in ipairs(multitargets or {}) do
        for _, other in ipairs(target.triggers or {}) do
            if other ~= row and other.modifier.guid == row.modifier.guid and other.charid == row.charid then
                other.triggered = false
                other.augmentations = {}
            end
        end
    end
end

local function PromptUsesTriggeredAction(triggerInfo)
    local modifier = triggerInfo.powerRollModifier
    return modifier ~= false and modifier ~= nil and modifier:try_get("type", "trigger") == "trigger"
end

--Accepting a prompt that costs the triggered action withdraws the reactor's other
--pending triggered-action prompts (using Parry removes Spend 1 Focus Parry). Runs
--inside the caller's ModifyProperties, so the withdrawals upload with the accept.
local g_baseDispatchAvailableTrigger = creature.DispatchAvailableTrigger
function creature:DispatchAvailableTrigger(triggerInfo)
    g_baseDispatchAvailableTrigger(self, triggerInfo)

    if triggerInfo == nil or (not triggerInfo.triggered) or (not PromptUsesTriggeredAction(triggerInfo)) then
        return
    end

    for id, other in pairs(self:try_get("availableTriggers", {})) do
        if id ~= triggerInfo.id and (not other.dismissed) and (not other.triggered) and PromptUsesTriggeredAction(other) then
            other.dismissed = true
        end
    end
end

--if included as part of a feature, renders a panel to appear in a dropdown suitable for selecting that feature.
function CharacterModifier:CreateDropdownPanel(featureInfo)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.createDropdownPanel ~= nil then
        return typeInfo.createDropdownPanel(self, featureInfo)
    end
    return nil
end

function CharacterModifier:HasDropdownPanel()
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    return typeInfo.createDropdownPanel ~= nil
end