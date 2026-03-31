local mod = dmhub.GetModLoading()

ActivatedAbility.RegisterType
{
	id = 'damage',
	text = 'Damage',
	canHaveDC = true,
	createBehavior = function()
		return ActivatedAbilityDamageBehavior.new{
			roll = "1d6",
		}
	end
}

ActivatedAbilityDamageBehavior.summary = 'Damage'

function ActivatedAbilityDamageBehavior:SummarizeBehavior(ability, creatureLookup)
	return string.format("%s Damage", dmhub.NormalizeRoll(dmhub.EvalGoblinScript(self.roll, creatureLookup, string.format("Damage roll for %s", ability.name))))
end


function ActivatedAbilityDamageBehavior:AccumulateSavingThrowConsequence(ability, casterToken, targets, consequences, options)
	local tokenids = GetConsequenceTokenIds(self, ability, casterToken, targets)
	if tokenids == false then
		return
	end

	consequences.damage = consequences.damage or {}
	consequences.damage[#consequences.damage+1] = {
		amount = dmhub.NormalizeRoll(dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(options.symbols or {}), string.format("Damage roll for %s", ability.name))),
		damageType = self.damageType,
		success = self.dcsuccess,
		tokens = tokenids,
	}
end


function ActivatedAbilityDamageBehavior:Cast(ability, casterToken, targets, options)
	if #targets == 0 then
		return
	end

	local casterName = creature.GetTokenDescription(casterToken)

	local dcaction = nil
	local tokenids = ActivatedAbility.GetTokenIds(targets)

	local targetGroups = {}

    local logMessage = nil
    if string.trim(self.chatMessage) ~= "" then
        logMessage = ActivatedAbilityDamageChatMessage.new{
            amount = 0,
            damageType = self.damageType,
            chatMessage = self.chatMessage,
            casterid = casterToken.charid,
            targetids = tokenids,
        }
    end

	if self:try_get('separateRolls') then
		local prevGroup = nil
		local prevTargetToken = nil
		for i,target in ipairs(targets) do
            options.symbols.target = target.token.properties
	        local rollStr = self:DescribeRoll(casterToken.properties, ability, options)
            options.symbols.target = nil
			if prevTargetToken ~= nil and prevTargetToken.charid == target.token.charid then

				--merge multiples aimed at the same token together. This is e.g. when targeting multiple magic missiles at the same target.
				prevGroup.roll = string.format("%s + %s", prevGroup.roll, rollStr)
				prevGroup.count = prevGroup.count + 1
			else
				prevTargetToken = target.token
				prevGroup = { targets = {target}, roll = rollStr, count = 1 }
				targetGroups[#targetGroups+1] = prevGroup
			end
		end
	else
	    local rollStr = self:DescribeRoll(casterToken.properties, ability, options)
		targetGroups = { { targets = targets, roll = rollStr, count = 1 } }
	end

	for i,targetGroup in ipairs(targetGroups) do
		local targets = targetGroup.targets
		local rollCanceled = false
		local rollComplete = false

		local symbols = DeepCopy(options.symbols or {})

		if #targets == 1 and targets[1].token ~= nil and targets[1].token.properties ~= nil then
			symbols.target = targets[1].token.properties:LookupSymbol()
		end

		--target hints for the dialog to set up. These show things like expected damage.
		local targetHints = {}

		for i,target in ipairs(targets) do
			local hit = true
			local half = false
			if dcaction ~= nil then
				local outcome = dcaction.info:GetTokenOutcome(target.token.charid)
				self:RecordOutcomeToApplyToTable(target.token, options, outcome)
				if outcome ~= nil and outcome.success then
					hit = false
				end

				if hit then
					self:RecordHitTarget(target.token, options, {failedSave = true})
				elseif self.dcsuccess == "half" then
					half = true
				end
			end

			if hit or half then
				targetHints[#targetHints+1] = {
					charid = target.token.charid,
					half = half,
				}
			end
		end

		local hasProjectile = false
		if ability.projectileObject ~= "none" then
			for i,target in ipairs(targets) do

				for j=1,targetGroup.count do
					hasProjectile = true
					Projectile.FireObject{
						ability = ability,
						casterToken = casterToken,
						targetToken = target.token,
						objectid = ability.projectileObject,
					}
				end
			end
		end


		local modifiers = casterToken.properties:GetDamageRollModifiers(nil, nil, {
			ability = ability,
			roll = targetGroup.roll,
			damageTypes = StringSet.new{ strings = { self.damageType } },
			symbols = {
				ability = GenerateSymbols(ability),
				cast = GenerateSymbols(options.symbols.cast),
			},
		})

        local title = string.format("%s: Roll for Damage", ability.name)
        local description = string.format("%s Damage Roll", ability.name)
        if self.titleText ~= "" then
            title = self.titleText
            description = ""
        end

        local rollStr = dmhub.EvalGoblinScript(targetGroup.roll, casterToken.properties:LookupSymbol(symbols), string.format("Damage roll for %s", ability.name))
		local rollid = nil
        print("ROLL:: SHOW", rollStr)

		local dialog
		local existingEmbedded = CharacterPanel.FindEmbeddedRollDialog()
		if existingEmbedded ~= nil then
			dialog = existingEmbedded
		else
			local displayed = CharacterPanel.DisplayAbility(casterToken, ability, options.symbols, {lock = true})
			if displayed then
				options.OnFinishCastHandlers = options.OnFinishCastHandlers or {}
				options.OnFinishCastHandlers[#options.OnFinishCastHandlers+1] = function()
					CharacterPanel.HideAbility(ability)
				end
			end

			local embeddedDialog = CharacterPanel.EmbedDialogInAbility()
			if embeddedDialog ~= nil then
				dialog = embeddedDialog
				for j=1,4 do
					coroutine.yield(0.01)
				end
			else
				dialog = GameHud.instance.rollDialog
			end
		end

		rollid = dialog.data.ShowDialog{
			title = title,
			description = description,
			roll = rollStr,
			modifiers = modifiers,
			creature = casterToken.properties,
			targetHints = targetHints,
			delayInstant = cond(hasProjectile, 2, 0),
			skipDeterministic = true,
			type = 'damage',
			cancelRoll = function()
				rollCanceled = true
			end,
			completeRoll = function(rollInfo)
                rollComplete = true

				--if we target the same creature multiple times, coalesce into one.
				local targetEntries = {}
				for i,target in ipairs(targets) do
					local existingEntry = nil
					for _,entry in ipairs(targetEntries) do
						if entry.charid == target.token.charid then
							existingEntry = entry
							break
						end
					end

					if existingEntry then
						existingEntry.count = existingEntry.count+1
					else
						targetEntries[#targetEntries+1] = {
							charid = target.token.charid,
							token = target.token,
							count = 1,
						}
					end
				end
				



				for i,target in ipairs(targetEntries) do
					local targetCreature = target.token.properties


					if dcaction ~= nil then
						local success = dcaction.info:GetTokenResult(target.token.charid)
						if success ~= nil then

							targetCreature:TriggerEvent("saveagainstdamage", {
								attribute = creature.savingThrowInfo[self.dc].description,
								outcome = cond(success, "success", "failure"),
								attacker = GenerateSymbols(casterToken.properties),
							})
						end
					end
					
					--accumulate damageEntries into here so we can inflict them in one transaction at the end.
					local damageEntries = {}

					for catName,value in pairs(rollInfo.categories) do

						for j=1,target.count do

							local saveText = ''

							local damageAmount = value
							local damageMultiplier = 1

							local info = {
								damageMultiplier = 1,
								saveText = "",
							}

							if dcaction ~= nil then
								local dcinfo = dcaction.info.tokens[target.token.charid]
								local outcome = dcaction.info:GetTokenOutcome(target.token.charid)
								if outcome ~= nil then

									--call the game system to see how it resolves saving throw damage calculations like this.
									local calc = GameSystem.SavingThrowDamageCalculation(outcome, self.dcsuccess)
									for k,v in pairs(calc) do
										info[k] = v
									end

									--give "Damage after save" modifiers a chance to modify the damage multiplier.
									local symbols = {
										damagemultiplier = info.damageMultiplier,
										damageonsuccess = self.dcsuccess,
										damageonfailure = 1,
										success = outcome.success,
										roll = dcinfo.result,
										dc = dcaction.info.checks[1].dc,
										attrid = self.dc,
										damagetype = catName,
										damage = damageAmount,
									}

									local mods = targetCreature:GetActiveModifiers()
									for i,mod in ipairs(mods) do
										mod.mod:ModifyDamageAfterSave(mod, symbols, info)
									end

								end
							end

							if info.saveText ~= "" then
								info.saveText = "--" .. info.saveText
							end
							
							damageAmount = math.floor(damageAmount * info.damageMultiplier)

                            if damageAmount > 0 then
                                damageEntries[#damageEntries+1] = {
                                    amount = damageAmount,
                                    catName = catName,
                                    desc = string.format("%s's %s%s", casterName, ability.name, info.saveText),
                                }

                                if logMessage ~= nil then
                                    logMessage.amount = damageAmount
                                    if catName == "untyped" then
                                        logMessage.damageType = nil
                                    else
                                        logMessage.damageType = catName
                                    end
                                end
                            end

							rollComplete = true
						end
					end

					if dcaction ~= nil then
						targetCreature:ClearMomentaryOngoingEffects()
					end

					for _,entry in ipairs(damageEntries) do
                        ability.RecordTokenMessage(target.token, options, string.format("%d %s damage", entry.amount, entry.catName or "untyped"))
                    end

					target.token:ModifyProperties{
						description = "Damaged",
						execute = function()
							for _,entry in ipairs(damageEntries) do
								local res = targetCreature:InflictDamageInstance(entry.amount, entry.catName, ability.keywords, entry.desc, {attacker = casterToken.properties, ability = ability, hasability = true, pusher = options.symbols.pusher, cannotBeReduced = self:try_get("cannotBeReduced"), doesNotTrigger = self:try_get("doesNotTrigger")})
								options.symbols.cast:CountDamage(target.token, res.damageDealt, entry.amount)
                                print("DAMAGE:: COUNT", res.damageDealt)
							end

						end,
					}
				end
			end
		}

		while not rollComplete do
			if rollCanceled then
				return
			end
			coroutine.yield(0.1)
		end

        ability:CommitToPaying(casterToken, options)

		if options ~= nil and options.complete ~= nil then

			--we did at least something for this so consider it complete
			options.complete()
			options.complete = nil
		end
	end

    if logMessage ~= nil and logMessage.amount > 0 then
        --send the chat message to the chat.
        chat.SendCustom(logMessage)
    end
end


--NOTE: casterCreature may be nil (currently not used at all)
function ActivatedAbilityDamageBehavior:DescribeRoll(casterCreature, ability, options)

	--don't break down goblin script for damage, unless it's a table.
	local roll = self.roll
	if type(roll) == "table" then
		roll = dmhub.EvalGoblinScript(roll, casterCreature:LookupSymbol(options.symbols), string.format("Damage roll for table for %s", ability.name))
	end

	return string.format("%s [%s%s]", roll, cond(self:try_get("magicalDamage", ability.isSpell), "magical ", ""), self.damageType)
end

function ActivatedAbilityDamageBehavior:AccumulateDamageTypes(ability, result)
	result[#result+1] = self.damageType
end

--- @class ActivatedAbilityDamageChatMessage
--- @field ability ActivatedAbility
ActivatedAbilityDamageChatMessage = RegisterGameType("ActivatedAbilityDamageChatMessage")
ActivatedAbilityDamageChatMessage.amount = 0
ActivatedAbilityDamageChatMessage.damageType = ""
ActivatedAbilityDamageChatMessage.chatMessage = ""
ActivatedAbilityDamageChatMessage.casterid = ""
ActivatedAbilityDamageChatMessage.targetids = {}

function ActivatedAbilityDamageChatMessage:Render(message)
    local token = self:GetCasterToken()

    if token == nil or (not token.valid) then
        return gui.Panel{
            width = 0, height = 0,
        }
    end

    local targetTokenPanels = {}
    for _,tok in ipairs(self:GetTargetTokens()) do
        if tok.valid then
            targetTokenPanels[#targetTokenPanels+1] = gui.CreateTokenImage(tok, {
                width = 28,
                height = 28,
                valign = "center",
                halign = "left",
                interactable = true,
                hover = gui.Tooltip(tok.name),
            })
        end
    end

    local damageTypeText = self.damageType
    if damageTypeText ~= "" then
        damageTypeText = " " .. damageTypeText
    end

    local messageText = string.format("%d%s damage", self.amount, damageTypeText)

    local detailLabel = gui.Label{
        classes = {"action-log-detail"},
        text = self.chatMessage,
    }

    local damageLabel = gui.Label{
        classes = {"action-log-subtext"},
        text = messageText,
    }

    local targetsPanel = nil
    if #targetTokenPanels > 0 then
        targetsPanel = gui.Panel{
            floating = true,
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "top",
            flow = "horizontal",
            wrap = true,
            maxWidth = 90,
            rmargin = 6,
            tmargin = 2,
            children = targetTokenPanels,
        }
    end

    local card = CreateActionLogCard{
        token = token,
        content = {detailLabel, damageLabel, targetsPanel},
    }

    local resultPanel = gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        refreshMessage = function(element, message)
        end,
        card,
    }

    return resultPanel
end

function ActivatedAbilityDamageChatMessage:GetCasterToken()
    return dmhub.GetCharacterById(self.casterid)
end

--- @return CharacterToken[]
function ActivatedAbilityDamageChatMessage:GetTargetTokens()
    local result = {}
    for i,tokenid in ipairs(self.targetids) do
        result[#result+1] = dmhub.GetCharacterById(tokenid)
    end
    return result
end
