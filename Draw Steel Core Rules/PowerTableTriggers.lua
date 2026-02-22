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

        if not selfIsTarget then
            --range check.
            local distance = token:Distance(triggerTarget)
            if tonumber(distance) > ExecuteGoblinScript(self.range, token.properties:LookupSymbol{}, 0) then
                return
            end
        end


        if self:try_get("castingFilter", "") ~= "" then
            local filter = ExecuteGoblinScript(self.castingFilter, token.properties:LookupSymbol(symbols), 0)
            if not GoblinScriptTrue(filter) then
                return
            end
        end

        local selfClone = dmhub.DeepCopy(self)
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
            if token.properties:GetHeroicOrMaliceResources() < ExecuteGoblinScript(selfClone.powerRollModifier:try_get("resourceCostAmount", "1"), token.properties:LookupSymbol(symbols), 1) then
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
        end

        if self.abilityTargets ~= "" then
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
        local triggerTarget = casterToken
        castOptions = castOptions or {}
        local symbols = castOptions.symbols or {}

        if triggerInfo.triggerwhilecasting then
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
            if (tonumber(token.properties:GetHeroicOrMaliceResources()) or 0) < (tonumber(self.powerRollModifier:try_get("resourceCostAmount", 1)) or 0) then
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

        if not selfIsTarget then
            --range check.
            local distance = token:Distance(triggerTarget)
            if tonumber(distance) > ExecuteGoblinScript(self.range, token.properties:LookupSymbol{}, 0) then
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
                    options = g_abilityTypeChoices,
                    idChosen = modifier.type,
                    change = function(element)
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
                    options = g_targetChoices,
                    idChosen = modifier.targetType,
                    change = function(element)
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
                    options = g_triggerChoices,
                    idChosen = modifier.trigger,
                    change = function(element)
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
                    gui.DeleteItemButton{
                        halign = "right",
                        valign = "center",
                        x = 30,
                        width = 12,
                        height = 12,
                        requireConfirm = true,
                        press = function()
                            local items = modifier:try_get("additionalCostModifiers", {})
                            table.remove(items, index)
                            Refresh()
                        end,
                    }
                }

                children[#children+1] = gui.Check{
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
                width = 260,
                height = 26,
                fontSize = 18,
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

--- @param info {modifier: CharacterModifier, charid: string, targetid: string}
function CharacterModifier:TriggerPayCost(info)
    local casterToken = dmhub.GetTokenById(info.charid)
    if casterToken == nil then
        return
    end

    local costTrigger = self.type == "trigger"

    local hasCost = costTrigger

    if hasCost then
        casterToken:ModifyProperties{
            description = "Pay Trigger Cost",
            execute = function()
                if self.type == "trigger" then
                    local resourcesTable = dmhub.GetTable("characterResources")
                    local resourceInfo = resourcesTable[g_triggerResourceId]
                    casterToken.properties:ConsumeResource(g_triggerResourceId, resourceInfo.usageLimit, 1, string.format("Used triggered ability: %s", self.name))
                end
            end,
        }
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