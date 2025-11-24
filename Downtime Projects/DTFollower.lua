--- Downtime follower information - A single follower
--- @class DTFollower
--- @field characteristics table The list of characteristic values for the follower
--- @field follower table The Codex follower object
--- @field token CharacterToken|nil The codex token that is the parent of the follower
DTFollower = RegisterGameType("DTFollower")
DTFollower.__index = DTFollower

--- Create a new follower object
--- @param follower table A Codex follower structure
--- @param token CharacterToken|nil A Codex character token that is the parent object of the follower
--- @return DTFollower|nil follower A downtime follower object
function DTFollower:new(follower, token)
    if follower == nil then return nil end

    local instance = setmetatable({}, self)

    -- guid might not be there - ensure it is
    if not follower.guid or #follower.guid == 0 then
        if token == nil or token.properties == nil then return nil end
        token:ModifyProperties{
            description = "Add ID to follower",
            execute = function ()
                follower.guid = dmhub.GenerateGuid()
            end,
        }
    end

    instance.characteristics = {}
    for _, char in ipairs(DTConstants.CHARACTERISTICS) do
        instance.characteristics[char.key] = 0
    end

    instance.follower = follower
    instance.token = token

    return instance
end

--- Returns the follower's unique identifier
--- @return string id The GUID uniquely identifying the follower
function DTFollower:GetID()
    return self.follower.guid or ""
end

--- Returns the follower's name
--- @return string name The follower's name
function DTFollower:GetName()
    return self.follower.name or "unnamed follower"
end

--- Returns the follower's languages
--- @return table languages The list of flags languages
function DTFollower:GetLanguages()
    return self.follower.languages or {}
end

--- Returns the follower's skills
--- @return table skills The list of flags skills
function DTFollower:GetSkills()
    return self.follower.skills or {}
end

--- Returns the follower's portrait identifier
--- @return string portrait The unique identifier for the follower's portrait
function DTFollower:GetPortrait()
    return self.follower.portrait or ""
end

--- Returns the follower's characteristics
--- @return table characteristics The list of characteristic values for the follower
function DTFollower:GetCharacteristics()
    return self.characteristics
end

--- Grant or revoke rolls for the follower
--- IMPORTANT: Always call within context of token:ModifyProperties()
--- @param numRolls number The number of rolls to grant, negative to revoke
--- @return DTFollower self For chaining
function DTFollower:GrantRolls(numRolls)
    self.follower[DTConstants.FOLLOWER_AVAILROLL_KEY] = math.max(0, self:GetAvailableRolls() + (numRolls or 0))
    return self
end

--- Return the nubmer of rolls the follower has
--- @return number numRolls The number of rolls
function DTFollower:GetAvailableRolls()
    return self.follower[DTConstants.FOLLOWER_AVAILROLL_KEY] or 0
end

--- Sets the number of avialable rolls.
--- IMPORTANT: Always call within context of token:ModifyProperties()
--- @param numRolls number The new number of rolls
--- @return DTFollower self For chaining
function DTFollower:SetAvailableRolls(numRolls)
    self.follower[DTConstants.FOLLOWER_AVAILROLL_KEY] = math.max(0, numRolls)
end

--- Return the follower's parent token / character id
--- @return string|nil tokenId The token ID or nil if we don't have a token
function DTFollower:GetTokenID()
    if self.token then return self.token.id end
    return nil
end
