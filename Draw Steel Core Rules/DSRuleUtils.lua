local mod = dmhub.GetModLoading()

--A creature whose "Block Enemy Line of Effect" custom attribute is above zero stands in
--the way of its enemies' sightlines. See RuleUtils.LineOfEffectBlocker below.
local g_blockLoEAttribute = "Block Enemy Line of Effect"

--The lookup key the attribute is registered under (name, whitespace stripped, lowercased),
--used only to skip the whole mechanic in games that don't have the attribute at all.
local g_blockLoESymbol = string.lower((string.gsub(g_blockLoEAttribute, "%s+", "")))

--Used by the War Dog Doomthief's Doom Magnet. A creature whose "Block Enemy Line of
--Effect Aura" is N > 0 blocks its enemies' line of effect through every square within
--N of it, for any ability that doesn't include it as a target.
local g_blockLoEAuraAttribute = "Block Enemy Line of Effect Aura"
local g_blockLoEAuraSymbol = string.lower((string.gsub(g_blockLoEAuraAttribute, "%s+", "")))

--Rays are cast from points this far inside a square's corners rather than the corners
--themselves, so a ray can never slip along the seam between two adjacent blockers.
local g_sampleInset = 0.3

--Each blocking rectangle is shrunk by this much on every side before the crossing test, so
--a ray that merely grazes a blocker's edge doesn't count as passing through it.
local g_squareEpsilon = 0.05

--True if the segment from (ax,ay) to (bx,by) passes through the rectangle x0..x1, y0..y1
--in tile space, where the square at loc (x,y) covers x..x+1 and y..y+1. This is the
--standard slab clip: narrow the segment's parameter range t in [0,1] to the part inside
--each axis band in turn; if anything survives both, the segment is inside the rectangle.
local function SegmentCrossesRect(ax, ay, bx, by, x0, y0, x1, y1)
    local tmin = 0
    local tmax = 1

    local d = bx - ax
    local lo = x0 + g_squareEpsilon
    local hi = x1 - g_squareEpsilon
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
    lo = y0 + g_squareEpsilon
    hi = y1 - g_squareEpsilon
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

--The creatures that block line of effect, per floor, worked out once per frame. Targeting
--checks every candidate in the same frame, and almost no creature on a map ever blocks.
local g_blockersFrame = nil
local g_blockersByFloor = {}

--- The creatures on a floor that block their enemies' line of effect, with their own body
--- ("Block Enemy Line of Effect") or an aura ("Block Enemy Line of Effect Aura").
--- @param floorIndex nil|number
--- @return {token: CharacterToken, blocksWithBody: boolean, auraRadius: number}[]
local function BlockersOnFloor(floorIndex)
    --no floor, nothing on it to block (and nil can't be a cache key).
    if floorIndex == nil then
        return {}
    end

    local frame = dmhub.FrameCount()
    if g_blockersFrame ~= frame then
        g_blockersFrame = frame
        g_blockersByFloor = {}
    end

    local blockers = g_blockersByFloor[floorIndex]
    if blockers ~= nil then
        return blockers
    end

    blockers = {}
    g_blockersByFloor[floorIndex] = blockers

    --inert in games whose data doesn't define either attribute at all.
    local haveBlock = CustomAttribute.attributeInfoByLookupSymbol[g_blockLoESymbol] ~= nil
    local haveAura = CustomAttribute.attributeInfoByLookupSymbol[g_blockLoEAuraSymbol] ~= nil
    if not haveBlock and not haveAura then
        return blockers
    end

    for _,tok in ipairs(dmhub.allTokens) do
        if tok.valid and tok.properties ~= nil and tok.floorIndex == floorIndex then
            local body = haveBlock and tok.properties:CalculateNamedCustomAttribute(g_blockLoEAttribute) or 0
            local radius = haveAura and tok.properties:CalculateNamedCustomAttribute(g_blockLoEAuraAttribute) or 0
            if type(body) ~= "number" then body = 0 end
            if type(radius) ~= "number" then radius = 0 end
            radius = math.max(0, math.floor(radius))
            if body > 0 or radius > 0 then
                blockers[#blockers+1] = {token = tok, blocksWithBody = body > 0, auraRadius = radius}
            end
        end
    end

    return blockers
end

--Filter modifiers registered under this id take a creature's line of effect away from a
--set of other creatures -- "no line of effect to any lightbender". Carried by the blinded
--creature itself, unlike "Block Enemy Line of Effect", which is about standing in the way.
local g_lineOfEffectFilterId = "lineofeffect"

CreatureFilter.Register{
    id = g_lineOfEffectFilterId,
    text = "Has Line Of Effect",
    description = "This filter controls whether a creature has line of effect to a target. If any of the filters are false, the creature has no line of effect to that target: it cannot target it, and the target is greyed out with the reason why.",
}

--A hidden creature with a "Wall Meld Angle" custom attribute above zero (Shadowmeld) can still
--be seen by creatures standing within that many degrees of straight in front of the wall it is
--flattened against. See RuleUtils.WallMeldSeesTarget below.
local g_wallMeldAttribute = "Wall Meld Angle"

--Targeting filters run per candidate every frame, and the wall lookup walks every wall on the
--floor, so each creature's wall normal is remembered by charid for this many seconds. The key
--also includes its square and floor, so moving recomputes at once.
local g_wallMeldCacheSeconds = 1
local g_wallMeldCache = {}

--A wall counts as "against" a creature when it is within this much of the creature's edge.
--A wall on the edge of a 1-square creature's square is 0.5 from its centre.
local g_wallMeldMargin = 0.25

--The direction (unit x, y in world/floor space) pointing out of the wall a creature is
--flattened against, towards the creature: the side from which it can be seen. Nil when no
--drawn building-layer wall is next to it. Token positions (PosAtLoc) and wall points share
--one space: 1 unit = 1 square, square centres on whole numbers.
--- @param targetToken CharacterToken
--- @return nil|{x: number, y: number}
local function ComputeWallMeldNormal(targetToken)
    local floor = game.GetFloor(targetToken.floorid)
    if floor ~= nil and not floor.isPrimaryLayerOnFloor then
        --walls live on the primary floor, not on its visual layers.
        floor = game.GetFloor(floor.actualFloor)
    end
    if floor == nil then
        return nil
    end

    local centre = targetToken:PosAtLoc()
    local halfWidth = math.max(1, targetToken.creatureDimensions.x) / 2
    local hit = floor:GetNearestWallSegment{
        x = centre.x,
        y = centre.y,
        maxDistance = halfWidth + g_wallMeldMargin,
    }
    if hit == nil or hit.segment == nil or #hit.segment < 4 then
        return nil
    end

    --closest point on the wall segment to the creature's centre.
    local ax, ay, bx, by = hit.segment[1], hit.segment[2], hit.segment[3], hit.segment[4]
    local abx, aby = bx - ax, by - ay
    local lengthSquared = abx*abx + aby*aby
    local t = 0
    if lengthSquared > 1e-6 then
        t = ((centre.x - ax)*abx + (centre.y - ay)*aby) / lengthSquared
        t = math.max(0, math.min(1, t))
    end

    local nx = centre.x - (ax + abx*t)
    local ny = centre.y - (ay + aby*t)
    local len = math.sqrt(nx*nx + ny*ny)
    if len < 0.01 then
        --centre sits on the wall line: no meaningful front side.
        return nil
    end

    return {x = nx/len, y = ny/len}
end

--Cached ComputeWallMeldNormal; see g_wallMeldCacheSeconds.
--- @param targetToken CharacterToken
--- @return nil|{x: number, y: number}
local function WallMeldNormal(targetToken)
    local key = string.format("%s|%s", targetToken.loc.str, tostring(targetToken.floorid))
    local now = dmhub.Time()
    local entry = g_wallMeldCache[targetToken.charid]
    if entry ~= nil and entry.key == key and now - entry.time < g_wallMeldCacheSeconds then
        return entry.normal
    end

    local normal = ComputeWallMeldNormal(targetToken)
    g_wallMeldCache[targetToken.charid] = {key = key, time = now, normal = normal}
    return normal
end

RuleUtils = {
    --- Finds an enemy creature standing between the source and the target that carries the
    --- "Block Enemy Line of Effect" custom attribute, or whose "Block Enemy Line of Effect Aura"
    --- (a radius) covers squares between them. Only enemies of the source block, and
    --- only while EVERY line the source could draw to the target passes through one of them --
    --- as with the engine's cover test, a single clear ray means the source can see through.
    --- Pass `originLoc` to measure from somewhere other than the source's own square, e.g.
    --- the origin of an area ability.
    --- An aura only blocks abilities that don't include its owner as a target, so pass the
    --- creatures the ability already includes in `includedCharids` to lift their auras.
    --- @param sourceToken CharacterToken
    --- @param targetToken CharacterToken
    --- @param originLoc nil|Loc measure from here instead of the source token's squares
    --- @param includedCharids nil|table<string, boolean> charids the ability already targets
    --- @return nil|CharacterToken the blocking token, or nil when line of effect is clear
    LineOfEffectBlocker = function(sourceToken, targetToken, originLoc, includedCharids)
        if sourceToken == nil or targetToken == nil then return nil end
        if not sourceToken.valid or not targetToken.valid then return nil end
        if sourceToken.charid == targetToken.charid then return nil end

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

        --usually nobody on the floor blocks, which ends the check here.
        local blockers = BlockersOnFloor(floorIndex)
        if #blockers == 0 then
            return nil
        end

        --a segment between the two footprints stays inside their bounding box, so a
        --blocker entirely outside it can't be in the way.
        local minx, miny, maxx, maxy
        for _,list in ipairs({sourceLocs, targetLocs}) do
            for _,loc in ipairs(list) do
                if minx == nil or loc.x < minx then minx = loc.x end
                if maxx == nil or loc.x > maxx then maxx = loc.x end
                if miny == nil or loc.y < miny then miny = loc.y end
                if maxy == nil or loc.y > maxy then maxy = loc.y end
            end
        end

        --One rectangle per enemy of the source that blocks: its footprint, grown on every
        --side by its aura radius (just the footprint when it only blocks with its body).
        local rects = nil
        for _,entry in ipairs(blockers) do
            local tok = entry.token
            if tok.valid and tok.charid ~= sourceToken.charid and tok.charid ~= targetToken.charid then
                local radius = entry.auraRadius
                --once the ability targets the aura's owner, its aura lets the ability through.
                --A creature that blocks with its own body still blocks.
                if includedCharids ~= nil and includedCharids[tok.charid] then
                    radius = 0
                end
                if (entry.blocksWithBody or radius > 0) and not tok:IsFriend(sourceToken) then
                    local x0, y0, x1, y1
                    for _,loc in ipairs(tok.locsOccupying) do
                        if x0 == nil or loc.x < x0 then x0 = loc.x end
                        if y0 == nil or loc.y < y0 then y0 = loc.y end
                        if x1 == nil or loc.x + 1 > x1 then x1 = loc.x + 1 end
                        if y1 == nil or loc.y + 1 > y1 then y1 = loc.y + 1 end
                    end
                    if x0 ~= nil and y0 ~= nil and x1 ~= nil and y1 ~= nil then
                        x0, y0, x1, y1 = x0 - radius, y0 - radius, x1 + radius, y1 + radius
                        if x0 < maxx + 1 and x1 > minx and y0 < maxy + 1 and y1 > miny then
                            rects = rects or {}
                            rects[#rects+1] = {x0 = x0, y0 = y0, x1 = x1, y1 = y1, token = tok}
                        end
                    end
                end
            end
        end

        if rects == nil then
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
                for _,rect in ipairs(rects) do
                    if SegmentCrossesRect(ax, ay, bx, by, rect.x0, rect.y0, rect.x1, rect.y1) then
                        hit = rect.token
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

    --- True when an enemy of the source on the floor has a line-of-effect aura. Only then
    --- does it matter which creatures an ability includes, so callers skip that work
    --- otherwise: always for the aura owner's allies, and in every game without one.
    --- @param sourceToken CharacterToken
    --- @param floorIndex nil|number the floor to look on; the source's own floor when nil
    --- @return boolean
    HostileLineOfEffectAura = function(sourceToken, floorIndex)
        if sourceToken == nil or not sourceToken.valid then
            return false
        end
        for _,entry in ipairs(BlockersOnFloor(floorIndex or sourceToken.floorIndex)) do
            if entry.auraRadius > 0 and entry.token.valid and not entry.token:IsFriend(sourceToken) then
                return true
            end
        end
        return false
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

    --- Why `sourceToken` cannot see `targetToken`, when an effect has taken its line of
    --- effect away (the "Has Line Of Effect" creature filter above). Returns nil while the
    --- source can still see the target, so one call serves as both the test and the tooltip.
    --- Directional: only the creature carrying the effect loses sight, not the creatures it
    --- has been blinded to.
    --- @param sourceToken CharacterToken the creature doing the looking
    --- @param targetToken CharacterToken
    --- @return nil|string
    LineOfEffectDenialReason = function(sourceToken, targetToken)
        if sourceToken == nil or targetToken == nil then return nil end
        if not sourceToken.valid or not targetToken.valid then return nil end
        if sourceToken.charid == targetToken.charid then return nil end
        if sourceToken.properties == nil or targetToken.properties == nil then return nil end

        --Objects are not creatures: their properties carry neither the filter modifiers nor
        --the symbols the filter script reads, so leave them out of this entirely.
        if sourceToken.isObject or targetToken.isObject then return nil end

        local passes, modifier = sourceToken.properties:TargetPassesFilter(g_lineOfEffectFilterId, targetToken.properties)
        if passes then
            return nil
        end

        local name = nil
        if modifier ~= nil then
            name = modifier:try_get("name")
        end

        if name ~= nil and name ~= "" then
            return string.format("You have no line of effect to this creature (%s).", name)
        end

        return "You have no line of effect to this creature."
    end,

    --- @param ability nil|ActivatedAbility the ability being used, when there is one
    HasLineOfEffect = function(toka, tokb, ability)
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

        --An effect on toka may have taken its line of effect to creatures like tokb away.
        --Areas are exempt: they need line of effect to where the area lands, not to each
        --creature in it. Callers with no ability (opportunity attacks) are never areas.
        local isAreaAbility = ability ~= nil and (ability:HasKeyword("Area") or ability.targetType == "map")
        if (not isAreaAbility) and RuleUtils.LineOfEffectDenialReason(toka, tokb) ~= nil then
            return false
        end

        local pierceWalls = (toka.properties ~= nil) and toka.properties:GetPierceWalls() or 0
        local coverInfo = dmhub.GetCoverInfo(toka, tokb, pierceWalls)
        return coverInfo == nil or coverInfo.coverModifier < 1
    end,

    --- True when `viewerToken` can see `targetToken` through its hiding because the target is
    --- flattened against a wall (Shadowmeld) and the viewer stands in front of that wall. The
    --- target's "Wall Meld Angle" custom attribute is the half-angle of that cone in degrees,
    --- measured from straight out of the wall; 0 (the default) means no such trait. False when
    --- no wall is next to the target or the viewer is on another floor, so normal Hidden applies.
    --- Callers use it to skip a Hidden targeting refusal, so it only says "can see", not "can't".
    --- @param viewerToken CharacterToken
    --- @param targetToken CharacterToken
    --- @return boolean
    WallMeldSeesTarget = function(viewerToken, targetToken)
        if viewerToken == nil or targetToken == nil then return false end
        if not viewerToken.valid or not targetToken.valid then return false end
        if targetToken.isObject or targetToken.properties == nil then return false end

        local angle = targetToken.properties:CalculateNamedCustomAttribute(g_wallMeldAttribute)
        if angle <= 0 then return false end
        if viewerToken.floorIndex ~= targetToken.floorIndex then return false end

        local normal = WallMeldNormal(targetToken)
        if normal == nil then return false end

        --compare the direction to the viewer with the wall's outward direction.
        local centre = targetToken:PosAtLoc()
        local viewer = viewerToken:PosAtLoc()
        local dx = viewer.x - centre.x
        local dy = viewer.y - centre.y
        local len = math.sqrt(dx*dx + dy*dy)
        if len < 1e-4 then return false end

        local cosine = (dx*normal.x + dy*normal.y) / len
        return cosine >= math.cos(math.rad(math.min(angle, 180)))
    end,

    --Prompt shown when a retarget picker (Goaded, Meat Shield) is limited to the
    --original strike's range. Names the striker and its reach so the player can
    --see why some tokens are greyed out. allowOriginal (the modifier's
    --changeTargetAllowOriginal flag, e.g. Lines of Force) says the original
    --target is itself a valid pick, so the prompt stops asking for a "new" one.
    RetargetPromptText = function(sourceToken, range, rangeType, allowOriginal)
        local text = RuleUtils.RetargetPromptTextBase(sourceToken, range, rangeType)
        if allowOriginal then
            text = text:gsub("^Choose a new target", "Choose a target", 1) .. " (you may keep the original target)"
        end
        return text
    end,

    RetargetPromptTextBase = function(sourceToken, range, rangeType)
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

    --The candidate list for a trigger that changes a strike's target. Every token
    --passing powerMod's changeTargetFilter is in `targets`; one that also fails a
    --"reasoned" filter stays listed but gets a tooltip in `reasons` (keyed by
    --charid) and can't be picked. symbols carries current/triggerer/caster.
    --Same logic as the trigger panel's local BuildRetargetCandidates.
    --- @param powerMod CharacterModifier the trigger's "power" modifier
    --- @param symbols table
    --- @return CharacterToken[] targets
    --- @return table<string, string> reasons
    BuildRetargetCandidates = function(powerMod, symbols)
        local filterFormula = powerMod:try_get("changeTargetFilter")
        local reasonedFilters = powerMod:try_get("changeTargetReasonedFilters", {})
        local targets = {}
        local reasons = {}
        for _, potential in ipairs(dmhub.allTokens) do
            symbols.target = potential.properties:LookupSymbol{}
            if trim(filterFormula or "") == "" or GoblinScriptTrue(ExecuteGoblinScript(filterFormula, potential.properties:LookupSymbol(symbols), 1)) then
                targets[#targets+1] = potential
                for _, reasonedFilter in ipairs(reasonedFilters) do
                    if trim(reasonedFilter.formula or "") ~= "" and not GoblinScriptTrue(ExecuteGoblinScript(reasonedFilter.formula, potential.properties:LookupSymbol(symbols), 1)) then
                        reasons[potential.charid] = ActivatedAbility.FormatFilterReason(reasonedFilter, symbols)
                        break
                    end
                end
            end
        end
        return targets, reasons
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

    --Removes retarget candidates the strike already targets: a strike can never
    --be redirected onto a creature it already hits. trigger.strikeTargets (a
    --charid list) is kept current by the roll dialog that published the trigger.
    --originalTargetId is the target the trigger fired for; when the modifier
    --sets changeTargetAllowOriginal (Lines of Force: "you can select a new
    --target"), keeping that creature is a legal choice, so it stays in the list.
    --Other strike targets are still excluded.
    RemoveRetargetStrikeTargets = function(targets, trigger, originalTargetId)
        local strikeTargets = nil
        if trigger ~= nil then
            strikeTargets = trigger:try_get("strikeTargets")
        end
        if strikeTargets == nil then
            return
        end
        local targeted = {}
        for _, charid in ipairs(strikeTargets) do
            targeted[charid] = true
        end
        if originalTargetId ~= nil and RuleUtils.RetargetAllowsOriginal(trigger) then
            targeted[originalTargetId] = nil
        end
        for i = #targets, 1, -1 do
            if targeted[targets[i].charid] then
                table.remove(targets, i)
            end
        end
    end,

    --The one legal retarget candidate, or nil if there are zero or several.
    --A candidate with an entry in `reasons` (out of range, filtered) is not
    --legal. Retarget prompts pass autoPickSole so a picker with one answer
    --(e.g. Mirror Token: "back onto the attacker") never has to be shown.
    SoleRetargetCandidate = function(targets, reasons)
        local sole = nil
        for _, tok in ipairs(targets or {}) do
            if reasons == nil or reasons[tok.charid] == nil then
                if sole ~= nil then
                    return nil
                end
                sole = tok
            end
        end
        return sole
    end,

    --True if the trigger's power-roll modifier lets the player keep the
    --original target in its retarget picker (changeTargetAllowOriginal).
    RetargetAllowsOriginal = function(trigger)
        if trigger == nil then
            return false
        end
        local mod = trigger:try_get("powerRollModifier")
        local powerMod = mod ~= nil and mod:try_get("powerRollModifier") or nil
        if powerMod == nil then
            return false
        end
        return powerMod:try_get("changeTargetAllowOriginal", false) == true
    end,

    --- Squares of height between two creatures, counting how tall each one is: 0 when
    --- their heights overlap, 1 when one stands right on top of the other. A Size 2
    --- creature on the ground is in melee reach of one standing 2 squares up (PEK8NNCT).
    --- Objects count as one square tall, as targeting always treated them.
    --- @param a CharacterToken
    --- @param b CharacterToken
    --- @return integer
    VerticalGapInTiles = function(a, b)
        local function top(tok)
            local height = 1
            if not tok.isObject then
                height = math.max(1, tok.tileSize or 1)
            end
            return tok.altitude + height - 1
        end
        return math.max(0, b.altitude - top(a), a.altitude - top(b))
    end,
}

--Lets a square-targeting ability (Empty Space / Any Space) refuse squares the
--caster can't reach through walls, e.g. throwing an object: put
--"target.LineOfEffect" in the ability's target filter. The action bar only
--range-checks those squares otherwise.
GameSystem.RegisterGoblinScriptField{
    target = Loc,
    name = "LineOfEffect",
    type = "boolean",
    desc = "True if the creature using the ability has line of effect to this location: walls don't block every line from its squares to it. True when there is no such creature to measure from.",
    seealso = {"Environment"},
    examples = {"target.LineOfEffect"},
    calculate = function(c)
        local engineLoc = rawget(c, "_tmp_loc")
        local casterid = rawget(c, "_tmp_casterid")
        if engineLoc == nil or casterid == nil then
            return true
        end
        local caster = dmhub.GetTokenById(casterid)
        if caster == nil or not caster.valid or caster.properties == nil then
            return true
        end
        --GetPierceWalls is a count; a bare 0 would read as true (pierce).
        return caster:GetLineOfSight(engineLoc, caster.properties:GetPierceWalls() > 0) > 0
    end,
}
