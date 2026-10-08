local mod = dmhub.GetModLoading()

MCDMUtils = {
    GetStandardAbility = function(nameorid)
        local abilityTable = dmhub.GetTable("standardAbilities")
        if abilityTable[nameorid] then
            return abilityTable[nameorid]
        end
        local name = string.lower(nameorid)
        for key,ability in unhidden_pairs(abilityTable) do
            --Skip rows with no name. A corrupt/nameless entry used to make
            --string.lower throw here, which aborts every caller -- including
            --monster free strike construction, blanking out the ability list
            --of every monster in the game.
            local abilityName = ability.name
            if type(abilityName) == "string" and string.lower(abilityName) == name then
                return ability
            end
        end

        return nil
    end
}

MCDMUtils.DeepReplace = function(node, from, to)
    if type(node) ~= "table" then
        return
    end

    for k,v in pairs(node) do
        if v == from then
            node[k] = to
        elseif type(v) == "string" then
            node[k] = regex.ReplaceAll(v, from, to)
        else
            MCDMUtils.DeepReplace(v, from, to)
        end
    end
end
--Nearest square of a token's footprint to another token's location. Token loc
--is the footprint's min corner, extending +x/+y by the creature's dimensions.
--Prefers squares not already holding another creature (e.g. a previously
--engulfed victim); the owner itself always occupies its own footprint, which
--is expected. Returns a Loc, or nil if the owner token is invalid.
--Used by the "pull ... into your space" forced-movement rule and by the
--engulfed-creature reposition behavior.
MCDMUtils.NearestFootprintLoc = function(ownerToken, targetToken)
    if ownerToken == nil or not ownerToken.valid then
        return nil
    end

    local dim = 1
    if ownerToken.creatureDimensions ~= nil and ownerToken.creatureDimensions.x ~= nil then
        dim = math.max(1, math.floor(ownerToken.creatureDimensions.x))
    end

    local ownerLoc = ownerToken.loc
    local targetLoc = targetToken.loc
    local best = nil
    local bestFree = nil

    local function chebyshev(loc)
        local dx = math.abs(loc.x - targetLoc.x)
        local dy = math.abs(loc.y - targetLoc.y)
        if dx > dy then return dx else return dy end
    end

    for dx = 0, dim - 1 do
        for dy = 0, dim - 1 do
            local candidate = ownerLoc:dir(dx, dy)
            local dist = chebyshev(candidate)
            if best == nil or dist < best.dist then
                best = { loc = candidate, dist = dist }
            end

            local occupiedByOther = false
            for _, tokAt in ipairs(game.GetTokensAtLoc(candidate) or {}) do
                if tokAt.charid ~= ownerToken.charid and tokAt.charid ~= targetToken.charid then
                    occupiedByOther = true
                end
            end
            if not occupiedByOther then
                if bestFree == nil or dist < bestFree.dist then
                    bestFree = { loc = candidate, dist = dist }
                end
            end
        end
    end

    local chosen = bestFree or best
    if chosen ~= nil then
        return chosen.loc
    end
    return nil
end

--True if targetToken currently stands inside ownerToken's footprint.
MCDMUtils.IsInsideFootprint = function(ownerToken, targetToken)
    if ownerToken == nil or not ownerToken.valid or targetToken == nil or not targetToken.valid then
        return false
    end

    local dim = 1
    if ownerToken.creatureDimensions ~= nil and ownerToken.creatureDimensions.x ~= nil then
        dim = math.max(1, math.floor(ownerToken.creatureDimensions.x))
    end

    local ownerLoc = ownerToken.loc
    local loc = targetToken.loc
    return loc.x >= ownerLoc.x and loc.x <= ownerLoc.x + dim - 1
       and loc.y >= ownerLoc.y and loc.y <= ownerLoc.y + dim - 1
end

--True if the given loc is inside ownerToken's footprint.
MCDMUtils.IsLocInsideFootprint = function(ownerToken, loc)
    if ownerToken == nil or not ownerToken.valid or loc == nil then
        return false
    end

    local dim = 1
    if ownerToken.creatureDimensions ~= nil and ownerToken.creatureDimensions.x ~= nil then
        dim = math.max(1, math.floor(ownerToken.creatureDimensions.x))
    end

    local ownerLoc = ownerToken.loc
    return loc.x >= ownerLoc.x and loc.x <= ownerLoc.x + dim - 1
       and loc.y >= ownerLoc.y and loc.y <= ownerLoc.y + dim - 1
end
