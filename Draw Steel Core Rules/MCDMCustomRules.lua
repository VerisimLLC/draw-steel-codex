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
    -- the same FillFeatureDetails entry point. Pass ourselves so features
    -- with unmet prerequisites (e.g. a minimum level) aren't offered.
    for _,template in ipairs(self:GetActiveTemplates()) do
        template:FillFeatureDetails(levelChoices, result, self)
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

--- Per-purchase breakdown of a points pool: { name, cost, optionGuid,
--- choiceName, choiceGuid, parent } per selected option, where parent is the template,
--- feat or monster group granting the choice. Static so hot-reloaded tokens
--- can call it.
--- @param c creature
--- @param pointsName string
--- @return table[]
function creature.PointsSpentBreakdown(c, pointsName)
    local result = {}
    if c == nil or pointsName == nil or pointsName == "" then
        return result
    end
    local targetName = string.lower(tostring(pointsName))
    local levelChoices = c:GetLevelChoices()
    for _,entry in ipairs(c:GetBuilderChoiceFeatures()) do
        local feature = entry.feature
        if feature ~= nil and feature.typeName == "CharacterFeatureChoice" and feature:try_get("costsPoints", false) then
            local name = feature:try_get("pointsName", "")
            if name == nil or name == "" then
                name = DEFAULT_POINTS_NAME
            end
            if string.lower(name) == targetName then
                for _,selectedId in ipairs(levelChoices[feature.guid] or {}) do
                    for _,option in ipairs(feature:try_get("options", {})) do
                        if option.guid == selectedId then
                            result[#result+1] = {
                                name = option.name,
                                cost = option.pointsCost or 1,
                                optionGuid = option.guid,
                                choiceName = feature:try_get("name", ""),
                                choiceGuid = feature.guid,
                                parent = entry.feat or entry.monsterGroup,
                            }
                            break
                        end
                    end
                end
            end
        end
    end
    return result
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

--[[
    Rival Abilities (Monsters p.232): a rival can replace its signature ability
    with a signature ability from its class, or from any kit for the classes in
    RIVAL_KIT_CLASSES. The replacement deals extra damage equal to the rival's
    level and targets two creatures if it normally targets one.

    The options are built per rival from its class, so this choice lives once in
    the Rival Ancestries template. A stored pick is "rivalsig:<ability guid>",
    which is enough to rebuild the granted ability without the creature.
]]
--- @class CharacterRivalAbilityChoice: CharacterFeatureChoice
--- @field new fun(o?: table): CharacterRivalAbilityChoice
CharacterRivalAbilityChoice = RegisterGameType("CharacterRivalAbilityChoice", "CharacterFeatureChoice")

CharacterRivalAbilityChoice.name = "Rival Abilities"
CharacterRivalAbilityChoice.numChoices = "1"

local RIVAL_OPTION_PREFIX = "rivalsig:"
local RIVAL_ORIGINAL_ID = "rivalsig:original"

--Which rivals may also take a kit signature ability. The book lists the fury,
--shadow, and tactician; the censor is a house addition.
local RIVAL_KIT_CLASSES = { Fury = true, Shadow = true, Tactician = true, Censor = true }

--- The rival's class name from its stat block, e.g. "Rival Conduit E3" -> "Conduit".
--- @param creature creature
--- @return string|nil
local function _rivalClassName(creature)
    local monsterType = creature:try_get("monster_type", "")
    local className = string.match(monsterType, "^Rival (.+)$")
    if className == nil then return nil end
    return (string.gsub(className, "%s+E%d+$", ""))
end

--- The stat block's own signature ability, if it has one.
--- @param creature creature
--- @return ActivatedAbility|nil
local function _rivalOwnSignature(creature)
    for _,ability in ipairs(creature:try_get("innateActivatedAbilities") or {}) do
        if ability:try_get("categorization") == "Signature Ability" then
            return ability
        end
    end
    return nil
end

--- Signature abilities granted by a class's level-1 choices.
--- @param class Class
--- @return ActivatedAbility[]
local function _classSignatureAbilities(class)
    local result = {}
    for _,level in pairs(class:try_get("levels") or {}) do
        for _,feature in ipairs(level.features or {}) do
            for _,option in ipairs(feature:try_get("options") or {}) do
                for _,modifier in ipairs(option:try_get("modifiers") or {}) do
                    local ability = modifier:try_get("activatedAbility")
                    if ability ~= nil and ability:try_get("categorization") == "Signature Ability" then
                        result[#result+1] = ability
                    end
                end
            end
        end
    end
    return result
end

--- Every class and kit signature ability, keyed by guid, with where it came from.
--- @return table<string, {ability: ActivatedAbility, className: string|nil, kitName: string|nil}>
local function _rivalAbilityIndex()
    local index = {}
    for _,class in unhidden_pairs(GetTableCached("classes")) do
        for _,ability in ipairs(_classSignatureAbilities(class)) do
            index[ability.guid] = { ability = ability, className = class.name }
        end
    end
    for _,kit in unhidden_pairs(GetTableCached(Kit.tableName)) do
        local ability = kit:try_get("signatureAbility")
        if ability ~= nil and ability:try_get("guid") ~= nil then
            index[ability.guid] = { ability = ability, kitName = kit.name }
        end
    end
    return index
end

--Built options are cached by id: the builder asks for them every refresh.
local g_rivalOptionCache = {}

--- The option for one replacement ability: grants the rival version of the
--- ability and suppresses the stat block's own signature ability.
--- @param entry {ability: ActivatedAbility, className: string|nil, kitName: string|nil}
--- @return CharacterFeature
local function _rivalReplacementOption(entry)
    local id = RIVAL_OPTION_PREFIX .. entry.ability.guid
    local cached = g_rivalOptionCache[id]
    if cached ~= nil then return cached end

    local ability = DeepCopy(entry.ability)
    ability.categorization = "Signature Ability"

    local notes = {"+Level damage"}
    if tostring(ability:try_get("numTargets", "1")) == "1" and ability:try_get("targetType") == "target" then
        ability.numTargets = "2"
        notes[#notes+1] = "targets 2"
    end

    --Extra damage equal to the rival's level, the way Ability Customisation adds damage.
    local behaviorGuid = dmhub.GenerateGuid()
    local powerMod = CharacterModifier.new{
        guid = dmhub.GenerateGuid(),
        sourceguid = behaviorGuid,
        name = "Rival Ability",
        description = "",
        behavior = "power",
        domains = {},
    }
    CharacterModifier.TypeInfo.power.init(powerMod)
    powerMod.rollType = "ability_power_roll"
    powerMod.activationCondition = true
    powerMod.damageModifier = "Level"
    ability.behaviors[#ability.behaviors+1] = ActivatedAbilityModifyPowerRollBehavior.new{
        guid = behaviorGuid,
        modifier = powerMod,
    }

    local source = entry.kitName and (entry.kitName .. " kit") or (entry.className or "")
    local option = CharacterFeature.new{
        guid = id,
        name = ability.name,
        description = string.format("%s signature ability (%s).", source, table.concat(notes, ", ")),
        source = "Rival Abilities",
        implementation = ability:try_get("implementation", 1),
        --The builder lists class abilities, then kit abilities, each as its own group.
        builderGroup = entry.kitName and "Kit Abilities" or "Class Abilities",
        order = (entry.kitName and "3 " or "2 ") .. ability.name,
        modifiers = {
            CharacterModifier.new{
                guid = id .. ":grant",
                name = ability.name,
                description = "",
                behavior = "activated",
                source = "Rival Abilities",
                sourceguid = id,
                activatedAbility = ability,
            },
            CharacterModifier.new{
                guid = id .. ":suppress",
                name = "Rival Abilities",
                description = "",
                behavior = "suppressabilities",
                source = "Rival Abilities",
                sourceguid = id,
                --Hide other signature abilities (the stat block's own). No explanation, so
                --it is removed rather than shown greyed out.
                abilityFilter = string.format('Ability.Categorization != "Signature Ability" or Ability.Name = "%s"', ability.name),
            },
        },
    }
    g_rivalOptionCache[id] = option
    return option
end

--- Display-only option for the stat block's own ability; picking it changes nothing.
--- @param own ActivatedAbility
--- @return CharacterFeature
local function _rivalOriginalOption(own)
    return CharacterFeature.new{
        guid = RIVAL_ORIGINAL_ID,
        name = own.name,
        description = "The rival's own signature ability.",
        source = "Rival Abilities",
        implementation = own:try_get("implementation", 1),
        builderGroup = "Class Abilities",
        order = "1",
        modifiers = {
            CharacterModifier.new{
                guid = RIVAL_ORIGINAL_ID .. ":show",
                name = own.name,
                description = "",
                behavior = "activated",
                source = "Rival Abilities",
                sourceguid = RIVAL_ORIGINAL_ID,
                activatedAbility = own,
            },
        },
    }
end

--- Options for applying picks: only the stored replacements, no creature needed.
--- @param choices table levelChoices
--- @return CharacterFeature[]
function CharacterRivalAbilityChoice:GetOptions(choices, creature)
    if creature ~= nil then
        return self:GetEntries(creature)
    end
    local result = {}
    local picked = choices[self.guid]
    if picked == nil then return result end
    local index = nil
    for _,id in ipairs(picked) do
        if id ~= RIVAL_ORIGINAL_ID and string.sub(id, 1, #RIVAL_OPTION_PREFIX) == RIVAL_OPTION_PREFIX then
            local cached = g_rivalOptionCache[id]
            if cached == nil then
                index = index or _rivalAbilityIndex()
                local entry = index[string.sub(id, #RIVAL_OPTION_PREFIX + 1)]
                cached = entry and _rivalReplacementOption(entry)
            end
            result[#result+1] = cached
        end
    end
    return result
end

--- Builder list for this rival: its own ability first, then its class's
--- signature abilities, then kit signature abilities where allowed.
--- @param creature creature
--- @return CharacterFeature[]
function CharacterRivalAbilityChoice:GetEntries(creature)
    local result = {}
    local own = _rivalOwnSignature(creature)
    if own ~= nil then
        result[#result+1] = _rivalOriginalOption(own)
    end

    local className = _rivalClassName(creature)
    if className == nil then return result end

    local classEntries, kitEntries = {}, {}
    for _,entry in pairs(_rivalAbilityIndex()) do
        if entry.className == className then
            classEntries[#classEntries+1] = entry
        elseif entry.kitName ~= nil and RIVAL_KIT_CLASSES[className] then
            kitEntries[#kitEntries+1] = entry
        end
    end
    local byName = function(a, b) return a.ability.name < b.ability.name end
    table.sort(classEntries, byName)
    table.sort(kitEntries, byName)
    for _,entry in ipairs(classEntries) do result[#result+1] = _rivalReplacementOption(entry) end
    for _,entry in ipairs(kitEntries) do result[#result+1] = _rivalReplacementOption(entry) end
    return result
end

function CharacterRivalAbilityChoice:Choices(numOption, existingChoices, creature)
    local result = {}
    for _,option in ipairs(self:GetEntries(creature)) do
        result[#result+1] = {
            id = option.guid,
            text = option.name,
            description = option.description,
            modifiers = option.modifiers,
        }
    end
    return result
end

--Builder hooks (looked up on the type table, so plain functions with self first).
--Until the Director picks something, the stat block's own ability shows as chosen.
function CharacterRivalAbilityChoice.GetSelected(self, creature)
    local picked = creature:GetLevelChoices()[self.guid]
    if picked == nil then
        return { RIVAL_ORIGINAL_ID }
    end
    return picked
end

--A tactician or fury can have 30+ options, so offer the builder's search box.
function CharacterRivalAbilityChoice.OfferFilter()
    return true
end

--Removing the implicit "own ability" pick stores an empty list, which frees the
--slot for a replacement.
function CharacterRivalAbilityChoice.RemoveSelection(self, creature, option)
    local levelChoices = creature:GetLevelChoices()
    if levelChoices[self.guid] == nil and option ~= nil and option.guid == RIVAL_ORIGINAL_ID then
        levelChoices[self.guid] = {}
        return true
    end
    return false
end