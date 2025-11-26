local mod = dmhub.GetModLoading()

--This file implements Triggered Abilities. They build heavily on Activated Abilities, just that they occur
--in response to some trigger rather than when the player decides.

RegisterGameType("TriggeredAbility", "ActivatedAbility")

TriggeredAbility.categorization = "Triggered Ability"
TriggeredAbility.despawnBehavior = "remove"
TriggeredAbility.DespawnBehaviors = {
    {
        id = "remove",
        text = "Remove Despawned Targets",
    },
    {
        id = "corpse",
        text = "Target Corpse",
    },
}

ActivatedAbility.OnTypeRegistered = function()
	TriggeredAbility.Types = {}

	for i,t in ipairs(ActivatedAbility.Types) do
		TriggeredAbility.Types[#TriggeredAbility.Types+1] = t
	end

	TriggeredAbility.Types[#TriggeredAbility.Types+1] = {
		id = 'momentary',
		text = 'Momentary Effect',
		createBehavior = function()
			return ActivatedAbilityApplyMomentaryEffectBehavior.new{
				name = "Momentary Effect",
				momentaryEffect = CharacterOngoingEffect.Create{}
			}
		end,
	}

	TriggeredAbility.TypesById = GetDropdownEnumById(TriggeredAbility.Types)
end

ActivatedAbility.OnTypeRegistered()


TriggeredAbility.TargetTypes = {
	{
		id = 'self',
		text = 'None/Self',
	},
	{
		id = 'all',
		text = 'Burst',
	},
	{
		id = 'attacker',
		text = 'Creature Attacking Me',
		condition = function(ability)
			return ability.trigger == "attacked" or ability.trigger == "hit" or ability.trigger == "losehitpoints" or ability.trigger == "inflictcondition" or ability.trigger == "winded" or ability.trigger == "dying"
		end,
	},
	{
		id = 'target',
		text = 'Target',
		condition = function(ability)
			return ability.trigger == "damage" or ability.trigger == "dealdamage" or ability.trigger == "movethrough" or ability.silent
		end,
	},
    {
        id = 'subject',
        text = 'Subject',
        condition = function(ability)
            return ability:try_get("subject", "self") ~= "self"
        end,
    },
    {
        id = "aura",
        text = "Creatures in Aura",
        condition = function(ability)
            return ability.trigger == "casterendturnaura"
        end,
    }
}

TriggeredAbility.triggers = {

	{
		id = "regainhitpoints",
		text = "Regain Stamina",
	},
	{
		id = "losehitpoints",
		text = "Lose Stamina",
        symbols = {
			damage = {
				name = "Damage",
				type = "number",
				desc = "The amount of damage taken when triggering this event.",
			},
			damagetype = {
				name = "Damage Type",
				type = "text",
				desc = "The type of damage taken when triggering this event.",
			},
            keywords = {
                name = "Keywords",
                type = "set",
                desc = "The keywords used to apply the damage.",
            },
            attacker = {
                name = "Attacker",
                type = "creature",
                desc = "The attacking creature. Only valid if Has Attacker is true.",
            },
            hasattacker = {
                name = "Has Attacker",
                type = "boolean",
                desc = "True if the damage has an attacker.",
            }
        },

        examples = {
            {
				script = "damage > 8 and (damage type is slashing or damage type is piercing)",
				text = "The triggered ability only activates if more than 8 damage was done and the damage was slashing or piercing damage."
			}
        },
	},
	{
		id = "zerohitpoints",
		text = "Drop to Zero Stamina",

        symbols = {
			damage = {
				name = "Damage",
				type = "number",
				desc = "The amount of damage taken when triggering this event.",
			},
			damagetype = {
				name = "Damage Type",
				type = "text",
				desc = "The type of damage taken when triggering this event.",
			},
        },

        examples = {
            {
				script = "damage > 8 and (damage type is slashing or damage type is piercing)",
				text = "The triggered ability only activates if more than 8 damage was done and the damage was slashing or piercing damage."
			}
        },

	},
	{
		id = "kill",
		text = "Kill a Creature",
	},
	{
		id = "creaturedeath",
		text = "Death",
	},
	{
		id = "saveagainstdamage",
		text = "Made Reactive Roll Against damage",
	},
	{
		id = "move",
		text = "Begin Movement",
        symbols = {
            path = {
                name = "Path",
                type = "path",
                desc = "The path taken by the creature during movement.",
            }
        }
	},
	{
		id = "finishmove",
		text = "Complete Movement",

        symbols = {
            path = {
                name = "Path",
                type = "path",
                desc = "The path taken by the creature during movement.",
            }
        }
        
	},
    {
        id = "forcemove",
        text = "Force Moved",
		symbols = {
			type = {
				name = "Type",
				type = "string",
				desc = "The type of forced movement. May be 'push', 'pull', or 'slide'",
			},
			hasattacker = {
				name = "Has Attacker",
				type = "creature",
				desc = "True if a creature is the one pushing/pulling/sliding",
			},
			attacker = {
				name = "Attacker",
				type = "creature",
				desc = "The creature who is causing the forced move to occur. Only valid if Has Attacker is true.",
			},


		}
    },
    {
        id = "teleport",
        text = "Teleports",
    },
	{
		id = "beginturn",
		text = "Start of Turn",
	},
	{
		id = "endturn",
		text = "End Turn",
	},
	{
		id = "beginround",
		text = "Begin Round",
		hide = function()
			return not GameSystem.HaveBeginRoundTrigger
		end,
	},
	{
		id = "endcombat",
		text = "End of Combat",
	},
	{
		id = "rollinitiative",
		text = "Draw Steel",
	},
	{
		id = "attack",
		text = "Attack an Enemy",
	},

	{
		id = "fumble",
		text = "Fumble an Attack",
		hide = function()
			--make sure our attack properties have a "fumble"
			local properties = GameSystem.GetRollProperties("attack", 0)
			for _,outcome in ipairs(properties:Outcomes()) do
				if outcome.failure and outcome.degree > 1 then
					return false
				end
			end

			return true
		end,
	},
	{
		id = "collide",
		text = "Collide with a Creature or Object",
        symbols = {
            speed = {
                name = "Speed",
                type = "number",
                desc = "The remaining speed of the creature when it collided.",
            },
            movementtype = {
                name = "Movement Type",
                type = "text",
                desc = "The type of forced movement that caused the collision: 'push', 'pull', or 'slide'.",
            },
            pusher = {
                name = "Pusher",
                type = "creature",
                desc = "The creature that pushed us into the object.",
            },
            withobject = {
                name = "With Object",
                type = "boolean",
                desc = "True if the collision is with an object.",
            },
            withcreature = {
                name = "With Creature",
                type = "boolean",
                desc = "True if the collision is with a creature.",
            },
        },
	},
	{
		id = "fall",
		text = "Land from a fall",
	},
}

function TriggeredAbility:GenerateManualVersion()
    local clone = DeepCopy(self)
    clone.temporaryClone = true
    clone.manualVersionOfTrigger = true

    clone.typeName = "ActivatedAbility"
    setmetatable(clone, ActivatedAbility.mt)

    local subjectType = self:try_get("subject", "self")
    if clone.targetType == "attacker" or clone.targetType == "subject" then
        clone.targetType = "target"
    elseif subjectType == "self" then
        clone.targetType = "self"
    elseif subjectType == "any" then
        clone.targetType = "target"
        clone.selfTarget = true
    elseif subjectType == "selfandheroes" then
        clone.targetType = "target"
        clone.targetAllegiance = "ally"
        clone.objectTarget = false
        clone.selfTarget = true
    elseif subjectType == "otherheroes" then
        clone.targetType = "target"
        clone.targetAllegiance = "ally"
        clone.objectTarget = false
        clone.selfTarget = false
    elseif subjectType == "selfandallies" then
        clone.targetType = "target"
        clone.targetAllegiance = "ally"
        clone.objectTarget = false
        clone.selfTarget = true
    elseif subjectType == "allies" then
        clone.targetType = "target"
        clone.targetAllegiance = "ally"
        clone.objectTarget = false
        clone.selfTarget = false
    elseif subjectType == "enemy" then
        clone.targetType = "target"
        clone.targetAllegiance = "enemy"
        clone.objectTarget = false
        clone.selfTarget = false
    elseif subjectType == "other" then
    end

    clone.range = clone:try_get("subjectRange", clone:try_get("range", "0"))

    clone.categorization = "Trigger"

    return clone
end

function TriggeredAbility.GetTriggerById(triggerid)
    for _,trigger in ipairs(TriggeredAbility.triggers) do
        if trigger.id == triggerid then
            return trigger
        end
    end
    
    return nil
end


function TriggeredAbility.RegisterTrigger(trigger)
	local index = #TriggeredAbility.triggers+1
	for i,entry in ipairs(TriggeredAbility.triggers) do
		if entry.id == trigger.id then
			index = i
			break
		end
	end
	TriggeredAbility.triggers[index] = trigger
	table.sort(TriggeredAbility.triggers, function(a,b) return a.text < b.text end)
end

TriggeredAbility.RegisterTrigger{
    id = "custom",
    text = "Custom Trigger",
    symbols = {
        {
            name = "Trigger Name",
            type = "text",
            desc = "The name of the trigger.",
        },
        {
            name = "Trigger Value",
            type = "number",
            desc = "A value associated with the trigger.",
        }
    }
}

TriggeredAbility.RegisterTrigger{
    id = "dealdamage",
    text = "Damage an Enemy",
    symbols = {
        {
            name = "Damage",
            type = "number",
            desc = "The amount of damage dealt.",
        },
        {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage dealt.",
        },
        {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        {
            name = "Target",
            type = "creature",
            desc = "The target of the damage.",
        },
    }
}

TriggeredAbility.RegisterTrigger{
    id = "winded",
    text = "Become Winded",
    symbols = {
        {
            name = "Damage",
            type = "number",
            desc = "The amount of damage dealt.",
        },
        {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage dealt.",
        },
        {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        {
            name = "Attacker",
            type = "creature",
            desc = "The creature which caused the winded condition.",
        },
    }
}

TriggeredAbility.RegisterTrigger{
    id = "dying",
    text = "Become Dying (Heroes Only)",
    symbols = {
        {
            name = "Damage",
            type = "number",
            desc = "The amount of damage dealt.",
        },
        {
            name = "Damage Type",
            type = "text",
            desc = "The type of damage dealt.",
        },
        {
            name = "Keywords",
            type = "set",
            desc = "The keywords used to apply the damage.",
        },
        {
            name = "Attacker",
            type = "creature",
            desc = "The creature which caused the dying condition.",
        },
    }
}

table.sort(TriggeredAbility.triggers, function(a,b) return a.text < b.text end)

function TriggeredAbility.GetTriggerDropdownOptions(includeNone)
	local result = {}

	if includeNone then
		result[#result+1] = {
			id = "none",
			text = "None",
		}
	end

	for _,item in ipairs(TriggeredAbility.triggers) do
		if item.hide == nil or (not item.hide()) then
			result[#result+1] = item
		end
	end

	table.sort(result, function(a,b)
		return a.text < b.text
	end)

	return result
end

TriggeredAbility.effects = {
	{
		id = "sethitpoints",
		text = "Set Hitpoints",
	}
}

ActivatedAbility.name = ""
ActivatedAbility.castingTime = "none"
TriggeredAbility.conditionFormula = ""
TriggeredAbility.save = 'none'
TriggeredAbility.savedc = '10'
TriggeredAbility.mandatory = true

function TriggeredAbility.OnDeserialize(self)
	ActivatedAbility.OnDeserialize(self)
end

function TriggeredAbility.Create(options)
	options = options or {}
	local args = ActivatedAbility.StandardArgs()
	args.trigger = "losehitpoints"
	for k,op in pairs(options) do
		args[k] = op
	end
	return TriggeredAbility.new(args)
end

local g_triggerDepth = 0
local g_triggerDepthFrame = -1

function TriggeredAbility:subjectHasRequiredCondition(subject, caster)
    if self:try_get("characterConditionRequired", "none") == "none" then
        return true
    end

    local conditionCaster = subject:HasCondition(self.characterConditionRequired)
    if self:try_get("characterConditionInflictedBySelf") then
        return conditionCaster == dmhub.LookupTokenId(caster)
    else
        return conditionCaster ~= false
    end
end

--auraControllerToken: token controlling an aura this is triggered from, or can be nil for a regular trigger attached to the creature it's triggering on.
--- @param characterModifier CharacterModifier
--- @param creature Creature
--- @param symbols table
--- @param auraControllerToken nil|CharacterToken
--- @param modContext table
--- @param argOptions {complete: function, debugLog: table}
--- @return nil
function TriggeredAbility:Trigger(characterModifier, creature, symbols, auraControllerToken, modContext, argOptions)

    argOptions = argOptions or {}

	local casterToken = dmhub.LookupToken(creature)
	if casterToken == nil then
        if argOptions.debugLog then
            argOptions.debugLog[#argOptions.debugLog+1] = {
                name = self.name,
                success = false,
                reason = "Creature not found",
            }
        end
		return
	end

    local subjectTarget = self:try_get("subject", "self")
    local subject = symbols and symbols.subject

    if subject == creature then
        subject = nil
    end

    if subject ~= nil and subjectTarget == "self" then
        if argOptions.debugLog then
            argOptions.debugLog[#argOptions.debugLog+1] = {
                name = self.name,
                success = false,
                reason = "Not self as subject",
            }
        end

        return
    end

    if subject == nil and subjectTarget ~= "self" and subjectTarget ~= "any" and subjectTarget ~= "selfandallies" and subjectTarget ~= "selfandheroes" then
        if argOptions.debugLog then
            argOptions.debugLog[#argOptions.debugLog+1] = {
                name = self.name,
                success = false,
                reason = "Wrong subject",
            }
        end

        return
    end

    if not self:subjectHasRequiredCondition(subject or creature, creature) then
        if argOptions.debugLog then
            local conditionInfo = dmhub.GetTable(CharacterCondition.tableName)[self:try_get("characterConditionRequired", "none")]
            local conditionName = conditionInfo and conditionInfo.name or self:try_get("characterConditionRequired", "none")
            argOptions.debugLog[#argOptions.debugLog+1] = {
                name = self.name,
                success = false,
                reason = "Subject does not have " .. conditionName,
            }
        end

        return
    end

    local subjectToken

    if subject ~= nil then
        subjectToken = dmhub.LookupToken(subject)
        if subjectToken == nil then

            if argOptions.debugLog then
                argOptions.debugLog[#argOptions.debugLog+1] = {
                    name = self.name,
                    success = false,
                    reason = "No subject token",
                }
            end

            return
        end
        local subjectRangeFormula = self:try_get("subjectRange", "")
        if subjectRangeFormula ~= "" then
            local range = dmhub.EvalGoblinScriptDeterministic(subjectRangeFormula, creature:LookupSymbol(symbols), nil, "Calculate Subject Range")
            if range ~= nil then
                local distance = subjectToken:Distance(casterToken)
                range = tonumber(range)
                if distance > range then
                    --out of range.

                    if argOptions.debugLog then
                        argOptions.debugLog[#argOptions.debugLog+1] = {
                            name = self.name,
                            success = false,
                            reason = "Out of range",
                        }
                    end

                    return
                end
            end
        end

        if subjectTarget == "selfandallies" or subjectTarget == "allies" then
            if not casterToken:IsFriend(subjectToken) then
                if argOptions.debugLog then
                    argOptions.debugLog[#argOptions.debugLog+1] = {
                            name = self.name,
                            success = false,
                            reason = "Not an ally",
                        }
                end

                return
            end
        elseif subjectTarget == "enemy" then
            if casterToken:IsFriend(subjectToken) then
                if argOptions.debugLog then
                    argOptions.debugLog[#argOptions.debugLog+1] = {
                        name = self.name,
                        success = false,
                        reason = "Not an enemy",
                    }
                end

                return
            end
        elseif subjectTarget == "selfandheroes" or subjectTarget == "otherheroes" then
            if not subjectToken.properties:IsHero() then

                if argOptions.debugLog then
                    argOptions.debugLog[#argOptions.debugLog+1] = {
                        name = self.name,
                        success = false,
                        reason = "Subject not a hero",
                    }
                end

                return
            end
        end
    end


	modContext = modContext or {}
	symbols = table.shallow_copy(symbols or {})
    symbols.mode = symbols.mode or 1

    if symbols.subject == nil then
        symbols.subject = creature
    end

	if trim(self.conditionFormula) ~= "" then
		local condition = dmhub.EvalGoblinScriptDeterministic(self.conditionFormula, creature:LookupSymbol(symbols), 0, "Trigger condition")
		if tonumber(condition) == 0 then
			--we fail the trigger condition

            if argOptions.debugLog then
                argOptions.debugLog[#argOptions.debugLog+1] = {
                    name = self.name,
                    success = false,
                    reason = "Trigger condition failed",
                }
            end

			return
		end
	end

	local targets

	if self.targetType == 'all' then
		targets = {}
		local range = self:GetRange(creature)
		for i,tok in ipairs(dmhub.allTokens) do
			if (tok.id ~= casterToken.id or self:try_get("selfTarget", false)) and self:TargetPassesFilter(casterToken, tok, symbols) and range >= tok:Distance(casterToken) then
				targets[#targets+1] = {
					loc = tok.loc,
					token = tok,
				}
			end
		end
    elseif self.targetType == 'subject' and subjectToken ~= nil then
        targets = {
            {
                loc = subjectToken.loc,
                token = subjectToken,
            }
        }
    elseif self.targetType == "aura" then
        print("AURA:: CASTING...")
        local aura = symbols.aura
        if aura == nil then
            print("AURA:: Could not find aura in triggered ability.", self.name)

            if argOptions.debugLog then
                argOptions.debugLog[#argOptions.debugLog+1] = {
                    name = self.name,
                    success = false,
                    reason = "No aura found",
                }
            end
            return
        end

        local tokens = dmhub.allTokens
        for i,tok in ipairs(tokens) do
            if tok.id ~= casterToken.id and aura.area:ContainsToken(tok) and self:TargetPassesFilter(casterToken, tok, symbols) then
                targets = targets or {}
                targets[#targets+1] = {
                    loc = tok.loc,
                    token = tok,
                }
            end
        end

        if targets == nil or #targets == 0 then
            print("AURA:: NO TARGETS FOUND IN AURA")
            return
        end

        print("AURA:: FOUND", #targets)
        
	elseif self.targetType == 'attacker' or self.targetType == 'target' then
		if symbols[self.targetType] == nil then

            if argOptions.debugLog then
                argOptions.debugLog[#argOptions.debugLog+1] = {
                    name = self.name,
                    success = false,
                    reason = self.targetType .. " not available",
                }
            end

			return
		end

		local attackerCreature = symbols[self.targetType]
        if type(attackerCreature) == "function" then
            attackerCreature = attackerCreature("self")
        end
		local attackerToken = dmhub.LookupToken(attackerCreature)

		if attackerToken == nil then

            if argOptions.debugLog then
                argOptions.debugLog[#argOptions.debugLog+1] = {
                    name = self.name,
                    success = false,
                    reason = "No attacker token",
                }
            end

			return
		end
		
		targets = {
			{
				loc = attackerToken.loc,
				token = attackerToken,
			}
		}

	else
		targets = {
			{
				loc = casterToken.loc,
				token = casterToken,
			},
		}
	end

    if argOptions.debugLog then
        argOptions.debugLog[#argOptions.debugLog+1] = {
            name = self.name,
            success = true,
        }
    end

	local executeTrigger = function()

		local options = { symbols = symbols }
		local needCoroutine = self:CastInstantPortion(casterToken, targets, options)
		if not needCoroutine then
			if options.pay then
				self:ConsumeResources(casterToken, {
					costOverride = options.costOverride,
				})

			end

			return
		end

		local nframe = dmhub.FrameCount()

		if nframe ~= g_triggerDepthFrame then
			g_triggerDepth = 0
			g_triggerDepthFrame = nframe
		end

		if g_triggerDepth > 8 then
			printf("Too many triggers stacked in the same frame, aborting.")
			return
		end

		g_triggerDepth = g_triggerDepth + 1

        print("CAST:: COROUTINE:: Start synchronous", tostring(coroutine.running()))
		dmhub.CoroutineSynchronous(TriggeredAbility.TriggerCo, self, targets, characterModifier, casterToken, creature, symbols, auraControllerToken, modContext, argOptions)

		g_triggerDepth = g_triggerDepth - 1
	end

	if self.mandatory or (self:try_get("mandatoryDifferentPlayer", false) and casterToken.activeControllerId == nil) then
		executeTrigger()
	else
		dmhub.Coroutine(function()
			local guid = dmhub.GenerateGuid()

            local targetids = {}
            for i,tok in ipairs(targets) do
                if tok.token.charid ~= casterToken.charid then
                    targetids[#targetids+1] = tok.token.charid
                end
            end

            local casterSymbols = casterToken.properties:LookupSymbol{}

            local activateText = nil
            local modes = nil
            if self.multipleModes then
                local modeList = self:try_get("modeList", {})
                activateText = modeList[1].text
                for i=2,#modeList do
                    local modeEntry = modeList[i]
                    local passes = true
                    local formula = modeEntry.condition or ""
                    if formula ~= "" then
                        local condition = dmhub.EvalGoblinScriptDeterministic(formula, creature:LookupSymbol(symbols), 0, "Trigger condition")
                        if tonumber(condition) == 0 then
                            passes = false
                        end
                    end

                    if passes then
                        modes = modes or {}
                        modes[#modes+1] = {
                            text = modeEntry.text,
                            rules = StringInterpolateGoblinScript(modeEntry.rules, casterSymbols),
                        }
                    end
                end
            end

            local text = self.name
            local cost = self:try_get("resourceNumber")
            if type(cost) == "number" then
                text = string.format("%s (%d %s)", text, cost, casterToken.properties:GetHeroicResourceName())
            end

			local trigger = ActiveTrigger.new{
				id = guid,
                activateText = activateText,
				text = text,
				rules = StringInterpolateGoblinScript(self:try_get("triggerPrompt"), casterSymbols),
                targets = targetids,
                clearOnDismiss = true,
                modes = modes,
                heroicResourceCost = tonumber(cost),
			}

            if self:ActionResource() == CharacterResource.triggerResourceId then
                trigger.free = false
            end

			casterToken:ModifyProperties{
				description = "Trigger",
				undoable = false,
				execute = function()
					casterToken.properties:DispatchAvailableTrigger(trigger)
				end,
			}

            local triggers = casterToken.properties:GetAvailableTriggers() or {}
            trigger = triggers[guid]

            local turnid = casterToken.properties:GetResourceRefreshId("turn")
            local starttime = dmhub.Time()

			local sustain = true
			local gameupdate = dmhub.ngameupdate
            
			while trigger ~= nil and (not trigger.triggered) and (not trigger.dismissed) and sustain do
				coroutine.yield()

				trigger = nil
                if casterToken == nil or (not casterToken.valid) then
                    break
                end

                if casterToken.properties:GetResourceRefreshId("turn") ~= turnid then
                    local runtime = dmhub.Time() - starttime
                    if runtime < 2 then
                        --let it roll over to the next turn as our turn id since it changed
                        --turn almost immediately.
                        turnid = casterToken.properties:GetResourceRefreshId("turn")
                    elseif runtime > 8 then
                        --make sure we show the trigger for at least 8 seconds, then expire it.
                        sustain = false
                    end
                end

                local triggers = casterToken.properties:GetAvailableTriggers() or {}
                trigger = triggers[guid]

                --give at least 5 seconds to recover if the trigger is not found.
                while trigger == nil and dmhub.Time() < starttime+5 and casterToken.valid do

                    local triggers = casterToken.properties:GetAvailableTriggers() or {}
                    trigger = triggers[guid]

				    coroutine.yield()
                end

                if trigger == nil or not casterToken.valid then
                    break
                end

                if trigger and gameupdate ~= dmhub.ngameupdate then
                    gameupdate = dmhub.ngameupdate

                    if not self:CanAfford(casterToken) then
                        sustain = false
                    end

                    if trim(self.conditionFormula) ~= "" then
                        local condition = dmhub.EvalGoblinScriptDeterministic(self.conditionFormula,
                            casterToken.properties:LookupSymbol(symbols), 0, "Trigger condition")
                        if tonumber(condition) == 0 then
                            --we no longer sustain the trigger condition
                            sustain = false
                        end
                    end
                end
            end

			if trigger ~= nil and casterToken ~= nil and casterToken.valid then
				casterToken:ModifyProperties{
					description = "Clear Trigger",
					undoable = false,
					execute = function()
						casterToken.properties:ClearAvailableTrigger(trigger)
					end,
				}
			end

			if trigger ~= nil and trigger.triggered then
                local removes = {}
                for i, target in ipairs(targets) do
                    if target.token ~= nil and (not target.token.valid) then
                        if self.despawnBehavior == "remove" then
                            removes[#removes+1] = i
                        else
                            local corpse = target.token:FindCorpse()
                            if corpse == nil then
                                removes[#removes+1] = i
                            else
                                target.token = corpse
                            end
                        end
                    end
                end

                for i=#removes,1,-1 do
                    table.remove(targets, removes[i])
                end

                if #removes > 0 and #targets == 0 then
                    --no targets left, so cancel.
                    return
                end

                if type(trigger.triggered) == "number" then
                    --the first mode is just the 'activate' which will show up as true.
                    symbols.mode = trigger.triggered + 1
                else
                    symbols.mode = 1
                end
				dmhub.Schedule(0.01, function() --make execute in the main thread with a schedule.
					executeTrigger()
				end)
			end
		end)
	end

end

function TriggeredAbility:TriggerCo(targets, characterModifier, casterToken, creature, symbols, auraControllerToken, modContext, argOptions)

    print("COROUTINE:: TriggerCo", self.name, "targets:", #targets, "symbols:", symbols, "auraControllerToken:", auraControllerToken and auraControllerToken.name or "nil", "modContext:", modContext)
    argOptions = argOptions or {}

	if auraControllerToken == nil then
		auraControllerToken = casterToken
	end

    local targetArea

    if self.targetType == 'all' then
        targetArea = dmhub.CalculateShape{
            shape = "RadiusFromCreature",
            targetPoint = casterToken:PosAtLoc(casterToken.loc),
            token = casterToken,
            range = 0,
            radius = self:GetRange(creature),
        }
    end

	self:Cast(auraControllerToken, targets,

	{
		symbols = symbols,
        targetArea = targetArea,
		alreadyInCoroutine = true,
        OnFinishCastHandlers = {
            function()
                if argOptions.complete then
                    argOptions.complete()
                end
            end,
        },
	}
	)

    print("COROUTINE:: TriggerCo finished", self.name, "targets:", #targets, "symbols:", symbols, "auraControllerToken:", auraControllerToken and auraControllerToken.name or "nil", "modContext:", modContext)
end

function TriggeredAbility:RenderTokenDependent(token, result)
	local text = ""
	if self.mandatory then
		text = "This ability will activate automatically."
	elseif token.properties:TriggeredAbilityEnabled(self) then
		text = "This ability will activate automatically. Click to prevent it from activating."
	else
		text = "Activation of this ability is disabled. Click to enable it."
	end

	result[#result+1] = gui.Label{
		text = text,
		italics = true,
	}
end


--triggered abilities don't generally count as "casting an ability".
function TriggeredAbility:CountsAsRegularAbilityCast()
    return false
end

function TriggeredAbility:ShowChatMessageOnCast()
    return not self.mandatory
end