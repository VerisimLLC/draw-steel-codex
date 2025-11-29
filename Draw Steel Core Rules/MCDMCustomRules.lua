local mod = dmhub.GetModLoading()


function creature:Kit()
    return nil
end

function character:KitID()
    return self:try_get("kitid")
end

function character:Kit()
	local table = dmhub.GetTable(Kit.tableName)
	local kit = table[self:KitID()]
	if kit ~= nil then

		if self:has_key("kitid2") and self:GetNumberOfKits() > 1 then
			local kit2 = table[self.kitid2]
			if kit2 ~= nil then
				kit = Kit.CombineKits(self, kit, kit2)
			end
		end

		return kit
	elseif self:has_key("kitid2") and self:GetNumberOfKits() > 1 then
		return table[self.kitid2]
	end

	return nil
end

--how we calculate the basic features a character gets.
function character:GetClassFeatures(options)
	options = options or {}
	local result = {}

	local levelChoices = self:GetLevelChoices()

	local characterType = self:CharacterType()
	if characterType ~= nil then
		characterType:FillClassFeatures(levelChoices, result)
	end

	local race = self:Race()
	if race ~= nil then
		race:FillClassFeatures(self:CharacterLevel(), levelChoices, result)
	end

	local subrace = self:Subrace()
	if subrace ~= nil then
		subrace:FillClassFeatures(self:CharacterLevel(), levelChoices, result)
	end

    local career = self:Background()
    if career ~= nil then
        career:FillClassFeatures(levelChoices, result)
    end

    local culture = self:GetCulture()
    if culture ~= nil and culture.init then
        culture:FillClassFeatures(self:GetLevelChoices(), result)
    end

	local kit = self:Kit()
	if kit ~= nil then
		kit:FillClassFeatures(self, levelChoices, result)
	end

	for i,entry in ipairs(self:GetClassesAndSubClasses()) do
		if i == 1 then
			result[#result+1] = entry.class:GetPrimaryFeature()
		end


		entry.class:FillFeaturesForLevel(levelChoices, entry.level, self:ExtraLevelInfo(), i ~= 1, result)
	end

    local complications = self:Complications()
	for _, complication in ipairs(complications) do
		complication:FillClassFeatures(levelChoices, result)
	end

	local titles = self:Titles()
	for _, title in ipairs(titles) do
		title:FillClassFeatures(levelChoices, result)
	end

	for i,featid in ipairs(self:try_get("creatureFeats", {})) do
		local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
		local featInfo = featTable[featid]
		if featInfo ~= nil then
			featInfo:FillClassFeatures(levelChoices, result)
		end
	end

	local passedResult = {}
	for _, feature in ipairs(result) do
		--make sure the creature meets the pre-requisites for this feature.
		local prerequisites = feature:try_get("prerequisites", {})
		if prerequisites == nil or #prerequisites == 0 then
			passedResult[#passedResult+1] = feature
		else
			for i,prerequisite in ipairs(prerequisites) do
				if prerequisite:Met(self) then
					passedResult[#passedResult+1] = feature
				end
			end
		end
	end

	return passedResult
end


--returns a list of { class/race/background/characterType = Class/Race/Background, levels = {list of ints}, feature = CharacterFeature or CharacterChoice }
function character:GetClassFeaturesAndChoicesWithDetails()
	local result = {}

	local characterType = self:CharacterType()
	if characterType ~= nil then
		characterType:FillFeatureDetails(self:GetLevelChoices(), result)
	end

	local race = self:Race()
	if race ~= nil then
		race:FillFeatureDetails(self:CharacterLevel(), self:GetLevelChoices(), result)
	end

	local subrace = self:Subrace()
	if subrace ~= nil then
		subrace:FillFeatureDetails(self:CharacterLevel(), self:GetLevelChoices(), result)
	end

    local career = self:Background()
    if career ~= nil then
        career:FillFeatureDetails(self:GetLevelChoices(), result)
    end

    local culture = self:GetCulture()
    if culture ~= nil and culture.init then
        culture:FillFeatureDetails(self:GetLevelChoices(), result)
    end

	local kit = self:Kit()
	if kit ~= nil then
		kit:FillFeatureDetails(self, self:GetLevelChoices(), result)
	end

	local classFeatures = {}

	for i,entry in ipairs(self:GetClassesAndSubClasses()) do
		entry.class:FillFeatureDetailsForLevel(self:GetLevelChoices(), entry.level, self:ExtraLevelInfo(), i ~= 1, classFeatures)
	end



	for _,f in ipairs(classFeatures) do
		result[#result+1] = f
	end

    local complications = self:Complications()
    for _, complication in ipairs(complications) do
        complication:FillFeatureDetails(self:GetLevelChoices(), result)
    end

	local titles = self:Titles()
	for _, title in ipairs(titles) do
		title:FillFeatureDetails(self:GetLevelChoices(), result)
	end

	for i,featid in ipairs(self:try_get("creatureFeats", {})) do
		local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
		local featInfo = featTable[featid]
		if featInfo ~= nil then
			featInfo:FillFeatureDetails(self:GetLevelChoices(), result)
		end
	end

	local passedResult = {}
	for _, feature in ipairs(result) do
		local prerequisites = feature.feature:try_get("prerequisites", {})
		if prerequisites == nil or #prerequisites == 0 then
			passedResult[#passedResult+1] = feature
		else
			for i,prerequisite in ipairs(prerequisites) do
				if prerequisite:Met(self) then
					passedResult[#passedResult+1] = feature
				end
			end
		end
	end

	return passedResult
end

--resource grouping options.
CharacterResource.groupingOptions = {
    {
        id = "Class Specific",
        text = "General",
    },
    {
        id = "Actions",
        text = "Actions",
    },
    {
        id = "Hidden",
        text = "Hidden",
    },
}