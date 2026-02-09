local mod = dmhub.GetModLoading()

--This file implements the core rules for classes.

RegisterGameType("Class")
RegisterGameType("ClassLevel") --type which represents the benefits a character gets at a specific level.
RegisterGameType("CharacterChoice")
RegisterGameType("CharacterFeatureChoice", "CharacterChoice")
RegisterGameType("CharacterSubclassChoice", "CharacterChoice")
RegisterGameType("CharacterFeatureList")

function Class.CreateNew(options)
	options = options or {}
	return Class.new(options)
end

Class.name = "Unnamed Class"
Class.details = ""
Class.portraitid = ""
Class.tableName = "classes"
Class.isSubclass = false
Class.primaryClassId = ""
Class.hit_die = 8
Class.savingThrows = {}
Class.spellcastingAttr = "none"

Class.spellcastingLevelOptions = {
	{
		id = "full",
		text = "Full",
	},
	{
		id = "half",
		text = "Half",
	},
	{
		id = "third",
		text = "Third",
	},
	{
		id = "custom",
		text = "Custom",
	}
}
Class.spellcastingLevelValues = {
	full = 1,
	half = 2,
	third = 3,
}
Class.spellLeveling = "full" --only relevant if spellcastingAttr isn't "none"
Class.spellLevelFormula = "" --relevant if spellLeveling is "custom". e.g. for Warlocks.
Class.spellList = {} --generally only zero or one spell list, but allow for future flexibility to have multiple spell lists?
Class.cantripsKnownFormula = ""
Class.spellsKnownFormula = ""
Class.hasSpellbook = false
Class.spellbookSizeFormula = ""

function Class:Describe()
	return self.name
end


function Class:Domain()
	return string.format("class:%s", self.id)
end

function Class:Subdomain()
	if self.primaryClassId == "" then
		return nil
	end

	return string.format("class:%s", self.primaryClassId)
end

function Class.OnDeserialize(self)
	local domain = self:Domain()
	for k,level in pairs(self:try_get("levels", {})) do
		level:SetDomain(domain)
		if self.primaryClassId ~= "" then
			level:SetDomain(string.format("class:%s", self.primaryClassId))
		end
	end

	local SetClass = function(feature)
		feature.classid = self.id
	end
	for k,level in pairs(self:try_get("levels", {})) do
		level:VisitAllFeatures(SetClass)
	end
end

function Class:ForceDomains()
	local domains = {}
	domains[self:Domain()] = true
	if self:Subdomain() ~= nil then
		domains[self:Subdomain()] = true
	end
	for k,level in pairs(self:try_get("levels", {})) do
		level:ForceDomains(domains)
	end
end

function Class:FeatureSourceName()
	return string.format("%s Class Feature", self.name)
end

--gets core modifiers which does things like saving throws.
function Class:FillPrimaryModifiers(modifiers)

	local saves = {}
	for i,save in ipairs(self.savingThrows) do
		saves[save] = true
	end

	modifiers[#modifiers+1] = CharacterModifier.new{
		behavior = 'proficiency',
		guid = dmhub.GenerateGuid(),
		name = self.name,
		source = self.name,
		description = "Class Saving Throw",
		subtype = 'save',
		skills = saves,
		proficiency = GameSystem.ProficientId(),
	}
end

function Class:GetPrimaryFeature()
	local result = CharacterFeature.Create{
		name = self.name,
		source = self.name,
	}

	self:FillPrimaryModifiers(result.modifiers)
	return result
end

function Class.GetDropdownList()
	local result = {}
	local classesTable = dmhub.GetTable(Class.tableName)
	for k,v in pairs(classesTable) do
		result[#result+1] = { id = k, text = v.name }
	end

	table.sort(result, function(a,b)
		return a.text < b.text
	end)
	return result
end

function Class:HitDieResourceType()
	if GameSystem.haveHitDice == false then
		return nil
	end

	return string.format("hitDie%d", self.hit_die)
end

--gets the ClassLevel a class gets at a specific level. levelNum == 0 gives the benefits you get when you select this class as your primary class. levelNum == -1 is for multiclass.
function Class:GetLevel(levelNum, subkey)
    subkey = subkey or ""
	local key
	if levelNum == 0 then
		key = "primary"
	elseif levelNum == -1 then
		key = "multiclass"
	else
		key = string.format("%slevel-%d", subkey, levelNum)
	end

	local table = self:get_or_add("levels", {})
	if table[key] == nil then
		table[key] = ClassLevel.CreateNew()
		table[key]:SetDomain(self:Domain())
	end

	return table[key]
end

--fills levels into result. returns the number of entries before the real level 1 begins.
function Class:FillLevelsUpTo(levelNum, extraLevelInfo, secondaryClass, result)
	local levelsTable = self:get_or_add("levels", {})
	

	if secondaryClass ~= "noprimary" then --special code meaning don't give either primary or multiclass.
		if not secondaryClass then
			if levelsTable.primary ~= nil then
				result[#result+1] = levelsTable.primary
			end
		else
			if levelsTable.multiclass ~= nil then
				result[#result+1] = levelsTable.multiclass
			end
		end
	end

    local encounter = extraLevelInfo and extraLevelInfo.encounter or nil
    if levelNum > 1 then
        encounter = nil
    end

    for i=1,(encounter or 4) do
        local key = string.format("tutoriallevel-%d", i)
        if levelsTable[key] ~= nil then
            result[#result+1] = levelsTable[key]
        end
    end

    local nlevelsbefore1 = #result

    if encounter == nil then
        for i=1,levelNum do
            local key = string.format("level-%d", i)
            if levelsTable[key] ~= nil then
                result[#result+1] = levelsTable[key]
            end
        end
    end

	return nlevelsbefore1
end

function Class:GetSubclasses(choices, levelNum, extraLevelInfo)
	local result = {}

	local subclassesTable = GetTableCached("subclasses")
	
	local levels = {}
	self:FillLevelsUpTo(levelNum, extraLevelInfo, false, levels)
	for i,levelInfo in ipairs(levels) do
		for j,feature in ipairs(levelInfo.features) do
			if feature.typeName == 'CharacterSubclassChoice' and choices[feature.guid] ~= nil and #choices[feature.guid] > 0 then
				local subclass = subclassesTable[choices[feature.guid][1]]
				if subclass ~= nil and (not subclass:try_get("hidden", false)) then
					result[#result+1] = subclass
				end
			end
		end
	end

	return result
end

--This fills 'result' with the features we have for this class up to the given level.
--Features with duplicate names will have only the highest level returned.
--choices is a map of string -> {string choice} made for that string.
function Class:FillFeaturesForLevel(choices, levelNum, extraLevelInfo, secondaryClass, result)
	local levels = {}
	self:FillLevelsUpTo(levelNum, extraLevelInfo, secondaryClass, levels)

	local features = {}
	for i,levelInfo in ipairs(levels) do
		for j,feature in ipairs(levelInfo.features) do
			if feature.typeName == 'CharacterFeature' then
				features[feature.name] = feature
			else
				feature:FillChoice(choices, result)
			end
		end
	end


	for k,feature in pairs(features) do
		result[#result+1] = feature
	end
end

--This is like FillFeaturesForLevel() but it wraps with additional details about the source of the features.
--result is filled with a list of { class = Class object, levels = {list of ints}, feature = CharacterFeature or CharacterChoice }
function Class:FillFeatureDetailsForLevel(choices, levelNum, extraLevelInfo, secondaryClass, result)
	local levels = {}
	local numTutorialLevels = self:FillLevelsUpTo(levelNum, extraLevelInfo, secondaryClass, levels)

	local featureNames = {}
	local features = {}
	for i,levelInfo in ipairs(levels) do
		local levelNum = i - numTutorialLevels
        if levelNum < 1 then
            levelNum = 1
        end

		for j,feature in ipairs(levelInfo.features) do
			if features[feature:CharacterUniqueID()] == nil then
				featureNames[#featureNames+1] = feature:CharacterUniqueID()
				features[feature:CharacterUniqueID()] = {
					class = self,
					levels = {levelNum}, 
					feature = feature,
				}
			else
				--this is a level-up of an existing feature.
				local info = features[feature:CharacterUniqueID()]
				info.levels[#info.levels+1] = levelNum
				info.feature = feature
			end
		end
	end

	for i,featureName in ipairs(featureNames) do
		local info = features[featureName]
		local resultFeatures = {}
		info.feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			local entry = shallow_copy_table(info)
			entry.feature = resultFeature
			result[#result+1] = entry
		end
	end
end

function ClassLevel.CreateNew()
	return ClassLevel.new{
		features = {} --list of CharacterChoice, or CharacterFeature objects
	}
end

function ClassLevel:MergeFeatures(other)
    local features = self:get_or_add("features", {})
    local otherFeatures = other:try_get("features", {})

    for i,feature in ipairs(otherFeatures) do
        features[#features+1] = feature
    end
end

function ClassLevel:VisitAllFeatures(f)
	for _,feature in ipairs(self.features) do
		feature:VisitRecursive(f)
	end
end

function ClassLevel:SetDomain(domainid)
	local domains = self:get_or_add("domains", {})
	if not domains[domainid] then
		domains[domainid] = true
		for _,feature in ipairs(self.features) do
			
			feature:VisitRecursive(function(f)
				f:SetDomain(domainid)
			end)
		end
	end
end

function ClassLevel:ForceDomains(domains)
	for _,feature in ipairs(self.features) do
		feature:VisitRecursive(function(f)
			f:ForceDomains(domains)
		end)
	end
end

function CharacterChoice:SetDomain(domainid)
end

function CharacterChoice:ForceDomains(domains)
end

CharacterChoice.name = "Choice"
CharacterChoice.rulesText = ""
CharacterChoice.description = "Choose a feature"
CharacterChoice.inheritChoice = false

function CharacterChoice:CreateDropdownPanel()
    return nil
end

function CharacterChoice:HasCustomDropdownPanel()
    return false
end

function CharacterChoice:GetSummaryText()
	if self.description == "" then
		--don't really have any rules text.
		return nil
	end
	return string.format("<b>%s</b>.  %s", self.name, self.description)
end

function CharacterChoice:GetDetailedSummaryText()
	return self:GetSummaryText()
end

function CharacterFeatureChoice:GetDetailedSummaryText()
	local summary = self:GetSummaryText()
	local options = self:try_get("options", {})
	local traits = {}
	for _,option in ipairs(options) do
		local descr = option.description or ""
		descr = descr:trim()
		if #descr > 0 then
			local pointValue = ""
			if self:try_get("costsPoints", false) then
				local pointCost = option.pointsCost or 1
				pointValue = string.format(" (%d Point%s)", pointCost, pointCost ~= 1 and "s" or "")
			end
			traits[#traits+1] = string.format("* <b>%s%s:</b> %s", option.name, pointValue, option.description or "")
		end
	end
	if #traits > 0 then
		summary = string.format("%s\n\n%s", summary, table.concat(traits, "\n"))
	end
	return summary
end

function CharacterFeatureList:GetDetailedSummaryText()
	local summary = self:GetSummaryText()
	local options = self:try_get("options", {})
	local traits = {}
	for _,option in ipairs(options) do
		local descr = option.description or ""
		descr = descr:trim()
		if #descr > 0 then
			local pointValue = ""
			if self:try_get("costsPoints", false) then
				local pointCost = option.pointsCost or 1
				pointValue = string.format(" (%d Point%s)", pointCost, pointCost ~= 1 and "s" or "")
			end
			traits[#traits+1] = string.format("* <b>%s%s:</b> %s", option.name, pointValue, option.description or "")
		end
	end
	if #traits > 0 then
		summary = string.format("%s\n\n%s", summary, table.concat(traits, "\n"))
	end
	return summary
end

function CharacterChoice:CharacterUniqueID()
	return self.guid
end

function CharacterChoice:Describe()
	return self.name
end

function CharacterChoice:GetRulesText()
	return self.rulesText
end

function CharacterChoice:GetDescription()
	return self.description
end

function CharacterChoice:Choices(numOption, existingChoices, creature)
	return nil
end

function CharacterChoice:GetOptions(choices)
	return nil
end

function CharacterChoice:NumChoices(creature)
	return 0
end

function CharacterChoice:CanRepeat()
	return false
end

function CharacterChoice:FillChoice(choices, result)
	
end

function CharacterChoice:FillFeats(choices, result)
end

function CharacterChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self
end

function CharacterChoice:VisitRecursive(fn)
	fn(self)
end

function CharacterSubclassChoice:Describe()
	return "Subclass"
end


CharacterFeatureChoice.costsPoints = false
CharacterFeatureChoice.pointsName = "Points"
CharacterFeatureChoice.allowFormerLifeChoices = false

function CharacterFeatureChoice.CreateNew(args)
	local params = {
		guid = dmhub.GenerateGuid(),
		numChoices = 1,
		allowDuplicateChoices = false,
		options = {}, --list of CharacterFeatureList, CharacterFeature or CharacterFeatureChoice objects.
	}

	for k,v in pairs(args or {}) do
		params[k] = v
	end

	return CharacterFeatureChoice.new(params)
end

function CharacterFeatureChoice:VisitRecursive(fn)
	fn(self)

	for i,option in ipairs(self.options) do
		option:VisitRecursive(fn)
	end
end

function CharacterFeatureChoice:GetOptions(choices)
    if self.allowFormerLifeChoices then
        --try to fish out our former life ancestry and include any options from there.
        local raceid = rawget(choices, "raceid")
        if raceid ~= nil then
            local inheritedOptions = {}
            local raceTable = GetTableCached(Race.tableName)
            local ancestry = raceTable[raceid]
            if ancestry ~= nil then
                local formerLifeFeature = ancestry:IsInherited()
                if formerLifeFeature ~= nil then
                    local inheritedid = choices[formerLifeFeature.guid]
                    if inheritedid ~= nil then
                        local inheritedAncestry = raceTable[inheritedid[1] or "none"]
                        if inheritedAncestry ~= nil and inheritedAncestry:GetClassLevel() ~= nil then
                            local features = inheritedAncestry:GetClassLevel().features
                            for i,feature in ipairs(features) do
                                if feature.typeName == "CharacterFeatureChoice" and feature.costsPoints then
                                    --get any feature that costs points from the former life.
                                    for _,option in ipairs(feature.options) do
                                        inheritedOptions[#inheritedOptions+1] = option
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if #inheritedOptions > 0 then
                for _,option in ipairs(self.options) do
                    inheritedOptions[#inheritedOptions+1] = option
                end

                return inheritedOptions
            end 
        end
    end

    if self.inheritChoice and #self.inheritChoice > 0 then
        local options = rawget(self, "_tmp_options")
        if options ~= nil then
            return options
        end

        options = {}
        self._tmp_options = options
        for _,choiceRef in ipairs(self.inheritChoice) do
            local choice = choiceRef:Resolve()
            if choice ~= nil then
                local choiceOptions = choice:GetOptions(choices)
                for _,option in ipairs(choiceOptions) do
                    options[#options+1] = option
                end
            end
        end
        
        for _,option in ipairs(self.options) do
            options[#options+1] = option
        end

        return options
    end

    return self.options
end

function CharacterFeatureChoice:Choices(numOption, existingChoices, creature)

	if numOption > #existingChoices+1 then
		return nil
	end

    local options = self:GetOptions(creature:GetLevelChoices())

	local usePoints = self:try_get("costsPoints")
	local pointsSpend = 0
	local thisFeaturePointSpend = 0
	local pointsAvailable = 0

	if usePoints then
		pointsAvailable = self:NumChoices(creature)
		for choiceIndex,choice in ipairs(existingChoices) do
			for i,feature in ipairs(options) do
				if choice == feature.guid then
					if choiceIndex == numOption then
						thisFeaturePointSpend = feature:try_get("pointsCost", 1)
					end
					pointsSpend = pointsSpend + feature:try_get("pointsCost", 1)
					break
				end
			end
		end


	end

	local result = {}

	--count how many available options there are. If there are zero, return nil
	--to indicate that we shouldn't show a dropdown with all greyed-out options.
	local numAvailableOptions = 0

	for i,feature in ipairs(options) do
		local canChoose = true

		if self.allowDuplicateChoices == false then
			for j,choice in ipairs(existingChoices) do
				if j ~= numOption and choice == feature.guid then
					--eliminate this duplicate choice.
					canChoose = false
				end
			end
		end

		--make sure the creature meets the pre-requisites for this feature.
		for i,prerequisite in ipairs(feature:try_get("prerequisites", {})) do
			if not prerequisite:Met(creature) then
				canChoose = false
			end
		end

		local isDisabled = false
		local classes = nil

		if usePoints and pointsSpend - thisFeaturePointSpend + feature:try_get("pointsCost", 1) > pointsAvailable then
			isDisabled = true
			classes = {"disabled"}
		end

		if canChoose then
			if not isDisabled then
				numAvailableOptions = numAvailableOptions + 1
			end

			local text = feature.name
			-- if usePoints then
			-- 	local cost = feature:try_get("pointsCost", 1)
			-- 	text = string.format("%s (%d %s)", text, cost, self.pointsName)
			-- end
			result[#result+1] = {
				id = feature.guid,
				text = text,
				description = feature.description,
				classes = classes,
				pointsCost = feature:try_get("pointsCost", 1),
				modifiers = feature:try_get("modifiers"),
                hasCustomPanel = feature:HasCustomDropdownPanel(),
                panel = function()
                    return feature:CreateDropdownPanel(text)
                end,
			}
		end
	end

	if numOption > #existingChoices and numAvailableOptions == 0 then
		return nil
	end

	return result
end

function CharacterFeatureChoice:NumChoices(creature)
	local result = ExecuteGoblinScript(self.numChoices, GenerateSymbols(creature), 1, "Number of choices")
	return result
end

function CharacterFeatureChoice:CanRepeat()
	return self.allowDuplicateChoices
end

function CharacterFeatureChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local options = self:GetOptions(choices)

	for j,choiceid in ipairs(choiceidList) do
		for i,option in ipairs(options) do
			if choiceid == option.guid then
				option:FillChoice(choices, result)
			end
		end
	end
end

function CharacterFeatureChoice:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

    local options = self:GetOptions(choices)

	for j,choiceid in ipairs(choiceidList) do
		for i,option in ipairs(options) do
			if choiceid == option.guid then
				option:FillFeaturesRecursive(choices, result)
			end
		end
	end
end

-------------------------------------------------
-- CharacterSkillsChoice and CharacterToolsChoice are specialized generators designed to allow choices to fill in for duplicate tool/skill proficiencies.
-------------------------------------------------

RegisterGameType("CharacterSkillsChoice", "CharacterChoice")

CharacterSkillsChoice.name = "Extra Proficiency"
CharacterSkillsChoice.guid = "duplicate-skills-choice"
CharacterSkillsChoice.description = "You received the same skill from multiple sources. Choose a different skill instead."

function CharacterSkillsChoice.Create(quantity, skillDuplicates)
	return CharacterSkillsChoice.new{
		quantity = quantity,
		existingSkills = skillDuplicates,
	}
end

function CharacterSkillsChoice:NumChoices(creature)

	local result = ExecuteGoblinScript(self.quantity, creature, 1, "Number of choices")
	return result
end

function CharacterSkillsChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

	local skills = {}
	for i,id in ipairs(choiceidList) do
		skills[id] = true
	end

	result[#result+1] = CharacterFeature.new{
		guid = "duplicate-skills-choice",
		name = "Choose Skills",
		source = "Character Feature",
		description = "You received the same skill from multiple sources. Choose a different skill instead.",
		modifiers = {
			CharacterModifier.new {
				behavior = 'proficiency',
				guid = 'skills-duplicate-choice',
				name = "Skills",
				subtype = 'skill',
				skills = skills,
				proficiency = "proficient",
			}
		},
	}
end

function CharacterSkillsChoice:Choices(numOption, existingChoices, creature)
	if numOption > #existingChoices+1 then
		return nil
	end

	local result = {}
	for i,skill in ipairs(Skill.SkillsInfo) do
		if self.existingSkills[skill.id] == nil then
			local canChoose = true
			for j,existing in ipairs(existingChoices) do
				if j ~= numOption and existing == skill.id then
					--eliminate this duplicate choice.
					canChoose = false
				end
			end

			if canChoose then
				result[#result+1] = {
					id = skill.id,
					text = skill.name,
				}
			end
		end
	end

	return result
end

RegisterGameType("CharacterToolsChoice", "CharacterChoice")

CharacterToolsChoice.name = "Extra Tools Proficiency"
CharacterToolsChoice.guid = "duplicate-tools-choice"
CharacterToolsChoice.description = "You received the same tool proficiency from multiple sources. Choose a different tool proficiency instead."

function CharacterToolsChoice.Create(quantity, skillDuplicates)
	return CharacterToolsChoice.new{
		quantity = quantity,
		existingSkills = skillDuplicates,
	}
end

function CharacterToolsChoice:NumChoices(creature)
	local result = ExecuteGoblinScript(self.quantity, creature, 1, "Number of choices")
	return result
end

function CharacterToolsChoice:FillChoice(choices, result)
	local choiceidList = choices[self.guid]
	if choiceidList == nil then
		return
	end

	local skills = {}
	for i,id in ipairs(choiceidList) do
		if i <= self.quantity then
			skills[id] = true
		end
	end

	result[#result+1] = CharacterFeature.new{
		guid = "duplicate-tools-choice",
		name = "Choose Skills",
		source = "Character Feature",
		description = "You received the same skill from multiple sources. Choose a different skill instead.",
		modifiers = {
			CharacterModifier.new {
				behavior = 'proficiency',
				guid = 'tools-duplicate-choice',
				name = "Skills",
				subtype = 'equipment',
				skills = skills,
				proficiency = 'proficient',
			}
		},
	}
end

function CharacterToolsChoice:Choices(numOption, existingChoices, creature)
	if numOption > #existingChoices+1 then
		return nil
	end

	local result = {}

	local equipment = GetTableCached("tbl_Gear")
	local cats = GetTableCached("equipmentCategories")
	for k,equip in pairs(equipment) do
		if (not equip:try_get("hidden")) and equip:try_get("equipmentCategory") and cats[equip.equipmentCategory] and cats[equip.equipmentCategory].allowIndividualProficiency and cats[equip.equipmentCategory].isTool and self.existingSkills[k] == nil then
			local canChoose = true
			for j,existing in ipairs(existingChoices) do
				if j ~= numOption and existing == k then
					--eliminate this duplicate choice.
					canChoose = false
				end
			end

			if canChoose then
				result[#result+1] = {
					id = k,
					text = equip.name,
				}
			end
		end
	end

	table.sort(result, function(a,b) 
		return a.text < b.text
	end)

	return result
end

function CharacterSubclassChoice.CreateNew(args)
	local params = {
		guid = dmhub.GenerateGuid(),
	}

	for k,arg in pairs(args) do
		params[k] = arg
	end

	return CharacterSubclassChoice.new(params)
end

--- @return Panel|nil
local function renderSubclass(item)
	local fd = {}
	item:FillFeatureDetailsForLevel({}, 1, nil, "nonprmiary", fd)
	if #fd == 0 then return nil end
	local textItems = {}
	for _,item in ipairs(fd) do
		local s = item.feature:GetDetailedSummaryText()
		if s ~= nil and #s > 0 then
			textItems[#textItems+1] = s
		end
	end
	local text = table.concat(textItems, "\n")
	return gui.Label{
		height = "auto",
		width = "96%",
		textAlignment = "topleft",
		text = text,
	}
end

function CharacterSubclassChoice:Choices(numOption, existingChoices, creature)
	local result = {}

	local subclassesTable = GetTableCached("subclasses")
	for k,subclass in unhidden_pairs(subclassesTable) do
		if subclass.primaryClassId == self.classid then
			if GoblinScriptTrue(ExecuteGoblinScript(subclass:try_get("prerequisite", ""), GenerateSymbols(creature), 1, "Subclass Prerequisite")) then
				result[#result+1] = {
					id = k,
					text = subclass.name,
					description = subclass.details,
					-- TODO: If building out descriptions gets prioritized render = function() return renderSubclass(subclass) end,
				}
			end
		end
	end

	return result
end

function CharacterSubclassChoice:GetOptions(choices, creature)
	local options = {}
	local choices = self:Choices(nil, choices, creature)
	for _,item in ipairs(choices) do
		options[#options+1] = {
			guid = item.id,
			name = item.text,
			description = item.description,
			unique = true,
			render = item.render,
		}
	end
	return options
end

function CharacterSubclassChoice:NumChoices(creature)
	return 1
end

CharacterFeatureList.name = "Features"
CharacterFeatureList.description = "List of Features"

function CharacterFeatureList:SetDomain(domainid)
end

function CharacterFeatureList:GetSummaryText()
	if self:GetRulesText() == "" then
		return nil
	end

	return string.format("<b>%s.</b>  %s", self.name, self:GetRulesText())
end


function CharacterFeatureList:GetRulesText()
	return self.description
end

function CharacterFeatureList:GetDescription()
	return self.description
end

function CharacterFeatureList:HasCustomDropdownPanel()
    return false
end

function CharacterFeatureList:CreateDropdownPanel()
    return nil
end

function CharacterFeatureList.CreateNew()
	return CharacterFeatureList.new{
		guid = dmhub.GenerateGuid(),
		features = {} --list of CharacterChoice, or CharacterFeature objects
	}
end

function CharacterFeatureList:ForceDomains(domains)
	for _,feature in ipairs(self.features) do
		feature:VisitRecursive(function(f)
			f:ForceDomains(domains)
		end)
	end
end

function CharacterFeatureList:Choices(numOption, existingChoices)
	return nil
end

function CharacterFeatureList:NumChoices(creature)
	return 0
end

function CharacterFeatureList:FillChoice(choices, result)
	for i,feature in ipairs(self.features) do
		feature:FillChoice(choices, result)
	end
end

function CharacterFeatureList:FillFeats(choices, result)
end

function CharacterFeatureList:FillFeaturesRecursive(choices, result)
	result[#result+1] = self

	for i,feature in ipairs(self.features) do
		feature:FillFeaturesRecursive(choices, result)
	end
end

function CharacterFeatureList:VisitRecursive(fn)
	fn(self)
	for i,feature in ipairs(self.features) do
		feature:VisitRecursive(fn)
	end
end

function CharacterFeatureList:Describe()
	return self.name
end

--when tables load, add class levels to creature symbols. e.g. "warlock level".
local initClasses = false

dmhub.RegisterEventHandler("refreshTables", function()
	if initClasses then
		return
	end

	initClasses = true
	
	local classesTable = dmhub.GetTable('classes')

	for classid,classInfo in pairs(classesTable) do
		if not classInfo:try_get("hidden", false) then
			local key = classInfo.name
			key = string.gsub(key, "%s+", "")
			key = string.lower(key)
			key = key .. "level"

			local prettyName = string.format("%s Level", classInfo.name)

			local fn = function(c)
				return c:GetLevelInClass(classid)
			end

			creature.lookupSymbols[key] = fn
			character.lookupSymbols[key] = fn

			creature.helpSymbols[key] = {
				name = prettyName,
				type = "number",
				desc = string.format("The number of levels the character has in the %s class.", classInfo.name),
				domain = classInfo:Domain(),
			}
		end

	end

end)
