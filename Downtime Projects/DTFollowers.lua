--- Downtime followers information - abstraction of character.followers
--- @class DTFollowers
--- @field followers table List of followers as class objects
--- @field creature Creature The creature that owns these followers
DTFollowers = RegisterGameType("DTFollowers")

--- Creates a new downtime followers instance
--- @param followers table The followers on the creature
--- @param creature Creature The creature that owns the followers
--- @return DTFollowers instance The new downtime followers instance
function DTFollowers.CreateNew(followers, creature)
    local instance = DTFollowers.new{
        followers = {},
        creature = creature,
    }

    if followers and type(followers) == "table" and next(followers) then
        for followerId,_ in pairs(followers) do
            local follower = dmhub.GetCharacterById(followerId)
            if follower then instance.followers[follower.id] = follower end
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

--- Retrieve the total number of rolls the followers have. Only counts followers
--- that still resolve to a live character, so rolls stranded on a deleted
--- follower are not reported as spendable.
--- @return number numRolls The number of rolls
function DTFollowers:AggregateAvailableRolls()
    if not (self.creature and self.creature:IsHero()) then
        return 0
    end

    local downtimeInfo = self.creature:GetDowntimeInfo()
    if not downtimeInfo then return 0 end

    local total = 0
    for id,_ in pairs(self.followers or {}) do
        total = total + downtimeInfo:GetFollowerRolls(id)
    end
    return total
end

--- Extend creature to get downtime followers
--- @return DTFollowers|nil followers The downtime followers for the character
creature.GetDowntimeFollowers = function(self)
    if self:IsHero() then
        return DTFollowers.CreateNew(self:try_get(DTConstants.FOLLOWERS_STORAGE_KEY), self)
    end
    return nil
end
