local mod = dmhub.GetModLoading()

--- Artisan follower - a follower who can work on creation projects
--- @class DTFollowerArtisan
DTFollowerArtisan = RegisterGameType("DTFollowerArtisan", "DTFollower")
DTFollowerArtisan.__index = DTFollowerArtisan

--- Creates a new artisan follower instance
--- @param follower table A Codex follower structure
--- @param token CharacterToken|nil A Codex character token that is the parent object of the follower
--- @return DTFollowerArtisan|DTFollower|nil instance The new artisan follower instance
function DTFollowerArtisan:new(follower, token)
    local instance = setmetatable(DTFollower:new(follower, token), self)

    instance.characteristics["rea"] = 1

    local charToSet = "mgt"
    if follower.characteristic and type(follower.characteristic) == "string" then
        local isValid = false
        for _, char in ipairs(DTConstants.CHARACTERISTICS) do
            if char.key == follower.characteristic then
                isValid = true
                break
            end
        end
        if isValid and follower.characteristic ~= "rea" then
            charToSet = follower.characteristic
        end
    end
    instance.characteristics[charToSet] = 1

    return instance
end
