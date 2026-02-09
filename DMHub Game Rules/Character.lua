local mod = dmhub.GetModLoading()


RegisterGameType("character", "creature")

TokenTypes.character = character

character.description = 'Character'

character.experienceRequirements = {
	300,
	900,
	2700,
	6500,
	14000,
	23000,
	34000,
	48000,
	64000,
	85000,
	100000,
	120000,
	140000,
	165000,
	195000,
	225000,
	265000,
	305000,
	355000,
}

character.roll_hitpoints = false
character.override_hitpoints = false
character.override_hitpoints_note = ""
character.max_hitpoints = 10 --this is only used for overrides

local g_defaultCharTypeId = "139fe6fa-c9e7-4d69-9c93-60833b1bdeaf"

function character.CreateNew(chartypeid)
	local result = character.new{
        ctime = ServerTimestamp(),

		chartypeid = chartypeid or g_defaultCharTypeId,

		damage_taken = 0,

		attributes = creature.CreateAttributes(),

        characterDescription = CharacterDescription:new(),

		--map of skill id -> string if we have proficiency.
		skillProficiencies = {
		},

		savingThrowProficiencies = {
		},

		--map of item id -> { quantity = xxx }
		inventory = {
		},

		--equipment map of creature.EquipmentSlots keys -> item id.
		equipment = {
		},

		--list of innate attacks (type = AttackDefinition)
		--this is in addition to attacks derived from weapons.
		innateAttacks = {
		},

		--map of string -> string. For every choice string guid we
		--map to the corresponding choice the player has made.
		levelChoices = {
		},
	}

	return result
end

function character.OnDeserialize(self)
	if self:try_get("chartypeid") == "" then
		self.chartypeid = g_defaultCharTypeId -- hard-code of "Character" guid. Used to repair bugs where no chartypeid was assigned.
	end

	for k,v in pairs(self:try_get("attributes", {})) do
		if rawget(v, "id") ~= k then
			v.id = k
		end
	end
end


function character:CharTypeID()
	return self:try_get('chartypeid')
end

function character:CharacterType()
	local chartypeid = self:try_get("chartypeid")
	if chartypeid ~= nil then
		local characterTypeTable = GetTableCached(CharacterType.tableName)
		if characterTypeTable then
			return characterTypeTable[chartypeid]
		end
	end

	return nil
end

function creature:GetNotesForTable(tableid)
	if self:has_key("notes") == false then return nil end

	local notes = {}
	for _,note in ipairs(self.notes) do
		if note.tableid == tableid then
			notes[#notes+1] = note
		end
	end

	return notes
end

function creature:GetNoteForTableRow(tableid, rowid)
	if self:has_key("notes") == false then
		return nil
	end

	for _,note in ipairs(self.notes) do
		if note.tableid == tableid and note.rowid == rowid then
			return note
		end
	end

	return nil
end

function creature:GetOrAddNoteForTableRow(tableid, rowid)
	if self:has_key("notes") == false then
		self.notes = {}
	end

	local index = nil
	for i,note in ipairs(self.notes) do
		if note.tableid == tableid then
			index = i
		end

		if note.tableid == tableid and note.rowid == rowid then
			return note
		end
	end

	local result ={
		tableid = tableid,
		rowid = rowid,
		title = "",
		text = "",
	}

	if index == nil then
		self.notes[#self.notes+1] = result
	else
		table.insert(self.notes, index+1, result)
	end

	return result
end

function creature:RemoveNoteForTableRow(tableid, rowid)
	if self:has_key("notes") == false then
		return nil
	end

	for i,note in ipairs(self.notes) do
		if note.tableid == tableid and note.rowid == rowid then
			table.remove(self.notes, i)
			return
		end
	end
end

function creature:RemoveNotesForTable(tableid)
	if self:has_key("notes") == false then return end
	for i = #self.notes, 1, -1 do
		if self.notes[i].tableid == tableid then
			table.remove(self.notes, i)
		end
	end
end

function character:RaceID()
	return self:try_get('raceid', Race.DefaultRace())
end

function character:SubraceID()
	return self:try_get('subraceid')
end

function character:Race()
	local table = GetTableCached('races')
	return table[self:RaceID()] or table[Race.DefaultRace()]
end

function character:Subrace()
	local table = GetTableCached('subraces')
	return table[self:try_get('subraceid', 'none')]
end

function character:BackgroundID()
	return self:try_get('backgroundid', 'none')
end

function character:Background()
	local table = GetTableCached(Background.tableName)
	return table[self:BackgroundID()]
end

function creature:Level()
    return self:CharacterLevel()
end

function creature:CharacterLevel()
	return 1
end

function character:CharacterLevelFromChosenClasses()
	local classes = self:get_or_add("classes", {})
	local result = 0
	for i,entry in ipairs(classes) do
		result = result + entry.level
	end

	return result
end

function character:CharacterLevel()
	local result = self:CharacterLevelFromChosenClasses()
	return math.max(result, self:try_get("levelOverride", 1))
end

function creature:FillHitDice(targetTable)
end

function character:FillHitDice(targetTable)
	if not GameSystem.haveHitDice then
		return
	end

	local classesTable = GetTableCached('classes')
	local classes = self:get_or_add("classes", {})
	for i,entry in ipairs(classes) do
		local classInfo = classesTable[entry.classid]
		if classInfo ~= nil then
			local dieType = classInfo:HitDieResourceType()
			if dieType ~= nil then
				targetTable[dieType] = (targetTable[dieType] or 0) + entry.level
			end
		end
	end
end


function character:GetLevelInClass(classid)
	local classes = self:get_or_add("classes", {})
	for i,entry in ipairs(classes) do
		if entry.classid == classid then
			return entry.level
		end
	end

	return 0
end

function character:SetClass(classid, level)
	local classes = self:get_or_add("classes", {})

	if level == nil or level <= 0 then
		local newClasses = {}
		for i,entry in ipairs(classes) do
			if entry.classid ~= classid then
				newClasses[#newClasses+1] = entry
			end
		end

		self.classes = newClasses
		return
	end

	for i,entry in ipairs(classes) do
		if entry.classid == classid then
			entry.level = level
			return
		end
	end

	classes[#classes+1] = {
		classid = classid,
		level = level,
	}
end

function character:GetClassLevel(classid)
	local classes = self:try_get("classes", {})
	for i,entry in ipairs(classes) do
		if entry.classid == classid then
			return entry.level
		end
	end

	return 0
end

function character:BaseWalkingSpeed()
	local baseSpeed = 30
	local race = self:Race()
	if race ~= nil then
		baseSpeed = race.moveSpeeds.walk or baseSpeed
	end

	return self:try_get("walkingSpeed", baseSpeed)
end


function character:GetBaseCreatureSize()
	local override = self:try_get("creatureSizeOverride", "none")
	if override ~= "none" then
		return override
	end

	local race = self:AncestryOrInheritedAncestry()
	if race ~= nil then
		return race.size
	end
	return self:try_get("creatureSize")
end

function character:SetSizeOverride(sz)
	self.creatureSizeOverride = sz
end

---------------
--SKILLS
---------------


function character.SkillProficiencyBonus(self, skillInfo, descriptionTable)
	local level = self:SkillProficiencyLevel(skillInfo)
	local proficiencyBonus = GameSystem.CalculateProficiencyBonus(self, level)

	local modifiers = self:GetActiveModifiers()
	for _,mod in ipairs(modifiers) do
		proficiencyBonus = mod.mod:ModifySkillProficiencyBonus(mod, self, skillInfo, proficiencyBonus, descriptionTable)
	end

	return proficiencyBonus
end

function character.SkillMod(self, skillInfo)
    if skillInfo == nil then
        return 0
    end

	local proficiencyBonus = self:SkillProficiencyBonus(skillInfo)

	local attrBonus = self:GetAttribute(skillInfo.attribute):Modifier()
	local baseValue = proficiencyBonus + attrBonus
	return self:CalculateAttribute(skillInfo.id, baseValue)
end

function character.HasSkillProficiency(self, skillInfo)
	return self.skillProficiencies[skillInfo.id]
end

function character.BaseSkillProficiencyLevel(self, skillInfo, log)
	local result = "none"

	local modifiers = self:GetActiveModifiers()
	for i,mod in ipairs(modifiers) do
		result = mod.mod:SkillProficiency(mod, self, skillInfo.id, result, log)
	end

	return result
end

--returns the proficiency value.
function character.SkillProficiencyLevel(self, skillInfo)
	if skillInfo == nil then
		return GameSystem.NotProficient()
	end

	local prof = self.skillProficiencies[skillInfo.id]
	if prof == nil or prof == false then
		return creature.proficiencyKeyToValue[self:BaseSkillProficiencyLevel(skillInfo)]

	elseif prof == true then
		return GameSystem.Proficient()
	else
		return creature.proficiencyKeyToValue[prof]
	end
end

function character.SkillProficiencyOverridden(self, skillInfo)
	return self.skillProficiencies[skillInfo.id] ~= nil
end

function character.SkillProficiencyHasOverrides(self)
	return true
end


function character.ToggleSkillProficiency(self, skillInfo)
	if self:HasSkillProficiency(skillInfo) then
		self.skillProficiencies[skillInfo.id] = nil
	else
		self.skillProficiencies[skillInfo.id] = true
	end
end

---------------
--SAVING THROWS
---------------
function character.SavingThrowMod(self, saveid)
	local saveInfo = creature.savingThrowInfo[saveid]

	if saveInfo ~= nil then
		return GameSystem.CalculateSavingThrowModifier(self, saveInfo, self:SavingThrowProficiencyLevel(saveid))
	else
		return 0
	end
end


function character.BaseSavingThrowProficiencyLevel(self, attr, log)
	local result = 'none'

	local modifiers = self:GetActiveModifiers()
	for i,mod in ipairs(modifiers) do
		result = mod.mod:SavingThrowProficiency(mod, self, attr, result, log)
	end

	return result
end

function character.BaseSavingThrowProficiency(self, attr, log)
	return self:BaseSavingThrowProficiencyLevel(attr, log) ~= "none"
end

function character.SavingThrowProficiency(self, attr)
	local result = self.savingThrowProficiencies[attr]
	if result == nil then
		result = self:BaseSavingThrowProficiencyLevel(attr)
	end

	if result == true then
		result = GameSystem.ProficientId()
	elseif result == false then
		result = GameSystem.NotProficientId()
	end

	return creature.proficiencyKeyToValue[result].id
end

function character.HasSavingThrowProficiency(self, attr)
	local result = self.savingThrowProficiencies[attr]
	if result == nil then
		result = self:BaseSavingThrowProficiency(attr)
	elseif result ~= false then
		result = (result ~= GameSystem.NotProficientId())
	end
	return result
end

function character.ToggleSavingThrowProficiency(self, attr)
	local newValue = true
	if self.savingThrowProficiencies[attr] then
		newValue = nil
	end

	self.savingThrowProficiencies[attr] = newValue
end

function character:BaseHitpoints()
	if self.override_hitpoints then
		return self.max_hitpoints
	end

	local conMod = GameSystem.BonusHitpointsForLevel(self)
	local result = 0
	local classesTable = GetTableCached('classes')
	local classes = self:get_or_add("classes", {})
	for i,classInfo in ipairs(classes) do
		local c = classesTable[classInfo.classid]
		if c ~= nil then
			if i == 1 then
				result = result + GameSystem.FixedHitpointsForLevel(c, true) + conMod
			end
			if classInfo.level > 1 or i ~= 1 then
				local skipLevelOne = cond(i == 1, 1, 0)
				if self.roll_hitpoints then
					local hitpointRolls = self:try_get("hitpointRolls", {})
					for j=1+skipLevelOne,classInfo.level do
						local key = string.format("%s-%d", classInfo.classid, j)
						local rollInfo = hitpointRolls[key]
						local rollValue = 0
						if rollInfo ~= nil then
							rollValue = rollInfo.roll
						end
						local roll = math.max(1, (tonumber(rollValue) or 0) + (tonumber(conMod) or 0))
						result = result + roll
					end
				else
					result = result + (classInfo.level-skipLevelOne) * math.max(1, (GameSystem.FixedHitpointsForLevel(c, false) + conMod))
				end
			end
		end
	end

	if result < 1 then
		result = 1
	end

	return result
end

--Called from DMHub to allow initialization of a token
function CreateToken(token)
	token.properties = character.CreateNew()
end

--this ranks characters as higher for being the primary token.
function character.PrimaryTokenRank(self)
	return 1
end

--called by DMHub to see a creature's dark vision info.
function character:GetDarkvision()
	local darkvision = 0

	local override = self:try_get("darkvision")
	if override ~= nil then
		darkvision = override
	end

	darkvision = self:CalculateAttribute("darkvision", darkvision)
	if darkvision <= 0 then
		return nil
	end

	return darkvision
end

function creature:GetClassesAndSubClasses()
	return {}
end

--returns all classes and subclasses in a list of { class -> Class, level -> int, hasSubclass -> bool? }
function character:GetClassesAndSubClasses()
	local classes = self:get_or_add("classes", {})
	local result = {}

	local classesTable = GetTableCached('classes')
	for i,entry in ipairs(classes) do
		local classInfo = classesTable[entry.classid]
		if classInfo ~= nil then
			result[#result+1] = {
				class = classInfo,
				level = entry.level,
			}

			local classEntry = result[#result]

			local subclasses = classInfo:GetSubclasses(self:GetLevelChoices(), entry.level, self:ExtraLevelInfo())
			for j,subclass in ipairs(subclasses) do
				classEntry.hasSubclass = true
				result[#result+1] = {
					class = subclass,
					level = entry.level,
				}
			end
		end
	end

	return result
end

function character:GetSubClass(classInfo)
	local classes = self:get_or_add("classes", {})
	for i,entry in ipairs(classes) do
		if entry.classid == classInfo.id then
			local subclasses = classInfo:GetSubclasses(self:GetLevelChoices(), entry.level, self:ExtraLevelInfo())
			for j,subclass in ipairs(subclasses) do
				if entry.level > 0 then
					return subclass
				end
			end
		end
	end

	return nil
end

function creature:ExtraLevelInfo()
    return self:try_get("extraLevelInfo", {})
end

function character:GetClassLevels()
	local result = {}
	local classes = self:GetClassesAndSubClasses()
	for i,entry in ipairs(classes) do
		entry.class:FillLevelsUpTo(entry.level, self:ExtraLevelInfo(), i ~= 1, result)
	end

	return result
end

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

	local background = self:Background()
	if background ~= nil then
		background:FillClassFeatures(levelChoices, result)
	end

	for i,entry in ipairs(self:GetClassesAndSubClasses()) do
		if i == 1 then
			result[#result+1] = entry.class:GetPrimaryFeature()
			
		end

		entry.class:FillFeaturesForLevel(levelChoices, entry.level, self:ExtraLevelInfo(), i ~= 1, result)
	end
	
	for i,featid in ipairs(self:try_get("creatureFeats", {})) do
		local featTable = GetTableCached(CharacterFeat.tableName)
		local featInfo = featTable[featid]
		if featInfo ~= nil then
			featInfo:FillClassFeatures(levelChoices, result)
		end
	end

	return result
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

	local background = self:Background()
	if background ~= nil then
		background:FillFeatureDetails(self:GetLevelChoices(), result)
	end

	for i,entry in ipairs(self:GetClassesAndSubClasses()) do
		entry.class:FillFeatureDetailsForLevel(self:GetLevelChoices(), entry.level, i ~= 1, result)
	end

	for i,featid in ipairs(self:try_get("creatureFeats", {})) do
		local featTable = GetTableCached(CharacterFeat.tableName)
		local featInfo = featTable[featid]
		if featInfo ~= nil then
			featInfo:FillFeatureDetails(self:GetLevelChoices(), result)
		end
	end

	return result
end

function character:GetFeatures()
    local features = self:try_get("characterFeatures")

    if features == nil then
        features = {}
    else
        features = table.shallow_copy(features)
    end

    for i,feature in ipairs(self:GetClassFeatures()) do
        features[#features+1] = feature
    end

    return features
end

--gets a list of CharacterModifier objects which are currently active on this creature.
function character:CalculateActiveModifiers(calculatingModifiers)
	local result = calculatingModifiers or {}

	self:FillBaseActiveModifiers(result)

	local classFeatures = self:GetClassFeatures()
	for j,feature in ipairs(classFeatures) do
        feature:FillModifiers(self, result)
	end

	self:FillTemporalActiveModifiers(result)
	self:FillModifiersFromModifiers(result)

	result = self:FilterModifiers(result)
	self:CalculateConditionModifiers(result)
	return result
end

function character:IsDying()
    if self:IsHero() then
        local hp = self:CurrentHitpoints()
        return hp <= 0 and hp > -self:BloodiedThreshold()
    end

    return false
end

function character:IsDead()
    if self:IsHero() then
        return self:CurrentHitpoints() <= -self:BloodiedThreshold()
    end
	return self:CurrentHitpoints() <= 0
end

function creature:IsStable()
	return self:CurrentHitpoints() <= 0 and self:GetNumDeathSavingThrowSuccesses() >= 3
end

--called by dmhub to get a descriptive summary of the character.
function creature:GetCharacterSummaryText()
	return self:RaceOrMonsterType()
end


function character:GetCharacterSummaryText()
	local classEntries = {}
	local classesTable = GetTableCached('classes')
	for i,entry in ipairs(self:GetClassesAndSubClasses()) do
		if not entry.hasSubclass then
			local name = entry.class.name
			local parentClass = classesTable[entry.class.primaryClassId]
			if parentClass ~= nil then
				name = string.format("%s %s", name, parentClass.name)
			end
			classEntries[#classEntries+1] = {
				name = name,
				level = entry.level,
			}
		end
	end

	table.sort(classEntries, function(a,b) return a.level > b.level end)

	local text = ""
	for _,entry in ipairs(classEntries) do
		if text ~= "" then
			text = text .. " / "
		end

		text = string.format("%s%s", text, entry.name, entry.level)
	end

	local race = self:Race()
	local subrace = self:Subrace()
	local raceText = "(Unknown)"
	if race ~= nil then
		raceText = race.name
	end

	if subrace ~= nil then
		raceText = subrace.name
	end

	return string.format("Level %d %s %s", self:CharacterLevel(), raceText, text)
end

--called by dmhub to summarize a creature's info in the lobby.
function creature:GetLobbySummaryText()
	local classesTable = GetTableCached('classes')
	local classes = self:get_or_add("classes", {})
	local className = ''
	for i,entry in ipairs(classes) do
		local classInfo = classesTable[entry.classid]
		if classInfo ~= nil then
			if className == '' then
				className = classInfo.name
			else
				className = string.format("%s/%s", className, classInfo.name)
			end
		end
	end

	return {
		class = className,
		level = self:CharacterLevel(),
	}
end

function character:GetHeight()
	
	local race = self:Race()
	if race ~= nil then
		return race:try_get("height", 6)
	end

	return 6
end

character.lookupSymbols = {
	always = function(c)
		return 1
	end,

	never = function(c)
		return 0
	end,

	level = function(c)
		return c:CharacterLevel()
	end,
	spellcastingabilitymodifier = function(c)
		return c:SpellcastingAbilityModifier()
	end,

	--allow cr on characters for ease of use.
	challengerating = function(c)
		return c:CharacterLevel()
	end,
	cr = function(c)
		return c:CharacterLevel()
	end,

	multiclass = function(c)
		return #c:try_get("classes", {}) > 1
	end,

	monoclass = function(c)
		return #c:try_get("classes", {}) == 1
	end,

	subclasses = function(c)
		local result = {}
		local classes = c:GetClassesAndSubClasses()
		for i,entry in ipairs(classes) do
			if entry.class.isSubclass then
				result[#result+1] = entry.class.name
			end
		end

		return StringSet.new{
			strings = result,
		}
	end,

	type = function(c)
		return c:Race().name
	end,

	subtype = function(c)
		local race = c:Subrace()
		if race ~= nil then
			return race.name
		end

		return ""
	end,
}

for k,sym in pairs(creature.lookupSymbols) do
	if character.lookupSymbols[k] == nil then
		character.lookupSymbols[k] = creature.lookupSymbols[k]
	end
end

AddGoblinScriptDerived(creature, character)

--the ancestry, or if a revenant, the former life ancestry.
function character:AncestryOrInheritedAncestry()
    return self:InheritedAncestry() or self:Race()
end

function character:InheritedAncestry()
    local ancestry = self:Race()
    local formerLifeFeature = ancestry and ancestry:IsInherited()
    if formerLifeFeature then
        local inherited = formerLifeFeature:GetInheritedAncestry(self)
        return inherited
    end

    return nil
end

function character:RaceOrMonsterType()
	local result = {}
	local subrace = self:Subrace()
	if subrace ~= nil then
		result = {subrace.name}
	else
        local race = self:Race()
        if race then
		    result = {self:Race().name}
        end
	end

	local mods = self:GetActiveModifiers()
	local symbols = GenerateSymbols(self)
	for i=1,#mods do
		result = mods[i].mod:ModifyCreatureTypes(mod, symbols, result)
	end

	return result[1] or ""
end

function character:GetNameGeneratorTable()
	local key = self:Race():try_get("nameGenerator")
	if key == nil then
		return nil
	end

	local nameDataTable = GetTableCached("nameGenerators")
	return nameDataTable[key]
end