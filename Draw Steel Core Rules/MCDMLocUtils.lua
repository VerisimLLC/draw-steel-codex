local mod = dmhub.GetModLoading()


MCDMLocUtils = {}

--- @param token CharacterToken
--- @return Loc[]
MCDMLocUtils.GetTokenAdjacentLocsInOpposingPairs = function(token)
    local locs = token.locsOccupying
    local topLeft = locs[1]
    local bottomRight = locs[1]

    for _,loc in ipairs(locs) do
        if loc.x < topLeft.x or loc.y < topLeft.y then
            topLeft = loc
        end

        if loc.x > bottomRight.x or loc.y > bottomRight.y then
            bottomRight = loc
        end
    end

    local result = {}
    result[#result+1] = topLeft:dir(-1, -1)
    result[#result+1] = bottomRight:dir(1, 1)

    --scan across top and bottom getting opposites.
    for i=0, bottomRight.x-topLeft.x do
        result[#result+1] = topLeft:dir(i, -1)
        result[#result+1] = bottomRight:dir(-i, 1)
    end

    --scan across left and right getting opposites. Go from -1 to +1 to get the corners.
    for i=-1, 1+bottomRight.y-topLeft.y do
        result[#result+1] = topLeft:dir(-1, i)
        result[#result+1] = bottomRight:dir(1, -i)
    end

    return result
end