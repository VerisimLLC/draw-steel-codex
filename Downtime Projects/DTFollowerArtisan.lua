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
    error("THC:: DTFollowerArtisan:new()")
    local instance = setmetatable(DTFollower:new(follower, token), self)
    return instance
end
