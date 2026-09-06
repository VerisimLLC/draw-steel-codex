local mod = dmhub.GetModLoading()


--ability to inherit ancestries as with Revenant.

--- @class CharacterAncestryInheritanceChoice: CharacterChoice
CharacterAncestryInheritanceChoice = RegisterGameType("CharacterAncestryInheritanceChoice", "CharacterChoice")

CharacterAncestryInheritanceChoice.ancestryid = "none"

function CharacterAncestryInheritanceChoice:Describe()
	return "Former Ancestry"
end


function CharacterAncestryInheritanceChoice.CreateNew(args)
	local params = {
		guid = dmhub.GenerateGuid(),
	}

	for k,arg in pairs(args) do
		params[k] = arg
	end

	return CharacterAncestryInheritanceChoice.new(params)
end

function CharacterAncestryInheritanceChoice:GetInheritedAncestry(creature)
    local choices = creature:GetLevelChoices()
    if choices == nil then
        return nil
    end
    local choice = choices[self.guid]
    if choice ~= nil and #choice > 0 then
        return dmhub.GetTable(Race.tableName)[choice[1]]
    end
    return nil
end

function CharacterAncestryInheritanceChoice:Choices(numOption, existingChoices, creature)
	local result = {}

    local ancestryTable = dmhub.GetTable(Race.tableName)
    for k,ancestry in unhidden_pairs(ancestryTable) do
        if k ~= self.ancestryid then
            result[#result+1] = {
                id = k,
                text = ancestry.name,
            }
        end
    end

    table.sort(result, function(a,b)
        return a.text < b.text
    end)

	return result
end

function CharacterAncestryInheritanceChoice:GetOptions()
    local options = {}
    local choices = self:Choices()
    for _,item in ipairs(choices) do
        options[#options+1] = {
            guid = item.id,
            name = item.text,
            unique = true,
        }
    end
    return options
end

function CharacterAncestryInheritanceChoice:NumChoices(creature)
	return 1
end