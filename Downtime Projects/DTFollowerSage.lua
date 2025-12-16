local mod = dmhub.GetModLoading()

--- Sage follower - a follower who can work on research projects
--- @class DTFollowerSage
DTFollowerSage = RegisterGameType("DTFollowerSage", "DTFollower")
DTFollowerSage.__index = DTFollowerSage

--- Creates a new sage follower instance
--- @param follower table A Codex follower structure
--- @param token CharacterToken|nil A Codex character token that is the parent object of the follower
--- @return DTFollowerSage|DTFollower|nil instance The new sage follower instance
function DTFollowerSage:new(follower, token)
    error("THC:: DTFollowerSage:new()")
    local instance = setmetatable(DTFollower:new(follower, token), self)
    return instance
end
