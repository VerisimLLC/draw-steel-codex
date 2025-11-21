local mod = dmhub.GetModLoading()

local appearanceJukebox = Jukebox.Create(1)

TokenTypes.monster = monster

monster.description = 'Monster'
monster.proficientWithAllWeapons = true

function monster.OnDeserialize(self)
	for k,v in pairs(self:try_get("attributes")) do
		if rawget(v, "id") ~= k then
			v.id = k
		end
	end
end

local settingAssignMonstersNames = setting{
	id = "assignmonstersnames",
	description = "Monsters Name Generation",
	help = "When a monster is created from the bestiary or by duplication it will be given a unique name, typically something like Goblin 1, Goblin 2, etc.",
	editor = "check",
	default = true,
	storage = "game",
	section = "game",
}

local settingAssignMonstersNamesPrivate = setting{
	id = "monstersnamesprivate",
	description = "Monster Names Private",
	help = "Monster names are private to the DM by default.",
	editor = "check",
	default = true,
	storage = "game",
	section = "game",
}


function monster.OnCreateFromBestiary(self, token)

    --make sure we clear out any minion squad information.
    token.properties.minionSquad = nil

	self.damage_taken = 0

	if token.numAppearanceVariations > 1 then
		appearanceJukebox:CheckSize(token.numAppearanceVariations)

		local index = appearanceJukebox:Next() - 1
		token:SwitchAppearanceVariation(index)
	end

    local role = self:try_get("role")

    if role == "Solo" or role == "Leader" then
        --solos and leaders just get named their type.
        token.name = self.monster_type
	elseif settingAssignMonstersNames:Get() and self:has_key("monster_type") and (not self.minion) then
		local tokens = dmhub.GetTokens{pending = true}
		local nameGenerator = self:GetNameGeneratorTable()
        local genericTable = false
        if nameGenerator == nil and self.monster_type ~= "" then
           nameGenerator = monster.AdjectivesNameGeneratorTable()
            genericTable = true
        end
		local foundName = false
		token.namePrivate = settingAssignMonstersNamesPrivate:Get()
		if nameGenerator ~= nil then
			--try rolling until we get a unique one.
			for i=1,10 do
				token.name = nameGenerator:Roll():JoinString(" ")
                if genericTable then
                    token.name = string.format("%s %s", token.name, self.monster_type)
                end
				local unique = true
				for _,tok in ipairs(tokens) do
					if tok.name == token.name then
						unique = false
						break
					end
				end

				if unique then
					foundName = true
					break
				end
			end
		end

		if not foundName then
			--no name generator or couldn't find a unique name, choose a generic name.
			local highestNumber = 0

			for _,tok in ipairs(tokens) do
				if tok.name ~= nil then
					local matchedName, number = string.match(tok.name, "^(.-)%s+(%d+)$")
					if matchedName == self.monster_type then
						local num = tonumber(number)
						if num > highestNumber then
							highestNumber = num
						end
					end
				end
			end

			token.name = string.format("%s %d", self.monster_type, highestNumber+1)
		end
	end

	--do a local validate and repair.
	self:ValidateAndRepair(true)
end

function monster.RerollHitpoints(self)

	--if the monster has less than 1hp give it 1hp.
	--TODO: make this behavior controllable with an option so a monster can
	--be dead on arrival. (Or maybe just not exist at all?)
	if self.max_hitpoints < 1 then
		self.max_hitpoints = 1
	end
end

function monster.AdjectivesNameGeneratorTable()
	local nameDataTable = dmhub.GetTable("nameGenerators") or {}
    for k,v in pairs(nameDataTable) do
        if v.name == "Generic Monster Adjectives" then
            return v
        end
    end

    return nil
end

function monster:GetNameGeneratorTable()
    local monsterType = self:RaceOrMonsterType()
	local nameDataTable = dmhub.GetTable("nameGenerators") or {}
	if monsterType ~= nil and monsterType ~= "" then
        monsterType = string.lower(monsterType)
		for k,v in pairs(nameDataTable) do
			if string.starts_with(string.lower(v.name), monsterType) then
				return v
			end
		end
	end

	if self:has_key("monster_subtype") then
		for k,v in pairs(nameDataTable) do
			if string.starts_with(string.lower(v.name), string.lower(self.monster_subtype)) then
				return v
			end
		end
	end

	return nil
end

monster.monster_type = 'Monster'

function monster.CreateNew(retainer)
	local result = monster.new{
		cr = 1,

		retainer = retainer and retainer == "retainer",

		monster_type = 'Monster', --this is the specific type of monster. e.g. Adult Black Dragon
		monster_category = 'Monster', --this is the "Type" of monster. e.g. Dragon


		damage_taken = 0,
		max_hitpoints = 10,

		attributes = creature.CreateAttributes(),

		walkingSpeed = 5,

        equipment = {
            mainhand1 = "22ab52f5-955b-40c8-80c3-826f823e0a5b",
        },

		--map of skill id -> rating for that skill. 'true' means the monster is proficient and use proficiency bonus.
		skillRatings = {
		},

		--map of saving throw -> rating for that saving throw.
		savingThrowRatings = {
		},

		--list of innate attacks (type = AttackDefinition)
		innateAttacks = {
		},
	}

	return result
end

function monster.GetMonsterType(self)
	return self.monster_type
end

function monster:BaseWalkingSpeed()
	return self.walkingSpeed
end

function monster.SetWalkingSpeed(self, newValue)
	local val = tonumber(newValue)
	if type(val) == 'number' then
		self.walkingSpeed = val
	end
end

---------------
--SAVING THROWS
---------------
function monster.SavingThrowMod(self, saveid)
	local rating = self.savingThrowRatings[saveid]
	if rating ~= nil then
		return rating
	end

	local saveInfo = creature.savingThrowInfo[saveid]
	if saveInfo ~= nil then
		return GameSystem.CalculateSavingThrowModifier(self, saveInfo, GameSystem.NotProficient())
	else
		return 0
	end
end

function monster.SavingThrowProficiency(self, saveid)
	local rating = self.savingThrowRatings[saveid]

	if rating then
		return creature.proficiencyMultiplierToValue[1].id
	else
		return creature.proficiencyMultiplierToValue[0].id
	end
end

function monster.HasSavingThrowProficiency(self, attr)
	return self.savingThrowRatings[attr] ~= nil
end

function monster.HasDefaultSavingThrowProficiency(self, attr)
	local saveInfo = creature.savingThrowInfo[attr]
	if saveInfo ~= nil then
		return self.savingThrowRatings[attr] == GameSystem.CalculateSavingThrowModifier(self, saveInfo, GameSystem.NotProficient()) + self:ProficiencyBonus()
	else
		return 0
	end
end

function monster.DefaultSavingThrowProficiency(self, attr)
	local saveInfo = creature.savingThrowInfo[attr]
	if saveInfo ~= nil then
		return GameSystem.CalculateSavingThrowModifier(self, saveInfo, GameSystem.NotProficient()) + self:ProficiencyBonus()
	else
		return 0
	end
end

function monster.ToggleSavingThrowProficiency(self, attr)
	if self:HasSavingThrowProficiency(attr) then
		self.savingThrowRatings[attr] = nil
	else
		self.savingThrowRatings[attr] = nil
		self.savingThrowRatings[attr] = self:SavingThrowMod(attr)+self:ProficiencyBonus()
	end
end

function monster.SetSavingThrowRating(self, attr, val)
	local num = tonumber(val)
	self.savingThrowRatings[attr] = num --nil will remove the saving throw rating.
end

---------------
--SKILLS
---------------
function monster.SkillMod(self, skillInfo)
	local rating = self.skillRatings[skillInfo.id]
	local baseValue
	if rating == true then
		--standard proficiency.
		baseValue = self:GetAttribute(skillInfo.attribute):Modifier() + self:ProficiencyBonus()
	else
		if rating ~= nil then
			baseValue = rating
		else
			baseValue = self:GetAttribute(skillInfo.attribute):Modifier()
		end
	end

	return self:CalculateAttribute(skillInfo.id, baseValue)
end

function monster.SkillProficiencyBonus(self, skillInfo)
	if self.skillRatings[skillInfo.id] == nil then
		return 0
	end

	if self.skillRatings[skillInfo.id] == true then
		return self:ProficiencyBonus()
	end

	return self.skillRatings[skillInfo.id] - self:GetAttribute(skillInfo.attribute):Modifier()
end


function monster.HasSkillProficiency(self, skillInfo)
	return self.skillRatings[skillInfo.id] ~= nil
end

function monster.SetSkillProficiency(self, skillInfo, val)
	if val then
		self.skillRatings[skillInfo.id] = true
	else
		self.skillRatings[skillInfo.id] = nil
	end
end

function monster.SkillProficiencyLevel(self, skillInfo)
	if self.skillRatings[skillInfo.id] ~= nil then
		return GameSystem.Proficient()
	else
		return GameSystem.NotProficient()
	end
end

function monster.SkillProficiencyOverridden(self, skillInfo)
	return false
end

function monster.SkillProficiencyHasOverrides(self)
	return false
end


function monster.ToggleSkillProficiency(self, skillInfo)
	if self:HasSkillProficiency(skillInfo) then
		self.skillRatings[skillInfo.id] = nil
	else
		self.skillRatings[skillInfo.id] = true
	end
end

function monster.SetSkillRating(self, skillInfo, val)
	local num = tonumber(val)
	if num ~= nil then
		self.skillRatings[skillInfo.id] = num
	end
end

function monster:RaceOrMonsterType()
    local monsterGroup = self:MonsterGroup()
    if monsterGroup ~= nil then
        return monsterGroup.name
    end

    return "Monster"
end


function monster:SpellcastingLevel()

	local monsterSpellcasting = self:try_get("monsterSpellcasting")
	if monsterSpellcasting ~= nil and monsterSpellcasting.spellcastingLevel ~= nil then
		return monsterSpellcasting.spellcastingLevel
	end

	local cr = (tonumber(self:try_get("cr", 0)) or 0)
	return cr
end

function monster:ProficiencyBonus()
	return self:BaseProficiencyBonus()
end

function monster:CR()
	return tonumber(self:try_get("cr", 0))
end

function monster:PrettyCR()
	if not self:has_key("cr") then
		return "--"
	end

	local cr = tonumber(self.cr)
	if cr == nil then
		return "--"
	end

	if cr >= 1 then
		return tostring(cr)
	end

	if cr <= 0 then
		return "0"
	end

	return string.format("1/%d", 1/cr)
end

local validCR = {
	[0.125] = true,
	[0.25] = true,
	[0.5] = true,
}
for i=0,30 do
	validCR[i] = true
end

local validCRDenom = {[2] = true, [4] = true, [8] = true}
function monster:SetCR(str)
	if type(str) == "number" then
		self.cr = str
		return
	end
	local i1,i2,denom = string.find(str, "1/(%d+)")
	if i1 ~= nil then
		denom = tonumber(denom)
		if validCRDenom[denom] then
			self.cr = 1/denom
		end
		return
	end

	local num = tonumber(str)
	if num ~= nil and validCR[num] then
		self.cr = num
	end
end

monster.lookupSymbols = {
	level = function(c)
		return c:SpellcastingLevel()
	end,
	cr = function(c)
		return c:CR()
	end,
	challengerating = function(c)
		return c:CR()
	end,
}

for k,sym in pairs(creature.lookupSymbols) do
	if monster.lookupSymbols[k] == nil then
		monster.lookupSymbols[k] = sym
	end
end

AddGoblinScriptDerived(creature, monster)

--monsters die as soon as they are down.
function monster:IsDead()
	return self:IsDown()
end