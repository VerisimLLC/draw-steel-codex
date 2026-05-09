local mod = dmhub.GetModLoading()

--- @class CharacterPrerequisite
--- @field guid string Unique identifier.
--- @field type string Prerequisite type id (e.g. "skillProficiency", "equipmentProficiency").
--- @field skill string Id of the skill or equipment category required.
CharacterPrerequisite = RegisterGameType("CharacterPrerequisite")

CharacterPrerequisite.skill = 'none'

CharacterPrerequisite.registry = {}

CharacterPrerequisite.options = {
	{
		id = 'none',
		text = 'Add Prerequisite...',
	},
	{
		id = 'equipmentProficiency',
		text = 'Equipment Proficiency',
	},
	{
		id = 'skillProficiency',
		text = 'Skill Proficiency',
	},
}

function CharacterPrerequisite.Register(t)
	CharacterPrerequisite.registry[t.id] = t

	local index = #CharacterPrerequisite.options+1
	for i,option in ipairs(CharacterPrerequisite.options) do
		if option.id == t.id then
			index = i
			break
		end
	end

	CharacterPrerequisite.options[index] = {
		id = t.id,
		text = t.text,
	}
end

CharacterPrerequisite.Register{
	id = "equipmentProficiency",
	text = "Equipment Proficiency",
	met = function(self, creature)
		local proficiencies = creature:EquipmentProficienciesKnown()
		return proficiencies[self.skill] ~= nil
	end,
	options = function()
		return EquipmentCategory.GetEquipmentProficiencyDropdownOptions()
	end,
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
	id = "levelRequirement",
	text = "Character Level",
	met = function(self, creature)
		local requirement = tonumber(self.skill)
		return requirement == nil or creature:CharacterLevel() >= requirement
	end,
	options = function()
		local result = {}
		for i=1,GameSystem.numLevels do
			result[#result+1] = {
				id = tostring(i),
				text = string.format("Level %d", i),
			}
		end
		return result
	end
}

function CharacterPrerequisite.Create(options)
	local args = {
		guid = dmhub.GenerateGuid(),
	}

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return CharacterPrerequisite.new(args)
end

function CharacterPrerequisite:Met(creature)
	local info = CharacterPrerequisite.registry[self.type]

	if info ~= nil and info.met ~= nil then
		return info.met(self, creature)
	end

	return true
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMPrerequisite.lua:199
function CharacterPrerequisite:Editor(params)
	local resultPanel

	local args = {
		width = 600,
		height = 'auto',
		minHeight = 40,
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
			fontSize = 26,
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
--]==]
