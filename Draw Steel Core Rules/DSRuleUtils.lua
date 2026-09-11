local mod = dmhub.GetModLoading()

--A creature whose "Block Enemy Line of Effect" custom attribute is above zero stands in
--the way of its enemies' sightlines. See RuleUtils.LineOfEffectBlocker below.
local g_blockLoEAttribute = "Block Enemy Line of Effect"

--The lookup key the attribute is registered under (name, whitespace stripped, lowercased),
--used only to skip the whole mechanic in games that don't have the attribute at all.
local g_blockLoESymbol = string.lower((string.gsub(g_blockLoEAttribute, "%s+", "")))

--Rays are cast from points this far inside a square's corners rather than the corners
--themselves, so a ray can never slip along the seam between two adjacent blockers.
local g_sampleInset = 0.3

--Each blocker square is shrunk by this much on every side before the crossing test, so a
--ray that merely grazes a blocker's edge doesn't count as passing through it.
local g_squareEpsilon = 0.05

--True if the segment from (ax,ay) to (bx,by) passes through the map square whose lower
--corner is (sx,sy). Tile space: the square at loc (x,y) covers x..x+1 and y..y+1. This is
--the standard slab clip -- narrow the segment's parameter range t in [0,1] to the part
--inside each axis band in turn; if anything survives both, the segment is inside the square.
local function SegmentCrossesSquare(ax, ay, bx, by, sx, sy)
    local tmin = 0
    local tmax = 1

    local d = bx - ax
    local lo = sx + g_squareEpsilon
    local hi = sx + 1 - g_squareEpsilon
    if d == 0 then
        if ax < lo or ax > hi then return false end
    else
        local t1 = (lo - ax) / d
        local t2 = (hi - ax) / d
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
        if tmin > tmax then return false end
    end

    d = by - ay
    lo = sy + g_squareEpsilon
    hi = sy + 1 - g_squareEpsilon
    if d == 0 then
        if ay < lo or ay > hi then return false end
    else
        local t1 = (lo - ay) / d
        local t2 = (hi - ay) / d
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
        if tmin > tmax then return false end
    end

    return true
end

--The points a ray may start from or end at inside a footprint: the centre of every square
--it occupies, plus four inset corner points when it is a single square. The corner samples
--are what let a ray find the gap beside a lone blocker; larger creatures already have
--several square centres to choose between. Returned flat as {x1,y1,x2,y2,...}.
local function SamplePoints(locs)
    local pts = {}
    local corners = (#locs == 1)
    for _,loc in ipairs(locs) do
        pts[#pts+1] = loc.x + 0.5
        pts[#pts+1] = loc.y + 0.5

        if corners then
            for _,dx in ipairs({g_sampleInset, 1 - g_sampleInset}) do
                for _,dy in ipairs({g_sampleInset, 1 - g_sampleInset}) do
                    pts[#pts+1] = loc.x + dx
                    pts[#pts+1] = loc.y + dy
                end
            end
        end
    end

    return pts
end

RuleUtils = {
    --- Finds an enemy creature standing between the source and the target that carries the
    --- "Block Enemy Line of Effect" custom attribute. Only enemies of the source block, and
    --- only while EVERY line the source could draw to the target passes through one of them --
    --- as with the engine's cover test, a single clear ray means the source can see through.
    --- Pass `originLoc` to measure from somewhere other than the source's own square, e.g.
    --- the origin of an area ability.
    --- @param sourceToken CharacterToken
    --- @param targetToken CharacterToken
    --- @param originLoc nil|Loc measure from here instead of the source token's squares
    --- @return nil|CharacterToken the blocking token, or nil when line of effect is clear
    LineOfEffectBlocker = function(sourceToken, targetToken, originLoc)
        if sourceToken == nil or targetToken == nil then return nil end
        if not sourceToken.valid or not targetToken.valid then return nil end
        if sourceToken.charid == targetToken.charid then return nil end

        --inert in games whose data doesn't define the attribute at all.
        if CustomAttribute.attributeInfoByLookupSymbol[g_blockLoESymbol] == nil then
            return nil
        end

        if originLoc ~= nil and not originLoc.valid then
            originLoc = nil
        end

        local sourceLocs = sourceToken.locsOccupying
        local floorIndex = sourceToken.floorIndex
        if originLoc ~= nil then
            sourceLocs = {originLoc}
            floorIndex = originLoc.floor
        end

        local targetLocs = targetToken.locsOccupying
        if sourceLocs == nil or #sourceLocs == 0 or targetLocs == nil or #targetLocs == 0 then
            return nil
        end

        --cross-floor targeting isn't something we can reason about with 2D squares.
        if targetToken.floorIndex ~= floorIndex then
            return nil
        end

        --a segment between the two footprints can only enter squares inside their
        --bounding box, so anything outside it is not worth testing.
        local minx, miny, maxx, maxy
        for _,list in ipairs({sourceLocs, targetLocs}) do
            for _,loc in ipairs(list) do
                if minx == nil or loc.x < minx then minx = loc.x end
                if maxx == nil or loc.x > maxx then maxx = loc.x end
                if miny == nil or loc.y < miny then miny = loc.y end
                if maxy == nil or loc.y > maxy then maxy = loc.y end
            end
        end

        --Squares held by enemies of the source that carry the attribute. The attribute is
        --cached per creature, so testing it before the friend test keeps the usual
        --nobody-has-it case down to one table lookup per token on the map.
        local squares = nil
        for _,tok in ipairs(dmhub.allTokens) do
            if tok.valid and tok.properties ~= nil and tok.floorIndex == floorIndex
                and tok.charid ~= sourceToken.charid and tok.charid ~= targetToken.charid then
                local blocks = tok.properties:CalculateNamedCustomAttribute(g_blockLoEAttribute)
                if type(blocks) == "number" and blocks > 0 and not tok:IsFriend(sourceToken) then
                    for _,loc in ipairs(tok.locsOccupying) do
                        if loc.x >= minx and loc.x <= maxx and loc.y >= miny and loc.y <= maxy then
                            squares = squares or {}
                            squares[#squares+1] = {x = loc.x, y = loc.y, token = tok}
                        end
                    end
                end
            end
        end

        if squares == nil then
            return nil
        end

        local sourcePts = SamplePoints(sourceLocs)
        local targetPts = SamplePoints(targetLocs)

        local blocker = nil
        for i = 1, #sourcePts, 2 do
            local ax, ay = sourcePts[i], sourcePts[i+1]
            for j = 1, #targetPts, 2 do
                local bx, by = targetPts[j], targetPts[j+1]

                local hit = nil
                for _,square in ipairs(squares) do
                    if SegmentCrossesSquare(ax, ay, bx, by, square.x, square.y) then
                        hit = square.token
                        break
                    end
                end

                --one unobstructed ray is enough; the source can shoot past the blockers.
                if hit == nil then
                    return nil
                end

                blocker = blocker or hit
            end
        end

        return blocker
    end,

    --- The blocker's name as it should read to the local player, for tooltips explaining
    --- why a target is unavailable. Falls back to a generic noun when the name is hidden.
    --- @param blockerToken CharacterToken
    --- @return string
    LineOfEffectBlockerName = function(blockerToken)
        if blockerToken ~= nil and blockerToken.valid and blockerToken.canLocalPlayerSeeName
            and blockerToken.name ~= nil and blockerToken.name ~= "" then
            return blockerToken.name
        end

        return "Another creature"
    end,

    HasLineOfEffect = function(toka, tokb)
        --Honor a per-creature line-of-effect square cap (the "Line Of Effect Limit"
        --custom attribute, used by the Dazzled condition). When > 0 on either
        --token, sight is severed once the two tokens are more than that many
        --squares apart -- it doesn't matter which side has the limit, because
        --LoE is mutual.
        local distance
        local function checkLimit(tok)
            if tok == nil or tok.properties == nil then return true end
            local limit = tok.properties:CalculateNamedCustomAttribute("Line Of Effect Limit")
            if limit <= 0 then return true end
            distance = distance or toka:Distance(tokb)
            return distance <= limit
        end
        if not checkLimit(toka) or not checkLimit(tokb) then
            return false
        end

        --A creature carrying "Block Enemy Line of Effect" severs its enemies' line of
        --effect through its own space. Directional: only enemies of `toka` are blocked.
        if RuleUtils.LineOfEffectBlocker(toka, tokb) ~= nil then
            return false
        end

        local pierceWalls = (toka.properties ~= nil) and toka.properties:GetPierceWalls() or 0
        local coverInfo = dmhub.GetCoverInfo(toka, tokb, pierceWalls)
        return coverInfo == nil or coverInfo.coverModifier < 1
    end,

    --Prompt shown when a retarget picker (Goaded, Meat Shield) is limited to the
    --original strike's range. Names the striker and its reach so the player can
    --see why some tokens are greyed out.
    RetargetPromptText = function(sourceToken, range, rangeType)
        if rangeType ~= "ability" or sourceToken == nil or not sourceToken.valid then
            return "Choose a new target for the strike"
        end
        local sourceName = "the attacker"
        if sourceToken.canLocalPlayerSeeName and sourceToken.name ~= nil and sourceToken.name ~= "" then
            sourceName = sourceToken.name
        end
        range = tonumber(range)
        if range == nil or range <= 0 then
            return string.format("Choose a new target within %s's line of effect", sourceName)
        end
        local rangeText = tostring(range)
        if range == math.floor(range) then
            rangeText = tostring(math.floor(range))
        end
        local unit = "squares"
        if range == 1 then unit = "square" end
        return string.format("Choose a new target within %s %s and line of effect of %s", rangeText, unit, sourceName)
    end,

    --Greys out retarget candidates the striker could not actually hit. Adds a
    --tooltip to `reasons` (charid -> text, the shape changeTargetReasonedFilters
    --uses) for any target beyond `range` squares or with no line of effect.
    AddRetargetRangeReasons = function(targets, reasons, sourceToken, range)
        if sourceToken == nil or not sourceToken.valid then
            return
        end
        local sourceName = "The attacker"
        if sourceToken.canLocalPlayerSeeName and sourceToken.name ~= nil and sourceToken.name ~= "" then
            sourceName = sourceToken.name
        end
        range = tonumber(range)
        --whole-number ranges print as "5", not "5.0".
        local rangeText = tostring(range)
        if range ~= nil and range == math.floor(range) then
            rangeText = tostring(math.floor(range))
        end
        for _, tok in ipairs(targets) do
            if reasons[tok.charid] == nil and tok.valid and tok.charid ~= sourceToken.charid then
                if range ~= nil and range > 0 and sourceToken:Distance(tok) > range then
                    reasons[tok.charid] = string.format("%s's strike can only reach targets within %s squares.", sourceName, rangeText)
                elseif not RuleUtils.HasLineOfEffect(sourceToken, tok) then
                    reasons[tok.charid] = string.format("%s has no line of effect to this creature.", sourceName)
                end
            end
        end
    end,
}
