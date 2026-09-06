local mod = dmhub.GetModLoading()

--- @class Race: GameType
--- @field name string Display name (e.g. "Elf", "Human").
--- @field tableName string Data table name ("races").
--- @field height number Default height in feet.
--- @field weight string Weight description string.
--- @field lifeSpan string Life span description string.
--- @field size string Default creature size (e.g. "Medium").
--- @field moveSpeeds table<string, number> Default movement speeds (e.g. {walk = 30}).
--- @field portraitid string Asset id for the race portrait image.
--- @field subrace boolean If true, this is a subrace rather than a base race.
--- @field details string Short lore summary.
--- @field lore string Long-form lore text.
Race = RegisterGameType("Race")

local defaultRace = nil

Race.tableName = "races"
Race.height = 6
Race.weight = ""
Race.lifeSpan = ""
Race.size = "Medium"
Race.moveSpeeds = {
	walk = 30,
}

--portrait used in previews of the race.
Race.portraitid = ""

Race.name = "New Ancestry"
Race.subrace = false
Race.details = ""
Race.lore = ""

Race._tmp_domains = false

--- @return Race
function Race.CreateNew()
	return Race.new{
	}
end

--- @return string
function Race:Describe()
	return self.name
end

--- @return string
function Race:Domain()
	return string.format("race:%s", self.id)
end

function Race:EnsureDomain()
	if self._tmp_domains then
		return
	end

	self._tmp_domains = true
	local domain = self:Domain()
	self:GetClassLevel():SetDomain(domain)

	for _,level in ipairs(self:try_get("levels") or {}) do
		level:SetDomain(domain)
	end
end

--- Returns the CharacterAncestryInheritanceChoice feature if this race uses the Former Life mechanic, or false.
--- @return false|CharacterFeature
function Race:IsInherited()
    local formerLifeFeature = self and self:GetClassLevel() and self:GetClassLevel().features[1]
    if formerLifeFeature == nil or formerLifeFeature.typeName ~= 'CharacterAncestryInheritanceChoice' then
        return false
    end

    return formerLifeFeature
end

function Race:ForceDomains(domains)
	return
end

--- Fills result with features from this race up to characterLevel.
--- @param characterLevel nil|integer
--- @param choices table<string, string[]>
--- @param result CharacterFeature[]
function Race:FillClassFeatures(characterLevel, choices, result)
	if result == nil then
		printf("ERROR:: %s", traceback())
	end
	self:EnsureDomain()
	for i,feature in ipairs(self:GetClassLevel().features) do
		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			feature:FillChoice(choices, result)
		end
	end

	for levelNum,level in ipairs(self:try_get("levels") or {}) do
		if characterLevel ~= nil and levelNum > characterLevel then
			break
		end
		
		for i,feature in ipairs(level.features) do
			if feature.typeName == 'CharacterFeature' then
				result[#result+1] = feature
			else
				feature:FillChoice(choices, result)
			end
		end
	end
end

--- Fills result with feature detail entries wrapping each feature with its source race.
--- @param characterLevel nil|integer
--- @param choices table<string, string[]>
--- @param result {race: Race, feature: CharacterFeature|CharacterChoice}[]
--result is filled with a list of { race = Race object, feature = CharacterFeature or CharacterChoice }
function Race:FillFeatureDetails(characterLevel, choices, result)
	self:EnsureDomain()

	for i,feature in ipairs(self:GetClassLevel().features) do
		local resultFeatures = {}
		feature:FillFeaturesRecursive(choices, resultFeatures)

		for i,resultFeature in ipairs(resultFeatures) do
			result[#result+1] = {
				race = self,
				feature = resultFeature,
			}
		end
	end
	
	for levelNum,level in ipairs(self:try_get("levels") or {}) do
		if characterLevel ~= nil and levelNum > characterLevel then
			break
		end

		for i,feature in ipairs(level.features) do
			local resultFeatures = {}
			feature:FillFeaturesRecursive(choices, resultFeatures)

			for i,resultFeature in ipairs(resultFeatures) do
				result[#result+1] = {
					race = self,
					feature = resultFeature,
				}
			end
		end
	end
end

--- @return string
function Race:FeatureSourceName()
	return string.format("%s Race Feature", self.name)
end

--- Returns the ClassLevel object that stores this race's base modifiers and features.
--- @return ClassLevel
--this is where a race stores its modifiers etc, which are very similar to what a class gets.
function Race:GetClassLevel()
	if self:try_get("modifierInfo") == nil then
		self.modifierInfo = ClassLevel:CreateNew()
	end

	return self.modifierInfo
end

--- Returns the id of the default race (Human if available, else the first found).
--- @return nil|string
function Race.DefaultRace()
	if defaultRace == nil then

		local racesTable = dmhub.GetTable('races') or {}
		for k,v in pairs(racesTable) do
			if defaultRace == nil or v.name == 'Human' then
				defaultRace = k
			end
		end
	end
	return defaultRace
end

--- @return DropdownOption[]
function Race.GetDropdownList()
	local result = {}
	local racesTable = dmhub.GetTable('races')
	for k,v in pairs(racesTable) do
		result[#result+1] = { id = k, text = v.name }
		dmhub.Debug('DEFAULT RACE DROPDOWN: ' .. k .. ' -> ' .. v.name)
	end
	table.sort(result, function(a,b)
		return a.text < b.text
	end)
	return result
end

--- Returns (or creates) the ClassLevel entry for the given level number.
--- @param levelNum integer
--- @return ClassLevel
function Race:GetLevel(levelNum)

    local key = string.format("level-%d", levelNum)

	local table = self:get_or_add("levels", {})
	if table[key] == nil then
		table[key] = ClassLevel.CreateNew()
		table[key]:SetDomain(self:Domain())
	end

	return table[key]
end