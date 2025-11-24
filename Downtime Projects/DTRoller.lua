--- Downtime Roller information - abstraction of an entity that can roll on a project
--- @class DTRoller
--- @field name string The name of the roller
--- @field characteristics table The list of characteristics for the roller as attrId = value
--- @field languages table Flag list of language id's known
--- @field skills table List of skills the roller knows in id,text pairs
--- @field object character|DTFollower|DTRoll The source object
--- @field _adjustRolls fun(self: DTRoller, amount: number) Adjusts available rolls (private)
DTRoller = RegisterGameType("DTRoller")
DTRoller.__index = DTRoller

--- Creates a new downtime roller instance
--- @param object character|DTFollower|DTRoll The entity to abstract for the roll
--- @return DTRoller|nil instance The new downtime roller instance
function DTRoller:new(object)
    local instance = setmetatable({}, self)

    local _object = DTRoller._validateConstructor(object)
    if _object then
        local languages = DTBusinessRules.GetGlobalLanguages()

        if DTRoller._isCharacterType(_object) then
            local token = dmhub.LookupToken(_object)
            instance.name = (token.name and #token.name > 0 and token.name) or "(unnamed character)"
            instance.characteristics = DTRoller._charAttrsToList(_object)
            instance.languages = DTHelpers.MergeFlagLists(languages, _object:LanguagesKnown(), true)
            instance.skills = DTRoller._charSkillsToList(_object)
            instance.object = _object
            instance._adjustRolls = function(self, amount)
                local downtimeInfo = self.object:GetDowntimeInfo()
                if downtimeInfo then
                    downtimeInfo:SetAvailableRolls(downtimeInfo:GetAvailableRolls() + amount)
                end
            end
        elseif DTRoller._isFollowerType(_object) then
            instance.name = _object:GetName()
            instance.characteristics = _object:GetCharacteristics()
            instance.languages = DTHelpers.MergeFlagLists(languages, _object:GetLanguages(), true)
            instance.skills = DTRoller._followerSkillsToList(_object)
            instance.object = _object
            instance._adjustRolls = function(self, amount)
                self.object:SetAvailableRolls(self.object:GetAvailableRolls() + amount)
            end
        end

        return instance
    end

    return nil
end

--- Return the roller's name
--- @return string name The roller's name
function DTRoller:GetName()
    return self.name
end

--- Return the roller's characteristics
--- @return table characteristics The roller's characteristics in id = value format
function DTRoller:GetCharacteristics()
    return self.characteristics
end

--- Return a specific characteristic
--- @param attrId string The characteristic id
--- @return number value The roller's characteristic value
function DTRoller:GetCharacteristic(attrId)
    return self.characteristics[attrId] or 0
end

--- Return the roller's languages known
--- @return table skills Flag list of languages known
function DTRoller:GetLanguagesKnown()
    return self.languages
end

--- Return the roller's skills known
--- @return table skills The skills known
function DTRoller:GetSkillsKnown()
    return self.skills
end

--- Adjust the follower's number of available rolls
--- @param amount number The amount to adjust the rolls by
--- @return DTRoller self For chaining
function DTRoller:AdjustRolls(amount)
    self:_adjustRolls(amount)
    return self
end

--- Returns the token / character id of the rolling entity
--- @return string|nil id The token id of the rolling entity
function DTRoller:GetTokenID()
    if self.object then
        if DTRoller._isCharacterType(self.object) then
            local token = dmhub.LookupToken(self.object)
            if token then return token.id end
        elseif DTRoller._isFollowerType(self.object) then
            return self.object:GetTokenID()
        end
    end
    return nil
end

--- Returns the follower id of the rolling follower, if it is one
--- @return string|nil The follower Id
function DTRoller:GetFollowerID()
    if self.object and DTRoller._isFollowerType(self.object) then
        return self.object:GetID()
    end
    return nil
end

--- Validates the constructor and returns an appropriate objec type therefrom
--- @param object character|DTFollower|DTRoll The entity to abstract for the roll
--- @return character|DTFollower|nil validatedObject The validated object
function DTRoller._validateConstructor(object)
    if DTRoller._isCharacterType(object) or DTRoller._isFollowerType(object) then
        return object            
    end

    if DTRoller._isRollType(object) then
        local tokenId = object:GetRolledByID()
        if tokenId and #tokenId then
            local token = dmhub.GetTokenById(tokenId)
            if token and token.properties and token.properties:IsHero() then

                local followerId = object:GetRolledByFollowerID()
                if followerId and #followerId then
                    local followers = token.properties:GetDowntimeFollowers()
                    if followers then
                        return followers:GetFollower(followerId)
                    else
                        return nil
                    end
                end

                return token.properties
            end
        end
    end

    return nil
end

--- Calcualte the list of attributes given a character
--- @param c character The character
--- @return table attributes List of attributes as attrId = value pairs
function DTRoller._charAttrsToList(c)
    local attrList = {}
    for _, char in ipairs(DTConstants.CHARACTERISTICS) do
        attrList[char.key] = tonumber(c:GetAttribute(char.key):Modifier())
    end
    return attrList
end

--- Determine the list of skills given a character
--- @param c character The character
--- @return table skills List of skills the character knows in id,text pairs
function DTRoller._charSkillsToList(c)
    local skillList = {}
    for _, skill in ipairs(Skill.SkillsInfo) do
        if c:ProficientInSkill(skill) then
            skillList[#skillList + 1] = { id = skill.name, text = skill.name}
        end
    end
    return skillList
end

--- Determine the list of skills given a follower
--- @param f DTFollower The follower
--- @return table skills List of skills the follower knows in id,text pairs
function DTRoller._followerSkillsToList(f)
    local skillList = {}
    local skillTable = dmhub.GetTable(Skill.tableName)
    for id,_ in pairs(f:GetSkills()) do
        skillList[#skillList + 1] = { id = id, text = skillTable[id].name}
    end
    return skillList
end

--- Determines whether the object represents a character type
--- @param object character|DTFollower|DTFollowerArtisan|DTFollowerSage|DTRoll the object to evaluate
--- @return boolean isCharacterType
function DTRoller._isCharacterType(object)
    local objType = string.lower(object.typeName or "")
    return objType == "character"
end

--- Determines whether the object represents a follower type
--- @param object character|DTFollower|DTFollowerArtisan|DTFollowerSage|DTRoll the object to evaluate
--- @return boolean isFollowerType 
function DTRoller._isFollowerType(object)
    local objType = string.lower(object.typeName or "")
    return objType == "dtfollower" or objType == "dtfollowerartisan" or objType == "dtfollowersage"
end

--- Determine whether the object represents a roll type
--- @param object character|DTFollower|DTFollowerArtisan|DTFollowerSage|DTRoll the object to evaluate
--- @return boolean isRollType
function DTRoller._isRollType(object)
    local objType = string.lower(object.typeName or "")
    return objType == "dtroll"
end
