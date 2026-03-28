local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

--- @class ActivatedAbilitySkillCheckBehavior:ActivatedAbilityBehavior
--- @field summary string Short label shown in behavior lists.
--- @field consequenceText string Text shown when the check fails.
--- @field rollType string What is rolled: "attribute" or a specific skill/attribute id.
ActivatedAbilitySkillCheckBehavior = RegisterGameType("ActivatedAbilitySkillCheckBehavior", "ActivatedAbilityBehavior")


ActivatedAbilitySkillCheckBehavior.summary = 'Skill Check'
ActivatedAbilitySkillCheckBehavior.consequenceText = ''
ActivatedAbilitySkillCheckBehavior.rollType = 'attribute'


ActivatedAbility.RegisterType
{
	id = 'skill_check',
	text = 'Skill Check',
	canHaveDC = true,
	createBehavior = function()
		return ActivatedAbilitySkillCheckBehavior.new{
            dc = creature.attributeIds[1],
		}
	end
}

function ActivatedAbilitySkillCheckBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Roll Check"
end


function ActivatedAbilitySkillCheckBehavior:AccumulateSavingThrowConsequence(ability, casterToken, targets, consequences)
	local tokenids = ActivatedAbility.GetConsequenceTokenIds(self, ability, casterToken, targets)
	if tokenids == false then
		return
	end

    if self.consequenceText ~= "" then
        consequences.text = consequences.text or {}
        consequences.text[#consequences.text+1] = {
            text = self.consequenceText,
            tokens = tokenids,
        }
    end

end

function ActivatedAbilitySkillCheckBehavior:Cast(ability, casterToken, targets, options)


	if #targets == 0 then
		return
	end

	local casterName = creature.GetTokenDescription(casterToken)


	local dcaction = nil
	local tokenids = ActivatedAbility.GetTokenIds(targets)


	local explanation = nil
	if self.rollType == "attribute" then
		explanation = "Rolling an attribute check"
	elseif self.rollType == "skill" then
		local t = dmhub.GetTable(Skill.tableName)
		local s = t[self.dc]
		explanation = "Rolling a skill check"
		if s ~= nil then
			explanation = string.format("Roll a %s check", s.name)
		end
	else
		explanation = "Rolling a flat check"
	end

	local dc_options = self:try_get("dc_options")
	dc_options = dc_options or {}

	dcaction = ability:RequireSavingThrowsCo(self, casterToken, tokenids, {
        rollType = self.rollType,
		id = self.dc,
		text = "Roll",
		explanation = explanation,
		dc_options = dc_options, --self:try_get("dc_options"),
		targets = targets,
	})

	if dcaction == nil then
		--they ended up closing the saving throw dialog, meaning we just cancel the spell.
		return
		
	end

	--people rolled so we consider this to have consumed the resource.
    ability:CommitToPaying(casterToken, options)

    local skillName = nil
    if self.rollType == "skill" then
        local t = dmhub.GetTable(Skill.tableName)
        local s = t[self.dc]
        if s ~= nil then
            skillName = s.name
        end
    end
    local casterClassInfo = casterToken.properties:IsHero() and casterToken.properties:GetClass() or nil
    track("skill_check", {
        rollType = self.rollType,
        skillId = self.dc,
        skillName = skillName,
        caster = casterClassInfo and casterClassInfo.name or casterToken.properties:try_get("monster_type", "monster"),
        targetCount = #targets,
        dailyLimit = 30,
    })

	--check if everyone succeeded on a 'none' dc, meaning nobody will take damage
	--so we won't even roll for damage.
	if self.dcsuccess == 'none' then
		local targetsFailed = false
		for i,target in ipairs(targets) do
			local res = dcaction.info:GetTokenResult(target.token.charid)
			if res == false then
				targetsFailed = true
			end
			--local dcinfo = dcaction.info.tokens[target.token.charid]
			--if dcinfo ~= nil and dcinfo.result ~= nil and dcaction.info.checks[1].dc ~= nil and dcinfo.result < dcaction.info.checks[1].dc then
			--	targetsFailed = true
			--end
		end

		if targetsFailed == false then
			return
		end
	end

	--get rid of any targets that were removed.
	for i=#targets,1,-1 do
		local target = targets[i]
		local dcinfo = dcaction.info.tokens[target.token.charid]
		if dcinfo == nil then
			table.remove(targets, i)
		end
	end

	for i,target in ipairs(targets) do
		--new way of recording hit targets.
		local outcome = dcaction.info:GetTokenOutcome(target.token.charid)
		self:RecordOutcomeToApplyToTable(target.token, options, outcome)

		--old way of recording hit targets.
		local res = dcaction.info:GetTokenResult(target.token.charid)
		if res ~= true then
			self:RecordHitTarget(target.token, options, {failedSave = true})
		end
    end

end

function ActivatedAbilitySkillCheckBehavior:DCEditor(parentPanel, list)

    list[#list+1] = gui.Panel{
        classes = {"formPanel"},
		gui.Label{
			classes = "formLabel",
			text = "Roll Type:",
		},
        gui.Dropdown{
            classes = {"formDropdown"},
            options = {
                {
                    id = "attribute",
                    text = "Attribute",
                },
                {
                    id = "skill",
                    text = "Skill",
                },
                {
                    id = "flat",
                    text = "Flat",
                },
            },
            idChosen = self.rollType,
            change = function(element)
                if element.idChosen == self.rollType then
                    return
                end

                self.rollType = element.idChosen

                if self.rollType == "flat" then
                    self.dc = "flat"
                else
                    self.dc = nil
                end
                parentPanel:FireEvent("refreshBehavior")
            end,
        }
    }

    if self.rollType ~= "flat" then
        local options
        
        if self.rollType == "attribute" then
            options = DeepCopy(creature.attributeDropdownOptions)
        else
            options = DeepCopy(Skill.skillsDropdownOptions)
        end


        list[#list+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = "formLabel",
                text = "Check:",
            },
            gui.Dropdown{
                classes = {"formDropdown"},
                options = options,
                idChosen = self:try_get('dc', 'none'),
                textDefault = "Choose...",
                change = function(element)
                    if element.idChosen == 'none' then
                        self.dc = nil
                    else
                        self.dc = element.idChosen
                    end

                    parentPanel:FireEvent('refreshBehavior')
                end,
            },
        }
    end

	list[#list+1] = gui.Panel{
		classes = "formPanel",
		gui.Label{
			classes = "formLabel",
			text = "DC:",
		},
		gui.GoblinScriptInput{
			classes = "formInput",
			value = self:try_get("dcvalue", ""),
			change = function(element)
				self.dcvalue = element.value
			end,

			documentation = {
				domains = parentPanel.data.parentAbility.domains,
				help = string.format("This GoblinScript is used to determine the DC for checks for this ability."),
				output = "number",
				examples = {
					{
						script = "8 + Wisdom Modifier + Proficiency Bonus",
						text = "This sets the DC to 8 plus the caster's Wisdom Modifier and Proficiency Bonus",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature casting the ability",
			},
		},
	}
end


function ActivatedAbilitySkillCheckBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	self:DCEditor(parentPanel, result)
	return result
end