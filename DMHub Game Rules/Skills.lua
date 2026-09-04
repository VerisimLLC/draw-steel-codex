local mod = dmhub.GetModLoading()

--- @class Skill
--- @field tableName string Data table name ("Skills").
--- @field name string Display name.
--- @field attribute string Governing ability score id (e.g. "str", "dex").
--- @field hasPassive boolean If true, a passive version of this skill exists.
--- @field specializations boolean|table If false, no specializations; otherwise a list of specialization objects.
--- @field hidden boolean If true, this skill is hidden from UI menus.
Skill = RegisterGameType("Skill")

--- @class SkillSpecialization
--- @field id string Unique identifier.
--- @field name string Display name for this specialization.
SkillSpecialization = RegisterGameType("SkillSpecialization")

Skill.tableName = "Skills"
Skill.hasPassive = false
Skill.specializations = false
Skill.hidden = false

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMSkills.lua:41
function Skill.CreateNew()
	return Skill.new{
		id = dmhub.GenerateGuid(),
		name = "New Skill",
		attribute = "str",
		specializations = {},
	}
end
--]==]

--- @param name string
--- @return nil|Skill
function Skill.FindByName(name)
	name = string.lower(name)
	local t = dmhub.GetTable(Skill.tableName)
	for k,v in pairs(t) do
		if string.lower(v.name) == name then
			return v
		end
	end

	return nil
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMSkills.lua:50
function Skill.GetSpecializationDropdownOptions(self)
	local result = {}
	result[#result+1] = {
		id = "all",
		text = "All",
	}

	for _,s in ipairs(Skill.GetSpecializations(self)) do
		result[#result+1] = {
			id = s.id,
			text = s.text,
		}
	end
	return result
end
--]==]

function Skill.GetSpecializations(self)
	return self.specializations or {}
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMSkills.lua:70
function Skill.AddSpecialization(self)
	local specializations = Skill.GetSpecializations(self)

	specializations[#specializations+1] = SkillSpecialization.CreateNew()

	self.specializations = specializations
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMSkills.lua:78
function Skill.GetSpecializationById(self, id)
	for _,s in ipairs(Skill.GetSpecializations(self)) do
		if s.id == id then
			return s
		end
	end
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMSkills.lua:86
function Skill.DeleteSpecializationById(self, id)
	local specializations = Skill.GetSpecializations(self)
	local newSpecializations = {}
	for _,s in ipairs(specializations) do
		if s.id ~= id then
			newSpecializations[#newSpecializations+1] = s
		end
	end

	self.specializations = newSpecializations
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMSkills.lua:98
function SkillSpecialization.CreateNew()
	return SkillSpecialization.new{
		id = dmhub.GenerateGuid(),
		text = "New Specialization",
	}
end
--]==]

local ParseAdvantage = function(str)
	if str == nil then
		return nil
	end
	str = string.lower(str)
	if str ~= '' then
		if string.startswith('advantage', str) then
			return 'advantage'
		elseif string.startswith('disadvantage', str) then
			return 'disadvantage'
		end
	end

	return nil
end

local initCategories = false

dmhub.RegisterEventHandler("refreshTables", function()
	local skillTable = dmhub.GetTable(Skill.tableName) or {}
	Skill.SkillsInfo = {}
	for id,info in pairs(skillTable) do
		Skill.SkillsInfo[#Skill.SkillsInfo+1] = info
	end

	table.sort(Skill.SkillsInfo, function(a,b)
		return string.lower(a.name) < string.lower(b.name)
	end)

	Skill.SkillsById = {}

	for i,skill in ipairs(Skill.SkillsInfo) do
		Skill.SkillsById[skill.id] = skill
	end

	Skill.skillsDropdownOptions = {}
	Skill.skillsDropdownOptionsWithNone = {
		{
			id = 'none',
			text = 'Choose Skill...',
		}
	}
	for i,skillInfo in ipairs(Skill.SkillsInfo) do
        if not skillInfo.hidden then
            Skill.skillsDropdownOptions[#Skill.skillsDropdownOptions+1] = {
                id = skillInfo.id,
                text = skillInfo.name,
            }
            Skill.skillsDropdownOptionsWithNone[#Skill.skillsDropdownOptionsWithNone+1] = Skill.skillsDropdownOptions[#Skill.skillsDropdownOptions]
        end
	end

	--Passive skills
	Skill.PassiveSkills = {}
	for i,v in pairs(Skill.SkillsInfo) do
		if v.hasPassive and not v.hidden then
			Skill.PassiveSkills[#Skill.PassiveSkills+1] = v
		end
	end
	
	--init creature commands for skills.
	for i,v in ipairs(Skill.SkillsInfo) do
		local skillInfo = v
        if not skillInfo.hidden then
            local commandKey = skillInfo.id
            creature.commands[commandKey] = function(self, str)
                self:RollSkillCheck(skillInfo, ParseAdvantage(str))
            end
        end
	end

    RollCheck.LoadSkills()

	if initCategories then
		return
	end

	initCategories = true

	for i,skill in ipairs(Skill.SkillsInfo) do
        if not skill.hidden then
            CustomAttribute.RegisterAttribute
            {
                id = skill.id,
                text = string.format("%s Modifier", skill.name),
                attributeType = "number",
                category = "Skills",
            }
        end
	end

	for i,skill in ipairs(Skill.SkillsInfo) do
		if skill.hasPassive and not skill.hidden then
			CustomAttribute.RegisterAttribute
			{
				id = string.format("PASSIVE-%s", skill.id),
				text = string.format("Passive %s Modifier", skill.name),
				attributeType = "number",
				category = "Senses",
			}
		end
	end

end)
