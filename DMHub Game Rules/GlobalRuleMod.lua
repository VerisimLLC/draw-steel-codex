local mod = dmhub.GetModLoading()

--- @class GlobalRuleMod
--- @field TableName string Data table name ("globalRuleMods").
--- @field applyCharacters boolean If true, this modifier applies to player characters.
--- @field applyMonsters boolean If true, this modifier applies to monsters.
--- @field applyRetainers boolean If true, this modifier applies to retainers.
--- @field applyCompanions boolean If true, this modifier applies to companions.
--- A global rule modifier that is applied to all creatures of matching types without being attached to any character.
GlobalRuleMod = RegisterGameType("GlobalRuleMod")

GlobalRuleMod.TableName = "globalRuleMods"

GlobalRuleMod.applyCharacters = true
GlobalRuleMod.applyMonsters = true
GlobalRuleMod.applyRetainers = true
GlobalRuleMod.applyCompanions = true

GlobalRuleMod.ApplyOptions = {
	{
		id = "none",
		text = "Disabled",
	},
	{
		id = "monsters",
		text = "Monsters",
	},
	{
		id = "characters",
		text = "Heroes",
	},
	{
		id = "retainers",
		text = "Retainers",
	},
	{
		id = "companions",
		text = "Companions",
	},
    {
        id = "characters_retainers",
        text = "Heroes and Retainers",
    },
	{
		id = "all",
		text = "All Creatures",
	},
}

function GlobalRuleMod:OnDeserialize()
    if not self:has_key("_migrated_apply") then
        self._migrated_apply = true
        if cond(self.applyCharacters, 1, 0) + cond(self.applyMonsters, 1, 0) == 1 then
            self.applyRetainers = false
            self.applyCompanions = false
        end
    end
end

function GlobalRuleMod:GetApplyID()
    if self.applyCharacters and self.applyMonsters and self.applyRetainers then
        return "all"
    elseif self.applyCharacters and self.applyRetainers then
        return "characters_retainers"
    elseif self.applyCharacters then
        return "characters"
    elseif self.applyMonsters then
        return "monsters"
    elseif self.applyRetainers then
        return "retainers"
    elseif self.applyCompanions then
        return "companions"
    else
        return "none"
    end
end

function GlobalRuleMod.CreateNew(name)
	return GlobalRuleMod.new{
		name = name,
	}
end

function GlobalRuleMod:FillClassFeatures(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do

		if feature.typeName == 'CharacterFeature' then
			result[#result+1] = feature
		else
			if choices[feature.guid] ~= nil then
				feature:FillChoice(choices, result)
			end
		end
	end
end

--result is filled with a list of { race = GlobalRuleMod object, feature = CharacterFeature or CharacterChoice }
function GlobalRuleMod:FillFeatureDetails(choices, result)
	for i,feature in ipairs(self:GetClassLevel().features) do
		result[#result+1] = {
			race = self,
			feature = feature,
		}
	end
	
end

function GlobalRuleMod:FeatureSourceName()
	return string.format("%s Global Rule Mod Feature", self.name)
end

--this is where a global rule mod stores its modifiers etc, which are very similar to what a class gets.
function GlobalRuleMod:GetClassLevel()
	if self:try_get("modifierInfo") == nil then
		self.modifierInfo = ClassLevel:CreateNew()
	end

	return self.modifierInfo
end

