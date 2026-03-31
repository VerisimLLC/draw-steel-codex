local mod = dmhub.GetModLoading()

CharacterPrerequisite.options = {
    {
		id = 'none',
		text = 'Add Prerequisite...',
	},
}

function character:GetDeities()
	local choices = self:GetLevelChoices()
	local deitiesTable = dmhub.GetTable(Deity.tableName) or {}

	local deities = {}
	-- Look through all choices to find deity selections
	for choiceId, choiceValues in pairs(choices) do
		-- Check if this choice looks like a deity choice by examining the values
		if choiceValues and #choiceValues > 0 then
			for _, chosenValue in ipairs(choiceValues) do
				-- Check if the chosen value is a deity ID
				local deity = deitiesTable[chosenValue]
				if deity then
					deities[#deities + 1] = deity
				end
			end
		end
	end
	return deities
end

function character:GetDomains()
	local choices = self:GetLevelChoices()
	local domainsTable = dmhub.GetTable(DeityDomain.tableName) or {}

	local domains = {}
	for choiceId, choiceValues in pairs(choices) do
		-- Check if this choice looks like a domain choice by examining the values
		if choiceValues and #choiceValues > 0 then
			for _, chosenValue in ipairs(choiceValues) do
				-- Check if the chosen value is a domain ID
				local domain = domainsTable[chosenValue]
				if domain then
					domains[#domains + 1] = domain
				end
			end
		end
	end

	--Conduits Domain is managed by their subclass
	local classes = self:GetClassesAndSubClasses()
	for i, classInfo in ipairs(classes) do
		local class = classInfo.class
		if class then
			local domainName = string.match(class.name, "^(%w+)%s+Domain")
			if domainName then
				for _, domain in unhidden_pairs(domainsTable) do
					if string.lower(domain.name) == string.lower(domainName) then
						domains[#domains + 1] = domain
					end
				end
			end
		end
	end

	return domains
end

function monster:GetDeities()
	return {}
end

function monster:GetDomains()
	return {}
end

function creature:GetDeities()
	return {}
end

function creature:GetDomains()
	return {}
end

CharacterPrerequisite.Register{
	id = "deity",
	text = "Deity",
	met = function(self, creature)
		if not self.skill or self.skill == "none" then
			return true
		end
		local deities = creature:GetDeities()
		
		if not deities or #deities == 0 then
			return false
		end
		
		for _, deity in ipairs(deities) do
			if deity.id == self.skill then
				return true
			end
		end
		return false
	end,
	options = function()
		return Deity.GetDropdownList()
	end
}

CharacterPrerequisite.Register{
	id = "domain",
	text = "Domain",
	met = function(self, creature)
		if not self.skill or self.skill == "none" then
			return true
		end
		local domains = creature:GetDomains()

		if not domains or #domains == 0 then
			return false
		end

		local domainsTable = dmhub.GetTable(DeityDomain.tableName) or {}
		for _, domain in ipairs(domains) do
			if domain.id == self.skill then
				return true
			end
		end
		return false
	end,
	options = function()
		return DeityDomain.GetDropdownList()
	end
}

CharacterPrerequisite.Register{
	id = "skillProficiency",
	text = "Skill Proficiency",
	met = function(self, creature)
		return creature:ProficientInSkill(Skill.SkillsById[self.skill])
	end,
	options = function()
		return Skill.skillsDropdownOptions
	end
}

CharacterPrerequisite.Register{
	id = "goblinscript",
	text = "Goblinscript",
	met = function(self, creature)
		return ExecuteGoblinScript(self:try_get("filter", ""), creature:LookupSymbol(), 0, "Filter target") == 1
	end,
}

function CharacterFeatureList:CharacterUniqueID()
	--a repeated feature is an upgrade.
	return self.name
end

function CharacterFeatureList:FillChoice(choices, result)
	local parentPrereqs = self:try_get("prerequisites")

	if parentPrereqs and #parentPrereqs > 0 then
		for i, feature in ipairs(self.features) do
            --The prerequisites are checked on return from this function, so we need to
            --copy the feature. TODO: work out a more efficient way to do this, since it's not ideal.
            --Possibly store in _tmp_prerequisites or similar.
            local featureCopy = table.shallow_copy_with_meta(feature)
            featureCopy.prerequisites = parentPrereqs
			featureCopy:FillChoice(choices, result)
		end
	else
		for i, feature in ipairs(self.features) do
			feature:FillChoice(choices, result)
		end
	end
end

function CharacterFeatureList:FillFeaturesRecursive(choices, result)
    result[#result+1] = self
    
    local parentPrereqs = self:try_get("prerequisites")
    
    if parentPrereqs and #parentPrereqs > 0 then
        for i, feature in ipairs(self.features) do
            --The prerequisites are checked on return from this function, so we need to
            --copy the feature. TODO: work out a more efficient way to do this, since it's not ideal.
            --Possibly store in _tmp_prerequisites or similar.
            local featureCopy = table.shallow_copy_with_meta(feature)
            featureCopy.prerequisites = parentPrereqs
            featureCopy:FillFeaturesRecursive(choices, result)
        end
    else
        for i, feature in ipairs(self.features) do
            feature:FillFeaturesRecursive(choices, result)
        end
    end
end

function CharacterPrerequisite:Editor(params)
	local resultPanel

	local args = {
		width = 400,
		height = 'auto',
		vmargin = 4,
		halign = "left",
		borderWidth = 1,
		borderColor = 'white',
		bgimage = 'panels/square.png',
		bgcolor = 'black',
		flow = 'vertical',
		pad = 4,
	}

	for k,p in pairs(params) do
		args[k] = p
	end

	resultPanel = gui.Panel(args)

	local Refresh
	Refresh = function()
		local typeInfo = CharacterPrerequisite.registry[self.type]
	
		local children = {}

		local titleText = 'Prerequisite'

		if typeInfo ~= nil then
			titleText = string.format("%s Prerequisite", typeInfo.text)
		end

		children[#children+1] = gui.Label{
			text = titleText,
			color = 'white',
			halign = 'left',
			valign = 'top',
			width = 'auto',
			height = 'auto',
			fontSize = 18,
		}

		local skillOptions = {}
		if typeInfo ~= nil then
			if typeInfo.options == nil then
				skillOptions = nil
			else
				skillOptions = typeInfo.options()
			end
		end

		if skillOptions ~= nil then
			if self.skill == 'none' then
				table.insert(skillOptions, 1, { id = 'none', text = 'Choose Proficiency...' })
			end

			children[#children+1] = gui.Dropdown{
				halign = "left",
				vmargin = 4,
				width = 240,
				height = 24,
				fontSize = 18,
				options = skillOptions,
				idChosen = self.skill,
				change = function(element)
					self.skill = element.idChosen
					resultPanel:FireEvent("change")
				end,
			}
		else
			children[#children+1] = gui.GoblinScriptInput{
            value = self:try_get("filter", ""),
            change = function(element)
                self.filter = element.value
            end,
            documentation = {
                help = string.format("This GoblinScript is used to determine the creature passes the required prerequisite."),
                output = "number",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is has this feature.",
            }
        }
		end

		if typeInfo ~= nil and typeInfo.editor ~= nil then
			children[#children+1] = typeInfo.editor(self)
		end

		children[#children+1] = gui.DeleteItemButton{
			floating = true,
			halign = "right",
			valign = "top",
			width = 16,
			height = 16,
			click = function(element)
				resultPanel:FireEvent("delete")
			end,
		}

		resultPanel.children = children
	end

	Refresh()

	return resultPanel
end