local mod = dmhub.GetModLoading()

ActivatedAbilityCast.highestnumberonattackdice = 0

GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbilityCast,
    name = "highestnumberonattackdice",
    type = "number",
    desc = "The highest number rolled on the d6 attack dice.",
    seealso = {},
    examples = {},
    calculate = function(c)
        return c.highestnumberonattackdice
    end,
}

--options can include these functions:
--  completeAttackRoll: when the to-hit roll completes rolling this is called
--  completeAttack: when the entire attack is completed (including damage, or including a miss with no damage roll) this is called. bool argument which is true iff the attack hit. Options argument: {criticalHit = true if a critical hit}
--  cancelAttack: When the user cancels out either on the attack roll or the damage roll.
function creature.MCDMRollAttack(self, attack, targets, options)

    options.symbols = options.symbols or {}
    options.symbols.cast = options.symbols.cast or {}

	local optionsCopy = DeepCopy(options or {})

	--"cast" is the one symbol we want to not deep copy.
	if optionsCopy.symbols ~= nil and optionsCopy.symbols.cast ~= nil then
		optionsCopy.symbols.cast = options.symbols.cast
	end

	options = optionsCopy

	local beginAttack = options.beginAttack
	local completeAttack = options.completeAttack
	local cancelAttack = options.cancelAttack
	local keywords = options.keywords

	options.beginAttack = nil
	options.completeAttack = nil
	options.cancelAttack = nil
	options.keywords = nil

	local completefn
	
	local selfToken = dmhub.LookupToken(self)
	local selfName = creature.GetTokenDescription(selfToken)
	local attackName = attack.name

	if targets ~= nil and #targets > 0 then

		local targetCreature = targets[1].properties

		options.roll = {}

		local modifiers = {}
		local bestCount = 99999
		local bestIndex = 0

		--try to find a token with the least number of modifiers to use as the 'base', and the rest
		--will have boons/banes as a delta from them.

		for i,target in ipairs(targets) do
			--standard modifier descriptions with modifier field and hint.
			local candidateModifiers = self:GetDamageRollModifiers(attack, target, options)
			local count = 0
			for j,modifier in ipairs(candidateModifiers) do
				if modifier.hint ~= nil and modifier.hint.result then
					count = count+1
				end
			end

			if count < bestCount then
				modifiers = candidateModifiers
				bestCount = count
				bestIndex = i
			end
		end

		--calculate the target information for each target, including calculating out the roll so we can
		--compare number of boons from one target to another.
		local multitokens = {}
		for i,target in ipairs(targets) do
			local candidateModifiers = self:GetDamageRollModifiers(attack, target, options)

			for _,mod in ipairs(candidateModifiers) do
				if mod.modifier ~= nil then
					mod.modifier:InstallSymbolsFromContext{
						ability = GenerateSymbols(options.ability),
						attack = GenerateSymbols(attack),
					}
				end
			end

			--calculate the roll text for this target.
			local roll = attack:DescribeDamageRoll()

			for _,mod in ipairs(candidateModifiers) do
				if mod.modifier ~= nil then
					if mod.modFromTarget then
						roll = mod.modifier:ModifyDamageAgainstUs(mod.context, target.properties, self, roll)
					else
						roll = mod.modifier:ModifyDamageRoll(mod, self, target.properties, roll)
					end
					mod.modifier:InstallSymbolsFromContext{
						ability = GenerateSymbols(options.ability),
						attack = GenerateSymbols(attack),
					}
				end
			end

			local rollInfo = dmhub.ParseRoll(roll)
			local boons = 0

			for catid,category in pairs(rollInfo.categories) do
				for _,group in ipairs(category.groups) do
					if group.numFaces == 4 then
						if group.subtraction then
							boons = boons - group.numDice
						else
							boons = boons + group.numDice
						end
					end
				end
			end

			local boonsText = nil

			for _,mod in ipairs(candidateModifiers) do
				if mod.modifier ~= nil then
					local text = mod.modifier:GetSummaryText()
					local found = false
					for _,m in ipairs(modifiers) do
						local t = m.modifier:GetSummaryText()
						if text == t and m.hint.result == mod.hint.result then
							found = true
							break
						end
					end

					if found == false then
						if boonsText == nil then
							boonsText = ""
						else
							boonsText = boonsText .. "\n\n"
						end

						boonsText = boonsText .. mod.modifier.name
					end
				end
			end

			multitokens[#multitokens+1] = {
				token = target,
				boons = boons,
				text = boonsText,
			}
		end

		--now normalize it so the base token has 0 boons.
		local baseBoons = multitokens[bestIndex].boons
		for _,token in ipairs(multitokens) do
			token.boons = token.boons - baseBoons
		end

		for _,mod in ipairs(modifiers) do
			if mod.modifier ~= nil then
				mod.modifier:InstallSymbolsFromContext{
					ability = GenerateSymbols(options.ability),
					attack = GenerateSymbols(attack),
				}
			end
		end

		--damage checkboxes can be passed in from the ability. Note that these
		--are not standard modifiers with a "modifier" field. ShowDialog knows what to do with them.
		for _,mod in ipairs(options.damageCheckboxes or {}) do
			modifiers[#modifiers+1] = mod
		end

		local targetHints = {}

		for _,target in ipairs(targets) do
			targetHints[#targetHints+1] = {
				charid = target.id,
				half = false,
			}
		end

		local rollid
		rollid = GameHud.instance.rollDialog.data.ShowDialog{
			title = 'Attack Roll',
			roll = attack:DescribeDamageRoll(),
			description = targets[1]:DescribeRollAgainst(string.format("%s Attack Roll", attackName)),
			creature = self,
			targetCreature = targetCreature,
            skipDeterministic = true,

			multitargets = multitokens,

			--hint the target so damage indicators are shown over them.
			targetHints = targetHints,

			modifiers = modifiers,
			type = 'damage',
			critical = false,
			completeRoll = function(rollInfo)

                for _,roll in ipairs(rollInfo.rolls) do
                    if roll.numFaces == 6 then
                        options.symbols.cast.highestnumberonattackdice = math.max(options.symbols.cast.highestnumberonattackdice or 0, roll.result)
                    end
                end

				local attackInfo = {
					criticalHit = false,
					damageRaw = 0,
					damageDealt = 0,
				}

				for i,target in ipairs(targets) do
					local targetCreature = target.properties

					target:BeginChanges()
					targetCreature:TriggerEvent("hit", {
						attacker = GenerateSymbols(self),
						attack = GenerateSymbols(attack),
					})
					targetCreature:RecordDamageEntry{
						id = rollid or dmhub.GenerateGuid(),
						damage = 0,
					}

					local extravalue = 0
					local extraboons = multitokens[i].boons
					for _,roll in ipairs(rollInfo.rolls) do
						if (extraboons > 0 and roll.category == "extraboons") or (extraboons < 0 and roll.category == "extrabanes") then
							extravalue = extravalue + roll.result
							if extraboons > 0 then
								extraboons = extraboons - 1
							else
								extraboons = extraboons + 1
							end
						end
					end

					local damageInstances = {}

					for catName,value in pairs(rollInfo.categories) do
						if catName ~= "extraboons" and catName ~= "extrabanes" then
							damageInstances[#damageInstances+1] = {
								amount = value + extravalue,
								category = catName,
							}

							extravalue = 0
						end
					end

					for _,damageInstance in ipairs(damageInstances) do
						local amount = damageInstance.amount
						local category = damageInstance.category
						local result = targetCreature:InflictDamageInstance(amount, category, keywords, string.format("%s's %s", selfName, attackName), { criticalhit = false, attacker = self })
						attackInfo.damageRaw = attackInfo.damageRaw + amount
						attackInfo.damageDealt = attackInfo.damageDealt + result.damageDealt
					end

					self:ClearMomentaryOngoingEffects()
					targetCreature:ClearMomentaryOngoingEffects()
					target:CompleteChanges('Damaged')

					if selfToken ~= nil then
						selfToken:ClearTarget(target.id)
					end
				end

				if completeAttack then
					completeAttack(true, attackInfo)
				end
			end,

			cancelRoll = function()
				if selfToken ~= nil then
					for _,target in ipairs(targets) do
						selfToken:ClearTarget(target.id)
					end
				end
				if cancelAttack ~= nil then
					cancelAttack()
				end
			end,

		}

		for _,target in ipairs(targets) do
			local targetCreature = target.properties
			targetCreature:ClearMomentaryOngoingEffects()
		end
		self:ClearMomentaryOngoingEffects()

	end
end

function ActivatedAbilityAttackBehavior:Cast(ability, casterToken, targets, options)

	local fireObjectArgs = nil

	local damageCheckboxes = {}

	local attack = nil
	local beginAttack = nil
	local targetTokens = {}
	for i,target in ipairs(targets) do
		local targetCreature = target.token.properties

		options.symbols = options.symbols or {}
		options.symbols.target = GenerateSymbols(targetCreature)
		attack = self:GetAttack(ability, casterToken.properties, options)

		if i == 1 and ability:has_key("attackOverride") and ability.attackOverride:has_key("consumeAmmo") and ability.attackOverride:has_key("meleeRange") and (casterToken:DistanceInFeet(target.token) - 2.5) <= ability.attackOverride.meleeRange then
			--this is a melee attack, so make sure we don't consume projectiles to use it.
			options.meleeAttack = true
		end

		if i == 1 and ability:has_key("attackOverride") and (ability.attackOverride:has_key("consumeAmmo") or ability.attackOverride:try_get("outOfAmmo", false)) and ((not ability.attackOverride:has_key("meleeRange")) or (casterToken:DistanceInFeet(target.token) - 2.5) > ability.attackOverride.meleeRange) then
			local consumeAmmo = ability.attackOverride:try_get("consumeAmmo")

			--we are out of ammo, but just find the mundane ammo for this weapon and use that.
			if consumeAmmo == nil then
				local gearTable = dmhub.GetTable('tbl_Gear')
				for k,gear in pairs(gearTable) do
					if gear:try_get("equipmentCategory") == ability.attackOverride:try_get("ammoType") then
						consumeAmmo = { [k] = 1 }
					end
				end
			end
			for k,_ in pairs(consumeAmmo) do
				if beginAttack == nil then
					--throw a missile at the target.
					beginAttack = function(rollInfo)
						Projectile.Fire{
							rollInfo = rollInfo,
							ability = ability,
							casterToken = casterToken,
							targetToken = target.token,
							missileid = k,
						}
						if options.markLineOfSight ~= nil then
							options.markLineOfSight:DestroyLineOfSight()
						end
					end
				end
			end
		elseif attack:try_get("melee") then
			beginAttack = function(rollInfo)
				Anim.MeleeAttack{
					rollInfo = rollInfo,
					attackerToken = casterToken,
					targetToken = target.token,
					damage = dmhub.RollExpectedValue(self:ExpectedDamageRoll(ability, casterToken, target.token, options)),
				}
			end
		elseif ability.projectileObject ~= "none" then
			fireObjectArgs = {
				ability = ability,
				casterToken = casterToken,
				targetToken = target.token,
				objectid = ability.projectileObject,
			}
		end

		--see if there are any other effects that might be triggered by this which we should show checkboxes for.
		--fold effects with the same description into the same checkbox.
		damageCheckboxes = {}
		local allBehaviors = ability.behaviors
		local damageCheckboxesByText = {}
		for _,behavior in ipairs(allBehaviors) do
			if GameSystem.GetApplyToInfo(behavior.applyto).attack_hit and behavior:try_get("hitDescription", "") ~= "" then
				local symbols = {}
				for k,v in pairs(options.symbols or {}) do
					symbols[k] = v
				end
				symbols.target = target.token.properties
				local passFilter = true
				passFilter = GoblinScriptTrue(ExecuteGoblinScript(behavior.filterTarget, casterToken.properties:LookupSymbol(symbols), 1, string.format("Filter targets: %s", ability.name)))
				local info
				info = {
					check = true,
					text = behavior.hitDescription,
					value = passFilter,
					tooltip = behavior:try_get("hitDetails"),
					target = target.token.properties,
					behavior = behavior,
					additionalInfo = {},
					change = function(val)
						info.value = val
						for _,other in ipairs(info.additionalInfo) do
							other.value = val
						end
					end,
				}

				options.passFilterOverrides = options.passFilterOverrides or {}
				options.passFilterOverrides[#options.passFilterOverrides+1] = info

				local existing = damageCheckboxesByText[info.text]
				if existing ~= nil then
					--another checkbox with the same name, so just add as an additional checkbox to that.
					existing.additionalInfo[#existing.additionalInfo] = info
				else
					damageCheckboxes[#damageCheckboxes+1] = info
					damageCheckboxesByText[info.text] = info
				end
			end
		end

		targetTokens[#targetTokens+1] = target.token
	end

	local canceled = false
	local completed = false
	local attackHit = false

	casterToken.properties:MCDMRollAttack(attack, targetTokens, {
		ability = ability,
		damageCheckboxes = damageCheckboxes,
		symbols = options.symbols,
		keywords = ability.keywords,
		beginAttack = function(rollInfo)
			if beginAttack ~= nil then
				beginAttack(rollInfo)
			end

			--go ahead and pay for this ability now so that during the damage phase we have updated resources correctly.
			if not options.alreadyPaid then
				options.alreadyPaid = true
				ability:ConsumeResources(casterToken, {
					costOverride = options.costOverride,
					meleeAttack = options.meleeAttack,
				})
			end

			if fireObjectArgs ~= nil then
				Projectile.FireObject(fireObjectArgs)
			end
		end, 

		completeAttackRoll = function(rollInfo)
            ability:CommitToPaying(casterToken, options)
			local outcome = rollInfo.properties:GetOutcome(rollInfo)

			for _,targetToken in ipairs(targetTokens) do
				self:RecordOutcomeToApplyToTable(targetToken, options, outcome)
			end

			for _,roll in ipairs(rollInfo.rolls) do
				if (not roll.dropped) and roll.numFaces == 20 then
					options.symbols.cast.naturalattackroll = roll.result
				end
			end

			options.symbols.cast.attackroll = rollInfo.total
			if options.markLineOfSight ~= nil then
				options.markLineOfSight:Destroy()
				options.markLineOfSight = nil
			end
		end,

		completeAttack = function(hit, completeAttackOptions)
            ability:CommitToPaying(casterToken, options)
			completed = true
			attackHit = hit
			if attackHit then
				options.symbols.cast.damagedealt = options.symbols.cast.damagedealt + completeAttackOptions.damageDealt
				options.symbols.cast.damageraw = options.symbols.cast.damageraw + completeAttackOptions.damageRaw

				for _,targetToken in ipairs(targetTokens) do
					self:RecordHitTarget(targetToken, options)
				end
			end
		end,
		cancelAttack = function()
			canceled = true
		end,
	})

	while canceled == false and completed == false do
		coroutine.yield(0.1)
	end

	if canceled then
		return
	end

	if attackHit and self:has_key("attackTriggeredAbility") then
		--trigger the ability for this attack.
		for _,target in ipairs(targets) do
			self.attackTriggeredAbility:AttackHitWhileInCoroutine(casterToken, target.token)
		end
	end
end

