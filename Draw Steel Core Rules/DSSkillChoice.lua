local mod = dmhub.GetModLoading()

RegisterGameType("CharacterSkillChoice", "CharacterChoice")

CharacterSkillChoice.name = "Skill"
CharacterSkillChoice.description = "Choose a Skill"
CharacterSkillChoice.categories = {}
CharacterSkillChoice.individualSkills = {}
CharacterSkillChoice.numChoices = 1

function CharacterSkillChoice.Create(options)
	local result = CharacterSkillChoice.new{
		guid = dmhub.GenerateGuid(),
	}

    for k,v in pairs(options or {}) do
        result[k] = v
    end

    return result
end

local g_tagCache = {}
local g_optCache = {}

dmhub.RegisterEventHandler("refreshTables", function(keys)
	g_tagCache = {}
    g_optCache = {}
end)

function CharacterSkillChoice:_cache()
	if g_tagCache[self.categories] ~= nil and g_optCache[self.categories] ~= nil then return end

    local tags = {}
    local options = {}

	local skillsTable = dmhub.GetTable(Skill.tableName)
	for k,skill in pairs(skillsTable) do
		if (not skill:try_get("hidden", false)) and (self.categories[skill.category] or self.individualSkills[k]) then
			tags[#tags+1] = {
				id = k,
				text = skill.name,
                description = skill:try_get("description"),
				unique = true, --this means there will be checking in the builder so if we already have this id selected somewhere it won't be shown here.
			}
            options[#options+1] = {
                guid = k,
                name = skill.name,
                description = skill:try_get("description"),
                unique = true,
            }
		end
	end

	g_tagCache[self.categories] = tags
    g_optCache[self.categories] = options
end

function CharacterSkillChoice:Choices(numOption, existingChoices, creature)
	if g_tagCache[self.categories] == nil then self:_cache() end
	return g_tagCache[self.categories]
end

function CharacterSkillChoice:GetOptions(choices)
    if g_optCache[self.categories] == nil then self:_cache() end
    return g_optCache[self.categories]
end

function CharacterSkillChoice:GetDescription()
	return self.description
end

function CharacterSkillChoice:NumChoices(creature)
	return self.numChoices
end

function CharacterSkillChoice:CanRepeat()
	return false
end

local g_hit = 0
local g_miss = 0

function CharacterSkillChoice:GetSkillFeatures()
    if self:try_get("_tmp_skillFeatures") ~= nil and (dmhub.DeepEqual(self:try_get("_tmp_skillFeaturesKey"), self.categories)) then
        g_hit = g_hit + 1
        return self._tmp_skillFeatures
    end

    self._tmp_skillFeaturesKey = table.shallow_copy(self.categories)
    for k,v in pairs(self.individualSkills) do
        self._tmp_skillFeaturesKey[k] = true
    end

    local skillFeatureIndex = 1
    if not self:has_key("_tmp_skillFeatures") then
        self._tmp_skillFeatures = {}
    end

    local skillsTable = dmhub.GetTable(Skill.tableName)
    for k,skill in pairs(skillsTable) do
        if (not skill:try_get("hidden", false)) and (self.categories[skill.category] or self.individualSkills[k]) then
            local feature = self._tmp_skillFeatures[skillFeatureIndex] or dmhub.DeepCopy(MCDMImporter.GetStandardFeature("Skill"))
            skillFeatureIndex = skillFeatureIndex + 1
            feature.id = k
            feature.guid = k
            feature.name = skill.name
            feature.modifiers[1].name = skill.name
            feature.modifiers[1].skills = {[k] = true}
            feature.modifiers[1].sourceguid = self.guid

            self._tmp_skillFeatures[#self._tmp_skillFeatures+1] = feature
        end
    end

    while #self._tmp_skillFeatures >= skillFeatureIndex do
        table.remove(self._tmp_skillFeatures)
    end

    return self._tmp_skillFeatures
end

function CharacterSkillChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local skillFeatures = self:GetSkillFeatures()
    for _,choiceid in ipairs(choiceidList) do
        for _,f in ipairs(skillFeatures) do
            if f.guid == choiceid then
                f:FillChoice(choices, result)
            end
        end
    end
end

function CharacterSkillChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end
    
    local skillFeatures = self:GetSkillFeatures()
    for _,choiceid in ipairs(choiceidList) do
        for _,f in ipairs(skillFeatures) do
            if choiceid.guid == choiceid then
                f:FillFeaturesRecursive(choices, result)
            end
        end
    end
end

function CharacterSkillChoice:VisitRecursive(fn)
	fn(self)
end

function CharacterSkillChoice:CreateEditor(classOrRace, params)
	params = params or {}

    local resultPanel

    resultPanel = {
        width = "100%",
        height = "auto",
        flow = "vertical",

        gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Skills",
            },
            gui.Input{
                width = 180,
                text = tonumber(self.numChoices),
                characterLimit = 2,

                change = function(element)
                    local n = math.max(1, round(tonumber(element.text) or self.numChoices))
                    self.numChoices = n
                    resultPanel:FireEvent("change")
                end,
            }
        },

        gui.Panel{
            classes = {"formPanel"},
            flow = "vertical",
            height = "auto",
            create = function(element)
                local children = {}
                local skillTable = dmhub.GetTable(Skill.tableName)
                for k,v in pairs(self.individualSkills) do
                    local skill = skillTable[k]
                    if skill ~= nil then
                        children[#children+1] = gui.Label {
                            text = skill.name,
                            fontSize = 16,
                            textAlignment = "left",
                            width = 300,
                            vmargin = 4,

                            gui.DeleteItemButton{
                                halign = "right",
                                width = 16,
                                height = 16,
                                click = function(element)
                                    self.individualSkills[k] = nil
                                    resultPanel:FireEventTree("create")
                                    resultPanel:FireEvent("change")
                                end,
                            }
                        }
                        
                    end
                end

                table.sort(children, function(a,b)
                    return a.text < b.text
                end)

                for k,v in pairs(self.categories) do
                    local info = Skill.categoriesById[k]
                    if info ~= nil then
                        children[#children+1] = gui.Label{
                            text = string.format("%s Skill Group", info.text),
                            fontSize = 16,
                            textAlignment = "left",
                            width = 300,
                            vmargin = 4,

                            gui.DeleteItemButton{
                                halign = "right",
                                width = 16,
                                height = 16,
                                click = function(element)
                                    self.categories[k] = nil
                                    resultPanel:FireEventTree("create")
                                    resultPanel:FireEvent("change")
                                end,
                            }
                        }
                    end
                end

                children[#children+1] = gui.Dropdown{
                    width = 300,
                    textDefault = "Add Skills...",
                    hasSearch = true,
                    create = function(element)
                        element.idChosen = nil
                        local result = {}
                        for k,v in pairs(Skill.categoriesById) do
                            if not self.categories[k] then
                                local entry = DeepCopy(v)
                                entry.text = string.format("%s Skill Group", entry.text)
                                entry.ord = "A-" .. entry.text
                                result[#result+1] = entry
                            end
                        end

                        local skills = {}
                        local skillTable = dmhub.GetTable(Skill.tableName)
                        for k,v in pairs(skillTable) do
                            if not v:try_get("hidden", false) then
                                result[#result+1] = {
                                    id = k,
                                    text = v.name,
                                    ord = "B-" .. v.name,
                                }
                            end
                        end

                        table.sort(result, function(a,b)
                            return a.ord < b.ord
                        end)

                        element.options = result
                    end,

                    change = function(element)
                        local value = element.idChosen
                        if Skill.categoriesById[value] then
                            self.categories = DeepCopy(self.categories)
                            self.categories[value] = true
                        else
                            self.individualSkills = DeepCopy(self.individualSkills)
                            self.individualSkills[value] = true
                        end
                        resultPanel:FireEventTree("create")
                        resultPanel:FireEvent("change")
                    end,
                }

                element.children = children
            end,
        },
    }

    for k,v in pairs(params) do
        resultPanel[k] = v
    end

    resultPanel = gui.Panel(resultPanel)

    return resultPanel
end

CharacterChoice.RegisterChoice{
    id = "skill",
    text = "Choice of a Skill",
    type = CharacterSkillChoice,
}