local mod = dmhub.GetModLoading()


function creature:Kit()
    return nil
end

function character:KitID()
    return self:try_get("kitid")
end

function character:Kit()
	local table = GetTableCached(Kit.tableName)
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

	-- Kit features are gathered last so we can check whether any prior feature
	-- grants kit access.
	local hasKitAccess = false
	for _,feature in ipairs(result) do
		for _,m in ipairs(feature.modifiers) do
			if m.behavior == "kitaccess" and m.kitType ~= "none" then
				hasKitAccess = true
				break
			end
		end
		if hasKitAccess then break end
	end

	if hasKitAccess then
		local kit = self:Kit()
		if kit ~= nil then
			kit:FillClassFeatures(self, levelChoices, result)
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

--- Returns an array of { feature = CharacterChoice, ... } entries for every
--- CharacterChoice-derived feature reachable from this creature's "catch-all"
--- sources -- the ones not covered by the per-source builder tabs.
---
--- Common sources (creature-level): characterFeatures, creatureFeats,
--- creatureTemplates. Subclasses add more via FillExtraBuilderChoiceFeatures:
---   monster -> monsterGroup traits
---   character -> CharacterType (chartypeid) features
--- @return table[]
function creature:GetBuilderChoiceFeatures()
    local result = {}
    local levelChoices = self:GetLevelChoices()

    -- characterFeatures: direct features stored on the creature.
    for _,feature in ipairs(self:try_get("characterFeatures", {})) do
        local nested = {}
        feature:FillFeaturesRecursive(levelChoices, nested)
        for _,f in ipairs(nested) do
            result[#result+1] = { feature = f }
        end
    end

    -- creatureFeats: feats picked via AddFeat. Same FillFeatureDetails path
    -- the character sheet uses.
    local featTable = dmhub.GetTable(CharacterFeat.tableName) or {}
    for _,featid in ipairs(self:try_get("creatureFeats", {})) do
        local feat = featTable[featid]
        if feat ~= nil then
            feat:FillFeatureDetails(levelChoices, result)
        end
    end

    -- creatureTemplates: templates inherit from CharacterFeat and expose
    -- the same FillFeatureDetails entry point.
    for _,template in ipairs(self:GetActiveTemplates()) do
        template:FillFeatureDetails(levelChoices, result)
    end

    self:FillExtraBuilderChoiceFeatures(result, levelChoices)

    local filtered = {}
    for _,entry in ipairs(result) do
        local feature = entry.feature
        if feature and feature.IsDerivedFrom and feature.IsDerivedFrom("CharacterChoice") then
            filtered[#filtered+1] = entry
        end
    end
    return filtered
end

--- Default no-op hook. Subclasses (monster, character) override to add
--- their own sources.
--- @param result table
--- @param levelChoices table
function creature:FillExtraBuilderChoiceFeatures(result, levelChoices)
end

--- character override: pull in CharacterType-supplied features. Class/race/
--- career/etc. features are already handled by their own builder tabs and
--- intentionally not duplicated here.
--- @param result table
--- @param levelChoices table
function character:FillExtraBuilderChoiceFeatures(result, levelChoices)
    local characterType = self:CharacterType()
    if characterType ~= nil then
        characterType:FillFeatureDetails(levelChoices, result)
    end
end

--- @return boolean true if this creature has any CharacterChoice-derived
--- features that the builder's catch-all Choices section should surface.
function creature:HasBuilderChoices()
    return #self:GetBuilderChoiceFeatures() > 0
end

--- Set true to log [PointsSpent] diagnostics tracing how GetPointsSpentByName
--- resolves a points pool (which feature choices it sees, their pointsName,
--- and what matched). Left in place as a debugging aid; flip to true to trace.
local DEBUG_POINTS_SPENT = false

--- The display name a points pool falls back to when a CharacterFeatureChoice
--- has costsPoints enabled but no explicit "pointsName" set. Kept in sync with
--- CBFeatureWrapper.DEFAULT_POINTS_NAME in FeatureCache.lua.
local DEFAULT_POINTS_NAME = "Points"

--- Totals the points spent on a named points pool across a list of feature
--- entries (each entry is a { feature = CharacterChoice } table). A points
--- pool is named via the "pointsName" field of a CharacterFeatureChoice that
--- has costsPoints enabled (an unset/blank name resolves to DEFAULT_POINTS_NAME);
--- each selected option spends its "pointsCost" (defaulting to 1).
--- @param entries table[] List of { feature = ... } entries to scan.
--- @param levelChoices table The creature's levelChoices map.
--- @param targetName string Lowercased points-pool name to match.
--- @return number
local function _sumPointsSpent(entries, levelChoices, targetName)
    local total = 0
    if DEBUG_POINTS_SPENT then
        print(string.format("[PointsSpent] resolving pool %q across %d feature entries",
            tostring(targetName), #entries))
    end
    for _,entry in ipairs(entries) do
        local feature = entry.feature
        if feature ~= nil and feature.typeName == "CharacterFeatureChoice" then
            local costsPoints = feature:try_get("costsPoints", false)
            local pointsName = feature:try_get("pointsName", "")
            if pointsName == nil or pointsName == "" then
                pointsName = DEFAULT_POINTS_NAME
            end
            local isMatch = costsPoints and string.lower(pointsName) == targetName

            if DEBUG_POINTS_SPENT and costsPoints then
                local sel = levelChoices[feature.guid]
                print(string.format("[PointsSpent]   choice '%s' guid=%s pointsName=%q selectedCount=%s match=%s",
                    tostring(feature:try_get("name", "?")), tostring(feature.guid),
                    tostring(pointsName), sel and tostring(#sel) or "nil", tostring(isMatch)))
            end

            if isMatch then
                local selectedList = levelChoices[feature.guid]
                if selectedList ~= nil then
                    for _,selectedId in ipairs(selectedList) do
                        for _,option in ipairs(feature:try_get("options", {})) do
                            if option.guid == selectedId then
                                total = total + (option.pointsCost or 1)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    if DEBUG_POINTS_SPENT then
        print(string.format("[PointsSpent] pool %q total = %d", tostring(targetName), total))
    end
    return total
end

--- Returns how many character-build points of the named pool have been spent
--- on this creature. Points pools are named via the "pointsName" field of a
--- CharacterFeatureChoice that has costsPoints enabled. Matching is
--- case-insensitive. The base creature implementation scans the catch-all
--- builder-choice sources (characterFeatures, feats, templates, plus any
--- subclass-specific sources such as monsterGroup traits).
--- @param pointsName string The display name of the points pool to total.
--- @return number
function creature:GetPointsSpentByName(pointsName)
    if pointsName == nil or pointsName == "" then
        return 0
    end

    return _sumPointsSpent(
        self:GetBuilderChoiceFeatures(),
        self:GetLevelChoices(),
        string.lower(tostring(pointsName)))
end

--- character override: point pools most commonly live on class/race/career/
--- etc. features, which are surfaced by GetClassFeaturesAndChoicesWithDetails
--- rather than the catch-all builder-choice sources.
--- @param pointsName string The display name of the points pool to total.
--- @return number
function character:GetPointsSpentByName(pointsName)
    if pointsName == nil or pointsName == "" then
        return 0
    end

    return _sumPointsSpent(
        self:GetClassFeaturesAndChoicesWithDetails(),
        self:GetLevelChoices(),
        string.lower(tostring(pointsName)))
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