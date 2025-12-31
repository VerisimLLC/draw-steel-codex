local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityInvokeAbilityBehavior
ActivatedAbilityInvokeAbilityBehavior = RegisterGameType("ActivatedAbilityInvokeAbilityBehavior", "ActivatedAbilityBehavior")

--- @class AbilityInvocation
AbilityInvocation = RegisterGameType("AbilityInvocation")

AbilityUtils = {
	--utility to scan an ability for e.g. <<range>> and extract all parameters.
	ExtractAbilityParameters = function(node, output)
		if type(node) ~= "table" then
			return
		end

		for k,v in pairs(node) do
			if type(v) == "string" then
				local s = v

				for count=1,8 do
					local match = regex.MatchGroups(s, "^.*?<<(?<name>[a-zA-Z_]+)>>(?<tail>.*)$")
					if match == nil then
						break
					end

					output[match.name] = true
					s = match.tail
				end

			elseif type(v) == "table" then
				AbilityUtils.ExtractAbilityParameters(v, output)
			end
		end
	end,

	DeepReplaceAbility = function(node, from, to)
		if type(node) ~= "table" then
			return
		end

		for k,v in pairs(node) do
			if v == from then
				node[k] = to
			elseif type(v) == "string" then
				node[k] = regex.ReplaceAll(v, from, to)
			else
				AbilityUtils.DeepReplaceAbility(v, from, to)
			end
		end
	end,

	--utility to scan for an <<expression>> in a string and evaluate it as goblin script.
	--Useful to evaluate in the context of the caster.
	SubstituteAbilityParameters = function(str, symbols)
        str = StringInterpolateGoblinScript(str, symbols)
		local result = ""
		for i=1,8 do
			local match = regex.MatchGroups(str, "^(?<head>.*)?<<(?<expression>.*?)>>(?<tail>.*)$")
			if match == nil then
				result = result .. str
				break
			end

			result = result .. match.head

            local val = dmhub.EvalGoblinScript(match.expression, symbols, "Substitute parameter in invocation") 
			result = result .. val

			str = match.tail
		end

		return result
	end,
}



ActivatedAbility.RegisterType
{
	id = 'invoke_ability',
	text = 'Invoke Ability',
	createBehavior = function()
		local customAbility = ActivatedAbility.Create()
		customAbility.name = "Invoked Ability"
		return ActivatedAbilityInvokeAbilityBehavior.new{
			customAbility = customAbility,
		}
	end,
}

ActivatedAbilityInvokeAbilityBehavior.summary = 'Invoke Ability'
ActivatedAbilityInvokeAbilityBehavior.promptText = ''

--if true we will invoke on the caster token.
ActivatedAbilityInvokeAbilityBehavior.invokeOnCaster = false
ActivatedAbilityInvokeAbilityBehavior.runOnController = false


function ActivatedAbilityInvokeAbilityBehavior:Cast(ability, casterToken, targets, options)

    print("INVOKE:: Casting on", #targets, ability.name, "coroutine:", coroutine.running())
    --TODO: maybe only commit to paying with more generous criteria -- only if an ability
    --is actually used?
    ability:CommitToPaying(casterToken, options)
    for i,target in ipairs(targets) do
        if target.token ~= nil then
            print("INVOKE:: CASTING ON TARGET", i, "/", #targets)


            --be careful not to put anything in here we don't want to transmit to the database.
			local symbols = { spellname = options.symbols.spellname or ability.name, charges = options.symbols.charges, cast = options.symbols.cast, forcedMovementOrigin = options.symbols.forcedMovementOrigin }

			if self.runOnController and target.token.activeControllerId ~= nil and self.abilityType ~= "custom" then

                --clean out the ability so we don't copy too much.
                local cast = DeepCopy(options.symbols.cast)
                cast.ability = nil
                symbols.cast = cast

                local subjectid
                if options.symbols.subject ~= nil then
                    local s = options.symbols.subject
                    if type(s) == "function" then
                        s = s("self")
                    end

                    subjectid = dmhub.LookupTokenId(s)
                end


				--dispatch this to run on the controller.
				local invocation = AbilityInvocation.new{
					timestamp = ServerTimestamp(),
					userid = target.token.activeControllerId,
					abilityType = self.abilityType,
					namedAbility = self.namedAbility,
					standardAbility = self.standardAbility,
                    standardAbilityParams = self:try_get("standardAbilityParams"),
					targeting = self.targeting,
					invokerid = casterToken.id,
					casterid = cond(self.invokeOnCaster, casterToken.id, target.token.id),
                    targetid = target.token.id,
                    subjectid = subjectid,
					symbols = symbols,
					abilityAttr = {
						promptOverride = cond(self.promptText ~= "", StringInterpolateGoblinScript(self.promptText, casterToken.properties:LookupSymbol{})),
					}
				}

				target.token:ModifyProperties{
					description = "Invoke Ability",
					undoable = false,
					execute = function()
						local invokes = target.token.properties:get_or_add("remoteInvokes", {})
						invokes[#invokes+1] = DeepCopy(invocation)
					end,
				}

			else

				local abilityTemplate = nil
				if self.abilityType == "named" then
					local abilities = target.token.properties:GetActivatedAbilities{allLoadouts = true, bindCaster = true}
					for _,ability in ipairs(abilities) do
						if string.lower(ability.name) == string.lower(self.namedAbility) then
							abilityTemplate = ability
							break
						end
					end
				elseif self.abilityType == "custom" then
					abilityTemplate = self.customAbility
				elseif self.abilityType == "standard" then
					local t = dmhub.GetTable("standardAbilities") or {}
					abilityTemplate = t[self.standardAbility]
				end

				if abilityTemplate ~= nil then
					local abilityClone = abilityTemplate:MakeTemporaryClone()

					if self.abilityType == "standard" or self.abilityType == "custom" then

                        local allParameters = {}
                        AbilityUtils.ExtractAbilityParameters(abilityClone, allParameters)

                        local symbols = table.union(options.symbols, {
                            target = GenerateSymbols(target.token.properties),
                            invoker = GenerateSymbols(casterToken.properties),
                        })
						for k,v in pairs(self:try_get("standardAbilityParams", {})) do
                            allParameters[k] = nil
							local str = AbilityUtils.SubstituteAbilityParameters(v, casterToken.properties:LookupSymbol(symbols))
							AbilityUtils.DeepReplaceAbility(abilityClone, "<<"..k..">>", str)
						end
                        for k,_ in pairs(allParameters) do
                            --clear out any parameters we didn't explicitly set.
                            AbilityUtils.DeepReplaceAbility(abilityClone, "<<"..k..">>", "")
                        end
					end

					abilityClone.invoker = ability:try_get("invoker") or casterToken.properties

					if self.inheritRange then
						abilityClone.range = ability.range
						abilityClone.rangeUsesInvoker = true
					end

					if self:try_get("inheritKeywords", false) then
						abilityClone.keywords = ability.keywords
					end

					if self.promptText ~= "" then
						abilityClone.promptOverride = StringInterpolateGoblinScript(self.promptText, casterToken.properties:LookupSymbol{})
					end

                    local autoTarget = self:try_get("autoTarget", true)
                    if autoTarget and not abilityClone:RequiresPromptWhenCast() then
                        abilityClone.castImmediately = true
                        print("INVOKE:: Auto-target enabled for", abilityClone.name)
                    end

                    if self.targeting == "formula" then
                        options.targetingFormula = self:try_get("targetingFormula", "")
                    end

                    print("Invoke:: Execute...")
                    local invokerToken = cond(self.invokeOnCaster, casterToken, target.token)
					self.ExecuteInvoke(casterToken, abilityClone, invokerToken, self.targeting, symbols, options)
				end
			end

		end
	end
end

function ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(invokerToken, abilityClone, casterToken, targeting, symbols, options)
    options = options or {}

    print("INVOKE:: STARTING:", abilityClone.name)
    --wait until we aren't casting on the action bar to invoke this. Also resolve
    --any new casts that may have started since we got here.
    local snapshot = ActivatedAbility.GetActiveCastSnapshot()
    while gamehud.rollDialog.data.IsShown() or gamehud.actionBarPanel.data.IsCastingSpell() or ActivatedAbility.HasCoroutinesNotInSnapshot(snapshot) do
        coroutine.safe_sleep_while(function()

            return gamehud.actionBarPanel.data.IsCastingSpell() or ActivatedAbility.HasCoroutinesNotInSnapshot(snapshot)
        end)

        --give a chance for other casts to continue.
        coroutine.yield()
        coroutine.yield()
    end

        print("INVOKE:: CONTINUE FOR", abilityClone.name, "active casts = ", ActivatedAbility.CountActiveCasts(), "coroutine:", coroutine.running())



	local casting = false

	symbols.invoker = symbols.invoker or GenerateSymbols(invokerToken.properties)
    local invoker = symbols.invoker
    if type(invoker) == "function" then
        invoker = invoker("self")
    end

	abilityClone.invoker = invokerToken.properties

	local OnBeginCast = abilityClone:try_get("OnBeginCast")
	local OnFinishCast = abilityClone:try_get("OnFinishCast")

	abilityClone.OnBeginCast = function()
		if OnBeginCast then
			OnBeginCast()
		end
		casting = true
	end

    local finishedCasting = false

	abilityClone.OnFinishCast = function(ability, options)
		if OnFinishCast then
			OnFinishCast(ability, options)
		end
		casting = false
        finishedCasting = true
        print("INVOKE:: FINISHED CASTING", ability.name, "with abort =", json(options.abort), "pay =", options.pay)
        if options.pay then
            --if the ability we invoked had to be paid for, we have to pay for the invoke.
            ability:CommitToPaying(casterToken, options)
        end
	end

    local canceled = false

    while not finishedCasting do
        local castCount = 0

        local invokerCallback = {
            oncast = function()
                castCount = castCount + 1
            end,
            oncancel = function()
                canceled = true
            end,
        }

        print("AI:: PUSH:: IN INVOKE token", creature.GetTokenDescription(invokerToken), "targeting =", targeting, "ai", invokerToken.properties._tmp_aicontrol, "promptCallback =", invokerToken.properties._tmp_aipromptCallback, "for", abilityClone.name, coroutine.running())
        if targeting == "prompt" and invokerToken.properties._tmp_aicontrol > 0 and invokerToken.properties._tmp_aipromptCallback then
            print("PUSH:: INVOKING!!!!!")
            targeting = invokerToken.properties._tmp_aipromptCallback(invokerToken, casterToken, abilityClone, symbols, options)
        end

        if targeting == "prompt" then
            print("INVOKE:: PROMPT CAST FOR", abilityClone.name, coroutine.running())
            abilityClone.countsAsCast = true
            abilityClone.skippable = true
            gamehud.actionBarPanel:FireEventTree("invokeAbility", casterToken, abilityClone, symbols, invokerCallback)
        else
            abilityClone.countsAsCast = options.countsAsCast or false
            local targets
            if targeting == "self" then
                targets = { { token = casterToken } }
            elseif targeting == "inherit" then
                targets = options.targets or {}
            elseif targeting == "formula" then
                targets = {}
                local allTokens = dmhub.allTokens
                local symbols = table.shallow_copy(options.symbols)
                symbols.invoker = invokerToken.properties
                symbols.caster = casterToken.properties

                for _,token in ipairs(allTokens) do
                    symbols.target = token.properties
                    if GoblinScriptTrue(ExecuteGoblinScript(options.targetingFormula, invokerToken.properties:LookupSymbol(symbols), 0)) then
                        targets[#targets+1] = { token = token }
                    end
                end
            end

            print("INVOKE:: Requires prompt =", abilityClone:RequiresPromptWhenCast(), "for", abilityClone.name, coroutine.running())
            if abilityClone:RequiresPromptWhenCast() then
                local synth = abilityClone:SynthesizeAbilities(casterToken.properties)
                print("INVOKE:: SYNTHESIZED ABILITIES =", synth ~= nil and #synth or 0, "for", abilityClone.name, coroutine.running())
                if synth ~= nil and #synth == 1 then
                    --if exactly one synthesized ability then just auto-cast it?
                    abilityClone = synth[1]
                end
            end

            if abilityClone:RequiresPromptWhenCast() then
                print("INVOKE:: REQUIRING PROMPT")
                abilityClone.skippable = true
                gamehud.actionBarPanel:FireEventTree("invokeAbility", casterToken, abilityClone, symbols, invokerCallback, {instantCast = true, targets = targets})
            else
                print("INVOKE:: IMMEDIATE CAST")
                abilityClone:Cast(casterToken, targets, {
                    symbols = symbols,
                })
            end
        end

        print("INVOKE:: Waiting for cast to finish", abilityClone.name, coroutine.running())
        coroutine.safe_sleep_while(function()

            local isCasting = casting
            local isPreparing = gamehud.actionBarPanel.data.IsCastingSpell()

            local result = isCasting or isPreparing

            return result
        end)
        print("INVOKE:: CAST FINISHED FOR", abilityClone.name, coroutine.running())

        if castCount <= 1 then
            --this looks like a direct cancel out of casting so we just break out.
            break
        end
    end

    print("INVOKE:: FINISHED FOR", abilityClone.name, coroutine.running(), "CANCELED:", canceled)

end

ActivatedAbilityInvokeAbilityBehavior.abilityType = "custom"
ActivatedAbilityInvokeAbilityBehavior.namedAbility = ""
ActivatedAbilityInvokeAbilityBehavior.standardAbility = ""
ActivatedAbilityInvokeAbilityBehavior.targeting = "prompt"
ActivatedAbilityInvokeAbilityBehavior.inheritRange = false

function ActivatedAbilityInvokeAbilityBehavior:EditorItems(parentPanel)

	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Prompt Text:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self.promptText,
            multiline = true,
            width = 300,
            height = "auto",
            maxHeight = 140,
			change = function(element)
				self.promptText = element.text
			end,
		}
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Type:",
		},
		gui.Dropdown{
			options = {
				{ text = "Custom Ability", id = "custom" },
				{ text = "Named Ability", id = "named" },
				cond(dmhub.GetTable("standardAbilities") ~= nil, { text = "Standard Ability", id = "standard" } ),
			},
			idChosen = self.abilityType,
			change = function(element)
				self.abilityType = element.idChosen
				parentPanel:FireEventTree("refreshInvoke")
			end,
		}
	}

	result[#result+1] = gui.Check{
		text = "Invoke on Caster Token",
		value = self.invokeOnCaster,
		change = function(element)
			self.invokeOnCaster = element.value
		end,
	}
	
	result[#result+1] = gui.Check{
		classes = {cond(self.abilityType == "custom", "collapsed-anim")},
		text = "Target Player Casts",
		value = self.runOnController,
		change = function(element)
			self.runOnController = element.value
		end,
		refreshInvoke = function(element)
			element:SetClass("collapsed-anim", self.abilityType == "custom")
		end,
	}

	result[#result+1] = gui.PrettyButton{
		width = 200,
		height = 50,
		text = "Edit Ability",
		create = function(element)
			element:SetClass("collapsed", self.abilityType ~= "custom")
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
		click = function(element)
			element.root:AddChild(self.customAbility:ShowEditActivatedAbilityDialog())
		end,
	}

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		create = function(element)
			element:SetClass("collapsed", self.abilityType ~= "named")
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
		gui.Label{
			classes = {"formLabel"},
			text = "Ability Name:",
		},
		gui.Input{
			classes = {"formInput"},
			text = self.namedAbility,
			change = function(element)
				self.namedAbility = element.text
			end,
		},
	}

	local standardAbilities = {}
	for k,v in unhidden_pairs(dmhub.GetTable("standardAbilities") or {}) do
		standardAbilities[#standardAbilities+1] = { text = v.name, id = k }
	end

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		create = function(element)
			element:SetClass("collapsed", self.abilityType ~= "standard")
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
		gui.Label{
			classes = {"formLabel"},
			text = "Ability:",
		},
		gui.Dropdown{
			sort = true,
			idChosen = self.standardAbility,
			options = standardAbilities,
            hasSearch = true,
			change = function(element)
				self.standardAbility = element.idChosen
				parentPanel:FireEventTree("refreshInvoke")
			end,
		},
	}

	result[#result+1] = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		data = {
			abilityTypeCached = nil,
		},
		create = function(element)
			element:SetClass("collapsed", self.abilityType == "named")

			if self.abilityType == "named" or element.data.abilityTypeCached == self.standardAbility then
				element.children = {}
				return
			end

			element.data.abilityTypeCached = self.standardAbility

            local abilityTemplate

            if self.abilityType == "standard" then
			    local t = dmhub.GetTable("standardAbilities") or {}
			    abilityTemplate = t[self.standardAbility]
            else
                abilityTemplate = self.customAbility
            end

			if abilityTemplate == nil then
				print("Error: Could not find ability template:", self.standardAbility)
				return
			end

			local parameters = {}
			AbilityUtils.ExtractAbilityParameters(abilityTemplate, parameters)

			local children = {}

			for k,v in pairs(parameters) do
				children[#children+1] = gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						text = k,
					},
					gui.Input{
						classes = {"formInput"},
                        width = 280,
						text = self:try_get("standardAbilityParams", {})[k] or "",
						change = function(element)
							local t = self:get_or_add("standardAbilityParams", {})
							t[k] = element.text
						end,
					},
				}
			end

			element.children = children
		end,
		refreshInvoke = function(element)
			element:FireEventTree("create")
		end,
	}

    local targetingFormulaPanel

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Targeting:",
		},
		gui.Dropdown{
            classes = {"formDropdown"},
			options = {
				{ text = "Prompt Player", id = "prompt" },
				{ text = "Self", id = "self" },
                { text = "Inherit From This Ability", id = "inherit"},
                { text = "Creatures Matching Formula", id = "formula"},
			},
			idChosen = self.targeting,
			change = function(element)
				self.targeting = element.idChosen
                targetingFormulaPanel:FireEvent("refreshTargeting")
			end,
		}
	}

    targetingFormulaPanel = gui.Panel{
        classes = {"formPanel"},
        create = function(element)
            element:SetClass("collapsed", self.targeting ~= "formula")
        end,
        refreshTargeting = function(element)
            element:FireEventTree("create")
        end,
        gui.Label{
            classes = {"formLabel"},
            text = "Targeting Formula:",
        },
        gui.GoblinScriptInput{
            classes = {"formInput"},
            value = self:try_get("targetingFormula", ""),
            change = function(element)
                self.targetingFormula = element.value
            end,
            documentation = {
                help = "This GoblinScript is used to determine which targets may be targeted by this ability.",
                output = "boolean",
                subject = creature.helpSymbols,
				subjectDescription = "The creature invoking the ability",
                examples = {},
                symbols = {
                    target = {name = "Target", type = "creature", desc = "The candidate target of the ability"},
                    caster = {name = "Caster", type = "creature", desc = "The creature casting the invoked ability."},
                    invoker = {name = "Invoker", type = "creature", desc = "The creature invoking the ability. The same as Self."},
                }
            }
        },
    }

    result[#result+1] = targetingFormulaPanel

    result[#result+1] = gui.Check{
        text = "Auto-select targets when possible",
        value = self:try_get("autoTarget", true),
        change = function(element)
            self.autoTarget = element.value
        end,
    }

	result[#result+1] = gui.Check{
		text = "Inherit Range",
		value = self.inheritRange,
		change = function(element)
			self.inheritRange = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Inherit Keywords",
		value = self:try_get("inheritKeywords", false),
		change = function(element)
			self.inheritKeywords = element.value
		end,
	}

	return result

end

AbilityInvocation.timestamp = 0
AbilityInvocation.abilityType = "named"
AbilityInvocation.abilityid = "none"
AbilityInvocation.targeting = "prompt"
AbilityInvocation.targetingFormula = ""
AbilityInvocation.invokerid = "none"
AbilityInvocation.casterid = "none"

--must be executed from within a co-routine.
function AbilityInvocation:Invoke()
	local invokerToken = dmhub.GetTokenById(self.invokerid)
	local casterToken = dmhub.GetTokenById(self.casterid)

	if invokerToken == nil or casterToken == nil then
		return false
	end

    if self:has_key("subjectid") then
        local subjectToken = dmhub.GetTokenById(self.subjectid)
        if subjectToken ~= nil then
            self.symbols.subject = GenerateSymbols(subjectToken.properties)
        end
    end

	local abilityTemplate = nil
	if self.abilityType == "named" then
		local abilities = casterToken.properties:GetActivatedAbilities{allLoadouts = true, bindCaster = true}
		for _,ability in ipairs(abilities) do
			if string.lower(ability.name) == string.lower(self.namedAbility) then
				abilityTemplate = ability
				break
			end
		end
	elseif self.abilityType == "standard" then
        abilityTemplate = MCDMUtils.GetStandardAbility(self.standardAbility)
	end

	if abilityTemplate == nil then
		return false
	end

	local abilityClone = abilityTemplate:MakeTemporaryClone()
	if self.abilityType == "standard" or self.abilityType == "custom" then
        local lookupSymbols = table.shallow_copy(self.symbols)
        if self:has_key("targetid") then
            local targetToken = dmhub.GetTokenById(self.targetid)
            if targetToken ~= nil then
                lookupSymbols.target = GenerateSymbols(targetToken.properties)
            end
        end

		local allParameters = {}
		AbilityUtils.ExtractAbilityParameters(abilityClone, allParameters)

        lookupSymbols = invokerToken.properties:LookupSymbol(lookupSymbols)
		for k,v in pairs(self:try_get("standardAbilityParams", {})) do
            allParameters[k] = nil
			local str = AbilityUtils.SubstituteAbilityParameters(v, lookupSymbols)
			AbilityUtils.DeepReplaceAbility(abilityClone, "<<"..k..">>", str)
		end

        for k,_ in pairs(allParameters) do
            --clear out any parameters we didn't explicitly set.
            AbilityUtils.DeepReplaceAbility(abilityClone, "<<"..k..">>", "")
        end
	end

	for k,v in pairs(self:try_get("abilityAttr", {})) do
		abilityClone[k] = v
	end

	local options = {
        targetingFormula = self.targetingFormula,
    }
	ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(invokerToken, abilityClone, casterToken, self.targeting, self.symbols, options)
	return true
end