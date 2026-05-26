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
