--- Downtime followers information - abstraction of character.followers
--- @class DTFollowers
--- @field followers table List of followers as class objects
DTFollowers = RegisterGameType("DTFollowers")
DTFollowers.__index = DTFollowers

--- Creates a new downtime followers instance
--- @param followers table The followers on the creature
--- @param token CharacterToken|nil The DMHub token that is the parent of the creature
--- @return DTFollowers instance The new downtime followers instance
function DTFollowers:new(followers, token)
    local instance = setmetatable({}, self)
    instance.followers = {}

    if followers and type(followers) == "table" and next(followers) then
        for followerId,_ in pairs(followers) do
            local follower = dmhub.GetCharacterById(followerId)
            if follower then
                instance.followers[follower.id] = follower
                -- local type = string.lower(follower.properties:try_get("followerType", ""))
                -- local dtFollower = DTFollower:new(follower, token)
                -- if type == "artisan" then
                --     dtFollower = DTFollowerArtisan:new(follower, token)
                -- elseif type == "sage" then
                --     dtFollower = DTFollowerSage:new(follower, token)
                -- end
                -- if dtFollower then
                --     instance.followers[dtFollower:GetID()] = dtFollower
                -- end
            end
        end
    end

    return instance
end

--- Retrieve a specific follower using its key
--- @param followerId string GUID identifier for the follower
--- @return DTFollower|nil follower The follower or nil if the key wasn't provided or found
function DTFollowers:GetFollower(followerId)
    return self.followers[followerId or ""]
end

--- Retrieve the total number of rolls the followers have
--- @return number numRolls The number of rolls
function DTFollowers:AggregateAvailableRolls()
    local numRolls = 0
    for _, follower in pairs(self.followers or {}) do
        numRolls = numRolls + (follower.properties:GetAvailableRolls())
    end
    return numRolls
end

--- Find all the followers that have available rolls
--- @return table followers The followers with rolls
function DTFollowers:GetFollowersWithAvailbleRolls()
    local followers = {}
    for id, follower in pairs(self.followers or {}) do
        if follower.properties:GetAvailableRolls() > 0 then
            followers[id] = follower
        end
    end
    return followers
end

--- Extend creature to get downtime followers
--- @return DTFollowers|nil followers The downtime followers for the character
creature.GetDowntimeFollowers = function(self)
    if self:IsHero() then
        local token = dmhub.LookupToken(self)
        return DTFollowers:new(self:try_get(DTConstants.FOLLOWERS_STORAGE_KEY), token)
    end
    return nil
end
