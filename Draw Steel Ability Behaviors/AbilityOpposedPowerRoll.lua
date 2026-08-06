local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityOpposedRollBehavior:ActivatedAbilityBehavior
ActivatedAbilityOpposedRollBehavior = RegisterGameType("ActivatedAbilityOpposedRollBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityOpposedRollBehavior.summary = 'Opposed Power Roll'

ActivatedAbility.RegisterType
{
	id = 'opposed',
	text = 'Opposed Power Roll',
	createBehavior = function()
		return ActivatedAbilityOpposedRollBehavior.new{
			attackAttributes = { attribute = "mgt", skill = nil },
			defenseAttributes = { attribute = "mgt", skill = nil },
		}
	end
}

function ActivatedAbilityOpposedRollBehavior.CheckNameFromId(id)
	if creature.attributesInfo[id] then
		return creature.attributesInfo[id].description
	else
		return Skill.SkillsById[id].name
	end
end

function ActivatedAbilityOpposedRollBehavior:CreateCheck(ability, casterToken, targets, attrid, isattacker, options)

	local explanation = nil
	if isattacker then
		explanation = string.format("Opposed Power Roll for your %s", ability.name)
	else
		explanation = string.format("Opposed Power Roll against's %s's %s.", casterToken.description, ability.name)
	end

    check = RollCheck.new{
        type = "opposed_power_roll",
        id = attrid,
        text = ActivatedAbilityOpposedRollBehavior.CheckNameFromId(attrid),
        explanation = explanation,
        silent = false,
        options = {
            casterid = casterToken.charid,
			skills = options.skills,
			--Carried along so the roller's own modifiers can be filtered on the
			--ability, e.g. "only when I am searching for hidden creatures".
			ability = ability,
        },
    }

	return check
end

ActivatedAbilityOpposedRollBehavior.silent = true

function ActivatedAbilityOpposedRollBehavior:Cast(ability, casterToken, targets, options)

	local checks = {}

	local attackerChecks = {}
	local defenderChecks = {}

	for _,attr in ipairs(self.attackAttributes) do
		local characteristic = attr.attribute
		options.skills = {attr.skill}
		local check = self:CreateCheck(ability, casterToken, targets, characteristic, true, options)

		local addedMods = {}

		--Check targets for modifiers that would effect this roll
		for _, target in ipairs(targets) do
			if target.token ~= nil then
				local targetCreature = target.token:GetCreature()
				local targetMods = targetCreature:GetActiveModifiers()
				local caster = casterToken:GetCreature()

				for _,mod in ipairs(targetMods) do
					--this is run from the defender's perspective.
					local m = mod.mod:DescribeModifyPowerRoll(mod, targetCreature, "opposed_power_roll", {ability = ability, caster = caster, target = targetCreature})
					if m ~= nil then
						if options.symbols ~= nil then
							m.modifier:InstallSymbolsFromContext(options.symbols)
						end

						--this is told from the caster's perspective.
						m.hint = m.modifier:HintModifyPowerRolls(mod, caster, "opposed_power_roll", {
							ability = ability,
							target = targetCreature,
						})

						if m.hint ~= nil then
							addedMods[#addedMods+1] = m
						end
					end
				end
			end
		end

		--Pass Target mods onto check
		check.modifiers = addedMods
		checks[#checks+1] = check
		attackerChecks[#attackerChecks+1] = #checks
	end

	for _,attr in ipairs(self.defenseAttributes) do
		local characteristic = attr.attribute
		options.skills = {attr.skill}
		local check = self:CreateCheck(ability, casterToken, targets, characteristic, false, options)
		checks[#checks+1] = check
		defenderChecks[#defenderChecks+1] = #checks
	end

	local tokenInfo = {}
	tokenInfo[casterToken.charid] = {
		team = "attacker",
		checks = attackerChecks,
	}

	for _,target in ipairs(targets) do
		if target.token ~= nil then
			tokenInfo[target.token.charid] = {
				team = "defender",
				checks = defenderChecks,
			}
		end
	end

	local actionid = dmhub.SendActionRequest(RollRequest.new{
		checks = checks,
		silent = self.silent,
		tokens = tokenInfo,
	})

	local dcresult = {}

	if self.silent then
		AwaitRequestedActionCoroutine(actionid, dcresult)
	else
		gamehud:ShowRollSummaryDialog(actionid, dcresult)
	end

	while dcresult.result == nil do
		coroutine.yield(0.1)
	end

	if dcresult.result == false then
		return
	end

	local dcaction = dcresult.action

	local attackerRoll = dcaction.info.tokens[casterToken.charid].result

	if attackerRoll == nil then
		return
	end

	for _,target in ipairs(targets) do
		if target.token ~= nil then
			local defenderRoll = dcaction.info.tokens[target.token.charid].result
			--State does not change on ties
			if defenderRoll ~= nil and defenderRoll < attackerRoll then
				self:RecordHitTarget(target.token, options)
			end
		end
	end
end

function ActivatedAbilityOpposedRollBehavior:EditorItems(parentPanel)
	local result = {}
	self:OpposedCheckTypeEditor(parentPanel, "Attacker Roll", "attackAttributes", result)
	self:OpposedCheckTypeEditor(parentPanel, "Defender Roll", "defenseAttributes", result)
	return result
end


function ActivatedAbilityBehavior:OpposedCheckTypeEditor(parentPanel, title, attributeName, list)
	-- Entries should be a table: { attribute = attrid, skill = skillid or nil }
	local entries = self:get_or_add(attributeName, {})
	
	-- Do we need more than one entry?
	local entry = entries[1]
	if not entry then
		entry = { attribute = nil, skill = nil }
		entries[1] = entry
	end

	local attributeOptions = {
		{ id = "none", text = "Select Characteristic..." }
	}
	for _, attrid in ipairs(creature.attributeIds) do
		attributeOptions[#attributeOptions+1] = {
			id = attrid,
			text = creature.attributesInfo[attrid].description,
		}
	end

	local skillOptions = { { id = "none", text = "(No Skill)" } }
	for _, skillInfo in ipairs(Skill.SkillsInfo) do
		skillOptions[#skillOptions+1] = {
			id = skillInfo.id,
			text = skillInfo.name,
		}
	end

	-- Characteristic dropdown
	local attrDropdown = gui.Dropdown{
		classes = "formDropdown",
		options = attributeOptions,
		idChosen = entry.attribute or "none",
		change = function(element)
			if element.idChosen ~= "none" then
				entry.attribute = element.idChosen
				entry.skill = nil -- reset skill if attribute changes
			else
				entry.attribute = nil
				entry.skill = nil
			end
			parentPanel:FireEvent('refreshBehavior')
		end,
	}

	-- Skill dropdown only if a Characteristic is selected
	local skillDropdown = nil
	if entry.attribute and entry.attribute ~= "none" then
		skillDropdown = gui.Dropdown{
			classes = "formDropdown",
			options = skillOptions,
			idChosen = entry.skill or "none",
			change = function(element)
				if element.idChosen ~= "none" then
					entry.skill = element.idChosen
				else
					entry.skill = nil
				end
				parentPanel:FireEvent('refreshBehavior')
			end,
		}
	end

	local panel = gui.Panel{
		classes = {"formPanel"},
		flow = "vertical",
		gui.Label{
			classes = "formLabel",
			text = title,
		},
		attrDropdown,
		skillDropdown
	}

	list[#list+1] = panel
end

--[[ RollCheck.RegisterCustom{
    id = "opposed_power_roll",
    rollType = "opposed_power_roll",
	Describe = function(check, isplayer)
        local attrName = check.info.attrid
        local attrInfo = creature.attributesInfo[check.info.attrid]
        attrName = attrInfo and attrInfo.description or attrName
        return "Opposed Roll vs " .. attrName
    end,
	GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,
	GetModifiers = function(check, creature)
        return creature:GetModifiersForPowerRoll(check:GetRoll(creature), "test_power_roll")
    end,
	ShowDialog = function(check, dialogOptions)
        dialogOptions.rollProperties = RollPropertiesPowerTable.new{
            --tiers = DeepCopy(check.info.tiers)
        }
        --dialogOptions.PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(dialogOptions.rollProperties, dialogOptions.creature)
        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
} ]]