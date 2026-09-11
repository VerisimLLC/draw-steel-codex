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
			--Set target as creature properties
			symbols.target = targets[1].token.properties
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
        local isRolledDamage = not dmhub.IsRollDeterministic(rollStr)
        local damageDice = GameSystem.GetDamageDiceInRoll(rollStr)
		local rollid = nil
        print("ROLL:: SHOW", rollStr)

		--Acquire the embedded roll dialog, queuing behind any other ability
		--roll in progress. The helper installs the cast-aware HideAbility
		--OnFinishCast handler. See CharacterPanel.AcquireAbilityRollDialog.
		local dialog = CharacterPanel.AcquireAbilityRollDialog(casterToken, ability, options.symbols, {lock = true, renderAsAbility = true}, options)
		if dialog == nil or (not dialog.valid) or dialog.data == nil then
			return false
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
			--Keep the dialog up after the dice settle so the roll ends with an
			--Accept Result / Re-roll step, consistent with power rolls.
			showDialogDuringRoll = true,
			amendable = true,
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

						--Patron damage handling (Acolyte class). If the behavior's
						--damageType is "patron" (or the roll categorized damage as
						--"patron"), substitute the caster's patron-element damage
						--type and tag this damage event with patrondamage=true.
						--Falls back to "untyped" if the caster has no patron set.
						local catPatronDamage = false
						local effectiveCatName = catName
						if string.lower(tostring(catName)) == "patron" then
							catPatronDamage = true
							local resolved = nil
							if casterToken.properties.PatronDamageType ~= nil then
								resolved = casterToken.properties:PatronDamageType()
							end
							if type(resolved) == "string" and resolved ~= "" then
								effectiveCatName = string.lower(resolved)
							else
								effectiveCatName = "untyped"
								local cast = options.symbols and options.symbols.cast
								if cast == nil or not cast:try_get("_tmp_patronDamageWarned", false) then
									if cast ~= nil then cast._tmp_patronDamageWarned = true end
									print(string.format(
										"PATRON DAMAGE:: caster has no patron_damage_type set; emitting untyped for AbilityDamage on %s.",
										ability.name
									))
								end
							end
						end

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
                                    catName = effectiveCatName,
                                    patrondamage = catPatronDamage,
                                    desc = string.format("%s's %s%s", casterName, ability.name, info.saveText),
                                }

                                if logMessage ~= nil then
                                    logMessage.amount = damageAmount
                                    if effectiveCatName == "untyped" then
                                        logMessage.damageType = nil
                                    else
                                        logMessage.damageType = effectiveCatName
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
								local res = targetCreature:InflictDamageInstance(entry.amount, entry.catName, ability.keywords, entry.desc, {attacker = casterToken.properties, ability = ability, hasability = true, pusher = options.symbols.pusher, cannotBeReduced = self:try_get("cannotBeReduced"), doesNotTrigger = self:try_get("doesNotTrigger"), hasrolleddamage = isRolledDamage, damagedice = damageDice, cast = options.symbols.cast, patrondamage = entry.patrondamage})
								options.symbols.cast:CountDamage(target.token, res.damageDealt, entry.amount, isRolledDamage, entry.patrondamage)
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

--- @class ActivatedAbilityDamageChatMessage: GameType
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
        classes = {"action-log-detail", "sizeXs", "fg"},
        text = self.chatMessage,
    }

    local damageLabel = gui.Label{
        classes = {"action-log-subtext", "sizeXxs", "fgMuted"},
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


--- @class ActivatedAbilityLeechDamageBehavior:ActivatedAbilityBehavior
--- Deals automatic (no power roll, no save) damage to its targets and then
--- restores that same amount of Stamina to the aura's caster. Built for effects
--- like the Shambling Mound's Leeching Wilds: "any enemy who starts their turn
--- in the area takes N damage, and the shambling mound regains an equal amount
--- of Stamina." The Stamina regained equals the damage actually taken after the
--- target's damage immunities and weaknesses are applied, since it is read from
--- the value InflictDamageInstance reports back.
ActivatedAbilityLeechDamageBehavior = RegisterGameType("ActivatedAbilityLeechDamageBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityLeechDamageBehavior.summary = 'Leech Damage'
ActivatedAbilityLeechDamageBehavior.roll = "4"
ActivatedAbilityLeechDamageBehavior.damageType = "acid"

ActivatedAbility.RegisterType
{
	id = 'leech_damage',
	text = 'Leech Damage',
	createBehavior = function()
		return ActivatedAbilityLeechDamageBehavior.new{
			roll = "4",
			damageType = "acid",
		}
	end
}

function ActivatedAbilityLeechDamageBehavior:SummarizeBehavior(ability, creatureLookup)
	return string.format("%s %s Damage; aura caster regains that Stamina",
		dmhub.NormalizeRoll(dmhub.EvalGoblinScript(self.roll, creatureLookup, string.format("Leech damage for %s", ability.name))),
		self.damageType)
end

--Resolve the creature that should regain Stamina: the aura's caster (the
--creature the aura belongs to). On aura-modifier triggers the aura installs a
--"caster" symbol pointing at its owner and an "aura" symbol holding the
--AuraInstance (which carries its casterid). Prefer the symbol, fall back to the
--aura's casterid, and return nil outside of an aura context so the behavior
--simply deals damage with no heal.
function ActivatedAbilityLeechDamageBehavior:ResolveLeechToken(options)
	local symbols = options.symbols or {}

	local casterSym = symbols.caster
	if type(casterSym) == "function" then
		casterSym = casterSym("self")
	end
	if casterSym ~= nil then
		local tok = dmhub.LookupToken(casterSym)
		if tok ~= nil and tok.valid then
			return tok
		end
	end

	local aura = symbols.aura
	if aura ~= nil then
		local casterid = nil
		pcall(function() casterid = aura.casterid end)
		if casterid ~= nil then
			local tok = dmhub.GetTokenById(casterid)
			if tok ~= nil and tok.valid then
				return tok
			end
		end
	end

	return nil
end

function ActivatedAbilityLeechDamageBehavior:Cast(ability, casterToken, targets, options)
	if #targets == 0 then
		return
	end

	ability:CommitToPaying(casterToken, options)

	local leechToken = self:ResolveLeechToken(options)

	local damageType = self.damageType
	local sourceDescription = ability.name

	local totalDealt = 0

	for _,target in ipairs(targets) do
		if target.token ~= nil and target.token.valid and target.token.properties ~= nil then
			local targetCreature = target.token.properties
			local amount = dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(options.symbols or {}), string.format("Leech damage for %s", ability.name))
			amount = tonumber(amount) or 0
			if amount > 0 then
				target.token:ModifyProperties{
					description = sourceDescription,
					execute = function()
						--No attacker is passed: this is automatic aura damage, mirroring
						--creature:AuraDamage. damageDealt is the amount that landed after
						--the target's immunities and weaknesses.
						local res = targetCreature:InflictDamageInstance(amount, damageType, {}, sourceDescription, { damagesound = "Attack.Enviro" })
						if type(res) == "table" and type(res.damageDealt) == "number" then
							totalDealt = totalDealt + res.damageDealt
						end
					end,
				}
			end
		end
	end

	if leechToken ~= nil and totalDealt > 0 then
		local canHeal = (leechToken.properties:CalculateNamedCustomAttribute("Cannot Regain Stamina") == 0)
		leechToken:ModifyProperties{
			description = string.format("%s: Regain Stamina", ability.name),
			execute = function()
				leechToken.properties:Heal(totalDealt, sourceDescription)
			end,
		}
		if canHeal then
			leechToken.properties:FloatLabel(string.format("+%d Stamina", totalDealt), "#66ff66")
		end
	end
end

function ActivatedAbilityLeechDamageBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:RollEditor(parentPanel, result)
	self:DamageTypeEditor(parentPanel, result)
	return result
end

--- @class ActivatedAbilityLeechTempStaminaBehavior:ActivatedAbilityBehavior
--- Deals automatic damage to its targets and grants the caster a fixed amount
--- of temporary Stamina for each target who actually took damage. Built for
--- effects like the Shambling Mound's Leech maneuver: "Each creature engulfed
--- by the shambling mound takes 5 poison damage. The shambling mound gains 5
--- temporary Stamina for each creature who takes damage this way."
--- The damage defaults to cannotBeReduced + bypassTempStamina because such
--- effects usually originate "inside" a temporary-Stamina shield (the sack) and
--- must hit the creature's real Stamina rather than the shield.
ActivatedAbilityLeechTempStaminaBehavior = RegisterGameType("ActivatedAbilityLeechTempStaminaBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityLeechTempStaminaBehavior.summary = 'Leech Temporary Stamina'
ActivatedAbilityLeechTempStaminaBehavior.roll = "5"
ActivatedAbilityLeechTempStaminaBehavior.damageType = "poison"
ActivatedAbilityLeechTempStaminaBehavior.tempPerTarget = "5"
ActivatedAbilityLeechTempStaminaBehavior.cannotBeReduced = true
ActivatedAbilityLeechTempStaminaBehavior.bypassTempStamina = true

ActivatedAbility.RegisterType
{
	id = 'leech_temp_stamina',
	text = 'Leech Temporary Stamina',
	createBehavior = function()
		return ActivatedAbilityLeechTempStaminaBehavior.new{
			roll = "5",
			damageType = "poison",
			tempPerTarget = "5",
		}
	end
}

function ActivatedAbilityLeechTempStaminaBehavior:SummarizeBehavior(ability, creatureLookup)
	return string.format("%s %s Damage; caster gains %s temporary Stamina per damaged target",
		dmhub.NormalizeRoll(dmhub.EvalGoblinScript(self.roll, creatureLookup, string.format("Leech damage for %s", ability.name))),
		self.damageType,
		tostring(self.tempPerTarget))
end

function ActivatedAbilityLeechTempStaminaBehavior:Cast(ability, casterToken, targets, options)
	if #targets == 0 then
		return
	end

	ability:CommitToPaying(casterToken, options)

	local damageType = self.damageType
	local sourceDescription = ability.name
	local cannotBeReduced = self:try_get("cannotBeReduced", true)
	local bypassTempStamina = self:try_get("bypassTempStamina", true)

	local numDamaged = 0
	--charids of the creatures actually damaged, for the action-log card below.
	local damagedTokenIds = {}
	local lastAmount = 0

	for _,target in ipairs(targets) do
		if target.token ~= nil and target.token.valid and target.token.properties ~= nil then
			local targetCreature = target.token.properties
			local amount = dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(options.symbols or {}), string.format("Leech damage for %s", ability.name))
			amount = tonumber(amount) or 0
			if amount > 0 then
				lastAmount = amount
				ability.RecordTokenMessage(target.token, options, string.format("%d %s damage", amount, damageType))
				target.token:ModifyProperties{
					description = sourceDescription,
					execute = function()
						local res = targetCreature:InflictDamageInstance(amount, damageType, {}, sourceDescription, {
							attacker = casterToken.properties,
							ability = ability,
							hasability = true,
							cannotBeReduced = cannotBeReduced,
							bypassTempStamina = bypassTempStamina,
						})
						if type(res) == "table" and type(res.damageDealt) == "number" and res.damageDealt > 0 then
							numDamaged = numDamaged + 1
						end
					end,
				}
				damagedTokenIds[#damagedTokenIds+1] = target.token.charid
			end
		end
	end

	local grantedTemp = 0
	if numDamaged > 0 then
		local perTarget = tonumber(dmhub.EvalGoblinScript(self.tempPerTarget, casterToken.properties:LookupSymbol(options.symbols or {}), string.format("Temp stamina for %s", ability.name))) or 0
		--Draw Steel temporary Stamina does not stack: the higher of the current
		--and new values wins. SetTemporaryHitpoints overwrites, so clamp here.
		local grant = perTarget * numDamaged
		if grant > 0 and grant > casterToken.properties:TemporaryHitpoints() then
			grantedTemp = grant
			casterToken:ModifyProperties{
				description = string.format("%s: Gain Temporary Stamina", ability.name),
				execute = function()
					casterToken.properties:SetTemporaryHitpoints(grant, sourceDescription)
					casterToken.properties:DispatchEvent("gaintempstamina", {})
				end,
			}
			casterToken.properties:FloatLabel(string.format("+%d Temp Stamina", grant), "#66ff66")
		end
	end

	--Action-log card: the base RecordTokenMessage notes are easy to miss, so post
	--an explicit damage card (reusing the standard damage card) showing the poison
	--dealt to each target, with the Stamina the caster leeched folded into the
	--caption. Only when something actually happened.
	if #damagedTokenIds > 0 then
		local caption = ability.name
		if grantedTemp > 0 then
			caption = string.format("%s (+%d temporary Stamina)", ability.name, grantedTemp)
		end
		chat.SendCustom(ActivatedAbilityDamageChatMessage.new{
			amount = lastAmount,
			damageType = damageType,
			chatMessage = caption,
			casterid = casterToken.charid,
			targetids = damagedTokenIds,
		})
	end
end

function ActivatedAbilityLeechTempStaminaBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:RollEditor(parentPanel, result)
	self:DamageTypeEditor(parentPanel, result)
	return result
end
